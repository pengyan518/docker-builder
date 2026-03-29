#!/usr/bin/env bash
# scripts/download_models_on_pod.sh
#
# Run this script INSIDE a RunPod Pod that has the Network Volume mounted.
# Models are downloaded directly to the volume — no S3 API needed.
#
# Hugging Face CLI: the script auto-installs via pip when missing (unless --no-install-cli).
# You can also install manually:
#   python3 -m pip install --user -U "huggingface_hub[cli]"
#   export PATH="$HOME/.local/bin:$PATH"
#
# Usage:
#   export HF_TOKEN=hf_xxx
#   # Must match where the Pod mounts the Network Volume — same as RUNPOD_VOLUME_PATH in the image
#   # (worker-comfyui defaults to /runpod-volume; see scripts/start_with_runpod_volume.sh).
#   # Optional LoRA from R2: put the same R2_* vars in the shell, or copy your .env into the Pod
#   # (e.g. scp .env pod:/workspace/.env) — this script auto-loads ./.env if present.
#   bash download_models_on_pod.sh
#   # If your volume is mounted elsewhere, e.g. /workspace:
#   #   bash download_models_on_pod.sh --volume-path /workspace
#
#   # Or skip sections you already have:
#   bash download_models_on_pod.sh --skip-flux --skip-llama
#
# Options:
#   --volume-path PATH   Network Volume mount path (default: /runpod-volume; must match pod mount + start_with_runpod_volume.sh)
#   --skip-flux          Skip FLUX unet / vae / clip
#   --skip-siglip        Skip SigLIP
#   --skip-joy           Skip Joy Caption Two weights
#   --skip-llama         Skip Llama 3.1 8B bnb-4bit
#   --skip-upscale       Skip 4x-UltraSharp
#   --skip-lora          Skip LoRA (from R2; requires R2_* env vars)
#   --dry-run            Print actions without downloading
#   --no-install-cli     Do not run pip install; fail if hf / huggingface-cli missing
#   --no-install-aws     Do not pip-install awscli; fail if aws missing (needed for R2 LoRA)
#   -h, --help           Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== Defaults =====
# Align with Dockerfile / start_with_runpod_volume.sh (RUNPOD_VOLUME_PATH default /runpod-volume).
# If you previously downloaded to /workspace/models, move or rsync to ${VOLUME_PATH}/models.
VOLUME_PATH="/workspace"
SKIP_FLUX=false
SKIP_SIGLIP=false
SKIP_JOY=false
SKIP_LLAMA=false
SKIP_UPSCALE=false
SKIP_LORA=false
DRY_RUN=false
NO_INSTALL_CLI=false
NO_INSTALL_AWS=false

# hf | huggingface-cli (set by ensure_hf_cli)
_HF_SUBCMD=""

log()  { echo "[pod-download] $*"; }
warn() { echo "[pod-download] WARN: $*" >&2; }
die()  { echo "[pod-download] ERROR: $*" >&2; exit 1; }

# Typical install paths for pip --user
_hf_export_path() {
  export PATH="${HOME}/.local/bin:/root/.local/bin:${PATH}"
}

ensure_hf_cli() {
  _hf_export_path
  if command -v hf >/dev/null 2>&1; then
    _HF_SUBCMD="hf"
    log "Using: $(command -v hf)"
    return 0
  fi
  if command -v huggingface-cli >/dev/null 2>&1; then
    _HF_SUBCMD="huggingface-cli"
    log "Using: $(command -v huggingface-cli)"
    return 0
  fi
  if $NO_INSTALL_CLI; then
    die "Neither 'hf' nor 'huggingface-cli' found. Install with: python3 -m pip install --user -U 'huggingface_hub[cli]' && export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
  log "Installing huggingface_hub[cli] via pip (--user) ..."
  if $DRY_RUN; then
    echo "[DRY-RUN] python3 -m pip install --user -U huggingface_hub[cli]"
    _HF_SUBCMD="hf"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user -q -U "huggingface_hub[cli]"
  elif command -v pip3 >/dev/null 2>&1; then
    pip3 install --user -q -U "huggingface_hub[cli]"
  else
    die "No python3/pip3. Install Python 3 + pip, then: pip install 'huggingface_hub[cli]'"
  fi
  _hf_export_path
  if command -v hf >/dev/null 2>&1; then
    _HF_SUBCMD="hf"
    log "Using: $(command -v hf)"
    return 0
  fi
  if command -v huggingface-cli >/dev/null 2>&1; then
    _HF_SUBCMD="huggingface-cli"
    log "Using: $(command -v huggingface-cli)"
    return 0
  fi
  die "CLI still not on PATH after pip. Run: python3 -m pip install --user -U 'huggingface_hub[cli]' && export PATH=\"\$HOME/.local/bin:\$PATH\" && hash -r"
}

ensure_aws_cli() {
  _hf_export_path
  if command -v aws >/dev/null 2>&1; then
    log "Using aws: $(command -v aws)"
    return 0
  fi
  if $NO_INSTALL_AWS; then
    die "aws CLI not found (pod has no aws). Install: python3 -m pip install --user awscli && export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
  if $DRY_RUN; then
    echo "[DRY-RUN] python3 -m pip install --user awscli"
    return 0
  fi
  log "Installing awscli via pip (--user) for R2 copy ..."
  python3 -m pip install --user -q awscli 2>/dev/null || pip3 install --user -q awscli
  _hf_export_path
  command -v aws >/dev/null 2>&1 || die "aws still not found after pip install. Run: python3 -m pip install --user awscli"
  log "Using aws: $(command -v aws)"
}

# Loads R2_*, HF_TOKEN, etc. from a local .env if you copied it onto the Pod (not from git).
load_dotenv_if_present() {
  local f
  for f in "./.env" "${SCRIPT_DIR}/../.env" "${VOLUME_PATH}/.env"; do
    if [[ -f "$f" ]]; then
      log "Loading env file: $f"
      set -a
      # shellcheck source=/dev/null
      source "$f"
      set +a
      return 0
    fi
  done
}

# ===== Argument parsing =====
while [[ $# -gt 0 ]]; do
  case "$1" in
    --volume-path) VOLUME_PATH="$2"; shift 2 ;;
    --skip-flux)    SKIP_FLUX=true;    shift ;;
    --skip-siglip)  SKIP_SIGLIP=true;  shift ;;
    --skip-joy)     SKIP_JOY=true;     shift ;;
    --skip-llama)   SKIP_LLAMA=true;   shift ;;
    --skip-upscale) SKIP_UPSCALE=true; shift ;;
    --skip-lora)    SKIP_LORA=true;    shift ;;
    --dry-run)      DRY_RUN=true;      shift ;;
    --no-install-cli) NO_INSTALL_CLI=true; shift ;;
    --no-install-aws) NO_INSTALL_AWS=true; shift ;;
    -h|--help)
      sed -n '2,45p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ===== Validate =====
[[ -d "${VOLUME_PATH}" ]] || die "Volume path not found: ${VOLUME_PATH}. Is the Network Volume mounted?"

load_dotenv_if_present

[[ -n "${HF_TOKEN:-}" ]] || die "HF_TOKEN is not set. Export it or add HF_TOKEN= to a .env next to the script (e.g. copy .env to the Pod)."

MODELS="${VOLUME_PATH}/models"

ensure_hf_cli

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

# Hugging Face snapshot download (supports `hf` or legacy `huggingface-cli`)
hf_download() {
  local repo="$1"; shift
  local dest="$1"; shift
  # remaining args are passed as --include / --exclude patterns or extra flags
  log "HF download: ${repo} -> ${dest}"
  if [[ "${_HF_SUBCMD}" == "hf" ]]; then
    run hf download "${repo}" \
      --token "${HF_TOKEN}" \
      --local-dir "${dest}" \
      "$@"
  else
    run huggingface-cli download "${repo}" \
      --token "${HF_TOKEN}" \
      --local-dir "${dest}" \
      --local-dir-use-symlinks False \
      "$@"
  fi
}

# Single-file curl download with skip-if-exists
download_one() {
  local url="$1"
  local dest="$2"
  run mkdir -p "$(dirname "${dest}")"
  if [[ -f "${dest}" ]]; then
    local sz
    sz=$(stat -f%z "${dest}" 2>/dev/null || stat -c%s "${dest}" 2>/dev/null || echo 0)
    if [[ "${sz}" -gt 1000 ]]; then
      log "Skip (exists): ${dest}"
      return 0
    fi
    warn "Re-download (tiny/incomplete): ${dest}"
    run rm -f "${dest}"
  fi
  log "GET -> ${dest}"
  run curl -fL --progress-bar --retry 5 --retry-delay 10 \
    --connect-timeout 30 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    -o "${dest}" "${url}"
}

# ===== Create standard dirs (helps RunPod volume diagnostics) =====
run mkdir -p \
  "${MODELS}/checkpoints" \
  "${MODELS}/clip_vision" \
  "${MODELS}/configs" \
  "${MODELS}/controlnet" \
  "${MODELS}/embeddings" \
  "${MODELS}/loras" \
  "${MODELS}/unet" \
  "${MODELS}/vae" \
  "${MODELS}/clip" \
  "${MODELS}/upscale_models" \
  "${MODELS}/LLM" \
  "${MODELS}/Joy_caption_two/text_model"

# ===== 1. FLUX =====
if ! $SKIP_FLUX; then
  log "=== FLUX unet / vae / clip ==="
  hf_download black-forest-labs/FLUX.1-dev "${MODELS}/unet" \
    --include "flux1-dev.safetensors"
  hf_download black-forest-labs/FLUX.1-dev "${MODELS}/vae" \
    --include "ae.safetensors"
  hf_download comfyanonymous/flux_text_encoders "${MODELS}/clip" \
    --include "t5xxl_fp8_e4m3fn.safetensors" \
    --include "clip_l.safetensors"
else
  log "=== Skipping FLUX ==="
fi

# ===== 2. SigLIP (Joy Caption Two) =====
if ! $SKIP_SIGLIP; then
  log "=== SigLIP (google/siglip-so400m-patch14-384) ==="
  hf_download google/siglip-so400m-patch14-384 \
    "${MODELS}/clip/siglip-so400m-patch14-384" \
    --exclude "*.gitattributes" --exclude "README.md"
else
  log "=== Skipping SigLIP ==="
fi

# ===== 3. Joy Caption Two weights (HF Space LFS files) =====
if ! $SKIP_JOY; then
  log "=== Joy Caption Two weights ==="
  JOY_BASE="https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808"
  download_one "${JOY_BASE}/config.yaml"                          "${MODELS}/Joy_caption_two/config.yaml"
  download_one "${JOY_BASE}/clip_model.pt"                        "${MODELS}/Joy_caption_two/clip_model.pt"
  download_one "${JOY_BASE}/image_adapter.pt"                     "${MODELS}/Joy_caption_two/image_adapter.pt"
  download_one "${JOY_BASE}/text_model/README.md"                 "${MODELS}/Joy_caption_two/text_model/README.md"
  download_one "${JOY_BASE}/text_model/adapter_config.json"       "${MODELS}/Joy_caption_two/text_model/adapter_config.json"
  download_one "${JOY_BASE}/text_model/adapter_model.safetensors" "${MODELS}/Joy_caption_two/text_model/adapter_model.safetensors"
  download_one "${JOY_BASE}/text_model/special_tokens_map.json"   "${MODELS}/Joy_caption_two/text_model/special_tokens_map.json"
  download_one "${JOY_BASE}/text_model/tokenizer.json"            "${MODELS}/Joy_caption_two/text_model/tokenizer.json"
  download_one "${JOY_BASE}/text_model/tokenizer_config.json"     "${MODELS}/Joy_caption_two/text_model/tokenizer_config.json"
else
  log "=== Skipping Joy Caption Two ==="
fi

# ===== 4. Llama 3.1 8B bnb-4bit =====
if ! $SKIP_LLAMA; then
  log "=== Llama 3.1 8B bnb-4bit ==="
  hf_download unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit \
    "${MODELS}/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit" \
    --exclude "*.gitattributes" --exclude "README.md"
else
  log "=== Skipping Llama ==="
fi

# ===== 5. 4x-UltraSharp upscale model =====
if ! $SKIP_UPSCALE; then
  log "=== 4x-UltraSharp ==="
  download_one \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true" \
    "${MODELS}/upscale_models/4x-UltraSharp.pth"
else
  log "=== Skipping 4x-UltraSharp ==="
fi

# ===== 6. LoRA from Cloudflare R2 (optional) =====
if ! $SKIP_LORA; then
  if [[ -n "${R2_ACCESS_KEY_ID:-}" && -n "${R2_SECRET_ACCESS_KEY:-}" && \
        -n "${R2_ENDPOINT:-}" && -n "${R2_BUCKET_NAME:-}" ]]; then
    R2_KEY="${R2_LORA_KEY:-models/lora/lora_Flux_Dev_4-step.safetensors}"
    LORA_DEST="${MODELS}/loras/lora_Flux_Dev_4-step.safetensors"
    if [[ -f "${LORA_DEST}" ]]; then
      log "Skip (exists): ${LORA_DEST}"
    else
      log "=== LoRA from R2: s3://${R2_BUCKET_NAME}/${R2_KEY} ==="
      ensure_aws_cli
      mkdir -p "$(dirname "${LORA_DEST}")"
      run env \
        AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
        aws s3 cp "s3://${R2_BUCKET_NAME}/${R2_KEY}" "${LORA_DEST}" \
          --endpoint-url "${R2_ENDPOINT}" \
          --region auto
    fi
  else
    log "=== Skipping LoRA (R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY / R2_ENDPOINT / R2_BUCKET_NAME not set) ==="
  fi
else
  log "=== Skipping LoRA ==="
fi

# ===== Done =====
if ! $DRY_RUN; then
  touch "${MODELS}/.volume_models_ready"
  log ""
  log "All models downloaded to: ${MODELS}"
  log "Volume ready flag: ${MODELS}/.volume_models_ready"
  log ""
  log "Directory summary:"
  du -sh "${MODELS}"/*/  2>/dev/null || true
fi

log "Done."

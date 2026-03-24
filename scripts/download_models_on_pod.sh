#!/usr/bin/env bash
# scripts/download_models_on_pod.sh
#
# Run this script INSIDE a RunPod Pod that has the Network Volume mounted.
# Models are downloaded directly to the volume — no S3 API needed.
#
# Prerequisites (run once in the Pod terminal):
#   pip install -q "huggingface_hub[cli]"
#
# Usage:
#   export HF_TOKEN=hf_xxx
#   bash download_models_on_pod.sh
#
#   # Or skip sections you already have:
#   bash download_models_on_pod.sh --skip-flux --skip-llama
#
# Options:
#   --volume-path PATH   Volume mount path (default: /workspace)
#   --skip-flux          Skip FLUX unet / vae / clip
#   --skip-siglip        Skip SigLIP
#   --skip-joy           Skip Joy Caption Two weights
#   --skip-llama         Skip Llama 3.1 8B bnb-4bit
#   --skip-upscale       Skip 4x-UltraSharp
#   --skip-lora          Skip LoRA (from R2; requires R2_* env vars)
#   --dry-run            Print actions without downloading
#   -h, --help           Show this help

set -euo pipefail

# ===== Defaults =====
VOLUME_PATH="/workspace"
SKIP_FLUX=false
SKIP_SIGLIP=false
SKIP_JOY=false
SKIP_LLAMA=false
SKIP_UPSCALE=false
SKIP_LORA=false
DRY_RUN=false

log()  { echo "[pod-download] $*"; }
warn() { echo "[pod-download] WARN: $*" >&2; }
die()  { echo "[pod-download] ERROR: $*" >&2; exit 1; }

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
    -h|--help)
      sed -n '2,30p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ===== Validate =====
[[ -n "${HF_TOKEN:-}" ]] || die "HF_TOKEN is not set. Run: export HF_TOKEN=hf_xxx"
[[ -d "${VOLUME_PATH}" ]] || die "Volume path not found: ${VOLUME_PATH}. Is the Network Volume mounted?"

MODELS="${VOLUME_PATH}/models"

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

# huggingface-cli wrapper with resume support
hf_download() {
  local repo="$1"; shift
  local dest="$1"; shift
  # remaining args are passed as --include patterns or extra flags
  log "HF download: ${repo} -> ${dest}"
  run huggingface-cli download "${repo}" \
    --token "${HF_TOKEN}" \
    --local-dir "${dest}" \
    --local-dir-use-symlinks False \
    "$@"
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

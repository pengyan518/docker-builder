#!/usr/bin/env bash
# scripts/upload_models_to_volume.sh
#
# Download ComfyUI models locally, then upload to a RunPod Network Volume via S3 API.
# Expects .env in project root (or cwd) with:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT, AWS_BUCKET
#   HF_TOKEN (Hugging Face; required for gated / LFS models)
# Optional for LoRA on R2:
#   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT
#   R2_BUCKET_NAME=my-ai-models
#   R2_LORA_KEY=models/lora/lora_Flux_Dev_4-step.safetensors  (object key inside bucket)
#
# Usage:
#   ./scripts/upload_models_to_volume.sh              # download + upload
#   ./scripts/upload_models_to_volume.sh --download-only
#   ./scripts/upload_models_to_volume.sh --upload-only
#   ./scripts/upload_models_to_volume.sh --dry-run
#
# S3 layout: s3://$AWS_BUCKET/models/...  ->  mounted as /runpod-volume/models/...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOWNLOAD_ONLY=false
UPLOAD_ONLY=false
DRY_RUN=false
STAGING_DIR="${MODEL_STAGING_DIR:-${PROJECT_ROOT}/model_staging}"
AWS_REGION="${AWS_REGION:-us-il-1}"

log() { echo "[upload-models] $*"; }
die() { echo "[upload-models] ERROR: $*" >&2; exit 1; }

load_env() {
  local f
  for f in "${PROJECT_ROOT}/.env" "./.env"; do
    if [[ -f "$f" ]]; then
      log "Loading env from $f"
      set -a
      # shellcheck source=/dev/null
      source "$f"
      set +a
      return 0
    fi
  done
  die "No .env found in ${PROJECT_ROOT} or current directory"
}

require_vars() {
  local missing=()
  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || missing+=("AWS_ACCESS_KEY_ID")
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || missing+=("AWS_SECRET_ACCESS_KEY")
  [[ -n "${AWS_ENDPOINT:-}" ]] || missing+=("AWS_ENDPOINT")
  [[ -n "${AWS_BUCKET:-}" ]] || missing+=("AWS_BUCKET")
  ((${#missing[@]} == 0)) || die "Missing env vars: ${missing[*]}"
}

require_hf_for_download() {
  [[ -n "${HF_TOKEN:-}" ]] || die "HF_TOKEN is required for download (FLUX / Llama / Space LFS)"
}

run_cmd() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

download_one() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    local sz
    sz=$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest" 2>/dev/null || echo 0)
    if [[ "$sz" -gt 1000 ]]; then
      log "Skip (exists): $dest"
      return 0
    fi
    log "Re-download (tiny file): $dest"
    rm -f "$dest"
  fi
  log "GET -> $dest"
  run_cmd curl -fL --progress-bar --retry 5 --retry-delay 10 \
    --connect-timeout 30 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    -o "$dest" "$url"
}

sync_to_s3() {
  require_vars
  local src="${STAGING_DIR}/models"
  [[ -d "$src" ]] || die "Staging dir missing: $src (run without --upload-only first)"
  log "Sync $src -> s3://${AWS_BUCKET}/models/"
  run_cmd aws s3 sync "$src" "s3://${AWS_BUCKET}/models/" \
    --endpoint-url "${AWS_ENDPOINT}" \
    --region "${AWS_REGION}" \
    --only-show-errors
  log "Done. Verify: aws s3 ls s3://${AWS_BUCKET}/models/ --endpoint-url ${AWS_ENDPOINT} --region ${AWS_REGION}"
}

download_all() {
  require_hf_for_download
  local root="${STAGING_DIR}/models"
  mkdir -p "$root"

  log "Staging directory: $root"

  # Standard worker-comfyui empty dirs (optional; helps RunPod volume diagnostics)
  mkdir -p "$root/checkpoints" "$root/clip_vision" "$root/configs" "$root/controlnet" "$root/embeddings"

  # --- FLUX ---
  download_one "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors" \
    "$root/unet/flux1-dev.safetensors"
  download_one "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" \
    "$root/vae/ae.safetensors"
  download_one "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors?download=true" \
    "$root/clip/t5xxl_fp8_e4m3fn.safetensors"
  download_one "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true" \
    "$root/clip/clip_l.safetensors"

  # --- SigLIP (Joy Caption Two) ---
  local sig=google/siglip-so400m-patch14-384
  local sigb="$root/clip/siglip-so400m-patch14-384"
  download_one "https://huggingface.co/${sig}/resolve/main/config.json" "$sigb/config.json"
  download_one "https://huggingface.co/${sig}/resolve/main/model.safetensors" "$sigb/model.safetensors"
  download_one "https://huggingface.co/${sig}/resolve/main/preprocessor_config.json" "$sigb/preprocessor_config.json"
  download_one "https://huggingface.co/${sig}/resolve/main/special_tokens_map.json" "$sigb/special_tokens_map.json"
  download_one "https://huggingface.co/${sig}/resolve/main/spiece.model" "$sigb/spiece.model"
  download_one "https://huggingface.co/${sig}/resolve/main/tokenizer.json" "$sigb/tokenizer.json"
  download_one "https://huggingface.co/${sig}/resolve/main/tokenizer_config.json" "$sigb/tokenizer_config.json"

  # --- Joy Caption Two (HF Space) ---
  local joy="https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808"
  mkdir -p "$root/Joy_caption_two/text_model"
  download_one "$joy/config.yaml" "$root/Joy_caption_two/config.yaml"
  download_one "$joy/clip_model.pt" "$root/Joy_caption_two/clip_model.pt"
  download_one "$joy/image_adapter.pt" "$root/Joy_caption_two/image_adapter.pt"
  download_one "$joy/text_model/README.md" "$root/Joy_caption_two/text_model/README.md"
  download_one "$joy/text_model/adapter_config.json" "$root/Joy_caption_two/text_model/adapter_config.json"
  download_one "$joy/text_model/adapter_model.safetensors" "$root/Joy_caption_two/text_model/adapter_model.safetensors"
  download_one "$joy/text_model/special_tokens_map.json" "$root/Joy_caption_two/text_model/special_tokens_map.json"
  download_one "$joy/text_model/tokenizer.json" "$root/Joy_caption_two/text_model/tokenizer.json"
  download_one "$joy/text_model/tokenizer_config.json" "$root/Joy_caption_two/text_model/tokenizer_config.json"

  # --- Llama 3.1 8B bnb-4bit only ---
  local llm=unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit
  local llmb="$root/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit"
  download_one "https://huggingface.co/${llm}/resolve/main/config.json" "$llmb/config.json"
  download_one "https://huggingface.co/${llm}/resolve/main/generation_config.json" "$llmb/generation_config.json"
  download_one "https://huggingface.co/${llm}/resolve/main/model.safetensors" "$llmb/model.safetensors"
  download_one "https://huggingface.co/${llm}/resolve/main/special_tokens_map.json" "$llmb/special_tokens_map.json"
  download_one "https://huggingface.co/${llm}/resolve/main/tokenizer.json" "$llmb/tokenizer.json"
  download_one "https://huggingface.co/${llm}/resolve/main/tokenizer_config.json" "$llmb/tokenizer_config.json"

  # --- Upscale ---
  download_one "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true" \
    "$root/upscale_models/4x-UltraSharp.pth"

  # --- LoRA from R2 (optional) ---
  if [[ -n "${R2_ACCESS_KEY_ID:-}" && -n "${R2_SECRET_ACCESS_KEY:-}" && -n "${R2_ENDPOINT:-}" ]]; then
    local r2_key="${R2_LORA_KEY:-my-ai-models/models/lora/lora_Flux_Dev_4-step.safetensors}"
    mkdir -p "$root/loras"
    local out="$root/loras/lora_Flux_Dev_4-step.safetensors"
    if [[ -f "$out" ]]; then
      log "Skip (exists): $out"
    else
      log "R2 -> $out (key=$r2_key)"
      if $DRY_RUN; then
        echo "[DRY-RUN] aws s3 cp s3://<r2-bucket>/$r2_key $out ..."
      else
        # R2 bucket: set R2_BUCKET_NAME or derive from env
        local b="${R2_BUCKET_NAME:-}"
        [[ -n "$b" ]] || die "R2_BUCKET_NAME required when using R2 for LoRA"
        AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
        aws s3 cp "s3://${b}/${r2_key}" "$out" \
          --endpoint-url "${R2_ENDPOINT}" \
          --region auto
      fi
    fi
  else
    log "Skipping LoRA (set R2_* and R2_BUCKET_NAME to fetch lora_Flux_Dev_4-step.safetensors)"
  fi

  touch "${root}/.volume_models_ready"
  log "Download phase complete."
}

usage() {
  cat << EOF
Usage: $0 [options]

Options:
  --download-only   Download into MODEL_STAGING_DIR (default: ${PROJECT_ROOT}/model_staging)
  --upload-only     aws s3 sync staging/models -> s3://AWS_BUCKET/models/
  --dry-run         Print actions only
  -h, --help        This help

Environment (.env):
  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT, AWS_BUCKET  (RunPod volume S3)
  HF_TOKEN                                                            (Hugging Face)
  Optional: R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT, R2_BUCKET_NAME, R2_LORA_KEY
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --download-only) DOWNLOAD_ONLY=true; shift ;;
      --upload-only) UPLOAD_ONLY=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  load_env

  if $UPLOAD_ONLY && $DOWNLOAD_ONLY; then
    die "Use only one of --upload-only or --download-only"
  fi

  if ! $UPLOAD_ONLY; then
    download_all
  fi

  if ! $DOWNLOAD_ONLY; then
    sync_to_s3
  fi

  log "All done."
}

main "$@"

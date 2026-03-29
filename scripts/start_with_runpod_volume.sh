#!/usr/bin/env bash
# Link /comfyui/models to Network Volume when models are present, then start the RunPod worker.
# Mount path defaults to /runpod-volume (RunPod Serverless Network Volume).
# If the container exits immediately, check Pod logs in RunPod (GPU check / handler / ComfyUI).
# SSH "container is not running" means the main process already exited — logs show why.

set -euo pipefail

VOL_ROOT="${RUNPOD_VOLUME_PATH:-/workspace}"
MODELS_ON_VOL="${VOL_ROOT}/models"
MARKER_UNET="${MODELS_ON_VOL}/unet/flux1-dev.safetensors"
READY_FLAG="${MODELS_ON_VOL}/.volume_models_ready"

echo "worker-comfyui: start_with_runpod_volume — RUNPOD_VOLUME_PATH=${RUNPOD_VOLUME_PATH:-<unset>}, VOL_ROOT=${VOL_ROOT}, MODELS_ON_VOL=${MODELS_ON_VOL}"

# ComfyUI reads extra_model_paths.yaml at startup. The image ships base_path: /runpod-volume; if the
# Network Volume is mounted at /workspace, that path does not exist and model lists stay empty ([]).
# Regenerate this file so base_path always matches the real mount (VOL_ROOT).
# EXTRA_MODEL_PATHS="/comfyui/extra_model_paths.yaml"
# cat >"${EXTRA_MODEL_PATHS}" <<EOF
# # Generated at container start from RUNPOD_VOLUME_PATH (default /runpod-volume). Do not edit in image.
# runpod_worker_comfy:
#   base_path: ${VOL_ROOT}
#   checkpoints: models/checkpoints/
#   clip: models/clip/
#   clip_vision: models/clip_vision/
#   configs: models/configs/
#   controlnet: models/controlnet/
#   embeddings: models/embeddings/
#   loras: models/loras/
#   upscale_models: models/upscale_models/
#   vae: models/vae/
#   unet: models/unet/
# EOF
# echo "worker-comfyui: wrote ${EXTRA_MODEL_PATHS} with base_path: ${VOL_ROOT}"

COMFYUI_MODELS="/comfyui/models"

if [[ -d "$MODELS_ON_VOL" ]]; then
  if [[ -f "$MARKER_UNET" || -f "$READY_FLAG" ]]; then
    echo "worker-comfyui: Using Network Volume models at ${MODELS_ON_VOL}"

    # Try to replace /comfyui/models entirely with a symlink first.
    # On Docker overlay FS, rm -rf on an image-layer directory may silently fail,
    # leaving the original dir intact and causing ln -sfn to create a link *inside*
    # rather than *replacing* it. Detect this and fall back to per-subdir linking.
    if rm -rf "${COMFYUI_MODELS}" 2>/dev/null && [[ ! -d "${COMFYUI_MODELS}" ]]; then
      ln -sfn "$MODELS_ON_VOL" "${COMFYUI_MODELS}"
      echo "worker-comfyui: Replaced ${COMFYUI_MODELS} -> ${MODELS_ON_VOL} (full symlink)"
    else
      echo "worker-comfyui: Cannot remove image-layer ${COMFYUI_MODELS}; linking per subdirectory"
      for vol_sub in "${MODELS_ON_VOL}"/*/; do
        sub_name="$(basename "$vol_sub")"
        target="${COMFYUI_MODELS}/${sub_name}"
        rm -rf "${target}" 2>/dev/null || true
        ln -sfn "${vol_sub%/}" "${target}"
        echo "  ${target} -> ${vol_sub%/}"
      done
      # Also link top-level files (e.g. .volume_models_ready)
      for vol_file in "${MODELS_ON_VOL}"/*; do
        [[ -f "$vol_file" ]] || continue
        fname="$(basename "$vol_file")"
        ln -sf "$vol_file" "${COMFYUI_MODELS}/${fname}"
      done
    fi
  else
    echo "worker-comfyui: Network Volume models dir exists but FLUX UNet not found; keeping image /comfyui/models" >&2
    echo "worker-comfyui: Upload models with scripts/upload_models_to_volume.sh" >&2
  fi
else
  echo "worker-comfyui: No ${MODELS_ON_VOL}; using image /comfyui/models" >&2
fi

echo "worker-comfyui: exec /start.sh"
exec /start.sh "$@"

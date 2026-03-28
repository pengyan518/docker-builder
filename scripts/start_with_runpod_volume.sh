#!/usr/bin/env bash
# Link /comfyui/models to Network Volume when models are present, then start the RunPod worker.
# Mount path defaults to /runpod-volume (RunPod Serverless Network Volume).
# If the container exits immediately, check Pod logs in RunPod (GPU check / handler / ComfyUI).
# SSH "container is not running" means the main process already exited — logs show why.

set -euo pipefail

VOL_ROOT="${RUNPOD_VOLUME_PATH:-/runpod-volume}"
MODELS_ON_VOL="${VOL_ROOT}/models"
MARKER_UNET="${MODELS_ON_VOL}/unet/flux1-dev.safetensors"
READY_FLAG="${MODELS_ON_VOL}/.volume_models_ready"

echo "worker-comfyui: start_with_runpod_volume — RUNPOD_VOLUME_PATH=${RUNPOD_VOLUME_PATH:-<unset>}, VOL_ROOT=${VOL_ROOT}, MODELS_ON_VOL=${MODELS_ON_VOL}"

if [[ -d "$MODELS_ON_VOL" ]]; then
  if [[ -f "$MARKER_UNET" || -f "$READY_FLAG" ]]; then
    echo "worker-comfyui: Using Network Volume models at ${MODELS_ON_VOL}"
    rm -rf /comfyui/models
    ln -sfn "$MODELS_ON_VOL" /comfyui/models
  else
    echo "worker-comfyui: Network Volume models dir exists but FLUX UNet not found; keeping image /comfyui/models" >&2
    echo "worker-comfyui: Upload models with scripts/upload_models_to_volume.sh" >&2
  fi
else
  echo "worker-comfyui: No ${MODELS_ON_VOL}; using image /comfyui/models" >&2
fi

echo "worker-comfyui: exec /start.sh"
exec /start.sh "$@"

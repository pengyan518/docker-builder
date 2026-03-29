# RunPod worker-comfyui with custom nodes; large models live on Network Volume (see scripts/upload_models_to_volume.sh).
#
# 5.8.5-base ships CUDA 12.6. Some RunPod GPU nodes have older drivers; the runtime then fails before your CMD runs:
#   nvidia-container-cli: unsatisfied condition: cuda>=12.6
# 5.5.1-base uses an older CUDA stack and is compatible with more hosts (same pattern as Dockerfile.upscale).
# Rebuild with: docker build --build-arg WORKER_COMFYUI_TAG=5.8.5-base ...  when your provider supports CUDA 12.6+.
ARG WORKER_COMFYUI_TAG=5.5.1-base
FROM runpod/worker-comfyui:${WORKER_COMFYUI_TAG}

# Optional: runtime HF token for nodes that download on demand (not required if all models are on volume).
ARG HF_TOKEN=""
ENV HUGGINGFACE_TOKEN=${HF_TOKEN}
ENV HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}

RUN comfy-node-install https://github.com/ltdrdata/ComfyUI-Impact-Pack
RUN comfy-node-install https://github.com/rgthree/rgthree-comfy
RUN comfy-node-install https://github.com/TTPlanetPig/Comfyui_TTP_Toolset
RUN comfy-node-install https://github.com/kijai/ComfyUI-KJNodes
RUN comfy-node-install https://github.com/yolain/ComfyUI-Easy-Use
RUN comfy-node-install https://github.com/EvilBT/ComfyUI_SLK_joy_caption_two

# Network Volume layout: /runpod-volume/models/...  (S3 sync from upload script)
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Symlink /comfyui/models -> volume when flux unet or .volume_models_ready is present
COPY scripts/start_with_runpod_volume.sh /usr/local/bin/start_with_runpod_volume.sh
RUN chmod +x /usr/local/bin/start_with_runpod_volume.sh

CMD ["/usr/local/bin/start_with_runpod_volume.sh"]

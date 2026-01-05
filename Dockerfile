# start from a clean base image (replace <version> with the desired release)
FROM runpod/worker-comfyui:5.5.1-base

# Set Hugging Face token (build argument)
ARG HF_TOKEN
ARG CIVITAI_TOKEN
# R2 credentials for downloading models
ARG R2_ENDPOINT
ARG R2_ACCESS_KEY_ID
ARG R2_SECRET_ACCESS_KEY

ENV HUGGINGFACE_TOKEN=${HF_TOKEN}
ENV HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}

# install custom nodes using comfy-cli
# RUN comfy-node-install was-node-suite-comfyui
# RUN comfy-node-install https://github.com/kijai/ComfyUI-KJNodes
# RUN comfy-node-install https://github.com/pythongosssss/ComfyUI-Custom-Scripts
RUN comfy-node-install https://github.com/yolain/ComfyUI-Easy-Use
RUN comfy-node-install https://github.com/rgthree/rgthree-comfy
RUN comfy-node-install https://github.com/TTPlanetPig/Comfyui_TTP_Toolset
RUN comfy-node-install https://github.com/ltdrdata/ComfyUI-Impact-Pack
RUN comfy-node-install https://github.com/cubiq/ComfyUI_essentials
# download models using comfy-cli
# the "--filename" is what you use in your ComfyUI workflow
# Download FLUX UNET model (注意：FLUX 模型应放在 models/unet 而不是 checkpoints)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors --relative-path models/unet --filename flux1-dev.safetensors

# Download VAE model
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors --relative-path models/vae --filename ae.safetensors

# Download CLIP models for FLUX
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors?download=true --relative-path models/clip --filename t5xxl_fp8_e4m3fn.safetensors
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true --relative-path models/clip --filename clip_l.safetensors

# Download upscale_models 4x_NMKD-Superscale
RUN comfy model download --url "https://civitai.com/api/download/models/156841?type=Model&format=PickleTensor&token=${CIVITAI_TOKEN}" --relative-path models/upscale_models --filename 4x_NMKD-Superscale.pt
# Download upscale_models 4x-UltraSharp
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true --relative-path models/upscale_models --filename 4x-UltraSharp.pth
# https://civitai.com/api/download/models/2052724?type=Model&format=PickleTensor

# Install rclone for R2 downloads
RUN curl https://rclone.org/install.sh | bash

# Configure rclone for R2 (non-interactive)
RUN mkdir -p /root/.config/rclone && \
    echo "[myR2]" > /root/.config/rclone/rclone.conf && \
    echo "type = s3" >> /root/.config/rclone/rclone.conf && \
    echo "provider = Cloudflare" >> /root/.config/rclone/rclone.conf && \
    echo "access_key_id = ${R2_ACCESS_KEY_ID}" >> /root/.config/rclone/rclone.conf && \
    echo "secret_access_key = ${R2_SECRET_ACCESS_KEY}" >> /root/.config/rclone/rclone.conf && \
    echo "endpoint = ${R2_ENDPOINT}" >> /root/.config/rclone/rclone.conf && \
    echo "acl = private" >> /root/.config/rclone/rclone.conf

# Download lora models from R2
RUN rclone copyto myR2:my-ai-models/models/lora_Flux_Dev_4-step.safetensors /comfyui/models/loras/lora_Flux_Dev_4-step.safetensors --config /root/.config/rclone/rclone.conf
RUN rclone copyto myR2:my-ai-models/models/shuimo_BRairt.F1_V1.safetensors models/loras

# Optional: other models (commented out for now)
# RUN comfy model download --url https://huggingface.co/shiertier/clip_vision/resolve/main/SD15/model.safetensors --relative-path models/clip_vision --filename models.safetensors
# RUN comfy model download --url https://huggingface.co/lllyasviel/ic-light/resolve/main/iclight_sd15_fcon.safetensors --relative-path models/diffusion_models --filename iclight_sd15_fcon.safetensors

# Copy local static input files into the ComfyUI input directory (delete if not needed)
# Assumes you have an 'input' folder next to your Dockerfile
# COPY input/ /comfyui/input/
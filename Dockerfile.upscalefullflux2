FROM enhou/runpod-comfyui-serverless-upscale-flux-full:202604050134

ARG HF_TOKEN
ARG CIVITAI_TOKEN
ENV HUGGINGFACE_TOKEN=${HF_TOKEN}
ENV HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}

RUN comfy-node-install https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler
RUN comfy-node-install https://github.com/BadCafeCode/masquerade-nodes-comfyui
RUN comfy-node-install https://github.com/pythongosssss/ComfyUI-Custom-Scripts
RUN comfy-node-install https://github.com/cubiq/ComfyUI_essentials

# --- FLUX2 Klein 模型 ---
# Text encoder (Qwen3 8B FP8, 单文件, 8.66GB)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} \
    --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors \
    --relative-path models/clip \
    --filename qwen_3_8b_fp8mixed.safetensors

# FLUX2 VAE (336MB)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} \
    --url https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors \
    --relative-path models/vae \
    --filename flux2-vae.safetensors

# FLUX2 Klein UNET (需要 HF 账号同意许可协议)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} \
    --url https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors \
    --relative-path models/unet \
    --filename "FLUX.2-klein-9b-fp8-v2_flux2 Klein b9"

# --- SeedVR2 超分模型 (可选 bake) ---
# DiT 模型 (16.5GB)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} \
    --url https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors \
    --relative-path models/seedvr2 \
    --filename seedvr2_ema_7b_sharp_fp16.safetensors

# VAE (501MB)
RUN comfy model download --set-hf-api-token ${HF_TOKEN} \
    --url https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors \
    --relative-path models/seedvr2 \
    --filename ema_vae_fp16.safetensors
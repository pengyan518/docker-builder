# start from a clean base image (replace <version> with the desired release)
FROM runpod/worker-comfyui:5.8.5-base

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
# RUN comfy-node-install https://github.com/cubiq/ComfyUI_essentials

RUN comfy-node-install https://github.com/ltdrdata/ComfyUI-Impact-Pack
RUN comfy-node-install https://github.com/rgthree/rgthree-comfy
RUN comfy-node-install https://github.com/TTPlanetPig/Comfyui_TTP_Toolset
RUN comfy-node-install https://github.com/kijai/ComfyUI-KJNodes
RUN comfy-node-install https://github.com/yolain/ComfyUI-Easy-Use
RUN comfy-node-install https://github.com/EvilBT/ComfyUI_SLK_joy_caption_two

# Same as slim Dockerfile: volume fallback when CMD bypasses symlink startup; SigLIP hidden_states fix.
COPY scripts/patch_joy_caption_two_base_path.py /usr/local/bin/patch_joy_caption_two_base_path.py
RUN python3 /usr/local/bin/patch_joy_caption_two_base_path.py
RUN sed -i '/vision_outputs = self.model(pixel_values=pixel_values, output_hidden_states=True)/i\        self.model.config.output_hidden_states = True' \
    /comfyui/custom_nodes/comfyui_slk_joy_caption_two/joy_caption_two_node.py

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
# RUN comfy model download --url "https://civitai.com/api/download/models/156841?type=Model&format=PickleTensor&token=${CIVITAI_TOKEN}" --relative-path models/upscale_models --filename 4x_NMKD-Superscale.pt
# Download upscale_models 4x-UltraSharp
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true --relative-path models/upscale_models --filename 4x-UltraSharp.pth
# https://civitai.com/api/download/models/2052724?type=Model&format=PickleTensor


# Joy Caption Two weights (required by ComfyUI_SLK_joy_caption_two; install alone does not fetch them).
# Copy of HF Space folder cgrkzexw-599808 -> ComfyUI models/Joy_caption_two (see EvilBT readme_us.md).
RUN mkdir -p /comfyui/models/Joy_caption_two/text_model
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/config.yaml --relative-path models/Joy_caption_two --filename config.yaml
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/clip_model.pt --relative-path models/Joy_caption_two --filename clip_model.pt
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/image_adapter.pt --relative-path models/Joy_caption_two --filename image_adapter.pt
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/README.md --relative-path models/Joy_caption_two/text_model --filename README.md
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/adapter_config.json --relative-path models/Joy_caption_two/text_model --filename adapter_config.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/adapter_model.safetensors --relative-path models/Joy_caption_two/text_model --filename adapter_model.safetensors
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/special_tokens_map.json --relative-path models/Joy_caption_two/text_model --filename special_tokens_map.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/tokenizer.json --relative-path models/Joy_caption_two/text_model --filename tokenizer.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/spaces/fancyfeast/joy-caption-alpha-two/resolve/main/cgrkzexw-599808/text_model/tokenizer_config.json --relative-path models/Joy_caption_two/text_model --filename tokenizer_config.json
# download models using comfy-cli
# the "--filename" is what you use in your ComfyUI workflow



# Install rclone for R2 downloads
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip && \
    curl https://rclone.org/install.sh | bash && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
RUN rclone copyto myR2:my-ai-models/models/lora/lora_Flux_Dev_4-step.safetensors /comfyui/models/loras/lora_Flux_Dev_4-step.safetensors --config /root/.config/rclone/rclone.conf
# RUN rclone copyto myR2:my-ai-models/models/lora/shuimo_BRairt.F1_V1.safetensors /comfyui/models/loras/shuimo_BRairt.F1_V1.safetensors --config /root/.config/rclone/rclone.conf

# Optional: other models (commented out for now)
# RUN comfy model download --url https://huggingface.co/shiertier/clip_vision/resolve/main/SD15/model.safetensors --relative-path models/clip_vision --filename models.safetensors
# RUN comfy model download --url https://huggingface.co/lllyasviel/ic-light/resolve/main/iclight_sd15_fcon.safetensors --relative-path models/diffusion_models --filename iclight_sd15_fcon.safetensors

# Copy local static input files into the ComfyUI input directory (delete if not needed)
# Assumes you have an 'input' folder next to your Dockerfile
# COPY input/ /comfyui/input/

# google/siglip-so400m-patch14-384 for ComfyUI_SLK_joy_caption_two -> models/clip/siglip-so400m-patch14-384 (EvilBT readme)
RUN mkdir -p /comfyui/models/clip/siglip-so400m-patch14-384
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/config.json --relative-path models/clip/siglip-so400m-patch14-384 --filename config.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors --relative-path models/clip/siglip-so400m-patch14-384 --filename model.safetensors
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/preprocessor_config.json --relative-path models/clip/siglip-so400m-patch14-384 --filename preprocessor_config.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/special_tokens_map.json --relative-path models/clip/siglip-so400m-patch14-384 --filename special_tokens_map.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/spiece.model --relative-path models/clip/siglip-so400m-patch14-384 --filename spiece.model
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/tokenizer.json --relative-path models/clip/siglip-so400m-patch14-384 --filename tokenizer.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/tokenizer_config.json --relative-path models/clip/siglip-so400m-patch14-384 --filename tokenizer_config.json



# Llama 3.1 8B for ComfyUI_SLK_joy_caption_two -> models/LLM/<folder> (EvilBT readme; may require HF account access to Llama)
# 2.1 unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit
RUN mkdir -p /comfyui/models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename config.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/generation_config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename generation_config.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/model.safetensors --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename model.safetensors
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/special_tokens_map.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename special_tokens_map.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/tokenizer.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename tokenizer.json
RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit/resolve/main/tokenizer_config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct-bnb-4bit --filename tokenizer_config.json
# 2.2 unsloth/Meta-Llama-3.1-8B-Instruct (sharded weights)
# RUN mkdir -p /comfyui/models/LLM/Meta-Llama-3.1-8B-Instruct
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename config.json
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/generation_config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename generation_config.json
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/model.safetensors.index.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename model.safetensors.index.json
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/model-00001-of-00004.safetensors --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename model-00001-of-00004.safetensors
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/model-00002-of-00004.safetensors --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename model-00002-of-00004.safetensors
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/model-00003-of-00004.safetensors --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename model-00003-of-00004.safetensors
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/model-00004-of-00004.safetensors --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename model-00004-of-00004.safetensors
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/special_tokens_map.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename special_tokens_map.json
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/tokenizer.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename tokenizer.json
# RUN comfy model download --set-hf-api-token ${HF_TOKEN} --url https://huggingface.co/unsloth/Meta-Llama-3.1-8B-Instruct/resolve/main/tokenizer_config.json --relative-path models/LLM/Meta-Llama-3.1-8B-Instruct --filename tokenizer_config.json

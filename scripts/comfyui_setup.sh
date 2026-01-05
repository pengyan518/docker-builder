#!/usr/bin/env bash
# comfyui_setup.sh - ComfyUI 安装和配置模块

# ========== ComfyUI 安装 ==========
install_comfyui() {
    log_step "安装 ComfyUI..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 ComfyUI"
        return 0
    fi
    
    # 确保 ComfyUI 目录的父目录存在
    local comfyui_parent
    comfyui_parent=$(dirname "$COMFYUI_DIR")
    ensure_directory "$comfyui_parent"
    
    if [[ ! -d "$COMFYUI_DIR" ]]; then
        log_info "克隆 ComfyUI 仓库..."
        cd "$comfyui_parent" || { log_error "无法进入目录: $comfyui_parent"; return 1; }
        git clone https://github.com/comfyanonymous/ComfyUI.git
        cd "$COMFYUI_DIR" || { log_error "无法进入 ComfyUI 目录"; return 1; }
    else
        log_info "更新现有 ComfyUI..."
        cd "$COMFYUI_DIR" || { log_error "无法进入 ComfyUI 目录"; return 1; }
        git pull origin master || log_warning "ComfyUI 更新失败，继续使用现有版本"
    fi
    
    log_success "ComfyUI 安装完成"
}

# ========== ComfyUI 依赖安装 ==========
install_comfyui_dependencies() {
    local venv_path=$1
    
    log_step "安装 ComfyUI 依赖..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 ComfyUI 依赖"
        return 0
    fi
    
    source "$venv_path/bin/activate"
    cd "$COMFYUI_DIR"
       
    # 安装额外依赖
    log_info "安装额外依赖..."
    local extra_packages=(
        aiohttp
        websockets
        opencv-python
        scipy
        scikit-image
        transformers
        accelerate
        safetensors
        compel
        clip-interrogator
        kornia
    )
    
    pip install "${extra_packages[@]}"

    # 安装 ComfyUI 核心依赖
    if [[ -f "requirements.txt" ]]; then
        log_info "安装 ComfyUI 核心依赖..."
        pip install -r requirements.txt
    fi
    
    log_success "ComfyUI 依赖安装完成"
}

# ========== 模型目录结构 ==========
create_model_directories() {
    log_step "创建模型目录结构..."
    
    cd "$COMFYUI_DIR"
    
    local model_dirs=(
        models/checkpoints
        models/vae
        models/clip
        models/controlnet
        models/loras
        models/unet
        models/diffusion_models
        models/embeddings
        models/hypernetworks
        models/upscale_models
        models/style_models
        custom_nodes
        output
        input
        temp
    )
    
    for dir in "${model_dirs[@]}"; do
        ensure_directory "$dir"
    done
    
    log_success "模型目录结构创建完成"
}

# ========== 模型符号链接 ==========
setup_model_symlinks() {
    log_step "设置模型符号链接..."
    
    # 检查 /models 目录是否存在（Vast.ai 通常挂载模型到这里）
    if [[ -d "/models" ]]; then
        log_info "检测到 /models 目录，创建符号链接..."
        
        local model_types=(
            checkpoints
            vae
            clip
            controlnet
            loras
            unet
            diffusion_models
            embeddings
            hypernetworks
            upscale_models
        )
        
        for model_type in "${model_types[@]}"; do
            local vast_dir="/models/$model_type"
            local comfyui_dir="$COMFYUI_DIR/models/$model_type"
            
            if [[ -d "$vast_dir" ]]; then
                # 如果 ComfyUI 目录已存在且不是符号链接，先备份
                if [[ -d "$comfyui_dir" ]] && [[ ! -L "$comfyui_dir" ]]; then
                    log_info "备份现有目录: $comfyui_dir"
                    mv "$comfyui_dir" "${comfyui_dir}.backup.$(date +%Y%m%d_%H%M%S)"
                fi
                
                # 创建符号链接
                create_safe_symlink "$vast_dir" "$comfyui_dir"
            else
                log_info "创建本地目录: $comfyui_dir"
                ensure_directory "$comfyui_dir"
            fi
        done
    else
        log_info "未检测到 /models 目录，使用本地存储"
        create_model_directories
    fi
    
    log_success "模型符号链接设置完成"
}

# ========== Custom Nodes 安装 ==========
install_custom_nodes() {
    log_step "安装 Custom Nodes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 Custom Nodes"
        return 0
    fi
    
    cd "$COMFYUI_DIR/custom_nodes"
    
    # ComfyUI Manager
    if [[ ! -d "ComfyUI-Manager" ]]; then
        log_info "安装 ComfyUI Manager..."
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    fi
    
    # WAS Node Suite
    if [[ ! -d "was-node-suite-comfyui" ]]; then
        log_info "安装 WAS Node Suite..."
        git clone https://github.com/WASasquatch/was-node-suite-comfyui.git
        cd was-node-suite-comfyui
        pip install -r requirements.txt
        cd ..
    fi
    
    # # ControlNet Preprocessors
    # if [[ ! -d "comfyui_controlnet_aux" ]]; then
    #     log_info "安装 ControlNet Preprocessors..."
    #     git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git
    #     cd comfyui_controlnet_aux
    #     pip install -r requirements.txt
    #     cd ..
    # fi
    
    log_success "Custom Nodes 安装完成"
}

# ========== ComfyUI 配置生成 ==========
# generate_comfyui_config() {
#     log_step "生成 ComfyUI 配置..."
    
#     # 获取 GPU 内存信息
#     local gpu_memory_mb=$(get_gpu_info | tail -1)
#     local gpu_memory_gb=$((gpu_memory_mb / 1024))
    
#     # 生成配置文件
#     cat > "$COMFYUI_DIR/extra_model_paths.yaml" << EOF
# # ComfyUI 额外模型路径配置
# # 由安装脚本自动生成

# # Checkpoints 路径
# checkpoints:
#   - $COMFYUI_DIR/models/checkpoints
#   - /models/checkpoints

# # VAE 路径  
# vae:
#   - $COMFYUI_DIR/models/vae
#   - /models/vae

# # CLIP 路径
# clip:
#   - $COMFYUI_DIR/models/clip
#   - /models/clip

# # ControlNet 路径
# controlnet:
#   - $COMFYUI_DIR/models/controlnet
#   - /models/controlnet

# # LoRA 路径
# loras:
#   - $COMFYUI_DIR/models/loras
#   - /models/loras

# # UNet 路径
# unet:
#   - $COMFYUI_DIR/models/unet
#   - /models/unet

# # Diffusion Models 路径
# diffusion_models:
#   - $COMFYUI_DIR/models/diffusion_models
#   - /models/diffusion_models

# # Embeddings 路径
# embeddings:
#   - $COMFYUI_DIR/models/embeddings
#   - /models/embeddings

# # Upscale Models 路径
# upscale_models:
#   - $COMFYUI_DIR/models/upscale_models
#   - /models/upscale_models
# EOF
    
#     # 生成 ComfyUI 启动配置
#     local memory_flag=""
#     if [[ $gpu_memory_gb -lt 8 ]]; then
#         memory_flag="--lowvram"
#     elif [[ $gpu_memory_gb -lt 6 ]]; then
#         memory_flag="--novram"
#     fi
    
#     # 保存配置到环境变量文件
#     cat > "$COMFYUI_DIR/.comfyui_config" << EOF
# # ComfyUI 运行时配置
# COMFYUI_MEMORY_FLAG="$memory_flag"
# COMFYUI_GPU_MEMORY_GB="$gpu_memory_gb"
# COMFYUI_EXTRA_ARGS="--enable-cors-header --verbose"
# EOF
    
#     log_success "ComfyUI 配置生成完成"
# }

# ========== 启动脚本生成 ==========
generate_comfyui_startup_script() {
    log_step "生成 ComfyUI 启动脚本..."
    
    # 读取配置
    local memory_flag=""
    local extra_args=""
    if [[ -f "$COMFYUI_DIR/.comfyui_config" ]]; then
        source "$COMFYUI_DIR/.comfyui_config"
        memory_flag="$COMFYUI_MEMORY_FLAG"
        extra_args="$COMFYUI_EXTRA_ARGS"
    fi
    
    # 生成启动脚本
    generate_script "$WORK_DIR/start_comfyui.sh" "#!/bin/bash
set -e

echo \"🎨 启动 ComfyUI...\"

# 切换到 ComfyUI 目录
cd \"$COMFYUI_DIR\"

# 激活虚拟环境
source \"$WORK_DIR/venv/bin/activate\"

# 设置环境变量
export PYTHONPATH=\"$COMFYUI_DIR\"
# export CUDA_VISIBLE_DEVICES=\${CUDA_VISIBLE_DEVICES:-0}

# 加载 GPU 内存优化设置
# if [[ -n \"\${CUDA_MEMORY_FRACTION:-}\" ]]; then
#     export CUDA_MEMORY_FRACTION
# fi

# if [[ -n \"\${TORCH_CUDA_ALLOC_CONF:-}\" ]]; then
#     export TORCH_CUDA_ALLOC_CONF
# fi

# 启动 ComfyUI
exec python main.py \\
    --listen \"$COMFYUI_HOST\" \\
    --port \"$COMFYUI_PORT\" \\
    $memory_flag \\
    $extra_args
"
    
    log_success "ComfyUI 启动脚本生成完成"
}

# ========== ComfyUI 健康检查 ==========
check_comfyui_health() {
    local max_attempts=${1:-30}
    local wait_seconds=${2:-10}
    
    log_step "检查 ComfyUI 健康状态..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f "http://$COMFYUI_HOST:$COMFYUI_PORT/system_stats" > /dev/null 2>&1; then
            log_success "ComfyUI 健康检查通过"
            return 0
        fi
        
        log_info "等待 ComfyUI 启动... ($((attempt+1))/$max_attempts)"
        sleep $wait_seconds
        attempt=$((attempt+1))
    done
    
    log_error "ComfyUI 健康检查失败"
    return 1
}

# ========== 测试 ComfyUI ==========
test_comfyui() {
    local venv_path=$1
    
    log_step "测试 ComfyUI 安装..."
    
    source "$venv_path/bin/activate"
    cd "$COMFYUI_DIR"
    
    # 测试基本导入
    python -c "
import sys
import os
sys.path.insert(0, os.getcwd())

try:
    import main
    import execution
    import server
    import nodes
    print('✅ ComfyUI 核心模块导入成功')
except ImportError as e:
    print(f'❌ ComfyUI 模块导入失败: {e}')
    sys.exit(1)

# 测试节点加载
try:
    import folder_paths
    import model_management
    print('✅ ComfyUI 依赖模块导入成功')
except ImportError as e:
    print(f'❌ ComfyUI 依赖模块导入失败: {e}')
    sys.exit(1)

print('✅ ComfyUI 测试通过')
"
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_success "ComfyUI 测试通过"
        return 0
    else
        log_error "ComfyUI 测试失败"
        return 1
    fi
}

# ========== 主要设置函数 ==========
setup_comfyui() {
    local venv_path=$1
    
    log_step "设置 ComfyUI..."
        
    # 安装 ComfyUI
    install_comfyui

    # 安装依赖
    install_comfyui_dependencies "$venv_path"
    
    # 设置模型目录和符号链接
    setup_model_symlinks
    
    # # 安装 Custom Nodes
    # if ask_yes_no "是否安装 Custom Nodes？" "Y"; then
    #     install_custom_nodes
    # fi
    
    # 生成配置
    # generate_comfyui_config
    
    # 生成启动脚本
    generate_comfyui_startup_script
    
    # 测试安装
    if ! test_comfyui "$venv_path"; then
        log_error "ComfyUI 安装验证失败"
        # return 1
    fi
    
    log_success "ComfyUI 设置完成"
}

# ========== ComfyUI 信息显示 ==========
show_comfyui_info() {
    log_step "ComfyUI 环境信息："
    
    echo "==================================="
    echo "ComfyUI 目录: $COMFYUI_DIR"
    echo "ComfyUI 地址: http://$COMFYUI_HOST:$COMFYUI_PORT"
    
    if [[ -d "$COMFYUI_DIR" ]]; then
        echo "安装状态: ✅ 已安装"
        
        # 显示版本信息
        if [[ -d "$COMFYUI_DIR/.git" ]]; then
            cd "$COMFYUI_DIR"
            local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "未知")
            local commit_date=$(git log -1 --format=%cd --date=short 2>/dev/null || echo "未知")
            echo "版本信息: $commit_hash ($commit_date)"
        fi
        
        # 显示模型目录
        echo
        echo "模型目录:"
        local model_dirs=("checkpoints" "vae" "clip" "controlnet" "loras")
        for dir in "${model_dirs[@]}"; do
            local model_dir="$COMFYUI_DIR/models/$dir"
            if [[ -d "$model_dir" ]]; then
                local count=$(find "$model_dir" -maxdepth 1 -type f -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" | wc -l)
                echo "  $dir: $count 个模型文件"
            fi
        done
        
        # 显示 Custom Nodes
        echo
        echo "Custom Nodes:"
        if [[ -d "$COMFYUI_DIR/custom_nodes" ]]; then
            local node_count=$(find "$COMFYUI_DIR/custom_nodes" -maxdepth 1 -type d | wc -l)
            echo "  已安装: $((node_count-1)) 个节点包"
        else
            echo "  未安装"
        fi
    else
        echo "安装状态: ❌ 未安装"
    fi
    
    echo "==================================="
}

log_info "ComfyUI 设置模块 (comfyui_setup.sh) 已加载"

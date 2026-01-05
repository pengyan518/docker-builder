#!/usr/bin/env bash
# nvidia_setup.sh - NVIDIA 驱动和 CUDA 环境设置模块

# ========== NVIDIA 检测函数 ==========
check_nvidia_driver() {
    log_step "检查 NVIDIA 驱动..."
    
    if nvidia-smi &>/dev/null; then
        log_success "NVIDIA 驱动已安装并可用"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
        return 0
    elif dpkg -l | grep -q nvidia; then
        log_warning "检测到 NVIDIA 包但驱动可能有问题"
        return 1
    else
        log_error "未检测到 NVIDIA 驱动"
        return 1
    fi
}

check_cuda() {
    log_step "检查 CUDA..."
    
    if nvcc --version &>/dev/null; then
        log_success "CUDA 编译器可用"
        nvcc --version
        return 0
    else
        log_warning "CUDA 编译器未找到，但这通常不影响推理"
        return 1
    fi
}

get_gpu_info() {
    if nvidia-smi &>/dev/null; then
        local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        local gpu_names=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
        
        log_info "检测到 $gpu_count 个 GPU:"
        local i=0
        while IFS= read -r name && IFS= read -r memory <&3; do
            log_info "  GPU $i: $name ($memory MB)"
            ((i++))
        done <<< "$gpu_names" 3<<< "$gpu_memory"
        
        # 返回第一个GPU的内存大小（MB）
        echo "$gpu_memory" | head -1
    else
        echo "0"
    fi
}

# ========== NVIDIA 驱动安装 ==========
install_nvidia_driver() {
    log_step "安装 NVIDIA 驱动..."
    
    # 检查是否已安装
    if check_nvidia_driver; then
        log_info "NVIDIA 驱动已存在，跳过安装"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 NVIDIA 驱动"
        return 0
    fi
    
    # 添加 NVIDIA 官方仓库
    log_info "添加 NVIDIA 官方仓库..."
    wget -O- https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub | apt-key add -
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64 /" > /etc/apt/sources.list.d/cuda.list
    
    # 更新包列表
    apt-get update
    
    # 安装驱动
    log_info "安装 NVIDIA 驱动..."
    apt-get install -y nvidia-driver-535
    
    log_warning "NVIDIA 驱动安装完成，需要重启系统才能生效"
    log_info "请重启后重新运行此脚本"
    
    return 0
}

# ========== PyTorch 环境设置 ==========
setup_pytorch() {
    local venv_path=$1
    
    log_step "设置 PyTorch 环境..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 PyTorch"
        return 0
    fi
    
    # 激活虚拟环境
    source "$venv_path/bin/activate"
    
    # 检测 CUDA 版本
    local cuda_version=""
    if nvcc --version &>/dev/null; then
        cuda_version=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
        log_info "检测到 CUDA 版本: $cuda_version"
    fi
    
    # 根据 CUDA 版本选择 PyTorch 安装方式
    if [[ -n "$cuda_version" ]] && [[ "$cuda_version" =~ ^12\. ]]; then
        log_info "安装 PyTorch (CUDA 12.x)..."
        pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu129
    elif [[ -n "$cuda_version" ]] && [[ "$cuda_version" =~ ^11\. ]]; then
        log_info "安装 PyTorch (CUDA 11.x)..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
    else
        log_warning "未检测到 CUDA 或版本不支持，安装 CPU 版本 PyTorch"
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    fi
    
    log_success "PyTorch 安装完成"
}

verify_pytorch_cuda() {
    local venv_path=$1
    
    log_step "验证 PyTorch CUDA 支持..."
    
    source "$venv_path/bin/activate"
    
    python -c "
import torch
import sys

print(f'PyTorch 版本: {torch.__version__}')
print(f'CUDA 可用: {torch.cuda.is_available()}')

if torch.cuda.is_available():
    print(f'CUDA 版本: {torch.version.cuda}')
    print(f'cuDNN 版本: {torch.backends.cudnn.version()}')
    print(f'GPU 数量: {torch.cuda.device_count()}')
    
    for i in range(torch.cuda.device_count()):
        gpu_name = torch.cuda.get_device_name(i)
        gpu_memory = torch.cuda.get_device_properties(i).total_memory / 1024**3
        print(f'GPU {i}: {gpu_name} ({gpu_memory:.1f} GB)')
    
    # 测试基本 CUDA 操作
    try:
        x = torch.randn(1000, 1000).cuda()
        y = torch.randn(1000, 1000).cuda()
        z = torch.mm(x, y)
        print('✅ CUDA 基本操作测试通过')
    except Exception as e:
        print(f'❌ CUDA 基本操作测试失败: {e}')
        sys.exit(1)
else:
    print('⚠️  CUDA 不可用，将使用 CPU 进行推理')
"
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_success "PyTorch CUDA 验证通过"
        return 0
    else
        log_error "PyTorch CUDA 验证失败"
        return 1
    fi
}

# ========== GPU 内存优化 ==========
optimize_gpu_memory() {
    log_step "优化 GPU 内存设置..."
    
    # 获取 GPU 内存信息
    local gpu_memory_mb=$(get_gpu_info | tail -1)
    
    if [[ "$gpu_memory_mb" -gt 0 ]]; then
        local gpu_memory_gb=$((gpu_memory_mb / 1024))
        log_info "GPU 内存: ${gpu_memory_gb} GB"
        
        # 根据 GPU 内存调整设置
        if [[ $gpu_memory_gb -ge 24 ]]; then
            export CUDA_MEMORY_FRACTION=0.9
            export TORCH_CUDA_ALLOC_CONF="expandable_segments:True"
            log_info "高内存 GPU 配置 (>= 24GB)"
        elif [[ $gpu_memory_gb -ge 12 ]]; then
            export CUDA_MEMORY_FRACTION=0.8
            export TORCH_CUDA_ALLOC_CONF="expandable_segments:True"
            log_info "中等内存 GPU 配置 (>= 12GB)"
        else
            export CUDA_MEMORY_FRACTION=0.7
            export TORCH_CUDA_ALLOC_CONF="expandable_segments:True,max_split_size_mb:512"
            log_info "低内存 GPU 配置 (< 12GB)"
        fi
    else
        log_warning "未检测到 GPU，跳过内存优化"
    fi
}

# ========== 安装图形库 ==========
install_graphics_libraries() {
    log_step "安装图形和系统库..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将安装图形库"
        return 0
    fi
    
    local graphics_packages=(
        libgl1-mesa-glx
        libglib2.0-0
        libsm6
        libxext6
        libxrender-dev
        libgomp1
        libfontconfig1
        libxrandr2
        libegl1-mesa
        libgbm1
        libopencv-dev
        python3-opencv
    )
    install_packages "${graphics_packages[@]}"
    log_success "图形库安装完成"
}

# ========== 主要设置函数 ==========
setup_nvidia_environment() {
    log_step "设置 NVIDIA 环境..."
    
    # 检查现有安装
    local nvidia_ok=false
    if check_nvidia_driver; then
        nvidia_ok=true
    fi
    
    # 如果驱动有问题且不是 dry-run 模式，询问是否安装
    if [[ "$nvidia_ok" == "false" ]] && [[ "$DRY_RUN" != "true" ]]; then
        if ask_yes_no "NVIDIA 驱动有问题，是否尝试安装？" "N"; then
            install_nvidia_driver
            log_warning "请重启系统后重新运行脚本"
            exit 0
        else
            log_warning "继续安装，但 GPU 加速可能不可用"
        fi
    fi
    
    # 检查 CUDA
    check_cuda
    
    # 安装图形库
    # install_graphics_libraries
    
    # 优化 GPU 内存
    optimize_gpu_memory
    
    log_success "NVIDIA 环境设置完成"
}

setup_pytorch_environment() {
    local venv_path=$1
    
    log_step "设置 PyTorch 环境..."
    
    # 安装 PyTorch
    setup_pytorch "$venv_path"
    
    # 验证安装
    if ! verify_pytorch_cuda "$venv_path"; then
        log_error "PyTorch CUDA 验证失败"
        return 1
    fi
    
    log_success "PyTorch 环境设置完成"
}

# ========== 环境信息显示 ==========
show_nvidia_info() {
    log_step "NVIDIA 环境信息："
    
    echo "==================================="
    
    # 驱动信息
    if nvidia-smi &>/dev/null; then
        echo "NVIDIA 驱动信息:"
        nvidia-smi --query-gpu=driver_version --format=csv,noheader
        echo
        
        echo "GPU 信息:"
        nvidia-smi --query-gpu=index,name,memory.total,memory.used,temperature.gpu,power.draw --format=csv,noheader
        echo
    else
        echo "❌ NVIDIA 驱动不可用"
        echo
    fi
    
    # CUDA 信息
    if nvcc --version &>/dev/null; then
        echo "CUDA 信息:"
        nvcc --version | grep "release"
        echo
    else
        echo "❌ CUDA 不可用"
        echo
    fi
    
    echo "==================================="
}

log_info "NVIDIA 设置模块 (nvidia_setup.sh) 已加载"

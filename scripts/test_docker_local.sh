#!/usr/bin/env bash
# test_docker_local.sh
# 本地测试 Docker 镜像中的 ComfyUI
#
# 使用方法:
#   ./test_docker_local.sh [OPTIONS]
#
# 选项:
#   --build         先构建镜像
#   --gpu           使用 GPU (需要 nvidia-docker)
#   --help          显示帮助

set -euo pipefail

# ===== 配置 =====
IMAGE_NAME="${IMAGE_NAME:-enhou/runpod-comfyui-serverless-tezuka:latest}"
CONTAINER_NAME="comfyui-test"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

# 平台配置
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
USE_BUILDX="${USE_BUILDX:-auto}"  # auto, true, false
BUILDX_BUILDER="${BUILDX_BUILDER:-runpod-builder}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
本地测试 Docker 镜像中的 ComfyUI

使用方法:
    $0 [OPTIONS]

选项:
    --build         先构建镜像
    --gpu           使用 GPU (需要 nvidia-docker 或 Docker Desktop with GPU)
    --stop          停止并删除容器
    --use-buildx    强制使用 buildx 跨平台构建
    --no-buildx     强制使用传统 docker build
    --help          显示此帮助信息

环境变量:
    IMAGE_NAME      镜像名称 (默认: enhou/runpod-comfyui-serverless:latest)
    COMFYUI_PORT    ComfyUI 端口 (默认: 8188)
    HF_TOKEN        Hugging Face Token (构建时需要)
    DOCKER_PLATFORM 目标平台 (默认: linux/amd64)
    USE_BUILDX      使用 buildx (默认: auto - ARM64 自动启用)

示例:
    # 构建并运行 (with GPU) - 自动检测架构
    ./test_docker_local.sh --build --gpu

    # Mac 上强制使用 buildx 跨平台构建
    ./test_docker_local.sh --build --use-buildx

    # 仅运行已存在的镜像
    ./test_docker_local.sh --gpu

    # 停止容器
    ./test_docker_local.sh --stop

注意:
    - Mac (ARM64) 会自动使用 buildx 构建 linux/amd64 镜像
    - buildx 构建比传统构建慢，但兼容 RunPod
    - 构建不需要 GPU，但运行推荐使用 GPU

EOF
}

detect_platform() {
    log_info "检测系统平台..."
    
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    # 标准化架构名称
    case "${arch}" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
    esac
    
    log_info "检测到系统: ${os} ${arch}"
    
    # 自动决定是否使用 buildx
    if [[ "${USE_BUILDX}" == "auto" ]]; then
        if [[ "${arch}" == "arm64" ]]; then
            log_warning "检测到 ARM64 架构 (Mac M1/M2/M3)，将使用 buildx 进行跨平台构建"
            log_info "目标平台: ${DOCKER_PLATFORM}"
            USE_BUILDX="true"
        else
            log_info "检测到 AMD64 架构，可以使用传统 docker build"
            USE_BUILDX="false"
        fi
    fi
    
    log_info "构建方式: $([ "${USE_BUILDX}" == "true" ] && echo "buildx (跨平台)" || echo "docker build (原生)")"
}

check_docker() {
    log_info "检查 Docker 环境..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        log_info "请访问 https://www.docker.com/products/docker-desktop 下载安装"
        exit 1
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行，请启动 Docker Desktop"
        exit 1
    fi
    
    # 如果使用 buildx，检查是否可用
    if [[ "${USE_BUILDX}" == "true" ]]; then
        if ! docker buildx version &> /dev/null; then
            log_error "Docker buildx 未安装或未启用"
            log_info "请确保使用 Docker Desktop 最新版本"
            exit 1
        fi
        log_success "Docker buildx 可用"
    fi
    
    log_success "Docker 环境检查通过"
}

setup_buildx() {
    if [[ "${USE_BUILDX}" != "true" ]]; then
        return 0
    fi
    
    log_info "设置 Docker buildx 构建器..."
    
    # 检查构建器是否已存在
    if docker buildx inspect "${BUILDX_BUILDER}" &> /dev/null; then
        log_info "构建器 ${BUILDX_BUILDER} 已存在，将使用现有构建器"
    else
        log_info "创建新的构建器 ${BUILDX_BUILDER}..."
        docker buildx create \
            --name "${BUILDX_BUILDER}" \
            --driver docker-container \
            --bootstrap \
            --use
        log_success "构建器创建成功"
    fi
    
    # 使用构建器
    docker buildx use "${BUILDX_BUILDER}"
    
    log_success "Buildx 构建器已就绪"
}

build_image() {
    log_info "开始构建 Docker 镜像..."
    
    if [[ -z "${HF_TOKEN:-}" ]]; then
        log_error "HF_TOKEN 未设置"
        log_info "请先设置 HF_TOKEN:"
        log_info "  export HF_TOKEN=\"hf_your_token_here\""
        exit 1
    fi
    
    # 检查 Docker 和环境
    check_docker
    
    # 检测平台
    detect_platform
    
    # 设置 buildx（如果需要）
    setup_buildx
    
    log_info "构建镜像: ${IMAGE_NAME}"
    log_info "目标平台: ${DOCKER_PLATFORM}"
    log_warning "这可能需要 30-60 分钟，因为需要下载 ~33GB 模型..."
    
    if [[ "${USE_BUILDX}" == "true" ]]; then
        # 使用 buildx 跨平台构建
        log_info "使用 buildx 进行跨平台构建..."
        log_warning "Mac 用户: buildx 构建会比原生构建慢 2-3 倍"
        
        docker buildx build \
            --platform "${DOCKER_PLATFORM}" \
            --build-arg HF_TOKEN="${HF_TOKEN}" \
            -t "${IMAGE_NAME}" \
            -f Dockerfile \
            --load \
            --progress=plain \
            .
    else
        # 使用传统 docker build
        log_info "使用传统 docker build..."
        
        docker build \
            --build-arg HF_TOKEN="${HF_TOKEN}" \
            -t "${IMAGE_NAME}" \
            -f Dockerfile \
            --progress=plain \
            .
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "镜像构建成功: ${IMAGE_NAME}"
        
        # 显示镜像信息
        if docker images "${IMAGE_NAME}" &> /dev/null; then
            IMAGE_SIZE=$(docker images "${IMAGE_NAME}" --format "{{.Size}}")
            log_info "镜像大小: ${IMAGE_SIZE}"
        fi
    else
        log_error "镜像构建失败"
        log_info "💡 提示:"
        log_info "  1. 检查网络连接是否稳定"
        log_info "  2. 确认 HF_TOKEN 有效"
        log_info "  3. 查看错误日志定位问题"
        exit 1
    fi
}

stop_container() {
    log_info "停止并删除容器..."
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "${CONTAINER_NAME}" 2>/dev/null || true
        docker rm "${CONTAINER_NAME}" 2>/dev/null || true
        log_success "容器已停止并删除"
    else
        log_info "容器不存在，无需停止"
    fi
}

check_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        log_info "检测到 NVIDIA GPU:"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
        return 0
    else
        log_warning "未检测到 NVIDIA GPU 或 nvidia-smi 不可用"
        log_warning "如果你有 GPU，确保已安装 NVIDIA Container Toolkit"
        return 1
    fi
}

run_container() {
    local use_gpu=$1
    
    log_info "启动容器: ${CONTAINER_NAME}"
    log_info "ComfyUI 将运行在: http://localhost:${COMFYUI_PORT}"
    
    # 停止已存在的容器
    stop_container
    
    # 构建 docker run 命令
    local docker_cmd="docker run -d --name ${CONTAINER_NAME}"
    
    # GPU 支持
    if [[ "${use_gpu}" == "true" ]]; then
        if check_gpu; then
            docker_cmd="${docker_cmd} --gpus all"
            log_info "使用 GPU 模式"
        else
            log_error "未检测到 GPU，但指定了 --gpu 选项"
            log_info "提示: 在 Mac 或无 GPU 环境中，移除 --gpu 选项"
            exit 1
        fi
    else
        log_warning "CPU 模式运行 (不推荐，会非常慢)"
    fi
    
    # 端口映射
    docker_cmd="${docker_cmd} -p ${COMFYUI_PORT}:8188"
    
    # 镜像名称
    docker_cmd="${docker_cmd} ${IMAGE_NAME}"
    
    # runpod/worker-comfyui 需要特殊的启动命令来运行 ComfyUI UI
    # 覆盖默认的 CMD，直接启动 ComfyUI
    # docker run -d --name comfyui-test -p 8188:8188 enhou/runpod-comfyui-serverless:latest python /comfyui/main.py --listen 0.0.0.0 --port 8188
	# docker run -d --name runpod-test --gpus all -p 8188:8188 enhou/runpod-comfyui-serverless-tezuka:latest python /comfyui/main.py --listen 0.0.0.0 --port 8188
	
    docker_cmd="${docker_cmd} python /comfyui/main.py --listen 0.0.0.0 --port 8188"
    
    log_info "执行命令: ${docker_cmd}"
    
    eval "${docker_cmd}"
    
    if [[ $? -eq 0 ]]; then
        log_success "容器已启动"
        log_info ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_success "ComfyUI 正在启动..."
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info ""
        log_info "🌐 Web UI: ${GREEN}http://localhost:${COMFYUI_PORT}${NC}"
        log_info "📊 查看日志: ${YELLOW}docker logs -f ${CONTAINER_NAME}${NC}"
        log_info "🛑 停止容器: ${YELLOW}./test_docker_local.sh --stop${NC}"
        log_info ""
        log_warning "等待 30-60 秒让 ComfyUI 完全启动..."
        log_info ""
        
        # 等待 ComfyUI 启动
        log_info "监控启动日志..."
        sleep 5
        docker logs "${CONTAINER_NAME}"
        
        log_info ""
        log_info "继续查看实时日志..."
        docker logs -f "${CONTAINER_NAME}"
    else
        log_error "容器启动失败"
        exit 1
    fi
}

# ===== 主程序 =====
main() {
    local do_build=false
    local use_gpu=true
    local do_stop=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build)
                do_build=true
                shift
                ;;
            --gpu)
                use_gpu=true
                shift
                ;;
			--cpu)
                use_gpu=false
                shift
                ;;
            --stop)
                do_stop=true
                shift
                ;;
            --use-buildx)
                USE_BUILDX="true"
                shift
                ;;
            --no-buildx)
                USE_BUILDX="false"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 停止容器
    if [[ "${do_stop}" == "true" ]]; then
        stop_container
        exit 0
    fi
    
    # 构建镜像
    if [[ "${do_build}" == "true" ]]; then
        build_image
    fi
    
    # 检查镜像是否存在
    if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
        log_warning "镜像不存在于本地: ${IMAGE_NAME}"
        log_info "尝试从 Docker Hub 拉取镜像..."
        
        if docker pull "${IMAGE_NAME}"; then
            log_success "镜像拉取成功"
            
            # 检查镜像平台
            local img_platform=$(docker image inspect "${IMAGE_NAME}" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null)
            local host_platform=$(uname -s | tr '[:upper:]' '[:lower:]')/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
            
            if [[ "${img_platform}" != "${host_platform}" ]]; then
                log_warning "镜像平台 (${img_platform}) 与主机平台 (${host_platform}) 不匹配"
                log_warning "将使用 QEMU 模拟运行，性能会很差"
                log_info "这仅用于验证配置，不适合性能测试"
            fi
        else
            log_error "无法拉取镜像: ${IMAGE_NAME}"
            log_info "请选择以下方式之一:"
            log_info "  1. 构建镜像: ./test_docker_local.sh --build"
            log_info "  2. 检查镜像名称是否正确"
            log_info "  3. 检查 Docker Hub 登录状态（如果是私有镜像）"
            exit 1
        fi
    fi
    
    # 运行容器
    run_container "${use_gpu}"
}

main "$@"


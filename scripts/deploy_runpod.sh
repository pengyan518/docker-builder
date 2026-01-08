#!/usr/bin/env bash
# scripts/deploy_runpod.sh
# RunPod Serverless 部署脚本
#
# 功能:
# 1. 构建优化的 Docker 镜像
# 2. 推送到 Docker Hub/Registry
# 3. 在 RunPod 上创建/更新 Serverless Endpoint
#
# 使用方法:
#   ./scripts/deploy_runpod.sh [OPTIONS]
#
# 选项:
#   --build-only    仅构建镜像，不推送
#   --push-only     仅推送镜像，不构建
#   --skip-tests    跳过测试
#   --help          显示帮助信息

set -euo pipefail

# ===== 配置 =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Docker 镜像配置
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-enhou}"
IMAGE_NAME="${IMAGE_NAME:-runpod-comfyui-serverless-tezuka}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

# 平台配置（RunPod 需要 linux/amd64）
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
USE_BUILDX="${USE_BUILDX:-auto}"  # auto, true, false
BUILDX_BUILDER="${BUILDX_BUILDER:-runpod-builder}"

# RunPod 配置
RUNPOD_API_KEY="${RUNPOD_API_KEY:-}"
RUNPOD_ENDPOINT_ID="${RUNPOD_ENDPOINT_ID:-}"

# Hugging Face 配置
HF_TOKEN="${HF_TOKEN:-}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== 函数 =====
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
RunPod Serverless 部署脚本（支持 Mac 跨平台构建）

使用方法:
    $0 [OPTIONS]

选项:
    --build-only     仅构建镜像，不推送
    --push-only      仅推送镜像，不构建
    --skip-tests     跳过测试
    --use-buildx     强制使用 buildx 跨平台构建
    --no-buildx      强制使用传统 docker build
    --help           显示此帮助信息

环境变量:
    DOCKER_REGISTRY       Docker 仓库地址 (默认: docker.io)
    DOCKER_USERNAME       Docker 用户名 (默认: enhou)
    DOCKER_PASSWORD       Docker 密码/Token
    IMAGE_NAME            镜像名称 (默认: comfyui-serverless)
    IMAGE_TAG             镜像标签 (默认: latest)
    DOCKER_PLATFORM       目标平台 (默认: linux/amd64)
    USE_BUILDX            使用 buildx (默认: auto)
    RUNPOD_API_KEY        RunPod API 密钥
    RUNPOD_ENDPOINT_ID    RunPod Endpoint ID (可选)
    HF_TOKEN              Hugging Face Token (用于下载模型)

示例:
    # 完整部署流程（自动检测是否需要 buildx）
    export HF_TOKEN="hf_xxxxx"
    export DOCKER_PASSWORD="your_token"
    ./scripts/deploy_runpod.sh

    # Mac 上跨平台构建
    ./scripts/deploy_runpod.sh --use-buildx

    # 仅构建镜像
    ./scripts/deploy_runpod.sh --build-only

    # 仅推送镜像
    export DOCKER_PASSWORD="your_token"
    ./scripts/deploy_runpod.sh --push-only

    # 使用自定义标签
    IMAGE_TAG=v1.0.0 ./scripts/deploy_runpod.sh

注意:
    - Mac (ARM64) 会自动使用 buildx 进行跨平台构建
    - Linux (AMD64) 可以使用传统 docker build
    - 跨平台构建需要 15-30 分钟，请耐心等待

EOF
}

# ========== 环境变量加载 ==========
load_environment() {
    log_info "加载环境变量..."
    
    # 尝试从多个位置加载 .env 文件
    local env_files=("./.env")
    
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            log_info "从 $env_file 加载环境变量"
            set -a
            # shellcheck source=/dev/null
            source "$env_file"
            set +a
            break
        fi
    done
    
    # 导出关键环境变量
    local key_vars=(
        "HF_TOKEN"
        "IMAGE_NAME"
        "IMAGE_TAG"
        "DOCKER_PASSWORD"
		"CIVITAI_TOKEN"
		"R2_ACCESS_KEY_ID"
		"R2_SECRET_ACCESS_KEY"
		"R2_ENDPOINT"
    )
    
    local var
    for var in "${key_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            export "$var"
        fi
    done
    
    log_info "环境变量加载完成"
}

detect_platform() {
    # 检测当前系统架构
    local arch=$(uname -m)
    local os=$(uname -s)
    
    log_info "检测到系统: ${os} ${arch}"
    
    # 自动决定是否使用 buildx
    if [[ "${USE_BUILDX}" == "auto" ]]; then
        if [[ "${arch}" == "arm64" ]] || [[ "${arch}" == "aarch64" ]]; then
            log_info "检测到 ARM64 架构，将使用 buildx 进行跨平台构建"
            USE_BUILDX="true"
        else
            log_info "检测到 AMD64 架构，可以使用传统 docker build"
            USE_BUILDX="false"
        fi
    fi
    
    log_info "构建方式: $([ "${USE_BUILDX}" == "true" ] && echo "buildx (跨平台)" || echo "docker build (原生)")"
    log_info "目标平台: ${DOCKER_PLATFORM}"
}

check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行，请启动 Docker"
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
    
    # 检查 Dockerfile
    if [[ ! -f "${PROJECT_ROOT}/Dockerfile" ]]; then
        log_error "Dockerfile 不存在"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

setup_buildx() {
    if [[ "${USE_BUILDX}" != "true" ]]; then
        return 0
    fi
    
    log_info "设置 Docker buildx 构建器..."
    
    # 检查构建器是否已存在
    if docker buildx inspect "${BUILDX_BUILDER}" &> /dev/null; then
        log_info "构建器 ${BUILDX_BUILDER} 已存在"
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
    log_info "镜像名称: ${FULL_IMAGE_NAME}"
    log_info "目标平台: ${DOCKER_PLATFORM}"
    
    cd "${PROJECT_ROOT}"
    
    if [[ "${USE_BUILDX}" == "true" ]]; then
        # 使用 buildx 跨平台构建
        log_info "使用 buildx 进行跨平台构建（这可能需要 15-30 分钟）..."
        log_warning "首次构建会下载基础镜像，请耐心等待"
        
        docker buildx build \
            --platform "${DOCKER_PLATFORM}" \
            --build-arg HF_TOKEN="${HF_TOKEN}" \
			--build-arg CIVITAI_TOKEN="${CIVITAI_TOKEN}" \
			--build-arg R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
			--build-arg R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
			--build-arg R2_ENDPOINT="${R2_ENDPOINT}" \
            -f Dockerfile \
            -t "${FULL_IMAGE_NAME}" \
            --load \
            --progress=plain \
            .
    else
        # 使用传统 docker build
        log_info "使用传统 docker build..."
        
        # 使用 extra_model_paths.yaml 文件
        # docker build -f Dockerfile --build-arg HF_TOKEN="${HF_TOKEN}" --build-arg BUILDKIT_INLINE_CACHE=1 --progress=plain --build-arg EXTRA_MODEL_PATHS=/extra_model_paths.yaml .
        docker build \
            -f Dockerfile \
            -t "${FULL_IMAGE_NAME}" \
            --build-arg HF_TOKEN="${HF_TOKEN}" \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
			--build-arg CIVITAI_TOKEN="${CIVITAI_TOKEN}" \
			--build-arg R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
			--build-arg R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
			--build-arg R2_ENDPOINT="${R2_ENDPOINT}" \
            --progress=plain \
            .
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "镜像构建成功: ${FULL_IMAGE_NAME}"
        
        # 显示镜像信息
        if docker images "${FULL_IMAGE_NAME}" &> /dev/null; then
            IMAGE_SIZE=$(docker images "${FULL_IMAGE_NAME}" --format "{{.Size}}")
            log_info "镜像大小: ${IMAGE_SIZE}"
        fi
    else
        log_error "镜像构建失败"
        exit 1
    fi
}

build_and_push_image() {
    # 使用 buildx 直接构建并推送（更高效）
    if [[ "${USE_BUILDX}" != "true" ]]; then
        log_error "此函数仅用于 buildx 模式"
        return 1
    fi
    
    log_info "开始跨平台构建并推送..."
    log_info "镜像名称: ${FULL_IMAGE_NAME}"
    log_info "目标平台: ${DOCKER_PLATFORM}"
    log_warning "这可能需要 15-30 分钟，请耐心等待"
    
    cd "${PROJECT_ROOT}"
    
    # 登录 Docker Registry
    if [[ -n "${DOCKER_PASSWORD:-}" ]]; then
        log_info "登录 Docker Registry..."
        echo "${DOCKER_PASSWORD}" | docker login "${DOCKER_REGISTRY}" -u "${DOCKER_USERNAME}" --password-stdin
    fi
    
    # 使用 buildx 构建并直接推送
    docker buildx build \
        --platform "${DOCKER_PLATFORM}" \
        -f Dockerfile \
        -t "${FULL_IMAGE_NAME}" \
        --push \
        --progress=plain \
        .
    
    if [[ $? -eq 0 ]]; then
        log_success "镜像构建并推送成功: ${FULL_IMAGE_NAME}"
        
        # 验证镜像
        log_info "验证镜像平台..."
        docker buildx imagetools inspect "${FULL_IMAGE_NAME}" | grep -E "(Platform|Digest)" || true
    else
        log_error "镜像构建或推送失败"
        exit 1
    fi
}

push_image() {
    log_info "推送镜像到仓库..."
    
    # 登录 Docker Registry (如果需要)
    if [[ -n "${DOCKER_PASSWORD:-}" ]]; then
        echo "${DOCKER_PASSWORD}" | docker login "${DOCKER_REGISTRY}" -u "${DOCKER_USERNAME}" --password-stdin
    fi
    
    # 推送镜像
    docker push "${FULL_IMAGE_NAME}"
    
    if [[ $? -eq 0 ]]; then
        log_success "镜像推送成功: ${FULL_IMAGE_NAME}"
    else
        log_error "镜像推送失败"
        exit 1
    fi
}

test_image_locally() {
    log_info "本地测试镜像..."
    
    # # 检查必需的环境变量
    # if [[ -z "${SUPABASE_URL:-}" ]] || [[ -z "${SUPABASE_SERVICE_KEY:-}" ]]; then
    #     log_warning "缺少 Supabase 环境变量，跳过本地测试"
    #     return 0
    # fi
    
    # 运行容器测试
    log_info "启动测试容器..."
    # docker run --rm -d \
    #     --name runpod-test \
    #     -e HF_TOKEN="${HF_TOKEN}" \
    #     --gpus all \
    #     "${FULL_IMAGE_NAME}"
	# docker stop runpod-test
	# docker rm -f runpod-test 2>/dev/null || true
	# docker run -d --name runpod-test --gpus all -p 8188:8188 enhou/runpod-comfyui-serverless-upscale-lora:latest python /comfyui/main.py --listen 0.0.0.0 --port 8188
	docker run -d \
		--name runpod-test \
		--gpus all \
		-p 8188:8188 \
		"${FULL_IMAGE_NAME}" \
		python /comfyui/main.py --listen 0.0.0.0 --port 8188
    
    # 等待容器启动
    sleep 10
    
    # 检查容器状态
    if docker ps | grep -q runpod-test; then
        log_success "容器启动成功"
        docker logs runpod-test
        docker stop runpod-test
    else
        log_error "容器启动失败"
        docker logs runpod-test
        docker rm -f runpod-test 2>/dev/null || true
        exit 1
    fi
}

deploy_to_runpod() {
    log_info "部署到 RunPod Serverless..."
    
    if [[ -z "${RUNPOD_API_KEY}" ]]; then
        log_warning "RUNPOD_API_KEY 未设置，跳过 RunPod 部署"
        log_info "请手动在 RunPod 控制台创建 Serverless Endpoint"
        log_info "使用镜像: ${FULL_IMAGE_NAME}"
        # return 0
    fi
    
    # TODO: 使用 RunPod API 创建/更新 Endpoint
    # 这里需要根据 RunPod API 文档实现
    
    log_info "请访问 RunPod 控制台完成部署配置:"
    log_info "https://www.runpod.io/console/serverless"
    log_info ""
    log_info "部署配置:"
    log_info "  镜像: ${FULL_IMAGE_NAME}"
    log_info "  GPU: NVIDIA A4000 或更高"
    log_info "  最小 VRAM: 16GB"
    log_info "  网络存储: 建议启用 (用于模型缓存)"
    log_info ""
    log_info "环境变量 (必需):"
    log_info "  SUPABASE_URL"
    log_info "  SUPABASE_SERVICE_KEY"
    log_info "  R2_ENDPOINT"
    log_info "  R2_ACCESS_KEY_ID"
    log_info "  R2_SECRET_ACCESS_KEY"
    log_info "  R2_BUCKET_NAME"
    log_info "  STORAGE_BACKEND (supabase 或 r2)"
}

# ===== 主流程 =====
main() {
    local BUILD_ONLY=false
    local PUSH_ONLY=false
    local SKIP_TESTS=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            --push-only)
                PUSH_ONLY=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
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
    
    log_info "========================================="
    log_info "RunPod Serverless 部署脚本"
    log_info "========================================="
    
    load_environment
    
    # 检测平台和构建方式
    detect_platform
    
    check_prerequisites
    
    if [[ "${PUSH_ONLY}" == "false" ]]; then
        # 设置 buildx（如果需要）
        setup_buildx
        
        # 如果使用 buildx 且不是仅构建模式，可以直接构建并推送
        if [[ "${USE_BUILDX}" == "true" ]] && [[ "${BUILD_ONLY}" == "false" ]]; then
            log_info "使用 buildx 一步完成构建和推送（更高效）"
            build_and_push_image
            
            if [[ "${SKIP_TESTS}" == "false" ]]; then
                log_warning "跨平台构建的镜像无法在本地测试（架构不匹配）"
                log_info "镜像已推送，可以在 RunPod 上测试"
            fi
            
            deploy_to_runpod
            
            log_success "========================================="
            log_success "部署流程完成！"
            log_success "========================================="
            return 0
        fi
        
        # 传统流程：先构建
        build_image
        
        if [[ "${SKIP_TESTS}" == "false" ]]; then
            if [[ "${USE_BUILDX}" == "true" ]]; then
                log_warning "跨平台构建的镜像无法在本地测试（架构不匹配）"
            else
                test_image_locally
            fi
        fi
    fi
    
    if [[ "${BUILD_ONLY}" == "false" ]]; then
        push_image
        deploy_to_runpod
    fi
    
    log_success "========================================="
    log_success "部署流程完成！"
    log_success "========================================="
    log_info "镜像: ${FULL_IMAGE_NAME}"
    log_info ""
    log_info "下一步:"
    log_info "1. 在 RunPod 控制台创建 Serverless Endpoint"
    log_info "2. 配置环境变量"
    log_info "3. 测试 Endpoint"
    log_info ""
    log_info "测试命令:"
    log_info "  curl -X POST https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/run \\"
    log_info "    -H 'Authorization: Bearer YOUR_API_KEY' \\"
    log_info "    -H 'Content-Type: application/json' \\"
    log_info "    -d '{\"input\": {\"prompt\": \"a beautiful landscape\", \"model_checkpoint\": \"sd_xl_base_1.0.safetensors\"}}'"
}

# 运行主流程
main "$@"

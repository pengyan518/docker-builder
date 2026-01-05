#!/usr/bin/env bash
# config.sh - 配置管理模块

# ========== 默认配置 ==========
readonly DEFAULT_WORK_DIR="/my-hybrid-service"
readonly DEFAULT_COMFYUI_DIR="/workspace/ComfyUI"
readonly DEFAULT_PYTHON_VERSION="3.10"
readonly DEFAULT_REPO="black-forest-labs/FLUX.1-dev"
readonly DEFAULT_CONNECTIONS="5"
readonly DEFAULT_SPLIT="16"

# ========== 全局配置变量 ==========
# 工作目录配置
WORK_DIR="${WORK_DIR:-$DEFAULT_WORK_DIR}"
COMFYUI_DIR="${COMFYUI_DIR:-$DEFAULT_COMFYUI_DIR}"
PYTHON_VERSION="${PYTHON_VERSION:-$DEFAULT_PYTHON_VERSION}"

# 服务配置
FASTAPI_HOST="${FASTAPI_HOST:-0.0.0.0}"
FASTAPI_PORT="${FASTAPI_PORT:-8000}"
COMFYUI_HOST="${COMFYUI_HOST:-0.0.0.0}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

# 下载配置
HF_REPO="${HF_REPO:-$DEFAULT_REPO}"
CONNECTIONS="${CONNECTIONS:-$DEFAULT_CONNECTIONS}"
SPLIT="${SPLIT:-$DEFAULT_SPLIT}"

# 自动化配置
AUTO_INSTALL="${AUTO_INSTALL:-false}"
SKIP_DEPS="${SKIP_DEPS:-false}"
DRY_RUN="${DRY_RUN:-false}"

# 模型下载配置
AUTO_DOWNLOAD_MODEL="${AUTO_DOWNLOAD_MODEL:-flux1-dev.safetensors}"
AUTO_DOWNLOAD_TYPE="${AUTO_DOWNLOAD_TYPE:-}"
AUTO_DOWNLOAD_ALL="${AUTO_DOWNLOAD_ALL:-false}"

# Cloudflare R2 配置
R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-}"
R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-}"
R2_ENDPOINT="${R2_ENDPOINT:-}"

# Ngrok 配置
NGROK_TOKEN="${NGROK_TOKEN:-}"
NGROK_DOMAIN="${NGROK_DOMAIN:-}"

# GitHub 配置
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ========== 配置验证函数 ==========
validate_config() {
    log_step "验证配置..."
    
    local errors=0
    
    # 验证工作目录
    if [[ ! -d "$WORK_DIR" ]]; then
        log_error "工作目录不存在: $WORK_DIR"
        ((errors++))
    fi
    
    # 验证 Python 版本
    if ! command -v "python$PYTHON_VERSION" > /dev/null 2>&1; then
        log_error "Python $PYTHON_VERSION 未安装"
        ((errors++))
    fi
    
    # 验证端口可用性
    for port in $FASTAPI_PORT $COMFYUI_PORT; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "端口 $port 已被占用"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "配置验证通过"
        return 0
    else
        log_error "配置验证失败，发现 $errors 个错误"
        return 1
    fi
}

# ========== 配置显示函数 ==========
show_config() {
    log_info "当前配置:"
    echo "  工作目录: $WORK_DIR"
    echo "  ComfyUI目录: $COMFYUI_DIR"
    echo "  Python版本: $PYTHON_VERSION"
    echo "  FastAPI地址: $FASTAPI_HOST:$FASTAPI_PORT"
    echo "  ComfyUI地址: $COMFYUI_HOST:$COMFYUI_PORT"
    echo "  HF仓库: $HF_REPO"
    echo "  自动安装: $AUTO_INSTALL"
    echo "  跳过依赖: $SKIP_DEPS"
    echo "  预演模式: $DRY_RUN"
    
    if [[ -n "$AUTO_DOWNLOAD_MODEL" ]]; then
        echo "  自动下载模型: $AUTO_DOWNLOAD_MODEL"
    fi
    
    if [[ -n "$R2_ENDPOINT" ]]; then
        echo "  R2端点: $R2_ENDPOINT"
    fi
    
    if [[ -n "$NGROK_TOKEN" ]]; then
        echo "  Ngrok: 已配置"
    fi
}

# ========== 环境变量加载 ==========
load_environment() {
    log_step "加载环境变量..."
    
    # 尝试从多个位置加载 .env 文件
    local env_files=(
        "$WORK_DIR/.env"
        "${HOME}/.env"
        "./.env"
    )
    
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
        "R2_ACCESS_KEY_ID"
        "R2_SECRET_ACCESS_KEY"
        "R2_ENDPOINT"
        "NGROK_TOKEN"
        "GITHUB_USERNAME"
        "GITHUB_TOKEN"
    )
    
    local var
    for var in "${key_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            export "$var"
        fi
    done
    
    log_success "环境变量加载完成"
}

# ========== 配置解析函数 ==========
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --work-dir)
                WORK_DIR="$2"
                shift 2
                ;;
            --comfyui-dir)
                COMFYUI_DIR="$2"
                shift 2
                ;;
            --python-version)
                PYTHON_VERSION="$2"
                shift 2
                ;;
            --auto-install)
                AUTO_INSTALL="true"
                shift
                ;;
            --skip-deps)
                SKIP_DEPS="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --model)
                AUTO_DOWNLOAD_MODEL="$2"
                shift 2
                ;;
            --type)
                AUTO_DOWNLOAD_TYPE="$2"
                shift 2
                ;;
            --all-models)
                AUTO_DOWNLOAD_ALL="true"
                shift
                ;;
            --fastapi-port)
                FASTAPI_PORT="$2"
                shift 2
                ;;
            --comfyui-port)
                COMFYUI_PORT="$2"
                shift 2
                ;;
            --ngrok-token)
                NGROK_TOKEN="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ========== 帮助信息 ==========
show_help() {
    cat << EOF
Vast.ai ComfyUI 集成部署脚本

用法: $0 [选项]

选项:
    --work-dir DIR          指定工作目录 (默认: $DEFAULT_WORK_DIR)
    --comfyui-dir DIR       指定ComfyUI目录 (默认: $DEFAULT_COMFYUI_DIR)
    --python-version VER    指定Python版本 (默认: $DEFAULT_PYTHON_VERSION)
    --auto-install          自动安装模式，不询问用户
    --skip-deps             跳过依赖检查和安装
    --dry-run               预演模式，不执行实际操作
    --model MODEL           指定要下载的模型
    --type TYPE             指定要下载的模型类型
    --all-models            下载所有模型
    --fastapi-port PORT     指定FastAPI端口 (默认: 8000)
    --comfyui-port PORT     指定ComfyUI端口 (默认: 8188)
    --ngrok-token TOKEN     指定Ngrok认证token
    -h, --help              显示此帮助信息

环境变量:
    WORK_DIR               工作目录
    COMFYUI_DIR            ComfyUI目录
    AUTO_INSTALL           自动安装模式
    HF_TOKEN               Hugging Face API Token
    R2_ACCESS_KEY_ID       Cloudflare R2 Access Key
    R2_SECRET_ACCESS_KEY   Cloudflare R2 Secret Key
    R2_ENDPOINT            Cloudflare R2 Endpoint
    NGROK_TOKEN            Ngrok认证token
    GITHUB_USERNAME        GitHub用户名
    GITHUB_TOKEN           GitHub Personal Access Token

示例:
    # 基本安装
    $0
    
    # 自动安装模式
    $0 --auto-install
    
    # 指定工作目录和模型
    $0 --work-dir /custom/path --model flux1-dev.safetensors
    
    # 预演模式
    $0 --dry-run

EOF
}

# ========== 配置文件生成 ==========
generate_env_template() {
    local env_file="${1:-$WORK_DIR/.env.template}"
    
    cat > "$env_file" << EOF
# Vast.ai ComfyUI 集成服务配置文件

# ========== 基础配置 ==========
WORK_DIR=$WORK_DIR
COMFYUI_DIR=$COMFYUI_DIR
PYTHON_VERSION=$PYTHON_VERSION

# ========== 服务配置 ==========
FASTAPI_HOST=$FASTAPI_HOST
FASTAPI_PORT=$FASTAPI_PORT
COMFYUI_HOST=$COMFYUI_HOST
COMFYUI_PORT=$COMFYUI_PORT

# ========== Hugging Face 配置 ==========
HF_TOKEN=hf_your_token_here
HF_REPO=$HF_REPO

# ========== Cloudflare R2 配置 ==========
R2_ACCESS_KEY_ID=your_access_key_here
R2_SECRET_ACCESS_KEY=your_secret_key_here
R2_ENDPOINT=your_endpoint_here

# ========== Ngrok 配置 ==========
NGROK_TOKEN=your_ngrok_token_here
NGROK_DOMAIN=your_domain_here

# ========== GitHub 配置 ==========
GITHUB_USERNAME=your_username_here
GITHUB_TOKEN=your_personal_access_token_here

# ========== 自动化配置 ==========
AUTO_INSTALL=false
SKIP_DEPS=false
DRY_RUN=false

# ========== 模型下载配置 ==========
AUTO_DOWNLOAD_MODEL=$AUTO_DOWNLOAD_MODEL
AUTO_DOWNLOAD_TYPE=
AUTO_DOWNLOAD_ALL=false

EOF
    
    log_success "生成配置模板: $env_file"
}

# ========== 配置初始化 ==========
init_config() {
    log_step "初始化配置..."
    
    # 加载环境变量
    load_environment
    
    # 确保工作目录存在
    ensure_directory "$WORK_DIR"
    
    # 生成配置模板（如果不存在）
    if [[ ! -f "$WORK_DIR/.env" ]] && [[ ! -f "$WORK_DIR/.env.template" ]]; then
        generate_env_template "$WORK_DIR/.env.template"
        log_info "请根据需要编辑 $WORK_DIR/.env.template 并重命名为 .env"
    fi
    
    log_success "配置初始化完成"
}

log_info "配置模块 (config.sh) 已加载"

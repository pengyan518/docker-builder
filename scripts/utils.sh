#!/usr/bin/env bash
# utils.sh - 通用工具函数模块

# 严格错误处理
set -euo pipefail

# ========== 颜色定义 ==========
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${CYAN}🚀 $1${NC}"; }

# ========== 错误处理 ==========
handle_error() {
    local exit_code=$?
    local line_no=$1
    log_error "脚本在第 $line_no 行失败，退出码: $exit_code"
    cleanup
    exit $exit_code
}

cleanup() {
    log_info "执行清理操作..."
    # 清理临时文件等
    rm -f /tmp/vast_setup_*
}

# 设置错误陷阱
setup_error_handling() {
    trap 'handle_error $LINENO' ERR
    trap 'cleanup; exit 130' INT TERM
}

# ========== 系统检查函数 ==========
check_root() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    else
        log_error "此脚本需要 root 权限"
        return 1
    fi
}

detect_system_info() {
    log_step "检测系统信息..."
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep ^NAME= /etc/os-release | cut -d'"' -f2)
        local os_version=$(grep VERSION_ID= /etc/os-release | cut -d'"' -f2)
        local os_codename=$(grep VERSION_CODENAME= /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "unknown")
        
        log_info "操作系统: $os_name $os_version ($os_codename)"
        
        # 导出系统信息供其他模块使用
        export DETECTED_OS_NAME="$os_name"
        export DETECTED_OS_VERSION="$os_version"
        export DETECTED_OS_CODENAME="$os_codename"
    else
        log_warning "无法检测操作系统信息"
        export DETECTED_OS_NAME="unknown"
        export DETECTED_OS_VERSION="unknown"
        export DETECTED_OS_CODENAME="unknown"
    fi
    
    # 检测架构
    local arch=$(uname -m)
    log_info "系统架构: $arch"
    export DETECTED_ARCH="$arch"
    
    # 检测内核版本
    local kernel=$(uname -r)
    log_info "内核版本: $kernel"
    export DETECTED_KERNEL="$kernel"
    
    # 检测容器环境
    if [[ -f /.dockerenv ]]; then
        log_info "运行环境: Docker 容器"
        export DETECTED_CONTAINER="docker"
    elif [[ -n "${VAST_CONTAINERLABEL:-}" ]] || [[ -f /etc/vast_info ]]; then
        log_info "运行环境: Vast.ai 实例"
        export DETECTED_CONTAINER="vast"
    else
        log_info "运行环境: 物理机/虚拟机"
        export DETECTED_CONTAINER="none"
    fi
}

check_vast_env() {
    if [[ -f "/etc/vast_info" ]] || [[ -n "${VAST_CONTAINERLABEL:-}" ]]; then
        log_success "检测到 Vast.ai 环境"
        return 0
    else
        log_warning "似乎不在 Vast.ai 环境中运行"
        return 1
    fi
}

check_disk_space() {
    local required_gb=${1:-20}
    local available_gb
    available_gb=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    
    if [[ $available_gb -lt $required_gb ]]; then
        log_error "磁盘空间不足。需要 ${required_gb}GB，可用 ${available_gb}GB"
        return 1
    else
        log_success "磁盘空间充足: ${available_gb}GB 可用"
        return 0
    fi
}

# ========== APT 包管理 ==========
setup_apt() {
    log_step "设置 APT 包管理器..."
    
    # 设置非交互模式
    export DEBIAN_FRONTEND=noninteractive
    
    # 清理APT锁
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/cache/apt/archives/lock
    rm -rf /var/lib/apt/lists/*
    
    # 更新包列表
    apt-get update
    log_success "APT 设置完成"
}

install_packages() {
    local packages=("$@")
    log_step "安装包: ${packages[*]}"
    
    apt-get install -y --no-install-recommends "${packages[@]}"
    log_success "包安装完成"
}

# ========== 网络检查 ==========
check_internet() {
    log_step "检查网络连接..."
    if curl -sSf https://www.google.com > /dev/null 2>&1; then
        log_success "网络连接正常"
        return 0
    else
        log_error "网络连接失败"
        return 1
    fi
}

wait_for_service() {
    local service_name=$1
    local host=${2:-localhost}
    local port=$3
    local max_attempts=${4:-30}
    local wait_seconds=${5:-10}
    
    log_step "等待 $service_name 启动..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f "http://$host:$port/health" > /dev/null 2>&1 || \
           nc -z "$host" "$port" > /dev/null 2>&1; then
            log_success "$service_name 已就绪"
            return 0
        fi
        
        log_info "等待 $service_name 启动... ($((attempt+1))/$max_attempts)"
        sleep "$wait_seconds"
        attempt=$((attempt+1))
    done
    
    log_error "$service_name 启动超时"
    return 1
}

# ========== 文件操作 ==========
backup_file() {
    local file_path=$1
    if [[ -f "$file_path" ]]; then
        local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file_path" "$backup_path"
        log_info "已备份: $file_path -> $backup_path"
    fi
}

create_safe_symlink() {
    local source=$1
    local target=$2
    
    # 如果目标已存在且不是符号链接，先备份
    if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
        backup_file "$target"
        rm -rf "$target"
    fi
    
    # 创建符号链接
    ln -sfn "$source" "$target"
    log_success "创建符号链接: $source -> $target"
}

# ========== 用户交互 ==========
ask_yes_no() {
    local question=$1
    local default=${2:-"N"}
    
    if [[ "${AUTO_INSTALL:-false}" == "true" ]]; then
        log_info "$question (自动模式: $default)"
        [[ "$default" =~ ^[Yy]$ ]]
        return $?
    fi
    
    local prompt
    if [[ "$default" =~ ^[Yy]$ ]]; then
        prompt="$question (Y/n): "
    else
        prompt="$question (y/N): "
    fi
    
    while true; do
        read -p "$prompt" -n 1 -r
        echo
        
        if [[ -z "$REPLY" ]]; then
            [[ "$default" =~ ^[Yy]$ ]]
            return $?
        elif [[ "$REPLY" =~ ^[Yy]$ ]]; then
            return 0
        elif [[ "$REPLY" =~ ^[Nn]$ ]]; then
            return 1
        else
            echo "请输入 y 或 n"
        fi
    done
}

# ========== 进程管理 ==========
kill_process_by_pattern() {
    local pattern=$1
    local signal=${2:-TERM}
    
    if pgrep -f "$pattern" > /dev/null; then
        log_info "终止进程: $pattern"
        pkill -$signal -f "$pattern" || true
        sleep 2
        
        # 如果还有进程，强制终止
        if pgrep -f "$pattern" > /dev/null; then
            log_warning "强制终止进程: $pattern"
            pkill -KILL -f "$pattern" || true
        fi
    fi
}

# ========== 配置文件生成 ==========
generate_script() {
    local script_path=$1
    local script_content=$2
    
    cat > "$script_path" << EOF
$script_content
EOF
    chmod +x "$script_path"
    log_success "生成脚本: $script_path"
}

# ========== 环境变量处理 ==========
load_env_file() {
    local env_file=${1:-".env"}
    
    if [[ -f "$env_file" ]]; then
        log_info "加载环境变量: $env_file"
        # 安全地加载环境变量
        set -a
        # shellcheck source=/dev/null
        source "$env_file"
        set +a
        log_success "环境变量加载完成"
    else
        log_warning "环境变量文件不存在: $env_file"
    fi
}

export_env_vars() {
    local vars=("$@")
    local var
    for var in "${vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            export "$var"
            log_info "导出环境变量: $var"
        fi
    done
}

# ========== 版本检查 ==========
check_command_version() {
    local command=$1
    # min_version parameter is available but not used in current implementation
    # local min_version=${2:-""}
    
    if command -v "$command" > /dev/null 2>&1; then
        local version
        version=$($command --version 2>&1 | head -n 1)
        log_success "$command 可用: $version"
        return 0
    else
        log_error "$command 未找到"
        return 1
    fi
}

# ========== 目录管理 ==========
ensure_directory() {
    local dir_path=$1
    local owner=${2:-""}
    local permissions=${3:-"755"}
    
    mkdir -p "$dir_path"
    
    if [[ -n "$owner" ]]; then
        chown "$owner" "$dir_path"
    fi
    
    chmod "$permissions" "$dir_path"
    log_success "确保目录存在: $dir_path"
}

# ========== 模块加载检查 ==========
log_info "工具函数模块 (utils.sh) 已加载"

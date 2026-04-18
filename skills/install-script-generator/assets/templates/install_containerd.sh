#!/bin/bash

#############################################
# containerd 自动安装脚本 v1.0
# 功能：自动下载并安装 containerd 和 runc
# 支持多种 containerd 版本和架构
# 支持内网/外网环境自动检测
#############################################

set -e  # 遇到错误立即退出
set -o pipefail

# ==================== 默认配置 ====================

# containerd 版本
CONTAINERD_VERSION=""

# 系统架构 (x64, arm64)
ARCH=""

# containerd 下载 URL（优先级最高）
CONTAINERD_FILE_URL=""

# runc 下载 URL（优先级最高）
RUNC_FILE_URL=""

# 安装目录
INSTALL_DIR="/usr/local"

# 下载目录
DOWNLOAD_DIR="/tmp"

# 是否删除安装包（默认删除）
DELETE_PACKAGE=true

# 是否启用 K8s 配置（默认不启用）
ENABLE_K8S_CONFIG=false

# 是否跳过 DockerHub 镜像源配置（默认不跳过）
SKIP_DOCKERHUB_MIRROR=false

# 调试模式
DEBUG=false

# 网络类型（内网/外网）
NETWORK_TYPE=""

# ==================== 颜色输出 ====================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# ==================== sudo 兼容 ====================

SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO_CMD=(sudo -n)
    else
        log_error "未找到 sudo，且当前用户不是 root。请以 root 运行，或安装/配置 sudo。"
        exit 1
    fi
fi

run_root() {
    if [ "${#SUDO_CMD[@]}" -gt 0 ]; then
        "${SUDO_CMD[@]}" "$@"
    else
        "$@"
    fi
}

run_with_fallback() {
    "$@" 2>/dev/null || run_root "$@"
}

ensure_dir() {
    local dir="$1"
    local desc="$2"
    if [ ! -d "$dir" ]; then
        log_info "创建${desc}: ${dir}"
        mkdir -p "$dir" 2>/dev/null || run_root mkdir -p "$dir"
    fi
}

# ==================== 帮助信息 ====================

usage() {
    cat <<EOF
用法: $0 [选项]

containerd 自动安装脚本 - 支持多种 containerd 版本和架构

选项:
  -v, --version <版本>      containerd 版本 (例如: 1.6, 1.7, 2.0, 2.1, 2.2)
  -a, --arch <架构>         系统架构 (x64, arm64) [默认: 自动检测]
  -n, --network <网络>      网络类型 (in, out) [默认: 自动检测]
  -u, --url <URL>           直接指定 containerd 下载 URL (优先级最高)
  --runc-url <URL>          直接指定 runc 下载 URL (优先级最高)
  -d, --dir <目录>          安装目录 [默认: /usr/local]
  --download-dir <目录>     下载目录 [默认: /tmp]
  --keep-package            保留安装包 (默认删除)
  --enable-k8s-config       启用 Kubernetes 配置 (默认不启用)
  --skip-dockerhub-mirror   跳过 DockerHub 镜像源配置 (默认不跳过)
  --debug                   启用调试模式
  -h, --help                显示此帮助信息

示例:
  # 安装 containerd 2.2 (自动检测架构)
  $0 -v 2.2

  # 安装 containerd 1.7 (arm64 架构)
  $0 -v 1.7 -a arm64

  # 指定内网环境安装 (跳过网络检测)
  $0 -v 2.2 -n in

  # 指定外网环境安装 (跳过网络检测)
  $0 -v 2.2 -n out

  # 使用自定义 URL 安装
  $0 -u https://github.com/containerd/containerd/releases/download/v2.2.2/containerd-2.2.2-linux-amd64.tar.gz

  # 使用自定义 URL 安装 containerd 和 runc
  $0 -u https://github.com/containerd/containerd/releases/download/v1.6.39/containerd-1.6.39-linux-amd64.tar.gz --runc-url https://github.com/opencontainers/runc/releases/download/v1.2.9/runc.amd64

  # 安装到指定目录并保留安装包
  $0 -v 2.2 -d /opt/containerd --keep-package

  # 安装并启用 Kubernetes 配置（用于 K8s 集群）
  $0 -v 1.7 --enable-k8s-config

  # 安装并跳过 DockerHub 镜像源配置
  $0 -v 1.7 --skip-dockerhub-mirror

支持的版本:
  - 1.6     containerd v1.6.x (稳定版 - 维护到 2027-03)
  - 1.7     containerd v1.7.x (LTS - 维护到 2025-10)
  - 2.0     containerd v2.0.x (稳定版)
  - 2.1     containerd v2.1.x (稳定版)
  - 2.2     containerd v2.2.x (Current - 当前版本)

支持的架构:
  - x64             Intel/AMD 64位
  - arm64/aarch64   ARM 64位

注意:
  1. 如果指定 --url，则 --arch、--version 参数将被忽略
  2. 如果指定 --runc-url，则 runc 将从指定 URL 下载
  3. 如果不指定 --arch，脚本会自动检测系统架构
  4. 如果不指定 --network，脚本会自动检测内网/外网环境
  5. 需要写入系统路径时会自动使用 sudo（建议用有 sudo 权限的用户运行）
  6. 未指定 --runc-url 时，runc 版本会根据 containerd 版本自动选择
  7. --enable-k8s-config 会配置 Kubernetes 所需的 settings (sandbox_image, config_path, SystemdCgroup)
  8. --skip-dockerhub-mirror 会跳过 DockerHub 国内镜像源配置

EOF
    exit 0
}

# ==================== 参数解析 ====================

parse_args() {
    local parsed_options

    parsed_options=$(getopt \
        -o v:a:n:u:d:h \
        --long version:,arch:,network:,url:,runc-url:,dir:,download-dir:,keep-package,enable-k8s-config,skip-dockerhub-mirror,debug,help \
        -- "$@")

    if [ $? -ne 0 ]; then
        log_error "参数解析失败，请使用 --help 查看用法"
        exit 1
    fi

    eval set -- "$parsed_options"

    while true; do
        case "$1" in
            -v|--version)
                CONTAINERD_VERSION="$2"
                shift 2
                ;;
            -a|--arch)
                ARCH="$2"
                shift 2
                ;;
            -n|--network)
                NETWORK_TYPE="$2"
                shift 2
                ;;
            -u|--url)
                CONTAINERD_FILE_URL="$2"
                shift 2
                ;;
            --runc-url)
                RUNC_FILE_URL="$2"
                shift 2
                ;;
            -d|--dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --download-dir)
                DOWNLOAD_DIR="$2"
                shift 2
                ;;
            --keep-package)
                DELETE_PACKAGE=false
                shift
                ;;
            --enable-k8s-config)
                ENABLE_K8S_CONFIG=true
                shift
                ;;
            --skip-dockerhub-mirror)
                SKIP_DOCKERHUB_MIRROR=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    # 验证必需参数
    if [ -z "$CONTAINERD_FILE_URL" ] && [ -z "$CONTAINERD_VERSION" ]; then
        log_error "必须指定 containerd 版本 (-v/--version) 或下载 URL (-u/--url)"
        log_info "使用 --help 查看详细用法"
        exit 1
    fi

    # 验证网络类型（如果指定）
    if [ -n "$NETWORK_TYPE" ]; then
        case "$NETWORK_TYPE" in
            in|out)
                log_debug "使用指定的网络类型: $NETWORK_TYPE"
                ;;
            *)
                log_error "不支持的网络类型: $NETWORK_TYPE"
                log_info "支持的网络类型: in (内网), out (外网)"
                exit 1
                ;;
        esac
    fi

    log_debug "参数解析完成:"
    log_debug "  CONTAINERD_VERSION: ${CONTAINERD_VERSION:-未指定}"
    log_debug "  ARCH: ${ARCH:-自动检测}"
    log_debug "  NETWORK_TYPE: ${NETWORK_TYPE:-自动检测}"
    log_debug "  CONTAINERD_FILE_URL: ${CONTAINERD_FILE_URL:-自动构建}"
    log_debug "  RUNC_FILE_URL: ${RUNC_FILE_URL:-自动构建}"
    log_debug "  INSTALL_DIR: $INSTALL_DIR"
    log_debug "  DOWNLOAD_DIR: $DOWNLOAD_DIR"
    log_debug "  DELETE_PACKAGE: $DELETE_PACKAGE"
    log_debug "  ENABLE_K8S_CONFIG: $ENABLE_K8S_CONFIG"
    log_debug "  SKIP_DOCKERHUB_MIRROR: $SKIP_DOCKERHUB_MIRROR"
}

# ==================== 架构检测 ====================

detect_arch() {
    # 如果用户已经通过参数指定了架构,验证并使用
    if [ -n "$ARCH" ]; then
        # 统一架构名称
        case "$ARCH" in
            x64|x86_64|amd64)
                ARCH="amd64"
                log_debug "统一架构名称: $ARCH -> amd64"
                ;;
            arm64|aarch64)
                ARCH="arm64"
                log_debug "统一架构名称: $ARCH -> arm64"
                ;;
            *)
                log_warn "警告: 不常见的架构 '$ARCH'"
                log_warn "支持的架构: amd64, arm64"
                log_warn "将尝试继续,可能失败"
                ;;
        esac
        log_debug "使用指定的架构: $ARCH"
        return
    fi

    # 自动检测系统架构
    local sys_arch
    log_info "正在检测系统架构..."
    sys_arch=$(uname -m 2>/dev/null)

    # 检测失败时的容错处理
    if [ $? -ne 0 ] || [ -z "$sys_arch" ]; then
        log_warn "警告: 无法自动检测系统架构 (uname -m 命令失败)"
        log_info "将使用默认架构: amd64"
        ARCH="amd64"
        return
    fi

    log_debug "检测到系统架构: $sys_arch"

    # 根据检测到的架构设置 ARCH 变量
    case "$sys_arch" in
        x86_64|amd64)
            ARCH="amd64"
            log_info "检测到系统架构: $ARCH (Intel/AMD 64位)"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            log_info "检测到系统架构: $ARCH (ARM 64位)"
            ;;
        i686|i386)
            log_warn "警告: 检测到 32 位系统 ($sys_arch)"
            log_warn "containerd 不提供 32 位版本的预编译包"
            log_warn "将使用默认架构: amd64 (可能失败)"
            ARCH="amd64"
            ;;
        *)
            log_warn "警告: 不支持的系统架构: $sys_arch"
            log_warn "支持的架构: amd64, arm64"
            log_warn "将使用默认架构: amd64 (可能失败)"
            ARCH="amd64"
            ;;
    esac
}

# ==================== 网络检测 ====================

detect_network() {
    # 如果用户已经指定了网络类型，直接使用
    if [ -n "$NETWORK_TYPE" ]; then
        if [ "$NETWORK_TYPE" = "in" ]; then
            log_info "使用指定的网络类型: 内网 (in)"
        else
            log_info "使用指定的网络类型: 外网 (out)"
        fi
        log_debug "跳过网络自动检测"
        return
    fi

    log_info "正在检测网络环境..."

    # 方法 1: 检查 DNS 配置
    if [ -f /etc/resolv.conf ]; then
        local dns_server
        dns_server=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1)
        if [[ "$dns_server" == *"192.168.0.180"* ]]; then
            NETWORK_TYPE="in"
            log_info "检测到内网环境 (DNS: $dns_server)"
            return
        fi
    fi

    # 方法 2: 测试内网网关连通性
    if ping -c 1 192.168.0.1 &>/dev/null 2>&1; then
        NETWORK_TYPE="in"
        log_info "检测到内网环境 (网关可达)"
        return
    fi

    # 方法 3: 检查环境变量
    if [ -n "$INTRANET_MIRROR" ]; then
        NETWORK_TYPE="in"
        log_info "检测到内网环境 (环境变量: $INTRANET_MIRROR)"
        return
    fi

    # 方法 4: 尝试连接内网镜像
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 http://mirrors.lpx.com/test &>/dev/null 2>&1; then
            NETWORK_TYPE="in"
            log_info "检测到内网环境 (镜像可达)"
            return
        fi
    fi

    # 方法 5: 简单检测
    if ip addr show 2>/dev/null | grep -q "192.168.0."; then
        NETWORK_TYPE="in"
        log_warn "检测到内网环境 (简单检测)"
    else
        NETWORK_TYPE="out"
        log_info "检测到外网环境"
    fi

    log_debug "网络类型: $NETWORK_TYPE"
}

# ==================== URL 构建 ====================

build_urls() {
    # 处理 runc URL（如果已指定）
    if [ -n "$RUNC_FILE_URL" ]; then
        log_info "使用指定的 runc 下载 URL: $RUNC_FILE_URL"
    fi

    # 如果已经指定了 containerd URL,直接使用(优先级最高,不检测架构)
    if [ -n "$CONTAINERD_FILE_URL" ]; then
        log_info "使用指定的 containerd 下载 URL: $CONTAINERD_FILE_URL"

        # 如果没有指定 runc URL，尝试从 containerd URL 提取版本号来构建 runc URL
        if [ -z "$RUNC_FILE_URL" ]; then
            # 从 URL 提取版本号
            local extracted_version=$(echo "$CONTAINERD_FILE_URL" | grep -oP 'containerd-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [ -n "$extracted_version" ]; then
                # 提取主版本号 (1.x 或 2.x)
                RUNC_VERSION=$(echo "$extracted_version" | grep -oP '^[0-9]+\.[0-9]+')
                get_runc_version "$RUNC_VERSION"
                # 检测架构用于构建 runc URL
                detect_arch
                # 构建 runc URL（根据网络类型）
                if [ "$NETWORK_TYPE" = "in" ]; then
                    RUNC_FILE_URL="http://192.168.0.180:8082/soft/runtime/runc/v${FULL_RUNC_VERSION}/runc.${ARCH}"
                else
                    RUNC_FILE_URL="https://github.com/opencontainers/runc/releases/download/v${FULL_RUNC_VERSION}/runc.${ARCH}"
                fi
                log_info "根据 containerd 版本自动构建 runc URL: $RUNC_FILE_URL"
            else
                log_warn "无法从 containerd URL 提取版本号，runc URL 未构建"
            fi
        fi
        return
    fi

    # 只有在需要构建 URL 时才检测架构
    detect_arch

    log_info "根据版本和架构构建下载 URL..."

    # 内网镜像基础 URL
    local INTRANET_CONTAINERD_BASE="http://192.168.0.180:8082/soft/runtime/containerd"
    local INTRANET_RUNC_BASE="http://192.168.0.180:8082/soft/runtime/runc"

    # 外网镜像基础 URL
    local INTERNET_CONTAINERD_BASE="https://github.com/containerd/containerd/releases/download"
    local INTERNET_RUNC_BASE="https://github.com/opencontainers/runc/releases/download"

    # 根据网络类型选择基础 URL
    local CONTAINERD_MIRROR_BASE
    local RUNC_MIRROR_BASE
    [ "$NETWORK_TYPE" = "in" ] && CONTAINERD_MIRROR_BASE="$INTRANET_CONTAINERD_BASE" || CONTAINERD_MIRROR_BASE="$INTERNET_CONTAINERD_BASE"
    [ "$NETWORK_TYPE" = "in" ] && RUNC_MIRROR_BASE="$INTRANET_RUNC_BASE" || RUNC_MIRROR_BASE="$INTERNET_RUNC_BASE"

    # 根据版本构建具体版本号
    local FULL_CONTAINERD_VERSION=""
    case "$CONTAINERD_VERSION" in
        1.6)
            FULL_CONTAINERD_VERSION="1.6.39"
            RUNC_VERSION="1.6"
            get_runc_version "$RUNC_VERSION"
            ;;
        1.7)
            FULL_CONTAINERD_VERSION="1.7.24"
            RUNC_VERSION="1.7"
            get_runc_version "$RUNC_VERSION"
            ;;
        2.0)
            FULL_CONTAINERD_VERSION="2.0.7"
            RUNC_VERSION="2.0"
            get_runc_version "$RUNC_VERSION"
            ;;
        2.1)
            FULL_CONTAINERD_VERSION="2.1.6"
            RUNC_VERSION="1.3"
            get_runc_version "$RUNC_VERSION"
            ;;
        2.2)
            FULL_CONTAINERD_VERSION="2.2.2"
            RUNC_VERSION="1.4"
            get_runc_version "$RUNC_VERSION"
            ;;
        *)
            log_error "不支持的 containerd 版本: $CONTAINERD_VERSION"
            log_info "支持的版本: 1.6, 1.7, 2.0, 2.1, 2.2"
            exit 1
            ;;
    esac

    # 构建完整的下载 URL
    CONTAINERD_FILE_URL="${CONTAINERD_MIRROR_BASE}/v${FULL_CONTAINERD_VERSION}/containerd-${FULL_CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"

    # 如果没有指定 runc URL，则自动构建
    if [ -z "$RUNC_FILE_URL" ]; then
        RUNC_FILE_URL="${RUNC_MIRROR_BASE}/v${FULL_RUNC_VERSION}/runc.${ARCH}"
    fi

    log_info "构建的 containerd 下载 URL: $CONTAINERD_FILE_URL"
    log_info "构建的 runc 下载 URL: $RUNC_FILE_URL"
}

# ==================== 获取 runc 版本 ====================

get_runc_version() {
    case "$1" in
        1.6)
            FULL_RUNC_VERSION="1.2.9"
            ;;
        1.7)
            FULL_RUNC_VERSION="1.2.9"
            ;;
        2.0)
            FULL_RUNC_VERSION="1.2.9"
            ;;
        1.3)
            FULL_RUNC_VERSION="1.3.4"
            ;;
        1.4)
            FULL_RUNC_VERSION="1.4.0"
            ;;
        *)
            FULL_RUNC_VERSION="1.2.9"
            log_warn "警告: 未知的 runc 版本组,使用默认版本: $FULL_RUNC_VERSION"
            ;;
    esac
}

# ==================== K8s 配置 ====================

configure_k8s_settings() {
    log_info "========================================="
    log_info "配置 Kubernetes 所需设置"
    log_info "========================================="

    # 1. 修改 sandbox/sandbox_image 为阿里云镜像（兼容 1.x 和 2.0）
    log_info "修改 sandbox/sandbox_image 为阿里云镜像..."
    # containerd 1.x: sandbox_image = "registry.k8s.io/pause:3.9"（支持单引号和双引号）
    run_with_fallback sed -i "s#sandbox_image = [\"'].*[\"']#sandbox_image = \"registry.aliyuncs.com/google_containers/pause:3.9\"#g" /etc/containerd/config.toml
    # containerd 2.0: sandbox = "registry.k8s.io/pause:3.10"（支持单引号和双引号）
    # 直接匹配完整的 registry.k8s.io 地址，避免影响 sandboxer
    run_with_fallback sed -i "s#sandbox = [\"']registry\.k8s\.io/pause:.*[\"']#sandbox = \"registry.aliyuncs.com/google_containers/pause:3.10\"#g" /etc/containerd/config.toml

    # 2. 修改 config_path
    log_info "修改 config_path..."
    local NEW_PATH="/etc/containerd/certs.d"

# 兼容性不高，对awk版本有要求
#     awk -i inplace -v path="$NEW_PATH" '
# BEGIN { found = 0 }
# 
# /cri.*registry\]/ {
#     found = 1
# }
# 
# found && /^\[/ {
#     found = 0
# }
# 
# found && /config_path/ {
#     if (match($0, /config_path = ".*"/)) {
#         sub(/config_path = ".*"/, "config_path = \"" path "\"")
#     }
#     else {
#         sub(/config_path = .*/, "config_path = \"" path "\"")
#     }
#     found = 0
# }
# 
# { print }
# ' /etc/containerd/config.toml

awk -v path="$NEW_PATH" '
BEGIN { in_block=0 }

# 匹配 v1 registry（允许前导空格）
/^[[:space:]]*\[plugins\."io.containerd.grpc.v1.cri"\.registry\]/ {
    in_block=1
    print
    next
}

# 匹配 v2 registry（兼容单/双引号）
/^[[:space:]]*\[plugins\.(["'"'"'])io.containerd.cri.v1.images\1\.registry\]/ {
    in_block=1
    print
    next
}

# 遇到新的 section 退出
/^[[:space:]]*\[/ {
    in_block=0
}

# 只改当前 block 的 config_path
in_block && /^[[:space:]]*config_path[[:space:]]*=/ {
    sub(/=.*/, "= \"" path "\"")
}

{ print }
' /etc/containerd/config.toml > /tmp/config.toml && \
run_with_fallback cp /tmp/config.toml /etc/containerd/config.toml




    # 3. 启用 SystemdCgroup（K8s 推荐）
    log_info "启用 SystemdCgroup..."
    run_with_fallback sed -i 's|SystemdCgroup = false|SystemdCgroup = true|g' /etc/containerd/config.toml

    # 4. 验证修改
    log_info "验证 K8s 配置修改..."
    grep -E "sandbox|sandbox_image|SystemdCgroup|config_path" /etc/containerd/config.toml

    log_info "K8s 配置完成！"
}

# ==================== DockerHub 镜像源配置 ====================

configure_dockerhub_mirror() {
    log_info "========================================="
    log_info "配置 DockerHub 国内镜像源"
    log_info "========================================="

    if command -v curl &> /dev/null; then
        curl -sSL http://192.168.0.180:8082/scripts/runtime/docker/dockerhub_mirrors/get_available_mirror.sh | bash
        log_info "DockerHub 镜像源配置完成！"
    else
        log_warn "系统未安装 curl，跳过 DockerHub 镜像源配置"
    fi
}

# ==================== 主逻辑 ====================

main() {
    # 解析参数
    parse_args "$@"

    # 检测网络环境
    detect_network

    # 构建 containerd 和 runc 下载 URL (内部会检测架构)
    build_urls

    # 从 URL 提取文件名
    local CONTAINERD_FILE=$(basename "$CONTAINERD_FILE_URL")
    local RUNC_FILE=$(basename "$RUNC_FILE_URL")

    # 安装路径配置
    local CONTAINERD_INSTALL_PATH="${INSTALL_DIR}/containerd-${CONTAINERD_VERSION:-custom}"

    log_info "========================================="
    log_info "开始安装 containerd 和 runc"
    log_info "========================================="
    log_info "containerd 版本:  ${CONTAINERD_VERSION:-自定义}"
    log_info "runc 版本:        ${FULL_RUNC_VERSION:-自动}"
    log_info "系统架构:         ${ARCH}"
    log_info "网络类型:         ${NETWORK_TYPE}"
    log_info "containerd 地址:  ${CONTAINERD_FILE_URL}"
    log_info "runc 地址:        ${RUNC_FILE_URL}"
    log_info "安装路径:         ${CONTAINERD_INSTALL_PATH}"
    log_info "下载目录:         ${DOWNLOAD_DIR}"
    log_info "删除安装包:       ${DELETE_PACKAGE}"
    log_info "========================================="

    # 1. 如果安装目录不存在就创建
    if [ ! -d "$INSTALL_DIR" ]; then
        ensure_dir "$INSTALL_DIR" "目录"
    fi

    # 2. 如果下载目录不存在就创建
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        ensure_dir "$DOWNLOAD_DIR" "目录"
    fi

    # 3. 判断 containerd 软件安装目录是否存在
    if [ -d "$CONTAINERD_INSTALL_PATH" ]; then
        log_warn "containerd 安装目录 ${CONTAINERD_INSTALL_PATH} 已存在，跳过安装"
        DIR_EXISTS=true
    else
        DIR_EXISTS=false
    fi

    # 4. 判断安装包是否存在
    if [ -f "${DOWNLOAD_DIR}/${CONTAINERD_FILE}" ]; then
        log_info "containerd 安装包 ${CONTAINERD_FILE} 已存在"
        ZIP_SOFT_EXISTS=true
    else
        ZIP_SOFT_EXISTS=false
    fi

    # 5. 如果软件未安装且安装包不存在，则下载
    if [ "$DIR_EXISTS" = false ] && [ "$ZIP_SOFT_EXISTS" = false ]; then
        log_info "开始下载 containerd..."

        # 使用 wget 或 curl 下载
        if command -v wget &> /dev/null; then
            wget -O "${DOWNLOAD_DIR}/${CONTAINERD_FILE}" "$CONTAINERD_FILE_URL" || {
                log_error "containerd 下载失败"
                exit 1
            }
        elif command -v curl &> /dev/null; then
            curl -L -o "${DOWNLOAD_DIR}/${CONTAINERD_FILE}" "$CONTAINERD_FILE_URL" || {
                log_error "containerd 下载失败"
                exit 1
            }
        else
            log_error "系统未安装 wget 或 curl，无法下载"
            exit 1
        fi

        log_info "containerd 下载完成"
    fi

    # 6. 判断是否需要下载 runc
    NEED_DOWNLOAD_RUNC=false
    if [ ! -f "${DOWNLOAD_DIR}/${RUNC_FILE}" ]; then
        # 如果本地下载包不存在，需要下载
        if [ ! -f "/usr/local/sbin/runc" ]; then
            # runc 未安装，必须下载
            NEED_DOWNLOAD_RUNC=true
        else
            # runc 已安装，检查是否需要更新
            # 通过比较版本或简单跳过下载
            log_info "runc 已安装，跳过下载"
        fi
    else
        log_info "runc 安装包 ${RUNC_FILE} 已存在"
    fi

    if [ "$NEED_DOWNLOAD_RUNC" = true ]; then
        log_info "开始下载 runc..."

        if command -v wget &> /dev/null; then
            wget -O "${DOWNLOAD_DIR}/${RUNC_FILE}" "$RUNC_FILE_URL" || {
                log_error "runc 下载失败"
                exit 1
            }
        elif command -v curl &> /dev/null; then
            curl -L -o "${DOWNLOAD_DIR}/${RUNC_FILE}" "$RUNC_FILE_URL" || {
                log_error "runc 下载失败"
                exit 1
            }
        fi

        log_info "runc 下载完成"
    fi

    # 7. 如果 containerd 未安装,创建安装路径并解压
    if [ "$DIR_EXISTS" = false ]; then
        log_info "创建 containerd 安装路径: ${CONTAINERD_INSTALL_PATH}"
        run_with_fallback mkdir -p "$CONTAINERD_INSTALL_PATH"

        log_info "解压 containerd 到 ${CONTAINERD_INSTALL_PATH}"
        # containerd 的包解压后直接包含 bin 等目录，不需要 --strip-components
        run_with_fallback tar -xzf "${DOWNLOAD_DIR}/${CONTAINERD_FILE}" -C "$CONTAINERD_INSTALL_PATH" || {
            log_error "containerd 解压失败"
            exit 1
        }

        log_info "containerd 解压完成"
    fi

    # 8. 创建软连接 /usr/local/containerd -> /usr/local/containerd-{version}
    if [ -L "${INSTALL_DIR}/containerd" ] || [ -e "${INSTALL_DIR}/containerd" ]; then
        log_warn "软连接 ${INSTALL_DIR}/containerd 已存在，将更新"
        run_with_fallback rm -f "${INSTALL_DIR}/containerd"
    fi
    log_info "创建软连接: ${INSTALL_DIR}/containerd -> ${CONTAINERD_INSTALL_PATH}"
    run_with_fallback ln -s "$CONTAINERD_INSTALL_PATH" "${INSTALL_DIR}/containerd"

    # 9. 安装 runc 到 /usr/local/sbin
    # 只有当 runc 文件存在时才安装
    if [ -f "${DOWNLOAD_DIR}/${RUNC_FILE}" ]; then
        log_info "安装 runc 到 /usr/local/sbin"
        if [ -f "/usr/local/sbin/runc" ]; then
            log_warn "/usr/local/sbin/runc 已存在，将更新"
            run_with_fallback rm -f /usr/local/sbin/runc
        fi
        run_with_fallback install -m 755 "${DOWNLOAD_DIR}/${RUNC_FILE}" /usr/local/sbin/runc || {
            log_error "runc 安装失败"
            exit 1
        }
    else
        log_info "runc 安装包不存在，跳过安装（runc 可能已安装）"
    fi

    # 10. 创建 containerd 二进制文件软连接到 /usr/local/bin
    log_info "创建 containerd 二进制文件软连接"
    for cmd in containerd containerd-shim containerd-shim-runc-v2 containerd-stress ctr; do
        if [ -f "${CONTAINERD_INSTALL_PATH}/bin/${cmd}" ]; then
            if [ -L "/usr/local/bin/${cmd}" ] || [ -e "/usr/local/bin/${cmd}" ]; then
                log_warn "/usr/local/bin/${cmd} 已存在，将更新"
                run_with_fallback rm -f "/usr/local/bin/${cmd}"
            fi
            run_with_fallback ln -s "${CONTAINERD_INSTALL_PATH}/bin/${cmd}" "/usr/local/bin/${cmd}"
            log_debug "创建软连接: /usr/local/bin/${cmd} -> ${CONTAINERD_INSTALL_PATH}/bin/${cmd}"
        fi
    done

    # 11. 生成默认配置文件
    CONFIG_DIR="/etc/containerd"
    CONFIG_FILE="${CONFIG_DIR}/config.toml"

    if [ ! -d "$CONFIG_DIR" ]; then
        log_info "创建 containerd 配置目录: ${CONFIG_DIR}"
        run_with_fallback mkdir -p "$CONFIG_DIR"
    fi

    # 如果配置文件已存在，先备份
    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "备份现有配置: ${BACKUP_FILE}"
        run_with_fallback cp "$CONFIG_FILE" "$BACKUP_FILE"
    fi

    # 每次都重新生成配置
    log_info "生成 containerd 默认配置: ${CONFIG_FILE}"
    "${CONTAINERD_INSTALL_PATH}/bin/containerd" config default 2>/dev/null | run_with_fallback tee "$CONFIG_FILE" >/dev/null || {
        log_error "生成默认配置失败"
        exit 1
    }

    # 12. 创建 systemd 服务文件
    SERVICE_FILE="/etc/systemd/system/containerd.service"

    # 如果服务文件已存在，先备份
    if [ -f "$SERVICE_FILE" ]; then
        BACKUP_FILE="${SERVICE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "备份现有服务文件: ${BACKUP_FILE}"
        run_with_fallback cp "$SERVICE_FILE" "$BACKUP_FILE"
    fi

    # 每次都重新生成服务文件
    log_info "生成 systemd 服务文件: ${SERVICE_FILE}"
    cat <<EOF | run_with_fallback tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target dbus.service

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=${CONTAINERD_INSTALL_PATH}/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# LimitNOFILE=1048576

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

    run_with_fallback systemctl daemon-reload
    log_info "systemd 服务文件生成完成"

    # 13. 配置 K8s 设置（如果启用）
    if [ "$ENABLE_K8S_CONFIG" = true ]; then
        configure_k8s_settings
    fi

    # 14. 配置 DockerHub 镜像源（如果不跳过）
    if [ "$SKIP_DOCKERHUB_MIRROR" = false ]; then
        configure_dockerhub_mirror
    fi

    # 15. 删除安装包
    if [ "$DELETE_PACKAGE" = true ]; then
        log_info "删除安装包: ${DOWNLOAD_DIR}/${CONTAINERD_FILE}"
        run_with_fallback rm -f "${DOWNLOAD_DIR}/${CONTAINERD_FILE}"
        log_info "删除安装包: ${DOWNLOAD_DIR}/${RUNC_FILE}"
        run_with_fallback rm -f "${DOWNLOAD_DIR}/${RUNC_FILE}"
    else
        log_info "保留安装包: ${DOWNLOAD_DIR}/${CONTAINERD_FILE}"
        log_info "保留安装包: ${DOWNLOAD_DIR}/${RUNC_FILE}"
    fi

    # 16. 显示安装信息
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="

    cat <<EOF
安装信息:
----------------------------------------
containerd 版本:  ${CONTAINERD_VERSION:-自定义}
runc 版本:        ${FULL_RUNC_VERSION:-自动}
系统架构:         ${ARCH}
网络类型:         ${NETWORK_TYPE}
containerd 地址:  ${CONTAINERD_FILE_URL}
runc 地址:        ${RUNC_FILE_URL}
安装路径:         ${CONTAINERD_INSTALL_PATH}
软连接:           ${INSTALL_DIR}/containerd
配置文件:         ${CONFIG_FILE}
服务文件:         ${SERVICE_FILE}
K8s 配置:         $([ "$ENABLE_K8S_CONFIG" = true ] && echo "已启用" || echo "未启用")
DockerHub 镜像:   $([ "$SKIP_DOCKERHUB_MIRROR" = false ] && echo "已配置" || echo "未配置")

使用方法:
  # 启动 containerd 服务
  systemctl enable --now containerd

  # 查看服务状态
  systemctl status containerd

  # 验证安装
  containerd --version
  runc --version
  ctr version

  # 查看 containerd 配置
  containerd config default

  # 使用 ctr 拉取镜像
  ctr images pull docker.io/library/nginx:alpine

  # 使用 ctr 运行容器
  ctr run docker.io/library/nginx:alpine test

注意:
  1. systemd cgroup 驱动已在配置中默认启用
  2. 如需用于 Kubernetes，请确保 SystemdCgroup = true
  3. 如需修改配置，请编辑 ${CONFIG_FILE}
  4. 修改配置后需要重启服务: systemctl restart containerd
  5. 检查配置： grep -E "sandbox_image|SystemdCgroup|config_path" /etc/containerd/config.toml
----------------------------------------
EOF
}

# 执行主函数
main "$@"

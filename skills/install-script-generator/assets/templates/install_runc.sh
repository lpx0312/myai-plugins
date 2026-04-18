#!/bin/bash

#############################################
# runc 自动安装脚本 v1.0
# 功能：自动下载并安装 runc
# 支持多种 runc 版本和架构
# 支持内网/外网环境自动检测
#############################################

set -e  # 遇到错误立即退出
set -o pipefail

# ==================== 默认配置 ====================

# runc 版本
RUNC_VERSION=""

# 系统架构 (x64, arm64)
ARCH=""

# runc 下载 URL（优先级最高）
RUNC_FILE_URL=""

# GitHub Token（用于访问 GitHub API）
GITHUB_TOKEN=""

# HTTP 代理
HTTP_PROXY=""

# 安装目录
INSTALL_DIR="/usr/local"

# 下载目录
DOWNLOAD_DIR="/tmp"

# 是否删除安装包（默认删除）
DELETE_PACKAGE=true

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

# ==================== 帮助信息 ====================

usage() {
    cat <<EOF
用法: $0 [选项]

runc 自动安装脚本 - 支持多种 runc 版本和架构

选项:
  -v, --version <版本>      runc 版本 (例如: 1.2.2, 1.1.13, 1.0.3)
  -a, --arch <架构>         系统架构 (x64, arm64) [默认: 自动检测]
  -n, --network <网络>      网络类型 (in, out) [默认: 自动检测]
  -u, --url <URL>           直接指定 runc 下载 URL (优先级最高)
  -t, --token <TOKEN>       GitHub Token (用于访问 GitHub API)
  -p, --proxy <PROXY>       HTTP 代理 (例如: http://192.168.0.4:7890)
  -d, --dir <目录>          安装目录 [默认: /usr/local]
  --download-dir <目录>     下载目录 [默认: /tmp]
  --keep-package            保留安装包 (默认删除)
  --debug                   启用调试模式
  -h, --help                显示此帮助信息

示例:
  # 安装 runc 1.2.2 (自动检测架构)
  $0 -v 1.2.2

  # 安装 runc 1.1.13 (arm64 架构)
  $0 -v 1.1.13 -a arm64

  # 指定内网环境安装 (跳过网络检测)
  $0 -v 1.2.2 -n in

  # 使用 GitHub Token 和代理安装
  $0 -v 1.2.2 -t ghp_xxx -p http://192.168.0.4:7890

  # 使用自定义 URL 安装
  $0 -u https://github.com/opencontainers/runc/releases/download/v1.2.2/runc.amd64

  # 安装到指定目录并保留安装包
  $0 -v 1.2.2 -d /opt/runc --keep-package

支持的版本系列:
  - 1.x      v1.0.0 ~ v1.2.2 (最新稳定版)

支持的架构:
  - x64             Intel/AMD 64位
  - arm64/aarch64   ARM 64位

注意:
  1. 如果指定 --url，则 --arch、--version 参数将被忽略
  2. 如果不指定 --arch，脚本会自动检测系统架构
  3. 如果不指定 --network，脚本会自动检测内网/外网环境
  4. 需要写入系统路径时会自动使用 sudo（建议用有 sudo 权限的用户运行）
  5. runc 是容器运行时组件，通常与 containerd 配合使用

EOF
    exit 0
}

# ==================== sudo 兼容 ====================

SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        # -n: 非交互模式，避免脚本卡住等待输入密码
        SUDO_CMD=(sudo -n)
    else
        log_error "未找到 sudo，且当前用户不是 root。请以 root 运行，或安装/配置 sudo。" >&2
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

# ==================== 参数解析 ====================

parse_args() {
    local parsed_options

    parsed_options=$(getopt \
        -o v:a:n:u:t:p:d:h \
        --long version:,arch:,network:,url:,token:,proxy:,dir:,download-dir:,keep-package,debug,help \
        -- "$@")

    if [ $? -ne 0 ]; then
        log_error "参数解析失败，请使用 --help 查看用法"
        exit 1
    fi

    eval set -- "$parsed_options"

    while true; do
        case "$1" in
            -v|--version)
                RUNC_VERSION="$2"
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
                RUNC_FILE_URL="$2"
                shift 2
                ;;
            -t|--token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            -p|--proxy)
                HTTP_PROXY="$2"
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
    if [ -z "$RUNC_FILE_URL" ] && [ -z "$RUNC_VERSION" ]; then
        log_error "必须指定 runc 版本 (-v/--version) 或下载 URL (-u/--url)"
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
    log_debug "  RUNC_VERSION: ${RUNC_VERSION:-未指定}"
    log_debug "  ARCH: ${ARCH:-自动检测}"
    log_debug "  NETWORK_TYPE: ${NETWORK_TYPE:-自动检测}"
    log_debug "  RUNC_FILE_URL: ${RUNC_FILE_URL:-自动构建}"
    log_debug "  GITHUB_TOKEN: ${GITHUB_TOKEN:+已设置}"
    log_debug "  HTTP_PROXY: ${HTTP_PROXY:-未设置}"
    log_debug "  INSTALL_DIR: $INSTALL_DIR"
    log_debug "  DOWNLOAD_DIR: $DOWNLOAD_DIR"
    log_debug "  DELETE_PACKAGE: $DELETE_PACKAGE"
}

# ==================== 架构检测 ====================

detect_arch() {
    # 如果用户已经通过参数指定了架构,验证并使用
    if [ -n "$ARCH" ]; then
        # 统一架构名称
        case "$ARCH" in
            x64|x86_64|amd64)
                ARCH="x64"
                log_debug "统一架构名称: $ARCH -> x64"
                ;;
            arm64|aarch64)
                ARCH="arm64"
                log_debug "统一架构名称: $ARCH -> arm64"
                ;;
            *)
                log_warn "警告: 不常见的架构 '$ARCH'"
                log_warn "支持的架构: x64, arm64"
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
        log_info "将使用默认架构: x64"
        ARCH="x64"
        return
    fi

    log_debug "检测到系统架构: $sys_arch"

    # 根据检测到的架构设置 ARCH 变量
    case "$sys_arch" in
        x86_64|amd64)
            ARCH="x64"
            log_info "检测到系统架构: $ARCH (Intel/AMD 64位)"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            log_info "检测到系统架构: $ARCH (ARM 64位)"
            ;;
        i686|i386)
            log_warn "警告: 检测到 32 位系统 ($sys_arch)"
            log_warn "runc 不提供 32 位版本的预编译包"
            log_warn "将使用默认架构: x64 (可能失败)"
            ARCH="x64"
            ;;
        *)
            log_warn "警告: 不支持的系统架构: $sys_arch"
            log_warn "支持的架构: x64, arm64"
            log_warn "将使用默认架构: x64 (可能失败)"
            ARCH="x64"
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

build_runc_url() {
    # 如果已经指定了 URL,直接使用(优先级最高,不检测架构)
    if [ -n "$RUNC_FILE_URL" ]; then
        log_info "使用指定的下载 URL: $RUNC_FILE_URL"
        return
    fi

    # 只有在需要构建 URL 时才检测架构
    detect_arch

    log_info "根据版本和架构构建下载 URL..."

    # 内网镜像基础 URL
    local INTRANET_BASE="http://192.168.0.180:8082/soft/runtime/runc"

    # 外网 GitHub 仓库
    local GITHUB_REPO="opencontainers/runc"

    # 构建文件名（runc 使用 runc.amd64 / runc.arm64 格式）
    local URL_ARCH
    [ "$ARCH" = "x64" ] && URL_ARCH="amd64" || URL_ARCH="arm64"
    local RUNC_FILE="runc.${URL_ARCH}"

    if [ "$NETWORK_TYPE" = "in" ]; then
        # 内网环境：直接构建 URL（版本号需要 v 前缀）
        RUNC_FILE_URL="${INTRANET_BASE}/v${RUNC_VERSION}/${RUNC_FILE}"
        log_info "使用内网镜像构建下载 URL"
    else
        # 外网环境：通过 GitHub API 获取下载链接
        log_info "正在从 GitHub API 获取下载链接..."

        local API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/v${RUNC_VERSION}"
        local curl_cmd="curl -s"

        # 添加代理
        if [ -n "$HTTP_PROXY" ]; then
            curl_cmd="$curl_cmd -x \"$HTTP_PROXY\""
            log_debug "使用代理: $HTTP_PROXY"
        fi

        # 添加 Token 认证
        if [ -n "$GITHUB_TOKEN" ]; then
            curl_cmd="$curl_cmd -H \"Authorization: token $GITHUB_TOKEN\""
            log_debug "使用 GitHub Token 认证"
        fi

        # 调用 GitHub API
        local api_response
        api_response=$(eval "$curl_cmd \"$API_URL\"") || {
            log_error "GitHub API 调用失败"
            log_info "如果遇到速率限制，请使用 --token 参数提供 GitHub Token"
            log_info "如果需要代理，请使用 --proxy 参数"
            exit 1
        }

        # 解析 API 响应获取浏览器下载 URL
        # 使用 sed 提取 JSON 中的 browser_download_url 字段
        RUNC_FILE_URL=$(echo "$api_response" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | grep "$RUNC_FILE" | head -1)

        if [ -z "$RUNC_FILE_URL" ]; then
            log_error "无法从 GitHub API 获取 runc ${RUNC_VERSION} (${URL_ARCH}) 的下载链接"
            log_info "请检查版本号和架构是否正确"
            log_info "访问 https://github.com/${GITHUB_REPO}/releases 查看可用版本"
            exit 1
        fi

        log_debug "GitHub API 响应成功"
    fi

    log_info "构建的下载 URL: $RUNC_FILE_URL"
}

# ==================== 主逻辑 ====================

main() {
    # 解析参数
    parse_args "$@"

    # 检测网络环境
    detect_network

    # 构建 runc 下载 URL (内部会检测架构)
    build_runc_url

    # 从 URL 提取文件名
    local RUNC_FILE=$(basename "$RUNC_FILE_URL")

    # 安装路径配置
    local RUNC_INSTALL_PATH="${INSTALL_DIR}/runc-${RUNC_VERSION:-custom}"

    log_info "========================================="
    log_info "开始安装 runc"
    log_info "========================================="
    log_info "runc 版本:      ${RUNC_VERSION:-自定义}"
    log_info "系统架构:       ${ARCH}"
    log_info "网络类型:       ${NETWORK_TYPE}"
    log_info "下载地址:       ${RUNC_FILE_URL}"
    log_info "安装路径:       ${RUNC_INSTALL_PATH}"
    log_info "下载目录:       ${DOWNLOAD_DIR}"
    log_info "删除安装包:     ${DELETE_PACKAGE}"
    log_info "========================================="

    # 1. 如果安装目录不存在就创建
    if [ ! -d "$INSTALL_DIR" ]; then
        ensure_dir "$INSTALL_DIR" "目录"
    fi

    # 2. 如果下载目录不存在就创建
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        ensure_dir "$DOWNLOAD_DIR" "目录"
    fi

    # 3. 判断软件安装目录是否存在
    if [ -d "$RUNC_INSTALL_PATH" ]; then
        log_warn "软件安装目录 ${RUNC_INSTALL_PATH} 已存在，跳过安装"
        DIR_EXISTS=true
    else
        DIR_EXISTS=false
    fi

    # 4. 判断安装包是否存在
    if [ -f "${DOWNLOAD_DIR}/${RUNC_FILE}" ]; then
        log_info "安装包 ${RUNC_FILE} 已存在"
        ZIP_SOFT_EXISTS=true
    else
        ZIP_SOFT_EXISTS=false
    fi

    # 5. 如果软件未安装且安装包不存在，则下载
    if [ "$DIR_EXISTS" = false ] && [ "$ZIP_SOFT_EXISTS" = false ]; then
        log_info "开始下载 ${RUNC_FILE_URL} 到 ${DOWNLOAD_DIR}"

        # 构建下载命令
        local download_cmd=""
        if command -v wget &> /dev/null; then
            download_cmd="wget -O \"${DOWNLOAD_DIR}/${RUNC_FILE}\" \"$RUNC_FILE_URL\""
            # 添加代理支持
            if [ -n "$HTTP_PROXY" ]; then
                download_cmd="export http_proxy=\"$HTTP_PROXY\" https_proxy=\"$HTTP_PROXY\"; $download_cmd"
            fi
        elif command -v curl &> /dev/null; then
            download_cmd="curl -L -o \"${DOWNLOAD_DIR}/${RUNC_FILE}\" \"$RUNC_FILE_URL\""
            # 添加代理支持
            if [ -n "$HTTP_PROXY" ]; then
                download_cmd="curl -L -x \"$HTTP_PROXY\" -o \"${DOWNLOAD_DIR}/${RUNC_FILE}\" \"$RUNC_FILE_URL\""
            fi
        else
            log_error "系统未安装 wget 或 curl，无法下载"
            exit 1
        fi

        # 执行下载
        eval "$download_cmd" || {
            log_error "下载失败"
            exit 1
        }

        log_info "下载完成"
    fi

    # 6. 如果软件未安装,创建安装路径并安装
    if [ "$DIR_EXISTS" = false ]; then
        log_info "创建软件安装路径: ${RUNC_INSTALL_PATH}"
        run_with_fallback mkdir -p "$RUNC_INSTALL_PATH"

        log_info "安装 runc 到 ${RUNC_INSTALL_PATH}"
        # runc 是单个二进制文件，直接复制
        run_with_fallback cp "${DOWNLOAD_DIR}/${RUNC_FILE}" "${RUNC_INSTALL_PATH}/runc" || {
            log_error "安装失败"
            exit 1
        }

        log_info "安装完成"
    fi

    # 7. 创建软连接 /usr/local/runc -> /usr/local/runc-{version}
    local RUNC_SYMLINK="${INSTALL_DIR}/runc"
    if [ -L "$RUNC_SYMLINK" ] || [ -e "$RUNC_SYMLINK" ]; then
        log_warn "软连接 ${RUNC_SYMLINK} 已存在，将更新"
        run_with_fallback rm -f "$RUNC_SYMLINK"
    fi
    log_info "创建软连接: ${RUNC_SYMLINK} -> ${RUNC_INSTALL_PATH}"
    run_with_fallback ln -s "$RUNC_INSTALL_PATH" "$RUNC_SYMLINK"

    # 8. 创建 runc 的软连接到 /usr/bin
    log_info "创建 runc 二进制文件软连接"
    if [ -L "/usr/bin/runc" ] || [ -e "/usr/bin/runc" ]; then
        log_warn "/usr/bin/runc 已存在，将更新"
        run_with_fallback rm -f "/usr/bin/runc"
    fi
    run_with_fallback ln -s "${RUNC_INSTALL_PATH}/runc" "/usr/bin/runc"
    log_debug "创建软连接: /usr/bin/runc -> ${RUNC_INSTALL_PATH}/runc"

    # 9. 设置执行权限
    log_info "设置执行权限"
    run_with_fallback chmod +x "${RUNC_INSTALL_PATH}/runc"
    run_with_fallback chmod +x "/usr/bin/runc"

    # 10. 验证安装
    log_info "验证安装..."
    if /usr/bin/runc --version &>/dev/null; then
        log_info "runc 安装成功！"
        /usr/bin/runc --version
    else
        log_warn "runc 安装完成，但验证失败。请检查安装路径"
    fi

    # 11. 删除安装包
    if [ "$DELETE_PACKAGE" = true ]; then
        log_info "删除安装包: ${DOWNLOAD_DIR}/${RUNC_FILE}"
        rm -f "${DOWNLOAD_DIR}/${RUNC_FILE}"
    else
        log_info "保留安装包: ${DOWNLOAD_DIR}/${RUNC_FILE}"
    fi

    # 12. 显示安装信息
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="

    cat <<EOF
安装信息:
----------------------------------------
runc 版本:      ${RUNC_VERSION:-自定义}
系统架构:       ${ARCH}
网络类型:       ${NETWORK_TYPE}
下载地址:       ${RUNC_FILE_URL}
安装路径:       ${RUNC_INSTALL_PATH}
软连接:         ${RUNC_SYMLINK}

使用方法:
  runc --version
  runc list

注意事项:
  1. runc 是 OCI 容器运行时实现
  2. 通常与 containerd 配合使用
  3. 配置文件位于: /etc/runc/runc.config (可选)
----------------------------------------
EOF
}

# 执行主函数
main "$@"

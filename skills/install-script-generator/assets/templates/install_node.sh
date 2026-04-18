#!/bin/bash

#############################################
# Node.js 自动安装脚本 v1.0
# 功能：自动下载并安装 Node.js
# 支持多种 Node.js 版本和架构
# 支持内网/外网环境自动检测
#############################################

set -e  # 遇到错误立即退出
set -o pipefail

# ==================== 默认配置 ====================

# Node.js 版本
NODE_VERSION=""

# 系统架构 (x64, arm64)
ARCH=""

# Node.js 下载 URL（优先级最高）
NODE_FILE_URL=""

# 安装目录
INSTALL_DIR="/usr/local"

# 下载目录
DOWNLOAD_DIR="/tmp"

# 是否删除安装包（默认删除）
DELETE_PACKAGE=true

# 调试模式
DEBUG=false
# HTTP 代理
HTTP_PROXY=""

# 网络类型（内网/外网）
NETWORK_TYPE=""

# 内网基础 URL
INTRANET_BASE_URL=""

# 外网基础 URL
INTERNET_BASE_URL=""

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

Node.js 自动安装脚本 - 支持多种 Node.js 版本和架构

选项:
  -v, --version <版本>      Node.js 版本 (例如: 10, 12, 14, 16, 18, 20, 22, 24)
  -a, --arch <架构>         系统架构 (x64, arm64) [默认: 自动检测]
  -n, --network <网络>      网络类型 (in, out) [默认: 自动检测]
  -u, --url <URL>           直接指定 Node.js 下载 URL (优先级最高)
  -i, --intranet-base <URL> 内网基础 URL
  -e, --internet-base <URL> 外网基础 URL
  -d, --dir <目录>          安装目录 [默认: /usr/local]
  -p, --proxy <PROXY>       HTTP 代理 (例如: http://192.168.0.4:7890)
  --download-dir <目录>     下载目录 [默认: /tmp]
  --keep-package            保留安装包 (默认删除)
  --debug                   启用调试模式
  -h, --help                显示此帮助信息

示例:
  # 安装 Node.js 20 (自动检测架构)
  $0 -v 20

  # 安装 Node.js 18 (arm64 架构)
  $0 -v 18 -a arm64

  # 指定内网环境安装 (跳过网络检测)
  $0 -v 20 -n in

  # 指定外网环境安装 (跳过网络检测)
  $0 -v 20 -n out

  # 使用自定义 URL 安装
  $0 -u https://nodejs.org/dist/v20.19.0/node-v20.19.0-linux-x64.tar.gz

  # 安装到指定目录并保留安装包
  $0 -v 20 -d /opt/nodejs --keep-package

支持的版本:
  - 10      Node.js v10.x (已停止维护)
  - 12      Node.js v12.x (已停止维护)
  - 14      Node.js v14.x (已停止维护)
  - 16      Node.js v16.x (已停止维护)
  - 18      Node.js v18.x (LTS - 维护到 2025-04)
  - 20      Node.js v20.x (LTS - 维护到 2026-04)
  - 22      Node.js v22.x (LTS - 维护到 2027-04)
  - 24      Node.js v24.x (Current - 当前版本)

支持的架构:
  - x64             Intel/AMD 64位
  - arm64/aarch64   ARM 64位

注意:
  1. 如果指定 --url，则 --arch、--version 参数将被忽略
  2. 如果不指定 --arch，脚本会自动检测系统架构
  3. 如果不指定 --network，脚本会自动检测内网/外网环境
  4. 需要写入系统路径时会自动使用 sudo（建议用有 sudo 权限的用户运行）

EOF
    exit 0
}

# ==================== 参数解析 ====================

parse_args() {
    local parsed_options

    parsed_options=$(getopt \
        -o v:a:n:u:d:i:e:h \
        --long version:,arch:,network:,url:,dir:,download-dir:,intranet-base:,internet-base:,keep-package,debug,help \
        -- "$@")

    if [ $? -ne 0 ]; then
        log_error "参数解析失败，请使用 --help 查看用法"
        exit 1
    fi

    eval set -- "$parsed_options"

    while true; do
        case "$1" in
            -v|--version)
                NODE_VERSION="$2"
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
                NODE_FILE_URL="$2"
                shift 2
                ;;
            -i|--intranet-base)
                INTRANET_BASE_URL="$2"
                shift 2
                ;;
            -e|--internet-base)
                INTERNET_BASE_URL="$2"
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
            -p|--proxy)
                HTTP_PROXY="$2"
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
    if [ -z "$NODE_FILE_URL" ] && [ -z "$NODE_VERSION" ]; then
        log_error "必须指定 Node.js 版本 (-v/--version) 或下载 URL (-u/--url)"
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
    log_debug "  NODE_VERSION: ${NODE_VERSION:-未指定}"
    log_debug "  ARCH: ${ARCH:-自动检测}"
    log_debug "  NETWORK_TYPE: ${NETWORK_TYPE:-自动检测}"
    log_debug "  NODE_FILE_URL: ${NODE_FILE_URL:-自动构建}"
    log_debug "  INSTALL_DIR: $INSTALL_DIR"
    log_debug "  DOWNLOAD_DIR: $DOWNLOAD_DIR"
    log_debug "  HTTP_PROXY: ${HTTP_PROXY:-未设置}"
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
            log_warn "Node.js 不提供 32 位版本的预编译包"
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

build_node_url() {
    # 如果已经指定了 URL,直接使用(优先级最高,不检测架构)
    if [ -n "$NODE_FILE_URL" ]; then
        log_info "使用指定的下载 URL: $NODE_FILE_URL"
        return
    fi

    # 只有在需要构建 URL 时才检测架构
    detect_arch

    log_info "根据版本和架构构建下载 URL..."

    # 内网镜像基础 URL
    local INTRANET_BASE="${INTRANET_BASE_URL:-http://192.168.0.180:8082/soft/node}"

    # 外网镜像基础 URL
    local INTERNET_BASE="${INTERNET_BASE_URL:-https://nodejs.org/dist}"

    # 根据网络类型选择基础 URL
    local MIRROR_BASE
    [ "$NETWORK_TYPE" = "in" ] && MIRROR_BASE="$INTRANET_BASE" || MIRROR_BASE="$INTERNET_BASE"

    # 根据版本构建具体版本号
    local FULL_VERSION=""
    case "$NODE_VERSION" in
        10)
            FULL_VERSION="10.24.1"
            ;;
        12)
            FULL_VERSION="12.22.12"
            ;;
        14)
            FULL_VERSION="14.21.3"
            ;;
        16)
            FULL_VERSION="16.20.2"
            ;;
        18)
            FULL_VERSION="18.20.5"
            ;;
        20)
            FULL_VERSION="20.18.1"
            ;;
        22)
            FULL_VERSION="22.12.0"
            ;;
        24)
            FULL_VERSION="24.14.0"
            ;;
        *)
            log_error "不支持的 Node.js 版本: $NODE_VERSION"
            log_info "支持的版本: 10, 12, 14, 16, 18, 20, 22, 24"
            exit 1
            ;;
    esac

    # 构建完整的下载 URL
    NODE_FILE_URL="${MIRROR_BASE}/v${FULL_VERSION}/node-v${FULL_VERSION}-linux-${ARCH}.tar.gz"

    log_info "构建的下载 URL: $NODE_FILE_URL"
}

# ==================== 主逻辑 ====================

main() {
    # 解析参数
    parse_args "$@"

    # 检测网络环境
    detect_network

    # 构建 Node.js 下载 URL (内部会检测架构)
    build_node_url

    # 从 URL 提取文件名
    local NODE_FILE=$(basename "$NODE_FILE_URL")

    # 安装路径配置
    local NODE_INSTALL_PATH="${INSTALL_DIR}/node-${NODE_VERSION:-custom}"
    local NODE_PATH="${INSTALL_DIR}/node"
    local NODE_HOME="${NODE_PATH}"

    log_info "========================================="
    log_info "开始安装 Node.js"
    log_info "========================================="
    log_info "Node.js 版本:  ${NODE_VERSION:-自定义}"
    log_info "系统架构:      ${ARCH}"
    log_info "网络类型:      ${NETWORK_TYPE}"
    log_info "下载地址:      ${NODE_FILE_URL}"
    log_info "安装路径:      ${NODE_INSTALL_PATH}"
    log_info "下载目录:      ${DOWNLOAD_DIR}"
    log_info "删除安装包:    ${DELETE_PACKAGE}"
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
    if [ -d "$NODE_INSTALL_PATH" ]; then
        log_warn "软件安装目录 ${NODE_INSTALL_PATH} 已存在，跳过安装"
        DIR_EXISTS=true
    else
        DIR_EXISTS=false
    fi

    # 4. 判断安装包是否存在
    if [ -f "${DOWNLOAD_DIR}/${NODE_FILE}" ]; then
        log_info "安装包 ${NODE_FILE} 已存在"
        ZIP_SOFT_EXISTS=true
    else
        ZIP_SOFT_EXISTS=false
    fi

    # 5. 如果软件未安装且安装包不存在，则下载
    if [ "$DIR_EXISTS" = false ] && [ "$ZIP_SOFT_EXISTS" = false ]; then
        log_info "开始下载 ${NODE_FILE_URL} 到 ${DOWNLOAD_DIR}"

        # 构建下载命令
        if command -v wget &> /dev/null; then
            local download_cmd="wget -O \"${DOWNLOAD_DIR}/${NODE_FILE}\" \"$NODE_FILE_URL\""
            if [ -n "$HTTP_PROXY" ]; then
                download_cmd="export http_proxy=\"$HTTP_PROXY\" https_proxy=\"$HTTP_PROXY\"; $download_cmd"
            fi
            eval "$download_cmd" || {
                log_error "下载失败"
                exit 1
            }
        elif command -v curl &> /dev/null; then
            if [ -n "$HTTP_PROXY" ]; then
                curl -L -x "$HTTP_PROXY" -o "${DOWNLOAD_DIR}/${NODE_FILE}" "$NODE_FILE_URL" || {
                    log_error "下载失败"
                    exit 1
                }
            else
                curl -L -o "${DOWNLOAD_DIR}/${NODE_FILE}" "$NODE_FILE_URL" || {
                    log_error "下载失败"
                    exit 1
                }
            fi
        else
            log_error "系统未安装 wget 或 curl，无法下载"
            exit 1
        fi

        log_info "下载完成"
    fi
    # 6. 如果软件未安装,创建安装路径并解压
    if [ "$DIR_EXISTS" = false ]; then
        log_info "创建软件安装路径: ${NODE_INSTALL_PATH}"
        run_with_fallback mkdir -p "$NODE_INSTALL_PATH"

        log_info "解压软件到 ${NODE_INSTALL_PATH}"
        # 解压并去除顶级目录（--strip-components=1）
        run_with_fallback tar -xzf "${DOWNLOAD_DIR}/${NODE_FILE}" -C "$NODE_INSTALL_PATH" --strip-components=1 || {
            log_error "解压失败"
            exit 1
        }

        log_info "解压完成"
    fi

    # 7. 创建软连接 /usr/local/node -> /usr/local/node-{version}
    if [ -L "$NODE_PATH" ] || [ -e "$NODE_PATH" ]; then
        log_warn "软连接 ${NODE_PATH} 已存在，将更新"
        run_with_fallback rm -f "$NODE_PATH"
    fi
    log_info "创建软连接: ${NODE_PATH} -> ${NODE_INSTALL_PATH}"
    run_with_fallback ln -s "$NODE_INSTALL_PATH" "$NODE_PATH"

    # 8. 创建 node 和 npm 的软连接到 /usr/bin
    log_info "创建 Node.js 二进制文件软连接"
    for cmd in node npm npx; do
        if [ -L "/usr/bin/${cmd}" ] || [ -e "/usr/bin/${cmd}" ]; then
            log_warn "/usr/bin/${cmd} 已存在，将更新"
            run_with_fallback rm -f "/usr/bin/${cmd}"
        fi
        run_with_fallback ln -s "${NODE_INSTALL_PATH}/bin/${cmd}" "/usr/bin/${cmd}"
        log_debug "创建软连接: /usr/bin/${cmd} -> ${NODE_INSTALL_PATH}/bin/${cmd}"
    done

    # 9. 设置 NODE_HOME 环境变量
    ENV_FILE="/etc/profile.d/node_home.sh"
    log_info "设置 NODE_HOME 环境变量到 ${ENV_FILE}"

    cat <<EOF | run_with_fallback tee "$ENV_FILE" >/dev/null
export NODE_HOME=${NODE_HOME}
export PATH=\$NODE_HOME/bin:\$PATH
EOF

    run_with_fallback chmod 644 "$ENV_FILE"
    log_info "环境变量配置完成"

    # 10. 验证安装
    log_info "验证安装..."
    if node --version 2>&1; then
        log_info "Node.js 安装成功！"
        if npm --version 2>&1; then
            log_info "npm 安装成功！"
        fi
    else
        log_warn "Node.js 安装完成，但验证失败。可能需要重新加载环境变量: source ${ENV_FILE}"
    fi

    # 11. 删除安装包
    if [ "$DELETE_PACKAGE" = true ]; then
        log_info "删除安装包: ${DOWNLOAD_DIR}/${NODE_FILE}"
        run_with_fallback rm -f "${DOWNLOAD_DIR}/${NODE_FILE}"
    else
        log_info "保留安装包: ${DOWNLOAD_DIR}/${NODE_FILE}"
    fi

    # 12. 显示安装信息
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="

    cat <<EOF
安装信息:
----------------------------------------
Node.js 版本:  ${NODE_VERSION:-自定义}
系统架构:      ${ARCH}
网络类型:      ${NETWORK_TYPE}
下载地址:      ${NODE_FILE_URL}
安装路径:      ${NODE_INSTALL_PATH}
软连接:        ${NODE_PATH}
NODE_HOME:     ${NODE_HOME}
环境变量文件:  ${ENV_FILE}

使用方法:
  source ${ENV_FILE}
  node --version
  npm --version
  npx --version

npm 常用命令:
  npm config set registry https://registry.npmmirror.com  # 设置淘宝镜像
  npm install -g <package>                                 # 全局安装包
  npm update -g                                            # 更新全局包
----------------------------------------
EOF
}

# 执行主函数
main "$@"

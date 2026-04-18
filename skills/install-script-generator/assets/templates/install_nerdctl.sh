#!/bin/bash

#############################################
# nerdctl 自动安装脚本 v1.0
# 功能：自动下载并安装 nerdctl
# 支持多种 nerdctl 版本和架构
# 支持内网/外网环境自动检测
#############################################

set -e  # 遇到错误立即退出
set -o pipefail

# ==================== 默认配置 ====================

# nerdctl 版本
NERDCTL_VERSION=""

# 系统架构 (x64, arm64)
ARCH=""

# nerdctl 下载 URL（优先级最高）
NERDCTL_FILE_URL=""

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
INTRANET_BASE=""

# 外网基础 URL
INTERNET_BASE=""

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

nerdctl 自动安装脚本 - 支持多种 nerdctl 版本和架构

选项:
  -v, --version <版本>      nerdctl 版本 (例如: 2.2.1, 2.0.0, 1.7.7)
  -a, --arch <架构>         系统架构 (x64, arm64) [默认: 自动检测]
  -n, --network <网络>      网络类型 (in, out) [默认: 自动检测]
  -i, --intranet-base <URL> 内网基础 URL
  -e, --internet-base <URL> 外网基础 URL
  -u, --url <URL>           直接指定 nerdctl 下载 URL (优先级最高)
  -d, --dir <目录>          安装目录 [默认: /usr/local]
  -p, --proxy <PROXY>       HTTP 代理 (例如: http://192.168.0.4:7890)
  --download-dir <目录>     下载目录 [默认: /tmp]
  --keep-package            保留安装包 (默认删除)
  --debug                   启用调试模式
  -h, --help                显示此帮助信息

示例:
  # 安装 nerdctl 2.2.1 (自动检测架构)
  $0 -v 2.2.1

  # 安装 nerdctl 2.0.0 (arm64 架构)
  $0 -v 2.0.0 -a arm64

  # 指定内网环境安装 (跳过网络检测)
  $0 -v 2.2.1 -n in

  # 指定外网环境安装 (跳过网络检测)
  $0 -v 2.2.1 -n out

  # 使用自定义 URL 安装
  $0 -u https://github.com/containerd/nerdctl/releases/download/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz

  # 安装到指定目录并保留安装包
  $0 -v 2.2.1 -d /opt/nerdctl --keep-package

支持的版本系列:
  - 2.x      v2.0.0 ~ v2.2.1 (最新稳定版)
  - 1.x      v1.0.0 ~ v1.7.7 (早期版本)
  - 0.x      v0.0.1 ~ v0.23.0 (实验版本)

支持的架构:
  - x64             Intel/AMD 64位
  - arm64/aarch64   ARM 64位

注意:
  1. 如果指定 --url，则 --arch、--version 参数将被忽略
  2. 如果不指定 --arch，脚本会自动检测系统架构
  3. 如果不指定 --network，脚本会自动检测内网/外网环境
  4. 需要写入系统路径时会自动使用 sudo（建议用有 sudo 权限的用户运行）
  5. nerdctl 需要 containerd 作为后端运行时

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
        -o v:a:n:i:e:u:d:h \
        --long version:,arch:,network:,intranet-base:,internet-base:,url:,dir:,download-dir:,keep-package,debug,help \
        -- "$@")

    if [ $? -ne 0 ]; then
        log_error "参数解析失败，请使用 --help 查看用法"
        exit 1
    fi

    eval set -- "$parsed_options"

    while true; do
        case "$1" in
            -v|--version)
                NERDCTL_VERSION="$2"
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
            -i|--intranet-base)
                INTRANET_BASE="$2"
                shift 2
                ;;
            -e|--internet-base)
                INTERNET_BASE="$2"
                shift 2
                ;;
            -u|--url)
                NERDCTL_FILE_URL="$2"
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
    if [ -z "$NERDCTL_FILE_URL" ] && [ -z "$NERDCTL_VERSION" ]; then
        log_error "必须指定 nerdctl 版本 (-v/--version) 或下载 URL (-u/--url)"
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
    log_debug "  NERDCTL_VERSION: ${NERDCTL_VERSION:-未指定}"
    log_debug "  ARCH: ${ARCH:-自动检测}"
    log_debug "  NETWORK_TYPE: ${NETWORK_TYPE:-自动检测}"
    log_debug "  NERDCTL_FILE_URL: ${NERDCTL_FILE_URL:-自动构建}"
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
            log_warn "nerdctl 不提供 32 位版本的预编译包"
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

build_nerdctl_url() {
    # 如果已经指定了 URL,直接使用(优先级最高,不检测架构)
    if [ -n "$NERDCTL_FILE_URL" ]; then
        log_info "使用指定的下载 URL: $NERDCTL_FILE_URL"
        return
    fi

    # 只有在需要构建 URL 时才检测架构
    detect_arch

    log_info "根据版本和架构构建下载 URL..."

    # 内网镜像基础 URL (使用参数值或默认值)
    local INTRANET_MIRROR_BASE="${INTRANET_BASE:-http://192.168.0.180:8082/soft/runtime/nerdctl}"

    # 外网镜像基础 URL (使用参数值或默认值)
    local INTERNET_MIRROR_BASE="${INTERNET_BASE:-https://github.com/containerd/nerdctl/releases/download}"

    # 根据网络类型选择基础 URL
    local MIRROR_BASE
    [ "$NETWORK_TYPE" = "in" ] && MIRROR_BASE="$INTRANET_MIRROR_BASE" || MIRROR_BASE="$INTERNET_MIRROR_BASE"

    # 验证版本号格式 (x.y.z)
    if ! [[ "$NERDCTL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的版本号格式: $NERDCTL_VERSION"
        log_info "版本号格式应为: x.y.z (例如: 2.2.1, 2.0.0, 1.7.7)"
        exit 1
    fi

    # 构建 URL 架构部分 (amd64/arm64)
    local URL_ARCH
    [ "$ARCH" = "x64" ] && URL_ARCH="amd64" || URL_ARCH="arm64"

    # 构建完整的下载 URL
    NERDCTL_FILE_URL="${MIRROR_BASE}/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${URL_ARCH}.tar.gz"

    log_info "构建的下载 URL: $NERDCTL_FILE_URL"
}

# ==================== 主逻辑 ====================

main() {
    # 解析参数
    parse_args "$@"

    # 检测网络环境
    detect_network

    # 构建 nerdctl 下载 URL (内部会检测架构)
    build_nerdctl_url

    # 从 URL 提取文件名
    local NERDCTL_FILE=$(basename "$NERDCTL_FILE_URL")

    # 安装路径配置
    local NERDCTL_INSTALL_PATH="${INSTALL_DIR}/nerdctl-${NERDCTL_VERSION:-custom}"

    log_info "========================================="
    log_info "开始安装 nerdctl"
    log_info "========================================="
    log_info "nerdctl 版本:  ${NERDCTL_VERSION:-自定义}"
    log_info "系统架构:      ${ARCH}"
    log_info "网络类型:      ${NETWORK_TYPE}"
    log_info "下载地址:      ${NERDCTL_FILE_URL}"
    log_info "安装路径:      ${NERDCTL_INSTALL_PATH}"
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
    if [ -d "$NERDCTL_INSTALL_PATH" ]; then
        log_warn "软件安装目录 ${NERDCTL_INSTALL_PATH} 已存在，跳过安装"
        DIR_EXISTS=true
    else
        DIR_EXISTS=false
    fi

    # 4. 判断安装包是否存在
    if [ -f "${DOWNLOAD_DIR}/${NERDCTL_FILE}" ]; then
        log_info "安装包 ${NERDCTL_FILE} 已存在"
        ZIP_SOFT_EXISTS=true
    else
        ZIP_SOFT_EXISTS=false
    fi

    # 5. 如果软件未安装且安装包不存在，则下载
    if [ "$DIR_EXISTS" = false ] && [ "$ZIP_SOFT_EXISTS" = false ]; then
        log_info "开始下载 ${NERDCTL_FILE_URL} 到 ${DOWNLOAD_DIR}"

        # 构建下载命令
        if command -v wget &> /dev/null; then
            local download_cmd="wget -O \"${DOWNLOAD_DIR}/${NERDCTL_FILE}\" \"$NERDCTL_FILE_URL\""
            if [ -n "$HTTP_PROXY" ]; then
                download_cmd="export http_proxy=\"$HTTP_PROXY\" https_proxy=\"$HTTP_PROXY\"; $download_cmd"
            fi
            eval "$download_cmd" || {
                log_error "下载失败"
                exit 1
            }
        elif command -v curl &> /dev/null; then
            if [ -n "$HTTP_PROXY" ]; then
                curl -L -x "$HTTP_PROXY" -o "${DOWNLOAD_DIR}/${NERDCTL_FILE}" "$NERDCTL_FILE_URL" || {
                    log_error "下载失败"
                    exit 1
                }
            else
                curl -L -o "${DOWNLOAD_DIR}/${NERDCTL_FILE}" "$NERDCTL_FILE_URL" || {
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
        log_info "创建软件安装路径: ${NERDCTL_INSTALL_PATH}"
        run_with_fallback mkdir -p "$NERDCTL_INSTALL_PATH"

        log_info "解压软件到 ${NERDCTL_INSTALL_PATH}"
        # 解压文件（nerdctl 压缩包是扁平结构，不需要 --strip-components）
        run_with_fallback tar -xzf "${DOWNLOAD_DIR}/${NERDCTL_FILE}" -C "$NERDCTL_INSTALL_PATH" || {
            log_error "解压失败"
            exit 1
        }

        log_info "解压完成"
    fi

    # 7. 创建软连接 /usr/local/nerdctl -> /usr/local/nerdctl-{version}
    local NERDCTL_SYMLINK="${INSTALL_DIR}/nerdctl"
    if [ -L "$NERDCTL_SYMLINK" ] || [ -e "$NERDCTL_SYMLINK" ]; then
        log_warn "软连接 ${NERDCTL_SYMLINK} 已存在，将更新"
        run_with_fallback rm -f "$NERDCTL_SYMLINK"
    fi
    log_info "创建软连接: ${NERDCTL_SYMLINK} -> ${NERDCTL_INSTALL_PATH}"
    run_with_fallback ln -s "$NERDCTL_INSTALL_PATH" "$NERDCTL_SYMLINK"

    # 8. 创建 nerdctl 的软连接到 /usr/bin
    log_info "创建 nerdctl 二进制文件软连接"
    if [ -L "/usr/bin/nerdctl" ] || [ -e "/usr/bin/nerdctl" ]; then
        log_warn "/usr/bin/nerdctl 已存在，将更新"
        run_with_fallback rm -f "/usr/bin/nerdctl"
    fi
    run_with_fallback ln -s "${NERDCTL_INSTALL_PATH}/nerdctl" "/usr/bin/nerdctl"
    log_debug "创建软连接: /usr/bin/nerdctl -> ${NERDCTL_INSTALL_PATH}/nerdctl"

    # 9. 设置执行权限
    log_info "设置执行权限"
    run_with_fallback chmod +x "${NERDCTL_INSTALL_PATH}/nerdctl"
    run_with_fallback chmod +x "/usr/bin/nerdctl"

    # 10. 安装 bash 补全 (可选)
    if [ -f "${NERDCTL_INSTALL_PATH}/extras/complete/bash-completion" ]; then
        COMPLETION_DIR="/usr/share/bash-completion/completions"
        if [ -d "$COMPLETION_DIR" ]; then
            log_info "安装 bash 补全"
            run_with_fallback cp -f "${NERDCTL_INSTALL_PATH}/extras/complete/bash-completion" "${COMPLETION_DIR}/nerdctl"
            log_debug "复制补全文件: ${COMPLETION_DIR}/nerdctl"
        else
            log_debug "bash 补全目录不存在，跳过补全安装"
        fi
    else
        log_debug "未找到 bash 补全文件，跳过补全安装"
    fi

    # 11. 验证安装
    log_info "验证安装..."
    if /usr/bin/nerdctl version &>/dev/null; then
        log_info "nerdctl 安装成功！"
        /usr/bin/nerdctl version
    else
        log_warn "nerdctl 安装完成，但验证失败。请检查安装路径"
    fi

    # 12. 删除安装包
    if [ "$DELETE_PACKAGE" = true ]; then
        log_info "删除安装包: ${DOWNLOAD_DIR}/${NERDCTL_FILE}"
        rm -f "${DOWNLOAD_DIR}/${NERDCTL_FILE}"
    else
        log_info "保留安装包: ${DOWNLOAD_DIR}/${NERDCTL_FILE}"
    fi

    # 13. 显示安装信息
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="

    cat <<EOF
安装信息:
----------------------------------------
nerdctl 版本:  ${NERDCTL_VERSION:-自定义}
系统架构:      ${ARCH}
网络类型:      ${NETWORK_TYPE}
下载地址:      ${NERDCTL_FILE_URL}
安装路径:      ${NERDCTL_INSTALL_PATH}
软连接:        ${NERDCTL_SYMLINK}

使用方法:
  nerdctl version
  nerdctl ps
  nerdctl images

常用命令对照 (Docker -> nerdctl):
  docker ps        ->  nerdctl ps
  docker images    ->  nerdctl images
  docker run       ->  nerdctl run
  docker exec      ->  nerdctl exec
  docker logs      ->  nerdctl logs
  docker stop      ->  nerdctl stop
  docker rm        ->  nerdctl rm

注意事项:
  1. nerdctl 需要 containerd 作为后端运行时
  2. 请确保 containerd 服务已启动: systemctl status containerd
  3. 配置文件位于: /etc/nerdctl/nerdctl.toml
----------------------------------------
EOF
}

# 执行主函数
main "$@"

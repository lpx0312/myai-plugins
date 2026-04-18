#!/bin/bash

#############################################
# Helm 自动安装脚本 v1.0
# 功能：自动下载并安装 Helm
# 支持多种 Helm 版本和架构
# 支持内网/外网环境自动检测
#############################################

set -e  # 遇到错误立即退出
set -o pipefail

# ==================== 默认配置 ====================

# Helm 版本
HELM_VERSION=""

# 系统架构 (x64, arm64)
ARCH=""

# Helm 下载 URL（优先级最高）
HELM_FILE_URL=""

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

# ==================== sudo 兼容 ====================

SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
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

# ==================== 帮助信息 ====================

usage() {
    cat <<EOF
用法: $0 [选项]

Helm 自动安装脚本 - 支持多种 Helm 版本和架构

选项:
  -v, --version <版本>      Helm 版本 (例如: 3.12.3, 3.10.0, 3.9.0)
  -a, --arch <架构>         系统架构 (x64, arm64) [默认: 自动检测]
  -n, --network <网络>      网络类型 (in, out) [默认: 自动检测]
  -i, --intranet-base <URL> 内网基础 URL [默认: http://192.168.0.180:8082/soft/k8s/helm]
  -e, --internet-base <URL> 外网基础 URL [默认: https://get.helm.sh]
  -u, --url <URL>           直接指定 Helm 下载 URL (优先级最高)
  -d, --dir <目录>          安装目录 [默认: /usr/local]
  -p, --proxy <PROXY>       HTTP 代理 (例如: http://192.168.0.4:7890)
  --download-dir <目录>     下载目录 [默认: /tmp]
  --keep-package            保留安装包 (默认删除)
  --debug                   启用调试模式
  -h, --help                显示此帮助信息

示例:
  # 安装 Helm 3.12.3 (自动检测架构)
  $0 -v 3.12.3

  # 安装 Helm 3.10.0 (arm64 架构)
  $0 -v 3.10.0 -a arm64

  # 指定内网环境安装 (跳过网络检测)
  $0 -v 3.12.3 -n in

  # 指定外网环境安装 (跳过网络检测)
  $0 -v 3.12.3 -n out

  # 使用自定义 URL 安装
  $0 -u https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz

  # 安装到指定目录并保留安装包
  $0 -v 3.12.3 -d /opt/helm --keep-package

支持的版本系列:
  - 3.x      v3.0.0 ~ v3.12.3 (最新稳定版)

支持的架构:
  - x64             Intel/AMD 64位
  - arm64/aarch64   ARM 64位
  - arm/v7          ARM 32位
  - 386             x86 32位

注意:
  1. 如果指定 --url，则 --arch、--version 参数将被忽略
  2. 如果不指定 --arch，脚本会自动检测系统架构
  3. 如果不指定 --network，脚本会自动检测内网/外网环境
  4. 需要写入系统路径时会自动使用 sudo（建议用有 sudo 权限的用户运行）
  5. Helm 是 Kubernetes 的包管理工具，用于管理 Helm Charts

EOF
    exit 0
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
                HELM_VERSION="$2"
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
                HELM_FILE_URL="$2"
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
    if [ -z "$HELM_FILE_URL" ] && [ -z "$HELM_VERSION" ]; then
        log_error "必须指定 Helm 版本 (-v/--version) 或下载 URL (-u/--url)"
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
    log_debug "  HELM_VERSION: ${HELM_VERSION:-未指定}"
    log_debug "  ARCH: ${ARCH:-自动检测}"
    log_debug "  NETWORK_TYPE: ${NETWORK_TYPE:-自动检测}"
    log_debug "  HELM_FILE_URL: ${HELM_FILE_URL:-自动构建}"
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
                ARCH="amd64"
                log_debug "统一架构名称: $ARCH -> amd64"
                ;;
            arm64|aarch64)
                ARCH="arm64"
                log_debug "统一架构名称: $ARCH -> arm64"
                ;;
            arm|armv7l|armhf)
                ARCH="arm"
                log_debug "统一架构名称: $ARCH -> arm"
                ;;
            386|i386|i686)
                ARCH="386"
                log_debug "统一架构名称: $ARCH -> 386"
                ;;
            *)
                log_warn "警告: 不常见的架构 '$ARCH'"
                log_warn "支持的架构: amd64, arm64, arm, 386"
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
        armv7l|armv6l|armhf)
            ARCH="arm"
            log_info "检测到系统架构: $ARCH (ARM 32位)"
            ;;
        i686|i386)
            ARCH="386"
            log_info "检测到系统架构: $ARCH (x86 32位)"
            ;;
        *)
            log_warn "警告: 不支持的系统架构: $sys_arch"
            log_warn "支持的架构: amd64, arm64, arm, 386"
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

build_helm_url() {
    # 如果已经指定了 URL,直接使用(优先级最高,不检测架构)
    if [ -n "$HELM_FILE_URL" ]; then
        log_info "使用指定的下载 URL: $HELM_FILE_URL"
        return
    fi

    # 只有在需要构建 URL 时才检测架构
    detect_arch

    log_info "根据版本和架构构建下载 URL..."

    # 内网镜像基础 URL（如果未指定则使用默认值）
    local intranet_base="${INTRANET_BASE:-http://192.168.0.180:8082/soft/k8s/helm}"

    # 外网镜像基础 URL（如果未指定则使用默认值）
    local internet_base="${INTERNET_BASE:-https://get.helm.sh}"

    # 根据网络类型选择基础 URL
    local MIRROR_BASE
    [ "$NETWORK_TYPE" = "in" ] && MIRROR_BASE="$intranet_base" || MIRROR_BASE="$internet_base"

    # 验证版本号格式 (x.y.z)
    if ! [[ "$HELM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的版本号格式: $HELM_VERSION"
        log_info "版本号格式应为: x.y.z (例如: 3.12.3, 3.10.0, 3.9.0)"
        exit 1
    fi

    # 构建完整的下载 URL
    # 外网: https://get.helm.sh/helm-v{version}-linux-{arch}.tar.gz
    # 内网: http://192.168.0.180:8082/soft/k8s/helm/v{version}/helm-v{version}-linux-{arch}.tar.gz
    if [ "$NETWORK_TYPE" = "in" ]; then
        HELM_FILE_URL="${MIRROR_BASE}/v${HELM_VERSION}/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz"
    else
        HELM_FILE_URL="${MIRROR_BASE}/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz"
    fi

    log_info "构建的下载 URL: $HELM_FILE_URL"
}

# ==================== 主逻辑 ====================

main() {
    # 解析参数
    parse_args "$@"

    # 检测网络环境
    detect_network

    # 构建 Helm 下载 URL (内部会检测架构)
    build_helm_url

    # 从 URL 提取文件名
    local HELM_FILE=$(basename "$HELM_FILE_URL")

    # 安装路径配置 (Helm 直接安装到指定目录的 bin 子目录)
    local HELM_INSTALL_PATH="${INSTALL_DIR}/helm-${HELM_VERSION:-custom}"

    log_info "========================================="
    log_info "开始安装 Helm"
    log_info "========================================="
    log_info "Helm 版本:      ${HELM_VERSION:-自定义}"
    log_info "系统架构:       ${ARCH}"
    log_info "网络类型:       ${NETWORK_TYPE}"
    log_info "下载地址:       ${HELM_FILE_URL}"
    log_info "安装路径:       ${HELM_INSTALL_PATH}"
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
    if [ -d "$HELM_INSTALL_PATH" ]; then
        log_warn "软件安装目录 ${HELM_INSTALL_PATH} 已存在，跳过安装"
        DIR_EXISTS=true
    else
        DIR_EXISTS=false
    fi

    # 4. 判断安装包是否存在
    if [ -f "${DOWNLOAD_DIR}/${HELM_FILE}" ]; then
        log_info "安装包 ${HELM_FILE} 已存在"
        ZIP_SOFT_EXISTS=true
    else
        ZIP_SOFT_EXISTS=false
    fi

    # 5. 如果软件未安装且安装包不存在，则下载
    if [ "$DIR_EXISTS" = false ] && [ "$ZIP_SOFT_EXISTS" = false ]; then
        log_info "开始下载 ${HELM_FILE_URL} 到 ${DOWNLOAD_DIR}"

        # 构建下载命令
        if command -v wget &> /dev/null; then
            local download_cmd="wget -O \"${DOWNLOAD_DIR}/${HELM_FILE}\" \"$HELM_FILE_URL\""
            if [ -n "$HTTP_PROXY" ]; then
                download_cmd="export http_proxy=\"$HTTP_PROXY\" https_proxy=\"$HTTP_PROXY\"; $download_cmd"
            fi
            eval "$download_cmd" || {
                log_error "下载失败"
                exit 1
            }
        elif command -v curl &> /dev/null; then
            if [ -n "$HTTP_PROXY" ]; then
                curl -L -x "$HTTP_PROXY" -o "${DOWNLOAD_DIR}/${HELM_FILE}" "$HELM_FILE_URL" || {
                    log_error "下载失败"
                    exit 1
                }
            else
                curl -L -o "${DOWNLOAD_DIR}/${HELM_FILE}" "$HELM_FILE_URL" || {
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
        log_info "创建软件安装路径: ${HELM_INSTALL_PATH}"
        run_with_fallback mkdir -p "$HELM_INSTALL_PATH"

        log_info "解压软件到 ${DOWNLOAD_DIR}"
        # Helm 压缩包内含 linux-amd64/helm 或 linux-arm64/helm 等目录结构
        # 需要提取到临时目录再移动
        local TEMP_EXTRACT_DIR="${DOWNLOAD_DIR}/helm-temp-$$"
        mkdir -p "$TEMP_EXTRACT_DIR"
        run_with_fallback tar -xzf "${DOWNLOAD_DIR}/${HELM_FILE}" -C "$TEMP_EXTRACT_DIR" || {
            log_error "解压失败"
            run_with_fallback rm -rf "$TEMP_EXTRACT_DIR"
            exit 1
        }

        # 将 helm 二进制文件移动到安装目录
        # Helm 压缩包结构: {os}-{arch}/helm
        local HELM_BIN
        HELM_BIN=$(find "$TEMP_EXTRACT_DIR" -type f -name "helm" | head -1)
        if [ -z "$HELM_BIN" ]; then
            log_error "在压缩包中未找到 helm 二进制文件"
            run_with_fallback rm -rf "$TEMP_EXTRACT_DIR"
            exit 1
        fi

        run_with_fallback cp "$HELM_BIN" "${HELM_INSTALL_PATH}/helm"
        run_with_fallback rm -rf "$TEMP_EXTRACT_DIR"
        log_info "解压完成"
    fi

    # 7. 创建软连接 /usr/local/helm -> /usr/local/helm-{version}
    local HELM_SYMLINK="${INSTALL_DIR}/helm"
    if [ -L "$HELM_SYMLINK" ] || [ -e "$HELM_SYMLINK" ]; then
        log_warn "软连接 ${HELM_SYMLINK} 已存在，将更新"
        run_with_fallback rm -f "$HELM_SYMLINK"
    fi
    log_info "创建软连接: ${HELM_SYMLINK} -> ${HELM_INSTALL_PATH}"
    run_with_fallback ln -s "${HELM_INSTALL_PATH}" "$HELM_SYMLINK"

    # 8. 创建 helm 的软连接到 /usr/bin
    log_info "创建 helm 二进制文件软连接"
    if [ -L "/usr/bin/helm" ] || [ -e "/usr/bin/helm" ]; then
        log_warn "/usr/bin/helm 已存在，将更新"
        run_with_fallback rm -f "/usr/bin/helm"
    fi
    run_with_fallback ln -s "${HELM_INSTALL_PATH}/helm" "/usr/bin/helm"
    log_debug "创建软连接: /usr/bin/helm -> ${HELM_INSTALL_PATH}/helm"

    # 9. 设置执行权限
    log_info "设置执行权限"
    run_with_fallback chmod +x "${HELM_INSTALL_PATH}/helm"
    run_with_fallback chmod +x "/usr/bin/helm"

    # 10. 安装 bash 补全
    log_info "安装 bash 补全"
    COMPLETION_DIR="/usr/share/bash-completion/completions"
    if [ -d "$COMPLETION_DIR" ]; then
        # 生成 helm 的 bash 补全
        if ${HELM_INSTALL_PATH}/helm completion bash > "${COMPLETION_DIR}/helm" 2>/dev/null; then
            log_debug "安装 bash 补全文件: ${COMPLETION_DIR}/helm"
        else
            log_debug "无法生成 helm bash 补全，跳过"
        fi
    else
        log_debug "bash 补全目录不存在，跳过补全安装"
    fi

    # 11. 验证安装
    log_info "验证安装..."
    if /usr/bin/helm version &>/dev/null; then
        log_info "Helm 安装成功！"
        /usr/bin/helm version
    else
        log_warn "Helm 安装完成，但验证失败。请检查安装路径"
    fi

    # 12. 删除安装包
    if [ "$DELETE_PACKAGE" = true ]; then
        log_info "删除安装包: ${DOWNLOAD_DIR}/${HELM_FILE}"
        rm -f "${DOWNLOAD_DIR}/${HELM_FILE}"
    else
        log_info "保留安装包: ${DOWNLOAD_DIR}/${HELM_FILE}"
    fi

    # 13. 显示安装信息
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="

    cat <<EOF
安装信息:
----------------------------------------
Helm 版本:      ${HELM_VERSION:-自定义}
系统架构:       ${ARCH}
网络类型:       ${NETWORK_TYPE}
下载地址:       ${HELM_FILE_URL}
安装路径:       ${HELM_INSTALL_PATH}
软连接:         ${HELM_SYMLINK}

使用方法:
  helm version
  helm list
  helm repo list
  helm search repo

常用命令:
  # 添加 chart 仓库
  helm repo add stable https://charts.helm.sh/stable

  # 搜索 chart
  helm search repo nginx

  # 安装 chart
  helm install my-release stable/nginx

  # 列出已安装的 releases
  helm list

  # 卸载 release
  helm uninstall my-release

注意事项:
  1. Helm 需要 Kubernetes 集群配置 (kubeconfig)
  2. 配置文件通常位于: ~/.kube/config
  3. 确保有足够的权限访问 Kubernetes API
----------------------------------------
EOF
}

# 执行主函数
main "$@"

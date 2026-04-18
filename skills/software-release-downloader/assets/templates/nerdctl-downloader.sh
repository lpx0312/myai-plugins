#!/bin/bash

# nerdctl 版本下载脚本
# 从 GitHub Releases 页面获取所有版本，下载 arm64 和 amd64 架构的二进制文件

set -e

# 版本信息
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="nerdctl-downloader"

# 配置
REPO_OWNER="containerd"
REPO_NAME="nerdctl"
BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
DOWNLOAD_DIR="./nerdctl_binaries"
DRY_RUN=false
VERIFY_MODE=false
PROXY=""
GITHUB_TOKEN=""

# 显示帮助信息
show_help() {
    cat << EOF
用法: $SCRIPT_NAME [选项] [下载目录]

从 GitHub 下载 nerdctl 的所有稳定版本二进制文件 (amd64 和 arm64)

选项:
  -h, --help         显示此帮助信息并退出
  -v, --version      显示脚本版本并退出
  -d, --dir DIR      指定下载目录 (默认: ./nerdctl_binaries)
  -n, --dry-run      模拟运行，仅显示下载链接和 URL 可用性
  -V, --verify       下载时验证文件完整性，并显示详细验证结果
  -p, --proxy URL    设置代理服务器 (例如: http://127.0.0.1:7890)
  -t, --token TOKEN  设置 GitHub Token (避免 API 限流)

示例:
  $SCRIPT_NAME                              # 下载到默认目录
  $SCRIPT_NAME -d /opt/nerdctl              # 下载到指定目录
  $SCRIPT_NAME -V                           # 下载并验证文件完整性
  $SCRIPT_NAME -n                           # 模拟运行，查看将下载的文件
  $SCRIPT_NAME -p http://192.168.0.225:7897 # 使用代理下载
  $SCRIPT_NAME -t ghp_xxxx -V               # 使用 Token 和代理下载并验证

环境变量:
  GITHUB_TOKEN    也可通过环境变量设置 GitHub Token

EOF
}

# 检查必需的环境变量
if [[ -z "${GITHUB_TOKEN}" ]]; then
    log_error "GITHUB_TOKEN 环境变量未设置"
    exit 1
fi

if [[ -z "${PROXY}" ]]; then
    log_error "PROXY 环境变量未设置"
    exit 1
fi

# 显示版本信息
show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        -d|--dir)
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -V|--verify)
            VERIFY_MODE=true
            shift
            ;;
        -p|--proxy)
            PROXY="$2"
            shift 2
            ;;
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -*)
            echo "错误: 未知选项 $1"
            echo "运行 '$SCRIPT_NAME --help' 获取帮助"
            exit 1
            ;;
        *)
            # 兼容旧版用法：直接传入目录参数
            DOWNLOAD_DIR="$1"
            shift
            ;;
    esac
done

# 支持环境变量设置 Token
if [ -z "$GITHUB_TOKEN" ] && [ -n "$GITHUB_TOKEN_ENV" ]; then
    GITHUB_TOKEN="$GITHUB_TOKEN_ENV"
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 检查依赖
check_dependencies() {
    local deps=("curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "缺少依赖: $dep，请先安装"
            exit 1
        fi
    done
}

# 获取所有版本信息
get_all_releases() {
    log_info "正在从 GitHub API 获取版本信息..."

    local releases=()
    local page=1
    local per_page=100

    # 构建 curl 认证头
    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
        log_info "使用 GitHub Token 认证"
    fi

    while true; do
        local response
        if [ -n "$GITHUB_TOKEN" ]; then
            response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "${API_URL}?per_page=${per_page}&page=${page}")
        else
            response=$(curl -s "${API_URL}?per_page=${per_page}&page=${page}")
        fi

        # 检查是否获取到数据
        if [ -z "$response" ] || [ "$response" = "[]" ]; then
            break
        fi

        # 检查API限流
        local has_message
        has_message=$(echo "$response" | jq 'has("message")' 2>/dev/null)
        if [ "$has_message" = "true" ]; then
            local error_msg
            error_msg=$(echo "$response" | jq -r '.message')
            if [[ "$error_msg" == *"rate limit"* ]]; then
                log_error "GitHub API 限流! 请使用 -t 参数设置 GitHub Token"
                log_info "获取 Token: https://github.com/settings/tokens"
                log_info "使用方法: $SCRIPT_NAME -t ghp_your_token_here"
            else
                log_error "GitHub API 出错: $error_msg"
            fi
            exit 1
        fi

        # 提取版本标签
        local tags
        tags=$(echo "$response" | jq -r '.[].tag_name')

        while IFS= read -r tag; do
            releases+=("$tag")
        done <<< "$tags"

        # 检查是否还有更多页面
        local count
        count=$(echo "$response" | jq 'length')
        if [ "$count" -lt "$per_page" ]; then
            break
        fi

        ((page++))
    done

    echo "${releases[@]}"
}

# 过滤稳定版本（排除 rc, beta, alpha 等预发布版本）
filter_stable_versions() {
    local versions=("$@")

    for version in "${versions[@]}"; do
        # 排除包含 rc, beta, alpha 的版本
        if [[ ! "$version" =~ (rc|beta|alpha) ]]; then
            echo "$version"
        fi
    done
}

# 获取指定版本的下载链接
get_download_url() {
    local version="$1"
    local arch="$2"
    local filename="nerdctl-${version#v}-linux-${arch}.tar.gz"
    echo "${BASE_URL}/${version}/${filename}"
}

# 检测 URL 是否存在
check_url_exists() {
    local url="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --head -L "$url" 2>/dev/null)

    if [ "$http_code" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# 验证 tar.gz 文件完整性
verify_tarball() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        log_error "文件不存在: $file_path"
        return 1
    fi

    # VERIFY_MODE 时显示详细信息
    if [ "$VERIFY_MODE" = true ]; then
        log_info "验证文件: $(basename "$file_path")"
    fi

    # 使用 tar -tf 测试文件完整性
    if tar -tf "$file_path" > /dev/null 2>&1; then
        if [ "$VERIFY_MODE" = true ]; then
            log_success "验证通过: $(basename "$file_path")"
        fi
        return 0
    else
        log_error "文件损坏: $(basename "$file_path")"
        # 删除损坏的文件
        rm -f "$file_path"
        log_warning "已删除损坏的文件"
        return 1
    fi
}

# 下载文件
download_file() {
    local url="$1"
    local output_dir="$2"
    local filename="$3"

    local output_path="${output_dir}/${filename}"

    # dry-run 模式：只显示 URL 并检测可用性
    if [ "$DRY_RUN" = true ]; then
        echo "  $url"
        echo "    -> $output_path"
        # 检测 URL 是否存在
        if check_url_exists "$url"; then
            echo "    [状态: 可用]"
        else
            echo "    [状态: 不可用或不存在]"
        fi
        return 0
    fi

    # 如果文件已存在且有效，跳过下载
    if [ -f "$output_path" ]; then
        log_warning "文件已存在，验证中: $output_path"
        if verify_tarball "$output_path"; then
            return 0
        else
            log_warning "文件已损坏，重新下载"
        fi
    fi

    # 检测 URL 是否存在
    log_info "检测 URL 可用性: $url"
    if ! check_url_exists "$url"; then
        log_error "URL 不存在或不可访问: $url"
        return 1
    fi
    log_success "URL 可用"

    log_info "下载: $url"

    # 使用 curl 下载，显示进度
    if curl -L --progress-bar -o "${output_path}.tmp" "$url"; then
        mv "${output_path}.tmp" "$output_path"
        log_success "下载完成: $output_path"

        # 验证下载的文件
        if verify_tarball "$output_path"; then
            return 0
        else
            return 1
        fi
    else
        rm -f "${output_path}.tmp"
        log_error "下载失败: $url"
        return 1
    fi
}

# 下载指定版本的所有架构
download_version() {
    local version="$1"
    local arches=("amd64" "arm64")
    local success_count=0
    local fail_count=0

    # 创建版本目录
    local version_dir="${DOWNLOAD_DIR}/${version}"
    mkdir -p "$version_dir"

    log_info "处理版本: $version"

    for arch in "${arches[@]}"; do
        local url
        url=$(get_download_url "$version" "$arch")
        local filename="nerdctl-${version#v}-linux-${arch}.tar.gz"

        if download_file "$url" "$version_dir" "$filename"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    if [ $fail_count -eq 0 ]; then
        log_success "版本 $version 下载完成 (成功: $success_count)"
    else
        log_warning "版本 $version 部分下载失败 (成功: $success_count, 失败: $fail_count)"
    fi
}

# 主函数
main() {
    # 设置代理
    if [ -n "$PROXY" ]; then
        export HTTP_PROXY="$PROXY"
        export HTTPS_PROXY="$PROXY"
        log_info "已设置代理: $PROXY"
    fi

    log_info "nerdctl 版本下载脚本"
    log_info "下载目录: $DOWNLOAD_DIR"
    if [ "$DRY_RUN" = true ]; then
        log_info "模式: DRY-RUN (仅显示下载链接，不实际下载)"
    elif [ "$VERIFY_MODE" = true ]; then
        log_info "模式: 下载并验证文件完整性"
    fi
    echo ""

    # 检查依赖
    check_dependencies

    # 创建下载目录
    mkdir -p "$DOWNLOAD_DIR"

    # 获取所有版本
    local all_versions
    all_versions=$(get_all_releases)

    if [ -z "$all_versions" ]; then
        log_error "未获取到任何版本信息"
        exit 1
    fi

    # 转换为数组
    local versions_array=($all_versions)

    log_success "获取到 ${#versions_array[@]} 个版本"
    echo ""

    # 过滤稳定版本
    local stable_versions
    stable_versions=$(filter_stable_versions "${versions_array[@]}")

    if [ -z "$stable_versions" ]; then
        log_error "未找到稳定版本"
        exit 1
    fi

    local stable_array=($stable_versions)
    log_info "找到 ${#stable_array[@]} 个稳定版本"
    echo ""

    # 显示版本列表
    log_info "稳定版本列表:"
    for v in "${stable_array[@]}"; do
        echo "  - $v"
    done
    echo ""

    # dry-run 模式：直接显示下载链接，跳过确认
    if [ "$DRY_RUN" = true ]; then
        log_info "以下是将要下载的文件:"
        echo ""
        local available_count=0
        local unavailable_count=0
        for version in "${stable_array[@]}"; do
            log_info "版本: $version"
            for arch in "amd64" "arm64"; do
                local url
                url=$(get_download_url "$version" "$arch")
                local filename="nerdctl-${version#v}-linux-${arch}.tar.gz"
                local output_path="${DOWNLOAD_DIR}/${version}/${filename}"
                echo "  $url"
                echo "    -> $output_path"
                # 检测 URL 是否存在
                if check_url_exists "$url"; then
                    echo "    [状态: 可用]"
                    available_count=$((available_count + 1))
                else
                    echo "    [状态: 不可用或不存在]"
                    unavailable_count=$((unavailable_count + 1))
                fi
            done
            echo ""
        done
        log_success "DRY-RUN 完成!"
        log_info "共 ${#stable_array[@]} 个版本，$(( ${#stable_array[@]} * 2 )) 个文件"
        log_info "可用: $available_count, 不可用: $unavailable_count"
        exit 0
    fi

    # 下载所有版本
    log_info "开始下载..."
    echo ""

    local total_success=0
    local total_fail=0

    for version in "${stable_array[@]}"; do
        download_version "$version"
        echo ""
    done

    log_success "所有下载完成!"
    log_info "文件保存在: $DOWNLOAD_DIR"
}

# 运行主函数
main "$@"

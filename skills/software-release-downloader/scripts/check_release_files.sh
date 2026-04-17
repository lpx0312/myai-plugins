#!/bin/bash

# 检查 GitHub Release 文件命名模式
# 用法: ./check_release_files.sh <owner> <repo> [tag]

set -e

OWNER="$1"
REPO="$2"
TAG="${3:-latest}"

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
    echo "用法: $0 <owner> <repo> [tag]"
    echo ""
    echo "示例:"
    echo "  $0 containerd containerd v1.7.0"
    echo "  $0 opencontainers runc v1.1.7"
    echo "  $0 nerdctl nerdctl latest"
    exit 1
fi

echo "正在检查 ${OWNER}/${REPO} 的 Release 文件..."
echo "Tag: ${TAG}"
echo ""

# 获取 release 信息
if [ "$TAG" = "latest" ]; then
    API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/latest"
else
    API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/tags/${TAG}"
fi

RELEASE_DATA=$(curl -s "$API_URL")

# 检查是否出错
if echo "$RELEASE_DATA" | grep -q '"message"'; then
    echo "错误: $(echo "$RELEASE_DATA" | jq -r '.message')"
    exit 1
fi

# 显示版本信息
VERSION=$(echo "$RELEASE_DATA" | jq -r '.tag_name // .name // "unknown"')
echo "版本: $VERSION"
echo ""

# 获取所有 assets
ASSETS=$(echo "$RELEASE_DATA" | jq -r '.assets[]? | "\(.name)|\(.size)|\(.download_url)"' 2>/dev/null)

if [ -z "$ASSETS" ]; then
    echo "未找到 release 文件"
    echo ""
    echo "可能的原因:"
    echo "  1. 该版本没有预编译的二进制文件"
    echo "  2. Tag 名称不正确"
    echo ""
    echo "可用版本:"
    curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases?per_page=10" | \
        jq -r '.[].tag_name' | head -20
    exit 1
fi

# 显示文件列表
echo "Release 文件:"
echo "----------------------------------------"
printf "%-50s %12s %s\n" "文件名" "大小" "下载 URL"
echo "----------------------------------------"

while IFS='|' read -r name size url; do
    if [ -n "$name" ]; then
        # 格式化大小
        if [ "$size" -gt 1048576 ]; then
            size_mb=$(echo "scale=1; $size / 1048576" | bc)
            size_str="${size_mb} MB"
        elif [ "$size" -gt 1024 ]; then
            size_kb=$(echo "scale=1; $size / 1024" | bc)
            size_str="${size_kb} KB"
        else
            size_str="${size} B"
        fi

        # 截断过长的 URL
        short_url="${url:0:80}"
        if [ ${#url} -gt 80 ]; then
            short_url="${short_url}..."
        fi

        printf "%-50s %12s %s\n" "$name" "$size_str" "$url"
    fi
done <<< "$ASSETS"

echo "----------------------------------------"
echo ""

# 分析文件模式
echo "文件命名分析:"
echo "----------------------------------------"

# 提取包含 amd64/arm64 的文件
echo ""
echo "amd64 文件:"
echo "$ASSETS" | grep -i "amd64\|x86_64" | while IFS='|' read -r name size url; do
    echo "  - $name"
done

echo ""
echo "arm64 文件:"
echo "$ASSETS" | grep -i "arm64\|aarch64" | while IFS='|' read -r name size url; do
    echo "  - $name"
done

echo ""
echo "通用文件 (无架构标识):"
echo "$ASSETS" | grep -iv "amd64\|arm64\|x86_64\|aarch64\|i386\|i686" | while IFS='|' read -r name size url; do
    if [ -n "$name" ]; then
        echo "  - $name"
    fi
done

echo ""
echo "----------------------------------------"
echo ""
echo "根据以上信息，确定:"
echo "  1. 文件类型: tar.gz 压缩包 或 纯二进制"
echo "  2. 文件命名模式: 替换 {version} 和 {arch} 占位符"
echo ""
echo "示例模式:"
echo "  - tar.gz:   {name}-{version}-linux-{arch}.tar.gz"
echo "  - 二进制:   {name}.{arch}"

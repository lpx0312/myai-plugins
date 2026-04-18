# 阶段 2: 脚本编写

**输入：** 阶段 1 收集的信息
**输出：** `install_{tool}.sh`

---

## 2.1 参照模板创建脚本

1. 读取参考模板
2. 在本地创建脚本文件：
   ```bash
   mkdir -p "${MIRROR_LOCAL_ROOT}\scripts\{output_dir}"
   cat > "${MIRROR_LOCAL_ROOT}\scripts\{output_dir}\install_{tool}.sh" << 'EOF'
   # 模板内容，修改以下变量
   EOF
   ```

---

## 2.2 必须修改的变量

```bash
# ==================== 默认配置区 ====================
TOOL_NAME="kubectl"              # 工具名称（全大写）
INTRANET_BASE="http://mirrors.lpx.com/soft/k8s/kubectl"  # 内网基础 URL
# 文件名格式 - 使用阶段 1 查找到的实际格式
FILE_PATTERN="kubectl.{arch}"    # 注意是 . 而非 -
VERSION="${DEFAULT_VERSION:-1.32.0}"
```

---

## 2.3 脚本固定结构

脚本按以下顺序编写：

| 序号 | 部分 | 说明 |
|------|------|------|
| 1 | 默认配置区 | 变量定义 |
| 2 | 颜色输出函数 | `log_info`, `log_error` |
| 3 | 帮助信息 | `usage()` |
| 4 | 参数解析 | `parse_args()` |
| 5 | 架构检测 | `detect_arch()` |
| 6 | 网络检测 | `detect_network()` |
| 7 | URL 构建 | `build_{tool}_url()` |
| 8 | 主逻辑 | `main()` |

---

## 2.4 URL 构建示例

```bash
build_kubectl_url() {
    local arch=$1
    local version=$2
    local network_type=$3

    if [ "$network_type" = "in" ]; then
        # 内网：直接使用内网 URL（注意文件名分隔符是 . 而非 -）
        local url_arch
        [ "$arch" = "x64" ] && url_arch="amd64" || url_arch="arm64"
        echo "${INTRANET_BASE}/v${version}/kubectl.${url_arch}"
    else
        # 外网：通过 GitHub API 获取
        local api_url="https://api.github.com/repos/kubernetes/kubernetes/releases/tags/v${version}"
        echo "https://dl.k8s.io/release/v${version}/bin/linux/${url_arch}/kubectl"
    fi
}
```

---

## 2.5 常见错误预防

| 错误 | 预防措施 |
|------|---------|
| 文件名分隔符错误 | 内网单文件通常是 `.{arch}` 而非 `-{arch}` |
| 路径错误 | 使用阶段 1 搜索到的实际路径 |
| 版本前缀错误 | 内网路径通常需要 `v` 前缀（如 `v1.32.0`） |

# 阶段 2: 脚本编写

## 确定输出路径

**正确处理输出目录：**

1. **获取用户工作目录** - 使用 `pwd` 命令获取当前工作目录
2. **解析用户指定的路径**：
   - 如果用户指定绝对路径，直接使用
   - 如果用户指定相对路径（如 `runtime/docker_tools/image-syncer`），拼接用户工作目录
   - 如果用户没指定，默认为当前工作目录

3. **创建目录时使用用户工作目录作为基准**

如果用户没有指定目录，询问：

```
请输入脚本输出目录 [默认: 当前工作目录]:
```

## 生成下载脚本

**重要：完全按照 nerdctl-downloader.sh 模板生成！**

首先读取参考模板。使用 mirror-file-manager skill 获取模板的本地路径：

1. **获取模板 URL**：
   - 模板 base URL：`http://mirrors.lpx.com/soft/runtime/`
   - nerdctl 模板：`http://mirrors.lpx.com/soft/runtime/nerdctl/nerdctl-downloader.sh`
   - containerd 模板：`http://mirrors.lpx.com/soft/runtime/containerd/containerd-downloader.sh`
   - runc 模板：`http://mirrors.lpx.com/soft/runtime/runc/runc-downloader.sh`

2. **转换为本地路径** - 使用 mirror-file-manager skill：
   - 将 `http://mirrors.lpx.com` 替换为 `${MIRROR_LOCAL_ROOT}`
   - 示例：`http://mirrors.lpx.com/soft/runtime/nerdctl/nerdctl-downloader.sh`
     → `${MIRROR_LOCAL_ROOT}\soft\runtime\nerdctl\nerdctl-downloader.sh`

## 必须遵守的关键规则

0. **必需环境变量检查** - 在参数解析之后、日志函数定义之后检查：
   ```bash
   # 解析命令行参数...
   while [[ $# -gt 0 ]]; do
       ...
   done

   # 支持环境变量设置 Token
   if [ -z "$GITHUB_TOKEN" ] && [ -n "$GITHUB_TOKEN_ENV" ]; then
       GITHUB_TOKEN="$GITHUB_TOKEN_ENV"
   fi

   # 颜色输出和日志函数定义...

   # 检查必需的环境变量（必须在日志函数定义之后）
   if [[ -z "${GITHUB_TOKEN}" ]]; then
       log_error "GITHUB_TOKEN 环境变量未设置"
       exit 1
   fi

   if [[ -z "${PROXY}" ]]; then
       log_error "PROXY 环境变量未设置"
       exit 1
   fi
   ```

   **注意：不要在日志函数定义之前检查环境变量！** 否则会报错 `log_error: 未找到命令`。

1. **代理设置方式** - 使用环境变量，不是 curl 参数
   ```bash
   # 正确方式 (curl 自动使用)
   export HTTP_PROXY="$PROXY"
   export HTTPS_PROXY="$PROXY"

   # 错误方式 (不要这样)
   curl -x "$PROXY" ...
   ```

2. **下载函数直接调用 curl** - 不要动态构建命令字符串
   ```bash
   # 正确方式
   if curl -L --progress-bar -o "${output_path}.tmp" "$url"; then
       mv "${output_path}.tmp" "$output_path"
       log_success "下载完成: $output_path"
   else
       rm -f "${output_path}.tmp"
       log_error "下载失败: $url"
       return 1
   fi

   # 错误方式 (不要这样)
   local curl_cmd="curl -L -s"
   if [[ -n "$HTTP_PROXY" ]]; then
       curl_cmd="$curl_cmd -x \"$HTTP_PROXY\""
   fi
   if [[ -n "$HTTPS_PROXY" ]]; then
       curl_cmd="$curl_cmd -x \"$HTTPS_PROXY\""
   fi
   $curl_cmd "$url" -o "$output"
   ```

3. **日志输出到 stderr**
   ```bash
   log_info() {
       echo -e "${BLUE}[INFO]${NC} $1" >&2
   }
   ```

4. **使用 sed 解析 JSON** - 不要使用 `grep -oP`
   ```bash
   # 正确方式
   tags=$(echo "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

   # 错误方式 (不兼容)
   grep -oP '"tag_name":\s*"\K[^"]*"'
   ```

5. **错误日志必须包含完整 URL**
   ```bash
   log_error "下载失败: $url"  # 必须包含 URL
   log_error "URL 不存在或不可访问: $url"
   ```

## 模板结构

**完全参考 nerdctl-downloader.sh 的结构：**

- 日志函数 (log_info, log_success, log_warning, log_error)
- get_all_releases() - 使用 sed 解析
- filter_stable_versions() - 使用 grep -vE
- get_download_url() - 返回完整 URL
- check_url_exists() - 使用 curl 检测
- verify_*() - 根据文件类型选择
- download_file() - 直接调用 curl
- download_version() - 循环架构
- main() - 主函数流程

## 根据项目类型选择模板

| 文件类型 | 参考模板 |
|----------|----------|
| tar.gz 压缩包 | containerd-downloader.sh |
| 纯二进制文件 | runc-downloader.sh |

## 关键修改点

| 变量 | 说明 |
|------|------|
| `SCRIPT_NAME` | 脚本名称（如 nerdctl-downloader） |
| `REPO_OWNER` | GitHub 用户名/组织 |
| `REPO_NAME` | 仓库名称 |
| `DOWNLOAD_DIR` | 默认下载目录（如 ./nerdctl_binaries） |
| `get_download_url()` | 根据项目文件命名规则修改 |
| `verify_*()` | tar.gz 用 `verify_tarball()`，纯文件用 `verify_binary()` |
| `filter_stable_versions()` | 某些项目需要排除特殊格式 |

## 特殊处理

### containerd - 排除 API 版本
```bash
filter_stable_versions() {
    # 排除 rc/beta/alpha 和 api/v* 格式
    if [[ ! "$version" =~ (rc|beta|alpha) ]] && [[ ! "$version" =~ ^api/ ]]; then
        echo "$version"
    fi
}
```

### kubectl - 不同架构的下载 URL
kubectl 使用不同的目录区分架构，需要特殊处理：
```bash
get_download_url() {
    local version="$1"
    local arch="$2"
    local arch_path="amd64"
    [ "$arch" = "arm64" ] && arch_path="arm64"
    echo "https://dl.k8s.io/release/${version}/bin/linux/${arch_path}/kubectl"
}
```

### 纯二进制验证 (runc 模式)
```bash
verify_binary() {
    # 1. 检查文件大小（> 1MB）
    # 2. 用 file 命令检查 ELF 格式
    # 3. 设置可执行权限 chmod +x
}
```

### tar.gz 验证 (containerd 模式)
```bash
verify_tarball() {
    # 使用 tar -tf 测试文件完整性
    if tar -tf "$file_path" > /dev/null 2>&1; then
        return 0
    fi
}
```

## 生成入口脚本 (download.sh)

```bash
#!/bin/bash

CURRENT_DIR=$(cd `dirname $0`; pwd)

# 检查必需的环境变量
if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo  "[ ERROR ]: GITHUB_TOKEN 环境变量未设置"
    exit 1
fi

if [[ -z "${HTTP_PROXY}" ]]; then
    echo  "[ ERROR ]: PROXY 环境变量未设置"
    exit 1
fi

if [[ -z "${HTTPS_PROXY}" ]]; then
    echo  "[ ERROR ]: HTTPS_PROXY 环境变量未设置"
    exit 1
fi

# 使用入口脚本统一下载
if [[ "$1" == "-n" ]]; then
    bash {name}-downloader.sh -p ${HTTPS_PROXY} -t ${GITHUB_TOKEN} -V -d ${CURRENT_DIR} -n
else
    bash {name}-downloader.sh -p ${HTTPS_PROXY} -t ${GITHUB_TOKEN} -V -d ${CURRENT_DIR}
fi
```

**入口脚本说明：**
- `CURRENT_DIR` - 获取脚本所在目录的绝对路径
- **必须设置 `HTTPS_PROXY`** - 不存在则直接退出
- **必须设置 `GITHUB_TOKEN`** - 不存在则直接退出
- 使用环境变量设置代理和 Token
- 启用验证模式：`-V`
- 下载到脚本所在目录
- **重要：变量必须加引号**，避免空变量导致参数解析错误

## 输出文件结构

生成的文件结构：

```
{output_dir}/
├── {name}-downloader.sh    # 完整下载脚本
└── download.sh             # 统一入口脚本
```

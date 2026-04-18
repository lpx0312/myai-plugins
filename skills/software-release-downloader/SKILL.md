---
name: software-release-downloader
description: 自动生成 GitHub Release 下载脚本和统一入口脚本。当用户需要为任何 GitHub 项目（如 containerd, runc, nerdctl, kubectl, helm, terraform 等）创建下载脚本的完整工作流时使用。也适用于用户说"帮我写个安装脚本"、"参照 X 脚本写 Y 脚本"、"给这个项目写个下载器"等场景。
---

> ⚠️ **首次使用需设置环境变量**
>
> **Windows (PowerShell):**
> ```powershell
> $env:MIRROR_LOCAL_ROOT = "Z:\"
> $env:GITHUB_TOKEN = "ghp_xxxx"
> ```
>
> **Windows (CMD):**
> ```cmd
> set MIRROR_LOCAL_ROOT=Z:\
> set GITHUB_TOKEN=ghp_xxxx
> ```
>
> **Linux/macOS:**
> ```bash
> export MIRROR_LOCAL_ROOT="/mirrors"
> export GITHUB_TOKEN="ghp_xxxx"
> ```
>
> 永久生效：添加到 `~/.bashrc`、`~/.zshrc` 或系统环境变量。

# GitHub Release 下载脚本生成器

这个 skill 帮你快速为任何 GitHub 项目生成完整的 Release 下载脚本，包括：
1. **下载脚本** - 功能完整的下载工具
2. **入口脚本** - 简化的统一调用入口

## 何时使用

- 用户需要下载 GitHub 项目的 release 二进制文件
- 用户说"帮我写个下载脚本"、"创建安装脚本"
- 用户说"参照 containerd-downloader.sh 给 nerdctl 写个类似的"
- 用户想批量下载某个项目的所有版本

## 脚本特性

### 下载脚本 ({name}-downloader.sh)

1. **从 GitHub API 获取所有版本** - 支持分页获取
2. **过滤稳定版本** - 排除 rc/beta/alpha 预发布版本
3. **双架构支持** - amd64 和 arm64
4. **文件完整性验证** - tar.gz 用 `tar -tf`，纯二进制用 `stat` + `file`
5. **代理支持** - 通过 `-p` 参数设置
6. **GitHub Token** - 避免 API 限流
7. **Dry-run 模式** - 预览将下载的文件
8. **验证模式** - 下载后验证文件完整性

### 入口脚本 (download.sh)

统一入口脚本，用于简化日常使用：
- 自动获取脚本所在目录
- 预配置代理和 Token
- 直接执行下载

## 工作流程

### 1. 收集项目信息

向用户询问以下信息：

- **GitHub 仓库** - owner/repo 格式（如 containerd/containerd）
- **二进制文件名模式** - 需要了解项目的 release 文件命名规则
- **文件类型** - tar.gz 压缩包还是纯二进制文件
- **输出目录** - 脚本保存位置

如果用户不确定文件名模式，使用 `scripts/check_release_files.sh` 来检查。

### 2. 确定输出路径（重要！）

**正确处理输出目录：**

1. **获取用户工作目录** - 使用 `pwd` 命令获取当前工作目录
2. **解析用户指定的路径**：
   - 如果用户指定绝对路径，直接使用
   - 如果用户指定相对路径（如 `runtime/docker_tools/image-syncer`），拼接用户工作目录
   - 如果用户没指定，默认为当前工作目录

3. **创建目录时使用用户工作目录作为基准**：
   ```bash
   # 示例：用户工作目录是 ${MIRROR_LOCAL_ROOT}，用户指定 runtime/docker_tools/image-syncer
   # 最终路径应该是 ${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer
   # 而不是 .claude/projects/z--soft/runtime/docker_tools/image-syncer
   ```

如果用户没有指定目录，询问：

```
请输入脚本输出目录 [默认: 当前工作目录]:
```

### 3. 生成下载脚本

**重要：完全按照 nerdctl-downloader.sh 模板生成！**

首先读取参考模板。使用 mirror-file-manager skill 获取模板的本地路径：

1. **获取模板 URL**：
   - 模板 base URL：`http://mirrors.lpx.com/soft/runtime/`
   - nerdctl 模板：`http://mirrors.lpx.com/soft/runtime/nerdctl/nerdctl-downloader.sh`
   - containerd 模板：`http://mirrors.lpx.com/soft/runtime/containerd/containerd-downloader.sh`
   - runc 模板：`http://mirrors.lpx.com/soft/runtime/runc/runc-downloader.sh`

2. **转换为本地路径** - 使用 mirror-file-manager skill：
   - 将 `http://mirrors.lpx.com` 替换为 `${MIRROR_LOCAL_ROOT}`（注意路径分隔符转换）
   - 示例：`http://mirrors.lpx.com/soft/runtime/nerdctl/nerdctl-downloader.sh`
     → `${MIRROR_LOCAL_ROOT}\soft\runtime\nerdctl\nerdctl-downloader.sh`

**必须遵守的关键规则：**

0. **必需环境变量检查** - 脚本开头必须检查：
   ```bash
   # 检查必需的环境变量
   if [[ -z "${GITHUB_TOKEN}" ]]; then
       log_error "GITHUB_TOKEN 环境变量未设置"
       exit 1
   fi

   if [[ -z "${PROXY}" ]]; then
       log_error "PROXY 环境变量未设置"
       exit 1
   fi
   ```

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

**关键：确定正确的输出目录**

首先获取用户的实际工作目录（不是 `.claude/projects` 目录）：
```bash
# 获取工作目录
WORK_DIR=$(pwd)
# 如果路径包含 .claude/projects，说明在错误的目录，需要切换
if [[ "$WORK_DIR" =~ .*\.claude/projects.* ]]; then
    # 尝试获取用户指定的实际工作目录
    # 通常用户会在命令中指定相对路径，如 runtime/docker_tools/image-syncer
    WORK_DIR="${MIRROR_LOCAL_ROOT}"  # 或者从其他上下文推断
fi
```

用户指定的输出目录处理：
```bash
# 用户指定目录（如 runtime/docker_tools/image-syncer）
USER_DIR="runtime/docker_tools/image-syncer"

# 拼接完整路径（使用用户工作目录作为基准）
OUTPUT_DIR="${WORK_DIR}/${USER_DIR}"

# 如果用户指定了绝对路径，直接使用
if [[ "$USER_DIR" = /* ]]; then
    OUTPUT_DIR="$USER_DIR"
fi
```

根据项目类型选择模板：

- **tar.gz 压缩包** - 参考模板 containerd-downloader.sh
- **纯二进制文件** - 参考模板 runc-downloader.sh

关键修改点：

| 变量 | 说明 |
|------|------|
| `SCRIPT_NAME` | 脚本名称（如 nerdctl-downloader） |
| `REPO_OWNER` | GitHub 用户名/组织 |
| `REPO_NAME` | 仓库名称 |
| `DOWNLOAD_DIR` | 默认下载目录（如 ./nerdctl_binaries） |
| `get_download_url()` | 根据项目文件命名规则修改 |
| `verify_*()` | tar.gz 用 `verify_tarball()`，纯文件用 `verify_binary()` |
| `filter_stable_versions()` | 某些项目需要排除特殊格式 |

### 4. 生成入口脚本 (download.sh)

入口脚本模板（完全按照 nerdctl/download.sh 格式）：

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


# 判断是否带 -n
EXTRA_ARGS=""
if [[ "$1" == "-n" ]]; then
    EXTRA_ARGS="-n"
fi

# 可以保留注释的旧命令作为备份
#bash {name}-downloader.sh -p http://192.168.0.225:7897 -t xxxx -V -d ${CURRENT_DIR}

bash {name}-downloader.sh -p "${HTTPS_PROXY}" -t "${GITHUB_TOKEN}" -V -d "${CURRENT_DIR}" ${EXTRA_ARGS}
```

**入口脚本说明：**
- `CURRENT_DIR` - 获取脚本所在目录的绝对路径
- **必须设置 `HTTPS_PROXY`** - 不存在则直接退出
- **必须设置 `GITHUB_TOKEN`** - 不存在则直接退出
- 使用环境变量设置代理和 Token
- 启用验证模式：`-V`
- 下载到脚本所在目录
- **重要：变量必须加引号**，避免空变量导致参数解析错误

### 5. 输出文件结构

生成的文件结构：

```
{output_dir}/
├── {name}-downloader.sh    # 完整下载脚本
└── download.sh             # 统一入口脚本
```

**重要：确保输出目录正确**

脚本必须直接写入用户指定的工作目录，而不是 `.claude/projects` 目录。

示例检查：
```bash
# 错误的路径（不要这样）
/c/Users/lipanx/.claude/projects/z--soft/runtime/docker_tools/image-syncer/

# 正确的路径（应该这样）
${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer/
```

如果发现脚本被写入错误的目录，需要将文件移动到正确位置：
```bash
# 从错误位置复制到正确位置
cp /c/Users/lipanx/.claude/projects/z--soft/runtime/docker_tools/image-syncer/*.sh \
   ${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer/
```

### 6. 验证和测试

生成的脚本应该：

1. 添加可执行权限：
   ```bash
   chmod +x {name}-downloader.sh download.sh
   ```

2. 先用 dry-run 模式测试：使用入口脚本模拟测试
   ```bash
   ./download.sh -n
   ```
   只要模式测试通过，就说明脚本可以交付了，不需要其他测试了

## 文件命名规则示例

| 项目 | 文件模式 | 说明 |
|------|----------|------|
| containerd | `containerd-{version}-linux-{arch}.tar.gz` | 标准命名 |
| runc | `runc.{arch}` | 直接可执行文件 |
| nerdctl | `nerdctl-{version}-linux-{arch}.tar.gz` | 包含 OS |
| kubectl | `kubectl` (单文件) | 所有架构同名，需处理 |
| helm | `helm-{version}-linux-{arch}.tar.gz` | 包含 OS |

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

## 检查 Release 文件

使用 `scripts/check_release_files.sh` 快速查看项目的 release 文件命名：

```bash
bash scripts/check_release_files.sh <owner> <repo> [tag]
```

例如：
```bash
bash scripts/check_release_files.sh containerd containerd v1.7.0
```

## 完成后

1. **验证脚本位置** - 确保脚本不在 `.claude/projects` 目录：
   ```bash
   # 错误示例 - 如果发现脚本在这里，需要移动
   /c/Users/lipanx/.claude/projects/z--soft/...

   # 正确位置 - 用户的工作目录
   ${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer/
   ```

2. **将生成的两个脚本保存到用户指定目录**

3. **告知用户如何使用**：
   ```bash
   # 方式1：使用入口脚本（推荐）
   ./download.sh

   # 方式2：直接使用下载脚本
   ./{name}-downloader.sh --help
   ./{name}-downloader.sh -n              # dry-run 模式
   ./{name}-downloader.sh -p "${HTTPS_PROXY}"  # 使用代理
   ./{name}-downloader.sh -t "${GITHUB_TOKEN}" -V   # 使用 token 并验证
   ```

4. 如果用户有测试机器，建议先在测试环境验证

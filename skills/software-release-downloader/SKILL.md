---
name: software-release-downloader
description: 自动生成 GitHub Release 下载脚本和统一入口脚本。当用户需要为任何 GitHub 项目（如 containerd, runc, nerdctl, kubectl, helm, terraform 等）创建下载脚本的完整工作流时使用。也适用于用户说"帮我写个下载脚本"、"参照 X 脚本写 Y 脚本"、"给这个项目写个下载器"等场景。
---

> ⚠️ **首次使用需设置环境变量**
>
> **Windows (PowerShell):**
> ```powershell
> $env:MIRROR_LOCAL_ROOT = "Z:\"
> $env:GITHUB_TOKEN = "ghp_xxxx"
> $env:HTTPS_PROXY = "http://192.168.0.225:7897"
> ```
>
> **Linux/macOS:**
> ```bash
> export MIRROR_LOCAL_ROOT="/mirrors"
> export GITHUB_TOKEN="ghp_xxxx"
> export HTTPS_PROXY="http://192.168.0.225:7897"
> ```
>
> 永久生效：添加到 `~/.bashrc`、`~/.zshrc` 或系统环境变量。

# GitHub Release 下载脚本生成器

本 skill 指导完成从脚本编写到测试验证的完整工作流。

---

## 背景说明

### 文件服务器架构

本项目使用内网文件服务器（`http://mirrors.lpx.com`）存储软件和脚本，并通过 `${MIRROR_LOCAL_ROOT}`（Windows: `Z:\`，Linux: `/mirrors`）挂载到本地。

| 类型 | 本地路径 | 访问方式 |
|------|---------|---------|
| 脚本模板 | `${MIRROR_LOCAL_ROOT}\soft\runtime\{tool}` | 直接读取本地文件 |
| 内网软件 | `${MIRROR_LOCAL_ROOT}\soft\{path}` | 直接读取本地文件 |
| 脚本 URL | `http://mirrors.lpx.com/soft/runtime/{path}` | 远程执行时使用 |

### 核心原则

1. **先搜索，后假设** - 使用 Everything Search 直接搜索本地挂载目录
2. **最小改动** - 参照模板，只修改工具特定的部分
3. **完整测试** - dry-run 测试是必须的

---

## 工作流程

| 阶段 | 任务 | 关键输出 |
|------|------|---------|
| 1 | 信息收集 | 模板路径、目标路径、项目信息 |
| 2 | 脚本编写 | `{name}-downloader.sh` + `download.sh` |
| 3 | 文档编写 | `README.md` |
| 4 | 测试验证 | dry-run 测试通过 |
| 5 | 上传验证 | 确认文件服务器可访问 |

---

## 阶段详情

- [阶段 1: 信息收集](./references/01-information.md)
- [阶段 2: 脚本编写](./references/02-scripting.md)
- [阶段 3: 文档编写](./references/03-documentation.md)
- [阶段 4: 测试验证](./references/04-testing.md)
- [阶段 5: 上传验证](./references/05-upload.md)

---

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

---

## 常用工具配置参考

| 工具 | GitHub 仓库 | 文件模式 | 类型 |
|------|-------------|----------|------|
| containerd | containerd/containerd | `containerd-{version}-linux-{arch}.tar.gz` | tar.gz |
| runc | opencontainers/runc | `runc.{arch}` | 二进制 |
| nerdctl | containerd/nerdctl | `nerdctl-{version}-linux-{arch}.tar.gz` | tar.gz |
| kubectl | kubernetes/kubernetes | `kubectl` | 单文件 |
| helm | helm/helm | `helm-{version}-linux-{arch}.tar.gz` | tar.gz |
| terraform | hashicorp/terraform | `terraform_{version}_linux_{arch}.zip` | zip |

> ⚠️ 上表是参考，实际文件模式以阶段 1 搜索结果为准。

---

## 模板位置

| 模板 | 本地路径 |
|------|---------|
| nerdctl | `${MIRROR_LOCAL_ROOT}\soft\runtime\nerdctl\nerdctl-downloader.sh` |
| containerd | `${MIRROR_LOCAL_ROOT}\soft\runtime\containerd\containerd-downloader.sh` |
| runc | `${MIRROR_LOCAL_ROOT}\soft\runtime\runc\runc-downloader.sh` |

---

## 检查 Release 文件

使用 `scripts/check_release_files.sh` 快速查看项目的 release 文件命名：

```bash
bash scripts/check_release_files.sh <owner> <repo> [tag]
```

例如：
```bash
bash scripts/check_release_files.sh containerd containerd v1.7.0
```

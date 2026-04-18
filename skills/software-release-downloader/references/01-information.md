# 阶段 1: 收集项目信息

## 何时使用

- 用户需要下载 GitHub 项目的 release 二进制文件
- 用户说"帮我写个下载脚本"、"创建安装脚本"
- 用户说"参照 containerd-downloader.sh 给 nerdctl 写个类似的"
- 用户想批量下载某个项目的所有版本

## 收集项目信息

向用户询问以下信息：

- **GitHub 仓库** - owner/repo 格式（如 containerd/containerd）
- **二进制文件名模式** - 需要了解项目的 release 文件命名规则
- **文件类型** - tar.gz 压缩包还是纯二进制文件
- **输出目录** - 脚本保存位置

如果用户不确定文件名模式，使用 `scripts/check_release_files.sh` 来检查。

## 常用项目参考

| 项目 | GitHub 仓库 | 文件模式 | 说明 |
|------|-------------|----------|------|
| containerd | containerd/containerd | `containerd-{version}-linux-{arch}.tar.gz` | tar.gz 压缩包 |
| runc | opencontainers/runc | `runc.{arch}` | 纯二进制文件 |
| nerdctl | containerd/nerdctl | `nerdctl-{version}-linux-{arch}.tar.gz` | tar.gz 压缩包 |
| kubectl | kubernetes/kubernetes | `kubectl` | 单文件，所有架构同名 |
| helm | helm/helm | `helm-{version}-linux-{arch}.tar.gz` | tar.gz 压缩包 |
| terraform | hashicorp/terraform | `terraform_{version}_linux_{arch}.zip` | zip 压缩包 |

## 检查 Release 文件

使用 `scripts/check_release_files.sh` 快速查看项目的 release 文件命名：

```bash
bash scripts/check_release_files.sh <owner> <repo> [tag]
```

例如：
```bash
bash scripts/check_release_files.sh containerd containerd v1.7.0
```

## 环境变量检查

确保用户已设置必需的环境变量：

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

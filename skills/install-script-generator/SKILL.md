---
name: install-script-generator
description: 自动生成 Linux 二进制工具安装脚本的完整工作流。当用户需要为任何二进制工具（containerd, runc, nerdctl, kubectl, helm, terraform 等）编写安装脚本时使用。也适用于用户说"帮我写个安装脚本"、"参照 X 脚本写 Y 脚本"等场景。
---

# 二进制安装脚本生成器

本 skill 指导完成从脚本编写到测试验证的完整工作流。

---

## 背景说明

### 文件服务器架构

本项目使用内网文件服务器（`http://mirrors.lpx.com`）存储软件和脚本，并通过 `${MIRROR_LOCAL_ROOT}`（Windows: `Z:\`，Linux: `/mirrors`）挂载到本地。

| 类型 | 本地路径 | 访问方式 |
|------|---------|---------|
| 脚本模板 | `${MIRROR_LOCAL_ROOT}\scripts\runtime\{tool}` | 直接读取本地文件 |
| 内网软件 | `${MIRROR_LOCAL_ROOT}\soft\{path}` | 直接读取本地文件 |
| 脚本 URL | `http://mirrors.lpx.com/scripts/{path}` | 远程执行时使用 |


### 核心原则

1. **先搜索，后假设** - 使用 Everything Search 直接搜索本地挂载目录，不需要逐级 curl 确认
2. **最小改动** - 参照模板，只修改工具特定的部分
3. **完整测试** - 内网测试是必须的

---

## 工作流程

| 阶段 | 任务 | 关键输出 |
|------|------|---------|
| 1 | 信息收集 | 模板路径、目标路径、内网 URL、内网文件名 |
| 2 | 脚本编写 | `install_{tool}.sh` |
| 3 | 文档编写 | `README.md` |
| 4 | 远程测试 | 验证安装成功 |
| 5 | 上传验证 | 确认文件服务器可访问 |

- 远程测试： **使用 ssh-mcp-server MCP 连接测试服务器：`${TEST_NODE_IP}`**  : 
如果测试${TEST_NODE_IP}不存在，提示用户设置，如果测试${TEST_NODE_IP}存在，则必须执行远程测试步骤

---

## 阶段详情

- [阶段 1: 信息收集](./references/01-information.md)
- [阶段 2: 脚本编写](./references/02-scripting.md)
- [阶段 3: 文档编写](./references/03-documentation.md)
- [阶段 4: 远程测试](./references/04-testing.md)
- [阶段 5: 上传验证](./references/05-upload.md)

---

## 环境变量

> ⚠️ **首次使用需设置**

**Windows (PowerShell):**
```powershell
$env:MIRROR_LOCAL_ROOT = "Z:\"
$env:GITHUB_TOKEN = "ghp_xxxx"
$env:MIRROR_INTRANET_BASE_URL="http://mirrors.xx.com"
$env:TEST_NODE_IP='192.168.x.x'

```

**Linux/macOS:**
```bash
export MIRROR_LOCAL_ROOT="/mirrors"
export GITHUB_TOKEN="ghp_xxxx"
export MIRROR_INTRANET_BASE_URL="http://mirrors.xx.com"
export TEST_NODE_IP='192.168.x.x'
```

---

## 常见工具配置参考

| 工具 | GitHub 仓库 | 内网文件路径 | 内网文件名 |
|------|-------------|--------------|------------|
| kubectl | kubernetes/kubernetes | `soft/k8s/kubectl` | `kubectl.{arch}` |
| helm | helm/helm | `soft/{path}` | `helm-{version}-linux-{arch}.tar.gz` |
| terraform | hashicorp/terraform | `soft/{path}` | `terraform_{version}_linux_{arch}.zip` |
| runc | opencontainers/runc | `soft/runtime/runc` | `runc.{arch}` |
| nerdctl | opencontainers/nerdctl | `soft/runtime/nerdctl` | `nerdctl-{version}-linux-{arch}.tar.gz` |
| kind | kubernetes-sigs/kind | `soft/{path}` | `kind-linux-{arch}` |
| crictl | kubernetes-sigs/cri-tools | `soft/{path}` | `crictl-{version}-linux-{arch}.tar.gz` |
| buildkit | moby/buildkit | `soft/{path}` | `buildkit-v{version}.linux-{arch}.tar.gz` |

> ⚠️ 上表是参考，实际路径和文件名以阶段 1 搜索结果为准。

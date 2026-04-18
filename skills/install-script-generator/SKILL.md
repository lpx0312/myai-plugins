---
name: install-script-generator
description: 自动生成 Linux 二进制工具安装脚本的完整工作流。当用户需要为任何二进制工具（containerd, runc, nerdctl, kubectl, helm, terraform 等）编写安装脚本时使用。也适用于用户说"帮我写个安装脚本"、"参照 X 脚本写 Y 脚本"等场景。
---

# 二进制安装脚本生成器

本 skill 指导完成从脚本编写到测试验证的完整工作流。


 ⚠️ **首次使用需设置环境变量**
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



## 工作流程

### 阶段 1: 信息收集

首先确认以下信息：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `TOOL_NAME` | 工具名称（如 runc, kubectl） | - |
| `TEMPLATE_PATH` | 参考模板路径 | 自动选择 |
| `VERSION` | 默认安装版本 | 最新稳定版 |
| `TARGET_DIR` | 输出目录 | `runtime/{tool_name}` |
| `INTRANET_BASE` | 内网基础URL | - |
| `EXTRANET_BASE` | 外网基础URL | - |

#### 1.1 获取模板路径
**参考模板选择规则：**
- Docker 生态工具 → `runtime/nerdctl/install_nerdctl.sh`
- 单二进制文件 → `runtime/runc/install_runc.sh`
- 复杂工具 → `runtime/containerd/install_containerd.sh`

1. **获取模板 URL**：
   - 模板 base URL：`http://mirrors.lpx.com/scripts/runtime/`
   - nerdctl 模板：`http://mirrors.lpx.com/scripts/runtime/nerdctl/install_nerdctl.sh`
   - containerd 模板：`http://mirrors.lpx.com/scripts/runtime/containerd/install_containerd.sh`
   - runc 模板：`http://mirrors.lpx.com/scripts/runtime/runc/install_runc.sh`

2. **转换为本地路径** - 使用 mirror-file-manager skill：
   - 将 `http://mirrors.lpx.com` 替换为 `${MIRROR_LOCAL_ROOT}`（注意路径分隔符转换）
   - 示例：`http://mirrors.lpx.com/scripts/runtime/nerdctl/install_nerdctl.sh`
     → `${MIRROR_LOCAL_ROOT}\soft\runtime\nerdctl\install_nerdctl.sh`

- 注意: 如果mirrors.lpx.com 域名无法访问，可以使用mirror-file-manager skill 来变化成内网IP地址

#### 1.2 获取脚本输出路径（重要！）
**确定输出路径（重要！）**

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

#### 1.3 获取内网软件基础URL: INTRANET_BASE
**确定内网软件基础URL: INTRANET_BASE（重要！）**
**默认值：** `http://mirrors.lpx.com/soft/runtime/{tool_name}`
- 如果用户没有指定，默认使用默认值。
- 如果用户指定的不存在,就在http://mirrors.lpx.com/soft($MIRROR_LOCAL_ROOT/soft) 这个下面查找
     例如: 比如需要安装软件名称是nerdctl, 查找到soft下 有 runtime/nerdctl/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz 文件 ， 则 INTRANET_BASE 就是 `http://mirrors.lpx.com/soft/runtime/nerdctl`

#### 1.4 获取内网软件文件名格式和路径
**确定内网软件文件名格式和路径（重要！）**

具体的文件名和路径，可以根据 1.3 获取的 INTRANET_BASE 的过程中来确定，例如：
     例如: 查找到soft下 有 runtime/nerdctl/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz 文件 ，则文件名就是 `${tool}-${version}-linux-${arch}.tar.gz`
          文件路径就是 `${INTRANET_BASE}/v${version}/${tool}-${version}-linux-${arch}.tar.gz`


#### 1.5 获取外网软件基础URL: EXTRANET_BASE  

外网基础URL: EXTRANET_BASE 
两种方法:
1. 根据用户指定的 GitHub 仓库来确定。例如：
     例如: 如果用户指定的 GitHub 仓库是 opencontainers/runc, 则 EXTRANET_BASE 就是 `https://github.com/opencontainers/runc/releases/download/v1.5.0-rc.2/runc.amd64` 则 EXTRANET_BASE 就是 `https://github.com/opencontainers/runc/releases/download` 还需要使用curl -I 来确认是否可以访问

2. 根据内网软件对应的下载脚本来确认：
    比如需要安装软件名称是nerdctl, 查找到soft下 有 runtime/nerdctl/install_nerdctl.sh 文件, 这个就是内网软件的下载脚本，分析这个脚本就可以确定 EXTRANET_BASE 是 `https://github.com/opencontainers/nerdctl/releases/download`
    路径就是：v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz

#### 1.6 获取下载的软件的内部结构

根据 1.3 找到的runtime/nerdctl/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz,可以使用tar -tf 来查看内部结构
```bash
tar -tf runtime/nerdctl/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz
```
后续编写安装脚本的时候 需要用到

### 阶段 2: 脚本编写

**核心原则：** 参照模板，只做最小必要修改。

**必须修改的变量：**
```bash
# 工具名称全大写
TOOL_NAME="runc"        # → RUNC

# 文件名格式
# 参考：1.6 获取下载的软件的内部结构
#  一般情况
# - tar.gz 包: {tool}-{version}-linux-{arch}.tar.gz
# - 单二进制: {tool}.{arch}  (如 runc.amd64)

# 内网镜像路径
INTRANET_BASE="http://192.168.0.180:8082/soft/runtime/{tool_name}"
```

**可选参数（如需要）：**
- `GITHUB_TOKEN` - GitHub API 认证
- `HTTP_PROXY` - 代理设置

**脚本是固定结构，按顺序包含：**
1. 默认配置区（变量定义）
2. 颜色输出函数
3. 帮助信息（usage）
4. 参数解析（parse_args）
5. 架构检测（detect_arch）
6. 网络检测（detect_network）
7. URL 构建（build_{tool}_url）
8. 主逻辑（main）

### 阶段 3: 文档编写

**完全参照** `runtime/nerdctl/README.md` 的结构和格式。

**必须包含的部分：**
1. YAML frontmatter（创建日期、更新时间、标签等）
2. 概述和脚本地址
3. 支持的配置（版本、架构）
4. 处理流程图
5. 命令行参数表
6. 使用方法（本地执行、远程调用）
7. 快速参考表
8. 安装目录结构
9. 网络检测逻辑说明
10. 系统要求
11. 注意事项
12. 故障排查
13. 版本管理
14. 高级用法
15. 工具基础用法
16. 相关资源
17. 更新日志

**搜索替换规则：**
```
nerdctl → {TOOL_NAME}
containerd/nerdctl → {runtime_dir}/{tool_name}
Docker → 相关上下文（保持一致性）
```

### 阶段 4: 远程测试

**测试服务器：** `192.168.1.182`

**测试命令格式：**
```bash
# 内网测试
curl -sSL http://mirrors.lpx.com/scripts/runtime/{tool_name}/install_{tool_name}.sh | sudo bash -s -- -v {version} -n in

# 外网测试（需要代理）
export http_proxy=http://192.168.0.4:7890
export https_proxy=http://192.168.0.4:7890
curl -sSL http://mirrors.lpx.com/scripts/runtime/{tool_name}/install_{tool_name}.sh | sudo bash -s -- -v {version} -n out -t ${GITHUB_TOKEN} -p http://192.168.0.4:7890
```

**测试步骤：**
1. 使用 `ssh-mcp-server` MCP 连接到测试服务器
2. 使用 `mirror-file-manager` MCP 获取脚本的内网地址
3. 执行内网测试（至少）
4. 如需外网测试，设置代理和 token
5. 验证安装结果：`{tool_name} version` 或类似命令

**遇到问题时：**
- 修改脚本
- 重新上传到文件服务器
- 更新 README.md（如有使用说明变化）
- 重新测试

### 阶段 5: 文件服务器上传
- 确认编写完成的安装脚本，是否在文件服务器上=
**目标结构：**
```
$MIRROR_LOCAL_ROOT/scripts/runtime/{tool_name}/
├── install_{tool_name}.sh
└── README.md
```

## 输出文件
完成后应生成：
```
runtime/{tool_name}/
├── install_{tool_name}.sh  # 安装脚本
└── README.md               # 使用文档
```

## 常见工具配置

| 工具 | GitHub 仓库 | 文件名格式 |
|------|-------------|-----------|
| kubectl | kubernetes/kubernetes | kubectl |
| helm | helm/helm | helm-{version}-linux-{arch}.tar.gz |
| terraform | hashicorp/terraform | terraform_{version}_linux_{arch}.zip |
| kind | kubernetes-sigs/kind | kind-linux-{arch} |
| crictl | kubernetes-sigs/cri-tools | crictl-{version}-linux-{arch}.tar.gz |
| buildkit | moby/buildkit | buildkit-v{version}.linux-{arch}.tar.gz |

## 注意事项

1. **保持一致性** - 脚本风格与模板完全一致
2. **最小改动** - 只修改工具特定的部分
3. **完整测试** - 内外网至少测试一种
4. **文档同步** - README.md 与脚本功能保持一致
5. **错误处理** - 保留模板中的所有错误检查逻辑

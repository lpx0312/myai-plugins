---
name: install-script-generator
description: 自动生成 Linux 二进制工具安装脚本的完整工作流。当用户需要为任何二进制工具（containerd, runc, nerdctl, kubectl, helm, terraform 等）编写安装脚本时使用。也适用于用户说"帮我写个安装脚本"、"参照 X 脚本写 Y 脚本"等场景。
---

# 二进制安装脚本生成器

本 skill 指导完成从脚本编写到测试验证的完整工作流。

## 工作流程

### 阶段 1: 信息收集

首先确认以下信息：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `TOOL_NAME` | 工具名称（如 runc, kubectl） | - |
| `TEMPLATE_PATH` | 参考模板路径 | 自动选择 |
| `GITHUB_REPO` | GitHub 仓库（如 opencontainers/runc） | - |
| `VERSION` | 默认安装版本 | 最新稳定版 |
| `TARGET_DIR` | 输出目录 | `runtime/{tool_name}` |

**参考模板选择规则：**
- Docker 生态工具 → `runtime/nerdctl/install_nerdctl.sh`
- 单二进制文件 → `runtime/runc/install_runc.sh`
- 复杂工具 → `runtime/containerd/install_containerd.sh`

### 阶段 2: 脚本编写

**核心原则：** 参照模板，只做最小必要修改。

**必须修改的变量：**
```bash
# 工具名称全大写
TOOL_NAME="runc"        # → RUNC

# GitHub 仓库
GITHUB_REPO="opencontainers/runc"

# 文件名格式
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
curl -sSL http://192.168.0.180:8082/scripts/runtime/{tool_name}/install_{tool_name}.sh | sudo bash -s -- -v {version} -n in

# 外网测试（需要代理）
export http_proxy=http://192.168.0.4:7890
export https_proxy=http://192.168.0.4:7890
curl -sSL http://192.168.0.180:8082/scripts/runtime/{tool_name}/install_{tool_name}.sh | sudo bash -s -- -v {version} -n out -t ${GITHUB_TOKEN} -p http://192.168.0.4:7890
```

**测试步骤：**
1. 使用 `m-ssh` MCP 连接到测试服务器
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

**使用 mirror-file-manager MCP：**
1. 搜索本地文件位置
2. 确认目标路径
3. 复制文件到 Z 盘对应目录

**目标结构：**
```
Z:/scripts/runtime/{tool_name}/
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

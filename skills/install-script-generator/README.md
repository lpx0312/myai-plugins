# install-script-generator

自动化安装脚本生成器 - 用于生成支持内网/外网环境的安装脚本。

## 概述

本 skill 用于生成标准化的安装脚本，支持多种工具的自动化安装，包括：
- Node.js
- nerdctl (Docker 兼容 CLI)
- runc (OCI 运行时)
- Helm (Kubernetes 包管理器)

## 目录结构

```
install-script-generator/
├── SKILL.md                    # 主技能文件
├── README.md                   # 本文档
├── assets/
│   ├── docs/
│   │   └── README.md          # 文档模板
│   └── templates/
│       ├── install_node.sh    # Node.js 安装模板
│       ├── install_nerdctl.sh  # nerdctl 安装模板
│       ├── install_runc.sh     # runc 安装模板
│       └── install_helm.sh     # Helm 安装模板
├── references/
│   ├── 01-information.md      # 阶段 1: 信息收集
│   ├── 02-scripting.md        # 阶段 2: 脚本编写
│   ├── 03-documentation.md     # 阶段 3: 文档编写
│   ├── 04-testing.md          # 阶段 4: 远程测试
│   └── 05-upload.md           # 阶段 5: 上传验证
└── evals/
    └── evals.json             # 评估测试用例
```

## 工作流程

### 阶段 1: 信息收集

收集目标工具的关键信息：

| 信息项 | 说明 |
|--------|------|
| TOOL_NAME | 工具名称（如 nerdctl, node） |
| CATEGORY | 分类（如 runtime, language） |
| GITHUB_REPO | GitHub 仓库地址 |
| VERSION_URL | 版本信息获取地址 |
| DOWNLOAD_PATTERN | 下载 URL 模式 |
| ARCH_MAP | 架构映射关系 |
| OUTPUT_DIR | 输出目录 |

### 阶段 2: 脚本编写

基于模板生成脚本，关键特性：

- **CLI 参数解析**: getopt 风格，支持 `-v`, `-a`, `-n`, `-u`, `-d` 等参数
- **网络检测**: 自动检测内网/外网环境
- **架构检测**: 自动检测 x64/arm64 架构
- **HTTP 代理支持**: `-t`, `-p` 参数支持代理
- **版本管理**: 软链接方式的版本切换
- **下载校验**: 文件大小检查

#### 模板变量

| 变量 | 说明 |
|------|------|
| `{TOOL_NAME}` | 工具名称 |
| `{UPPER_TOOL}` | 大写工具名 |
| `{VERSION_VAR}` | 版本变量名 |
| `{ARCH}` | 架构 |
| `{CATEGORY}` | 分类 |
| `{INSTALL_DIR}` | 安装目录 |
| `{DOWNLOAD_DIR}` | 下载目录 |

### 阶段 3: 文档编写

生成标准化的 README 文档，必须包含：

1. YAML frontmatter（创建日期、标签等）
2. 概述和脚本地址
3. 支持的配置（版本、架构）
4. 处理流程图
5. 命令行参数表
6. 使用方法
7. 快速参考表
8. 安装目录结构
9. 网络检测逻辑
10. 系统要求
11. 故障排查
12. 版本管理

### 阶段 4: 远程测试

在测试服务器上验证脚本：

```bash
# 内网测试
curl -sSL ${IN_SH_URL} | sudo bash -s -- -v {version} -n in

# 外网测试（带代理）
export HTTP_PROXY=${HTTP_PROXY}
curl -sSL ${IN_SH_URL} | sudo bash -s -- -v {version} -n out -t ${GITHUB_TOKEN} -p ${HTTP_PROXY}
```

### 阶段 5: 上传验证

确认脚本已上传到内网文件服务器：
- 本地路径: `${MIRROR_LOCAL_ROOT}\{OUTPUT_DIR}\install_{tool}.sh`
- 访问 URL: `${INTRANET_BASE_URL}\{OUTPUT_DIR}\install_{tool}.sh`

## 模板特性对比

| 特性 | install_node.sh | install_nerdctl.sh | install_runc.sh | install_helm.sh |
|------|-----------------|---------------------|------------------|------------------|
| CLI 参数解析 | ✅ | ✅ | ✅ | ✅ |
| 内网检测 | ✅ | ✅ | ✅ | ✅ |
| 架构检测 | ✅ | ✅ | ✅ | ✅ |
| HTTP 代理 | ✅ | ✅ | ✅ | ✅ |
| 版本管理 | ✅ | ✅ | ✅ | ✅ |
| 软链接安装 | ✅ | ✅ | ✅ | ✅ |
| Bash 补全 | ✅ | ✅ | - | - |
| 校验和验证 | - | - | ✅ | - |

## 通用命令行参数

| 参数 | 长参数 | 说明 |
|------|--------|------|
| `-v` | `--version` | 工具版本（必需） |
| `-a` | `--arch` | 系统架构 (x64, arm64) |
| `-n` | `--network` | 网络类型 (in, out) |
| `-u` | `--url` | 直接指定下载 URL |
| `-d` | `--dir` | 安装目录 |
| `-t` | `--token` | GitHub Token（外网用） |
| `-p` | `--proxy` | HTTP 代理 |
| `--download-dir` | - | 下载目录 |
| `--keep-package` | - | 保留安装包 |
| `--debug` | - | 调试模式 |
| `-h` | `--help` | 显示帮助 |

## 内网镜像地址

| 服务器 | 地址 |
|--------|------|
| 内网文件服务器 | `http://192.168.0.180:8082` |
| 内网镜像根目录 | `/path/to/mirror` |

## 使用方法

### 生成新工具的安装脚本

1. **收集信息**：确定工具的 GitHub 仓库、下载模式、版本格式
2. **选择模板**：根据工具类型选择最接近的模板
3. **替换变量**：将模板中的占位符替换为实际值
4. **测试验证**：在测试服务器上运行脚本
5. **上传部署**：发布到内网文件服务器

### 使用现有脚本

```bash
# 安装 Node.js
curl -sSL http://192.168.0.180:8082/scripts/language/node/install_node.sh | sudo bash -s -- -v 20.11.0 -n in

# 安装 nerdctl
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n in

# 安装 runc
curl -sSL http://192.168.0.180:8082/scripts/runtime/runc/install_runc.sh | sudo bash -s -- -v 1.1.12 -n in

# 安装 Helm
curl -sSL http://192.168.0.180:8082/scripts/runtime/helm/install_helm.sh | sudo bash -s -- -v 3.14.0 -n in
```

## 脚本输出位置规范

```
scripts/
├── runtime/
│   ├── nerdctl/
│   │   ├── install_nerdctl.sh
│   │   └── README.md
│   ├── runc/
│   │   ├── install_runc.sh
│   │   └── README.md
│   └── helm/
│       ├── install_helm.sh
│       └── README.md
└── language/
    └── node/
        ├── install_node.sh
        └── README.md
```

## 评估测试

参考 `evals/evals.json` 中的测试用例验证脚本功能：
- 参数解析测试
- 网络检测测试
- 下载功能测试
- 安装目录验证
- 版本切换测试

# 阶段 2: 脚本编写

**输入：** 阶段 1 收集的信息
**输出：** `install_{tool}.sh`
**输出目录**: 从 阶段 1 获取的 OUTPUT_DIR
**脚本的本地内网服务器路径**: `LOCAL_SH_PATH = ${MIRROR_LOCAL_ROOT}\{OUTPUT_DIR}\install_{tool}.sh`
**脚本的本地内网服务器URL**: `IN_SH_URL = ${MIRROR_INTRANET_BASE_URL}\{OUTPUT_DIR}\install_{tool}.sh`

---

## 2.0 模板概览

> **路径约定**：
> - 模板目录：`assets/templates`

---

## 2.1 模板选择原则

### 2.1.1 选择基础模板

按**分发形式**选择最接近的模板作为基础：

| 分发形式 | 基础模板 | 说明 |
|---------|---------|------|
| 单文件（直接可执行） | `install_runc.sh` | 下载 → chmod +x → cp 到 PATH |
| 压缩包（tar.gz/zip） | `install_helm.sh` | tar -xzf → cp 二进制 |

### 2.1.2 按需参考其他模板

需要某个功能时，先检查其他模板是否有：
- `install_runc.sh` - 单文件模式
- `install_helm.sh` - 压缩包直接解压
- `install_node.sh` - 环境变量 export、多软链接、解压到目录隔离

### 2.1.3 检索文件服务器中所有可用的模板文件

**【强制步骤】** 使用 Everything Search 搜索本地挂载目录的脚本模板。

```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT scripts install_*.sh", "max_results": 20 }
}
```

**读取模板内容：**
```bash
cat "${MIRROR_LOCAL_ROOT}\scripts\runtime\{template_path}\install_{tool}.sh"
```
- 如果有些功能在这些模板中找到了你需要的某些功能，就参考这个功能的实现

### 2.1.4 都没有再自行调整

确实没有的功能（如特殊解压参数、新认证方式）才自行实现。

---

## 2.2 脚本统一结构

所有模板统一包含以下 12 个部分，差异仅在局部实现：

| 序号 | 部分 | 说明 |
|------|------|------|
| 1 | Shebang + 错误处理 | `#!/bin/bash`, `set -e / set -o pipefail` |
| 2 | 默认配置变量 | `TOOL_NAME`, `VERSION`, `INTRANET_BASE`, `INTERNET_BASE` |
| 3 | 颜色输出函数 | `log_info`, `log_warn`, `log_error`, `log_debug` |
| 4 | sudo 兼容处理 | `run_root`, `ensure_dir` |
| 5 | 帮助信息 | `usage()` |
| 6 | 参数解析 | `parse_args()` ← 支持 `--proxy`, `--keep-package`, `--debug` |
| 7 | 架构检测 | `detect_arch()` |
| 8 | 网络检测 | `detect_network()` |
| 9 | URL 构建 | `build_{tool}_url()` |
| 10 | 主逻辑 | `main()` |
| 11 | 执行入口 | `main "$@"` |

### 2.2.1 CLI 参数说明

| 短选项 | 长选项 | 说明 | 默认值 |
|-------|-------|------|--------|
| `-v` | `--version` | 指定版本 | `DEFAULT_VERSION` |
| `-a` | `--arch` | 指定架构 | 自动检测 |
| `-n` | `--network` | 网络类型 (`in`/`out`) | 自动检测 |
| `-i` | `--intranet-base` | 内网镜像基础 URL | 模板定义 |
| `-e` | `--internet-base` | 外网镜像基础 URL | 模板定义 |
| `-u` | `--url` | 直接指定下载 URL | - |
| `-d` | `--dir` | 安装目录 | `/usr/local` |

> ⚠️ **INSTALL_DIR 默认值必须为 `/usr/local`**，不得擅自改为 `/opt` 或其他路径。
| `-p` | `--proxy` | HTTP 代理地址 | - |
| - | `--keep-package` | 保留安装包 | false |
| - | `--debug` | 调试模式 | false |
| `-h` | `--help` | 显示帮助 | - |

---

## 2.3 URL 构建模式

```bash
build_{tool}_url() {
    local arch=$1
    local version=$2
    local network_type=$3

    if [ "$network_type" = "in" ]; then
        # 内网：直接使用内网 URL
        local intranet_base="${INTRANET_BASE:-http://192.168.0.180:8082/soft/...}"
        local url_arch
        [ "$arch" = "x64" ] && url_arch="amd64" || url_arch="arm64"
        echo "${intranet_base}/v${version}/{tool}.${url_arch}"
    else
        # 外网：通过 GitHub API 获取或直接使用官方地址
        local internet_base="${INTERNET_BASE:-https://github.com/.../releases/download}"
        echo "${internet_base}/v${version}/{tool}-${url_arch}"
    fi
}
```

### 2.3.1 代理认证

如需使用代理，在下载命令中传入 `HTTP_PROXY`：

```bash
# curl 方式
if [ -n "$HTTP_PROXY" ]; then
    curl -L -x "$HTTP_PROXY" -o "${FILE}" "${FILE_URL}"
else
    curl -L -o "${FILE}" "${FILE_URL}"
fi

# wget 方式
if [ -n "$HTTP_PROXY" ]; then
    export http_proxy="$HTTP_PROXY" https_proxy="$HTTP_PROXY"
fi
wget -O "${FILE}" "${FILE_URL}"
```

### 2.3.2 GitHub Token 认证（如需）

```bash
if [ -n "$GITHUB_TOKEN" ]; then
    HEADER="Authorization: token $GITHUB_TOKEN"
    # 在 curl/wget 中使用 Header
fi
```

---

## 2.4 模板选择决策树

```
工具分发形式
    │
    ├─ 单文件 ──────────────────────────→ install_runc.sh (基础)
    │                                      直接 cp，无需解压
    │
    └─ 压缩包
           │
           ├─ 解压后直接用二进制 ────────→ install_helm.sh (基础)
           │                              默认 tar -xzf
           │                              如需 strip-components → 调整参数
           │
           └─ 需要多二进制隔离 ──────────→ install_helm.sh (基础)
               + 环境变量 + 软链接           参考 node.sh 叠加
```

---

## 2.5 按需叠加说明

### 叠加顺序

1. **选择基础模板** - 按分发形式选最接近的
2. **按需参考其他模板** - 需要某个功能时，先看其他模板有没有
3. **都没有再自行调整** - 确实没有的功能才自己写

### 可叠加的功能模块

| 功能 | 参考模板 | 说明 |
|------|---------|------|
| 单文件安装 | `install_runc.sh` | 下载后直接 cp |
| 压缩包解压 | `install_helm.sh` | tar -xzf |
| 环境变量 export | `install_node.sh` | `ENV_FILE="/etc/profile.d/xxx.sh"` + `export XXX_HOME` |
| 多软链接 | `install_node.sh` | `ln -s` |
| strip-components | `install_node.sh` | `tar --strip-components=1` |
| GitHub Token | `install_runc.sh` | `Authorization: token` |

### 2.5.1 环境变量配置代码示例

需要设置环境变量的工具（如 Java、Gradle、Node.js 等），**必须**生成以下代码：

```bash
# 9. 设置 XXX_HOME 环境变量
ENV_FILE="/etc/profile.d/xxx_home.sh"
log_info "设置 XXX_HOME 环境变量到 ${ENV_FILE}"

cat <<EOF | run_with_fallback tee "$ENV_FILE" >/dev/null
export XXX_HOME=${XXX_HOME}
export PATH=\$XXX_HOME/bin:\$PATH
EOF

run_with_fallback chmod 644 "$ENV_FILE"
log_info "环境变量配置完成"
```

> ⚠️ **所有需要设置环境变量的工具都必须生成 `/etc/profile.d/` 配置**，包括但不限于：Java (JAVA_HOME)、Gradle (GRADLE_HOME)、Maven (MAVEN_HOME)、Node.js (NODE_HOME) 等。

---

## 2.6 真正的结构差异点

只有以下差异点需要注意，其他均为配置值：

| 差异点 | 影响 |
|-------|------|
| 分发处理 | 单文件直接 cp vs 压缩包 tar 解压 |
| 安装方式 | 纯复制 vs 需要 export + ln -s |
| 解压参数 | tar --strip-components=1 视情况调整 |

### 2.6.1 常见错误预防

| 错误 | 预防措施 |
|------|---------|
| 文件名分隔符错误 | 内网单文件通常是 `.{arch}` 而非 `-{arch}` |
| 路径错误 | 使用阶段 1 搜索到的实际路径 |
| 版本前缀错误 | 内网路径通常需要 `v` 前缀（如 `v1.32.0`） |
| 架构名称错误 | 内网 `amd64` vs 外网 `x64`，注意转换 |

---

## 2.7 示例流程

### 2.7.1 新增 docker 工具（压缩包 + 多二进制 + 目录隔离）

```
1. 选择基础模板
   → 压缩包，选 helm.sh 作基础

2. 按需叠加
   → 需要多二进制隔离？node.sh 有这个模式，参考它
   → 叠加：创建 /usr/local/docker 目录 → 复制所有二进制 → 软链接 → export PATH
```

### 2.7.2 新增 runc 工具（单文件）

```
1. 选择基础模板
   → 单文件，选 runc.sh 作基础

2. 按需叠加
   → 不需要解压，直接用
   → 不需要环境变量
   → 少量调整 VERSION、INTRANET_BASE 等配置值
```

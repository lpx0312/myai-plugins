# 阶段 1: 信息收集

**目标：** 收集编写脚本所需的全部信息。

**核心方法：** 使用 Everything Search 搜索本地挂载目录，不再逐级 curl 确认。

---

## 1.1 确定工具名称

| 参数 | 说明 |
|------|------|
| `TOOL_NAME` | 工具名称（如 kubectl, helm, runc） |
| `CATEGORY` | 分类目录（如 `k8s`, `runtime`, `tools`） |

---

## 1.2 搜索内网软件位置 ⚠️ 核心步骤

**【强制步骤】** 使用 Everything Search 找到内网软件的实际路径。

```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT\\soft {tool_name} {arch}", "max_results": 20 }
}
```

**示例：** 搜索 kubectl
```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT\\soft kubectl", "max_results": 20 }
}
```

**输出：** 找到文件后，提取并**提炼为模板变量**：

### 提炼规则

从搜索到的本地路径：
```
${MIRROR_LOCAL_ROOT}/soft/k8s/kubectl/v1.32.0/kubectl.amd64
```

提炼出：
| 变量 | 值 | 说明 |
|------|-----|------|
| `INTRANET_BASE` | `http://mirrors.lpx.com/soft/k8s/kubectl` | 去掉 `$MIRROR_LOCAL_ROOT` 前缀 + 版本号 |
| `FILE_PATTERN` | `kubectl.{arch}` | 去掉版本号后的文件名，`.{arch}` 作为占位符 |
| `VERSION` | `v1.32.0` | 版本前缀 |

### 示例一：单二进制文件（如 kubectl, runc）

**搜索结果：** `${MIRROR_LOCAL_ROOT}/soft/k8s/kubectl/v1.32.0/kubectl.amd64`

**提炼：**
```bash
INTRANET_BASE="http://mirrors.lpx.com/soft/k8s/kubectl"
FILE_PATTERN="kubectl.{arch}"
VERSION="v1.32.0"
# 实际 URL: ${INTRANET_BASE}/v${VERSION}/kubectl.amd64
```

### 示例二：归档文件（如 helm, terraform, nerdctl）

**搜索结果：** `${MIRROR_LOCAL_ROOT}/soft/linux/helm/v3.14.0/helm-v3.14.0-linux-amd64.tar.gz`

**提炼：**
```bash
INTRANET_BASE="http://mirrors.lpx.com/soft/linux/helm"
FILE_PATTERN="helm-{version}-linux-{arch}.tar.gz"
VERSION="v3.14.0"
# 实际 URL: ${INTRANET_BASE}/v${VERSION}/helm-v${VERSION}-linux-{arch}.tar.gz
```

> ⚠️ **关键点：** 搜索结果中的 `v1.32.0` 或 `v3.14.0` 是**文件夹名称**，不是文件名的一部分。文件名格式以实际搜索结果为准。

**确认归档包内部结构（如果是归档文件必须提取）：**
```bash
tar -tf "${MIRROR_LOCAL_ROOT}/soft/linux/helm/v3.14.0/helm-v3.14.0-linux-amd64.tar.gz"
# 输出：helm-v3.14.0-linux-amd64/helm
#       helm-v3.14.0-linux-amd64/LICENSE
#       helm-v3.14.0-linux-amd64/README.md
```

---

## 1.3 确定输出目录

| 参数 | 说明 | 示例 |
|------|------|------|
| `OUTPUT_DIR` | 脚本输出目录 | `scripts/k8s/kubectl` |

**用户指定时：** 使用用户指定的路径（可使用 mirror-file-manager skill 转换）

**用户未指定时：** 询问用户

---

## 1.4 确认外网下载源（如需外网）

**方法一：** 搜索内网参考脚本，完整读取理解外网 URL 构建方式

```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT\\scripts install_{tool_name}*.sh", "max_results": 10 }
}
```

找到后**完整读取脚本**，从中理解外网 URL 的构建逻辑（仓库名、文件名格式等）。

**备用：** 如果脚本中外网 URL 不明显，再用 grep 辅助搜索：
```bash
grep -E "github.com|releases/download" "${MIRROR_LOCAL_ROOT}\scripts\{found_path}\install_{tool}.sh"
```

**方法二：** 直接构建 GitHub URL
```
https://github.com/{owner}/{repo}/releases/download/v{version}/{filename}
```
**上面方法搜索的都不对的话，最后在使用联网搜索来确认外网 URL 构建方式**

---

## 输出清单

| 参数 | 值 |
|------|---|
| `TOOL_NAME` | kubectl |
| `TEMPLATE_PATH` | `${MIRROR_LOCAL_ROOT}/scripts/runtime/runc/install_runc.sh` |
| `INTRANET_BASE` | `http://mirrors.lpx.com/soft/k8s/kubectl` |
| `INTRANET_FILE_PATTERN` | `kubectl.{arch}` |
| `OUTPUT_DIR` | `scripts/k8s/kubectl` |
| `EXTRANET_BASE` | `https://github.com/kubernetes/kubernetes/releases/download` |

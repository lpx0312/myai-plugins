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

## 1.2 搜索参考模板

**【强制步骤】** 使用 Everything Search 搜索本地挂载目录的脚本模板。

```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT scripts install_*.sh", "max_results": 20 }
}
```

**模板选择规则：**
- Docker 生态工具 → `runtime/nerdctl/install_nerdctl.sh`
- 单二进制文件 → `runtime/runc/install_runc.sh`
- 复杂工具 → `runtime/containerd/install_containerd.sh`

**读取模板内容：**
```bash
cat "${MIRROR_LOCAL_ROOT}\scripts\runtime\{template_path}\install_{tool}.sh"
```

---

## 1.3 搜索内网软件位置 ⚠️ 核心步骤

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

**输出：** 找到文件后，提取：
- 本地路径：`${MIRROR_LOCAL_ROOT}/soft/k8s/kubectl/v1.32.0/kubectl.amd64`
- 对应内网 URL：`http://mirrors.lpx.com/soft/k8s/kubectl/v1.32.0/kubectl.amd64`

---

## 1.4 确定输出目录

| 参数 | 说明 | 示例 |
|------|------|------|
| `OUTPUT_DIR` | 脚本输出目录 | `scripts/k8s/kubectl` |

**用户指定时：** 使用用户指定的路径（可使用 mirror-file-manager skill 转换）

**用户未指定时：** 询问用户

---

## 1.5 确认外网下载源（如需外网）

**方法一：** 使用 Everything Search 搜索内网已有脚本，再提取外网 URL

```json
mcp__everything-search__search
{
  "base": { "query": "path:$MIRROR_LOCAL_ROOT\\scripts install_{tool_name}*.sh", "max_results": 10 }
}
```

找到后提取外网地址：
```bash
grep -E "github.com|releases/download" "${MIRROR_LOCAL_ROOT}\scripts\{found_path}\install_{tool}.sh"
```

**方法二：** 直接构建 GitHub URL
```
https://github.com/{owner}/{repo}/releases/download/v{version}/{filename}
```

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

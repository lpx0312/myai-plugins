# 阶段 3: 文档编写

## 脚本说明文档

为每个下载脚本创建 README.md，包含：

### 基本结构

```markdown
# {工具名} 下载器

从 GitHub Releases 下载 {工具名} 的所有稳定版本。

## 使用方法

### 环境要求

- bash shell
- curl
- GitHub Token (避免 API 限流)

### 环境变量

```bash
export GITHUB_TOKEN="ghp_xxxx"      # GitHub Token
export HTTPS_PROXY="http://..."     # 代理服务器
```

### 快速使用

```bash
# 下载到当前目录
./download.sh

# 模拟运行 (预览)
./download.sh -n

# 使用验证模式
./download.sh -V
```

## 脚本说明

| 脚本 | 说明 |
|------|------|
| {name}-downloader.sh | 完整下载脚本，支持版本选择、架构检测 |
| download.sh | 统一入口脚本 |

## 输出目录

下载的文件保存在 `{DOWNLOAD_DIR}` 目录。
```

# 阶段 5: 上传到文件服务器

## 确认脚本位置

确保脚本不在 `.claude/projects` 目录：

```bash
# 错误示例 - 如果发现脚本在这里，需要移动
/c/Users/lipanx/.claude/projects/z--soft/...

# 正确位置 - 用户的工作目录
${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer/
```

如果发现脚本被写入错误的目录，需要将文件移动到正确位置：

```bash
# 从错误位置复制到正确位置
cp /c/Users/lipanx/.claude/projects/z--soft/runtime/docker_tools/image-syncer/*.sh \
   ${MIRROR_LOCAL_ROOT}/runtime/docker_tools/image-syncer/
```

## 上传到内网文件服务器

使用 mirror-file-manager skill 上传脚本到内网服务器：

1. 确定目标路径，例如：
   - `http://mirrors.lpx.com/soft/runtime/{tool}/{name}-downloader.sh`
   - `http://mirrors.lpx.com/soft/runtime/{tool}/download.sh`

2. 使用 SCP 或 curl 上传

## 验证文件服务器可访问

上传后验证：
```bash
curl -I http://mirrors.lpx.com/soft/runtime/{tool}/{name}-downloader.sh
```

## 告知用户

告诉用户如何使用：

```bash
# 方式1：使用入口脚本（推荐）
./download.sh

# 方式2：直接使用下载脚本
./{name}-downloader.sh --help
./{name}-downloader.sh -n              # dry-run 模式
./{name}-downloader.sh -p "${HTTPS_PROXY}"  # 使用代理
./{name}-downloader.sh -t "${GITHUB_TOKEN}" -V   # 使用 token 并验证
```

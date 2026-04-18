# 阶段 4: 远程测试


**输入：** 阶段 2 收集的信息
**脚本的本地内网服务器路径**: `LOCAL_SH_PATH = ${MIRROR_LOCAL_ROOT}\{OUTPUT_DIR}\install_{tool}.sh`
**脚本的本地内网服务器URL**: `IN_SH_URL = ${MIRROR_INTRANET_BASE_URL}\{OUTPUT_DIR}\install_{tool}.sh`

**使用 ssh-mcp-server MCP 连接测试服务器：** `${TEST_NODE_IP}`

- 后续服务都在测试服务器上执行。
---

## 4.1 内网测试（必须）

```bash
curl -sSL ${IN_SH_URL} | sudo bash -s -- -v {version} -n in
```

---

## 4.2 外网测试（如需要）

```bash
export HTTP_PROXY=${HTTP_PROXY}
curl -sSL ${IN_SH_URL} | sudo bash -s -- -v {version} -n out -t ${GITHUB_TOKEN} -p ${HTTP_PROXY}
```

---

## 4.3 验证步骤

**：**

1. 检查文件大小：
   ```bash
   ls -la /tmp/{tool}-{arch}  # 必须 > 0
   ```

2. 检查安装目录：
   ```bash
   ls -la /usr/local/{tool}-{version}/
   ```

3. 验证可执行：
   ```bash
   /usr/local/{tool}-{version}/{tool} version --client
   ```

---

## 4.4 常见错误排查

| 错误表现 | 可能原因 | 解决方案 |
|---------|---------|---------|
| 404 Not Found | 内网路径错误 | 重新执行阶段 1 确认路径 |
| 文件大小为 0 | 文件名分隔符错误（`-` vs `.`） | 检查 URL 中的文件名格式 |
| 下载失败 | 版本目录不存在 | 确认版本目录存在 |
| 权限错误 | 需要 sudo | 使用 `sudo bash -s -- ...` |

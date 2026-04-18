# 阶段 4: 远程测试

**测试服务器：** `192.168.1.182`

---

## 4.1 内网测试（必须）

```bash
curl -sSL http://192.168.0.180:8082/scripts/{category}/{tool}/install_{tool}.sh | sudo bash -s -- -v {version} -n in
```

---

## 4.2 外网测试（如需要）

```bash
export https_proxy=http://192.168.0.4:7890
curl -sSL http://192.168.0.180:8082/scripts/{category}/{tool}/install_{tool}.sh | sudo bash -s -- -v {version} -n out -t ${GITHUB_TOKEN} -p http://192.168.0.4:7890
```

---

## 4.3 验证步骤

**使用 ssh-mcp-server MCP：**

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

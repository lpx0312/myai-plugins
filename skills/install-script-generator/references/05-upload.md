# 阶段 5: 上传验证

---

## 5.1 确认脚本已上传

脚本应该在阶段 2 创建时已写入本地挂载目录：

```bash
# 确认文件存在
ls -la "${MIRROR_LOCAL_ROOT}\scripts\{category}\{tool}\install_{tool}.sh"
```

---

## 5.2 验证文件服务器可访问

```bash
curl -sI "http://192.168.0.180:8082/scripts/{category}/{tool}/install_{tool}.sh" | head -1
```

期望输出：`HTTP/1.1 200 OK`

---

## 5.3 输出最终信息

| 信息 | 值 |
|------|---|
| 脚本 URL | `http://192.168.0.180:8082/scripts/{category}/{tool}/install_{tool}.sh` |
| 安装命令 | `curl -sSL <URL> \| sudo bash -s -- -v {version} -n in` |
| 支持版本 | 内网文件服务器上存在的版本 |

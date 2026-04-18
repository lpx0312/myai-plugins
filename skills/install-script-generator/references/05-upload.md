# 阶段 5: 上传验证

从阶段 1 收集的信息中获取 OUTPUT_DIR：
**脚本的本地内网服务器路径**: `LOCAL_SH_PATH = ${MIRROR_LOCAL_ROOT}\{OUTPUT_DIR}\install_{tool}.sh`
**脚本的本地内网服务器URL**: `IN_SH_URL = ${MIRROR_INTRANET_BASE_URL}\{OUTPUT_DIR}\install_{tool}.sh`

---

## 5.1 确认脚本已上传

脚本应该在阶段 2 创建时已写入本地挂载目录：

```bash
# 确认文件存在
ls -la "${LOCAL_SH_PATH}"
```

---

## 5.2 验证文件服务器可访问

```bash
curl -sI ${IN_SH_URL} | head -1
```

期望输出：`HTTP/1.1 200 OK`

---

## 5.3 输出最终信息

| 信息 | 值 |
|------|---|
| 脚本 URL | `${IN_SH_URL}` |
| 安装命令 | `curl -sSL ${IN_SH_URL} \| sudo bash -s -- -v {version} -n in` |
| 支持版本 | 内网文件服务器上存在的版本 |

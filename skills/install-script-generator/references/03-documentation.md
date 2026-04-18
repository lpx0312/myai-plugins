# 阶段 3: 文档编写

**输入：** 阶段 2 完成的脚本
**输出：** `README.md`
**输出目录**: 从 阶段 1 获取的 OUTPUT_DIR
**输出文档的本地内网服务器路径**: `${MIRROR_LOCAL_ROOT}\{OUTPUT_DIR}\README.md`
**输出文档的本地内网服务器URL**: `${MIRROR_INTRANET_BASE_URL}\{OUTPUT_DIR}\README.md`

---

## 3.1 参照文档模板

完全参照 `assets/docs/README.md` 的结构和格式。

---

## 3.2 必须包含的部分

1. YAML frontmatter（创建日期、更新时间、标签等）
2. 概述和脚本地址
3. 支持的配置（版本、架构）
4. 处理流程图
5. 命令行参数表
6. 使用方法（本地执行、远程调用）
7. 快速参考表
8. 安装目录结构
9. 网络检测逻辑说明
10. 系统要求
11. 注意事项
12. 故障排查
13. 版本管理
14. 高级用法
15. 工具基础用法
16. 相关资源
17. 更新日志

---

## 3.3 搜索替换规则

```
nerdctl → {TOOL_NAME}
containerd/nerdctl → {category}/{tool_name}
Docker → 相关上下文（保持一致性）
runtime/nerdctl → scripts/{category}/{tool_name}
内网地址 → http://192.168.0.180:8082/scripts/{category}/{tool_name}
```



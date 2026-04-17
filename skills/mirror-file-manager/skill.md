---
name: mirror-file-manager
description: 文件服务器地址映射。触发场景：用户提到Z盘路径要转URL，或URL要转本地路径,或要在文件服务器上搜索/下载文件。
---

# 文件服务器配置

## 地址映射表

| 本地路径 | 内网域名 | 内网IP | 外网域名 |
|---------|---------|--------|---------|
| `Z:\` | `http://mirrors.lpx.com` | `http://192.168.0.180:8082` | `https://mirrors.sktill.top:7000` |

**转换规则：** 直接替换前缀，路径分隔符 `\` ↔ `/`

**示例：**
```
Z:\soft\JDK\jdk.tar.gz
  → http://mirrors.lpx.com/soft/JDK/jdk.tar.gz
  → http://192.168.0.180:8082/soft/JDK/jdk.tar.gz
  → https://mirrors.sktill.top:7000/soft/JDK/jdk.tar.gz
```

## 搜索文件

使用 Everything Search MCP,搜索文件服务器用 `path:Z:\` 限定：

```json
mcp__everything-search__search
{
  "base": { "query": "path:Z:\\ 关键词", "max_results": 50 }
}
```

## 下载到服务器

1. 用 Everything 扫描目录结构推断目标位置
2. 向用户确认路径
3. 执行下载：`curl -L -o "Z:/目标路径/文件名" "源URL"`
4. 输出三种访问地址

## 输出格式

单个文件返回完整地址：
```
本地路径: Z:\xxx
内网域名: http://mirrors.lpx.com/xxx
内网IP:   http://192.168.0.180:8082/xxx
外网地址: https://mirrors.sktill.top:7000/xxx
```

多个文件用表格展示。

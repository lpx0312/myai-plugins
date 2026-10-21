---
name: tc-img
description: 上传本地图片/截图到自建 Chevereto 图床（TC图床），返回可直接嵌入 markdown 的外链。当用户说"传图床"、"上传图片/截图到图床"、"把这个图传上去换个外链"、"md 里插图"、"截图外链"、"tc图床"、"Chevereto 上传"时使用；写文档/手册过程中需要嵌入本地图片时也应自动使用——先上传换外链再写进 md，不要把图片文件塞进仓库或笔记库占空间。
---

# TC 图床上传（Chevereto API v1）

把本地图片上传到自建 Chevereto 图床，输出 `![alt](直链)` + 纯 URL。支持：单文件 / 多文件 / glob / 目录（取最新一张）/ Windows 剪贴板截图。写文档遇到"要嵌图"的场景一律走本 skill，用外链代替本地图片文件。

## 前置：环境变量（谁用谁设置）

| 变量 | 含义 | 示例 |
|---|---|---|
| `TCIMG_URL` | Chevereto 站点根地址，不带尾斜杠 | `https://img.example.com` |
| `TCIMG_TOKEN` | 用户 API key（图床网页 Settings → API 生成） | 只通过环境变量注入，**禁止写进任何文件/git/对话正文** |

两条铁律：

1. **上传端点决定图链 host**：用哪个地址上传，md 里的图链就是哪个 host。想让文档随处可看就填公网可达地址；填内网地址时图链仅内网可见。
2. **token 零落盘**：本机部署了 keyHive 密钥管家时，凭据存于「chevereto图床」条目（url 字段含内外网双地址，token 字段是上传 key）。标准注入模式：

```bash
export TCIMG_URL="https://img.example.com"                     # 取条目 url 字段里的公网地址
export TCIMG_TOKEN="$(keyhive reveal <id> token | jq -r .value)"
bash "<skill目录>/scripts/tcimg.sh" 图片.png
unset TCIMG_TOKEN
```

## 命令

```bash
S=<skill目录>/scripts/tcimg.sh
bash "$S" 图.png                          # 单文件（Windows 风格路径 D:\a.png 会自动转换）
bash "$S" shot-*.png 图1.jpg              # 批量 / glob
bash "$S" D:/pics                         # 目录 → 自动取最新一张图片
bash "$S" --clip                          # 上传剪贴板里的截图（仅 Windows）
bash "$S" --album 3 图.png                # 归入指定相册（默认不指定）
bash "$S" --clean 图.png                  # 上传成功且直链校验通过后删除本地文件
```

## 输出与退出码

每张图一组：`── 文件名`、`![alt](url)`、`URL: url`；目录模式会额外在 stderr 提示选中了哪张。结尾 `SUMMARY: 成功 N 失败 M`。

| 退出码 | 含义 |
|---|---|
| 0 | 全部成功 |
| 1 | 有失败（含输入文件不存在、目录无图片、直链校验不过） |
| 2 | 环境/用法错误（TCIMG_URL/TCIMG_TOKEN 未设置、依赖缺失、无输入） |

agent 嵌图写文档时：取 `![alt](url)` 行写进 md；成功后如果用户明确要求不留本地副本，才用 `--clean` 重跑或自行删源文件。

## 坑位清单（这些约定为什么存在）

1. **剪贴板取图必须 PowerShell `-STA`**：MTA 模式下 `Clipboard::GetImage()` 会不可靠地返回 null，报"剪贴板里没有图片"。
2. **带空格的路径引号传具体文件，别走 glob**：glob 展开按空格分词会碎；Windows 风格路径（`D:\a b.png`）脚本已用 cygpath 自动转换。
3. **`--clean` 是三重条件**：上传成功 + 直链 HEAD 校验 2xx/3xx + 非剪贴板临时文件，都满足才删；剪贴板临时文件由脚本 trap 统一清理。
4. **Chevereto 对格式/大小有限制**（png/jpg/gif/bmp 等，上限视站点配置约 10MB 级），超限/不支持时 API 返回明确错误，脚本原样透传到 stderr。
5. **上传无自动重试**：避免响应丢失时重复传图占库；失败时看 stderr 原因，确认网络后手动重跑。
6. **中文文件名会被服务端改成随机串**（如 `b679bb1e....png`），直链仍是安全 ASCII，md 的 alt 文本保留原名不受影响。
7. **同名文件重复上传不覆盖**：Chevereto 自动加随机后缀生成新文件（`blue0490a1....png`），重复跑命令会占库——同一次任务里别对同一文件重复传。
8. **图片内容自审**：内网拓扑、凭据、聊天记录等敏感截图不要传公开图床——图链是任何人可访问的。

## 何时不用本 skill

- 已经是外链（http/https）的图：直接写进 md，不必中转上传。
- 只想本地看图或图片必须随仓库分发（如 README 徽章、源码资源）：保持本地引用。

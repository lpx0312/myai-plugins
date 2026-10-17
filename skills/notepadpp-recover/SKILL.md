---
name: notepadpp-recover
description: 找回 Notepad++ 关机/崩溃/异常退出后"消失的未保存文件"并整体备份归档。当出现以下情况时使用：Notepad++ 重启后之前打开的一堆标签页全没了、关机或断电后 Notepad++ 里未保存的内容找不到、打开着的"新文件 1/新文件 2"消失了、怀疑会话丢失、想查 Notepad++ 历史保存过哪些没保存的内容、要把 Notepad++ 未保存记录整体备份成一个归档目录、想一次性打开全部历史备份。关键词：Notepad++、notepad++、np++、未保存、没保存、标签页丢失、标签全没了、会话丢失、session.xml、backup 目录、崩溃恢复、断电恢复、快照备份。
---

# Notepad++ 未保存文件 / 丢失会话 恢复

Notepad++ 关机后标签页全没了 —— **内容通常一个都没丢**，只是"标签列表"丢了。

## 一句话原理

Notepad++ 有两套独立机制，恢复时千万别混淆：

| 文件 | 作用 | 丢了会怎样 |
| --- | --- | --- |
| `session.xml` | 只记「哪些标签开着、光标在哪」 | 标签列表消失 → 看起来"文件全没了" |
| `backup` 目录 | **未保存文档的内容快照**（每 N 秒一份） | 这个丢了才是真的丢内容 |

**关键结论：`session.xml` 被覆盖/丢失 ≠ 内容丢失。** 未保存的内容全在 `backup` 目录里，
文件名格式是 `原文件名@YYYY-MM-DD_HHMMSS`（时间戳 = 快照生成时间）。

所以标准恢复动作是：**去 `backup` 目录捞文件**，而不是想办法修 `session.xml`。

## 快速开始

一条命令搞定「扫描 + 生成清单 + 整体归档」：

```bash
python scripts/notepadpp_recover.py --archive "D:/未保存文件恢复"
```

产出 3 样东西：

| 产物 | 用途 |
| --- | --- |
| `<归档目录>\<原备份文件名>` | 全部备份的副本（防止原目录被 Notepad++ 轮换删除） |
| `未保存文件恢复清单.md` | 按日期分组、带内容摘要的可检索清单，用来"认领"文件 |
| `全部备份会话.xml` | 载入它可一次性在 Notepad++ 打开全部备份（见下方坑 3） |

只扫描不落盘（先看看有没有货）：

```bash
python scripts/notepadpp_recover.py
```

## 先判断"能不能救"

| 现象 | 判定 | 处理 |
| --- | --- | --- |
| `backup` 目录有文件 | **能救**，内容都在 | 直接归档 + 看清单 |
| `backup` 目录空 / 不存在 | 当时可能没开"备份"，或已被清理 | 放弃内容恢复，只能查最近文档 |
| 备份文件 0 字节 | 该文档当时是空的 | 无内容可恢复（清单里会标 `[空文件]`） |

判定脚本会自动查 `config.xml` 里 `<GUIConfig name="Backup" .../>` 的
`isSnapshotMode` / `snapshotBackupTiming`，并告诉你实际生效的备份目录
（注意 `useCustumDir="yes"` 时备份目录被改到别处了）。

## 关键路径速查

| 场景 | 路径 |
| --- | --- |
| 安装版配置 | `%APPDATA%\Notepad++\` |
| 安装版备份 | `%APPDATA%\Notepad++\backup\` |
| 安装版会话 | `%APPDATA%\Notepad++\session.xml` |
| 便携版 | `notepad++.exe` 同级的 `backup\` 与 `session.xml` |
| 自定义备份目录 | 见 `config.xml` 里 `Backup` 的 `dir` 属性 |
| 关机/崩溃日志 | `%APPDATA%\Notepad++\nppLogNulContentCorruptionIssue.log` |

## 「为什么标签会丢」—— 用日志一锤定音

`nppLogNulContentCorruptionIssue.log` 记录了每次关机事件：

```text
2026-10-13 23:17:25  WM_QUERYENDSESSION (lParam: 1073741824 - ENDSESSION_CRITICAL) ===
2026-10-13 23:17:25  WM_ENDSESSION (wParam: TRUE, lParam: 1073741824 - ENDSESSION_CRITICAL)
```

正常退出时，关机事件之后会紧跟：

```text
...\session.xml is opened.
...\session.xml  3532/3532 bytes are written.
...\session.xml is closed.
```

**判断规则：**

- 关机事件后**有** `session.xml ... bytes are written` → 会话正常落盘，标签丢失另有原因
- 关机事件后**没有**这段 → 系统强制结束进程，会话没来得及写 → **这就是标签列表丢失的原因**，
  但 `backup` 目录的内容快照仍在，照常恢复
- 出现 `ENDSESSION_CRITICAL`（lParam `1073741824`）通常是关机流程被强杀，最容易踩这个坑

脚本会自动解析该日志，在报告和清单里列出最近 8 次关机事件及 session 是否写入。

## 脚本用法

```bash
python scripts/notepadpp_recover.py [选项]
```

| 选项 | 说明 |
| --- | --- |
| （无） | 打印扫描报告，不改动任何文件 |
| `--archive DIR` | 复制全部备份到 DIR，并生成清单 + 会话文件 |
| `--index FILE` | 只生成 Markdown 清单 |
| `--make-session FILE` | 只生成 Notepad++ 会话文件 |
| `--session-base DIR` | 会话文件引用的文件所在目录（默认备份原目录，**建议改成归档目录**） |
| `--config-dir DIR` | 手动指定配置目录（便携版/非标准安装） |
| `--all-profiles` | 扫描本机所有用户的 Notepad++ 配置 |
| `--json` | 机器可读输出 |

输出乱码时（Git Bash / 重定向管道）：

```bash
export PYTHONIOENCODING=utf-8
```

## 手工流程（没有脚本时）

1. 打开 `%APPDATA%\Notepad++\backup\`，按修改时间排序
2. `文件名@YYYY-MM-DD_HHMMSS` 中，时间戳落在"丢失那天之前最近一次编辑"的就是目标
3. 直接用 Notepad++ 打开（可能要选"所有文件"），或复制一份去掉 `@时间戳` 后缀另存
4. 同时看一眼 `session.xml`：里面 `backupFilePath` 属性直接给出该标签对应的备份文件名

## 实操踩坑（实测记录，别重复踩）

### 1. 备份文件名会"消失"，先归档再操作

Notepad++ 运行期间会**轮换/删除**旧快照。实测：生成会话文件时 131 个备份全在，
几分钟后再验证，其中 2 个已被运行中的 Notepad++ 删掉，导致会话加载报 `Cannot open file`。
**结论：先 `--archive` 复制一份，后续所有操作基于归档副本。**

### 2. 用 `-openSession` 加载会话时，路径要用空格分隔

官方用法是 `-openSession <路径>`。写成 `-openSession=<路径>` 会被当成文件名去打开，
弹 `Cannot open file`。从 `notepad++.exe` 二进制里可提取到帮助文本确认：

```text
-openSession : Open a session. filePath m...
-multiInst -nosession -openSession ...
```

### 3. 会话文件里的中文必须写成数字实体，否则整个会话被静默忽略

**这是最容易踩的坑。** 手写/程序生成的 `session.xml`，如果 `filename` 里直接写原始
UTF-8 中文，Notepad++ **不报错、直接忽略整个会话**，只显示一个空白"新文件 1"。

必须写成 `&#x65B0;` 这种 XML 数字实体（Notepad++ 自己写 session 时就是这么干的）。
本脚本的 `xml_escape()` 已处理。

验证方法：加载会话后看窗口标题，正常会显示 `<某个备份文件路径> - Notepad++`；
如果显示 `新文件 1 - Notepad++`，说明会话**没**被加载。

### 4. 后台实测隔离方式

想验证会话文件又不打扰正在用的 Notepad++，用独立实例：

```bash
"C:/Program Files/Notepad++/notepad++.exe" -multiInst -nosession -openSession <会话文件>
```

`-nosession` 保证不改写你的 `session.xml`；`-multiInst` 保证另起进程。

### 5. Windows 中文控制台会因 emoji 崩溃

代码页 936 下 `✅`(U+2705) 编码不了，`print` 直接抛 `UnicodeEncodeError` 中断脚本。
脚本已用 `stream.reconfigure(errors="replace")` 兜住。

## 边界与误区

- **`session.xml` 不用修**，也不建议手写回去。内容恢复走 `backup` 目录，标签页手动重开即可。
- **同一文档会有多个版本**：`新文件 1` 可能同时存在 `@2024-11-06` 和 `@2026-10-17` 两份快照，
  清单里有「同一文档的多个历史版本」专章列出，按时间挑最接近的。
- **`新文件 N` 是未命名标签**，N 与内容没有对应关系，只能靠摘要认领。
- 备份只会保留**最近**的状态，没有更细的历史回溯能力（每 7 秒一份会被覆盖/轮换）。
- Notepad++ 完全没开过"备份"功能时，本 skill 无从恢复 —— 但不影响事后去把功能打开。

## 预防

- 首选项 → 备份：保持「会话快照和周期性备份」开启（`isSnapshotMode="yes"`）
- 首选项 → MISC：勾选「记住上次会话」，保证标签列表落盘
- 定期用本脚本 `--archive` 归档一次，并清理过老的备份（长期会累积到上百个文件）

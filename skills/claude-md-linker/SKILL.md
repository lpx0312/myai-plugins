---
name: claude-md-linker
description: 把 Claude Code 的全局指令文件 ~/.claude/CLAUDE.md 用 Windows 符号链接（symlink）统一映射到其它 AI Agent 的全局指令文件（Codex 的 ~/.codex/AGENTS.md、ZCode 的 ~/.zcode/AGENTS.md、Pi 的 ~/.pi/agent/AGENTS.md、OpenCode、Gemini CLI、Qwen Code、iFlow、Cursor、Cline、Copilot、Amazon Q 等），实现"改一处、处处同步"。当用户提到"把 CLAUDE.md 同步/软链接/映射到各 Agent / AGENTS.md"、"统一各 AI 的全局指令/记忆文件"、"让 Codex/Pi/ZCode 共用 Claude 的全局 CLAUDE.md"、"symlink CLAUDE.md to AGENTS.md"、"全局指令文件链接"、"链接全局 md"时，务必使用本技能；即使用户只说"帮我把这个 CLAUDE.md 链接过去"，也应使用。
---

# CLAUDE.md → 各 Agent 全局指令文件软链接器（Windows）

把 Claude Code 的主指令文件 `CLAUDE.md` 通过 **Windows 符号链接** 映射成其它 AI 编码 Agent 的全局指令文件，让所有 AI 共用同一份全局记忆/规则：只维护 `~/.claude/CLAUDE.md` 一处，其余自动跟随。

## 为什么必须用「符号链接」而不是「硬链接」

- **硬链接**：多个文件名指向同一个 inode。一旦某个程序（Claude Code、编辑器等）用「写临时文件 → 重命名替换」的方式保存，就会产生新 inode，硬链接立即断裂、从此不再同步。**不要用硬链接。**
- **符号链接**：指向*路径*。目标文件无论被替换多少次，链接始终跟着 `C:\Users\<你>\.claude\CLAUDE.md` 这个路径走，因此永久同步。

本机已有的正确范例（可在动手前对照）：

```
C:\Users\<你>\.codex\AGENTS.md    <SYMLINK> -> C:\Users\<你>\.claude\CLAUDE.md
C:\Users\<你>\.zcode\AGENTS.md    <SYMLINK> -> C:\Users\<你>\.claude\CLAUDE.md
C:\Users\<你>\.pi\agent\AGENTS.md <SYMLINK> -> C:\Users\<你>\.claude\CLAUDE.md
```

## 快速开始

技能自带脚本 `scripts/link-agent-md.ps1`。**先跑 DryRun 预览**，确认无误再真正执行：

```bash
# 1) 预览（不修改任何文件）
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-md.ps1" -DryRun

# 2) 正式执行（若当前进程无符号链接权限，会弹 UAC 提权）
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-md.ps1"
```

`<skill目录>` 解析为技能所在目录的绝对路径（例如 `C:\Users\<你>\.cc-switch\skills\claude-md-linker`）。

## 默认目标（父目录不存在则自动跳过 = 该 Agent 未安装）

| Agent | 全局指令文件 |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| ZCode | `~/.zcode/AGENTS.md` |
| Pi | `~/.pi/agent/AGENTS.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| Qwen Code | `~/.qwen/QWEN.md` |
| iFlow | `~/.iflow/IFLOW.md` |
| Cursor | `~/.cursor/AGENTS.md` |
| Cline | `~/.cline/AGENTS.md` |
| GitHub Copilot | `~/.copilot/AGENTS.md` |
| Amazon Q | `~/.amazonq/AGENTS.md` |

链接任意「别的 .md」也可以，用 `-Targets` 指定（可多个，逗号分隔）：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-md.ps1" \
  -Targets "$env:USERPROFILE\.foo\MY.md","$env:USERPROFILE\.bar\AGENTS.md"
```

## 脚本行为

对每个目标文件：

1. 已经是「指向源文件的符号链接」→ 报告 `OK`，不动。
2. 是普通文件 / 指向别处的符号链接 / 硬链接 → 报告 `REPLACE`，把原文件复制为 `<文件>.bak_<时间戳>`（除非 `-NoBackup`），删除后新建符号链接。
3. 是目录 → 直接 `ERROR` 跳过（安全保护，绝不递归删除目录）。
4. 父目录不存在 → `SKIP`（该 Agent 未安装）；加 `-CreateDirs` 则连同目录一起创建。
5. 源文件不存在 → `ERROR` 退出，不做任何改动。

脚本输出为英文状态行（`SOURCE / MODE / OK / CREATE / REPLACE / BACKUP / LINKED / SKIP / WARN / ERROR`），便于稳定解析。

## 参数

| 参数 | 说明 |
|---|---|
| `-Source <path>` | 主文件，默认 `%USERPROFILE%\.claude\CLAUDE.md` |
| `-Targets <p1,p2,...>` | 自定义目标，默认使用上表 |
| `-DryRun` | 只预览不落盘 |
| `-NoElevate` | 不提权，仅在本进程尝试创建（开发者模式开启时可用），否则逐条报错 |
| `-NoBackup` | 覆盖普通文件时不保留 `.bak_<时间戳>` |
| `-CreateDirs` | 目标父目录不存在时也创建 |

## 权限说明（本机关键点）

Windows 创建符号链接需要 `SeCreateSymbolicLinkPrivilege`，来源二选一：

- **管理员令牌**（提权，会有 UAC 弹窗）；或
- 开启 **Windows 开发者模式**（设置 → 系统 → 开发者选项），普通用户即可免提权创建。

脚本会先探测当前进程能否创建符号链接：

- 能（开发者模式已开）→ 直接执行，不弹 UAC。
- 不能 → 自动以 `Start-Process -Verb RunAs` **提权重跑自身**（弹一次 UAC，请点「是」），并把子进程报告写回日志后回显。
- 用户加 `-NoElevate` 或不方便弹窗 → 保持非提权，逐条 `ERROR`，让用户自行开启开发者模式或改用管理员终端。

> 提权用的是同一用户的令牌，`%USERPROFILE%` 不变，因此默认路径仍然正确。

## 验证结果

执行后用下面任一方式确认「确实是符号链接」且「双向同步」：

```bash
# 看类型：应显示 <SYMLINK> 或 lrwxrwxrwx
cmd //c "dir /a C:\\Users\\%USERNAME%\\.codex\\AGENTS.md"
ls -la ~/.pi/agent/AGENTS.md

# 看内容一致
diff ~/.claude/CLAUDE.md ~/.pi/agent/AGENTS.md && echo SAME

# 实测同步：改 CLAUDE.md，看目标文件是否立刻变
printf 'SYNC_TEST\n' >> ~/.claude/CLAUDE.md
tail -n 1 ~/.pi/agent/AGENTS.md
# 测完记得回滚：用原始字节数 truncate，或恢复 .bak
```

## 排障

| 现象 | 原因与处理 |
|---|---|
| `mklink` 报「没有足够的权限执行此操作」 | 未提权且未开开发者模式。让脚本自动提权，或开启开发者模式，或用管理员终端。 |
| 之前用硬链接，改动不同步 | 硬链接被「原子替换保存」打断。脚本会识别并 `REPLACE` 成符号链接。 |
| `ERROR ... path is a directory` | 目标路径是目录，脚本拒绝操作。请确认目标应是文件（如 `AGENTS.md`）。 |
| 目标 `SKIP ... agent dir not found` | 该 Agent 未安装；确认目录改名/位置后，用 `-Targets` 指定正确路径，或加 `-CreateDirs`。 |
| 提权窗口一闪而过、无输出 | 子进程报告写在临时日志里，父进程会读取回显；若被安全软件拦截，改用管理员终端手动跑一次。 |

## 新增一个 Agent

1. 找到它的全局指令文件路径（多数约定为 `<agent目录>/AGENTS.md`，部分用 `GEMINI.md`/`QWEN.md` 等）。
2. 直接用 `-Targets` 跑一次即可；若想纳入默认列表，编辑 `scripts/link-agent-md.ps1` 里的 `$defaultTargets` 追加一行。

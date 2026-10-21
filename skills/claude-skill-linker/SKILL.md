---
name: claude-skill-linker
description: 把 Claude Code 的全局 skills 目录 ~/.claude/skills 作为唯一真源，用 Windows 符号链接（symlink）或 NTFS 联接（junction，免管理员权限）软链到其它 AI Agent 的 skills 目录（Codex ~/.codex/skills、ZCode ~/.zcode/skills、Pi ~/.pi/agent/skills、DSH ~/.dsh/skills、~/.agents/skills、OpenCode、Gemini CLI、Qwen Code、iFlow、Cursor、Cline、Copilot、CodeBuddy、WorkBuddy、Qoder、Trae CN 等），实现"skill 只维护一份、所有 Agent 共用"。当用户提到"把 skills 目录同步/软链/映射到各 Agent"、"让 Codex/Cursor/Pi/ZCode 共用 Claude 的 skill"、"skill 目录软链接"、"只改 Claude 的 skill 就行"、"symlink skills directory"、"多个 AI 共用一个 skill 库"、"skill 一份多处生效"时，务必使用本技能；即使用户只说"帮我把 skill 目录链接到别的 agent"，也应使用。
---

# Claude Code skills → 各 Agent skills 目录软链接器（Windows）

把 Claude Code 的主 skills 目录 ~/.claude/skills 通过**目录符号链接 / NTFS 联接**映射到其它 AI Agent 的 skills 目录：只维护 ~/.claude/skills 一处，所有 Agent 自动跟随。

## 为什么必须用「链接」而不是复制

- **复制**：改一处不会同步，很快就出现 N 份互不一致的 skill。
- **硬链接**：只能对文件，且一旦被「写临时文件 → 重命名替换」（编辑器、Claude、git 都爱这么干）就会断裂。**不要用硬链接。**
- **符号链接 / 联接**：指向*路径*，目标目录里内容怎么变都自动跟随，永久同步。

## 两种链接策略（本技能的核心设计）

| 模式 | 结果 | 适用场景 |
|---|---|---|
| `Whole` 整体链接 | `<agent>/skills` → `~/.claude/skills`（一条链接） | 该 Agent 的 skills 目录本来不存在 / 是空的。最省事，**以后新增 skill 零操作** |
| `PerSkill` 逐技能链接 | `<agent>/skills/<skill>` → `~/.claude/skills/<skill>`（每个 skill 一条） | 该 Agent 自己已经装了私有 skill，不能整目录覆盖 |
| `Auto`（默认） | 目标不存在或是链接 → `Whole`；目标是真实目录 → `PerSkill` | 绝大多数情况直接用这个 |

> 注意：`Whole` 模式下 ~/.claude/skills 里的 `.system`、迁移标记 json 等也会被别的 Agent 看到（一般无害；本机 ZCode/Cursor/WorkBuddy/.agents 就是这么链的）。不想暴露就用 `-Mode PerSkill`（默认已排除 `.system`）。

## 快速开始

技能自带脚本 `scripts/link-agent-skills.ps1`。**先跑 DryRun 预览**，确认无误再真正执行：

```
# 1) 预览（不修改任何东西）
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-skills.ps1" -DryRun

# 2) 正式执行（默认 junction，无需提权、不弹 UAC）
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-skills.ps1"

# 3) 只处理某几个 Agent
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-skills.ps1" -Agents Codex,Cursor,Pi
```

`<skill目录>` 解析为技能所在目录的绝对路径（例如 `C:\Users\<你>\.claude\skills\claude-skill-linker`）。

## 默认目标（Agent 配置目录不存在则自动跳过 = 未安装）

| Agent | 目标 skills 目录 |
|---|---|
| Codex | `~/.codex/skills` |
| ZCode | `~/.zcode/skills` |
| Pi | `~/.pi/agent/skills` |
| DSH (DeepSeek Harness) | `~/.dsh/skills` |
| Agents（共享约定） | `~/.agents/skills` |
| OpenCode | `~/.config/opencode/skill`（或 `skills`，自动择一） |
| Gemini CLI | `~/.gemini/skills` |
| Qwen Code | `~/.qwen/skills` |
| iFlow | `~/.iflow/skills` |
| Cursor | `~/.cursor/skills` |
| Cline | `~/.cline/skills` |
| GitHub Copilot | `~/.copilot/skills` |
| Amazon Q | `~/.aws/amazonq/skills` |
| CodeBuddy | `~/.codebuddy/skills` |
| WorkBuddy | `~/.workbuddy/skills` |
| Qoder | `~/.qoder/skills` |
| Trae CN | `~/.trae-cn/skills` |

> 表里靠后的几个 Agent 的「用户级 skills 目录」属于**尽力而为**：只有该目录已存在时才会被处理；若某 Agent 实际路径不同，用 `-Targets` 指定即可（见下）。

任意目录都可以链，用 `-Targets` 指定（多个用逗号或分号分隔）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/link-agent-skills.ps1" ^
  -Targets "$env:USERPROFILE\.foo\skills;$env:USERPROFILE\.bar\skills"
```

项目级技能库同理：`-Source "D:\proj\.claude\skills" -Targets "D:\proj\.codex\skills"`。

## 脚本行为

对每个目标：

1. 已是「指向源目录的链接」→ 报 `OK`，不动。
2. 是链接但指向别处 / 是真实目录 → 报 `REPLACE`；真实目录先整体改名成 `<名>.bak_<时间戳>`（除非 `-NoBackup`），链接本身则直接删除（**只删链接本身，绝不递归删除它指向的内容**）。
3. 目标父目录（Agent 配置目录）不存在 → `SKIP`（该 Agent 未安装）；加 `-CreateDirs` 则连目录一起建。
4. 源目录不存在 → `ERROR` 退出，不做任何改动。
5. `PerSkill` 模式只链接含 `SKILL.md` 的子目录，跳过 `.` 开头的目录（如 `.system`）；可用 `-Include`/`-Exclude` 通配符过滤。
6. 加 `-Prune` 时，`PerSkill` 模式会清掉目标里「指向源、但源里已删除」的过期链接（不动该 Agent 自己的真实目录）。

输出为英文状态行（`SOURCE / LINKTYPE / MODE / OK / CREATE / REPLACE / BACKUP / LINKED / PRUNE / SKIP / MKDIR / WARN / ERROR / SUMMARY`），便于稳定解析。

## 参数

| 参数 | 说明 |
|---|---|
| `-Source <path>` | 真源目录，默认 `%USERPROFILE%\.claude\skills` |
| `-Targets <p1;p2>` | 自定义目标 skills 目录（覆盖内置表） |
| `-Agents <名字,...>` | 只处理内置表里的这些 Agent（`Codex`、`Cursor`、`Pi`…） |
| `-Mode Auto/Whole/PerSkill` | 链接策略，默认 `Auto` |
| `-LinkType Auto/SymbolicLink/Junction` | 链接类型，默认 `Auto` |
| `-Include` / `-Exclude` | 按 skill 目录名过滤，默认 `*` / `.system` |
| `-DryRun` | 只预览不落盘 |
| `-NoBackup` | 覆盖真实目录时不保留 `.bak_<时间戳>` |
| `-CreateDirs` | Agent 目录不存在时也创建 |
| `-Prune` | 清理过期链接（`PerSkill` 模式） |
| `-NoElevate` | 强制 `SymbolicLink` 却不提权（开发者模式开启时可用） |

## 权限说明（本机关键点）

- **Junction（默认首选）**：NTFS 目录联接，**普通用户即可创建，完全不弹 UAC**。只能用于本地路径（不能指向网络共享 / 网盘挂载点）。
- **SymbolicLink**：需要 `SeCreateSymbolicLinkPrivilege`，来源二选一：管理员令牌（UAC 弹窗）或开启 **Windows 开发者模式**（设置 → 系统 → 开发者选项）。

脚本启动时会探测当前进程能否创建符号链接：

- 能（已开开发者模式）→ 默认用 `SymbolicLink`。
- 不能 → 自动改用 `Junction`，**不弹 UAC、直接成功**（这是本技能相对 `claude-md-linker` 的主要改进）。
- 强行指定 `-LinkType SymbolicLink` 且无权限时，才会用 `Start-Process -Verb RunAs` 提权重跑自身（弹一次 UAC）；加 `-NoElevate` 则不弹窗、逐条报 `ERROR`。

## 验证结果

```
# 看类型：整体链接应显示 <SYMLINKD> / <JUNCTION> 或 lrwxrwxrwx
cmd //c "dir /a C:\Users\%USERNAME%\.codex\skills"
ls -la ~/.zcode/skills ~/.pi/agent/skills

# 看单个 skill 是否可见（内容应与 Claude 侧完全一致）
cat ~/.codex/skills/<某个skill>/SKILL.md

# 实测同步：在 Claude 侧改一个 skill，看目标侧是否立刻可见
echo SYNC_TEST >> ~/.claude/skills/<某个skill>/SKILL.md
tail -n 1 ~/.codex/skills/<某个skill>/SKILL.md   # 应能看到 SYNC_TEST
```

## 日常维护流程

1. **新增 skill**：只往 ~/.claude/skills/ 里加（`/plugin install`、marketplace、手写都行）。
   - `Whole` 模式：**什么都不用做**，所有 Agent 立刻可见。
   - `PerSkill` 模式：重跑一次脚本（可加 `-Prune`）把新 skill 补链上。
2. **删除 skill**：`PerSkill` 模式重跑 `-Mode PerSkill -Prune` 清掉悬空链接。
3. **不要在各 Agent 侧"另建"skill**：写进去的其实落到 ~/.claude/skills（同一份文件）——这是预期行为，但要知道影响面是全体的。

## 排障

| 现象 | 原因与处理 |
|---|---|
| `SKIP ... agent dir not found` | 该 Agent 未安装，或配置目录在别处。用 `-Targets` 指定正确路径，或加 `-CreateDirs`。 |
| `ERROR ... 没有足够的权限` | 强行用了 `-LinkType SymbolicLink`。去掉该参数用默认（junction），或开开发者模式 / 用管理员终端。 |
| 目标目录被换成链接后，Agent 说找不到它自己某个 skill | 那个 skill 原本在该 Agent 私有目录里，被整体替换了。从 `<名>.bak_<时间戳>` 找回，或改用 `-Mode PerSkill`。 |
| Junction 创建失败 / 指向网络路径 | Junction 不支持网络共享、FAT32 等；改用 `-LinkType SymbolicLink`（提权或开发者模式）。 |
| Agent 扫不到链进来的 skill | 少数 Agent 不跟随 reparse point（罕见）。改用 `-Mode PerSkill`，或确认该 Agent 的 skills 路径是否就是表里那个。 |
| 之前是复制粘贴的旧副本，改动不同步 | 直接跑默认命令，脚本会 `REPLACE` 成链接并留下 `.bak_` 备份。 |
| 提权窗口一闪而过、无输出 | 子进程报告写在临时日志里，由父进程回读；若被安全软件拦截，改用管理员终端手动跑一次。 |

## 新增一个 Agent

1. 找到它的用户级 skills 目录（多数约定为 `<agent配置目录>/skills`，个别是 `skill`）。
2. 直接用 `-Targets` 跑一次即可；想纳入默认列表就编辑 `scripts/link-agent-skills.ps1` 里的 `$agentSpecs` 追加一行（`Sub` 可写多个候选目录名，自动择一）。

## 非 Windows（macOS / Linux / WSL）

不需要脚本，一条命令即可（整体链接）：

```
ln -sfn ~/.claude/skills ~/.codex/skills    # 目标不存在时
ln -sfn ~/.claude/skills ~/.cursor/skills
```

逐技能链接：

```
for s in ~/.claude/skills/*/; do
  name="$(basename "$s")"
  [ -f "$s/SKILL.md" ] && ln -sfn "$s" ~/.codex/skills/"$name"
done
```

## 回滚

```
# 只删链接本身，再把备份目录改回来
cmd //c "rmdir C:\Users\%USERNAME%\.codex\skills"
cmd //c "move C:\Users\%USERNAME%\.codex\skills.bak_20261021_151540 C:\Users\%USERNAME%\.codex\skills"
```

> 清理链接时**只能删链接本身**：脚本内部用 `[IO.Directory]::Delete(path, false)` 或 `rmdir` 删除 reparse point，不会递归进源目录，可放心执行。

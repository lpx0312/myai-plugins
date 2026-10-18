---
name: gh-ops
description: 用 gh CLI 完成 GitHub 平台侧的实操任务——建仓库/改仓库、开 PR（含 fork、草稿、body-file）、评审与合并、打 tag 发 release、Actions 触发与看日志、secret/variable、ruleset/分支保护、gh api 直连。当用户说"提到 PR / 开个 PR / 合并 PR / 建仓库 / 把这个目录推上 GitHub / 打 tag / 发版 / release / 看 CI 为啥挂 / 重跑 workflow / 加 secret / 设分支保护 / 调 GitHub API / 批量改 issue"时必须使用。只管 GitHub 平台动作（gh）；本地 git 的 commit/rebase/stash 用 git 本身，镜像同步与镜像查找用 dsync-cli / dhs。
license: MIT
---

# gh-ops — GitHub 平台实操手册

本技能把 `gh`（GitHub CLI）从"会敲两条命令"变成"能安全地把活干完"。
职责边界：**GitHub 平台侧动作走 gh**；**本地仓库动作（commit/rebase/stash/worktree）走 git**；
镜像查找走 dhs、镜像同步走 dsync，不要混进来。

## 铁律（先读，违反必出事）

1. **写操作前先预检**：`bash scripts/preflight.sh`，确认账号、目标仓库、当前分支、是否已有 PR。
2. **仓库显式化**：cwd 不在仓库根时，每条 gh 命令都带 `--repo OWNER/NAME`（或 `-R`），不靠 cwd 猜。
3. **正文一律走文件**：PR/release 正文用 `--body-file` / `--notes-file` 写真实换行，**不要**用 `--body "…\\n…"` 拼。
4. **默认不用 `--fill`**：`--fill` 会把 commit 标题当 PR 正文，评审者看到的是垃圾。显式给 title + body-file。
5. **推送/合并/删除需用户明确授权**：`git push`、`gh pr merge`、`gh release create`、`gh repo delete`、`gh secret delete` 属破坏性或对外可见动作，用户没说要执行就不执行（可以先 `--dry-run`/给命令让用户确认）。
6. **禁止 force push**：除非用户单独、明确批准；批准后只用 `--force-with-lease`。
7. **不代跑交互式命令**：`gh auth login`、`gh repo create`（无参数交互模式）会卡住；缺认证就报出确切前置条件。
8. **凭证不落地**：token 从环境变量或 keyhive（见 skill `keyhive`）取，绝不写进文件、commit、PR 正文、对话记录。
9. **不谎报**：没跑过的 check 不写"已验证"，不存在的截图不外链，没合并的不说"已合并"。
10. **一个 PR 一件事**：不把无关改动塞进同一个分支，不"顺手"改无关文件。

## 0. 预检（每个写任务的第一步）

```bash
bash scripts/preflight.sh            # 账号 / token 来源 / 仓库根 / 分支 / 远端 / 是否已有 PR
```

输出解读见 `references/troubleshooting.md`。

## 1. 任务路由

| 用户说的话 | 读哪个 reference | 一条关键命令 |
|---|---|---|
| 建仓库 / 把这目录推上 GitHub | `references/repo.md` | `gh repo create NAME --source=. --private --push` |
| 改仓库描述/topic/默认分支/可见性 | `references/repo.md` | `gh repo edit --add-topic …` |
| fork / 同步 fork / 克隆 | `references/repo.md` | `gh repo fork --clone` |
| 提 PR / 开 PR / 发 PR | `references/pr.md` | `gh pr create -B main -t "…" -F body.md` |
| 看 PR / 评审 / 回应 review | `references/pr.md` | `gh pr view N --json …` / `gh pr review N --approve` |
| 合并 PR / 开 auto-merge | `references/pr.md` | `gh pr merge N --squash --delete-branch` |
| 打 tag / 发版 / release / 附二进制 | `references/release-tag.md` | `gh release create vX.Y.Z --generate-notes` |
| CI 挂了 / 看日志 / 重跑 / 触发 workflow | `references/actions-secrets.md` | `gh run view ID --log-failed` |
| 加 secret / variable | `references/actions-secrets.md` | `gh secret set NAME --body "$V"` |
| 分支保护 / ruleset | `references/actions-secrets.md` | `gh ruleset list` / `gh api` |
| 批量改 issue / 调任意 API / 分页 | `references/api-jq.md` | `gh api --paginate --jq …` |
| 报错看不懂 | `references/troubleshooting.md` | 按报错原文查表 |

## 2. 核心速查

### 仓库
```bash
gh repo create my-repo --private --source=. --remote=origin --push      # 本地目录 → 远端
gh repo create my-repo --public --clone                                  # 纯新建
gh repo create org/my-repo --private --source=. --push                    # 组织下
gh repo view --json nameWithOwner,visibility,defaultBranchRef,stargazerCount
gh repo edit --description "…" --add-topic ai,cli --default-branch main
gh repo list OWNER --limit 50 --json name,visibility,updatedAt
gh repo delete OWNER/NAME --yes                                          # 需 delete_repo scope
```

### PR
```bash
git push -u origin HEAD                                   # PR 前必须先把分支推上去
gh pr create -B main -H feat/x -t "feat: …" -F /tmp/pr.md # 显式标题正文
gh pr create --draft -t "wip: …" -F /tmp/pr.md            # 草稿（用户明说才用）
gh pr view --json number,url,state,isDraft,mergeable,statusCheckRollup
gh pr checks N --watch --fail-fast
gh pr diff N --patch
gh pr review N --approve -b "LGTM"
gh pr merge N --squash --delete-branch
gh pr list --search "is:open author:@me" --json number,title,url
```

### tag / release
```bash
git tag -a v1.2.0 -m "v1.2.0"          # 附注 tag，不推 --tags 洪水
git push origin v1.2.0
gh release create v1.2.0 --target main --generate-notes -t "v1.2.0" -F notes.md
gh release create v1.2.0-rc1 --prerelease --draft -F notes.md ./dist/*.tar.gz
gh release upload v1.2.0 ./dist/app.zip --clobber
```

### Actions / 配置
```bash
gh run list --limit 10 --json databaseId,workflowName,conclusion,headBranch
gh run view ID --log-failed
gh run rerun ID --failed
gh workflow run ci.yml --ref main -f env=prod
gh secret set MY_TOKEN --body "$MY_TOKEN"    # repo 级；--env/--org 换作用域
gh variable set REGION --body cn-hangzhou
gh ruleset list
```

### API / 结构化输出
```bash
gh api repos/{owner}/{repo} --jq '.stargazers_count'
gh api --paginate repos/O/R/issues --jq '.[] | "\(.number) \(.title)"'
gh api -X POST repos/O/R/issues -f title="Bug" -f body="…" -F labels[]=bug
gh api rate_limit --jq '.rate'
```

## 3. 认证与多账号（本机特有坑）

- 优先级：`GH_TOKEN` > `GITHUB_TOKEN` > `gh auth login` 存在 keyring 的账号。
- **本机现状**：环境变量 `GITHUB_TOKEN`（`ghp_…`，scope 很宽）+ keyring 里的 `gho_…` 同时存在，
  `gh auth status` 会显示两个，"Active account" 永远是环境变量那个。
- 于是：**`gh auth switch` 不生效**。真要切到 keyring 账号，先 `unset GITHUB_TOKEN`（同一 shell 内）。
- 查 token 来源：
  ```bash
  [ -n "${GH_TOKEN:-}" ] && echo "用 GH_TOKEN"
  [ -n "${GITHUB_TOKEN:-}" ] && echo "用 GITHUB_TOKEN"
  gh auth status 2>&1 | grep -E 'account|scopes'
  ```
- 需要新 token / 更细权限（`workflow`、`delete_repo`）时，从 **keyhive** 取，不要向用户要明文：
  `keyhive search github` → 按需 reveal 单个字段 → 只注入命令行环境。
- 只读任务可以完全不建 token：`gh api` 匿名也行，但 rate limit 只有 60/h。

## 4. Windows / Git Bash 坑

- **多行正文**：Git Bash 里 `--body "第一行\n第二行"` 会被原样发出去。用
  `printf '%s\n' … > /tmp/pr.md` 再 `-F /tmp/pr.md`，或用 `bash scripts/pr-body-gen.sh`。
- **中文乱码**：PowerShell/CMD 默认不是 UTF-8，写文件再传；Git Bash 默认 UTF-8 更稳。
- **路径被吃掉**：MSYS 会把 `/api/…` 这类参数当路径改写，必要时前缀 `MSYS_NO_PATHCONV=1`。
- **CRLF**：仓库 `core.autocrlf=true` 时 diff 全是换行噪声，PR 前 `git diff --stat` 确认。
- **`&&` / heredoc**：CMD 不支持，统一用 Git Bash 执行本技能的命令。
- `gh` 位置：`/c/Tools/gh/bin/gh`（v2.65）。找不到就先 `command -v gh`。

## 5. 交付汇报格式

干完活按这个说，别只说"好了"：

```
仓库:   OWNER/NAME（可见性）
分支:   feat/x → main（ahead N / behind M）
PR:     #123 URL（草稿/就绪，检查: 3✔ 0✘ 1⏳）
发布:   v1.2.0 URL（draft/prerelease，附件 n 个）
验证:   实际跑过的命令 + 结果
风险:   未跑/未验证/待人工的项
```

## 6. 与 github-kb 的分工（写 vs 只读）

一句话边界：**本技能负责"改 GitHub"，`github-kb` 负责"查 GitHub + 管本地知识库"。**

| 请求 | 归谁 |
|---|---|
| 建仓库、改仓库设置、删仓库 | **gh-ops** |
| 提 PR、评审、合并、重开、关闭 | **gh-ops** |
| 建 issue / 加标签 / 关闭 issue | **gh-ops** |
| 打 tag、发 release、传附件 | **gh-ops** |
| 触发 workflow、看日志、重跑、secret/variable、ruleset | **gh-ops** |
| 搜 GitHub 上的项目 / issue / PR / 代码 | `github-kb` |
| 读 issue / PR 的正文与评论并总结（只读） | `github-kb` |
| clone 仓库进 KB、维护 `GITHUB_KB.md` 目录 | `github-kb` |
| "GitHub 上有没有人遇到过这个报错" | `github-kb` |
| 发评论、加/删标签、开关 issue/PR、写 `gh api` 的写操作 | **gh-ops** |
| 本地 git 的 commit/rebase/stash | 直接用 git，两个都不管 |

用户一句话里既有"查"又有"改"：先查（github-kb 的检索套路），再改（本技能），
并在汇报里分开说"查到什么"和"改了什么"。

## 7. 取 ID / 打表用 jq，不要用 --template

`--template` 是 Go 模板，会把数值型 ID 渲染成科学计数法（`3.8992700359e+10`），取 run/job 的
databaseId 时必错：

```bash
gh run list --limit 3 --json databaseId,status,conclusion --jq '.[] | "\(.databaseId) \(.status)"'
```

jq 插值 `\(…)` 必须落在 jq 的双引号字符串内，外壳用单引号：
`--jq '"state=\(.state)"'`。

## 8. 实测记录

2026-10-17 在 `lpx0312/gh-ops-selftest`（临时私有仓库，已删）端到端跑通并按结果修订本手册：

| 动作 | 结果 |
|---|---|
| `git init` + `gh repo create --source=. --private --push` | ✅ 仓库建立并推送，default=main |
| 建分支 → commit → `git push -u origin HEAD` | ✅ |
| `scripts/pr-body-gen.sh` → `gh pr create -B main -F` | ✅ PR #1 |
| `gh pr checks --watch --fail-fast`（带 ci.yml） | ✅ test pass 5s |
| `gh pr review --approve`（自己的 PR） | ❌ `Can not approve your own pull request` → 已写入 pr.md |
| `gh pr merge --squash --delete-branch` | ✅ squash 合并 + 远端分支删除 |
| `git tag -a` + `git push origin v0.1.0` + `gh release create`（2 个附件） | ✅ release 带 tar.gz + SHA256SUMS |
| `gh run list --template '{{.databaseId}}'` | ❌ 渲染成 `3.8992700359e+10` → 已改写为 --json/--jq |
| `gh repo delete --yes` | ✅ 随后 `gh repo view` 报 Could not resolve |

## 9. 参考文件

> 相关但不同职责：`github-kb`（只读检索 + 本地知识库 `D:\AI\github-code`）。

- `references/repo.md` — 建/改/迁移/删除仓库、fork、模板、可见性、迁移
- `references/pr.md` — PR 全生命周期、fork PR、评审、合并策略、auto-merge、冲突处理
- `references/release-tag.md` — tag 语义、附注 tag、release 创建/附件/回滚
- `references/actions-secrets.md` — workflow/run/cache、secret/variable、ruleset/分支保护
- `references/api-jq.md` — gh api 用法、`-f`/`-F` 区别、分页、jq/template 模式
- `references/troubleshooting.md` — 报错原文 → 原因 → 处理；Windows 专项
- `assets/pr-body-template.md` — PR 正文骨架
- `assets/release-notes-template.md` — release notes 骨架
- `scripts/preflight.sh` — 环境/仓库/PR 预检
- `scripts/pr-body-gen.sh` — 从 git log + diffstat 生成 PR 正文草稿

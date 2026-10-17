# PR 全生命周期

## 0. 前置：分支必须已在远端
```bash
git switch -c feat/x           # 或 git checkout -b
git status -sb                 # 确认改动范围
git add -A && git commit -m "feat: …"
git push -u origin HEAD        # 【需用户授权】没推上去 PR 必失败
```
失败特征：`Head sha can't be blank` / `No commits between main and feat/x`。

## 1. 创建 PR

```bash
# 标准姿势：显式 title + body 文件（推荐）
bash /path/to/gh-ops/scripts/pr-body-gen.sh --base main --out /tmp/pr.md
$EDITOR /tmp/pr.md
gh pr create --base main --head "$(git branch --show-current)" \
  --title "feat(scope): 一句话说清结果" --body-file /tmp/pr.md

# 草稿（用户明确说"先开草稿"才用）
gh pr create --draft -t "wip: …" -F /tmp/pr.md

# 指定评审人 / 标签 / 里程碑
gh pr create -B main -t "…" -F /tmp/pr.md \
  -r alice,bob -l bug -l "needs-review" -m "v1.2" -a @me

# 先看会发生什么
gh pr create --dry-run -t "…" -F /tmp/pr.md

# 从模板仓库的 PR 模板起步
gh pr create -T .github/pull_request_template.md -t "…" -F /tmp/pr.md
```

**`--fill` 的适用边界**：只在 commit 标题本身就是合格 PR 标题、且单 commit 时用；
多 commit 或需要评审说明时一律手写。`--fill-verbose` 会把所有 commit body 堆进去，通常更糟。

### 跨仓 / fork PR
```bash
# 从自己的 fork 提到上游
gh pr create --repo UPSTREAM/REPO --base main --head mylogin:feat/x -t "…" -F /tmp/pr.md

# 同组织跨仓（gh 的 --head 不支持"组织:分支"），走 REST：
gh api -X POST repos/OWNER/BASE/pulls \
  -f title="…" -F body=@/tmp/pr.md \
  -f base=main -f head="ORG:feat/x" -f head_repo="FORK_REPO" -F draft=false
```

## 2. 查看与评审

```bash
gh pr view                       # 当前分支的 PR
gh pr view 123 --comments
gh pr view 123 --json number,url,state,isDraft,mergeable,mergeStateStatus,reviewDecision,\
additions,deletions,changedFiles,commits,statusCheckRollup,reviewRequests
gh pr diff 123 --patch           # 完整补丁
gh pr diff 123 --name-only
gh pr list --search "is:open review-requested:@me" --json number,title,url
gh pr status
```

### 提交评审
```bash
gh pr review 123 --approve -b "LGTM，已本地验证"
gh pr review 123 --comment -b "两个小问题见下"
gh pr review 123 --request-changes -F /tmp/review.md
gh pr review 123 --approve --body "…"    # 行内评论需走 API：
gh api -X POST repos/O/R/pulls/123/reviews -F event=COMMENT -F body=@/tmp/review.md
```

### 评论 / 编辑 / 指派
```bash
gh pr comment 123 -F /tmp/comment.md
gh pr edit 123 --title "…" --body-file /tmp/pr.md
gh pr edit 123 --add-label bug --remove-label wip --add-reviewer alice --add-assignee @me
gh pr ready 123                  # 草稿 → 就绪
gh pr close 123 --delete-branch  # 关闭（删远端分支需授权）
gh pr reopen 123
```

## 3. 同步远端变更 / 解决冲突

```bash
gh pr checkout 123                       # 本地检出别人的 PR
git fetch origin && git rebase origin/main
git push --force-with-lease              # 【需用户单独批准】
```
冲突时不要自作主张选边：列出冲突文件 + 双方意图，交用户决定。

## 4. 合并

```bash
gh pr checks 123 --watch --fail-fast     # 先确认 check
gh pr merge 123 --squash --delete-branch # 仓库惯例优先（squash/merge/rebase）
gh pr merge 123 --merge   --delete-branch
gh pr merge 123 --rebase
gh pr merge 123 --squash --auto          # 开 auto-merge，等 check 全绿后自动合
gh pr merge 123 --squash --subject "chore: …" --body "…"
gh pr merge 123 --admin                  # 绕过保护：破坏性，必须用户明确要求
```
- `--delete-branch` 会同时删本地和远端分支；本地不在该分支才能删。
- 合并后确认：`gh pr view 123 --json state,mergedAt,mergeCommit`。

## 5. 交付
`gh pr view 123 --json url,number,baseRefName,headRefName,isDraft,mergeable` → 把 URL、base/head、
草稿状态、check 汇总报给用户。没合并的说"未合并"，pending 的说"⏳"。

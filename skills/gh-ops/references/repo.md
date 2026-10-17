# 仓库操作（repo）

前置：`bash ../scripts/preflight.sh`（或至少 `gh auth status` + `command -v gh`）。

## 1. 新建仓库（三条路径，别混）

### A. 已有本地目录 → 远端仓库（最常见）
```bash
cd /path/to/project
git rev-parse --is-inside-work-tree 2>/dev/null || git init -b main   # 未 git 化才 init
git add -A && git commit -m "chore: initial import"                  # 至少一个 commit
gh repo create PROJECT_NAME --private --source=. --remote=origin --push
```
- 可见性必须显式：`--private` / `--public` / `--internal`（组织）。
- `--source=.` 时仓库名默认取目录名；要改名就显式给第一个参数。
- 已经手动 `git remote add origin` 过：`--remote=origin` 会报 already exists → 去掉 `--remote`，
  只 `gh repo create NAME --source=. --push`，或先 `git remote remove origin`。
- 组织仓库：`gh repo create ORG/NAME --private --source=. --push`（需在组织里有建仓权限）。

### B. 纯新建 + 本地克隆
```bash
gh repo create NAME --public --clone --add-readme --gitignore Node --license mit
```
`gh repo license list` 查 license key；`--gitignore` 取 <https://github.com/github/gitignore> 的名字。

### C. 从模板仓库
```bash
gh repo create NAME --template OWNER/TEMPLATE --private --clone
gh repo create NAME --template OWNER/TEMPLATE --include-all-branches --clone
```

**踩坑**：`gh repo create` 无参数 = 交互向导，AI 会卡住，永远显式传参。

## 2. 查看
```bash
gh repo view --json nameWithOwner,description,visibility,defaultBranchRef,stargazerCount,forkCount,isPrivate,createdAt
gh repo view OWNER/NAME --web              # 开浏览器
gh repo list OWNER --limit 100 --json name,visibility,updatedAt,primaryLanguage
gh repo list ORG --archived=false --source
```

## 3. 修改（gh repo edit）

```bash
gh repo edit --description "一句话说明"
gh repo edit --add-topic ai,cli,agent --remove-topic old
gh repo edit --homepage "https://example.com"
gh repo edit --default-branch main
gh repo edit --enable-issues --enable-wiki --enable-discussions
gh repo edit --disable-issues --disable-wiki
gh repo edit --visibility public --accept-visibility-change-consequences   # 危险：公开后记录不可回收
gh repo edit --enable-squash-merge --enable-merge-commit --enable-rebase-merge
gh repo edit --delete-branch-on-merge
gh repo edit --archive                                    # 只读归档
```
读当前 settings：
```bash
gh api repos/O/R --jq '{visibility,has_issues,default_branch,allow_squash_merge,delete_branch_on_merge}'
```

## 4. fork / 同步 / 上游

```bash
gh repo fork OWNER/NAME --clone --remote=true              # fork 并加 upstream 远端
gh repo fork --org ORG                                     # 当前仓库 fork 到组织
gh repo sync                                               # 用上游同步当前 fork 的默认分支
gh repo sync --branch feature-x --source upstream-owner/repo
git remote add upstream https://github.com/OWNER/NAME.git   # 手动补上游
git fetch upstream && git rebase upstream/main
```
> fork 提 PR 见 `pr.md` 的 `--head owner:branch` 与组织内跨仓的特殊写法。

## 5. 克隆 / 重命名 / 转移 / 删除

```bash
gh repo clone OWNER/NAME -- --depth 1
gh repo rename NEW_NAME                       # 会提示改本地 remote，注意旧链接
gh repo rename NEW_NAME --repo OWNER/OLD --yes
gh api -X POST repos/OWNER/NAME/transfer -f new_owner=TARGET   # 转移（需目标同意）
gh repo delete OWNER/NAME --yes               # 需 delete_repo scope；不可恢复
gh repo archive OWNER/NAME --yes              # 优先用 archive 代替 delete
```

## 6. 协作者 / 团队 / 权限

```bash
gh api repos/O/R/collaborators --jq '.[].login'
gh api -X PUT repos/O/R/collaborators/USER -f permission=push     # pull|triage|push|maintain|admin
gh api -X PUT repos/O/R/collaborators/USER -f permission=pull
gh api -X DELETE repos/O/R/collaborators/USER
```

## 7. 其它常用

```bash
gh label clone OWNER/SOURCE_REPO            # 从模板仓库复制 label 体系
gh label list --json name,color,description
gh issue develop 12 --checkout              # 从 issue 建分支（自动命名）
gh browse --branch main                     # 打开网页对应页
gh search repos "topic:agent-skills stars:>500" --limit 20 --json fullName,stargazersCount
```

## 检查清单（建仓后）
- [ ] 有 README / LICENSE / .gitignore
- [ ] description + topics 填了（否则搜不到）
- [ ] 默认分支名符合预期
- [ ] 合并策略与 delete-branch-on-merge 设对
- [ ] 分支保护/ruleset 见 `actions-secrets.md`

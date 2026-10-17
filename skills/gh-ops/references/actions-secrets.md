# Actions / secret / ruleset

## 1. 看 CI

```bash
gh run list --limit 10 --json databaseId,workflowName,status,conclusion,headBranch,event,createdAt
gh run list --workflow ci.yml --branch main --limit 5
gh run view <run-id>                                  # 概况 + 各 job
gh run view <run-id> --log-failed                     # 只失败步骤日志（首选）
gh run view <run-id> --log > /tmp/run.log             # 全量日志（很大）
gh run view <run-id> --job <job-id>                   # 单 job
gh run watch <run-id> --exit-status                   # 等它跑完，失败时非 0 退出
gh workflow list --all                                # 含 disabled
gh workflow view ci.yml
```

常见 conclusion：`success` / `failure` / `cancelled` / `skipped` / `timed_out` / `action_required`。
`action_required` 通常是 fork PR 需维护者批准 workflow。

## 2. 触发 / 重跑 / 取消

```bash
gh workflow run ci.yml --ref main                 # 需 workflow_dispatch 触发器
gh workflow run ci.yml --ref feat/x -f env=prod -f dry_run=true
gh run rerun <run-id>                             # 全部重跑
gh run rerun <run-id> --failed                    # 只重跑失败 job
gh run cancel <run-id>
gh workflow enable ci.yml / gh workflow disable ci.yml
```
没有 `workflow_dispatch` 的 workflow 不能手动触发 → 先加触发器，别用 API 绕。

## 3. 缓存与产物

```bash
gh cache list --limit 20 --json id,key,sizeInBytes,ref
gh cache delete <cache-id>
gh cache delete --all                             # 破坏性，需用户确认
gh run download <run-id> -n artifact-name -D ./out
```

## 4. secret / variable

```bash
# repo 级
gh secret set NAME --body "$VALUE"
gh secret set NAME < ./value.txt              # 或从文件/标准输入
gh secret list
gh secret delete NAME

# environment / org 级
gh secret set NAME --env production --body "$VALUE"
gh secret set NAME --org MYORG --body "$VALUE"
gh secret set NAME --org MYORG --repos repo1,repo2 --body "$VALUE"   # org→指定仓库

# 变量（非敏感配置，明文可读）
gh variable set REGION --body cn-hangzhou
gh variable get REGION
gh variable list
gh variable delete REGION
```
- **secret 值只进不出**：`gh secret list` 只显示名字和更新时间，别指望读回。
- 值走 `--body "$ENV"` 或重定向，不要写在命令历史里（`export HISTIGNORE` 或从 keyhive 直取直传）。
- 需要 token 才能改 secret：`repo` scope 足够；org 级要 `admin:org`。
- Dependabot secret / Codespaces secret 分别走 `gh api repos/O/R/dependabot/secrets`、`/codespaces/secrets`。

## 5. 分支保护 / ruleset

| 平台 | 命令 |
|---|---|
| Rulesets（推荐，新版） | `gh ruleset list` / `gh ruleset view <id>` / `gh ruleset check <branch>` |
| 经典分支保护 | `gh api repos/O/R/branches/main/protection` |

```bash
gh ruleset list --json databaseId,name,target
gh ruleset check main                     # 当前分支命中哪些规则
gh api repos/O/R/branches/main/protection --jq '.required_status_checks.contexts'
```

建/改 ruleset（gh 无写命令，走 API）：
```bash
gh api -X POST repos/O/R/rulesets --input ruleset.json
cat > ruleset.json <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [{ "context": "ci" }] } },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
```

## 6. 只读巡检一条龙
```bash
gh run list --limit 5 --json workflowName,conclusion,headBranch,createdAt
gh pr list --search "is:open review-requested:@me" --json number,title,url
gh api rate_limit --jq '.rate'
gh secret list; gh variable list
```

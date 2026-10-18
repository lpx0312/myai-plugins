# gh api 与结构化输出

## 1. 基本形态
```bash
gh api <endpoint>                     # 默认 GET，输出 JSON
gh api repos/{owner}/{repo}           # {owner}/{repo} 可用当前仓库自动填充
gh api repos/O/R/issues --jq '.[0].title'
gh api graphql -f query='{ viewer { login } }'      # GraphQL
gh api --hostname ghe.example.com repos/O/R         # GitHub Enterprise
```

## 2. `-f` 与 `-F` 的区别（最容易错的地方）

| 写法 | 含义 |
|---|---|
| `-f key=value` | **字符串**字段（永远当 string 发） |
| `-F key=value` | **类型化**：`123`→number，`true`→bool，`@file`→读文件内容 |
| `-F key=@file` | 从文件读值 |
| `--input file.json` | 整个请求体从 JSON 文件读（复杂嵌套首选） |
| `--field key[]=a` | 数组元素 |

```bash
gh api -X POST repos/O/R/issues -f title="Bug: 崩溃" -f body="复现步骤…" -F assignees[]=me
gh api -X POST repos/O/R/pulls -F body=@/tmp/pr.md -f title="…" -f base=main -f head=feat/x
gh api -X PATCH repos/O/R --input repo-patch.json
```
方法：`-X GET|POST|PATCH|PUT|DELETE`。

## 3. 分页
```bash
gh api --paginate repos/O/R/issues --jq '.[].number'
gh api --paginate --slurp repos/O/R/issues --jq 'add | length'    # 所有页合成一个数组
gh api --paginate repos/O/R/pulls --jq '.[] | select(.draft) | .number'
```
默认 30/页；`?per_page=100` 提高，仍要 `--paginate`。

## 4. jq 常用模式
```bash
--jq '.rate'                                  # 单字段
--jq '.[] | .login'                           # 数组映射
--jq '.[] | "\(.number)\t\(.title)"'        # TSV
--jq '[.[] | {n: .number, t: .title}]'        # 重组对象
--jq 'group_by(.state) | map({state: .[0].state, n: length})'
--jq 'sort_by(.updatedAt) | reverse | .[0:5]'
--jq 'select(.mergeable == "MERGEABLE")'
```

## 5. `--json` 字段查询（gh 命令专用，比 jq 稳）

```bash
gh pr view 123 --json number,title,mergeable
gh pr list --json number,title,statusCheckRollup --jq '.[] | select(.statusCheckRollup != [])'
gh repo view --json nameWithOwner,visibility
gh run list --json databaseId,conclusion
```
不确定有哪些字段：**`--json` 后面不写字段**就打印全部可用字段，挑完再收窄（比报错法更省事）。

⚠️ `--template` / `-T` 在 `gh pr create` / `gh issue create` 上是 **PR/issue 正文模板**
（`--template` 指向 `.github/pull_request_template.md` 之类的文件），**不是** Go 模板。
用之前先 `--help` 确认你撞上的是哪一个。

Go 模板替代 jq：
```bash
gh pr list --template '{{range .}}{{.number}}: {{.title}}{{"\n"}}{{end}}'
```

## 6. 幂等 / 批量改
```bash
# 批量给所有 open issue 打 label
gh issue list --state open --limit 200 --json number --jq '.[].number' | \
  xargs -I{} gh issue edit {} --add-label triage

# 批量关闭陈旧 issue
gh issue list --state open --search "updated:<2024-01-01" --json number --jq '.[].number' | \
  xargs -I{} gh issue close {} -c "stale"

# 确认变更（先 dry 一遍：把 gh api 换成 echo）
```
> 批量操作前先 `--jq 'length'` 看命中数量；数字不对就停。

## 7. 限流
```bash
gh api rate_limit --jq '.rate'
gh api rate_limit --jq '.resources | to_entries | map({k: .key, remaining: .value.remaining})'
```
剩 0 就等 reset 时间：`gh api rate_limit --jq '.rate.reset' | xargs -I{} date -d @{}`。
GitHub Actions 里用 `GITHUB_TOKEN` 是 1000/h per repo；PAT 5000/h。

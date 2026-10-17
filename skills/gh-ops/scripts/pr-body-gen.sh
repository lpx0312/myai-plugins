#!/usr/bin/env bash
# pr-body-gen — 从 git log + diffstat 生成 PR 正文草稿（避免 --body 里手拼换行）
# 用法:
#   bash pr-body-gen.sh                    # base=自动探测(origin/HEAD >> main >> master)，输出到 stdout
#   bash pr-body-gen.sh --base develop --out /tmp/pr.md
#   bash pr-body-gen.sh --repo OWNER/NAME  # 只用于提示，不影响生成
set -uo pipefail

base=""
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --out)  out="${2:-}"; shift 2 ;;
    --repo) shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf '不在 git 仓库内\n' >&2; exit 1; }

if [ -z "$base" ]; then
  if git symbolic-ref -q refs/remotes/origin/HEAD >/dev/null 2>&1; then
    base=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')
  elif git show-ref -q --verify refs/remotes/origin/main; then base=main
  elif git show-ref -q --verify refs/remotes/origin/master; then base=master
  else base=$(git rev-parse --abbrev-ref HEAD); fi
fi

branch=$(git rev-parse --abbrev-ref HEAD)
range="$base..HEAD"
commits=$(git log --oneline --no-decorate "$range" 2>/dev/null || true)
stat=$(git diff --stat "$base"...HEAD 2>/dev/null || true)
files=$(git diff --name-only "$base"...HEAD 2>/dev/null | head -40 || true)
ahead=$(git rev-list --count "$range" 2>/dev/null || echo 0)

body=$(cat <<EOF
## 变更内容

<!-- 一段话说清做了什么 -->

## 为什么

<!-- 解决的问题 / Closes #0 -->

## 怎么做

<!-- 关键取舍 -->

## 验证

<!-- 只写真跑过的 -->
- [ ] \`<命令>\` → 结果

## 影响与风险

- 用户可见变化：
- 兼容性 / 迁移：
- 回滚方式：

---

<details>
<summary>分支与提交（自动生成，可删）</summary>

base: \`$base\`  ←  head: \`$branch\`  （$ahead 个提交）

\`\`\`
$commits
\`\`\`

\`\`\`
$stat
\`\`\`

改动文件（前 40）：
\`\`\`
$files
\`\`\`

</details>
EOF
)

if [ -n "$out" ]; then
  printf '%s\n' "$body" > "$out"
  printf '已写入 %s（base=%s, head=%s, %s 个提交）\n' "$out" "$base" "$branch" "$ahead"
  if [ "$ahead" = "0" ]; then printf 'WARN: 该分支相对 %s 没有提交，PR 会被拒绝（No commits between）\n' "$base" >&2; fi
else
  printf '%s\n' "$body"
fi

#!/usr/bin/env bash
# gh-ops preflight — 一次看清 gh 环境 / 认证 / 当前仓库 / PR 状态
# 用法:
#   bash preflight.sh                 # 检查当前目录所属仓库
#   bash preflight.sh OWNER/NAME       # 检查指定仓库
set -uo pipefail

target_repo="${1:-}"
hdr(){ printf '\n== %s ==\n' "$*"; }

hdr "gh"
if command -v gh >/dev/null 2>&1; then
  printf 'path:    %s\n' "$(command -v gh)"
  printf 'version: %s\n' "$(gh --version 2>&1 | head -1)"
else
  printf 'MISSING: 未找到 gh。Windows 装法: winget install GitHub.cli 或解压到 D:\\SystemTools\n'
  exit 1
fi

hdr "token 来源（优先级 GH_TOKEN > GITHUB_TOKEN > keyring）"
if [ -n "${GH_TOKEN:-}" ]; then printf 'GH_TOKEN     已设置（覆盖 keyring 账号）\n'; fi
if [ -n "${GITHUB_TOKEN:-}" ]; then printf 'GITHUB_TOKEN 已设置（覆盖 keyring 账号，gh auth switch 会失效）\n'; fi
if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then printf '两者都为空 → 使用 keyring 里的账号\n'; fi

hdr "认证"
gh auth status 2>&1 | sed 's/^/  /'

hdr "限流"
gh api rate_limit --jq '"  core \(.resources.core.remaining)/\(.resources.core.limit)  graphql \(.resources.graphql.remaining)/\(.resources.graphql.limit)"' 2>/dev/null \
  || printf '  (取不到，可能未认证)\n'

hdr "仓库上下文"
root=""
if root=$(git rev-parse --show-toplevel 2>/dev/null); then
  printf 'root:   %s\n' "$root"
  printf 'branch: %s\n' "$(git rev-parse --abbrev-ref HEAD)"
  printf 'dirty:  %s 个改动\n' "$(git status --porcelain | wc -l | tr -d ' ')"
  printf 'remotes:\n'; git remote -v | sed 's/^/  /'
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ -n "$up" ]; then
    printf 'upstream: %s  (%s)\n' "$up" "$(git rev-list --left-right --count "$up...HEAD" | awk '{print "behind "$1" / ahead "$2}')"
  else
    printf 'upstream: 无（git push -u origin HEAD）\n'
  fi
else
  printf '不是 git 仓库（cwd: %s）\n' "$PWD"
fi

hdr "GitHub 侧"
if [ -n "$target_repo" ]; then repo_arg=(-R "$target_repo"); else repo_arg=(); fi
if gh repo view "${repo_arg[@]}" --json nameWithOwner,visibility,defaultBranchRef,isFork,pushedAt \
     --template 'repo:    {{.nameWithOwner}}  ({{.visibility}}){{"\n"}}default: {{.defaultBranchRef.name}}{{"\n"}}pushed:  {{.pushedAt}}{{"\n"}}' 2>/dev/null; then
  gh pr list "${repo_arg[@]}" --head "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" --state all --limit 3 \
     --json number,state,isDraft,url,title \
     --template '{{range .}}PR:      #{{.number}} {{.state}} draft={{.isDraft}} {{.url}}{{"\n"}}{{end}}' 2>/dev/null \
     || printf 'PR:      (查不到)\n'
else
  printf 'repo:    无法访问（名字错 / 无权限 / 还没建）\n'
fi

hdr "结论提示"
printf '写操作前确认：账号对不对、目标仓库对不对、分支对不对、要推的分支已 commit。\n'

#!/bin/bash
# verify-scripts.sh —— 脚本静态校验（不需要连任何主机）
# 用法：bash tests/verify-scripts.sh   退出码 0 = 全部通过

set -u
cd "$(dirname "$0")/.." || exit 2

fail=0
note() { printf '%-6s %s\n' "$1" "$2"; }

for f in scripts/*.sh; do
  name=$(basename "$f")

  if ! bash -n "$f" 2>/dev/null; then
    note FAIL "$name 语法错误"; fail=1
  else
    note ok "$name 语法"
  fi

  grep -q 'set -u' "$f"        || { note FAIL "$name 缺 set -u"; fail=1; }
  grep -q 'LC_ALL=C' "$f"      || { note FAIL "$name 缺 LC_ALL=C"; fail=1; }
  grep -q '_state' "$f"        || { note FAIL "$name 缺 _state"; fail=1; }
  grep -q '##END' "$f"         || { note FAIL "$name 缺 ##END"; fail=1; }
  grep -q 'CMD:' "$f"          || { note FAIL "$name 缺 CMD 行"; fail=1; }

  if grep -qE '\|\|[[:space:]]*true' "$f"; then
    note FAIL "$name 存在裸 || true"; fail=1
  fi

  if grep -qE 'admin@123|--secret[[:space:]]+["'"'"']?[A-Za-z0-9@._-]{3,}' "$f"; then
    note FAIL "$name 疑似硬编码口令"; fail=1
  fi

  if grep -qE '^\s*[^#]*(tee|mktemp|mkdir) ' "$f"; then
    note FAIL "$name 出现远端落盘类命令"; fail=1
  fi
done

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILED"
fi
exit "$fail"

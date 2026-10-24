#!/bin/bash
# heketi-check.sh —— heketi 只读巡检（L2）
# 用法（不落盘）：ssh root@<heketi-host> 'tr -d "\r" | bash -s' < scripts/heketi-check.sh
# 铁律：只读。不 create/delete/expand/disable/resync。
#
# 凭据：默认从 /etc/heketi/heketi.json 就地读取（只读），不硬编码、不从命令行传。
#       secret 只进入变量，从不回显；打印命令时一律脱敏成 ***。
# 输出契约：见 docs/adr/0002-脚本输出契约.md。
# 超时：轻命令 15s、topology 60s（references/commands.md §7），超时记 SKIP(timeout)。

set -u
export LC_ALL=C LANG=C

_state() { printf '##STATE %s %s%s\n' "$1" "$2" "${3:+ $3}"; }

HK_JSON="${HK_JSON:-/etc/heketi/heketi.json}"
HK_USER="${HK_USER:-admin}"

# 未显式传 secret 时，就地解析 heketi.json 的 jwt.<user>.key
if [ -z "${HK_SECRET:-}" ] && [ -r "${HK_JSON}" ]; then
  HK_SECRET=$(awk -v u="$HK_USER" '
    index($0, "\"" u "\"") > 0 && /:[[:space:]]*\{[[:space:]]*$/ { inbox = 1; next }
    inbox && /"key"[[:space:]]*:/ {
      sub(/.*"key"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); print; exit
    }
  ' "${HK_JSON}" 2>/dev/null)
fi

echo "##META host=$(hostname 2>/dev/null) date=$(date -Is 2>/dev/null) lc=${LC_ALL} user=${HK_USER} cred_src=${HK_JSON}"

if [ -z "${HK_SECRET:-}" ]; then
  echo "##HK-00 CMD: (skipped) 无法从 ${HK_JSON} 取得凭据"
  _state HK-00 SKIP "no-credentials"
  echo "##END"
  exit 0
fi

# heketi-cli 包装：打印命令时一律脱敏
show_hk() { printf 'heketi-cli --user %s --secret *** %s' "${HK_USER}" "$*"; }

run_to() {
  local t="$1" id="$2"; shift 2
  local out rc
  printf '##%s CMD: timeout %ss %s\n' "$id" "$t" "$*"
  out=$(timeout "$t" "$@" 2>&1); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then _state "$id" OK
  elif [ "$rc" -eq 124 ]; then _state "$id" SKIP "timeout=${t}s"
  else _state "$id" ERR "rc=$rc"; fi
  return 0
}

run_hk_to() {
  local t="$1" id="$2"; shift 2
  local out rc
  printf '##%s CMD: timeout %ss %s\n' "$id" "$t" "$(show_hk "$@")"
  out=$(timeout "$t" heketi-cli --user "${HK_USER}" --secret "${HK_SECRET}" "$@" 2>&1); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then _state "$id" OK
  elif [ "$rc" -eq 124 ]; then _state "$id" SKIP "timeout=${t}s"
  else _state "$id" ERR "rc=$rc"; fi
  return 0
}

run_to 15 HK-01 systemctl is-active heketi
run_to 15 HK-01b heketi-cli --version
run_hk_to 15 HK-01c cluster list
run_hk_to 60 HK-02 topology info
run_hk_to 15 HK-04 volume list
run_to 15 HK-04b gluster v list

echo "##END"

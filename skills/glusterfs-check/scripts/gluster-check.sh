#!/bin/bash
# gluster-check.sh —— GlusterFS 只读巡检（L1）
# 用法（不落盘）：ssh root@<host> 'tr -d "\r" | bash -s' < scripts/gluster-check.sh
# 铁律：只读。不写文件、不改配置、不触发 heal、不启停服务。
#
# 输出契约（docs/adr/0002-脚本输出契约.md）：
#   ##<ID> CMD: <实际执行的命令>
#   <命令原始输出>
#   ##STATE <ID> OK | ERR rc=N | SKIP <reason>
#   → ERR / SKIP 在报告里必须落成 SKIP(命令失败|超时|原因)，不得判 PASS。
#
# 预算（docs/adr/0008-巡检预算与卷数上限.md）：
#   HEAL_MAX_VOLUMES=20     卷数超过上限时，超出部分 heal 标 SKIP(budget)
#   HEAL_VOLS="vol_a vol_b" 只查指定卷（优先级高于上限）

set -u
export LC_ALL=C LANG=C

_state() { printf '##STATE %s %s%s\n' "$1" "$2" "${3:+ $3}"; }

run() {
  local id="$1"; shift
  local out rc
  printf '##%s CMD: %s\n' "$id" "$*"
  out=$("$@" 2>&1); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then _state "$id" OK; else _state "$id" ERR "rc=$rc"; fi
  return 0
}

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

in_list() {
  local v="$1"; shift
  [ $# -eq 0 ] && return 0
  for x in "$@"; do [ "$x" = "$v" ] && return 0; done
  return 1
}

# 从当前 $xml 取字段值（字段缺失返回空，不做默认值 —— ADR-0005）
pick() { printf '%s' "$xml" | sed -n "s:.*<$1>\([0-9]*\)</$1>.*:\1:p" | head -1; }

echo "##META host=$(hostname 2>/dev/null) date=$(date -Is 2>/dev/null) lc=${LC_ALL}"

run L1-01 systemctl is-active glusterd
run L1-02 gluster --version
run L1-02b rpm -q glusterfs-server
run L1-03 gluster peer status
run_to 60 L1-04 gluster v info --xml
run_to 60 L1-05 gluster v status --xml

HEAL_MAX="${HEAL_MAX_VOLUMES:-20}"
idx=0
for v in $(gluster v list 2>/dev/null); do
  idx=$((idx + 1))

  if ! xml=$(gluster v info "$v" --xml 2>&1); then
    printf '%s\n' "$xml"
    _state "L1-13[$v]" SKIP "no-data"
    _state "L1-07[$v]" SKIP "no-data"
    continue
  fi

  rep=$(pick replicaCount)
  arb=$(pick arbiterCount)
  disp=$(pick disperseCount)
  snap=$(pick snapshotCount)

  # L1-13 快照数量
  if [ -z "$snap" ]; then
    _state "L1-13[$v]" SKIP "field-missing:snapshotCount"
  else
    printf '##L1-13 vol=%s snapshotCount=%s\n' "$v" "$snap"
    _state "L1-13[$v]" OK
  fi

  # L1-07 需要先知道拓扑；字段缺失不猜默认值
  if [ -z "$rep" ] || [ -z "$arb" ] || [ -z "$disp" ]; then
    _state "L1-07[$v]" SKIP "unsupported:missing-type-fields"
    continue
  fi
  printf '##L1-07 vol=%s replica=%s arbiter=%s disperse=%s\n' "$v" "$rep" "$arb" "$disp"

  if [ "$rep" -le 1 ] && [ "$arb" -eq 0 ] && [ "$disp" -le 1 ]; then
    _state "L1-07[$v]" SKIP "distribute-only"
    continue
  fi

  if ! in_list "$v" ${HEAL_VOLS:-}; then
    _state "L1-07[$v]" SKIP "budget:not-in-HEAL_VOLS"
    continue
  fi

  if [ -z "${HEAL_VOLS:-}" ] && [ "$idx" -gt "$HEAL_MAX" ]; then
    _state "L1-07[$v]" SKIP "budget:volumes>${HEAL_MAX}"
    continue
  fi

  run_to 120 "L1-07[$v]" gluster v heal "$v" info summary --xml
done

echo "##END"

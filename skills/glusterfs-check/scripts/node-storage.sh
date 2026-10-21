#!/bin/bash
# node-storage.sh —— 单台存储主机的 brick 容量/挂载只读检查（L1-09/10/11/12）
# 用法：ssh root@<brick-host> 'tr -d "\r" | bash -s' < scripts/node-storage.sh
# 铁律：只读。不 mount、不改 LVM、不写文件。
#
# 输出契约见 docs/adr/0002-script-output-contract.md。
# 注意：本脚本只能证明"本机现有砖的状态"；"该有砖却没有砖"必须由 L1-04/L1-05 的
# 集群视图交叉判断，不能因为 ##NO_BRICK_DIRS 就判 PASS。

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

echo "##META host=$(hostname 2>/dev/null) date=$(date -Is 2>/dev/null) lc=${LC_ALL}"

dirs=$(ls -d /var/lib/heketi/mounts/vg_*/brick_*/brick 2>/dev/null)
if [ -z "${dirs}" ]; then
  echo "##L1-11 CMD: (none) ls -d /var/lib/heketi/mounts/vg_*/brick_*/brick"
  _state L1-11 SKIP "no-brick-dir-on-host"
  echo "##NO_BRICK_DIRS"
  echo "##END"
  exit 0
fi

# L1-11 判据 C：输出本机砖清单，供与 L1-04 的期望清单求差集
echo "##BRICKLIST count=$(printf '%s\n' ${dirs} | grep -c .)"
printf '%s\n' ${dirs}
echo "##STATE BRICKLIST OK"

# L1-11 逐个 brick 校验挂载来源；findmnt 失败（目录不存在/未挂载）同样按异常上报
for d in ${dirs}; do
  if out=$(findmnt -n -T "${d}" -o TARGET,SOURCE,FSTYPE 2>&1); then
    printf '%s\n' "$out"
    echo "##STATE L1-11[${d}] OK"
  else
    printf '%s\n' "$out"
    echo "##STATE L1-11[${d}] ERR mount-check-failed"
  fi
done

run L1-09 df -P -B1 ${dirs}
run L1-09i df -P -i ${dirs}
run L1-10 lvs --noheadings -o lv_name,vg_name,pool_lv,lv_size,data_percent,metadata_percent
# VGS 仅作参考，不进 L1-12 判据；L1-12 由 lvs 的 lv_size 聚合得出
run VGS vgs --noheadings -o vg_name,vg_size,vg_free

echo "##END"

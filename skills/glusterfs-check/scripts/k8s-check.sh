#!/bin/bash
# k8s-check.sh —— Kubernetes 侧只读巡检（L3）
# 用法：bash scripts/k8s-check.sh（在持有目标 kubeconfig 的机器上执行，不落盘）
# 前置：kubectl 的 current-context 必须是用户点名的集群；脚本第一步会打印，先核对再分析。
# 铁律：只读。不 apply/delete/edit/patch/scale/exec。
#
# 命令形态遵循 references/commands.md 白名单：一律 `-o json`（ADR-0003）。
# K8S-02（SC Secret type）依赖 SC 里的 secretName/secretNamespace，需先解析本脚本的
# K8S-01 输出，再由分析阶段单独执行：
#   kubectl -n <ns> get secret <name> -o jsonpath='{.type}'
#
# 输出契约：见 docs/adr/0002-script-output-contract.md。JSON 体积可能较大，
# 每个块后附 ##SIZE 行，超限时由报告侧截断并注明。

set -u
export LC_ALL=C LANG=C

_state() { printf '##STATE %s %s%s\n' "$1" "$2" "${3:+ $3}"; }

run_json() {
  local id="$1"; shift
  local out rc bytes
  printf '##%s CMD: %s\n' "$id" "$*"
  out=$(timeout 60 "$@" 2>&1); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  bytes=$(printf '%s' "$out" | wc -c | tr -d ' ')
  printf '##SIZE %s bytes=%s\n' "$id" "$bytes"
  if [ "$rc" -eq 0 ]; then _state "$id" OK
  elif [ "$rc" -eq 124 ]; then _state "$id" SKIP "timeout=60s"
  else _state "$id" ERR "rc=$rc"; fi
  return 0
}

echo "##META host=$(hostname 2>/dev/null) date=$(date -Is 2>/dev/null) lc=${LC_ALL}"

run_json CTX kubectl config current-context
run_json K8S-01 kubectl get sc -o json
run_json K8S-03 kubectl get pvc -A -o json
run_json K8S-03b kubectl get pv -o json
run_json K8S-05 kubectl get events -A --field-selector type=Warning -o json

echo "##END"

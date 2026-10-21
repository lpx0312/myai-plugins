#!/usr/bin/env bash
# dir-manifest.sh — 跨平台目录清单生成/对比（Linux / Windows Git Bash 通用）
# 解决跨机器（如本地 Windows vs 远程 Linux）对比目录差异：两端各自 gen 出清单，
# 只传清单（文本）回来，本地 cmp 得出差异报告。不依赖 rsync。
#
# 清单行格式: "<md5> <相对路径>"（路径可含空格/中文），LF 换行，两端格式统一。
# 注意: 符号链接与空目录不进清单（find -type f）；需要对比它们时用
#       diff -rq --no-dereference 直接比。

set -u

usage() {
    cat <<'EOF' >&2
用法:
  dir-manifest.sh gen <目录>                生成清单到 stdout（重定向到文件保存）
  dir-manifest.sh cmp <清单A> <清单B>        对比两份清单，输出差异报告
示例:
  dir-manifest.sh gen /data/app > a.manifest
  dir-manifest.sh cmp a.manifest b.manifest
退出码: gen 0=成功 2=错误; cmp 0=一致 1=有差异 2=错误
EOF
    exit 2
}

die() { echo "ERROR: $*" >&2; exit 2; }

cmd_gen() {
    local dir=$1
    [ -d "$dir" ] || die "不是目录: $dir"
    (
        cd "$dir" || exit 2
        # md5sum 输出 "<hash><空格><空格或*>path"：剥掉标记统一为 "<hash><空格>path"
        find . -type f -exec md5sum -- {} + 2>/dev/null \
            | sed -E 's/^([0-9a-f]{32}) [ *]/\1 /' \
            | sort -k2
    )
}

cmd_cmp() {
    local fa=$1 fb=$2
    [ -f "$fa" ] || die "清单不存在: $fa"
    [ -f "$fb" ] || die "清单不存在: $fb"
    # 行格式 "<32位hash><空格><路径>"：路径从第 34 列起，兼容含空格路径
    # FNR==NR 圈定第一个清单（同一路径自比也正确）
    awk '
        FNR == NR { a[substr($0, 34)] = $1; next }
        { b[substr($0, 34)] = $1 }
        END {
            na = 0; oa = 0; d = 0
            for (p in a) {
                na++
                if (p in b) {
                    if (a[p] != b[p]) { printf "DIFF      %s  [%s -> %s]\n", p, a[p], b[p]; d++ }
                } else { printf "ONLY-IN-A %s\n", p; oa++ }
            }
            nb = 0; ob = 0
            for (p in b) { nb++; if (!(p in a)) { printf "ONLY-IN-B %s\n", p; ob++ } }
            printf "SUMMARY: A=%d B=%d same=%d diff=%d only-in-A=%d only-in-B=%d\n", \
                   na, nb, na - oa - d, d, oa, ob
            exit ((oa + ob + d) > 0) ? 1 : 0
        }
    ' "$fa" "$fb"
}

[ $# -ge 1 ] || usage
case $1 in
    gen) [ $# -eq 2 ] || usage; cmd_gen "$2" ;;
    cmp) [ $# -eq 3 ] || usage; cmd_cmp "$2" "$3" ;;
    *)   usage ;;
esac

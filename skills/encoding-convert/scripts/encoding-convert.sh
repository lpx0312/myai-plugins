#!/usr/bin/env bash
# encoding-convert.sh — 目录级文件编码/换行符/BOM 检测与批量转换（目标: UTF-8 + LF + 无 BOM）
# 默认只检测不修改；--apply 才写文件；默认生成 .bak 备份。
# 依赖: file iconv sed grep (Git Bash 与 Linux GNU 系均自带)
set -u

VERSION="1.0.0"

TARGET_DIR=""
APPLY=false
BACKUP=true
KEEP_BOM=false
KEEP_EOL=false
EXT_LIST=""      # 逗号分隔扩展名白名单（可选，默认所有文本文件）
FROM_EXTRA=""    # 逗号分隔额外源编码（默认尝试 GBK GB18030）

# 默认排除目录（版本控制/依赖/构建产物/IDE）
DEFAULT_EXCLUDES=".git .svn .hg node_modules target build dist __pycache__ .idea .vscode .gradle out bin"
EXTRA_EXCLUDES=""

# Windows 专属文件：编码与换行都完全不动
# 原因: .bat/.cmd 的 cmd.exe 解析对 LF 有坑且中文依赖 GBK 代码页；
#       .ps1/.vbs 同样绑定本地代码页；VS 的 .sln/.csproj 要求 BOM+CRLF
WIN_KEEP_EXT="bat cmd ps1 ps1m psm1 vbs sln csproj vbproj fsproj"

# ============================
# 帮助
# ============================
usage() {
  cat <<EOF
Usage: encoding-convert.sh [options] <target_dir>

检测目录下所有文本文件的编码/换行符/BOM，并可批量转换为 UTF-8 + LF + 无 BOM。
默认只检测（dry-run），加 --apply 才实际修改文件。

Options:
  --apply            实际执行转换（默认仅检测）
  --no-backup        转换时不生成 .bak 备份（默认生成）
  --ext a,b,c        只处理指定扩展名（默认所有识别为文本的文件）
  --exclude d1,d2    追加排除目录（默认已排除: $DEFAULT_EXCLUDES）
  --from ENC,...     追加源编码尝试列表（默认 GBK GB18030，如 BIG5,SHIFT_JIS）
  --keep-bom         保留 UTF-8 BOM（默认去除）
  --keep-eol         不转换换行符，只转编码（默认 CRLF -> LF）
  -h, --help         显示帮助

Examples:
  encoding-convert.sh ./src                    # 只检测，输出清单
  encoding-convert.sh --apply ./src            # 执行转换（带 .bak 备份）
  encoding-convert.sh --ext java,xml ./src     # 只处理 .java/.xml
  encoding-convert.sh --apply --from BIG5 ./src
EOF
}

# ============================
# 参数解析
# ============================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     APPLY=true; shift ;;
    --no-backup) BACKUP=false; shift ;;
    --keep-bom)  KEEP_BOM=true; shift ;;
    --keep-eol)  KEEP_EOL=true; shift ;;
    --ext)       EXT_LIST="$2"; shift 2 ;;
    --exclude)   EXTRA_EXCLUDES="$2"; shift 2 ;;
    --from)      FROM_EXTRA="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "Unknown option: $1"; usage; exit 1 ;;
    *)           TARGET_DIR="$1"; shift ;;
  esac
done

[[ -z "$TARGET_DIR" ]] && { usage; exit 1; }
[[ -d "$TARGET_DIR" ]] || { echo "Directory not found: $TARGET_DIR"; exit 1; }

# ============================
# 检测函数
# ============================
get_charset() {   # file -bi 提取 charset；二进制/未知时可能为空或 binary/unknown-8bit
  file -bi "$1" 2>/dev/null | sed -n 's/.*charset=\(.*\)$/\1/p'
}

get_mime() {
  file -b --mime-type "$1" 2>/dev/null
}

has_utf8_bom() {
  local h
  h="$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')"
  [[ "$h" == "efbbbf"* ]]
}

has_cr() {
  LC_ALL=C grep -q $'\r' "$1" 2>/dev/null
}

# 源编码候选（按 file 报告分派；未知编码走 GBK 系启发）
# 返回空串 = 已是 UTF-8/us-ascii 无需转码
src_candidates() {
  local cs="$1"
  case "$cs" in
    utf-8|us-ascii|ascii)      echo "" ;;
    utf-16le)                  echo "UTF-16LE" ;;
    utf-16be)                  echo "UTF-16BE" ;;
    utf-16*)                   echo "UTF-16 UTF-16LE UTF-16BE" ;;
    *)                         echo "GBK GB18030 ${FROM_EXTRA//,/ }" ;;
  esac
}

# ============================
# 统计
# ============================
TOTAL=0; N_CONV=0; N_TODO=0; N_SKIP=0; N_BIN=0; N_WIN=0; N_EXT=0; N_FAIL=0

report() { # fmt...
  printf '%s\n' "$*"
}

# ============================
# 单文件处理
# ============================
process_file() {
  local f="$1"
  TOTAL=$((TOTAL+1))

  local base ext
  base="${f##*/}"
  if [[ "$base" == *.* ]]; then ext="${base##*.}"; ext="${ext,,}"; else ext=""; fi

  # --ext 白名单（最先过滤，静默跳过不刷屏）
  if [[ -n "$EXT_LIST" ]]; then
    local ok=""
    IFS=',' read -ra _arr <<< "$EXT_LIST"
    for e in "${_arr[@]}"; do
      e="${e,,}"; e="${e#.}"
      [[ "$e" == "$ext" ]] && ok=1
    done
    if [[ -z "$ok" ]]; then
      N_EXT=$((N_EXT+1))
      return
    fi
  fi

  # Windows 专属文件完全跳过
  if [[ " $WIN_KEEP_EXT " == *" $ext "* ]]; then
    N_WIN=$((N_WIN+1))
    printf '%-58s %s\n' "$f" "[SKIP-WIN] Windows 专属文件，编码/换行均不动"
    return
  fi

  # 空文件跳过
  if [[ ! -s "$f" ]]; then
    N_SKIP=$((N_SKIP+1))
    printf '%-58s %s\n' "$f" "[SKIP] empty"
    return
  fi

  local mime cs
  mime="$(get_mime "$f")"
  cs="$(get_charset "$f")"

  # UTF-16 BOM 优先识别（Git Bash 的 file 会把 UTF-16 判成 octet-stream）
  local head2
  head2="$(head -c 2 "$f" | od -An -tx1 | tr -d ' \n')"
  if [[ "$head2" == "fffe" ]]; then
    mime="text/plain"; cs="utf-16le"
  elif [[ "$head2" == "feff" ]]; then
    mime="text/plain"; cs="utf-16be"
  fi

  # 二进制判定
  local is_text=0
  case "$mime" in
    text/*) is_text=1 ;;
    application/json|application/xml|application/javascript|application/x-shellscript|application/x-python|application/yaml|application/x-yaml|application/toml) is_text=1 ;;
    *)
      case "$cs" in
        ""|binary) is_text=0 ;;
        *) is_text=1 ;;   # unknown-8bit / iso-8859-1 等仍视为文本（GBK 常被误报）
      esac
      ;;
  esac
  if [[ $is_text -eq 0 ]]; then
    N_BIN=$((N_BIN+1))
    printf '%-58s %s\n' "$f" "[SKIP-BIN] $mime"
    return
  fi

  local cands bom cr
  cands="$(src_candidates "$cs")"
  has_utf8_bom "$f" && bom=1 || bom=0
  has_cr "$f" && cr=1 || cr=0

  local disp_cs disp_eol disp_bom
  disp_cs="${cs:-unknown}"
  [[ $cr -eq 1 ]] && disp_eol="CRLF" || disp_eol="LF"
  disp_bom=""
  [[ $bom -eq 1 ]] && disp_bom="BOM"
  # UTF-16 转换后 iconv 会产出 UTF-8 BOM，也算待去除项
  if [[ $KEEP_BOM == false && "$cands" == *UTF-16* ]]; then disp_bom="BOM"; fi

  # 判断是否需要动作
  local need_enc=0 need_bom=0 need_eol=0
  [[ -n "$cands" ]] && need_enc=1
  [[ $bom -eq 1 && $KEEP_BOM == false ]] && need_bom=1
  [[ $cr -eq 1 && $KEEP_EOL == false ]] && need_eol=1

  if [[ $need_enc -eq 0 && $need_bom -eq 0 && $need_eol -eq 0 ]]; then
    N_SKIP=$((N_SKIP+1))
    printf '%-58s %s\n' "$f" "[SKIP] $disp_cs $disp_eol, 已达标"
    return
  fi

  if [[ $APPLY == false ]]; then
    local plan=""
    [[ $need_enc -eq 1 ]] && plan="${plan}utf8<-${cands%% *} "
    [[ -n "$disp_bom" && $KEEP_BOM == false ]] && plan="${plan}去BOM "
    [[ $need_eol  -eq 1 ]] && plan="${plan}CRLF->LF"
    N_TODO=$((N_TODO+1))
    printf '%-58s %s\n' "$f" "[TODO] $disp_cs $disp_eol $disp_bom | ${plan}"
    return
  fi

  # ---- 实际转换 ----
  local tmp src ok_src=""
  tmp="$(mktemp)"
  if [[ $need_enc -eq 1 ]]; then
    for src in $cands; do
      if iconv -f "$src" -t UTF-8 "$f" > "$tmp" 2>/dev/null; then ok_src="$src"; break; fi
    done
    if [[ -z "$ok_src" ]]; then
      rm -f "$tmp"
      N_FAIL=$((N_FAIL+1))
      printf '%-58s %s\n' "$f" "[FAIL] 无法从候选编码($cands)转换"
      return
    fi
  else
    cat "$f" > "$tmp" || { rm -f "$tmp"; N_FAIL=$((N_FAIL+1)); printf '%-58s %s\n' "$f" "[FAIL] read error"; return; }
  fi

  # 统一处理 BOM：覆盖两种来源 —— 原生 UTF-8 BOM、UTF-16 转换产出的 BOM
  if [[ $KEEP_BOM == false ]] && has_utf8_bom "$tmp"; then
    sed -i '1s/^\xef\xbb\xbf//' "$tmp"
  fi
  [[ $need_eol -eq 1 ]] && sed -i 's/\r$//' "$tmp"

  # 回读校验：结果必须是合法 UTF-8（用 stdout 重定向，libiconv 不认 -o）
  if ! iconv -f UTF-8 -t UTF-8 "$tmp" > /dev/null 2>&1; then
    rm -f "$tmp"
    N_FAIL=$((N_FAIL+1))
    printf '%-58s %s\n' "$f" "[FAIL] 转换结果不是合法 UTF-8"
    return
  fi

  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
    N_SKIP=$((N_SKIP+1))
    printf '%-58s %s\n' "$f" "[SKIP] 内容无实际变化"
    return
  fi

  if [[ $BACKUP == true && ! -f "${f}.bak" ]]; then
    cp -p "$f" "${f}.bak"
  fi

  cat "$tmp" > "$f"   # cat 写回而非 mv，保留原文件权限/属主
  rm -f "$tmp"

  local done_info=""
  [[ -n "$ok_src" ]] && done_info="${ok_src}->UTF-8 "
  { [[ $KEEP_BOM == false ]] && { [[ $bom -eq 1 ]] || [[ "$ok_src" == *UTF-16* ]]; }; } && done_info="${done_info}去BOM "
  [[ $need_eol -eq 1 ]] && done_info="${done_info}LF"
  N_CONV=$((N_CONV+1))
  printf '%-58s %s\n' "$f" "[OK] ${done_info}$([[ $BACKUP == true ]] && echo ' (bak)')"
}

# ============================
# 主流程
# ============================
EXCLUDE_ARGS=()
for d in $DEFAULT_EXCLUDES; do
  EXCLUDE_ARGS+=( -o -name "$d" )
done
if [[ -n "$EXTRA_EXCLUDES" ]]; then
  IFS=',' read -ra _ex <<< "$EXTRA_EXCLUDES"
  for d in "${_ex[@]}"; do EXCLUDE_ARGS+=( -o -name "${d// /}" ); done
fi

echo "Target: $TARGET_DIR  Mode: $([[ $APPLY == true ]] && echo APPLY || echo DRY-RUN)$( [[ $APPLY == true ]] && { [[ $BACKUP == true ]] && echo " (+backup)"; } )"
echo "----"

while IFS= read -r -d '' f; do
  process_file "$f"
done < <(find "$TARGET_DIR" \( -type d \( -name . "${EXCLUDE_ARGS[@]}" \) -o -name '*.bak' \) -prune -o -type f -print0 2>/dev/null)

echo "===="
echo "SUMMARY: total=$TOTAL converted=$N_CONV todo=$N_TODO skip=$N_SKIP skip-bin=$N_BIN skip-win=$N_WIN skip-ext=$N_EXT fail=$N_FAIL"
if [[ $N_FAIL -gt 0 ]]; then exit 2; fi
exit 0

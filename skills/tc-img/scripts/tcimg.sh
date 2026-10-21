#!/usr/bin/env bash
# tcimg — 上传图片到 Chevereto 图床（API v1），输出 markdown 外链
# 依赖: bash curl jq；--clip 模式另需 Windows PowerShell
# 环境变量（谁用谁设置，token 禁止写进文件/git/对话正文）:
#   TCIMG_URL    Chevereto 站点根地址（不带尾斜杠，如 https://img.example.com）
#   TCIMG_TOKEN  用户 API key（图床网页 Settings → API 生成）
# 注意: 用哪个地址上传，返回的图链就是哪个 host —— 想让文档随处可看就填公网地址。
set -euo pipefail

PROG=tcimg
IMG_EXTS='png jpg jpeg gif bmp webp'

usage() { cat <<'EOF'
用法: tcimg [选项] [<图片|目录|glob> ...]     # 文件/批量/目录任选
      tcimg --clip [选项]                      # 上传 Windows 剪贴板里的图片

选项:
  --clip        从剪贴板取图（截图工具直接进剪贴板的场景）
  --album <ID>  上传到指定相册（Chevereto album_id；默认不指定）
  --clean       上传成功且直链校验通过后删除本地源文件
  -h, --help    帮助

输入形态:
  文件路径      单个/多个图片文件，Windows 风格路径（D:\a.png）自动转换
  glob          通配符，如 dir/*.png（路径含空格时请直接引号传文件，别走 glob）
  目录          取该目录下最新修改的一张图片
  --clip        剪贴板（仅 Windows）

输出: 每张图两行 —— ![alt](直链) 和纯 URL；结尾 SUMMARY 统计
退出码: 0=全部成功  1=有失败  2=环境/用法错误
EOF
}

die() { echo "$PROG: $*" >&2; exit 2; }

for c in curl jq; do command -v "$c" >/dev/null 2>&1 || die "缺少依赖: $c"; done
[ -n "${TCIMG_URL:-}" ]   || die "TCIMG_URL 未设置（Chevereto 站点根地址，如 https://img.example.com，不带尾斜杠）"
[ -n "${TCIMG_TOKEN:-}" ] || die "TCIMG_TOKEN 未设置（图床网页 Settings → API 生成的用户 key）"
case "$TCIMG_URL" in */) die "TCIMG_URL 末尾不要带 /";; esac

CLIP=0; ALBUM=""; CLEAN=0; ARGS=(); FAIL_INPUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --clip)  CLIP=1 ;;
    --album) [ $# -ge 2 ] || die "--album 需要一个相册 ID 参数"; ALBUM=$2; shift ;;
    --clean) CLEAN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "未知选项: $1（-h 看帮助）" ;;
    *)  ARGS+=("$1") ;;
  esac
  shift
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FILES=()

# ---- 剪贴板（仅 Windows，必须 -STA 否则 GetImage 不可靠）----
if [ "$CLIP" -eq 1 ]; then
  [ ${#ARGS[@]} -eq 0 ] || die "--clip 模式不要再给文件参数"
  command -v powershell >/dev/null 2>&1 || die "--clip 仅支持 Windows（需要 PowerShell）"
  f="$TMP_DIR/clip-$(date +%Y%m%d%H%M%S).png"
  win=$(cygpath -w "$f" 2>/dev/null || echo "$f")
  powershell -NoProfile -STA -Command '
    Add-Type -AssemblyName System.Windows.Forms
    $img=[System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $img) { exit 1 }
    Add-Type -AssemblyName System.Drawing
    $img.Save("'"$win"'",[System.Drawing.Imaging.ImageFormat]::Png)
  ' || die "剪贴板里没有图片（或正被其他程序占用）"
  FILES+=("$f")
fi

# ---- 文件 / 目录 / glob ----
if [ ${#ARGS[@]} -gt 0 ]; then
  [ "$CLIP" -eq 0 ] || die "--clip 模式不要再给文件参数"
  shopt -s nullglob nocaseglob
  for a in "${ARGS[@]}"; do
    p=$a
    command -v cygpath >/dev/null 2>&1 && p=$(cygpath -u "$a" 2>/dev/null || echo "$a")
    if [ -f "$p" ]; then
      FILES+=("$p")
    elif [ -d "$p" ]; then
      latest=$(find "$p" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                 -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
                 -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
      if [ -n "$latest" ]; then
        FILES+=("$latest")
        echo "[dir] 取目录最新一张: $latest" >&2
      else
        echo "$PROG: 目录里没有图片($IMG_EXTS): $a" >&2; FAIL_INPUT=1
      fi
    elif [[ "$p" == *[\*\?\[]* ]]; then
      n=0
      for g in $p; do [ -f "$g" ] && { FILES+=("$g"); n=$((n+1)); }; done
      [ "$n" -gt 0 ] || { echo "$PROG: 没有匹配到文件: $a" >&2; FAIL_INPUT=1; }
    else
      echo "$PROG: 文件不存在: $a" >&2; FAIL_INPUT=1
    fi
  done
  shopt -u nullglob nocaseglob
fi

[ ${#FILES[@]} -gt 0 ] || die "没有可上传的文件（-h 看用法）"

# ---- 上传单张：成功 stdout 输出直链；失败 stderr 输出原因 ----
upload_one() {
  local f=$1 body="$TMP_DIR/resp.json" code msg base safe ext src
  # 统一先 cp 到纯 ASCII 临时路径再上传（Windows 专属坑）：
  #  mingw32 curl 的 fopen 走 ANSI(GBK) 代码页，路径含中文时须靠 MSYS 参数转换才能匹配
  #  NTFS 文件名；但同一 -F 里 multipart filename 又必须 ASCII（GBK 字节会被 UTF-8 服务端
  #  MySQL 拒收 400）——两者对字节的要求冲突。落到 ASCII 路径后路径/filename 双双恒定，
  #  任何 中文目录/中文文件名/Windows风格路径 组合都稳定。原名保留在 md 的 alt 里。
  base=$(basename "$f")
  safe=$(printf '%s' "${base%.*}" | LC_ALL=C tr -cd 'A-Za-z0-9._-' | cut -c1-60)
  ext=${base##*.}
  case "$ext" in [A-Za-z0-9]*) ;; *) ext=png ;; esac
  [ -n "$safe" ] || safe="img-$(date +%Y%m%d%H%M%S)"
  src="$TMP_DIR/up-$$-$RANDOM$RANDOM.${ext}"
  cp -- "$f" "$src"
  # ;filename= 会让 MSYS 对 curl 参数的 POSIX→Windows 路径转换失效（分号打断识别，
  # curl 26 读不到文件），必须主动转成 Windows 原生正斜杠路径绕过转换；Linux 无 cygpath 原样。
  command -v cygpath >/dev/null 2>&1 && src=$(cygpath -m "$src")
  if [ -n "$ALBUM" ]; then
    code=$(curl -sS --connect-timeout 15 --max-time 120 -o "$body" -w '%{http_code}' \
      -X POST "$TCIMG_URL/api/1/upload" -F "source=@$src;filename=${safe}.${ext}" -F "key=$TCIMG_TOKEN" -F "album_id=$ALBUM") || return 1
  else
    code=$(curl -sS --connect-timeout 15 --max-time 120 -o "$body" -w '%{http_code}' \
      -X POST "$TCIMG_URL/api/1/upload" -F "source=@$src;filename=${safe}.${ext}" -F "key=$TCIMG_TOKEN") || return 1
  fi
  if [ "$code" = 200 ] && jq -e '(.status_code==200) and (.image.url|type=="string")' "$body" >/dev/null 2>&1; then
    jq -r '.image.url' "$body"
  else
    msg=$(jq -r '.error.message // empty' "$body" 2>/dev/null || true)
    echo "上传失败 HTTP $code ${msg:-$(head -c 200 "$body" 2>/dev/null | tr -d '\n')}" >&2
    return 1
  fi
}

verify_url() { # 直链 HEAD 校验，2xx/3xx 视为通过
  local c
  c=$(curl -skI --connect-timeout 10 --max-time 30 -o /dev/null -w '%{http_code}' "$1") || return 1
  case "$c" in 2??|3??) return 0 ;; *) return 1 ;; esac
}

OK=0; FAIL=0
for f in "${FILES[@]}"; do
  base=$(basename "$f"); alt=${base%.*}
  echo "── $base"
  if url=$(upload_one "$f"); then
    if verify_url "$url"; then
      echo "![${alt}](${url})"
      echo "URL: ${url}"
      OK=$((OK+1))
      if [ "$CLEAN" -eq 1 ]; then
        case "$f" in
          "$TMP_DIR"/*) ;;  # 剪贴板临时文件统一由 trap 清理
          *) rm -f -- "$f" && echo "[clean] 已删除本地文件: $f" ;;
        esac
      fi
    else
      echo "[FAIL] 上传成功但直链校验未通过: $url" >&2
      FAIL=$((FAIL+1))
    fi
  else
    FAIL=$((FAIL+1))
  fi
done
echo "SUMMARY: 成功 $OK 失败 $FAIL 共 $((OK+FAIL))"
[ "$FAIL" -eq 0 ] && [ "$FAIL_INPUT" -eq 0 ] || exit 1

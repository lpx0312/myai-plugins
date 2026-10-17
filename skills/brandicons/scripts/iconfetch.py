#!/usr/bin/env python3
"""Search open icon libraries (Iconify, 200k+ icons) for draw.io image styles.

Iconify aggregates 200,000+ open-source icons from 150+ sets (Solar, MingCute,
Remix, TDesign, Tabler, Material Design Icons, Iconoir, Lucide, Flat Color
Icons, …) behind one no-login API — the practical AI-usable stand-in for
iconfont.cn, which is login-walled (SPA + captcha + no public API). This script
resolves a keyword query to draw.io `image` styles so a diagram node gets a real
icon instead of a plain box.

Usage:
  python iconfetch.py "server"
  python iconfetch.py "cloud database" --limit 10
  python iconfetch.py "warning triangle" --color 0ea5e9 --size 32
  python iconfetch.py "打印机 扫描"                     # common CN terms auto-mapped
  python iconfetch.py "rocket" --colorful --embed      # colored sets, self-contained
  python iconfetch.py "firewall" --cell                # ready-to-paste <mxCell>
  python iconfetch.py "alert" --sets ri,tabler --json

By default the icon is referenced by URL
(https://api.iconify.design/<set>/<name>.svg), so draw.io fetches it whenever
the diagram is rendered or opened — network required at render time. Use
--embed to fetch the SVG once and inline it as a self-contained data URI
(portable; offline-safe export). For monochrome sets, --color tints the icon;
colored sets (flat-color-icons, skill-icons, …) ignore it.

The result style prefix is the same one used by draw.io image shapes:
  shape=image;html=1;imageAspect=0;aspect=fixed;verticalLabelPosition=bottom;
  verticalAlign=top;image=<url-or-data-uri>
"""
import argparse
import gzip
import html
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

_API = "https://api.iconify.design"
_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")

STYLE = ("shape=image;html=1;imageAspect=0;aspect=fixed;"
         "verticalLabelPosition=bottom;verticalAlign=top;image=")

# Curated high-quality, mostly monochrome line/fill sets (order = preference).
# solar/mingcute/ri/tdesign are the closest in feel to iconfont's popular sets.
DEFAULT_MONO = "solar,mingcute,ri,tdesign,mdi,tabler,iconoir,lucide"
# Colored / flat sets (palette=true); used with --colorful or --sets.
DEFAULT_COLOR = "flat-color-icons,skill-icons,logos,noto"

# Small Chinese -> English alias map so 中文关键词 "just work" for the most
# common diagram nodes. Unmapped CJK tokens are dropped on the retry pass.
_ALIAS = {
    "服务器": "server", "主机": "host", "存储": "database", "数据库": "database",
    "云": "cloud", "网络": "network", "路由": "router", "路由器": "router",
    "防火墙": "firewall", "交换机": "switch", "交换机网络": "network",
    "用户": "user", "人员": "user", "打印机": "printer", "扫描": "scan",
    "相机": "camera", "摄像头": "cctv", "监控": "cctv", "手机": "smartphone",
    "电话": "phone", "电脑": "monitor", "计算机": "monitor", "显示屏": "monitor",
    "告警": "alert", "警告": "alert", "报警": "alert", "提醒": "bell",
    "安全": "shield", "锁": "lock", "加密": "lock", "邮件": "mail",
    "文件": "file", "文件夹": "folder", "文档": "document", "硬盘": "harddisk",
    "磁盘": "harddisk", "数据": "data", "图表": "chart", "统计": "chart",
    "设置": "settings", "配置": "settings", "齿轮": "settings", "电源": "power",
    "电源开关": "power", "机器人": "robot", "人工智能": "ai", "智能": "robot",
    "无线": "wifi", "信号": "signal", "蓝牙": "bluetooth", "卫星": "satellite",
    "时钟": "clock", "时间": "clock", "日历": "calendar", "备份": "backup",
    "同步": "sync", "上传": "upload", "下载": "download", "搜索": "search",
    "放大镜": "search", "首页": "home", "房子": "home", "建筑": "building",
    "工厂": "factory", "汽车": "car", "飞机": "airplane", "航空": "airplane",
    "工业": "factory", "能源": "bolt", "电": "bolt", "温度": "temperature",
    "湿度": "water", "天气": "weather", "雨": "rain", "闪电": "lightning",
    "地球": "globe", "全球": "globe", "位置": "location", "定位": "location",
    "地图": "map", "旗子": "flag", "旗帜": "flag", "奖杯": "trophy",
    "流程": "flow", "接口": "api", "插件": "puzzle", "代码": "code",
    "编程": "code", "终端": "terminal", "控制台": "console", "日志": "document-text",
}


def _request(url, timeout=20):
    """GET with a browser User-Agent; retry once on transient HTTP/network errors.

    api.iconify.design blocks the default Python UA (403) and occasionally
    answers 400 under load, so a short retry makes the script reliable.
    """
    for attempt in range(2):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": _UA,
                                                       "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    raw = gzip.decompress(raw)
                return raw
        except (urllib.error.HTTPError, urllib.error.URLError):
            if attempt == 0:
                time.sleep(1.2)
                continue
            raise
    raise AssertionError("unreachable")  # pragma: no cover


def translate(query):
    """Map CJK tokens via _ALIAS; return (english, mapped_any)."""
    out, mapped = [], False
    for token in query.split():
        if re.search(r"[\u4e00-\u9fff]", token):
            if token in _ALIAS:
                out.append(_ALIAS[token])
                mapped = True
        else:
            out.append(token)
    return " ".join(out).strip(), mapped


def search(query, prefixes=None, limit=32):
    """Query the Iconify search API.

    The live API caps a response at 32 icons and 400s on any `start` >= 32
    (pagination is disabled server-side), so a single request + client-side
    slice is all that is possible. Ask for a more specific keyword for more.
    """
    limit = max(0, min(int(limit), 32))
    params = {"query": query}
    if prefixes:
        params["prefixes"] = ",".join(prefixes)
    url = _API + "/search?" + urllib.parse.urlencode(params)
    try:
        data = json.loads(_request(url).decode("utf-8"))
    except urllib.error.HTTPError:
        return [], {}
    return data.get("icons", [])[:limit], data.get("collections", {})


def svg_url(prefix, name, color=None):
    url = f"{_API}/{prefix}/{name}.svg"
    if color:
        url += "?color=%23" + urllib.parse.quote(color.strip("#"), safe="")
    return url


def build(prefix, name, meta, color=None, size=48, embed=False):
    """Return one result dict: style (+ready cell) for a single icon."""
    url = svg_url(prefix, name, color)
    image = url
    if embed:
        try:
            svg = _request(url)
            # Percent-encoded data URI — exactly what draw.io itself writes when
            # you paste an SVG. Percent-encoding also removes every ';' (the
            # style-value separator draw.io uses), so the image= value survives.
            image = "data:image/svg+xml," + urllib.parse.quote(svg.decode("utf-8"), safe="")
        except Exception as exc:  # noqa: BLE001 - report and keep CDN URL
            sys.stderr.write(f"warning: could not fetch {url} ({exc}); using URL\n")
    meta = meta or {}
    lic = meta.get("license") or {}
    author = meta.get("author") or {}
    style = STYLE + image
    return {
        "icon": f"{prefix}:{name}", "set": prefix,
        "set_name": meta.get("name", prefix),
        "license": lic.get("title", "?"), "spdx": lic.get("spdx", ""),
        "author": author.get("name", ""),
        "palette": bool(meta.get("palette")), "w": size, "h": size,
        "style": style, "url": url,
        "cell": (f'<mxCell id="icon" value="" style="{style}" vertex="1">'
                 f'<mxGeometry x="0" y="0" width="{size}" height="{size}" '
                 f'as="geometry"/></mxCell>'),
    }


def preview_html(results):
    """Lightweight visual picker — one <img> per candidate."""
    cards = []
    for i, r in enumerate(results):
        src = html.escape(r["url"], quote=True)
        cards.append(
            f'<div style="display:inline-block;text-align:center;margin:10px">'
            f'<img src="{src}" width="48" height="48" '
            f'style="padding:8px;border:1px solid #ddd;border-radius:8px">'
            f'<div style="font:12px monospace;max-width:140px;word-break:break-all">'
            f'{html.escape(r["icon"])}</div></div>')
    return ("<!doctype html><meta charset=utf-8>"
            "<body style='font-family:sans-serif;background:#f6f7f9'>"
            f"<h3>iconfetch — {len(results)} candidates</h3>{''.join(cards)}</body>")


def main():
    # Windows consoles default to cp936/GBK; force UTF-8 so CN aliases and
    # set names print cleanly (no-op on terminals that are already UTF-8).
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="+", help='keywords, e.g. "server" / "cloud database"')
    ap.add_argument("--limit", type=int, default=12)
    ap.add_argument("--sets", help='icon set prefixes to search, comma list, e.g. "mdi,tabler"; '
                                   'special value "all" searches every set')
    ap.add_argument("--colorful", action="store_true",
                    help="include coloured sets (flat-color-icons, skill-icons, …)")
    ap.add_argument("--color", help="tint monochrome icons: hex like 0ea5e9 or ffffff (no #)")
    ap.add_argument("--size", type=int, default=48, help="cell width/height in px (icons are square)")
    ap.add_argument("--embed", action="store_true",
                    help="inline the SVG as a data URI (fetches now; portable, offline-safe export)")
    ap.add_argument("--cell", action="store_true", help="also print a ready-to-paste <mxCell> per hit")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--preview", action="store_true",
                    help="write a local HTML grid of the candidates and open it")
    args = ap.parse_args()

    if not 0 < args.size <= 512:
        ap.error("--size must be in 1..512")

    query = " ".join(args.query)
    prefixes = None
    if args.sets and args.sets != "all":
        prefixes = [p.strip() for p in args.sets.split(",") if p.strip()]
    elif args.sets == "all":
        prefixes = None
    elif args.colorful:
        prefixes = [p for p in (DEFAULT_COLOR + "," + DEFAULT_MONO).split(",")]
    else:
        prefixes = DEFAULT_MONO.split(",")

    english, mapped = translate(query)
    icons, collections = search(english or query, prefixes, args.limit)
    if not icons and (mapped or english != query):
        # Chinese-only query with no hits: retry on the plain English mapping.
        icons, collections = search(english, prefixes, args.limit)
    if not icons and prefixes:
        # Nothing in the curated sets — fall back to every set so exotic
        # keywords still get a shot.
        icons, collections = search(english or query, None, args.limit)

    if not icons:
        sys.exit(f"no icon matched {query!r} — try another keyword, a different "
                 f"language, or --sets to search specific icon sets "
                 f"(list: {_API}/collections?prefixes=)")

    results = [build(prefix, name, collections.get(prefix), args.color, args.size, args.embed)
               for prefix, name in (ic.split(":", 1) for ic in icons)]
    # Prefer non-coloured duplicates first so --color stays meaningful, but
    # keep overall relevance order stable within a set.
    if not args.colorful and not args.color:
        results.sort(key=lambda r: (r["palette"],))

    if args.preview:
        path = os.path.join(tempfile.gettempdir(), f"iconfetch-{os.getpid()}.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(preview_html(results))
        webbrowser.open("file://" + path)
        print(f"preview written to {path}")

    if args.json:
        print(json.dumps(results, indent=2, ensure_ascii=False))
        return

    print(f"{len(results)} matches for {query!r}"
          + (f" (mapped CN → {english!r})" if mapped else "") + ":")
    for i, r in enumerate(results, 1):
        lic = f"{r['license']}{'/' + r['spdx'] if r['spdx'] else ''}"
        shown = r["style"]
        if len(shown) > 150:
            shown = shown[:147] + "..."
        print(f"{i:>2}. {r['icon']}  [{r['set_name']}, {lic}]  {r['w']}x{r['h']}")
        print(f"    {shown}")
        if args.cell:
            print(f"    {r['cell']}")


if __name__ == "__main__":
    main()

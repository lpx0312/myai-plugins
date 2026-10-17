#!/usr/bin/env python3
"""Brand / vendor logos for draw.io image styles, from Simple Icons (CC0).

Complements iconfetch.py (generic everyday icons via Iconify) and aiicons.py
(AI/LLM brands via lobe-icons): this script resolves BRAND logos — Redis,
Docker, Kubernetes, MySQL, GitHub, WeChat, Alibaba Cloud, Nginx, … — from the
Simple Icons library (3,300+ brand glyphs, CC0, single-path SVGs) to a draw.io
`image` style, tinted with each brand's OFFICIAL color by default.

Usage:
  python brandicons.py redis
  python brandicons.py "微信"                     # common CN names auto-map
  python brandicons.py "阿里云"                    # -> alibaba-cloud
  python brandicons.py kubernetes --cell          # ready-to-paste <mxCell>
  python brandicons.py "redis" --color ffffff     # custom tint (hex, no #)
  python brandicons.py docker --embed             # inline SVG as a data URI
  python brandicons.py cloud --limit 8            # fuzzy list, pick one
  python brandicons.py nginx --json
  python brandicons.py --refresh                  # force re-pull slug index

By default the style references https://cdn.simpleicons.org/<slug> (serves the
SVG in the brand's official color; append /<hex> for a custom tint), so draw.io
fetches it at render time — network required when the diagram opens. Use
--embed to fetch the SVG once and inline it as a self-contained data URI
(portable, offline-safe export), exactly like pasting the SVG by hand.

The slug/hex index is cached at ~/.drawio-skill/simple-icons-index.json with a
7-day TTL (jsDelivr primary mirror, unpkg fallback); --refresh re-pulls it.
"""
import argparse
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Fastest POPs first for CN networks; all serve the same npm file. (unpkg and
# the npm tarball itself do NOT ship _data/ — jsDelivr is the only CDN that
# serves it, so these are its alternate POP domains.)
MIRRORS = [
    "https://testingcf.jsdelivr.net/npm/simple-icons@latest/_data/simple-icons.json",
    "https://gcore.jsdelivr.net/npm/simple-icons@latest/_data/simple-icons.json",
    "https://cdn.jsdelivr.net/npm/simple-icons@latest/_data/simple-icons.json",
]
CDN = "https://cdn.simpleicons.org/"
CACHE = os.path.join(os.path.expanduser("~"), ".drawio-skill",
                     "simple-icons-index.json")
TTL = 7 * 24 * 3600
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")

STYLE = ("shape=image;html=1;imageAspect=0;aspect=fixed;"
         "verticalLabelPosition=bottom;verticalAlign=top;image=")

# Common CN brand names -> verified-present slugs (Simple Icons has no 飞书/
# 钉钉/腾讯云/华为云/京东 icons — see HINTS). Keep this list verified.
_CN = {
    "微信": "wechat", "腾讯qq": "qq", "qq": "qq",
    "阿里云": "alibaba-cloud", "淘宝": "taobao", "支付宝": "alipay",
    "哔哩哔哩": "bilibili", "b站": "bilibili",
    "知乎": "zhihu", "百度": "baidu", "字节跳动": "bytedance",
    "抖音": "tiktok", "小米": "xiaomi", "华为": "huawei",
    "微博": "sina-weibo", "新浪微博": "sina-weibo", "码云": "gitee",
    "k8s": "kubernetes",
    "aws": "amazon-web-services", "亚马逊云": "amazon-web-services",
    "亚马逊": "amazon",
}

# Popular brands people expect but Simple Icons does NOT carry -> guidance.
_HINTS = {
    "feishu": "飞书 is not in Simple Icons — try iconfetch.py or paste its SVG manually",
    "飞书": "飞书 is not in Simple Icons — try iconfetch.py or paste its SVG manually",
    "lark": "Lark/飞书 is not in Simple Icons — try iconfetch.py",
    "dingtalk": "钉钉 is not in Simple Icons — try iconfetch.py or paste its SVG manually",
    "钉钉": "钉钉 is not in Simple Icons — try iconfetch.py or paste its SVG manually",
    "wecom": "企业微信 is not in Simple Icons — try iconfetch.py",
    "企业微信": "企业微信 is not in Simple Icons — try iconfetch.py",
    "腾讯云": "腾讯云 is not in Simple Icons — use shapesearch.py / iconfetch.py",
    "tencentcloud": "腾讯云 is not in Simple Icons — use shapesearch.py / iconfetch.py",
    "华为云": "华为云 is not in Simple Icons — use shapesearch.py / iconfetch.py",
    "京东": "京东 is not in Simple Icons — try iconfetch.py",
}


def _request(url, timeout=30):
    """GET with a browser UA; retry once on transient errors (mirrors are CDNs)."""
    for attempt in range(2):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    raw = gzip.decompress(raw)
                return raw
        except (urllib.error.HTTPError, urllib.error.URLError):
            if attempt == 0:
                time.sleep(1.0)
                continue
            raise
    raise AssertionError("unreachable")  # pragma: no cover


def load_index(refresh=False):
    """Return the [{title, slug?, hex, ...}] brand list, cached locally."""
    if not refresh and os.path.isfile(CACHE) and \
            time.time() - os.path.getmtime(CACHE) < TTL:
        with open(CACHE, encoding="utf-8") as f:
            return json.load(f)
    last_exc = None
    for mirror in MIRRORS:
        try:
            data = json.loads(_request(mirror).decode("utf-8"))
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w", encoding="utf-8") as f:
                json.dump(data, f)
            return data
        except Exception as exc:  # noqa: BLE001 - try the next mirror
            last_exc = exc
    if os.path.isfile(CACHE):  # stale cache beats no cache
        with open(CACHE, encoding="utf-8") as f:
            return json.load(f)
    raise SystemExit(f"could not fetch the Simple Icons index from any mirror "
                     f"({last_exc}); retry with --refresh later")


def _names(entry):
    """All matchable lowercase names for one brand entry."""
    slug = entry.get("slug") or entry["title"].lower().replace(" ", "-")
    names = [slug, entry["title"].lower()]
    for k in ("aka", "old", "dup"):
        for a in (entry.get("aliases") or {}).get(k, []):
            if isinstance(a, str):
                names.append(a.lower())
    return names


def _compact(s):
    return s.lower().replace(" ", "").replace("-", "")


def search(entries, query, limit=6):
    """Rank brands: exact > prefix > substring. Returns de-duplicated list."""
    q = query.strip().lower()
    qc = _compact(q)
    buckets = ([], [], [])
    for e in entries:
        for n in _names(e):
            nc = _compact(n)
            if n == q or nc == qc:
                buckets[0].append(e)
            elif nc.startswith(qc) or n.startswith(q):
                buckets[1].append(e)
            elif qc in nc or q in n:
                buckets[2].append(e)
            else:
                continue
            break
    out, seen = [], set()
    for bucket in buckets:
        for e in bucket:
            key = e["title"]
            if key not in seen:
                seen.add(key)
                out.append(e)
    return out[:limit]


def _probe(url, timeout=15):
    """Single GET without retry — validates a CDN slug candidate."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def build(entry, color=None, size=48, embed=False):
    """One result dict: URL/style (+ready cell) for a single brand.

    A few titles' CDN slugs differ from the JSON-derived one (e.g. "Alibaba
    Cloud" serves at /alibabacloud, not /alibaba-cloud), so probe the CDN and
    fall back to the hyphen-less form. The probe doubles as the fetch for
    --embed, so the emitted URL is always one the CDN actually serves.
    """
    slug = entry.get("slug") or entry["title"].lower().replace(" ", "-")
    compact = slug.replace("-", "")
    candidates = [slug] + ([compact] if compact != slug else [])
    final_slug, svg = slug, None
    for cand in candidates:
        try:
            svg = _probe(CDN + cand)
            final_slug = cand
            break
        except Exception:  # noqa: BLE001 - try the next slug candidate
            continue
    if svg is None:
        sys.stderr.write(f"warning: CDN served no SVG for '{slug}'; "
                         f"the style may not render\n")
    url = CDN + final_slug + (f"/{color.lstrip('#')}" if color else "")
    image = url
    if embed:
        try:
            body = (svg.decode("utf-8") if svg is not None and not color
                    else _probe(url).decode("utf-8"))
            # Percent-encoded data URI — what draw.io itself writes when you
            # paste an SVG; also removes every ';' so the style survives.
            image = "data:image/svg+xml," + urllib.parse.quote(body, safe="")
        except Exception as exc:  # noqa: BLE001 - report and keep CDN URL
            sys.stderr.write(f"warning: could not fetch {url} ({exc}); "
                             f"using URL\n")
    style = STYLE + image
    return {
        "brand": entry["title"], "slug": slug,
        "official_color": "#" + entry.get("hex", "000000"),
        "license": "CC0", "w": size, "h": size,
        "style": style, "url": url,
        "cell": (f'<mxCell id="brand" value="{entry["title"]}" style="{style}"'
                 f' vertex="1"><mxGeometry x="0" y="0" width="{size}" '
                 f'height="{size}" as="geometry"/></mxCell>'),
    }


def main():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="*", help='brand name, e.g. "redis" / "微信" / "阿里云"')
    ap.add_argument("--limit", type=int, default=6, help="max fuzzy matches to show")
    ap.add_argument("--color", help="custom tint: hex like dc2626 (no #); "
                                    "default = the brand's official color")
    ap.add_argument("--size", type=int, default=48, help="cell width/height in px")
    ap.add_argument("--embed", action="store_true",
                    help="inline the SVG as a data URI (fetches now; offline-safe)")
    ap.add_argument("--cell", action="store_true", help="also print a ready-to-paste <mxCell>")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--refresh", action="store_true", help="re-pull the slug index cache")
    args = ap.parse_args()

    if not 0 < args.size <= 512:
        ap.error("--size must be in 1..512")
    if not args.query and not args.refresh:
        ap.error("a brand name is required (or --refresh to update the index)")
    if args.refresh:
        load_index(refresh=True)
        if not args.query:
            print(f"index refreshed -> {CACHE}")
            return

    original = " ".join(args.query)
    query = original
    entries = load_index(refresh=False)
    mapped = _CN.get(query.lower()) or _CN.get(query)
    if mapped:
        query = mapped
    hits = search(entries, query, args.limit)
    if not hits:
        hint = _HINTS.get(query.lower()) or _HINTS.get(query)
        if hint:
            sys.exit(f"no match for {query!r}: {hint}")
        sys.exit(f"no brand matched {query!r} — check the spelling (English "
                 f"brand names work best), or browse simpleicons.org")

    results = [build(e, args.color, args.size, args.embed) for e in hits]

    if args.json:
        print(json.dumps(results, indent=2, ensure_ascii=False))
        return

    exact_note = " (exact)" if _compact(query) == _compact(
        hits[0].get("slug") or hits[0]["title"]) else ""
    map_note = f" (mapped {original} -> {query})" if original != query else ""
    print(f"{len(results)} match(es) for {original!r}{map_note}{exact_note} "
          f"[Simple Icons, CC0]:")
    for i, r in enumerate(results, 1):
        tint = args.color or r["official_color"]
        print(f"{i:>2}. {r['brand']}  #{tint.lstrip('#')}  {r['w']}x{r['h']}")
        shown = r["style"] if len(r["style"]) <= 150 else r["style"][:147] + "..."
        print(f"    {shown}")
        if args.cell:
            print(f"    {r['cell']}")


if __name__ == "__main__":
    main()

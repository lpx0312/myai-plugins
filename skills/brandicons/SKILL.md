---
name: brandicons
version: 1.0.0
description: Use when a diagram or 架构图/流程图/拓扑图 (especially one being drawn with drawio-skill) needs a BRAND or VENDOR LOGO icon on a node — Redis, Docker, Kubernetes, MySQL, NGINX, GitHub, AWS, 微信, 阿里云, 淘宝, 支付宝, 华为, 百度, 知乎, B站… Runs scripts/brandicons.py to fetch each brand's OFFICIAL-color SVG from Simple Icons (3,300+ brands, CC0, no login) and emit a draw.io image style or ready-to-paste <mxCell>. CN brand names auto-map (微信→wechat, 阿里云→alibaba-cloud, k8s→kubernetes); --embed inlines the SVG as a data URI (offline-safe). Designed to pair with drawio-skill WITHOUT modifying it — brand logos and generic everyday icons both come from here (scripts/brandicons.py + scripts/iconfetch.py).
license: MIT
---

# Brand Logos for Diagrams (Simple Icons)

Resolves **brand / vendor logos** to draw.io `image` styles, tinted with each
brand's official color, from the Simple Icons library (3,300+ single-path
brand glyphs, CC0, CDN-served, no login — the scriptable stand-in for
iconfont.cn when a diagram needs recognizable brand marks).

## Routing: which icon tool for which need

| Need | Tool |
| --- | --- |
| **Brand / vendor logo** (Redis, Docker, K8s, MySQL, 微信, 阿里云 …) | **this skill** — `scripts/brandicons.py` |
| Generic everyday icon (server, database, firewall, user, alert …) | **this skill** — `scripts/iconfetch.py` (Iconify, 200k+ icons) |
| AI/LLM brand logos (OpenAI, Claude, Gemini, Ollama …) | drawio-skill's bundled `aiicons.py` |
| Cloud architecture shapes (AWS/Azure/GCP/K8s stencils) | drawio-skill's `shapesearch.py` |

This skill is intentionally SEPARATE so drawio-skill stays unmodified and
update-safe. When a drawio-skill diagram needs brand logos, run this script
and feed its output into the diagram's XML (see the embedding patterns below).

## Usage

```bash
python3 <this-skill-dir>/scripts/brandicons.py redis
python3 <this-skill-dir>/scripts/brandicons.py 微信                 # CN names auto-map
python3 <this-skill-dir>/scripts/brandicons.py "阿里云"              # -> alibaba-cloud
python3 <this-skill-dir>/scripts/brandicons.py kubernetes --cell    # ready-to-paste <mxCell>
python3 <this-skill-dir>/scripts/brandicons.py "redis" --color ffffff   # custom tint (default = official brand color)
python3 <this-skill-dir>/scripts/brandicons.py docker --embed       # inline SVG as a data URI
python3 <this-skill-dir>/scripts/brandicons.py cloud --limit 8      # fuzzy list, pick one
python3 <this-skill-dir>/scripts/brandicons.py nginx --json         # machine-readable
python3 <this-skill-dir>/scripts/iconfetch.py server           # everyday icons (Iconify, 200k+)
python3 <this-skill-dir>/scripts/brandicons.py --refresh            # force re-pull the slug index
```

Output per hit: the brand name, official color hex, and the full
`shape=image;...image=<url-or-data-uri>` style. `--cell` additionally prints
a ready `<mxCell>`; the script can also be imported (`import brandicons`) to
batch-build embedded styles programmatically.

## Embedding into a .drawio diagram

Two forms, both render in draw.io desktop:

1. **URL reference** (needs network when the diagram opens):
   `shape=image;html=1;imageAspect=0;aspect=fixed;verticalLabelPosition=bottom;verticalAlign=top;image=https://cdn.simpleicons.org/redis`
2. **`--embed` data URI** (self-contained, offline-safe) — the same style
   with `image=data:image/svg+xml,...`. Prefer this for deliverables.

Icon-on-a-card pattern (icon centered inside a titled box; child coordinates
are relative to the parent):

```xml
<mxCell id="node1" value="Redis 缓存" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#fef2f2;strokeColor=#dc2626;fontSize=13;fontColor=#1e293b;verticalAlign=top;spacingTop=8;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="160" height="130" as="geometry" />
</mxCell>
<mxCell id="node1-icon" value="" style="shape=image;html=1;imageAspect=0;aspect=fixed;image=data:image/svg+xml,..." vertex="1" parent="node1">
  <mxGeometry x="55" y="42" width="50" height="50" as="geometry" />
</mxCell>
```

## Notes & limits

- Default tint = the brand's official color (from the Simple Icons data);
  `--color <hex>` overrides.
- CN alias map: 微信/阿里云/淘宝/支付宝/哔哩哔哩/知乎/百度/字节跳动/抖音/小米/华为/微博/码云/k8s/aws/亚马逊云…
- NOT in the library (script prints a hint, falls back gracefully): 飞书,
  钉钉, 腾讯云, 华为云, 企业微信, 京东 — use this skill's iconfetch.py or
  paste those SVGs manually.
- Slug index caches at `~/.drawio-skill/simple-icons-index.json` (7-day TTL;
  mirrors testingcf/gcore/cdn.jsdelivr.net, fastest first — ~1.5s cold start).
- A few CDN slugs differ from the JSON-derived one (e.g. Alibaba Cloud serves
  at `/alibabacloud`); the script probes the CDN and repairs this itself.

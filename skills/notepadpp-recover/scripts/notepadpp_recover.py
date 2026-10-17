#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
notepadpp_recover.py — Notepad++ 未保存文件 / 丢失会话 恢复工具

核心原理：
  Notepad++ 开启"备份"(快照模式)后，所有打开且被修改过、但尚未保存（或保存后又改过）
  的文档，会每 N 秒快照到 backup 目录，文件名格式： 原文件名@YYYY-MM-DD_HHMMSS
  即使关机/崩溃导致 session.xml（已打开标签列表）没写成功，这些内容快照依然留在磁盘上。

用法：
  python notepadpp_recover.py                        # 扫描并打印报告（不改动任何文件）
  python notepadpp_recover.py --archive DIR          # 备份归档 + 生成 Markdown 清单
  python notepadpp_recover.py --index FILE           # 只生成 Markdown 清单
  python notepadpp_recover.py --make-session FILE    # 生成可被 Notepad++ 加载的会话文件
  python notepadpp_recover.py --json                 # 机器可读输出
  python notepadpp_recover.py --config-dir DIR       # 手动指定 Notepad++ 配置目录
  python notepadpp_recover.py --all-profiles         # 扫描本机所有用户配置目录
"""

import argparse
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime

BT = chr(96)          # 反引号，用于拼 Markdown 行内代码，避免源码里出现反引号
SESSION_NAME = "全部备份会话.xml"
TS_RE = re.compile(r"^(?P<name>.*)@(?P<ts>\d{4}-\d{2}-\d{2}_\d{6})$")


# --------------------------------------------------------------------------
# 1. 定位 Notepad++ 配置目录
# --------------------------------------------------------------------------
def candidate_config_dirs():
    """列出所有可能的 Notepad++ 配置目录（安装版 + 便携版）。"""
    cands = []

    # 安装版：%APPDATA%\Notepad++
    appdata = os.environ.get("APPDATA")
    if appdata:
        cands.append(os.path.join(appdata, "Notepad++"))

    # 便携版：notepad++.exe 同级目录
    exe_cands = []
    for env in ("ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"):
        base = os.environ.get(env)
        if base:
            exe_cands.append(os.path.join(base, "Notepad++"))
    exe_cands += [
        r"C:\Program Files\Notepad++",
        r"C:\Program Files (x86)\Notepad++",
        r"D:\SystemTools\Notepad++",
        r"D:\SystemTools\notepad++",
        r"D:\Notepad++",
        r"Z:\soft\Notepad++",
    ]
    for d in exe_cands:
        if os.path.isfile(os.path.join(d, "notepad++.exe")):
            cands.append(d)
        # 便携版也可能只有 backup/session.xml 而没有 exe（被挪走了）
        elif os.path.isdir(os.path.join(d, "backup")):
            cands.append(d)

    # 去重并只保留真实存在且含 session.xml / backup 的
    out, seen = [], set()
    for d in cands:
        d = os.path.abspath(d)
        key = d.lower()
        if key in seen:
            continue
        seen.add(key)
        if os.path.isdir(d) and (
            os.path.isfile(os.path.join(d, "session.xml"))
            or os.path.isdir(os.path.join(d, "backup"))
            or os.path.isfile(os.path.join(d, "config.xml"))
        ):
            out.append(d)
    return out


def all_user_config_dirs():
    """扫描 C:\\Users\\*\\AppData\\Roaming\\Notepad++（多用户场景）。"""
    res = []
    users_root = os.path.join(os.environ.get("SystemDrive", "C:") + os.sep, "Users")
    try:
        for name in os.listdir(users_root):
            p = os.path.join(users_root, name, "AppData", "Roaming", "Notepad++")
            if os.path.isdir(p):
                res.append(p)
    except OSError:
        pass
    return res


# --------------------------------------------------------------------------
# 2. 解析 config.xml —— 判断备份是否开启、是否自定义目录
# --------------------------------------------------------------------------
def parse_config(config_dir):
    info = {
        "config_xml": None,
        "remember_last_session": None,
        "backup_action": None,
        "backup_use_custom_dir": None,
        "backup_custom_dir": None,
        "is_snapshot_mode": None,
        "snapshot_backup_timing": None,
        "effective_backup_dir": None,
    }
    cfg = os.path.join(config_dir, "config.xml")
    if not os.path.isfile(cfg):
        return info
    info["config_xml"] = cfg
    try:
        tree = ET.parse(cfg)
    except ET.ParseError:
        return info

    for node in tree.iter():
        tag = node.tag
        if tag == "GUIConfig":
            name = node.get("name")
            if name == "RememberLastSession":
                info["remember_last_session"] = (node.text or "").strip()
            elif name == "Backup":
                info["backup_action"] = node.get("action")
                info["backup_use_custom_dir"] = node.get("useCustumDir")
                info["backup_custom_dir"] = node.get("dir")
                info["is_snapshot_mode"] = node.get("isSnapshotMode")
                info["snapshot_backup_timing"] = node.get("snapshotBackupTiming")

    # 计算真正生效的备份目录
    custom = info["backup_custom_dir"]
    if (info["backup_use_custom_dir"] or "").lower() == "yes" and custom:
        info["effective_backup_dir"] = custom
    else:
        info["effective_backup_dir"] = os.path.join(config_dir, "backup")
    return info


# --------------------------------------------------------------------------
# 3. 解析 session.xml —— 当前"已打开标签"清单
# --------------------------------------------------------------------------
def parse_session(config_dir):
    sess = os.path.join(config_dir, "session.xml")
    result = {"session_xml": sess, "exists": os.path.isfile(sess), "files": []}
    if not result["exists"]:
        return result
    try:
        tree = ET.parse(sess)
    except ET.ParseError:
        return result
    for node in tree.iter("File"):
        result["files"].append({
            "filename": node.get("filename") or "",
            "backup": node.get("backupFilePath") or "",
            "lang": node.get("lang") or "",
        })
    return result


# --------------------------------------------------------------------------
# 3.5 解析关机日志 —— 判断"关机时 session.xml 到底写没写成功"
#     Notepad++ 会把每次关机事件记进 nppLogNulContentCorruptionIssue.log：
#       WM_QUERYENDSESSION (系统关机通知) / WM_ENDSESSION (会话结束)
#     正常退出会紧跟 session.xml is opened / N bytes are written / is closed。
#     若关机事件后没有这段写入记录 => 标签列表丢失，但内容快照仍在 backup 目录。
# --------------------------------------------------------------------------
SHUTDOWN_LOG = "nppLogNulContentCorruptionIssue.log"


def parse_shutdown_log(config_dir, max_events=8):
    path = os.path.join(config_dir, SHUTDOWN_LOG)
    res = {"log": path, "exists": os.path.isfile(path), "events": []}
    if not res["exists"]:
        return res
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return res

    idxs = [i for i, ln in enumerate(lines) if "WM_QUERYENDSESSION" in ln]
    for i in idxs[-max_events:]:
        head = lines[i]
        ts = head[:19]
        reason = ""
        if "lParam:" in head:
            reason = head.split("lParam:", 1)[1].strip()
        # 向后扫描（直到下一次关机事件或 80 行），找 session.xml 写入
        written = None   # None=未观察到, True=写成功, False=尝试但失败
        j = i + 1
        limit = min(len(lines), i + 80)
        while j < limit:
            if "WM_QUERYENDSESSION" in lines[j]:
                break
            ln = lines[j]
            if "session.xml" in ln and "bytes are written" in ln:
                parts = ln.split()
                try:
                    nums = [p for p in parts if "/" in p][0]
                    a, b = nums.split("/")
                    written = (a == b)
                except Exception:
                    written = True
                break
            j += 1
        res["events"].append({
            "time": ts,
            "reason": reason,
            "session_written": written,
        })
    return res


# --------------------------------------------------------------------------
# 4. 扫描备份目录
# --------------------------------------------------------------------------
def guess_kind(text):
    s = text.lstrip()
    if not s:
        return "空"
    if s.startswith("#!"):
        return "shell 脚本"
    if s.startswith("-----BEGIN"):
        return "证书/密钥"
    if s.startswith("<?xml"):
        return "XML"
    if s.startswith("{") or s.startswith("["):
        return "JSON/数据"
    if "apiVersion:" in text[:2000] or "\nkind:" in text[:2000]:
        return "K8s YAML"
    if re.search(r"^\[?root@|^\s*\$ |^C:\\|^PS [A-Z]:", text[:400], re.M):
        return "终端操作记录"
    return "文本"


def preview(path, limit=800):
    try:
        with open(path, "rb") as f:
            raw = f.read(limit)
    except OSError:
        return ""
    if not raw:
        return ""
    if b"\x00" in raw:
        return "<二进制内容>"
    txt = raw.decode("utf-8", errors="replace")
    lines = [ln.strip() for ln in txt.replace("\r", "").split("\n")]
    lines = [ln for ln in lines if ln and ln != "\ufffd"]
    s = " ".join(lines[:3])
    s = re.sub(r"\s+", " ", s).strip()
    return s[:160]


def scan_backups(backup_dir):
    items = []
    if not os.path.isdir(backup_dir):
        return items
    for fn in sorted(os.listdir(backup_dir)):
        path = os.path.join(backup_dir, fn)
        if not os.path.isfile(path):
            continue
        m = TS_RE.match(fn)
        if m:
            doc_name, stamp = m.group("name"), m.group("ts")
            try:
                ts = datetime.strptime(stamp, "%Y-%m-%d_%H%M%S")
            except ValueError:
                ts = datetime.fromtimestamp(os.path.getmtime(path))
        else:
            doc_name, ts = fn, datetime.fromtimestamp(os.path.getmtime(path))
        try:
            size = os.path.getsize(path)
        except OSError:
            size = 0
        pv = preview(path) if size else ""
        items.append({
            "file": fn,
            "path": path,
            "doc_name": doc_name,
            "timestamp": ts.strftime("%Y-%m-%d %H:%M:%S"),
            "date": ts.strftime("%Y-%m-%d"),
            "size": size,
            "empty": size == 0,
            "kind": guess_kind(pv),
            "preview": pv,
        })
    items.sort(key=lambda x: x["timestamp"], reverse=True)
    return items


def group_versions(items):
    """同一个原文件名可能有多个历史快照 —— 列出可选版本。"""
    g = defaultdict(list)
    for it in items:
        if not it["empty"]:
            g[it["doc_name"]].append(it)
    return {k: v for k, v in g.items() if len(v) > 1}


# --------------------------------------------------------------------------
# 5. Markdown 清单
# --------------------------------------------------------------------------
def build_markdown(config_dir, cfg, sess, items, source_backup_dir, shutdown=None):
    shutdown = shutdown or {}
    gv = group_versions(items)
    live = [f for f in sess["files"] if f.get("backup")]
    total_size = sum(i["size"] for i in items)
    empty_n = sum(1 for i in items if i["empty"])

    L = []
    L.append("# Notepad++ 未保存文件恢复清单")
    L.append("")
    L.append("> 由 `notepadpp_recover.py` 自动生成于 " +
             datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    L.append("")
    L.append("| 项目 | 值 |")
    L.append("| --- | --- |")
    L.append("| Notepad++ 配置目录 | `%s` |" % config_dir)
    L.append("| 备份目录（生效） | `%s` |" % source_backup_dir)
    L.append("| 快照模式 | %s（间隔 %s ms） |" % (
        cfg.get("is_snapshot_mode") or "未知",
        cfg.get("snapshot_backup_timing") or "未知"))
    L.append("| 记住上次会话 | %s |" % (cfg.get("remember_last_session") or "未知"))
    L.append("| session.xml 中的标签数 | %d |" % len(sess["files"]))
    L.append("| 备份文件总数 | %d（其中空文件 %d） |" % (len(items), empty_n))
    L.append("| 备份总大小 | %.1f KB |" % (total_size / 1024.0))
    if items:
        L.append("| 时间跨度 | %s ~ %s |" % (items[-1]["date"], items[0]["date"]))
    L.append("")
    L.append("## 恢复方式")
    L.append("")
    L.append("1. 直接在 Notepad++ 里打开上表「备份目录」中对应的文件；")
    L.append("2. 或从归档目录复制一份，去掉 `@YYYY-MM-DD_HHMMSS` 后缀另存为正式文件。")
    L.append("")
    L.append("> 注意：`session.xml` 只记录「哪些标签打开着」，**未保存内容**全靠本目录的备份文件。"
             "所以标签列表丢了不影响内容恢复。")
    L.append("")

    if shutdown.get("exists") and shutdown.get("events"):
        L.append("## 关机事件诊断（为什么标签会丢）")
        L.append("")
        L.append("读自 " + BT + SHUTDOWN_LOG + BT + "。session 写入=正常 表示关机时标签列表已落盘；"
                 "未写入 表示系统强制结束进程、会话没保存 —— 这时标签列表丢失，"
                 "但**内容快照仍在本目录**，照常可恢复。")
        L.append("")
        L.append("| 关机时间 | 关机类型 | session.xml 是否写入 |")
        L.append("| --- | --- | --- |")
        for e in shutdown["events"]:
            sw = e["session_written"]
            flag = "正常" if sw is True else ("**未写入（异常）**" if sw is None else "**写入不完整**")
            if e["reason"].startswith("0 "):
                reason = "普通关机/重启"
            elif "CRITICAL" in e["reason"]:
                reason = "ENDSESSION_CRITICAL（强制结束）"
            else:
                reason = e["reason"][:40]
            L.append("| %s | %s | %s |" % (e["time"], reason, flag))
        L.append("")

    if sess["files"]:
        L.append("## 当前 session.xml 记录的标签")
        L.append("")
        L.append("| 文件名 | 关联备份 | 语言 |")
        L.append("| --- | --- | --- |")
        for f in sess["files"]:
            b = os.path.basename(f["backup"]) if f["backup"] else "—（已保存到磁盘）"
            L.append("| `%s` | `%s` | %s |" % (
                f["filename"].replace("|", "/").replace("`", "'"),
                b.replace("|", "/").replace("`", "'"),
                f["lang"] or "-"))
        L.append("")

    if gv:
        L.append("## 同一文档的多个历史版本（%d 个文档）" % len(gv))
        L.append("")
        L.append("以下原文件名存在多份快照，按需挑最接近你要的那一份：")
        L.append("")
        for name in sorted(gv):
            vers = sorted(gv[name], key=lambda x: x["timestamp"], reverse=True)
            L.append("- **%s**（%d 个版本）" % (name, len(vers)))
            for v in vers:
                L.append("  - `%s` — %d B — %s" % (v["file"], v["size"], v["kind"]))
        L.append("")

    L.append("## 完整索引（共 %d 个，按时间倒序）" % len(items))
    L.append("")
    cur = ""
    for it in items:
        if it["date"] != cur:
            cur = it["date"]
            L.append("")
            L.append("### %s" % cur)
            L.append("")
        tag = " **[空文件]**" if it["empty"] else ""
        L.append("- `%s` — %d B · %s%s" % (it["file"], it["size"], it["kind"], tag))
        if it["preview"]:
            pv = it["preview"].replace("`", "'").replace("|", "/")
            L.append("  > %s" % pv)
    L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------
# 6. 归档
# --------------------------------------------------------------------------
def do_archive(source_backup_dir, dest_dir, items, markdown, index_name):
    os.makedirs(dest_dir, exist_ok=True)
    copied = 0
    for it in items:
        dst = os.path.join(dest_dir, it["file"])
        if os.path.abspath(dst) == os.path.abspath(it["path"]):
            continue
        shutil.copy2(it["path"], dst)
        copied += 1
    index_path = os.path.join(dest_dir, index_name)
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(markdown)
    return copied, index_path


# --------------------------------------------------------------------------
# 7. 生成会话文件（让 Notepad++ 一次性加载全部备份）
# --------------------------------------------------------------------------
FILE_ATTRS = (
    'firstVisibleLine="0" xOffset="0" scrollWidth="0" startPos="0" endPos="0" '
    'selMode="0" offset="0" wrapCount="1" lang="None (Normal Text)" encoding="-1" '
    'userReadOnly="no" originalFileLastModifTimestamp="0" '
    'originalFileLastModifTimestampHigh="0" tabColourId="-1" '
    'mapFirstVisibleDisplayLine="-1" mapFirstVisibleDocLine="-1" '
    'mapLastVisibleDocLine="-1" mapNbLine="-1" mapHigherPos="-1" mapWidth="-1" '
    'mapHeight="-1" mapKByteInDoc="512" mapWrapIndentMode="-1" mapIsWrap="no"'
)


def xml_escape(s):
    """转义为 XML 安全字符串。

    关键坑：Notepad++ 的会话解析器要求 filename 中的**非 ASCII 字符写成数字实体**
    （如 &#x65B0;）。若直接写原始 UTF-8 中文，整个会话文件会被静默忽略，
    Notepad++ 只显示一个空白新文档。这里统一转换成 &#xHEX; 形式。
    """
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "&":
            out.append("&amp;")
        elif ch == "<":
            out.append("&lt;")
        elif ch == ">":
            out.append("&gt;")
        elif ch == '"':
            out.append("&quot;")
        elif o > 127:
            out.append("&#x%X;" % o)
        else:
            out.append(ch)
    return "".join(out)


def make_session(items, base_dir, out_path):
    lines = ['<?xml version="1.0" encoding="UTF-8" ?>', "<NotepadPlus>",
             '    <Session activeView="0">', '        <mainView activeIndex="0">']
    for it in items:
        p = os.path.join(base_dir, it["file"])
        lines.append('            <File %s filename="%s" backupFilePath="" />'
                     % (FILE_ATTRS, xml_escape(os.path.abspath(p))))
    lines += ["        </mainView>", '        <subView activeIndex="0" />',
              "    </Session>", "</NotepadPlus>", ""]
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return out_path


# --------------------------------------------------------------------------
# 8. 报告
# --------------------------------------------------------------------------
def print_report(config_dir, cfg, sess, items, source_backup_dir, shutdown=None):
    shutdown = shutdown or {}
    print("=" * 72)
    print("Notepad++ 配置目录 : %s" % config_dir)
    print("备份目录（生效）   : %s" % source_backup_dir)
    print("  快照模式         : %s  (间隔 %s ms)" % (
        cfg.get("is_snapshot_mode"), cfg.get("snapshot_backup_timing")))
    print("  记住上次会话     : %s" % cfg.get("remember_last_session"))
    print("  session.xml      : %s (%d 个标签)" % (
        "存在" if sess["exists"] else "不存在", len(sess["files"])))
    for f in sess["files"]:
        b = os.path.basename(f["backup"]) if f["backup"] else "已保存到磁盘"
        print("    - %s   [备份: %s]" % (f["filename"], b))
    if shutdown.get("exists") and shutdown.get("events"):
        print("关机事件（判断标签为何丢失）:")
        for e in shutdown["events"]:
            sw = e["session_written"]
            if sw is True:
                flag = "session正常写入"
            elif sw is None:
                flag = "session未写入  <== 异常，标签列表丢失的原因"
            else:
                flag = "session写入不完整"
            print("  %s  %-32s %s" % (e["time"], e["reason"][:32], flag))
    elif shutdown.get("exists"):
        print("关机事件: 日志存在但未解析到关机记录")
    print("-" * 72)
    print("备份文件总数: %d  空文件: %d  总大小: %.1f KB" % (
        len(items), sum(1 for i in items if i["empty"]),
        sum(i["size"] for i in items) / 1024.0))
    if items:
        print("时间跨度  : %s ~ %s" % (items[-1]["date"], items[0]["date"]))
    gv = group_versions(items)
    if gv:
        print("多版本文档: %d 个（同一原文件名存在多份快照）" % len(gv))
    print("=" * 72)

    cur = ""
    for it in items:
        if it["date"] != cur:
            cur = it["date"]
            print("\n--- %s ---" % cur)
        flag = " [空]" if it["empty"] else ""
        print("  %-46s %8d B  %-10s%s" %
              (it["file"][:46], it["size"], it["kind"], flag))
        if it["preview"]:
            print("      %s" % it["preview"][:110])
    print()


# --------------------------------------------------------------------------
def _make_console_safe():
    """Windows 中文控制台/重定向时，GBK 编码器遇到 ✅ 之类的字符会直接抛
    UnicodeEncodeError 让脚本崩掉。这里把输出流的错误处理改成 replace，
    保证无论控制台代码页是什么都能跑完（该字符显示成 ? 而已）。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except Exception:
            pass


def main():
    _make_console_safe()
    ap = argparse.ArgumentParser(
        description="Notepad++ 未保存文件 / 丢失会话 恢复工具")
    ap.add_argument("--config-dir", help="手动指定 Notepad++ 配置目录")
    ap.add_argument("--all-profiles", action="store_true",
                    help="扫描本机所有用户的 Notepad++ 配置目录")
    ap.add_argument("--archive", metavar="DIR",
                    help="把全部备份复制到 DIR，并生成 Markdown 清单")
    ap.add_argument("--index", metavar="FILE", help="生成 Markdown 清单到 FILE")
    ap.add_argument("--make-session", metavar="FILE",
                    help="生成 Notepad++ 会话文件（File -> Load Session 可一次加载全部备份）")
    ap.add_argument("--session-base", metavar="DIR",
                    help="会话文件里引用的文件所在目录（默认用备份原目录）")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()

    if args.config_dir:
        dirs = [os.path.abspath(args.config_dir)]
        if not os.path.isdir(dirs[0]):
            print("错误：目录不存在 %s" % dirs[0], file=sys.stderr)
            return 2
    else:
        dirs = candidate_config_dirs()
        if args.all_profiles:
            dirs += all_user_config_dirs()
            # 去重
            seen, tmp = set(), []
            for d in dirs:
                if d.lower() not in seen:
                    seen.add(d.lower())
                    tmp.append(d)
            dirs = tmp

    if not dirs:
        print("错误：未找到 Notepad++ 配置目录。请用 --config-dir 手动指定，", file=sys.stderr)
        print("      常见位置：%APPDATA%\\Notepad++ 或 notepad++.exe 同级目录。", file=sys.stderr)
        return 1

    all_result = []
    for config_dir in dirs:
        cfg = parse_config(config_dir)
        sess = parse_session(config_dir)
        backup_dir = cfg["effective_backup_dir"] or os.path.join(config_dir, "backup")
        items = scan_backups(backup_dir)
        shutdown = parse_shutdown_log(config_dir)
        md = build_markdown(config_dir, cfg, sess, items, backup_dir, shutdown)

        entry = {
            "config_dir": config_dir,
            "backup_dir": backup_dir,
            "config": cfg,
            "session": sess,
            "shutdown_log": {
                "exists": shutdown.get("exists"),
                "events": shutdown.get("events", []),
            },
            "count": len(items),
            "total_bytes": sum(i["size"] for i in items),
            "items": items,
        }

        if not args.json:
            print_report(config_dir, cfg, sess, items, backup_dir, shutdown)

        if args.index:
            idx = args.index
            if len(dirs) > 1:
                root, ext = os.path.splitext(idx)
                idx = "%s-%s%s" % (root, os.path.basename(config_dir) or "profile", ext)
            with open(idx, "w", encoding="utf-8") as f:
                f.write(md)
            entry["index"] = idx
            if not args.json:
                print("清单已生成: %s" % idx)

        if args.archive:
            dest = args.archive
            if len(dirs) > 1:
                dest = os.path.join(args.archive, os.path.basename(config_dir) or "profile")
            copied, index_path = do_archive(backup_dir, dest, items,
                                            md, "未保存文件恢复清单.md")
            # 会话文件必须指向**归档副本**：活的 backup 目录会被 Notepad++ 轮换删除，
            # 指向它的会话文件很快就会失效（实测会弹出 "Cannot open file"）。
            sess_path = make_session(items, dest, os.path.join(dest, SESSION_NAME))
            entry["archive"] = {
                "dir": os.path.abspath(dest),
                "copied": copied,
                "index": os.path.abspath(index_path),
                "session": os.path.abspath(sess_path),
            }
            if not args.json:
                print("归档完成: %s（复制 %d 个文件）" % (dest, copied))
                print("清单位置: %s" % index_path)
                print("会话文件: %s" % sess_path)

        if args.make_session:
            base = args.session_base or backup_dir
            sp = make_session(items, base, args.make_session)
            entry["session_file"] = os.path.abspath(sp)
            if not args.json:
                print("会话文件已生成: %s" % sp)
                print("  在 Notepad++ 中：文件 -> 载入会话(Load Session) 选中它即可一次性打开全部备份")

        all_result.append(entry)

    if args.json:
        print(json.dumps(all_result if len(all_result) > 1 else all_result[0],
                         ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

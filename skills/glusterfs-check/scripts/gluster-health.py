#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""gluster-health.py -- GlusterFS 只读巡检，人读版报告。

它不做别的事：把 gluster / lvs / df / heketi 的查询结果翻译成一张中文表，
最后给出 P0/P1/P2 结论。全程只读：不写文件、不启停服务、不触发 heal、不改 LVM。

这是"给人看"的输出，不替代 `##STATE` 三态契约（那套见 gluster-check.sh 等）。
判定口径与 references/thresholds.md 一致；设计取舍见 docs/adr/0012-人读版报告脚本.md。

用法：
    python scripts/gluster-health.py --nodes 192.168.1.42,192.168.1.43,192.168.1.44
    python scripts/gluster-health.py --nodes ... --heketi-on 192.168.1.42
    python scripts/gluster-health.py --nodes ... --verbose   # 附每块砖明细 + 实际执行的命令
    python scripts/gluster-health.py --fixtures tests/fixtures   # 离线自测，不连任何主机

运行位置：
    任何能 ssh 到这几台机器的地方（Windows/macOS/Linux 都行）；
    如果直接跑在 42 上，脚本会自动识别本机地址，不再 ssh 自己。

依赖：python 2.7 或 3.x；ssh 客户端（OpenSSH）。
"""

from __future__ import print_function, unicode_literals

import io
import os
import re
import socket
import subprocess
import sys
import time
import unicodedata

PY2 = sys.version_info[0] < 3
IS_WIN = os.name == 'nt'
W = 74  # 报告宽度

if PY2:
    text_type = unicode          # noqa: F821  (py2 专用)
else:
    text_type = str


def _u(s):
    """统一成 unicode。

    py2 下 str 是字节串，一旦混进 % 格式化或 east_asian_width() 就会报
    "must be unicode, not str"。所有要进表格的文本都过这道闸。
    """
    if isinstance(s, text_type):
        return s
    if isinstance(s, bytes):
        return s.decode('utf-8', 'replace')
    return text_type(s)

# ---------------------------------------------------------------- 输出 ----


def emit(text):
    """跨 py2/py3 的 UTF-8 输出。"""
    data = _u(text).encode('utf-8')
    if PY2:
        sys.stdout.write(data)
    else:
        sys.stdout.buffer.write(data)


def out(text=''):
    emit(_u(text).rstrip() + '\n')


def rule(char='-'):
    out(char * W)


def section(no, title):
    out()
    out(' %s、%s' % (no, title))
    rule('-')

# ---------------------------------------------------------------- 采集 ----


def local_ips():
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            ips.add(info[4][0])
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('192.0.2.1', 9))          # 不真正发包，只为拿出口地址
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return ips


class Runner(object):
    def __init__(self, timeout=120, fixtures=None):
        self.timeout = timeout
        self.local = local_ips()
        self.fixtures = fixtures
        self.executed = []

    def _ssh_opts(self):
        known = 'NUL' if IS_WIN else '/dev/null'
        # LogLevel=ERROR 很关键：否则首次连一台新机器时 ssh 会往 stderr 打
        # "Warning: Permanently added '<ip>' (ECDSA) to the list of known hosts."，
        # 这行被并进 stdout 后会被当成 findmnt 输出，直接造成"砖挂载丢失"的误报。
        return ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'LogLevel=ERROR',
                '-o', 'UserKnownHostsFile=' + known]

    def run(self, node, key, cmd, timeout=None):
        """返回 (rc, 输出文本)。fixtures 模式下从文件读，不连主机。"""
        if self.fixtures:
            path = os.path.join(self.fixtures, key + '.out')
            if not os.path.exists(path):
                return 127, ''
            with io.open(path, 'r', encoding='utf-8', errors='replace') as f:
                return 0, f.read()

        timeout = timeout or self.timeout
        if node in self.local:
            argv = ['bash', '-c', cmd]
            self.executed.append('(本机) ' + cmd)
        else:
            argv = ['ssh'] + self._ssh_opts() + ['root@' + node, cmd]
            self.executed.append('ssh root@%s %s' % (node, cmd))

        try:
            p = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT)
            if not PY2:
                try:
                    data, _ = p.communicate(timeout=timeout)
                except subprocess.TimeoutExpired:
                    p.kill()
                    data, _ = p.communicate()
                    return 124, 'timeout'
            else:
                data, _ = p.communicate()
            if data is None:
                data = b''
            if not isinstance(data, bytes):
                data = data.encode('utf-8', 'replace')
            return p.returncode, data.decode('utf-8', 'replace')
        except OSError as exc:
            return 127, 'ssh 失败: %s' % exc

# ---------------------------------------------------------------- 解析 ----


def pick(block, tag):
    m = re.search(r'<%s>([^<]*)</%s>' % (tag, tag), block)
    return m.group(1).strip() if m else None


def parse_vinfo(xml):
    vols = []
    for blk in re.findall(r'<volume>(.*?)</volume>', xml, re.S):
        head = blk.split('<optCount>')[0]
        d = {
            'name': pick(head, 'name'),
            'status': pick(head, 'statusStr'),
            'type': pick(head, 'typeStr'),
            'dist': int(pick(head, 'distCount') or 0),
            'repl': int(pick(head, 'replicaCount') or 0),
            'arb': int(pick(head, 'arbiterCount') or 0),
            'disp': int(pick(head, 'disperseCount') or 0),
            'snap': pick(head, 'snapshotCount'),
            'bricks': [],
            'opts': {},
        }
        for bm in re.finditer(r'<brick[^>]*>(.*?)</brick>', blk, re.S):
            body = bm.group(1)
            nm = re.search(r'<name>([^<]+)</name>', body)
            if not nm:
                continue
            host, _, path = nm.group(1).partition(':')
            d['bricks'].append({
                'host': host,
                'path': path,
                'arb': pick(body, 'isArbiter') == '1',
            })
        for om in re.finditer(r'<option>\s*<name>([^<]+)</name>\s*<value>([^<]*)</value>',
                              blk, re.S):
            d['opts'][om.group(1)] = om.group(2)
        if d['name']:
            vols.append(d)
    return vols


def parse_vstatus(xml):
    res = {}
    for blk in re.findall(r'<volume>(.*?)</volume>', xml, re.S):
        name = pick(blk, 'volName')
        if not name:
            continue
        bricks, shd = [], []
        for nm in re.findall(r'<node>(.*?)</node>', blk, re.S):
            hostname = pick(nm, 'hostname') or ''
            status = pick(nm, 'status')
            port = pick(nm, 'port')
            path = pick(nm, 'path') or ''
            rec = {'host': hostname, 'path': path,
                   'up': status == '1', 'port': port}
            if hostname == 'Self-heal Daemon':
                shd.append(rec)
            else:
                bricks.append(rec)
        res[name] = {'bricks': bricks, 'shd': shd}
    return res


def parse_heal(xml):
    total = sb = 0
    bricks = []
    for bm in re.finditer(r'<brick[^>]*>(.*?)</brick>', xml, re.S):
        body = bm.group(1)
        name = pick(body, 'name') or '?'
        st = pick(body, 'status') or '?'
        t = int(pick(body, 'totalNumberOfEntries') or 0)
        s = int(pick(body, 'numberOfEntriesInSplitBrain') or 0)
        total += t
        sb += s
        bricks.append({'name': name, 'status': st, 'entries': t, 'sb': s})
    return {'total': total, 'sb': sb, 'bricks': bricks}


def parse_peer(text):
    peers = []
    for blk in re.split(r'Hostname:\s*', text)[1:]:
        host = blk.split('\n')[0].strip()
        st = re.search(r'State:\s*(.+)', blk)
        ip = re.search(r'Other names:\s*\n\s*([0-9.]+)', blk)
        peers.append({
            'host': host,
            'state': st.group(1).strip() if st else '?',
            'ip': ip.group(1) if ip else '',
        })
    m = re.search(r'Number of Peers:\s*(\d+)', text)
    return {'count': int(m.group(1)) if m else len(peers), 'peers': peers}


def parse_df(text):
    """df -P / df -P -i 输出 -> [{'fs','total','used','avail','pct','mount'}]"""
    rows = []
    for line in text.splitlines():
        if not line.strip() or line.startswith('Filesystem'):
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        mount = ' '.join(parts[5:])
        pct = parts[4].rstrip('%')
        if not pct.isdigit():
            continue
        rows.append({'fs': parts[0], 'total': parts[1], 'used': parts[2],
                     'avail': parts[3], 'pct': int(pct), 'mount': mount})
    return rows


def parse_dfi(text):
    return parse_df(text)


def parse_findmnt(text, dirs):
    """解析带 ##F 标记的 findmnt 输出 -> {砖目录: {target, source, fstype, err}}。

    必须在远端打标记：远端命令输出里可能混进 ssh 警告、motd、profile 的 echo，
    按行序对应砖会错位，进而把"A 砖的信息"安到"B 砖"头上。这里按目录名匹配。
    """
    res = {}
    for line in text.splitlines():
        if not line.startswith('##F '):
            continue
        parts = line[4:].strip().split()
        if len(parts) < 2:
            continue
        d = parts[0]
        if len(parts) >= 4 and parts[1].startswith('/'):
            res[d] = {'target': parts[1], 'source': parts[2],
                      'fstype': parts[3], 'err': None}
        else:
            res[d] = {'target': None, 'source': None, 'fstype': None,
                      'err': ' '.join(parts[1:]) or 'no-output'}
    for d in dirs:
        res.setdefault(d, {'target': None, 'source': None, 'fstype': None,
                           'err': 'no-marker'})
    return res


def parse_lvs(text):
    """从右往左取列：最后两列是 data/meta 百分比，第三列是大小；
    thin pool 行的 pool_lv 是空的，所以不能按固定列位切。"""
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        rows.append({
            'lv': parts[0],
            'vg': parts[1],
            'pool': ' '.join(parts[2:-3]),
            'size': parts[-3],
            'data': parts[-2],
            'meta': parts[-1],
        })
    return rows


def to_float(s):
    try:
        return float(_u(s).replace(',', '.').rstrip('%'))
    except (TypeError, ValueError):
        return None


def parse_heketi(text):
    """解析带 ## 前缀的 heketi 输出。"""
    res = {'service': None, 'version': None, 'cluster': None,
           'nodes': [], 'devices': [], 'volumes': [], 'raw': [],
           'no_secret': False}
    cur = None
    for line in text.splitlines():
        if line.startswith('##HEKETI_SERVICE '):
            res['service'] = line.split(' ', 1)[1].strip()
        elif line.startswith('##HEKETI_VERSION '):
            res['version'] = line.split(' ', 1)[1].strip()
        elif line.startswith('##NO_SECRET'):
            res['no_secret'] = True
        elif line.startswith('##CLUSTER '):
            body = line[10:].strip()
            m = re.search(r'Cluster Id:\s*(\w+)', body)
            if m and not res['cluster']:
                res['cluster'] = m.group(1)
            elif re.match(r'^[0-9a-fA-F]{32}$', body) and not res['cluster']:
                res['cluster'] = body        # 有的版本只打一串 id
        elif line.startswith('##TOPO '):
            body = line[7:]
            res['raw'].append(body)
            if re.match(r'\s*Node Id:', body):
                cur = {'id': body.split(':', 1)[1].strip(), 'state': '?'}
                res['nodes'].append(cur)
            elif 'Size (GiB)' in body:
                m = re.search(
                    r'State:(\w+).*?Size \(GiB\):\s*([\d.]+).*?'
                    r'Used \(GiB\):\s*([\d.]+).*?Free \(GiB\):\s*([\d.]+)',
                    body)
                if m:
                    res['devices'].append({
                        'state': m.group(1),
                        'size': float(m.group(2)),
                        'used': float(m.group(3)),
                        'free': float(m.group(4)),
                    })
            elif 'State:' in body and cur is not None:
                m = re.search(r'State:\s*(\w+)', body)
                if m:
                    cur['state'] = m.group(1)
        elif line.startswith('##VOL '):
            body = line[6:]
            m = re.search(r'Id:(\w+).*?Name:(vol_\w+)', body)
            if m:
                res['volumes'].append(m.group(2))
        elif line.startswith('##ERR '):
            res['raw'].append(line[6:])

    # cluster id 兜底：cluster list 的输出形态在不同 heketi 版本里不一致，
    # 拓扑信息里也带 Cluster Id，卷列表里带 Cluster:<id>，按可信度依次兜。
    if not res['cluster']:
        m = re.search(r'Cluster Id:\s*([0-9A-Za-z]+)', text)
        if m:
            res['cluster'] = m.group(1)
    if not res['cluster']:
        m = re.search(r'Cluster:([0-9a-fA-F]{32})', text)
        if m:
            res['cluster'] = m.group(1)
    return res

# ---------------------------------------------------------------- 判定 ----


class Findings(object):
    def __init__(self):
        self.items = []

    def add(self, sev, title, detail=''):
        self.items.append({'sev': sev, 'title': title, 'detail': detail})

    def count(self, sev):
        return len([x for x in self.items if x['sev'] == sev])


def short_brick(path):
    """把 /var/lib/heketi/mounts/vg_x/brick_y/brick 压成 brick_y…"""
    p = path.rstrip('/')
    name = os.path.basename(p)
    if name == 'brick':
        name = os.path.basename(os.path.dirname(p))
    return (name[:16] + '…') if len(name) > 17 else name


def default_volume_type(v):
    if v['repl'] <= 1 and v['arb'] == 0 and v['disp'] == 0:
        return 'none'
    return 'replicated'


def judge_volume(v, st, heal, f):
    name = v['name']
    bricks = (st or {}).get('bricks') or []
    has_status = bool(bricks)
    total = len(bricks) or len(v['bricks'])
    online = len([b for b in bricks if b['up']])

    if v['status'] != 'Started':
        f.add('P0', '卷 %s 未启动（%s）' % (name, v['status']),
              '该卷不可读写，使用它的 Pod 会挂载失败')
    if default_volume_type(v) == 'none':
        f.add('P1', '卷 %s 没有副本（Distribute）' % name,
              '任意一块砖坏掉就丢数据')
    if v['dist'] > 1:
        f.add('P1', '卷 %s 被 add-brick 扩过（distCount=%d）' % (name, v['dist']),
              '高风险 PVC 信号：扩容过的卷容易出现权限/容量不一致')
    if v['disp'] == 0 and v['dist'] * (v['repl'] + v['arb']) != (len(v['bricks']) or 1):
        f.add('P1', '卷 %s 拓扑异常：砖数 %d ≠ %d×(%d+%d)' % (
            name, len(v['bricks']), v['dist'], v['repl'], v['arb']),
            '可能是 add-brick/remove-brick 中途失败')

    if not has_status:
        # 没采到状态 != 砖全掉线。宁可标 SKIP，也不能凭空报 P0。
        f.add('SKIP', '卷 %s 的砖状态未采集' % name,
              'gluster v status 失败/超时，本卷的在线判定跳过（不代表正常）')
    elif online < total:
        holes = [b for b in bricks if not b['up']]
        f.add('P0', '卷 %s 有 %d/%d 块砖离线' % (name, total - online, total),
              '离线：' + '、'.join('%s:%s' % (b['host'], short_brick(b['path']))
                                  for b in holes))

    if default_volume_type(v) != 'none':
        if heal is None:
            f.add('SKIP', '卷 %s 的 heal 信息未采集' % name,
                  'gluster v heal 失败/超时，不能当成 0 条待自愈')
        elif heal['sb'] > 0:
            f.add('P0', '卷 %s 存在脑裂 %d 条（待自愈 %d 条）' % (
                name, heal['sb'], heal['total']),
                  '必须人工介入（08 手册），本工具不做任何自动处置')
        elif heal['total'] >= 100:
            f.add('P0', '卷 %s 待自愈 %d 条（≥100）' % (name, heal['total']),
                  '已不是瞬时抖动，需要人工确认')
        elif heal['total'] > 0:
            f.add('P1', '卷 %s 待自愈 %d 条' % (name, heal['total']),
                  '10 分钟后再看一次：仍 >0 升 P0，归零则关闭')
        if heal and any(b['status'] != 'Connected' for b in heal['bricks']):
            f.add('P0', '卷 %s 的 heal 检查中有砖未 Connected' % name,
                  '通常与砖离线同源，不重复计数')

    snap = v['snap']
    if snap not in (None, '', '0'):
        f.add('P2', '卷 %s 有 %s 个快照' % (name, snap),
              '快照持续占 thin pool，且阻止卷删除/缩容')

    if v['opts'].get('nfs.disable', '') != 'on':
        f.add('P2', '卷 %s 未关闭 NFS（nfs.disable=%s）' % (
            name, v['opts'].get('nfs.disable', '缺失')), '基线要求 nfs.disable=on')
    if 'user.heketi.id' not in v['opts']:
        f.add('P1', '卷 %s 缺 user.heketi.id' % name,
              'heketi 可能无法管理该卷（扩容/删除会失败）')
    if 'auth.allow' in v['opts']:
        f.add('P2', '卷 %s 设置了 auth.allow' % name,
              '可能是刻意限制访问，需人工确认')


def judge_node(n, svc, ver, df_rows, dfi_rows, lvs_rows, fm_rows, bricks, f):
    if svc != 'active':
        f.add('P0', '%s 的 glusterd 不是 active（%s）' % (n, svc or '取不到'),
              '该节点的砖全部不可用')

    for i, br in enumerate(bricks):
        fm = fm_rows.get(br['path'])
        label = '%s:%s' % (br['host'], short_brick(br['path']))
        if not fm or fm.get('source') is None:
            f.add('P0', '砖挂载检查失败 %s' % label,
                  (fm or {}).get('err') or 'findmnt 无输出')
            continue
        lvname = os.path.basename(fm['target'] or '')
        if fm['fstype'] != 'xfs' or lvname not in (fm['source'] or ''):
            f.add('P0', '砖 %s 挂载丢失（实际来源 %s，类型 %s）' % (
                label, fm['source'], fm['fstype']),
                '数据还在 LV 里，但砖目录已指向别的文件系统，等同砖不可用')

    for row in df_rows:
        if row['pct'] >= 90:
            f.add('P0', '%s 的 %s 使用率 %d%%' % (n, short_brick(row['mount']), row['pct']),
                  '写满会报 no space left on device，甚至 Transport endpoint is not connected')
        elif row['pct'] >= 80:
            f.add('P2', '%s 的 %s 使用率 %d%%' % (n, short_brick(row['mount']), row['pct']),
                  '进入 80% 以上，计划内扩容/清理')

    for row in dfi_rows:
        if row['pct'] >= 90:
            f.add('P0', '%s 的 %s inode 使用率 %d%%' % (n, short_brick(row['mount']), row['pct']),
                  '小文件多时 inode 先耗尽，同样写不进去')
        elif row['pct'] >= 80:
            f.add('P2', '%s 的 %s inode 使用率 %d%%' % (n, short_brick(row['mount']), row['pct']),
                  '进入 80% 以上，计划内清理')

    for row in lvs_rows:
        if not row['lv'].startswith('tp_'):
            continue
        d = to_float(row['data'])
        m = to_float(row['meta'])
        pool = (row['lv'][:10] + '…') if len(row['lv']) > 11 else row['lv']
        if d is not None and d >= 90:
            f.add('P0', '%s 的 thin pool %s 已分配 %.1f%%' % (n, pool, d),
                  '池满后写入 EIO、砖转只读')
        elif d is not None and d >= 80:
            f.add('P2', '%s 的 thin pool %s 已分配 %.1f%%' % (n, pool, d),
                  '若同砖 df 很低，说明删文件后块未回收（fstrim 可回落）')
        if m is not None and m >= 80:
            f.add('P2', '%s 的 thin pool %s 元数据 %.1f%%' % (n, pool, m),
                  '元数据满同样锁死池')


def judge_heketi(hk, gluster_vols, f):
    if hk['service'] and hk['service'] != 'active':
        f.add('P0', 'heketi 服务不是 active（%s）' % hk['service'],
              '无法新建/删除/扩容 PVC')
    if hk['no_secret']:
        f.add('SKIP', 'heketi 凭据读取失败',
              '/etc/heketi/heketi.json 里没解析到 jwt.admin.key，heketi 相关判定跳过')

    offline_nodes = [n for n in hk['nodes'] if n['state'] != 'online']
    if offline_nodes:
        f.add('P0', 'heketi 有 %d 个节点离线' % len(offline_nodes),
              '离线节点的砖不可调度')

    dev_off = [d for d in hk['devices'] if d['state'] != 'online']
    if dev_off:
        f.add('P1', 'heketi 有 %d 个设备离线' % len(dev_off),
              '可用容量减少，heketi 不会再往上放砖')

    sizes = sum(d['size'] for d in hk['devices'])
    free = sum(d['free'] for d in hk['devices'])
    if sizes > 0:
        ratio = free * 100.0 / sizes
        if ratio < 10:
            f.add('P0', 'heketi 存储池余量 %.1f%%（<10%%）' % ratio,
                  '即将无法新建/扩容 PVC')
        elif ratio < 20:
            f.add('P1', 'heketi 存储池余量 %.1f%%（<20%%）' % ratio,
                  '按当前速度会较快耗尽')

    if hk['volumes']:
        hk_set = set(hk['volumes'])
        gl_set = set(gluster_vols)
        missing = hk_set - gl_set
        orphan = gl_set - hk_set
        if missing:
            f.add('P0', 'heketi 记录了 %d 个卷，gluster 里不存在' % len(missing),
                  '、'.join(sorted(missing)) + ' —— 对应 PVC 的后端已丢')
        if orphan:
            f.add('P2', 'gluster 里有 %d 个卷 heketi 不认' % len(orphan),
                  '、'.join(sorted(orphan)) + ' —— 孤儿卷，白占池空间，需人工确认')

# ---------------------------------------------------------------- 排版 ----


def dwidth(s):
    """终端显示宽度：CJK 全角字符算 2 列。"""
    w = 0
    for ch in _u(s):
        w += 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
    return w


def pad(s, width, align='<'):
    s = _u(s)
    gap = width - dwidth(s)
    if gap < 0:
        gap = 0
    if align == '>':
        return ' ' * gap + s
    if align == '^':
        left = gap // 2
        return ' ' * left + s + ' ' * (gap - left)
    return s + ' ' * gap


def row(cells):
    """cells: [(文本, 宽度, 对齐)] -> 一行（每格先过 _u，避免 py2 字节串）。"""
    return ' ' + ' '.join(pad(_u(t), w, a) for t, w, a in cells)

# ---------------------------------------------------------------- 主流程 ----

USAGE = '''用法:
  python gluster-health.py --nodes 192.168.1.42,192.168.1.43,192.168.1.44
选项:
  --nodes a,b,c    节点 IP，第一台为执行点（必填）
  --heketi-on IP   heketi 所在节点，默认第一台
  --verbose        附每块砖明细 + 实际执行的命令
  --timeout N      单条命令超时秒数，默认 120
  --fixtures DIR   离线自测：从目录读采集结果，不连主机
'''

# 手写解析：py2 下 argparse 把 unicode 帮助文本写到 ASCII stdout 会抛
# UnicodeEncodeError；这里全部走 emit()，两种 python 行为一致。
FLAGS = {
    '--nodes': 'nodes',
    '--heketi-on': 'heketi_on',
    '--timeout': 'timeout',
    '--fixtures': 'fixtures',
}


def parse_args(argv):
    opts = {'nodes': None, 'heketi_on': None, 'verbose': False,
            'timeout': 120, 'fixtures': None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('-h', '--help'):
            emit(USAGE)
            raise SystemExit(0)
        if a == '--verbose':
            opts['verbose'] = True
            i += 1
            continue
        key, val = None, None
        if '=' in a and a.split('=', 1)[0] in FLAGS:
            key, val = a.split('=', 1)
        elif a in FLAGS and i + 1 < len(argv):
            key, val = a, argv[i + 1]
            i += 1
        if key is None:
            emit('未知参数: %s\n' % a)
            emit(USAGE)
            raise SystemExit(2)
        name = FLAGS[key]
        opts[name] = int(val) if name == 'timeout' else val
        i += 1
    return opts


def main(argv):
    opts = parse_args(argv)

    if not opts['nodes'] and not opts['fixtures']:
        emit(USAGE)
        return 2

    nodes = [x.strip() for x in (opts['nodes'] or
                                 '192.168.1.42,192.168.1.43,192.168.1.44').split(',')
             if x.strip()]
    heketi_on = opts['heketi_on'] or nodes[0]
    r = Runner(timeout=opts['timeout'], fixtures=opts['fixtures'])
    f = Findings()

    # ---- 采集
    meta = {}
    conn_bad = []
    for n in nodes:
        rc, txt = r.run(n, 'node.%s.identity' % n,
                        'echo "##HOST $(hostname 2>/dev/null)"; '
                        'echo "##DATE $(date \'+%Y-%m-%d %H:%M %z\' 2>/dev/null)"; '
                        'echo "##SVC $(timeout 10 systemctl is-active glusterd 2>&1)"; '
                        'echo "##VER $(timeout 10 gluster --version 2>&1 | head -1)"',
                        timeout=40)
        d = {'svc': '', 'ver': '', 'host': '', 'date': ''}
        for line in txt.splitlines():
            for k, tag in (('host', '##HOST '), ('date', '##DATE '),
                           ('svc', '##SVC '), ('ver', '##VER ')):
                if line.startswith(tag):
                    d[k] = line[len(tag):].strip()
        meta[n] = d
        if rc == 255 or 'Permission denied' in txt or 'Connection timed out' in txt \
                or 'Connection refused' in txt or 'Could not resolve' in txt:
            conn_bad.append(n)

    if conn_bad:
        out()
        out(' [FAIL] 连不上：%s' % '、'.join(conn_bad))
        out('        检查：本机公钥是否已放到这些机器的 root；IP/端口是否可达。')
        out()
        return 3

    rc, peer_txt = r.run(nodes[0], 'peer', 'timeout 20 gluster peer status 2>&1', timeout=40)
    peer = parse_peer(peer_txt) if rc == 0 else {'count': 0, 'peers': []}

    rc, vinfo_txt = r.run(nodes[0], 'vinfo', 'timeout 60 gluster v info --xml 2>&1', timeout=90)
    vols = parse_vinfo(vinfo_txt) if rc == 0 else []
    if rc != 0 or not vols:
        f.add('SKIP', '拿不到卷信息（gluster v info 失败）', 'rc=%d，后续卷判定不可用' % rc)

    rc, vstat_txt = r.run(nodes[0], 'vstatus', 'timeout 60 gluster v status --xml 2>&1', timeout=90)
    vstat = parse_vstatus(vstat_txt) if rc == 0 else {}

    heals = {}
    for v in vols:
        if default_volume_type(v) == 'none':
            continue
        key = 'heal.%s' % v['name']
        rc, htxt = r.run(nodes[0], key,
                         'timeout 120 gluster v heal %s info summary --xml 2>&1' % v['name'],
                         timeout=150)
        heals[v['name']] = parse_heal(htxt) if rc == 0 else None

    # 每台主机：砖目录 -> findmnt / df / inode / lvs
    node_data = {}
    for n in nodes:
        mine = [b['path'] for v in vols for b in v['bricks'] if b['host'] == n]
        mine = sorted(set(mine))
        nd = {'bricks': [{'host': n, 'path': p} for p in mine],
              'fm': {}, 'df': [], 'dfi': [], 'lvs': []}
        if not mine:
            node_data[n] = nd
            continue
        dirs = ' '.join(mine)
        rc, txt = r.run(n, 'node.%s.findmnt' % n,
                        'for d in %s; do echo -n "##F $d "; '
                        'timeout 10 findmnt -n -T "$d" -o TARGET,SOURCE,FSTYPE '
                        '2>/dev/null || echo ERR; done' % dirs,
                        timeout=60)
        nd['fm'] = parse_findmnt(txt, mine) if rc == 0 else {}
        rc, txt = r.run(n, 'node.%s.df' % n, 'timeout 20 df -P -B1 %s 2>&1' % dirs, timeout=40)
        nd['df'] = parse_df(txt) if rc == 0 else []
        rc, txt = r.run(n, 'node.%s.dfi' % n, 'timeout 20 df -P -i %s 2>&1' % dirs, timeout=40)
        nd['dfi'] = parse_dfi(txt) if rc == 0 else []
        rc, txt = r.run(n, 'node.%s.lvs' % n,
                        'timeout 20 lvs --noheadings -o '
                        'lv_name,vg_name,pool_lv,lv_size,data_percent,metadata_percent 2>&1',
                        timeout=40)
        nd['lvs'] = parse_lvs(txt) if rc == 0 else []
        node_data[n] = nd

    # heketi
    hk = None
    if heketi_on:
        script = (
            'echo "##HEKETI_SERVICE $(timeout 10 systemctl is-active heketi 2>&1)"\n'
            'echo "##HEKETI_VERSION $(timeout 10 heketi-cli --version 2>&1 | head -1)"\n'
            'SEC=$(awk -v u=admin '
            '\'index($0,"\\"" u "\\"")>0 && /:[[:space:]]*\\{[[:space:]]*$/ {inb=1;next} '
            'inb && /"key"[[:space:]]*:/ {sub(/.*"key"[[:space:]]*:[[:space:]]*"/,""); '
            'sub(/".*/,""); print; exit}\' /etc/heketi/heketi.json 2>/dev/null)\n'
            'if [ -n "$SEC" ]; then\n'
            '  timeout 20 heketi-cli --user admin --secret "$SEC" cluster list 2>&1 '
            '| sed "s/^/##CLUSTER /"\n'
            '  timeout 60 heketi-cli --user admin --secret "$SEC" topology info 2>&1 '
            '| sed "s/^/##TOPO /"\n'
            '  timeout 20 heketi-cli --user admin --secret "$SEC" volume list 2>&1 '
            '| sed "s/^/##VOL /"\n'
            'else\n'
            '  echo "##NO_SECRET"\n'
            'fi\n'
        )
        rc, txt = r.run(heketi_on, 'heketi', script, timeout=150)
        hk = parse_heketi(txt) if rc == 0 else None

    # ---- 判定
    for v in vols:
        judge_volume(v, vstat.get(v['name']), heals.get(v['name']), f)

    bad_peers = [p for p in peer['peers'] if 'Connected' not in p['state']]
    if bad_peers:
        f.add('P0', '集群成员异常：%d 个 peer 未 Connected' % len(bad_peers),
              '；'.join('%s(%s) %s' % (p['host'], p['ip'], p['state']) for p in bad_peers))

    for n in nodes:
        d = meta.get(n, {})
        judge_node(n, d.get('svc', ''), d.get('ver', ''),
                   node_data[n]['df'], node_data[n]['dfi'],
                   node_data[n]['lvs'], node_data[n]['fm'],
                   node_data[n]['bricks'], f)

    if hk is not None:
        judge_heketi(hk, [v['name'] for v in vols], f)

    # ---- 渲染
    first = nodes[0]
    stamp = meta.get(first, {}).get('date') or time.strftime('%Y-%m-%d %H:%M %z')
    out()
    out('=' * W)
    scope = nodes[0] if len(nodes) == 1 else '-'.join([nodes[0], nodes[-1]])
    out(' GlusterFS 巡检报告   %s' % scope)
    out(' 时间 %s   只读快照   执行点 %s（%s）' % (
        stamp, first, meta.get(first, {}).get('host', '?')))
    out('=' * W)

    # 一、节点
    section('一', '节点与服务')
    for n in nodes:
        d = meta.get(n, {})
        svc = d.get('svc', '')
        ver = re.sub(r'^glusterfs\s*', '', d.get('ver', '') or '?')
        mark = '[ OK ]' if svc == 'active' else '[FAIL]'
        out(' %s %-15s %-12s glusterd %-8s glusterfs %s' % (
            mark, n, d.get('host', '?'), svc or '?', ver))

    if peer['peers']:
        ok = len([p for p in peer['peers'] if 'Connected' in p['state']])
        mark = '[ OK ]' if ok == len(peer['peers']) else '[FAIL]'
        out(' %s 集群成员 %d 台（%d 个 peer），%d/%d Connected' % (
            mark, ok + 1, len(peer['peers']), ok, len(peer['peers'])))
        for p in peer['peers']:
            st = 'Connected' if 'Connected' in p['state'] else p['state']
            note = '（名称别名）' if 'arbiter' in p['host'] else ''
            out('        %-20s %-15s %s%s' % (p['host'], p['ip'], st, note))

    # 二、卷
    section('二', '卷与数据')
    if not vols:
        out(' [SKIP] 没有取到卷信息')
    else:
        out(' %d 个卷' % len(vols))
        out(row([('卷名', 40, '<'), ('拓扑', 6, '<'), ('在线', 7, '>'),
                 ('待自愈', 7, '>'), ('脑裂', 4, '>'), ('快照', 5, '>')]))
        for v in vols:
            st = vstat.get(v['name']) or {}
            bricks = st.get('bricks') or []
            total = len(bricks) or len(v['bricks'])
            online = len([b for b in bricks if b['up']])
            h = heals.get(v['name'])
            topo = '%dx%d' % (v['dist'], v['repl']) if v['disp'] == 0 else 'disp%d' % v['disp']
            if v['arb']:
                topo += '+%d' % v['arb']
            out(row([(v['name'], 40, '<'), (topo, 6, '<'),
                     (('%d/%d' % (online, total)) if bricks else 'n/a', 7, '>'),
                     (('%d' % h['total']) if h else '?', 7, '>'),
                     (('%d' % h['sb']) if h else '?', 4, '>'),
                     (v['snap'] or '?', 5, '>')]))
        bad = [v for v in vols if v['status'] != 'Started']
        if bad:
            out(' [FAIL] %s 未启动' % '、'.join(v['name'] for v in bad))

    # 三、容量
    section('三', 'brick 容量与挂载')
    out(row([('节点', 15, '<'), ('砖', 4, '>'), ('最满使用率', 11, '>'),
             ('inode', 7, '>'), ('池分配率', 10, '>'), ('挂载', 6, '<')]))
    for n in nodes:
        nd = node_data[n]
        if not nd['bricks']:
            out(row([(n, 15, '<'), ('-', 4, '>'), ('-', 11, '>'),
                     ('-', 7, '>'), ('-', 10, '>'), ('-', 6, '<')]))
            continue
        pct = max([x['pct'] for x in nd['df']] or [0])
        ipct = max([x['pct'] for x in nd['dfi']] or [0])
        pools = [to_float(x['data']) for x in nd['lvs'] if x['lv'].startswith('tp_')]
        pools = [p for p in pools if p is not None]
        pool = ('%.1f%%' % max(pools)) if pools else '?'
        fm_vals = list(nd['fm'].values())
        fm_ok = bool(fm_vals) and all(x.get('source') and x['fstype'] == 'xfs'
                                      for x in fm_vals)
        out(row([(n, 15, '<'), ('%d' % len(nd['bricks']), 4, '>'),
                 ('%d%%' % pct, 11, '>'), ('%d%%' % ipct, 7, '>'),
                 (pool, 10, '>'), ('[ OK ]' if fm_ok else '[FAIL]', 6, '<')]))

    if opts['verbose']:
        out()
        out(' 砖明细：')
        for n in nodes:
            nd = node_data[n]
            for i, br in enumerate(nd['bricks']):
                fm = nd['fm'].get(br['path'], {})
                out('  %-15s %-58s %s' % (
                    n, '…' + br['path'][-50:],
                    (fm.get('source') or fm.get('err') or '?')))

    # 四、heketi
    section('四', 'heketi')
    if hk is None:
        out(' [SKIP] 未采集（--heketi-on 未指定或命令失败）')
    else:
        svc = hk['service'] or '?'
        mark = '[ OK ]' if svc == 'active' else '[FAIL]'
        out(' %s 服务 %-8s 版本 %-8s 簇 %s' % (
            mark, svc, (hk['version'] or '?'), hk['cluster'] or '?'))
        if hk['nodes'] or hk['devices']:
            ntot = len(hk['nodes'])
            nok = len([x for x in hk['nodes'] if x['state'] == 'online'])
            dtot = len(hk['devices'])
            dok = len([x for x in hk['devices'] if x['state'] == 'online'])
            size = sum(x['size'] for x in hk['devices'])
            free = sum(x['free'] for x in hk['devices'])
            ratio = (free * 100.0 / size) if size else 0
            mark = '[ OK ]' if nok == ntot and dok == dtot and ratio >= 20 else '[WARN]'
            out(' %s 节点 %d/%d 在线   设备 %d/%d 在线   容量 %.0f GiB，余 %.0f GiB（%.1f%%）' % (
                mark, nok, ntot, dok, dtot, size, free, ratio))
        if hk['volumes']:
            gl = set(v['name'] for v in vols)
            hs = set(hk['volumes'])
            if hs == gl:
                out(' [ OK ] 卷对账一致：heketi %d 个 / gluster %d 个' % (len(hs), len(gl)))
            else:
                out(' [WARN] 卷对账不一致：heketi %d 个 / gluster %d 个' % (len(hs), len(gl)))
                if hs - gl:
                    out('        heketi 有、gluster 无：%s' % '、'.join(sorted(hs - gl)))
                if gl - hs:
                    out('        gluster 有、heketi 无：%s' % '、'.join(sorted(gl - hs)))

    # 五、结论
    section('五', '结论')
    out(' P0 × %d    P1 × %d    P2 × %d' % (
        f.count('P0'), f.count('P1'), f.count('P2')))
    if not f.items:
        out(' [ OK ] 未发现需要处置的问题')
    for item in sorted(f.items, key=lambda x: ('P0', 'P1', 'P2', 'SKIP').index(x['sev'])):
        tag = {'P0': '[FAIL]', 'P1': '[WARN]', 'P2': '[WARN]', 'SKIP': '[SKIP]'}[item['sev']]
        out(' %s %s %s' % (tag, item['sev'], item['title']))
        if item['detail']:
            out('        %s' % item['detail'])

    out()
    out(' 说明：单次快照，不含趋势结论；heal 条目、容量变化需多次比对才有意义。')
    out(' 未做：Kubernetes 层（SC/PVC/PV）—— 需要 kubeconfig，本次未提供。')

    if opts['verbose'] and r.executed:
        out()
        out(' 本次执行（只读）：')
        for cmd in r.executed:
            out('  - %s' % cmd)

    out()
    out('=' * W)
    out()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

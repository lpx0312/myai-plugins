#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""gluster-health.py 的离线回归。

两部分：
1) 端到端：用真实采集结果（fixtures / fixtures-bad）跑完整报告，断言结论；
2) 定点：把踩过的坑固化成单元断言（ssh 警告污染 findmnt、heketi 版本间输出差异）。

不连任何主机。用法：python tests/test-report.py
"""

from __future__ import print_function

import importlib.util
import os
import subprocess
import sys

sys.dont_write_bytecode = True   # 不往 scripts/ 里写 __pycache__（ADR-0006 目录卫生）

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'scripts', 'gluster-health.py')

CASES = [
    ('fixtures', ['P0 × 0', 'P1 × 0', 'P2 × 0',
                  '未发现需要处置的问题',
                  '3/3', '卷对账一致', '2 个卷']),
    ('fixtures-bad', ['P0 × 5', 'P1 × 1', 'P2 × 1',
                      '有 1/3 块砖离线', '存在脑裂 2 条',
                      '使用率 92%', '已分配 91.5%',
                      'heketi 有 1 个节点离线', '有 1 个设备离线',
                      '有 1 个快照']),
]

# ssh 首次连接时混进 stdout 的那一行；2026-10-21 线上误报就是它造成的
SSH_NOISE = ("Warning: Permanently added '192.168.1.44' (ECDSA) "
             "to the list of known hosts.")


def load_module():
    spec = importlib.util.spec_from_file_location('gluster_health', SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def unit_checks(mod):
    fails = []

    # 1) findmnt 里有噪音行时，必须按 ##F 标记的目录名匹配，不能按行序
    dirs = ['/mnt/vg_a/brick_aaa/brick', '/mnt/vg_a/brick_bbb/brick']
    text = '\n'.join([
        SSH_NOISE,
        '##F %s /mnt/vg_a/brick_aaa /dev/mapper/vg_a-brick_aaa xfs' % dirs[0],
        '##F %s /mnt/vg_a/brick_bbb /dev/mapper/vg_a-brick_bbb xfs' % dirs[1],
    ])
    got = mod.parse_findmnt(text, dirs)
    if got[dirs[0]]['source'] != '/dev/mapper/vg_a-brick_aaa':
        fails.append('findmnt 标记匹配错位')
    if any('Permanently' in (v.get('source') or '') for v in got.values()):
        fails.append('findmnt 把 ssh 警告当成了挂载来源')

    # 2) findmnt 失败的砖要落成 err，而不是静默变成 None
    got = mod.parse_findmnt('##F %s ERR' % dirs[0], dirs)
    if got[dirs[0]]['source'] is not None or not got[dirs[0]]['err']:
        fails.append('findmnt 失败未被标记')
    if got[dirs[1]]['err'] != 'no-marker':
        fails.append('缺失的砖未被标记 no-marker')

    # 3) heketi cluster id：cluster list 只打一串 id 时也要认出来
    hk = mod.parse_heketi('##CLUSTER 0da3b44ec6c7c94061c94893de3ff02f\n')
    if hk['cluster'] != '0da3b44ec6c7c94061c94893de3ff02f':
        fails.append('heketi 裸 id 未识别')

    # 4) cluster list 啥也没给时，从 topology 的 Cluster Id 兜底
    hk = mod.parse_heketi('##TOPO Cluster Id: ee4c1cb97575ea27abe89e552b79650a\n')
    if hk['cluster'] != 'ee4c1cb97575ea27abe89e552b79650a':
        fails.append('heketi cluster id 未被兜底')

    # 5) py2 下字节串会进表格：pad 必须能吃 bytes（2026-10-21 真机崩溃点）
    try:
        mod.pad(b'abc', 6)
        mod.row([(b'x', 3, '>'), ('中文', 8, '<')])
    except Exception as exc:
        fails.append('pad/row 不接受 bytes: %s' % exc)

    return fails


def main():
    failed = 0
    mod = load_module()
    for msg in unit_checks(mod):
        print('unit           失败: %s' % msg)
        failed += 1
    if not failed:
        print('%-14s ok' % 'unit')

    for case, expects in CASES:
        path = os.path.join(HERE, case)
        p = subprocess.Popen([sys.executable, SCRIPT, '--fixtures', path],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = p.communicate()[0].decode('utf-8', 'replace')
        if p.returncode != 0:
            print('%-14s rc=%d' % (case, p.returncode))
            failed += 1
            continue
        if 'Traceback' in out:
            print('%-14s 出现异常堆栈' % case)
            failed += 1
        miss = [x for x in expects if x not in out]
        if miss:
            print('%-14s 缺失: %s' % (case, ' | '.join(miss)))
            failed += 1
        else:
            print('%-14s ok' % case)

    print('---')
    print('ALL PASS' if failed == 0 else 'FAILED(%d)' % failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

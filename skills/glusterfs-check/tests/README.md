# 回归基线

改脚本前后，按改动范围跑下面三个。**都不需要连任何主机**。

## 1. 静态校验（每次改脚本必跑）

```bash
bash tests/verify-scripts.sh
```

校验项（对应 `docs/adr/0002-脚本输出契约.md`）：

| 检查 | 为什么 |
|---|---|
| `bash -n` | 语法错误 |
| 含 `set -u` | 未定义变量当空处理会掩盖拼写错误 |
| 含 `LC_ALL=C` | `lvs`/`df` 的小数点、列宽受 locale 影响 |
| 无裸 `\|\| true` | 吞掉错误后"空输出"会被误判 PASS |
| 无硬编码口令 | 凭据必须就地读取 |
| 每个脚本都有 `_state` 且以 `##END` 收尾 | 三态契约 |
| 有 `##STATE` 输出且有 `CMD:` 行 | 报告自检要能列出"执行了什么" |

## 2. 人读版脚本回归（python）

```bash
python tests/test-report.py
```

`tests/fixtures`（真实采集结果，正常态）与 `tests/fixtures-bad`（在其上构造 5 类故障）
喂给 `scripts/gluster-health.py`，断言结论行；另有单元断言覆盖真机踩过的三类坑：

| 断言 | 为什么 |
|---|---|
| `##F` 噪音行被忽略、按目录名匹配 | ssh 的 `Warning: Permanently added ...` 曾顶掉 findmnt 首行，误报"砖挂载丢失" |
| 缺数据落 `SKIP`，不显示成 0 | `v status` / `heal` 采集失败不能变成"一切正常" |
| `pad/row` 接受 bytes | python 2.7 下 `str()` 是字节串，曾直接 `TypeError` 崩在表格第一行 |

## 3. 结构样例（golden sample）

`tests/samples/*.golden` 是**结构**样例：id、IP、时间都换成了占位符，只用来确认
"某个检查项的块长什么样、状态行怎么写"，**不能**拿它跟真实输出做逐字 diff（真实 id 每次都不一样）。

比对方式：只看形状——

```bash
# 真实输出里的状态行
... | grep '^##STATE' | sed 's/\[.*\]//' | sort -u
# 与样例的状态行比较
grep '^##STATE' tests/samples/gluster-check.golden | sed 's/\[.*\]//' | sort -u
```

## 4. 新增检查项时的清单

1. `references/checks.md` 写判定与证据要求；
2. `references/thresholds.md` 写阈值与严重级；
3. `scripts/*.sh` 加采集段，输出 `##<ID> CMD` / 原始输出 / `##STATE`；
4. **人读版同步**：`scripts/gluster-health.py` 的 `judge_*` 加同一判据（两处维护，见 ADR-0012）；
5. `tests/samples/*.golden` 补形状；改了解析就给 `tests/fixtures*` 补样本；
6. 跑 `bash tests/verify-scripts.sh` 和 `python tests/test-report.py`；
7. 如引入新词，补 `docs/glossary.md`；如改判据口径，补 ADR。

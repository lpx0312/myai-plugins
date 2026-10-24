---
name: glusterfs-check
description: GlusterFS 只读巡检（heketi + Kubernetes 场景）。检查集群/卷/brick 健康、heal 与 split-brain、brick 容量、heketi 拓扑与设备、SC/PVC/PV 映射与高风险 PVC，输出带严重级的巡检报告和人工修复指引。绝不执行任何修改类动作（扩容、改 PVC、替换 PVC、触发 heal、重启服务、删卷）。触发场景：glusterfs 巡检、存储健康检查、存储池检查、brick stopped、heal 不过、分片/仲裁节点告警、高风险 pvc、PV/PVC 挂载失败、Transport endpoint is not connected、no space left on device、脚本输出看不懂/要一份人能看懂的巡检报告。
---

# GlusterFS 只读巡检

**这个技能只做检查。** 它读、不写；它报告问题、给修复指引，但不修。所有修复步骤都在 `references/remediation/` 里，仅供**人**执行。

它是自包含的：检查项、命令、期望值、判定阈值、修复手册全部在本目录内，不引用任何外部文档。

---

## 0. 先决定用哪种模式（授权闸门）

**默认是 runbook 模式。** 只有同时满足下面两条，才允许连目标：

| 要素 | 要求 | 例子 |
|---|---|---|
| 目标 | 用户**明确点名**了主机或集群 | 「巡检 10.10.0.11-13」「用 `~/.kube/xxx` 查这个集群」 |
| 范围 | 是**只读巡检** | 「巡检」「健康检查」「查一下」 |

缺任意一条 → **runbook 模式**：只输出命令清单和回填表，**一条连接都不建**。

通道**不是**硬闸：L1/L2 默认 ssh，L3 默认 kubeconfig；用户说「只给命令」「别连主机」时降级为 runbook。
（依据 `docs/adr/0001-授权闸门与连接姿态.md`）

硬规则：

- 用户只说「巡检 glusterfs」而没给主机 → runbook。不要去猜 IP、不要翻 `known_hosts`、不要扫网段。
- 只给了 kubeconfig → **只查 k8s 层**（L3）。不顺着 SC 的 `resturl` 去 ssh 那台主机。
- 只给了 ssh 主机 → 查 L1/L2。L3 标 `SKIP(no-kubeconfig)`，**不要**去翻本机其它 kubeconfig 试。
- 绝不"借"凭据跨域：不用 SC 里的 secret 去调 heketi REST（除非用户明确说可以）。
- 通道：先探测环境里 ssh MCP 的**工具是否真的暴露**（配了 MCP 但拿不到工具的情况常见）。可用 → 走 MCP；不可用 → 回退本机 `ssh`，姿势完全相同，并在报告头部记 `channel=local-ssh`。两者都**仅限用户点名的主机**。（`docs/adr/0009-通道探测与降级.md`）

ssh 调用的固定姿势（防止"巡检"变成"改机器"）：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL \
    root@<host> '<只读命令>'
```

- `BatchMode=yes`：绝不弹密码、绝不交互。
- `UserKnownHostsFile=NUL`（Linux 侧用 `/dev/null`）：**不写 known_hosts**，不动本地任何配置。
- `LogLevel=ERROR`：压掉 `Warning: Permanently added '<ip>' ... to the list of known hosts.`。这行会走 stderr，
  一旦并进 stdout 再按行序解析，就会被当成命令输出——**实测因此误报过"砖挂载丢失"**（来源显示成 `Permanently`）。（`docs/adr/0012-人读版报告脚本.md`）
- 不生成、不复制、不修改密钥；不改 `~/.ssh/config`。
- 单条命令超时 ≤ 60s，`heal info` ≤ 120s/卷，整体巡检设总预算（默认 10 分钟）。
  卷数 > 20 时 heal 只查高风险卷，其余标 `SKIP(budget)` 并列出卷名（`docs/adr/0008-巡检预算与卷数上限.md`）。

**从 Windows 传脚本时的坑**（实测）：PowerShell 往管道写字符串会在末尾补一个 `\r`，远端 `bash -s` 会报 `$'\r': command not found` 并以非 0 退出。固定写法：

```bash
# 本机（PowerShell）→ 远端
Get-Content -Raw scripts/gluster-check.sh | ssh <opts> root@<host> "tr -d '\r' | bash -s"
```

脚本本身必须是 LF 换行（不要 CRLF）。

---

## 1. 执行流程

```
1  授权判定         → 全量直连 / 聚焦直连 / runbook（默认）
2  环境探测         → gluster 版本、heketi 版本、SC 的 provisioner
3  L1 集群与卷      → references/checks.md 的 L1-*
4  L2 heketi        → HK-*（需要 heketi 主机访问）
5  L3 Kubernetes    → K8S-*（需要 kubeconfig）
6  判定             → 按 references/thresholds.md 定 P0/P1/P2
7  报告             → 按本文件 §4 的格式输出（默认不落盘）；用户要"能看懂的表"时走 §4.0
8  只读自检          → 对照 references/commands.md 列出本次执行的命令
```

**环境探测不通过怎么办**：版本偏离基线（glusterfs 8.5 / heketi 9.x|10.4）时**仍然照跑**——报告顶部写明「版本不在支持矩阵，结论仅供参考」；只有命令不存在、或关键字段缺失导致判据无法成立时，才对**该单项**标 `SKIP(unsupported: <缺什么>)`。字段缺失不得当默认值使用。（`docs/adr/0005-版本不在矩阵仍执行.md`）

---

## 2. 检查项与阈值

- 检查项全表：`references/checks.md`（每项含命令、期望、判定、证据要求）
- 阈值、严重级、拓扑识别规则：`references/thresholds.md`
- 命令白名单（哪些能跑、哪些禁止、哪些算"重读"）：`references/commands.md`
- 关于本技能自身的决策与用词：`docs/adr/`（ADR）、`docs/glossary.md`（术语表）

**范围**：L1 集群/卷 + L2 heketi + L3 k8s。**不做**：`/etc/fstab` 逐行核对、全量日志扫描（只做定向 grep）、brick 数据 md5 校验、逐卷 `heal info` 全量文件列表、`du/find` 扫盘。

> thin pool 的 `data_percent` **要查**，别当噪音：实测新建 1G 卷只有 1.22%，往里写 200MB 升到 20.78%，删掉文件不回落，在 brick 文件系统上 `fstrim` 后回到 1.37%；另一个 5G 卷（`df` 只有 1%）曾高达 94.03%，`fstrim` 后 0.27%。所以它高有两种成因：真实占用，或"删了没回收"。**池高 + `df` 低 = 陈旧分配**，仍按容量风险定级，处置写"先 fstrim（主机侧，人工）再考虑扩容"。
>
> 容量口径：L1-09（`df` 使用率与 inode）、L1-10（thin pool 分配率）、L1-12（同卷各砖尺寸 / 与 heketi 记录是否一致）。

---

## 3. 只读铁律

1. 只执行 `references/commands.md` 白名单里的命令。白名单外的一律不跑，即使看起来无害。
2. 任何会改变状态的命令**都不执行**——包括"看起来只是触发一下"的：`gluster v heal <vol>`（会启动自愈）、`gtool fstab|flush`、`heketi-cli device resync`、`mount`、`systemctl restart`。
3. 不创建、不删除、不改动远端任何文件（包括 `/tmp` 下的临时文件）。脚本一律走 stdin heredoc，`ssh host 'bash -s' < script.sh`，不落盘。
4. 不修改本地任何文件/配置（不写 `known_hosts`、不改 kubeconfig、不装包）。
5. 默认**不落盘**报告。用户明确要求并给了目录，才写文件。
6. `scripts/gluster-health.py`（人读版）同样只调用白名单命令、不写远端文件；它只是**换了一种展示**，
   不改变 §5 的检查范围（L1/L2 默认，L3 需 `--kubeconfig`，见 `docs/adr/0014-人读版附L3与超时统一.md`），
   也不替代 `##STATE` 契约脚本（`docs/adr/0012-人读版报告脚本.md`）。

遇到写操作请求 → 见 `references/refusals.md`：**拒绝 + 给手册章节 + 不复述可执行命令让人误以为已经做了**。

---

## 4. 报告格式

先给结论表，再给细节，最后给证据与自检。**不落盘时直接在对话里输出。**

### 4.0 人读版输出（用户说"看不懂"时）

`scripts/gluster-health.py` 把同样的检查跑一遍，直接输出中文表（节点 → 卷 → 容量 → heketi → 结论），
不出 XML、不落盘：

```bash
python scripts/gluster-health.py --nodes 10.10.0.11,10.10.0.12,10.10.0.13
python scripts/gluster-health.py --nodes ... --verbose          # 附每块砖的挂载源 + 实际执行的命令
python scripts/gluster-health.py --nodes ... --kubeconfig ~/.kube/config   # 附查 L3（SC/PVC/PV/事件）
```

- `--kubeconfig` 给出时附查 L3；**只打印 current-context 供人工核对，绝不 use-context**。kubectl 只在本机执行。
- `--heketi-user` 可指定 heketi 用户（默认 admin，对应 heketi.json 的 `jwt.<user>.key`）。
- L3 判定含 K8S-01..06 与 HK-05/06（容量对账、clusterid 一致性）；heketi 侧会按需逐卷 `volume info` 取 Size。

- 它是**给人看**的：结论口径与 §4.2 的 `P0/P1/P2` 相同，表格里不带证据行；要四段式时仍按 §4.3 写。
- 阈值与 `references/thresholds.md` 一致；**采集失败一律显示 `n/a` / `?` 并落 `SKIP`，不当成 0**。
- 机器契约仍是 `##STATE` 那套（`gluster-check.sh` 等），两者不互相替代。

### 4.1 头部

```
巡检对象：<集群标识>（<主机> / <kubeconfig context>）
巡检时间：YYYY-MM-DD HH:MM（时区）
巡检模式：全量直连 / 聚焦直连（范围：…）/ runbook（未连接）
版本：glusterfs x.y / heketi x.y / SC provisioner
结论：P0 × n，P1 × n，P2 × n，INFO × n，SKIP × n
声明：本次为单次快照巡检，不含趋势结论；heal 条目、容量变化等需多次比对才有意义。
```

### 4.2 结论表

| 编号 | 检查项 | 结果 | 判定 | 关键证据 |
|---|---|---|---|---|
| L1-05 | brick 在线 | 3/3 Online | PASS | 见 §5.1 |
| L1-07 | heal / split-brain | 1 卷 entries=2 | P1 | `vol_x`: entries=2, split-brain=0 |

判定列只用：`PASS` / `P0` / `P1` / `P2` / `INFO` / `SKIP(原因)`。

- `INFO`：事实为真但无需处置（如空盘待分配、heal 复查已归零），**不计入 P0/P1/P2 计数**。
- **单一根因原则**：同一根因只记一次，取最严重那级（brick 离线只记 L1-05 的 P0，L1-07 不再记 P1）。

### 4.3 问题详情（每个非 PASS 一项）

四段式，缺一不可：

```
【L1-05】vol_xxx 的 brick 10.10.0.13 离线
- 判定依据：<执行的命令> → <输出里的关键行>
- 影响：该卷副本数从 3 降为 2，再坏一台即不可写；heal 无法完成
- 修复路径：references/remediation/03-brick离线恢复.md（人工执行，需维护窗口）
- 风险提示：该流程含 gluster v stop/start，会短时中断该卷读写
```

### 4.4 证据与截断

- 失败项保留原始输出（截到关键 20 行）；通过项只给一行结论 + 数字。
- 单层输出上限 ~200 行；超出写「已截断，完整输出需授权落盘到指定目录」。
- 末尾附「本次执行的命令」清单（用于只读自检）。

---

## 5. 覆盖的检查（摘要）

| 层 | 编号 | 检查 |
|---|---|---|
| L1 | 01–03 | glusterd 存活、版本一致性、peer 状态 |
| L1 | 04–06 | 卷类型/拓扑、brick 在线、卷启动状态 |
| L1 | 07–08 | heal entries 与 split-brain、卷基线选项 |
| L1 | 09–13 | brick 文件系统使用率/inode、thin pool 分配率、brick 挂载是否真的存在（含清单交叉）、同卷各砖尺寸与 heketi 记录是否一致、快照数量 |
| L2 | HK-01–06 | heketi 服务/版本、node 与 device 状态、device 余量、卷对账、容量一致性、clusterid 一致性 |
| L3 | K8S-01–06 | SC 基线、SC Secret、PVC/PV/卷映射、高风险 PVC 三信号、挂载类事件、孤儿与 Pending 资源 |

全部命令、期望值、判定规则见 `references/checks.md`。

---

## 6. 报告之后

- 用户问「怎么修」→ 从 `references/remediation/` 摘对应章节，四段式给出；**仍然不执行**。
- 用户说「你直接帮我修」→ 拒绝，给出：为什么拒绝（只读技能）、需要人工做什么、风险等级、维护窗口建议。详见 `references/refusals.md`。
- 用户要落盘 → 问清目录，写一个 Markdown 文件；文件名 `YYYY-MM-DD-<集群标识>-巡检报告.md`。

---

## 7. 自检（每次巡检结束必做）

1. 把本次实际执行的每条命令，对照 `references/commands.md` 的白名单逐条核对。
2. 任何一条不在白名单 → 立即在报告里标注「越界命令」，并说明是否产生了副作用（理论上不执行，但要如实报告）。
3. 检查是否写了远端/本地文件：应为 0。若 heredoc 里有 `>`、`tee`、`mkdir`、`mktemp`，视为违规。
4. 核对脚本的 `##STATE` 行：任何 `ERR` / `SKIP` 段落必须落成 `SKIP(命令失败|超时|原因)`，**不得判 PASS**；没有 `##STATE` 的检查项视为未采集，按 `SKIP(no-data)` 处理。（`docs/adr/0002-脚本输出契约.md`）
5. 用了人读版脚本时，`--verbose` 会打印本次执行的全部命令，同样要逐条对白名单；它的 `[SKIP]` 行等价于 `SKIP(原因)`。

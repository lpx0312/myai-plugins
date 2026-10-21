# 阈值、严重级与判定规则

## 1. 严重级定义

| 级别 | 含义 | 处理时效 | 典型现象 |
|---|---|---|---|
| **P0** | 数据风险或存储已不可用 | 立即（当天） | brick 离线、卷 Stopped、split-brain、卷/挂载点 100% 满、heketi 侧卷丢失、PVC 后端卷不存在 |
| **P1** | 冗余降级或即将不可用 | 24 小时内 | 无副本卷、peer 断开、heal 积压、设备离线、池余量 <20%、SC Secret 缺失、挂载事件 |
| **P2** | 趋势性/配置偏差 | 计划内 | 使用率 80–89%、inode 80–89%、`allowVolumeExpansion: true`、SC 缺 arbiter 参数、孤儿卷、Released PV |
| **INFO** | 事实为真、无需处置 | 不处理 | 空盘待分配、heal 复查已归零、曾瞬时非 0 |
| **SKIP** | 无法判定 | — | 版本不支持单项、未授权该主机、无 kubeconfig、超时、字段缺失 |

判定列只允许 `PASS / P0 / P1 / P2 / INFO / SKIP(原因)`。**不允许**出现"疑似""大概""可能有问题"这类没有判据的措辞——每条判定必须能指回一条命令输出。
**单一根因原则**：同一根因只记一次，取最严重那级（如 brick 离线只记 L1-05 的 P0，L1-07 不再重复记 P1）。

---

## 2. 数值阈值

| 指标 | P2 | P0 | 说明 |
|---|---|---|---|
| brick 文件系统使用率 | ≥80% | ≥90% | 写满会报 `no space left on device`；写入中途满会 `Transport endpoint is not connected` |
| brick inode 使用率 | ≥80% | ≥90% | 小文件多（日志、缓存、registry）时先炸 inode 而不是容量 |
| thin pool `data_percent` | ≥80% | ≥90% | 池满后写入 `EIO`、brick 转只读。高值需与 `df` 交叉：池高 + `df` 低 = 陈旧分配（删除未回收），见下方说明 |
| thin pool `metadata_percent` | ≥80% | — | 元数据满同样锁死池 |
| 存储池 Free 占比（heketi） | — | <10% → P0；<20% → P1 | `sum(Free)/sum(Size)`，按 cluster 汇总 |
| heal entries（单卷） | — | ≥100 首见即 P0；`0 < n < 100` → P1（复查仍 >0 升 P0，归零降 INFO） | 见 §4 快照规则与 ADR-0004 |
| split-brain 条目 | — | >0 → P0 | 不做自动处置，直接转 08 手册 |
| 快照数量（单卷） | ≥1 → P2 | — | 快照持续占池空间，且阻止卷删除/缩容；heketi 卷默认 `Snapshot: Disabled`，有值说明是人工建的，见 L1-13 |
| brick 挂载点丢失 | — | 必为 P0 | `findmnt` 显示根盘即为丢失 |
| PVC Pending 时长 | — | >10 分钟 → P1 | 需结合 heketi/容量结论 |
| PV 处于 Released | P2 | — | 有 claimRef 但 PVC 已删 |
| brick LV 大小 vs heketi 记录 | P2 | — | 偏差 >10%，见 L1-12 判据 B |
| 同卷 brick 尺寸差 | P2 | — | 最大/最小 >1.1，见 L1-12 判据 A |

**thin pool 高占比的两种成因**（实测）：

| 现象 | 成因 | 处置（人工） |
|---|---|---|
| 池 high + `df` 也 high | 真实占用 | 扩 PV / 扩池 / 清数据 |
| 池 high + `df` low | 删除文件后块未回收（brick 挂载无 `discard`） | 在 **brick 文件系统**上 `fstrim`；走 gluster 客户端挂载点会失败（`Function not implemented`） |

> 不要因为"可能是陈旧分配"就把高占比判为 PASS。池满时写入会真的失败，定级按容量风险走，处置方式再区分。

阈值可按客户基线整体上调/下调，但**必须在报告头部写明"本报告使用的阈值"**，不能悄悄换。

---

## 3. 拓扑识别规则

从 `gluster v info --xml` 的 `distCount / replicaCount / arbiterCount / disperseCount` 判定，**不用文本 `brickCount`**：

| 组合 | 类型 | 含义 |
|---|---|---|
| `dist=1, replica=3, arbiter=0` | Replicate 1×3 | 3 份完整数据，可容忍 1 节点故障（多数派要求 2 在线） |
| `dist=1, replica=2, arbiter=1` | Replicate 2+1（arbiter） | 2 份数据 + 1 份仲裁；**仲裁节点只存元数据，容量占用与数据节点不同步** |
| `dist=1, replica=1, arbiter=0` | Distribute | 无冗余，**不产生 heal**，跳过 L1-07 |
| `dist>1` | 分布式副本（被 add-brick 扩过） | 高风险 PVC 信号 |

推论：

- 只有 **arbiter 卷**才存在"数据节点够、仲裁节点先满"的问题；replica-3 卷上不要套用这个结论。
- 只有 **有副本** 的卷才有 `heal`；对 Distribute 卷跑 `heal info` 是浪费（且可能报错）。
- `dist>1` 说明卷被 `add-brick` 扩过。**gtool 扩容不改 brick 数**，所以 `dist>1` 基本等价于"走过 heketi/PVC 扩容路径"，需要与 K8S-04 的信号②③交叉确认。

---

## 4. 快照规则（本技能不落盘，必须遵守）

单次巡检不构成趋势结论。以下判定必须区分"首见"与"复查"：

| 指标 | 首见 | 复查（≥10 分钟后） | 定级 |
|---|---|---|---|
| heal entries ≥ 100 | 记 P0 | —（无需复查） | P0 |
| heal entries > 0（<100） | 记 P1，标注"待复查" | 仍 >0 | P0 |
| heal entries > 0（<100） | 记 P1 | 归零 | **关闭**，降为 INFO（曾瞬时非 0） |
| 使用率 89% | P2 | 仍 89% 且无增长 | 不升级（无趋势数据） |
| PVC Pending | P1 | 仍 Pending | P1（不因时间自动升 P0，除非有 `FailedMount`） |

报告头部固定声明：

> 本次为单次快照巡检，不含趋势结论；heal 条目、容量变化等需多次比对才有意义。

需要趋势时，用户明确要求落盘后，按 `YYYY-MM-DD-<集群>-巡检报告.md` 保存，下次巡检读取上一份做对比。

---

## 5. 误报控制（已知的坑）

| 场景 | 现象 | 处理 |
|---|---|---|
| 业务繁忙 | `heal info` 瞬时 entries 非 0（<100） | 按 §4 复查，不直接 P0；**≥100 例外，首见即 P0** |
| thin pool 高占比 | `data_percent` 94% 但 `df` 只有 1% | **不是误报**：是删除未回收（已实测 `fstrim` 后降到 0.27%）。按 P0/P2 报容量风险，处置写"先 fstrim 再考虑扩容" |
| thin pool 判读 | 把 `data_percent` 当"文件系统使用率"看 | 它是池的**块分配率**，与 `df` 不是一回事；两者必须一起看 |
| 多网卡 / 多主机名 | peer 的 `Other names` 与 hostname 不同 | 按 `peerid`/`uuid` 去重，不要按 IP 数节点 |
| 同一主机多个 brick | `df` 一次传入多个目录只输出一次挂载点 | 按挂载点聚合，别按卷计数 |
| `gluster v status` 文本折行 | brick 路径被 80 列折断，grep 不到 | 解析统一用 `--xml` |
| SHD 行 | `Self-heal Daemon` 的 `port=N/A`、`path` 是主机名 | 与 brick 分开判定，不要当 brick 离线 |
| kubectl 列位变化 | 旧脚本按 `awk '{print $3}'` 取 PV 会错位 | 只解析 `-o json`，不解析表格 |
| heketi volume 与 gluster 名字 | 名字都是 `vol_<32hex>`，但 heketi 的 Id 不带前缀 | 比较时统一去掉 `vol_` 前缀再比 |

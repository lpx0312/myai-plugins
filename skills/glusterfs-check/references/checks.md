# 检查项全表（L1 / L2 / L3）

约定：
- **执行域**：`gls` = 任一 glusterfs 节点；`each-gls` = 每台 brick 所在主机（需逐台授权）；`heketi` = 装了 heketi 的主机（通常 gls01）；`k8s` = 有 kubeconfig 的控制面。
- **证据**：报告里必须能指回具体输出行，不能只写"检查通过"。
- 所有命令都在 `references/commands.md` 白名单内；`--xml` 用于需要解析的地方（文本输出会按 80 列硬折行，`gluster v status` 尤其会断 brick 路径）。
- 单卷 `heal info` 可能慢，必须带超时；卷多时先做 L1-04，把 `Distribute`（无副本）类型的卷跳过 heal 检查。
- **输出契约**：脚本每段以 `##STATE <ID> OK|ERR|SKIP` 收尾。`ERR` / `SKIP` 的段落只能判 `SKIP(命令失败|超时|原因)`，**不得判 PASS**；没有 `##STATE` 的检查项视为未采集（`docs/adr/0002-脚本输出契约.md`）。
- **预算与抽样**：全量巡检总预算 10 分钟。`heal info` 按卷 120s，卷数超过 `HEAL_MAX_VOLUMES`（默认 20）时只查高风险卷（有快照 / `distCount>1` / 有非 Connected 砖），其余标 `SKIP(budget)` 并在报告列出卷名；也可用 `HEAL_VOLS="vol_a vol_b"` 指定重点卷（`docs/adr/0008-巡检预算与卷数上限.md`）。

---

## L1 · 集群与卷

### L1-01 glusterd 服务

| 项 | 内容 |
|---|---|
| 执行域 | each-gls（至少 gls 一台；每台单独判定） |
| 命令 | `systemctl is-active glusterd` |
| 期望 | `active` |
| 判定 | 非 `active` → **P0**（该节点上的 brick 全部不可用） |
| 证据 | 每台主机的返回值 |

### L1-02 版本一致性

| 项 | 内容 |
|---|---|
| 执行域 | each-gls |
| 命令 | `gluster --version \| head -1` |
| 期望 | 基线 `glusterfs 8.5`（或用户声明的基线），且各节点一致 |
| 判定 | 跨节点版本不一致 → **P1**；与基线不符 → **不整体 SKIP**：照常执行，报告顶部声明「版本不在支持矩阵，结论仅供参考」；仅当命令不存在或关键字段缺失时对该单项标 `SKIP(unsupported: <缺什么>)`（ADR-0005） |
| 证据 | 每台主机的版本行 |

> 只授权了一台主机时：只判定该主机，其余标 `SKIP(host-not-authorized)`，不要推断"应该都一样"。

### L1-03 peer 状态

| 项 | 内容 |
|---|---|
| 执行域 | gls |
| 命令 | `gluster peer status` |
| 期望 | `Number of Peers: N-1`；每条 `State: Peer in Cluster (Connected)` |
| 判定 | 出现 `Disconnected` / `Peer Rejected` / peer 数少于节点数 → **P0** |
| 证据 | peer 条数与每条 State；peer 的 `Other names`（用于识别双网卡/多主机名） |

### L1-04 卷类型与拓扑

| 项 | 内容 |
|---|---|
| 执行域 | gls（一次拿全部卷） |
| 命令 | `gluster v info --xml` |
| 关键字段 | `name` / `statusStr` / `brickCount` / `distCount` / `replicaCount` / `arbiterCount` / `disperseCount` / `typeStr` / `bricks/brick/isArbiter` |
| 判定 | ① `replicaCount=1` 且 `arbiterCount=0` 且 `disperseCount=0` → **P1** 无冗余（Distribute）<br>② `distCount > 1` → **P1** 卷被 add-brick 扩过（高风险 PVC 信号，交叉 K8S-04）<br>③ `brickCount ≠ distCount × (replicaCount + arbiterCount)`（非 disperse 卷）→ **P1** 拓扑异常<br>④ `arbiterCount > 0` → 记为 arbiter 卷（影响容量判定与修复手册选择） |
| 证据 | 每个卷一行：`vol / typeStr / distCount x (replica+arbiter) / brickCount / statusStr` |

> 实测：`Number of Bricks: 1 x 3 = 3` 在 XML 里是 `distCount=1, replicaCount=3`；arbiter 卷是 `replicaCount=2, arbiterCount=1`。**不要用文本里的 `brickCount==3` 判断"正常"**——replica-3 与 2+1 arbiter 都是 3。

### L1-05 brick 在线状态

| 项 | 内容 |
|---|---|
| 执行域 | gls（一次拿全部卷） |
| 命令 | `gluster v status --xml` |
| 解析 | `node` 里 `hostname != "Self-heal Daemon"` 的是 brick；`status=1` 在线、`0` 离线；`port=N/A` 是 SHD，单独判定 |
| 判定 | 任一 brick `status=0` → **P0**（brick stopped，卷降级）<br>SHD `status=0` → **P1**（自愈守护异常） |
| 证据 | 离线 brick 的 `hostname:path`、卷名、`port`；在线的给 `在线数/总数` |

### L1-06 卷启动状态

| 项 | 内容 |
|---|---|
| 执行域 | gls（复用 L1-04 的 XML，不重复调用） |
| 字段 | `statusStr`（`Started` / `Stopped`） |
| 判定 | `Stopped` → **P0**（不可读写） |
| 补充 | 卷不存在但 PV 存在 → 见 HK-04（heketi 有、gluster 无） |

### L1-07 heal 与 split-brain

| 项 | 内容 |
|---|---|
| 执行域 | gls（逐卷；跳过 Distribute-only 卷） |
| 命令 | `gluster v heal <vol> info summary --xml`（超时 120s/卷） |
| 字段 | `brick/status`、`totalNumberOfEntries`、`numberOfEntriesInHealPending`、`numberOfEntriesInSplitBrain`、`numberOfEntriesPossiblyHealing` |
| 判定 | `split-brain > 0` → **P0**（必须人工介入，见 08 手册）<br>`totalEntries ≥ 100` **首见即 P0**（百条积压已非瞬时抖动，不必等复查）<br>`0 < totalEntries < 100` 首见 → **P1**（标注"待复查"）；≥10 分钟复查仍 >0 → **P0**；复查归零 → **关闭**并降为 `INFO`（曾瞬时非 0）<br>brick `status != Connected` → 只写"关联 L1-05"，**不单独计入 P1 计数**（单一根因原则，ADR-0004） |
| 证据 | 每卷：`entries / split-brain / 待 heal 的 brick 数`；非 0 的卷给 brick 名 |
| 坑 | 业务繁忙时 entries 瞬时非 0 是正常的。首次非 0 只判 P1，并要求"10 分钟后复查一次再定性"，复查仍非 0 才升 P0 |

### L1-08 卷基线选项

| 项 | 内容 |
|---|---|
| 执行域 | gls（复用 L1-04 XML 的 `<options>`，不额外调用） |
| 期望 | `nfs.disable=on`；`user.heketi.id` 存在（heketi 管理的卷）；`transport.address-family=inet`（与部署一致时） |
| 判定 | `nfs.disable` 非 on → **P2**；缺 `user.heketi.id` → **P1**（heketi 可能无法管理该卷，扩容/删除会失败）<br>`auth.allow` 被设置 → **P2** 仅提示（可能是有意的访问控制，需人工确认） |
| 证据 | 实际键值对 |

### L1-09 brick 文件系统使用率 / inode

| 项 | 内容 |
|---|---|
| 执行域 | each-gls |
| 命令 | `df -P -B1 <brick 挂载目录...>`、`df -P -i <brick 挂载目录...>` |
| 目录怎么来 | 由 L1-04 的 brick 路径推出：brick 路径 = `<mount>/brick`，挂载目录取上一级（即 `dirname`） |
| 判定 | 使用率 ≥80% → **P2**；≥90% → **P0**（写满会导致 `no space left on device` / `Transport endpoint is not connected`）<br>inode ≥80% → **P2**；≥90% → **P0** |
| 证据 | 每个 brick 挂载点的 `已用/总量/百分比` 与 inode 百分比 |
| 注意 | 一次 `df` 传入多个目录时，同一挂载点只输出一次；按挂载点聚合，不要按卷重复计数 |

### L1-10 thin pool 分配率（data_percent）

| 项 | 内容 |
|---|---|
| 执行域 | each-gls |
| 命令 | `lvs --noheadings -o lv_name,pool_lv,lv_size,data_percent,metadata_percent` |
| 映射 | **必须用 `pool_lv` 列**把 brick 映射到池，不要拿 `tp_<id>` 与 `brick_<id>` 的名字后缀配对（见下方实测） |
| 判定 | 任一 thin pool 的 `data_percent` ≥80% → **P2**；≥90% → **P0**（池满后写入会 `EIO` / brick 转只读）<br>同时 `metadata_percent` ≥80% → **P2**（元数据满同样会锁死池） |
| 交叉判定 | 若池 ≥80% 但对应 brick 的 `df` 使用率很低（<50%）→ 标注「疑似陈旧分配」：文件已删但块未回收（brick 挂载无 `discard`）。**仍按容量风险定级**，因为池满会真的写不进去 |
| 证据 | 池名、`data_percent`、`metadata_percent`、对应 brick、该 brick 的 `df` |

实测数据（本环境，供判读参考）：

| 场景 | pool `data_percent` |
|---|---|
| 新建 1G 卷（只有 mkfs 元数据） | **1.22%** |
| 往卷里写 200MB | **20.78%** |
| 删除该 200MB 文件（不 fstrim） | **20.78%**（不回落） |
| 在 brick 文件系统上 `fstrim` 后 | **1.37%**（回落） |
| 一个 5G 卷（`df` 仅 1%）运行一段时间后 | **94.03%**，`fstrim` 后 **0.27%** |

> 结论：`data_percent` **是有效指标**，反映 thin pool 真实分配量。高值有两种成因：真实占用，或"删了文件没回收"。后者用 `df` 低 + 池高来区分，处置靠主机侧 `fstrim`（**写操作，人工执行**，见 `05-gtool扩容PVC.md`）。
>
> ⚠️ `fstrim` 走 gluster 客户端挂载点会失败（`FITRIM ioctl failed: Function not implemented`，已实测），必须打在 **brick 文件系统**上。

> **不要按名字后缀配对 `tp_*` 与 `brick_*`**：同一集群里连着建了 4 次 1G 测试卷，池名有时等于砖名、有时是另一串随机 id，**同一台主机前后结果也会变**：
>
> | 次 | 42 | 43 | 44 |
> |---|---|---|---|
> | 原始卷 | 同名 | 同名 | 不同名 |
> | 测试1 | 同名 | 同名 | 不同名 |
> | 测试2 | 同名 | 同名 | 不同名 |
> | 测试3（`device resync` 之后） | 同名 | **不同名** | **同名** |
>
> heketi 自己的命令就是 `--thin vg_xxx/tp_<串A> --name brick_<串B>`，两串都是它生成的，规律未确认。**不能据此判断某台主机异常**，也不要做任何"某节点有问题"的推断。结论只有一个：**以 `lvs` 的 `pool_lv` 列为准，永远不靠名字猜**。

### L1-11 brick 挂载点校验

| 项 | 内容 |
|---|---|
| 执行域 | each-gls |
| 命令 | `findmnt -n -T <brick 挂载目录> -o TARGET,SOURCE,FSTYPE` |
| 期望 | `SOURCE` 是该 brick 的 LV（`/dev/mapper/<vg>-brick_<id>` 或 `/dev/<vg>/brick_<id>`），`FSTYPE=xfs` |
| 判定 | `SOURCE` 不是对应 brick LV（例如显示根盘 `/dev/sda3`、`/dev/vda1`）→ **P0**：**brick 挂载丢失**，目录指向了系统盘（此时数据还在 LV 里，未丢，但 brick 不可用）<br>`findmnt` 本身失败（目录不存在 / 未挂载，脚本输出 `ERR mount-check-failed`）→ 同样 **P0**，按挂载丢失处理，不要当"没有砖"放行 |
| 判据 C（清单交叉） | 以 L1-04 的 brick 路径为**期望清单**，逐主机与本机 `##BRICKLIST` 求差集：<br>· **本机缺砖**（清单有、本机没有）→ **P0**：等同该砖不可用，按挂载丢失处理<br>· **本机多砖**（本机有、清单没有）→ **P2**：孤儿砖，heketi 已无记录，仍占池空间，需人工确认是否回收 |
| 证据 | 目录、实际 SOURCE、期望的 LV 名；清单差集的两侧路径 |

### L1-12 容量一致性（同卷各砖 + 与 heketi 记录）

| 项 | 内容 |
|---|---|
| 执行域 | 复用 L1-09/10 的每砖 `lv_size`，按卷聚合（卷↔砖关系来自 L1-04）；有 L2 时再比 heketi |
| 判据 A | 同卷内 `max(lv_size) / min(lv_size) > 1.1` → **P2**：replica 卷可用空间按**最小副本**算；不均会造成容量浪费、写入提前失败，扩容易只扩一部分 |
| 判据 B | 每砖 `lv_size` 与 heketi 记录的 `Size (GiB)` 差 >10% → **P2**：<br>· LV 大于记录 → 手工扩过 LV 但 DB 未同步<br>· LV 小于记录 → 容量虚标，写满早于预期<br>注：`heketi-cli device resync` **不会**改砖的 `Size` 记录（实测 resync 后仍 5 GiB、LV 11.00g），所以 resync 之后本判据仍会报，属预期 |
| 证据 | 每卷各砖 `lv_size` + 最大/最小比值；有 heketi 时附 `heketi Size` |

### L1-13 快照数量

| 项 | 内容 |
|---|---|
| 执行域 | gls（复用 L1-04 XML 的 `<snapshotCount>`，脚本按卷逐条输出 `snapshotCount=`） |
| 期望 | `snapshotCount = 0`（heketi 管理的卷默认 `Snapshot: Disabled`） |
| 判定 | `snapshotCount > 0` → **P2**：快照会持续占用 thin pool 空间，且**阻止卷删除/缩容**；heketi 侧显示 `Snapshot: Disabled` 时说明是人工用 gluster 命令建的，需人工确认留存理由<br>若该卷同时 `data_percent ≥ 80%` 或 `df ≥ 80%` → 容量项照常按 L1-09/L1-10 定级（**不重复计**，遵守单一根因原则） |
| 证据 | 卷名 + `snapshotCount`；有快照时附 `gluster v info <vol>` 里 `Snapshot Count` 行 |

---

## L2 · heketi

凭证来源：`/etc/heketi/heketi.json`（明文，读该文件属于只读）。**报告里绝不打印 secret**，只写「已从 heketi.json 读取」。

```bash
HK="heketi-cli --user <user> --secret <secret>"
```

### HK-01 heketi 服务与版本

| 项 | 内容 |
|---|---|
| 执行域 | heketi |
| 命令 | `systemctl is-active heketi`；`heketi-cli --version`；`$HK cluster list` |
| 期望 | `active`；版本为 9.0 / 10.4；`cluster list` 正常返回 cluster id |
| 判定 | 服务非 active → **P0**（无法新建/删除 PVC）<br>版本不在基线 → 照常执行，报告顶部声明「版本不在支持矩阵，结论仅供参考」（ADR-0005）<br>`cluster list` 报错（DB 锁/损坏）→ **P0** |

### HK-02 节点与设备状态

| 项 | 内容 |
|---|---|
| 执行域 | heketi |
| 命令 | `$HK topology info` |
| 解析 | `Node Id` / `State: online\|offline`；`Devices:` 的 `Id` / `State` / `Size (GiB)` / `Used` / `Free`；`Tags: arbiter:disabled` |
| 判定 | node offline → **P0**（该节点 brick 不可调度）<br>device offline → **P1**（容量减少；heketi 不会再往上放 brick）<br>device `State: online` 但 `Bricks:` 为空且 Used=0 → **INFO**（空盘待分配，属正常状态，不计级；只有"设备长期空置 + 池余量告急"时才由人工确认是否纳管，巡检不判 P2） |
| 证据 | 节点数、在线节点数、设备数、离线设备清单 |

### HK-03 存储池余量

| 项 | 内容 |
|---|---|
| 执行域 | heketi（复用 HK-02 输出） |
| 计算 | `sum(Free) / sum(Size)`（同一 cluster 内） |
| 判定 | <20% → **P1**；<10% → **P0**（即将无法新建/扩容 PVC） |
| 证据 | 每个 device 的 Free，以及汇总百分比 |

### HK-04 卷对账（heketi ↔ gluster）

| 项 | 内容 |
|---|---|
| 执行域 | heketi + gls |
| 命令 | `$HK volume list`；`gluster v list` |
| 解析 | heketi 行格式 `Id:<id> Cluster:<cid> Name:vol_<id>` |
| 判定 | **heketi 有、gluster 无** → **P0**（对应 PVC 后端已丢，业务读写会失败）<br>**gluster 有、heketi 无** → **P2**（孤儿卷，白占空间，需人工确认是否可回收）<br>名字不符合 `vol_<id>` 规则 → **P1**（非 heketi 创建/被改名） |
| 证据 | 两个集合及差集大小 |

### HK-05 卷容量一致性（需 L3）

| 项 | 内容 |
|---|---|
| 执行域 | heketi + k8s |
| 命令 | `$HK volume info <id>`（取 `Size:`，单位 GiB）；`kubectl get pv -o json` |
| 判定 | `heketi Size` ≠ `PV .spec.capacity.storage`（换算成 GiB 比较）→ **P1**；PV 容量大于实际卷 → **P0**（业务以为有空间，实际写满） |
| 证据 | 卷名、heketi size、PV capacity |

### HK-06 clusterid 一致性（需 L3）

| 项 | 内容 |
|---|---|
| 执行域 | heketi + k8s |
| 命令 | `$HK cluster list`（取 id）；`kubectl get sc -o json`（`parameters.clusterid`） |
| 判定 | 不一致 → **P0**（新 PVC 建不出来，或建到错误的集群） |
| 证据 | SC 名、两个 id |

---

## L3 · Kubernetes

统一前置：`kubectl config current-context` 必须就是用户点名的集群；上下文不对 → 停止并询问，**不要** `use-context` 或换 config。

### K8S-01 StorageClass 基线

| 项 | 内容 |
|---|---|
| 命令 | `kubectl get sc -o json`，筛 `provisioner == kubernetes.io/glusterfs` |
| 检查 | `parameters.resturl`、`parameters.clusterid` 非空；`secretName`/`secretNamespace` 存在；`reclaimPolicy`；`volumeBindingMode`；`allowVolumeExpansion`；`volumeoptions` 是否含 `user.heketi.arbiter true` 与 `user.heketi.average-file-size` |
| 判定 | `allowVolumeExpansion: true` → **P2**（门没关，仍可能产生高风险盘）<br>缺 `user.heketi.arbiter true` → **P2**（2+1 拓扑下数据/仲裁容量会不等）<br>缺 `user.heketi.average-file-size` → **P2**<br>`resturl`/`clusterid` 为空 → **P0**（无法创建 PVC） |
| 证据 | 每个 SC 一行参数摘要 |

### K8S-02 SC 引用的 Secret

| 项 | 内容 |
|---|---|
| 命令 | `kubectl -n <secretNamespace> get secret <secretName> -o jsonpath='{.type}'` |
| 期望 | `kubernetes.io/glusterfs` |
| 判定 | Secret 不存在 → **P1**（新建 PVC 失败）；类型不对 → **P2** |
| 证据 | ns/name/type；**不要**输出 secret 内容 |

### K8S-03 PVC ↔ PV ↔ 卷 映射

| 项 | 内容 |
|---|---|
| 命令 | `kubectl get pvc -A -o json`；`kubectl get pv -o json` |
| 解析 | PV 的 `spec.glusterfs.path` 即卷名（`vol_...`）；`spec.claimRef` 反查 ns/pvc |
| 判定 | PVC `Pending` >10 分钟 → **P1**（provisioner/heketi 或容量问题）<br>PV `Released` 且有 `claimRef` 指向已不存在的 PVC → **P2**（残留）<br>PV 有 `glusterfs.path` 但卷在 L1-04 中不存在 → **P0**（悬空 PV，Pod 挂载会失败） |
| 证据 | 映射表：`namespace / pvc / pv / vol`，只列前 N 条 + 总数 |

### K8S-04 高风险 PVC（三信号）

| 信号 | 判据 | 判定 |
|---|---|---|
| ① 拓扑被扩 | L1-04 的 `distCount > 1` | 单独 → **P1** |
| ② 容量对不上 | `heketi Size` ≠ `PV capacity`（HK-05） | 单独 → **P1**；配合 ① → **P0** |
| ③ 门未关 | SC `allowVolumeExpansion: true` | 单独 → **P2** |

补充判据（有据可查时）：`PVC.spec.resources.requests.storage` 大于 `PV.spec.capacity.storage` → **P1**（PVC 永远无法满足）。

> 只报"疑似"，给人工核对清单（卷名、PV、heketi size、PV capacity、拓扑），**不要**下"数据已损坏"的结论——只有出现 `file transport not connected` 才是数据丢失信号（见 01 手册）。

### K8S-05 挂载类事件

| 项 | 内容 |
|---|---|
| 命令 | `kubectl get events -A -o json`（或 `--field-selector type=Warning`） |
| 过滤 | reason ∈ `FailedMount` / `FailedAttachVolume`；message 含 `Transport endpoint is not connected` / `no space left on device` / `glusterfs` |
| 时间窗 | 默认最近 24h（按 `lastTimestamp`） |
| 判定 | 存在 → **P1**；同一 PVC 反复出现且当前 Pod 未 Running → **P0** |
| 证据 | ns / 涉及 PVC / reason / message 摘要（去重计数，不逐条贴） |

### K8S-06 孤儿与卡住资源

| 项 | 内容 |
|---|---|
| 命令 | 复用 K8S-03 的 JSON；`kubectl get pv -o json` 看 `metadata.deletionTimestamp` |
| 判定 | PV 有 `deletionTimestamp` 但长时间未消失（>10 分钟）→ **P2**（finalizer 卡住，常见于后端卷已异常）<br>PVC `Pending` 且无对应 PV → 已并入 K8S-03 |
| 证据 | 清单 + 存在时长 |

---

## 交叉引用

| 现象 | 修复手册 |
|---|---|
| 高风险 PVC / 扩容后权限异常 | `references/remediation/01-高风险PVC处置.md` |
| 需要换一个新的 PVC | `references/remediation/02-替换PVC.md` |
| brick 离线 / 大面积 brick stopped | `references/remediation/03-brick离线恢复.md` |
| 单卷需要 stop/start | `references/remediation/04-单卷停启.md` |
| 容量不足要扩 PVC | `references/remediation/05-gtool扩容PVC.md` |
| 仲裁节点空间不足 | `references/remediation/06-单独扩容仲裁节点.md` |
| SC 参数不对 / 要关扩容门 | `references/remediation/07-SC基线修正.md` |
| split-brain / 需要深挖日志 | `references/remediation/08-日志定位与深度排查.md` |

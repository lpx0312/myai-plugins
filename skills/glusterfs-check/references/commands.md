# 只读命令白名单

**规则：白名单外一律不执行。** 匹配按「可执行文件 + 子命令」精确匹配，不接受通配；管道后的 `head/grep/awk/sed/sort/uniq/cut` 只用于处理**本地已拿到的输出**，不算额外命令。

每条命令都标了**负载等级**：`轻` = 可随意跑；`中` = 单卷级、带超时；`重` = 默认禁止（见 §4）。

---

## 1. 连接

| 场景 | 写法 | 负载 |
|---|---|---|
| ssh（本机 fallback） | `ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@<host> '<白名单内命令>'` | 轻 |
| ssh（MCP） | 调用环境里可用的 ssh MCP 的"执行命令"能力，参数同上 | 轻 |
| 执行脚本（不落盘） | `ssh ... root@<host> 'bash -s' < scripts/xxx.sh`；Windows 端用 PowerShell 管道时必须写成 `... "tr -d '\r' \| bash -s"` | 轻 |

脚本统一 `export LC_ALL=C` 并按 `docs/adr/0002-脚本输出契约.md` 输出三态：
`##<ID> CMD:` → 原始输出 → `##STATE <ID> OK|ERR|SKIP`。`ERR`/`SKIP` 不得判 PASS。

Linux 侧 `UserKnownHostsFile` 用 `/dev/null`；Windows 侧用 `NUL`。目的都是**不写 known_hosts**。

`LogLevel=ERROR` 不是可选项：首次连一台新机器时 ssh 会往 stderr 打
`Warning: Permanently added '<ip>' (ECDSA) to the list of known hosts.`。这行一旦并进 stdout，
任何**按行序**解析的输出都会错位——实测把 findmnt 的第 1 行顶掉，误报成"砖挂载丢失"
（来源被读成 `Permanently`、类型被读成 `added`）。

### 1.1 通用只读工具（允许）

这些不改变任何状态，用于格式化/过滤输出：`echo`、`hostname`、`date`、`whoami`、`head`、`tail`、`grep`、`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`、`wc`、`ls`（只列名）、`timeout`、`findmnt`（只读选项）、`df`、`free`、`cat`（只读单个文本文件）。

需要把多行结果和"是哪块砖"绑定时，允许 `echo -n "##<标记> "` 打行首标记（只往 stdout 写，不写文件）；
解析端必须按标记里的目录名匹配，**不能按行序**。`scripts/gluster-health.py` 的 `##F` 就是这么用的。

**禁止的"格式化工具"用法**：`sed -i`（原地改文件）、`awk` 里调 `system()`、`find -delete`、`xargs rm`。

> 脚本里循环调用 ssh 时必须加 `-n`（`ssh -n ...`），否则 ssh 会吃掉脚本自己的 stdin，后面的命令静默不执行——实测踩过：循环里第一次 ssh 把剩余脚本吞了，导致清理步骤没跑。

---

## 2. GlusterFS（L1）

| 命令 | 用途 | 负载 |
|---|---|---|
| `gluster --version` | L1-02 | 轻 |
| `gluster peer status` | L1-03 | 轻 |
| `gluster pool list` | L1-03 辅助（看 localhost 与 peer 状态） | 轻 |
| `gluster v list` | HK-04 对账 | 轻 |
| `gluster v info --xml` | L1-04 / L1-06 / L1-08（一次拿全部） | 轻 |
| `gluster v info <vol> --xml` | 聚焦模式 | 轻 |
| `gluster v status --xml` | L1-05（一次拿全部卷） | 中 |
| `gluster v status <vol> --xml` | 聚焦模式 | 轻 |
| `gluster v heal <vol> info summary --xml` | L1-07 | 中 |
| `gluster v get <vol> all` | 仅当 XML 里 options 不全时兜底 | 中 |

> 禁用 `gluster v heal <vol> info`（会全量列出文件，大卷上极慢）——除非用户明确要求看具体文件清单，且限定单卷。

## 3. 主机只读（L1-09 / L1-10 / L1-11）

| 命令 | 用途 | 负载 |
|---|---|---|
| `df -P -B1 <dirs>` | L1-09 容量（按 1 字节单位，便于换百分比） | 轻 |
| `df -P -i <dirs>` | L1-09 inode | 轻 |
| `findmnt -n -T <dir> -o TARGET,SOURCE,FSTYPE` | L1-11 挂载点校验 | 轻 |
| `lvs --noheadings -o lv_name,vg_name,lv_size` | L1-10 尺寸关系 | 轻 |
| `vgs --noheadings -o vg_name,vg_size,vg_free` | 仅作参考（不进判定） | 轻 |
| `systemctl is-active <glusterd\|heketi\|glusterfs-fstab-monitor>` | L1-01 / HK-01 | 轻 |
| `rpm -q glusterfs-server` | 版本佐证（可选） | 轻 |
| `ls -d /var/lib/heketi/mounts/vg_*/brick_*/brick` | 枚举本机 brick（只列名，不读内容） | 轻 |
| `cat /etc/heketi/heketi.json` | 取 heketi 用户/口令/端口；**输出里的 secret 不得进报告** | 轻 |
| `journalctl -u glusterd --since "-24h" --no-pager \| grep -iE 'error\|failed'` | 定向查错（见 §5 限制） | 中 |

## 4. heketi（L2）

`HK="heketi-cli --user <u> --secret <s>"`

| 命令 | 用途 | 负载 |
|---|---|---|
| `heketi-cli --version` | HK-01 | 轻 |
| `$HK cluster list` | HK-01 / HK-06 | 轻 |
| `$HK topology info` | HK-02 / HK-03（一次拿全） | 中 |
| `$HK volume list` | HK-04 | 轻 |
| `$HK volume info <id>` | HK-05（`Size` 字段） | 轻 |
| `$HK device info <id>` | 仅在 topology 信息不足时逐个补 | 中 |

## 5. Kubernetes（L3）

| 命令 | 用途 | 负载 |
|---|---|---|
| `kubectl config current-context` | 前置校验（必须是用户点名的集群） | 轻 |
| `kubectl get sc -o json` | K8S-01 | 轻 |
| `kubectl -n <ns> get secret <name> -o jsonpath='{.type}'` | K8S-02（**只取 type**） | 轻 |
| `kubectl get pvc -A -o json` | K8S-03 | 中 |
| `kubectl get pv -o json` | K8S-03 / K8S-06 | 中 |
| `kubectl get events -A -o json` | K8S-05（可加 `--field-selector type=Warning`） | 中 |
| `kubectl get pods -A -o json` | 仅当需要确认"挂载失败是否影响业务" | 中 |
| `kubectl describe pvc -n <ns> <name>` | 聚焦模式排障 | 轻 |

> **`-o` 形态只认 `json`（`-o jsonpath` 仅限 K8S-02 取 secret type）**。`-o yaml`、`-o wide`、
> `-o custom-columns` 都**不在白名单**——脚本为图方便用表格输出属于越界（ADR-0003）。
> 需要列式视图时，由分析阶段在本地对 JSON 做投影。

---

## 6. 禁止清单（一律不执行，无例外）

### 6.1 卷/集群

| 禁止 | 为什么 | 只读替代 |
|---|---|---|
| `gluster v start / stop / restart` | 中断业务读写 | `gluster v status <vol> --xml` |
| `gluster v create / delete` | 建/删卷 | — |
| `gluster v add-brick / remove-brick` | 改拓扑、触发 rebalance | `gluster v info --xml` 看 `distCount` |
| `gluster v heal <vol> [full]` | **触发自愈**，产生 IO 与写入 | `gluster v heal <vol> info summary --xml` |
| `gluster v set / reset` | 改卷参数 | `gluster v get <vol> all` |
| `gluster peer probe / detach` | 改集群成员 | `gluster peer status` |
| `gluster v replace-brick` | 换砖 | — |
| `systemctl start/stop/restart glusterd` | 断服务 | `systemctl is-active` |

### 6.2 heketi / gtool

| 禁止 | 为什么 | 只读替代 |
|---|---|---|
| `heketi-cli volume create/delete/expand` | 改后端卷 | `volume list / info` |
| `heketi-cli device add/delete/disable/enable/resync` | 改设备状态/DB | `topology info` |
| `heketi-cli node add/delete` | 改集群 | `topology info` |
| `heketi-cli cluster create/delete` | 改集群 | `cluster list` |
| `gtool ex/expand` | 扩容（写 LVM + 改 DB） | `lvs` |
| `gtool fstab` | 改写 `/etc/fstab` 与 heketi DB | — |
| `gtool flush` | 主机状态回写 heketi DB | — |

### 6.3 Kubernetes

| 禁止 | 为什么 | 只读替代 |
|---|---|---|
| `kubectl apply/create/delete/edit/patch/replace/scale/rollout` | 改资源 | `get` / `describe` |
| `kubectl exec` / `kubectl cp` | 进容器 = 可能写数据 | `logs --tail=100` |
| `kubectl debug` / `port-forward` / `proxy` | 改变运行态 | — |
| `kubectl cordon/uncordon/drain/taint` | 改调度 | `get nodes` |

### 6.4 主机 / LVM / 文件

| 禁止 | 为什么 |
|---|---|
| `mount` / `umount` / `mount -a` | 改变挂载状态 |
| `fstrim` / `discard` 类操作 | 会释放 thin pool 块（数据安全，但属于变更；巡检只报告，处置由人工做） |
| `lvcreate/lvremove/lvextend/lvresize/lvchange`、`vgextend/vgreduce` | 改 LVM |
| `mkfs.*` / `wipefs` / `dd` | 毁数据 |
| `rm/mv/cp`（远端文件） | 改文件 |
| `tee` / `>` / `>>` / `mkdir` / `mktemp`（远端） | 落盘 |
| `rsync` / `scp`（往远端） | 传输/覆盖 |
| `ssh-copy-id` / `ssh-keygen` | 改凭据 |
| `pkill` / `kill` | 杀进程 |
| `yum/dnf install/remove` | 装包 |
| `chmod/chown`（远端） | 改权限（高风险 PVC 修复需要，但那是人工执行） |

---

## 7. 负载与超时

| 命令 | 超时 | 备注 |
|---|---|---|
| 单条轻命令 | 15s | 版本、peer、list、get |
| `gluster v status --xml` | 60s | 卷多时可能慢 |
| `gluster v heal <vol> info summary --xml` | 120s/卷 | 超过就记 `SKIP(timeout)` 并写进报告，**不重试轰炸** |
| `heketi topology info` | 60s | DB 大时慢 |
| `kubectl get pvc/pv/events -o json` | 60s | 超时可退化为 `--field-selector` 或单 ns |
| 单次巡检总预算 | 10 分钟 | 超时则输出已完成部分 + `SKIP(budget)` |

---

## 8. 自检方法

巡检结束前，把本次执行过的命令（含 ssh 里的内层命令）逐条与本文件比对：

1. 命中的在白名单 → ✅
2. 未命中 → 标 **越界命令**，在报告里单列一节，写清是否执行、是否可回滚
3. 特别检查远端是否出现 `>`、`tee`、`mkdir`、`mktemp`、`rm` —— 出现即违规，必须报告

> 自检结果必须出现在报告的"本次执行命令"附录里，不能只写"已自检通过"。

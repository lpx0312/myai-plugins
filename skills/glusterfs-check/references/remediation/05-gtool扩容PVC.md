# 05 · 用 gtool 扩容 PVC

> **本文档仅供人工执行。本技能不执行任何扩容动作。**
> 风险等级：**中**（后端 LVM 操作，在线生效）；是否需要停机：不需要；是否可回滚：**不可缩小**。

## 适用

PVC 容量耗尽，典型报错：

- `no space left on device`
- `Transport endpoint is not connected`（写入中途写满）
- 容器内 `df` 已接近 100%

## 前置条件

1. **gtool 已安装在 heketi 主机上**（gtool 需要读写本机 heketi 配置与 LVM）。
2. **目标卷不是"高风险盘"**：曾用 `kubectl edit pvc` 扩容过的卷，gtool 会主动报错退出。先用巡检的 K8S-04 判定。
3. **存储池有余量**：
   ```bash
   heketi-cli --user <u> --secret <s> topology info | grep -i free
   ```
4. 版本匹配：glusterfs 8.5 + heketi 9.0 / 10.4。

## 步骤

```bash
# 1) 从 PV 拿到卷名（在控制面执行）
kubectl get pv <pv-name> -o jsonpath='{.spec.glusterfs.path}'
# 得到形如 vol_d60ab464381985caecf95fdce35ba2ef

# 2) 在 heketi 主机上扩容（二选一）
gtool ex -v vol_xxxx -s +10     # 在当前基础上加 10Gi
gtool ex -v vol_xxxx -s 25      # 直接扩到 25Gi（绝对值）

# 3) 确认
gtool ex -h                     # 查看用法
df -h <挂载点>                   # 容器内或主机挂载点
```

扩容是在线生效的，**不需要**重启 Pod，也不需要动 PVC。

## 关于"要不要顺手改 PV/PVC 容量"

- **不建议改 PVC**：最新基线里 PVC 容量是不可变字段；即便能改，也会把卷变成高风险盘（见 `01`）。
- **PV 容量可选**：部分环境为了让 `kubectl describe pv` 显示与实际一致，会 `kubectl edit pv` 把 `spec.capacity.storage` 调大。这一步不影响后端，只影响展示与调度判断；**不做也不会有任何问题，做错了反而制造不一致**。看不明白就别做。
- 如果一定要改：只能改 PV，且新值不得超过后端实际容量；**永远不要**通过改 PVC 来"让容量生效"。

## 常见报错

### 1. ssh 相关报错（gtool 需要通过 heketi 的 key 连各节点）

```
# 在 heketi 主机上，用 heketi 自己的 key 给所有存储节点（含本机）做免密
ssh-copy-id -i /etc/heketi/heketi_key root@<node1>
ssh-copy-id -i /etc/heketi/heketi_key root@<node2>
ssh-copy-id -i /etc/heketi/heketi_key root@<node3>
```

若 sshd 配了 `AllowUsers` / 端口不是 22，需要相应放开或调整，不是 gtool 的问题。

### 2. `Logical volume tp_... not found in volume group vg_...`

说明该卷的拓扑不符合 gtool 的默认假设（非标准盘）。做法：手工补全拓扑信息。

```bash
# a) 导出卷拓扑
gluster v info <vol> --xml > ./info

# b) 看 bricks 行，拿到每块砖的主机与路径
grep mounts ./info

# c) 对每个 brick，ssh 到对应主机查 thinpool 名字（Pool 列）
ssh -i /etc/heketi/heketi_key root@<server-ip> lvs <brick 引用>

# d) 把 thinpool 名字按 server 一一对应填进 ./info 的对应 brick 节点
vi ./info

# e) 用拓扑文件重新扩容
gtool ex -v <vol> -s <目标大小> --info ./info
```

⚠️ server ip 与 thinpool 名必须**一一对应**，错位会把容量加到别的盘上。

## 校验

```bash
# 后端
gluster v status <vol> --xml
gluster v heal <vol> info summary --xml     # 扩容后 entries 短暂非 0 属正常

# 业务
kubectl -n <ns> exec <pod> -- df -h <挂载点>
kubectl -n <ns> logs <pod> --tail=50
```

## 先别扩：thin pool 快满但 `df` 很低时，先回收

现象（巡检 L1-10 会报）：`lvs` 里该池 `data_percent` ≥80%，但对应 brick 的 `df` 只有个位数。

成因：brick 挂载没有 `discard`，删掉的文件不会把块还给 thin pool。池被判满后，写入会 `EIO`，brick 转只读——**这是真实的容量风险，不是误报**。

```bash
# 1) 确认池占比与对应关系（用 pool_lv 列，别按名字猜）
lvs --noheadings -o lv_name,pool_lv,lv_size,data_percent,metadata_percent

# 2) 在该 brick 所在主机上，对 brick 文件系统做回收（不是对 gluster 挂载点）
fstrim -v /var/lib/heketi/mounts/<vg>/<brick>/brick

# 3) 复查，应明显下降
lvs --noheadings -o lv_name,data_percent | grep <brick_id>
```

实测参考：一个 5G 砖（`df` 1%、池 94.03%）执行 `fstrim` 后池降到 **0.27%**；新建 1G 卷写 200MB 再删文件，池保持 20.78%，`fstrim` 后回到 1.37%。

注意：

- **走 gluster 客户端挂载点执行 `fstrim` 会失败**（`FITRIM ioctl failed: Function not implemented`，已实测），必须打在 brick 文件系统上。
- `fstrim` 只回收"已删除文件占用的块"，不动有效数据；但它会产生一轮 IO，建议低峰执行。
- `fstrim` 后池仍高 → 说明是真实占用，这时才走 gtool 扩容（本手册前面的流程）。
- 逐台主机做，做完一台看一台，不要全集群一把梭。

## 明确禁止

- 用 `kubectl edit pvc` / `kubectl patch pvc` 扩容。
- 在 gtool 扩容后立刻做 `heketi-cli device resync`（会打乱 DB，必要时由存储负责人评估）。
- 对"已用 PVC 扩容过的卷"强行用 gtool（会报错，不要绕过）。
- 缩容。glusterfs 不支持安全缩容。

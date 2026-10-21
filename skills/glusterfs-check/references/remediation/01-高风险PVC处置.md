# 01 · 高风险 PVC 处置

> **本文档仅供人工执行。本技能不执行任何修复、扩容、替换动作。**
> 风险等级：**高**（涉及数据）；是否需要停机：视路径而定；是否可回滚：部分不可回滚。

## 适用

巡检中命中 K8S-04 的信号（`distCount > 1` / `PV capacity ≠ heketi Size` / `allowVolumeExpansion: true`），或业务侧已经出现下列症状：

- Pod 启动失败，日志或事件出现 `Permission denied`，且该 Pod 以非 root 用户运行
- 挂载点目录权限变成 `d---------`，属主变成 `root:root`
- 写入报 `Transport endpoint is not connected`
- `df` 看到的剩余空间与实际可写入量严重不符

## 背景：为什么"改 PVC 扩容"是高危

`kubectl edit pvc` 把 `spec.resources.requests.storage` 改大，在 glusterfs + heketi 的旧链路里会触发后端卷重建/重分布，已知后果：

1. **挂载点属主/权限被重置**：变成 `root:root` + `d---------`。非 root 启动的 Pod 直接失去写权限（root 启动的 Pod 不受影响）。
2. **数据重新计算 hash 并散布到多个新分片**：小文件多时 CPU 与耗时显著上升；分片之间用量不均。
3. **实际可用空间不可靠**：PVC 显示 3G、`df` 显示剩 1.5G，但写入 >1.1G 的文件仍会失败。
4. **可恢复性变差**：数据分散在多个分片，出问题需要跨分片聚合才能拼出一个完整副本；实践中一旦 `gfid` 丢失，基本找不回。
5. **数据丢失信号**：一旦业务从挂载点访问报 `file transport not connected`，即为已发生数据丢失，不可找回。

## 处置路径（三选一，按现状判断）

### 路径 A：只是权限坏了（数据可读可写，Pod 起不来）

前置：能确认数据本身没坏（Pod 内 `ls` 能列出文件、能读到内容）。

```bash
# 1) 找到 PV 对应的卷名与 glusterfs 服务端地址
kubectl get pv <pv-name> -o jsonpath='{.spec.glusterfs.path}'
kubectl get sc <sc-name> -o jsonpath='{.parameters.resturl}'

# 2) 在任一能访问存储网的机器上临时挂载
mkdir -p /mnt/fix
mount -t glusterfs <server-ip>:<vol-name> /mnt/fix

# 3) 恢复属主属组与权限（按原 Pod 的运行用户来）
chown <uid>:<gid> /mnt/fix
chmod 775 /mnt/fix
chmod g+s /mnt/fix        # 需要保持与原目录一致时

# 4) 卸载
umount /mnt/fix
```

说明：
- 权限变更会同步到正在挂载的 Pod，**通常不需要重启 Pod**；是否重启取决于应用自身是否缓存了权限判断。
- 属主写错会引入新的权限问题，改前先 `stat` 记录原值。
- 这一步只改目录本身，**不要**递归 `chown -R`（会动到全部数据，耗时且可能改变业务预期）。

回滚：把属主/权限改回原值（改前必须记录）。

### 路径 B：数据已经损坏 / 需要换盘

转 `02-替换PVC.md`。不要试图在坏盘上做 heal 修复后再用。

### 路径 C：还没坏，只是有风险（最常见）

**什么都别改。** 做两件事：

1. 关掉扩容门：按 `07-SC基线修正.md` 把 `allowVolumeExpansion` 改成 `false`（只影响新建，不影响存量）。
2. 后续扩容一律走 `gtool`：见 `05-gtool扩容PVC.md`。

> 已经扩过的卷不要"改回去"——缩容在 glusterfs 上不是安全操作，可能直接丢数据。

## 校验（人工执行后）

```bash
# 权限是否恢复
stat -c '%U:%G %a %n' /mnt/fix

# 业务侧
kubectl -n <ns> get pod <pod> -o wide
kubectl -n <ns> logs <pod> --tail=50

# 存储侧：副本是否完整、有无 heal 积压
gluster v status <vol> --xml
gluster v heal <vol> info summary --xml
```

## 明确禁止

- 再次 `kubectl edit pvc` 改容量"试试看"。
- 在未确认数据完整性的情况下执行 `gluster v heal <vol> full`。
- 用 `chown -R` 大范围改权限。
- 把"改 PVC 扩容"当成常规扩容手段——常规手段只有 `gtool`。

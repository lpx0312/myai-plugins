# 02 · 替换 PVC

> **本文档仅供人工执行。本技能不执行任何修复、扩容、替换动作。**
> 风险等级：**高**；是否需要停机：**建议停机**（数据备份期间有写入则无法保证一致）；是否可回滚：可（改回旧 PVC），但旧数据另说。

## 适用

- 卷内数据有误 / 部分文件读不出来，需要从其它副本重建一份可用数据
- 高风险 PVC 处置后仍不可用（见 `01-高风险PVC处置.md` 路径 B）
- 需要把业务从 glusterfs 迁到别的存储（流程相同，只换 StorageClass）

## 前置条件（缺一不可）

1. **存储池有足够余量**：新 PVC 会真实占用空间。
   ```bash
   heketi-cli --user <u> --secret <s> topology info | grep -i free
   ```
   口令在 `/etc/heketi/heketi.json`（明文）；heketi 在哪台主机看 SC 的 `parameters.resturl`。
2. 记录业务当前的副本数、镜像、环境变量、挂载点——替换后要原样恢复。
3. 有可用的备份落点（本地盘/NFS/对象存储），且**容量足够放下一份完整数据**。
4. 明确维护窗口：替换过程需要重启业务负载。

## 步骤

### Step 1 建新 PVC

从原 PVC 复制一份，删掉不该带的字段：

必须删：`metadata.annotations`、`metadata.creationTimestamp`、`metadata.resourceVersion`、`metadata.uid`、`spec.volumeName`、`status`
必须改：`metadata.name`（不能与旧的重名）
建议保留：`accessModes`、`storageClassName`、`volumeMode`、`metadata.labels`
容量：整数 + `Gi`，**可以比原 PVC 大**（这一步是安全的扩容时机）

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <new-name>
  namespace: <same-ns>
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: <n>Gi
  storageClassName: <same-sc>
  volumeMode: Filesystem
```

```bash
kubectl apply -f new-pvc.yaml
kubectl -n <ns> get pvc <new-name> -w     # 等到 Bound
```

### Step 2 迁移数据（二选一）

**方式 A：Job（推荐，适合有集群内镜像仓库）**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: copy-<new-name>
  namespace: <ns>
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: rsync
        image: <带 rsync 的镜像>
        command: ["sh","-c","rsync -cavh /src/ /dst/"]
        volumeMounts:
        - {name: src, mountPath: /src}
        - {name: dst, mountPath: /dst}
      volumes:
      - name: src
        persistentVolumeClaim: {claimName: <old-name>}
      - name: dst
        persistentVolumeClaim: {claimName: <new-name>}
```

前提：旧 PVC 仍能被正常挂载（能读）。若旧 PVC 已无法挂载，走方式 B。

**方式 B：主机侧挂载 + rsync（旧 PVC 挂不上时）**

```bash
mkdir -p /tmp/old /tmp/new
mount -t glusterfs <server-ip>:<old-vol> /tmp/old
mount -t glusterfs <server-ip>:<new-vol> /tmp/new
rsync -cavh /tmp/old/ /tmp/new     # 注意源路径以 / 结尾
umount /tmp/new && umount /tmp/old
```

若旧卷部分文件损坏，`rsync` 会报 read error：**记录下来**，这些文件只能从 brick 后端或其他副本人工抢救（见下）。

### Step 3 切换业务

```bash
kubectl -n <ns> scale deploy/<name> --replicas=0     # 或 sts
kubectl -n <ns> edit deploy/<name>                   # 改 claimName 为新 PVC
kubectl -n <ns> scale deploy/<name> --replicas=<原值>
```

### Step 4 验证

```bash
kubectl -n <ns> get pod -w
kubectl -n <ns> logs <pod> --tail=100
kubectl -n <ns> exec <pod> -- df -h <挂载点>
kubectl -n <ns> exec <pod> -- ls -la <挂载点> | head
```

确认：Pod Running、无权限报错、能读到关键文件、写入正常。

### Step 5 回收旧 PVC（可选，不可回滚）

```bash
kubectl -n <ns> delete pvc <old-name>
```

前提：**已确认新 PVC 数据完整、业务稳定运行至少一个观察周期**。删除后后端卷与数据一并释放，找不回来。

## 从 brick 后端抢救数据（旧卷已挂不上时）

```bash
gluster v info <old-vol> | grep Brick
```

按输出 ssh 到各主机，进入 brick 目录备份。三条硬规则：

1. **不要备份 `.glusterfs` 目录**（会把内部元数据一起复制出去，恢复时出问题）。
2. **不要从标了 `(arbiter)` 的 brick 备份**——仲裁砖没有真实数据。
3. 同一主机有多个 brick 时，分别备份到**同一个**目标目录（它们本来就是一个卷的不同分片）。

```bash
rsync -cavh --exclude=.glusterfs \
  /var/lib/heketi/mounts/<vg>/<brick>/brick/ /backup/<old-vol>/
```

> 注意：从 brick 直接拷出来的是"分片视图"，多个 brick 拼起来才完整；只有一片时可能缺文件。这也是为什么优先从客户端挂载点备份。

## 回滚

- 切换前：直接不改，删掉新 PVC 即可。
- 切换后：把 workload 的 `claimName` 改回旧的，恢复副本数。旧 PVC **不要删**直到确认不再需要。

## 明确禁止

- 在业务仍写入时做"在线"rsync 并声称数据一致。
- 删除旧 PVC 前不做一次完整的文件数/大小对比。
- 用 `cp -a` 代替 `rsync -c`（无校验，中断后不可续）。

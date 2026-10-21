# 03 · brick 离线恢复

> **本文档仅供人工执行。本技能不执行任何修复、挂载、重启动作。**
> 风险等级：**高**；是否需要停机：通常不需要（单砖），整卷 stop/start 需要维护窗口；是否可回滚：可。

## 适用

巡检命中以下任一：

- `L1-05`：某卷存在 `status=0` 的 brick（`gluster v status --xml`）
- `L1-11`：brick 目录的 `findmnt` 显示的是根盘而不是自己的 LV（**挂载丢失**）
- `L1-01`：某台主机 `glusterd` 非 active
- 业务侧：`Transport endpoint is not connected`、偶发 IO 错误

## 先分类，再动手

| 类型 | 特征 | 处理方向 |
|---|---|---|
| **A. 单砖离线（挂载丢失 / LV 未挂）** | 其它副本在线；该主机 SSH 正常；`findmnt` 指向根盘 | 主机侧重挂 LV，再让卷重新拉起 brick |
| **B. 主机重启 / 宕机** | 整机 brick 全离线 | `mount -a` → `systemctl restart glusterd` |
| **C. brick 进程崩溃/卡死（节点在线）** | 挂载正常、进程不在或卡住 | 查 brick 日志 → 停启整卷 |
| **D. 大面积 brick 离线** | 多卷、多砖同时离线 | 先按主机聚合，逐台恢复；恢复不了按数据故障升级 |

## 通用前置

1. 记录现场（便于回滚与报障）：
   ```bash
   gluster v status <vol> --xml          # 哪些砖离线
   gluster peer status                   # peer 是否正常
   systemctl is-active glusterd          # 本机服务
   findmnt -n -T <brick挂载目录> -o TARGET,SOURCE,FSTYPE
   ```
2. 确认**其它副本在线**（replica 3 至少 2 个在线才安全；arbiter 卷至少 2 个）。
3. 明确该卷承载的业务，必要时先降载或停业务。

---

## 类型 A：挂载丢失

判断：`gluster v status <vol> clients` 里该砖显示 `Brick is offline`；主机上 `findmnt` 指向根盘。

```bash
# 1) 在故障主机上确认 LV 还在（不要跳过这步）
lvs --noheadings -o lv_name,vg_name,lv_size | grep <brick_id>

# 2) 重新挂载（目录已存在则不要重建）
mount /dev/<vg>/brick_<brick_id> /var/lib/heketi/mounts/<vg>/brick_<brick_id>

# 3) 确认挂上了
findmnt -n -T /var/lib/heketi/mounts/<vg>/brick_<brick_id>/brick -o TARGET,SOURCE

# 4) 让卷重新拉起该 brick（会短时中断该卷读写！需维护窗口）
gluster v stop <vol> --mode=script
gluster v start <vol>
```

> 该版本**不支持**单砖 `volume stop <vol> <brick>`，只能停整卷。所以第 4 步一定要在窗口内做。

若 `/etc/fstab` 里对应条目丢了，**先补条目再挂载**，否则下次重启还会掉（fstab 的正确写法参考同主机上其它 brick 行：`/dev/mapper/<vg>-brick_<id> /var/lib/heketi/mounts/<vg>/brick_<id> xfs rw,inode64,noatime,nouuid 1 2`）。

## 类型 B：主机重启后

```bash
# 在重启后的主机上
mount -a
systemctl restart glusterd
systemctl is-active glusterd

# 回到任一节点复查
gluster v status --xml
```

主机重启期间写入的增量数据，会在 brick 上线后由 self-heal 自动补回（可能持续一段时间，期间 `heal info` entries 非 0 是正常的）。

## 类型 C：brick 进程崩溃

```bash
# 看日志定位（近 200 行足够定性）
tail -200 /var/log/glusterfs/bricks/<brick名>.log
journalctl -u glusterd --since "-2h" --no-pager | tail -100
```

常见原因：盘满、inode 满、LV 未挂、`trusted.glusterfs.volume-id` 丢失、`.glusterfs` 目录缺失。对应处置：
- 盘/inode 满 → 先扩容（`05` / `06`），再拉起
- LV 未挂 → 类型 A
- 元数据丢失 → **转 08 手册**，不要盲目 `mkfs`

修复后：

```bash
gluster v stop <vol> --mode=script
gluster v start <vol>
```

## 类型 D：大面积 brick 离线

先聚合，别一个一个救：

```bash
# 统计离线的 brick，按主机归并
gluster v status --xml    # 解析出 hostname:path + status=0
```

若离线砖**集中在同一台主机**：

```bash
# 该主机上
mount -a
systemctl restart glusterd
```

恢复后重新巡检；仍有离线砖，逐卷按类型 A/C 处理。若同一卷**多数副本**离线（replica 3 有 2 个离线），**停止操作，按数据故障升级**——继续折腾可能把仅存的副本也弄坏。

## 校验

```bash
gluster v status <vol> --xml                 # 期望全部 status=1
gluster v heal <vol> info summary --xml      # entries 会先升后降，属正常
gluster peer status
```

数据一致性抽查（只读）：

```bash
# 从客户端挂载点读
mount -t glusterfs <server>:/<vol> /mnt/check
ls -la /mnt/check
umount /mnt/check
```

## 明确禁止

- **brick 没挂上就 `rm`/`mkfs`/格式化**——数据还在 LV 里，先挂载。
- 未经确认就在 brick 目录里删文件"清理空间"。
- 多数副本离线时继续 `stop/start` 折腾。
- 直接 `pkill -9 glusterfsd`（会连带杀掉正常 brick；该版本要用精确进程名，且优先走服务管理）。

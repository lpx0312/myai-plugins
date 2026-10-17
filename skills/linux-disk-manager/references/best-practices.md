# Linux磁盘管理最佳实践

## 安全原则

### 数据安全
1. **确认磁盘设备**: 操作前务必用`lsblk`确认磁盘设备名
2. **数据备份**: 操作会清除磁盘数据,确保已备份重要数据
3. **分步验证**: 每步操作后验证结果,不要一次性执行所有命令
4. **测试环境**: 新流程先在测试环境验证

### 风险提示
- ⚠️ `fdisk`、`mkfs`、`pvcreate`等命令会清除数据
- ⚠️ `lvremove`、`vgremove`不可逆
- ⚠️ 错误的fstab配置可能导致系统无法启动
- ⚠️ 根分区操作需特别谨慎

## 文件系统选择

### XFS
**优点**:
- 大文件性能优异
- 支持更大文件系统(16EB vs 16TB)
- 在线扩容方便(xfs_growfs)
- 并发性能好

**缺点**:
- 不能缩容
- 小文件性能略低于ext4

**适用场景**:
- 大文件存储(视频、镜像、数据库)
- 需要在线扩容
- 高并发场景

### EXT4
**优点**:
- 稳定性好,兼容性强
- 可以缩容
- 工具链成熟

**缺点**:
- 单个文件系统最大16TB
- 在线扩容需要umount(某些情况)

**适用场景**:
- 小文件存储
- 需要缩容
- 兼容性要求高

### 选择建议
```
数据用途         | 推荐文件系统
----------------|------------
Docker/K8S      | XFS
数据库           | XFS
日志             | XFS
普通应用         | EXT4或XFS
/home            | EXT4(可缩容)
/boot            | EXT4
```

## LVM vs 标准分区

### 使用LVM的场景
✅ 多磁盘需要聚合
✅ 未来可能扩容
✅ 需要快照功能
✅ 需要跨磁盘的条带化或镜像
✅ K8S节点(docker/kubelet目录)

### 使用标准分区的场景
✅ 单磁盘,简单场景
✅ 不需要后续扩容
✅ 追求简单直接
✅ /boot分区(必须标准分区)

### 混合方案
```
/dev/sda1: /boot (标准分区)
/dev/sda2: LVM PV
  ├─ vg_root/root (LV,挂载/)
  ├─ vg_data/data (LV,挂载/data)
  └─ vg_swap/swap (LV,用作swap)
```

## /etc/fstab配置要点

### UUID vs 设备名
**推荐UUID**:
```bash
# ✅ 推荐:使用UUID
UUID=abc123-def4-5678 /data xfs defaults 0 0

# ❌ 不推荐:使用设备名(可能变化)
/dev/sdb1 /data xfs defaults 0 0

# ✅ 可接受:LVM路径(相对稳定)
/dev/mapper/vg_data-lv_data /data xfs defaults 0 0
```

### 挂载选项
```bash
defaults         # 标准选项(rw,suid,dev,exec,auto,nouser,async)
noatime          # 不更新访问时间(提升性能)
nodiratime       # 不更新目录访问时间
ro               # 只读挂载
noexec           # 禁止执行(安全考虑)
```

### 第6列(fsck顺序)
```bash
0   # 不检查(如数据盘)
1   # 根分区首先检查
2   # 其他文件系统
```

### 推荐配置
```bash
# 系统盘
UUID=xxx / xfs defaults 0 1

# 数据盘
UUID=xxx /data xfs defaults,noatime 0 2

# swap
UUID=xxx swap swap defaults 0 0
```

## 性能优化

### 磁盘调度算法
```bash
# 查看当前调度器
cat /sys/block/sdb/queue/scheduler

# SSD推荐deadline或noop
echo deadline > /sys/block/sdb/queue/scheduler

# HDD推荐cfq
echo cfq > /sys/block/sdb/queue/scheduler
```

###挂载选项优化
```bash
# 数据库场景
mount -o noatime,nodiratime,barrier=0 /dev/sdb1 /data

# 高并发场景
mount -o noatime,nodiratime /dev/sdb1 /data

# 安全优先
mount -o defaults,noexec,nodev /dev/sdb1 /data
```

## 故障排查

### 磁盘识别不到
```bash
# 1. 检查物理连接
lsblk
fdisk -l

# 2. 扫描SCSI总线
echo "- - -" > /sys/class/scsi_host/host0/scan

# 3. 查看内核日志
dmesg | grep -i sd
tail -f /var/log/messages
```

### 挂载失败
```bash
# 检查1: 文件系统类型
blkid /dev/sdb1

# 检查2: 挂载点是否存在
ls -ld /data

# 检查3: 是否已挂载
mount | grep sdb1

# 检查4: 文件系统损坏
xfs_repair -n /dev/sdb1    # XFS检查(不修复)
fsck -n /dev/sdb1          # EXT4检查(不修复)
```

### LVM问题
```bash
# LV找不到
vgscan
lvscan

# VG不激活
vgchange -ay vg_data

# 显示详细信息
lvdisplay -v /dev/vg_data/lv_data
```

## 回滚方案

### 非LVM回滚
```bash
# 1. 卸载
umount /data

# 2. 删除fstab配置
vi /etc/fstab  # 删除对应行

# 3. 删除分区(可选)
fdisk /dev/sdb
# d → 1 → w
```

### LVM回滚
```bash
# 1. 卸载
umount /data

# 2. 停用LV
lvchange -an /dev/vg_data/lv_data

# 3. 删除LV
lvremove /dev/vg_data/lv_data

# 4. 删除VG
vgremove vg_data

# 5. 删除PV
pvremove /dev/sdb1

# 6. 删除分区(可选)
fdisk /dev/sdb
```

## 特殊场景

### K8S节点磁盘配置
```bash
# Docker目录
/dev/mapper/vg_docker-lv_docker  /var/lib/docker  xfs  defaults,noatime  0 2

# Kubelet目录
/dev/mapper/vg_k8s-lv_kubelet    /var/lib/kubelet xfs  defaults,noatime  0 2
```

### 数据库磁盘配置
```bash
# MySQL/PostgreSQL数据目录
UUID=xxx /var/lib/mysql xfs defaults,noatime,barrier=0 0 2

# 推荐: 使用XFS + barrier=0提升性能
# 警告: 需要可靠的硬件(UPS/RAID卡BBWC)
```

### 日志磁盘配置
```bash
# 应用日志
UUID=xxx /var/log/app xfs defaults,noatime 0 2

# 考虑: 使用单独的磁盘避免日志占满根分区
```

## 监控建议

### 定期检查
```bash
# 磁盘使用率
df -hT

# 磁盘IO
iostat -x 1

# LVM剩余空间
vgdisplay vg_data | grep Free

# 查找大文件
find /data -type f -size +100M 2>/dev/null
```

### 告警阈值
- 磁盘使用率 > 80%: 警告
- 磁盘使用率 > 90%: 严重
- VG剩余空间 < 20%: 考虑扩容
- IO等待 %iowait > 20%: 性能瓶颈

## 学习资源

### 官方文档
- Red Hat LVM Guide: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/
- XFS Documentation: https://xfs.wiki.kernel.org/

### 推荐阅读
- LVM实战: 理解VG/LV/PV关系
- 磁盘性能调优: 调度算法、挂载选项
- fstab详解: 各字段含义和最佳实践

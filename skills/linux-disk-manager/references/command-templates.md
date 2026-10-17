# Linux磁盘管理命令模板

## 磁盘分区模板

### fdisk自动分区
```bash
# 创建单个主分区,使用全部空间
echo -e "n\np\n1\n\n\nw" | fdisk /dev/sdb

# 创建指定大小分区(如40G)
echo -e "n\np\n1\n\n+40G\nw" | fdisk /dev/sdb

# 创建多个分区
echo -e "n\np\n1\n\n+40G\nw" | fdisk /dev/sdb
echo -e "n\np\n2\n\n+40G\nw" | fdisk /dev/sdb
echo -e "n\np\n3\n\n\nw" | fdisk /dev/sdb
```

### 刷新分区表
```bash
partprobe /dev/sdb
# 或
partprobe
# 或
kpartx -a /dev/sdb
```

## LVM管理模板

### 创建PV(物理卷)
```bash
# 创建单个PV
pvcreate /dev/sdb1

# 创建多个PV
pvcreate /dev/sdb1 /dev/sdc1 /dev/sdd1

# 验证PV
pvs
pvdisplay /dev/sdb1
```

### 创建VG(卷组)
```bash
# 创建VG
vgcreate vg_data /dev/sdb1

# 创建VG(聚合多个PV)
vgcreate vg_data /dev/sdb1 /dev/sdc1

# 查看VG
vgs
vgdisplay vg_data
```

### 创建LV(逻辑卷)
```bash
# 指定大小创建
lvcreate -n lv_data -L 100G vg_data

# 使用VG全部空间
lvcreate -n lv_data -l 100%FREE vg_data

# 使用VG的50%
lvcreate -n lv_data -l 50%VG vg_data

# 验证LV
lvs
lvdisplay /dev/vg_data/lv_data
```

### LV扩容
```bash
# 扩容指定大小
lvextend -L +50G /dev/vg_data/lv_data

# 扩容到指定大小
lvextend -L 200G /dev/vg_data/lv_data

# 使用VG全部剩余空间
lvextend -l +100%FREE /dev/vg_data/lv_data

# XFS文件系统刷新
xfs_growfs /data

# EXT4文件系统刷新
resize2fs /dev/vg_data/lv_data
```

### 删除LVM
```bash
# 停用LV
lvchange -an /dev/vg_data/lv_data

# 删除LV
lvremove /dev/vg_data/lv_data

# 删除VG
vgremove vg_data

# 删除PV
pvremove /dev/sdb1
```

## 文件系统模板

### 格式化
```bash
# XFS格式化
mkfs.xfs /dev/sdb1

# EXT4格式化
mkfs.ext4 /dev/sdb1

# 添加卷标
mkfs.xfs -L "Data Disk" /dev/sdb1
```

### 挂载
```bash
# 临时挂载
mount /dev/sdb1 /data

# 指定文件系统类型
mount -t xfs /dev/sdb1 /data

# 指定选项挂载
mount -o defaults,noatime /dev/sdb1 /data
```

### /etc/fstab配置
```bash
# 获取UUID
blkid /dev/sdb1

# XFS fstab条目
UUID=xxx /data xfs defaults 0 0

# EXT4 fstab条目
UUID=xxx /data ext4 defaults 0 0

# LVM fstab条目(使用路径)
/dev/mapper/vg_data-lv_data /data xfs defaults 0 0

# LVM fstab条目(使用UUID)
UUID=xxx /data xfs defaults 0 0

# 测试fstab
umount /data
mount -a
df -hT | grep /data
```

## 磁盘扫描模板

### 扫描SCSI总线(新增硬盘)
```bash
# 扫描特定host
echo "- - -" > /sys/class/scsi_host/host0/scan

# 扫描所有host
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

# 验证识别
fdisk -l
lsblk
```

### 重新扫描已存在磁盘(扩容)
```bash
# 重新扫描特定磁盘
echo 1 > /sys/block/sda/device/rescan

# 验证扩容
fdisk -l /dev/sda
```

## 验证命令模板

### 磁盘信息查看
```bash
# 树形结构查看
lsblk

# 查看分区详情
fdisk -l /dev/sdb

# 查看UUID和文件系统
blkid
blkid /dev/sdb1

# 查看挂载和空间使用
df -hT

# 查看挂载详情
mount | grep /data
```

### LVM信息查看
```bash
# 查看PV
pvs
pvdisplay /dev/sdb1

# 查看VG
vgs
vgdisplay vg_data

# 查看LV
lvs
lvdisplay /dev/vg_data/lv_data
```

### 功能测试
```bash
# 写入测试
echo "test-$(date)" > /data/disk-test.txt
cat /data/disk-test.txt

# 性能测试(可选)
dd if=/dev/zero of=/data/test.img bs=1M count=1000
```

## 常见问题处理

### 卸载占用目录
```bash
# 查看占用进程
lsof /data
fuser -m /data

# 结束进程
kill -9 <PID>

# 强制卸载
umount -l /data
```

### 分区表损坏
```bash
# 修复分区表
parted /dev/sdb print
parted /dev/sdb mklabel msdos  # 或 gpt
```

### LVM路径问题
```bash
# LV路径的三种形式
/dev/vg_data/lv_data
/dev/mapper/vg_data-lv_data
/dev/dm-0

# 推荐使用前两种
```

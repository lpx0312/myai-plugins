# Linux磁盘管理场景参考

## 6大核心场景详细流程

### 场景1: 新增磁盘(非LVM)标准流程

**适用**: 单个磁盘,简单分区,无需后续扩容

**流程**:
1. 磁盘预检查: `lsblk /dev/sdb`, `fdisk -l /dev/sdb`
2. 磁盘分区: `echo -e "n\np\n1\n\n\nw" | fdisk /dev/sdb`
3. 刷新分区表: `partprobe /dev/sdb`
4. 格式化: `mkfs.xfs /dev/sdb1` 或 `mkfs.ext4 /dev/sdb1`
5. 创建挂载点: `mkdir -p /data`
6. 临时挂载: `mount /dev/sdb1 /data`
7. 获取UUID: `blkid /dev/sdb1`
8. 配置fstab: `echo "UUID=xxx /data xfs defaults 0 0" >> /etc/fstab`
9. 验证: `df -hT /data`, 写入测试文件

---

### 场景2: 新增磁盘(LVM)标准流程

**适用**: 多磁盘聚合,需要灵活扩容

**流程**:
1. 磁盘预检查: `lsblk`
2. 磁盘分区: 为每个磁盘创建分区
3. 创建PV: `pvcreate /dev/sdb1 /dev/sdc1`
4. 创建VG: `vgcreate vg_data /dev/sdb1 /dev/sdc1`
5. 创建LV: `lvcreate -n lv_data -l 100%FREE vg_data`
6. 格式化: `mkfs.xfs /dev/vg_data/lv_data`
7. 挂载: `mount /dev/vg_data/lv_data /data`
8. 配置fstab: 使用LV路径或UUID
9. 验证: `df -hT`, `vgs`, `lvs`

---

### 场景3: 不停机热添加硬盘

**适用**: VMware/ESXi虚拟机运行时添加新硬盘

**流程**:
1. 扫描SCSI总线: `echo "- - -" > /sys/class/scsi_host/host0/scan`
2. 批量扫描: `for host in /sys/class/scsi_host/host*; do echo "- - -" > "$host/scan"; done`
3. 验证识别: `fdisk -l`, `lsblk`
4. 后续按场景1或2继续

---

### 场景4: 不停机扩容已存在硬盘

**适用**: ESXi环境扩容已有磁盘(注意:VMware Workstation不支持)

**流程**:
1. 重新扫描磁盘: `echo 1 > /sys/block/sda/device/rescan`
2. 验证扩容: `fdisk -l /dev/sda`
3. LVM扩容: `pvresize`, `lvextend`, `xfs_growfs`
4. 非LVM扩容: 需要删除旧分区,重新分区(数据有风险)

---

### 场景5: LVM逻辑卷扩容

**适用**: 在已有VG中扩容LV

**流程**:
1. 查看VG剩余空间: `vgdisplay vg_data | grep Free`
2. 扩容LV: `lvextend -L +50G /dev/vg_data/lv_data`
3. 或使用全部剩余: `lvextend -l +100%FREE /dev/vg_data/lv_data`
4. XFS刷新: `xfs_growfs /data`
5. EXT4刷新: `resize2fs /dev/vg_data/lv_data`
6. 验证: `df -hT /data`

---

### 场景6: 磁盘信息查询与诊断

**适用**: 查看磁盘状态、UUID、挂载情况

**常用命令**:
- 查看块设备: `lsblk`
- 查看UUID: `blkid`
- 查看挂载: `df -hT`
- 查看LVM: `pvs`, `vgs`, `lvs`
- 查看分区: `fdisk -l`

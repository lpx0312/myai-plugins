---
name: wake-on-lan
description: 通过 Wake-on-LAN (WOL) 远程唤醒局域网主机。支持单台或批量唤醒，自动验证主机启动状态。触发词包括 "wake"、"唤醒"、"开机"、"远程开机"、"WOL"、"启动主机"、"wake up"。支持的主机：esxi200, xp, r3600, all（全部主机）。
---

# Wake-on-LAN 远程唤醒

远程唤醒局域网内主机并验证启动状态。

## 工作流程

### 1. 主机名验证

当收到唤醒请求时，首先验证主机名是否匹配：

```bash
# 支持的主机名
esxi200  -> 192.168.0.200 (MAC: 22:02:4d:07:5c:7a)
xp       -> 192.168.0.225 (MAC: 1C:83:41:8A:4E:7B)
r3600    -> 192.168.0.198 (MAC: 2C:F0:5D:3D:27:87)
all      -> 唤醒所有主机
```

**如果主机名不匹配**，提示用户：
```
❌ 未找到主机: {输入的主机名}
可用的主机:
  - esxi200 (192.168.0.200)
  - xp (192.168.0.225)
  - r3600 (192.168.0.198)
  - all (唤醒所有主机)
```

### 2. 发送唤醒命令

使用 `scripts/wake_and_verify.sh` 脚本唤醒并验证：

```bash
# 唤醒单台主机并验证
~/wake_and_verify.sh <主机名>

# 示例
~/wake_and_verify.sh r3600
```

该脚本会：
1. 发送 WOL 魔术包
2. 等待主机启动（最长 3 分钟）
3. 每 10 秒 ping 一次验证主机是否在线
4. 报告启动状态

### 3. 手动验证（可选）

如需手动验证，使用以下命令：

```bash
# 发送唤醒包
wakeonlan <MAC地址>

# 等待 30 秒后验证
sleep 30 && ping -c 1 <IP地址>
```

## 主机列表

| 名称 | IP地址 | MAC地址 | 用途 |
|------|--------|---------|------|
| esxi200 | 192.168.0.200 | 22:02:4d:07:5c:7a | ESXi 虚拟化主机 |
| xp | 192.168.0.225 | 1C:83:41:8A:4E:7B | Windows XP 测试机 |
| r3600 | 192.168.0.198 | 2C:F0:5D:3D:27:87 | Ryzen 3600 工作站 |

## 快速命令

### 唤醒单台主机

```bash
wakeonlan 22:02:4d:07:5c:7a    # esxi200
wakeonlan 1C:83:41:8A:4E:7B    # xp
wakeonlan 2C:F0:5D:3D:27:87    # r3600
```

### 唤醒所有主机

```bash
wakeonlan 22:02:4d:07:5c:7a && \
wakeonlan 1C:83:41:8A:4E:7B && \
wakeonlan 2:2C:F0:5D:3D:27:87
```

### 验证主机状态

```bash
ping -c 1 192.168.0.200 && echo "esxi200 在线"
ping -c 1 192.168.0.225 && echo "xp 在线"
ping -c 1 192.168.0.198 && echo "r3600 在线"
```

## 前提条件

1. 目标主机 BIOS/UEFI 已开启 WOL (Wake on LAN)
2. 目标主机网卡已开启 WOL 功能
3. 主机处于睡眠或软关机状态（非断电）
4. 网络支持广播包传输

## 快速别名 (可选)

添加到 `~/.bashrc`:

```bash
alias wake-esxi='wakeonlan 22:02:4d:07:5c:7a'
alias wake-xp='wakeonlan 1C:83:41:8A:4E:7B'
alias wake-r3600='wakeonlan 2C:F0:5D:3D:27:87'
alias wake-all='wakeonlan 22:02:4d:07:5c:7a && wakeonlan 1C:83:41:8A:4E:7B && wakeonlan 2C:F0:5D:3D:27:87'
```

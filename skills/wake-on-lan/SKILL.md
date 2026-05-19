---
name: wake-on-lan
description: 通过 Wake-on-LAN (WOL) 远程唤醒局域网主机。支持单台或批量唤醒，自动验证主机启动状态。触发词包括 "wake"、"唤醒"、"开机"、"远程开机"、"WOL"、"启动主机"、"wake up"。支持的主机：esxi200, xp, r3600, all（全部主机）。
---

# Wake-on-LAN 远程唤醒

远程唤醒局域网内主机并验证启动状态。

## 环境判断

首先判断当前操作系统，选择对应的唤醒方式：

| 系统 | 唤醒方式 | 依赖 |
|------|----------|------|
| Windows | Python + Scapy 脚本 | `pip install scapy` |
| Linux | wakeonlan 命令行工具 | 见下方安装命令 |

## Windows 唤醒方式

使用 `scripts/wol_windows.py` 脚本（基于 Scapy Layer 2 广播，支持唤醒+验证）：

```bash
# 使用主机名（自动唤醒并验证启动状态）
python scripts/wol_windows.py <主机名>

# 示例
python scripts/wol_windows.py esxi200
python scripts/wol_windows.py xp
python scripts/wol_windows.py r3600
python scripts/wol_windows.py all      # 唤醒所有主机

# 也可以直接传 MAC 地址（仅发送唤醒包，不验证）
python scripts/wol_windows.py 22:02:4d:07:5c:7a
```

## Linux 唤醒方式

### 安装 wakeonlan

先检查 `wakeonlan` 是否已安装，未安装则按发行版安装：

```bash
# 检查是否已安装
which wakeonlan || echo "未安装"
```

| 系统类型 | 安装命令 |
| :--- | :--- |
| Debian/Ubuntu | `sudo apt update && sudo apt install wakeonlan -y` |
| RHEL/CentOS | `sudo dnf install wakeonlan -y` |
| Arch Linux | `sudo pacman -S wakeonlan` |
| Alpine Linux | `sudo apk add wakeonlan` |

### 唤醒命令

```bash
# 唤醒并验证
~/wake_and_verify.sh <主机名>

# 或直接发送唤醒包
wakeonlan <MAC地址>
```

## 工作流程

### 1. 主机名验证

当收到唤醒请求时，首先验证主机名是否匹配：

```
esxi200  -> 192.168.0.200 (MAC: 22:02:4d:07:5c:7a)
xp       -> 192.168.0.225 (MAC: 1C:83:41:8A:4E:7B)
r3600    -> 192.168.0.198 (MAC: 2C:F0:5D:3D:27:87)
all      -> 唤醒所有主机
```

**如果主机名不匹配**，提示用户：
```
未找到主机: {输入的主机名}
可用的主机:
  - esxi200 (192.168.0.200)
  - xp (192.168.0.225)
  - r3600 (192.168.0.198)
  - all (唤醒所有主机)
```

### 2. 发送唤醒命令

根据操作系统选择命令：

**Windows：**
```bash
python scripts/wol_windows.py <主机名>
```

**Linux：**
```bash
~/wake_and_verify.sh <主机名>
```

### 3. 验证主机状态

```bash
ping -c 1 192.168.0.200 && echo "esxi200 在线"
ping -c 1 192.168.0.225 && echo "xp 在线"
ping -c 1 192.168.0.198 && echo "r3600 在线"
```

## 主机列表

| 名称 | IP地址 | MAC地址 | 用途 |
|------|--------|---------|------|
| esxi200 | 192.168.0.200 | 22:02:4d:07:5c:7a | ESXi 虚拟化主机 |
| xp | 192.168.0.225 | 1C:83:41:8A:4E:7B | Windows XP 测试机 |
| r3600 | 192.168.0.198 | 2C:F0:5D:3D:27:87 | Ryzen 3600 工作站 |

## 前提条件

1. 目标主机 BIOS/UEFI 已开启 WOL (Wake on LAN)
2. 目标主机网卡已开启 WOL 功能
3. 主机处于睡眠或软关机状态（非断电）
4. 网络支持广播包传输

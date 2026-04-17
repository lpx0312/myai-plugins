---
name: esxi-vm-manager
description: Use when managing ESXi hosts - enabling/disabling maintenance mode, starting/stopping VMs, managing VM snapshots, or powering on/off ESXi hosts.
---

# ESXi 虚拟机管理器

通过 ssh-mcp-server 远程管理 ESXi 主机和虚拟机的各项操作。

## 什么时候使用

当用户想要：
- 开启或关闭 ESXi 维护模式
- 开启或关闭虚拟机
- 创建或删除虚拟机快照
- 关闭或开启 ESXi 主机
- 列出所有虚拟机及状态信息
- 设置虚拟机的 CPU 和内存配置
- 虚拟机精简置备磁盘空间清理

## 强制要求

1. **所有操作必须使用 `mcp__ssh-mcp-server__execute-command` 工具，禁止用 Bash(curl) 或 Bash(ssh)**
2. **禁止添加任何验证步骤，命令执行成功即可**
3. **用户输入的主机和 VM 名称直接使用，不需要额外判断或询问**
4. **所有 `mcp__ssh-mcp-server__execute-command` 调用必须设置 `timeout: 1000000`，这是强制要求**

## ESXi 主机

| 主机名 | IP地址 |
|--------|--------|
| esxi200 | 192.168.0.200 |
| esxi3 | 192.168.0.3 |

## 功能模块

根据操作类型，直接加载对应的参考文档执行：

| 操作类型 | 参考文档 |
|----------|----------|
| 维护模式、ESXi 开关机 | `references/host-management.md` |
| 虚拟机开关机 | `references/vm-management.md` |
| 快照创建、删除 | `references/snapshot-management.md` |
| 精简置备磁盘空间清理 | `references/thin-cleanup.md` |

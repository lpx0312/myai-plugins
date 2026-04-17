# ESXi 精简置备磁盘空间清理

本文档包含虚拟机精简置备(thin)磁盘空间清理的操作。

---

## 强制要求

1. **必须使用 `mcp__ssh-mcp-server__execute-command` 工具执行所有命令，禁止用 Bash(curl) 或 Bash(ssh)**
2. **禁止添加任何验证步骤，命令执行成功即可**
3. **所有 `mcp__ssh-mcp-server__execute-command` 调用必须设置 `timeout: 1000000`，这是强制要求**
4. **第0步检查初始状态必须执行，这决定后续是否需要开关机**

---

## IP / 名称解析规则

**输入格式判断**：

| 输入格式 | 示例 | 解析结果 |
|----------|------|----------|
| 纯 IP 地址 | `192.168.2.112` | IP: `192.168.2.112`，VM标识: `192.168.2.112` |
| 名称-IP格式 | `K8S01-192.168.2.111` | IP: `192.168.2.111`，VM标识: `K8S01-192.168.2.111` |

**解析方法**：如果输入包含 `-`，按 `-` 分割取最后一部分作为 IP 地址

---

## 核心工作流程

```
输入解析 → 检查初始状态 → 关闭VM → 删除快照 → 开启VM → fstrim清理 → 关闭VM → vmdk压缩 → [条件性开机]
```

**关键逻辑**：
- **第0步**：检查虚拟机初始状态（开机/关机）
- **最后一步**：如果初始状态是**开机**，则最后重新开启；如果初始状态是**关机**，则保持关机

---

## 第零步：检查虚拟机初始状态

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: vim-cmd vmsvc/getallvms | grep -w "{VM标识}" && esxcli vm process list | grep -w "{VM名称}"**
**timeout: 1000000**

**记录初始状态**：
- 如果 VM 在运行列表中 → `INITIAL_STATE=on`
- 如果 VM 不在运行列表中 → `INITIAL_STATE=off`

---

## 第一步：关闭虚拟机（仅当初始状态为开机时执行）

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-off-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 第二步：删除快照

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/snapshot-del-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 第三步：开启虚拟机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-on-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 第四步：执行 fstrim 清理（直连虚拟机）

**工具: mcp__ssh-mcp-server__execute-command**
**server: {虚拟机IP}**
**command: fstrim -av**
**timeout: 1000000**

> **注意**：此步骤直接连接虚拟机内部执行，使用 ssh-mcp-server 连接虚拟机 IP，不是先连接 ESXi 再 ssh 到 VM。

---

## 第五步：再次关闭虚拟机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-off-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 第六步：VMDK 压缩（回收空间）

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/storage-thin-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 第七步：条件性开机（仅当初始状态为开机时执行）

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-on-vm.sh | sh -s -- "{VM标识}"**
**timeout: 1000000**

---

## 快速命令参考表

| 步骤 | 操作 | 条件 | 命令格式 |
|------|------|------|----------|
| 0 | 检查初始状态 | 必须 | `vim-cmd vmsvc/getallvms \| grep` |
| 1 | 关机 | 仅当初始开机 | `...power-off-vm.sh \| sh -s -- "{VM标识}"` |
| 2 | 删除快照 | 必须 | `...snapshot-del-vm.sh \| sh -s -- "{VM标识}"` |
| 3 | 开机 | 必须 | `...power-on-vm.sh \| sh -- "{VM标识}"` |
| 4 | fstrim | 必须 | ssh-mcp-server直连VM: `fstrim -av` |
| 5 | 关机 | 必须 | `...power-off-vm.sh \| sh -s -- "{VM标识}"` |
| 6 | vmdk压缩 | 必须 | `...storage-thin-vm.sh \| sh -s -- "{VM标识}"` |
| 7 | 条件性开机 | 仅当初始开机 | `...power-on-vm.sh \| sh -- "{VM标识}"` |

---

## 脚本来源

| 脚本 | 用途 |
|------|------|
| `power-off-vm.sh` | 关闭虚拟机 |
| `power-on-vm.sh` | 开启虚拟机 |
| `snapshot-del-vm.sh` | 删除所有快照 |
| `storage-thin-vm.sh` | 精简置备空间回收 |

---

## ESXi 主机信息

| 主机名 | IP地址 |
|--------|--------|
| esxi200 | 192.168.0.200 |
| esxi3 | 192.168.0.3 |

---

## 确定使用的 ESXi 主机

**根据用户输入判断**：

| 用户输入关键词 | 选择的 ESXi |
|---------------|-------------|
| `esxi200` 或 `192.168.0.200` | esxi200 (192.168.0.200) |
| `esxi3` 或 `192.168.0.3` | esxi3 (192.168.0.3) |
| 两台都提到或未明确 | 询问用户 |

**询问模板**：
```
检测到两台 ESXi 服务器：
- esxi200 (192.168.0.200)
- esxi3 (192.168.0.3)

请问需要对哪台 ESXi 上的虚拟机进行清理？
```

---

## 错误处理

| 错误 | 可能原因 | 解决建议 |
|------|----------|----------|
| 无法连接ESXi | 网络不通/主机未启动 | 检查 ESXi 主机是否可达 |
| 虚拟机不存在 | IP或名称错误 | 确认虚拟机标识 |
| fstrim失败 | SSH无法连接VM | 检查VM的SSH服务状态 |
| 脚本执行失败 | 脚本不存在或权限问题 | 检查脚本URL是否可访问 |

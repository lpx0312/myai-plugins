# ESXi 快照管理

本文档包含虚拟机快照的操作：创建快照、删除快照、还原快照。

---

## 强制要求

1. **必须使用 `mcp__ssh-mcp-server__execute-command` 工具执行所有命令，禁止用 Bash(curl) 或 Bash(ssh)**
2. **禁止添加任何验证步骤，命令执行成功即可**
3. **用户输入的 VM 名称直接使用，不需要替换或判断**
4. **所有 `mcp__ssh-mcp-server__execute-command` 调用必须设置 `timeout: 1000000`，这是强制要求**

---

## 1. 创建快照

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/snapshot-create-vm.sh | sh -s -- "{用户输入的VM完整名称}"**
**timeout: 1000000**

---

## 2. 删除快照

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/snapshot-del-vm.sh | sh -s -- "{用户输入的VM完整名称}"**
**timeout: 1000000**

---

## 3. 还原快照

还原虚拟机到**最近一个快照**（自动取最新快照，多快照场景同样适用）。还原过程：若 VM 运行中则先关机 → 还原到最新快照 → 自动开机。

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/snapshot-revert-vm.sh | sh -s -- "{用户输入的VM完整名称}"**
**timeout: 1000000**

**参数说明：**
- `{用户输入的VM完整名称}` - 虚拟机的完整名称（与 list-all-vms 输出一致）

**行为说明：**
- 多快照时自动选择 **Id 最大（即最近创建）** 的快照进行还原
- VM 处于运行状态时会先 `power.off` 再还原，还原后自动 `power.on`
- VM 没有快照时会提示"没有快照，无法还原"并退出

**示例命令：**
```
wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/snapshot-revert-vm.sh | sh -s -- "zk01-192.168.1.51"
```
这会将虚拟机 "zk01-192.168.1.51" 还原到最近一个快照，并自动开机。

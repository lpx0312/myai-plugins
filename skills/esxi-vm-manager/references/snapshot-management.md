# ESXi 快照管理

本文档包含虚拟机快照的操作：创建快照、删除快照。

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

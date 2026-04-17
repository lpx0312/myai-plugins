# ESXi 虚拟机管理

本文档包含虚拟机级别的操作：开关虚拟机。

---

## 强制要求

1. **必须使用 `mcp__ssh-mcp-server__execute-command` 工具执行所有命令，禁止用 Bash(curl) 或 Bash(ssh)**
2. **禁止添加任何验证步骤，命令执行成功即可**
3. **用户输入的 VM 名称直接使用，不需要替换或判断**
4. **所有 `mcp__ssh-mcp-server__execute-command` 调用必须设置 `timeout: 1000000`，这是强制要求**

---

## 1. 开启虚拟机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-on-vm.sh | sh -s -- "{用户输入的VM完整名称}"**
**timeout: 1000000**

---

## 2. 关闭虚拟机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-off-vm.sh | sh -s -- "{用户输入的VM完整名称}"**
**timeout: 1000000**

---

## 3. 列出所有虚拟机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/list-all-vms.sh | sh**
**timeout: 1000000**

返回表格形式展示所有虚拟机信息：VM ID / 虚拟机名称 / 状态(开机/关机) / CPU / 内存

---

## 4. 设置虚拟机 CPU 和内存

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/set-vm-resources.sh | sh -s -- "{用户输入的VM完整名称}" "{CPU核心数}" "{内存大小(GB)}"**
**timeout: 1000000**

**参数说明：**
- `{用户输入的VM完整名称}` - 虚拟机的完整名称
- `{CPU核心数}` - CPU 核心数，如 2、4、8
- `{内存大小(GB)}` - 内存大小（GB），如 2、4、8、16

**示例命令：**
```
wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/set-vm-resources.sh | sh -s -- "ceshi-temp-01" "4" "8"
```
这会将虚拟机 "ceshi-temp-01" 的 CPU 设置为 4 核，内存设置为 8 GB。

# ESXi 主机管理

本文档包含 ESXi 主机级别的操作：维护模式切换、主机开关机。

---

## 强制要求

1. **必须使用 `mcp__ssh-mcp-server__execute-command` 工具执行所有命令，禁止用 Bash(curl) 或 Bash(ssh)**
2. **禁止添加任何验证步骤，命令执行成功即可**
3. **所有 `mcp__ssh-mcp-server__execute-command` 调用必须设置 `timeout: 1000000`，这是强制要求**

---

## 1. 开启维护模式

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: esxcli system maintenanceMode set --enable true**
**timeout: 1000000**

---

## 2. 关闭维护模式

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: esxcli system maintenanceMode set --enable false**
**timeout: 1000000**

---

## 3. 关闭 ESXi 主机

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: wget -qO- http://mirrors.lpx.com/scripts/esxi/scripts/power-off-esxi.sh | sh**
**timeout: 1000000**

---

## 4. 开启 ESXi 主机

### 步骤 1：使用 wake-on-lan skill 唤醒

```
工具: Skill
skill: wake-on-lan
args: esxi200
```

### 步骤 2：等待主机启动（最多 300 秒）

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: for i in {1..10}; do ping -c 1 192.168.0.200 && break || sleep 30; done**
**timeout: 1000000**

### 步骤 3：等待 30 秒确保系统完全启动

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: sleep 30**
**timeout: 1000000**

### 步骤 4：退出维护模式

**工具: mcp__ssh-mcp-server__execute-command**
**server: 192.168.0.200**
**command: esxcli system maintenanceMode set --enable false**
**timeout: 1000000**

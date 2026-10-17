---
name: pwsh-profile
description: 在 Windows 机器上通过 PowerShell profile 添加持久化的快捷命令（函数/别名）。覆盖 $PROFILE 位置、如何新增函数、如何热重载、以及在 profile 里启动进程/服务的常见坑（如 Start-Process 直接执行 npx.cmd 报 "%1 不是有效的 Win32 应用程序"）。当用户想要"加个快捷命令/别名/封装脚本到终端"、"把某条长命令做成命令"、"管理 PowerShell 启动脚本"时触发。
---

# PowerShell Profile 快捷命令管理

把常用的长命令、服务启停、环境切换封装成**持久化函数**，每次打开终端（pwsh / PowerShell）自动可用。

## 核心概念

`$PROFILE` 是 PowerShell 启动时自动加载的脚本路径。内容会随每个新终端会话自动执行，是放置快捷函数、别名、环境变量的最佳位置。

```powershell
# 查看当前 profile 路径
echo $PROFILE
# 典型路径：C:\Users\<用户>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1

# 如果文件/目录不存在，新建它
if (!(Test-Path $PROFILE)) { New-Item -Path $PROFILE -Type File -Force }
# 编辑
notepad $PROFILE
# 或者用 code / vim
```

**热重载（改完不用重开窗口）：**
```powershell
. $PROFILE        # 点号 + 空格 + 路径 = 在当前作用域重新执行
```

## 添加快捷命令的范式

在 `$PROFILE` 里用一个 `function` 包裹逻辑，比 alias 更强大（可带参数、多语句）：

```powershell
function <名字> {
    param(
        [string]$Arg1,
        [switch]$Force      # 布尔开关：调用时加 -Force
    )
    # 逻辑...
    Write-Host "完成" -ForegroundColor Green
}
```

要点：
- 函数名用小写驼峰或 kebab 风格，避免与已有 cmdlet 冲突（可用 `Get-Command <名字>` 先查）。
- 环境变量在函数里改只影响当前会话，持久化要写回 `$PROFILE` 或用户/系统环境变量。
- 用 `Write-Host -ForegroundColor` 给成功/警告/信息上色，便于辨识。

## 常见坑（必读）

### 坑 1：Start-Process 直接执行 .cmd 报 "%1 不是有效的 Win32 应用程序"

`npx` / `npm` 在 Windows 上其实是 `npx.cmd`、`npm.cmd`（批处理脚本）。
`Start-Process -FilePath "npx"` 会用 `CreateProcess` 直接尝试把它当 PE 可执行文件加载，
加载 `.cmd` 失败返回 `ERROR_BAD_EXE_FORMAT`(193)，PowerShell 翻译成 `%1 不是有效的 Win32 应用程序`。

✅ 修复：让 `cmd.exe /c` 来解释 `.cmd`：
```powershell
# ❌ 错误写法
Start-Process -FilePath "npx" -ArgumentList "--yes","@agegr/pi-web@latest"

# ✅ 正确写法
Start-Process -FilePath "cmd.exe" -ArgumentList "/c","npx","--yes","@agegr/pi-web@latest" -PassThru -WindowStyle Hidden
```

### 坑 2：Start-Process -NoNewWindow 把后台服务日志刷进当前窗口

启动长期运行的服务器时，`-NoNewWindow` 会让它的 stdout/stderr 直接输出到你**正在交互**的窗口，污染且无法干净退出。
✅ 改用 `-WindowStyle Hidden`，进程在后台安静运行，PID 仍可拿到用于停止。

### 坑 3：保存 PID 要用 `$script:` 作用域

在函数里给变量赋值，默认是函数局部作用域，函数返回后丢失，导致 `unset` 时找不到 PID。
✅ 用 `$script:piWebProcess` 把句柄存到脚本作用域（profile 顶层），另一个函数才能读到。

### 坑 4：用命令行内容匹配并杀进程树

`Get-Process` 无法按完整命令行过滤，要用 `Get-CimInstance Win32_Process` 查 `CommandLine`。
杀整棵进程树（含 npx 包装层 + 子 node）用 `taskkill /PID <id> /T /F`，比逐个 `Stop-Process` 可靠。
筛选时排除 shell 自身（`powershell/pwsh/cmd/bash/git-bash`），避免误杀。

### 坑 5：profile 里字符串含 `$` 被提前展开

`$PROXY` 这类要在运行时展开的值，写在双引号里会被立即替换。需要用反引号转义 `` `$ ``，或包成函数延迟求值。
（见 `references/templates.ps1` 的 `set-proxy` 示例。）

## 参考模板

`references/templates.ps1` 提供可直接复制的范式：
- `set-proxy` / `unset-proxy`：一键设置/清除 HTTP(S) 代理（含 `` `$ `` 转义处理）
- `set-pi-web` / `unset-pi-web`：用 `cmd /c` 启动 npx 服务、按命令行匹配杀进程树
- `Get-PiWebProcess`：用 `Get-CimInstance Win32_Process` 按 `CommandLine` 匹配并排除 shell 自身

## 工作流程

1. 确认/新建 `$PROFILE`（`Test-Path` → `New-Item -Force`）。
2. 在 `$PROFILE` 末尾追加一个 `function`；函数名先 `Get-Command` 查冲突。
3. 涉及启动外部命令（尤其 `npx`/`npm`/`node` 等 `.cmd`）：一律用 `cmd.exe /c` 包裹，配 `-WindowStyle Hidden`，PID 用 `$script:` 保存。
4. 需要停止时，按 `CommandLine` 匹配 `Win32_Process` + `taskkill /T /F`。
5. 改完执行 `. $PROFILE` 热重载验证。

## 幂等性建议

如果用户已有同名函数，先读取 `$PROFILE` 内容确认，避免重复追加；必要时用唯一注释标记（如 `# pi-web 服务`）定位并替换整段。

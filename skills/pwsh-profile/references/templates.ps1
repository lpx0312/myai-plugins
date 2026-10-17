#region 代理快速切换
function set-proxy {
    $PROXY_HOST = "192.168.0.225"
    $PROXY_PORT = "7897"
    $env:http_proxy  = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:HTTP_PROXY  = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:https_proxy = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:HTTPS_PROXY = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:ftp_proxy   = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:FTP_PROXY   = "http://$PROXY_HOST`:$PROXY_PORT"
    $env:all_proxy   = "socks5://$PROXY_HOST`:$PROXY_PORT"
    $env:ALL_PROXY   = "socks5://$PROXY_HOST`:$PROXY_PORT"
    $env:no_proxy    = "localhost,192.168.0.0/22,127.0.0.1,::1"
    $env:NO_PROXY    = "localhost,192.168.0.0/22,127.0.0.1,::1"
    Write-Host "代理已开启" -ForegroundColor Green
}

function unset-proxy {
    $env:http_proxy  = $null; $env:HTTP_PROXY  = $null
    $env:https_proxy = $null; $env:HTTPS_PROXY = $null
    $env:ftp_proxy   = $null; $env:FTP_PROXY   = $null
    $env:all_proxy   = $null; $env:ALL_PROXY   = $null
    $env:no_proxy    = $null; $env:NO_PROXY    = $null
    Write-Host "代理已关闭" -ForegroundColor Green
}
#endregion

#region pi-web 服务
# 启动：用 cmd /c 解释 npx(.cmd)，避免 Start-Process 直接执行 .cmd 报
# "%1 不是有效的 Win32 应用程序" (193)。-WindowStyle Hidden 让服务后台安静运行。
function set-pi-web {
    $env:npm_config_registry = "https://registry.npmmirror.com"
    Write-Host "正在启动 pi-web (registry: $env:npm_config_registry) ..." -ForegroundColor Cyan
    $script:piWebProcess = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "npx", "--yes", "@agegr/pi-web@latest" `
        -PassThru -WindowStyle Hidden
    Write-Host "pi-web 已启动 (PID: $($script:piWebProcess.Id))" -ForegroundColor Green
}

# 按命令行匹配 pi-web 相关进程，排除 shell 自身（避免误杀当前终端）
function Get-PiWebProcess {
    Get-CimInstance Win32_Process | Where-Object {
        (($_.CommandLine -match "pi-web") -or ($_.CommandLine -match "@agegr")) -and
        ($_.Name -notmatch "^(powershell|pwsh|cmd|bash|git-bash)\.exe$")
    } | Select-Object -ExpandProperty ProcessId
}

# 停止：taskkill /T 杀整棵进程树（含 npx 包装层与子 node），/F 强制
function unset-pi-web {
    $pids = Get-PiWebProcess
    if ($pids.Count -eq 0) {
        Write-Host "未检测到正在运行的 pi-web 进程" -ForegroundColor Yellow
    } else {
        foreach ($p in $pids) {
            & taskkill /PID $p /T /F | Out-Null
            Write-Host "已停止 pi-web 进程树 (PID: $p)" -ForegroundColor Green
        }
    }
    $script:piWebProcess = $null
    $env:npm_config_registry = $null
    Write-Host "npm registry 已重置" -ForegroundColor Green
}
#endregion

#!/usr/bin/env pwsh
# add-profile-fn.ps1
# 幂等地把一个快捷函数追加/更新到 $PROFILE。
# 用法：
#   pwsh add-profile-fn.ps1 -Name "set-pi-web" -BodyFile "func_body.ps1" [-Marker "# pi-web 服务"]
#
# 原理：用唯一 Marker 注释定位旧段落，存在则整段替换，不存在则追加，避免重复。

param(
    [Parameter(Mandatory = $true)]  [string] $Name,        # 函数名
    [Parameter(Mandatory = $true)]  [string] $BodyFile,    # 包含 function X { ... } 的文件
    [string] $Marker = "# $Name",                           # 定位标记
    [string] $ProfilePath = $PROFILE
)

if (!(Test-Path $ProfilePath)) {
    New-Item -Path $ProfilePath -Type File -Force | Out-Null
    Write-Host "已创建 profile: $ProfilePath" -ForegroundColor Green
}

$body = Get-Content -Raw -Path $BodyFile
$profileText = Get-Content -Raw -Path $ProfilePath

$startTag = "#region $Marker"
$endTag   = "#endregion"

# 检查是否已存在带 Marker 的段落
$existing = $profileText -match [regex]::Escape($startTag)
if ($existing) {
    # 用正则替换从 #region Marker 到 #endregion 的整段
    $pattern = "(?s)$([regex]::Escape($startTag)).*?$([regex]::Escape($endTag))"
    $replacement = "$startTag`n$body`n$endTag"
    $profileText = [regex]::Replace($profileText, $pattern, $replacement)
    Write-Host "已更新 profile 中的 $Name" -ForegroundColor Yellow
} else {
    # 追加新段
    $newBlock = "`n$startTag`n$body`n$endTag`n"
    if ($profileText.Length -gt 0 -and !$profileText.EndsWith("`n")) { $newBlock = "`n$newBlock" }
    $profileText += $newBlock
    Write-Host "已追加 $Name 到 profile" -ForegroundColor Green
}

Set-Content -Path $ProfilePath -Value $profileText -NoNewline
Write-Host "完成。执行 '. `$PROFILE' 热重载即可使用 $Name" -ForegroundColor Cyan

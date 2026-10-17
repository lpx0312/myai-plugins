param(
    [string]$Root,
    [string]$Pattern,
    [string]$FullPath,
    [string]$Created,
    [string]$Modified
)

# Keep this script ASCII-only: PowerShell 5.1 misreads UTF-8 without BOM as ANSI.
# Chinese characters are safe as command-line arguments (passed as UTF-16), so a
# non-ASCII FullPath is fine; just never write non-ASCII text inside this file.

if ($FullPath) {
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        Write-Output 'FILE NOT FOUND'
        exit 1
    }
    $files = @(Get-Item -LiteralPath $FullPath)
} else {
    if (-not $Root -or -not $Pattern) {
        Write-Output 'MISSING ARGS: pass either -FullPath or both -Root and -Pattern'
        exit 3
    }
    $files = @(Get-ChildItem -Path $Root -Recurse -Filter $Pattern -File -ErrorAction SilentlyContinue)
}

if ($files.Count -eq 0) {
    Write-Output 'FILE NOT FOUND'
    exit 1
}
if ($files.Count -gt 1) {
    Write-Output 'MULTIPLE MATCHES:'
    $files | ForEach-Object { Write-Output "  $($_.FullName)" }
    exit 2
}

$f = $files[0]
if ($Created)  { $f.CreationTime  = Get-Date $Created }
if ($Modified) {
    $t = Get-Date $Modified
    $f.LastWriteTime  = $t
    $f.LastAccessTime = $t
}

Write-Output "Updated: $($f.FullName)"
$f | Select-Object FullName, CreationTime, LastWriteTime, LastAccessTime | Format-List

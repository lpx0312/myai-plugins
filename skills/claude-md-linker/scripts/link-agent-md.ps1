<#
.SYNOPSIS
  Link Claude Code's global instruction file (CLAUDE.md) into other AI agents'
  global instruction files (AGENTS.md / GEMINI.md / QWEN.md / ...) using Windows
  symbolic links, so one edit in CLAUDE.md stays in sync everywhere.

.DESCRIPTION
  For each target file:
    - if it is already a symlink pointing at the source  -> report OK
    - otherwise back it up (unless -NoBackup), remove it, and create a symlink
    - target whose parent directory does not exist is skipped (agent not installed)
      unless -CreateDirs is given

  Creating a Windows symlink needs SeCreateSymbolicLinkPrivilege, which is granted
  by an elevated token OR by enabling Windows Developer Mode. If neither is
  available, this script relaunches itself elevated (UAC prompt) unless -NoElevate.

  This file is intentionally ASCII-only: Windows PowerShell 5.1 reads a non-BOM
  UTF-8 script as ANSI/GBK, which would garble any non-ASCII literal.

.PARAMETER Source
  Master instruction file. Default: %USERPROFILE%\.claude\CLAUDE.md

.PARAMETER Targets
  One or more target paths. Default: the known list of agent global files.

.PARAMETER DryRun
  Show what would happen without changing anything.

.PARAMETER NoElevate
  Never relaunch elevated. Tries to create links in-process (works when
  Developer Mode is on) and reports per-target errors otherwise.

.PARAMETER NoBackup
  Do not keep a .bak_<timestamp> copy of a replaced regular file.

.PARAMETER CreateDirs
  Also process targets whose parent directory does not exist (creates dirs).

.PARAMETER Elevated
  Internal switch used for the elevated relaunch. Do not pass manually.

.PARAMETER LogFile
  Internal: write the report lines to this file (used to carry output back from
  the elevated child process, since RunAs cannot redirect stdout).

.EXAMPLE
  pwsh -File link-agent-md.ps1
  Link the default source into every default target that exists.

.EXAMPLE
  pwsh -File link-agent-md.ps1 -DryRun
  Preview the plan.

.EXAMPLE
  pwsh -File link-agent-md.ps1 -Targets "$env:USERPROFILE\.foo\MY.md"
  Link a custom target.
#>
[CmdletBinding()]
param(
    [string]$Source = "$env:USERPROFILE\.claude\CLAUDE.md",
    [string[]]$Targets,
    [switch]$DryRun,
    [switch]$NoElevate,
    [switch]$NoBackup,
    [switch]$CreateDirs,
    [switch]$Elevated,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Default target list: known global instruction files of common AI agents.
# Targets whose parent directory is missing are skipped (agent not installed).
# ---------------------------------------------------------------------------
$defaultTargets = @(
    "$env:USERPROFILE\.codex\AGENTS.md",
    "$env:USERPROFILE\.zcode\AGENTS.md",
    "$env:USERPROFILE\.pi\agent\AGENTS.md",
    "$env:USERPROFILE\.config\opencode\AGENTS.md",
    "$env:USERPROFILE\.gemini\GEMINI.md",
    "$env:USERPROFILE\.qwen\QWEN.md",
    "$env:USERPROFILE\.iflow\IFLOW.md",
    "$env:USERPROFILE\.cursor\AGENTS.md",
    "$env:USERPROFILE\.cline\AGENTS.md",
    "$env:USERPROFILE\.copilot\AGENTS.md",
    "$env:USERPROFILE\.amazonq\AGENTS.md"
)
if (-not $Targets -or $Targets.Count -eq 0) { $Targets = $defaultTargets }

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
$script:Report = New-Object System.Collections.Generic.List[string]
function Emit([string]$line) {
    Write-Host $line
    if ($LogFile) { $script:Report.Add($line) | Out-Null }
}
function FlushLog() {
    if ($LogFile) {
        try { Set-Content -LiteralPath $LogFile -Value ($script:Report -join [Environment]::NewLine) -Encoding UTF8 } catch {}
    }
}

# ---------------------------------------------------------------------------
# Can we create a symlink in this process? (Developer Mode or elevated token)
# ---------------------------------------------------------------------------
function Test-CanCreateSymlink {
    $probe = Join-Path $env:TEMP ('slprobe_' + [guid]::NewGuid().ToString('N') + '.txt')
    $link  = $probe + '.lnk'
    try {
        New-Item -ItemType File -Path $probe -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $probe -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $link  -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Relaunch elevated once, if needed, and relay the child's report.
# ---------------------------------------------------------------------------
if (-not $DryRun -and -not $NoElevate -and -not $Elevated -and -not (Test-CanCreateSymlink)) {
    $log = Join-Path $env:TEMP ('claude-md-linker_' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')
    $parts = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
        '-Source', ('"' + $Source + '"'),
        '-Elevated', '-LogFile', ('"' + $log + '"')
    )
    if ($PSBoundParameters.ContainsKey('Targets') -and $Targets) {
        $parts += '-Targets'
        foreach ($t in $Targets) { $parts += ('"' + $t + '"') }
    }
    if ($NoBackup)   { $parts += '-NoBackup' }
    if ($CreateDirs) { $parts += '-CreateDirs' }

    Write-Host 'Symlink creation needs administrator rights (UAC prompt) or Windows Developer Mode.'
    Write-Host 'Requesting elevation...'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList ($parts -join ' ')
    } catch {
        Write-Host ''
        Write-Host ('Elevation cancelled or failed: ' + $_.Exception.Message)
        Write-Host 'Options: enable Windows Developer Mode, run an elevated shell, or re-run with -NoElevate.'
        exit 2
    }
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Validate source
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Source)) {
    Emit ('ERROR   source not found: ' + $Source)
    FlushLog
    exit 1
}
$srcFull = (Get-Item -LiteralPath $Source -Force).FullName

$mode = 'non-elevated'
if ($Elevated) { $mode = 'elevated' } elseif (Test-CanCreateSymlink) { $mode = 'developer-mode' }
Emit ('SOURCE  ' + $srcFull)
Emit ('MODE    ' + $mode)
Emit ''

# ---------------------------------------------------------------------------
# Process each target
# ---------------------------------------------------------------------------
foreach ($target in $Targets) {
    $t = [Environment]::ExpandEnvironmentVariables($target)
    $parent = Split-Path -Parent $t

    if (-not (Test-Path -LiteralPath $parent)) {
        if ($CreateDirs) {
            if ($DryRun) { Emit ('DRY     would create dir: ' + $parent) }
            else {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
                Emit ('MKDIR   ' + $parent)
            }
        } else {
            Emit ('SKIP    ' + $t + '  (agent dir not found: ' + $parent + ')')
            continue
        }
    }

    $existing = Get-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue

    if ($existing -and $existing.PSIsContainer) {
        Emit ('ERROR   ' + $t + '  (path is a directory, refusing to touch it)')
        continue
    }

    if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
        $cur = $existing.Target
        if ($cur -is [array]) { $cur = $cur[0] }
        $curFull = $null
        if ($cur) { try { $curFull = [IO.Path]::GetFullPath($cur) } catch { $curFull = $cur } }
        if ($curFull -and $curFull -eq $srcFull) {
            Emit ('OK      ' + $t + '  (already linked)')
            continue
        }
        Emit ('REPLACE ' + $t + '  (was symlink -> ' + $cur + ')')
    } elseif ($existing) {
        $lt = $existing.LinkType
        if (-not $lt) { $lt = 'file' }
        Emit ('REPLACE ' + $t + '  (was ' + $lt + ')')
    } else {
        Emit ('CREATE  ' + $t)
    }

    if ($DryRun) {
        Emit ('DRY     would link ' + $t + ' -> ' + $srcFull)
        continue
    }

    if ($existing -and -not $NoBackup -and $existing.LinkType -ne 'SymbolicLink') {
        $bak = $t + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
        try {
            Copy-Item -LiteralPath $t -Destination $bak -Force
            Emit ('BACKUP  ' + $bak)
        } catch {
            Emit ('WARN    could not back up ' + $t + ' : ' + $_.Exception.Message)
        }
    }

    if ($existing) {
        try { Remove-Item -LiteralPath $t -Force -Recurse } catch {
            Emit ('ERROR   cannot remove ' + $t + ' : ' + $_.Exception.Message)
            continue
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $t -Target $srcFull -ErrorAction Stop | Out-Null
        $check = Get-Item -LiteralPath $t -Force
        if ($check.LinkType -eq 'SymbolicLink') {
            Emit ('LINKED  ' + $t + ' -> ' + $srcFull)
        } else {
            Emit ('WARN    ' + $t + ' created but LinkType=' + $check.LinkType)
        }
    } catch {
        Emit ('ERROR   ' + $t + ' : ' + $_.Exception.Message)
    }
}

Emit ''
Emit 'Done.'
FlushLog

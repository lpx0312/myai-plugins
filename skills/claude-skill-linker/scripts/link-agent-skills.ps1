<#
.SYNOPSIS
  Link Claude Code's global skills directory (%USERPROFILE%\.claude\skills) into
  other AI agents' skill directories, so every agent shares one copy of the
  skills and a single edit in ~/.claude/skills stays in sync everywhere.

.DESCRIPTION
  Two linking strategies:

    Whole     one link:  <agent>\skills  ->  ~/.claude/skills
              Simplest, zero maintenance. Replaces an existing real directory
              of that agent (backed up first) because a link cannot live next
              to real content.

    PerSkill  one link per skill:
              <agent>\skills\<skill>  ->  ~/.claude/skills\<skill>
              Keeps the agent's own private skills intact; only skills that
              exist under ~/.claude/skills are linked in.

  Auto (default): Whole when the target skills path is absent or already a
  link, PerSkill when the target exists as a real directory.

  Link type:
    SymbolicLink  needs SeCreateSymbolicLinkPrivilege (elevated token or
                  Windows Developer Mode).
    Junction      NTFS directory junction, NO administrator rights needed, but
                  only for local paths (not network shares).
  Auto (default) picks SymbolicLink when available and falls back to Junction.

  This file is intentionally ASCII-only: Windows PowerShell 5.1 reads a
  non-BOM UTF-8 script as ANSI/GBK, which would garble any non-ASCII literal.

.PARAMETER Source
  Source skills directory. Default: %USERPROFILE%\.claude\skills

.PARAMETER Targets
  Custom target skill directories (full paths). Overrides the built-in agent
  table. Example: "$env:USERPROFILE\.foo\skills"

.PARAMETER Agents
  Only process these agents from the built-in table (e.g. -Agents Codex,Cursor).

.PARAMETER Mode
  Auto | Whole | PerSkill. Default: Auto.

.PARAMETER LinkType
  Auto | SymbolicLink | Junction. Default: Auto.

.PARAMETER Include
  Skill name wildcards to link. Default: *

.PARAMETER Exclude
  Skill name wildcards to skip. Default: .system

.PARAMETER DryRun
  Show the plan, change nothing.

.PARAMETER NoBackup
  Delete existing content instead of moving it to <name>.bak_<timestamp>.

.PARAMETER NoElevate
  Never relaunch elevated (only relevant when -LinkType SymbolicLink is forced
  and the current process cannot create symlinks).

.PARAMETER CreateDirs
  Also process targets whose parent (agent) directory does not exist.

.PARAMETER Prune
  In PerSkill mode, remove links inside the target dir that point into the
  source but whose skill no longer exists.

.PARAMETER Elevated
  Internal switch used for the elevated relaunch. Do not pass manually.

.PARAMETER LogFile
  Internal: write report lines to this file (carries output back from the
  elevated child process, since RunAs cannot redirect stdout).

.EXAMPLE
  pwsh -File link-agent-skills.ps1 -DryRun
  Preview what would be linked.

.EXAMPLE
  pwsh -File link-agent-skills.ps1
  Link ~/.claude/skills into every installed agent.

.EXAMPLE
  pwsh -File link-agent-skills.ps1 -Mode PerSkill -Prune
  Per-skill links only, and clean up stale ones.
#>
[CmdletBinding()]
param(
    [string]$Source = "$env:USERPROFILE\.claude\skills",
    [string[]]$Targets,
    [string[]]$Agents,
    [ValidateSet('Auto', 'Whole', 'PerSkill')][string]$Mode = 'Auto',
    [ValidateSet('Auto', 'SymbolicLink', 'Junction')][string]$LinkType = 'Auto',
    [string[]]$Include = @('*'),
    [string[]]$Exclude = @('.system'),
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$NoElevate,
    [switch]$CreateDirs,
    [switch]$Prune,
    [switch]$Elevated,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Accept comma / semicolon separated lists too, because "-File script.ps1
# -Targets a,b,c" binds the whole string as ONE element under -File.
# ---------------------------------------------------------------------------
function Split-List([string[]]$values) {
    $out = @()
    foreach ($v in $values) {
        if (-not $v) { continue }
        foreach ($part in ($v -split '[;,]')) {
            $p = $part.Trim()
            if ($p) { $out += $p }
        }
    }
    return $out
}
$Targets = Split-List $Targets
$Agents = Split-List $Agents

# ---------------------------------------------------------------------------
# Built-in agent table. Dir = agent config dir, Sub = candidate skill-dir names
# (the first existing one wins; otherwise the first one is used).
# Agents whose config dir does not exist are skipped (not installed).
# ---------------------------------------------------------------------------
$agentSpecs = @(
    @{ Name = 'Codex';          Dir = "$env:USERPROFILE\.codex";           Sub = @('skills') },
    @{ Name = 'ZCode';          Dir = "$env:USERPROFILE\.zcode";           Sub = @('skills') },
    @{ Name = 'Pi';             Dir = "$env:USERPROFILE\.pi\agent";        Sub = @('skills') },
    @{ Name = 'DSH';            Dir = "$env:USERPROFILE\.dsh";             Sub = @('skills') },
    @{ Name = 'Agents';         Dir = "$env:USERPROFILE\.agents";          Sub = @('skills') },
    @{ Name = 'OpenCode';       Dir = "$env:USERPROFILE\.config\opencode"; Sub = @('skill', 'skills') },
    @{ Name = 'Gemini CLI';     Dir = "$env:USERPROFILE\.gemini";          Sub = @('skills') },
    @{ Name = 'Qwen Code';      Dir = "$env:USERPROFILE\.qwen";            Sub = @('skills') },
    @{ Name = 'iFlow';          Dir = "$env:USERPROFILE\.iflow";           Sub = @('skills') },
    @{ Name = 'Cursor';         Dir = "$env:USERPROFILE\.cursor";          Sub = @('skills') },
    @{ Name = 'Cline';          Dir = "$env:USERPROFILE\.cline";           Sub = @('skills') },
    @{ Name = 'GitHub Copilot'; Dir = "$env:USERPROFILE\.copilot";         Sub = @('skills') },
    @{ Name = 'Amazon Q';       Dir = "$env:USERPROFILE\.aws\amazonq";     Sub = @('skills') },
    @{ Name = 'CodeBuddy';      Dir = "$env:USERPROFILE\.codebuddy";       Sub = @('skills') },
    @{ Name = 'WorkBuddy';      Dir = "$env:USERPROFILE\.workbuddy";       Sub = @('skills') },
    @{ Name = 'Qoder';          Dir = "$env:USERPROFILE\.qoder";           Sub = @('skills') },
    @{ Name = 'Trae CN';        Dir = "$env:USERPROFILE\.trae-cn";         Sub = @('skills') }
)

# ---------------------------------------------------------------------------
# Reporting / stats
# ---------------------------------------------------------------------------
$script:Report = New-Object System.Collections.Generic.List[string]
$script:Stats = @{
    OK = 0; CREATE = 0; LINKED = 0; REPLACE = 0; PRUNE = 0
    SKIP = 0; ERROR = 0; WARN = 0; BACKUP = 0; MKDIR = 0; DRY = 0
}

function Emit([string]$line) {
    Write-Host $line
    if ($LogFile) { $script:Report.Add($line) | Out-Null }
}
function Status([string]$tag, [string]$msg) {
    if ($script:Stats.ContainsKey($tag)) { $script:Stats[$tag] = $script:Stats[$tag] + 1 }
    Emit (('{0,-8}{1}' -f $tag, $msg))
}
function FlushLog() {
    if ($LogFile) {
        try { Set-Content -LiteralPath $LogFile -Value ($script:Report -join [Environment]::NewLine) -Encoding UTF8 } catch {}
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Normalize([string]$p) {
    if (-not $p) { return $null }
    $p = $p.Trim()
    if ($p.StartsWith('\\?\')) { $p = $p.Substring(4) }
    try { $p = [IO.Path]::GetFullPath($p) } catch {}
    return $p.TrimEnd('\', '/')
}

function Get-LinkInfo($item) {
    if (-not $item) { return (New-Object psobject -Property @{ IsLink = $false; LinkType = $null; Target = $null }) }
    $lt = $null
    try { $lt = $item.LinkType } catch {}
    if (-not $lt -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $lt = 'ReparsePoint' }
    $target = $null
    if ($lt) {
        try {
            $t = $item.Target
            if ($t -is [array]) { $t = $t[0] }
            if ($t) { $target = [string]$t }
        } catch {}
    }
    return (New-Object psobject -Property @{ IsLink = [bool]$lt; LinkType = $lt; Target = $target })
}

# Delete a reparse point WITHOUT touching what it points at.
function Remove-LinkOnly([string]$path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    if ($item.PSIsContainer) { [IO.Directory]::Delete($path, $false) }
    else { [IO.File]::Delete($path) }
}

function Backup-Path([string]$path) {
    $bak = $path + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
    try {
        Move-Item -LiteralPath $path -Destination $bak -Force -ErrorAction Stop
        Status 'BACKUP' ($bak + '  (moved aside)')
        return $true
    } catch {
        Status 'WARN' ('could not move aside ' + $path + ' : ' + $_.Exception.Message)
        return $false
    }
}

function Test-WildcardList([string]$name, [string[]]$patterns) {
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }
    return $false
}

function Get-SourceSkills {
    $res = @()
    $items = Get-ChildItem -LiteralPath $script:SrcFull -Directory -Force -ErrorAction SilentlyContinue
    foreach ($i in $items) {
        $n = $i.Name
        if ($n.StartsWith('.')) { continue }
        if (-not (Test-WildcardList $n $Include)) { continue }
        if (Test-WildcardList $n $Exclude) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $i.FullName 'SKILL.md'))) { continue }
        $res += $i
    }
    return $res
}

function Test-CanCreateSymlink {
    $probe = Join-Path $env:TEMP ('slprobe_' + [guid]::NewGuid().ToString('N'))
    $lnk = $probe + '_lnk'
    try {
        New-Item -ItemType Directory -Path $probe -Force -ErrorAction Stop | Out-Null
        New-Item -ItemType SymbolicLink -Path $lnk -Target $probe -ErrorAction Stop | Out-Null
        [IO.Directory]::Delete($lnk, $false)
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-DirLink([string]$path, [string]$target) {
    if ($script:EffectiveType -eq 'Junction') {
        New-Item -ItemType Junction -Path $path -Target $target -ErrorAction Stop | Out-Null
        return 'Junction'
    }
    try {
        New-Item -ItemType SymbolicLink -Path $path -Target $target -ErrorAction Stop | Out-Null
        return 'SymbolicLink'
    } catch {
        if ($script:AllowJunctionFallback) {
            Emit ('WARN    symlink failed (' + $_.Exception.Message + '), falling back to junction')
            New-Item -ItemType Junction -Path $path -Target $target -ErrorAction Stop | Out-Null
            return 'Junction'
        }
        throw
    }
}

# ---------------------------------------------------------------------------
# Can we create symlinks here? Decide the effective link type.
# ---------------------------------------------------------------------------
$script:CanSymlink = Test-CanCreateSymlink
if ($LinkType -eq 'Junction') {
    $script:EffectiveType = 'Junction'
    $script:AllowJunctionFallback = $false
} elseif ($LinkType -eq 'SymbolicLink') {
    $script:EffectiveType = 'SymbolicLink'
    $script:AllowJunctionFallback = $false
} elseif ($script:CanSymlink) {
    $script:EffectiveType = 'SymbolicLink'
    $script:AllowJunctionFallback = $true
} else {
    $script:EffectiveType = 'Junction'
    $script:AllowJunctionFallback = $true
}

# ---------------------------------------------------------------------------
# Relaunch elevated once (only if SymbolicLink is explicitly forced).
# ---------------------------------------------------------------------------
if ($LinkType -eq 'SymbolicLink' -and -not $script:CanSymlink -and -not $NoElevate -and -not $Elevated -and -not $DryRun) {
    $log = Join-Path $env:TEMP ('claude-skill-linker_' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')
    $parts = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
        '-Source', ('"' + $Source + '"'),
        '-Mode', $Mode, '-LinkType', 'SymbolicLink',
        '-Elevated', '-LogFile', ('"' + $log + '"')
    )
    if ($Targets) { $parts += '-Targets'; foreach ($t in $Targets) { $parts += ('"' + $t + '"') } }
    if ($Agents) { $parts += '-Agents'; foreach ($a in $Agents) { $parts += ('"' + $a + '"') } }
    if ($NoBackup)   { $parts += '-NoBackup' }
    if ($CreateDirs) { $parts += '-CreateDirs' }
    if ($Prune)      { $parts += '-Prune' }

    Write-Host 'Forced -LinkType SymbolicLink needs administrator rights (UAC prompt) or Windows Developer Mode.'
    Write-Host 'Requesting elevation...'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList ($parts -join ' ')
    } catch {
        Write-Host ''
        Write-Host ('Elevation cancelled or failed: ' + $_.Exception.Message)
        Write-Host 'Options: drop -LinkType (Auto uses junctions, no elevation), enable Developer Mode, or run an elevated shell.'
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
    Status 'ERROR' ('source not found: ' + $Source)
    FlushLog
    exit 1
}
$script:SrcFull = Normalize ((Get-Item -LiteralPath $Source -Force).FullName)

$linkTypeNote = $script:EffectiveType
if ($script:EffectiveType -eq 'SymbolicLink' -and $script:AllowJunctionFallback) {
    $linkTypeNote = 'SymbolicLink (falls back to Junction)'
} elseif ($script:EffectiveType -eq 'Junction' -and -not $script:CanSymlink -and $LinkType -eq 'Auto') {
    $linkTypeNote = 'Junction (no symlink privilege here, no elevation needed)'
}

Emit ('SOURCE   ' + $script:SrcFull)
Emit ('LINKTYPE ' + $linkTypeNote)
Emit ('MODE     ' + $Mode)
if ($DryRun) { Emit 'DRYRUN   nothing will be changed' }

# ---------------------------------------------------------------------------
# Resolve target list
# ---------------------------------------------------------------------------
$resolved = @()
if ($Targets) {
    foreach ($t in $Targets) {
        $resolved += @{ Name = 'custom'; TargetPath = [Environment]::ExpandEnvironmentVariables($t) }
    }
} else {
    foreach ($spec in $agentSpecs) {
        if ($Agents -and -not ($Agents -contains $spec.Name)) { continue }
        $dir = [Environment]::ExpandEnvironmentVariables($spec.Dir)
        $chosen = $null
        if (Test-Path -LiteralPath $dir) {
            foreach ($n in $spec.Sub) {
                if (Test-Path -LiteralPath (Join-Path $dir $n)) { $chosen = $n; break }
            }
        }
        if (-not $chosen) { $chosen = $spec.Sub[0] }
        $resolved += @{ Name = $spec.Name; TargetPath = (Join-Path $dir $chosen) }
    }
}

# ---------------------------------------------------------------------------
# Whole-directory linking
# ---------------------------------------------------------------------------
function Process-Whole([string]$targetPath, $existing, $info) {
    $action = 'CREATE'
    $note = ''
    if ($existing) {
        if ($info.IsLink) {
            $cur = Normalize $info.Target
            if ($cur -and ($cur -ieq $script:SrcFull)) { Status 'OK' ($targetPath + '  (already linked)'); return }
            $action = 'REPLACE'
            $note = '  (was ' + $info.LinkType + ' -> ' + $info.Target + ')'
        } else {
            $action = 'REPLACE'
            $note = '  (was a real directory)'
        }
    }

    if ($DryRun) { Status 'DRY' ($action + ' link ' + $targetPath + ' -> ' + $script:SrcFull + $note); return }
    Status $action ($targetPath + $note)

    if ($existing) {
        if ($info.IsLink) {
            Remove-LinkOnly $targetPath
        } else {
            if (-not $NoBackup) {
                if (-not (Backup-Path $targetPath)) {
                    Status 'ERROR' ($targetPath + '  (backup failed, left untouched)')
                    return
                }
            }
            if (Test-Path -LiteralPath $targetPath) {
                Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $used = New-DirLink $targetPath $script:SrcFull
        $chk = Get-LinkInfo (Get-Item -LiteralPath $targetPath -Force)
        if ($chk.IsLink) { Status 'LINKED' ($targetPath + ' -> ' + $script:SrcFull + '  [' + $used + ']') }
        else { Status 'WARN' ($targetPath + '  created but is not a link') }
    } catch {
        Status 'ERROR' ($targetPath + ' : ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Per-skill linking
# ---------------------------------------------------------------------------
function Prune-Target([string]$targetPath, [string[]]$keep) {
    $items = Get-ChildItem -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    foreach ($i in $items) {
        if ($keep -contains $i.Name) { continue }
        $ii = Get-LinkInfo $i
        if (-not $ii.IsLink) { continue }
        $cur = Normalize $ii.Target
        if (-not $cur) { continue }
        if (-not $cur.ToLowerInvariant().StartsWith($script:SrcFull.ToLowerInvariant())) { continue }
        if ($DryRun) { Status 'PRUNE' ($i.FullName + '  (would remove stale link -> ' + $ii.Target + ')'); continue }
        try {
            Remove-LinkOnly $i.FullName
            Status 'PRUNE' ($i.FullName + '  (stale link removed)')
        } catch {
            Status 'ERROR' ($i.FullName + ' : ' + $_.Exception.Message)
        }
    }
}

function Process-PerSkill([string]$targetPath, $existing, $info) {
    if ($existing -and $info.IsLink) {
        $cur = Normalize $info.Target
        if ($cur -and ($cur -ieq $script:SrcFull)) {
            Status 'OK' ($targetPath + '  (already whole-linked; nothing to do)')
            return
        }
        Status 'ERROR' ($targetPath + '  (is a link to ' + $info.Target + '); refusing per-skill linking, use -Mode Whole')
        return
    }
    if ($existing -and -not $existing.PSIsContainer) {
        Status 'ERROR' ($targetPath + '  (path is a file)')
        return
    }

    if (-not $existing) {
        if ($DryRun) {
            Status 'DRY' ('would create dir: ' + $targetPath)
        } else {
            try {
                New-Item -ItemType Directory -Path $targetPath -Force -ErrorAction Stop | Out-Null
                Status 'MKDIR' $targetPath
            } catch {
                Status 'ERROR' ('cannot create ' + $targetPath + ' : ' + $_.Exception.Message)
                return
            }
        }
    }

    $skills = Get-SourceSkills
    $keep = @()
    foreach ($s in $skills) {
        $name = $s.Name
        $srcSkill = Normalize $s.FullName
        $link = Join-Path $targetPath $name
        $keep += $name

        $ex = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        $ei = Get-LinkInfo $ex
        $action = 'CREATE'
        $note = ''
        if ($ex) {
            if ($ei.IsLink) {
                $cur = Normalize $ei.Target
                if ($cur -and ($cur -ieq $srcSkill)) { Status 'OK' $link; continue }
                $action = 'REPLACE'
                $note = '  (was ' + $ei.LinkType + ' -> ' + $ei.Target + ')'
            } elseif ($ex.PSIsContainer) {
                $action = 'REPLACE'
                $note = '  (was a real directory)'
            } else {
                $action = 'REPLACE'
                $note = '  (was a real file)'
            }
        }

        if ($DryRun) { Status 'DRY' ($action + ' link ' + $link + ' -> ' + $srcSkill + $note); continue }
        Status $action ($link + $note)

        if ($ex) {
            if ($ei.IsLink) {
                Remove-LinkOnly $link
            } else {
                if (-not $NoBackup) {
                    if (-not (Backup-Path $link)) {
                        Status 'ERROR' ($link + '  (backup failed, left untouched)')
                        continue
                    }
                }
                if (Test-Path -LiteralPath $link) {
                    Remove-Item -LiteralPath $link -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        try {
            $used = New-DirLink $link $srcSkill
            $chk = Get-LinkInfo (Get-Item -LiteralPath $link -Force)
            if ($chk.IsLink) { Status 'LINKED' ($link + ' -> ' + $srcSkill + '  [' + $used + ']') }
            else { Status 'WARN' ($link + '  created but is not a link') }
        } catch {
            Status 'ERROR' ($link + ' : ' + $_.Exception.Message)
        }
    }

    if ($Prune) { Prune-Target $targetPath $keep }
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
function Process-Target([string]$name, [string]$targetPath) {
    Emit ''
    Emit ('===> ' + $name)
    Emit ('     ' + $targetPath)

    $parent = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $parent)) {
        if (-not $CreateDirs) {
            Status 'SKIP' ($targetPath + '  (agent dir not found: ' + $parent + ')')
            return
        }
        if ($DryRun) {
            Status 'DRY' ('would create dir: ' + $parent)
        } else {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Status 'MKDIR' $parent
        }
    }

    $existing = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    $info = Get-LinkInfo $existing

    $effMode = $Mode
    if ($effMode -eq 'Auto') {
        if ($existing -and -not $info.IsLink) { $effMode = 'PerSkill' } else { $effMode = 'Whole' }
    }
    Emit ('       mode: ' + $effMode)

    if ($effMode -eq 'Whole') { Process-Whole $targetPath $existing $info }
    else { Process-PerSkill $targetPath $existing $info }
}

foreach ($r in $resolved) { Process-Target $r.Name $r.TargetPath }

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Emit ''
$summaryFmt = 'SUMMARY  ok={0} create={1} linked={2} replace={3} prune={4} skip={5} error={6}'
Emit ($summaryFmt -f $script:Stats['OK'], $script:Stats['CREATE'], $script:Stats['LINKED'], $script:Stats['REPLACE'], $script:Stats['PRUNE'], $script:Stats['SKIP'], $script:Stats['ERROR'])
Emit 'Done.'
FlushLog

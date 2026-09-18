# sync-cfe.ps1 - sync empty src/cfe folders and repository.json cfe section
<#
.SYNOPSIS
    Syncs empty src/cfe directories and repository.json cfe keys
    with names from live_extensions_list (-ExtensionNames).
    Does not launch Enterprise / vrunner infobase extensions list by default.

.EXAMPLE
    .\sync-cfe.ps1 -ProjectRoot . -ExtensionNames @("MyExt","Other")
.EXAMPLE
    .\sync-cfe.ps1 -ProjectRoot . -DryRun
.EXAMPLE
    .\sync-cfe.ps1 -ProjectRoot . -UseVrunnerList
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string[]]$ExtensionNames,

    [Parameter(Mandatory = $false)]
    [switch]$Prune,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$SkipIb,

    [Parameter(Mandatory = $false)]
    [switch]$UseVrunnerList
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfeDir = Join-Path $ProjectRoot "src\cfe"
$repoPath = Join-Path $ProjectRoot "repository.json"
$autumnPath = Join-Path $ProjectRoot "autumn-properties.json"

function Get-RepoCfeKeys {
    if (-not (Test-Path -LiteralPath $repoPath)) { return @() }
    try {
        $j = Get-Content -LiteralPath $repoPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.cfe) {
            return @($j.cfe.PSObject.Properties.Name)
        }
    } catch {}
    return @()
}

function Get-SrcCfeFolders {
    if (-not (Test-Path -LiteralPath $cfeDir -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $cfeDir -Directory -Force |
            Where-Object { $_.Name -notmatch '^\.' } |
            ForEach-Object { $_.Name }
    )
}

$NotInRepository = @("NinjaLive")

function Test-RepoManagedName {
    param([string]$Name)
    if (-not $Name) { return $false }
    return ($NotInRepository -notcontains $Name)
}

function Get-IbExtensionsViaVrunner {
    Write-Host "Warning: -UseVrunnerList launches Enterprise; canonical list is live_extensions_list" -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $autumnPath)) {
        Write-Host "Warning: autumn-properties.json missing - skip IB list" -ForegroundColor Yellow
        return @()
    }
    try {
        Push-Location $ProjectRoot
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $raw = & vrunner infobase extensions list --json 2>&1 | Out-String
        $ErrorActionPreference = $prevEap
        Pop-Location

        $names = New-Object System.Collections.Generic.List[string]
        $trimmed = $raw.Trim()
        if ($trimmed -match '^\s*[\[{]') {
            try {
                $parsed = $trimmed | ConvertFrom-Json
                if ($parsed -is [System.Array]) {
                    foreach ($item in $parsed) {
                        if ($item.name) { [void]$names.Add([string]$item.name) }
                        elseif ($item.Name) { [void]$names.Add([string]$item.Name) }
                        elseif ($item -is [string]) { [void]$names.Add($item) }
                    }
                } elseif ($parsed.extensions) {
                    foreach ($item in @($parsed.extensions)) {
                        if ($item.name) { [void]$names.Add([string]$item.name) }
                        elseif ($item -is [string]) { [void]$names.Add($item) }
                    }
                } elseif ($parsed.PSObject.Properties.Name -contains "data") {
                    foreach ($item in @($parsed.data)) {
                        if ($item.name) { [void]$names.Add([string]$item.name) }
                        elseif ($item -is [string]) { [void]$names.Add($item) }
                    }
                }
            } catch {}
        }

        if ($names.Count -eq 0) {
            foreach ($line in ($raw -split "`r?`n")) {
                $line = $line.Trim().Trim('"')
                if (-not $line) { continue }
                if ($line -match '(?i)^(info|warn|error|done|using|vrunner)') { continue }
                if ($line.Contains('=') -or $line.Contains(':') -or $line.Contains('{') -or $line.Contains('[')) { continue }
                if ($line -match '^\w+$' -and $line.Length -gt 1) {
                    [void]$names.Add($line)
                }
            }
        }

        return [string[]]@($names | Select-Object -Unique)
    } catch {
        Write-Host "Warning: vrunner extensions list failed: $_" -ForegroundColor Yellow
        if ((Get-Location).Path -eq $ProjectRoot) { Pop-Location -ErrorAction SilentlyContinue }
        return @()
    }
}

function Ensure-RepoCfeKeys {
    param([string[]]$Names)
    if (-not (Test-Path -LiteralPath $repoPath)) {
        Write-Host "Error: repository.json required at $repoPath" -ForegroundColor Red
        exit 1
    }
    $raw = Get-Content -LiteralPath $repoPath -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    if (-not $j.cfe) {
        $j | Add-Member -NotePropertyName cfe -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($n in $Names) {
        if (-not $n) { continue }
        if (-not (Test-RepoManagedName $n)) { continue }
        $exists = $j.cfe.PSObject.Properties.Name -contains $n
        if (-not $exists) {
            $j.cfe | Add-Member -NotePropertyName $n -NotePropertyValue $n -Force
            [void]$added.Add($n)
        }
    }
    if ($added.Count -gt 0 -and -not $DryRun) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($repoPath, ($j | ConvertTo-Json -Depth 20), $utf8)
    }
    return [string[]]$added.ToArray()
}

# --- main ---
$fromIb = @()
$fromRepo = @(Get-RepoCfeKeys)
$fromSrc = @(Get-SrcCfeFolders)

if ($ExtensionNames -and $ExtensionNames.Count -gt 0) {
    $fromIb = @($ExtensionNames)
} elseif ($UseVrunnerList -and -not $SkipIb) {
    Write-Host "Fetching extensions from IB via vrunner (deprecated)..." -ForegroundColor DarkGray
    $fromIb = @(Get-IbExtensionsViaVrunner)
} elseif (-not $SkipIb -and -not $UseVrunnerList) {
    Write-Host "Skip IB list via Enterprise; pass -ExtensionNames from live_extensions_list" -ForegroundColor DarkGray
}

$target = @()
if ($fromIb.Count -gt 0) {
    $target = $fromIb
    Write-Host "=== Extensions from IB ===" -ForegroundColor Cyan
    foreach ($n in $fromIb) { Write-Host "  $n" }
} else {
    $target = @($fromRepo + $fromSrc | Select-Object -Unique | Sort-Object)
    Write-Host "=== Fallback: repository.json + src/cfe ===" -ForegroundColor Yellow
    foreach ($n in $target) { Write-Host "  $n" }
}

if (-not (Test-Path -LiteralPath $cfeDir -PathType Container)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $cfeDir -Force | Out-Null
        Write-Host "Created $cfeDir"
    } else {
        Write-Host "[DryRun] would create $cfeDir"
    }
}

$created = New-Object System.Collections.Generic.List[string]
foreach ($n in $target) {
    $dir = Join-Path $cfeDir $n
    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [void]$created.Add($n)
    }
}

$repoAdded = @(Ensure-RepoCfeKeys -Names $target)

Write-Host ""
Write-Host "=== Created folders ===" -ForegroundColor Cyan
if ($created.Count -eq 0) {
    Write-Host "  (nothing)" -ForegroundColor Yellow
} else {
    foreach ($n in $created) {
        $prefix = if ($DryRun) { "[DryRun] " } else { "" }
        Write-Host ("  {0}{1}\{2}" -f $prefix, $cfeDir, $n) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== repository.json cfe keys added ===" -ForegroundColor Cyan
if ($repoAdded.Count -eq 0) {
    Write-Host "  (nothing)" -ForegroundColor Yellow
} else {
    foreach ($n in $repoAdded) { Write-Host "  $n" -ForegroundColor Green }
}

if ($fromIb.Count -gt 0) {
    $extra = @($fromRepo | Where-Object { $fromIb -notcontains $_ })
    if ($extra.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Warning: in repository.json but not in IB ===" -ForegroundColor Yellow
        foreach ($n in $extra) { Write-Host "  $n" }
        if ($Prune -and -not $DryRun) {
            Write-Host "Prune does not auto-remove keys (manual review)." -ForegroundColor Yellow
        }
    }
}

$result = [ordered]@{
    projectRoot = $ProjectRoot
    fromIb      = @($fromIb)
    created     = @($created)
    repoAdded   = @($repoAdded)
    dryRun      = [bool]$DryRun
}
($result | ConvertTo-Json -Depth 5 -Compress) | Write-Output

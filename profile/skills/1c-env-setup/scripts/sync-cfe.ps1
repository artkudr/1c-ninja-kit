# sync-cfe.ps1 - sync src/cfe folders and .v8-project.json extensions section
<#
.SYNOPSIS
    Syncs src/cfe directories and .v8-project.json extensions keys
    with names from live_extensions_list (-ExtensionNames).

.EXAMPLE
    .\sync-cfe.ps1 -ProjectRoot . -ExtensionNames @("MyExt","Other")
.EXAMPLE
    .\sync-cfe.ps1 -ProjectRoot . -DryRun
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
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cfeDir = Join-Path $ProjectRoot "src\cfe"
$registryPath = Join-Path $ProjectRoot ".v8-project.json"

function Get-RegistryExtNames {
    if (-not (Test-Path -LiteralPath $registryPath)) { return @() }
    try {
        $j = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $db = @($j.databases)[0]
        if ($db -and $db.extensions) { return @($db.extensions | ForEach-Object { $_.name }) }
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

function Ensure-RegistryExtNames {
    param([string[]]$Names)
    if (-not (Test-Path -LiteralPath $registryPath)) {
        Write-Host "Error: .v8-project.json required at $registryPath" -ForegroundColor Red
        exit 1
    }
    $raw = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    if (-not $j.databases -or @($j.databases).Count -eq 0) {
        Write-Host "Error: .v8-project.json has no databases" -ForegroundColor Red
        exit 1
    }
    $db = $j.databases[0]
    if (-not $db.extensions) {
        $db | Add-Member -NotePropertyName extensions -NotePropertyValue @() -Force
    }
    $existing = @($db.extensions | ForEach-Object { $_.name })
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($n in $Names) {
        if (-not $n) { continue }
        if (-not (Test-RepoManagedName $n)) { continue }
        if ($existing -contains $n) { continue }
        $entry = [ordered]@{ name = $n; src = "src\cfe\$n" }
        $db.extensions = @($db.extensions) + @([pscustomobject]$entry)
        [void]$added.Add($n)
    }
    if ($added.Count -gt 0 -and -not $DryRun) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($registryPath, ($j | ConvertTo-Json -Depth 20), $utf8)
    }
    return [string[]]$added.ToArray()
}

# --- main ---
$fromIb = @()
$fromRepo = @(Get-RegistryExtNames)
$fromSrc = @(Get-SrcCfeFolders)

if ($ExtensionNames -and $ExtensionNames.Count -gt 0) {
    $fromIb = @($ExtensionNames)
} else {
    Write-Host "Pass -ExtensionNames from live_extensions_list for IB sync" -ForegroundColor DarkGray
}

$target = @()
if ($fromIb.Count -gt 0) {
    $target = $fromIb
    Write-Host "=== Extensions from IB ===" -ForegroundColor Cyan
    foreach ($n in $fromIb) { Write-Host "  $n" }
} else {
    $target = @($fromRepo + $fromSrc | Select-Object -Unique | Sort-Object)
    Write-Host "=== Fallback: .v8-project.json + src/cfe ===" -ForegroundColor Yellow
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

$repoAdded = @(Ensure-RegistryExtNames -Names $target)

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
Write-Host "=== .v8-project.json extensions added ===" -ForegroundColor Cyan
if ($repoAdded.Count -eq 0) {
    Write-Host "  (nothing)" -ForegroundColor Yellow
} else {
    foreach ($n in $repoAdded) { Write-Host "  $n" -ForegroundColor Green }
}

if ($fromIb.Count -gt 0) {
    $extra = @($fromRepo | Where-Object { $fromIb -notcontains $_ })
    if ($extra.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Warning: in .v8-project.json but not in IB ===" -ForegroundColor Yellow
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

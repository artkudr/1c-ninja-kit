# sync-cc-1c-skills — fetch/classify/purge; promote only from promote-whitelist (after rewrite)
# Pipeline: sync.ps1 -> rewrite.ps1 -> sync.ps1 -Promote
# Default: does not touch live.

[CmdletBinding()]
param(
    [switch]$Promote,
    [switch]$PromoteOnly,
    [switch]$SkipFetch,
    [string]$SourcePath = "",
    [string]$RepoUrl = "https://github.com/Nikolay-Shirokov/cc-1c-skills",
    [string]$Branch = "port-cursor"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SkillRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$PoliciesDir = Join-Path $SkillRoot "policies"
$LiveSkills = Join-Path $env:USERPROFILE ".cursor\skills"
$Quarantine = Join-Path $env:USERPROFILE ".cursor\devccskills"
$VendorDir = Join-Path $Quarantine "_vendor"
$SkillsMirror = Join-Path $Quarantine "skills"
$ReportPath = Join-Path $Quarantine "LAST-SYNC.md"

function Fill-PolicySkills {
    param(
        [string]$FileName,
        [System.Collections.Generic.List[string]]$Target
    )
    $path = Join-Path $PoliciesDir $FileName
    if (-not (Test-Path $path)) { throw "No policy: $path" }
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $Target.Clear()
    if ($null -ne $json.skills) {
        foreach ($s in @($json.skills)) {
            if ($null -ne $s -and "$s".Length -gt 0) { $Target.Add([string]$s) }
        }
    }
}

function Test-OverlayMatch {
    param([string]$Name, $Patterns)
    foreach ($p in @($Patterns)) {
        if ($p.EndsWith("*")) {
            $prefix = $p.Substring(0, $p.Length - 1)
            if ($Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        elseif ($Name -eq $p) { return $true }
    }
    return $false
}

function Fill-UpstreamSkillNames {
    param(
        [string]$SkillsRoot,
        [System.Collections.Generic.List[string]]$Target
    )
    $Target.Clear()
    if (-not (Test-Path $SkillsRoot)) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name)) {
        $Target.Add($d.Name)
    }
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

Write-Host "sync-cc-1c-skills"
Write-Host "  policies: $PoliciesDir"
Write-Host "  quarantine: $Quarantine"
Write-Host "  live: $LiveSkills"

$hardDrop = New-Object System.Collections.Generic.List[string]
$study = New-Object System.Collections.Generic.List[string]
$overlay = New-Object System.Collections.Generic.List[string]
$approved = New-Object System.Collections.Generic.List[string]
$promoteList = New-Object System.Collections.Generic.List[string]
Fill-PolicySkills "hard-drop.json" $hardDrop
Fill-PolicySkills "quarantine-study.json" $study
Fill-PolicySkills "overlay-preserve.json" $overlay
Fill-PolicySkills "whitelist.json" $approved
Fill-PolicySkills "promote-whitelist.json" $promoteList
$knownJson = Get-Content -LiteralPath (Join-Path $PoliciesDir "known-ccskills.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$known = New-Object System.Collections.Generic.List[string]
if ($null -ne $knownJson.skills) {
    foreach ($s in @($knownJson.skills)) { if ($s) { $known.Add([string]$s) } }
}

$commit = $knownJson.source.commit
$fetched = $false

if (-not $PromoteOnly) {
    New-Item -ItemType Directory -Force -Path $Quarantine | Out-Null
    New-Item -ItemType Directory -Force -Path $VendorDir | Out-Null

    if (-not $SkipFetch) {
        if ($SourcePath -and (Test-Path $SourcePath)) {
            $srcSkills = Join-Path $SourcePath ".cursor\skills"
            if (-not (Test-Path $srcSkills)) { $srcSkills = Join-Path $SourcePath "skills" }
            Write-Host "SourcePath: $SourcePath"
        }
        else {
            $clonePath = Join-Path $VendorDir "cc-1c-skills"
            if (Test-Path (Join-Path $clonePath ".git")) {
                Write-Host "git fetch/checkout $Branch in $clonePath"
                git -C $clonePath fetch --depth 1 origin $Branch
                git -C $clonePath checkout -f "origin/$Branch"
            }
            else {
                Write-Host "git clone -b $Branch --depth 1"
                if (Test-Path $clonePath) { Remove-Item -LiteralPath $clonePath -Recurse -Force }
                git clone -b $Branch --depth 1 $RepoUrl $clonePath
            }
            $SourcePath = $clonePath
            $srcSkills = Join-Path $SourcePath ".cursor\skills"
            $fetched = $true
            $commit = (git -C $SourcePath rev-parse HEAD).Trim()
        }

        if (-not (Test-Path $srcSkills)) {
            throw "Upstream skills dir not found: $srcSkills"
        }

        if (Test-Path $SkillsMirror) { Remove-Item -LiteralPath $SkillsMirror -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $SkillsMirror | Out-Null
        Copy-Item -Path (Join-Path $srcSkills "*") -Destination $SkillsMirror -Recurse -Force
        Write-Host "Mirrored skills -> $SkillsMirror"
    }
}

$upstreamNames = New-Object System.Collections.Generic.List[string]
Fill-UpstreamSkillNames $SkillsMirror $upstreamNames
if ($upstreamNames.Count -eq 0 -and -not $PromoteOnly) {
    throw "Empty quarantine skills: $SkillsMirror (run sync without -PromoteOnly first)"
}

$dropped = [System.Collections.Generic.List[string]]::new()
$studyKept = [System.Collections.Generic.List[string]]::new()
$newSkills = [System.Collections.Generic.List[string]]::new()
$whitelistCandidates = [System.Collections.Generic.List[string]]::new()
$preserved = [System.Collections.Generic.List[string]]::new()
$promoted = [System.Collections.Generic.List[string]]::new()
$skippedOverlay = [System.Collections.Generic.List[string]]::new()
$promoteMissing = [System.Collections.Generic.List[string]]::new()

# Purge hard-drop from quarantine after mirror
foreach ($name in $upstreamNames) {
    if ($hardDrop -contains $name) {
        $dir = Join-Path $SkillsMirror $name
        if (Test-Path $dir) {
            Remove-Item -LiteralPath $dir -Recurse -Force
            $dropped.Add($name)
        }
    }
}
Fill-UpstreamSkillNames $SkillsMirror $upstreamNames

foreach ($name in $upstreamNames) {
    if ($study -contains $name) {
        $studyKept.Add($name)
        continue
    }
    if ($known -notcontains $name) {
        $newSkills.Add($name)
        continue
    }
    if (Test-OverlayMatch -Name $name -Patterns $overlay) {
        $preserved.Add($name)
        continue
    }
    if ($approved -contains $name) {
        $whitelistCandidates.Add($name)
    }
}

$transformNote = "soft-transform via rewrite.ps1 (separate); promote uses promote-whitelist.json only"

if ($Promote -or $PromoteOnly) {
    # Re-read promote list (may have been filled by rewrite after this sync's classify)
    Fill-PolicySkills "promote-whitelist.json" $promoteList
    if ($promoteList.Count -eq 0) {
        Write-Warning "promote-whitelist.json is empty — run rewrite.ps1 first. Nothing promoted."
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $env:USERPROFILE ".cursor\skills.bak-$stamp"
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    foreach ($name in $promoteList) {
        if (Test-OverlayMatch -Name $name -Patterns $overlay) {
            $skippedOverlay.Add($name)
            continue
        }
        if ($hardDrop -contains $name) { continue }
        if ($study -contains $name) { continue }
        $src = Join-Path $SkillsMirror $name
        $dst = Join-Path $LiveSkills $name
        if (-not (Test-Path $src)) {
            $promoteMissing.Add($name)
            continue
        }
        if (Test-Path $dst) {
            Copy-Item -LiteralPath $dst -Destination (Join-Path $backup $name) -Recurse -Force
        }
        if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        # Copy without __pycache__ (robocopy /XD); exit 0–7 = success
        & robocopy $src $dst /E /XD __pycache__ /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed ($LASTEXITCODE) $src -> $dst"
        }
        $promoted.Add($name)
    }
    Write-Host "Backup: $backup"
    Write-Host "Promoted: $($promoted.Count)"
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# LAST-SYNC")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- When: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- Branch: $Branch")
[void]$sb.AppendLine("- Commit: $commit")
[void]$sb.AppendLine("- Fetched: $fetched")
[void]$sb.AppendLine("- Promote: $($Promote -or $PromoteOnly)")
[void]$sb.AppendLine("- $transformNote")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## dropped ($($dropped.Count))")
$dropped | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## quarantine-study ($($studyKept.Count))")
$studyKept | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## new / not in known-ccskills ($($newSkills.Count))")
$newSkills | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## overlay-preserve hit ($($preserved.Count))")
$preserved | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## whitelist candidates (need rewrite) ($($whitelistCandidates.Count))")
$whitelistCandidates | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## promote-whitelist size (policy) ($($promoteList.Count))")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## promoted ($($promoted.Count))")
$promoted | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## skipped (overlay on promote) ($($skippedOverlay.Count))")
$skippedOverlay | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## promote missing in quarantine ($($promoteMissing.Count))")
$promoteMissing | ForEach-Object { [void]$sb.AppendLine("- $_") }

New-Item -ItemType Directory -Force -Path $Quarantine | Out-Null
Write-Utf8Bom -Path $ReportPath -Content $sb.ToString()
Write-Host "Report: $ReportPath"
Write-Host "Done. dropped=$($dropped.Count) study=$($studyKept.Count) new=$($newSkills.Count) whitelist=$($whitelistCandidates.Count) promoted=$($promoted.Count)"

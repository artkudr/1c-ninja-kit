# env-setup.ps1 — оркестратор развёртывания окружения 1С-проекта
<#
.SYNOPSIS
    Создаёт каркас каталогов и конфигов проекта 1С на той же машине.

.DESCRIPTION
    Режимы: Init (полная инициализация), Refresh (только недостающее), Check (dry-run отчёт).
    Интерактивный выбор базы/логина — в агенте (SKILL.md); скрипт принимает готовые параметры.

.EXAMPLE
    .\env-setup.ps1 -Mode Check
.EXAMPLE
    .\env-setup.ps1 -Mode Init -SourceProject C:\1C\projects\ecoladev -IbConnection '/S"srv/db"' -DbUser Admin -DbPwd secret
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Init", "Refresh", "Check")]
    [string]$Mode = "Init",

    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$SourceProject,

    [Parameter(Mandatory = $false)]
    [string]$IbConnection,

    [Parameter(Mandatory = $false)]
    [string]$DbUser,

    [Parameter(Mandatory = $false)]
    [string]$DbPwd,

    [Parameter(Mandatory = $false)]
    [string]$V8Version,

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$RepoUser,

    [Parameter(Mandatory = $false)]
    [string]$RepoAdmin = "Администратор",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSyncCfe,

    [Parameter(Mandatory = $false)]
    [string[]]$ExtensionNames
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatesDir = Join-Path $scriptDir "templates"
$dryRun = ($Mode -eq "Check")

$ProjectRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    if ($dryRun) {
        Write-Host "[Check] project root missing: $ProjectRoot" -ForegroundColor Yellow
    } else {
        New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
    }
}
if (Test-Path -LiteralPath $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$report = New-Object System.Collections.Generic.List[object]

function Add-Report {
    param([string]$Item, [string]$Status, [string]$Detail = "")
    [void]$report.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
}

function Write-FileSafe {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$OnlyIfMissing
    )
    $exists = Test-Path -LiteralPath $Path
    if ($exists -and $OnlyIfMissing -and -not $Force) {
        Add-Report (Split-Path $Path -Leaf) "skip" "exists"
        return $false
    }
    if ($dryRun) {
        $action = if ($exists) { "would-overwrite" } else { "would-create" }
        Add-Report (Split-Path $Path -Leaf) $action $Path
        return $true
    }
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # UTF-8 without BOM for JSON-ish files
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
    Add-Report (Split-Path $Path -Leaf) $(if ($exists) { "updated" } else { "created" }) $Path
    return $true
}

function Ensure-Dir {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Add-Report $Path "ok" "exists"
        return
    }
    if ($dryRun) {
        Add-Report $Path "would-create" ""
        return
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Add-Report $Path "created" ""
}

function Get-Template {
    param([string]$Name)
    $p = Join-Path $templatesDir $Name
    if (-not (Test-Path -LiteralPath $p)) { throw "Template missing: $p" }
    return Get-Content -LiteralPath $p -Raw -Encoding UTF8
}

function Copy-FromSource {
    param([string]$RelativePath, [switch]$Required)
    if (-not $SourceProject) { return $false }
    $src = Join-Path $SourceProject $RelativePath
    $dst = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $src)) {
        if ($Required) {
            Write-Host "Warning: source missing $src" -ForegroundColor Yellow
        }
        return $false
    }
    if ((Test-Path -LiteralPath $dst) -and -not $Force -and $Mode -ne "Init") {
        Add-Report $RelativePath "skip" "exists"
        return $true
    }
    if ((Test-Path -LiteralPath $dst) -and -not $Force -and (Test-Path -LiteralPath $dst)) {
        # Init: не затирать без Force
        if (-not $Force) {
            Add-Report $RelativePath "skip" "exists (use -Force)"
            return $true
        }
    }
    if ($dryRun) {
        Add-Report $RelativePath "would-copy" "from $src"
        return $true
    }
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Add-Report $RelativePath "copied" "from $SourceProject"
    return $true
}

function Copy-NinjaLive {
    $dest = Join-Path $ProjectRoot "src\cfe\NinjaLive"
    $destCfg = Join-Path $dest "Configuration.xml"
    $destResolved = $null
    if (Test-Path -LiteralPath $dest) {
        $destResolved = (Resolve-Path -LiteralPath $dest).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($SourceProject) {
        $fromSrc = Join-Path $SourceProject "src\cfe\NinjaLive"
        if (Test-Path -LiteralPath (Join-Path $fromSrc "Configuration.xml")) {
            [void]$candidates.Add((Resolve-Path -LiteralPath $fromSrc).Path)
        }
    }
    $canonical = "C:\1C\projects\ecoladev\src\cfe\NinjaLive"
    if (Test-Path -LiteralPath (Join-Path $canonical "Configuration.xml")) {
        $rp = (Resolve-Path -LiteralPath $canonical).Path
        if ($candidates -notcontains $rp) {
            [void]$candidates.Add($rp)
        }
    }

    $src = $null
    foreach ($p in $candidates) {
        if ($destResolved -and ($p -eq $destResolved)) { continue }
        $src = $p
        break
    }

    if (-not $src) {
        if (Test-Path -LiteralPath $destCfg) {
            Add-Report "src/cfe/NinjaLive" "ok" "already present"
        } else {
            Add-Report "src/cfe/NinjaLive" "fail" "source missing (SourceProject or C:\1C\projects\ecoladev\src\cfe\NinjaLive)"
            Write-Host "Warning: NinjaLive sources not found" -ForegroundColor Yellow
        }
        return
    }

    if ((Test-Path -LiteralPath $destCfg) -and -not $Force) {
        Add-Report "src/cfe/NinjaLive" "skip" "exists"
        return
    }

    if ($dryRun) {
        Add-Report "src/cfe/NinjaLive" "would-copy" "from $src"
        return
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & robocopy $src $dest /E /XD .git /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($code -ge 8) {
        Add-Report "src/cfe/NinjaLive" "fail" "robocopy exit $code from $src"
        Write-Host "Error: copy NinjaLive failed (robocopy $code)" -ForegroundColor Red
        return
    }
    Add-Report "src/cfe/NinjaLive" "copied" "from $src"
}

function Find-SiblingSource {
    $parent = Split-Path $ProjectRoot -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent)) { return $null }
    $candidates = @(
        Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $ProjectRoot } |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName "autumn-properties.json")) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName "repository.json"))
            } |
            Sort-Object Name
    )
    if ($candidates.Count -eq 0) { return $null }
    return $candidates[0].FullName
}

function Get-DetectedV8Version {
    $found = Get-ChildItem @(
        "C:\Program Files\1cv8\*\bin\1cv8.exe",
        "C:\Program Files (x86)\1cv8\*\bin\1cv8.exe"
    ) -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]"0.0.0.0" } } -Descending |
        Select-Object -First 1
    if ($found) { return $found.Directory.Parent.Name }
    return "8.3"
}

function Merge-Gitignore {
    $snippetPath = Join-Path $templatesDir "gitignore-1c.snippet"
    $snippet = Get-Content -LiteralPath $snippetPath -Raw -Encoding UTF8
    $gi = Join-Path $ProjectRoot ".gitignore"
    if (-not (Test-Path -LiteralPath $gi)) {
        [void](Write-FileSafe -Path $gi -Content $snippet)
        return
    }
    $existing = Get-Content -LiteralPath $gi -Raw -Encoding UTF8
    $needed = @(".build/", ".cursor/mcp.json", "!.cursor/mcp.json.example", "/build/")
    $toAdd = @()
    foreach ($line in $needed) {
        if ($existing -notmatch [regex]::Escape($line)) {
            $toAdd += $line
        }
    }
    if ($toAdd.Count -eq 0) {
        Add-Report ".gitignore" "ok" "required entries present"
        return
    }
    if ($dryRun) {
        Add-Report ".gitignore" "would-append" ($toAdd -join ", ")
        return
    }
    $append = "`r`n# 1c-env-setup`r`n" + ($toAdd -join "`r`n") + "`r`n"
    Add-Content -LiteralPath $gi -Value $append -Encoding UTF8
    Add-Report ".gitignore" "updated" ($toAdd -join ", ")
}

function Test-SameFsPath {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    $a = [IO.Path]::GetFullPath($Left).TrimEnd('\')
    $b = [IO.Path]::GetFullPath($Right).TrimEnd('\')
    return $a.Equals($b, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PathLinkInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; IsLink = $false; LinkType = ""; Target = "" }
    }
    $item = Get-Item -LiteralPath $Path -Force
    $linkType = [string]$item.LinkType
    $isReparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $target = ""
    if ($item.Target) {
        if ($item.Target -is [System.Array]) { $target = [string]$item.Target[0] }
        else { $target = [string]$item.Target }
    }
    return [pscustomobject]@{
        Exists   = $true
        IsLink   = ($isReparse -or $linkType -eq "Junction" -or $linkType -eq "SymbolicLink")
        LinkType = $linkType
        Target   = $target
    }
}

function Test-FileSymlinkAllowed {
    $src = Join-Path $env:TEMP "1c-env-setup-symlink-probe-src.mdc"
    $dst = Join-Path $env:TEMP "1c-env-setup-symlink-probe-dst.mdc"
    try {
        Set-Content -LiteralPath $src -Value "probe" -Encoding UTF8
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
        cmd /c "mklink `"$dst`" `"$src`" >nul 2>&1" | Out-Null
        if (-not (Test-Path -LiteralPath $dst)) { return $false }
        $item = Get-Item -LiteralPath $dst -Force
        return ([string]$item.LinkType -eq "SymbolicLink")
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
        if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Force }
    }
}

function Test-SameVolume {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    $a = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Left))
    $b = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Right))
    return $a.Equals($b, [StringComparison]::OrdinalIgnoreCase)
}

function Get-HardlinkPaths {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $raw = & cmd /c "fsutil hardlink list `"$Path`"" 2>&1
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($raw | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -notmatch "^Error" })
}

function Test-IsHardlinkTo {
    param([string]$Path, [string]$CanonFile)
    $links = Get-HardlinkPaths $Path
    if ($links.Count -lt 2) { return $false }
    $canonFull = [IO.Path]::GetFullPath($CanonFile)
    $root = [IO.Path]::GetPathRoot($canonFull).TrimEnd('\')
    foreach ($rel in $links) {
        $candidate = if ($rel.Length -ge 2 -and $rel[1] -eq ':') { $rel } else { $root + $rel }
        if (Test-SameFsPath $candidate $canonFull) { return $true }
    }
    return $false
}

function New-ProjectRuleLink {
    param(
        [string]$Src,
        [string]$Dst,
        [bool]$SymlinkOk,
        [bool]$SameVol
    )
    # File symlink first (needs SeCreateSymbolicLinkPrivilege / Developer Mode).
    # Fallback: hardlink /H on the same volume (no Developer Mode).
    # Copy only if another volume — hardlink cannot cross volumes.
    if ($SymlinkOk) {
        cmd /c "mklink `"$Dst`" `"$Src`" >nul 2>&1" | Out-Null
        $fi = Get-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue
        if ($fi -and [string]$fi.LinkType -eq "SymbolicLink") { return "file-symlink" }
        if ($fi) { Remove-Item -LiteralPath $Dst -Force }
    }
    if ($SameVol) {
        cmd /c "mklink /H `"$Dst`" `"$Src`" >nul 2>&1" | Out-Null
        if ((Test-Path -LiteralPath $Dst) -and (Test-IsHardlinkTo $Dst $Src)) { return "hardlink" }
        if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force }
    }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
    return "copy"
}

function Get-ProjectContextVars {
    $name = (Split-Path $ProjectRoot -Leaf)
    $compat = "Version8_3_27"
    $cfgPath = Join-Path $ProjectRoot "src\cf\Configuration.xml"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            [xml]$cfg = Get-Content -LiteralPath $cfgPath -Encoding UTF8
            $node = $cfg.SelectSingleNode("//*[local-name()='CompatibilityMode']")
            if ($node -and $node.InnerText) {
                $compat = $node.InnerText.Trim()
            }
        } catch {}
    }
    return [pscustomobject]@{
        ProjectName = $name
        CompatMode  = $compat
    }
}

function Expand-TemplateContent {
    param([string]$Content, [object]$Vars)
    return $Content.
        Replace("{{PROJECT_NAME}}", $Vars.ProjectName).
        Replace("{{COMPAT_MODE}}", $Vars.CompatMode)
}

function Install-ScaffoldFile {
    param(
        [string]$DestRelative,
        [string]$TemplateRelative,
        [switch]$ExpandPlaceholders
    )
    $dest = Join-Path $ProjectRoot ($DestRelative -replace '/', '\')
    $tplPath = Join-Path $templatesDir ($TemplateRelative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $tplPath)) {
        Add-Report $DestRelative "fail" "template missing: $TemplateRelative"
        return
    }
    $exists = Test-Path -LiteralPath $dest
    if ($exists -and -not $Force) {
        Add-Report $DestRelative "skip" "exists"
        return
    }
    $content = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8
    if ($ExpandPlaceholders) {
        $vars = Get-ProjectContextVars
        $content = Expand-TemplateContent -Content $content -Vars $vars
    }
    if ($dryRun) {
        $action = if ($exists) { "would-overwrite" } else { "would-create" }
        Add-Report $DestRelative $action $tplPath
        return
    }
    $dir = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($dest, $content, $utf8)
    Add-Report $DestRelative $(if ($exists) { "updated" } else { "created" }) $tplPath
}

function Sync-CursorCommands {
    $cmdDir = Join-Path $ProjectRoot ".cursor\commands"
    $tplDir = Join-Path $templatesDir "cursor-commands"
    if (-not (Test-Path -LiteralPath $tplDir)) {
        Add-Report ".cursor/commands" "fail" "template dir missing"
        return
    }
    if ($dryRun) {
        Ensure-Dir $cmdDir
    } elseif (-not (Test-Path -LiteralPath $cmdDir)) {
        New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null
    }
    $files = @(Get-ChildItem -LiteralPath $tplDir -Filter "*.md" -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $dest = Join-Path $cmdDir $file.Name
        $exists = Test-Path -LiteralPath $dest
        if ($exists -and -not $Force) {
            Add-Report ".cursor/commands/$($file.Name)" "skip" "exists"
            continue
        }
        if ($dryRun) {
            $action = if ($exists) { "would-overwrite" } else { "would-create" }
            Add-Report ".cursor/commands/$($file.Name)" $action $file.FullName
            continue
        }
        Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
        Add-Report ".cursor/commands/$($file.Name)" $(if ($exists) { "updated" } else { "created" }) ""
    }
    if ($files.Count -gt 0) {
        Add-Report ".cursor/commands" "synced" "$($files.Count) opsx commands"
    }
}

function Sync-OpenspecScaffold {
    # Scaffold only from skill templates. Never copy live changes/* or specs/*/spec.md from SourceProject.
    $openspecDirs = @(
        "openspec",
        "openspec\templates",
        "openspec\specs",
        "openspec\changes",
        "openspec\changes\archive"
    )
    foreach ($d in $openspecDirs) {
        Ensure-Dir (Join-Path $ProjectRoot $d)
    }

    Install-ScaffoldFile -DestRelative "openspec/README.md" -TemplateRelative "openspec/README.md"
    Install-ScaffoldFile -DestRelative "openspec/specs/README.md" -TemplateRelative "openspec/specs-README.md"
    Install-ScaffoldFile -DestRelative "openspec/changes/README.md" -TemplateRelative "openspec/changes-README.md"
    Install-ScaffoldFile -DestRelative "openspec/config.yaml" -TemplateRelative "openspec/config.yaml.tpl" -ExpandPlaceholders
    Install-ScaffoldFile -DestRelative "openspec/project.md" -TemplateRelative "openspec/project.md.tpl" -ExpandPlaceholders

    $artifactTplDir = Join-Path $templatesDir "openspec\templates"
    if (Test-Path -LiteralPath $artifactTplDir) {
        Get-ChildItem -LiteralPath $artifactTplDir -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Install-ScaffoldFile -DestRelative "openspec/templates/$($_.Name)" -TemplateRelative "openspec/templates/$($_.Name)"
        }
    }

    Add-Report "openspec/" "scaffold" "templates only; live changes/specs preserved"
}

function Sync-ProjectRulesFromProfile {
    # Cursor читает только project .cursor/rules/*.mdc как файлы (не папку профиля, не folder junction).
    # Канон — %USERPROFILE%\.cursor\rules. Папку канона не удалять.
    # Directory junction (/J, /D) на папку запрещён: Cursor/индексатор его плохо ест.
    # /J ≠ file symlink: junction НЕ требует SeCreateSymbolicLinkPrivilege / Developer Mode;
    # file symlink и mklink /D — требуют. На этой машине канон — hardlink файлов (mklink /H).
    # Порядок: file symlink → hardlink /H (тот же том) → копия только другой диск.
    # Снимать folder junction только cmd /c rmdir без /S. Remove-Item -Recurse по junction запрещён.
    $canon = Join-Path $env:USERPROFILE ".cursor\rules"
    $dest = Join-Path $ProjectRoot ".cursor\rules"
    if (-not (Test-Path -LiteralPath $canon)) {
        Add-Report ".cursor/rules" "error" "canon missing: $canon"
        return
    }
    $mdc = @(Get-ChildItem -LiteralPath $canon -Filter "*.mdc" -File -ErrorAction SilentlyContinue)
    if ($mdc.Count -eq 0) {
        Add-Report ".cursor/rules" "error" "no .mdc in canon: $canon"
        return
    }

    $info = Get-PathLinkInfo $dest
    $symlinkOk = Test-FileSymlinkAllowed
    $sameVol = Test-SameVolume $canon $ProjectRoot
    $mode = if ($symlinkOk) { "file-symlink" } elseif ($sameVol) { "hardlink" } else { "copy" }
    $note = $mode
    if ($info.Exists -and $info.IsLink) { $note = "drop folder $($info.LinkType), then $mode" }

    if ($dryRun) {
        Add-Report ".cursor/rules" "would-sync" "$note ($($mdc.Count) mdc)"
        return
    }

    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($info.Exists -and $info.IsLink) {
        cmd /c rmdir "$dest" | Out-Null
        if (Test-Path -LiteralPath $dest) {
            Add-Report ".cursor/rules" "error" "failed to remove folder link (use rmdir, not Remove-Item -Recurse): $dest"
            return
        }
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    $destInfo = Get-PathLinkInfo $dest
    if ($destInfo.IsLink) {
        Add-Report ".cursor/rules" "error" "dest is still a folder link: $dest"
        return
    }

    $modesUsed = @{}
    $synced = 0
    foreach ($file in $mdc) {
        $src = $file.FullName
        $dst = Join-Path $dest $file.Name
        if (Test-Path -LiteralPath $dst) {
            $fi = Get-Item -LiteralPath $dst -Force
            $tgt = ""
            if ($fi.Target) {
                if ($fi.Target -is [System.Array]) { $tgt = [string]$fi.Target[0] }
                else { $tgt = [string]$fi.Target }
            }
            if ([string]$fi.LinkType -eq "SymbolicLink" -and (Test-SameFsPath $tgt $src)) {
                $modesUsed["file-symlink"] = $true
                $synced++
                continue
            }
            if (Test-IsHardlinkTo $dst $src) {
                $modesUsed["hardlink"] = $true
                $synced++
                continue
            }
            Remove-Item -LiteralPath $dst -Force
        }
        $used = New-ProjectRuleLink -Src $src -Dst $dst -SymlinkOk $symlinkOk -SameVol $sameVol
        $modesUsed[$used] = $true
        $synced++
    }

    $canonNames = @{}
    foreach ($file in $mdc) { $canonNames[$file.Name] = $true }
    Get-ChildItem -LiteralPath $dest -Filter "*.mdc" -File -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $canonNames.ContainsKey($_.Name)) {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }

    $usedMode = ($modesUsed.Keys | Sort-Object) -join "+"
    if (-not $usedMode) { $usedMode = $mode }
    Add-Report ".cursor/rules" $usedMode "$synced mdc from profile (no folder junction)"
}

function Write-AutumnProperties {
    $path = Join-Path $ProjectRoot "autumn-properties.json"
    if ((Test-Path -LiteralPath $path) -and -not $Force -and $Mode -eq "Refresh") {
        Add-Report "autumn-properties.json" "skip" "Refresh without -Force"
        return
    }
    if ((Test-Path -LiteralPath $path) -and -not $Force -and -not $IbConnection) {
        Add-Report "autumn-properties.json" "skip" "exists"
        return
    }

    # Prefer copy from source then patch
    if ($SourceProject -and (Test-Path -LiteralPath (Join-Path $SourceProject "autumn-properties.json")) -and -not $IbConnection) {
        [void](Copy-FromSource "autumn-properties.json")
        return
    }

    $v8 = $V8Version
    if (-not $v8 -and $SourceProject) {
        $sp = Join-Path $SourceProject "autumn-properties.json"
        if (Test-Path -LiteralPath $sp) {
            try {
                $sj = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($sj.vrunner.v8version) { $v8 = [string]$sj.vrunner.v8version }
                if (-not $DbUser -and $sj.vrunner.'db-user') { $script:DbUser = [string]$sj.vrunner.'db-user' }
            } catch {}
        }
    }
    if (-not $v8) { $v8 = Get-DetectedV8Version }

    $conn = $IbConnection
    if (-not $conn) { $conn = '/S"server/infobase"' }
    $user = if ($DbUser) { $DbUser } else { "" }
    $pwd = if ($null -ne $DbPwd) { $DbPwd } else { "" }

    $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
    $webPort = 8083
    if ($v8 -like "8.5*") { $webPort = 8085 }

    $tpl = Get-Template "autumn-properties.json.tpl"
    $content = $tpl.
        Replace("{{IBCONNECTION}}", $conn).
        Replace("{{DB_USER}}", $user).
        Replace("{{DB_PWD}}", $pwd).
        Replace("{{V8VERSION}}", $v8).
        Replace("{{APP_NAME}}", $app).
        Replace("{{WEB_PORT}}", "$webPort")

    [void](Write-FileSafe -Path $path -Content $content)
}

function Patch-AutumnCredentials {
    $path = Join-Path $ProjectRoot "autumn-properties.json"
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not $IbConnection -and -not $DbUser -and $null -eq $DbPwd -and -not $V8Version) { return }
    if ($dryRun) {
        Add-Report "autumn-properties.json" "would-patch" "credentials/ibconnection"
        return
    }
    $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($IbConnection) { $j.vrunner.ibconnection = $IbConnection }
    if ($DbUser) { $j.vrunner.'db-user' = $DbUser }
    if ($null -ne $DbPwd -and $PSBoundParameters.ContainsKey("DbPwd")) { $j.vrunner.'db-pwd' = $DbPwd }
    if ($V8Version) { $j.vrunner.v8version = $V8Version }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ($j | ConvertTo-Json -Depth 20), $utf8)
    Add-Report "autumn-properties.json" "patched" "credentials"
}

function Write-RepositoryJson {
    $path = Join-Path $ProjectRoot "repository.json"
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Add-Report "repository.json" "ok" "exists"
        return
    }
    if ($SourceProject -and (Copy-FromSource "repository.json" -Required)) {
        return
    }
    $root = if ($RepoRoot) { $RepoRoot } else { "Z:\\Хранилища" }
    $user = if ($RepoUser) { $RepoUser } else { "User" }
    $admin = if ($RepoAdmin) { $RepoAdmin } else { "Администратор" }
    $tpl = Get-Template "repository.json.tpl"
    $content = $tpl.
        Replace("{{REPO_ROOT}}", ($root -replace '\\', '\\')).
        Replace("{{REPO_USER}}", $user).
        Replace("{{REPO_ADMIN}}", $admin)
    # Fix double-escaping for JSON path: use ConvertTo-Json for values instead
    $obj = [ordered]@{
        root      = $root
        user      = $user
        adminUser = $admin
        cfe       = [ordered]@{}
    }
    $content = ($obj | ConvertTo-Json -Depth 5) + "`n"
    [void](Write-FileSafe -Path $path -Content $content)
}

function ConvertTo-McpJsonPath {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return "" }
    return ($Path -replace '\\', '\\')
}

function ConvertTo-McpJsonString {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    return (($Value -replace '\\', '\\') -replace '"', '\"')
}

function Get-McpMachinePaths {
    $autumnRoot = "C:\1C\projects\1c-ninja-mcp"
    return [pscustomobject]@{
        VrunnerMcpBat  = Join-Path $env:LOCALAPPDATA "ovm\current\bin\vrunner-mcp.bat"
        BslAnalyzerExe = Join-Path $env:LOCALAPPDATA "bsl-analyzer\bsl-analyzer.exe"
        AutumnMain     = Join-Path $autumnRoot "main.os"
        ShcntxHelpDb   = Join-Path $autumnRoot "src\data\shcntx_help.db"
    }
}

function Get-McpJsonFromSkillTemplate {
    param(
        [string]$BslUser,
        [string]$BslPassword,
        [string]$AppName,
        [string]$WebPort,
        [string]$ProjectRootPath
    )
    $paths = Get-McpMachinePaths
    $tpl = Get-Template "mcp.json.example.tpl"
    return $tpl.
        Replace("{{VRUNNER_MCP_BAT}}", (ConvertTo-McpJsonPath $paths.VrunnerMcpBat)).
        Replace("{{AUTUMN_MAIN}}", (ConvertTo-McpJsonPath $paths.AutumnMain)).
        Replace("{{SHCNTX_HELP_DB}}", (ConvertTo-McpJsonPath $paths.ShcntxHelpDb)).
        Replace("{{BSL_ANALYZER_EXE}}", (ConvertTo-McpJsonPath $paths.BslAnalyzerExe)).
        Replace("{{PROJECT_ROOT}}", (ConvertTo-McpJsonPath $ProjectRootPath)).
        Replace("{{WEB_PORT}}", "$WebPort").
        Replace("{{APP_NAME}}", $AppName).
        Replace("{{BSL_USER}}", (ConvertTo-McpJsonString $BslUser)).
        Replace("{{BSL_PASSWORD}}", (ConvertTo-McpJsonString $BslPassword))
}

function Test-UserMcpOverlap {
    $userMcp = Join-Path $env:USERPROFILE ".cursor\mcp.json"
    $canonNames = @(
        "vrunner",
        "1c-mcp-toolkit",
        "1c-ninja-mcp",
        "bsl-analyzer-reference",
        "bsl-analyzer-workspace"
    )
    if (-not (Test-Path -LiteralPath $userMcp)) {
        Add-Report "user mcp.json" "ok" "absent (1C MCP lives in project)"
        return
    }
    try {
        $j = Get-Content -LiteralPath $userMcp -Raw -Encoding UTF8 | ConvertFrom-Json
        $names = @()
        if ($j.mcpServers) {
            $names = @($j.mcpServers.PSObject.Properties.Name)
        }
        $overlap = @($names | Where-Object { $canonNames -contains $_ })
        if ($overlap.Count -gt 0) {
            Add-Report "user mcp.json" "warn" ("duplicates if project also has: " + ($overlap -join ", "))
        } else {
            Add-Report "user mcp.json" "ok" "no overlapping 1C server names"
        }
    } catch {
        Add-Report "user mcp.json" "warn" "could not parse"
    }
}

function Write-McpFiles {
    # Эталон — шаблон скилла. Не копировать user mcp.json и не брать MCP из SourceProject.
    $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
    $webPort = 8083
    if ($V8Version -like "8.5*") { $webPort = 8085 }

    $exampleContent = Get-McpJsonFromSkillTemplate -BslUser "<пользователь_ИБ>" -BslPassword "<пароль>" `
        -AppName $app -WebPort "$webPort" -ProjectRootPath $ProjectRoot

    $examplePath = Join-Path $ProjectRoot ".cursor\mcp.json.example"
    [void](Write-FileSafe -Path $examplePath -Content $exampleContent -OnlyIfMissing:(-not $Force))

    $mcpPath = Join-Path $ProjectRoot ".cursor\mcp.json"
    if ((Test-Path -LiteralPath $mcpPath) -and -not $Force -and $Mode -eq "Refresh") {
        Add-Report "mcp.json" "skip" "Refresh"
        return
    }

    $user = if ($DbUser) { $DbUser } else { "<пользователь_ИБ>" }
    $pwd = if ($null -ne $DbPwd -and $PSBoundParameters.ContainsKey("DbPwd")) { $DbPwd } else { "<пароль>" }
    $mcpContent = Get-McpJsonFromSkillTemplate -BslUser $user -BslPassword $pwd `
        -AppName $app -WebPort "$webPort" -ProjectRootPath $ProjectRoot

    if ($dryRun -and -not (Test-Path -LiteralPath $mcpPath)) {
        Add-Report "mcp.json" "would-create" "from skill template"
        return
    }
    if ((Test-Path -LiteralPath $mcpPath) -and -not $Force) {
        Add-Report "mcp.json" "skip" "exists (use -Force)"
        return
    }
    [void](Write-FileSafe -Path $mcpPath -Content $mcpContent)
}

function Write-BslAnalyzerToml {
    $path = Join-Path $ProjectRoot "bsl-analyzer.toml"
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Add-Report "bsl-analyzer.toml" "ok" "exists"
        return
    }
    if ($SourceProject -and (Copy-FromSource "bsl-analyzer.toml")) { return }
    $tpl = Get-Template "bsl-analyzer.toml.tpl"
    [void](Write-FileSafe -Path $path -Content $tpl)
}

# ========== MAIN ==========

Write-Host "=== 1c-env-setup ($Mode) ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

# Sanity
$vrunnerOk = $false
try {
    $vr = & vrunner --version 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $vr -match '3\.') {
        $vrunnerOk = $true
        Add-Report "vrunner" "ok" ($vr.Trim() -replace '\s+', ' ')
    }
} catch {}
if (-not $vrunnerOk) {
    Add-Report "vrunner" "fail" "not in PATH - machine stack not ready"
    if ($Mode -ne "Check") {
        Write-Host "Error: vrunner not found. Install vanessa-runner 3 on this machine first." -ForegroundColor Red
        $report | Format-Table -AutoSize
        exit 1
    }
}

$bslExe = Join-Path $env:LOCALAPPDATA "bsl-analyzer\bsl-analyzer.exe"
if (Test-Path -LiteralPath $bslExe) {
    Add-Report "bsl-analyzer.exe" "ok" $bslExe
} else {
    Add-Report "bsl-analyzer.exe" "warn" "not found - MCP workspace unavailable"
}

if (-not $SourceProject) {
    $auto = Find-SiblingSource
    if ($auto) {
        $SourceProject = $auto
        Write-Host "Auto SourceProject: $SourceProject" -ForegroundColor Yellow
        Add-Report "SourceProject" "auto" $SourceProject
    } else {
        Add-Report "SourceProject" "none" ""
    }
} else {
    $SourceProject = (Resolve-Path -LiteralPath $SourceProject).Path
    Add-Report "SourceProject" "set" $SourceProject
}

Sync-ProjectRulesFromProfile
Sync-CursorCommands
Sync-OpenspecScaffold

# Scaffold dirs
$dirs = @(
    "src\cf", "src\cfe", "src\epf", "src\erf",
    "build\out\syntax-check\junit", "build\out\syntax-check\allure",
    "build\out\epf", "build\out\erf",
    "tools\web-test\scenarios\after-load", "tools\web-test\scenarios\manual",
    "docs", ".cursor", ".cursor\commands",
    "openspec", "openspec\templates", "openspec\specs",
    "openspec\changes", "openspec\changes\archive"
)
foreach ($d in $dirs) {
    Ensure-Dir (Join-Path $ProjectRoot $d)
}

Copy-NinjaLive

# README in src/cfe if empty marker
$cfeReadme = Join-Path $ProjectRoot "src\cfe\README.md"
if (-not (Test-Path -LiteralPath $cfeReadme)) {
    $readme = @"
# Код расширений

Предназначен для хранения исходных текстов расширений конфигурации, созданных на платформе 1С:Предприятие.
На каждое расширение создается отдельный подкаталог с именем расширения.
"@
    [void](Write-FileSafe -Path $cfeReadme -Content $readme -OnlyIfMissing)
}

$excludes = Join-Path $ProjectRoot "tools\syntax-check-excludes.txt"
if (-not (Test-Path -LiteralPath $excludes)) {
    [void](Write-FileSafe -Path $excludes -Content "# syntax-check excludes`n" -OnlyIfMissing)
}

Write-AutumnProperties
if ($IbConnection -or $DbUser -or $PSBoundParameters.ContainsKey("DbPwd") -or $V8Version) {
    if ((Test-Path -LiteralPath (Join-Path $ProjectRoot "autumn-properties.json")) -or $dryRun) {
        Patch-AutumnCredentials
    }
}

Write-RepositoryJson
Write-BslAnalyzerToml
Write-McpFiles
Test-UserMcpOverlap
Merge-Gitignore

# docs/dev-stack.md
$devStack = Join-Path $ProjectRoot "docs\dev-stack.md"
if (-not (Test-Path -LiteralPath $devStack)) {
    if (-not ($SourceProject -and (Copy-FromSource "docs\dev-stack.md"))) {
        [void](Write-FileSafe -Path $devStack -Content (Get-Template "dev-stack.md.tpl") -OnlyIfMissing)
    }
}

# smoke.config
$smoke = Join-Path $ProjectRoot "tools\web-test\smoke.config.json"
if (-not (Test-Path -LiteralPath $smoke)) {
    if (-not ($SourceProject -and (Copy-FromSource "tools\web-test\smoke.config.json"))) {
        $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
        $webPort = 8083
        if ($V8Version -like "8.5*") { $webPort = 8085 }
        elseif ((Test-Path (Join-Path $ProjectRoot "autumn-properties.json"))) {
            try {
                $aj = Get-Content (Join-Path $ProjectRoot "autumn-properties.json") -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($aj.vrunner.v8version -like "8.5*") { $webPort = 8085 }
                if ($aj.web.port) { $webPort = [int]$aj.web.port }
            } catch {}
        }
        $tpl = (Get-Template "smoke.config.json.tpl").Replace("{{APP_NAME}}", $app).Replace("{{WEB_PORT}}", "$webPort")
        [void](Write-FileSafe -Path $smoke -Content $tpl -OnlyIfMissing)
    }
}

# Default after-load script stub
$defaultJs = Join-Path $ProjectRoot "tools\web-test\scenarios\after-load\default.js"
if (-not (Test-Path -LiteralPath $defaultJs)) {
    $js = "// placeholder smoke scenario - replace after web-publish`r`nmodule.exports = async function () { /* no-op */ };`r`n"
    [void](Write-FileSafe -Path $defaultJs -Content $js -OnlyIfMissing)
}

# repository.json MUST exist after Init
$repoPath = Join-Path $ProjectRoot "repository.json"
if (-not (Test-Path -LiteralPath $repoPath) -and -not $dryRun) {
    Write-Host "Error: repository.json is required but missing" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $repoPath) -and $dryRun) {
    Add-Report "repository.json" "fail" "required"
}

# Sync CFE (no Enterprise list; names from live_extensions_list or fallback repo+src)
if (-not $SkipSyncCfe -and $Mode -ne "Check") {
    $syncScript = Join-Path $scriptDir "sync-cfe.ps1"
    $syncArgs = @{ ProjectRoot = $ProjectRoot; SkipIb = $true }
    if ($ExtensionNames) { $syncArgs.ExtensionNames = $ExtensionNames }
    Write-Host ""
    Write-Host "=== sync-cfe ===" -ForegroundColor Cyan
    & $syncScript @syncArgs
    Add-Report "sync-cfe" "done" ""
} elseif ($Mode -eq "Check") {
    Add-Report "sync-cfe" "skipped" "Check mode"
}

Write-Host ""
Write-Host "=== Report ===" -ForegroundColor Cyan
$report | Format-Table -AutoSize

Write-Host ""
Write-Host "Manual next steps:" -ForegroundColor Yellow
Write-Host "  1. Reload MCP in Cursor (project .cursor/mcp.json is the only 1C MCP source)"
Write-Host "  2. cfe_load NinjaLive -> web-publish -> live_extensions_list -> sync-cfe -ExtensionNames (NOT vrunner extensions list)"
Write-Host "  3. Warm bsl-analyzer graph (metadata/graph status -> ready)"
Write-Host "  4. toolkit :6003 only as fallback"
Write-Host "  5. User %USERPROFILE%\.cursor\mcp.json must NOT repeat vrunner/autumn/toolkit/bsl-analyzer-*"

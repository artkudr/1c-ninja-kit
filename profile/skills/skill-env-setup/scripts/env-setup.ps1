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
    .\env-setup.ps1 -Mode Init -SourceProject C:\1C\projects\my-project -IbConnection '/S"srv/db"' -DbUser Admin -DbPwd secret
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
    [int]$WebPort = 0,

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

# $PSBoundParameters inside a function is that function's own table, so an explicitly
# passed -DbPwd "" (empty password) was never honored in MCP/config files. Capture once.
$DbPwdProvided = $PSBoundParameters.ContainsKey("DbPwd")

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

function Get-KitRoot {
    # Kit reference for NinjaLive. Installed skill lives outside the kit, so probe
    # env override, the canonical machine path, then siblings of the project.
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:NINJA_KIT_ROOT) { [void]$candidates.Add($env:NINJA_KIT_ROOT) }
    [void]$candidates.Add("C:\1C\projects\1c-ninja-kit")
    $parent = Split-Path -Parent $ProjectRoot
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c "manifest.yaml")) -and
            (Test-Path -LiteralPath (Join-Path $c "project-scaffold\cfe\NinjaLive\Configuration.xml"))) {
            return $c
        }
    }
    return $null
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
    # Kit reference: canonical NinjaLive pair shipped with 1c-ninja-kit.
    $kitRoot = Get-KitRoot
    if ($kitRoot) {
        $fromKit = Join-Path $kitRoot "project-scaffold\cfe\NinjaLive"
        if (Test-Path -LiteralPath (Join-Path $fromKit "Configuration.xml")) {
            $rp = (Resolve-Path -LiteralPath $fromKit).Path
            if ($candidates -notcontains $rp) { [void]$candidates.Add($rp) }
        }
    }
    # Fallback: probe sibling projects (any repo next to this one that carries
    # NinjaLive sources). Generic on purpose - no project is hardcoded here.
    $siblings = @()
    try {
        $parent = Split-Path -Parent $ProjectRoot
        if ($parent -and (Test-Path -LiteralPath $parent)) {
            $siblings = @(Get-ChildItem -LiteralPath $parent -Directory -Force -EA SilentlyContinue)
        }
    } catch { $siblings = @() }
    foreach ($sib in $siblings) {
        $probe = Join-Path $sib.FullName "src\cfe\NinjaLive"
        if (Test-Path -LiteralPath (Join-Path $probe "Configuration.xml")) {
            $rp = (Resolve-Path -LiteralPath $probe).Path
            if ($candidates -notcontains $rp) { [void]$candidates.Add($rp) }
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
            Add-Report "src/cfe/NinjaLive" "fail" "source missing (pass -SourceProject <path>, or keep NinjaLive sources in a sibling repo)"
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
                (Test-Path -LiteralPath (Join-Path $_.FullName ".v8-project.json"))
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

function Get-V8PathForVersion([string]$Version) {
    $installed = Get-ChildItem 'C:\Program Files\1cv8\*\bin\1cv8.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Directory.Parent.Name } | Sort-Object -Unique
    if ($Version) {
        $m = $installed | Where-Object { $_ -like "$Version*" } |
            Sort-Object { try { [version]$_ } catch { [version]'0.0' } } -Descending | Select-Object -First 1
        if ($m) { return (Join-Path "C:\Program Files\1cv8\$m" 'bin') }
    }
    $best = $installed | Sort-Object { try { [version]$_ } catch { [version]'0.0' } } -Descending | Select-Object -First 1
    if ($best) { return (Join-Path "C:\Program Files\1cv8\$best" 'bin') }
    return ''
}

function ConvertFrom-IbConnectionToDbRecord([string]$Conn) {
    # /F"path" | /Fpath | /S"server\ref" | /Sserver\ref | /server/ref
    $c = $Conn.Trim()
    if ($c -match '^/F\s*"?([^"]+)"?$') {
        return [ordered]@{ type = 'file'; path = $Matches[1].TrimEnd('"') }
    }
    if ($c -match '^/S\s*"?([^"\\/]+)[\\/]([^"]+)"?$') {
        return [ordered]@{ type = 'server'; server = $Matches[1]; ref = $Matches[2].TrimEnd('"') }
    }
    if ($c -match '^/?([^/\\]+)[\\/](.+)$') {
        return [ordered]@{ type = 'server'; server = $Matches[1]; ref = $Matches[2] }
    }
    throw "Cannot parse ibconnection: $Conn"
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
    $needed = @(".build/", "/build/", ".v8-project.json")
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
    $append = "`r`n# skill-env-setup`r`n" + ($toAdd -join "`r`n") + "`r`n"
    Add-Content -LiteralPath $gi -Value $append -Encoding UTF8
    Add-Report ".gitignore" "updated" ($toAdd -join ", ")
}

function Get-ProjectContextVars {
    $name = (Split-Path $ProjectRoot -Leaf)
    return [pscustomobject]@{
        ProjectName = $name
    }
}

function Expand-TemplateContent {
    param([string]$Content, [object]$Vars)
    return $Content.Replace("{{PROJECT_NAME}}", $Vars.ProjectName)
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

function Sync-ProjectRulesFromProfile {
    # Kit rules live in the global OpenCode profile: AGENTS.md + skills/kit/rules.
    Add-Report "rules" "n/a" "opencode: global AGENTS.md + skills/kit/rules (kit.ps1 apply)"
}
function Write-V8Project {
    $path = Join-Path $ProjectRoot ".v8-project.json"
    if ((Test-Path -LiteralPath $path) -and -not $Force -and $Mode -eq "Refresh") {
        Add-Report ".v8-project.json" "skip" "Refresh without -Force"
        return
    }
    if ((Test-Path -LiteralPath $path) -and -not $Force -and -not $IbConnection) {
        Add-Report ".v8-project.json" "skip" "exists"
        return
    }

    # Prefer copy from source then patch
    if ($SourceProject -and (Test-Path -LiteralPath (Join-Path $SourceProject ".v8-project.json")) -and -not $IbConnection) {
        [void](Copy-FromSource ".v8-project.json")
        return
    }

    $v8 = $V8Version
    if (-not $v8 -and $SourceProject) {
        $sp = Join-Path $SourceProject ".v8-project.json"
        if (Test-Path -LiteralPath $sp) {
            try {
                $sj = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($sj.v8path -and $sj.v8path -match '([0-9]+(\.[0-9]+){2,})') { $v8 = $Matches[1] }
                if (-not $DbUser -and $sj.databases -and @($sj.databases).Count -gt 0 -and $sj.databases[0].user) {
                    $script:DbUser = [string]$sj.databases[0].user
                }
            } catch {}
        }
    }
    if (-not $v8) { $v8 = Get-DetectedV8Version }

    $conn = $IbConnection
    if (-not $conn) { $conn = '/S"server/infobase"' }
    $user = if ($DbUser) { $DbUser } else { "" }
    $pwd = if ($null -ne $DbPwd) { $DbPwd } else { "" }

    $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
    $webPort = Resolve-WebPort

    $dbRec = ConvertFrom-IbConnectionToDbRecord $conn
    $dbRec.id = "main"
    $dbRec.name = $app
    $dbRec.user = $user
    $dbRec.password = $pwd
    $dbRec.configSrc = "src\cf"
    $dbRec.extensions = @()
    $obj = [ordered]@{
        v8path    = (Get-V8PathForVersion $v8)
        databases = @($dbRec)
        default   = "main"
        web       = [ordered]@{ appName = $app; port = $webPort }
    }
    [void](Write-FileSafe -Path $path -Content (($obj | ConvertTo-Json -Depth 6) + "`n"))
}

function Patch-V8ProjectCredentials {
    $path = Join-Path $ProjectRoot ".v8-project.json"
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not $IbConnection -and -not $DbUser -and -not $DbPwdProvided -and -not $V8Version) { return }
    if ($dryRun) {
        Add-Report ".v8-project.json" "would-patch" "credentials/ibconnection"
        return
    }
    $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.databases -or @($j.databases).Count -eq 0) {
        $j | Add-Member -NotePropertyName databases -NotePropertyValue @([ordered]@{
            id = "main"; name = (Split-Path $ProjectRoot -Leaf).ToLowerInvariant(); type = "file"
            user = ""; password = ""; configSrc = "src\cf"; extensions = @()
        }) -Force
    }
    $db = $j.databases[0]
    if ($IbConnection) {
        $rec = ConvertFrom-IbConnectionToDbRecord $IbConnection
        $db | Add-Member -NotePropertyName type -NotePropertyValue $rec.type -Force
        if ($rec.Contains("path")) {
            $db | Add-Member -NotePropertyName path -NotePropertyValue $rec.path -Force
        } else {
            $db | Add-Member -NotePropertyName server -NotePropertyValue $rec.server -Force
            $db | Add-Member -NotePropertyName ref -NotePropertyValue $rec.ref -Force
        }
    }
    if ($DbUser) { $db | Add-Member -NotePropertyName user -NotePropertyValue $DbUser -Force }
    if ($DbPwdProvided) { $db | Add-Member -NotePropertyName password -NotePropertyValue $DbPwd -Force }
    if ($V8Version) { $j | Add-Member -NotePropertyName v8path -NotePropertyValue (Get-V8PathForVersion $V8Version) -Force }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ($j | ConvertTo-Json -Depth 20), $utf8)
    Add-Report ".v8-project.json" "patched" "credentials"
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

function Resolve-WebPort {
    # Priority: -WebPort > .v8-project.json web.port > 8083/8085 by platform (kit rule).
    if ($WebPort -gt 0) { return $WebPort }
    $ap = Join-Path $ProjectRoot ".v8-project.json"
    if (Test-Path -LiteralPath $ap) {
        try {
            $aj = Get-Content -LiteralPath $ap -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($aj.web.port) { return [int]$aj.web.port }
        } catch {}
    }
    if ($V8Version -like "8.5*") { return 8085 }
    return 8083
}

function Write-ProjectAgents {
    # AGENTS.md — единственная always-on память проекта. Не перезаписываем ручные правки.
    $path = Join-Path $ProjectRoot "AGENTS.md"
    if (Test-Path -LiteralPath $path) {
        Add-Report "AGENTS.md" "skip" "exists (project memory; edit manually)"
        return
    }
    $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
    $webPort = Resolve-WebPort
    $v8 = if ($V8Version) { $V8Version } else { "8.3" }
    $ib = if ($IbConnection) { $IbConnection } else { "см. .v8-project.json" }
    $projectName = Split-Path $ProjectRoot -Leaf
    $content = (Get-Template "AGENTS.md.tpl").
        Replace("{{PROJECT_NAME}}", $projectName).
        Replace("{{APP_NAME}}", $app).
        Replace("{{PROJECT_ROOT}}", $ProjectRoot).
        Replace("{{WEB_PORT}}", "$webPort").
        Replace("{{V8_VERSION}}", $v8).
        Replace("{{IB_CONNECTION}}", $ib)
    [void](Write-FileSafe -Path $path -Content $content -OnlyIfMissing)
}

function Get-McpMachinePaths {
    # Ninja MCP main.os: env override, then the 1c-ninja-kit component.
    $roots = @()
    if ($env:NINJA_MCP_ROOT) { $roots += $env:NINJA_MCP_ROOT }
    $roots += "C:\1C\projects\1c-ninja-kit\components\1c-ninja-mcp"
    $ninjaRoot = $null
    foreach ($r in $roots) {
        if (Test-Path -LiteralPath (Join-Path $r "main.os")) { $ninjaRoot = $r; break }
    }
    if (-not $ninjaRoot) { $ninjaRoot = $roots[0] }
    return [pscustomobject]@{
        BslAnalyzerExe    = Join-Path $env:LOCALAPPDATA "bsl-analyzer\bsl-analyzer.exe"
        BslAnalyzerAppExe = Join-Path $env:USERPROFILE ".bsl-analyzer\bin\bsl-analyzer-app.exe"
        NinjaMain         = Join-Path $ninjaRoot "main.os"
        ShcntxHelpDb      = Join-Path $ninjaRoot "src\data\shcntx_help.db"
        NinjaRoot         = $ninjaRoot
    }
}

function Test-UserMcpOverlap {
    $userMcp = Join-Path $env:USERPROFILE ".config\opencode\opencode.jsonc"
    if (-not (Test-Path -LiteralPath $userMcp)) {
        $userMcp = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
    }
    $canonNames = @(
        "1c-mcp-toolkit",
        "1c-ninja-mcp",
        "bsl-analyzer-reference",
        "bsl-analyzer-workspace",
        "v8std"
    )
    if (-not (Test-Path -LiteralPath $userMcp)) {
        Add-Report "user mcp.json" "ok" "absent (1C MCP lives in project)"
        return
    }
    try {
        $j = Get-Content -LiteralPath $userMcp -Raw -Encoding UTF8 | ConvertFrom-Json
        $names = @()
        if ($j.mcp -and $j.mcp.servers) { $names = @($j.mcp.servers.PSObject.Properties.Name) }
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

function Get-OpenCodeConfigFromTemplate {
    param(
        [string]$User,
        [string]$Password,
        [string]$AppName,
        [string]$WebPort,
        [string]$ProjectRootPath
    )
    $paths = Get-McpMachinePaths
    $tpl = Get-Template "opencode.jsonc.tpl"
    return $tpl.
        Replace("{{NINJA_MAIN}}", (ConvertTo-McpJsonPath $paths.NinjaMain)).
        Replace("{{SHCNTX_HELP_DB}}", (ConvertTo-McpJsonPath $paths.ShcntxHelpDb)).
        Replace("{{BSL_ANALYZER_EXE}}", (ConvertTo-McpJsonPath $paths.BslAnalyzerExe)).
        Replace("{{BSL_ANALYZER_APP_EXE}}", (ConvertTo-McpJsonPath $paths.BslAnalyzerAppExe)).
        Replace("{{PROJECT_ROOT}}", (ConvertTo-McpJsonPath $ProjectRootPath)).
        Replace("{{WEB_PORT}}", "$WebPort").
        Replace("{{APP_NAME}}", $AppName).
        Replace("{{IB_USER}}", (ConvertTo-McpJsonString $User)).
        Replace("{{IB_PASSWORD}}", (ConvertTo-McpJsonString $Password))
}

function Write-OpenCodeMcpFiles {
    # OpenCode V2: mcp.servers в project opencode.jsonc (в .gitignore, содержит пароль ИБ).
    $app = if ($AppName) { $AppName } else { (Split-Path $ProjectRoot -Leaf).ToLowerInvariant() }
    $webPort = Resolve-WebPort

    $path = Join-Path $ProjectRoot "opencode.jsonc"
    if ((Test-Path -LiteralPath $path) -and -not $Force -and $Mode -eq "Refresh") {
        Add-Report "opencode.jsonc" "skip" "Refresh"
        return
    }
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Add-Report "opencode.jsonc" "skip" "exists (use -Force)"
        return
    }
    $user = if ($DbUser) { $DbUser } else { "<user>" }
    $pwd = if ($DbPwdProvided) { $DbPwd } else { "<password>" }
    $content = Get-OpenCodeConfigFromTemplate -User $user -Password $pwd `
        -AppName $app -WebPort "$webPort" -ProjectRootPath $ProjectRoot
    if ($dryRun) {
        Add-Report "opencode.jsonc" "would-create" "from skill template"
        return
    }
    [void](Write-FileSafe -Path $path -Content $content)
    Add-Report "opencode.jsonc" "created" "NINJA_URL=http://localhost:$webPort/$app/hs/ninja-live"
}

function Write-McpFiles {
    Write-OpenCodeMcpFiles
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

Write-Host "=== skill-env-setup ($Mode) ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

# Sanity: платформа + скиллы контура
$v8exe = Get-ChildItem @(
    "C:\Program Files\1cv8\*\bin\1cv8.exe",
    "C:\Program Files (x86)\1cv8\*\bin\1cv8.exe"
) -ErrorAction SilentlyContinue | Select-Object -First 1
if ($v8exe) {
    Add-Report "1cv8" "ok" $v8exe.FullName
} else {
    Add-Report "1cv8" "fail" "not found - platform missing"
    if ($Mode -ne "Check") {
        Write-Host "Error: 1cv8 not found. Install the 1C platform on this machine first." -ForegroundColor Red
        $report | Format-Table -AutoSize
        exit 1
    }
}

$ccSkillsRoot = Join-Path $env:USERPROFILE ".config\opencode\skills"
if (Test-Path -LiteralPath (Join-Path $ccSkillsRoot "db-list\SKILL.md")) {
    Add-Report "cc-1c-skills" "ok" "installed"
} else {
    Add-Report "cc-1c-skills" "fail" "missing - run install\cc-skills.ps1"
    if ($Mode -ne "Check") {
        Write-Host "Error: cc-1c-skills not installed. Run: C:\1C\projects\1c-ninja-kit\install\cc-skills.ps1" -ForegroundColor Red
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

# Scaffold dirs
$dirs = @(
    "src\cf", "src\cfe", "src\epf", "src\erf",
    "build\out\syntax-check\junit", "build\out\syntax-check\allure",
    "build\out\cfe", "build\out\epf", "build\out\erf",
    "tools\web-test\scenarios\after-load", "tools\web-test\scenarios\manual",
    "docs", ".opencode"
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

Write-V8Project
if ($IbConnection -or $DbUser -or $PSBoundParameters.ContainsKey("DbPwd") -or $V8Version) {
    if ((Test-Path -LiteralPath (Join-Path $ProjectRoot ".v8-project.json")) -or $dryRun) {
        Patch-V8ProjectCredentials
    }
}

Write-BslAnalyzerToml
Write-McpFiles
Write-ProjectAgents
Test-UserMcpOverlap
Merge-Gitignore

# .ignore for ripgrep (works in folders without .git)
$ignorePath = Join-Path $ProjectRoot ".ignore"
if (-not (Test-Path -LiteralPath $ignorePath)) {
    [void](Write-FileSafe -Path $ignorePath -Content (Get-Template "ignore-rg.snippet") -OnlyIfMissing)
}

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
        $webPort = Resolve-WebPort
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

# .v8-project.json MUST exist after Init
$repoPath = Join-Path $ProjectRoot ".v8-project.json"
if (-not (Test-Path -LiteralPath $repoPath) -and -not $dryRun) {
    Write-Host "Error: .v8-project.json is required but missing" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $repoPath) -and $dryRun) {
    Add-Report ".v8-project.json" "fail" "required"
}

# Sync CFE (no Enterprise list; names from live_extensions_list or fallback repo+src)
if (-not $SkipSyncCfe -and $Mode -ne "Check") {
    $syncScript = Join-Path $scriptDir "sync-cfe.ps1"
    $syncArgs = @{ ProjectRoot = $ProjectRoot }
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
    Write-Host "  1. Reload MCP in OpenCode (project opencode.jsonc is the only 1C MCP source)"
    Write-Host "  2. Load NinjaLive: db-load-xml -Extension -> web-publish -> live_extensions_list -> sync-cfe -ExtensionNames"
    Write-Host "  3. Warm bsl-analyzer graph (metadata/graph status -> ready)"
    Write-Host "  4. toolkit :6003 only as fallback (server is disabled in opencode.jsonc by default)"
    Write-Host "  5. Global %USERPROFILE%\.config\opencode\opencode.json(c) must NOT repeat 1C MCP server names"
    Write-Host "  6. Always-on rules come from %USERPROFILE%\.config\opencode\AGENTS.md (kit.ps1 apply)"

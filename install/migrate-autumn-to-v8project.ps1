# migrate-autumn-to-v8project.ps1 — одноразовая миграция проекта на .v8-project.json
#
# Читает autumn-properties.json + repository.json, пишет .v8-project.json,
# удаляет из opencode.jsonc блок сервера vrunner, правит .gitignore,
# удаляет autumn/repository. Идемпотентен к повторному запуску (пропускает готовое).
#
# Использование:
#   powershell -NoProfile -File install\migrate-autumn-to-v8project.ps1 -ProjectRoot C:\1C\projects\dt-bp3
#   ... -DryRun

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Add-Report([string]$What, [string]$Action, [string]$Note = "") {
    Write-Host ("  [{0,-10}] {1} {2}" -f $Action, $What, $Note)
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

function Remove-VrunnerServerBlock([string]$text) {
    $m = [regex]::Match($text, '"vrunner"\s*:\s*\{')
    if (-not $m.Success) { return $text }
    $start = $m.Index
    $braceStart = $text.IndexOf('{', $start)
    $depth = 0; $i = $braceStart
    for (; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { break } }
    }
    $end = $i
    $after = $end + 1
    while ($after -lt $text.Length -and ($text[$after] -eq ' ' -or $text[$after] -eq "`t")) { $after++ }
    if ($after -lt $text.Length -and $text[$after] -eq ',') {
        $after++
    } else {
        $before = $start - 1
        while ($before -ge 0 -and ($text[$before] -eq ' ' -or $text[$before] -eq "`t")) { $before-- }
        if ($before -ge 0 -and $text[$before] -eq ',') { $start = $before }
    }
    return $text.Remove($start, $after - $start)
}

Write-Host "=== migrate $ProjectRoot ===" -ForegroundColor Cyan

# --- autumn ---
$autumnPath = Join-Path $ProjectRoot "autumn-properties.json"
$repoPath = Join-Path $ProjectRoot "repository.json"
$regPath = Join-Path $ProjectRoot ".v8-project.json"
if (-not (Test-Path -LiteralPath $autumnPath)) {
    Write-Host "  autumn-properties.json отсутствует — миграция не требуется" -ForegroundColor Yellow
    return 0
}
$autumn = Get-Content -LiteralPath $autumnPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repository = $null
if (Test-Path -LiteralPath $repoPath) {
    $repository = Get-Content -LiteralPath $repoPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# --- src/cfe ---
$cfeDir = Join-Path $ProjectRoot "src\cfe"
$extNames = @()
if (Test-Path -LiteralPath $cfeDir) {
    $extNames = @(Get-ChildItem -LiteralPath $cfeDir -Directory | ForEach-Object { $_.Name })
}

# --- .v8-project.json ---
$v8version = ""
if ($autumn.vrunner -and $autumn.vrunner.v8version) { $v8version = [string]$autumn.vrunner.v8version }
$conn = ""
if ($autumn.vrunner -and $autumn.vrunner.ibconnection) { $conn = [string]$autumn.vrunner.ibconnection }
$user = ""
if ($autumn.vrunner -and $null -ne $autumn.vrunner.'db-user') { $user = [string]$autumn.vrunner.'db-user' }
$pwd = ""
if ($autumn.vrunner -and $null -ne $autumn.vrunner.'db-pwd') { $pwd = [string]$autumn.vrunner.'db-pwd' }

$dbRec = ConvertFrom-IbConnectionToDbRecord $conn
$appName = (Split-Path $ProjectRoot -Leaf).ToLowerInvariant()
$webPort = $null
if ($autumn.web) {
    if ($autumn.web.appName) { $appName = [string]$autumn.web.appName }
    if ($null -ne $autumn.web.port -and "$($autumn.web.port)" -ne "") { $webPort = [int]$autumn.web.port }
}
if (-not $webPort) { $webPort = if ($v8version -like "8.5*") { 8085 } else { 8083 } }

$extensions = @()
foreach ($n in ($extNames | Sort-Object)) {
    $e = [ordered]@{ name = $n; src = "src\cfe\$n" }
    if ($repository -and $repository.cfe -and ($repository.cfe.PSObject.Properties.Name -contains $n)) {
        $folder = [string]$repository.cfe.$n
        $e.repository = [ordered]@{
            path      = (Join-Path ([string]$repository.root) $folder)
            user      = [string]$repository.user
            password  = ""
            adminUser = [string]$repository.adminUser
        }
    }
    $extensions += $e
}

$dbRec.id = "main"
$dbRec.name = $appName
$dbRec.user = $user
$dbRec.password = $pwd
$dbRec.configSrc = "src\cf"
$dbRec.extensions = $extensions

$project = [ordered]@{
    v8path    = (Get-V8PathForVersion $v8version)
    databases = @($dbRec)
    default   = "main"
    web       = [ordered]@{ appName = $appName; port = $webPort }
}
if ($autumn.vrunner -and $autumn.vrunner.validate -and $autumn.vrunner.validate.'syntax-check') {
    $sc = $autumn.vrunner.validate.'syntax-check'
    $v = [ordered]@{}
    if ($sc.mode) { $v.mode = @($sc.mode) }
    if ($sc.'exception-file') { $v.exceptionFile = [string]$sc.'exception-file' }
    if ($v.Count -gt 0) { $project.validate = [ordered]@{ 'syntax-check' = $v } }
}

if ($DryRun) {
    Add-Report ".v8-project.json" "would-write" "(db=$appName, ext=$($extensions.Count))"
} else {
    [IO.File]::WriteAllText($regPath, (($project | ConvertTo-Json -Depth 8) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Add-Report ".v8-project.json" "written" "(db=$appName, ext=$($extensions.Count), repo-ext=$(@($extensions | Where-Object { $_.repository }).Count))"
}

# --- opencode.jsonc: убрать блок vrunner ---
$ocPath = Join-Path $ProjectRoot "opencode.jsonc"
if (Test-Path -LiteralPath $ocPath) {
    $oc = Get-Content -LiteralPath $ocPath -Raw -Encoding UTF8
    if ($oc -match '"vrunner"') {
        $ocNew = Remove-VrunnerServerBlock $oc
        # env AUTUMN_PROPERTIES больше не нужен (реестр — .v8-project.json)
        $ocNew = ($ocNew -split "`r?`n" | Where-Object { $_ -notmatch '"AUTUMN_PROPERTIES"' }) -join "`r`n"
        if ($DryRun) {
            Add-Report "opencode.jsonc" "would-edit" "remove vrunner server"
        } else {
            [IO.File]::WriteAllText($ocPath, $ocNew, (New-Object System.Text.UTF8Encoding($false)))
            Add-Report "opencode.jsonc" "edited" "vrunner server removed"
        }
    } else {
        Add-Report "opencode.jsonc" "ok" "no vrunner server"
    }
} else {
    Add-Report "opencode.jsonc" "skip" "absent"
}

# --- .gitignore ---
$giPath = Join-Path $ProjectRoot ".gitignore"
if (Test-Path -LiteralPath $giPath) {
    $gi = Get-Content -LiteralPath $giPath -Raw -Encoding UTF8
    $giNew = $gi
    if ($giNew -notmatch '(?m)^\.v8-project\.json\s*$') { $giNew = $giNew.TrimEnd() + "`r`n.v8-project.json`r`n" }
    if ($giNew -notmatch '(?m)^\.v8-xsd/\s*$') { $giNew = $giNew.TrimEnd() + "`r`n.v8-xsd/`r`n" }
    $giNew = ($giNew -split "`r?`n" | Where-Object { $_ -notmatch '^\s*autumn-properties\.json\s*$' -and $_ -notmatch '^\s*repository\.json\s*$' }) -join "`r`n"
    if ($giNew -ne $gi) {
        if ($DryRun) { Add-Report ".gitignore" "would-edit" "v8-project + v8-xsd" }
        else { [IO.File]::WriteAllText($giPath, $giNew, (New-Object System.Text.UTF8Encoding($false))); Add-Report ".gitignore" "edited" "" }
    } else {
        Add-Report ".gitignore" "ok" ""
    }
}

# --- удалить autumn / repository ---
foreach ($f in @("autumn-properties.json", "repository.json")) {
    $p = Join-Path $ProjectRoot $f
    if (Test-Path -LiteralPath $p) {
        if ($DryRun) { Add-Report $f "would-delete" "" }
        else { Remove-Item -LiteralPath $p -Force; Add-Report $f "deleted" "" }
    }
}

Write-Host "=== done ===" -ForegroundColor Cyan
return 0

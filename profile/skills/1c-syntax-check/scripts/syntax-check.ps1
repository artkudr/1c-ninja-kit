# syntax-check.ps1 — платформенный синтаксический контроль конфигурации (DESIGNER /CheckConfig)
#
# Читает .v8-project.json (вверх от ProjectRoot): v8path, запись базы, validate.syntax-check.
# Расширения проверяет db-cfe-admin check; здесь — основная конфигурация (и опционально -Extension).
#
# Код возврата: 0 — ошибок нет; 1 — есть ошибки / сбой.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$Extension,

    [Parameter(Mandatory = $false)]
    [string[]]$Modes,

    [Parameter(Mandatory = $false)]
    [string]$ExceptionFile,

    [Parameter(Mandatory = $false)]
    [string]$V8Path,

    [Parameter(Mandatory = $false)]
    [string]$InfoBasePath,

    [Parameter(Mandatory = $false)]
    [string]$InfoBaseServer,

    [Parameter(Mandatory = $false)]
    [string]$InfoBaseRef,

    [Parameter(Mandatory = $false)]
    [string]$UserName,

    [Parameter(Mandatory = $false)]
    [string]$Password
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Find-V8Project([string]$startDir) {
    $d = $startDir
    for ($i = 0; $i -lt 20 -and $d; $i++) {
        $pj = Join-Path $d ".v8-project.json"
        if (Test-Path $pj) { return $pj }
        $parent = [System.IO.Path]::GetDirectoryName($d)
        if ($parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

function Get-DefaultV8Path {
    $found = Get-ChildItem @(
        "C:\Program Files\1cv8\*\bin\1cv8.exe",
        "C:\Program Files (x86)\1cv8\*\bin\1cv8.exe"
    ) -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]"0.0.0.0" } } -Descending |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

$projFile = Find-V8Project (Resolve-Path -LiteralPath $ProjectRoot).Path
$proj = $null
$dbRec = $null
if ($projFile) {
    try {
        $proj = Get-Content -LiteralPath $projFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $databases = @($proj.databases)
        if ($databases.Count -gt 0) {
            $dbRec = $databases | Where-Object { $_.id -eq $proj.default } | Select-Object -First 1
            if (-not $dbRec) { $dbRec = $databases[0] }
        }
    } catch {}
}

# Платформа: явный путь > v8path реестра > авто
if (-not $V8Path -and $proj -and $proj.v8path) { $V8Path = [string]$proj.v8path }
if ($V8Path -and (Test-Path -LiteralPath $V8Path -PathType Container)) { $V8Path = Join-Path $V8Path "1cv8.exe" }
if (-not $V8Path -or -not (Test-Path -LiteralPath $V8Path)) {
    $auto = Get-DefaultV8Path
    if (-not $auto) { Write-Host "Error: 1cv8.exe not found (set v8path in .v8-project.json or -V8Path)" -ForegroundColor Red; exit 1 }
    if (-not $V8Path) { $V8Path = $auto }
}
if (-not (Test-Path -LiteralPath $V8Path)) { Write-Host "Error: 1cv8.exe not found at $V8Path" -ForegroundColor Red; exit 1 }

# Подключение: явные параметры > запись реестра
if (-not $InfoBasePath -and -not $InfoBaseServer -and $dbRec) {
    if ($dbRec.type -eq "server") { $InfoBaseServer = [string]$dbRec.server; $InfoBaseRef = [string]$dbRec.ref }
    elseif ($dbRec.path) { $InfoBasePath = [string]$dbRec.path }
}
if (-not $UserName -and $dbRec -and $dbRec.user) { $UserName = [string]$dbRec.user }
if (-not $Password -and $dbRec -and $null -ne $dbRec.password) { $Password = [string]$dbRec.password }
if (-not $InfoBasePath -and -not ($InfoBaseServer -and $InfoBaseRef)) {
    Write-Host "Error: no database (set default record in .v8-project.json or pass -InfoBasePath/-InfoBaseServer)" -ForegroundColor Red
    exit 1
}

# Режимы и исключения
$validate = $null
if ($proj -and $proj.validate -and $proj.validate.'syntax-check') { $validate = $proj.validate.'syntax-check' }
if (-not $Modes -or $Modes.Count -eq 0) {
    if ($validate -and $validate.mode) { $Modes = @($validate.mode) }
    else { $Modes = @('ExtendedModulesCheck', 'ThinClient', 'WebClient', 'Server', 'ExternalConnection', 'ThickClientOrdinaryApplication') }
}
$exceptionPatterns = @()
if (-not $ExceptionFile -and $validate -and $validate.exceptionFile) {
    $ExceptionFile = [string]$validate.exceptionFile
}
if ($ExceptionFile) {
    if (-not [System.IO.Path]::IsPathRooted($ExceptionFile)) {
        $base = if ($projFile) { Split-Path $projFile -Parent } else { $ProjectRoot }
        $ExceptionFile = Join-Path $base $ExceptionFile
    }
    if (Test-Path -LiteralPath $ExceptionFile) {
        $exceptionPatterns = @(Get-Content -LiteralPath $ExceptionFile -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } | ForEach-Object { $_.Trim() })
    }
}

# Ключи хранилища (основная конфигурация / расширение) из записи реестра
$repoKeys = @()
$repoRec = $null
if ($Extension) {
    if ($dbRec -and $dbRec.extensions) {
        $repoRec = @($dbRec.extensions | Where-Object { $_.name -eq $Extension } | Select-Object -First 1).repository
    }
} else {
    if ($dbRec -and $dbRec.repository) { $repoRec = $dbRec.repository }
}
if ($repoRec -and $repoRec.path) {
    $repoKeys += "/ConfigurationRepositoryF`"$($repoRec.path)`""
    if ($repoRec.user) { $repoKeys += "/ConfigurationRepositoryN`"$($repoRec.user)`"" }
    if ($null -ne $repoRec.password -and "$($repoRec.password)" -ne "") { $repoKeys += "/ConfigurationRepositoryP`"$($repoRec.password)`"" }
}

# Сборка команды
$conn = if ($InfoBasePath) { @("/F`"$InfoBasePath`"") } else { @("/S`"$InfoBaseServer/$InfoBaseRef`"") }
$auth = @()
if ($UserName) {
    $auth += "/N`"$UserName`""
    if ($null -ne $Password -and "$Password" -ne "") { $auth += "/P`"$Password`"" }
}
$modeArgs = @()
foreach ($m in $Modes) { if ($m) { $modeArgs += "-$m" } }

$outFile = Join-Path ([IO.Path]::GetTempPath()) ("syntax_check_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".log")
$argList = @("DESIGNER") + $conn + $auth + @("/CheckConfig") + $modeArgs
if ($Extension) { $argList += @("-Extension", "`"$Extension`"") }
$argList += $repoKeys
$argList += @("/Out", "`"$outFile`"", "/DisableStartupDialogs")

$displayArgs = ($argList -join " ")
if ($Password) { $displayArgs = $displayArgs.Replace($Password, "***") }
Write-Host ("Running: 1cv8.exe " + $displayArgs)
$p = Start-Process -FilePath $V8Path -ArgumentList $argList -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$outFile.stdout" -RedirectStandardError "$outFile.stderr"
$exit = $p.ExitCode

function Read-PlatformLog([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return "" }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { return "" }
    try { return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { return [System.Text.Encoding]::GetEncoding(866).GetString($bytes) }
}

$log = (Read-PlatformLog $outFile)
if (-not $log) { $log = (Read-PlatformLog "$outFile.stdout") }

$lines = @($log -split "`r?`n" | Where-Object { $_.Trim() })
$errorLines = @($lines | Where-Object { $_ -match '(?i)ошибк|error' })
if ($exceptionPatterns.Count -gt 0) {
    $errorLines = @($errorLines | Where-Object {
        $line = $_
        -not (@($exceptionPatterns | Where-Object { $line.Contains($_) }).Count -gt 0)
    })
}

if ($lines.Count -gt 0) {
    Write-Host "--- Log ---"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host "--- End ---"
}

if ($errorLines.Count -gt 0) {
    Write-Host ("Синтакс-контроль: ошибок $($errorLines.Count) (после исключений: $($exceptionPatterns.Count) паттернов)") -ForegroundColor Red
    exit 1
}
Write-Host "Синтакс-контроль: ошибок нет" -ForegroundColor Green
exit 0

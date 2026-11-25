# web-publish v1.10 — Publish 1C infobase via profile Apache (apache-83 / apache-85)
# Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
<#
.SYNOPSIS
    Публикация информационной базы 1С через Apache HTTP Server

.DESCRIPTION
    Генерирует default.vrd и настраивает httpd.conf.
    Apache — профильный (не в проекте):
      %USERPROFILE%\tools\apache-83  порт 8083  (платформа 8.3*)
      %USERPROFILE%\tools\apache-85  порт 8085  (платформа 8.5*)
    Если Apache нет — ставит его кит (install\kit.ps1 deps -What apache): версия
    и адрес загрузки живут в companions/pins.json, а не в этом скрипте.
    Платформа: -V8Path или v8path из .v8-project.json → bin с wsap24.dll.
    AppName: -AppName / web.appName из .v8-project.json / smoke webUrl / имя папки проекта.

.PARAMETER ApachePath
    Корень Apache; иначе web.apachePath из .v8-project.json или профиль apache-83/85.
    Может указывать на копию дерева: тогда Define SRVROOT / ServerRoot и пути
    pid/log привязываются к копии, рабочая установка не затрагивается.

.PARAMETER Port
    Порт; иначе web.port из .v8-project.json / smoke / 8083|8085 по версии

.PARAMETER PoolServices
    HTTP-сервисы с пулом сеансов (reuseSessions=autouse). Элемент — "Имя=rootUrl";
    строку делить не нужно: элементы через ',' или ';'. Принимается массив строк.
    Повтор параметра невозможен: PowerShell запрещает повтор именованного
    параметра языком — два сервиса задаются массивом или строкой с разделителем.
    Пустое имя, отсутствующий '=' и пустой rootUrl —
    ошибка входа (код 1). Иначе web.poolServices из .v8-project.json (строки
    или объекты { name, rootUrl }). Пусто — в vrd нет элементов service,
    publishByDefault остаётся true.

.PARAMETER SessionMaxAge
    Секунды простоя сеанса пула до замены; иначе web.poolSessionMaxAge / 20.

.PARAMETER PoolSize
    Сколько сеансов держать в пуле; иначе web.poolSize / 4.

.PARAMETER PoolTimeout
    Секунды ожидания свободного сеанса пула; иначе web.poolTimeout / 5.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$V8Path,

    [Parameter(Mandatory=$false)]
    [string]$V8Version,

    [Parameter(Mandatory=$false)]
    [string]$InfoBasePath,

    [Parameter(Mandatory=$false)]
    [string]$InfoBaseServer,

    [Parameter(Mandatory=$false)]
    [string]$InfoBaseRef,

    [Parameter(Mandatory=$false)]
    [string]$UserName,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [string]$AppName,

    [Parameter(Mandatory=$false)]
    [string]$ApachePath,

    [Parameter(Mandatory=$false)]
    [int]$Port = 0,

    [Parameter(Mandatory=$false)]
    [string[]]$PoolServices,

    [Parameter(Mandatory=$false)]
    [int]$SessionMaxAge = 0,

    [Parameter(Mandatory=$false)]
    [int]$PoolSize = 0,

    [Parameter(Mandatory=$false)]
    [int]$PoolTimeout = 0,

    [Parameter(Mandatory=$false)]
    [switch]$Manual
)

# --- Encoding ---
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot "Resolve-1cWebTargets.ps1")

function Get-VersionSortKey([string]$verName) {
    try { return [version]$verName } catch {
        $parts = [regex]::Matches($verName, '\d+') | ForEach-Object { [int]$_.Value }
        while ($parts.Count -lt 4) { $parts += 0 }
        return [version]::new($parts[0], $parts[1], $parts[2], $parts[3])
    }
}

function Find-PlatformBinByVersion([string]$versionSpec) {
    if (-not $versionSpec) { return $null }
    $exes = @()
    $exes += Get-ChildItem "C:\Program Files\1cv8\*\bin\1cv8.exe" -ErrorAction SilentlyContinue
    $exes += Get-ChildItem "${env:ProgramFiles(x86)}\1cv8\*\bin\1cv8.exe" -ErrorAction SilentlyContinue
    if (-not $exes) { return $null }

    $matched = foreach ($exe in $exes) {
        $verDir = $exe.Directory.Parent.Name
        $binDir = $exe.Directory.FullName
        $wsap = Join-Path $binDir "wsap24.dll"
        if (-not (Test-Path -LiteralPath $wsap)) { continue }
        $exact = ($verDir -eq $versionSpec)
        $prefix = ($verDir -like ($versionSpec + "*"))
        if (-not $exact -and -not $prefix) { continue }
        [pscustomobject]@{
            Bin = $binDir
            Ver = $verDir
            Exact = $exact
            Key = Get-VersionSortKey $verDir
        }
    }
    if (-not $matched) { return $null }
    $best = $matched | Sort-Object @{ Expression = 'Exact'; Descending = $true }, @{ Expression = 'Key'; Descending = $true } | Select-Object -First 1
    return $best
}

function ConvertTo-XmlAttribute([string]$value) {
    if ($null -eq $value) { return "" }
    return ($value -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;')
}

# Пул сеансов: единый разбор входа в обеих версиях (web-publish.py).
# Элемент — "Имя=rootUrl". Приходим из строки с разделителями ',' и ';',
# массива или web.poolServices ({ name, rootUrl }). Повтор параметра здесь
# невозможен: PowerShell запрещает его языком, в Python повтор работает.
# Пустое имя, отсутствующий '=' и пустой rootUrl — ошибка входа: испорченный
# rootUrl иначе молча выключает пул (платформа сверяет его с сервисом).
function New-PoolServiceSpec($item) {
    $raw = ""
    $name = ""
    $rootUrl = ""
    if ($item -is [string]) {
        $raw = $item.Trim()
        if (-not $raw) {
            if (-not $script:PoolServiceError) { $script:PoolServiceError = "пустой элемент — нужен формат 'Имя=rootUrl'" }
            return $null
        }
        $eq = $raw.IndexOf('=')
        if ($eq -lt 0) {
            if (-not $script:PoolServiceError) { $script:PoolServiceError = "'$raw': нет '=' — нужен формат 'Имя=rootUrl'" }
            return $null
        }
        $name = $raw.Substring(0, $eq).Trim()
        $rootUrl = $raw.Substring($eq + 1).Trim()
        if (-not $name) {
            if (-not $script:PoolServiceError) { $script:PoolServiceError = "'$raw': пустое имя — нужен формат 'Имя=rootUrl'" }
            return $null
        }
    } else {
        $name = "$($item.name)".Trim()
        $rootUrl = "$($item.rootUrl)".Trim()
        $raw = $name
        if (-not $name) {
            if (-not $script:PoolServiceError) { $script:PoolServiceError = "пустой элемент — нужен формат 'Имя=rootUrl'" }
            return $null
        }
    }
    if (-not $rootUrl) {
        if (-not $script:PoolServiceError) { $script:PoolServiceError = "'$raw': пустой rootUrl — нужен формат 'Имя=rootUrl'" }
        return $null
    }
    return [pscustomobject]@{ Name = $name; RootUrl = $rootUrl }
}

# Корень Apache и пути pid/log держим внутри того дерева, куда публикуем.
# Копия дерева (web.apachePath на копию) приносит Define SRVROOT исходной
# установки — httpd тогда пишет logs/httpd.pid и logs/error_log в рабочее
# дерево: копия перезаписывала pid живого Apache. Абсолютный PidFile/ErrorLog/
# CustomLog вне дерева переводим в logs/<имя> и сообщаем об этом.
function Set-ApacheConfRoot([string]$Conf, [string]$ApacheRoot) {
    $rootFull = [System.IO.Path]::GetFullPath($ApacheRoot)
    $rootNorm = $rootFull.Replace('/', '\').TrimEnd('\')
    $rootFwd = $rootFull.Replace('\', '/').TrimEnd('/')
    $nl = if ($Conf -match "`r`n") { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Conf -split "`r?`n")) { $lines.Add($line) }
    $notes = @()

    $defineFound = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(?<indent>[ \t]*)Define[ \t]+SRVROOT[ \t]+') { continue }
        $defineFound = $true
        $newLine = $Matches['indent'] + 'Define SRVROOT "' + $rootFwd + '"'
        if ($lines[$i] -ne $newLine) {
            $lines[$i] = $newLine
            $notes += "Define SRVROOT -> $rootFwd"
        }
    }

    if (-not $defineFound) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '^(?<indent>[ \t]*)ServerRoot[ \t]+(?<value>.+)$') { continue }
            if ($Matches['value'] -like '*${SRVROOT}*') { break }
            $newLine = $Matches['indent'] + 'ServerRoot "' + $rootFwd + '"'
            if ($lines[$i] -ne $newLine) {
                $lines[$i] = $newLine
                $notes += "ServerRoot -> $rootFwd"
            }
            break
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(?<indent>[ \t]*)(?<directive>PidFile|ErrorLog|CustomLog|ScriptLog|RewriteLog)[ \t]+(?:"(?<quoted>[^"]*)"|(?<plain>\S+))(?<tail>.*)$') { continue }
        $indent = $Matches['indent']
        $directive = $Matches['directive']
        $path = if ($Matches['quoted']) { $Matches['quoted'] } else { $Matches['plain'] }
        $tail = $Matches['tail']
        if ($path -match '^(syslog:|pipe:|\|)') { continue }
        $isAbs = ($path -match '^[A-Za-z]:[\\/]') -or $path.StartsWith('\\\\') -or ($path -match '^/')
        $candidate = if ($isAbs) { $path } else { Join-Path $ApacheRoot $path }
        try { $pathNorm = [System.IO.Path]::GetFullPath($candidate).Replace('/', '\').TrimEnd('\') } catch { continue }
        if ($pathNorm.Equals($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($pathNorm.StartsWith($rootNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $leaf = Split-Path -Leaf $path
        if (-not $leaf) { $leaf = 'httpd.pid' }
        $lines[$i] = $indent + $directive + ' "logs/' + $leaf + '"' + $tail
        $notes += "$directive $path -> logs/$leaf (путь вёл вне $rootNorm)"
    }

    foreach ($note in $notes) { Write-Host "httpd.conf: $note" -ForegroundColor DarkGray }
    return ($lines -join $nl)
}

$portArg = if ($PSBoundParameters.ContainsKey('Port') -and $Port -gt 0) { $Port } else { $null }
$targets = Resolve-1cWebTargets -V8Version $V8Version -AppName $AppName -ApachePath $ApachePath -Port $portArg
$projectRoot = $targets.ProjectRoot
$V8Version = $targets.V8Version
$AppName = $targets.AppName
$ApachePath = $targets.ApachePath
$Port = $targets.Port

# --- Resolve HTTP-service session pool (web.poolServices in .v8-project.json) ---
$registry = Read-1cJsonFile (Join-Path $projectRoot ".v8-project.json")
$webCfg = $null
if ($registry -and $registry.web) { $webCfg = $registry.web }

$script:PoolServiceError = $null
$poolInput = @()
if ($PSBoundParameters.ContainsKey('PoolServices')) {
    $poolInput = @($PoolServices)
} elseif ($webCfg -and $webCfg.poolServices) {
    $poolInput = @($webCfg.poolServices)
}
$PoolServiceSpecs = @()
foreach ($item in $poolInput) {
    $elements = if ($item -is [string]) { $item -split '[,;]' } else { @($item) }
    foreach ($element in $elements) {
        $spec = New-PoolServiceSpec $element
        if ($spec) { $PoolServiceSpecs += $spec }
    }
}
if ($script:PoolServiceError) {
    Write-Host "Error: PoolServices: $($script:PoolServiceError)" -ForegroundColor Red
    exit 1
}

if ($SessionMaxAge -le 0) {
    $SessionMaxAge = if ($webCfg -and $null -ne $webCfg.poolSessionMaxAge) { [int]$webCfg.poolSessionMaxAge } else { 20 }
}
if ($PoolSize -le 0) {
    $PoolSize = if ($webCfg -and $null -ne $webCfg.poolSize) { [int]$webCfg.poolSize } else { 4 }
}
if ($PoolTimeout -le 0) {
    $PoolTimeout = if ($webCfg -and $null -ne $webCfg.poolTimeout) { [int]$webCfg.poolTimeout } else { 5 }
}

Write-Host "Apache profile: apache-$($targets.ApacheLabel) -> $ApachePath (port $Port)" -ForegroundColor Yellow

# --- Resolve V8Path (registry / CLI) ---
if (-not $V8Path) {
    if ($V8Version) {
        $found = Find-PlatformBinByVersion $V8Version
        if ($found) {
            $V8Path = $found.Bin
            Write-Host "Platform by v8version=$V8Version -> $($found.Ver): $V8Path" -ForegroundColor Yellow
        } else {
            Write-Host "Error: платформа под v8version=$V8Version не найдена (нужен bin с wsap24.dll). Укажите -V8Path или поправьте v8path в .v8-project.json" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Error: не заданы -V8Path и v8path в .v8-project.json" -ForegroundColor Red
        exit 1
    }
} elseif (Test-Path $V8Path -PathType Leaf) {
    $V8Path = Split-Path $V8Path -Parent
}

# Validate wsap24.dll
$wsapDll = Join-Path $V8Path "wsap24.dll"
if (-not (Test-Path $wsapDll)) {
    Write-Host "Error: wsap24.dll не найден в $V8Path" -ForegroundColor Red
    exit 1
}

# --- Validate connection ---
if (-not $InfoBasePath -and (-not $InfoBaseServer -or -not $InfoBaseRef)) {
    Write-Host "Error: укажите -InfoBasePath или -InfoBaseServer + -InfoBaseRef" -ForegroundColor Red
    exit 1
}

# --- Check / Install Apache ---
$httpdExe = Join-Path (Join-Path $ApachePath "bin") "httpd.exe"

if (-not (Test-Path $httpdExe)) {
    if ($Manual) {
        Write-Host "Apache не найден: $ApachePath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Установите Apache через кит:" -ForegroundColor Cyan
        Write-Host "  install\kit.ps1 deps -What apache -Platform $($targets.ApacheLabel)"
        exit 1
    }

    # Версии и адрес загрузки Apache держит кит (companions/pins.json + kit.ps1 deps),
    # чтобы на разных машинах не приезжали разные сборки и версии.
    # Корень кита — только из NINJA_KIT_ROOT (его ставит kit.ps1 apply): угадывать
    # чужой путь нельзя, иначе на другой машине команда молча уйдёт не туда.
    $kitRoot = $env:NINJA_KIT_ROOT
    if (-not $kitRoot -or -not (Test-Path (Join-Path $kitRoot 'install\kit.ps1'))) {
        Write-Host "Apache не найден: $ApachePath" -ForegroundColor Yellow
        Write-Host "Кит не найден: NINJA_KIT_ROOT пуст или неверен. Задайте переменную (kit.ps1 apply) и повторите." -ForegroundColor Yellow
        Write-Host "Поставьте Apache из кита: install\kit.ps1 deps -What apache -Platform $($targets.ApacheLabel)" -ForegroundColor Cyan
        exit 1
    }

    Write-Host "Apache не найден: $ApachePath" -ForegroundColor Yellow
    Write-Host "Ставлю профильный Apache (apache-$($targets.ApacheLabel)) через kit deps..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kitRoot 'install\kit.ps1') `
        deps -What apache -Platform $targets.ApacheLabel
    if (-not (Test-Path $httpdExe)) {
        Write-Host "Error: kit deps не поставил Apache: $ApachePath" -ForegroundColor Red
        exit 1
    }
}

# --- AppName already resolved via Resolve-1cWebTargets ---
if (-not $AppName) {
    Write-Host "Error: не удалось определить имя публикации. Задайте -AppName или web.appName в .v8-project.json / tools/web-test/smoke.config.json webUrl" -ForegroundColor Red
    exit 1
}

Write-Host "Публикация: $AppName (port $Port)" -ForegroundColor Cyan

# --- Create publish directory ---
$publishDir = Join-Path (Join-Path $ApachePath "publish") $AppName
if (-not (Test-Path $publishDir)) {
    New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
}

# --- Generate default.vrd ---
$vrdPath = Join-Path $publishDir "default.vrd"

$ibParts = @()
if ($InfoBaseServer -and $InfoBaseRef) {
    $ibParts += "Srvr=&quot;$InfoBaseServer&quot;"
    $ibParts += "Ref=&quot;$InfoBaseRef&quot;"
} else {
    $ibParts += "File=&quot;$InfoBasePath&quot;"
}
if ($UserName) { $ibParts += "Usr=&quot;$UserName&quot;" }
if ($Password) { $ibParts += "Pwd=&quot;$Password&quot;" }
$ibString = ($ibParts -join ";") + ";"

# Пул сеансов задаётся на элементе <service>: на <httpServices> платформа 8.5
# эти атрибуты не принимает. publishByDefault остаётся true — новые сервисы
# (в том числе из расширений) публикуются как раньше.
$poolServiceLines = @()
foreach ($spec in $PoolServiceSpecs) {
    $escapedName = ConvertTo-XmlAttribute $spec.Name
    $rootUrlAttr = if ($spec.RootUrl) { " rootUrl=`"$(ConvertTo-XmlAttribute $spec.RootUrl)`"" } else { "" }
    $poolServiceLines += "        <service name=`"$escapedName`"$rootUrlAttr enable=`"true`" reuseSessions=`"autouse`" sessionMaxAge=`"$SessionMaxAge`" poolSize=`"$PoolSize`" poolTimeout=`"$PoolTimeout`"/>"
}
if ($poolServiceLines.Count -gt 0) {
    $httpServicesXml = @"
    <httpServices publishByDefault="true" publishExtensionsByDefault="true">
$($poolServiceLines -join "`n")
    </httpServices>
"@
} else {
    $httpServicesXml = '    <httpServices publishByDefault="true" publishExtensionsByDefault="true"/>'
}

$vrdContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<point xmlns="http://v8.1c.ru/8.2/virtual-resource-system"
       xmlns:xs="http://www.w3.org/2001/XMLSchema"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       base="/$AppName"
       ib="$ibString">
    <standardOdata enable="true"/>
    <ws pointEnableCommon="true"/>
$httpServicesXml
</point>
"@

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
# Переводы строк — LF, как у web-publish.py: обе версии дают побайтово один vrd.
$vrdContent = $vrdContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($vrdPath, $vrdContent, $utf8Bom)
Write-Host "default.vrd: $vrdPath" -ForegroundColor Green
if ($PoolServiceSpecs.Count -gt 0) {
    $poolNames = ($PoolServiceSpecs | ForEach-Object { if ($_.RootUrl) { "$($_.Name)=$($_.RootUrl)" } else { $_.Name } }) -join ', '
    Write-Host "Пул сеансов HTTP-сервисов: $poolNames (sessionMaxAge=$SessionMaxAge, poolSize=$PoolSize, poolTimeout=$PoolTimeout)" -ForegroundColor Green
} else {
    Write-Host "Пул сеансов HTTP-сервисов: выключен (web.poolServices / -PoolServices пуст)" -ForegroundColor DarkGray
}

# --- Update httpd.conf ---
$confFile = Join-Path (Join-Path $ApachePath "conf") "httpd.conf"
if (-not (Test-Path $confFile)) {
    Write-Host "Error: httpd.conf не найден: $confFile" -ForegroundColor Red
    exit 1
}

$confContent = [System.IO.File]::ReadAllText($confFile)
$apachePathFwd = $ApachePath -replace '\\','/'
$wsapDllFwd = $wsapDll -replace '\\','/'
$publishDirFwd = $publishDir -replace '\\','/'
$vrdPathFwd = $vrdPath -replace '\\','/'

$confContent = Set-ApacheConfRoot -Conf $confContent -ApacheRoot $ApachePath

# --- Global block (Listen + LoadModule) ---
$globalMarkerStart = "# --- 1C: global ---"
$globalMarkerEnd = "# --- End: global ---"
$globalBlock = @"
$globalMarkerStart
Listen $Port
LoadModule _1cws_module "$wsapDllFwd"
$globalMarkerEnd
"@

if ($confContent -match [regex]::Escape($globalMarkerStart)) {
    # Replace existing global block
    $pattern = [regex]::Escape($globalMarkerStart) + '[\s\S]*?' + [regex]::Escape($globalMarkerEnd)
    $confContent = [regex]::Replace($confContent, $pattern, $globalBlock)
} else {
    # Comment out default Listen to avoid port conflict
    $confContent = $confContent -replace '(?m)^(Listen\s+\d+)', '#$1  # commented by web-publish'
    # Append global block
    $confContent = $confContent.TrimEnd() + "`n`n" + $globalBlock + "`n"
}

# --- Publication block ---
$pubMarkerStart = "# --- 1C Publication: $AppName ---"
$pubMarkerEnd = "# --- End: $AppName ---"
$pubBlock = @"
$pubMarkerStart
Alias "/$AppName" "$publishDirFwd"
<Directory "$publishDirFwd">
    AllowOverride All
    Require all granted
    SetHandler 1c-application
    ManagedApplicationDescriptor "$vrdPathFwd"
</Directory>
$pubMarkerEnd
"@

if ($confContent -match [regex]::Escape($pubMarkerStart)) {
    # Replace existing publication block
    $pattern = [regex]::Escape($pubMarkerStart) + '[\s\S]*?' + [regex]::Escape($pubMarkerEnd)
    $confContent = [regex]::Replace($confContent, $pattern, $pubBlock)
} else {
    # Append publication block
    $confContent = $confContent.TrimEnd() + "`n`n" + $pubBlock + "`n"
}

[System.IO.File]::WriteAllText($confFile, $confContent)
Write-Host "httpd.conf обновлён" -ForegroundColor Green

# --- Ensure logs dir: pid и error_log пишутся в своё дерево ---
$logsDir = Join-Path $ApachePath "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# --- Helper: filter httpd processes by our ApachePath ---
function Get-OurHttpd {
    $httpdExeNorm = (Resolve-Path $httpdExe -ErrorAction SilentlyContinue).Path
    Get-Process httpd -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $httpdExeNorm } catch { $false }
    }
}

# --- Check port availability ---
# Порт занят только слушающим сокетом. TIME_WAIT после закрытых сеансов держит
# запись с PID 0 — это не занятость (та же логика в check_port_in_use у web-publish.py).
$portHolders = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -and $_.OwningProcess -ne 0 })
$portCheck = $portHolders | Select-Object -First 1
if ($portCheck) {
    $ourProc = Get-OurHttpd
    if ($ourProc) {
        # Our Apache holds the port — will restart
    } else {
        $holder = Get-Process -Id $portCheck.OwningProcess -ErrorAction SilentlyContinue
        $holderName = if ($holder) { "$($holder.ProcessName) (PID: $($holder.Id))" } else { "PID $($portCheck.OwningProcess)" }
        Write-Host "Error: порт $Port занят процессом $holderName" -ForegroundColor Red
        Write-Host "Укажите другой порт: -Port 9090" -ForegroundColor Yellow
        exit 1
    }
}

# --- Start Apache if not running ---
$httpdProc = Get-OurHttpd
if ($httpdProc) {
    Write-Host "Apache уже запущен (PID: $(($httpdProc | Select-Object -First 1).Id))" -ForegroundColor Yellow
    Write-Host "Перезапуск для применения конфигурации..."
    $httpdProc | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
} else {
    # Check if a foreign httpd holds the port
    $foreignHttpd = Get-Process httpd -ErrorAction SilentlyContinue
    if ($foreignHttpd) {
        Write-Host "[WARN] Обнаружен сторонний Apache (PID: $(($foreignHttpd | Select-Object -First 1).Id))" -ForegroundColor Yellow
        Write-Host "       Наш Apache: $httpdExe" -ForegroundColor Yellow
    }
}

Write-Host "Запуск Apache..."
Start-Process -FilePath $httpdExe -WorkingDirectory $ApachePath -WindowStyle Hidden

Start-Sleep -Seconds 2

$httpdCheck = Get-OurHttpd
if ($httpdCheck) {
    Write-Host "Apache запущен (PID: $(($httpdCheck | Select-Object -First 1).Id))" -ForegroundColor Green
} else {
    Write-Host "Apache не удалось запустить" -ForegroundColor Red
    # Run config test for diagnostics
    $testResult = & $httpdExe -t 2>&1
    if ($testResult) {
        Write-Host "--- httpd -t ---" -ForegroundColor Yellow
        $testResult | ForEach-Object { Write-Host "  $_" }
    }
    $errorLog = Join-Path (Join-Path $ApachePath "logs") "error.log"
    if (Test-Path $errorLog) {
        Write-Host "--- error.log (последние 10 строк) ---" -ForegroundColor Yellow
        Get-Content $errorLog -Tail 10
    }
    exit 1
}

# --- Result ---
Write-Host ""
Write-Host "=== Публикация готова ===" -ForegroundColor Green
Write-Host "URL (веб-клиент): http://localhost:$Port/$AppName/ru_RU/" -ForegroundColor Cyan
Write-Host "OData:            http://localhost:$Port/$AppName/odata/standard.odata" -ForegroundColor Cyan
Write-Host "HTTP-сервисы:     http://localhost:$Port/$AppName/hs/<RootUrl>/..." -ForegroundColor Cyan
Write-Host "Web-сервисы:      http://localhost:$Port/$AppName/ws/<Имя>?wsdl" -ForegroundColor Cyan

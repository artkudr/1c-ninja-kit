#Requires -Version 5.1
<#
  deps.ps1 — машинный слой кита: ставит внешние зависимости в стандартные пути.

  Запускается только через install/kit.ps1 (команда `deps`) и используется оттуда же
  в `doctor` для отчёта о версиях. Отдельным скриптом не рассчитан — требует
  Write-Status / Expand-EnvPath из kit.ps1 (если их нет, подставляет свои).

  Политика версий — latest с upstream (GitHub releases, Apache Lounge).
  companions/pins.json хранит: откуда брать, шаблоны имён ассетов, тестовые и
  минимально допустимые версии. Фактически установленное пишется в
  %LOCALAPPDATA%\1c-ninja-kit\deps-state.json — машинное состояние, не в git.

  Здесь НЕ ставится: платформа 1С (её дистрибутив) и wsap24.dll из неё же.
  Без платформы Apache бесполезен, поэтому doctor проверяет её отдельно.
#>

if (-not (Get-Command Write-Status -ErrorAction SilentlyContinue)) {
  function Write-Status([string]$Level, [string]$Msg) {
    Write-Host ("[{0}] {1}" -f $Level, $Msg)
  }
}
if (-not (Get-Command Expand-EnvPath -ErrorAction SilentlyContinue)) {
  function Expand-EnvPath([string]$p) { return [Environment]::ExpandEnvironmentVariables($p) }
}

$script:DepsStateDir = Join-Path $env:LOCALAPPDATA '1c-ninja-kit'
$script:DepsCacheDir = Join-Path $script:DepsStateDir 'cache'
$script:DepsStatePath = Join-Path $script:DepsStateDir 'deps-state.json'
$script:DepsPinsCache = $null

# ---------------------------------------------------------------- pins / state

function Get-DepsPins([string]$KitRoot) {
  if ($script:DepsPinsCache) { return $script:DepsPinsCache }
  $path = Join-Path $KitRoot 'companions\pins.json'
  if (-not (Test-Path -LiteralPath $path)) { throw "pins.json not found: $path" }
  $script:DepsPinsCache = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
  return $script:DepsPinsCache
}

function Get-DepsState {
  if (Test-Path -LiteralPath $script:DepsStatePath) {
    try { return (Get-Content -LiteralPath $script:DepsStatePath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { }
  }
  return [pscustomobject]@{}
}

function Save-DepsState($State) {
  New-Item -ItemType Directory -Force -Path $script:DepsStateDir | Out-Null
  $json = $State | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($script:DepsStatePath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Set-DepsStateEntry($State, [string]$Key, $Meta) {
  if (-not $Meta) { return }
  $entry = [pscustomobject]@{
    version     = [string]$Meta.Version
    installedAt = (Get-Date).ToString('s')
    source      = [string]$Meta.Source
    sha256      = [string]$Meta.Sha256
  }
  $State | Add-Member -NotePropertyName $Key -NotePropertyValue $entry -Force
}

# ------------------------------------------------------------------ utilities

function Get-DepsHash([string]$Text) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally { $sha.Dispose() }
}

function Get-WebText([string]$Url) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add('User-Agent', '1c-ninja-kit')
  try { return $wc.DownloadString($Url) } finally { $wc.Dispose() }
}

function Invoke-DepsDownload([string]$Url, [string]$OutFile) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $attempt = 0
  while ($true) {
    $attempt++
    try {
      $wc = New-Object System.Net.WebClient
      $wc.Headers.Add('User-Agent', '1c-ninja-kit')
      try { $wc.DownloadFile($Url, $OutFile) } finally { $wc.Dispose() }
      return
    } catch {
      if ($attempt -ge 3) { throw }
      Start-Sleep -Seconds 2
    }
  }
}

# Скачивает файл в локальный кеш (повторные прогоны и -Offline работают без сети).
function Get-DepsFile([string]$Url, [string]$FileName, [switch]$Offline, [string]$ExpectedSha256) {
  New-Item -ItemType Directory -Force -Path $script:DepsCacheDir | Out-Null
  $safe = ($FileName -replace '[^\w\.\-]', '_')
  $cache = Join-Path $script:DepsCacheDir ('{0}-{1}' -f (Get-DepsHash $Url).Substring(0, 12), $safe)
  if (-not (Test-Path -LiteralPath $cache)) {
    if ($Offline) { throw "offline: в кеше нет $safe ($Url)" }
    $tmp = "$cache.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    Invoke-DepsDownload $Url $tmp
    Move-Item -LiteralPath $tmp -Destination $cache -Force
  }
  if ($ExpectedSha256) {
    $actual = (Get-FileHash -LiteralPath $cache -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
      Remove-Item -LiteralPath $cache -Force
      throw "sha256 не совпал: $FileName (ожидался $ExpectedSha256, получен $actual)"
    }
  }
  return $cache
}

function Expand-DepsZip([string]$ZipPath) {
  $dir = Join-Path $env:TEMP ('1c-ninja-kit-dep-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $dir)
  return $dir
}

# Внешняя команда через cmd /c: stderr не превращается в NativeCommandError,
# который при $ErrorActionPreference='Stop' обрывает выполнение на «npm notice».
function Invoke-DepsNative([string]$Exe, [string[]]$ArgumentList, [string]$WorkDir) {
  $quoted = @($ArgumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
  $command = '"' + $Exe + '" ' + ($quoted -join ' ') + ' 2>&1'
  Push-Location $WorkDir
  try {
    $out = (& cmd /c $command | Out-String)
    $code = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  return [pscustomobject]@{ Output = $out; Code = $code }
}

function Get-GitHubLatestRelease([string]$Repo) {
  return (Get-WebText "https://api.github.com/repos/$Repo/releases/latest") | ConvertFrom-Json
}

function Find-ReleaseAsset($Release, [string]$NamePattern) {
  return @($Release.assets | Where-Object { $_.name -match $NamePattern } |
    Sort-Object name -Descending | Select-Object -First 1)
}

# sha256 из произвольного текста (checksums.txt, ассет *.sha256 с выводом CertUtil).
function Get-Sha256FromText([string]$Text) {
  $m = [regex]::Match($Text, '(?i)\b[0-9a-f]{64}\b')
  if ($m.Success) { return $m.Value }
  return $null
}

# sha256 из ассета checksums.txt того же релиза (если он там есть).
function Get-ReleaseChecksum($Release, [string]$AssetName) {
  $sum = Find-ReleaseAsset $Release '^checksums\.txt$'
  if (-not $sum) { return $null }
  foreach ($line in ((Get-WebText $sum.browser_download_url) -split "`r?`n")) {
    $parts = @($line.Trim() -split '\s+')
    if ($parts.Count -ge 2 -and $parts[1].TrimStart('*') -eq $AssetName) { return (Get-Sha256FromText $parts[0]) }
  }
  return $null
}

# Лаунчер bsl-analyzer кладёт app в %USERPROFILE%\.bsl-analyzer\bin, но берёт путь
# из известной папки Windows, а не из переменной окружения. На обычной машине это одно
# и то же; на всякий случай проверяем оба варианта.
function Get-DepsBslAppPath($Pins) {
  $candidates = @(
    (Expand-EnvPath $Pins.bslAnalyzer.appExe),
    (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.bsl-analyzer\bin\bsl-analyzer-app.exe')
  ) | Where-Object { $_ } | Select-Object -Unique
  foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
  return $candidates[0]
}

function Get-ExeVersion([string]$Exe, [string]$Argument, [string]$Pattern) {
  if (-not (Test-Path -LiteralPath $Exe)) { return $null }
  try {
    $out = & $Exe $Argument 2>&1 | Out-String
    $m = [regex]::Match($out, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value }
  } catch { }
  return $null
}

function Test-DepsVersionAtLeast([string]$Actual, [string]$Minimum) {
  if (-not $Actual) { return $false }
  if (-not $Minimum) { return $true }
  try { return ([version]$Actual -ge [version]$Minimum) } catch { return ($Actual -eq $Minimum) }
}

# Переключает junction %LOCALAPPDATA%\ovm\current на слот движка OneScript.
function Set-DepsJunction([string]$Link, [string]$Target) {
  $existing = @(Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue)
  if ($existing.Count -gt 0) {
    if ($existing[0].Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      # Junction удаляется без -Recurse: иначе PowerShell полезет внутрь цели.
      cmd /c rmdir "$Link" | Out-Null
    } else {
      throw "путь занят обычным каталогом, а не junction: $Link (уберите его вручную)"
    }
  }
  New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
}

function Add-UserPathEntry([string]$Dir) {
  if (-not $Dir) { return $false }
  $norm = $Dir.TrimEnd('\')
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @($current -split ';' | Where-Object { $_ })
  if (@($parts | Where-Object { $_.TrimEnd('\') -ieq $norm }).Count -gt 0) { return $false }
  [Environment]::SetEnvironmentVariable('Path', (($parts + $norm) -join ';'), 'User')
  if (($env:Path -split ';' | Where-Object { $_.TrimEnd('\') -ieq $norm }).Count -eq 0) {
    $env:Path = $env:Path.TrimEnd(';') + ';' + $norm
  }
  return $true
}

function Get-InstalledV8Platforms {
  $found = New-Object System.Collections.ArrayList
  foreach ($root in @('C:\Program Files\1cv8', 'C:\Program Files (x86)\1cv8')) {
    foreach ($dir in @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
      if ($dir.Name -notmatch '^8\.(\d)\.') { continue }
      if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'bin\1cv8.exe'))) { continue }
      $mask = '8.' + $Matches[1]
      if (-not $found.Contains($mask)) { [void]$found.Add($mask) }
    }
  }
  return @($found | Sort-Object)
}

# --------------------------------------------------------------- status report

function Get-DepsNodePath {
  $portable = Join-Path (Expand-EnvPath '%USERPROFILE%\tools\node') 'node.exe'
  if (Test-Path -LiteralPath $portable) { return $portable }
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $portable
}

# Каталог скилла skill-web-test, где лежит package.json.
# Сначала глобальная копия (после kit.ps1 apply), иначе — исходники кита.
function Get-DepsWebTestScriptsDir([string]$KitRoot) {
  $pins = Get-DepsPins $KitRoot
  $global = Join-Path $env:USERPROFILE ([string]$pins.webTest.skillScriptsRelative)
  if (Test-Path -LiteralPath (Join-Path $global 'package.json')) { return $global }
  return (Join-Path $KitRoot 'profile\skills\skill-web-test\scripts')
}

function Get-DepsPlaywrightBrowserDir {
  $root = Join-Path $env:LOCALAPPDATA 'ms-playwright'
  if (-not (Test-Path -LiteralPath $root)) { return $null }
  $dir = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^chromium-\d+$' } |
    Sort-Object Name -Descending | Select-Object -First 1)
  if ($dir.Count -eq 0) { return $null }
  return $dir[0].FullName
}

function Get-DepsPlaywrightInfo([string]$ScriptsDir) {
  $pkg = Join-Path $ScriptsDir 'node_modules\playwright\package.json'
  if (-not (Test-Path -LiteralPath $pkg)) { return $null }
  $text = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8
  if ($text -match '"version"\s*:\s*"([^"]+)"') { return $Matches[1] }
  return 'installed'
}

function Get-MissingOscriptPackages([string]$BinDir, $Pins) {
  $wanted = @($Pins.oneScript.packages)
  $oscript = Join-Path $BinDir 'oscript.exe'
  $opmOs = Join-Path (Split-Path -Parent $BinDir) 'lib\opm\src\cmd\opm.os'
  if (-not (Test-Path -LiteralPath $oscript) -or -not (Test-Path -LiteralPath $opmOs)) { return $wanted }
  # Запускаем opm.os именно этим движком: opm.bat зовёт `oscript` из PATH, и на
  # машине с другим OneScript список пакетов приедет от чужого движка.
  $list = ''
  try {
    $list = (Invoke-DepsNative $oscript @($opmOs, 'list') (Split-Path -Parent $BinDir)).Output
  } catch { }
  $missing = New-Object System.Collections.ArrayList
  foreach ($pkg in $wanted) {
    if ($list -notmatch ('(?m)^\s*' + [regex]::Escape($pkg) + '\s*\|')) { [void]$missing.Add($pkg) }
  }
  return @($missing)
}

function New-DepStatus([string]$Key, [string]$Label, [bool]$Required, [bool]$Installed, [string]$Version, [string]$Path, [string]$Note) {
  return [pscustomobject]@{
    Key       = $Key
    Label     = $Label
    Required  = $Required
    Installed = $Installed
    Version   = $Version
    Path      = $Path
    Note      = $Note
  }
}

function Get-DepsStatus([string]$KitRoot) {
  $pins = Get-DepsPins $KitRoot
  $statuses = New-Object System.Collections.ArrayList

  # OneScript + пакеты контура
  $ovmBin = Join-Path (Expand-EnvPath $pins.oneScript.ovmCurrent) 'bin'
  $oscript = Join-Path $ovmBin 'oscript.exe'
  $osVer = Get-ExeVersion $oscript '--version' 'Version\s+(\d+(?:\.\d+){1,3})'
  [void]$statuses.Add((New-DepStatus 'oscript' 'OneScript' $true ([bool]$osVer) $osVer $oscript 'официальный zip OneScript'))
  if ($osVer) {
    $missing = @(Get-MissingOscriptPackages $ovmBin $pins)
    $note = if ($missing.Count -eq 0) { 'пакеты: ' + (@($pins.oneScript.packages) -join ', ') } else { 'не хватает: ' + ($missing -join ', ') }
    [void]$statuses.Add((New-DepStatus 'oscript-packages' 'Пакеты OneScript' $true ($missing.Count -eq 0) $osVer (Join-Path $ovmBin 'opm.bat') $note))
  } else {
    [void]$statuses.Add((New-DepStatus 'oscript-packages' 'Пакеты OneScript' $true $false '' (Join-Path $ovmBin 'opm.bat') 'сначала движок OneScript'))
  }

  # bsl-analyzer: лаунчер + app, который кладёт лаунчер
  $launcher = Expand-EnvPath $pins.bslAnalyzer.installAs
  $appExe = Get-DepsBslAppPath $pins
  $lVer = Get-ExeVersion $launcher '--launcher-version' '(\d+(?:\.\d+){1,3})'
  $aVer = Get-ExeVersion $appExe '--version' '(\d+(?:\.\d+){1,3})'
  [void]$statuses.Add((New-DepStatus 'bsl-analyzer' 'bsl-analyzer (лаунчер)' $true ([bool]$lVer) $lVer $launcher ('min app ' + $pins.bslAnalyzer.minAppVersion)))
  [void]$statuses.Add((New-DepStatus 'bsl-analyzer-app' 'bsl-analyzer app' $true ([bool]$aVer) $aVer $appExe 'кладёт лаунчер (--launcher-update)'))

  # ripgrep
  $rg = Expand-EnvPath $pins.ripgrep.recommendedPath
  $rgVer = Get-ExeVersion $rg '--version' 'ripgrep\s+(\d+(?:\.\d+){1,3})'
  [void]$statuses.Add((New-DepStatus 'ripgrep' 'Ripgrep' $false ([bool]$rgVer) $rgVer $rg 'нужен в PATH'))

  # Веб-прогоны: Node + Playwright + браузер Chromium
  $nodeExe = Get-DepsNodePath
  $nodeVer = Get-ExeVersion $nodeExe '--version' 'v(\d+(?:\.\d+){1,3})'
  [void]$statuses.Add((New-DepStatus 'node' 'Node.js' $true ([bool]$nodeVer) $nodeVer $nodeExe ('min ' + $pins.webTest.minNodeVersion)))

  $wtScripts = Get-DepsWebTestScriptsDir $KitRoot
  $pwVer = Get-DepsPlaywrightInfo $wtScripts
  [void]$statuses.Add((New-DepStatus 'playwright' 'Playwright (skill-web-test)' $true ([bool]$pwVer) $pwVer (Join-Path $wtScripts 'node_modules\playwright') 'пакет в каталоге скилла'))

  $chromium = Get-DepsPlaywrightBrowserDir
  $chromiumPath = if ($chromium) { $chromium } else { Join-Path $env:LOCALAPPDATA 'ms-playwright' }
  [void]$statuses.Add((New-DepStatus 'playwright-browser' 'Playwright Chromium' $true ([bool]$chromium) '' $chromiumPath 'браузеры из %LOCALAPPDATA%\ms-playwright'))

  # Apache по профилям платформ
  foreach ($label in @('8.3', '8.5')) {
    $cfg = $pins.apache.platforms.$label
    $dir = Expand-EnvPath $cfg.toolsDir
    $httpd = Join-Path $dir 'bin\httpd.exe'
    $ver = Get-ExeVersion $httpd '-v' 'Apache/(\d+(?:\.\d+){1,3})'
    $note = 'порт ' + $cfg.port
    [void]$statuses.Add((New-DepStatus ('apache-' + $label.Replace('.', '')) ('Apache ' + $label) $false ([bool]$ver) $ver $dir $note))
  }

  # Toolkit EPF (optional fallback live)
  $epf = Expand-EnvPath $pins.mcpToolkit.recommendedPath
  [void]$statuses.Add((New-DepStatus 'toolkit' 'MCP Toolkit EPF' $false (Test-Path -LiteralPath $epf) '' $epf 'нужен только как fallback live'))

  return @($statuses)
}

# ---------------------------------------------------------------- installers

function Install-DepOneScript([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $ovmRoot = Expand-EnvPath '%LOCALAPPDATA%\ovm'
  $bin = Join-Path $ovmRoot 'current\bin'
  $oscript = Join-Path $bin 'oscript.exe'
  $opmOs = Join-Path (Split-Path -Parent $bin) 'lib\opm\src\cmd\opm.os'
  $engine = [string]$pins.oneScript.engineVersion

  if ($DryRun) {
    if (Test-Path -LiteralPath $oscript) { Write-Status 'INFO' "OneScript уже стоит: $oscript" }
    else { Write-Status 'INFO' "would install OneScript $engine -> $bin" }
  } else {
    if (-not (Test-Path -LiteralPath $oscript)) {
      # Движок ставится прямо из официального zip OneScript: внутри уже есть
      # bin\opm.bat и lib, поэтому OVM не нужен. OVM умеет то же самое, но качает
      # движок со своего сервера обновлений — на практике он падает (EOF потока).
      $rel = Get-GitHubLatestRelease $pins.oneScript.githubRepo
      $ver = ([string]$rel.tag_name).TrimStart('v', 'V')
      if (-not $ver) { $ver = $engine }
      $slot = Join-Path $ovmRoot $ver

      if (-not (Test-Path -LiteralPath (Join-Path $slot 'bin\oscript.exe'))) {
        $asset = Find-ReleaseAsset $rel ('^OneScript-' + [regex]::Escape($ver) + '-win-x64\.zip$')
        if (-not $asset) { $asset = Find-ReleaseAsset $rel '^OneScript-.*-win-x64\.zip$' }
        if (-not $asset) { throw "в релизе $($rel.tag_name) нет win-x64 zip" }
        Write-Status 'INFO' "OneScript: ставлю движок $ver из $($asset.name)"
        $zip = Get-DepsFile $asset.browser_download_url $asset.name -Offline:$Offline
        $tmp = Expand-DepsZip $zip
        try {
          New-Item -ItemType Directory -Force -Path $slot | Out-Null
          Copy-Item -Path (Join-Path $tmp '*') -Destination $slot -Recurse -Force
        } finally {
          Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
      }

      Set-DepsJunction (Join-Path $ovmRoot 'current') $slot
      if (-not (Test-Path -LiteralPath $oscript)) { throw "oscript.exe не появился: $oscript" }
      Write-Status 'OK' "OneScript $ver -> $slot (current)"
    } elseif ($Update) {
      Write-Status 'INFO' "OneScript: движок уже стоит ($engine), обновление не требуется"
    }

    if (Add-UserPathEntry $bin) { Write-Status 'INFO' "PATH: добавлен $bin (нужна новая сессия)" }
  }

  if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $opmOs)) { throw "opm не найден в движке: $opmOs" }
    foreach ($pkg in @($pins.oneScript.packages)) {
      $missing = @(Get-MissingOscriptPackages $bin $pins)
      if ($missing -notcontains $pkg -and -not $Update) { continue }

      $spec = $pkg
      Write-Status 'INFO' "opm: ставлю пакет $spec (latest)"
      $res = Invoke-DepsNative $oscript @($opmOs, 'install', $spec) (Split-Path -Parent $bin)
      if ($res.Code -ne 0 -and $res.Output -match 'устаревшая версия движка|Требуемая версия') {
        # Hub бывает впереди релизов OneScript: пакет требует движок, которого ещё нет.
        $good = [string]$pins.oneScript.knownGood.$pkg
        if ($good) {
          Write-Status 'WARN' "opm: latest $pkg требует движок новее выпущенного - ставлю проверенную $good"
          $spec = "$pkg@$good"
          $res = Invoke-DepsNative $oscript @($opmOs, 'install', $spec) (Split-Path -Parent $bin)
        }
      }
      if ($res.Code -ne 0) {
        Write-Host $res.Output
        throw "opm install $spec завершился с кодом $($res.Code)"
      }
      Write-Status 'OK' "opm: $spec"
    }
    $left = @(Get-MissingOscriptPackages $bin $pins)
    if ($left.Count -gt 0) { throw ('не установились пакеты: ' + ($left -join ', ')) }
  }

  $ver = Get-ExeVersion $oscript '--version' 'Version\s+(\d+(?:\.\d+){1,3})'
  return [pscustomobject]@{ Version = $ver; Source = "github:$($pins.oneScript.githubRepo)"; Sha256 = '' }
}

function Install-DepBslAnalyzer([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $launcher = Expand-EnvPath $pins.bslAnalyzer.installAs
  $appExe = Get-DepsBslAppPath $pins

  if ($DryRun) {
    if ((Test-Path -LiteralPath $launcher) -and (Test-Path -LiteralPath $appExe) -and -not $Update) {
      Write-Status 'INFO' "bsl-analyzer уже стоит: $launcher"
    } else {
      Write-Status 'INFO' "would install bsl-analyzer launcher -> $launcher"
    }
    return $null
  }

  $rel = Get-GitHubLatestRelease $pins.bslAnalyzer.githubRepo
  $needLauncher = $Update -or (-not (Test-Path -LiteralPath $launcher))
  if ($needLauncher) {
    $asset = Find-ReleaseAsset $rel $pins.bslAnalyzer.launcherAssetPattern
    if (-not $asset) { throw "в релизе $($rel.tag_name) нет ассета лаунчера" }
    $sha = Get-ReleaseChecksum $rel $asset.name
    $file = Get-DepsFile $asset.browser_download_url $asset.name -Offline:$Offline -ExpectedSha256 $sha
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launcher) | Out-Null
    if (Test-Path -LiteralPath $launcher) {
      $bak = "$launcher.bak"
      try {
        if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
        Move-Item -LiteralPath $launcher -Destination $bak -Force
      } catch {
        throw "лаунчер занят (запущен MCP bsl-analyzer?): остановите сервер и повторите. $($_.Exception.Message)"
      }
    }
    Copy-Item -LiteralPath $file -Destination $launcher -Force
    Write-Status 'OK' "bsl-analyzer launcher $($rel.tag_name) -> $launcher"
  }

  if (-not (Test-Path -LiteralPath $appExe)) {
    Write-Status 'INFO' 'bsl-analyzer: подтягиваю app (--launcher-update, ~80 МБ)'
    $upd = Invoke-DepsNative $launcher @('--launcher-update') (Split-Path -Parent $launcher)
    if ($upd.Code -ne 0) {
      Write-Host $upd.Output
      throw "launcher-update завершился с кодом $($upd.Code)"
    }
    $appExe = Get-DepsBslAppPath $pins
  }
  if (-not (Test-Path -LiteralPath $appExe)) { throw "app не появился: $appExe" }

  $ver = Get-ExeVersion $launcher '--launcher-version' '(\d+(?:\.\d+){1,3})'
  return [pscustomobject]@{ Version = $ver; Source = "github:$($pins.bslAnalyzer.githubRepo)@$($rel.tag_name)"; Sha256 = '' }
}

function Install-DepRipgrep([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $dst = Expand-EnvPath $pins.ripgrep.toolsDir

  if ($DryRun) {
    if ((Test-Path -LiteralPath (Join-Path $dst 'rg.exe')) -and -not $Update) {
      Write-Status 'INFO' "ripgrep уже стоит: $dst"
    } else {
      Write-Status 'INFO' "would install ripgrep -> $dst"
    }
    return $null
  }

  $rel = Get-GitHubLatestRelease $pins.ripgrep.githubRepo
  $asset = Find-ReleaseAsset $rel $pins.ripgrep.assetPattern
  if (-not $asset) { throw "в релизе $($rel.tag_name) нет windows-ассета ripgrep" }
  $sha = Get-ReleaseChecksum $rel ($asset.name + '.sha256')
  if (-not $sha) {
    $shaAsset = Find-ReleaseAsset $rel ('^' + [regex]::Escape($asset.name) + '\.sha256$')
    if ($shaAsset) { $sha = Get-Sha256FromText (Get-WebText $shaAsset.browser_download_url) }
  }
  $zip = Get-DepsFile $asset.browser_download_url $asset.name -Offline:$Offline -ExpectedSha256 $sha
  $tmp = Expand-DepsZip $zip
  try {
    $rg = @(Get-ChildItem $tmp -Recurse -Filter 'rg.exe' -File | Select-Object -First 1)
    if ($rg.Count -eq 0) { throw 'в архиве ripgrep нет rg.exe' }
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Path (Join-Path $rg[0].DirectoryName '*') -Destination $dst -Recurse -Force
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }

  if (Add-UserPathEntry $dst) { Write-Status 'INFO' "PATH: добавлен $dst (нужна новая сессия)" }
  $ver = Get-ExeVersion (Join-Path $dst 'rg.exe') '--version' 'ripgrep\s+(\d+(?:\.\d+){1,3})'
  Write-Status 'OK' "ripgrep $ver -> $dst"
  return [pscustomobject]@{ Version = $ver; Source = "github:$($pins.ripgrep.githubRepo)@$($rel.tag_name)"; Sha256 = $sha }
}

function Install-DepsNodePortable([string]$KitRoot, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $nodeDir = Expand-EnvPath $pins.webTest.nodeToolsDir
  $nodeExe = Join-Path $nodeDir 'node.exe'
  $min = [string]$pins.webTest.minNodeVersion

  $current = Get-ExeVersion $nodeExe '--version' 'v(\d+(?:\.\d+){1,3})'
  if ($current -and (Test-DepsVersionAtLeast $current $min)) { return $nodeExe }

  if ($DryRun) {
    Write-Status 'INFO' "would install Node.js LTS -> $nodeDir"
    return $nodeExe
  }

  Write-Status 'INFO' 'Node.js: ставлю portable LTS'
  $index = (Get-WebText $pins.webTest.nodeDistIndex) | ConvertFrom-Json
  $lts = @($index | Where-Object { $_.lts } |
    Sort-Object { [version]([string]$_.version).TrimStart('v') } -Descending |
    Select-Object -First 1)
  if ($lts.Count -eq 0) { throw 'не нашёл LTS-сборку Node.js в nodejs.org/dist/index.json' }
  $ver = [string]$lts[0].version
  $zipName = "node-$ver-win-x64.zip"
  $zip = Get-DepsFile ("https://nodejs.org/dist/$ver/$zipName") $zipName -Offline:$Offline
  $tmp = Expand-DepsZip $zip
  try {
    $inner = @(Get-ChildItem $tmp -Directory | Select-Object -First 1)
    if ($inner.Count -eq 0) { throw 'в архиве Node.js нет каталога с файлами' }
    New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
    Copy-Item -Path (Join-Path $inner[0].FullName '*') -Destination $nodeDir -Recurse -Force
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Add-UserPathEntry $nodeDir) { Write-Status 'INFO' "PATH: добавлен $nodeDir (нужна новая сессия)" }
  if (-not (Test-Path -LiteralPath $nodeExe)) { throw "node.exe не появился: $nodeExe" }
  Write-Status 'OK' "Node.js $ver -> $nodeDir"
  return $nodeExe
}

function Install-DepWebTest([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $scripts = Get-DepsWebTestScriptsDir $KitRoot
  $global = Join-Path $env:USERPROFILE ([string]$pins.webTest.skillScriptsRelative)
  $isGlobal = ($scripts -eq $global)

  if ($DryRun) {
    if (-not (Get-ExeVersion (Get-DepsNodePath) '--version' 'v(\d+(?:\.\d+){1,3})')) {
      Write-Status 'INFO' "would install Node.js LTS -> $(Expand-EnvPath $pins.webTest.nodeToolsDir)"
    } else { Write-Status 'INFO' "Node.js уже стоит: $(Get-DepsNodePath)" }
    if (Get-DepsPlaywrightInfo $scripts) { Write-Status 'INFO' "playwright уже стоит: $scripts" }
    else { Write-Status 'INFO' "would run npm ci -> $scripts" }
    if (Get-DepsPlaywrightBrowserDir) { Write-Status 'INFO' "chromium уже стоит: $(Get-DepsPlaywrightBrowserDir)" }
    else { Write-Status 'INFO' "would install chromium ($env:LOCALAPPDATA\ms-playwright)" }
    return $null
  }

  $nodeExe = Install-DepsNodePortable -KitRoot $KitRoot -Offline:$Offline
  $npm = Join-Path (Split-Path -Parent $nodeExe) 'npm.cmd'
  if (-not (Test-Path -LiteralPath $npm)) { $npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source }
  if (-not $npm) { throw "npm не найден рядом с node.exe: $nodeExe" }

  if (-not (Test-Path -LiteralPath (Join-Path $scripts 'package.json'))) {
    throw "нет package.json в каталоге скилла: $scripts"
  }

  Push-Location $scripts
  try {
    if ($Update -or -not (Get-DepsPlaywrightInfo $scripts)) {
      Write-Status 'INFO' "npm: ставлю зависимости в $scripts"
      if (Test-Path -LiteralPath (Join-Path $scripts 'package-lock.json')) {
        $npmResult = Invoke-DepsNative $npm @('ci', '--no-audit', '--no-fund') $scripts
      } else {
        $npmResult = Invoke-DepsNative $npm @('install', '--no-audit', '--no-fund') $scripts
      }
      if ($npmResult.Code -ne 0) {
        Write-Host $npmResult.Output
        throw "npm завершился с кодом $($npmResult.Code)"
      }
    }

    $pwCmd = Join-Path $scripts 'node_modules\.bin\playwright.cmd'
    if (-not (Test-Path -LiteralPath $pwCmd)) { throw "playwright.cmd не найден: $pwCmd" }
    if (-not (Get-DepsPlaywrightBrowserDir) -or $Update) {
      Write-Status 'INFO' 'playwright: ставлю браузер chromium'
      $pwResult = Invoke-DepsNative $pwCmd @('install', 'chromium') $scripts
      if ($pwResult.Code -ne 0) {
        Write-Host $pwResult.Output
        throw "playwright install завершился с кодом $($pwResult.Code)"
      }
    }
  } finally {
    Pop-Location
  }

  if (-not $isGlobal) {
    Write-Status 'WARN' 'скилл ещё не в OpenCode: после kit.ps1 apply повторите kit.ps1 deps -What web-test'
  }

  $nodeVer = Get-ExeVersion $nodeExe '--version' 'v(\d+(?:\.\d+){1,3})'
  $pwVer = Get-DepsPlaywrightInfo $scripts
  Write-Status 'OK' "Node.js $nodeVer, playwright $pwVer -> $scripts"
  return [pscustomobject]@{ Version = "node $nodeVer / playwright $pwVer"; Source = "npm:$scripts"; Sha256 = '' }
}

function Resolve-DepApachePlatforms([string[]]$Platform, [switch]$All) {
  if ($All) { return @('8.3', '8.5') }
  if ($Platform -and $Platform.Count -gt 0) {
    $out = New-Object System.Collections.ArrayList
    foreach ($p in $Platform) {
      switch ($p) {
        { $_ -in @('8.3', '83') } { if (-not $out.Contains('8.3')) { [void]$out.Add('8.3') } }
        { $_ -in @('8.5', '85') } { if (-not $out.Contains('8.5')) { [void]$out.Add('8.5') } }
        default { throw "неизвестная платформа '$p' (ожидается 8.3|83|8.5|85)" }
      }
    }
    return @($out)
  }
  $detected = @(Get-InstalledV8Platforms)
  if ($detected.Count -eq 0) { return @('8.3') }
  return $detected
}

function Get-ApacheLoungeLatest([string]$Listing, [string]$AssetPattern) {
  $html = Get-WebText $Listing
  $rx = 'href="(/download/VS18/binaries/httpd-(\d+(?:\.\d+){1,3})-\d+-Win64-VS18\.zip)"'
  $best = $null
  foreach ($m in [regex]::Matches($html, $rx)) {
    if ($AssetPattern -and ($m.Groups[1].Value -notmatch $AssetPattern)) { continue }
    $ver = $m.Groups[2].Value
    if (-not $best -or ([version]$ver -gt [version]$best.Version)) {
      $best = [pscustomobject]@{ Version = $ver; Url = ('https://www.apachelounge.com' + $m.Groups[1].Value) }
    }
  }
  return $best
}

function Install-DepApache([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun, [switch]$All, [string[]]$Platform) {
  $pins = Get-DepsPins $KitRoot
  $labels = @(Resolve-DepApachePlatforms -Platform $Platform -All:$All)
  $latest = $null
  $metas = New-Object System.Collections.ArrayList

  foreach ($label in $labels) {
    $cfg = $pins.apache.platforms.$label
    $dst = Expand-EnvPath $cfg.toolsDir
    $httpd = Join-Path $dst 'bin\httpd.exe'
    if ((Test-Path -LiteralPath $httpd) -and -not $Update) {
      Write-Status 'INFO' "Apache $label уже стоит: $dst"
      continue
    }
    if ($DryRun) {
      Write-Status 'INFO' "would install Apache $label -> $dst (port $($cfg.port))"
      continue
    }

    if (-not $latest) {
      $latest = Get-ApacheLoungeLatest $pins.apache.listing $pins.apache.assetPattern
      if (-not $latest) { throw 'не нашёл windows-сборку Apache на странице Apache Lounge' }
      Write-Status 'INFO' "Apache Lounge: версия $($latest.Version)"
    }

    $zip = Get-DepsFile $latest.Url ("httpd-$($latest.Version)-Win64-VS18.zip") -Offline:$Offline
    $tmp = Expand-DepsZip $zip
    # При обновлении не теряем уже настроенные публикации: старый httpd.conf
    # (с блоками web-publish) возвращаем на место после распаковки.
    $conf = Join-Path $dst 'conf\httpd.conf'
    $keepConf = $null
    if (Test-Path -LiteralPath $conf) { $keepConf = [System.IO.File]::ReadAllText($conf) }
    try {
      $inner = Join-Path $tmp 'Apache24'
      if (-not (Test-Path -LiteralPath $inner)) {
        $found = @(Get-ChildItem $tmp -Directory -Recurse -Filter 'Apache24' | Select-Object -First 1)
        if ($found.Count -eq 0) { throw 'в архиве нет каталога Apache24' }
        $inner = $found[0].FullName
      }
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item -Path (Join-Path $inner '*') -Destination $dst -Recurse -Force
    } finally {
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $content = if ($keepConf) { $keepConf } elseif (Test-Path -LiteralPath $conf) { [System.IO.File]::ReadAllText($conf) } else { $null }
    if ($content) {
      $fwd = ($dst -replace '\\', '/')
      $content = [regex]::Replace($content, '(?m)^Define SRVROOT .*$', "Define SRVROOT `"$fwd`"")
      [System.IO.File]::WriteAllText($conf, $content)
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $dst 'publish') | Out-Null

    $ver = Get-ExeVersion $httpd '-v' 'Apache/(\d+(?:\.\d+){1,3})'
    Write-Status 'OK' "Apache $ver ($label) -> $dst (port $($cfg.port))"
    [void]$metas.Add([pscustomobject]@{ Key = ('apache-' + $label.Replace('.', '')); Version = $ver; Source = 'apachelounge'; Sha256 = '' })
  }
  return @($metas)
}

function Install-DepToolkit([string]$KitRoot, [switch]$Update, [switch]$Offline, [switch]$DryRun) {
  $pins = Get-DepsPins $KitRoot
  $epf = Expand-EnvPath $pins.mcpToolkit.recommendedPath
  if (Test-Path -LiteralPath $epf) {
    Write-Status 'INFO' "MCP Toolkit уже стоит: $epf"
    if (-not $Update) { return $null }
  }
  if ($DryRun) {
    Write-Status 'INFO' "would install MCP_Toolkit.epf -> $epf"
    return $null
  }

  $rel = Get-GitHubLatestRelease $pins.mcpToolkit.githubRepo
  $asset = Find-ReleaseAsset $rel ('^' + [regex]::Escape([string]$pins.mcpToolkit.windowsEpfAsset) + '$')
  if (-not $asset) { throw "в релизе $($rel.tag_name) нет $($pins.mcpToolkit.windowsEpfAsset)" }
  $sha = Get-ReleaseChecksum $rel $asset.name
  $file = Get-DepsFile $asset.browser_download_url $asset.name -Offline:$Offline -ExpectedSha256 $sha
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $epf) | Out-Null
  Copy-Item -LiteralPath $file -Destination $epf -Force
  Write-Status 'OK' "MCP_Toolkit.epf $($rel.tag_name) -> $epf"
  return [pscustomobject]@{ Version = ([string]$rel.tag_name).TrimStart('v'); Source = "github:$($pins.mcpToolkit.githubRepo)@$($rel.tag_name)"; Sha256 = $sha }
}

# --------------------------------------------------------------- orchestrator

function Expand-DepsSelection([string[]]$What) {
  $all = @('oscript', 'bsl-analyzer', 'ripgrep', 'web-test', 'apache', 'toolkit')
  $required = @('oscript', 'bsl-analyzer')
  $out = New-Object System.Collections.ArrayList
  foreach ($w in @($What)) {
    switch ($w) {
      'all' { foreach ($k in $all) { if (-not $out.Contains($k)) { [void]$out.Add($k) } } }
      'required' { foreach ($k in $required) { if (-not $out.Contains($k)) { [void]$out.Add($k) } } }
      default {
        if ($all -notcontains $w) { throw "неизвестный компонент '$w' (all|required|$($all -join '|'))" }
        if (-not $out.Contains($w)) { [void]$out.Add($w) }
      }
    }
  }
  return @($out)
}

function Invoke-Deps {
  param(
    [Parameter(Mandatory = $true)][string]$KitRoot,
    [string[]]$What = @('all'),
    [switch]$Update,
    [switch]$All,
    [switch]$Offline,
    [switch]$DryRun,
    [string[]]$Platform
  )

  $keys = @(Expand-DepsSelection $What)
  Write-Host ("=== kit deps ({0}{1}) ===" -f ($keys -join ', '), $(if ($DryRun) { ', DryRun' } else { '' })) -ForegroundColor Cyan
  if ($Offline) { Write-Status 'INFO' ("режим offline: только локальный кеш " + $script:DepsCacheDir) }

  $state = Get-DepsState
  $fail = 0
  foreach ($key in $keys) {
    try {
      switch ($key) {
        'oscript' {
          $meta = Install-DepOneScript -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun
          if ($meta -and -not $DryRun) { Set-DepsStateEntry $state 'oscript' $meta }
        }
        'bsl-analyzer' {
          $meta = Install-DepBslAnalyzer -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun
          if ($meta -and -not $DryRun) { Set-DepsStateEntry $state 'bsl-analyzer' $meta }
        }
        'ripgrep' {
          $meta = Install-DepRipgrep -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun
          if ($meta -and -not $DryRun) { Set-DepsStateEntry $state 'ripgrep' $meta }
        }
        'web-test' {
          $meta = Install-DepWebTest -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun
          if ($meta -and -not $DryRun) { Set-DepsStateEntry $state 'web-test' $meta }
        }
        'apache' {
          $metas = @(Install-DepApache -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun -All:$All -Platform $Platform)
          foreach ($m in $metas) { if (-not $DryRun) { Set-DepsStateEntry $state $m.Key $m } }
        }
        'toolkit' {
          $meta = Install-DepToolkit -KitRoot $KitRoot -Update:$Update -Offline:$Offline -DryRun:$DryRun
          if ($meta -and -not $DryRun) { Set-DepsStateEntry $state 'toolkit' $meta }
        }
      }
    } catch {
      Write-Status 'FAIL' ("{0}: {1}" -f $key, $_.Exception.Message)
      $fail++
    }
  }

  if (-not $DryRun) { Save-DepsState $state }

  # Итог — только по выбранным компонентам, чтобы не пугать чужими WARN.
  $apacheKeys = @()
  if ($keys -contains 'apache') {
    $apacheKeys = @(Resolve-DepApachePlatforms -Platform $Platform -All:$All | ForEach-Object { 'apache-' + $_.Replace('.', '') })
  }
  $statuses = @(Get-DepsStatus $KitRoot | Where-Object {
      ($keys -contains 'oscript' -and $_.Key -like 'oscript*') -or
      ($keys -contains 'bsl-analyzer' -and $_.Key -like 'bsl-analyzer*') -or
      ($keys -contains 'ripgrep' -and $_.Key -eq 'ripgrep') -or
      ($keys -contains 'web-test' -and ($_.Key -eq 'node' -or $_.Key -like 'playwright*')) -or
      ($keys -contains 'toolkit' -and $_.Key -eq 'toolkit') -or
      ($apacheKeys -contains $_.Key)
    })

  Write-Host ''
  foreach ($s in $statuses) {
    if ($s.Installed) { Write-Status 'OK' ("{0} {1} -> {2}" -f $s.Label, $s.Version, $s.Path) }
    else { Write-Status 'WARN' ("{0} нет -> {1}" -f $s.Label, $s.Path) }
  }
  if ($fail -gt 0) { Write-Status 'FAIL' "deps: не установлено компонентов: $fail"; return 1 }
  Write-Status 'OK' 'deps готовы'
  return 0
}

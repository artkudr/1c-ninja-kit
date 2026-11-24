#Requires -Version 5.1
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'verify', 'apply', 'stage', 'deps', 'lock', 'help')]
  [string]$Command = 'help',

  [switch]$DryRun,
  [switch]$Strict,

  # stage/verify: проект, в который ставятся скиллы и правила.
  # Модель раздачи — проектная: копия в <проект>\.opencode, глобальный конфиг её не знает.
  [string]$ProjectRoot,

  [string]$ProfileName = '1c-ninja-kit',

  # deps: что ставить (по умолчанию всё, что проверяет doctor)
  [ValidateSet('all', 'required', 'oscript', 'bsl-analyzer', 'ripgrep', 'web-test', 'apache', 'toolkit')]
  [string[]]$What = @('all'),

  # deps: apache — обе ветки (8.3 и 8.5), а не только под установленную платформу
  [switch]$All,

  # deps: переустановить/обновить уже стоящее
  [switch]$Update,

  # deps: не ходить в сеть, брать только локальный кеш
  [switch]$Offline,

  # deps: ветка Apache (по умолчанию — по установленной платформе)
  [ValidateSet('8.3', '83', '8.5', '85')]
  [string[]]$Platform
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $KitRoot 'manifest.yaml'))) {
  throw "manifest.yaml not found near $PSScriptRoot"
}

function Write-Status([string]$Level, [string]$Msg) {
  $color = switch ($Level) {
    'OK' { 'Green' }
    'WARN' { 'Yellow' }
    'FAIL' { 'Red' }
    'INFO' { 'Cyan' }
    default { 'Gray' }
  }
  Write-Host ("[{0}] {1}" -f $Level, $Msg) -ForegroundColor $color
}

function Expand-EnvPath([string]$p) {
  return [Environment]::ExpandEnvironmentVariables($p)
}

# Машинный слой: установка внешних зависимостей и отчёт о их версиях.
. (Join-Path $PSScriptRoot 'deps.ps1')

function Set-FileContentUtf8([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-JsonLiteral([string]$Value) {
  # Minimal JSON string escaping for values injected into config files.
  if ($null -eq $Value) { return '' }
  return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Get-OpenCodeRoot() {
  return (Join-Path $env:USERPROFILE '.config\opencode')
}

# ---------- машинные пути и плейсхолдеры профиля ----------
# Правило: в profile/** нет путей с буквой диска. Машинные каталоги приходят из
# install/path-defaults.windows.yaml через плейсхолдеры, которые stage и apply
# подставляют в копии. Значение плейсхолдера — всегда env-форма ($env:VAR) или
# относительный путь: копия не должна зависеть от буквы диска этой машины.
# Шаблонное семейство ({{PROJECT_NAME}}, {{WEB_PORT}}, …) renderer не трогает:
# его разворачивает env-setup.ps1 при инициализации проекта.

$script:KitPlaceholderNames = @(
  'KIT_ROOT', 'CC_SKILLS_ROOT', 'SKILLS_ROOT', 'AGENTS_ROOT', 'COMMANDS_ROOT',
  'USER_MCP', 'PROJECT_MCP', 'PIPA_URL', 'PIPA_HOME', 'PIPA_KEY_FILE')

# Текстовые расширения, где плейсхолдеры вообще имеют смысл.
$script:RenderTextExtensions = @('.md', '.ps1', '.psm1', '.py', '.mjs', '.js', '.json',
  '.jsonc', '.yaml', '.yml', '.tpl', '.vbs', '.cmd', '.sh', '.txt', '.snippet')

function Get-PathDefaultsPath {
  return (Join-Path $KitRoot 'install\path-defaults.windows.yaml')
}

function Read-PathDefaults {
  # Плоский ридер машинного профиля: ключ через точку (mcpPolicy.userMcp),
  # скаляры в кавычках и без, комментарии. Вложенные последовательности
  # пропускаются — коду они не нужны. Полный YAML-парсер здесь лишний риск.
  $map = @{}
  $path = Get-PathDefaultsPath
  if (-not (Test-Path -LiteralPath $path)) { return $map }
  $stack = @()
  foreach ($raw in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
    $line = $raw.TrimEnd()
    if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
    if ($line.TrimStart().StartsWith('- ')) { continue }
    $m = [regex]::Match($line, '^(\s*)([\w.\-"]+):\s*(.*)$')
    if (-not $m.Success) { continue }
    $indent = $m.Groups[1].Value.Length
    $key = $m.Groups[2].Value.Trim('"')
    $value = $m.Groups[3].Value.Trim()

    while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
      $stack = @($stack | Select-Object -First ($stack.Count - 1))
    }
    $full = (@($stack | ForEach-Object { $_.Key }) + $key) -join '.'
    $stack += [pscustomobject]@{ Indent = $indent; Key = $key }

    if (-not $value) { continue }
    if ($value.StartsWith('[')) { continue }
    if ($value.StartsWith('"')) {
      $end = $value.LastIndexOf('"')
      if ($end -gt 0) { $value = $value.Substring(1, $end - 1) }
      $value = $value.Replace('\\', '\').Replace('\"', '"')
    } else {
      $hash = $value.IndexOf(' #')
      if ($hash -ge 0) { $value = $value.Substring(0, $hash).Trim() }
    }
    $map[$full] = $value
  }
  return $map
}

function Get-PathDefault([hashtable]$Defaults, [string]$Key) {
  if ($Defaults.ContainsKey($Key)) { return [string]$Defaults[$Key] }
  return ''
}

function Get-MachineEnvValue([string]$Name) {
  # env главнее файла. Порядок: процесс (то, что видит сессия), затем
  # пользователь и машина — чтобы новая переменная работала до перезапуска.
  foreach ($scope in @('Process', 'User', 'Machine')) {
    $value = [Environment]::GetEnvironmentVariable($Name, $scope)
    if ($value) { return [string]$value }
  }
  return ''
}

function ConvertTo-EnvForm([string]$Value) {
  # %USERPROFILE%\x -> $env:USERPROFILE\x: в pwsh %VAR% не раскрывается.
  if (-not $Value) { return '' }
  return [regex]::Replace($Value, '%([A-Za-z_][A-Za-z0-9_]*)%', '$$env:$1')
}

function Get-KitRootForm {
  if (-not (Get-MachineEnvValue 'NINJA_KIT_ROOT')) {
    throw ('NINJA_KIT_ROOT не задана. Профиль подставляет {{KIT_ROOT}} только через неё, ' +
      'чтобы не вписать в копию чужой путь. Задай переменную (kit.ps1 apply делает это сам) ' +
      'и запусти команду в новом процессе.')
  }
  return '$env:NINJA_KIT_ROOT'
}

function Get-PlaceholderMap([ValidateSet('stage', 'apply')][string]$Layer) {
  # Значения — только из машинного профиля (и env-токен для корня кита):
  # stage и verify считают карту одним и тем же кодом, поэтому подстановка не
  # зависит от того, какие переменные были в процессе в момент прогона.
  # Env-переопределения (CC_SKILLS_ROOT, PIPA_URL, PIPA_KEY_FILE) описаны
  # прозой в скиллах, а не подставлены: иначе копия «разъезжается» сама.
  $defaults = Read-PathDefaults
  $ccSkills = ConvertTo-EnvForm (Get-PathDefault $defaults 'ccSkills.skillsRoot')
  if (-not $ccSkills) { $ccSkills = '$env:USERPROFILE\.config\opencode\skills' }

  $pipaUrl = Get-PathDefault $defaults 'pipa.url'
  if (-not $pipaUrl) { $pipaUrl = 'http://127.0.0.1:8787/mcp' }
  $pipaKeyFile = Get-PathDefault $defaults 'pipa.keyFile'
  if (-not $pipaKeyFile) { $pipaKeyFile = '%PIPA_HOME%\pithos-pandoras.key' }

  $userMcp = ConvertTo-EnvForm (Get-PathDefault $defaults 'mcpPolicy.userMcp')
  if (-not $userMcp) { $userMcp = '$env:USERPROFILE\.config\opencode\opencode.json(c)' }

  $ocRel = '.config\opencode'
  $skillsRoot = if ($Layer -eq 'stage') { '.opencode/skills' } else { '$env:USERPROFILE\' + $ocRel + '\skills' }

  return @{
    KIT_ROOT        = (Get-KitRootForm)
    CC_SKILLS_ROOT  = $ccSkills
    SKILLS_ROOT     = $skillsRoot
    AGENTS_ROOT     = '$env:USERPROFILE\' + $ocRel + '\agents'
    COMMANDS_ROOT   = '$env:USERPROFILE\' + $ocRel + '\commands'
    USER_MCP        = $userMcp
    PROJECT_MCP     = 'opencode.jsonc'
    PIPA_URL        = $pipaUrl
    PIPA_HOME       = '$env:PIPA_HOME'
    PIPA_KEY_FILE   = (ConvertTo-EnvForm $pipaKeyFile)
  }
}

function Test-RenderTextFile([string]$Path) {
  return ($script:RenderTextExtensions -contains ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()))
}

function Get-RenderedFile([string]$Path, [hashtable]$Map) {
  # $null — файл копируется байт-в-байт (бинарь или нет ни одного нашего
  # плейсхолдера). Иначе текст и признак BOM: PowerShell 5.1 читает .ps1 с
  # кириллицей только с BOM, поэтому BOM сохраняется как был.
  if (-not $Map -or $Map.Count -eq 0) { return $null }
  if (-not (Test-RenderTextFile $Path)) { return $null }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  $changed = $false
  foreach ($name in $script:KitPlaceholderNames) {
    $token = '{{' + $name + '}}'
    if ($text.IndexOf($token, [System.StringComparison]::Ordinal) -lt 0) { continue }
    $text = $text.Replace($token, [string]$Map[$name])
    $changed = $true
  }
  if (-not $changed) { return $null }
  return [pscustomobject]@{ Text = $text; Bom = $hasBom }
}

function Copy-RenderedFile([string]$Source, [string]$Destination, [hashtable]$Map) {
  $rendered = Get-RenderedFile $Source $Map
  $dir = Split-Path -Parent $Destination
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  if ($null -eq $rendered) {
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return
  }
  $encoding = [System.Text.UTF8Encoding]::new([bool]$rendered.Bom)
  [System.IO.File]::WriteAllText($Destination, $rendered.Text, $encoding)
}

function Get-ExpectedFileHash([string]$Path, [hashtable]$Map) {
  # Хеш того, что должно лежать в копии: байты исходника или отрендеренный текст.
  # BOM входит в байты файла, поэтому в хеш он тоже входит.
  $rendered = Get-RenderedFile $Path $Map
  if ($null -eq $rendered) { return (Get-TextSha256 $Path) }
  $encoding = [System.Text.UTF8Encoding]::new([bool]$rendered.Bom)
  $body = $encoding.GetBytes($rendered.Text)
  $bytes = $body
  if ($rendered.Bom) {
    $bytes = New-Object byte[] ($body.Length + 3)
    $bytes[0] = 0xEF; $bytes[1] = 0xBB; $bytes[2] = 0xBF
    [Array]::Copy($body, 0, $bytes, 3, $body.Length)
  }
  return (Get-TextSha256Bytes $bytes)
}

function Get-TextSha256Bytes([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
  return (@($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-ProfileAbsolutePaths {
  # Линт профиля: путь с буквой диска на другой машине неверен. Исключения —
  # только системный корень платформы (allowlist) и node_modules/.git.
  $allowlist = @('C:\Program Files\1cv8')
  $pattern = '(?<![A-Za-z0-9_])[A-Za-z]:[\\/]'
  $issues = @()
  $root = Join-Path $KitRoot 'profile'
  if (-not (Test-Path -LiteralPath $root)) { return $issues }
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
    $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/')
    if (Test-StageExcluded $rel) { continue }
    if (-not (Test-RenderTextFile $file.FullName)) { continue }
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    foreach ($match in [regex]::Matches($text, $pattern)) {
      $tail = $text.Substring($match.Index, [Math]::Min(64, $text.Length - $match.Index))
      $allowed = $false
      foreach ($prefix in $allowlist) {
        if ($tail.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $allowed = $true; break }
      }
      if ($allowed) { continue }
      $lineNo = 1
      for ($i = 0; $i -lt $match.Index; $i++) { if ($text[$i] -eq "`n") { $lineNo++ } }
      $issues += [pscustomobject]@{
        File = 'profile\' + $rel
        Line = $lineNo
        Text = ($tail -split "[`r`n]")[0].Trim()
      }
    }
  }
  return $issues
}

function Get-OpenCodeConfigPath() {
  # Канон — opencode.jsonc. Если на машине есть только opencode.json, правим его:
  # два конкурирующих конфига в одном каталоге — это неопределённость, а не миграция.
  $ocRoot = Get-OpenCodeRoot
  $jsonc = Join-Path $ocRoot 'opencode.jsonc'
  $json = Join-Path $ocRoot 'opencode.json'
  if ((Test-Path -LiteralPath $json) -and -not (Test-Path -LiteralPath $jsonc)) { return $json }
  return $jsonc
}

# --- JSONC: точечная правка двух ключей без потери остального файла -----------

function Find-JsoncValueEnd([string]$Text, [int]$Start) {
  # Конец значения JSON: запятая или закрывающая скобка родителя на нулевой глубине.
  $length = $Text.Length
  $index = $Start
  $depth = 0
  $inString = $false
  $escaped = $false
  while ($index -lt $length) {
    $symbol = $Text[$index]
    if ($inString) {
      if ($escaped) { $escaped = $false }
      elseif ($symbol -eq '\') { $escaped = $true }
      elseif ($symbol -eq '"') { $inString = $false }
      $index++
      continue
    }
    if ($symbol -eq '"') { $inString = $true; $index++; continue }
    if ($symbol -eq '/' -and $index + 1 -lt $length) {
      if ($Text[$index + 1] -eq '/') {
        $index += 2
        while ($index -lt $length -and $Text[$index] -ne "`n" -and $Text[$index] -ne "`r") { $index++ }
        continue
      }
      if ($Text[$index + 1] -eq '*') {
        $index += 2
        while ($index + 1 -lt $length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) { $index++ }
        $index += 2
        continue
      }
    }
    if ($symbol -eq '{' -or $symbol -eq '[') { $depth++; $index++; continue }
    if ($symbol -eq '}' -or $symbol -eq ']') {
      if ($depth -eq 0) { break }
      $depth--
      $index++
      continue
    }
    if ($symbol -eq ',' -and $depth -eq 0) { break }
    $index++
  }
  $end = $index
  while ($end -gt $Start -and [char]::IsWhiteSpace($Text[$end - 1])) { $end-- }
  return $end
}

function Find-JsoncTopLevelValue([string]$Text, [string]$Name) {
  # Ищет свойство верхнего уровня по имени и возвращает границы его значения.
  $length = $Text.Length
  $index = 0
  $depth = 0
  $inString = $false
  $escaped = $false
  $stringStart = -1
  while ($index -lt $length) {
    $symbol = $Text[$index]
    if ($inString) {
      if ($escaped) { $escaped = $false }
      elseif ($symbol -eq '\') { $escaped = $true }
      elseif ($symbol -eq '"') {
        $inString = $false
        $literal = $Text.Substring($stringStart + 1, $index - $stringStart - 1)
        if ($depth -eq 1 -and $literal -eq $Name) {
          $next = $index + 1
          while ($next -lt $length -and [char]::IsWhiteSpace($Text[$next])) { $next++ }
          if ($next -lt $length -and $Text[$next] -eq ':') {
            $valueStart = $next + 1
            while ($valueStart -lt $length -and [char]::IsWhiteSpace($Text[$valueStart])) { $valueStart++ }
            return [pscustomobject]@{ Found = $true; Start = $valueStart; End = (Find-JsoncValueEnd $Text $valueStart) }
          }
        }
      }
      $index++
      continue
    }
    if ($symbol -eq '"') { $inString = $true; $stringStart = $index; $index++; continue }
    if ($symbol -eq '/' -and $index + 1 -lt $length) {
      if ($Text[$index + 1] -eq '/') {
        $index += 2
        while ($index -lt $length -and $Text[$index] -ne "`n" -and $Text[$index] -ne "`r") { $index++ }
        continue
      }
      if ($Text[$index + 1] -eq '*') {
        $index += 2
        while ($index + 1 -lt $length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) { $index++ }
        $index += 2
        continue
      }
    }
    if ($symbol -eq '{' -or $symbol -eq '[') { $depth++; $index++; continue }
    if ($symbol -eq '}' -or $symbol -eq ']') { $depth--; $index++; continue }
    $index++
  }
  return [pscustomobject]@{ Found = $false; Start = -1; End = -1 }
}

function Find-JsoncTopLevelProperty([string]$Text, [string]$Name) {
  # Как Find-JsoncTopLevelValue, но отдаёт ещё и начало имени свойства:
  # нужно, чтобы вырезать ключ целиком.
  $length = $Text.Length
  $index = 0
  $depth = 0
  $inString = $false
  $escaped = $false
  $stringStart = -1
  while ($index -lt $length) {
    $symbol = $Text[$index]
    if ($inString) {
      if ($escaped) { $escaped = $false }
      elseif ($symbol -eq '\') { $escaped = $true }
      elseif ($symbol -eq '"') {
        $inString = $false
        $literal = $Text.Substring($stringStart + 1, $index - $stringStart - 1)
        if ($depth -eq 1 -and $literal -eq $Name) {
          $next = $index + 1
          while ($next -lt $length -and [char]::IsWhiteSpace($Text[$next])) { $next++ }
          if ($next -lt $length -and $Text[$next] -eq ':') {
            $valueStart = $next + 1
            while ($valueStart -lt $length -and [char]::IsWhiteSpace($Text[$valueStart])) { $valueStart++ }
            return [pscustomobject]@{
              Found      = $true
              KeyStart   = $stringStart
              ValueStart = $valueStart
              ValueEnd   = (Find-JsoncValueEnd $Text $valueStart)
            }
          }
        }
      }
      $index++
      continue
    }
    if ($symbol -eq '"') { $inString = $true; $stringStart = $index; $index++; continue }
    if ($symbol -eq '/' -and $index + 1 -lt $length) {
      if ($Text[$index + 1] -eq '/') {
        $index += 2
        while ($index -lt $length -and $Text[$index] -ne "`n" -and $Text[$index] -ne "`r") { $index++ }
        continue
      }
      if ($Text[$index + 1] -eq '*') {
        $index += 2
        while ($index + 1 -lt $length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) { $index++ }
        $index += 2
        continue
      }
    }
    if ($symbol -eq '{' -or $symbol -eq '[') { $depth++; $index++; continue }
    if ($symbol -eq '}' -or $symbol -eq ']') { $depth--; $index++; continue }
    $index++
  }
  return [pscustomobject]@{ Found = $false; KeyStart = -1; ValueStart = -1; ValueEnd = -1 }
}

function Remove-JsoncTopLevelValue([string]$Text, [string]$Key) {
  # Удаляет свойство верхнего уровня вместе с запятой и осиротевшей строкой.
  $span = Find-JsoncTopLevelProperty $Text $Key
  if (-not $span.Found) { return $Text }
  $length = $Text.Length

  $lineStart = $span.KeyStart
  while ($lineStart -gt 0 -and $Text[$lineStart - 1] -ne "`n") { $lineStart-- }
  $prefix = $Text.Substring($lineStart, $span.KeyStart - $lineStart)
  $removeStart = if ($prefix.Trim() -eq '') { $lineStart } else { $span.KeyStart }

  $i = $span.ValueEnd
  while ($i -lt $length -and [char]::IsWhiteSpace($Text[$i])) { $i++ }
  if ($i -lt $length -and $Text[$i] -eq ',') {
    # Свойство не последнее: режем его вместе с запятой и переводом строки.
    $i++
    while ($i -lt $length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $i++ }
    if ($i -lt $length -and $Text[$i] -eq "`r") { $i++ }
    if ($i -lt $length -and $Text[$i] -eq "`n") { $i++ }
    return $Text.Substring(0, $removeStart) + $Text.Substring($i)
  }

  # Последнее свойство: убираем запятую перед ним.
  $j = $removeStart - 1
  while ($j -ge 0 -and [char]::IsWhiteSpace($Text[$j])) { $j-- }
  if ($j -ge 0 -and $Text[$j] -eq ',') {
    return $Text.Substring(0, $j) + $Text.Substring($span.ValueEnd)
  }
  return $Text.Substring(0, $removeStart) + $Text.Substring($span.ValueEnd)
}

function Set-JsoncTopLevelValue([string]$Text, [string]$Key, [string]$JsonValue) {
  $span = Find-JsoncTopLevelValue $Text $Key
  if ($span.Found) {
    return $Text.Substring(0, $span.Start) + $JsonValue + $Text.Substring($span.End)
  }
  $close = $Text.LastIndexOf('}')
  if ($close -lt 0) { throw "JSONC без закрывающей скобки: некуда вставить $Key" }
  $head = $Text.Substring(0, $close).TrimEnd()
  $tail = $Text.Substring($close)
  $trimmed = $head.TrimStart()
  $sep = if ($trimmed.EndsWith('{') -or $trimmed.EndsWith(',')) { '' } else { ',' }
  return $head + $sep + "`n  `"$Key`": " + $JsonValue + "`n" + $tail
}

function Convert-JsoncToJson([string]$Text) {
  # Комментарии и висячие запятые убираются только вне строк: иначе путь с «//» ломает разбор.
  $length = $Text.Length
  $sb = New-Object System.Text.StringBuilder
  $index = 0
  $inString = $false
  $escaped = $false
  while ($index -lt $length) {
    $symbol = $Text[$index]
    if ($inString) {
      [void]$sb.Append($symbol)
      if ($escaped) { $escaped = $false }
      elseif ($symbol -eq '\') { $escaped = $true }
      elseif ($symbol -eq '"') { $inString = $false }
      $index++
      continue
    }
    if ($symbol -eq '"') { $inString = $true; [void]$sb.Append($symbol); $index++; continue }
    if ($symbol -eq '/' -and $index + 1 -lt $length) {
      if ($Text[$index + 1] -eq '/') {
        $index += 2
        while ($index -lt $length -and $Text[$index] -ne "`n" -and $Text[$index] -ne "`r") { $index++ }
        continue
      }
      if ($Text[$index + 1] -eq '*') {
        $index += 2
        while ($index + 1 -lt $length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) { $index++ }
        $index += 2
        continue
      }
    }
    [void]$sb.Append($symbol)
    $index++
  }

  $plain = $sb.ToString()
  $sb2 = New-Object System.Text.StringBuilder
  $index = 0
  $inString = $false
  $escaped = $false
  while ($index -lt $plain.Length) {
    $symbol = $plain[$index]
    if ($inString) {
      [void]$sb2.Append($symbol)
      if ($escaped) { $escaped = $false }
      elseif ($symbol -eq '\') { $escaped = $true }
      elseif ($symbol -eq '"') { $inString = $false }
      $index++
      continue
    }
    if ($symbol -eq '"') { $inString = $true; [void]$sb2.Append($symbol); $index++; continue }
    if ($symbol -eq ',') {
      $next = $index + 1
      while ($next -lt $plain.Length -and [char]::IsWhiteSpace($plain[$next])) { $next++ }
      if ($next -lt $plain.Length -and ($plain[$next] -eq '}' -or $plain[$next] -eq ']')) { $index++; continue }
    }
    [void]$sb2.Append($symbol)
    $index++
  }
  return $sb2.ToString()
}

function Test-JsoncText([string]$Text) {
  try {
    $json = Convert-JsoncToJson $Text
    if (-not $json.Trim()) { return [pscustomobject]@{ Ok = $false; Error = 'пустой текст' } }
    $null = $json | ConvertFrom-Json
    return [pscustomobject]@{ Ok = $true; Error = '' }
  } catch {
    return [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message }
  }
}

function Read-JsoncObject([string]$Path) {
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  $check = Test-JsoncText $text
  if (-not $check.Ok) { throw "JSONC не разобран ($Path): $($check.Error)" }
  return (Convert-JsoncToJson $text) | ConvertFrom-Json
}

function Write-JsoncAtomically([string]$Path, [string]$Content) {
  # Битый глобальный конфиг ломает OpenCode целиком, поэтому: временный файл,
  # проверка разбора, резервная копия рядом, только потом замена.
  $dir = Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText($temp, $Content, [System.Text.UTF8Encoding]::new($false))
    $check = Test-JsoncText ([System.IO.File]::ReadAllText($temp, [System.Text.Encoding]::UTF8))
    if (-not $check.Ok) { throw "JSONC не разобран, файл не записан: $($check.Error)" }
    if (Test-Path -LiteralPath $Path) {
      $backup = $Path + '.bak-' + (Get-Date).ToString('yyyyMMdd-HHmmss')
      Copy-Item -LiteralPath $Path -Destination $backup -Force
      # Держим пять последних копий: apply запускают часто, каталог не должен пухнуть.
      $old = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -File -EA SilentlyContinue |
        Where-Object { $_.Name -like ((Split-Path -Leaf $Path) + '.bak-*') } |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 5)
      foreach ($item in $old) { Remove-Item -LiteralPath $item.FullName -Force -EA SilentlyContinue }
      try { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) }
      catch { Move-Item -LiteralPath $temp -Destination $Path -Force }
    } else {
      Move-Item -LiteralPath $temp -Destination $Path -Force
    }
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -EA SilentlyContinue }
  }
}

function Format-JsoncArray([string[]]$Items) {
  $lines = @(foreach ($item in $Items) { '    "' + (ConvertTo-JsonLiteral $item) + '"' })
  return '[' + "`n" + ($lines -join ",`n") + "`n  ]"
}

function Get-KitSkillSources {
  # Скилл и on-demand правило — одно и то же по форме: каталог с SKILL.md.
  $items = @()
  foreach ($dir in @(
      (Join-Path $KitRoot 'profile\skills'),
      (Join-Path $KitRoot 'profile\rules\on-demand'))) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $items += @(Get-ChildItem -LiteralPath $dir -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })
  }
  return $items
}

function Get-KitAlwaysRules {
  $dir = Join-Path $KitRoot 'profile\rules\always'
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md')
}

function Test-StageExcluded([string]$RelPath) {
  # В проект едет содержимое скилла, а не локальные установки и служебные каталоги.
  foreach ($seg in ($RelPath -split '[\\/]')) {
    if ($seg -eq 'node_modules' -or $seg -eq '.git') { return $true }
  }
  # Состояние браузерной сессии — машинное, у каждой копии своё.
  if ((Split-Path -Leaf $RelPath) -like '.browser-session*') { return $true }
  return $false
}

function Copy-TreeFiltered([string]$Source, [string]$Destination, [hashtable]$RenderMap) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $base = (Resolve-Path -LiteralPath $Source).Path
  foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File) {
    $rel = $file.FullName.Substring($base.Length).TrimStart('\', '/')
    if (Test-StageExcluded $rel) { continue }
    $target = Join-Path $Destination $rel
    Copy-RenderedFile $file.FullName $target $RenderMap
  }
}

function Get-KitProjectFiles([string]$Dir, [hashtable]$RenderMap) {
  # Относительный путь + хеш для каждого файла: так проверяется копия целиком,
  # а не только SKILL.md. С RenderMap хеш считается от того, что должно быть в
  # копии после подстановки плейсхолдеров.
  $result = @()
  if (-not (Test-Path -LiteralPath $Dir)) { return $result }
  $base = (Resolve-Path -LiteralPath $Dir).Path
  foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File) {
    $rel = $file.FullName.Substring($base.Length).TrimStart('\', '/')
    if (Test-StageExcluded $rel) { continue }
    $hash = if ($RenderMap) { Get-ExpectedFileHash $file.FullName $RenderMap } else { Get-TextSha256 $file.FullName }
    $result += [pscustomobject]@{ Rel = $rel; Hash = $hash }
  }
  return $result
}

function Test-PathUnderKit([string]$Path) {
  if (-not $Path) { return $false }
  if ($Path -match '^https?://') { return $false }
  try {
    $full = [System.IO.Path]::GetFullPath((Expand-EnvPath $Path)).TrimEnd('\', '/')
    $kit = [System.IO.Path]::GetFullPath($KitRoot).TrimEnd('\', '/')
    return $full.StartsWith($kit, [System.StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Clear-OpenCodeGlobalKitPaths {
  # Скиллы и правила больше не раздаются глобально: у каждого проекта своя копия.
  # Здесь убираем пути кита, оставшиеся от прежней модели, чужие записи не трогаем.
  $path = Get-OpenCodeConfigPath
  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{ Path = $path; Removed = 0; Exists = $false }
  }
  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $obj = Read-JsoncObject $path
  $removed = 0
  $changed = $false
  foreach ($key in @('skills', 'instructions')) {
    $present = @($obj.PSObject.Properties.Name) -contains $key
    if (-not $present) { continue }
    $current = @($obj.$key | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    $keep = @($current | Where-Object { -not (Test-PathUnderKit $_) })
    $removed += ($current.Count - $keep.Count)
    if ($keep.Count -eq 0) {
      # Пустой массив в конфиге — мусор: ключ убираем целиком.
      $text = Remove-JsoncTopLevelValue $text $key
      $changed = $true
    } elseif ($keep.Count -ne $current.Count) {
      $text = Set-JsoncTopLevelValue $text $key (Format-JsoncArray $keep)
      $changed = $true
    }
  }
  if ($changed) { Write-JsoncAtomically $path $text }
  return [pscustomobject]@{ Path = $path; Removed = $removed; Exists = $true }
}

function Set-KitProjectInstructions([string]$Root, [switch]$DryRunInner) {
  # В проектном конфиге достаточно instructions: .opencode/skills OpenCode находит сам.
  $path = Join-Path $Root 'opencode.jsonc'
  $glob = '.opencode/rules/always/*.md'
  $schemaJson = '"https://opencode.ai/config.json"'

  if ($DryRunInner) { return [pscustomobject]@{ Path = $path; Action = 'would-merge'; HasGlob = $true } }

  if (-not (Test-Path -LiteralPath $path)) {
    $body = "{" + "`n" + '  "$schema": ' + $schemaJson + ',' + "`n" + '  "instructions": [' + "`n" + '    "' + $glob + '"' + "`n" + '  ]' + "`n" + '}' + "`n"
    Set-FileContentUtf8 $path $body
    return [pscustomobject]@{ Path = $path; Action = 'created'; HasGlob = $true }
  }

  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $obj = Read-JsoncObject $path
  $hasGlob = @($obj.instructions | ForEach-Object { [string]$_ }) -contains $glob
  $hasSchema = (Find-JsoncTopLevelValue $text '$schema').Found
  if ($hasGlob -and $hasSchema) {
    return [pscustomobject]@{ Path = $path; Action = 'unchanged'; HasGlob = $true }
  }
  if (-not $hasSchema) {
    $text = Set-JsoncTopLevelValue $text '$schema' $schemaJson
  }
  if (-not $hasGlob) {
    $items = @(@($obj.instructions | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) + $glob |
        Where-Object { $_ } | Select-Object -Unique)
    $text = Set-JsoncTopLevelValue $text 'instructions' (Format-JsoncArray $items)
  }
  if (-not $text.EndsWith("`n")) { $text += "`n" }
  Write-JsoncAtomically $path $text
  return [pscustomobject]@{ Path = $path; Action = 'merged'; HasGlob = $true }
}

function Remove-LegacyKitSkills {
  # Старая модель: копия профиля в skills\kit. Удаляется только этот каталог.
  $path = Join-Path (Get-OpenCodeRoot) 'skills\kit'
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  Remove-Item -LiteralPath $path -Recurse -Force
  return $true
}

function Clear-OpenCodeGlobalAgentsBlock {
  # Правила приходят через instructions; управляемый блок в AGENTS.md — дубль.
  $path = Join-Path (Get-OpenCodeRoot) 'AGENTS.md'
  $begin = '<!-- 1c-ninja-kit:begin -->'
  $end = '<!-- 1c-ninja-kit:end -->'
  if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
  $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  if (-not $existing) { return 'absent' }
  if (-not $existing.Contains($begin) -or -not $existing.Contains($end)) { return 'no-block' }

  $i = $existing.IndexOf($begin)
  $j = $existing.IndexOf($end) + $end.Length
  $before = $existing.Substring(0, $i).TrimEnd()
  $after = $existing.Substring($j).TrimStart()
  $rest = $before
  if ($before -and $after) { $rest = $before + "`n`n" + $after }
  elseif ($after) { $rest = $after }
  $rest = $rest.Trim()

  if (-not $rest) {
    # Файл целиком был блоком кита — тогда и файла быть не должно.
    Remove-Item -LiteralPath $path -Force
    return 'removed'
  }
  Set-FileContentUtf8 $path ($rest + "`n")
  return 'cleaned'
}

function Get-TextSha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hash = $sha.ComputeHash($bytes)
  } finally { $sha.Dispose() }
  return (@($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Copy-ProfileFiles([string]$Source, [string]$Destination, [string]$Filter, [hashtable]$RenderMap) {
  # Копия с подстановкой плейсхолдеров; файлы без них и бинарные — байт-в-байт.
  # run.ps1 сохранён в UTF-8 с BOM: кириллица не должна зависеть от кодировки консоли.
  if (-not (Test-Path -LiteralPath $Source)) { throw "Source missing: $Source" }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $files = @(Get-ChildItem -LiteralPath $Source -File -Filter $Filter)
  foreach ($file in $files) {
    Copy-RenderedFile $file.FullName (Join-Path $Destination $file.Name) $RenderMap
  }
  return $files.Count
}

function Install-LeaseCleanTask {
  # Машинная задача: снимает мёртвые writer.lease bsl-analyzer (ничего не запускает).
  # Нужна из-за Windows-дефекта лаунчера: убитый backend оставляет аренду и граф отвечает
  # "graph busy ... used by another live process". Скрипт лежит в скилле skill-env-setup.
  #
  # Задача стартует не pwsh напрямую, а тонкий .vbs-лаунчер через wscript.exe. Планировщик
  # запускает консольные программы в интерактивной сессии, поэтому прямой вызов pwsh даёт
  # видимое консольное окно на каждый прогон; `-WindowStyle Hidden` его не убирает (окно
  # успевает показаться). wscript — GUI-подсистема, окна нет вообще.
  param([string]$SkillsDst)

  $script = Join-Path $SkillsDst 'skill-env-setup\scripts\bsl-analyzer-lease-clean.ps1'
  if (-not (Test-Path -LiteralPath $script)) {
    Write-Status 'WARN' 'lease-clean: скрипт не найден в скиллах, задача не ставится'
    return
  }
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
  if (-not $pwsh) {
    Write-Status 'WARN' 'lease-clean: pwsh не найден, задача не ставится'
    return
  }

  $launcher = Join-Path $SkillsDst 'skill-env-setup\scripts\bsl-analyzer-lease-clean.vbs'
  $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'

  $taskName = 'bsl-analyzer lease clean'
  if ($DryRun) {
    Write-Status 'INFO' "would register scheduled task '$taskName' (logon + every 5 min, hidden via wscript)"
    return
  }

  try {
    if ((Test-Path -LiteralPath $launcher) -and (Test-Path -LiteralPath $wscript)) {
      $action = New-ScheduledTaskAction -Execute $wscript -Argument "//B //Nologo `"$launcher`""
      $mode = 'wscript, no window'
    } else {
      # Старое поведение: окно на каждый прогон, но задача работает.
      Write-Status 'WARN' 'lease-clean: нет .vbs-лаунчера или wscript.exe — задача будет с видимым окном'
      $action = New-ScheduledTaskAction -Execute $pwsh `
        -Argument ("-WindowStyle Hidden -NoProfile -NonInteractive -File `"$script`"")
      $mode = 'pwsh (window may flash)'
    }
    $tLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $tRepeat = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
      -RepetitionInterval (New-TimeSpan -Minutes 5)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
      -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
      -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($tLogon, $tRepeat) `
      -Settings $settings -Principal $principal -Force `
      -Description 'Снимает мёртвые writer.lease bsl-analyzer (ничего не запускает).' | Out-Null
    Write-Status 'OK' "scheduled task '$taskName' registered (logon + every 5 min, $mode)"
  } catch {
    Write-Status 'WARN' "lease-clean: задача не зарегистрирована: $($_.Exception.Message)"
  }
}

function Invoke-Stage {
  # Проектная раздача: копия скиллов и правил внутрь проекта.
  # Глобальный конфиг в этом не участвует — проект самодостаточен.
  Write-Host '=== kit stage ===' -ForegroundColor Cyan
  if (-not $ProjectRoot) {
    Write-Status 'FAIL' 'stage: укажи проект — kit.ps1 stage -ProjectRoot C:\1C\projects\<проект>'
    return 1
  }
  $root = [System.IO.Path]::GetFullPath((Expand-EnvPath $ProjectRoot))
  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Write-Status 'FAIL' "stage: нет каталога $root"
    return 1
  }

  $ocDir = Join-Path $root '.opencode'
  $skillsDst = Join-Path $ocDir 'skills'
  $rulesDst = Join-Path $ocDir 'rules\always'
  $manifestPath = Join-Path $ocDir 'kit-stage.json'

  $sources = @(Get-KitSkillSources)
  $always = @(Get-KitAlwaysRules)
  $ids = @($sources | ForEach-Object { $_.Name })
  try {
    $renderMap = Get-PlaceholderMap 'stage'
  } catch {
    Write-Status 'FAIL' ("stage: " + $_.Exception.Message)
    return 1
  }
  Write-Status 'INFO' "project: $root"
  Write-Status 'INFO' ("skills -> .opencode\skills: {0}; always rules -> .opencode\rules\always: {1}" -f $sources.Count, $always.Count)
  Write-Status 'INFO' ("placeholders: " + (($renderMap.Keys | Sort-Object) -join ', '))

  if ($DryRun) {
    Write-Status 'INFO' "would stage $($sources.Count) skills and $($always.Count) always rules"
    Write-Status 'INFO' "would merge instructions '$('.opencode/rules/always/*.md')' into $(Join-Path $root 'opencode.jsonc')"
    Write-Status 'WARN' 'DryRun - no files written'
    return 0
  }

  New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
  New-Item -ItemType Directory -Force -Path $rulesDst | Out-Null

  # Прежние копии могли притащить локальные установки (node_modules) — убираем,
  # чтобы проект не разбухал.
  foreach ($noise in @(Get-ChildItem -LiteralPath $skillsDst -Recurse -Directory -Force -EA SilentlyContinue |
      Where-Object { $_.Name -eq 'node_modules' })) {
    Remove-Item -LiteralPath $noise.FullName -Recurse -Force
  }

  # Что ставили в прошлый раз и чего в профиле больше нет — убираем, чтобы проект
  # не тащил удалённые правила.
  $previous = @()
  if (Test-Path -LiteralPath $manifestPath) {
    try {
      $previous = @((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).skills)
    } catch { $previous = @() }
  }
  $removed = 0
  foreach ($name in $previous) {
    if ($ids -contains $name) { continue }
    $stale = Join-Path $skillsDst $name
    if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force; $removed++ }
  }

  foreach ($src in $sources) {
    # Копируем поверх, а не «удалить и заново»: OpenCode следит за каталогом,
    # и на время удаления скилл не должен исчезать из набора.
    $dst = Join-Path $skillsDst $src.Name
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-TreeFiltered $src.FullName $dst $renderMap
    $srcFiles = @(Get-KitProjectFiles $src.FullName $renderMap | ForEach-Object { $_.Rel })
    foreach ($f in @(Get-ChildItem -LiteralPath $dst -Recurse -File)) {
      $rel = $f.FullName.Substring($dst.Length).TrimStart('\', '/')
      if (Test-StageExcluded $rel) { Remove-Item -LiteralPath $f.FullName -Force; continue }
      if ($srcFiles -notcontains $rel) { Remove-Item -LiteralPath $f.FullName -Force }
    }
  }
  Write-Status 'OK' ("skills staged: {0}{1}" -f $sources.Count, $(if ($removed) { ", removed $removed stale" } else { '' }))

  $alwaysNames = @($always | ForEach-Object { $_.Name })
  $removedRules = 0
  foreach ($file in @(Get-ChildItem -LiteralPath $rulesDst -File -Filter '*.md' -EA SilentlyContinue)) {
    if ($alwaysNames -contains $file.Name) { continue }
    Remove-Item -LiteralPath $file.FullName -Force
    $removedRules++
  }
  foreach ($file in $always) {
    Copy-RenderedFile $file.FullName (Join-Path $rulesDst $file.Name) $renderMap
  }
  Write-Status 'OK' ("always rules staged: {0}{1}" -f $always.Count, $(if ($removedRules) { ", removed $removedRules stale" } else { '' }))

  $manifest = [ordered]@{
    profile  = $ProfileName
    version  = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
    stagedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    skills   = $ids
    always   = $alwaysNames
  }
  $manifestText = $manifest | ConvertTo-Json -Depth 5
  $manifestChanged = $true
  if (Test-Path -LiteralPath $manifestPath) {
    try {
      $old = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $manifestChanged = ((@($old.skills) -join ',') -ne ($ids -join ',')) -or
        ((@($old.always) -join ',') -ne ($alwaysNames -join ',')) -or
        ($old.version -ne $manifest.version)
    } catch { $manifestChanged = $true }
  }
  if ($manifestChanged) { Set-FileContentUtf8 $manifestPath $manifestText }
  Write-Status 'OK' "manifest -> $manifestPath$(if (-not $manifestChanged) { ' (unchanged)' } else { '' })"

  $cfg = Set-KitProjectInstructions $root
  Write-Status 'OK' ("config {0}: {1}, instructions=.opencode/rules/always/*.md" -f $cfg.Action, $cfg.Path)
  Write-Status 'INFO' 'config changes apply without restart; new session sees project skills'
  return 0
}

function Test-StageInProject([string]$Root) {
  # Проверка проектной копии: каждый файл скилла совпадает с профилем после
  # подстановки плейсхолдеров.
  $problems = @()
  $ocDir = Join-Path $Root '.opencode'
  $skillsDst = Join-Path $ocDir 'skills'
  $rulesDst = Join-Path $ocDir 'rules\always'
  $sources = @(Get-KitSkillSources)
  $always = @(Get-KitAlwaysRules)
  try {
    $renderMap = Get-PlaceholderMap 'stage'
  } catch {
    Write-Status 'FAIL' ("{0}: {1}" -f $Root, $_.Exception.Message)
    return 1
  }

  foreach ($src in $sources) {
    $dst = Join-Path $skillsDst $src.Name
    if (-not (Test-Path -LiteralPath $dst)) { $problems += "нет $($src.Name)"; continue }
    $a = @(Get-KitProjectFiles $src.FullName $renderMap)
    $b = @(Get-KitProjectFiles $dst)
    if ($a.Count -ne $b.Count) { $problems += "$($src.Name): файлов $($b.Count) из $($a.Count)"; continue }
    $bad = 0
    foreach ($f in $a) {
      $match = @($b | Where-Object { $_.Rel -eq $f.Rel })
      if ($match.Count -eq 0 -or $match[0].Hash -ne $f.Hash) { $bad++ }
    }
    if ($bad -gt 0) { $problems += "$($src.Name): разошлось файлов $bad" }
  }
  foreach ($file in $always) {
    $dst = Join-Path $rulesDst $file.Name
    if (-not (Test-Path -LiteralPath $dst)) { $problems += "нет правила $($file.Name)"; continue }
    if ((Get-ExpectedFileHash $file.FullName $renderMap) -ne (Get-TextSha256 $dst)) { $problems += "правило $($file.Name) разошлось" }
  }

  $cfgPath = Join-Path $Root 'opencode.jsonc'
  if (-not (Test-Path -LiteralPath $cfgPath)) {
    $problems += 'нет opencode.jsonc с instructions'
  } else {
    try {
      $cfg = Read-JsoncObject $cfgPath
      $glob = '.opencode/rules/always/*.md'
      $has = @($cfg.instructions | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -contains $glob
      if (-not $has) { $problems += "в opencode.jsonc нет instructions '$glob'" }
    } catch { $problems += "opencode.jsonc не разбирается: $($_.Exception.Message)" }
  }

  if ($problems.Count -gt 0) {
    Write-Status 'FAIL' ("{0}: {1} - run: kit.ps1 stage -ProjectRoot {0}" -f $Root, ($problems -join '; '))
    return 1
  }
  Write-Status 'OK' ("{0}: {1} skills and {2} always rules match profile" -f $Root, $sources.Count, $always.Count)
  return 0
}


function Invoke-ApplyOpenCode {
  # Глобально остаются только агенты, команды и скрипт каркаса. Скиллы и правила
  # больше не раздаются из кита: их ставит kit.ps1 stage в каждый проект.
  $ocRoot = Get-OpenCodeRoot
  Write-Status 'INFO' "OpenCode root: $ocRoot"

  $agentsSrc = Join-Path $KitRoot 'profile\agents'
  $commandsSrc = Join-Path $KitRoot 'profile\commands'
  $scriptsSrc = Join-Path $KitRoot 'profile\scripts'
  $agentsDst = Join-Path $ocRoot 'agents'
  $commandsDst = Join-Path $ocRoot 'commands'
  $scriptsDst = Join-Path $ocRoot 'scripts'

  $agentCount = @(Get-ChildItem $agentsSrc -File -Filter '*.md' -EA SilentlyContinue).Count
  $commandCount = @(Get-ChildItem $commandsSrc -File -Filter '*.md' -EA SilentlyContinue).Count
  $scriptCount = @(Get-ChildItem $scriptsSrc -File -EA SilentlyContinue).Count
  Write-Status 'INFO' "agents=$agentCount, commands=$commandCount, scripts=$scriptCount"

  if ($DryRun) {
    Write-Status 'INFO' "would copy agents=$agentCount, commands=$commandCount, scripts=$scriptCount -> $ocRoot"
    Write-Status 'INFO' 'would remove kit skill/instruction paths from the global config (if present)'
    Write-Status 'INFO' "would remove legacy $(Join-Path $ocRoot 'skills\kit') if present"
    Write-Status 'INFO' "would strip managed block from $(Join-Path $ocRoot 'AGENTS.md')"
    Write-Status 'INFO' "would set NINJA_KIT_ROOT (user env) -> $KitRoot"
    Write-Status 'WARN' 'DryRun - no files written'
    return 0
  }

  # 0. Корень кита для профиля: {{KIT_ROOT}} разворачивается в $env:NINJA_KIT_ROOT,
  # поэтому переменную ставит apply, а не догадка в каждом скилле. Новая
  # переменная видна только процессам, запущенным после этого — как PIPA_KEY.
  $currentKitRoot = Get-MachineEnvValue 'NINJA_KIT_ROOT'
  if ($currentKitRoot -ne $KitRoot) {
    [Environment]::SetEnvironmentVariable('NINJA_KIT_ROOT', $KitRoot, 'User')
    $env:NINJA_KIT_ROOT = $KitRoot
    if ($currentKitRoot) { Write-Status 'WARN' "NINJA_KIT_ROOT: $currentKitRoot -> $KitRoot (user env)" }
    else { Write-Status 'OK' "NINJA_KIT_ROOT -> $KitRoot (user env)" }
    Write-Status 'INFO' 'NINJA_KIT_ROOT увидят только новые процессы: перезапусти OpenCode и терминал'
  } else {
    Write-Status 'OK' "NINJA_KIT_ROOT = $KitRoot"
  }

  try {
    $renderMap = Get-PlaceholderMap 'apply'
  } catch {
    Write-Status 'FAIL' ("apply: " + $_.Exception.Message)
    return 1
  }

  # 1. Агентов, команды и скрипт каркаса OpenCode берёт только копией.
  [void](Copy-ProfileFiles $agentsSrc $agentsDst '*.md' $renderMap)
  [void](Copy-ProfileFiles $commandsSrc $commandsDst '*.md' $renderMap)
  [void](Copy-ProfileFiles $scriptsSrc $scriptsDst '*' $renderMap)
  Write-Status 'OK' "agents -> $agentsDst ($agentCount), commands -> $commandsDst ($commandCount), scripts -> $scriptsDst ($scriptCount)"

  # 2. Старая модель копировала профиль в skills\kit — сносим только этот каталог.
  if (Remove-LegacyKitSkills) { Write-Status 'OK' "removed legacy $(Join-Path $ocRoot 'skills\kit')" }
  else { Write-Status 'INFO' 'no legacy skills\kit' }

  # 3. Машинная задача lease-clean: скрипт лежит в репозитории кита.
  Install-LeaseCleanTask -SkillsDst (Join-Path $KitRoot 'profile\skills')

  # 4. Always-on правила теперь приходят из проектного конфига — блок в AGENTS.md дубль.
  $agentsState = Clear-OpenCodeGlobalAgentsBlock
  switch ($agentsState) {
    'removed' { Write-Status 'OK' "removed $(Join-Path $ocRoot 'AGENTS.md') (it was the kit block only)" }
    'cleaned' { Write-Status 'OK' "stripped managed block from $(Join-Path $ocRoot 'AGENTS.md')" }
    default { Write-Status 'INFO' 'global AGENTS.md: no kit block' }
  }

  # 5. Убираем из глобального конфига пути кита, оставшиеся от прежней модели.
  $cleared = Clear-OpenCodeGlobalKitPaths
  if (-not $cleared.Exists) {
    Write-Status 'WARN' "global config not found: $($cleared.Path)"
  } elseif ($cleared.Removed -gt 0) {
    Write-Status 'OK' "global config -> $($cleared.Path): removed $($cleared.Removed) kit path(s) from skills/instructions"
  } else {
    Write-Status 'OK' "global config -> $($cleared.Path): no kit skill/instruction paths"
  }

  $skillsMissing = @(Get-KitSkillSources | Where-Object { -not (Test-Path (Join-Path $_.FullName 'SKILL.md')) })
  foreach ($s in $skillsMissing) { Write-Status 'WARN' "skill without SKILL.md (skipped by OpenCode): $($s.Name)" }

  foreach ($name in @('opencode.json', 'opencode.jsonc')) {
    $cfg = Join-Path $ocRoot $name
    if (Test-Path -LiteralPath $cfg) {
      $raw = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
      $bad = @('1c-ninja-mcp', '1c-mcp-toolkit', 'bsl-analyzer')
      $hits = @($bad | Where-Object { $raw -match [regex]::Escape($_) })
      if ($hits.Count -gt 0) {
        Write-Status 'WARN' ("global $name contains 1C MCP servers: " + ($hits -join ', ') + ' -> move to project opencode.jsonc')
      }
      else {
        Write-Status 'OK' "global $name has no 1C MCP server names"
      }
      # browse — живой Chrome пользователя. По умолчанию он выключен: GitLab и трекеры
      # идут через CLI, проверка 1С — через skill-web-test.
      try {
        $cfgData = Read-JsoncObject $cfg
        $browse = $null
        if ($cfgData.mcp -and $cfgData.mcp.servers) { $browse = $cfgData.mcp.servers.browse }
        if ($browse -and -not ($browse.disabled -eq $true)) {
          Write-Status 'WARN' "global $name keeps browse enabled: это живой Chrome, включай осознанно (disabled: true)"
        }
      } catch { }
    }
  }
  Write-Status 'INFO' 'скиллы и правила ставятся в проект: kit.ps1 stage -ProjectRoot <проект>'
  return 0
}

function Invoke-Doctor {
  $kitVersion = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
  Write-Host "=== kit doctor ($kitVersion) KitRoot=$KitRoot ===" -ForegroundColor Cyan
  $fail = 0
  $warn = 0

  # Платформа 1С: ставится только дистрибутивом. Без неё Apache бесполезен —
  # 1С-коннектор wsap24.dll берётся из её bin.
  $v8exe = Get-ChildItem 'C:\Program Files\1cv8\*\bin\1cv8.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($v8exe) { Write-Status 'OK' "1cv8: $($v8exe.FullName)" }
  else {
    Write-Status 'FAIL' '1cv8 not found (C:\Program Files\1cv8\*\bin) - ставится дистрибутивом 1С, автоматически не ставится'
    $fail++
  }

  # Внешние зависимости: что стоит, чего нет и какой командой это лечится.
  # Версии и пути — из companions/pins.json, фактическое состояние — с машины.
  $pins = Get-DepsPins $KitRoot
  foreach ($dep in Get-DepsStatus $KitRoot) {
    $hint = switch -Wildcard ($dep.Key) {
      'oscript*' { 'oscript' }
      'bsl-analyzer*' { 'bsl-analyzer' }
      'apache-*' { 'apache' }
      'node' { 'web-test' }
      'playwright*' { 'web-test' }
      default { $dep.Key }
    }

    if (-not $dep.Installed) {
      if ($dep.Required) {
        Write-Status 'FAIL' "$($dep.Label) отсутствует: $($dep.Path)"
        $fail++
      } else {
        Write-Status 'WARN' "$($dep.Label) отсутствует: $($dep.Path)"
        $warn++
      }
      Write-Status 'INFO' "  поставить: kit.ps1 deps -What $hint"
      continue
    }

    $msg = "$($dep.Label) $($dep.Version) -> $($dep.Path)"
    if ($dep.Note) { $msg += " ($($dep.Note))" }

    $min = $null
    if ($dep.Key -eq 'bsl-analyzer-app') { $min = [string]$pins.bslAnalyzer.minAppVersion }
    elseif ($dep.Key -eq 'node') { $min = [string]$pins.webTest.minNodeVersion }
    elseif ($dep.Key -like 'apache-*') { $min = [string]$pins.apache.minVersion }

    if ($min -and -not (Test-DepsVersionAtLeast $dep.Version $min)) {
      Write-Status 'WARN' ("{0}; ниже минимума {1} - kit.ps1 deps -What {2} -Update" -f $msg, $min, $hint)
      $warn++
    } else {
      Write-Status 'OK' $msg
    }
  }

  $ninjaMain = Join-Path $KitRoot 'components\1c-ninja-mcp\main.os'
  if (Test-Path -LiteralPath $ninjaMain) { Write-Status 'OK' "1c-ninja-mcp -> $ninjaMain" }
  else { Write-Status 'FAIL' "1c-ninja-mcp missing: $ninjaMain"; $fail++ }

  $nl = Join-Path $KitRoot 'project-scaffold\cfe\NinjaLive'
  if (Test-Path -LiteralPath $nl) { Write-Status 'OK' "NinjaLive pair -> $nl" }
  else { Write-Status 'FAIL' "NinjaLive missing: $nl"; $fail++ }

  $ocRoot = Get-OpenCodeRoot
  foreach ($name in @('opencode.json', 'opencode.jsonc')) {
    $cfg = Join-Path $ocRoot $name
    if (-not (Test-Path -LiteralPath $cfg)) { continue }
    $raw = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
    $bad = @('1c-ninja-mcp', '1c-mcp-toolkit', 'bsl-analyzer')
    $hits = @($bad | Where-Object { $raw -match [regex]::Escape($_) })
    if ($hits.Count -gt 0) {
      Write-Status 'WARN' ("global opencode $name contains 1C MCP servers: " + ($hits -join ', '))
      $warn++
    } else {
      Write-Status 'OK' "global opencode $name has no 1C MCP server names"
    }
  }
  # Доставка профиля: скиллы и правила читаются по путям из открытого конфига,
  # агенты/команды/скрипт каркаса — копией. Сверяем то, что реально увидит OpenCode.
  $configPath = Get-OpenCodeConfigPath
  if (Test-Path -LiteralPath $configPath) {
    Write-Status 'OK' "global config: $configPath"
    try {
      $cfgData = Read-JsoncObject $configPath
      # Модель проектная: скиллы и правила живут в проекте, в глобальном конфиге их нет.
      # Ключ отсутствует или пуст — это норма; пути проверяем только если они прописаны.
      $skillPaths = @($cfgData.skills | Where-Object { $_ })
      if ($skillPaths.Count -eq 0) {
        Write-Status 'INFO' "global $((Split-Path -Leaf $configPath)): скиллы не прописаны (проектная модель, ок)"
      } else {
        $missing = @($skillPaths | Where-Object { -not (Test-Path -LiteralPath ([string]$_)) })
        if ($missing.Count -gt 0) {
          Write-Status 'WARN' ("skills paths missing: " + ($missing -join ', ') + ' - run: kit.ps1 apply')
          $warn++
        } else {
          Write-Status 'OK' ("skills paths: " + ($skillPaths -join ', '))
        }
      }
    } catch {
      Write-Status 'WARN' "global config unreadable: $($_.Exception.Message)"
      $warn++
    }
  } else {
    Write-Status 'INFO' 'global config absent (ok) - run: kit.ps1 apply'
  }
  $n = @(Get-ChildItem (Join-Path $ocRoot 'skills') -Recurse -File -Filter 'SKILL.md' -EA SilentlyContinue).Count
  Write-Status 'INFO' "external skills in $ocRoot\skills: $n"
  if (Test-Path (Join-Path $ocRoot 'skills\kit')) {
    Write-Status 'WARN' 'legacy skills\kit still present - run: kit.ps1 apply'
    $warn++
  }
  foreach ($pair in @(@('agents', 'profile\agents', '*.md'), @('commands', 'profile\commands', '*.md'), @('scripts', 'profile\scripts', '*'))) {
    $dst = Join-Path $ocRoot $pair[0]
    $src = Join-Path $KitRoot $pair[1]
    $srcFiles = @(Get-ChildItem -LiteralPath $src -File -Filter $pair[2] -EA SilentlyContinue)
    $missing = @($srcFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dst $_.Name)) })
    if ($missing.Count -gt 0) {
      Write-Status 'WARN' ("$($pair[0]): not installed: " + ($missing.Name -join ', ') + ' - run: kit.ps1 apply')
      $warn++
    } else {
      Write-Status 'OK' "$($pair[0]): $($srcFiles.Count) files -> $dst"
    }
  }
  if (Test-Path (Join-Path $ocRoot 'skills\db-list\SKILL.md')) {
    Write-Status 'OK' 'cc-1c-skills installed (db-* present)'
  } else {
    Write-Status 'WARN' 'cc-1c-skills missing - run: install\cc-skills.ps1'
    $warn++
  }

  # Задача lease clean: запуск должен идти через wscript-лаунчер, иначе на каждый прогон
  # появляется консольное окно (см. Install-LeaseCleanTask).
  $leaseTask = Get-ScheduledTask -TaskName 'bsl-analyzer lease clean' -ErrorAction SilentlyContinue
  if ($leaseTask) {
    $leaseAction = @($leaseTask.Actions)[0]
    $leaseExe = [string]$leaseAction.Execute
    $leaseVbs = if ([string]$leaseAction.Arguments -match '"?([^"]+\.vbs)"?') { $Matches[1] } else { '' }
    if ($leaseExe -notmatch 'wscript\.exe$') {
      Write-Status 'WARN' "lease-clean task runs '$leaseExe' (console window flashes) - rerun kit.ps1 apply"
      $warn++
    } elseif (-not (Test-Path -LiteralPath $leaseVbs)) {
      Write-Status 'WARN' "lease-clean launcher missing: $leaseVbs - rerun kit.ps1 apply"
      $warn++
    } else {
      Write-Status 'OK' 'lease-clean task runs hidden via wscript'
    }
  } else {
    Write-Status 'INFO' 'lease-clean task absent (ok) - kit.ps1 apply installs it'
  }

  Write-Host ("Summary: fail={0} warn={1}" -f $fail, $warn) -ForegroundColor Cyan
  if ($fail -gt 0) { Write-Status 'FAIL' 'doctor blocked'; return 1 }
  if ($Strict -and $warn -gt 0) { Write-Status 'FAIL' 'doctor strict failed'; return 1 }
  Write-Status 'OK' 'doctor ready'
  return 0
}

function Get-ProfileNames {
  # Фактический состав профиля: agents (*.md), skills (каталог с SKILL.md),
  # rules = always (*.md) + on-demand (каталог с SKILL.md). Порядок — ординарный,
  # чтобы namesHashSha256 не зависел от локали машины.
  $agents = @(Get-ChildItem (Join-Path $KitRoot 'profile\agents') -File -Filter '*.md' -EA SilentlyContinue |
    ForEach-Object { $_.BaseName })
  $skills = @(Get-ChildItem (Join-Path $KitRoot 'profile\skills') -Directory -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object { $_.Name })
  $rules = @(
    @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\always') -File -Filter '*.md' -EA SilentlyContinue |
      ForEach-Object { $_.BaseName })
    @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\on-demand') -Directory -EA SilentlyContinue |
      Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object { $_.Name })
  )
  $result = @{}
  foreach ($pair in @(@('agents', $agents), @('skills', $skills), @('rules', $rules))) {
    [string[]]$names = @($pair[1])
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    $result[$pair[0]] = $names
  }
  return $result
}

function Get-NamesHash([hashtable]$Names) {
  # Канон namesHashSha256 (docs/versioning.md): одна строка JSON без пробелов,
  # ключи по алфавиту (agents, rules, skills), имена ординарно отсортированы,
  # кириллица сырым UTF-8, LF в конце. Хеш — SHA-256, hex в нижнем регистре.
  $parts = @('agents', 'rules', 'skills') | ForEach-Object {
    $list = @($Names[$_]) | ForEach-Object { '"' + ($_ -replace '\\', '\\\\').Replace('"', '\"') + '"' }
    '"' + $_ + '":[' + ($list -join ',') + ']'
  }
  $canonical = '{' + ($parts -join ',') + '}' + "`n"
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $hash = $sha.ComputeHash($bytes)
  } finally { $sha.Dispose() }
  return (@($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Invoke-Lock {
  Write-Host '=== kit lock ===' -ForegroundColor Cyan
  $names = Get-ProfileNames
  $counts = @{
    agents = @($names.agents).Count
    skills = @($names.skills).Count
    rules  = @($names.rules).Count
  }
  $lock = [ordered]@{
    version         = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
    profile         = $ProfileName
    capturedAt      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    counts          = [ordered]@{ agents = $counts.agents; skills = $counts.skills; rules = $counts.rules }
    namesHashSha256 = (Get-NamesHash $names)
    skills          = @($names.skills)
    rules           = @($names.rules)
    agents          = @($names.agents)
  }

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('{')
  $scalars = @('version', 'profile', 'capturedAt')
  foreach ($key in $scalars) {
    [void]$sb.AppendLine("  `"$key`": `"$($lock[$key])`",")
  }
  [void]$sb.AppendLine('  "counts": {')
  [void]$sb.AppendLine("    `"agents`": $($counts.agents),")
  [void]$sb.AppendLine("    `"skills`": $($counts.skills),")
  [void]$sb.AppendLine("    `"rules`": $($counts.rules)")
  [void]$sb.AppendLine('  },')
  [void]$sb.AppendLine("  `"namesHashSha256`": `"$($lock.namesHashSha256)`",")
  foreach ($key in @('skills', 'rules', 'agents')) {
    [void]$sb.AppendLine("  `"$key`": [")
    $list = @($lock[$key])
    for ($i = 0; $i -lt $list.Count; $i++) {
      $comma = if ($i -lt $list.Count - 1) { ',' } else { '' }
      [void]$sb.AppendLine("    `"$($list[$i])`"$comma")
    }
    $closing = if ($key -eq 'agents') { '  ]' } else { '  ],' }
    [void]$sb.AppendLine($closing)
  }
  [void]$sb.AppendLine('}')
  $text = $sb.ToString()

  $path = Join-Path $KitRoot 'lock\profile.lock.json'
  if ($DryRun) {
    Write-Status 'INFO' ("would write {0} (agents={1} skills={2} rules={3})" -f $path, $counts.agents, $counts.skills, $counts.rules)
    return 0
  }
  Set-FileContentUtf8 $path $text
  Write-Status 'OK' ("lock -> {0}" -f $path)
  Write-Status 'INFO' ("agents={0} skills={1} rules={2} hash={3}" -f $counts.agents, $counts.skills, $counts.rules, $lock.namesHashSha256)
  return 0
}

function Invoke-Verify {
  Write-Host '=== kit verify ===' -ForegroundColor Cyan
  $fail = 0
  $skills = @(Get-ChildItem (Join-Path $KitRoot 'profile\skills') -Directory -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
  $always = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\always') -File -Filter '*.md' -EA SilentlyContinue).Count
  $ondemand = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\on-demand') -Directory -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
  $rules = $always + $ondemand
  $agents = @(Get-ChildItem (Join-Path $KitRoot 'profile\agents') -File -Filter '*.md' -EA SilentlyContinue).Count
  Write-Status 'OK' "profile skills=$skills rules=$rules (always=$always, on-demand=$ondemand) agents=$agents"

  # Профиль обязан оставаться переносимым: путь с буквой диска на другой машине
  # неверен. Исключение одно — системный корень платформы 1С (allowlist ниже).
  $pathIssues = @(Test-ProfileAbsolutePaths)
  if ($pathIssues.Count -gt 0) {
    $files = @($pathIssues | ForEach-Object { $_.File } | Sort-Object -Unique).Count
    Write-Status 'FAIL' ("profile: {0} absolute path(s) in {1} file(s) - use {{{{PLACEHOLDER}}}} or %ENV% / `$env:ENV" -f $pathIssues.Count, $files)
    foreach ($issue in $pathIssues) {
      Write-Status 'INFO' ("  {0}:{1}  {2}" -f $issue.File, $issue.Line, $issue.Text)
    }
    $fail++
  } else {
    Write-Status 'OK' 'profile: no absolute paths (allowlist: C:\Program Files\1cv8)'
  }

  # Маршруты и роли — единственный источник rule-routes.md. Копия в другом правиле
  # или в промпте разъедется при следующей правке, поэтому ловим её здесь.
  $routeRows = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules') -Recurse -File -Filter '*.md' -EA SilentlyContinue |
    Select-String -SimpleMatch '| `полный` |' -List)
  if ($routeRows.Count -ne 1) {
    Write-Status 'FAIL' ("route table must live in exactly one rule file, found: " + $(if ($routeRows.Count) { ($routeRows.Path -join ', ') } else { 'none' }))
    return 1
  }
  if ((Split-Path -Leaf $routeRows[0].Path) -ne 'rule-routes.md') {
    Write-Status 'FAIL' "route table lives in $($routeRows[0].Path); move it to profile\rules\always\rule-routes.md"
    return 1
  }
  Write-Status 'OK' 'route table: single source rule-routes.md'

  # Права: один shell-вход и явная модель у каждой роли. Два почти одинаковых паттерна
  # в семи файлах — источник «permission denied» и дрейфа; модель без явного выбора
  # означает, что планирование, код и приёмка идут одной дорогой моделью.
  $agentsDir = Join-Path $KitRoot 'profile\agents'
  if (-not (Test-Path (Join-Path $KitRoot 'profile\scripts\run.ps1'))) {
    Write-Status 'FAIL' 'profile\scripts\run.ps1 missing - roles have no single shell entry'; return 1
  }
  $oldShell = @(Get-ChildItem $agentsDir -File -Filter '*.md' -EA SilentlyContinue |
    Select-String -SimpleMatch 'opencode/skills/*/scripts/*.ps1')
  if ($oldShell.Count -gt 0) {
    Write-Status 'FAIL' ("agents still use per-skill shell patterns: " + (($oldShell | ForEach-Object { Split-Path -Leaf $_.Path }) -join ', ') + ' - route them through scripts/run.ps1')
    return 1
  }
  $noModel = @(Get-ChildItem $agentsDir -File -Filter '*.md' -EA SilentlyContinue |
    Where-Object {
      $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
      ($text -notmatch '(?m)^model:\s+\S+') -or ($text -notmatch '(?m)^temperature:')
    })
  if ($noModel.Count -gt 0) {
    Write-Status 'FAIL' ("agents without model/temperature: " + (($noModel | ForEach-Object { $_.BaseName }) -join ', '))
    return 1
  }
  Write-Status 'OK' 'agents: one shell entry scripts/run.ps1, model/temperature set'

  if (-not (Test-Path (Join-Path $KitRoot 'lock\profile.lock.json'))) {
    Write-Status 'FAIL' 'lock/profile.lock.json missing - run: kit.ps1 lock'; return 1
  }
  # Lock — снимок профиля. Расхождение значит, что его забыли пересобрать
  # после правки profile/: сам файл никто не читает, сверяет только verify.
  try {
    $lockData = Get-Content (Join-Path $KitRoot 'lock\profile.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $actual = Get-ProfileNames
    $drift = @()
    foreach ($key in @('agents', 'skills', 'rules')) {
      $a = @($actual[$key])
      $l = @($lockData.$key)
      if ($a.Count -ne $l.Count -or (Compare-Object -ReferenceObject $a -DifferenceObject $l -CaseSensitive)) {
        $drift += "$key lock=$($l.Count) profile=$($a.Count)"
      }
    }
    $hash = Get-NamesHash $actual
    if ($lockData.namesHashSha256 -ne $hash) { $drift += "namesHashSha256=$($lockData.namesHashSha256) profile=$hash" }
    if ($drift.Count -gt 0) {
      Write-Status 'FAIL' ("lock/profile.lock.json is stale (" + ($drift -join '; ') + ") - run: kit.ps1 lock")
      return 1
    }
    Write-Status 'OK' "lock matches profile (agents=$($actual.agents.Count) skills=$($actual.skills.Count) rules=$($actual.rules.Count))"
  } catch {
    Write-Status 'FAIL' "lock/profile.lock.json unreadable: $($_.Exception.Message) - run: kit.ps1 lock"; return 1
  }
  if (-not (Test-Path (Join-Path $KitRoot 'profile\profiles\1c-ninja-kit.yaml'))) {
    Write-Status 'FAIL' 'profile aggregate missing'; return 1
  }
  Write-Status 'OK' 'aggregate profile 1c-ninja-kit.yaml'

  # Доставка в глобальный профиль. Проверяем ровно то, что увидит OpenCode:
  # пути скиллов/правил в конфиге, отсутствие старой копии и копии агентов,
  # команд и скрипта каркаса — с подстановкой плейсхолдеров, как их пишет apply.
  $ocRoot = Get-OpenCodeRoot
  $skillsSrc = Join-Path $KitRoot 'profile\skills'
  $rulesSrc = Join-Path $KitRoot 'profile\rules'
  foreach ($dir in @($skillsSrc, $rulesSrc)) {
    if (Test-Path -LiteralPath $dir -PathType Container) { Write-Status 'OK' "skills source: $dir" }
    else { Write-Status 'FAIL' "skills source missing: $dir"; $fail++ }
  }

  $configPath = Get-OpenCodeConfigPath
  if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Status 'FAIL' "global config missing: $configPath - run: kit.ps1 apply"; $fail++
  } else {
    try {
      $cfgData = Read-JsoncObject $configPath
      $leaks = @()
      foreach ($key in @('skills', 'instructions')) {
        foreach ($entry in @($cfgData.$key | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })) {
          if (Test-PathUnderKit $entry) { $leaks += "$key=$entry" }
        }
      }
      if ($leaks.Count -gt 0) {
        Write-Status 'FAIL' ("global config still points into kit: " + ($leaks -join ', ') + ' - run: kit.ps1 apply'); $fail++
      } else {
        Write-Status 'OK' 'global config: no kit skill/instruction paths (project staging mode)'
      }
    } catch {
      Write-Status 'FAIL' "global config is not valid JSONC: $($_.Exception.Message)"; $fail++
    }
  }

  $legacy = Join-Path $ocRoot 'skills\kit'
  if (Test-Path -LiteralPath $legacy) {
    Write-Status 'FAIL' "legacy skills\kit still present: $legacy - run: kit.ps1 apply"; $fail++
  } else {
    Write-Status 'OK' 'no legacy skills\kit'
  }

  $globalAgents = Join-Path $ocRoot 'AGENTS.md'
  if (Test-Path -LiteralPath $globalAgents) {
    $rawAgents = Get-Content -LiteralPath $globalAgents -Raw -Encoding UTF8
    if ($rawAgents -and $rawAgents.Contains('<!-- 1c-ninja-kit:begin -->')) {
      Write-Status 'FAIL' 'global AGENTS.md still carries the kit block - run: kit.ps1 apply'; $fail++
    } else {
      Write-Status 'OK' 'global AGENTS.md has no kit block'
    }
  }

  $copies = @(
    @('agents', 'profile\agents', '*.md'),
    @('commands', 'profile\commands', '*.md'),
    @('scripts', 'profile\scripts', '*')
  )
  $applyMap = $null
  try { $applyMap = Get-PlaceholderMap 'apply' }
  catch { Write-Status 'WARN' ("placeholders not resolved: " + $_.Exception.Message) }
  foreach ($pair in $copies) {
    $layer = $pair[0]
    $src = Join-Path $KitRoot $pair[1]
    $dst = Join-Path $ocRoot $layer
    $srcFiles = @(Get-ChildItem -LiteralPath $src -File -Filter $pair[2] -EA SilentlyContinue)
    $problems = @()
    foreach ($file in $srcFiles) {
      $target = Join-Path $dst $file.Name
      if (-not (Test-Path -LiteralPath $target)) { $problems += "нет $($file.Name)"; continue }
      $expected = if ($applyMap) { Get-ExpectedFileHash $file.FullName $applyMap } else { Get-TextSha256 $file.FullName }
      if ($expected -ne (Get-TextSha256 $target)) { $problems += "разошёлся $($file.Name)" }
    }
    if ($srcFiles.Count -eq 0) { $problems += 'в профиле нет файлов' }
    if ($problems.Count -gt 0) {
      Write-Status 'FAIL' ("{0}: {1} - run: kit.ps1 apply" -f $dst, ($problems -join ', ')); $fail++
    } else {
      Write-Status 'OK' ("{0}: {1} files match profile" -f $dst, $srcFiles.Count)
    }
  }

  if ($fail -gt 0) { return 1 }

  if ($ProjectRoot) {
    $projRoot = [System.IO.Path]::GetFullPath((Expand-EnvPath $ProjectRoot))
    if (Test-StageInProject $projRoot) { $fail++ }
  } else {
    Write-Status 'INFO' 'проверить проектный набор: kit.ps1 verify -ProjectRoot <проект>'
  }

  if ($fail -gt 0) { return 1 }
  Write-Status 'INFO' ("VERSION=" + (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim())
  return 0
}

function Invoke-Apply {
  Write-Host "=== kit apply --profile $ProfileName ===" -ForegroundColor Cyan
  if ($ProfileName -ne '1c-ninja-kit') {
    Write-Status 'FAIL' "Unknown profile '$ProfileName'"; return 1
  }
  return (Invoke-ApplyOpenCode)
}


switch ($Command) {
  'doctor' { exit (Invoke-Doctor) }
  'verify' { exit (Invoke-Verify) }
  'lock' { exit (Invoke-Lock) }
  'apply' { exit (Invoke-Apply) }
  'stage' { exit (Invoke-Stage) }
  'deps' {
    exit (Invoke-Deps -KitRoot $KitRoot -What $What -Update:$Update -All:$All -Offline:$Offline `
        -DryRun:$DryRun -Platform $Platform)
  }
  default {
    $kitVersion = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
    Write-Host "1c-ninja-kit CLI $kitVersion"
    Write-Host '  kit.ps1 doctor [-Strict]'
    Write-Host '  kit.ps1 verify [-ProjectRoot <проект>]'
    Write-Host '  kit.ps1 lock [-DryRun]      # пересобрать lock/profile.lock.json из profile\'
    Write-Host '  kit.ps1 apply [-DryRun]     # агенты/команды/скрипт глобально; пути кита из глобального конфига убираются'
    Write-Host '  kit.ps1 stage -ProjectRoot <проект> [-DryRun]  # скиллы и правила копией в проект'
    Write-Host '  kit.ps1 deps [-What all|required|oscript|bsl-analyzer|ripgrep|web-test|apache|toolkit]'
    Write-Host '                [-Update] [-All] [-Offline] [-Platform 8.3|8.5] [-DryRun]'
    Write-Host 'Project bootstrap: skill-env-setup ("разверни окружение")'
    Write-Host "KitRoot: $KitRoot"
    exit 0
  }
}

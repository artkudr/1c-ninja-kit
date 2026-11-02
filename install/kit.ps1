#Requires -Version 5.1
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'verify', 'apply', 'deps', 'lock', 'help')]
  [string]$Command = 'help',

  [switch]$DryRun,
  [switch]$Strict,

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

# ---------- paths for rule/skill placeholders ----------
# Rules and SKILL.md stay layout-neutral: they carry {{SKILLS_ROOT}},
# {{AGENTS_ROOT}}, {{COMMANDS_ROOT}}, {{PROJECT_MCP}}, {{USER_MCP}}.
# apply resolves them for OpenCode, so no document ships stale absolute paths.

function Get-OpenCodeRoot() {
  return (Join-Path $env:USERPROFILE '.config\opencode')
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

function Get-KitSkillPaths([string]$KitRoot) {
  # Источники, которые OpenCode читает напрямую из репозитория кита.
  $skills = @(
    ((Join-Path $KitRoot 'profile\skills') -replace '\\', '/')
    ((Join-Path $KitRoot 'profile\rules') -replace '\\', '/')
  )
  $alwaysGlob = ((Join-Path $KitRoot 'profile\rules\always') -replace '\\', '/') + '/*.md'
  return [pscustomobject]@{ Skills = $skills; Instructions = @($alwaysGlob) }
}

function Write-OpenCodeGlobalConfig([string]$KitRoot) {
  $path = Get-OpenCodeConfigPath
  $paths = Get-KitSkillPaths $KitRoot
  $schemaJson = '"https://opencode.ai/config.json"'
  $skillsJson = Format-JsoncArray $paths.Skills
  $instructionsJson = Format-JsoncArray $paths.Instructions

  $text = ''
  if (Test-Path -LiteralPath $path) {
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  }
  if (-not $text.Trim()) {
    $text = "{" + "`n" + '  "$schema": ' + $schemaJson + ',' + "`n" + '  "skills": ' + $skillsJson + ',' + "`n" + '  "instructions": ' + $instructionsJson + "`n" + '}' + "`n"
  } else {
    # Меняем только свои два ключа: остальные настройки пользователя остаются как были.
    if (-not (Find-JsoncTopLevelValue $text '$schema').Found) {
      $text = Set-JsoncTopLevelValue $text '$schema' $schemaJson
    }
    $text = Set-JsoncTopLevelValue $text 'skills' $skillsJson
    $text = Set-JsoncTopLevelValue $text 'instructions' $instructionsJson
    if (-not $text.EndsWith("`n")) { $text += "`n" }
  }
  Write-JsoncAtomically $path $text
  return $path
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

function Copy-ProfileFiles([string]$Source, [string]$Destination, [string]$Filter) {
  # Копия байт-в-байт: taskctl.ps1 сохранён в UTF-8 с BOM, иначе PowerShell 5.1
  # читает кириллицу как ANSI. Чужие файлы в целевом каталоге не трогаем.
  if (-not (Test-Path -LiteralPath $Source)) { throw "Source missing: $Source" }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $files = @(Get-ChildItem -LiteralPath $Source -File -Filter $Filter)
  foreach ($file in $files) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Destination $file.Name) -Force
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

function Invoke-ApplyOpenCode {
  $ocRoot = Get-OpenCodeRoot
  Write-Status 'INFO' "OpenCode root: $ocRoot"

  $skillsSrc = Join-Path $KitRoot 'profile\skills'
  $rulesSrc = Join-Path $KitRoot 'profile\rules\on-demand'
  $agentsSrc = Join-Path $KitRoot 'profile\agents'
  $commandsSrc = Join-Path $KitRoot 'profile\commands'
  $scriptsSrc = Join-Path $KitRoot 'profile\scripts'
  $agentsDst = Join-Path $ocRoot 'agents'
  $commandsDst = Join-Path $ocRoot 'commands'
  $scriptsDst = Join-Path $ocRoot 'scripts'

  $skillCount = @(Get-ChildItem $skillsSrc -Directory -EA SilentlyContinue).Count
  $ruleCount = @(Get-ChildItem $rulesSrc -Directory -EA SilentlyContinue).Count
  $agentCount = @(Get-ChildItem $agentsSrc -File -Filter '*.md' -EA SilentlyContinue).Count
  $commandCount = @(Get-ChildItem $commandsSrc -File -Filter '*.md' -EA SilentlyContinue).Count
  $scriptCount = @(Get-ChildItem $scriptsSrc -File -EA SilentlyContinue).Count
  Write-Status 'INFO' "kit skills=$skillCount, on-demand rules=$ruleCount, agents=$agentCount"

  $paths = Get-KitSkillPaths $KitRoot
  $configPath = Get-OpenCodeConfigPath
  Write-Status 'INFO' ("config skills: " + ($paths.Skills -join ', '))
  Write-Status 'INFO' ("config instructions: " + ($paths.Instructions -join ', '))

  if ($DryRun) {
    Write-Status 'INFO' "would write $configPath (skills + instructions only; other keys kept)"
    Write-Status 'INFO' "would copy agents=$agentCount, commands=$commandCount, scripts=$scriptCount -> $ocRoot"
    Write-Status 'INFO' "would remove legacy $(Join-Path $ocRoot 'skills\kit') if present"
    Write-Status 'INFO' "would strip managed block from $(Join-Path $ocRoot 'AGENTS.md')"
    Write-Status 'WARN' 'DryRun - no files written'
    return 0
  }

  # 1. Скиллы и правила OpenCode читает по путям из конфига, а агентов, команды и
  #    скрипт каркаса — только копией: ссылку на файл по пути он не понимает.
  [void](Copy-ProfileFiles $agentsSrc $agentsDst '*.md')
  [void](Copy-ProfileFiles $commandsSrc $commandsDst '*.md')
  [void](Copy-ProfileFiles $scriptsSrc $scriptsDst '*')
  Write-Status 'OK' "agents -> $agentsDst ($agentCount), commands -> $commandsDst ($commandCount), scripts -> $scriptsDst ($scriptCount)"

  # 2. Старая модель копировала профиль в skills\kit — сносим только этот каталог.
  if (Remove-LegacyKitSkills) { Write-Status 'OK' "removed legacy $(Join-Path $ocRoot 'skills\kit')" }
  else { Write-Status 'INFO' 'no legacy skills\kit' }

  # 3. Машинная задача lease-clean: скрипт теперь лежит в репозитории кита.
  Install-LeaseCleanTask -SkillsDst $skillsSrc

  # 4. Always-on правила теперь приходят через instructions — блок в AGENTS.md дубль.
  $agentsState = Clear-OpenCodeGlobalAgentsBlock
  switch ($agentsState) {
    'removed' { Write-Status 'OK' "removed $(Join-Path $ocRoot 'AGENTS.md') (it was the kit block only)" }
    'cleaned' { Write-Status 'OK' "stripped managed block from $(Join-Path $ocRoot 'AGENTS.md')" }
    default { Write-Status 'INFO' 'global AGENTS.md: no kit block' }
  }

  $configPath = Write-OpenCodeGlobalConfig $KitRoot
  Write-Status 'OK' "global config -> $configPath (skills, instructions)"

  $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $configPath) -File -EA SilentlyContinue |
    Where-Object { $_.Name -like ((Split-Path -Leaf $configPath) + '.bak-*') } |
    Sort-Object LastWriteTime -Descending)
  if ($backups.Count -gt 0) { Write-Status 'INFO' "backup: $($backups[0].FullName)" }

  $skillsMissing = @(Get-ChildItem $skillsSrc -Directory | Where-Object { -not (Test-Path (Join-Path $_.FullName 'SKILL.md')) })
  foreach ($s in $skillsMissing) { Write-Status 'WARN' "skill without SKILL.md (skipped by OpenCode): $($s.Name)" }
  $rulesMissing = @(Get-ChildItem $rulesSrc -Directory | Where-Object { -not (Test-Path (Join-Path $_.FullName 'SKILL.md')) })
  foreach ($s in $rulesMissing) { Write-Status 'WARN' "rule without SKILL.md (skipped by OpenCode): $($s.Name)" }

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
    }
  }
  Write-Status 'INFO' 'перезапусти OpenCode: конфиг читается при старте'
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
      $skillPaths = @($cfgData.skills)
      if ($skillPaths.Count -eq 0) {
        Write-Status 'WARN' "global $((Split-Path -Leaf $configPath)) has no skills paths - run: kit.ps1 apply"
        $warn++
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
  $skills = @(Get-ChildItem (Join-Path $KitRoot 'profile\skills') -Directory -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
  $always = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\always') -File -Filter '*.md' -EA SilentlyContinue).Count
  $ondemand = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules\on-demand') -Directory -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
  $rules = $always + $ondemand
  $agents = @(Get-ChildItem (Join-Path $KitRoot 'profile\agents') -File -Filter '*.md' -EA SilentlyContinue).Count
  Write-Status 'OK' "profile skills=$skills rules=$rules (always=$always, on-demand=$ondemand) agents=$agents"

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
  # пути скиллов/правил в конфиге, отсутствие старой копии и байт-в-байт копии
  # агентов, команд и скрипта каркаса.
  $fail = 0
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
      $configured = @($cfgData.skills | ForEach-Object { [string]$_ })
      foreach ($expected in @($skillsSrc, $rulesSrc)) {
        $norm = ($expected -replace '\\', '/').TrimEnd('/')
        $hit = @($configured | Where-Object { ($_ -replace '\\', '/').TrimEnd('/') -eq $norm })
        if ($hit.Count -gt 0) { Write-Status 'OK' "config skills -> $expected" }
        else { Write-Status 'FAIL' "global config skills has no $expected - run: kit.ps1 apply"; $fail++ }
      }
      $broken = @($configured | Where-Object { -not (Test-Path -LiteralPath $_) })
      if ($broken.Count -gt 0) {
        Write-Status 'FAIL' ("config skills paths missing: " + ($broken -join ', ') + ' - run: kit.ps1 apply'); $fail++
      }
      $instr = @($cfgData.instructions | ForEach-Object { [string]$_ })
      if ($instr.Count -eq 0) {
        Write-Status 'FAIL' 'global config has no instructions - run: kit.ps1 apply'; $fail++
      } else {
        Write-Status 'OK' ("config instructions: " + ($instr -join ', '))
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
  foreach ($pair in $copies) {
    $layer = $pair[0]
    $src = Join-Path $KitRoot $pair[1]
    $dst = Join-Path $ocRoot $layer
    $srcFiles = @(Get-ChildItem -LiteralPath $src -File -Filter $pair[2] -EA SilentlyContinue)
    $problems = @()
    foreach ($file in $srcFiles) {
      $target = Join-Path $dst $file.Name
      if (-not (Test-Path -LiteralPath $target)) { $problems += "нет $($file.Name)"; continue }
      if ((Get-TextSha256 $file.FullName) -ne (Get-TextSha256 $target)) { $problems += "разошёлся $($file.Name)" }
    }
    if ($srcFiles.Count -eq 0) { $problems += 'в профиле нет файлов' }
    if ($problems.Count -gt 0) {
      Write-Status 'FAIL' ("{0}: {1} - run: kit.ps1 apply" -f $dst, ($problems -join ', ')); $fail++
    } else {
      Write-Status 'OK' ("{0}: {1} files match profile" -f $dst, $srcFiles.Count)
    }
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
  'deps' {
    exit (Invoke-Deps -KitRoot $KitRoot -What $What -Update:$Update -All:$All -Offline:$Offline `
        -DryRun:$DryRun -Platform $Platform)
  }
  default {
    $kitVersion = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
    Write-Host "1c-ninja-kit CLI $kitVersion"
    Write-Host '  kit.ps1 doctor [-Strict]'
    Write-Host '  kit.ps1 verify'
    Write-Host '  kit.ps1 lock [-DryRun]      # пересобрать lock/profile.lock.json из profile\'
    Write-Host '  kit.ps1 apply [-DryRun]     # пути скиллов/правил в opencode.jsonc + копия агентов/команд/скрипта'
    Write-Host '  kit.ps1 deps [-What all|required|oscript|bsl-analyzer|ripgrep|web-test|apache|toolkit]'
    Write-Host '                [-Update] [-All] [-Offline] [-Platform 8.3|8.5] [-DryRun]'
    Write-Host 'Project bootstrap: skill-env-setup ("разверни окружение")'
    Write-Host "KitRoot: $KitRoot"
    exit 0
  }
}

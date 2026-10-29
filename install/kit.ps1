#Requires -Version 5.1
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'verify', 'apply', 'help')]
  [string]$Command = 'help',

  [switch]$DryRun,
  [switch]$Strict,

  [string]$ProfileName = '1c-ninja-kit'
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

function Test-SoftPath([string]$Label, [string]$PathPattern, [bool]$Required) {
  $path = Expand-EnvPath $PathPattern
  if (Test-Path -LiteralPath $path) {
    Write-Status 'OK' "$Label -> $path"
    return $true
  }
  if ($Required) {
    Write-Status 'FAIL' "$Label missing: $path"
  } else {
    Write-Status 'WARN' "$Label missing: $path"
  }
  return $false
}

function Invoke-Robo([string]$Src, [string]$Dst, [switch]$ListOnly, [switch]$Mirror) {
  if (-not (Test-Path -LiteralPath $Src)) { throw "Source missing: $Src" }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  $roboArgs = @(
    $Src, $Dst, $(if ($Mirror) { '/MIR' } else { '/E' }), '/NFL', '/NDL', '/NJH', '/NJS', '/nc', '/ns', '/np',
    '/XD', '.git', '.build', 'node_modules', '__pycache__',
    '/XF', '.browser-session.json', '*.bak', '*.log'
  )
  if ($ListOnly) { $roboArgs += '/L' }
  & robocopy @roboArgs | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed $Src -> $Dst code=$LASTEXITCODE" }
  return $LASTEXITCODE
}

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

function Get-OpenCodeRoots {
  return @{
    Skills      = '%USERPROFILE%\.config\opencode\skills'
    Agents      = '%USERPROFILE%\.config\opencode\agents'
    Commands    = '.opencode\commands'
    ProjectMcp  = 'opencode.jsonc'
    UserMcp     = '<не заводи 1С MCP в user-конфиг — держи только в проекте>'
  }
}

function Convert-RulePlaceholders([string]$Text) {
  if ([string]::IsNullOrEmpty($Text)) { return $Text }
  $r = Get-OpenCodeRoots
  $map = [ordered]@{
    '{{SKILLS_ROOT}}'  = $r.Skills
    '{{AGENTS_ROOT}}'  = $r.Agents
    '{{COMMANDS_ROOT}}' = $r.Commands
    '{{PROJECT_MCP}}'  = $r.ProjectMcp
    '{{USER_MCP}}'     = $r.UserMcp
  }
  foreach ($k in $map.Keys) { $Text = $Text.Replace($k, $map[$k]) }
  return $Text
}
# SKILL.md / reference.md are robocopied verbatim, so resolve their placeholders
# after the sync - otherwise users would read a literal {{SKILLS_ROOT}}.
function Resolve-SkillPlaceholders([string]$SkillsRoot) {
  if (-not (Test-Path -LiteralPath $SkillsRoot)) { return 0 }
  $n = 0
  Get-ChildItem $SkillsRoot -Recurse -File -Filter '*.md' -EA SilentlyContinue | ForEach-Object {
    $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    if ($null -eq $t) { return }
    $t2 = Convert-RulePlaceholders $t
    if ($t2 -ne $t) {
      [System.IO.File]::WriteAllText($_.FullName, $t2, (New-Object System.Text.UTF8Encoding($false)))
      $n++
    }
  }
  return $n
}

function New-OpenCodeGlobalAgentsBlock([string]$KitRoot) {
  $alwaysRoot = Join-Path $KitRoot 'profile\rules\always'
  $always = @(Get-ChildItem $alwaysRoot -File -Filter '*.md' -EA SilentlyContinue | Sort-Object Name)

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# 1c-ninja-kit — глобальные инструкции OpenCode')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("<!-- managed by kit.ps1 apply; SoT = $KitRoot\profile\rules -->")
  [void]$sb.AppendLine('Правь SoT (`profile/rules/always/*.md`) и запускай apply заново — этот блок перезаписывается.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Stack defaults')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('- Платформа **8.3** → Apache **8083**, tools `%USERPROFILE%\tools\apache-83`; **8.5** → **8085**.')
  [void]$sb.AppendLine('- Web-URL включают `/ru_RU/`.')
  [void]$sb.AppendLine('- 1С MCP — **только** в project `opencode.jsonc`. Глобальный `~/.config/opencode/opencode.json(c)` без 1С-серверов и секретов.')
  [void]$sb.AppendLine('- Ninja-пара: kit `components/1c-ninja-mcp` + project `src/cfe/NinjaLive` (`/hs/ninja-live`).')
  [void]$sb.AppendLine('- Список расширений в ИБ: MCP `live_extensions_list` (не Предприятие).')
  [void]$sb.AppendLine('- Запрещено: Platform Tools MCP / реестр PT; ручные вызовы Конфигуратора в обход скиллов контура; правка XML метаданных вручную.')
  [void]$sb.AppendLine('- Отвечать пользователю на **русском**; при неоднозначности — `CONFUSION` (варианты A/B → вопрос), не молчаливый выбор.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Triage')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Путь | Когда |')
  [void]$sb.AppendLine('|------|-------|')
  [void]$sb.AppendLine('| Quick-fix | Один файл/метод; ≲20 строк BSL; без транзакций, публичного API, adopted CFE, RLS |')
  [void]$sb.AppendLine('| Docs-fix | Только Markdown / rules / docs |')
  [void]$sb.AppendLine('| Full-cycle | Всё остальное; крупное → OpenSpec (`rule-sdd-integrations`) до кода |')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## MCP routes')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Нужно | Инструмент |')
  [void]$sb.AppendLine('|--------|------------|')
  [void]$sb.AppendLine('| Семантика / graph / diagnostics | `bsl-analyzer-workspace` |')
  [void]$sb.AppendLine('| Live ИБ / static выгрузка | `1c-ninja-mcp` `live_*` |')
  [void]$sb.AppendLine('| Список расширений ИБ | `1c-ninja-mcp` `live_extensions_list` |')
  [void]$sb.AppendLine('| Load / dump / update / проверки / repo | скиллы `db-*`, `skill-repo-workflow`, `skill-syntax-check` |')
  [void]$sb.AppendLine('| Стандарты ITS/v8 | `v8std`; reference `bsl-analyzer-reference` |')
  [void]$sb.AppendLine('| Live fallback | `1c-mcp-toolkit` (выключен по умолчанию) |')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('В OpenCode имена MCP-инструментов нормализованы: `1c-ninja-mcp` + `live_query` → `mcp_1c_ninja_mcp_live_query`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Skills')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Kit skills: `~/.config/opencode/skills/kit/skills/<id>/SKILL.md`.')
  [void]$sb.AppendLine('Kit rules on-demand: `~/.config/opencode/skills/kit/rules/<id>/SKILL.md`.')
  [void]$sb.AppendLine('External skills (`cc-1c-skills`): `~/.config/opencode/skills/<id>/SKILL.md` — не переименовываются.')
  [void]$sb.AppendLine('Вызывай tool `skill` по точному id.')
  [void]$sb.AppendLine('Частые: `skill-env-setup`, `skill-project-context`, `skill-ninja-mcp`, `skill-bsl-analyzer`, `skill-repo-workflow`, `skill-web-test`, `skill-handoff`, `rule-anti-patterns`, `rule-forms`, `rule-sdd-integrations`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Subagents')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Агенты kit: `~/.config/opencode/agents/agent-*.md` (`mode: subagent`), запуск — tool `subagent`.')
  [void]$sb.AppendLine('`agent-explorer`, `agent-analyst`, `agent-planner`, `agent-architect`, `agent-arch-reviewer`, `agent-developer`, `agent-refactoring`, `agent-performance-optimizer`, `agent-error-fixer`, `agent-code-reviewer`, `agent-doc-writer`, `agent-tester`.')
  [void]$sb.AppendLine('Не зови субагента на замену строки. `agent-code-reviewer` — только по явной просьбе. Metadata/forms/CFE — через `meta-*` / `form-*` / `cfe-*`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Kit CLI')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('```text')
  [void]$sb.AppendLine('kit.ps1 doctor')
  [void]$sb.AppendLine('kit.ps1 verify')
  [void]$sb.AppendLine('kit.ps1 apply')
  [void]$sb.AppendLine('```')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Новый проект: `skill-env-setup` («разверни окружение») — он создаёт структуру, конфиги и `AGENTS.md`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Always-on rules (из `profile/rules/always`)')
  [void]$sb.AppendLine('')
  foreach ($r in $always) {
    [void]$sb.AppendLine("### $($r.BaseName)")
    [void]$sb.AppendLine('')
    $body = Convert-RulePlaceholders (Get-Content -LiteralPath $r.FullName -Raw -Encoding UTF8)
    [void]$sb.AppendLine(($body -replace '\A(\r?\n)+', '').TrimEnd())
    [void]$sb.AppendLine('')
  }
  return $sb.ToString()
}
function Write-OpenCodeGlobalAgents([string]$KitRoot) {
  $ocRoot = Get-OpenCodeRoot
  $path = Join-Path $ocRoot 'AGENTS.md'
  $begin = '<!-- 1c-ninja-kit:begin -->'
  $end = '<!-- 1c-ninja-kit:end -->'
  $block = $begin + "`n" + (New-OpenCodeGlobalAgentsBlock $KitRoot) + "`n" + $end + "`n"

  $existing = ''
  if (Test-Path -LiteralPath $path) { $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 }
  if ($existing -and $existing.Contains($begin) -and $existing.Contains($end)) {
    $pre = ($existing.Substring(0, $existing.IndexOf($begin)) -replace '\s+$', '')
    $post = ($existing.Substring($existing.IndexOf($end) + $end.Length) -replace '^\s+', '')
    $head = if ($pre) { $pre + "`n`n" } else { '' }
    $tail = if ($post) { "`n" + $post } else { "`n" }
    $content = $head + ($block -replace '\s+$', '') + $tail
  }
  elseif ($existing) {
    $content = ($existing -replace '\s+$', '') + "`n`n" + $block
  }
  else {
    $content = $block
  }
  Set-FileContentUtf8 $path $content
  return $path
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
  $skillsRoot = Join-Path $ocRoot 'skills'
  $kitSkillsRoot = Join-Path $skillsRoot 'kit'
  $kitSkillsDst = Join-Path $kitSkillsRoot 'skills'
  $kitRulesDst = Join-Path $kitSkillsRoot 'rules'
  $agentsDst = Join-Path $ocRoot 'agents'

  $skillCount = @(Get-ChildItem $skillsSrc -Directory -EA SilentlyContinue).Count
  $ruleCount = @(Get-ChildItem $rulesSrc -Directory -EA SilentlyContinue).Count
  $agentCount = @(Get-ChildItem $agentsSrc -File -Filter '*.md' -EA SilentlyContinue).Count
  Write-Status 'INFO' "kit skills=$skillCount, on-demand rules=$ruleCount, agents=$agentCount"

  if ($DryRun) {
    Write-Status 'INFO' "would mirror $skillsSrc -> $kitSkillsDst"
    Write-Status 'INFO' "would mirror $rulesSrc -> $kitRulesDst"
    Write-Status 'INFO' "would copy $agentsSrc -> $agentsDst (agent-*.md)"
    Write-Status 'WARN' 'DryRun - no files written'
    return 0
  }

  $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('1c-ninja-kit-stage-' + [guid]::NewGuid().ToString('N'))
  $stageSkills = Join-Path $stage 'skills'
  $stageRules = Join-Path $stage 'rules'
  try {
    [void](Invoke-Robo $skillsSrc $stageSkills)
    [void](Invoke-Robo $rulesSrc $stageRules)

    [void](Invoke-Robo $stageSkills $kitSkillsDst -Mirror)
    [void](Invoke-Robo $stageRules $kitRulesDst -Mirror)
    $skN = Resolve-SkillPlaceholders $kitSkillsRoot
    if ($skN) { Write-Status 'INFO' "resolved placeholders in kit skills ($skN files)" }

    New-Item -ItemType Directory -Force -Path $agentsDst | Out-Null
    Get-ChildItem $agentsSrc -File -Filter '*.md' | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $agentsDst $_.Name) -Force
    }
    Write-Status 'INFO' "copied agents -> $agentsDst ($agentCount files, native mode: subagent)"

    $agentsPath = Write-OpenCodeGlobalAgents $KitRoot
    Write-Status 'OK' "global instructions -> $agentsPath"
    Install-LeaseCleanTask -SkillsDst $kitSkillsDst

    $skillsMissing = @(Get-ChildItem $skillsSrc -Directory | Where-Object { -not (Test-Path (Join-Path $_.FullName 'SKILL.md')) })
    foreach ($s in $skillsMissing) { Write-Status 'WARN' "skill without SKILL.md (skipped by OpenCode): $($s.Name)" }
  }
  finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue }
  }

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
  return 0
}
function Invoke-Doctor {
  $kitVersion = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
  Write-Host "=== kit doctor ($kitVersion) KitRoot=$KitRoot ===" -ForegroundColor Cyan
  $fail = 0
  $warn = 0

  foreach ($c in @(
      @{ L = 'OVM oscript'; P = '%LOCALAPPDATA%\ovm\current\bin\oscript.exe' },
      @{ L = 'bsl-analyzer'; P = '%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe' }
    )) {
    if (-not (Test-SoftPath $c.L $c.P $true)) { $fail++ }
  }

  foreach ($c in @(
      @{ L = 'Apache 8.3 tools'; P = '%USERPROFILE%\tools\apache-83' },
      @{ L = 'Apache 8.5 tools'; P = '%USERPROFILE%\tools\apache-85' },
      @{ L = 'Ripgrep (fast code search)'; P = '%USERPROFILE%\tools\ripgrep\rg.exe' },
      @{ L = 'Toolkit EPF (recommended)'; P = '%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf' },
      @{ L = 'Toolkit EPF (legacy)'; P = 'C:\1C\soft\MCP_Toolkit.epf' }
    )) {
    if (-not (Test-SoftPath $c.L $c.P $false)) { $warn++ }
  }
  Write-Status 'INFO' 'If toolkit missing: https://github.com/ROCTUP/1c-mcp-toolkit/releases'
  Write-Status 'INFO' 'If bsl-analyzer missing: https://github.com/itrous/bsl-analyzer/releases (bsl-analyzer-windows-amd64.exe)'
  Write-Status 'INFO' 'If ripgrep missing: https://github.com/BurntSushi/ripgrep/releases -> %USERPROFILE%\tools\ripgrep + PATH'

  $ninjaMain = Join-Path $KitRoot 'components\1c-ninja-mcp\main.os'
  if (Test-Path -LiteralPath $ninjaMain) { Write-Status 'OK' "1c-ninja-mcp -> $ninjaMain" }
  else { Write-Status 'FAIL' "1c-ninja-mcp missing: $ninjaMain"; $fail++ }

  $nl = Join-Path $KitRoot 'project-scaffold\cfe\NinjaLive'
  if (Test-Path -LiteralPath $nl) { Write-Status 'OK' "NinjaLive pair -> $nl" }
  else { Write-Status 'FAIL' "NinjaLive missing: $nl"; $fail++ }

  $v8exe = Get-ChildItem 'C:\Program Files\1cv8\*\bin\1cv8.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($v8exe) { Write-Status 'OK' "1cv8: $($v8exe.FullName)" }
  else { Write-Status 'FAIL' '1cv8 not found (C:\Program Files\1cv8\*\bin)'; $fail++ }

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
  if (Test-Path (Join-Path $ocRoot 'skills')) {
    $n = @(Get-ChildItem (Join-Path $ocRoot 'skills') -Recurse -File -Filter 'SKILL.md' -EA SilentlyContinue).Count
    Write-Status 'INFO' "opencode profile installed: skills=$n (apply to refresh)"
  } else {
    Write-Status 'INFO' 'opencode profile absent (ok) - run: kit.ps1 apply'
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
  if (-not (Test-Path (Join-Path $KitRoot 'lock\profile.lock.json'))) {
    Write-Status 'FAIL' 'lock/profile.lock.json missing'; return 1
  }
  Write-Status 'OK' 'lock present'
  if (-not (Test-Path (Join-Path $KitRoot 'profile\profiles\1c-ninja-kit.yaml'))) {
    Write-Status 'FAIL' 'profile aggregate missing'; return 1
  }
  Write-Status 'OK' 'aggregate profile 1c-ninja-kit.yaml'
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
  'apply' { exit (Invoke-Apply) }
  default {
    $kitVersion = (Get-Content (Join-Path $KitRoot 'VERSION') -Raw).Trim()
    Write-Host "1c-ninja-kit CLI $kitVersion"
    Write-Host '  kit.ps1 doctor [-Strict]'
    Write-Host '  kit.ps1 verify'
    Write-Host '  kit.ps1 apply [-DryRun]'
    Write-Host 'Project bootstrap: skill-env-setup ("разверни окружение")'
    Write-Host "KitRoot: $KitRoot"
    exit 0
  }
}

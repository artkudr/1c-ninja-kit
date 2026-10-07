#Requires -Version 5.1
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'verify', 'apply', 'init-project', 'help')]
  [string]$Command = 'help',

  [switch]$DryRun,
  [switch]$Strict,

  [string]$ProfileName = '1c-ninja-kit',

  [ValidateSet('opencode')]
  [string]$Adapter = 'opencode',

  [string]$ProjectPath,
  [string]$AppName = 'ninja-kit-e2e',
  [string]$V8Version = '8.3',
  [int]$WebPort = 0,
  [string]$IbConnection = '',
  [string]$DbUser = '',
  [string]$DbPwd = '',
  [switch]$SkipNinjaLive
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

function Invoke-Robo([string]$Src, [string]$Dst, [switch]$ListOnly) {
  if (-not (Test-Path -LiteralPath $Src)) { throw "Source missing: $Src" }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  $roboArgs = @(
    $Src, $Dst, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/nc', '/ns', '/np',
    '/XD', '.git', '.build', 'node_modules', '__pycache__',
    '/XF', '.browser-session.json', '*.bak', '*.log'
  )
  if ($ListOnly) { $roboArgs += '/L' }
  & robocopy @roboArgs | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed $Src -> $Dst code=$LASTEXITCODE" }
  return $LASTEXITCODE
}

function Get-DefaultWebPort([string]$v8) {
  if ($v8 -like '8.5*') { return 8085 }
  return 8083
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
# Rules (profile\rules\*.mdc) and SKILL.md stay layout-neutral: they carry
# {{SKILLS_ROOT}}, {{RULES_ROOT}}, {{AGENTS_ROOT}}, {{COMMANDS_ROOT}},
# {{PROJECT_MCP}}, {{USER_MCP}}. apply resolves them per target root, so no
# document ships another client's paths. Single adapter: opencode.

function Get-AdapterRoots([string]$Adapter) {
  switch ($Adapter) {
    'opencode' {
      return @{
        Skills      = '%USERPROFILE%\.config\opencode\skills'
        Rules       = '%USERPROFILE%\.config\opencode\kit-rules'
        Agents      = '%USERPROFILE%\.config\opencode\agents'
        Commands    = '.opencode\commands'
        ProjectMcp  = 'opencode.jsonc'
        UserMcp     = '<не заводи 1С MCP в user-конфиг — держи только в проекте>'
      }
    }
    default {
      return @{
        Skills      = '<skills root>'
        Rules       = '<rules root>'
        Agents      = '<agents root>'
        Commands    = '<commands root>'
        ProjectMcp  = '<project mcp config>'
        UserMcp     = '<user mcp config>'
      }
    }
  }
}

function Convert-RulePlaceholders([string]$Text, [string]$Adapter) {
  if ([string]::IsNullOrEmpty($Text)) { return $Text }
  $r = Get-AdapterRoots $Adapter
  $map = [ordered]@{
    '{{SKILLS_ROOT}}'  = $r.Skills
    '{{RULES_ROOT}}'   = $r.Rules
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
function Resolve-SkillPlaceholders([string]$SkillsRoot, [string]$Adapter) {
  if (-not (Test-Path -LiteralPath $SkillsRoot)) { return 0 }
  $n = 0
  Get-ChildItem $SkillsRoot -Recurse -File -Filter '*.md' -EA SilentlyContinue | ForEach-Object {
    $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    if ($null -eq $t) { return }
    $t2 = Convert-RulePlaceholders $t $Adapter
    if ($t2 -ne $t) {
      [System.IO.File]::WriteAllText($_.FullName, $t2, (New-Object System.Text.UTF8Encoding($false)))
      $n++
    }
  }
  return $n
}

# ---------- markdown helpers (OpenCode adapter) ----------

function Split-Frontmatter([string]$Path) {
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ($raw -match '(?s)\A\uFEFF?---\r?\n(.*?)\r?\n---\r?\n?(.*)\z') {
    return [pscustomobject]@{ Fm = $Matches[1]; Body = $Matches[2] }
  }
  return [pscustomobject]@{ Fm = ''; Body = $raw }
}

function Get-FrontmatterField([string]$Fm, [string]$Key) {
  $lines = $Fm -split "\r?\n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*:\s*(.*)$')) {
      $val = $Matches[1].Trim()
      if ($val -match '^[>|][-+]?$') {
        $acc = @()
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
          if ($lines[$j] -match '^\s+\S') { $acc += $lines[$j].Trim() }
          elseif ($lines[$j].Trim() -eq '') { continue }
          else { break }
        }
        return (($acc -join ' ').Trim())
      }
      return $val.Trim('"').Trim("'").Trim()
    }
  }
  return ''
}

function Remove-RepeatedHeadingBlocks([string]$Body, [int]$MinLines = 6) {
  # Kit profile agents carry the same injected "## ... (mandatory)" block many times
  # (a sync artefact from an earlier round-trip). Remove later copies of any block that starts with a heading and
  # repeats verbatim. Section-boundary heuristics do not work here: the injected block
  # swallows the paragraph that follows it, so copies are not byte-identical.
  $lines = [System.Collections.Generic.List[string]]::new([string[]]($Body -split "\r?\n"))
  $removed = 0
  $progress = $true
  while ($progress) {
    $progress = $false
    $byHeading = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^#') {
        $k = ($lines[$i] -replace '\s+', ' ')
        if (-not $byHeading.ContainsKey($k)) { $byHeading[$k] = (New-Object System.Collections.Generic.List[int]) }
        $byHeading[$k].Add($i)
      }
    }
    $candidates = @($byHeading.GetEnumerator() | Where-Object { $_.Value.Count -ge 2 } |
      ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($candidates.Count -eq 0) { break }

    $maxN = [Math]::Min(80, [int][Math]::Floor($lines.Count / 2))
    for ($n = $maxN; $n -ge $MinLines; $n--) {
      $groups = @{}
      foreach ($i in $candidates) {
        if ($i + $n -gt $lines.Count) { continue }
        $key = ((($lines[$i..($i + $n - 1)]) -join "`n") -replace '\s+', ' ')
        if (-not $groups.ContainsKey($key)) { $groups[$key] = (New-Object System.Collections.Generic.List[int]) }
        $groups[$key].Add($i)
      }
      $hit = $null
      foreach ($g in $groups.GetEnumerator()) { if ($g.Value.Count -ge 2) { $hit = $g; break } }
      if ($null -ne $hit) {
        $positions = @($hit.Value | Sort-Object)
        for ($k = $positions.Count - 1; $k -ge 1; $k--) { $lines.RemoveRange($positions[$k], $n) }
        $removed += ($positions.Count - 1)
        $progress = $true
        break
      }
    }
  }
  if ($removed -eq 0) { return $Body }
  $out = ($lines -join "`n") -replace '(\r?\n){3,}', "`n`n"
  return $out
}

function Convert-AgentToOpenCode([string]$Path) {
  $parts = Split-Frontmatter $Path
  $desc = Get-FrontmatterField $parts.Fm 'description'
  $body = Remove-RepeatedHeadingBlocks $parts.Body
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine('mode: subagent')
  # Quote the description: plain YAML scalars break on ": " and drop the rest of the
  # frontmatter, which silently drops `mode` and turns the agent into a primary agent.
  if ($desc) { [void]$sb.AppendLine('description: ' + (ConvertTo-Json -InputObject $desc -Compress)) }
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine('')
  [void]$sb.Append(($body -replace '\A(\r?\n)+', ''))
  return $sb.ToString()
}

function Get-RuleInfo([string]$Path) {
  $parts = Split-Frontmatter $Path
  return [pscustomobject]@{
    Name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    Always = [bool]($parts.Fm -match '(?m)^alwaysApply:\s*true')
    Description = (Get-FrontmatterField $parts.Fm 'description')
    Body = $parts.Body
  }
}

function New-OpenCodeGlobalAgentsBlock([string]$KitRoot) {
  $rules = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules') -File -Filter '*.mdc' |
    Sort-Object Name | ForEach-Object { Get-RuleInfo $_.FullName })
  $always = @($rules | Where-Object { $_.Always })
  $ondemand = @($rules | Where-Object { -not $_.Always })

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# 1c-ninja-kit — глобальные инструкции OpenCode')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("<!-- managed by kit.ps1 apply -Adapter opencode; SoT = $KitRoot\profile\rules -->")
  [void]$sb.AppendLine('Правь SoT (`profile/rules/*.mdc`) и запускай apply заново — этот блок перезаписывается.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Stack defaults')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('- Платформа **8.3** → Apache **8083**, tools `%USERPROFILE%\tools\apache-83`; **8.5** → **8085**.')
  [void]$sb.AppendLine('- Web-URL включают `/ru_RU/`.')
  [void]$sb.AppendLine('- 1С MCP — **только** в project `opencode.jsonc`. Глобальный `~/.config/opencode/opencode.json(c)` без 1С-серверов и секретов.')
  [void]$sb.AppendLine('- Ninja-пара: kit `components/1c-ninja-mcp` + project `src/cfe/NinjaLive` (`/hs/ninja-live`).')
  [void]$sb.AppendLine('- Список расширений в ИБ: MCP `live_extensions_list` (не Предприятие).')
  [void]$sb.AppendLine('- Запрещено: Designer / `1cv8` / сырой `ibcmd` / Platform Tools MCP в обход vrunner.')
  [void]$sb.AppendLine('- Отвечать пользователю на **русском**; при неоднозначности — `CONFUSION` (варианты A/B → вопрос), не молчаливый выбор.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Triage')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Путь | Когда |')
  [void]$sb.AppendLine('|------|-------|')
  [void]$sb.AppendLine('| Quick-fix | Один файл/метод; ≲20 строк BSL; без транзакций, публичного API, adopted CFE, RLS |')
  [void]$sb.AppendLine('| Docs-fix | Только Markdown / rules / docs |')
  [void]$sb.AppendLine('| Full-cycle | Всё остальное; крупное → OpenSpec (`sdd-integrations`) до кода |')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## MCP routes')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Нужно | Инструмент |')
  [void]$sb.AppendLine('|--------|------------|')
  [void]$sb.AppendLine('| Семантика / graph / diagnostics | `bsl-analyzer-workspace` |')
  [void]$sb.AppendLine('| Live ИБ / static выгрузка | `1c-ninja-mcp` `live_*` |')
  [void]$sb.AppendLine('| Список расширений ИБ | `1c-ninja-mcp` `live_extensions_list` |')
  [void]$sb.AppendLine('| Load / syntax-check / repo | `vrunner` (`cf_load`, `cfe_load`, `validate_syntax_check`) |')
  [void]$sb.AppendLine('| Стандарты ITS/v8 | `v8std`; reference `bsl-analyzer-reference` |')
  [void]$sb.AppendLine('| Live fallback | `1c-mcp-toolkit` (выключен по умолчанию) |')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('В OpenCode имена MCP-инструментов нормализованы: `1c-ninja-mcp` + `live_query` → `mcp_1c_ninja_mcp_live_query`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Skills')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Скиллы kit лежат в `~/.config/opencode/skills/<id>/SKILL.md`; вызывай tool `skill` по точному id.')
  [void]$sb.AppendLine('Частые: `1c-env-setup`, `1c-project-context`, `repo-workflow`, `1c-orchestrator`-роли, `meta-*`, `form-*`, `skd-*`, `cfe-*`, `epf-*`, `1c-ninja-mcp`, `1c-bsl-analyzer`, `vrunner-mcp`, `web-test`, `handoff`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Subagents')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Агенты kit: `~/.config/opencode/agents/<id>.md` (`mode: subagent`), запуск — tool `subagent`.')
  [void]$sb.AppendLine('`1c-explorer`, `1c-analytic`, `1c-planner`, `1c-architect`, `1c-arch-reviewer`, `1c-developer`, `1c-refactoring`, `1c-performance-optimizer`, `1c-error-fixer`, `1c-code-reviewer`, `1c-doc-writer`, `1c-tester`, `1c-metadata-manager`.')
  [void]$sb.AppendLine('Не зови субагента на замену строки. `1c-code-reviewer` — только по явной просьбе. `1c-metadata-manager` — заглушка: используй `meta-*` / `form-*` / `cfe-*`.')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Kit CLI')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('```text')
  [void]$sb.AppendLine('kit.ps1 doctor')
  [void]$sb.AppendLine('kit.ps1 verify')
  [void]$sb.AppendLine('kit.ps1 apply -Adapter <opencode>')
  [void]$sb.AppendLine('kit.ps1 init-project -ProjectPath <dir> -Adapter <...>')
  [void]$sb.AppendLine('```')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('## Always-on rules (инлайн из `profile/rules`)')
  [void]$sb.AppendLine('')
  foreach ($r in $always) {
    [void]$sb.AppendLine("### $($r.Name)")
    [void]$sb.AppendLine('')
    $rDesc = Convert-RulePlaceholders $r.Description 'opencode'
    if ($rDesc) { [void]$sb.AppendLine("*$rDesc*"); [void]$sb.AppendLine('') }
    $rBody = Convert-RulePlaceholders $r.Body 'opencode'
    [void]$sb.AppendLine(($rBody -replace '\A(\r?\n)+', '').TrimEnd())
    [void]$sb.AppendLine('')
  }
  [void]$sb.AppendLine('## On-demand rules — `~/.config/opencode/kit-rules/<name>.md`')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Читай файл целиком, когда задача попадает в его тему. Не тащи в контекст заранее.')
  [void]$sb.AppendLine('')
  foreach ($r in $ondemand) {
    $rd = Convert-RulePlaceholders $r.Description 'opencode'
    $d = if ($rd) { $rd } else { '(без описания)' }
    [void]$sb.AppendLine("- ``$($r.Name)`` — $d")
  }
  [void]$sb.AppendLine('')
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

function Invoke-ApplyOpenCode {
  $ocRoot = Get-OpenCodeRoot
  Write-Status 'INFO' "OpenCode root: $ocRoot"

  $skillsDst = Join-Path $ocRoot 'skills'
  Write-Status 'INFO' "sync profile\skills -> $skillsDst"
  if ($DryRun) { [void](Invoke-Robo (Join-Path $KitRoot 'profile\skills') $skillsDst -ListOnly) }
  else { [void](Invoke-Robo (Join-Path $KitRoot 'profile\skills') $skillsDst) }
  if (-not $DryRun) {
    $skN = Resolve-SkillPlaceholders $skillsDst 'opencode'
    if ($skN) { Write-Status 'INFO' "resolve skill placeholders -> opencode ($skN files)" }
  }

  $agentsDst = Join-Path $ocRoot 'agents'
  New-Item -ItemType Directory -Force -Path $agentsDst | Out-Null
  $agents = @(Get-ChildItem (Join-Path $KitRoot 'profile\agents') -File -Filter '*.md' -EA SilentlyContinue)
  if (-not $DryRun) {
    foreach ($f in $agents) {
      Set-FileContentUtf8 (Join-Path $agentsDst $f.Name) (Convert-AgentToOpenCode $f.FullName)
    }
  }
  Write-Status 'INFO' "convert profile\agents -> $agentsDst ($($agents.Count) files, mode: subagent)"

  $rulesDst = Join-Path $ocRoot 'kit-rules'
  New-Item -ItemType Directory -Force -Path $rulesDst | Out-Null
  $rules = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules') -File -Filter '*.mdc' -EA SilentlyContinue)
  if (-not $DryRun) {
    foreach ($f in $rules) {
      $parts = Split-Frontmatter $f.FullName
      $body = Convert-RulePlaceholders $parts.Body 'opencode'
      Set-FileContentUtf8 (Join-Path $rulesDst ($f.BaseName + '.md')) $body
    }
    $agentsPath = Write-OpenCodeGlobalAgents $KitRoot
    Write-Status 'OK' "global instructions -> $agentsPath"
  }
  Write-Status 'INFO' "copy profile\rules -> $rulesDst ($($rules.Count) files, on-demand)"

  $skillsMissing = @()
  if (-not $DryRun) {
    $skillsMissing = @(Get-ChildItem (Join-Path $KitRoot 'profile\skills') -Directory |
      Where-Object { -not (Test-Path (Join-Path $_.FullName 'SKILL.md')) })
    foreach ($s in $skillsMissing) { Write-Status 'WARN' "skill without SKILL.md (skipped by OpenCode): $($s.Name)" }
  }

  foreach ($name in @('opencode.json', 'opencode.jsonc')) {
    $cfg = Join-Path $ocRoot $name
    if (Test-Path -LiteralPath $cfg) {
      $raw = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
      $bad = @('1c-ninja-mcp', '1c-mcp-toolkit', 'vrunner', 'bsl-analyzer')
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
  Write-Host "=== kit doctor (v0.3) KitRoot=$KitRoot ===" -ForegroundColor Cyan
  $fail = 0
  $warn = 0

  foreach ($c in @(
      @{ L = 'OVM oscript'; P = '%LOCALAPPDATA%\ovm\current\bin\oscript.exe' },
      @{ L = 'vrunner'; P = '%LOCALAPPDATA%\ovm\current\bin\vrunner.bat' },
      @{ L = 'vrunner-mcp'; P = '%LOCALAPPDATA%\ovm\current\bin\vrunner-mcp.bat' },
      @{ L = 'bsl-analyzer'; P = '%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe' }
    )) {
    if (-not (Test-SoftPath $c.L $c.P $true)) { $fail++ }
  }

  foreach ($c in @(
      @{ L = 'Apache 8.3 tools'; P = '%USERPROFILE%\tools\apache-83' },
      @{ L = 'Apache 8.5 tools'; P = '%USERPROFILE%\tools\apache-85' },
      @{ L = 'Toolkit EPF (recommended)'; P = '%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf' },
      @{ L = 'Toolkit EPF (legacy)'; P = 'C:\1C\soft\MCP_Toolkit.epf' }
    )) {
    if (-not (Test-SoftPath $c.L $c.P $false)) { $warn++ }
  }
  Write-Status 'INFO' 'If toolkit missing: https://github.com/ROCTUP/1c-mcp-toolkit/releases'
  Write-Status 'INFO' 'If bsl-analyzer missing: https://github.com/itrous/bsl-analyzer/releases (bsl-analyzer-windows-amd64.exe)'

  $ninjaMain = Join-Path $KitRoot 'components\1c-ninja-mcp\main.os'
  if (Test-Path -LiteralPath $ninjaMain) { Write-Status 'OK' "1c-ninja-mcp -> $ninjaMain" }
  else { Write-Status 'FAIL' "1c-ninja-mcp missing: $ninjaMain"; $fail++ }

  $nl = Join-Path $KitRoot 'project-scaffold\cfe\NinjaLive'
  if (Test-Path -LiteralPath $nl) { Write-Status 'OK' "NinjaLive pair -> $nl" }
  else { Write-Status 'FAIL' "NinjaLive missing: $nl"; $fail++ }

  try {
    $vr = (& vrunner --version 2>&1 | Out-String).Trim()
    if ($vr -match '^3\.') { Write-Status 'OK' "vrunner --version: $vr" }
    else { Write-Status 'WARN' "vrunner version unexpected: $vr"; $warn++ }
  } catch {
    Write-Status 'FAIL' 'vrunner --version failed'
    $fail++
  }

  $ocRoot = Get-OpenCodeRoot
  foreach ($name in @('opencode.json', 'opencode.jsonc')) {
    $cfg = Join-Path $ocRoot $name
    if (-not (Test-Path -LiteralPath $cfg)) { continue }
    $raw = Get-Content -LiteralPath $cfg -Raw -ErrorAction SilentlyContinue
    $bad = @('1c-ninja-mcp', '1c-mcp-toolkit', 'vrunner', 'bsl-analyzer')
    $hits = @($bad | Where-Object { $raw -match [regex]::Escape($_) })
    if ($hits.Count -gt 0) {
      Write-Status 'WARN' ("global opencode $name contains 1C MCP servers: " + ($hits -join ', '))
      $warn++
    } else {
      Write-Status 'OK' "global opencode $name has no 1C MCP server names"
    }
  }
  if (Test-Path (Join-Path $ocRoot 'skills')) {
    $n = @(Get-ChildItem (Join-Path $ocRoot 'skills') -Directory -EA SilentlyContinue).Count
    Write-Status 'INFO' "opencode profile installed: skills=$n (apply -Adapter opencode to refresh)"
  } else {
    Write-Status 'INFO' 'opencode profile absent (ok) - run: kit.ps1 apply -Adapter opencode'
  }

  Write-Host ("Summary: fail={0} warn={1}" -f $fail, $warn) -ForegroundColor Cyan
  if ($fail -gt 0) { Write-Status 'FAIL' 'doctor blocked'; return 1 }
  if ($Strict -and $warn -gt 0) { Write-Status 'FAIL' 'doctor strict failed'; return 1 }
  Write-Status 'OK' 'doctor ready'
  return 0
}

function Invoke-Verify {
  Write-Host '=== kit verify ===' -ForegroundColor Cyan
  $skills = @(Get-ChildItem (Join-Path $KitRoot 'profile\skills') -Directory -EA SilentlyContinue).Count
  $rules = @(Get-ChildItem (Join-Path $KitRoot 'profile\rules') -File -Filter '*.mdc' -EA SilentlyContinue).Count
  $agents = @(Get-ChildItem (Join-Path $KitRoot 'profile\agents') -File -Filter '*.md' -EA SilentlyContinue).Count
  Write-Status 'OK' "profile skills=$skills rules=$rules agents=$agents"
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
  Write-Host "=== kit apply --profile $ProfileName --adapter $Adapter ===" -ForegroundColor Cyan
  if ($ProfileName -ne '1c-ninja-kit') {
    Write-Status 'FAIL' "Unknown profile '$ProfileName'"; return 1
  }

  $skillsSrc = Join-Path $KitRoot 'profile\skills'
  $docsSrc = Join-Path $KitRoot 'profile\docs-patches'

  if ($Adapter -eq 'opencode') {
    return (Invoke-ApplyOpenCode)
  }

  if ($DryRun) { Write-Status 'WARN' 'DryRun - no files written' }
  else { Write-Status 'OK' "apply done (adapter=$Adapter)" }
  return 0
}


function Invoke-InitProject {
  Write-Host '=== kit init-project ===' -ForegroundColor Cyan
  if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Write-Status 'FAIL' 'Specify -ProjectPath (fresh folder). Do NOT use ecoladev.'
    return 1
  }
  $proj = [System.IO.Path]::GetFullPath($ProjectPath)
  $eco = [System.IO.Path]::GetFullPath('C:\1C\projects\ecoladev')
  if ($proj.TrimEnd('\') -ieq $eco.TrimEnd('\')) {
    Write-Status 'FAIL' 'Refusing to init-project on ecoladev'
    return 1
  }
  if ($proj -match '(?i)[\\/]ecoladev([\\/]|$)') {
    Write-Status 'FAIL' 'Refusing path under ecoladev'
    return 1
  }

  if ($WebPort -le 0) { $script:WebPort = Get-DefaultWebPort $V8Version }

  Write-Status 'INFO' "ProjectPath=$proj AppName=$AppName V8=$V8Version WebPort=$WebPort"
  if ($DryRun) {
    Write-Status 'WARN' 'DryRun - no files written'
    return 0
  }

  foreach ($d in @(
      'src\cf', 'src\cfe', 'src\epf', 'src\erf',
      'build\out\epf', 'build\out\erf', 'build\out\cfe',
      'tools\web-test\scenarios\after-load', 'tools\web-test\scenarios\manual',
      'docs', '.opencode\commands', 'openspec\specs', 'openspec\changes\archive', 'openspec\templates'
    )) {
    New-Item -ItemType Directory -Force -Path (Join-Path $proj $d) | Out-Null
  }

  if (-not $SkipNinjaLive) {
    $nlSrc = Join-Path $KitRoot 'project-scaffold\cfe\NinjaLive'
    $nlDst = Join-Path $proj 'src\cfe\NinjaLive'
    Write-Status 'INFO' "copy NinjaLive -> $nlDst"
    [void](Invoke-Robo $nlSrc $nlDst)
  }

  $tplRoot = Join-Path $KitRoot 'project-scaffold\templates'
  $vrunnerMcp = Expand-EnvPath '%LOCALAPPDATA%\ovm\current\bin\vrunner-mcp.bat'
  $bslExe = Expand-EnvPath '%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe'
  $autumnMain = Join-Path $KitRoot 'components\1c-ninja-mcp\main.os'
  $shcntx = Join-Path $KitRoot 'components\1c-ninja-mcp\src\data\shcntx_help.db'

  $ib = if ($IbConnection) { $IbConnection } else { '/S"SERVER/BASE_PLACEHOLDER"' }
  $user = if ($DbUser) { $DbUser } else { 'USER_PLACEHOLDER' }
  $pwd = if ($DbPwd) { $DbPwd } else { 'PWD_PLACEHOLDER' }

  $autumnTpl = Get-Content (Join-Path $tplRoot 'autumn-properties.json.tpl') -Raw -Encoding UTF8
  # Values go into a JSON template: escape them (/S"host/base" has quotes).
  $autumn = $autumnTpl.Replace('{{IBCONNECTION}}', (ConvertTo-JsonLiteral $ib)).
    Replace('{{DB_USER}}', (ConvertTo-JsonLiteral $user)).
    Replace('{{DB_PWD}}', (ConvertTo-JsonLiteral $pwd)).
    Replace('{{V8VERSION}}', (ConvertTo-JsonLiteral $V8Version)).
    Replace('{{APP_NAME}}', (ConvertTo-JsonLiteral $AppName)).Replace('{{WEB_PORT}}', "$WebPort")
  Set-FileContentUtf8 (Join-Path $proj 'autumn-properties.json') $autumn

  $repoTpl = Get-Content (Join-Path $tplRoot 'repository.json.tpl') -Raw -Encoding UTF8
  $repo = $repoTpl.Replace('{{REPO_ROOT}}', '\\\\SERVER\\repo-placeholder').
    Replace('{{REPO_USER}}', 'repo-user-placeholder').
    Replace('{{REPO_ADMIN}}', 'repo-admin-placeholder')
  Set-FileContentUtf8 (Join-Path $proj 'repository.json') $repo

  Copy-Item (Join-Path $tplRoot 'bsl-analyzer.toml.tpl') (Join-Path $proj 'bsl-analyzer.toml') -Force

  $giSnippet = Get-Content (Join-Path $tplRoot 'gitignore-1c.snippet') -Raw -Encoding UTF8
  $giExtra = "`n# kit secrets`nautumn-properties.json`n.env`n.dev.env`n"
  Set-FileContentUtf8 (Join-Path $proj '.gitignore') ($giSnippet + $giExtra)

  Copy-Item (Join-Path $tplRoot 'openspec\*') (Join-Path $proj 'openspec') -Recurse -Force
  Copy-Item (Join-Path $tplRoot 'dev-stack.md.tpl') (Join-Path $proj 'docs\dev-stack.md') -Force
  if (Test-Path (Join-Path $tplRoot 'smoke.config.json.tpl')) {
    Copy-Item (Join-Path $tplRoot 'smoke.config.json.tpl') (Join-Path $proj 'tools\web-test\smoke.config.json') -Force
  }

  # Adapter project context
  $agentsTpl = Get-Content (Join-Path $KitRoot 'adapters\shared\AGENTS.md.tpl') -Raw -Encoding UTF8
  Set-FileContentUtf8 (Join-Path $proj 'AGENTS.md') $agentsTpl
  $ocTpl = Get-Content (Join-Path $KitRoot 'adapters\opencode\opencode.jsonc.tpl') -Raw -Encoding UTF8
  $ocJson = $ocTpl.
      Replace('{{VRUNNER_MCP}}', (ConvertTo-JsonLiteral $vrunnerMcp)).
      Replace('{{NINJA_MAIN}}', (ConvertTo-JsonLiteral $autumnMain)).
      Replace('{{SHCNTX_HELP_DB}}', (ConvertTo-JsonLiteral $shcntx)).
      Replace('{{BSL_ANALYZER_EXE}}', (ConvertTo-JsonLiteral $bslExe)).
      Replace('{{PROJECT_ROOT}}', (ConvertTo-JsonLiteral $proj)).
      Replace('{{AUTUMN_PROPERTIES}}', (ConvertTo-JsonLiteral (Join-Path $proj 'autumn-properties.json'))).
      Replace('{{IB_USER}}', (ConvertTo-JsonLiteral $user)).
      Replace('{{IB_PASSWORD}}', (ConvertTo-JsonLiteral $pwd)).
      Replace('{{APP_NAME}}', (ConvertTo-JsonLiteral $AppName)).
      Replace('{{WEB_PORT}}', "$WebPort")
  Set-FileContentUtf8 (Join-Path $proj 'opencode.jsonc') $ocJson
  $ocEx = $ocJson
  if ($pwd -and $pwd -ne 'PWD_PLACEHOLDER') { $ocEx = $ocEx.Replace((ConvertTo-JsonLiteral $pwd), '<password>') }
  if ($user -and $user -ne 'USER_PLACEHOLDER') { $ocEx = $ocEx.Replace((ConvertTo-JsonLiteral $user), '<user>') }
  Set-FileContentUtf8 (Join-Path $proj 'opencode.jsonc.example') $ocEx
  Copy-Item (Join-Path $tplRoot 'commands\*') (Join-Path $proj '.opencode\commands') -Force
  Write-Status 'OK' 'wrote AGENTS.md + opencode.jsonc (+ .example) + .opencode/commands'

  $needsHuman = @()
  if (-not $IbConnection -or $IbConnection -match 'PLACEHOLDER') { $needsHuman += 'IbConnection' }
  if (-not $DbUser -or $DbUser -match 'PLACEHOLDER') { $needsHuman += 'DbUser' }
  if (-not $DbPwd -or $DbPwd -match 'PLACEHOLDER') { $needsHuman += 'DbPwd' }

  $report = [ordered]@{
    status = $(if ($needsHuman.Count) { 'needs-human' } else { 'ready-for-load' })
    adapter = $Adapter
    projectPath = $proj
    appName = $AppName
    webPort = $WebPort
    v8version = $V8Version
    ninjaMcp = $autumnMain
    ninjaLive = (Join-Path $proj 'src\cfe\NinjaLive')
    needsHuman = $needsHuman
    next = @(
      'Fill IB credentials if placeholders',
      'cfe_load NinjaLive via vrunner',
      'Publish Apache app + /hs/ninja-live',
      'MCP live_version + live_extensions_list'
    )
  }
  $reportPath = Join-Path $proj 'kit-init-report.json'
  Set-FileContentUtf8 $reportPath (($report | ConvertTo-Json -Depth 5))
  Write-Status 'OK' ("init-project done -> {0} status={1}" -f $reportPath, $report.status)
  return 0
}

switch ($Command) {
  'doctor' { exit (Invoke-Doctor) }
  'verify' { exit (Invoke-Verify) }
  'apply' { exit (Invoke-Apply) }
  'init-project' { exit (Invoke-InitProject) }
  default {
    Write-Host '1c-ninja-kit CLI v0.4'
    Write-Host '  kit.ps1 doctor [-Strict]'
    Write-Host '  kit.ps1 verify'
    Write-Host '  kit.ps1 apply [-Adapter opencode] [-DryRun]'
    Write-Host '  kit.ps1 init-project -ProjectPath PATH [options]'
    Write-Host 'FORBIDDEN: init-project on ecoladev'
    Write-Host "KitRoot: $KitRoot"
    exit 0
  }
}

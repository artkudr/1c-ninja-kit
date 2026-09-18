#Requires -Version 5.1
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'verify', 'apply', 'capture', 'init-project', 'help')]
  [string]$Command = 'help',

  [switch]$DryRun,
  [switch]$Force,
  [switch]$Strict,

  [string]$ProfileName = '1c-ninja-kit',

  [ValidateSet('cursor', 'deepseek', 'hermes')]
  [string]$Adapter = 'cursor',

  [string]$ProjectPath,
  [string]$AppName = 'ninja-kit-e2e',
  [string]$V8Version = '8.3',
  [int]$WebPort = 0,
  [string]$IbConnection = '',
  [string]$DbUser = '',
  [string]$DbPwd = '',
  [switch]$SkipRulesLink,
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

  $userMcp = Join-Path $env:USERPROFILE '.cursor\mcp.json'
  if (Test-Path -LiteralPath $userMcp) {
    $raw = Get-Content -LiteralPath $userMcp -Raw -ErrorAction SilentlyContinue
    $bad = @('vrunner', '1c-ninja-mcp', '1c-mcp-toolkit', 'bsl-analyzer-reference', 'bsl-analyzer-workspace')
    $hits = @($bad | Where-Object { $raw -match [regex]::Escape($_) })
    if ($hits.Count -gt 0) {
      Write-Status 'WARN' ("user mcp.json contains 1C servers: " + ($hits -join ', '))
      $warn++
    } else {
      Write-Status 'OK' 'user mcp.json has no known 1C server names'
    }
  } else {
    Write-Status 'INFO' 'user mcp.json absent (ok)'
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

  if ($Adapter -eq 'cursor') {
    $dst = Join-Path $env:USERPROFILE '.cursor'
    foreach ($p in @(
        @{ S = 'profile\skills'; D = 'skills' },
        @{ S = 'profile\rules'; D = 'rules' },
        @{ S = 'profile\agents'; D = 'agents' }
      )) {
      $src = Join-Path $KitRoot $p.S
      $target = Join-Path $dst $p.D
      Write-Status 'INFO' "sync $($p.S) -> $target"
      if ($DryRun) { [void](Invoke-Robo $src $target -ListOnly) }
      else { [void](Invoke-Robo $src $target) }
    }
    if (Test-Path $docsSrc) {
      $docsDst = Join-Path $dst 'docs'
      Write-Status 'INFO' "sync docs-patches -> $docsDst"
      if ($DryRun) { [void](Invoke-Robo $docsSrc $docsDst -ListOnly) }
      else { [void](Invoke-Robo $docsSrc $docsDst) }
    }
    if (-not $DryRun) { Write-Status 'INFO' 'Ensure user mcp.json has NO 1C servers' }
  }
  elseif ($Adapter -eq 'deepseek') {
    $targets = @(
      (Join-Path $env:USERPROFILE '.agents\skills'),
      (Join-Path $env:USERPROFILE '.dsh\skills')
    )
    foreach ($target in $targets) {
      Write-Status 'INFO' "sync skills -> $target"
      if ($DryRun) { [void](Invoke-Robo $skillsSrc $target -ListOnly) }
      else { [void](Invoke-Robo $skillsSrc $target) }
    }
  }
  elseif ($Adapter -eq 'hermes') {
    $target = Join-Path $env:USERPROFILE '.hermes\skills'
    Write-Status 'INFO' "sync skills -> $target"
    if ($DryRun) { [void](Invoke-Robo $skillsSrc $target -ListOnly) }
    else { [void](Invoke-Robo $skillsSrc $target) }
    $soulSrc = Join-Path $KitRoot 'adapters\hermes\SOUL.1c-ninja-kit.md'
    $soulDst = Join-Path $env:USERPROFILE '.hermes\SOUL.1c-ninja-kit.md'
    if (Test-Path $soulSrc) {
      Write-Status 'INFO' "copy SOUL fragment -> $soulDst"
      if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $soulDst) | Out-Null
        Copy-Item $soulSrc $soulDst -Force
      }
    }
  }

  if ($DryRun) { Write-Status 'WARN' 'DryRun - no files written' }
  else { Write-Status 'OK' "apply done (adapter=$Adapter)" }
  return 0
}

function Invoke-Capture {
  Write-Host '=== kit capture (live profile -> kit SoT) ===' -ForegroundColor Cyan
  if (-not $Force) {
    Write-Status 'FAIL' 'capture requires -Force'
    return 1
  }
  $srcRoot = Join-Path $env:USERPROFILE '.cursor'
  foreach ($p in @(
      @{ S = 'skills'; D = 'profile\skills' },
      @{ S = 'rules'; D = 'profile\rules' },
      @{ S = 'agents'; D = 'profile\agents' }
    )) {
    $src = Join-Path $srcRoot $p.S
    $d = Join-Path $KitRoot $p.D
    if (-not (Test-Path $src)) { Write-Status 'WARN' "skip missing $src"; continue }
    Write-Status 'INFO' "capture $($p.S) -> $($p.D)"
    if ($DryRun) { [void](Invoke-Robo $src $d -ListOnly) }
    else { [void](Invoke-Robo $src $d) }
  }
  Write-Status 'WARN' 'Re-run lock/inventory after capture'
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
      'docs', '.cursor\commands', 'openspec\specs', 'openspec\changes\archive', 'openspec\templates'
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

  $autumnTpl = Get-Content (Join-Path $tplRoot 'autumn-properties.json.tpl') -Raw
  $autumn = $autumnTpl.Replace('{{IBCONNECTION}}', $ib).Replace('{{DB_USER}}', $user).
    Replace('{{DB_PWD}}', $pwd).Replace('{{V8VERSION}}', $V8Version).
    Replace('{{APP_NAME}}', $AppName).Replace('{{WEB_PORT}}', "$WebPort")
  Set-FileContentUtf8 (Join-Path $proj 'autumn-properties.json') $autumn

  $repoTpl = Get-Content (Join-Path $tplRoot 'repository.json.tpl') -Raw
  $repo = $repoTpl.Replace('{{REPO_ROOT}}', '\\\\SERVER\\repo-placeholder').
    Replace('{{REPO_USER}}', 'repo-user-placeholder').
    Replace('{{REPO_ADMIN}}', 'repo-admin-placeholder')
  Set-FileContentUtf8 (Join-Path $proj 'repository.json') $repo

  Copy-Item (Join-Path $tplRoot 'bsl-analyzer.toml.tpl') (Join-Path $proj 'bsl-analyzer.toml') -Force

  $mcpObj = @{
    mcpServers = @{
      vrunner = @{ command = $vrunnerMcp }
      '1c-mcp-toolkit' = @{ url = 'http://127.0.0.1:6003/mcp'; type = 'streamable-http' }
      '1c-ninja-mcp' = @{
        command = 'oscript'
        args = @($autumnMain)
        env = @{
          SHCNTX_HELP_DB = $shcntx
          NINJA_URL = "http://localhost:$WebPort/$AppName/hs/ninja-live"
          NINJA_USER = $user
          NINJA_PASSWORD = $pwd
        }
      }
      'bsl-analyzer-reference' = @{
        command = $bslExe
        args = @('mcp', 'serve', '--profile', 'reference')
      }
      'bsl-analyzer-workspace' = @{
        command = $bslExe
        args = @('mcp', 'serve', '--profile', 'workspace', '--source-dir', $proj)
      }
    }
  }
  $mcpJson = $mcpObj | ConvertTo-Json -Depth 8
  Set-FileContentUtf8 (Join-Path $proj '.cursor\mcp.json') $mcpJson
  $mcpEx = $mcpJson
  if ($pwd -ne 'PWD_PLACEHOLDER' -and $pwd) {
    $mcpEx = $mcpEx.Replace($pwd, '<password>')
  }
  if ($user -ne 'USER_PLACEHOLDER' -and $user) {
    $mcpEx = $mcpEx.Replace($user, '<user>')
  }
  Set-FileContentUtf8 (Join-Path $proj '.cursor\mcp.json.example') $mcpEx

  $giSnippet = Get-Content (Join-Path $tplRoot 'gitignore-1c.snippet') -Raw
  $giExtra = "`n# kit secrets`nautumn-properties.json`n.env`n.dev.env`n"
  Set-FileContentUtf8 (Join-Path $proj '.gitignore') ($giSnippet + $giExtra)

  Copy-Item (Join-Path $tplRoot 'openspec\*') (Join-Path $proj 'openspec') -Recurse -Force
  Copy-Item (Join-Path $tplRoot 'cursor-commands\*') (Join-Path $proj '.cursor\commands') -Force
  Copy-Item (Join-Path $tplRoot 'dev-stack.md.tpl') (Join-Path $proj 'docs\dev-stack.md') -Force
  if (Test-Path (Join-Path $tplRoot 'smoke.config.json.tpl')) {
    Copy-Item (Join-Path $tplRoot 'smoke.config.json.tpl') (Join-Path $proj 'tools\web-test\smoke.config.json') -Force
  }

  if (-not $SkipRulesLink) {
    $rulesSrc = Join-Path $env:USERPROFILE '.cursor\rules'
    if (-not (Test-Path $rulesSrc)) { $rulesSrc = Join-Path $KitRoot 'profile\rules' }
    $rulesDst = Join-Path $proj '.cursor\rules'
    if (Test-Path $rulesDst) {
      $item = Get-Item $rulesDst -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Status 'FAIL' '.cursor/rules is a reparse point - remove manually'
        return 1
      }
    } else {
      New-Item -ItemType Directory -Force -Path $rulesDst | Out-Null
    }
    $linked = 0
    Get-ChildItem $rulesSrc -File -Filter '*.mdc' | ForEach-Object {
      $dest = Join-Path $rulesDst $_.Name
      if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force }
      $srcFile = $_.FullName
      $cmdLine = 'mklink /H "' + $dest + '" "' + $srcFile + '"'
      cmd /c $cmdLine | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Path $dest)) {
        $linked++
      } else {
        Copy-Item $srcFile $dest -Force
        $linked++
        Write-Status 'WARN' ("hardlink failed for {0} - copied" -f $_.Name)
      }
    }
    Write-Status 'OK' "rules linked/copied: $linked"
  }

  # Adapter project context
  $agentsTpl = Get-Content (Join-Path $KitRoot 'adapters\shared\AGENTS.md.tpl') -Raw
  if ($Adapter -eq 'hermes') {
    Set-FileContentUtf8 (Join-Path $proj '.hermes.md') $agentsTpl
    Copy-Item (Join-Path $KitRoot 'adapters\hermes\mcp_servers.fragment.yaml') (Join-Path $proj 'mcp_servers.fragment.yaml') -Force
    Write-Status 'OK' 'wrote .hermes.md + mcp_servers.fragment.yaml'
  }
  elseif ($Adapter -eq 'deepseek') {
    Set-FileContentUtf8 (Join-Path $proj 'AGENTS.md') $agentsTpl
    New-Item -ItemType Directory -Force -Path (Join-Path $proj '.dsh') | Out-Null
    Copy-Item (Join-Path $KitRoot 'adapters\deepseek\mcp.example.json') (Join-Path $proj '.dsh\mcp.servers.example.json') -Force
    Write-Status 'OK' 'wrote AGENTS.md + .dsh/mcp.servers.example.json'
  }
  else {
    # cursor: also drop AGENTS.md for harness-agnostic readers
    Set-FileContentUtf8 (Join-Path $proj 'AGENTS.md') $agentsTpl
    Write-Status 'OK' 'wrote AGENTS.md (cursor + portable)'
  }

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
  'capture' { exit (Invoke-Capture) }
  'init-project' { exit (Invoke-InitProject) }
  default {
    Write-Host '1c-ninja-kit CLI v0.2'
    Write-Host '  kit.ps1 doctor [-Strict]'
    Write-Host '  kit.ps1 verify'
    Write-Host '  kit.ps1 apply [-Adapter cursor|deepseek|hermes] [-DryRun]'
    Write-Host '  kit.ps1 capture -Force [-DryRun]'
    Write-Host '  kit.ps1 init-project -ProjectPath PATH [-Adapter ...] [options]'
    Write-Host 'FORBIDDEN: init-project on ecoladev'
    Write-Host "KitRoot: $KitRoot"
    exit 0
  }
}

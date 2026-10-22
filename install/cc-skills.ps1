<#
.SYNOPSIS
  Установка/обновление набора скиллов cc-1c-skills (ветка port-opencode) в ~/.config/opencode/skills.

.DESCRIPTION
  Кит не хранит cc-1c-skills: набор скачивается из репозитория и ставится глобально.
  Исключения: web-* (kit-версии под профильный Apache 8083/8085).
  Пути `.opencode/skills/...` в .md-файлах заменяются на фактический skills root.
  Штамп .cc-1c-skills.stamp.json хранит commit и список имён; при обновлении исчезнувшие имена удаляются.

.PARAMETER Update
  Обновить до свежей версии. Без ключа установка выполняется только если набора ещё нет.

.PARAMETER Ref
  Ветка/тег/commit. По умолчанию — branch из companions/pins.json (port-opencode).

.PARAMETER SourcePath
  Локальный клон репозитория вместо скачивания (офлайн/тест).

.PARAMETER SkillsRoot
  Каталог установки. По умолчанию %USERPROFILE%\.config\opencode\skills.

.PARAMETER DryRun
  Показать план без изменений.

.EXAMPLE
  powershell -NoProfile -File install\cc-skills.ps1
  powershell -NoProfile -File install\cc-skills.ps1 -Update
  powershell -NoProfile -File install\cc-skills.ps1 -Ref port-opencode -DryRun
#>
param(
    [switch]$Update,
    [string]$Ref = "",
    [string]$SourcePath = "",
    [string]$SkillsRoot = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$KitRoot = Split-Path $PSScriptRoot -Parent
$pinsPath = Join-Path $KitRoot "companions\pins.json"
if (-not (Test-Path $pinsPath)) { throw "pins.json not found: $pinsPath" }
$pins = Get-Content $pinsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cfg = $pins.cc1cSkills
if (-not $cfg -or -not $cfg.repo) { throw "companions/pins.json: cc1cSkills.repo missing" }

if (-not $SkillsRoot) { $SkillsRoot = Join-Path $env:USERPROFILE ".config\opencode\skills" }
$stampPath = Join-Path $SkillsRoot ".cc-1c-skills.stamp.json"
$exclude = @('web-info', 'web-publish', 'web-stop', 'web-test', 'web-unpublish')

$installed = Test-Path (Join-Path $SkillsRoot "db-list\SKILL.md")
if (-not $Update -and $installed) {
    $at = ""
    if (Test-Path $stampPath) {
        $st = Get-Content $stampPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($st.commit) { $at = " ($($st.commit.Substring(0, [Math]::Min(12, $st.commit.Length))), $($st.installedAt))" }
    }
    Write-Host "cc-1c-skills уже установлен$at. Обновление: cc-skills.ps1 -Update"
    return 0
}

$ref = if ($Ref) { $Ref } elseif ($cfg.ref) { [string]$cfg.ref } else { [string]$cfg.branch }
if ($DryRun -and -not $SourcePath) {
    Write-Host "[dry-run] git fetch $($cfg.repo) ref=$ref -> temp; установка ~76 скиллов (исключены: $($exclude -join ', ')) -> $SkillsRoot"
    return 0
}

$cleanup = $null
if ($SourcePath) {
    if (-not (Test-Path (Join-Path $SourcePath ".git"))) { throw "SourcePath is not a git clone: $SourcePath" }
    $src = (Resolve-Path $SourcePath).Path
} else {
    $src = Join-Path ([IO.Path]::GetTempPath()) ("cc-1c-skills-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $cleanup = $src
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    & git -C $src init --quiet
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    & git -C $src remote add origin $cfg.repo
    & git -C $src fetch --quiet --depth 1 origin $ref
    if ($LASTEXITCODE -ne 0) {
        Write-Host "fetch --depth 1 по '$ref' не прошёл, пробую полный fetch..." -ForegroundColor Yellow
        & git -C $src fetch --quiet origin
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed: $ref" }
    }
    & git -C $src checkout --quiet FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { & git -C $src checkout --quiet $ref }
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed: $ref" }
}

# --- Корень скиллов в дереве ---
$skillsSrc = Join-Path $src ".opencode\skills"
if (-not (Test-Path $skillsSrc)) {
    $cand = Get-ChildItem $src -Recurse -Directory -Filter "skills" -ErrorAction SilentlyContinue |
        Where-Object { (Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } | Measure-Object).Count -gt 10 } |
        Select-Object -First 1
    if (-not $cand) { throw "skills root not found in $src" }
    $skillsSrc = $cand.FullName
}

$names = @(Get-ChildItem $skillsSrc -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } |
    Where-Object { $exclude -notcontains $_.Name } |
    ForEach-Object { $_.Name } | Sort-Object)
if ($names.Count -lt 10) { throw "too few skills found: $($names.Count)" }

$commit = ""
if (Test-Path (Join-Path $src ".git")) { $commit = (& git -C $src rev-parse HEAD 2>$null | Out-String).Trim() }

Write-Host "Источник: $($cfg.repo) @ $ref ($commit)"
Write-Host "Скиллов к установке: $($names.Count) (исключены: $($exclude -join ', '))"

# --- Path-fix: .opencode/skills/ -> фактический skills root (только .md) ---
$fixed = 0
foreach ($n in $names) {
    $dir = Join-Path $skillsSrc $n
    Get-ChildItem $dir -Recurse -File -Filter *.md | ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        if ($text.Contains('.opencode/skills/')) {
            $text = $text.Replace('.opencode/skills/', "$SkillsRoot\")
            [IO.File]::WriteAllText($_.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
            $fixed++
        }
    }
}
Write-Host "Path-fix: $fixed .md-файлов"

# --- Копирование ---
New-Item -ItemType Directory -Force -Path $SkillsRoot | Out-Null
foreach ($n in $names) {
    & robocopy (Join-Path $skillsSrc $n) (Join-Path $SkillsRoot $n) /E /PURGE /NFL /NDL /NJH /NJS /NP /XD __pycache__ | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $n ($LASTEXITCODE)" }
}

# --- Прунинг исчезнувших имён (по прошлому штампу) ---
$removed = @()
if (Test-Path $stampPath) {
    $prev = @((Get-Content $stampPath -Raw -Encoding UTF8 | ConvertFrom-Json).names)
    $stale = @($prev | Where-Object { $names -notcontains $_ -and $exclude -notcontains $_ })
    foreach ($s in $stale) {
        $p = Join-Path $SkillsRoot $s
        if (Test-Path (Join-Path $p "SKILL.md")) {
            Remove-Item $p -Recurse -Force
            $removed += $s
        }
    }
}
if ($removed.Count -gt 0) { Write-Host "Удалены устаревшие: $($removed -join ', ')" }

# --- Штамп ---
$stampOut = [ordered]@{
    repo        = $cfg.repo
    ref         = $ref
    commit      = $commit
    installedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    names       = $names
}
($stampOut | ConvertTo-Json -Depth 4) | Set-Content -Path $stampPath -Encoding UTF8
Write-Host "Готово: $($names.Count) скиллов в $SkillsRoot"

if ($cleanup) { Remove-Item $cleanup -Recurse -Force -ErrorAction SilentlyContinue }
return 0

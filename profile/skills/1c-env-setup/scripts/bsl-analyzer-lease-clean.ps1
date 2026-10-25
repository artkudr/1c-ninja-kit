# Чистильщик мёртвых аренд bsl-analyzer. Ничего не запускает и не останавливает.
#
# Зачем: если процесс bsl-analyzer убили жёстко (закрытие редактора, крэш, перезагрузка), в кеше
# остаётся ...\workspaces\v1\<hash>\writer.lease с мёртвым PID. Следующий backend считает владельца
# живым и не забирает каталог: граф отвечает
#   graph busy: ... is used by another live process (pid <мёртвый>)
# и не работает до ручной уборки. Скрипт снимает только те аренды, чей процесс уже не существует.
#
# Задача планировщика "bsl-analyzer lease clean" ставится kit.ps1 apply -Adapter opencode.
#
# Примеры:
#   .\bsl-analyzer-lease-clean.ps1                     # все проекты + общий кеш профиля
#   .\bsl-analyzer-lease-clean.ps1 -Projects C:\1C\projects\devtools
#   .\bsl-analyzer-lease-clean.ps1 -WhatIf

[CmdletBinding(SupportsShouldProcess)]
param(
    # Проекты для проверки. По умолчанию — все каталоги ProjectsRoot с кешем .build\workspaces.
    [string[]]$Projects,

    [string]$ProjectsRoot = 'C:\1C\projects',

    # Общий кеш профиля (проекты без --cache-dir, например neofamily-dev).
    [string]$GlobalCacheRoot = (Join-Path $env:LOCALAPPDATA 'bsl-analyzer\workspaces\v1'),

    # Сколько дней хранить снятые аренды (writer.lease.stale-*). 0 — не чистить.
    [int]$KeepStaleDays = 14,

    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'bsl-analyzer\lease-clean.log')
)

$ErrorActionPreference = 'Stop'

$cacheRoots = [System.Collections.Generic.List[string]]::new()

if ($Projects) {
    foreach ($p in $Projects) { $cacheRoots.Add((Join-Path $p '.build\workspaces\v1')) }
} elseif (Test-Path $ProjectsRoot) {
    Get-ChildItem $ProjectsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $ws = Join-Path $_.FullName '.build\workspaces\v1'
        if (Test-Path $ws) { $cacheRoots.Add($ws) }
    }
}
if ($GlobalCacheRoot -and (Test-Path $GlobalCacheRoot)) { $cacheRoots.Add($GlobalCacheRoot) }

$actions = [System.Collections.Generic.List[string]]::new()

function Find-DeadLease {
    param([string]$LeasePath)

    $raw = Get-Content $LeasePath -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { return $null }

    try {
        $data = $raw | ConvertFrom-Json
    } catch {
        # Недописанный файл живого процесса: не трогаем.
        return $null
    }

    if (-not $data.pid) { return $null }
    if (Get-Process -Id $data.pid -ErrorAction SilentlyContinue) { return $null }

    # Пока проверяли, аренду могли переписать — тогда это уже другая запись, не наше дело.
    $again = Get-Content $LeasePath -Raw -ErrorAction SilentlyContinue
    if ($again -ne $raw) { return $null }

    return $data
}

foreach ($root in $cacheRoots) {
    foreach ($dir in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
        $lease = Join-Path $dir.FullName 'writer.lease'
        if (Test-Path $lease) {
            $dead = Find-DeadLease -LeasePath $lease
            if ($dead) {
                $target = "$lease.stale-$(Get-Date -Format yyyyMMdd-HHmmss)"
                if ($PSCmdlet.ShouldProcess($lease, "снять мёртвую аренду (pid $($dead.pid))")) {
                    Move-Item $lease $target -Force
                    $actions.Add("$(Split-Path $root -Parent) : снята аренда pid $($dead.pid) -> $(Split-Path $target -Leaf)")
                }
            }
        }

        if ($KeepStaleDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$KeepStaleDays)
            Get-ChildItem $dir.FullName -Filter 'writer.lease.stale-*' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                ForEach-Object {
                    if ($PSCmdlet.ShouldProcess($_.FullName, 'удалить старую снятую аренду')) {
                        Remove-Item $_.FullName -Force
                        $actions.Add("$(Split-Path $root -Parent) : удалена старая аренда $($_.Name)")
                    }
                }
        }
    }
}

if ($actions.Count -gt 0) {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $lines = $actions | ForEach-Object { "$stamp  $_" }
    $logDir = Split-Path $LogPath -Parent
    if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $lines -Encoding UTF8
    $actions | ForEach-Object { Write-Output $_ }
}

# Тишина при штатном прогоне: задача идёт по расписанию, лог не должен пухнуть.
exit 0

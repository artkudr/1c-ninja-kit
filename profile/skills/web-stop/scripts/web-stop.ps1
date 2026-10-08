# web-stop — Stop profile Apache (apache-83 / apache-85)
# Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
<#
.SYNOPSIS
    Остановка Apache HTTP Server профиля (по v8version проекта)

.PARAMETER ApachePath
    Корень Apache; иначе профиль apache-83/85

.PARAMETER V8Version
    Маска платформы для выбора профиля
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ApachePath,

    [Parameter(Mandatory=$false)]
    [string]$V8Version
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Resolve-1cWebTargets.ps1 lives in the adapter's skills root - probe the known
# ones instead of hardcoding a single client layout.
$_resolver = $null
foreach ($_sr in @(
    (Join-Path $env:USERPROFILE '.config\opencode\skills')
  )) {
  $_probe = Join-Path $_sr 'web-publish\scripts\Resolve-1cWebTargets.ps1'
  if (Test-Path -LiteralPath $_probe) { $_resolver = $_probe; break }
}
if (-not $_resolver) {
  throw "web-publish\scripts\Resolve-1cWebTargets.ps1 not found in any skill root (skill web-publish)."
}
. $_resolver
$targets = Resolve-1cWebTargets -V8Version $V8Version -ApachePath $ApachePath
$ApachePath = $targets.ApachePath
Write-Host "Apache profile: apache-$($targets.ApacheLabel) -> $ApachePath" -ForegroundColor Yellow

# --- Helper: filter httpd processes by our ApachePath ---
$httpdExe = Join-Path (Join-Path $ApachePath "bin") "httpd.exe"
$httpdExeNorm = (Resolve-Path $httpdExe -ErrorAction SilentlyContinue).Path
function Get-OurHttpd {
    Get-Process httpd -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $httpdExeNorm } catch { $false }
    }
}

# --- Check process (only our Apache) ---
$httpdProc = Get-OurHttpd
if (-not $httpdProc) {
    $foreign = Get-Process httpd -ErrorAction SilentlyContinue
    if ($foreign) {
        Write-Host "Наш Apache не запущен" -ForegroundColor Yellow
        Write-Host "[WARN] Обнаружен сторонний Apache (PID: $(($foreign | Select-Object -First 1).Id))" -ForegroundColor Yellow
    } else {
        Write-Host "Apache не запущен" -ForegroundColor Yellow
    }
    exit 0
}

$pids = ($httpdProc | ForEach-Object { $_.Id }) -join ", "
Write-Host "Останавливаю Apache (PID: $pids)..."

# --- Stop our processes ---
$httpdProc | Stop-Process -Force -ErrorAction SilentlyContinue

# --- Wait for shutdown ---
$maxWait = 5
$elapsed = 0
while ($elapsed -lt $maxWait) {
    Start-Sleep -Seconds 1
    $elapsed++
    $check = Get-OurHttpd
    if (-not $check) {
        Write-Host "Apache остановлен" -ForegroundColor Green
        Write-Host "Публикации сохранены. Перезапуск: /web-publish <база>  Удаление: /web-unpublish --all" -ForegroundColor Gray
        exit 0
    }
}

# --- Fallback: force kill ---
$remaining = Get-OurHttpd
if ($remaining) {
    Write-Host "Принудительная остановка..." -ForegroundColor Yellow
    $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $final = Get-OurHttpd
    if ($final) {
        Write-Host "Error: не удалось остановить Apache" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Apache остановлен" -ForegroundColor Green
Write-Host "Публикации сохранены. Перезапуск: /web-publish <база>  Удаление: /web-unpublish --all" -ForegroundColor Gray

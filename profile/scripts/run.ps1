<#
run.ps1 — единая точка запуска скриптов скиллов из ролей.

  powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\opencode\scripts\run.ps1" <script.ps1> [args...]

Разрешены только скрипты контура: <...>\skills\<скилл>\scripts\*.ps1 — и в профиле кита,
и в установленной копии. Всё остальное отклоняется с кодом 2.

Это оболочка, а не замена правам: роль всё равно должна иметь право на сам скилл.
Смысл один — не держать в семи агентах два почти одинаковых shell-паттерна и не
подбирать формулировку после каждого «permission denied».
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $Path))
}

$full = Resolve-FullPath $Script

if ($full -notlike '*\skills\*\scripts\*.ps1') {
    [Console]::Error.WriteLine('run.ps1: script outside the skill contour: ' + $full)
    exit 2
}
if (-not [System.IO.File]::Exists($full)) {
    [Console]::Error.WriteLine('run.ps1: script not found: ' + $full)
    exit 2
}

$child = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $full)
if ($Arguments) { $child += $Arguments }
& powershell.exe @child
$code = $LASTEXITCODE
if ($null -eq $code) { exit 0 }
exit $code

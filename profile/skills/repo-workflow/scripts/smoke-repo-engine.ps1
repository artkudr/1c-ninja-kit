# Safe smoke for repo wrapper: path resolve + designer call with missing metadata object.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$here = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
. (Join-Path $here 'repo-common.ps1')

$projectRoot = Get-RepoProjectRoot
$map = Get-RepoMap -ProjectRoot $projectRoot
$extName = ($map.cfe.PSObject.Properties | Select-Object -First 1).Name
$storagePath = Get-RepoStoragePath -Map $map -ExtensionName $extName
$main = Get-RepoVrunnerMain -ProjectRoot $projectRoot

Write-Host "Step 1: resolve without 1C"
Write-Host "  project root: $projectRoot"
Write-Host "  vrunner main: $main"
Write-Host "  extension:    $extName"
Write-Host "  storage:      $storagePath (exists: $(Test-Path -LiteralPath $storagePath))"
Write-Host "  autumn-props: $(Test-Path -LiteralPath (Join-Path $projectRoot 'autumn-properties.json'))"

if (-not (Test-Path -LiteralPath $storagePath)) {
	throw "Storage folder is not accessible: $storagePath"
}

Write-Host ""
Write-Host "Step 2: repo.ps1 lock on bogus object (expect platform error, no repo changes)"

$repoPs1 = Join-Path $here 'repo.ps1'
$bogusObject = ([char]0x041A)+([char]0x043E)+([char]0x043D)+([char]0x0441)+([char]0x0442)+([char]0x0430)+([char]0x043D)+([char]0x0442)+([char]0x0430)+'.__SmokeRepoEngineMissingObject__'
$logFile = Join-Path $env:TEMP ("repo-smoke-{0}.log" -f [guid]::NewGuid().ToString('N'))

Start-Transcript -Path $logFile -Force | Out-Null
$step2Failed = $false
$step2Error = $null
try {
	& $repoPs1 -Action lock -Extension $extName -FullName $bogusObject -Recursive:$false
} catch {
	$step2Failed = $true
	$step2Error = $_.Exception.Message
} finally {
	Stop-Transcript | Out-Null
}
$step2Output = Get-Content -LiteralPath $logFile -Raw -Encoding UTF8
Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue

if ($step2Output -notmatch 'vrunner run designer') {
	Write-Host "FAIL: designer command was not invoked"
	exit 1
}
if (-not $step2Failed) {
	Write-Host "FAIL: repo.ps1 completed without error for missing object"
	exit 1
}
if (-not $step2Error) {
	Write-Host "FAIL: empty error message"
	exit 1
}

Write-Host "OK: repo.ps1 failed as expected: $step2Error"
exit 0

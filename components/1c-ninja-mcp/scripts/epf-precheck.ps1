# epf-precheck — platform CheckConfig (modules/handlers/…) before EPF write.
# Port of epf-build source-check: embed into stub IB, then /CheckConfig; never writes .epf.
# Source: Nikolay-Shirokov/cc-1c-skills epf-build (port-cursor).
param(
	[Parameter(Mandatory)]
	[string]$SRC,

	[string]$Checks = "modules,handlers",

	[string]$Context = "ThinClient,Server",

	[string]$V8Path
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function ConvertTo-CleanPath {
	param([string]$Value, [string]$ParamName)
	if (-not $Value) { return $Value }
	$v = $Value.Trim()
	if ($v.Length -ge 2 -and $v[0] -eq $v[-1] -and ($v[0] -eq '"' -or $v[0] -eq "'")) {
		$v = $v.Substring(1, $v.Length - 2).Trim()
	}
	if ($v.Length -gt 3 -and ($v[-1] -eq '\' -or $v[-1] -eq '/')) { $v = $v.Substring(0, $v.Length - 1) }
	if ($v.Contains('"')) {
		Write-Host "Error: $ParamName contains a quote character: $Value" -ForegroundColor Red
		exit 1
	}
	return $v
}

function Get-SourceCheckList {
	param([string]$Checks)
	$known = @('modules', 'handlers', 'unreferenced', 'empty-handlers', 'config')
	if (-not $Checks -or -not $Checks.Trim()) {
		return @('modules', 'handlers')
	}
	$list = @($Checks -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
	if ($list -contains 'off') { return @() }
	foreach ($c in $list) {
		if ($known -notcontains $c) {
			Write-Host "Error: unknown check '$c' (expected: $($known -join ', ') or off)" -ForegroundColor Red
			exit 1
		}
	}
	return $list
}

function Get-CheckFlags {
	param([string[]]$Checks, [string[]]$Contexts)
	$flags = @()
	if ($Checks -contains 'modules') { foreach ($c in $Contexts) { $flags += "-$c" } }
	if ($Checks -contains 'handlers') { $flags += '-HandlersExistence' }
	if ($Checks -contains 'unreferenced') { $flags += '-UnreferenceProcedures' }
	if ($Checks -contains 'empty-handlers') { $flags += '-EmptyHandlers' }
	if ($Checks -contains 'config') { $flags += '-ConfigLogIntegrity', '-IncorrectReferences' }
	return $flags
}

function Resolve-RootXml {
	param([string]$Src)
	if (Test-Path $Src -PathType Leaf) {
		if ($Src -match '\.xml$') { return (Resolve-Path $Src).Path }
		Write-Host "Error: SRC file must be .xml root of ExternalDataProcessor/ExternalReport: $Src" -ForegroundColor Red
		exit 1
	}
	if (-not (Test-Path $Src -PathType Container)) {
		Write-Host "Error: SRC not found: $Src" -ForegroundColor Red
		exit 1
	}
	$files = @()
	$files += Get-ChildItem -LiteralPath $Src -Filter *.xml -File -ErrorAction SilentlyContinue
	$files += Get-ChildItem -LiteralPath $Src -Filter *.xml -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
	$seen = @{}
	foreach ($f in $files) {
		$full = $f.FullName
		if ($seen.ContainsKey($full)) { continue }
		$seen[$full] = $true
		try {
			$head = Get-Content -LiteralPath $full -TotalCount 40 -ErrorAction Stop | Out-String
		} catch { continue }
		if ($head -match 'ExternalDataProcessor|ExternalReport') {
			return $full
		}
	}
	Write-Host "Error: no ExternalDataProcessor/ExternalReport root XML under SRC: $Src" -ForegroundColor Red
	exit 1
}

function Resolve-V8Exe {
	param([string]$Hint)
	if ($Hint) {
		$h = ConvertTo-CleanPath $Hint '-V8Path'
		if (Test-Path $h -PathType Container) {
			$cand = Join-Path $h '1cv8.exe'
			if (Test-Path $cand) { return (Resolve-Path $cand).Path }
		}
		if (Test-Path $h -PathType Leaf) { return (Resolve-Path $h).Path }
	}
	foreach ($envName in @('V8PATH', 'VRUNNER_V8PATH')) {
		$v = [Environment]::GetEnvironmentVariable($envName)
		if ($v) {
			$r = Resolve-V8Exe $v
			if ($r) { return $r }
		}
	}
	$best = $null
	$bestVer = ''
	foreach ($root in @('C:\Program Files\1cv8', 'C:\Program Files (x86)\1cv8')) {
		if (-not (Test-Path $root)) { continue }
		Get-ChildItem -LiteralPath $root -Filter 1cv8.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
			$verDir = Split-Path (Split-Path $_.FullName -Parent) -Leaf
			if ($verDir -gt $bestVer) {
				$bestVer = $verDir
				$best = $_.FullName
			}
		}
	}
	return $best
}
function Resolve-SourcePath {
	param([string]$Line, [string]$SourceDir)
	$candidate = $null
	$m = [regex]::Match($Line, '(?:Обработка|Отчет|DataProcessor|Report)\.([^.]+)\.(?:Форма|Form)\.([^.]+)\.')
	if ($m.Success) { $candidate = (Join-Path $SourceDir (Join-Path $m.Groups[1].Value (Join-Path "Forms" (Join-Path $m.Groups[2].Value "Ext\Form\Module.bsl")))) }
	if (-not $candidate) {
		$m = [regex]::Match($Line, '(?:Обработка|Отчет|DataProcessor|Report)\.([^.]+)\.(МодульОбъекта|ObjectModule)')
		if ($m.Success) { $candidate = (Join-Path $SourceDir (Join-Path $m.Groups[1].Value "Ext\ObjectModule.bsl")) }
	}
	if (-not $candidate) {
		$m = [regex]::Match($Line, '(?:Обработка|Отчет|DataProcessor|Report)\.([^.]+)\.(МодульМенеджера|ManagerModule)')
		if ($m.Success) { $candidate = (Join-Path $SourceDir (Join-Path $m.Groups[1].Value "Ext\ManagerModule.bsl")) }
	}
	if ($candidate -and (Test-Path $candidate -PathType Leaf)) { return $candidate }
	return $null
}

function Invoke-PlatformProcess {
	param([string]$Exe, [string[]]$ProcArgs)
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $Exe
	$psi.Arguments = ($ProcArgs -join ' ')
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true
	$p = [System.Diagnostics.Process]::Start($psi)
	$out = $p.StandardOutput.ReadToEnd()
	$err = $p.StandardError.ReadToEnd()
	$p.WaitForExit()
	return @{ ExitCode = $p.ExitCode; Output = ($out + $err) }
}

$SRC = ConvertTo-CleanPath $SRC '-SRC'
$checkList = @(Get-SourceCheckList $Checks)
if ($checkList.Count -eq 0) {
	Write-Host "epf-precheck: checks=off — skip"
	exit 0
}

$contextList = @($Context -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($contextList.Count -eq 0) { $contextList = @('ThinClient', 'Server') }
elseif ($checkList -notcontains 'modules') {
	Write-Host "Error: -Context задан, но в -Checks нет modules — контексты относятся только к ней" -ForegroundColor Red
	exit 1
}

$sourceFile = Resolve-RootXml $SRC
$sourceDir = Split-Path $sourceFile -Parent
$v8 = Resolve-V8Exe $V8Path
if (-not $v8) {
	Write-Host "Error: 1cv8.exe not found (set V8PATH / VRUNNER_V8PATH or -V8Path)" -ForegroundColor Red
	exit 1
}

$stubScript = Join-Path $PSScriptRoot 'stub-db-create.ps1'
if (-not (Test-Path $stubScript)) {
	Write-Host "Error: stub-db-create.ps1 not found next to epf-precheck.ps1" -ForegroundColor Red
	exit 1
}

$checkBase = Join-Path $env:TEMP ("epf_ninja_check_" + [guid]::NewGuid().ToString('N'))
$logDir = Join-Path $env:TEMP ("epf_ninja_checklog_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

try {
	Write-Host "epf-precheck: stub IB + embed $sourceFile"
	$stubArgs = @(
		'-NoProfile', '-File', $stubScript,
		'-SourceDir', $sourceDir,
		'-V8Path', $v8,
		'-TempBasePath', $checkBase,
		'-EmbedSourceFile', $sourceFile
	)
	$stub = Start-Process -FilePath 'powershell.exe' -ArgumentList $stubArgs -NoNewWindow -Wait -PassThru
	if ($stub.ExitCode -ne 0) {
		Write-Host "Error: платформа не приняла исходники при подготовке проверки — сборка отменена" -ForegroundColor Red
		exit 1
	}

	$flags = @(Get-CheckFlags $checkList $contextList)
	$outFile = Join-Path $logDir 'check_log.txt'
	$a = @('DESIGNER', '/F', "`"$checkBase`"", '/CheckConfig') + $flags + @('/Out', "`"$outFile`"", '/DisableStartupDialogs')
	Write-Host "epf-precheck: 1cv8 $($a -join ' ')"
	$res = Invoke-PlatformProcess $v8 $a

	$lines = @()
	if (Test-Path $outFile) {
		$raw = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
		if ($raw) { $lines = @($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) }
	}

	if ($res.ExitCode -eq 0) {
		Write-Host "epf-precheck: OK (no issues)"
		exit 0
	}

	Write-Host "Error: платформа нашла проблемы в исходниках — сборка отменена" -ForegroundColor Red
	if ($lines.Count -eq 0) {
		Write-Host "  платформа вернула код $($res.ExitCode) без сообщений" -ForegroundColor Red
		if ($res.Output) { Write-Host $res.Output }
	}
	foreach ($l in $lines) {
		Write-Host "  $($l.TrimEnd())" -ForegroundColor Red
		$srcPath = Resolve-SourcePath $l $sourceDir
		if ($srcPath) { Write-Host "    -> $srcPath" -ForegroundColor Red }
	}
	exit 1
}
finally {
	if (Test-Path $checkBase) {
		Remove-Item -LiteralPath $checkBase -Recurse -Force -ErrorAction SilentlyContinue
	}
	if (Test-Path $logDir) {
		Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue
	}
}
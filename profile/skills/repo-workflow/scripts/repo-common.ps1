# Общие функции скиллов хранилища расширений 1С.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:RepoTypeFolders = @{
	'AccountingRegisters'            = 'РегистрБухгалтерии'
	'AccumulationRegisters'          = 'РегистрНакопления'
	'Bots'                           = 'Бот'
	'BusinessProcesses'              = 'БизнесПроцесс'
	'CalculationRegisters'           = 'РегистрРасчета'
	'Catalogs'                       = 'Справочник'
	'ChartsOfAccounts'               = 'ПланСчетов'
	'ChartsOfCalculationTypes'       = 'ПланВидовРасчета'
	'ChartsOfCharacteristicTypes'    = 'ПланВидовХарактеристик'
	'CommandGroups'                  = 'ГруппаКоманд'
	'CommonAttributes'               = 'ОбщийРеквизит'
	'CommonCommands'                 = 'ОбщаяКоманда'
	'CommonForms'                    = 'ОбщаяФорма'
	'CommonModules'                  = 'ОбщийМодуль'
	'CommonPictures'                 = 'ОбщаяКартинка'
	'CommonTemplates'                = 'ОбщийМакет'
	'Constants'                      = 'Константа'
	'DataProcessors'                 = 'Обработка'
	'DefinedTypes'                   = 'ОпределяемыйТип'
	'DocumentJournals'               = 'ЖурналДокументов'
	'DocumentNumerators'             = 'НумераторДокументов'
	'Documents'                      = 'Документ'
	'Enums'                          = 'Перечисление'
	'EventSubscriptions'             = 'ПодпискаНаСобытие'
	'ExchangePlans'                  = 'ПланОбмена'
	'ExternalDataSources'            = 'ВнешнийИсточникДанных'
	'FilterCriteria'                 = 'КритерийОтбора'
	'FunctionalOptions'              = 'ФункциональнаяОпция'
	'FunctionalOptionsParameters'    = 'ПараметрФункциональнойОпции'
	'HTTPServices'                   = 'HTTPСервис'
	'InformationRegisters'           = 'РегистрСведений'
	'IntegrationServices'            = 'СервисИнтеграции'
	'Interfaces'                     = 'Интерфейс'
	'Languages'                      = 'Язык'
	'Reports'                        = 'Отчет'
	'Roles'                          = 'Роль'
	'ScheduledJobs'                  = 'РегламентноеЗадание'
	'Sequences'                      = 'Последовательность'
	'SessionParameters'              = 'ПараметрСеанса'
	'SettingsStorages'               = 'ХранилищеНастроек'
	'StyleItems'                     = 'ЭлементСтиля'
	'Styles'                         = 'Стиль'
	'Subsystems'                     = 'Подсистема'
	'Tasks'                          = 'Задача'
	'WebServices'                    = 'WebСервис'
	'WSReferences'                   = 'WSСсылка'
	'XDTOPackages'                   = 'XDTOPackage'
}

function Get-RepoProjectRoot {
	$current = (Get-Location).Path
	while ($current) {
		$candidate = Join-Path $current 'repository.json'
		if (Test-Path -LiteralPath $candidate) {
			return $current
		}
		$parent = Split-Path $current -Parent
		if ($parent -eq $current) {
			break
		}
		$current = $parent
	}
	throw "Не найден repository.json. Запускай команду из корня проекта 1С."
}

function Get-RepoMap {
	param([string]$ProjectRoot)
	$path = Join-Path $ProjectRoot 'repository.json'
	$map = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
	if (-not $map.root) {
		throw "В repository.json нет поля root."
	}
	if (-not $map.user) {
		throw "В repository.json нет поля user."
	}
	if (-not $map.cfe) {
		throw "В repository.json нет секции cfe."
	}
	return $map
}

function Get-RepoStoragePath {
	param(
		$Map,
		[string]$ExtensionName
	)
	$folder = $Map.cfe.PSObject.Properties |
		Where-Object { $_.Name -eq $ExtensionName } |
		Select-Object -First 1
	if (-not $folder) {
		throw "Расширения '$ExtensionName' нет в repository.json — хранилище для него не используется."
	}
	$value = [string]$folder.Value
	if ([System.IO.Path]::IsPathRooted($value)) {
		return $value
	}
	return (Join-Path $Map.root $value)
}

function Get-RepoExtensionNameFromSrc {
	param(
		[string]$ProjectRoot,
		[string]$FolderName
	)
	$xmlPath = Join-Path $ProjectRoot "src\cfe\$FolderName\Configuration.xml"
	if (-not (Test-Path -LiteralPath $xmlPath)) {
		throw "Не найден $xmlPath"
	}
	$content = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
	$match = [regex]::Match($content, '(?s)<Properties>.*?<Name>([^<]+)</Name>')
	if (-not $match.Success) {
		throw "Не удалось прочитать <Name> из $xmlPath"
	}
	return $match.Groups[1].Value.Trim()
}

function Resolve-RepoTargetFromPath {
	param(
		[string]$ProjectRoot,
		[string]$InputPath
	)
	$full = $InputPath
	if (-not [System.IO.Path]::IsPathRooted($full)) {
		$full = Join-Path $ProjectRoot $full
	}
	$full = [System.IO.Path]::GetFullPath($full)
	$marker = '\src\cfe\'
	$idx = $full.ToLowerInvariant().IndexOf($marker)
	if ($idx -lt 0) {
		throw "Путь должен быть внутри src/cfe/<ИмяРасширения>/: $InputPath"
	}
	$after = $full.Substring($idx + $marker.Length)
	$parts = $after -split '[\\/]' | Where-Object { $_ }
	if ($parts.Count -lt 1) {
		throw "Не удалось определить расширение из пути: $InputPath"
	}
	$folderName = $parts[0]
	$extensionName = Get-RepoExtensionNameFromSrc -ProjectRoot $ProjectRoot -FolderName $folderName
	if ($parts.Count -eq 1 -or ($parts.Count -eq 2 -and $parts[1] -in @('Configuration.xml', 'ConfigDumpInfo.xml'))) {
		return [pscustomobject]@{
			ExtensionName = $extensionName
			FullName      = $null
			WholeExtension = $true
		}
	}
	$typeFolder = $parts[1]
	if ($typeFolder -eq 'Ext') {
		return [pscustomobject]@{
			ExtensionName = $extensionName
			FullName      = $null
			WholeExtension = $true
		}
	}
	$typeName = $script:RepoTypeFolders[$typeFolder]
	if (-not $typeName) {
		throw "Неизвестный тип метаданных '$typeFolder' в пути $InputPath"
	}
	if ($parts.Count -lt 3) {
		throw "В пути нет имени объекта: $InputPath"
	}
	$objectName = $parts[2]
	if ($objectName -like '*.xml') {
		$objectName = [System.IO.Path]::GetFileNameWithoutExtension($objectName)
	}
	return [pscustomobject]@{
		ExtensionName  = $extensionName
		FullName       = "$typeName.$objectName"
		WholeExtension = $false
	}
}

function ConvertTo-RepoXmlAttribute {
	param([string]$Value)
	return (($Value -replace '&', '&amp;') -replace '"', '&quot;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function Write-RepoObjectsFile {
	param(
		[string]$FullName,
		[switch]$WholeExtension,
		[bool]$Recursive = $true,
		[switch]$SubsystemDeep
	)
	$include = if ($Recursive) { 'true' } else { 'false' }
	if ($WholeExtension) {
		$xml = @"
<Objects xmlns="http://v8.1c.ru/8.3/config/objects" version="1.0">
  <Configuration includeChildObjects="$include"/>
</Objects>
"@
	} else {
		$escaped = ConvertTo-RepoXmlAttribute $FullName
		$inner = ''
		if ($SubsystemDeep -and $FullName.StartsWith('Подсистема.')) {
			$inner = "`n    <Subsystem includeObjectsFromSubordinateSubsystems=`"$include`"/>"
		}
		$xml = @"
<Objects xmlns="http://v8.1c.ru/8.3/config/objects" version="1.0">
  <Object fullName="$escaped" includeChildObjects="$include">$inner
  </Object>
</Objects>
"@
	}
	$dir = Join-Path $env:TEMP '1c-cfe-repo'
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
	$file = Join-Path $dir ("objects-{0}.xml" -f [guid]::NewGuid().ToString('N'))
	$utf8Bom = New-Object System.Text.UTF8Encoding $true
	[System.IO.File]::WriteAllText($file, $xml.Trim() + "`n", $utf8Bom)
	return $file
}

function Get-RepoVrunnerMain {
	param([string]$ProjectRoot)
	$candidates = New-Object System.Collections.Generic.List[string]
	$vrunnerCmd = Get-Command vrunner -ErrorAction SilentlyContinue
	if ($vrunnerCmd) {
		$binDir = [System.IO.Path]::GetDirectoryName($vrunnerCmd.Source)
		$candidates.Add([System.IO.Path]::GetFullPath((Join-Path $binDir '..\lib\vanessa-runner\src\main.os')))
	}
	$candidates.Add((Join-Path $env:LOCALAPPDATA 'ovm\current\lib\vanessa-runner\src\main.os'))
	foreach ($main in $candidates) {
		if (Test-Path -LiteralPath $main) {
			return $main
		}
	}
	throw "Не найден vanessa-runner 3 (main.os). Проверь PATH: vrunner --version"
}

function ConvertTo-RepoProcessArgument {
	param([string]$Value)
	if ($null -eq $Value) {
		return '""'
	}
	if ($Value -notmatch '[ \t"]') {
		return $Value
	}
	$escaped = ($Value -replace '\\', '\\') -replace '"', '\"'
	return '"' + $escaped + '"'
}

function Write-RepoLoadListFile {
	param([string]$SrcDir)
	$dir = Join-Path $env:TEMP '1c-cfe-repo'
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
	$file = Join-Path $dir ("load-list-{0}.txt" -f [guid]::NewGuid().ToString('N'))
	$srcFull = [System.IO.Path]::GetFullPath($SrcDir)
	$lines = New-Object System.Collections.Generic.List[string]
	Get-ChildItem -LiteralPath $srcFull -Recurse -File | ForEach-Object {
		if ($_.Name -eq 'ConfigDumpInfo.xml') {
			return
		}
		$rel = $_.FullName.Substring($srcFull.Length).TrimStart('\', '/')
		$lines.Add(($rel -replace '/', '\'))
	}
	if ($lines.Count -eq 0) {
		throw "В каталоге нет файлов для загрузки: $SrcDir"
	}
	$utf8Bom = New-Object System.Text.UTF8Encoding $true
	[System.IO.File]::WriteAllText($file, (($lines | Sort-Object) -join "`r`n") + "`r`n", $utf8Bom)
	return $file
}

function Get-RepoDesignerFailureMessage {
	param(
		[string]$CombinedOutput,
		[int]$ExitCode
	)

	if ($ExitCode -ne 0) {
		return "Конфигуратор завершился с кодом $ExitCode"
	}

	if ($CombinedOutput -match '(?m)^КРИТИЧНАЯОШИБКА\b' -or $CombinedOutput -match '(?m)^ОШИБКА\s*-') {
		return 'vrunner сообщил об ошибке выполнения'
	}

	$platformLines = New-Object System.Collections.Generic.List[string]
	foreach ($line in ($CombinedOutput -split "`r?`n")) {
		$trimmed = $line.TrimEnd()
		if (-not $trimmed) {
			continue
		}
		if ($trimmed -match '^(ИНФОРМАЦИЯ|ОТЛАДКА|ПРЕДУПРЕЖДЕНИЕ|КРИТИЧНАЯОШИБКА|ОШИБКА)\s*-') {
			$trimmed = ($trimmed -replace '^(ИНФОРМАЦИЯ|ОТЛАДКА|ПРЕДУПРЕЖДЕНИЕ|КРИТИЧНАЯОШИБКА|ОШИБКА)\s*-\s*', '').Trim()
		}
		if (-not $trimmed) {
			continue
		}
		if ($trimmed -eq 'Вывод платформы:' -or $trimmed -eq 'Выполняю команду Конфигуратора' -or $trimmed -eq 'Конфигуратор завершён') {
			continue
		}
		[void]$platformLines.Add($trimmed)
	}

	if ($platformLines.Count -eq 0) {
		return $null
	}

	$platformText = ($platformLines -join "`n")
	$errorPatterns = @(
		'(?im)^\s*Ошибка\b',
		'(?im)отсутствующие в обеих конфигурациях',
		'(?im)захвачен[^\n]{0,40}друг(им|ого)\s+пользовател',
		'(?im)не\s+удалось',
		'(?im)Operation\s+cancelled',
		'(?im)Exception'
	)
	foreach ($pattern in $errorPatterns) {
		if ($platformText -match $pattern) {
			$snippet = ($platformLines | Select-Object -First 6) -join '; '
			if ($snippet.Length -gt 400) {
				$snippet = $snippet.Substring(0, 400) + '...'
			}
			return "ошибка платформы: $snippet"
		}
	}

	return $null
}

function Invoke-RepoInfobaseUpdate {
	param(
		[string]$ProjectRoot,
		[string]$ExtensionName
	)
	$oscript = (Get-Command oscript -ErrorAction Stop).Source
	$main = Get-RepoVrunnerMain -ProjectRoot $ProjectRoot
	$parts = @(
		(ConvertTo-RepoProcessArgument $main),
		'infobase',
		'update',
		(ConvertTo-RepoProcessArgument "--target=$ExtensionName"),
		'--dynamic'
	)
	$argumentLine = $parts -join ' '
	Write-Host "vrunner infobase update --target=`"$ExtensionName`" --dynamic"
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $oscript
	$info.Arguments = $argumentLine
	$info.WorkingDirectory = $ProjectRoot
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$proc = New-Object System.Diagnostics.Process
	$proc.StartInfo = $info
	[void]$proc.Start()
	$stdout = $proc.StandardOutput.ReadToEnd()
	$stderr = $proc.StandardError.ReadToEnd()
	$proc.WaitForExit()
	$combinedOutput = (($stdout, $stderr) | Where-Object { $_ }) -join "`n"
	if ($stdout) { Write-Host $stdout }
	if ($stderr) { Write-Host $stderr }

	if ($proc.ExitCode -ne 0) {
		$snippet = ($combinedOutput -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 4) -join '; '
		if ($snippet -match 'уже работает конфигуратор|already opened|Configuration lock') {
			throw "Не удалось обновить конфигурацию БД: база заблокирована открытым Конфигуратором. Закройте Конфигуратор для этой ИБ и повторите."
		}
		throw "infobase update завершился с кодом $($proc.ExitCode). $snippet"
	}
}

function Get-RepoWebTestConfig {
	param([string]$ProjectRoot)
	$path = Join-Path $ProjectRoot 'tools\web-test\smoke.config.json'
	if (-not (Test-Path -LiteralPath $path)) {
		return $null
	}
	return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-RepoWebTestScript {
	param(
		$Config,
		[string]$ProjectRoot,
		[string]$ExtensionName
	)
	$webTestDir = Join-Path $ProjectRoot 'tools\web-test'
	$rel = $null
	if ($Config.extensions.PSObject.Properties.Name -contains $ExtensionName) {
		$rel = [string]$Config.extensions.$ExtensionName
	} elseif ($Config.defaultScript) {
		$rel = [string]$Config.defaultScript
		Write-Host "web-test: сценарий по умолчанию для расширения $ExtensionName"
	}
	if (-not $rel) {
		return $null
	}
	$scriptPath = Join-Path $webTestDir ($rel -replace '/', '\')
	if (-not (Test-Path -LiteralPath $scriptPath)) {
		throw "web-test: не найден сценарий $scriptPath"
	}
	return $scriptPath
}

function Invoke-RepoWebTestSmoke {
	param(
		[string]$ProjectRoot,
		[string]$ExtensionName
	)
	$config = Get-RepoWebTestConfig -ProjectRoot $ProjectRoot
	if (-not $config) {
		Write-Host 'web-test: smoke.config.json не найден — пропуск UI-проверки.'
		return
	}
	if ($config.enabled -eq $false) {
		Write-Host 'web-test: disabled в smoke.config.json — пропуск.'
		return
	}
	$webUrl = [string]$config.webUrl
	if (-not $webUrl) {
		throw 'web-test: в smoke.config.json не задан webUrl.'
	}
	$scriptPath = Resolve-RepoWebTestScript -Config $config -ProjectRoot $ProjectRoot -ExtensionName $ExtensionName
	if (-not $scriptPath) {
		Write-Host "web-test: нет сценария для $ExtensionName — пропуск."
		return
	}
	$runMjs = Join-Path $env:USERPROFILE '.cursor\skills\web-test\scripts\run.mjs'
	if (-not (Test-Path -LiteralPath $runMjs)) {
		throw "web-test: не найден $runMjs (skill web-test)."
	}
	$timeoutMin = 15
	if ($config.timeoutMin) {
		$timeoutMin = [int]$config.timeoutMin
	}
	Write-Host "web-test smoke: $webUrl"
	Write-Host "  сценарий: $scriptPath"
	$node = (Get-Command node -ErrorAction Stop).Source
	$args = @(
		$runMjs,
		'run',
		$webUrl,
		$scriptPath,
		"--timeout-min=$timeoutMin",
		'--no-record'
	)
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $node
	$info.Arguments = ($args | ForEach-Object { ConvertTo-RepoProcessArgument $_ }) -join ' '
	$info.WorkingDirectory = $ProjectRoot
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$proc = New-Object System.Diagnostics.Process
	$proc.StartInfo = $info
	[void]$proc.Start()
	$stdout = $proc.StandardOutput.ReadToEnd()
	$stderr = $proc.StandardError.ReadToEnd()
	$proc.WaitForExit()
	if ($stdout) { Write-Host $stdout }
	if ($stderr) { Write-Host $stderr }
	if ($proc.ExitCode -ne 0) {
		throw "web-test smoke завершился с кодом $($proc.ExitCode). Проверьте веб-публикацию ($webUrl) и сценарий."
	}
	if ($stdout -notmatch '"smoke"\s*:\s*"ok"') {
		Write-Host 'web-test: предупреждение — в выводе нет smoke: ok (сценарий мог завершиться без маркера).'
	}
	Write-Host 'web-test smoke: OK'
}

function Invoke-RepoDesigner {
	param(
		[string]$ProjectRoot,
		[string]$StoragePath,
		[string]$StorageUser,
		[string]$Additional,
		[switch]$InlineStorage
	)
	# Через oscript.exe и ProcessStartInfo: vrunner.bat/%* и вложенные кавычки ломают -comment.
	# IB и платформа — из autumn-properties.json (CWD = корень проекта).
	$oscript = (Get-Command oscript -ErrorAction Stop).Source
	$main = Get-RepoVrunnerMain -ProjectRoot $ProjectRoot
	# --storage-name у designer цепляет хранилище к основной конфигурации.
	# Для LoadConfigFromFiles расширения F/N должны идти в --additional рядом с -Extension.
	$parts = @(
		(ConvertTo-RepoProcessArgument $main),
		'run',
		'designer'
	)
	if (-not $InlineStorage) {
		$parts += @(
			(ConvertTo-RepoProcessArgument "--storage-name=$StoragePath"),
			(ConvertTo-RepoProcessArgument "--storage-user=$StorageUser")
		)
	}
	$parts += @(
		'--additional',
		(ConvertTo-RepoProcessArgument $Additional)
	)
	$argumentLine = $parts -join ' '
	if ($InlineStorage) {
		Write-Host "vrunner run designer (хранилище в --additional)"
	} else {
		Write-Host "vrunner run designer --storage-name=`"$StoragePath`" --storage-user=`"$StorageUser`""
	}
	Write-Host "  --additional=$Additional"
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $oscript
	$info.Arguments = $argumentLine
	$info.WorkingDirectory = $ProjectRoot
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$proc = New-Object System.Diagnostics.Process
	$proc.StartInfo = $info
	[void]$proc.Start()
	$stdout = $proc.StandardOutput.ReadToEnd()
	$stderr = $proc.StandardError.ReadToEnd()
	$proc.WaitForExit()
	$combinedOutput = (($stdout, $stderr) | Where-Object { $_ }) -join "`n"
	if ($stdout) { Write-Host $stdout }
	if ($stderr) { Write-Host $stderr }

	$failure = Get-RepoDesignerFailureMessage -CombinedOutput $combinedOutput -ExitCode $proc.ExitCode
	if ($failure) {
		throw $failure
	}
}

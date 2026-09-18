# Операции хранилища расширений 1С. Синтакс-контроль не запускает.
param(
	[Parameter(Mandatory = $true)]
	[ValidateSet('lock', 'commit', 'unlock', 'update', 'load', 'add-user')]
	[string]$Action,

	[string]$Path,
	[string]$Extension,
	[string]$FullName,
	[switch]$WholeExtension,
	[bool]$Recursive = $true,
	[string]$Comment,
	[string]$Version,
	[string]$NewUser,
	[ValidateSet('ReadOnly', 'LockObjects', 'ManageConfigurationVersions', 'Administration')]
	[string]$Role = 'LockObjects',
	[switch]$KeepLocked,
	[switch]$SkipWebTest
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'repo-common.ps1'
. $common

$projectRoot = Get-RepoProjectRoot
$map = Get-RepoMap -ProjectRoot $projectRoot

$target = $null
if ($Path) {
	$target = Resolve-RepoTargetFromPath -ProjectRoot $projectRoot -InputPath $Path
} elseif ($Extension) {
	$srcName = $Extension
	$configXml = Join-Path $projectRoot "src\cfe\$Extension\Configuration.xml"
	if (Test-Path -LiteralPath $configXml) {
		$srcName = Get-RepoExtensionNameFromSrc -ProjectRoot $projectRoot -FolderName $Extension
	}
	$target = [pscustomobject]@{
		ExtensionName  = $srcName
		FullName       = $FullName
		WholeExtension = [bool]($WholeExtension -or -not $FullName)
	}
} else {
	throw "Укажи -Path к файлу/каталогу в src/cfe или -Extension."
}

$storagePath = Get-RepoStoragePath -Map $map -ExtensionName $target.ExtensionName
$storageUser = [string]$map.user
if (-not (Test-Path -LiteralPath $storagePath)) {
	throw "Каталог хранилища не найден: $storagePath"
}

Write-Host "Расширение: $($target.ExtensionName)"
Write-Host "Хранилище:  $storagePath"
Write-Host "Пользователь хранилища: $storageUser"

if ($Action -eq 'add-user') {
	if (-not $NewUser) {
		throw "Для add-user нужен -NewUser."
	}
	$admin = [string]$map.adminUser
	if (-not $admin) {
		throw "В repository.json нет adminUser."
	}
	$rights = $Role
	$addUser = "/ConfigurationRepositoryAddUser -User `"$NewUser`" -Rights $rights -Extension `"$($target.ExtensionName)`""
	# Создание пользователя идёт от имени администратора хранилища.
	Invoke-RepoDesigner -ProjectRoot $projectRoot -StoragePath $storagePath -StorageUser $admin -Additional $addUser
	Write-Host "Пользователь '$NewUser' создан в хранилище $($target.ExtensionName) с ролью $rights."
	return
}

if ($Action -eq 'load') {
	$srcDir = Join-Path $projectRoot "src\cfe\$($target.ExtensionName)"
	if (-not (Test-Path -LiteralPath (Join-Path $srcDir 'Configuration.xml'))) {
		throw "Нет исходников расширения: $srcDir"
	}
	# Полная LoadConfigFromFiles при хранилище запрещена. Только частичная: -listFile по захваченным.
	# F/N в --additional: --storage-name у designer садится на основную конфигурацию.
	$listFile = Write-RepoLoadListFile -SrcDir $srcDir
	try {
		$name = $target.ExtensionName
		# vrunner 3: --additional не должен начинаться с «-Extension» — CLI воспримет как свой ключ.
		# Префикс /DisplayAllFunctions нейтрален для designer и не мешает LoadConfigFromFiles.
		$additional = "/DisplayAllFunctions -Extension `"$name`" /ConfigurationRepositoryF `"$storagePath`" /ConfigurationRepositoryN `"$storageUser`" /LoadConfigFromFiles `"$srcDir`" -Extension `"$name`" -listFile `"$listFile`" -format Hierarchical -updateConfigDumpInfo"
		Invoke-RepoDesigner -ProjectRoot $projectRoot -StoragePath $storagePath -StorageUser $storageUser -Additional $additional -InlineStorage
	} finally {
		if (Test-Path -LiteralPath $listFile) {
			Remove-Item -LiteralPath $listFile -Force -ErrorAction SilentlyContinue
		}
	}
	Invoke-RepoInfobaseUpdate -ProjectRoot $projectRoot -ExtensionName $target.ExtensionName
	if (-not $SkipWebTest) {
		Invoke-RepoWebTestSmoke -ProjectRoot $projectRoot -ExtensionName $target.ExtensionName
	} else {
		Write-Host 'web-test: пропуск (-SkipWebTest).'
	}
	Write-Host "Готово: load + update, расширение $($target.ExtensionName) из $srcDir"
	return
}

$objectsFile = Write-RepoObjectsFile `
	-FullName $target.FullName `
	-WholeExtension:([bool]$target.WholeExtension) `
	-Recursive $Recursive `
	-SubsystemDeep:($Recursive -and $target.FullName -like 'Подсистема.*')

try {
	$extArg = "-Extension $($target.ExtensionName)"
	$objectsArg = "-Objects $objectsFile"
	switch ($Action) {
		'lock' {
			$additional = "/ConfigurationRepositoryLock $objectsArg $extArg"
		}
		'unlock' {
			$additional = "/ConfigurationRepositoryUnLock $objectsArg $extArg"
		}
		'commit' {
			if (-not $Comment -or -not $Comment.Trim()) {
				throw "Для помещения нужен -Comment."
			}
			$safeComment = ($Comment.Trim() -replace '"', "'")
			$keep = ''
			if ($KeepLocked) {
				$keep = '-keepLocked'
			}
			$additional = "/ConfigurationRepositoryCommit $objectsArg -comment `"$safeComment`" $keep $extArg"
		}
		'update' {
			$ver = ''
			if ($Version) {
				$ver = "-v $Version"
			}
			$additional = "/ConfigurationRepositoryUpdateCfg $objectsArg $ver $extArg"
		}
	}
	Invoke-RepoDesigner -ProjectRoot $projectRoot -StoragePath $storagePath -StorageUser $storageUser -Additional $additional.Trim()
	if ($target.WholeExtension) {
		Write-Host "Готово: $Action, расширение $($target.ExtensionName) целиком, recursive=$Recursive"
	} else {
		Write-Host "Готово: $Action $($target.FullName), recursive=$Recursive"
	}
} finally {
	if (Test-Path -LiteralPath $objectsFile) {
		Remove-Item -LiteralPath $objectsFile -Force -ErrorAction SilentlyContinue
	}
}

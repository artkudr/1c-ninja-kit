# move-predefined v0.1.0 — перенос предопределённых элементов 1С без смены id
# Source: 1c-ninja-kit (skills/skill-move-predefined)
<#
.SYNOPSIS
    Переносит существующий предопределённый элемент в другую папку Ext/Predefined.xml.

.DESCRIPTION
    Меняет только положение узла <Item>: id, код, наименование и поддерево
    сохраняются. Опустевший ChildItems удаляется, разметка приводится к
    канонической (табы, переводы строк исходника, UTF-8 BOM, без пробела перед />).

.PARAMETER ObjectPath
    Каталог объекта (Catalogs/Имя) или его XML-файл (Catalogs/Имя.xml).

.PARAMETER Move
    Inline-перенос: "Элемент >> Папка". Несколько — через ";;".
    В корень: "Элемент >> /".

.PARAMETER DefinitionFile
    JSON с переносами. Формы: { "moves": [...] }, { "move": { "predefined": [...] } }
    или массив объектов { "item": "...", "folder": "..." }.

.PARAMETER NoValidate
    Не запускать meta-validate после правки.

.EXAMPLE
    move-predefined.ps1 -ObjectPath "Catalogs/Спр" -Move "Настройка >> Группа"

.EXAMPLE
    move-predefined.ps1 -ObjectPath "Catalogs/Спр.xml" -Move "A >> Группа ;; B >> /"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ObjectPath,

    [string]$Move,

    [string]$DefinitionFile,

    [switch]$NoValidate
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Die([string]$Message) {
    [Console]::Error.WriteLine("[ERROR] $Message")
    exit 1
}

function Info([string]$Message) {
    Write-Host "[INFO] $Message"
}

function Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

# --- Разбор переносов -------------------------------------------------------

function ConvertFrom-MoveString([string]$Text) {
    $parts = $Text -split '>>', 2
    if ($parts.Count -ne 2) {
        Die "Invalid move format (expected 'Item >> Folder'): $Text"
    }
    $itemName = $parts[0].Trim()
    $folderRaw = $parts[1].Trim()
    if (-not $itemName) {
        Die "Invalid move format: empty item name in '$Text'"
    }
    $folder = if ($folderRaw -in @('', '/', '\', 'root', 'корень')) { $null } else { $folderRaw }
    return [pscustomobject]@{ Item = $itemName; Folder = $folder }
}

function ConvertFrom-MoveEntry($Entry) {
    if ($Entry -is [string]) {
        return ConvertFrom-MoveString $Entry
    }

    $itemName = [string]$Entry.item
    if (-not $itemName) {
        Die "Move entry must have 'item'"
    }

    $hasFolder = $false
    $folder = $null
    foreach ($key in @('folder', 'into', 'target', 'папка')) {
        if ($Entry.PSObject.Properties.Name -contains $key) {
            $hasFolder = $true
            $raw = $Entry.$key
            $folder = if ($null -eq $raw -or "$raw".Trim() -in @('', '/', '\', 'root', 'корень')) { $null } else { "$raw".Trim() }
            break
        }
    }
    if (-not $hasFolder) {
        Die "Move entry for '$itemName' must have 'folder' (use null or '/' for root)"
    }
    return [pscustomobject]@{ Item = $itemName; Folder = $folder }
}

$moves = New-Object System.Collections.ArrayList

if ($Move -and $DefinitionFile) {
    Die "Use either -Move or -DefinitionFile, not both"
}

if ($Move) {
    foreach ($part in ($Move -split ';;')) {
        $text = $part.Trim()
        if (-not $text) { continue }
        [void]$moves.Add((ConvertFrom-MoveString $text))
    }
}
elseif ($DefinitionFile) {
    if (-not (Test-Path -LiteralPath $DefinitionFile)) {
        Die "DefinitionFile not found: $DefinitionFile"
    }
    try {
        $jsonText = Get-Content -LiteralPath $DefinitionFile -Raw -Encoding UTF8
        $json = $jsonText | ConvertFrom-Json
    }
    catch {
        Die "Invalid JSON in DefinitionFile: $($_.Exception.Message)"
    }

    $entries = $null
    if ($json -is [array]) {
        $entries = $json
    }
    elseif ($json.PSObject.Properties.Name -contains 'moves') {
        $entries = $json.moves
    }
    elseif ($json.PSObject.Properties.Name -contains 'move' -and $json.move -and $json.move.PSObject.Properties.Name -contains 'predefined') {
        $entries = $json.move.predefined
    }
    elseif ($json.PSObject.Properties.Name -contains 'predefined') {
        $entries = $json.predefined
    }
    else {
        Die "DefinitionFile must contain 'moves', 'move.predefined' or 'predefined'"
    }

    foreach ($entry in @($entries)) {
        [void]$moves.Add((ConvertFrom-MoveEntry $entry))
    }
}
else {
    Die "Specify -Move or -DefinitionFile"
}

if ($moves.Count -eq 0) {
    Die "No moves specified"
}

# --- Пути -------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $ObjectPath)) {
    Die "ObjectPath not found: $ObjectPath"
}
$resolved = (Resolve-Path -LiteralPath $ObjectPath).ProviderPath

if (Test-Path -LiteralPath $resolved -PathType Leaf) {
    if ([System.IO.Path]::GetFileName($resolved) -ieq 'Predefined.xml') {
        $predefPath = $resolved
        $objDir = Split-Path -Parent (Split-Path -Parent $resolved)
    }
    else {
        $objDir = Join-Path (Split-Path -Parent $resolved) ([System.IO.Path]::GetFileNameWithoutExtension($resolved))
        $predefPath = Join-Path (Join-Path $objDir 'Ext') 'Predefined.xml'
    }
}
else {
    $objDir = $resolved
    $predefPath = Join-Path (Join-Path $objDir 'Ext') 'Predefined.xml'
}

if (-not (Test-Path -LiteralPath $predefPath)) {
    Die "Predefined.xml not found: $predefPath"
}

# --- Чтение XML -------------------------------------------------------------

$bytes = [System.IO.File]::ReadAllBytes($predefPath)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$offset = if ($hasBom) { 3 } else { 0 }
$text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)

$newline = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } else { "`r`n" }

$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
try {
    $doc.LoadXml($text)
}
catch {
    Die "Invalid XML in ${predefPath}: $($_.Exception.Message)"
}

$root = $doc.DocumentElement
if (-not $root -or $root.LocalName -ne 'PredefinedData') {
    Die "Unexpected root element in ${predefPath}: expected PredefinedData"
}

$script:doc = $doc
$script:root = $root
$script:newline = $newline

# --- Работа с DOM -----------------------------------------------------------

function Test-Ws($Node) {
    return ($null -ne $Node -and ($Node.NodeType -eq 'Whitespace' -or $Node.NodeType -eq 'SignificantWhitespace'))
}

function Get-ElementChildren($Node) {
    return @($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
}

function Get-ItemName($ItemNode) {
    foreach ($child in $ItemNode.ChildNodes) {
        if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'Name') {
            return $child.InnerText.Trim()
        }
    }
    return $null
}

function Get-ItemIsFolder($ItemNode) {
    foreach ($child in $ItemNode.ChildNodes) {
        if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'IsFolder') {
            return ($child.InnerText.Trim() -ieq 'true')
        }
    }
    return $false
}

function Get-ItemChildItems($ItemNode) {
    foreach ($child in $ItemNode.ChildNodes) {
        if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'ChildItems') {
            return $child
        }
    }
    return $null
}

function Get-AllItems {
    param($Container, $List)

    foreach ($child in $Container.ChildNodes) {
        if ($child.NodeType -ne 'Element' -or $child.LocalName -ne 'Item') { continue }
        $name = Get-ItemName $child
        if (-not $name) {
            Die "Predefined item without <Name> in $predefPath"
        }
        [void]$List.Add([pscustomobject]@{
            Node      = $child
            Name      = $name
            IsFolder  = (Get-ItemIsFolder $child)
            Container = $Container
        })
        $childItems = Get-ItemChildItems $child
        if ($childItems) {
            Get-AllItems -Container $childItems -List $List
        }
    }
}

function Find-Item([string]$Name) {
    $all = New-Object System.Collections.ArrayList
    Get-AllItems -Container $script:root -List $all
    $hits = @($all | Where-Object { $_.Name -eq $Name })
    if ($hits.Count -eq 0) {
        Die "Predefined item '$Name' not found"
    }
    if ($hits.Count -gt 1) {
        Die "Predefined item '$Name' is ambiguous: $($hits.Count) items with this name"
    }
    return $hits[0]
}

function Get-ItemLevel($ItemNode) {
    $level = 0
    $current = $ItemNode.ParentNode
    while ($current) {
        if ($current.NodeType -eq 'Element' -and $current.LocalName -eq 'Item') {
            $level++
        }
        $current = $current.ParentNode
    }
    return $level
}

function Test-Descendant($Node, $Ancestor) {
    $current = $Node.ParentNode
    while ($current) {
        if ([object]::ReferenceEquals($current, $Ancestor)) { return $true }
        $current = $current.ParentNode
    }
    return $false
}

function Remove-NodeWithWhitespace($Node) {
    $parent = $Node.ParentNode
    if (-not $parent) { return }
    $previous = $Node.PreviousSibling
    if (Test-Ws $previous) {
        [void]$parent.RemoveChild($previous)
    }
    [void]$parent.RemoveChild($Node)
}

function Set-SubtreeIndent($Node, [int]$Indent) {
    $children = @(Get-ElementChildren $Node)
    if ($children.Count -eq 0) { return }

    foreach ($child in @($Node.ChildNodes)) {
        if (Test-Ws $child) {
            [void]$Node.RemoveChild($child)
        }
    }

    $children = @(Get-ElementChildren $Node)
    foreach ($child in $children) {
        $ws = $script:doc.CreateWhitespace("$($script:newline)" + ("`t" * ($Indent + 1)))
        [void]$Node.InsertBefore($ws, $child)
    }
    $closing = $script:doc.CreateWhitespace("$($script:newline)" + ("`t" * $Indent))
    [void]$Node.AppendChild($closing)

    foreach ($child in $children) {
        Set-SubtreeIndent $child ($Indent + 1)
    }
}

function Ensure-ChildItems($FolderNode) {
    $childItems = Get-ItemChildItems $FolderNode
    if ($childItems) { return $childItems }

    $childItems = $script:doc.CreateElement('ChildItems', $script:root.NamespaceURI)
    [void]$FolderNode.AppendChild($childItems)
    return $childItems
}

function Insert-Item($Container, $Node, [int]$Indent) {
    $lastWs = $null
    foreach ($child in $Container.ChildNodes) {
        if (Test-Ws $child) { $lastWs = $child }
    }

    $ws = $script:doc.CreateWhitespace("$($script:newline)" + ("`t" * $Indent))
    if ($lastWs) {
        [void]$Container.InsertBefore($ws, $lastWs)
        [void]$Container.InsertBefore($Node, $lastWs)
    }
    else {
        [void]$Container.AppendChild($ws)
        [void]$Container.AppendChild($Node)
        $closing = $script:doc.CreateWhitespace("$($script:newline)" + ("`t" * ($Indent - 1)))
        [void]$Container.AppendChild($closing)
    }

    Set-SubtreeIndent $Node $Indent
}

# --- Переносы ---------------------------------------------------------------

$moved = 0

foreach ($moveSpec in $moves) {
    $item = Find-Item $moveSpec.Item

    $folder = $null
    $targetContainer = $null
    $targetLevel = 0
    $targetLabel = 'корень'

    if ($null -eq $moveSpec.Folder) {
        $targetContainer = $script:root
        $targetLevel = 0
    }
    else {
        $folder = Find-Item $moveSpec.Folder
        if ([object]::ReferenceEquals($folder.Node, $item.Node)) {
            Die "Cannot move '$($moveSpec.Item)' into itself"
        }
        if (-not $folder.IsFolder) {
            Die "Predefined '$($moveSpec.Folder)' is not a folder (IsFolder=false)"
        }
        if (Test-Descendant $folder.Node $item.Node) {
            Die "Cannot move '$($moveSpec.Item)' into its own descendant '$($moveSpec.Folder)'"
        }
        $targetLabel = $moveSpec.Folder
        $targetLevel = (Get-ItemLevel $folder.Node) + 1
        $targetContainer = Get-ItemChildItems $folder.Node
    }

    $sourceContainer = $item.Node.ParentNode
    $alreadyThere = $false
    if ($null -eq $moveSpec.Folder) {
        $alreadyThere = [object]::ReferenceEquals($sourceContainer, $script:root)
    }
    else {
        if ($null -ne $targetContainer) {
            $alreadyThere = [object]::ReferenceEquals($sourceContainer, $targetContainer)
        }
    }
    if ($alreadyThere) {
        Info "Predefined '$($moveSpec.Item)' already in '$targetLabel', skipping"
        continue
    }

    $indent = 1 + 2 * $targetLevel

    if ($null -ne $moveSpec.Folder -and $null -eq $targetContainer) {
        $targetContainer = Ensure-ChildItems $folder.Node
        $folderIndent = 1 + 2 * (Get-ItemLevel $folder.Node)
        Set-SubtreeIndent $folder.Node $folderIndent
    }

    Remove-NodeWithWhitespace $item.Node

    if ($sourceContainer.LocalName -eq 'ChildItems' -and (Get-ElementChildren $sourceContainer).Count -eq 0) {
        Remove-NodeWithWhitespace $sourceContainer
    }

    Insert-Item $targetContainer $item.Node $indent
    Info "Moved predefined '$($moveSpec.Item)' -> '$targetLabel'"
    $moved++
}

if ($moved -eq 0) {
    Write-Host ""
    Write-Host "No changes." -ForegroundColor Yellow
    exit 0
}

# --- Сохранение -------------------------------------------------------------

$settings = New-Object System.Xml.XmlWriterSettings
$settings.Encoding = New-Object System.Text.UTF8Encoding($true)
$settings.Indent = $false
$settings.NewLineHandling = [System.Xml.NewLineHandling]::None

$memory = New-Object System.IO.MemoryStream
$writer = [System.Xml.XmlWriter]::Create($memory, $settings)
$doc.Save($writer)
$writer.Flush()
$writer.Close()
$outputBytes = $memory.ToArray()
$memory.Close()

$outputText = [System.Text.Encoding]::UTF8.GetString($outputBytes)
if ($outputText.Length -gt 0 -and $outputText[0] -eq [char]0xFEFF) {
    $outputText = $outputText.Substring(1)
}
$outputText = $outputText.Replace('encoding="utf-8"', 'encoding="UTF-8"')
$outputText = [regex]::Replace($outputText, '(?s)<!\[CDATA\[.*?\]\]>|<!--.*?-->|(?<=\S) />', {
    param($match)
    if ($match.Value -eq ' />') { '/>' } else { $match.Value }
})
$outputText = $outputText.TrimEnd("`r`n".ToCharArray())

[System.IO.File]::WriteAllText($predefPath, $outputText, (New-Object System.Text.UTF8Encoding($true)))
Info "Saved predefined data -> $predefPath"

# --- Валидация --------------------------------------------------------------

if (-not $NoValidate) {
    $validateScript = $null
    $probes = @(
        (Join-Path $PSScriptRoot '..\..\..\..\meta-validate\scripts\meta-validate.ps1'),
        (Join-Path $env:USERPROFILE '.config\opencode\skills\meta-validate\scripts\meta-validate.ps1')
    )
    foreach ($probe in $probes) {
        $probePath = [System.IO.Path]::GetFullPath($probe)
        if (Test-Path -LiteralPath $probePath) {
            $validateScript = $probePath
            break
        }
    }

    if ($validateScript) {
        Write-Host ""
        Write-Host "--- Running meta-validate ---" -ForegroundColor DarkGray
        & powershell.exe -NoProfile -File $validateScript -ObjectPath $objDir
        if ($LASTEXITCODE -ne 0) {
            Warn "meta-validate returned exit code $LASTEXITCODE"
        }
    }
    else {
        Warn "meta-validate not found, validation skipped"
    }
}

# --- Итог -------------------------------------------------------------------

Write-Host ""
Write-Host "=== move-predefined summary ===" -ForegroundColor Green
Write-Host "  Object: $objDir"
Write-Host "  Moved:  $moved"
exit 0

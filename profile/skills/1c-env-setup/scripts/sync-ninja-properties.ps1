#Requires -Version 5.1
<#
.SYNOPSIS
    Syncs the controlled (mirrored) properties of a bootstrap extension with the
    configuration it extends.

.DESCRIPTION
    A source-dumped configuration extension carries values that the platform requires to
    match the extended configuration:
      * Configuration.xml / ConfigurationExtensionCompatibilityMode
      * Configuration.xml / InterfaceCompatibilityMode
      * Languages/<lang>.xml / ExtendedConfigurationObject  (uuid of the adopted language)

    A bootstrap extension copied from another project (or from the kit) keeps the values of
    ITS source configuration, and cfe_load then fails with:
      "NinjaLive: Значение контролируемого свойства ... не совпадает со значением в
       расширяемой конфигурации"

    There is no vrunner / MCP command for this in the current stack, and the platform only
    offers it interactively in Designer ("обновить свойства расширения"). This script does
    the same mechanically: it reads the values from the target configuration dump and
    rewrites ONLY those elements in the extension, leaving the rest of the XML byte-identical.

    Idempotent. Never touches the configuration dump itself.

.EXAMPLE
    .\sync-ninja-properties.ps1 -ProjectRoot C:\1C\projects\unf-dev
.EXAMPLE
    .\sync-ninja-properties.ps1 -ProjectRoot C:\1C\projects\unf-dev -Check
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $false)]
    [string]$ExtensionName = "NinjaLive",

    [Parameter(Mandatory = $false)]
    [string]$ConfigDir,

    [Parameter(Mandatory = $false)]
    [string]$ExtensionDir,

    [Parameter(Mandatory = $false)]
    [switch]$Check,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$ProjectRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
if (-not $ConfigDir) { $ConfigDir = Join-Path $ProjectRoot "src\cf" }
if (-not $ExtensionDir) { $ExtensionDir = Join-Path $ProjectRoot "src\cfe\$ExtensionName" }

$report = New-Object System.Collections.Generic.List[object]
function Add-Report {
    param([string]$Item, [string]$Status, [string]$Detail = "")
    [void]$report.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
}

function Read-Utf8 { param([string]$Path) return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)) }

# Replace the inner text of <Element>...</Element> in a UTF-8 file, leaving everything
# else untouched. Returns $true when the file changed.
function Set-XmlElementValue {
    param(
        [string]$Path,
        [string]$Element,
        [string]$Value
    )
    $text = Read-Utf8 $Path
    $pattern = "(?<=<" + [regex]::Escape($Element) + ">).*?(?=</" + [regex]::Escape($Element) + ">)"
    $m = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return $null }
    $old = $m.Value
    if ($old -ceq $Value) { return $false }
    if ($Check) { return $true }
    $new = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $Value }, 1)
    [System.IO.File]::WriteAllText($Path, $new, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Get-XmlElementValue {
    param([string]$Path, [string]$Element)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Read-Utf8 $Path
    $m = [regex]::Match($text, "(?<=<" + [regex]::Escape($Element) + ">).*?(?=</" + [regex]::Escape($Element) + ">)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($m.Success) { return $m.Value }
    return $null
}

if (-not $Quiet) {
    $mode = if ($Check) { "Check" } else { "Apply" }
    Write-Host "=== sync-ninja-properties ($mode) ===" -ForegroundColor Cyan
    Write-Host "Config: $ConfigDir"
    Write-Host "Extension: $ExtensionDir"
}

$cfgMain = Join-Path $ConfigDir "Configuration.xml"
if (-not (Test-Path -LiteralPath $cfgMain)) {
    throw "Configuration dump not found: $cfgMain (dump the configuration first)"
}
$extMain = Join-Path $ExtensionDir "Configuration.xml"
if (-not (Test-Path -LiteralPath $extMain)) {
    throw "Extension Configuration.xml not found: $extMain"
}

# ---- 1. compatibility modes -------------------------------------------------
# The extension stores the compatibility mode under its own element name; the
# configuration dump uses both <CompatibilityMode> and <ConfigurationExtensionCompatibilityMode>.
$wanted = @(
    @{ Ext = "ConfigurationExtensionCompatibilityMode"; Cfg = @("ConfigurationExtensionCompatibilityMode", "CompatibilityMode") },
    @{ Ext = "InterfaceCompatibilityMode";        Cfg = @("InterfaceCompatibilityMode") }
)

foreach ($w in $wanted) {
    $cfgVal = $null
    foreach ($c in $w.Cfg) {
        $cfgVal = Get-XmlElementValue -Path $cfgMain -Element $c
        if ($cfgVal) { break }
    }
    $extVal = Get-XmlElementValue -Path $extMain -Element $w.Ext
    if (-not $cfgVal) {
        Add-Report $w.Ext "skip" "not present in configuration dump"
        continue
    }
    if (-not $extVal) {
        Add-Report $w.Ext "skip" "not present in extension"
        continue
    }
    if ($extVal -ceq $cfgVal) {
        Add-Report $w.Ext "ok" "already $cfgVal"
        continue
    }
    $changed = Set-XmlElementValue -Path $extMain -Element $w.Ext -Value $cfgVal
    if ($null -eq $changed) { Add-Report $w.Ext "fail" "element not found" }
    elseif ($changed) { Add-Report $w.Ext $(if ($Check) { "would-set" } else { "updated" }) "$extVal -> $cfgVal" }
    else { Add-Report $w.Ext "ok" "already $cfgVal" }
}

# ---- 2. adopted language objects -------------------------------------------
$cfgLangDir = Join-Path $ConfigDir "Languages"
$extLangDir = Join-Path $ExtensionDir "Languages"
if ((Test-Path -LiteralPath $cfgLangDir) -and (Test-Path -LiteralPath $extLangDir)) {
    $cfgMap = @{}
    foreach ($f in Get-ChildItem -LiteralPath $cfgLangDir -Filter "*.xml" -File) {
        $t = Read-Utf8 $f.FullName
        $nm = [regex]::Match($t, "(?<=<Name>).*?(?=</Name>)").Value
        $uu = [regex]::Match($t, "Language\s+uuid=""([^""]+)""").Groups[1].Value
        if ($nm -and $uu) { $cfgMap[$nm] = $uu }
    }
    foreach ($f in Get-ChildItem -LiteralPath $extLangDir -Filter "*.xml" -File) {
        $t = Read-Utf8 $f.FullName
        $nm = [regex]::Match($t, "(?<=<Name>).*?(?=</Name>)").Value
        $cur = [regex]::Match($t, "(?<=<ExtendedConfigurationObject>).*?(?=</ExtendedConfigurationObject>)").Value
        if (-not $cur) { continue }
        if (-not $cfgMap.ContainsKey($nm)) {
            Add-Report "Languages/$($f.Name)" "warn" "no '$nm' in configuration dump"
            continue
        }
        $want = $cfgMap[$nm]
        if ($cur -ceq $want) {
            Add-Report "Languages/$($f.Name)" "ok" "already $want"
            continue
        }
        $changed = Set-XmlElementValue -Path $f.FullName -Element "ExtendedConfigurationObject" -Value $want
        if ($changed) { Add-Report "Languages/$($f.Name)" $(if ($Check) { "would-set" } else { "updated" }) "$cur -> $want" }
        else { Add-Report "Languages/$($f.Name)" "ok" "already $want" }
    }
} else {
    Add-Report "Languages" "skip" "no Languages dir on one side"
}

if (-not $Quiet) {
    Write-Host ""
    $report | Format-Table -AutoSize | Out-String | Write-Host
}

$bad = @($report | Where-Object { $_.Status -eq "fail" })
if ($bad.Count -gt 0) { exit 1 }
exit 0

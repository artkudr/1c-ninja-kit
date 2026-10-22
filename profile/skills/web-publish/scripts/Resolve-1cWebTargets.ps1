# Shared resolver: profile Apache by platform line (8.3 / 8.5).
# Dot-source from web-* scripts. No Apache inside projects.
#
# Profile roots:
#   %USERPROFILE%\tools\apache-83  → port 8083  (платформа 8.3*)
#   %USERPROFILE%\tools\apache-85  → port 8085  (платформа 8.5*)
#
# Workspace overrides (.v8-project.json):
#   v8path (версия платформы), web.appName, web.port, web.apachePath

function Find-1cProjectRoot {
    param([string]$StartDir = (Get-Location).Path)
    $dir = $StartDir
    while ($dir) {
        if (Test-Path (Join-Path $dir ".v8-project.json")) { return $dir }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $StartDir
}

function Read-1cJsonFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch { return $null }
}

function Get-AppNameFromWebUrl([string]$webUrl) {
    if (-not $webUrl) { return $null }
    try {
        $u = [Uri]$webUrl
        $seg = ($u.AbsolutePath -split '/' | Where-Object { $_ }) | Select-Object -First 1
        if ($seg) { return $seg.ToLowerInvariant() }
    } catch {}
    return $null
}

function Get-PortFromWebUrl([string]$webUrl) {
    if (-not $webUrl) { return $null }
    try {
        $u = [Uri]$webUrl
        if ($u.IsDefaultPort) { return $null }
        return [int]$u.Port
    } catch { return $null }
}

function Get-V8VersionFromPath([string]$v8path) {
    if (-not $v8path) { return $null }
    if ($v8path -match '(\d+\.\d+(\.\d+){0,2})') { return $Matches[1] }
    return $null
}

function Get-DetectedV8VersionMask {
    $found = Get-ChildItem @(
        "C:\Program Files\1cv8\*\bin\1cv8.exe",
        "C:\Program Files (x86)\1cv8\*\bin\1cv8.exe"
    ) -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]"0.0.0.0" } } -Descending |
        Select-Object -First 1
    if ($found) { return $found.Directory.Parent.Name }
    return $null
}

function Get-PlatformApacheDefaults([string]$v8version) {
    $ver = if ($v8version) { $v8version.Trim() } else { "8.3" }
    if ($ver -like "8.5*") {
        return @{
            Label      = "85"
            Port       = 8085
            ApachePath = (Join-Path $env:USERPROFILE "tools\apache-85")
        }
    }
    return @{
        Label      = "83"
        Port       = 8083
        ApachePath = (Join-Path $env:USERPROFILE "tools\apache-83")
    }
}

function Resolve-1cWebTargets {
    param(
        [string]$ProjectRoot,
        [string]$V8Version,
        [string]$AppName,
        [string]$ApachePath,
        [Nullable[int]]$Port
    )

    if (-not $ProjectRoot) { $ProjectRoot = Find-1cProjectRoot }

    $registry = Read-1cJsonFile (Join-Path $ProjectRoot ".v8-project.json")
    $smoke = Read-1cJsonFile (Join-Path $ProjectRoot "tools\web-test\smoke.config.json")

    $cfgV8 = $null
    $cfgApp = $null
    $cfgPort = $null
    $cfgApache = $null
    if ($registry) {
        $cfgV8 = Get-V8VersionFromPath ([string]$registry.v8path)
        if ($registry.web) {
            if ($registry.web.appName) { $cfgApp = [string]$registry.web.appName }
            if ($null -ne $registry.web.port -and "$($registry.web.port)" -ne "") {
                $cfgPort = [int]$registry.web.port
            }
            if ($registry.web.apachePath) { $cfgApache = [string]$registry.web.apachePath }
        }
    }
    if (-not $cfgV8) { $cfgV8 = Get-DetectedV8VersionMask }
    if ($smoke -and $smoke.webUrl) {
        if (-not $cfgApp) { $cfgApp = Get-AppNameFromWebUrl ([string]$smoke.webUrl) }
        if (-not $cfgPort) { $cfgPort = Get-PortFromWebUrl ([string]$smoke.webUrl) }
    }

    if (-not $V8Version) { $V8Version = $cfgV8 }
    $defaults = Get-PlatformApacheDefaults $V8Version

    if (-not $ApachePath) {
        if ($cfgApache) { $ApachePath = $cfgApache }
        else { $ApachePath = $defaults.ApachePath }
    }
    if (-not [System.IO.Path]::IsPathRooted($ApachePath)) {
        $ApachePath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $ApachePath))
    }

    if (-not $AppName) {
        if ($cfgApp) { $AppName = $cfgApp }
        else {
            $leaf = (Split-Path $ProjectRoot -Leaf) -replace '[^\w\-]', ''
            if ($leaf) { $AppName = $leaf.ToLowerInvariant() }
        }
    }
    if ($AppName) { $AppName = $AppName.ToLowerInvariant() }

    $resolvedPort = $null
    if ($null -ne $Port -and $Port -gt 0) { $resolvedPort = [int]$Port }
    elseif ($cfgPort -and $cfgPort -gt 0) { $resolvedPort = [int]$cfgPort }
    else { $resolvedPort = [int]$defaults.Port }

    return [pscustomobject]@{
        ProjectRoot = $ProjectRoot
        V8Version   = $V8Version
        AppName     = $AppName
        Port        = $resolvedPort
        ApachePath  = $ApachePath
        ApacheLabel = $defaults.Label
        Defaults    = $defaults
    }
}

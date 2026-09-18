# Shared resolver: profile Apache by platform line (8.3 / 8.5).
# Dot-source from web-* scripts. No Apache inside projects.
#
# Profile roots:
#   %USERPROFILE%\tools\apache-83  → port 8083  (v8version 8.3*)
#   %USERPROFILE%\tools\apache-85  → port 8085  (v8version 8.5*)
#
# Workspace overrides (autumn-properties.json):
#   vrunner.v8version, web.appName, web.port, web.apachePath

function Find-1cProjectRoot {
    param([string]$StartDir = (Get-Location).Path)
    $dir = $StartDir
    while ($dir) {
        if (Test-Path (Join-Path $dir "autumn-properties.json")) { return $dir }
        if (Test-Path (Join-Path $dir "env.json")) { return $dir }
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

    $autumn = Read-1cJsonFile (Join-Path $ProjectRoot "autumn-properties.json")
    if (-not $autumn) { $autumn = Read-1cJsonFile (Join-Path $ProjectRoot "env.json") }
    $smoke = Read-1cJsonFile (Join-Path $ProjectRoot "tools\web-test\smoke.config.json")

    $cfgV8 = $null
    $cfgApp = $null
    $cfgPort = $null
    $cfgApache = $null
    if ($autumn -and $autumn.vrunner -and $autumn.vrunner.v8version) {
        $cfgV8 = [string]$autumn.vrunner.v8version
    }
    if ($autumn -and $autumn.web) {
        if ($autumn.web.appName) { $cfgApp = [string]$autumn.web.appName }
        if ($null -ne $autumn.web.port -and "$($autumn.web.port)" -ne "") {
            $cfgPort = [int]$autumn.web.port
        }
        if ($autumn.web.apachePath) { $cfgApache = [string]$autumn.web.apachePath }
    }
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

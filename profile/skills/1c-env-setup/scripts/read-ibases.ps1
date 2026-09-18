# read-ibases.ps1 — список информационных баз из ibases.v8i
<#
.SYNOPSIS
    Читает список баз 1С из ibases.v8i и выводит таблицу / JSON.

.EXAMPLE
    .\read-ibases.ps1
.EXAMPLE
    .\read-ibases.ps1 -Json
.EXAMPLE
    .\read-ibases.ps1 -Path "D:\custom\ibases.v8i"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-DefaultIbasesPath {
    $candidates = @(
        (Join-Path $env:APPDATA "1C\1CEStart\ibases.v8i"),
        (Join-Path $env:APPDATA "1C\1Cv8\ibases.v8i")
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $candidates[0]
}

function Read-IbasesFile {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "ibases.v8i not found: $FilePath"
    }
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes)
    } catch {
        return [System.Text.Encoding]::GetEncoding(1251).GetString($bytes)
    }
}

function Parse-ConnectString {
    param([string]$Connect)
    $result = @{
        Type    = "unknown"
        Path    = $null
        Server  = $null
        Ref     = $null
        Display = $Connect
    }
    if (-not $Connect) { return $result }

    if ($Connect -match '(?i)File\s*=\s*"([^"]+)"' -or $Connect -match "(?i)File\s*=\s*'([^']+)'" -or $Connect -match '(?i)File\s*=\s*([^;]+)') {
        $result.Type = "file"
        $result.Path = $Matches[1].Trim()
        $result.Display = $result.Path
        return $result
    }
    if ($Connect -match '(?i)Srvr\s*=\s*"([^"]+)"' -or $Connect -match "(?i)Srvr\s*=\s*'([^']+)'" -or $Connect -match '(?i)Srvr\s*=\s*([^;]+)') {
        $result.Type = "server"
        $result.Server = $Matches[1].Trim()
        if ($Connect -match '(?i)Ref\s*=\s*"([^"]+)"' -or $Connect -match "(?i)Ref\s*=\s*'([^']+)'" -or $Connect -match '(?i)Ref\s*=\s*([^;]+)') {
            $result.Ref = $Matches[1].Trim()
        }
        $result.Display = "$($result.Server)/$($result.Ref)"
        return $result
    }
    return $result
}

function Test-IbAvailable {
    param($Parsed)
    if ($Parsed.Type -eq "file" -and $Parsed.Path) {
        $cd = Join-Path $Parsed.Path "1Cv8.1CD"
        return (Test-Path -LiteralPath $cd)
    }
    if ($Parsed.Type -eq "server" -and $Parsed.Server -and $Parsed.Ref) {
        return $true  # формат ок; сеть не проверяем
    }
    return $false
}

function ConvertTo-IbConnection {
    param($Parsed)
    if ($Parsed.Type -eq "file" -and $Parsed.Path) {
        return ('/F"{0}"' -f $Parsed.Path)
    }
    if ($Parsed.Type -eq "server" -and $Parsed.Server -and $Parsed.Ref) {
        return ('/S"{0}/{1}"' -f $Parsed.Server, $Parsed.Ref)
    }
    return $null
}

function Get-IbasesList {
    param([string]$FilePath)

    $text = Read-IbasesFile $FilePath
    $bases = New-Object System.Collections.Generic.List[object]
    $current = $null

    foreach ($rawLine in ($text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if (-not $line) { continue }

        if ($line -match '^\[(.+)\]$') {
            if ($current -and $current.Connect) {
                $parsed = Parse-ConnectString $current.Connect
                $obj = [pscustomobject]@{
                    Name         = [string]$current.Name
                    Connect      = [string]$current.Connect
                    ID           = $current.ID
                    Order        = $current.Order
                    Type         = [string]$parsed.Type
                    Path         = $parsed.Path
                    Server       = $parsed.Server
                    Ref          = $parsed.Ref
                    Display      = [string]$parsed.Display
                    Available    = [bool](Test-IbAvailable $parsed)
                    IbConnection = ConvertTo-IbConnection $parsed
                }
                [void]$bases.Add($obj)
            }
            $current = @{
                Name    = $Matches[1]
                Connect = $null
                ID      = $null
                Order   = $null
            }
            continue
        }

        if (-not $current) { continue }

        if ($line -match '^(?i)Connect=(.+)$') {
            $current.Connect = $Matches[1].Trim()
        } elseif ($line -match '^(?i)ID=(.+)$') {
            $current.ID = $Matches[1].Trim()
        } elseif ($line -match '^(?i)Order=(.+)$') {
            $current.Order = $Matches[1].Trim()
        }
    }

    if ($current -and $current.Connect) {
        $parsed = Parse-ConnectString $current.Connect
        $obj = [pscustomobject]@{
            Name         = [string]$current.Name
            Connect      = [string]$current.Connect
            ID           = $current.ID
            Order        = $current.Order
            Type         = [string]$parsed.Type
            Path         = $parsed.Path
            Server       = $parsed.Server
            Ref          = $parsed.Ref
            Display      = [string]$parsed.Display
            Available    = [bool](Test-IbAvailable $parsed)
            IbConnection = ConvertTo-IbConnection $parsed
        }
        [void]$bases.Add($obj)
    }

    return [object[]]$bases.ToArray()
}

# --- main ---
if (-not $Path) { $Path = Get-DefaultIbasesPath }

$list = Get-IbasesList -FilePath $Path
if ($null -eq $list) { $list = @() }
if ($list -isnot [System.Array]) { $list = @($list) }

if ($Json) {
    $payload = [ordered]@{
        path  = $Path
        count = $list.Count
        bases = @($list | ForEach-Object {
            [ordered]@{
                index        = 0
                name         = $_.Name
                type         = $_.Type
                display      = $_.Display
                available    = $_.Available
                ibconnection = $_.IbConnection
                path         = $_.Path
                server       = $_.Server
                ref          = $_.Ref
                id           = $_.ID
            }
        })
    }
    $i = 1
    foreach ($b in $payload.bases) {
        $b.index = $i
        $i++
    }
    $payload | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host "Source: $Path" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("{0,-4} {1,-36} {2,-8} {3,-6} {4}" -f "No", "Name", "Type", "OK", "Connect") -ForegroundColor Cyan
Write-Host ("-" * 100)
$n = 1
foreach ($b in $list) {
    $ok = if ($b.Available) { "yes" } else { "no" }
    $disp = $b.Display
    if ($disp.Length -gt 50) { $disp = $disp.Substring(0, 47) + "..." }
    Write-Host ("{0,-4} {1,-36} {2,-8} {3,-6} {4}" -f $n, $b.Name, $b.Type, $ok, $disp)
    $n++
}
if ($list.Count -eq 0) {
    Write-Host "(empty)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Total: $($list.Count)" -ForegroundColor DarkGray

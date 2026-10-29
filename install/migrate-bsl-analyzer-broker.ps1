# Перевод project MCP bsl-analyzer-workspace на схему "общий backend без лаунчера".
#
# Что меняет в <проект>\opencode.jsonc (и .example, если есть), только внутри блока
# "bsl-analyzer-workspace":
#   - путь лаунчера %LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe -> %USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe
#     (лаунчер держит потомка в Windows Job и убивает broker-backend вместе с прокси, upstream #345);
#   - добавляет "--mode", "broker";
#   - добавляет "environment" с BSL_MCP_IDLE_TTL_SECS / BSL_MCP_ORPHAN_GRACE_SECS = 86400.
# bsl-analyzer-reference не трогается — ему лаунчер подходит.
#
# Скрипт идемпотентный: повторный запуск ничего не меняет.
#
# Примеры:
#   .\install\migrate-bsl-analyzer-broker.ps1 -DryRun
#   .\install\migrate-bsl-analyzer-broker.ps1
#   .\install\migrate-bsl-analyzer-broker.ps1 -Projects C:\1C\projects\devtools

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Projects,
    [string]$ProjectsRoot = 'C:\1C\projects',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not $Projects) {
    $Projects = @(
        Get-ChildItem $ProjectsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'opencode.jsonc') } |
            ForEach-Object { $_.FullName }
    )
}

$appPath = (Join-Path $env:USERPROFILE '.bsl-analyzer\bin\bsl-analyzer-app.exe').Replace('\', '\\')

function Get-BlockRange {
    param([string]$Text)

    $marker = '"bsl-analyzer-workspace"'
    $i = $Text.IndexOf($marker)
    if ($i -lt 0) { return $null }
    $open = $Text.IndexOf('{', $i)
    if ($open -lt 0) { return $null }

    $depth = 0
    $inStr = $false
    $esc = $false
    for ($j = $open; $j -lt $Text.Length; $j++) {
        $ch = $Text[$j]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($ch -eq '\') { $esc = $true }
            elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true; continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return [pscustomobject]@{ Start = $open; End = $j } }
        }
    }
    return $null
}

function Update-Block {
    param([string]$Block)

    $changed = $false

    # 1. Лаунчер -> app-бинарник.
    $newBlock = [regex]::Replace($Block, '"[^"]*bsl-analyzer\\\\+bsl-analyzer\.exe"', "`"$appPath`"")
    if ($newBlock -ne $Block) { $changed = $true; $Block = $newBlock }

    # 2. Явный broker.
    if ($Block -notmatch '"--mode"') {
        $newBlock = [regex]::Replace($Block, '("--profile",\s*"workspace",)', '$1 "--mode", "broker",')
        if ($newBlock -ne $Block) { $changed = $true; $Block = $newBlock }
    }

    # 3. TTL, чтобы backend не уходил через штатные 300 с.
    if ($Block -notmatch '"environment"') {
        $nl = if ($Block.Contains("`r`n")) { "`r`n" } else { "`n" }
        $m = [regex]::Match($Block, '(?m)^(?<indent>[ \t]*)"type":\s*"local",[ \t]*\r?$')
        if ($m.Success) {
            $ind = $m.Groups['indent'].Value
            $insert = "$nl" +
                "$ind// TTL: сутки простоя; мёртвые аренды снимает задача `"bsl-analyzer lease clean`".$nl" +
                "$ind`"environment`": {$nl" +
                "$ind  `"BSL_MCP_IDLE_TTL_SECS`": `"86400`",$nl" +
                "$ind  `"BSL_MCP_ORPHAN_GRACE_SECS`": `"86400`"$nl" +
                "$ind},"
            $pos = $m.Index + $m.Length
            $Block = $Block.Substring(0, $pos) + $insert + $Block.Substring($pos)
            $changed = $true
        }
    }

    return [pscustomobject]@{ Text = $Block; Changed = $changed }
}

$summary = @()

foreach ($project in $Projects) {
    foreach ($name in @('opencode.jsonc')) {
        $file = Join-Path $project $name
        if (-not (Test-Path -LiteralPath $file)) { continue }

        $text = Get-Content -LiteralPath $file -Raw
        $range = Get-BlockRange -Text $text
        if (-not $range) { continue }

        $block = $text.Substring($range.Start, $range.End - $range.Start + 1)
        $result = Update-Block -Block $block
        if (-not $result.Changed) { continue }

        $updated = $text.Substring(0, $range.Start) + $result.Text + $text.Substring($range.End + 1)
        $label = "$(Split-Path $project -Leaf)\$name"
        if ($DryRun) {
            $summary += "WOULD $label"
        } elseif ($PSCmdlet.ShouldProcess($file, 'перевести bsl-analyzer-workspace на app-бинарник + broker')) {
            Set-Content -LiteralPath $file -Value $updated -Encoding UTF8 -NoNewline
            $summary += "DONE  $label"
        }
    }
}

if ($summary.Count -eq 0) {
    Write-Output 'нечего менять: все конфиги уже на app-бинарнике с broker'
} else {
    $summary | ForEach-Object { Write-Output $_ }
}

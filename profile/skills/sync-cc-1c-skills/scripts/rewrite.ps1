# rewrite.ps1 — soft-transform quarantine skills (strip v8 hooks + path rewrite)
# Input:  policies/whitelist.json + soft-transform.json + %USERPROFILE%\.cursor\devccskills\skills\
# Output: updated quarantine files + policies/promote-whitelist.json + LAST-REWRITE.md
# Does NOT touch live skills. Idempotent.

[CmdletBinding()]
param(
    [string]$QuarantineSkills = "",
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SkillRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$PoliciesDir = Join-Path $SkillRoot "policies"
$LiveSkills = Join-Path $env:USERPROFILE ".cursor\skills"
$Quarantine = Join-Path $env:USERPROFILE ".cursor\devccskills"
if (-not $QuarantineSkills) {
    $QuarantineSkills = Join-Path $Quarantine "skills"
}
$ReportPath = Join-Path $Quarantine "LAST-REWRITE.md"
$PromotePath = Join-Path $PoliciesDir "promote-whitelist.json"

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Utf8Bom([string]$Path, [string]$Content) {
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Fill-PolicySkillList {
    param(
        [string]$FileName,
        [System.Collections.Generic.List[string]]$Target
    )
    $j = Read-JsonFile (Join-Path $PoliciesDir $FileName)
    $Target.Clear()
    if ($null -ne $j.skills) {
        foreach ($s in @($j.skills)) {
            if ($null -ne $s -and "$s".Length -gt 0) { $Target.Add([string]$s) }
        }
    }
}

function Test-NameInList([string]$Name, $List) {
    return ($List -contains $Name)
}

function Find-BalancedBlockEnd([string]$Text, [int]$OpenBraceIndex) {
    $depth = 0
    for ($i = $OpenBraceIndex; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

function Replace-PsFunction {
    param(
        [string]$Text,
        [string]$FunctionName,
        [string]$NewFunction
    )
    $rx = [regex]::new("(?m)^function\s+$([regex]::Escape($FunctionName))\b[^\r\n]*\{")
    $m = $rx.Match($Text)
    if (-not $m.Success) { return @{ Text = $Text; Changed = $false } }
    $openIdx = $m.Index + $m.Length - 1
    $endIdx = Find-BalancedBlockEnd $Text $openIdx
    if ($endIdx -lt 0) { return @{ Text = $Text; Changed = $false } }
    $newText = $Text.Substring(0, $m.Index) + $NewFunction + $Text.Substring($endIdx + 1)
    return @{ Text = $newText; Changed = ($newText -ne $Text) }
}

function Remove-PsFunction {
    param([string]$Text, [string]$FunctionName)
    $rx = [regex]::new("(?m)^function\s+$([regex]::Escape($FunctionName))\b[^\r\n]*\{")
    $m = $rx.Match($Text)
    if (-not $m.Success) { return @{ Text = $Text; Changed = $false } }
    $openIdx = $m.Index + $m.Length - 1
    $endIdx = Find-BalancedBlockEnd $Text $openIdx
    if ($endIdx -lt 0) { return @{ Text = $Text; Changed = $false } }
    $start = $m.Index
    # drop preceding blank line
    while ($start -gt 0 -and ($Text[$start - 1] -eq "`n" -or $Text[$start - 1] -eq "`r")) {
        $start--
        if ($start -gt 0 -and $Text[$start - 1] -eq "`n") { break }
    }
    $newText = $Text.Substring(0, $start) + $Text.Substring($endIdx + 1)
    return @{ Text = $newText; Changed = $true }
}

function Find-PyFunctionSpan {
    param([string]$Text, [string]$DefLineRegex)
    $rx = [regex]::new("(?m)^$DefLineRegex\s*$")
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $null }
    $start = $m.Index
    $rest = $Text.Substring($start)
    $next = [regex]::Match($rest, '(?m)\n(?=def |class )')
    if ($next.Success -and $next.Index -gt 0) {
        $end = $start + $next.Index
    } else {
        $end = $Text.Length
    }
    return @{ Start = $start; End = $end }
}

function Replace-PyFunction {
    param(
        [string]$Text,
        [string]$DefLineRegex,
        [string]$NewFunction
    )
    $span = Find-PyFunctionSpan -Text $Text -DefLineRegex $DefLineRegex
    if ($null -eq $span) { return @{ Text = $Text; Changed = $false } }
    $newText = $Text.Substring(0, $span.Start) + $NewFunction.TrimEnd() + "`r`n`r`n" + $Text.Substring($span.End).TrimStart("`r", "`n")
    return @{ Text = $newText; Changed = ($newText -ne $Text) }
}

function Remove-PyFunction {
    param([string]$Text, [string]$DefLineRegex)
    $span = Find-PyFunctionSpan -Text $Text -DefLineRegex $DefLineRegex
    if ($null -eq $span) { return @{ Text = $Text; Changed = $false } }
    $start = $span.Start
    while ($start -gt 0 -and ($Text[$start - 1] -eq "`n" -or $Text[$start - 1] -eq "`r")) {
        $start--
    }
    $newText = $Text.Substring(0, $start).TrimEnd("`r", "`n") + "`r`n`r`n" + $Text.Substring($span.End).TrimStart("`r", "`n")
    return @{ Text = $newText; Changed = $true }
}

function Invoke-PathRewrite {
    param([string]$Text, [string]$SkillName)
    $orig = $Text
    # ${CLAUDE_SKILL_DIR} → live path of the skill being rewritten
    $ownRoot = "%USERPROFILE%\.cursor\skills\$SkillName\"
    $Text = $Text.Replace('${CLAUDE_SKILL_DIR}/', $ownRoot)
    $Text = $Text.Replace('${CLAUDE_SKILL_DIR}\', $ownRoot)
    # Any .cursor/.claude skills/<name>/ (incl. cross-skill refs like erf→epf) → %USERPROFILE%...
    # Skip already-rewritten %USERPROFILE%\... paths via negative lookbehind.
    $rx = [regex]::new('(?<!%USERPROFILE%[\\/])\.(?:cursor|claude)[/\\]skills[/\\]([^/\\]+)[/\\]')
    $Text = $rx.Replace($Text, '%USERPROFILE%\.cursor\skills\$1\')
    return @{ Text = $Text; Changed = ($Text -ne $orig) }
}

function Invoke-CfeSkillHints {
    param([string]$Text)
    $orig = $Text
    # Replace common auto-detect block (4 steps with v8-project / db-list)
    $oldBlock4 = @'
Если пользователь не указал `-ConfigPath` — попробуй определить автоматически:
1. Прочитай `.v8-project.json` из корня проекта
2. Разреши целевую базу (по имени, ветке или `default` — алгоритм из `/db-list`)
3. Если у базы есть поле `configSrc` — используй как `-ConfigPath`
4. Если `configSrc` нет — спроси у пользователя
'@
    $newBlock = @'
Если пользователь не указал `-ConfigPath` — попробуй определить автоматически:
1. Прочитай скилл `1c-project-context` / корень проекта
2. Если есть `src/cf` (или `src/cf/Configuration.xml`) — используй как `-ConfigPath`
3. Иначе спроси у пользователя
'@
    if ($Text.Contains($oldBlock4)) {
        $Text = $Text.Replace($oldBlock4, $newBlock)
    }
    # cfe-validate shorter variant
    $oldBlock3 = @'
Если пользователь не указал путь — определи сам:
1. Прочитай `.v8-project.json` из корня проекта
2. Разреши целевую базу (по имени, ветке или `default`)
3. Возьми её поле `configSrc`
'@
    $newBlock3 = @'
Если пользователь не указал путь — определи сам:
1. Прочитай скилл `1c-project-context` / корень проекта
2. Если есть `src/cf` (или `src/cf/Configuration.xml`) — используй как `-ConfigPath`
3. Иначе спроси у пользователя
'@
    if ($Text.Contains($oldBlock3)) {
        $Text = $Text.Replace($oldBlock3, $newBlock3)
    }
    $Text = $Text.Replace(
        'Если `.v8-project.json` не найден и `-ConfigPath` не задан',
        'Если каталог конфигурации не найден и `-ConfigPath` не задан'
    )
    # leftover single-line hints
    $Text = [regex]::Replace($Text, '(?m)^1\.\s*Прочитай `\\.v8-project\.json`[^\r\n]*\r?\n', "1. Прочитай скилл ``1c-project-context`` / корень проекта`r`n")
    return @{ Text = $Text; Changed = ($Text -ne $orig) }
}

function Invoke-StripPs1 {
    param([string]$Text)
    $changed = $false
    $offNew = 'Чтобы править объект на поддержке: снять с поддержки через /support-edit или не трогать объект на замке.'
    $offOldPatterns = @(
        'Снять проверку для этой базы: editingAllowedCheck = warn|off в .v8-project.json.',
        'Снять проверку для этой базы: editingAllowedCheck = warn|off в `.v8-project.json`.',
        'предложи /db-list add',
        'предложи db-list add'
    )

    $editStub = @"
function Get-EditMode([string]`$cfgDir) {
	# Always deny for editingAllowedCheck (no .v8-project / PT registry).
	return 'deny'
}
"@
    $r = Replace-PsFunction -Text $Text -FunctionName 'Get-EditMode' -NewFunction $editStub.TrimEnd()
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    $posStub = @"
function Get-NewObjectPosition([string]`$cfgDir) {
	# Always end — .v8-project not used.
	return "end"
}
"@
    $r = Replace-PsFunction -Text $Text -FunctionName 'Get-NewObjectPosition' -NewFunction $posStub.TrimEnd()
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    $r = Remove-PsFunction -Text $Text -FunctionName 'Find-V8Project'
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    foreach ($old in $offOldPatterns) {
        if ($Text.Contains($old)) {
            # only replace the editingAllowedCheck offNote line
            if ($old -like '*editingAllowedCheck*') {
                $Text = $Text.Replace($old, $offNew)
                $changed = $true
            }
        }
    }
    # generic offNote assignment with v8-project
    $Text2 = [regex]::Replace($Text, '\$offNote\s*=\s*"[^"]*\.v8-project\.json[^"]*"', ('$offNote = "' + $offNew + '"'))
    if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true }

    # comment header soften — full upstream 3-line block (and partially stripped leftovers)
    $psGuardClean = "# read-only configs unless allowed. Trigger = bin present; mode always deny.`r`n# Guard errors degrade to allow."
    $psGuardPatterns = @(
        '(?m)^# read-only configs unless allowed\. Trigger = bin present; reaction from\r?\n# \.v8-project\.json editingAllowedCheck[^\r\n]*\r?\n# throws —[^\r\n]*',
        '(?m)^# read-only configs unless allowed\. Trigger = bin present; reaction from\r?\n# mode always deny[^\r\n]*\r?\n# throws —[^\r\n]*',
        '(?m)^# read-only configs unless allowed\. Trigger = bin present; reaction from\r?\n# throws —[^\r\n]*'
    )
    foreach ($pat in $psGuardPatterns) {
        $Text2 = [regex]::Replace($Text, $pat, $psGuardClean)
        if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true; break }
    }
    $Text2 = $Text -replace '(?m)^# \.v8-project\.json editingAllowedCheck[^\r\n]*', '# mode always deny (no .v8-project).'
    if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true }

    return @{ Text = $Text; Changed = $changed }
}

function Invoke-StripPy {
    param([string]$Text)
    $changed = $false
    $offNew = 'Чтобы править объект на поддержке: снять с поддержки через /support-edit или не трогать объект на замке.'

    $editStub = @'
def _sg_get_edit_mode(cfg_dir):
    # Always deny for editingAllowedCheck (no .v8-project / PT registry).
    return "deny"

'@
    $r = Replace-PyFunction -Text $Text -DefLineRegex 'def _sg_get_edit_mode\(cfg_dir\):' -NewFunction $editStub
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    $posStub = @'
def get_new_object_position(cfg_dir):
    """Always end — .v8-project not used."""
    return "end"

'@
    $r = Replace-PyFunction -Text $Text -DefLineRegex 'def get_new_object_position\(cfg_dir\):' -NewFunction $posStub
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    $r = Remove-PyFunction -Text $Text -DefLineRegex 'def _sg_find_v8project\(start_dir\):'
    if ($r.Changed) { $Text = $r.Text; $changed = $true }

    $Text2 = [regex]::Replace($Text, 'off_note\s*=\s*"[^"]*\.v8-project\.json[^"]*"', ('off_note = "' + $offNew + '"'))
    if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true }
    $Text2 = [regex]::Replace($Text, "off_note\s*=\s*'[^']*\.v8-project\.json[^']*'", ("off_note = '" + $offNew + "'"))
    if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true }

    # comment header soften — upstream split lines + leftovers from partial strip
    $pyGuardClean = "# present; mode always deny (no .v8-project).`r`n# Never throws (except sys.exit on deny) — errors degrade to allow."
    $pyGuardPatterns = @(
        '(?m)^# present; reaction from \.v8-project\.json editingAllowedCheck[^\r\n]*\r?\n# default deny\)\. Never throws[^\r\n]*',
        '(?m)^# present; mode always deny[^\r\n]*\r?\n# default deny\)\. Never throws[^\r\n]*',
        '(?m)^# present; reaction from \.v8-project\.json editingAllowedCheck[^\r\n]*'
    )
    foreach ($pat in $pyGuardPatterns) {
        $repl = if ($pat -like '*default deny*') { $pyGuardClean } else { '# present; mode always deny (no .v8-project).' }
        $Text2 = [regex]::Replace($Text, $pat, $repl)
        if ($Text2 -ne $Text) { $Text = $Text2; $changed = $true; break }
    }

    return @{ Text = $Text; Changed = $changed }
}

function Invoke-RewriteSkillDir {
    param(
        [string]$SkillName,
        [bool]$DoStrip,
        [bool]$DoCfeHints
    )
    $dir = Join-Path $QuarantineSkills $SkillName
    if (-not (Test-Path -LiteralPath $dir)) {
        return @{ Ok = $false; Reason = "missing in quarantine"; Files = @() }
    }
    $filesTouched = New-Object System.Collections.Generic.List[string]
    $ok = $true
    $reason = ""

    # Drop bytecode caches so they never ride along into promote
    if (-not $WhatIf) {
        Get-ChildItem -LiteralPath $dir -Directory -Recurse -Filter '__pycache__' -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $targets = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(ps1|py|md)$' -and $_.FullName -notmatch '[\\/]__pycache__[\\/]' } |
        ForEach-Object { $targets.Add($_.FullName) }

    foreach ($fp in $targets) {
        if (-not $fp -or -not (Test-Path -LiteralPath $fp)) { continue }
        $raw = [System.IO.File]::ReadAllText($fp)
        $text = $raw
        $fileChanged = $false
        $ext = [System.IO.Path]::GetExtension($fp).ToLowerInvariant()

        if ($DoStrip) {
            if ($ext -eq '.ps1') {
                $r = Invoke-StripPs1 -Text $text
                if ($r.Changed) { $text = $r.Text; $fileChanged = $true }
            }
            elseif ($ext -eq '.py') {
                $r = Invoke-StripPy -Text $text
                if ($r.Changed) { $text = $r.Text; $fileChanged = $true }
            }
        }

        if ($ext -eq '.md' -or $ext -eq '.ps1' -or $ext -eq '.py') {
            $r = Invoke-PathRewrite -Text $text -SkillName $SkillName
            if ($r.Changed) { $text = $r.Text; $fileChanged = $true }
        }

        if ($DoCfeHints -and $ext -eq '.md') {
            $r = Invoke-CfeSkillHints -Text $text
            if ($r.Changed) { $text = $r.Text; $fileChanged = $true }
        }
        elseif ($SkillName -like 'cfe-*' -and $ext -eq '.md') {
            $r = Invoke-CfeSkillHints -Text $text
            if ($r.Changed) { $text = $r.Text; $fileChanged = $true }
        }

        if ($fileChanged) {
            if (-not $WhatIf) {
                Write-Utf8Bom -Path $fp -Content $text
            }
            $filesTouched.Add($fp)
        }
    }

    # verify strip markers gone when DoStrip
    if ($DoStrip) {
        $still = @()
        foreach ($fp in (Get-ChildItem -LiteralPath (Join-Path $dir "scripts") -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($fp.Extension -notmatch '\.(ps1|py)$') { continue }
            $t = [System.IO.File]::ReadAllText($fp.FullName)
            if ($t -match 'function Find-V8Project\b|def _sg_find_v8project\b') {
                $still += "Find-V8Project in $($fp.Name)"
            }
            if ($t -match 'Get-Content[^\n]*\.v8-project\.json|open\(pj|editingAllowedCheck') {
                # editingAllowedCheck may remain in comments; flag only if Find still reads project
                if ($t -match 'Find-V8Project|_sg_find_v8project') {
                    $still += "v8 read in $($fp.Name)"
                }
            }
        }
        if ($still.Count -gt 0) {
            $ok = $false
            $reason = ($still -join '; ')
        }
    }

    return @{ Ok = $ok; Reason = $reason; Files = @($filesTouched) }
}

# --- main ---
Write-Host "rewrite.ps1"
Write-Host "  quarantine: $QuarantineSkills"
Write-Host "  policies: $PoliciesDir"

$soft = Read-JsonFile (Join-Path $PoliciesDir "soft-transform.json")
if ($soft.transformsDeferred) {
    throw "soft-transform.json transformsDeferred=true — set false when rewrite is ready"
}

$whitelist = New-Object System.Collections.Generic.List[string]
$hardDrop = New-Object System.Collections.Generic.List[string]
$study = New-Object System.Collections.Generic.List[string]
Fill-PolicySkillList "whitelist.json" $whitelist
Fill-PolicySkillList "hard-drop.json" $hardDrop
Fill-PolicySkillList "quarantine-study.json" $study
$stripList = New-Object System.Collections.Generic.List[string]
foreach ($s in @($soft.stripV8Hooks)) { if ($s) { $stripList.Add([string]$s) } }
$rewriteOnly = New-Object System.Collections.Generic.List[string]
foreach ($s in @($soft.rewriteSkillOnly)) { if ($s) { $rewriteOnly.Add([string]$s) } }

$promoted = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]
$details = New-Object System.Collections.Generic.List[string]

foreach ($name in ($whitelist | Sort-Object)) {
    if (Test-NameInList $name $hardDrop) {
        $skipped.Add("$name (hard-drop)")
        continue
    }
    if (Test-NameInList $name $study) {
        $skipped.Add("$name (quarantine-study)")
        continue
    }
    $dir = Join-Path $QuarantineSkills $name
    if (-not (Test-Path -LiteralPath $dir)) {
        $skipped.Add("$name (not in quarantine)")
        continue
    }

    $doStrip = Test-NameInList $name $stripList
    $doCfe = (Test-NameInList $name $rewriteOnly) -or ($name -like 'cfe-*')

    $result = Invoke-RewriteSkillDir -SkillName $name -DoStrip $doStrip -DoCfeHints $doCfe
    if ($result.Ok) {
        $promoted.Add($name)
        $mode = if ($doStrip) { "strip+path" } else { "path" }
        $details.Add("- $name [$mode] files=$($result.Files.Count)")
        Write-Host "OK $name ($mode) files=$($result.Files.Count)"
    }
    else {
        $failed.Add("$name : $($result.Reason)")
        Write-Host "FAIL $name : $($result.Reason)"
    }
}

# write promote-whitelist.json
$promoteObj = [ordered]@{
    version     = 1
    description = "Ready for sync.ps1 -Promote. Filled by rewrite.ps1 from whitelist after successful soft-transform."
    updatedBy   = "rewrite.ps1"
    updatedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    skills      = @($promoted | Sort-Object)
}
$promoteJson = ($promoteObj | ConvertTo-Json -Depth 5)
if (-not $WhatIf) {
    Write-Utf8Bom -Path $PromotePath -Content $promoteJson
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# LAST-REWRITE")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- When: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- Quarantine: $QuarantineSkills")
[void]$sb.AppendLine("- WhatIf: $WhatIf")
[void]$sb.AppendLine("- promote-whitelist: $($promoted.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## ok ($($promoted.Count))")
$details | ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## failed ($($failed.Count))")
$failed | ForEach-Object { [void]$sb.AppendLine("- $_") }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## skipped ($($skipped.Count))")
$skipped | ForEach-Object { [void]$sb.AppendLine("- $_") }

if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path $Quarantine | Out-Null
    Write-Utf8Bom -Path $ReportPath -Content $sb.ToString()
}

Write-Host "promote-whitelist: $($promoted.Count) -> $PromotePath"
Write-Host "Report: $ReportPath"
Write-Host "Done. ok=$($promoted.Count) failed=$($failed.Count) skipped=$($skipped.Count)"

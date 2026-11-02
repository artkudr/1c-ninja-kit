<#
taskctl.ps1 — машинное состояние задач с ролями.

Один вход, подкоманды. Всё, что можно посчитать, считает скрипт, а не модель.
Только встроенные средства PowerShell 5.1+. Данные — UTF-8 без BOM, переводы строк LF.
Сам скрипт сохранён в UTF-8 с BOM и назван латиницей: иначе PowerShell 5.1
прочитает кириллицу как ANSI, а правило «коммандеру можно только этот скрипт»
задаётся шаблоном имени.

Скрипт глобальный (один на машину, лежит вне проектов), а состояние задачи — в
проекте. Корень проекта: `--project <путь>`, иначе ближайший вверх по текущему
каталогу, где есть `Задачи\` или `.v8-project.json`. Старая раскладка
`<проект>\.opencode\scripts\taskctl.ps1` тоже работает: корнем становится проект.

  new --title "…" [--route полный|быстрый|синхронизация]
  start --task 042 --role Колдун
  finish --task 042 --role Колдун --verdict готово [--note "…"]
  resume --task 042 --reason "что решил человек"
  status --task 042 [--brief]
  next --task 042
  timeline --task 042
  block --task 042 --reason "…"
  unlock --task 042
  validate --task 042
  board [--write]

`--project <путь>` принимает любая команда.

Коды возврата:
  0 — успех;
  1 — ошибка аргументов или неизвестная команда (первое слово «аргумент:»);
  2 — ошибка данных: нет состояния, битый JSON, недопустимый переход, нет артефакта
      (первое слово уточняет: «аргумент:», «данные:», «переход:», «артефакт:»);
  3 — сбой записи или незавершённое восстановление;
  4 — задача занята другим процессом (блокировка).

Параллельная работа не поддерживается: роли запускаются по одной. Блокировки нужны
только чтобы второй процесс отказал кодом 4, а не испортил состояние молча.
#>

# --- окружение ---------------------------------------------------------------

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
try { $OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:AbortMarker = 'taskctl-abort'
$script:LockStaleMinutes = 30

# --- константы ---------------------------------------------------------------

$script:Roles = @('Оракул', 'Часовщик', 'Колдун', 'Инквизитор', 'Бард', 'Телепат')

# Маршруты: ключ — значение поля «маршрут» в состоянии.
$script:Routes = @{
    'полный'          = @('Оракул', 'Часовщик', 'Колдун', 'Инквизитор', 'Бард')
    'быстрый'         = @('Колдун', 'Инквизитор')
    'синхронизация'   = @('Телепат')
}

# (роль, вердикт) -> куда идти: next — дальше по маршруту, имя роли — возврат,
# done — задача закрыта, blocked — нужен человек.
$script:Transitions = @{
    'Оракул/готово'          = 'next'
    'Оракул/нужен-человек'   = 'blocked'
    'Оракул/сбой'            = 'blocked'
    'Часовщик/готово'        = 'next'
    'Часовщик/к-оракулу'     = 'Оракул'
    'Часовщик/сбой'          = 'blocked'
    'Колдун/готово'          = 'next'
    'Колдун/к-часовщику'     = 'Часовщик'
    'Колдун/сбой'            = 'blocked'
    'Инквизитор/готово'      = 'next'
    'Инквизитор/правки'      = 'Колдун'
    'Инквизитор/к-часовщику' = 'Часовщик'
    'Инквизитор/сбой'        = 'blocked'
    'Бард/готово'            = 'next'
    'Бард/правки'            = 'Оракул'
    'Бард/сбой'              = 'blocked'
    'Телепат/готово'         = 'next'
    'Телепат/сбой'           = 'blocked'
    'Телепат/частично'       = 'blocked'
}

$script:Verdicts = @{
    'Оракул'      = @('готово', 'нужен-человек', 'сбой')
    'Часовщик'    = @('готово', 'к-оракулу', 'сбой')
    'Колдун'      = @('готово', 'к-часовщику', 'сбой')
    'Инквизитор'  = @('готово', 'правки', 'к-часовщику', 'сбой')
    'Бард'        = @('готово', 'правки', 'сбой')
    'Телепат'     = @('готово', 'сбой', 'частично')
}

$script:AllowedStages = @('новая') + $script:Roles + @('готова')
$script:AllowedStatuses = @('новая', 'в работе', 'ждёт', 'готова', 'остановлена')

$script:Marker = '<!-- УДАЛИ ЭТУ СТРОКУ, КОГДА ЗАПОЛНИШЬ -->'
$script:MarkerNeedle = 'УДАЛИ ЭТУ СТРОКУ'
$script:ReasonNeedle = 'Заполнить содержательно'
$script:MaxReturnsPerStage = 2

# Корень проекта не выводится из расположения скрипта: скрипт глобальный и лежит
# вне проектов. --project, иначе вверх от текущего каталога до папки с Задачи\
# или .v8-project.json; старая раскладка .opencode\scripts внутри проекта — тоже.
function Resolve-ProjectRoot {
    param([string[]]$Argv, [string]$ScriptRoot)

    $explicit = ''
    if ($null -ne $Argv) {
        for ($index = 0; $index -lt $Argv.Count - 1; $index++) {
            if ([string]$Argv[$index] -eq '--project') { $explicit = [string]$Argv[$index + 1]; break }
        }
    }
    if ($explicit) {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($explicit)
        if (-not [System.IO.Directory]::Exists($full)) {
            $script:AbortText = 'ошибка: аргумент: каталог проекта не найден: ' + $explicit
            $script:ExitCode = 1
            throw (New-Object System.Exception($script:AbortMarker))
        }
        return (Get-Item -LiteralPath $full).FullName.TrimEnd('\')
    }

    $directory = (Get-Location).ProviderPath
    $candidate = $directory
    while ($candidate) {
        if ([System.IO.Directory]::Exists((Join-Path $candidate 'Задачи')) -or
            [System.IO.File]::Exists((Join-Path $candidate '.v8-project.json'))) {
            return $candidate.TrimEnd('\')
        }
        $parent = [System.IO.Path]::GetDirectoryName($candidate)
        if (-not $parent -or $parent -eq $candidate) { break }
        $candidate = $parent
    }

    if ($ScriptRoot) {
        $scriptsParent = [System.IO.Path]::GetDirectoryName($ScriptRoot)
        if ($scriptsParent -and [System.IO.Path]::GetFileName($scriptsParent) -eq '.opencode') {
            return [System.IO.Path]::GetDirectoryName($scriptsParent)
        }
    }
    return $directory.TrimEnd('\')
}

$script:Root = Resolve-ProjectRoot -Argv @($args) -ScriptRoot $PSScriptRoot
$script:TasksRoot = Join-Path $script:Root 'Задачи'
$script:TemplateDir = Join-Path $script:TasksRoot '_Шаблон'
$script:StateName = 'Состояние.json'
$script:EventsName = 'Журнал.jsonl'
$script:TaskFileName = 'Задача.md'
$script:LockName = 'Состояние.lock'
$script:NumberLockName = '.номер.lock'
$script:RepairName = 'ТРЕБУЕТСЯ-ПОЧИНКА.txt'

# Разделы артефакта по ролям. У часовщика два файла — план и приёмка.
$script:Tails = @{
    'Оракул'            = @(
        '## Что понятно',
        '<!-- требования и границы, без пересказа постановки -->',
        '',
        '## Вопросы',
        '<!-- что нужно уточнить у человека, или «нет» -->',
        '',
        '## Допущения',
        '<!-- на чём строим, если ответа нет -->',
        '',
        '## Не проверено',
        '<!-- что осталось за рамками, или «нет» -->'
    )
    'Часовщик/План'    = @(
        '## План',
        '<!-- шаги работ: что и в каком порядке -->',
        '',
        '## Риски',
        '<!-- что может пойти не так, или «нет» -->'
    )
    'Часовщик/Приёмка' = @(
        '## Приёмка',
        '<!-- проверяемые пункты: что смотреть и чем проверять -->',
        '',
        '## Не проверено',
        '<!-- что осталось за рамками, или «нет» -->'
    )
    'Колдун'           = @(
        '## Что сделано',
        '<!-- заполнить -->',
        '',
        '## Проверки',
        '<!-- какие проверки прогнаны и с каким результатом -->',
        '',
        '## Ответ по дефектам',
        '<!-- D1 — исправлено; D2 — не воспроизводится; D3 — не согласен, причина -->',
        '',
        '## Не проверено',
        '<!-- что осталось за рамками, или «нет» -->'
    )
    'Инквизитор'       = @(
        '## Проверки по приёмке',
        '<!-- по пунктам: что проверил, чем, результат -->',
        '',
        '## Дефекты',
        '<!-- D1 — что не так, пункт приёмки; нет дефектов — «нет» -->',
        '',
        '## Не проверено',
        '<!-- что осталось за рамками, или «нет» -->'
    )
    'Бард'             = @(
        '## Что изменилось',
        '<!-- что человек теперь видит и может сделать; названия — как в интерфейсе -->',
        '',
        '## Как проверить',
        '<!-- по шагам и контрольный пример на конкретных данных -->',
        '',
        '## Предупреждения',
        '<!-- что необратимо или требует отдельной установки; «нет» — если предупреждать не о чем -->',
        '',
        '## Ограничения',
        '<!-- чего гайд не покрывает, что не проверено, или «нет» -->'
    )
    'Телепат'          = @(
        '## Что синхронизировано',
        '<!-- какие данные, откуда и куда -->',
        '',
        '## Расхождения',
        '<!-- что не сошлось, или «нет» -->',
        '',
        '## Не проверено',
        '<!-- что осталось за рамками, или «нет» -->'
    )
}

$script:DefaultTaskMd = @'
# {{TASK}} — {{TITLE}}

- **Дата:** {{DATE}}
- **Маршрут:** {{ROUTE}}
- **Состояние:** в `Состояние.json`, смотреть командой `powershell -NoProfile -File "$env:USERPROFILE\.config\opencode\scripts\taskctl.ps1" status --task {{TASK}}`

## Что сделать

Заполнить постановку: какую работу надо выполнить.

## Зачем

Что изменится, когда задача закрыта.

## Критерий готовности

- [ ] Заполнить.

## Заметки человека

Ограничения, доступы, ссылки.
'@

# --- мелкие утилиты ----------------------------------------------------------

function Get-UtcNow {
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function ConvertFrom-Timestamp([string]$Text) {
    if (-not $Text) { return $null }
    $value = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $ok = [DateTime]::TryParseExact($Text, 'yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$value)
    if ($ok) { return $value }
    return $null
}

# PowerShell 7 превращает строки времени из JSON в DateTime. Возвращаем канонический вид,
# иначе после первого же изменения состояние запишется в чужом формате.
function ConvertTo-TimestampText($Value) {
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    return [string]$Value
}

function ConvertFrom-TimeValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime() }
    return ConvertFrom-Timestamp ([string]$Value)
}

function Get-Plural([int]$Number, [string]$One, [string]$Few, [string]$Many) {
    $n = [Math]::Abs($Number)
    if (($n % 10) -eq 1 -and ($n % 100) -ne 11) { return $One }
    if (($n % 10) -ge 2 -and ($n % 10) -le 4 -and -not (($n % 100) -ge 12 -and ($n % 100) -le 14)) { return $Few }
    return $Many
}

function Format-Duration([int]$Total) {
    if ($Total -lt 0) { $Total = 0 }
    if ($Total -lt 60) { return ([string]$Total) + 'с' }
    if ($Total -lt 3600) {
        $minutes = [int][Math]::Floor($Total / 60)
        $seconds = $Total % 60
        if ($seconds -eq 0) { return ([string]$minutes) + 'м' }
        return ([string]$minutes) + 'м ' + ([string]$seconds) + 'с'
    }
    $hours = [int][Math]::Floor($Total / 3600)
    $rest = [int][Math]::Floor(($Total % 3600) / 60)
    if ($rest -eq 0) { return ([string]$hours) + 'ч' }
    return ([string]$hours) + 'ч ' + ([string]$rest) + 'м'
}

function Get-LineCount([string]$Text) {
    if ($Text.Length -eq 0) { return 0 }
    $lines = [regex]::Split($Text, "\r\n|\r|\n")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { return $lines.Count - 1 }
    return $lines.Count
}

function Write-TextFile([string]$Path, [string]$Text) {
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if ($directory -and -not [System.IO.Directory]::Exists($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    $Text = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TextFile([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    if ($null -eq $property.Value) { return $Default }
    return $property.Value
}

function Set-Prop($Object, [string]$Name, $Value) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

# Единая точка отказа: готовит «ошибка: <уточнение>: <текст>» и прерывает команду.
# Текст буферизуется и печатается в Invoke-Main: сообщение из функции, чей результат
# присваивают переменной, иначе теряется вместе с присваиванием.
# Блокировки снимаются в finally, потому что это исключение, а не exit.
function Invoke-Abort([string]$Kind, [string]$Message, [int]$Code) {
    if ($Kind) {
        $script:AbortText = 'ошибка: ' + $Kind + ': ' + $Message
    } else {
        $script:AbortText = 'ошибка: ' + $Message
    }
    $script:ExitCode = $Code
    throw (New-Object System.Exception($script:AbortMarker))
}

function Write-WarningLine([string]$Message) {
    try { [Console]::Error.WriteLine('внимание: ' + $Message) } catch { Write-Output ('внимание: ' + $Message) }
}

# Текст исключения без обёртки PowerShell («Exception calling "Open" with ...»):
# причина должна быть видна, а не спрятана за формулировкой вызова метода.
function Get-ExceptionText($ErrorRecord) {
    $exception = $ErrorRecord.Exception
    if ($null -eq $exception) { return '' }
    if ($exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $exception.InnerException) {
        return [string]$exception.InnerException.Message
    }
    return [string]$exception.Message
}

# ConvertTo-Json в PowerShell 5.1 экранирует кириллицу как \uXXXX.
# Состояние читает человек, поэтому разворачиваем такие последовательности обратно.
# Управляющие символы (U+0000–U+001F), кавычка и обратный слэш остаются escape-ами:
# иначе файл перестаёт быть JSON по стандарту.
function ConvertTo-ReadableJson([string]$Json) {
    $builder = New-Object System.Text.StringBuilder
    $length = $Json.Length
    $index = 0
    while ($index -lt $length) {
        $symbol = $Json[$index]
        if ($symbol -ne [char]'\') {
            [void]$builder.Append($symbol)
            $index++
            continue
        }
        if ($index + 1 -ge $length) {
            [void]$builder.Append($symbol)
            $index++
            continue
        }
        $next = $Json[$index + 1]
        if ($next -eq [char]'u' -and $index + 5 -lt $length) {
            $hex = $Json.Substring($index + 2, 4)
            if ($hex -match '^[0-9a-fA-F]{4}$') {
                $code = [Convert]::ToInt32($hex, 16)
                $safe = ($code -ge 0x20) -and ($code -ne 0x22) -and ($code -ne 0x5C)
                if ($safe -and $code -ge 0xD800 -and $code -le 0xDBFF -and $index + 11 -lt $length -and $Json.Substring($index + 6, 2) -eq '\u') {
                    $lowHex = $Json.Substring($index + 8, 4)
                    if ($lowHex -match '^[0-9a-fA-F]{4}$') {
                        $low = [Convert]::ToInt32($lowHex, 16)
                        if ($low -ge 0xDC00 -and $low -le 0xDFFF) {
                            $point = 0x10000 + (($code - 0xD800) * 0x400) + ($low - 0xDC00)
                            [void]$builder.Append([char]::ConvertFromUtf32($point))
                            $index += 12
                            continue
                        }
                    }
                }
                if ($safe -and -not ($code -ge 0xD800 -and $code -le 0xDFFF)) {
                    [void]$builder.Append([char]$code)
                    $index += 6
                    continue
                }
            }
        }
        [void]$builder.Append($symbol).Append($next)
        $index += 2
    }
    return $builder.ToString()
}

# --- блокировки --------------------------------------------------------------

function Read-LockInfo([string]$Path) {
    $info = [pscustomobject]@{ 'Pid' = ''; 'Time' = ''; 'Node' = ''; 'Stamp' = $null }
    try {
        $text = Read-TextFile $Path
        foreach ($line in [regex]::Split($text, "\r\n|\r|\n")) {
            if ($line -match '^\s*pid\s*=\s*(.+)$') { $info.Pid = $Matches[1].Trim() }
            elseif ($line -match '^\s*время\s*=\s*(.+)$') { $info.Time = $Matches[1].Trim() }
            elseif ($line -match '^\s*узел\s*=\s*(.+)$') { $info.Node = $Matches[1].Trim() }
        }
    } catch { }
    if ($info.Time) { $info.Stamp = ConvertFrom-Timestamp $info.Time }
    if ($null -eq $info.Stamp) {
        try { $info.Stamp = [System.IO.File]::GetLastWriteTimeUtc($Path) } catch { }
    }
    return $info
}

function Test-LockStale($Info) {
    if ($null -eq $Info -or $null -eq $Info.Stamp) { return $false }
    return (([DateTime]::UtcNow - $Info.Stamp).TotalMinutes -gt $script:LockStaleMinutes)
}

# Берёт блокировку эксклюзивно и возвращает объект с путём; nil — не бывает:
# либо блокировка взята, либо команда завершается кодом 4.
function Enter-Lock([string]$Path, [string]$Subject, [int]$Attempts, [int]$DelayMs) {
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $text = 'pid=' + $PID + "`n" + 'время=' + (Get-UtcNow) + "`n" + 'узел=' + [System.Environment]::MachineName + "`n"
            $bytes = $script:Utf8NoBom.GetBytes($text)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            $stream.Close()
            $stream = $null
            return [pscustomobject]@{ 'Path' = $Path; 'Held' = $true }
        } catch [System.IO.IOException] {
            if ($null -ne $stream) { try { $stream.Close() } catch { } }
        } catch {
            if ($null -ne $stream) { try { $stream.Close() } catch { } }
            Invoke-Abort 'запись' ('не удалось создать блокировку ' + $Path + ': ' + (Get-ExceptionText $_)) 3
        }

        if ([System.IO.File]::Exists($Path)) {
            $info = Read-LockInfo $Path
            if (Test-LockStale $info) {
                Write-WarningLine ('снята брошенная блокировка ' + (Split-Path -Leaf $Path) + ' (pid=' + $info.Pid + ', ' + $info.Time + ')')
                try { [System.IO.File]::Delete($Path) } catch { }
                $attempt--
                if ($attempt -lt 0) { $attempt = 0 }
                continue
            }
        }
        if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds $DelayMs }
    }

    $info = Read-LockInfo $Path
    $who = ''
    if ($info.Pid) { $who = [string]$info.Pid }
    if ($info.Time) {
        if ($who) { $who = $who + ' ' + $info.Time } else { $who = [string]$info.Time }
    } elseif ($who) {
        $who = $who + ' (время неизвестно)'
    }
    if (-not $who) { $who = 'другой процесс' }
    Invoke-Abort '' ($Subject + ' занята: ' + $who) 4
}

function Exit-Lock($Lock) {
    if ($null -eq $Lock -or -not $Lock.Held) { return }
    try {
        if ([System.IO.File]::Exists($Lock.Path)) { [System.IO.File]::Delete($Lock.Path) }
    } catch {
        Write-WarningLine ('не удалось снять блокировку ' + $Lock.Path + ': ' + (Get-ExceptionText $_))
    }
}

# Частично записанная строка журнала: обрезаем хвост до последнего перевода строки.
function Repair-JournalTail([string]$Folder) {
    $path = Join-Path $Folder $script:EventsName
    if (-not [System.IO.File]::Exists($path)) { return }
    $length = (New-Object System.IO.FileInfo($path)).Length
    if ($length -le 0) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes[$bytes.Length - 1] -eq 0x0A) { return }
    $cut = -1
    for ($index = $bytes.Length - 1; $index -ge 0; $index--) {
        if ($bytes[$index] -eq 0x0A) { $cut = $index; break }
    }
    $keep = $cut + 1
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    try { $stream.SetLength($keep) } finally { $stream.Close() }
    Write-WarningLine ('журнал ' + $script:EventsName + ' был недописан, обрезан до последней целой строки')
}

# --- файлы задачи ------------------------------------------------------------

function Get-TasksDir {
    if (-not [System.IO.Directory]::Exists($script:TasksRoot)) {
        [void][System.IO.Directory]::CreateDirectory($script:TasksRoot)
    }
    return $script:TasksRoot
}

function Resolve-TaskFolder([string]$Argument) {
    $raw = $Argument.Trim()
    if (-not $raw) { return $null }

    if (Test-Path -LiteralPath $raw -PathType Container) {
        if (Test-Path -LiteralPath (Join-Path $raw $script:StateName)) {
            return (Resolve-Path -LiteralPath $raw).Path
        }
    }

    $tasks = Get-TasksDir
    $direct = Join-Path $tasks $raw
    if (Test-Path -LiteralPath $direct -PathType Container) { return $direct }

    if ($raw -match '^(\d+)') {
        $number = ([int]$Matches[1]).ToString('000')
        foreach ($folder in (Get-ChildItem -LiteralPath $tasks -Directory | Sort-Object Name)) {
            if ($folder.Name -eq '_Шаблон') { continue }
            if ($folder.Name -match '^(\d+)\s*-') {
                if (([int]$Matches[1]).ToString('000') -eq $number) { return $folder.FullName }
            }
        }
    }
    return $null
}

function Load-State($Folder) {
    $path = Join-Path $Folder $script:StateName
    if (-not [System.IO.File]::Exists($path)) {
        Invoke-Abort 'данные' ('в папке ' + (Split-Path -Leaf $Folder) + ' нет ' + $script:StateName) 2
    }
    try {
        $state = ConvertFrom-Json (Read-TextFile $path)
    } catch {
        Invoke-Abort 'данные' ($script:StateName + ' не разобран: ' + (Get-ExceptionText $_)) 2
    }
    foreach ($name in @('создано', 'обновлено')) {
        $property = $state.PSObject.Properties[$name]
        if ($null -ne $property -and $property.Value -is [datetime]) { $property.Value = ConvertTo-TimestampText $property.Value }
    }
    $current = Get-Prop $state 'текущий'
    if ($null -ne $current) {
        $property = $current.PSObject.Properties['начат']
        if ($null -ne $property -and $property.Value -is [datetime]) { $property.Value = ConvertTo-TimestampText $property.Value }
    }
    $waiting = Get-Prop $state 'ожидание'
    if ($null -ne $waiting) {
        $property = $waiting.PSObject.Properties['с']
        if ($null -ne $property -and $property.Value -is [datetime]) { $property.Value = ConvertTo-TimestampText $property.Value }
    }
    return $state
}

function Read-Events($Folder) {
    $path = Join-Path $Folder $script:EventsName
    if (-not [System.IO.File]::Exists($path)) { return @() }
    $text = Read-TextFile $path
    $events = New-Object System.Collections.ArrayList
    $number = 0
    foreach ($line in [regex]::Split($text, "\r\n|\r|\n")) {
        $number++
        if ($line.Trim().Length -eq 0) { continue }
        try {
            $event = ConvertFrom-Json $line
        } catch {
            Invoke-Abort 'данные' ('битая строка ' + $number + ' в ' + $script:EventsName) 2
        }
        $property = $event.PSObject.Properties['время']
        if ($null -ne $property -and $property.Value -is [datetime]) { $property.Value = ConvertTo-TimestampText $property.Value }
        [void]$events.Add($event)
    }
    return $events.ToArray()
}

function New-Event($State, [string]$Kind, $Fields) {
    $sequence = [int](Get-Prop $State 'номер_события' 0) + 1
    $event = [ordered]@{
        'номер'   = $sequence
        'время'   = (Get-UtcNow)
        'событие' = $Kind
        'задача'  = [string](Get-Prop $State 'задача' '')
    }
    foreach ($key in @('роль', 'круг', 'артефакт', 'вердикт', 'секунд', 'причина', 'примечание', 'этап', 'возврат', 'хэши', 'кто', 'ссылка')) {
        if (-not $Fields.ContainsKey($key)) { continue }
        $value = $Fields[$key]
        if ($null -eq $value) { continue }
        if ($value -is [string] -and $value -eq '') { continue }
        $event[$key] = $value
    }
    Set-Prop $State 'номер_события' $sequence
    return [pscustomobject]$event
}

# --- атомарная запись состояния и журнала ------------------------------------

function ConvertTo-StateText($State) {
    Set-Prop $State 'обновлено' (Get-UtcNow)
    $json = ConvertTo-Json $State -Depth 10
    return ((ConvertTo-ReadableJson $json) + "`n")
}

function ConvertTo-EventLine($Event) {
    $json = ConvertTo-Json $Event -Depth 10 -Compress
    return ((ConvertTo-ReadableJson $json) + "`n")
}

function Save-AtomicText([string]$Path, [string]$Text) {
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if ($directory -and -not [System.IO.Directory]::Exists($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    $Text = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = $script:Utf8NoBom.GetBytes($Text)
    Save-AtomicBytes $Path $bytes
}

function Save-AtomicBytes([string]$Path, [byte[]]$Bytes) {
    $temp = $Path + '.tmp-' + $PID
    try {
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temp, $Path, [NullString]::Value)
        } else {
            [System.IO.File]::Move($temp, $Path)
        }
    } catch {
        try { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } } catch { }
        throw
    }
}

function Write-RepairNote([string]$Folder, [string]$Details) {
    $path = Join-Path $Folder $script:RepairName
    $text = @(
        'Запись сорвалась и откат не удался — нужна ручная починка.',
        '',
        ('Когда: ' + (Get-UtcNow)),
        ('Папка: ' + (Split-Path -Leaf $Folder)),
        ('Что случилось: ' + $Details),
        '',
        'Что проверить:',
        '1. Состояние.json и Журнал.jsonl разошлись (номер_события не равен числу строк).',
        '2. Сравни их с последним успешным состоянием и решением человека.',
        '3. Пока файл здесь, задачи этой папки считай неисправными.',
        '4. После починки удали этот файл и запусти validate.'
    ) -join "`n"
    try { Write-TextFile $path ($text + "`n") } catch { }
}

# Единая запись: состояние атомарно, затем журнал; при сбое журнала — откат.
function Save-Transaction($Folder, $State, $NewEvents) {
    $statePath = Join-Path $Folder $script:StateName
    $journalPath = Join-Path $Folder $script:EventsName

    $oldState = $null
    if ([System.IO.File]::Exists($statePath)) {
        try { $oldState = [System.IO.File]::ReadAllBytes($statePath) } catch { $oldState = $null }
    }

    $journalExisted = [System.IO.File]::Exists($journalPath)
    $oldLength = 0
    if ($journalExisted) { $oldLength = (New-Object System.IO.FileInfo($journalPath)).Length }

    $stateText = ConvertTo-StateText $State

    try {
        Save-AtomicText $statePath $stateText
    } catch {
        Invoke-Abort 'запись' ('не удалось записать ' + $script:StateName + ': ' + (Get-ExceptionText $_)) 3
    }

    try {
        if ($null -ne $NewEvents -and @($NewEvents).Count -gt 0) {
            $builder = New-Object System.Text.StringBuilder
            foreach ($event in @($NewEvents)) { [void]$builder.Append((ConvertTo-EventLine $event)) }
            $bytes = $script:Utf8NoBom.GetBytes($builder.ToString())
            $stream = [System.IO.File]::Open($journalPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } finally {
                $stream.Close()
            }
        }
    } catch {
        $details = (Get-ExceptionText $_)
        $restored = $true
        try {
            if ($null -ne $oldState) {
                Save-AtomicBytes $statePath $oldState
            } elseif ([System.IO.File]::Exists($statePath)) {
                [System.IO.File]::Delete($statePath)
            }
        } catch { $restored = $false }
        try {
            if ($journalExisted) {
                $nowLength = -1
                if ([System.IO.File]::Exists($journalPath)) { $nowLength = (New-Object System.IO.FileInfo($journalPath)).Length }
                if ($nowLength -ne $oldLength) {
                    $stream = [System.IO.File]::Open($journalPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
                    try { $stream.SetLength($oldLength) } finally { $stream.Close() }
                }
            } elseif ([System.IO.File]::Exists($journalPath)) {
                if ((New-Object System.IO.FileInfo($journalPath)).Length -gt 0) { [System.IO.File]::Delete($journalPath) }
            }
        } catch { $restored = $false }

        if (-not $restored) {
            Write-RepairNote $Folder ('не удалось дописать ' + $script:EventsName + ' и откатить состояние: ' + $details)
            Invoke-Abort 'запись' ('восстановление не завершено, рядом с состоянием лежит ' + $script:RepairName) 3
        }
        Invoke-Abort 'запись' ('не удалось дописать ' + $script:EventsName + ': ' + $details + '; состояние и журнал возвращены к прежнему виду, команду можно повторить') 3
    }
}

# --- артефакты ---------------------------------------------------------------

function Get-RoleArtifactRel([string]$Role, [int]$Round) {
    $prefix = 'Круг-' + $Round.ToString('00')
    if ($Role -ceq 'Часовщик') { return 'Артефакты/Часовщик/' + $prefix + '-План.md' }
    return 'Артефакты/' + $Role + '/' + $prefix + '.md'
}

function Get-AcceptanceRel([int]$Round) {
    return 'Артефакты/Часовщик/Круг-' + $Round.ToString('00') + '-Приёмка.md'
}

function Get-ArtifactPaths([string]$Role, [int]$Round) {
    if ($Role -ceq 'Часовщик') {
        return @((Get-RoleArtifactRel $Role $Round), (Get-AcceptanceRel $Round))
    }
    return @((Get-RoleArtifactRel $Role $Round))
}

function Get-RoleDir($Folder, [string]$Role) {
    return Join-Path (Join-Path $Folder 'Артефакты') $Role
}

# Имя артефакта Барда: строго «Круг-NN.md» или «Круг-NN.pdf».
# Круг-010.pdf и Круг-01-old.pdf артефактами круга 1 не считаются.
function Get-BardArtifactRel([int]$Round, [string]$Extension) {
    return 'Артефакты/Бард/Круг-' + $Round.ToString('00') + '.' + $Extension
}

function Get-TextArtifactProblem([string]$FullPath, [string]$Rel) {
    if (-not [System.IO.File]::Exists($FullPath)) { return 'нет файла артефакта ' + $Rel }
    try {
        $text = Read-TextFile $FullPath
    } catch {
        return 'не удалось прочитать файл артефакта ' + $Rel + ': ' + (Get-ExceptionText $_)
    }
    if ($text.Trim().Length -eq 0) { return 'файл артефакта ' + $Rel + ' пустой' }
    if ($text.Contains($script:MarkerNeedle)) {
        return 'скелет не заполнен: в ' + $Rel + ' осталась служебная строка «УДАЛИ ЭТУ СТРОКУ»'
    }
    return $null
}

function Get-PdfArtifactProblem([string]$FullPath, [string]$Rel) {
    if (-not [System.IO.File]::Exists($FullPath)) { return 'нет файла артефакта ' + $Rel }
    if ((New-Object System.IO.FileInfo($FullPath)).Length -eq 0) { return 'файл артефакта ' + $Rel + ' пустой' }
    return $null
}

# Факты о файле артефакта: есть ли он, какого размера и остался ли в нём маркер скелета.
function Get-ArtifactFacts([string]$FullPath) {
    $facts = [pscustomobject]@{ 'Exists' = $false; 'Size' = [long]0; 'Marker' = $false; 'Error' = '' }
    if (-not [System.IO.File]::Exists($FullPath)) { return $facts }
    $facts.Exists = $true
    $facts.Size = (New-Object System.IO.FileInfo($FullPath)).Length
    if ($FullPath -match '\.md$' -and $facts.Size -gt 0) {
        try {
            $facts.Marker = (Read-TextFile $FullPath).Contains($script:MarkerNeedle)
        } catch {
            $facts.Error = (Get-ExceptionText $_)
        }
    }
    return $facts
}

# Состояние артефакта ОТКРЫТОГО этапа. Пока роль работает, в артефакте лежит скелет
# с маркером — это нормальное состояние, поэтому отсутствие файла и пустота считаются
# ошибкой, а незаполненный скелет — только предупреждением. Для закрытого этапа маркер
# остаётся ошибкой: там он означает, что этап закрыли, не заполнив скелет
# (см. Resolve-RoleArtifact).
function Get-OpenArtifactStatus($Folder, [string]$Role, [int]$Round) {
    $problems = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $chosen = ''

    if ($Role -ceq 'Бард') {
        $mdRel = Get-BardArtifactRel $Round 'md'
        $pdfRel = Get-BardArtifactRel $Round 'pdf'
        $md = Get-ArtifactFacts (Join-Path $Folder $mdRel)
        $pdf = Get-ArtifactFacts (Join-Path $Folder $pdfRel)
        if ($md.Error) {
            [void]$problems.Add('не удалось прочитать файл артефакта ' + $mdRel + ': ' + $md.Error)
            if ($pdf.Exists -and $pdf.Size -gt 0) { $chosen = $pdfRel } else { $chosen = $mdRel }
            return [pscustomobject]@{ 'Rel' = $chosen; 'Problems' = $problems.ToArray(); 'Warnings' = $warnings.ToArray() }
        }
        if ($md.Exists -and $md.Size -gt 0 -and -not $md.Marker) {
            $chosen = $mdRel
        } elseif ($pdf.Exists -and $pdf.Size -gt 0) {
            $chosen = $pdfRel
        } elseif ($md.Exists -and $md.Size -gt 0) {
            $chosen = $mdRel
            [void]$warnings.Add('скелет не заполнен: в ' + $mdRel + ' осталась служебная строка «УДАЛИ ЭТУ СТРОКУ»')
        } elseif ($pdf.Exists -or $md.Exists) {
            $empty = $mdRel
            if (-not $md.Exists) { $empty = $pdfRel }
            [void]$problems.Add('файл артефакта ' + $empty + ' пустой')
        } else {
            [void]$problems.Add('нет файла артефакта: нужен ' + $mdRel + ' или ' + $pdfRel)
        }
        return [pscustomobject]@{ 'Rel' = $chosen; 'Problems' = $problems.ToArray(); 'Warnings' = $warnings.ToArray() }
    }

    foreach ($rel in (Get-ArtifactPaths $Role $Round)) {
        if (-not $chosen) { $chosen = $rel }
        $facts = Get-ArtifactFacts (Join-Path $Folder $rel)
        if (-not $facts.Exists) {
            [void]$problems.Add('нет файла артефакта ' + $rel)
            continue
        }
        if ($facts.Size -le 0) {
            [void]$problems.Add('файл артефакта ' + $rel + ' пустой')
            continue
        }
        if ($facts.Error) {
            [void]$problems.Add('не удалось прочитать файл артефакта ' + $rel + ': ' + $facts.Error)
            continue
        }
        if ($facts.Marker) {
            [void]$warnings.Add('скелет не заполнен: в ' + $rel + ' осталась служебная строка «УДАЛИ ЭТУ СТРОКУ»')
        }
    }
    return [pscustomobject]@{ 'Rel' = $chosen; 'Problems' = $problems.ToArray(); 'Warnings' = $warnings.ToArray() }
}

# Возвращает Rel реального артефакта круга и Problem, если артефакта нет.
# Правило Барда: заполненный MD важнее PDF; пустой MD не мешает PDF.
function Resolve-RoleArtifact($Folder, [string]$Role, [int]$Round) {
    if ($Role -ceq 'Бард') {
        $mdRel = Get-BardArtifactRel $Round 'md'
        $pdfRel = Get-BardArtifactRel $Round 'pdf'
        $mdFull = Join-Path $Folder $mdRel
        $pdfFull = Join-Path $Folder $pdfRel
        $mdProblem = Get-TextArtifactProblem $mdFull $mdRel
        $pdfProblem = Get-PdfArtifactProblem $pdfFull $pdfRel
        if ($null -eq $mdProblem) { return [pscustomobject]@{ 'Rel' = $mdRel; 'Problem' = $null } }
        if ($null -eq $pdfProblem) { return [pscustomobject]@{ 'Rel' = $pdfRel; 'Problem' = $null } }
        $why = $mdProblem + '; ' + $pdfProblem
        return [pscustomobject]@{ 'Rel' = $mdRel; 'Problem' = ('нет артефакта круга ' + $Round + ': нужен ' + $mdRel + ' или ' + $pdfRel + ' (' + $why + ')') }
    }

    $first = $null
    foreach ($rel in (Get-ArtifactPaths $Role $Round)) {
        if ($null -eq $first) { $first = $rel }
        $problem = Get-TextArtifactProblem (Join-Path $Folder $rel) $rel
        if ($problem) { return [pscustomobject]@{ 'Rel' = $rel; 'Problem' = $problem } }
    }
    return [pscustomobject]@{ 'Rel' = $first; 'Problem' = $null }
}

function Test-Artifact($Folder, [string]$Role, [int]$Round) {
    return (Resolve-RoleArtifact $Folder $Role $Round).Problem}

function Get-ArtifactLineCount($Folder, [string]$Role, [int]$Round) {
    $resolved = Resolve-RoleArtifact $Folder $Role $Round
    if ($resolved.Problem) { return -1 }
    if ($resolved.Rel -notmatch '\.md$') { return -1 }
    $full = Join-Path $Folder $resolved.Rel
    if (-not [System.IO.File]::Exists($full)) { return -1 }
    return Get-LineCount (Read-TextFile $full)
}

# SHA-256 файла. Get-FileHash намеренно не используем: в Windows PowerShell он живёт
# в модуле Microsoft.PowerShell.Utility, а дочерний процесс 5.1, запущенный из pwsh
# с унаследованным PSModulePath, подхватывает одноимённый модуль PowerShell 7, не
# загружает его — и команда просто пропадает. Считаем напрямую через .NET.
# Три попытки: файл может быть ещё занят записью или проверкой антивируса.
# Возвращаем и хэш, и текст ошибки: молча пустая строка уже один раз спрятала дефект.
function Get-FileHashText([string]$Path) {
    $lastError = ''
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $stream = $null
        $sha = $null
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $bytes = $sha.ComputeHash($stream)
            $text = ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
            return [pscustomobject]@{ 'Hash' = $text; 'Error' = '' }
        } catch {
            $lastError = (Get-ExceptionText $_)
        } finally {
            if ($null -ne $stream) { try { $stream.Close() } catch { } }
            if ($null -ne $sha) { try { $sha.Dispose() } catch { } }
        }
        if ($attempt -lt 3) { Start-Sleep -Milliseconds (60 * $attempt) }
    }
    return [pscustomobject]@{ 'Hash' = ''; 'Error' = $lastError }
}

# Хэши артефактов круга: удачные и сбои с текстом причины. finish по этому набору
# отличает «хэшировать нечего» от «посчитать не удалось».
function Get-ArtifactHashes($Folder, [string]$Role, [int]$Round) {
    $hashes = [ordered]@{}
    $failures = New-Object System.Collections.ArrayList
    $targets = New-Object System.Collections.ArrayList

    if ($Role -ceq 'Бард') {
        $resolved = Resolve-RoleArtifact $Folder $Role $Round
        if (-not $resolved.Problem) { [void]$targets.Add($resolved.Rel) }
    } else {
        foreach ($rel in (Get-ArtifactPaths $Role $Round)) {
            if ([System.IO.File]::Exists((Join-Path $Folder $rel))) { [void]$targets.Add($rel) }
        }
    }

    foreach ($rel in $targets.ToArray()) {
        $result = Get-FileHashText (Join-Path $Folder $rel)
        if ($result.Error) {
            [void]$failures.Add([pscustomobject]@{ 'Rel' = $rel; 'Message' = $result.Error })
            continue
        }
        if ($result.Hash) { $hashes[$rel] = $result.Hash }
    }
    return [pscustomobject]@{ 'Hashes' = $hashes; 'Failures' = $failures.ToArray() }
}

# Текст раздела артефакта (## Заголовок) без самого заголовка.
function Get-SectionText([string]$Text, [string]$Heading) {
    $lines = [regex]::Split($Text, "\r\n|\r|\n")
    $collecting = $false
    $found = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        if (-not $collecting) {
            if ($line -match ('^#{1,6}\s+' + [regex]::Escape($Heading) + '\s*$')) { $collecting = $true }
            continue
        }
        if ($line -match '^#{1,6}\s+') { break }
        [void]$found.Add($line)
    }
    return ((@($found.ToArray())) -join "`n").Trim()
}

# Путь к существующему артефакту, упомянутому в тексте.
# Порядок разбора: сначала ссылка в обратных кавычках целиком (единственный способ
# без потерь передать путь с пробелами), затем путь по известным расширениям с
# учётом пробелов между словами, затем прежний разбор одного слова — запасной.
function Find-ArtifactRef($Folder, [string]$Text) {
    $extensions = 'md|pdf|txt|jsonl|json|ps1'

    $resolveCandidate = {
        param([string]$candidate)
        $candidate = $candidate.Trim()
        $candidate = [regex]::Replace($candidate, '^[`"''«»(\[<]+', '')
        $candidate = [regex]::Replace($candidate, '[`"''»)\]>.,;:!?]+$', '')
        $candidate = $candidate.Trim()
        $candidate = $candidate.Replace('\', '/').TrimStart('./')
        if (-not $candidate) { return $null }
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            try {
                if ([System.IO.File]::Exists($candidate)) { return $candidate }
            } catch { }
            return $null
        }
        foreach ($base in @($Folder, $script:Root)) {
            try {
                $full = Join-Path $base $candidate
                if ([System.IO.File]::Exists($full)) { return $candidate }
            } catch { }
        }
        return $null
    }

    # 1. Обратные кавычки: `путь с пробелами.md` — берётся целиком.
    foreach ($match in [regex]::Matches($Text, '`([^`\r\n]+)`')) {
        $found = & $resolveCandidate $match.Groups[1].Value
        if ($found) { return $found }
    }

    # 2. Расширение в токене: собираем путь из токена и до 4 слов перед ним —
    #    так ловится «Задачи/002 - 2026-11-02/Артефакты/…». Короткий вариант
    #    проверяется первым: прозе перед путём склеиться не даём.
    $tokens = @([regex]::Split($Text, '\s+') | Where-Object { $_ })
    for ($index = 0; $index -lt $tokens.Count; $index++) {
        $token = [regex]::Replace($tokens[$index], '^[`"''«»(\[<]+', '')
        $token = [regex]::Replace($token, '[`"''»)\]>.,;:!?]+$', '')
        if ($token -notmatch ('\.(?:' + $extensions + ')$')) { continue }
        for ($start = $index; $start -ge 0 -and ($index - $start) -le 4; $start--) {
            $parts = @()
            for ($k = $start; $k -le $index; $k++) { $parts += $tokens[$k] }
            $found = & $resolveCandidate ($parts -join ' ')
            if ($found) { return $found }
        }
    }

    # 3. Запасной разбор: одно слово без пробелов.
    foreach ($match in [regex]::Matches($Text, '[^\s`"''«»()\[\]<>]+\.(?:' + $extensions + ')')) {
        $found = & $resolveCandidate $match.Value
        if ($found) { return $found }
    }
    return $null
}

# Причина возврата из артефакта инициатора: непустой раздел и существующий путь.
function Get-ReturnReason($Folder, [string]$Role, [int]$Round) {
    $resolved = Resolve-RoleArtifact $Folder $Role $Round
    if ($resolved.Problem) { return [pscustomobject]@{ 'Problem' = $resolved.Problem } }

    $sourceRel = $resolved.Rel
    if ($sourceRel -notmatch '\.md$') {
        $twin = [regex]::Replace($sourceRel, '\.pdf$', '.md')
        if ([System.IO.File]::Exists((Join-Path $Folder $twin))) {
            $sourceRel = $twin
        } else {
            return [pscustomobject]@{ 'Problem' = ('возврат требует текстового артефакта с разделом «Причина возврата», а есть только ' + $resolved.Rel) }
        }
    }

    $text = Read-TextFile (Join-Path $Folder $sourceRel)
    $reason = Get-SectionText $text 'Причина возврата'
    if (-not $reason -or $reason.Contains($script:ReasonNeedle)) {
        return [pscustomobject]@{ 'Problem' = ('в ' + $sourceRel + ' нет заполненного раздела «## Причина возврата» — при возврате он обязателен') }
    }
    $ref = Find-ArtifactRef $Folder $reason
    if (-not $ref) {
        return [pscustomobject]@{ 'Problem' = 'в разделе «Причина возврата» нужен путь к артефакту, на который ссылаются (существующий файл); путь лучше давать в обратных кавычках относительно папки задачи, например `Артефакты/Колдун/Круг-01.md`' }
    }
    return [pscustomobject]@{ 'Problem' = $null; 'Reason' = $reason; 'Ref' = $ref; 'Rel' = $resolved.Rel }
}

# --- входные данные скелета --------------------------------------------------

function New-StateObject([string]$Task, [string]$Title, [string]$Route) {
    $stamp = Get-UtcNow
    $rounds = [ordered]@{}
    $times = [ordered]@{}
    foreach ($role in $script:Roles) {
        $rounds[$role] = 0
        $times[$role] = 0
    }
    return [pscustomobject][ordered]@{
        'задача'        = $Task
        'название'      = $Title
        'маршрут'       = $Route
        'состояние'     = 'новая'
        'этап'          = 'новая'
        'круги'         = [pscustomobject]$rounds
        'текущий'       = [pscustomobject][ordered]@{ 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'начат' = '' }
        'время_сек'     = [pscustomobject]$times
        # Лимит шагов задаётся полем steps в агенте, в состоянии его нет:
        # здесь только то, что скрипт действительно проверяет.
        'пределы'       = [pscustomobject][ordered]@{ 'попыток' = 3; 'строк' = 200 }
        'возврат'       = [pscustomobject][ordered]@{ 'этап' = ''; 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'причина' = ''; 'новый_круг' = $false; 'источник' = '' }
        # Ожидание ответа снаружи: пока пусто, заполняет block --waiting.
        'ожидание'      = [pscustomobject][ordered]@{ 'кто' = ''; 'ссылка' = ''; 'с' = ''; 'этап' = ''; 'круг' = 0 }
        'номер_события' = 0
        'создано'       = $stamp
        'обновлено'     = $stamp
    }
}

function Get-RoundOf($State, [string]$Role) {
    $rounds = Get-Prop $State 'круги'
    if ($null -eq $rounds) { return 0 }
    return [int](Get-Prop $rounds $Role 0)
}

function New-EmptyReturn {
    return [pscustomobject][ordered]@{
        'этап'       = ''
        'роль'       = ''
        'круг'       = 0
        'артефакт'   = ''
        'причина'    = ''
        'новый_круг' = $false
        'источник'   = ''
    }
}

function Add-InputLine($Lines, [string]$Label, [string]$Rel, $Folder) {
    if ([System.IO.File]::Exists((Join-Path $Folder $Rel))) {
        [void]$Lines.Add('- ' + $Label + ': ' + $Rel)
    }
}

function Get-InputLines($State, [string]$Role, [int]$Round, [string]$Variant, $Folder) {
    $lines = New-Object System.Collections.ArrayList
    # Постановку получает каждая роль на любом маршруте — это правило, а не случайность.
    [void]$lines.Add('- постановка: Задача.md')

    $oracleRounds     = Get-RoundOf $State 'Оракул'
    $watchmakerRounds = Get-RoundOf $State 'Часовщик'
    $warlockRounds    = Get-RoundOf $State 'Колдун'
    $inquisitorRounds = Get-RoundOf $State 'Инквизитор'
    $bardRounds       = Get-RoundOf $State 'Бард'

    switch ($Role) {
        'Оракул' {
            if ($Round -gt 1) {
                Add-InputLine $lines 'прошлый разбор' (Get-RoleArtifactRel 'Оракул' ($Round - 1)) $Folder
                if ($bardRounds -gt 0) {
                    $doc = Resolve-RoleArtifact $Folder 'Бард' $bardRounds
                    Add-InputLine $lines 'замечания барда' $doc.Rel $Folder
                }
            }
        }
        'Часовщик' {
            if ($oracleRounds -gt 0) {
                Add-InputLine $lines 'разбор оракула' (Get-RoleArtifactRel 'Оракул' $oracleRounds) $Folder
            }
            if ($Variant -eq 'приёмка') {
                [void]$lines.Add('- план: ' + (Get-RoleArtifactRel 'Часовщик' $Round))
            }
            if ($Round -gt 1) {
                Add-InputLine $lines 'прошлый план' (Get-RoleArtifactRel 'Часовщик' ($Round - 1)) $Folder
            }
        }
        'Колдун' {
            if ($watchmakerRounds -gt 0) {
                Add-InputLine $lines 'план' (Get-RoleArtifactRel 'Часовщик' $watchmakerRounds) $Folder
                Add-InputLine $lines 'приёмка' (Get-AcceptanceRel $watchmakerRounds) $Folder
            }
            if ($Round -gt 1) {
                Add-InputLine $lines 'прошлый круг' (Get-RoleArtifactRel 'Колдун' ($Round - 1)) $Folder
                Add-InputLine $lines 'отчёт инквизитора' (Get-RoleArtifactRel 'Инквизитор' ($Round - 1)) $Folder
            }
        }
        'Инквизитор' {
            if ($watchmakerRounds -gt 0) {
                Add-InputLine $lines 'приёмка' (Get-AcceptanceRel $watchmakerRounds) $Folder
            }
            if ($warlockRounds -gt 0) {
                Add-InputLine $lines 'работа колдуна' (Get-RoleArtifactRel 'Колдун' $warlockRounds) $Folder
            }
            if ($Round -gt 1) {
                Add-InputLine $lines 'прошлый отчёт' (Get-RoleArtifactRel 'Инквизитор' ($Round - 1)) $Folder
            }
        }
        'Бард' {
            if ($oracleRounds -gt 0) {
                Add-InputLine $lines 'разбор оракула' (Get-RoleArtifactRel 'Оракул' $oracleRounds) $Folder
            }
            if ($watchmakerRounds -gt 0) {
                Add-InputLine $lines 'план' (Get-RoleArtifactRel 'Часовщик' $watchmakerRounds) $Folder
                Add-InputLine $lines 'приёмка' (Get-AcceptanceRel $watchmakerRounds) $Folder
            }
            if ($warlockRounds -gt 0) {
                Add-InputLine $lines 'работа колдуна' (Get-RoleArtifactRel 'Колдун' $warlockRounds) $Folder
            }
            if ($inquisitorRounds -gt 0) {
                Add-InputLine $lines 'отчёт инквизитора' (Get-RoleArtifactRel 'Инквизитор' $inquisitorRounds) $Folder
            }
        }
        'Телепат' {
            if ($Round -gt 1) {
                Add-InputLine $lines 'прошлый круг' (Get-RoleArtifactRel 'Телепат' ($Round - 1)) $Folder
            }
        }
    }
    return $lines.ToArray()
}

function Get-SkeletonTail([string]$Role, [string]$Variant) {
    if ($Role -ceq 'Часовщик') {
        if ($Variant -eq 'приёмка') { return $script:Tails['Часовщик/Приёмка'] }
        return $script:Tails['Часовщик/План']
    }
    return $script:Tails[$Role]
}

function New-Skeleton($State, [string]$Role, [int]$Round, [string]$Variant, $Folder) {
    $task = [string](Get-Prop $State 'задача' '')
    $title = '# Задача ' + $task + ' · ' + $Role + ' · круг ' + $Round
    if ($Variant -eq 'план') { $title += ' — план' }
    if ($Variant -eq 'приёмка') { $title += ' — приёмка' }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add($script:Marker)
    [void]$lines.Add($title)
    [void]$lines.Add('')
    [void]$lines.Add('## Входные данные')

    $inputs = @(Get-InputLines $State $Role $Round $Variant $Folder)
    $return = Get-Prop $State 'возврат'
    $returnStage = [string](Get-Prop $return 'этап' '')
    $returnRel = [string](Get-Prop $return 'артефакт' '')
    if ($returnRel -and $returnStage -ceq $Role) {
        $line = '- артефакт возврата: ' + $returnRel
        if ($inputs -notcontains $line) { $inputs += $line }
    }
    if ($inputs.Count -eq 0) {
        [void]$lines.Add('- нет')
    } else {
        foreach ($line in $inputs) { [void]$lines.Add($line) }
    }
    [void]$lines.Add('')

    if ($returnStage -ceq $Role -and [string](Get-Prop $return 'причина' '')) {
        $reason = [string](Get-Prop $return 'причина' '')
        $source = [string](Get-Prop $return 'источник' '')
        [void]$lines.Add('## Причина возврата')
        [void]$lines.Add('<!-- ' + $script:ReasonNeedle + ': что изменил по причине возврата и на что смотреть проверяющему -->')
        [void]$lines.Add('')
        if ($source -eq 'возобновление') {
            [void]$lines.Add('Человек разрешил продолжить после остановки.')
        } else {
            [void]$lines.Add('Вернул: ' + [string](Get-Prop $return 'роль' '') + ', круг ' + [string](Get-Prop $return 'круг' 0))
        }
        if ($returnRel) { [void]$lines.Add('Откуда: ' + $returnRel) }
        [void]$lines.Add('Причина: ' + $reason)
        [void]$lines.Add('')
    }

    foreach ($line in (Get-SkeletonTail $Role $Variant)) { [void]$lines.Add($line) }
    return (($lines -join "`n") + "`n")
}

# --- журнал и шаги -----------------------------------------------------------

# Куда ведёт вердикт: next — дальше по маршруту, return — назад к роли,
# blocked — остановка, done — задача закрыта. Возврат и движение вперёд
# различаются по таблице переходов, а не по тому, есть ли роль в маршруте.
function Get-Step($State, [string]$Role, [string]$Verdict) {
    $direct = ''
    if ($script:Transitions.ContainsKey($Role + '/' + $Verdict)) {
        $direct = [string]$script:Transitions[$Role + '/' + $Verdict]
    }
    if (-not $direct) { return [pscustomobject]@{ 'Kind' = 'unknown'; 'Target' = '' } }
    if ($direct -eq 'blocked') { return [pscustomobject]@{ 'Kind' = 'blocked'; 'Target' = 'blocked' } }
    if ($script:Roles -ccontains $direct) { return [pscustomobject]@{ 'Kind' = 'return'; 'Target' = $direct } }

    $route = [string](Get-Prop $State 'маршрут' '')
    if (-not $script:Routes.ContainsKey($route)) { return [pscustomobject]@{ 'Kind' = 'unknown'; 'Target' = '' } }
    $sequence = @($script:Routes[$route])
    $index = [array]::IndexOf($sequence, $Role)
    if ($index -lt 0 -or $index + 1 -ge $sequence.Count) { return [pscustomobject]@{ 'Kind' = 'done'; 'Target' = 'done' } }
    return [pscustomobject]@{ 'Kind' = 'next'; 'Target' = $sequence[$index + 1] }
}

function Get-ReturnCount($Events, [string]$Target, [int]$Exclude) {
    $count = 0
    foreach ($event in $Events) {
        if ([int](Get-Prop $event 'номер' 0) -eq $Exclude) { continue }
        if ([string](Get-Prop $event 'событие' '') -ne 'этап.финиш') { continue }
        if ([string](Get-Prop $event 'возврат' '') -ceq $Target) { $count++ }
    }
    return $count
}

# --- вывод -------------------------------------------------------------------

function Get-StageText($State) {
    $stage = [string](Get-Prop $State 'этап' '')
    $status = [string](Get-Prop $State 'состояние' '')
    $current = Get-Prop $State 'текущий'
    if ($stage -eq 'новая') {
        if ($status -eq 'остановлена') { return 'новая, остановлена' }
        if ($status -eq 'ждёт') { return 'новая, ждёт ответа' }
        return 'новая (ещё не начата)'
    }
    if ($stage -eq 'готова') { return 'готова (мимо не ходит)' }
    $round = [int](Get-Prop $current 'круг' 0)
    if ([string](Get-Prop $current 'роль' '') -ceq $stage -and $round -gt 0) {
        return $stage + ', идёт круг ' + $round
    }
    $nextRound = (Get-RoundOf $State $stage) + 1
    if ($status -eq 'остановлена') { return $stage + ', остановлена' }
    if ($status -eq 'ждёт') { return $stage + ', ждёт ответа' }
    return $stage + ', следующий круг ' + $nextRound
}

function Get-EventReason($Events, [string]$Kind) {
    for ($index = $Events.Count - 1; $index -ge 0; $index--) {
        $event = $Events[$index]
        if ([string](Get-Prop $event 'событие' '') -ne $Kind) { continue }
        $reason = [string](Get-Prop $event 'причина' '')
        if ($reason) { return $reason }
        return 'без причины'
    }
    return 'причина не записана в журнале'
}

function Get-BlockedReason($State, $Events) {
    return Get-EventReason $Events 'остановка'
}

function Set-Blocked($State, [string]$Reason) {
    Set-Prop $State 'состояние' 'остановлена'
    Set-Prop $State 'текущий' ([pscustomobject][ordered]@{ 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'начат' = '' })
    Set-Prop $State 'возврат' (New-EmptyReturn)
    Set-Prop $State 'ожидание' (New-EmptyWaiting)
    return New-Event $State 'остановка' @{ 'причина' = $Reason; 'этап' = [string](Get-Prop $State 'этап' '') }
}

function New-EmptyWaiting {
    return [pscustomobject][ordered]@{
        'кто'    = ''
        'ссылка' = ''
        'с'      = ''
        'этап'   = ''
        'круг'   = 0
    }
}

# Ожидание ответа снаружи. В отличие от остановки у ожидания есть адресат и ссылка,
# поэтому задача не выглядит сломанной: видно, кого и с какого времени ждём.
function Set-Waiting($State, [string]$Who, [string]$Ref, [string]$Reason) {
    $stage = [string](Get-Prop $State 'этап' '')
    $current = Get-Prop $State 'текущий'
    $round = [int](Get-Prop $current 'круг' 0)
    if ($round -lt 1) { $round = Get-RoundOf $State $stage }
    Set-Prop $State 'состояние' 'ждёт'
    Set-Prop $State 'ожидание' ([pscustomobject][ordered]@{
        'кто'    = $Who
        'ссылка' = $Ref
        'с'      = (Get-UtcNow)
        'этап'   = $stage
        'круг'   = $round
    })
    Set-Prop $State 'текущий' ([pscustomobject][ordered]@{ 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'начат' = '' })
    Set-Prop $State 'возврат' (New-EmptyReturn)
    return New-Event $State 'ожидание' @{
        'кто'     = $Who
        'ссылка'  = $Ref
        'причина' = $Reason
        'этап'    = $stage
        'круг'    = $round
    }
}

# Блок ожидания из состояния; если его нет (старая задача) — из последнего события.
function Get-WaitingInfo($State, $Events) {
    $waiting = Get-Prop $State 'ожидание'
    if ($null -ne $waiting -and [string](Get-Prop $waiting 'кто' '')) { return $waiting }
    for ($index = $Events.Count - 1; $index -ge 0; $index--) {
        $event = $Events[$index]
        if ([string](Get-Prop $event 'событие' '') -ne 'ожидание') { continue }
        return [pscustomobject][ordered]@{
            'кто'    = [string](Get-Prop $event 'кто' '')
            'ссылка' = [string](Get-Prop $event 'ссылка' '')
            'с'      = [string](Get-Prop $event 'время' '')
            'этап'   = [string](Get-Prop $event 'этап' '')
            'круг'   = [int](Get-Prop $event 'круг' 0)
        }
    }
    return $null
}

# «ждём ответа: <кто>, с <дата>, <ссылка>» — одна и та же строка в status и next.
function Format-WaitingLine($Waiting) {
    if ($null -eq $Waiting) { return 'ждём ответа: адресат не записан' }
    $parts = @()
    $who = [string](Get-Prop $Waiting 'кто' '')
    if ($who) { $parts += $who }
    $since = [string](Get-Prop $Waiting 'с' '')
    if ($since) { $parts += 'с ' + $since }
    $ref = [string](Get-Prop $Waiting 'ссылка' '')
    if ($ref) { $parts += $ref }
    if ($parts.Count -eq 0) { return 'ждём ответа: адресат не записан' }
    return 'ждём ответа: ' + ($parts -join ', ')
}

function Get-LastArtifact($Events) {
    for ($index = $Events.Count - 1; $index -ge 0; $index--) {
        $artifact = [string](Get-Prop $Events[$index] 'артефакт' '')
        if ($artifact) { return $artifact }
    }
    return '—'
}

# Перечень вердиктов роли — единственный источник для отказа finish и подсказок next/start.
function Get-RoleVerdicts($Role) {
    if (-not $Role) { return @() }
    $known = $script:Verdicts[$Role]
    if ($null -eq $known) { return @() }
    return @($known)
}

# «вердикты: готово | сбой» — одна и та же строка в подсказках next и start.
function Format-VerdictsLine($Role) {
    $list = @(Get-RoleVerdicts $Role)
    if ($list.Count -eq 0) { return '' }
    return 'вердикты: ' + ($list -join ' | ')
}

# Вердикты роли, которой касается следующий шаг: сначала открытая роль (её закрывают finish),
# иначе роль, которую откроет start.
function Get-NextVerdictsLine($State) {
    $status = [string](Get-Prop $State 'состояние' '')
    if ($status -eq 'готова' -or $status -eq 'остановлена' -or $status -eq 'ждёт') { return '' }
    $role = [string](Get-Prop (Get-Prop $State 'текущий') 'роль' '')
    if (-not $role) {
        $role = [string](Get-Prop $State 'этап' '')
        if ($role -eq 'новая') {
            $route = [string](Get-Prop $State 'маршрут' '')
            $role = [string](@($script:Routes[$route])[0])
        }
    }
    return (Format-VerdictsLine $role)
}

function Get-NextLine($State, $Events) {
    $status = [string](Get-Prop $State 'состояние' '')
    $task = [string](Get-Prop $State 'задача' '')
    $current = Get-Prop $State 'текущий'
    if ($status -eq 'готова') { return 'готово: задача ' + $task + ' закрыта' }
    if ($status -eq 'остановлена') {
        return 'ждёт человека: ' + (Get-BlockedReason $State $Events) + ' — после решения: resume --task ' + $task + ' --reason "…"'
    }
    if ($status -eq 'ждёт') {
        return (Format-WaitingLine (Get-WaitingInfo $State $Events)) + ' — после ответа: resume --task ' + $task + ' --reason "…"'
    }
    $role = [string](Get-Prop $current 'роль' '')
    if ($role) {
        $verdicts = (Get-RoleVerdicts $role) -join '|'
        return 'finish --task ' + $task + ' --role ' + $role + ' --verdict <' + $verdicts + '>'
    }
    $stage = [string](Get-Prop $State 'этап' '')
    if ($stage -eq 'новая') { $stage = @($script:Routes[[string](Get-Prop $State 'маршрут' '')])[0] }
    return 'start --task ' + $task + ' --role ' + $stage
}

function Show-Usage {
    Write-Output 'taskctl.ps1 — состояние задач с ролями'
    Write-Output ''
    Write-Output '  new --title "…" [--route полный|быстрый|синхронизация]'
    Write-Output '  start --task 042 --role Колдун'
    Write-Output '  finish --task 042 --role Колдун --verdict <вердикт> [--note "…"]'
    Write-Output '  resume --task 042 --reason "что решил человек"'
    Write-Output '  status --task 042 [--brief]'
    Write-Output '  next --task 042'
    Write-Output '  timeline --task 042'
    Write-Output '  block --task 042 --reason "…" [--waiting "кто ответит"] [--ref "ссылка"]'
    Write-Output '  unlock --task 042'
    Write-Output '  validate --task 042'
    Write-Output '  board [--write] — единственный способ обновить Задачи.md'
    Write-Output '  --project <путь> — корень проекта (иначе ближайший вверх с Задачи\ или .v8-project.json)'
    Write-Output ''
    Write-Output 'Коды: 0 — успех, 1 — аргументы, 2 — данные/переход/артефакт, 3 — запись, 4 — занято.'
    Write-Output 'Состояния: новая, в работе, ждёт, готова, остановлена.'
    Write-Output 'ждёт — вопрос задан снаружи (block --waiting): status печатает, кого и с какого времени ждём;'
    Write-Output 'снимает ожидание resume --reason "ответ".'
    Write-Output 'Остановка (block, вердикт «сбой», лимит возвратов, к-часовщику на быстром маршруте) —'
    Write-Output 'это код 0 и слово «остановлена»: нормальный исход finish, а не ошибка.'
    Write-Output 'Быстрый маршрут: вердикт к-часовщику — это остановка на человеке, а не возврат.'
}

# --- Задача.md ---------------------------------------------------------------

# Раздел «Причина возврата» в постановке: человек должен видеть, зачем роль вернулась.
function Update-TaskMdReason($Folder, [string]$Reason, [string]$From, [string]$Artifact, [string]$Source) {
    $path = Join-Path $Folder $script:TaskFileName
    if (-not [System.IO.File]::Exists($path)) { return }
    $text = Read-TextFile $path
    $index = $text.IndexOf('## Причина возврата')
    if ($index -ge 0) { $text = $text.Substring(0, $index) }
    $block = New-Object System.Collections.ArrayList
    [void]$block.Add('## Причина возврата')
    [void]$block.Add('')
    if ($Source -eq 'возобновление') {
        [void]$block.Add('- Продолжение после остановки: ' + (Get-UtcNow))
    } else {
        [void]$block.Add('- Вернул: ' + $From)
    }
    if ($Artifact) { [void]$block.Add('- Артефакт: ' + $Artifact) }
    [void]$block.Add('- Причина: ' + $Reason)
    $text = $text.TrimEnd() + "`n`n" + (($block.ToArray()) -join "`n") + "`n"
    try { Write-TextFile $path $text } catch { Write-WarningLine ('не удалось дописать причину в ' + $script:TaskFileName + ': ' + (Get-ExceptionText $_)) }
}

# --- подкоманды --------------------------------------------------------------

function Invoke-New($Options) {
    $title = (Get-Option $Options 'title').Trim()
    if (-not $title) { Invoke-Abort 'аргумент' 'нужен --title' 1 }
    $route = Get-Option $Options 'route'
    if (-not $route) { $route = 'полный' }
    if (-not $script:Routes.ContainsKey($route)) {
        $names = ($script:Routes.Keys | Sort-Object) -join ', '
        Invoke-Abort 'аргумент' ('неизвестный маршрут ' + $route + ' (можно: ' + $names + ')') 1
    }

    $tasks = Get-TasksDir
    $lock = Enter-Lock (Join-Path $tasks $script:NumberLockName) 'нумерация задач' 2 200
    try {
        $numbers = @()
        foreach ($folder in (Get-ChildItem -LiteralPath $tasks -Directory)) {
            if ($folder.Name -match '^(\d+)\s*-') { $numbers += [int]$Matches[1] }
        }
        $number = 1
        if ($numbers.Count -gt 0) { $number = ($numbers | Measure-Object -Maximum).Maximum + 1 }
        $task = $number.ToString('000')

        $today = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
        $folderPath = Join-Path $tasks ($task + ' - ' + $today)
        if ([System.IO.Directory]::Exists($folderPath)) {
            Invoke-Abort 'данные' ('папка задачи уже есть: Задачи/' + $task + ' - ' + $today) 2
        }

        try {
            [void][System.IO.Directory]::CreateDirectory($folderPath)
        } catch {
            Invoke-Abort 'запись' ('не удалось создать папку задачи: ' + (Get-ExceptionText $_)) 3
        }

        try {
            $state = New-StateObject $task $title $route
            Save-AtomicText (Join-Path $folderPath $script:StateName) (ConvertTo-StateText $state)

            $template = $script:DefaultTaskMd
            $templatePath = Join-Path $script:TemplateDir $script:TaskFileName
            if ([System.IO.File]::Exists($templatePath)) { $template = Read-TextFile $templatePath }
            $body = $template.Replace('{{TASK}}', $task).Replace('{{TITLE}}', $title).Replace('{{DATE}}', $today).Replace('{{ROUTE}}', $route)
            Write-TextFile (Join-Path $folderPath $script:TaskFileName) $body
            Write-TextFile (Join-Path $folderPath $script:EventsName) ''
        } catch {
            try { [System.IO.Directory]::Delete($folderPath, $true) } catch { }
            Invoke-Abort 'запись' ('не удалось создать файлы задачи: ' + (Get-ExceptionText $_)) 3
        }
    } finally {
        Exit-Lock $lock
    }

    Write-Output $task
}

function Invoke-Start($Options, $Folder) {
    $role = Get-Option $Options 'role'
    if (-not $role) { Invoke-Abort 'аргумент' 'нужен --role' 1 }
    if ($script:Roles -cnotcontains $role) {
        $hint = ''
        foreach ($known in $script:Roles) {
            if ($known -eq $role) { $hint = ' — имя роли пишется с заглавной: ' + $known }
        }
        Invoke-Abort 'аргумент' ('неизвестная роль ' + $role + ' (можно: ' + ($script:Roles -join ', ') + ')' + $hint) 1
    }

    $state = Load-State $Folder
    $status = [string](Get-Prop $state 'состояние' '')
    $task = [string](Get-Prop $state 'задача' '')
    if ($status -eq 'готова') { Invoke-Abort 'переход' ('задача ' + $task + ' уже закрыта') 2 }
    if ($status -eq 'ждёт') {
        Invoke-Abort 'переход' ('задача ' + $task + ' ждёт ответа: сначала resume --task ' + $task + ' --reason "ответ"') 2
    }
    if ($status -eq 'остановлена') {
        Invoke-Abort 'переход' ('задача ' + $task + ' остановлена: сначала resume --task ' + $task + ' --reason "…"') 2
    }

    $route = [string](Get-Prop $state 'маршрут' '')
    if (-not $script:Routes.ContainsKey($route)) {
        Invoke-Abort 'данные' ('в состоянии неизвестный маршрут ' + $route) 2
    }
    $sequence = @($script:Routes[$route])
    if ($sequence -cnotcontains $role) {
        Invoke-Abort 'переход' ('роль ' + $role + ' не входит в маршрут ' + $route) 2
    }

    $expected = $sequence[0]
    $stage = [string](Get-Prop $state 'этап' '')
    if ($status -ne 'новая' -and $stage -ne 'новая') { $expected = $stage }
    if ($role -cne $expected) {
        Invoke-Abort 'переход' ('сейчас ожидается ' + $expected + ', а не ' + $role) 2
    }

    $current = Get-Prop $state 'текущий'
    $openRole = [string](Get-Prop $current 'роль' '')
    if ($openRole) {
        Invoke-Abort 'переход' ('этап ' + $openRole + ' уже открыт — сначала finish') 2
    }

    $rounds = Get-Prop $state 'круги'
    $base = [int](Get-Prop $rounds $role 0)
    $round = $base + 1

    # Возобновление без нового результата: круг тот же, скелет перезаписывается.
    $continuation = Get-Prop $state 'возврат'
    if ($null -ne $continuation -and [string](Get-Prop $continuation 'источник' '') -eq 'возобновление' -and [string](Get-Prop $continuation 'этап' '') -ceq $role) {
        if (-not [bool](Get-Prop $continuation 'новый_круг' $false) -and $base -ge 1) {
            $existing = Resolve-RoleArtifact $Folder $role $base
            if ($existing.Problem) { $round = $base }
        }
    }
    if ($round -lt 1) { $round = 1 }

    $limits = Get-Prop $state 'пределы'
    $ceiling = [int](Get-Prop $limits 'попыток' 3)
    if ($round -gt $ceiling) {
        Invoke-Abort 'переход' ('у роли ' + $role + ' исчерпан потолок кругов (' + $ceiling + ')') 2
    }

    Set-Prop $rounds $role $round

    foreach ($rel in (Get-ArtifactPaths $role $round)) {
        $full = Join-Path $Folder $rel
        if ([System.IO.File]::Exists($full) -and $round -ne $base) { continue }
        if ([System.IO.File]::Exists($full) -and $round -eq $base) {
            # повторный запуск того же круга: перезаписываем только незаполненный скелет
            $problem = Get-TextArtifactProblem $full $rel
            if (-not $problem) { continue }
        }
        $variant = ''
        if ($role -ceq 'Часовщик') {
            if ($rel.EndsWith('-Приёмка.md')) { $variant = 'приёмка' } else { $variant = 'план' }
        }
        Write-TextFile $full (New-Skeleton $state $role $round $variant $Folder)
    }

    $rel = Get-RoleArtifactRel $role $round
    Set-Prop $current 'роль' $role
    Set-Prop $current 'круг' $round
    Set-Prop $current 'артефакт' $rel
    Set-Prop $current 'начат' (Get-UtcNow)
    Set-Prop $state 'этап' $role
    Set-Prop $state 'состояние' 'в работе'

    $event = New-Event $state 'этап.старт' @{ 'роль' = $role; 'круг' = $round; 'артефакт' = $rel; 'этап' = $role }
    Save-Transaction $Folder $state @($event)

    Write-Output $rel
    $verdicts = Format-VerdictsLine $role
    if ($verdicts) { Write-Output $verdicts }
}

function Invoke-Finish($Options, $Folder) {
    $role = Get-Option $Options 'role'
    $verdict = Get-Option $Options 'verdict'
    $note = Get-Option $Options 'note'
    if (-not $role) { Invoke-Abort 'аргумент' 'нужен --role' 1 }
    if (-not $verdict) { Invoke-Abort 'аргумент' 'нужен --verdict' 1 }
    if ($script:Roles -cnotcontains $role) {
        $hint = ''
        foreach ($known in $script:Roles) {
            if ($known -eq $role) { $hint = ' — имя роли пишется с заглавной: ' + $known }
        }
        Invoke-Abort 'аргумент' ('неизвестная роль ' + $role + ' (можно: ' + ($script:Roles -join ', ') + ')' + $hint) 1
    }

    $state = Load-State $Folder
    $status = [string](Get-Prop $state 'состояние' '')
    $task = [string](Get-Prop $state 'задача' '')
    if ($status -eq 'готова') { Invoke-Abort 'переход' ('задача ' + $task + ' уже закрыта') 2 }
    if ($status -eq 'ждёт') {
        Invoke-Abort 'переход' ('задача ' + $task + ' ждёт ответа: сначала resume --task ' + $task + ' --reason "ответ"') 2
    }
    if ($status -eq 'остановлена') {
        Invoke-Abort 'переход' ('задача ' + $task + ' остановлена: сначала resume --task ' + $task + ' --reason "…"') 2
    }

    $current = Get-Prop $state 'текущий'
    $openRole = [string](Get-Prop $current 'роль' '')
    if ($openRole -cne $role) {
        $openText = $openRole
        if (-not $openText) { $openText = 'ничего' }
        Invoke-Abort 'переход' ('этап ' + $role + ' не открыт (открыт: ' + $openText + ')') 2
    }

    $allowed = @(Get-RoleVerdicts $role)
    if ($allowed -cnotcontains $verdict) {
        Invoke-Abort 'переход' ('вердикт ' + $verdict + ' не подходит роли ' + $role + ' (можно: ' + ($allowed -join ', ') + ')') 2
    }

    $round = [int](Get-Prop $current 'круг' 0)
    $resolved = Resolve-RoleArtifact $Folder $role $round
    if ($resolved.Problem) { Invoke-Abort 'артефакт' $resolved.Problem 2 }
    $rel = $resolved.Rel

    $limits = Get-Prop $state 'пределы'
    $maxLines = [int](Get-Prop $limits 'строк' 200)
    $lines = Get-ArtifactLineCount $Folder $role $round
    if ($lines -ge 0 -and $lines -gt $maxLines) {
        Write-Output ('внимание: отчёт ' + $lines + ' строк, порог ' + $maxLines + ' — длинное будет мешать читать')
    }

    $seconds = 0
    $started = ConvertFrom-TimeValue (Get-Prop $current 'начат' '')
    if ($null -ne $started) {
        $seconds = [int]([DateTime]::UtcNow - $started).TotalSeconds
    }
    if ($seconds -lt 0) { $seconds = 0 }

    $times = Get-Prop $state 'время_сек'
    Set-Prop $times $role ([int](Get-Prop $times $role 0) + $seconds)

    # Хэши считаем до записи события: если основной артефакт не захэшировался,
    # это сбой записи (код 3), а не событие с пустым словарём. Второстепенный файл
    # (приёмка Часовщика) без хэша — предупреждение, событие всё равно пишется.
    $hashInfo = Get-ArtifactHashes $Folder $role $round
    foreach ($failure in $hashInfo.Failures) {
        if ($failure.Rel -ceq $rel) {
            Invoke-Abort 'запись' ('не удалось посчитать хэш ' + $failure.Rel + ': ' + $failure.Message) 3
        }
        Write-Output ('внимание: не удалось посчитать хэш ' + $failure.Rel + ': ' + $failure.Message)
    }
    $hashes = $hashInfo.Hashes
    $fields = @{
        'роль'       = $role
        'круг'       = $round
        'вердикт'    = $verdict
        'секунд'     = $seconds
        'артефакт'   = $rel
        'примечание' = $note
        'этап'       = [string](Get-Prop $state 'этап' '')
        'хэши'       = $hashes
    }
    $event = New-Event $state 'этап.финиш' $fields

    $route = [string](Get-Prop $state 'маршрут' '')
    $sequence = @()
    if ($script:Routes.ContainsKey($route)) { $sequence = @($script:Routes[$route]) }
    $step = Get-Step $state $role $verdict
    if ($step.Kind -eq 'unknown') {
        Invoke-Abort 'данные' ('для вердикта ' + $verdict + ' роли ' + $role + ' нет перехода (маршрут ' + $route + ')') 2
    }
    $target = [string]$step.Target

    Set-Prop $state 'текущий' ([pscustomobject][ordered]@{ 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'начат' = '' })
    Set-Prop $state 'возврат' (New-EmptyReturn)

    if ($step.Kind -eq 'done') {
        Set-Prop $state 'этап' 'готова'
        Set-Prop $state 'состояние' 'готова'
        Save-Transaction $Folder $state @($event)
        Write-Output ('готово: задача ' + $task + ' закрыта')
        return
    }

    if ($step.Kind -eq 'blocked') {
        $reason = 'вердикт ' + $verdict + ' от ' + $role
        $blockEvent = Set-Blocked $state $reason
        Save-Transaction $Folder $state @($event, $blockEvent)
        Write-Output ('остановлена: задача ' + $task + ' — ' + $reason + ', нужен человек')
        return
    }

    if ($step.Kind -eq 'next') {
        Set-Prop $state 'этап' $target
        Set-Prop $state 'состояние' 'в работе'
        $nextRound = (Get-RoundOf $state $target) + 1
        Save-Transaction $Folder $state @($event)
        Write-Output ('дальше: ' + $target + ', круг ' + $nextRound + ' — start --task ' + $task + ' --role ' + $target)
        return
    }

    $ceiling = [int](Get-Prop $limits 'попыток' 3)

    # Возврат туда, где этапа нет (например к-часовщику на быстром маршруте), —
    # это не возврат, а остановка на человеке. Пишем это словами, а не намёком.
    if ($sequence -cnotcontains $target) {
        $reason = 'вердикт ' + $verdict + ' от ' + $role + ': на маршруте ' + $route + ' это остановка на человеке, а не возврат — роли ' + $target + ' в маршруте нет'
        $blockEvent = Set-Blocked $state $reason
        Save-Transaction $Folder $state @($event, $blockEvent)
        Write-Output ('остановлена: задача ' + $task + ' — ' + $reason + ', нужен человек')
        return
    }

    $rounds = Get-Prop $state 'круги'
    $targetRounds = [int](Get-Prop $rounds $target 0)
    $events = @(Read-Events $Folder)
    $returns = Get-ReturnCount $events $target 0

    if ($returns -ge $script:MaxReturnsPerStage) {
        $reason = 'исчерпан лимит возвратов на этап ' + $target + ' (не больше ' + $script:MaxReturnsPerStage + ' возвратов за задачу)'
        if ($targetRounds -ge $ceiling) {
            $reason += ', у роли ' + $target + ' уже ' + $targetRounds + ' ' + (Get-Plural $targetRounds 'круг' 'круга' 'кругов') + ', потолок ' + $ceiling
        }
        $blockEvent = Set-Blocked $state $reason
        Save-Transaction $Folder $state @($event, $blockEvent)
        Write-Output ('остановлена: задача ' + $task + ' — ' + $reason + ', нужен человек')
        return
    }

    if ($targetRounds -ge $ceiling) {
        $reason = 'у роли ' + $target + ' уже ' + $targetRounds + ' ' + (Get-Plural $targetRounds 'круг' 'круга' 'кругов') + ', потолок ' + $ceiling
        $blockEvent = Set-Blocked $state $reason
        Save-Transaction $Folder $state @($event, $blockEvent)
        Write-Output ('остановлена: задача ' + $task + ' — ' + $reason + ', нужен человек')
        return
    }

    # Возврат состоится: без причины возврата и ссылки на артефакт он не годится.
    $returnInfo = Get-ReturnReason $Folder $role $round
    if ($returnInfo.Problem) { Invoke-Abort 'артефакт' $returnInfo.Problem 2 }

    $event | Add-Member -MemberType NoteProperty -Name 'возврат' -Value $target -Force

    Set-Prop $state 'возврат' ([pscustomobject][ordered]@{
        'этап'       = $target
        'роль'       = $role
        'круг'       = $round
        'артефакт'   = $returnInfo.Rel
        'причина'    = $returnInfo.Reason
        'новый_круг' = $true
        'источник'   = 'возврат'
    })
    Set-Prop $state 'этап' $target
    Set-Prop $state 'состояние' 'в работе'
    Save-Transaction $Folder $state @($event)
    Update-TaskMdReason $Folder $returnInfo.Reason ($role + ', круг ' + $round) $returnInfo.Rel 'возврат'
    Write-Output ('дальше: ' + $target + ', круг ' + ($targetRounds + 1) + ' — start --task ' + $task + ' --role ' + $target)
    Write-Output ('причина возврата: ' + $returnInfo.Reason)
}

function Invoke-Resume($Options, $Folder) {
    $reason = (Get-Option $Options 'reason').Trim()
    if (-not $reason) { Invoke-Abort 'аргумент' 'нужен --reason: что решил человек' 1 }

    $state = Load-State $Folder
    $status = [string](Get-Prop $state 'состояние' '')
    $task = [string](Get-Prop $state 'задача' '')
    $stage = [string](Get-Prop $state 'этап' '')
    if ($status -ne 'остановлена' -and $status -ne 'ждёт') {
        Invoke-Abort 'переход' ('возобновлять можно только остановленную задачу или ожидающую ответа, а задача ' + $task + ' — ' + $status) 2
    }

    $route = [string](Get-Prop $state 'маршрут' '')
    if (-not $script:Routes.ContainsKey($route)) { Invoke-Abort 'данные' ('в состоянии неизвестный маршрут ' + $route) 2 }
    $sequence = @($script:Routes[$route])

    if ($stage -eq 'готова') { Invoke-Abort 'переход' 'закрытую задачу не возобновляют' 2 }
    $role = $stage
    if ($stage -eq 'новая') { $role = $sequence[0] }
    elseif ($sequence -cnotcontains $stage) { Invoke-Abort 'переход' ('этап ' + $stage + ' не входит в маршрут ' + $route) 2 }

    $events = @(Read-Events $Folder)
    $base = Get-RoundOf $state $role
    $filled = $false
    $artifactRel = ''
    if ($base -gt 0) {
        $resolved = Resolve-RoleArtifact $Folder $role $base
        if (-not $resolved.Problem) { $filled = $true; $artifactRel = $resolved.Rel }
    }
    if (-not $artifactRel) { $artifactRel = Get-LastArtifact $events }
    if ($artifactRel -eq '—') { $artifactRel = '' }

    $newRound = $filled
    $nextRound = $base
    if ($newRound) { $nextRound = $base + 1 } elseif ($nextRound -lt 1) { $nextRound = 1 }

    Set-Prop $state 'возврат' ([pscustomobject][ordered]@{
        'этап'       = $role
        'роль'       = $role
        'круг'       = $nextRound
        'артефакт'   = $artifactRel
        'причина'    = $reason
        'новый_круг' = $newRound
        'источник'   = 'возобновление'
    })
    Set-Prop $state 'состояние' 'в работе'
    Set-Prop $state 'текущий' ([pscustomobject][ordered]@{ 'роль' = ''; 'круг' = 0; 'артефакт' = ''; 'начат' = '' })
    Set-Prop $state 'ожидание' (New-EmptyWaiting)

    $event = New-Event $state 'возобновление' @{
        'роль'     = $role
        'круг'     = $nextRound
        'причина'  = $reason
        'этап'     = $stage
        'артефакт' = $artifactRel
    }
    Save-Transaction $Folder $state @($event)
    Update-TaskMdReason $Folder $reason '' $artifactRel 'возобновление'

    $word = 'круг тот же (' + $nextRound + '), скелет перезаписывается'
    if ($newRound) { $word = 'новый круг ' + $nextRound }
    Write-Output ('продолжаем: ' + $role + ', ' + $word + ' — start --task ' + $task + ' --role ' + $role)
}

function Invoke-Status($Options) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }

    $state = Load-State $folder
    $events = @(Read-Events $folder)
    $times = Get-Prop $state 'время_сек'
    $current = Get-Prop $state 'текущий'
    $status = [string](Get-Prop $state 'состояние' '')

    Write-Output ([string](Get-Prop $state 'задача' '') + ' — ' + [string](Get-Prop $state 'название' ''))
    Write-Output ('маршрут: ' + [string](Get-Prop $state 'маршрут' '') + ' · статус: ' + $status)
    Write-Output ('этап: ' + (Get-StageText $state))

    $parts = @()
    foreach ($role in $script:Roles) {
        $parts += $role + ' ' + (Format-Duration ([int](Get-Prop $times $role 0)))
    }
    Write-Output ('время: ' + ($parts -join ' · '))

    $artifact = [string](Get-Prop $current 'артефакт' '')
    if (-not $artifact) { $artifact = Get-LastArtifact $events }
    Write-Output ('артефакт: ' + $artifact)

    if ($status -eq 'ждёт') {
        Write-Output (Format-WaitingLine (Get-WaitingInfo $state $events))
        Write-Output ('причина: ' + (Get-EventReason $events 'ожидание'))
        Write-Output ('дальше: ждёт ответа — resume --task ' + [string](Get-Prop $state 'задача' '') + ' --reason "ответ"')
    } elseif ($status -eq 'остановлена') {
        Write-Output ('причина: ' + (Get-BlockedReason $state $events))
        Write-Output ('дальше: ждёт человека — resume --task ' + [string](Get-Prop $state 'задача' '') + ' --reason "…"')
    } else {
        Write-Output ('дальше: ' + (Get-NextLine $state $events))
    }

    if (-not $Options.ContainsKey('brief')) {
        Write-Output ''
        Write-Output 'последние события:'
        if ($events.Count -eq 0) { Write-Output '  (журнал пуст)' }
        $from = [Math]::Max(0, $events.Count - 3)
        for ($index = $from; $index -lt $events.Count; $index++) {
            $event = $events[$index]
            $parts = @()
            foreach ($key in @('событие', 'роль', 'круг', 'вердикт')) {
                $value = Get-Prop $event $key
                if ($null -ne $value -and "$value" -ne '') { $parts += [string]$value }
            }
            Write-Output ('  ' + [string](Get-Prop $event 'номер' '—') + ' ' + [string](Get-Prop $event 'время' '—') + ' ' + ($parts -join ' '))
        }
    }
}

function Invoke-Next($Options) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }
    $state = Load-State $folder
    Write-Output (Get-NextLine $state @(Read-Events $folder))
    $verdicts = Get-NextVerdictsLine $state
    if ($verdicts) { Write-Output $verdicts }
}

function Invoke-Timeline($Options) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }
    $events = @(Read-Events $folder)

    Write-Output '| номер | время | роль | круг | вердикт | секунд |'
    Write-Output '| --- | --- | --- | --- | --- | --- |'
    if ($events.Count -eq 0) {
        Write-Output '| — | — | — | — | — | — |'
        return
    }
    foreach ($event in $events) {
        $verdict = [string](Get-Prop $event 'вердикт' '')
        if (-not $verdict) { $verdict = [string](Get-Prop $event 'событие' '—') }
        Write-Output ('| ' + [string](Get-Prop $event 'номер' '—') + ' | ' + [string](Get-Prop $event 'время' '—') + ' | ' + [string](Get-Prop $event 'роль' '—') + ' | ' + [string](Get-Prop $event 'круг' '—') + ' | ' + $verdict + ' | ' + [string](Get-Prop $event 'секунд' '—') + ' |')
    }
}

function Invoke-Block($Options, $Folder) {
    $reason = (Get-Option $Options 'reason').Trim()
    if (-not $reason) { Invoke-Abort 'аргумент' 'нужен --reason' 1 }
    $who = (Get-Option $Options 'waiting').Trim()
    $ref = (Get-Option $Options 'ref').Trim()

    $state = Load-State $Folder
    $task = [string](Get-Prop $state 'задача' '')
    $status = [string](Get-Prop $state 'состояние' '')
    if ($status -eq 'готова') { Invoke-Abort 'переход' ('задача ' + $task + ' уже закрыта') 2 }

    # Есть адресат — задача не сломалась, а ждёт ответа снаружи.
    if ($who) {
        $event = Set-Waiting $state $who $ref $reason
        $since = [string](Get-Prop (Get-Prop $state 'ожидание') 'с' '')
        Save-Transaction $Folder $state @($event)
        Write-Output ('ждёт ответа: задача ' + $task + ' — ' + $who + ', с ' + $since)
        if (-not $ref) {
            Write-Output 'внимание: ссылки нет — искать ответ будет сложно'
        }
        return
    }

    if ($status -eq 'ждёт') {
        Invoke-Abort 'переход' ('задача ' + $task + ' уже ждёт ответа: чтобы уточнить адресата, укажи --waiting') 2
    }
    if ($status -eq 'остановлена') {
        Invoke-Abort 'переход' ('задача ' + $task + ' уже остановлена: чтобы ждать ответа, укажи --waiting "<кто ответит>"') 2
    }

    $event = Set-Blocked $state $reason
    Save-Transaction $Folder $state @($event)
    Write-Output ('остановлена: задача ' + $task + ' — ' + $reason)
}

function Invoke-Unlock($Options) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }

    $path = Join-Path $folder $script:LockName
    if (-not [System.IO.File]::Exists($path)) {
        Write-Output 'блокировки нет'
        return
    }
    $info = Read-LockInfo $path
    try {
        [System.IO.File]::Delete($path)
    } catch {
        Invoke-Abort 'запись' ('не удалось снять блокировку: ' + (Get-ExceptionText $_)) 3
    }
    Write-Output ('снята блокировка: pid=' + $info.Pid + ', время=' + $info.Time + ', узел=' + $info.Node)
}

function Invoke-Validate($Options) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }

    $state = Load-State $folder
    $events = @(Read-Events $folder)
    $problems = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList

    $task = [string](Get-Prop $state 'задача' '')
    $stage = [string](Get-Prop $state 'этап' '')
    $status = [string](Get-Prop $state 'состояние' '')
    $route = [string](Get-Prop $state 'маршрут' '')

    # 1. обязательные поля и их типы.
    foreach ($name in @('задача', 'название', 'маршрут', 'этап', 'состояние')) {
        $property = $state.PSObject.Properties[$name]
        if ($null -eq $property) { [void]$problems.Add('нет поля ' + $name) }
        elseif (-not ($property.Value -is [string]) -or -not $property.Value.Trim()) { [void]$problems.Add('поле ' + $name + ' пустое или не строка') }
    }
    foreach ($name in @('круги', 'время_сек', 'текущий')) {
        if ($null -eq $state.PSObject.Properties[$name]) { [void]$problems.Add('нет поля ' + $name) }
        elseif (-not ($state.PSObject.Properties[$name].Value -is [pscustomobject])) { [void]$problems.Add('поле ' + $name + ' не объект') }
    }
    $sequenceField = $state.PSObject.Properties['номер_события']
    if ($null -eq $sequenceField) {
        [void]$problems.Add('нет поля номер_события')
    } elseif (-not ($sequenceField.Value -is [int] -or $sequenceField.Value -is [long] -or $sequenceField.Value -is [double])) {
        [void]$problems.Add('поле номер_события не число')
    } elseif ([int]$sequenceField.Value -lt 0) {
        [void]$problems.Add('номер_события отрицательный: ' + [string]$sequenceField.Value)
    }
    foreach ($name in @('создано', 'обновлено')) {
        $property = $state.PSObject.Properties[$name]
        if ($null -eq $property) { [void]$problems.Add('нет поля ' + $name) }
        elseif ($null -eq (ConvertFrom-TimeValue $property.Value)) {
            [void]$problems.Add('поле ' + $name + ' не время вида yyyy-MM-ddTHH:mm:ssZ')
        }
    }

    $rounds = Get-Prop $state 'круги'
    if ($null -ne $rounds) {
        foreach ($role in $script:Roles) {
            $value = Get-Prop $rounds $role
            if ($null -eq $value) { [void]$problems.Add('в круги нет роли ' + $role); continue }
            $number = 0
            if (-not [int]::TryParse([string]$value, [ref]$number) -or $number -lt 0) {
                [void]$problems.Add('круги.' + $role + ' не неотрицательное число: ' + [string]$value)
            }
        }
    }
    $timeSeconds = Get-Prop $state 'время_сек'
    if ($null -ne $timeSeconds) {
        foreach ($role in $script:Roles) {
            $value = Get-Prop $timeSeconds $role
            if ($null -eq $value) { [void]$problems.Add('в время_сек нет роли ' + $role); continue }
            $number = 0
            if (-not [int]::TryParse([string]$value, [ref]$number) -or $number -lt 0) {
                [void]$problems.Add('время_сек.' + $role + ' не неотрицательное число: ' + [string]$value)
            }
        }
    }

    # 2. маршрут и этап.
    if (-not $script:Routes.ContainsKey($route)) {
        [void]$problems.Add('маршрут ' + $route + ' неизвестен (есть: ' + (($script:Routes.Keys | Sort-Object) -join ', ') + ')')
    } elseif ($stage -ne 'новая' -and $stage -ne 'готова' -and (@($script:Routes[$route]) -cnotcontains $stage)) {
        [void]$problems.Add('этап ' + $stage + ' не входит в маршрут ' + $route)
    }
    if ($script:AllowedStages -cnotcontains $stage) {
        [void]$problems.Add('этап ' + $stage + ' не из списка ' + ($script:AllowedStages -join ', '))
    }
    if ($script:AllowedStatuses -cnotcontains $status) {
        [void]$problems.Add('состояние ' + $status + ' не из списка ' + ($script:AllowedStatuses -join ', '))
    }

    # 2б. ожидание ответа снаружи: у «ждёт» должен быть адресат и время.
    # Отсутствие поля у остальных статусов — норма: старые задачи его не знают.
    $waiting = Get-Prop $state 'ожидание'
    if ($status -eq 'ждёт') {
        $who = ''
        if ($null -ne $waiting) { $who = [string](Get-Prop $waiting 'кто' '') }
        if (-not $who) {
            [void]$problems.Add('состояние ждёт, а блок ожидание пуст: не записано, кого ждём')
        } else {
            $since = ConvertFrom-TimeValue (Get-Prop $waiting 'с' '')
            if ($null -eq $since) {
                [void]$problems.Add('в блоке ожидание нет времени «с»')
            } elseif (([DateTime]::UtcNow - $since).TotalDays -gt 7) {
                $days = [int][Math]::Floor(([DateTime]::UtcNow - $since).TotalDays)
                $dayText = Get-Plural $days 'день' 'дня' 'дней'
                [void]$warnings.Add(([string]$days) + ' ' + $dayText + ' ждём ответа')
            }
        }
    }

    # 3. нумерация журнала.
    $journalPath = Join-Path $folder $script:EventsName
    $journalExists = [System.IO.File]::Exists($journalPath)
    $sequence = [int](Get-Prop $state 'номер_события' 0)
    if ($sequence -ne $events.Count) {
        [void]$problems.Add('номер_события=' + $sequence + ', а событий в журнале ' + $events.Count)
    }
    if (-not $journalExists -and $sequence -gt 0) {
        [void]$problems.Add('нет файла ' + $script:EventsName + ', хотя в состоянии ' + $sequence + ' событий')
    }
    for ($index = 1; $index -le $events.Count; $index++) {
        $event = $events[$index - 1]
        $number = [int](Get-Prop $event 'номер' 0)
        if ($number -ne $index) { [void]$problems.Add('у события в строке ' + $index + ' номер=' + $number) }
        if ([string](Get-Prop $event 'задача' '') -ne $task) {
            [void]$problems.Add('в событии ' + $index + ' чужая задача ' + [string](Get-Prop $event 'задача' ''))
        }
        if (-not [string](Get-Prop $event 'время' '')) {
            [void]$problems.Add('в событии ' + $index + ' нет времени')
        }
    }

    # 4. журнал против состояния: прогоняем всю историю заново.
    if ($script:Routes.ContainsKey($route)) {
        $replay = Get-ReplayResult $state $events
        foreach ($problem in $replay.Problems) { [void]$problems.Add($problem) }
    }

    # 5. открытый этап: файл артефакта на месте и непустой. Маркер скелета здесь — только
    # предупреждение: сразу после start в артефакте лежит скелет, и это нормальное
    # состояние работы. Ошибка — отсутствие файла или пустота. Для закрытого этапа
    # маркер остаётся ошибкой (проверка закрытых кругов ниже).
    $current = Get-Prop $state 'текущий'
    $currentRole = ''
    if ($null -ne $current) { $currentRole = [string](Get-Prop $current 'роль' '') }
    if ($status -eq 'в работе' -and $currentRole) {
        $currentRound = [int](Get-Prop $current 'круг' 0)
        $where = 'открытый этап ' + $currentRole + ', круг ' + $currentRound + ': '
        $open = Get-OpenArtifactStatus $folder $currentRole $currentRound
        foreach ($item in $open.Problems) { [void]$problems.Add($where + $item) }
        foreach ($item in $open.Warnings) { [void]$warnings.Add($where + $item) }
        if ($currentRole -cne 'Бард') {
            $planned = [string](Get-Prop $current 'артефакт' '')
            if ($planned -and $open.Rel -and $planned -cne $open.Rel) {
                [void]$problems.Add('текущий.артефакт=' + $planned + ', а роль пишет ' + $open.Rel)
            }
        }
        if ($currentRound -lt 1) { [void]$problems.Add('у открытого этапа круг ' + $currentRound) }
    }

    # 6. время: неотрицательно и сходится с журналом.
    $times = @{}
    foreach ($event in $events) {
        if ([string](Get-Prop $event 'событие' '') -ne 'этап.финиш') { continue }
        $role = [string](Get-Prop $event 'роль' '')
        $seconds = [int](Get-Prop $event 'секунд' 0)
        if ($seconds -lt 0) { [void]$problems.Add('в закрытии ' + $role + ' отрицательные секунды ' + $seconds) }
        $times[$role] = [int]$times[$role] + $seconds
    }
    if ($null -ne $timeSeconds) {
        foreach ($role in $script:Roles) {
            $seconds = [int](Get-Prop $timeSeconds $role 0)
            if ($seconds -ne [int]$times[$role]) {
                [void]$problems.Add('время_сек.' + $role + '=' + $seconds + ', а в журнале ' + [int]$times[$role])
            }
            if ($seconds -lt 0) { [void]$problems.Add('время_сек.' + $role + ' отрицательное') }
        }
    }

    # 7. артефакты закрытых кругов и их хэши.
    foreach ($event in $events) {
        if ([string](Get-Prop $event 'событие' '') -ne 'этап.финиш') { continue }
        $role = [string](Get-Prop $event 'роль' '')
        $round = [int](Get-Prop $event 'круг' 0)
        $rel = [string](Get-Prop $event 'артефакт' '')
        if (-not $rel -and $role -cne 'Бард') {
            [void]$problems.Add('в закрытии ' + $role + ' круга ' + $round + ' нет пути артефакта')
            continue
        }
        $resolved = Resolve-RoleArtifact $folder $role $round
        if ($resolved.Problem) {
            [void]$problems.Add('круг ' + $round + ', ' + $role + ': ' + $resolved.Problem)
            continue
        }
        $hashes = Get-Prop $event 'хэши'
        # Нет поля вовсе — старый журнал, молчим. Поле есть, а основного артефакта
        # в нём нет (например, пустой {}) — предупреждение: хэш не записан.
        if ($null -ne $hashes) {
            $mainRecorded = $false
            foreach ($property in $hashes.PSObject.Properties) {
                if ($property.Name -ceq $resolved.Rel) { $mainRecorded = $true }
                $full = Join-Path $folder $property.Name
                if (-not [System.IO.File]::Exists($full)) {
                    [void]$warnings.Add('файл ' + $property.Name + ' из закрытия ' + $role + ' круга ' + $round + ' пропал')
                    continue
                }
                $actual = Get-FileHashText $full
                if ($actual.Error) {
                    [void]$warnings.Add('не удалось проверить хэш ' + $property.Name + ' (' + $role + ', круг ' + $round + '): ' + $actual.Error)
                    continue
                }
                if ($actual.Hash -and $actual.Hash -ne [string]$property.Value) {
                    [void]$warnings.Add('файл ' + $property.Name + ' изменён после закрытия ' + $role + ' круга ' + $round)
                }
            }
            if (-not $mainRecorded) {
                [void]$warnings.Add('хэши не записаны: ' + $resolved.Rel + ' закрыт ' + $role + ' в круге ' + $round)
            }
        }
    }

    if ($problems.Count -gt 0) {
        Write-Output ('ошибка: данные: проблемы задачи ' + $task + ':')
        foreach ($problem in $problems) { Write-Output ('- ' + $problem) }
        $script:ExitCode = 2
        return
    }
    Write-Output 'ок'
    if ($warnings.Count -gt 0) {
        Write-Output ''
        foreach ($warning in $warnings) { Write-Output ('внимание: ' + $warning) }
    }
}

# Проигрывает журнал заново и сверяет результат с состоянием.
function Get-ReplayResult($State, $Events) {
    $problems = New-Object System.Collections.ArrayList
    $route = [string](Get-Prop $State 'маршрут' '')
    if (-not $script:Routes.ContainsKey($route)) {
        [void]$problems.Add('журнал не проверить: маршрут ' + $route + ' неизвестен')
        return [pscustomobject]@{ 'Problems' = $problems.ToArray(); 'Rounds' = @{} }
    }
    $sequence = @($script:Routes[$route])

    $stage = 'новая'
    $status = 'новая'
    $openRole = ''
    $openRound = 0
    $rounds = @{}
    $index = 0

    foreach ($event in $Events) {
        $index++
        $kind = [string](Get-Prop $event 'событие' '')
        $role = [string](Get-Prop $event 'роль' '')
        $round = [int](Get-Prop $event 'круг' 0)

        if ($kind -eq 'этап.старт') {
            if ($openRole) { [void]$problems.Add('событие ' + $index + ': старт ' + $role + ', когда открыт этап ' + $openRole) }
            if ($script:Roles -cnotcontains $role) {
                [void]$problems.Add('событие ' + $index + ': неизвестная роль ' + $role)
            } elseif ($sequence -cnotcontains $role) {
                [void]$problems.Add('событие ' + $index + ': роль ' + $role + ' вне маршрута ' + $route)
            } else {
                $expected = $sequence[0]
                if ($status -ne 'новая' -and $stage -ne 'новая') { $expected = $stage }
                if ($status -eq 'готова' -or $status -eq 'остановлена') {
                    [void]$problems.Add('событие ' + $index + ': старт ' + $role + ' при состоянии ' + $status)
                } elseif ($role -cne $expected) {
                    [void]$problems.Add('событие ' + $index + ': старт ' + $role + ', а ожидался ' + $expected)
                }
            }
            if ($round -lt 1) { [void]$problems.Add('событие ' + $index + ': старт без круга') }
            $previous = 0
            if ($rounds.ContainsKey($role)) { $previous = [int]$rounds[$role] }
            if ($round -gt $previous) { $rounds[$role] = $round }
            $openRole = $role
            $openRound = $round
            $stage = $role
            $status = 'в работе'
            continue
        }

        if ($kind -eq 'этап.финиш') {
            if (-not $openRole) {
                [void]$problems.Add('событие ' + $index + ': закрытие ' + $role + ' без открытого этапа')
            } elseif ($openRole -cne $role) {
                [void]$problems.Add('событие ' + $index + ': закрытие ' + $role + ', а открыт ' + $openRole)
            } elseif ($openRound -ne $round) {
                [void]$problems.Add('событие ' + $index + ': закрытие круга ' + $round + ', а открыт круг ' + $openRound)
            }
            $verdict = [string](Get-Prop $event 'вердикт' '')
            if ($script:Verdicts.ContainsKey($role)) {
                if (@($script:Verdicts[$role]) -cnotcontains $verdict) {
                    [void]$problems.Add('событие ' + $index + ': вердикт ' + $verdict + ' не подходит роли ' + $role)
                }
            } else {
                [void]$problems.Add('событие ' + $index + ': вердикт у неизвестной роли ' + $role)
            }
            $step = Get-Step $State $role $verdict
            $openRole = ''
            $openRound = 0
            if ($step.Kind -eq 'done') {
                $stage = 'готова'
                $status = 'готова'
            } elseif ($step.Kind -eq 'blocked') {
                $status = 'остановлена'
            } elseif ($step.Kind -eq 'return') {
                if ($sequence -ccontains $step.Target) {
                    $stage = [string]$step.Target
                    $status = 'в работе'
                } else {
                    # возврат туда, где этапа нет: задача встаёт на человеке
                    $status = 'остановлена'
                }
            } elseif ($step.Kind -eq 'next') {
                $stage = [string]$step.Target
                $status = 'в работе'
            } else {
                [void]$problems.Add('событие ' + $index + ': нет перехода для вердикта ' + $verdict + ' роли ' + $role)
            }
            continue
        }

        if ($kind -eq 'остановка') {
            if ($status -eq 'готова') { [void]$problems.Add('событие ' + $index + ': остановка закрытой задачи') }
            $status = 'остановлена'
            $openRole = ''
            $openRound = 0
            $eventStage = [string](Get-Prop $event 'этап' '')
            if ($eventStage) { $stage = $eventStage }
            continue
        }

        if ($kind -eq 'ожидание') {
            if ($status -eq 'готова') { [void]$problems.Add('событие ' + $index + ': ожидание у закрытой задачи') }
            $status = 'ждёт'
            $openRole = ''
            $openRound = 0
            $eventStage = [string](Get-Prop $event 'этап' '')
            if ($eventStage) { $stage = $eventStage }
            continue
        }

        if ($kind -eq 'возобновление') {
            if ($status -ne 'остановлена' -and $status -ne 'ждёт') {
                [void]$problems.Add('событие ' + $index + ': возобновление при состоянии ' + $status)
            }
            $status = 'в работе'
            $openRole = ''
            $openRound = 0
            $eventStage = [string](Get-Prop $event 'этап' '')
            if ($eventStage) { $stage = $eventStage }
            continue
        }

        [void]$problems.Add('событие ' + $index + ': неизвестный тип ' + $kind)
    }

    $stateStage = [string](Get-Prop $State 'этап' '')
    $stateStatus = [string](Get-Prop $State 'состояние' '')
    $current = Get-Prop $State 'текущий'
    $currentRole = ''
    $currentRound = 0
    if ($null -ne $current) {
        $currentRole = [string](Get-Prop $current 'роль' '')
        $currentRound = [int](Get-Prop $current 'круг' 0)
    }

    if ($stage -cne $stateStage) { [void]$problems.Add('по журналу этап ' + $stage + ', а в состоянии ' + $stateStage) }
    if ($status -cne $stateStatus) { [void]$problems.Add('по журналу состояние ' + $status + ', а в состоянии ' + $stateStatus) }
    if ($openRole -cne $currentRole) { [void]$problems.Add('по журналу открыт ' + $openRole + ', а в текущий.роль ' + $currentRole) }
    if ($openRole -and $openRound -ne $currentRound) { [void]$problems.Add('по журналу круг ' + $openRound + ', а в текущий.круг ' + $currentRound) }

    $roundsState = Get-Prop $State 'круги'
    if ($null -ne $roundsState) {
        foreach ($role in $script:Roles) {
            $count = [int](Get-Prop $roundsState $role 0)
            $max = 0
            if ($rounds.ContainsKey($role)) { $max = [int]$rounds[$role] }
            if ($count -ne $max) {
                [void]$problems.Add('круги.' + $role + '=' + $count + ', а последний открытый круг по журналу — ' + $max)
            }
        }
    }

    return [pscustomobject]@{ 'Problems' = $problems.ToArray(); 'Rounds' = $rounds }
}

function Invoke-Board($Options) {
    $rows = New-Object System.Collections.ArrayList
    if ([System.IO.Directory]::Exists($script:TasksRoot)) {
        foreach ($folder in (Get-ChildItem -LiteralPath $script:TasksRoot -Directory | Sort-Object Name)) {
            if ($folder.Name -eq '_Шаблон') { continue }
            $statePath = Join-Path $folder.FullName $script:StateName
            if (-not [System.IO.File]::Exists($statePath)) { continue }
            try {
                $state = ConvertFrom-Json (Read-TextFile $statePath)
            } catch {
                [void]$rows.Add([pscustomobject]@{
                    'задача' = $folder.Name
                    'название' = 'ошибка чтения ' + $script:StateName + ': ' + (Get-ExceptionText $_)
                    'маршрут' = '—'
                    'состояние' = '—'
                    'этап' = '—'
                    'время' = '—'
                })
                continue
            }
            $total = 0
            $times = Get-Prop $state 'время_сек'
            if ($null -ne $times) {
                foreach ($property in $times.PSObject.Properties) { $total += [int]$property.Value }
            }
            # В колонке состояния «ждёт», а рядом коротко — кого ждём.
            $statusCell = [string](Get-Prop $state 'состояние' '—')
            if ($statusCell -eq 'ждёт') {
                $who = [string](Get-Prop (Get-Prop $state 'ожидание') 'кто' '')
                if ($who) {
                    $who = $who.Replace('|', '\|')
                    if ($who.Length -gt 40) { $who = $who.Substring(0, 39) + '…' }
                    $statusCell = 'ждёт (' + $who + ')'
                }
            }
            [void]$rows.Add([pscustomobject]@{
                'задача' = [string](Get-Prop $state 'задача' $folder.Name)
                'название' = [string](Get-Prop $state 'название' '')
                'маршрут' = [string](Get-Prop $state 'маршрут' '—')
                'состояние' = $statusCell
                'этап' = [string](Get-Prop $state 'этап' '—')
                'время' = Format-Duration $total
            })
        }
    }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('| № | Название | Маршрут | Состояние | Этап | Время |')
    [void]$lines.Add('| --- | --- | --- | --- | --- | --- |')
    if ($rows.Count -eq 0) {
        [void]$lines.Add('| — | задач пока нет | — | — | — | — |')
    } else {
        foreach ($row in $rows) {
            $title = ([string]$row.'название').Replace('|', '\|')
            [void]$lines.Add('| ' + $row.'задача' + ' | ' + $title + ' | ' + $row.'маршрут' + ' | ' + $row.'состояние' + ' | ' + $row.'этап' + ' | ' + $row.'время' + ' |')
        }
    }
    $table = $lines -join "`n"
    Write-Output $table

    if ($Options.ContainsKey('write')) {
        $document = '# Задачи' + "`n`n" + 'Собрано скриптом `%USERPROFILE%\.config\opencode\scripts\taskctl.ps1 board --write`. Это единственный способ записи: доска не обновляется сама при каждом изменении, её надо пересобрать.' + "`n`n" + $table + "`n"
        try {
            Save-AtomicText (Join-Path $script:Root 'Задачи.md') $document
        } catch {
            Invoke-Abort 'запись' ('не удалось записать Задачи.md: ' + (Get-ExceptionText $_)) 3
        }
        Write-Output ''
        Write-Output 'записано: Задачи.md'
    }
}

# --- вход --------------------------------------------------------------------

function Get-Option($Options, [string]$Name) {
    if ($Options.ContainsKey($Name)) { return [string]$Options[$Name] }
    return ''
}

# Мутирующие команды идут под блокировкой задачи; finally снимает её при любом исходе.
function Invoke-WithLock($Options, [string]$Command) {
    $taskArgument = Get-Option $Options 'task'
    if (-not $taskArgument) { Invoke-Abort 'аргумент' 'нужен --task' 1 }
    $folder = Resolve-TaskFolder $taskArgument
    if ($null -eq $folder) { Invoke-Abort 'аргумент' ('задача ' + $taskArgument + ' не найдена') 1 }

    $lock = Enter-Lock (Join-Path $folder $script:LockName) 'задача' 26 200
    try {
        try {
            Repair-JournalTail $folder
        } catch {
            Invoke-Abort 'запись' ('не удалось проверить журнал: ' + (Get-ExceptionText $_)) 3
        }
        switch ($Command) {
            'start'  { Invoke-Start $Options $folder }
            'finish' { Invoke-Finish $Options $folder }
            'block'  { Invoke-Block $Options $folder }
            'resume' { Invoke-Resume $Options $folder }
        }
    } finally {
        Exit-Lock $lock
    }
}

function Invoke-Main {
    param([string[]]$Argv)

    if ($null -eq $Argv -or $Argv.Count -eq 0) {
        Show-Usage
        $script:ExitCode = 1
        return
    }

    $command = [string]$Argv[0]
    $options = @{}
    $index = 1
    while ($index -lt $Argv.Count) {
        $token = [string]$Argv[$index]
        if (-not $token.StartsWith('--')) {
            Invoke-Abort 'аргумент' ('непонятный аргумент: ' + $token) 1
        }
        $name = $token.Substring(2)
        $known = @('title', 'route', 'task', 'role', 'verdict', 'note', 'reason', 'brief', 'write', 'waiting', 'ref', 'project')
        if ($known -notcontains $name) {
            Invoke-Abort 'аргумент' ('непонятный аргумент: ' + $token) 1
        }
        if ($name -eq 'brief' -or $name -eq 'write') {
            $options[$name] = $true
            $index++
            continue
        }
        if ($index + 1 -ge $Argv.Count) {
            Invoke-Abort 'аргумент' ('у ' + $token + ' нет значения') 1
        }
        $options[$name] = [string]$Argv[$index + 1]
        $index += 2
    }

    try {
        switch ($command) {
            'new'      { Invoke-New $options }
            'start'    { Invoke-WithLock $options 'start' }
            'finish'   { Invoke-WithLock $options 'finish' }
            'resume'   { Invoke-WithLock $options 'resume' }
            'block'    { Invoke-WithLock $options 'block' }
            'unlock'   { Invoke-Unlock $options }
            'status'   { Invoke-Status $options }
            'next'     { Invoke-Next $options }
            'timeline' { Invoke-Timeline $options }
            'validate' { Invoke-Validate $options }
            'board'    { Invoke-Board $options }
            default {
                Invoke-Abort 'аргумент' ('неизвестная команда ' + $command) 1
            }
        }
    } catch {
        $message = Get-ExceptionText $_
        if ($message -eq $script:AbortMarker) {
            if ($script:AbortText) { Write-Output $script:AbortText }
        } else {
            Write-Output ('ошибка: запись: ' + $message)
            if ($script:ExitCode -eq 0) { $script:ExitCode = 3 }
        }
    }
}

$script:ExitCode = 0
$script:AbortText = ''
Invoke-Main -Argv @($args)
exit $script:ExitCode

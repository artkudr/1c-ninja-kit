# MACHINE BOOTSTRAP — голая Windows + только платформа 1С

Цель: довести машину до состояния, когда `kit.ps1 doctor` проходит required-проверки.  
Платформу 1С ставите вы (дистрибутив 1С). Остальное — **с публичных GitHub/сайтов**, не с чужого диска `C:\1C\soft`.

## 0. Проверка платформы

```powershell
Get-ChildItem "C:\Program Files\1cv8\*" -ErrorAction SilentlyContinue | Select-Object -First 5 Name
```

## 1. OneScript / OVM

1. [OneScript / OVM](https://oscript.io/) → `%LOCALAPPDATA%\ovm\current`
2. Пакеты контура (`autumn`, `autumn-mcp` и зависимости MCP-серверов) — в `lib`.

Проверено на машине: OneScript **2.2.0**, opm 1.6.5.

Если CLI `ovm` нет (на этой машине нет) — движок обновляется слотами, а не перезаписью:
скопировать текущий слот в `%LOCALAPPDATA%\ovm\<версия>`, наложить `bin\*` из архива
релиза, затем переключить junction `current` (`cmd /c mklink /J`).
Папку `lib` не трогать: в ней opm и пакеты, которыми живут MCP-серверы.
Подробности и откат — `%USERPROFILE%\.config\opencode\docs\ovm-slot-switch-2.2.0.md`.

## 2. bsl-analyzer (обязателен для семантики MCP)

**Upstream:** https://github.com/itrous/bsl-analyzer/releases  

1. Скачай **лаунчер** Windows: `bsl-analyzer-windows-amd64.exe` (не путать с огромным `bsl-analyzer-app-windows-amd64.exe` — app лаунчер подтянет сам).
2. Положи как:

```text
%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe
```

```powershell
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\bsl-analyzer" | Out-Null
# пример: после скачивания в Downloads
Copy-Item "$env:USERPROFILE\Downloads\bsl-analyzer-windows-amd64.exe" `
  "$env:LOCALAPPDATA\bsl-analyzer\bsl-analyzer.exe" -Force
& "$env:LOCALAPPDATA\bsl-analyzer\bsl-analyzer.exe" --launcher-version
# при необходимости:
# & "$env:LOCALAPPDATA\bsl-analyzer\bsl-analyzer.exe" --launcher-update
```

3. В project MCP: `bsl-analyzer-reference` (лаунчер) и `bsl-analyzer-workspace` (app-бинарник
   `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe`, `--mode broker`, см. шаблоны kit).

   Почему workspace не через лаунчер: с 0.4.0 профиль workspace по умолчанию идёт в общий backend
   (broker), а лаунчер на Windows держит потомка в Job с kill-on-close — backend умирает вместе с
   прокси и оставляет мёртвый `writer.lease`, после чего граф отвечает
   `graph busy ... used by another live process`. App-бинарник кладёт сам лаунчер при
   `--launcher-update`, путь стабилен.

   `kit.ps1 apply` дополнительно ставит задачу планировщика
   `bsl-analyzer lease clean` (при входе и каждые 5 минут): снимает мёртвые `writer.lease`
   во всех проектах и в общем кеше профиля, ничего не запускает. Задача стартует через
   `wscript.exe` и тонкий `.vbs`-лаунчер из `skill-env-setup`, поэтому консольное окно
   не появляется; прямой вызов `pwsh` в интерактивной сессии окно показывает.
4. Версия app: **≥ 0.2.86** (релиз v0.2.86 от 2026-10-07).

Документация MCP: репозиторий itrous/bsl-analyzer → docs/mcp.  
Скилл в kit: `profile/skills/skill-bsl-analyzer`.

## 3. Apache tools (web / ninja-live)

Не коммитить Apache в git. Разложите локально:

| Платформа | Порт | Каталог |
|-----------|------|---------|
| 8.3 | 8083 | `%USERPROFILE%\tools\apache-83` |
| 8.5 | 8085 | `%USERPROFILE%\tools\apache-85` |

Если 8.5 нет — doctor даст WARN; для 8.3 достаточно.

## 4. Ripgrep (поиск по коду из shell)

Рядом с Apache, в той же куче: `%USERPROFILE%\tools\ripgrep`. Нужен, чтобы поиск по исходникам из
shell был быстрым — иначе PowerShell `Select-String` на типовой выгрузке идёт минутами.

**Upstream:** https://github.com/BurntSushi/ripgrep/releases → `ripgrep-15.2.0-x86_64-pc-windows-msvc.zip`

```powershell
$dir = Join-Path $env:USERPROFILE 'tools\ripgrep'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
# распаковать asset в $dir (rg.exe кладётся в корень $dir)
[Environment]::SetEnvironmentVariable('Path',
  ([Environment]::GetEnvironmentVariable('Path','User') + ";$dir").TrimEnd(';'), 'User')
```

Проверка: `rg --version`. В PATH нужно до запуска новых сессий — текущий процесс opencode
видит старый PATH.

## 5. MCP Toolkit (optional fallback live)

**Не обязателен**, если работает NinjaLive (`live_*`).  
**Upstream:** https://github.com/ROCTUP/1c-mcp-toolkit/releases  

1. Скачай `MCP_Toolkit.epf` из **latest release** (не копируй с чужого ПК).
2. Рекомендуемый локальный путь (любой постоянный):

```text
%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf
```

```powershell
$dir = Join-Path $env:USERPROFILE 'tools\1c-mcp-toolkit'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
# скачай asset MCP_Toolkit.epf из releases в $dir
```

3. В 1С: Файл → Открыть → EPF → режим **«Встроенный сервер»** → порт **6003**.  
4. MCP URL: `http://127.0.0.1:6003/mcp`

Скилл: `profile/skills/skill-mcp-toolkit`.

## 6. Node / Playwright (optional, skill-web-test)

Только для UI smoke. Для `live_extensions_list` не нужен.

## 7. Clone kit + doctor

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git C:\1C\projects\1c-ninja-kit
cd C:\1C\projects\1c-ninja-kit
powershell -NoProfile -File .\install\kit.ps1 doctor
```

Required FAIL → не идите в apply, пока не закроете пробелы (oscript/платформа/bsl-analyzer).  
Toolkit missing → WARN (ок для ninja-only).

## 8. Дальше по харнессу

- OpenCode: `docs/opencode.md` + `docs/ADAPTATION.md`

## Сводка «откуда брать»

| Компонент | Где взять |
|-----------|-----------|
| 1C:Enterprise | ваш дистрибутив 1С |
| OneScript / OVM | https://oscript.io/ |
| vanessa-runner | `opm install` (через OVM) |
| bsl-analyzer launcher | https://github.com/itrous/bsl-analyzer/releases → `bsl-analyzer-windows-amd64.exe` |
| MCP Toolkit EPF | https://github.com/ROCTUP/1c-mcp-toolkit/releases → `MCP_Toolkit.epf` |
| 1c-ninja-mcp + NinjaLive | **внутри этого kit** (`components/`, `project-scaffold/cfe/`) |
| Apache | ваша поставка / раскладка в `%USERPROFILE%\tools\apache-8x` |
| Ripgrep | https://github.com/BurntSushi/ripgrep/releases → `%USERPROFILE%\tools\ripgrep` + PATH |

Машиночитаемые pins: `companions/pins.json`.

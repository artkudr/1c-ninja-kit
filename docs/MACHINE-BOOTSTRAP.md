# MACHINE BOOTSTRAP — голая Windows + только платформа 1С

Цель: довести машину до состояния, когда `kit.ps1 doctor` проходит required-проверки.  
Платформу 1С ставите вы (дистрибутив 1С). Остальное — **с публичных GitHub/сайтов**, не с чужого диска `C:\1C\soft`.

## 0. Проверка платформы

```powershell
Get-ChildItem "C:\Program Files\1cv8\*" -ErrorAction SilentlyContinue | Select-Object -First 5 Name
```

## 1. OneScript / OVM + vanessa-runner

1. [OneScript / OVM](https://oscript.io/) → `%LOCALAPPDATA%\ovm\current`
2. `opm install vanessa-runner@SNAPSHOT` (или зафиксированная **3.x**)
3. `vrunner --version` → ветка **3.x**
4. Рядом должен быть `vrunner-mcp.bat`

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

3. В project MCP: `bsl-analyzer-workspace` / `bsl-analyzer-reference` (см. шаблоны kit).  
4. Рекомендуемая версия app: **≥ 0.2.77** (лучше текущий release, напр. 0.2.79+).

Документация MCP: репозиторий itrous/bsl-analyzer → docs/mcp.  
Скилл в kit: `profile/skills/1c-bsl-analyzer`.

## 3. Apache tools (web / ninja-live)

Не коммитить Apache в git. Разложите локально:

| Платформа | Порт | Каталог |
|-----------|------|---------|
| 8.3 | 8083 | `%USERPROFILE%\tools\apache-83` |
| 8.5 | 8085 | `%USERPROFILE%\tools\apache-85` |

Если 8.5 нет — doctor даст WARN; для 8.3 достаточно.

## 4. MCP Toolkit (optional fallback live)

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

Скилл: `profile/skills/1c-mcp-toolkit`.

## 5. Node / Playwright (optional, web-test)

Только для UI smoke. Для `live_extensions_list` не нужен.

## 6. Clone kit + doctor

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git C:\1C\projects\1c-ninja-kit
cd C:\1C\projects\1c-ninja-kit
powershell -NoProfile -File .\install\kit.ps1 doctor
```

Required FAIL → не идите в apply, пока не закроете пробелы (oscript/vrunner/bsl-analyzer).  
Toolkit missing → WARN (ок для ninja-only).

## 7. Дальше по харнессу

- DeepSeek: `docs/TEST-GUIDE-deepseek.md`
- Hermes: `docs/TEST-GUIDE-hermes.md`
- Cursor: `adapters/cursor/` + `docs/ADAPTATION.md`

## Локальные патчи vrunner (optional)

См. `profile/docs-patches/vrunner-local-patches.md`.

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

Машиночитаемые pins: `companions/pins.json`.

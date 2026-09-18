---
name: 1c-env-setup
description: >-
  Развёртывание окружения 1С в новой папке на той же машине.
  Используй когда пользователь говорит «разверни окружение», /1c-env-setup,
  просит подготовить проект или настроить autumn/repository/src/cfe/MCP.
  Копирует src/cfe/NinjaLive, грузит в ИБ, список расширений — live_extensions_list (не Предприятие).
argument-hint: "[-SourceProject path] [-Mode Init|Refresh|Check] [-Force]"
---

# /1c-env-setup — Развёртывание окружения 1С

Личный скилл: `%USERPROFILE%\.cursor\skills\1c-env-setup\`.

Разворачивает **привычное** окружение в **новой папке** на **той же машине** (clone / копия / worktree). Софт уже установлен — скилл не ставит vrunner/OVM/Apache.

Пользователь **не** правит JSON руками: агент показывает базы, спрашивает логин/пароль и **сам записывает** настройки.

## Когда вызывать

- Фраза **«разверни окружение»** (основной синоним)
- `/1c-env-setup`
- «подготовь проект», «настрой окружение 1С»

**Не** для первой настройки ПК с нуля.

## Обязательные артефакты (после setup)

| Файл / каталог | Зачем |
|----------------|--------|
| `autumn-properties.json` | ИБ для vrunner 3 |
| `repository.json` | карта CFE → `repo-workflow` (**без файла setup failed**) |
| `src/cfe/NinjaLive/` | bootstrap live (копия эталона, не хранилище) |
| `src/cfe/<Имя>/` | пустые папки под остальные расширения |
| `.cursor/mcp.json.example` | эталон скилла без секретов (в git) |
| `.cursor/mcp.json` | полный MCP этой ИБ из шаблона скилла (gitignore) |
| `bsl-analyzer.toml` | диагностики / source roots |
| `.cursor/rules/*.mdc` | из канона профиля: **hardlink** (`mklink /H`); file symlink если есть право; копия только другой диск; directory junction **запрещён** |
| `.cursor/commands/opsx-*.md` | slash-команды OpenSpec (propose / apply / archive / explore) |
| `openspec/` | scaffold: README, `config.yaml`, `project.md`, `templates/`, пустые `specs/` и `changes/archive/` |

Канон правил — `%USERPROFILE%\.cursor\rules\`. Cursor читает **только** project `.cursor/rules/*.mdc` как обычные файлы (папку профиля агент не применяет; Customize textarea не умеет glob).

**Junction ≠ symlink.** `mklink /J` (directory junction) **не** требует admin/Developer Mode — поэтому junction на папку раньше создавался. File symlink (`mklink`) и `mklink /D` требуют `SeCreateSymbolicLinkPrivilege` / Developer Mode. Это разные операции.

Folder junction (`mklink /J` / `/D` на `.cursor/rules`) **не использовать**: Cursor/индексатор его плохо ест. Init/Refresh: **обычная папка** + для каждого `.mdc`:
1. file symlink (`mklink` без `/J`/`/D`) — если есть право;
2. иначе **hardlink** `mklink /H` (канон на этой машине: тот же том C:, без Developer Mode, Cursor видит обычный файл, правки в профиле = правки в проекте);
3. копия — **только** если другой диск (hardlink не встанет).

Править любой из двух путей hardlink — один inode. Не считать проект отдельным каноном.

## Жёсткие правила

- **Не** отвечай «открой autumn-properties и впиши сам» — это провал сценария.
- **Не** используй реестр PT — проект autumn-only (autumn / vrunner).
- **Не** правь XML метаданных. В рамках setup в ИБ грузится **только** bootstrap CFE `NinjaLive` (MCP `cfe_load`) — чтобы список расширений шёл по HTTP, без запуска Предприятия.
- **Не** копируй и **не** мержи `%USERPROFILE%\.cursor\mcp.json` в проект. Эталон JSON — шаблон скилла (`scripts/templates/mcp.json.example.tpl`) → `.cursor/mcp.json`.
- **Не** клади 1С-серверы (`vrunner`, `1c-ninja-mcp`, `1c-mcp-toolkit`, `bsl-analyzer-*`) в user `mcp.json`: Cursor читает оба файла, одинаковые имена дают дубли. User mcp — пустой `mcpServers` (или без этих имён). Live-URL только в project mcp **этой** ИБ.
- Список расширений ИБ — **главный способ**: MCP `1c-ninja-mcp` `live_extensions_list` (HTTP `/hs/ninja-live`). Порядок: `src/cfe/NinjaLive` → `cfe_load` → публикация → `live_extensions_list`. **Не** `vrunner infobase extensions list` / MCP `extensions_list` (это запуск Предприятия). **Не** `extensions_dump_list` для обзора состава. **Не** удалённый `cfe-list`.
- Список пользователей ИБ **не** запрашиваем.
- **Никогда** directory junction на `.cursor/rules` (`mklink /J` / `/D`). Init/Refresh: если папка — junction, снять `cmd /c rmdir` (без `/S`), создать обычную папку, для каждого `.mdc` — file symlink, иначе `mklink /H`, копия только другой диск. `Remove-Item -Recurse` по junction **запрещён**. Канон в `%USERPROFILE%\.cursor\rules` не удалять.

## История скилла

- 2026-09-17: Junction `/J` ≠ file symlink: `/J` не требует Developer Mode, но на папку `.cursor/rules` его не ставим (Cursor). File symlink пробуем первым; канон на этой машине — **hardlink** `mklink /H` файлов; копия только другой диск. Старый `/J` снимать через `cmd /c rmdir`.
- 2026-09-17: Folder junction на `.cursor/rules` **запрещён** (Cursor/индексатор не видит правила).
- 2026-09-17: MCP-эталон в шаблоне скилла (полный JSON: vrunner, toolkit, ninja live, bsl-analyzer reference+workspace). Setup **не** копирует user `mcp.json`. User `mcp.json` без 1С-серверов — иначе дубли.
- 2026-09-18: Live ninja — CFE `NinjaLive` (`/hs/ninja-live`), env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` (не `BSL_Analyzer` / `BSL_ANALYZER_*`).
- 2026-09-18: Список расширений ИБ — **главный способ** `live_extensions_list`. Setup копирует `src/cfe/NinjaLive`, агент грузит `cfe_load`, затем HTTP-список. `vrunner infobase extensions list` / MCP `extensions_list` — не канон (запуск Предприятия).
- 2026-09-18: OpenSpec scaffold: `.cursor/commands/opsx-*.md` + `openspec/` (шаблоны из скилла). Refresh **не** затирает живые `openspec/changes/*`, `openspec/specs/*/spec.md`, `config.yaml` и `project.md` без `-Force`. Из SourceProject **не** копируются changes и specs.

## Workflow агента (обязательный порядок)

### 1. Sanity

- `vrunner --version` — нет → стоп: «стек на машине не готов».
- Определи корень = открытый workspace.

### 2. SourceProject

- Если пользователь не указал: ищи sibling в `C:\1C\projects\` (есть `autumn-properties.json` + `repository.json`) и предложи выбрать.
- Иначе спроси путь или продолжай с шаблонов.

### 3. Выбор базы (интерактив)

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\1c-env-setup\scripts\read-ibases.ps1"
# или -Json
```

Покажи таблицу пользователю. Спроси:

1. номер из списка, **или**
2. «та же, что в SourceProject», **или**
3. ручной ввод server/ref или путь файловой базы.

Сформируй `ibconnection`: `/S"server/ref"` или `/F"path"`.

### 4. Логин и пароль (интерактив)

1. Если есть SourceProject — предложи `db-user` оттуда (пароль спросить/подтвердить).
2. Спроси **имя** и **пароль** (пустой — только с явным «да»).
3. Запиши `autumn-properties.json` (шаг 5) и **проверь вход загрузкой NinjaLive**, не списком через Предприятие: MCP vrunner `cfe_load` `SRC=./src/cfe/NinjaLive` `extension-name=NinjaLive`. Auth-ошибка → снова логин/пароль, **не** оставлять битый пароль в файле. Успешный load = учётка верна.

Пользователь хранилища (`repository.json` → `user`): при копировании SourceProject не спрашивать; иначе один раз (не путать с пользователем ИБ).

### 5. Запись файлов

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\1c-env-setup\scripts\env-setup.ps1" `
  -Mode Init `
  -ProjectRoot "<корень>" `
  -SourceProject "<соседний>" `
  -IbConnection '<строка>' `
  -DbUser "<имя>" `
  -DbPwd "<пароль>" `
  -V8Version "8.3.27.xxxx" `
  -AppName "<имя-публикации>"
```

Скрипт создаёт каталоги, autumn, repository, mcp example + mcp.json **из шаблона скилла** (не из user settings), bsl-analyzer.toml, gitignore, docs, smoke.config; **копирует** `src/cfe/NinjaLive` с эталона (SourceProject или `C:\1C\projects\ecoladev\src\cfe\NinjaLive`); **синхронизирует** `.cursor/rules/*.mdc` из профиля; **разворачивает** OpenSpec scaffold (`.cursor/commands/opsx-*.md`, `openspec/templates/`, README, `config.yaml`/`project.md` из tpl); вызывает `sync-cfe.ps1` **без** опроса ИБ через Предприятие (пусто или `-ExtensionNames`, если агент уже снял список). Warn, если user `mcp.json` содержит те же имена серверов.

Режимы:

| Mode | Поведение |
|------|-----------|
| `Init` | полная инициализация (default) |
| `Refresh` | не затирать конфиги, openspec changes/specs, commands без `-Force`; каталоги + sync-cfe |
| `Check` | dry-run отчёт без записи |

### 6. Bootstrap NinjaLive + список CFE (главный способ)

После записи файлов агент **обязан** (это не «ручной шаг пользователя»):

1. Убедиться, что `src/cfe/NinjaLive/Configuration.xml` есть (скрипт Init копирует с эталона). Эталон: SourceProject `src/cfe/NinjaLive`, иначе `C:\1C\projects\ecoladev\src\cfe\NinjaLive`.
2. MCP vrunner `cfe_load`: `SRC=./src/cfe/NinjaLive`, `extension-name=NinjaLive`, `active=true`, `safe-mode=false`. NinjaLive **не** в `repository.json` → не `repo.ps1`.
3. `web-publish` этой ИБ, если нет HTTP `/hs/ninja-live` (`publishExtensionsByDefault`).
4. Reload MCP. В project mcp: `NINJA_URL=http://localhost:{8083|8085}/{appName}/hs/ninja-live`.
5. Smoke: `live_version` → версия CFE (`0.1.0.0` на старте).
6. **Список расширений ИБ:** MCP `live_extensions_list` (без `url`, если env уже NINJA_*). Не Предприятие, не `extensions_list`.
7. Папки `src/cfe/<Имя>`: `sync-cfe.ps1 -ProjectRoot . -ExtensionNames @("Имя1","Имя2",…)`.

### 7. Отчёт пользователю

Готово / пропущено / **ручные шаги**:

1. Reload MCP в Cursor (источник 1С-серверов — project `.cursor/mcp.json`)
2. Если агент не сделал шаг 6: `cfe_load` NinjaLive → `web-publish` → `live_extensions_list` → `sync-cfe -ExtensionNames`
3. Прогрев bsl-analyzer (`graph`/`metadata` status → ready)
4. toolkit `:6003` — только fallback

## Скрипты

| Скрипт | Назначение |
|--------|------------|
| `scripts/read-ibases.ps1` | таблица / `-Json` из `ibases.v8i` |
| `scripts/env-setup.ps1` | оркестратор каркаса и конфигов |
| `scripts/sync-cfe.ps1` | имена из `-ExtensionNames` (агент: `live_extensions_list`) → `src/cfe/<Имя>` + `repository.json.cfe`; **не** запускает Предприятие |

```powershell
# Только список баз
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\1c-env-setup\scripts\read-ibases.ps1" -Json

# Только sync CFE (имена с live_extensions_list; без Предприятия)
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\1c-env-setup\scripts\sync-cfe.ps1" -ProjectRoot "." -ExtensionNames @("Имя1","Имя2")

# Check на текущем проекте
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\1c-env-setup\scripts\env-setup.ps1" -Mode Check -ProjectRoot "."
```

## Связанные скиллы

- `1c-project-context` — что читать после setup
- `repo-workflow` — работа с CFE из `repository.json` (не NinjaLive)
- `1c-ninja-mcp` — live, в т.ч. **главный** список CFE: `live_extensions_list`
- `1c-bsl-analyzer` — семантика кода
- `web-publish` — публикация `/hs/ninja-live`
- `vrunner-mcp` — `cfe_load` NinjaLive / syntax-check (не `extensions_list`)

Подробности форматов: [reference.md](reference.md).

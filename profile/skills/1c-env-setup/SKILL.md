---
name: 1c-env-setup
description: >-
  Развёртывание окружения 1С в новой папке на той же машине.
  Используй когда пользователь говорит «разверни окружение», /1c-env-setup,
  просит подготовить проект или настроить `.v8-project.json` / `src/cfe` / MCP.
  Копирует src/cfe/NinjaLive, грузит в ИБ, список расширений — live_extensions_list (не Предприятие).
argument-hint: "[-SourceProject path] [-Mode Init|Refresh|Check] [-Force]"
---

# /1c-env-setup — Развёртывание окружения 1С

Личный скилл: `{{SKILLS_ROOT}}\1c-env-setup\`.

Разворачивает **привычное** окружение в **новой папке** на **той же машине** (clone / копия / worktree). Софт уже установлен — скилл не ставит OVM/Apache; набор cc-1c-skills ставится `install/cc-skills.ps1`.

Пользователь **не** правит JSON руками: агент показывает базы, спрашивает логин/пароль и **сам записывает** настройки.

## Адаптер harness (`-Adapter opencode`)

| | `opencode` |
|---|---|
| MCP проекта | `opencode.jsonc` + `opencode.jsonc.example` (`mcp.servers`, `type: local/remote`, `oauth: false` у streamable-http) |
| Команды | `.opencode/commands/opsx-*.md` |
| Правила | **не создаются**: always-on → глобальный `~/.config/opencode/AGENTS.md`, on-demand → `~/.config/opencode/kit-rules/` (`kit.ps1 apply -Adapter opencode`) |
| Проверка дублей | `~/.config/opencode/opencode.json(c)` → `mcp.servers` |

`-WebPort <n>` — переопределить порт публикации (иначе 8083/8085 по версии платформы). Нужен, когда Apache на машине слушает один порт на все базы.

## Когда вызывать

- Фраза **«разверни окружение»** (основной синоним)
- `/1c-env-setup`
- «подготовь проект», «настрой окружение 1С»

**Не** для первой настройки ПК с нуля.

## Обязательные артефакты (после setup)

| Файл / каталог | Зачем |
|----------------|--------|
| `.v8-project.json` | реестр баз: ИБ, платформа, web, карта CFE (хранилища) |
| `src/cfe/NinjaLive/` | bootstrap live (копия эталона, не хранилище) |
| `src/cfe/<Имя>/` | пустые папки под остальные расширения |
| `opencode.jsonc` + `.example` | полный MCP этой ИБ (gitignore) + эталон без секретов |
| `.build/` | кеш bsl-analyzer (граф + поиск); передаётся как `--cache-dir`, в `.gitignore` |
| `bsl-analyzer.toml` | диагностики / source roots |
| `.opencode/commands/opsx-*.md` | slash-команды OpenSpec (propose / apply / archive / explore) |
| `openspec/` | scaffold: README, `config.yaml`, `project.md`, `templates/`, пустые `specs/` и `changes/archive/` |

Правила: always-on — глобальный `~/.config/opencode/AGENTS.md`, on-demand — `~/.config/opencode/kit-rules/` (обновляет `kit.ps1 apply -Adapter opencode`). В проекте rules не создаются.

## Жёсткие правила

- **Не** отвечай «открой `.v8-project.json` и впиши сам» — это провал сценария.
- **Не** используй реестр PT.
- **Не** правь XML метаданных. В рамках setup в ИБ грузится **только** bootstrap CFE `NinjaLive` (скилл `db-load-xml -Extension`) — чтобы список расширений шёл по HTTP, без запуска Предприятия.
- **Не** копируй и **не** мержи `%USERPROFILE%\.cursor\mcp.json` в проект. Эталон JSON — шаблон скилла (`scripts/templates/mcp.json.example.tpl`) → `{{PROJECT_MCP}}`.
- **Не** клади 1С-серверы (`1c-ninja-mcp`, `1c-mcp-toolkit`, `bsl-analyzer-*`, `v8std`) в user-конфиг: одинаковые имена дают дубли с проектом. Live-URL только в project MCP **этой** ИБ.
- `bsl-analyzer-workspace` в project MCP **всегда** с `--cache-dir "<корень>\.build"`: кеш живёт в проекте (`.build` в `.gitignore`), а не в профиле пользователя. Без этого флага анализатор пишет в `%LOCALAPPDATA%`.
- Список расширений ИБ — **главный способ**: MCP `1c-ninja-mcp` `live_extensions_list` (HTTP `/hs/ninja-live`). Порядок: `src/cfe/NinjaLive` → `db-load-xml -Extension` → публикация → `live_extensions_list`. **Не** запускать Предприятие ради списка.
- Список пользователей ИБ **не** запрашиваем.

## История скилла

- 2026-10-20: Кеш bsl-analyzer — в проекте: `bsl-analyzer-workspace` в шаблонах MCP запускается с `--cache-dir "<корень>\.build"`. Причина: кеш переживает перезапуски (тёплый старт — обход файлов, правки — инкремент), но не должен занимать профиль пользователя (~4 ГБ на крупной конфигурации).
- 2026-10-14: Контур скиллов: реестр баз `.v8-project.json`; bootstrap NinjaLive — `db-load-xml -Extension` + `db-cfe-admin set-properties`; cc-1c-skills ставится `install/cc-skills.ps1`.
- 2026-10-02: `-Adapter opencode`: project MCP в `opencode.jsonc` (`mcp.servers`, V2-схема); команды в `.opencode/commands`; `.cursor/rules` не создаются (глобальный `AGENTS.md` + `kit-rules`). Добавлен `-WebPort`. `main.os` ищется в `NINJA_MCP_ROOT` → `1c-ninja-kit\components\1c-ninja-mcp` → `1c-ninja-mcp`.
- 2026-09-22: В эталон MCP добавлен `v8std` (`https://ai.v8std.ru/mcp`, streamable-http; стандарты ITS/v8). Не класть в user-конфиг.
- 2026-09-17: MCP-эталон в шаблоне скилла (полный JSON: toolkit, ninja live, bsl-analyzer reference+workspace, v8std). Setup **не** копирует user-конфиг. User-конфиг без 1С-серверов — иначе дубли.
- 2026-09-18: Live ninja — CFE `NinjaLive` (`/hs/ninja-live`), env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` (не `BSL_Analyzer` / `BSL_ANALYZER_*`).
- 2026-09-18: Список расширений ИБ — **главный способ** `live_extensions_list`. Setup копирует `src/cfe/NinjaLive`, агент грузит `db-load-xml -Extension`, затем HTTP-список.
- 2026-09-18: OpenSpec scaffold: `.opencode/commands/opsx-*.md` + `openspec/` (шаблоны из скилла). Refresh **не** затирает живые `openspec/changes/*`, `openspec/specs/*/spec.md`, `config.yaml` и `project.md` без `-Force`. Из SourceProject **не** копируются changes и specs.

## Workflow агента (обязательный порядок)

### 1. Sanity

- Платформа `1cv8` и набор cc-1c-skills (`db-list` в skills root) — нет → стоп: «стек на машине не готов».
- Определи корень = открытый workspace.

### 2. SourceProject

- Если пользователь не указал: ищи sibling в `C:\1C\projects\` (есть `.v8-project.json`) и предложи выбрать.
- Иначе спроси путь или продолжай с шаблонов.

### 3. Выбор базы (интерактив)

```powershell
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\1c-env-setup\scripts\read-ibases.ps1"
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
3. Запиши `.v8-project.json` (шаг 5) и **проверь вход загрузкой NinjaLive**, не списком через Предприятие: `db-load-xml -ConfigDir "src\cfe\NinjaLive" -Mode Full -Extension "NinjaLive"`. Auth-ошибка → снова логин/пароль, **не** оставлять битый пароль в файле. Успешный load = учётка верна.

Пользователь хранилища (`.v8-project.json` → `extensions[].repository.user`): при копировании SourceProject не спрашивать; иначе один раз (не путать с пользователем ИБ).

### 5. Запись файлов

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\.config\opencode\skills\1c-env-setup\scripts\env-setup.ps1" `
  -Mode Init `
  -ProjectRoot "<корень>" `
  -SourceProject "<соседний>" `
  -Adapter opencode `
  -WebPort 8083 `
  -IbConnection '/F"C:\1C\bases\base"' `
  -DbUser "<имя>" `
  -DbPwd "" `
  -V8Version "8.5.1.1343" `
  -AppName "<имя-публикации>"
```

Скрипт создаёт каталоги, `.v8-project.json`, mcp example + `opencode.jsonc` **из шаблона скилла** (не из user settings), bsl-analyzer.toml, gitignore, docs, smoke.config; **копирует** `src/cfe/NinjaLive` с эталона (SourceProject или `C:\1C\projects\my-project\src\cfe\NinjaLive`); **разворачивает** OpenSpec scaffold (`.opencode/commands/opsx-*.md`, `openspec/templates/`, README, `config.yaml`/`project.md` из tpl); вызывает `sync-cfe.ps1` **без** опроса ИБ через Предприятие (пусто или `-ExtensionNames`, если агент уже снял список). Warn, если user-конфиг содержит те же имена серверов.

В `opencode.jsonc` (и в `.example`) `bsl-analyzer-workspace` пишется с `--source-dir "<корень>"` **и** `--cache-dir "<корень>\.build"` — кеш графа и поиска остаётся в проекте, а не в `%LOCALAPPDATA%`. Каталог `.build` уже в gitignore-сниппете; шаблоны обновлены вместе со скиллом, отдельного флага в `env-setup.ps1` нет.

Режимы:

| Mode | Поведение |
|------|-----------|
| `Init` | полная инициализация (default) |
| `Refresh` | не затирать конфиги, openspec changes/specs, commands без `-Force`; каталоги + sync-cfe |
| `Check` | dry-run отчёт без записи |

### 6. Bootstrap NinjaLive + список CFE (главный способ)

После записи файлов агент **обязан** (это не «ручной шаг пользователя»):

1. Убедиться, что `src/cfe/NinjaLive/Configuration.xml` есть (скрипт Init копирует с эталона). Эталон: SourceProject `src/cfe/NinjaLive`, иначе `C:\1C\projects\my-project\src\cfe\NinjaLive`.
2. `db-load-xml -ConfigDir "src\cfe\NinjaLive" -Mode Full -Extension "NinjaLive" -UpdateDB`; затем `db-cfe-admin set-properties -Name "NinjaLive" -Active on -SafeMode off`. NinjaLive — вне хранилища.
3. `web-publish` этой ИБ, если нет HTTP `/hs/ninja-live` (`publishExtensionsByDefault`).
4. Reload MCP. В project mcp: `NINJA_URL=http://localhost:{8083|8085}/{appName}/hs/ninja-live`.
5. Smoke: `live_version` → версия CFE (`0.1.0.0` на старте).
6. **Список расширений ИБ:** MCP `live_extensions_list` (без `url`, если env уже NINJA_*). Не Предприятие.
7. Папки `src/cfe/<Имя>`: `sync-cfe.ps1 -ProjectRoot . -ExtensionNames @("Имя1","Имя2",…)`.

### 7. Отчёт пользователю

Готово / пропущено / **ручные шаги**:

1. Reload MCP в OpenCode (источник 1С-серверов — project `opencode.jsonc`)
2. Если агент не сделал шаг 6: `cfe_load` NinjaLive → `web-publish` → `live_extensions_list` → `sync-cfe -ExtensionNames`
3. Прогрев bsl-analyzer (`graph`/`metadata` status → ready)
4. toolkit `:6003` — только fallback

## Скрипты

| Скрипт | Назначение |
|--------|------------|
| `scripts/read-ibases.ps1` | таблица / `-Json` из `ibases.v8i` |
| `scripts/env-setup.ps1` | оркестратор каркаса и конфигов |
| `scripts/sync-cfe.ps1` | имена из `-ExtensionNames` (агент: `live_extensions_list`) → `src/cfe/<Имя>` + `repository.json.cfe`; **не** запускает Предприятие |
| `scripts/sync-ninja-properties.ps1` | синхронизирует контролируемые свойства bootstrap-расширения с конфигурацией, которую оно расширяет |

```powershell
# Только список баз
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\1c-env-setup\scripts\read-ibases.ps1" -Json

# Только sync CFE (имена с live_extensions_list; без Предприятия)
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\1c-env-setup\scripts\sync-cfe.ps1" -ProjectRoot "." -ExtensionNames @("Имя1","Имя2")

# Check на текущем проекте
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\1c-env-setup\scripts\env-setup.ps1" -Mode Check -ProjectRoot "."
```

### Свойства расширения под базу (шаг 6.0)

Bootstrap-расширение, скопированное из другого проекта или из кита, несёт значения **чужой**
конфигурации, и `cfe_load` падает:

```text
NinjaLive: Значение контролируемого свойства РежимСовместимостиИнтерфейса ... не совпадает
           со значением в расширяемой конфигурации
NinjaLive: Значение контролируемого свойства ОбъектРасширяемойКонфигурации
           у объекта Язык.Русский не совпадает ...
```

Причина — три значения, которые обязаны зеркалить расширяемую конфигурацию:
`Configuration.xml/ConfigurationExtensionCompatibilityMode`, `Configuration.xml/InterfaceCompatibilityMode`,
`Languages/<язык>.xml/ExtendedConfigurationObject` (uuid языка в базе). Команды MCP для
этой синхронизации в стеке нет, платформа даёт её только интерактивно в конфигураторе
(«обновить свойства расширения»). Скрипт делает это механически, идемпотентно, не трогая
выгрузку конфигурации:

```powershell
powershell.exe -NoProfile -File "...\1c-env-setup\scripts\sync-ninja-properties.ps1" -ProjectRoot "." -Check
powershell.exe -NoProfile -File "...\1c-env-setup\scripts\sync-ninja-properties.ps1" -ProjectRoot "."
```

Работает и для любого другого bootstrap-расширения: `-ExtensionName`, `-ConfigDir`, `-ExtensionDir`.

## Связанные скиллы

- `1c-project-context` — что читать после setup
- `repo-workflow` — работа с CFE из хранилища (не NinjaLive)
- `1c-ninja-mcp` — live, в т.ч. **главный** список CFE: `live_extensions_list`
- `1c-bsl-analyzer` — семантика кода
- `web-publish` — публикация `/hs/ninja-live`
- `db-*` — операции с ИБ (load/dump/update/расширения); `1c-syntax-check` — синтакс-контроль конфигурации

Подробности форматов: [reference.md](reference.md).

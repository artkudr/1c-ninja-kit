---
name: skill-env-setup
description: >-
  Развёртывание окружения 1С в новой папке на той же машине.
  Используй когда пользователь говорит «разверни окружение», `skill-env-setup`,
  просит подготовить проект или настроить `.v8-project.json` / `src/cfe` / MCP.
  Копирует src/cfe/NinjaLive, грузит в ИБ, список расширений — live_extensions_list (не Предприятие).
argument-hint: "[-SourceProject path] [-Mode Init|Refresh|Check] [-Force]"
---

# skill-env-setup — Развёртывание окружения 1С

Личный скилл: `{{SKILLS_ROOT}}\kit\skills\skill-env-setup\`.

Разворачивает **привычное** окружение в **новой папке** на **той же машине** (clone / копия / worktree). Софт уже установлен — скилл не ставит OVM/Apache; набор cc-1c-skills ставится `install/cc-skills.ps1`.

Пользователь **не** правит JSON руками: агент показывает базы, спрашивает логин/пароль и **сам записывает** настройки.

## Harness OpenCode

| | `opencode` |
|---|---|
| MCP проекта | `opencode.jsonc` (`mcp.servers`, `type: local/remote`, `oauth: false` у streamable-http) |
| Команды | `.opencode/commands/opsx-*.md` |
| Правила | глобальные always-on → `~/.config/opencode/AGENTS.md`, on-demand → `~/.config/opencode/skills/kit/rules/` (`kit.ps1 apply`); в проекте — только `AGENTS.md` как память проекта (создаётся setup, не перезаписывается) |
| Проверка дублей | `~/.config/opencode/opencode.json(c)` → `mcp.servers` |

`-WebPort <n>` — переопределить порт публикации (иначе 8083/8085 по версии платформы). Нужен, когда Apache на машине слушает один порт на все базы.

## Когда вызывать

- Фраза **«разверни окружение»** (основной синоним)
- `/skill-env-setup`
- «подготовь проект», «настрой окружение 1С»

**Не** для первой настройки ПК с нуля.

## Обязательные артефакты (после setup)

| Файл / каталог | Зачем |
|----------------|--------|
| `.v8-project.json` | реестр баз: ИБ, платформа, web, карта CFE (хранилища) |
| `AGENTS.md` | память проекта: короткие правила и невыводимые факты; создаётся из шаблона, дальше правится вручную |
| `src/cfe/NinjaLive/` | bootstrap live (копия эталона, не хранилище) |
| `src/cfe/<Имя>/` | пустые папки под остальные расширения |
| `opencode.jsonc` + `.example` | полный MCP этой ИБ (gitignore) + эталон без секретов |
| `.build/` | кеш bsl-analyzer (граф + поиск); передаётся как `--cache-dir`, в `.gitignore` |
| `bsl-analyzer.toml` | диагностики / source roots |
| `.opencode/commands/opsx-*.md` | slash-команды OpenSpec (propose / apply / archive / explore) |
| `openspec/` | scaffold: README, `config.yaml`, `project.md`, `templates/`, пустые `specs/` и `changes/archive/` |

Правила: always-on — глобальный `~/.config/opencode/AGENTS.md`, on-demand — `~/.config/opencode/skills/kit/rules/` (обновляет `kit.ps1 apply`). В проекте создаётся только корневой `AGENTS.md` — память проекта, не копия глобальных правил; setup его не перезаписывает.

## Жёсткие правила

- **Не** отвечай «открой `.v8-project.json` и впиши сам» — это провал сценария.
- **Не** используй реестр PT.
- **Не** правь XML метаданных. В рамках setup в ИБ грузится **только** bootstrap CFE `NinjaLive` (скилл `db-load-xml -Extension`) — чтобы список расширений шёл по HTTP, без запуска Предприятия.
- **Не** копируй и **не** мержи пользовательский `~/.config/opencode/opencode.json(c)` в проект. Эталон — шаблон скилла `scripts/templates/opencode.jsonc.tpl` → `{{PROJECT_MCP}}`.
- **Не** клади 1С-серверы (`1c-ninja-mcp`, `1c-mcp-toolkit`, `bsl-analyzer-*`, `v8std`) в user-конфиг: одинаковые имена дают дубли с проектом. Live-URL только в project MCP **этой** ИБ.
- `bsl-analyzer-workspace` в project MCP **всегда** с `--cache-dir "<корень>\.build"`: кеш живёт в проекте (`.build` в `.gitignore`), а не в профиле пользователя. Без этого флага анализатор пишет в `%LOCALAPPDATA%`.
- `bsl-analyzer-workspace` запускается **не лаунчером**, а `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe` с `--mode broker` и `BSL_MCP_IDLE_TTL_SECS` / `BSL_MCP_ORPHAN_GRACE_SECS` = 86400. Лаунчер держит потомка в Windows Job с kill-on-close и убивает broker-backend вместе с прокси (upstream `itrous/bsl-analyzer#345`); после этого остаётся мёртвый `writer.lease`, и граф отвечает `graph busy ... used by another live process`. `bsl-analyzer-reference` остаётся на лаунчере — ему backend не нужен.
- Список расширений ИБ — **главный способ**: MCP `1c-ninja-mcp` `live_extensions_list` (HTTP `/hs/ninja-live`). Порядок: `src/cfe/NinjaLive` → `db-load-xml -Extension` → публикация → `live_extensions_list`. **Не** запускать Предприятие ради списка.
- Список пользователей ИБ **не** запрашиваем.

## Workflow агента (обязательный порядок)

### 1. Sanity

- Платформа `1cv8` и набор cc-1c-skills (`db-list` в skills root) — нет → стоп: «стек на машине не готов».
- Определи корень = открытый workspace.

### 2. SourceProject

- Если пользователь не указал: ищи sibling в `C:\1C\projects\` (есть `.v8-project.json`) и предложи выбрать.
- Иначе спроси путь или продолжай с шаблонов.

### 3. Выбор базы (интерактив)

```powershell
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\kit\skills\skill-env-setup\scripts\read-ibases.ps1"
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
powershell.exe -NoProfile -File "$env:USERPROFILE\.config\opencode\skills\kit\skills\skill-env-setup\scripts\env-setup.ps1" `
  -Mode Init `
  -ProjectRoot "<корень>" `
  -SourceProject "<соседний>" `
  -WebPort 8083 `
  -IbConnection '/F"C:\1C\bases\base"' `
  -DbUser "<имя>" `
  -DbPwd "" `
  -V8Version "8.5.1.1343" `
  -AppName "<имя-публикации>"
```

Скрипт создаёт каталоги, `.v8-project.json`, mcp example + `opencode.jsonc` **из шаблона скилла** (не из user settings), `AGENTS.md`, bsl-analyzer.toml, `.gitignore`, `.ignore`, docs, smoke.config; **копирует** `src/cfe/NinjaLive` с эталона (SourceProject → kit `project-scaffold/cfe/NinjaLive` → соседний проект); **разворачивает** OpenSpec scaffold (`.opencode/commands/opsx-*.md`, `openspec/templates/`, README, `config.yaml`/`project.md` из tpl); вызывает `sync-cfe.ps1` **без** опроса ИБ через Предприятие (пусто или `-ExtensionNames`, если агент уже снял список). Warn, если user-конфиг содержит те же имена серверов.

В `opencode.jsonc` (и в `.example`) `bsl-analyzer-workspace` пишется с `--source-dir "<корень>"`, `--cache-dir "<корень>\.build"` и `--mode broker`, а запускается из `bsl-analyzer-app.exe` (не лаунчера) — кеш графа и поиска остаётся в проекте, backend переживает закрытие клиента. Каталог `.build` уже в gitignore-сниппете. Отдельного флага в `env-setup.ps1` нет: путь app-бинарника берётся из `Get-McpMachinePaths` (`%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe`).

Машинная часть (один раз на машину, делает `kit.ps1 apply`): задача планировщика `bsl-analyzer lease clean` — при входе и каждые 5 минут снимает мёртвые `writer.lease` в кешах всех проектов и в общем кеше профиля. Ничего не запускает; лог только при изменениях — `%LOCALAPPDATA%\bsl-analyzer\lease-clean.log`. Задача запускается через `wscript.exe` и `.vbs`-лаунчер (`scripts\bsl-analyzer-lease-clean.vbs` рядом со скриптом), поэтому консольного окна на каждый прогон нет: прямой вызов `pwsh` в интерактивной сессии окно показывает, `-WindowStyle Hidden` его не скрывает. Существующие проекты переводятся на новую схему `install\migrate-bsl-analyzer-broker.ps1` (идемпотентно, `-DryRun`).

Режимы:

| Mode | Поведение |
|------|-----------|
| `Init` | полная инициализация (default) |
| `Refresh` | не затирать конфиги, openspec changes/specs, commands без `-Force`; каталоги + sync-cfe |
| `Check` | dry-run отчёт без записи |

### 6. Bootstrap NinjaLive + список CFE (главный способ)

После записи файлов агент **обязан** (это не «ручной шаг пользователя»):

1. Убедиться, что `src/cfe/NinjaLive/Configuration.xml` есть (скрипт Init копирует с эталона). Эталон: SourceProject `src/cfe/NinjaLive`, иначе kit `project-scaffold/cfe/NinjaLive` (поиск через `NINJA_KIT_ROOT` / `C:\1C\projects\1c-ninja-kit`), иначе соседний проект.
2. `db-load-xml -ConfigDir "src\cfe\NinjaLive" -Mode Full -Extension "NinjaLive" -UpdateDB`; затем `db-cfe-admin set-properties -Name "NinjaLive" -Active on -SafeMode off`. NinjaLive — вне хранилища.
3. `skill-web-publish` этой ИБ, если нет HTTP `/hs/ninja-live` (`publishExtensionsByDefault`).
4. Reload MCP. В project mcp: `NINJA_URL=http://localhost:{8083|8085}/{appName}/hs/ninja-live`.
5. Smoke: `live_version` → версия CFE (`0.1.0.0` на старте).
6. **Список расширений ИБ:** MCP `live_extensions_list` (без `url`, если env уже NINJA_*). Не Предприятие.
7. Папки `src/cfe/<Имя>`: `sync-cfe.ps1 -ProjectRoot . -ExtensionNames @("Имя1","Имя2",…)`.

### 7. Отчёт пользователю

Готово / пропущено / **ручные шаги**:

1. Reload MCP в OpenCode (источник 1С-серверов — project `opencode.jsonc`)
2. Если агент не сделал шаг 6: `cfe_load` NinjaLive → `skill-web-publish` → `live_extensions_list` → `sync-cfe -ExtensionNames`
3. Прогрев bsl-analyzer (`graph`/`metadata` status → ready)
4. toolkit `:6003` — только fallback

## Скрипты

| Скрипт | Назначение |
|--------|------------|
| `scripts/read-ibases.ps1` | таблица / `-Json` из `ibases.v8i` |
| `scripts/env-setup.ps1` | оркестратор каркаса и конфигов |
| `scripts/sync-cfe.ps1` | имена из `-ExtensionNames` (агент: `live_extensions_list`) → `src/cfe/<Имя>` + `.v8-project.json` → `extensions[]`; **не** запускает Предприятие |
| `scripts/sync-ninja-properties.ps1` | синхронизирует контролируемые свойства bootstrap-расширения с конфигурацией, которую оно расширяет |

```powershell
# Только список баз
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\kit\skills\skill-env-setup\scripts\read-ibases.ps1" -Json

# Только sync CFE (имена с live_extensions_list; без Предприятия)
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\kit\skills\skill-env-setup\scripts\sync-cfe.ps1" -ProjectRoot "." -ExtensionNames @("Имя1","Имя2")

# Check на текущем проекте
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\kit\skills\skill-env-setup\scripts\env-setup.ps1" -Mode Check -ProjectRoot "."
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
powershell.exe -NoProfile -File "...\skill-env-setup\scripts\sync-ninja-properties.ps1" -ProjectRoot "." -Check
powershell.exe -NoProfile -File "...\skill-env-setup\scripts\sync-ninja-properties.ps1" -ProjectRoot "."
```

Работает и для любого другого bootstrap-расширения: `-ExtensionName`, `-ConfigDir`, `-ExtensionDir`.

## Связанные скиллы

- `skill-project-context` — что читать после setup
- `skill-repo-workflow` — работа с CFE из хранилища (не NinjaLive)
- `1c-ninja-mcp` — live, в т.ч. **главный** список CFE: `live_extensions_list`
- `skill-bsl-analyzer` — семантика кода
- `skill-web-publish` — публикация `/hs/ninja-live`
- `db-*` — операции с ИБ (load/dump/update/расширения); `skill-syntax-check` — синтакс-контроль конфигурации

Подробности форматов: [reference.md](reference.md).

---
name: skill-bsl-analyzer
description: >-
  Семантика BSL через MCP bsl-analyzer workspace: graph (callers/callees),
  symbol_info, diagnostics file, metadata, search; модель cf+cfe+epf/erf
  (externals, ≥0.2.86). Перед правкой метода/CFE/внешних — влияние вызовов и
  точечные диагностики; не путать с ninja live_* и `skill-syntax-check`.
  Используй при анализе влияния, переименовании, ревью BSL, «кто вызывает»,
  недостижимый код / типы.
---

# bsl-analyzer (семантика кода по выгрузке)

Rust MCP **workspace** (itrous/bsl-analyzer, **≥0.2.86**): модель исходников `src/cf` + `src/cfe` + внешние EPF/ERF (`src/epf`, `src/erf`), граф вызовов, диагностики.  
Не путать с ninja `live_*` (живая ИБ) и с CLI `bsl-analyzer analyze` (тяжёлый полный прогон).

## Где лежит

| Что | Путь / имя |
|-----|------------|
| Upstream | https://github.com/itrous/bsl-analyzer |
| Releases (Windows launcher) | https://github.com/itrous/bsl-analyzer/releases → **`bsl-analyzer-windows-amd64.exe`** |
| Лаунчер (куда положить) | `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` (`--launcher-update` / `--launcher-self-update` / `--launcher-version`) |
| App | `%USERPROFILE%\.bsl-analyzer\bin\` (лаунчер качает нужную версию; не путать с ручной установкой `bsl-analyzer-app-windows-amd64.exe`) |
| Project MCP | `<репозиторий>\{{PROJECT_MCP}}` → `bsl-analyzer-workspace` и `bsl-analyzer-reference` |
| User MCP | **без** `bsl-analyzer-*` (иначе дубли с проектом) |
| Конфиг диагностик | `<репозиторий>\bsl-analyzer.toml` |
| Кеш | `<репозиторий>\.build` (`--cache-dir` в project MCP; gitignore) |

### Установка на новой машине

См. `docs/MACHINE-BOOTSTRAP.md` §2. Кратко: скачать launcher с GitHub Releases → переименовать/скопировать в `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` → при необходимости `--launcher-update`.

Прогрев: `metadata`/`graph` `action=status` → `ready` (на больших конфигурациях graph cold ~5 мин). Пока `loading` — повтори, не трактуй как «пусто».

### Кеш и повторные запуски

Кеш всегда в **проекте**: `bsl-analyzer-workspace` в project MCP запускается с `--cache-dir "<проект>\.build"` (каталог в `.gitignore`). Внутри — `workspaces\v1\<digest>\` с `bsl-search.db` и `bsl-graph.db`; сам `.build` из обхода и индексации исключён.

- Повторный запуск не пересобирает: граф публикуется с диска (обход файлов + открытие), это секунды, а не минуты.
- Правка тела метода — перепроецируется только изменённый модуль; смена сигнатуры — модуль и вызывающие; новый/удалённый `.bsl` или правка `.xml` — полная пересборка.
- Digest кеша зависит от состава источников (`root`, `extensions`, `scope`, `depends_on`, `exclude`, `exclude_globs`). Поменял список расширений в `bsl-analyzer.toml` — новый каталог и одна холодная сборка.
- Смена `--cache-dir` = новый пустой кеш (одна холодная сборка). Абсолютный путь обязателен: относительный считается от cwd процесса.
- Кеш машинно-локальный: после переноса папки проекта или на другой машине будет холодная сборка.

### Общий backend (broker) и «graph busy»

С 0.4.0 профиль workspace по умолчанию работает через общий backend (broker): клиент запускает прокси,
тот — один тяжёлый процесс на проект и каталог кеша. В project MCP поэтому запускается
`%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe` с `--mode broker`, а **не** лаунчер:
лаунчер держит потомка в Windows Job с kill-on-close и убивает backend вместе с прокси
(upstream `itrous/bsl-analyzer#345`). Без лаунчера backend переживает закрытие клиента и
переиспользуется следующими сессиями.

Симптом дефекта: `graph` → `state: failed`, ошибка
`graph busy: ... is used by another live process (pid <мёртвый>)`, при этом `initialize`/`outline`
работают. Причина — `writer.lease` в `<кеш>\workspaces\v1\<digest>` остался от убитого процесса,
а версия не забирает каталог у «живого» (на Windows проверка через именованный канал даёт
`ACCESS_DENIED`). Лечение:

1. `%LOCALAPPDATA%\bsl-analyzer\lease-clean.log` и скрипт скилла `skill-env-setup`
   `scripts\bsl-analyzer-lease-clean.ps1` — снимает аренду, если PID мёртв (задача
   `bsl-analyzer lease clean` делает это каждые 5 минут; запуск через `wscript`-лаунчер,
   окна не появляется).
2. Либо вручную: остановить процессы проекта и убрать `writer.lease` (базы `bsl-graph.db` /
   `bsl-search.db` не трогать), затем дать клиенту подключиться заново.

`BSL_MCP_IDLE_TTL_SECS` по умолчанию 300 с, `BSL_MCP_ORPHAN_GRACE_SECS` — 30 с; в project MCP
оба подняты до суток, иначе backend уходит между сессиями.

## Модель исходников и EPF/ERF

| Слой | Как попадает в анализ |
|------|------------------------|
| CF | `[source] root` (обычно `src/cf`) |
| CFE | `extensions` (часто `["src/cfe/*"]`) или auto-discovery `src/cfe/*` |
| EPF/ERF | ключ **`externals`** (массив `ExternalDecl`) или auto-discovery `src/epf/*`, `src/erf/*` |

Подтверждённый TOML (не строки-glob вроде `"src/epf/*"` — только struct):

```toml
[source]
root = "src/cf"
extensions = ["src/cfe/*"]
# omit externals → auto-discovery src/epf/*, src/erf/*
# externals = []  # явно выключить
externals = [
  { name = "МояОбработка", path = "path/to/root", depends_on = [] },
]
```

- `path` — каталог, в котором лежит **ровно один** экспорт: `<Name>.xml` рядом с `<Name>/` (как `--external NAME=PATH`).
- `depends_on` (опционально) — имена CFE из `extensions`; пустой/`[]` = только база; без поля — видит все расширения.
- CLI: `--external`, `--external-depends-on`, `--no-externals`; проверка: `bsl-analyzer check-config -c bsl-analyzer.toml`.

**Канон кита — nested:** `src/epf/<Name>/<Name>.xml` + `src/epf/<Name>/<Name>/` (аналогично `src/erf`). Скиллы `epf-init` / `erf-init` создают сразу nested. Плоская выгрузка «много `Name.xml` + `Name/` прямо в `src/epf`» **не** подходит для auto-discovery. Пока объект не в индексе — BSL EPF/ERF через ninja `read_module` / `bsl_search` + `epf-validate`, не через graph/diagnostics анализатора.

## Когда какой контур

| Задача | Куда |
|--------|------|
| Кто вызывает метод / влияние правки / rename | **bsl-analyzer** `graph` + `symbol_info` |
| Карточка символа (сигнатура, doc, usages) | `symbol_info` |
| Замечания по одному `.bsl` (в т.ч. EPF/ERF, если в индексе) | `diagnostics` `action=file` |
| Поиск / graph по внешним, если подключены | `search` / `graph` / `symbol_info` по тем же правилам, что CF/CFE |
| Обзор конфигурации / объект из XML | `metadata` (`info` / `tree` / `object`) |
| Поиск по смыслу/имени в коде | `search` `action=search_code` (без embeddings — лексика) |
| Текстовый grep по выгрузке (и EPF вне индекса) | **1c-ninja-mcp** `bsl_search` / `xml_search` / `read_module` |
| Данные / запрос / метаданные **живой** ИБ | ninja `live_*` (project URL) |
| Компиляция платформой / сборка EPF | `skill-syntax-check` / `epf-build` |
| Полный analyze всей конфигурации | CLI; **не** в обычном цикле правок |

## Поиск по проекту

Порядок и запреты — всегда-он правило `rule-mcp-first-search`. Здесь маршруты и грабли.

| Что ищем | Инструмент | Вызов |
|---|---|---|
| Имя или текст в BSL: метод, переменная, строка запроса | `search` | `action: "search_code"`, `query` |
| Структура объекта: реквизиты, табличные части, формы | `metadata` | `action: "object"`, `object_type`, `object_name` |
| Форма: элементы, реквизиты, команды | `metadata` | `action: "form"` |
| Кто вызывает, влияние правки, usages | `graph` | `resolve` → `callers` / `callees` / `neighbors` |
| Текст в XML-выгрузке: имена объектов и реквизитов, тексты ролей | **1c-ninja-mcp** | `xml_search`, `path` — корень выгрузки (`src/cf`) |
| BSL вне индекса: EPF/ERF | **1c-ninja-mcp** | `bsl_search`, `read_module` |
| Живая ИБ | **1c-ninja-mcp** | `live_query`, `live_metadata_structure`, `live_extensions_list` |

`search_code` индексирует **только BSL**. XML — `xml_search` (текст) и `metadata` (структура).
Без `EMBEDDING_URL` поиск лексический — для точных имён этого достаточно.

Грабли:

- `search_code` ищет по BSL, а не по XML: запрос по имени формы вернёт только модули, где это имя
  упоминается в коде.
- `xml_search` читает файлы выгрузки и падает на занятом файле (`IOException` — антивирус, параллельная
  сборка). Тогда — `grep` по конкретному файлу, а не по всему `src/cf`.
- `graph` `resolve` — не замена `search_code`, когда нужно просто найти, где встречается имя.
- `bsl-analyzer-reference` — про платформу. Код конфигурации им не ищется.

## Базовый workflow перед правкой метода

1. `graph` / `metadata` → `action=status` (если не ready — подожди или скажи пользователю).
2. `symbol_info` с квалифицированным именем: `Модуль.Метод` или имя объекта CFE.
3. Из ответа возьми `usages.graph_id` (или `graph` `action=resolve` → id).
4. `graph` `action=callers` (и при необходимости `callees`) по `id`.
5. `diagnostics` `action=file`, `path` = относительный или абсолютный путь к `.bsl`, `min_severity` = `warning`.
6. Правишь код → снова `diagnostics file` на затронутые модули → при необходимости `skill-syntax-check` по правилам проекта.

Пример (CFE):  
`ЦИС_СкидкиНаценкиЗаполнениеСервер.НазначитьРучнуюСкидку` → callers из форм Заказа/Реализации → diagnostics файла модуля.

## Инструменты workspace (кратко)

| Tool | action / вход | Заметки |
|------|----------------|---------|
| `graph` | `status`, `overview`, `resolve`, `callers`, `callees`, `neighbors`, `node` | `id` = durable node id; provenance `resolved` надёжнее `inferred` |
| `symbol_info` | `symbol` = `Модуль.Метод` | Для локальных переменных — `path`+`line`+`column` |
| `diagnostics` | `file` + `path`; `catalog`; `status` | Не гоняй `workspace` без нужды (дорого) |
| `metadata` | `info`, `tree`, `object`, `status` | Объекты **только из CFE** иногда не находятся как `ОбщийМодуль.X` — тогда `graph`/`symbol_info`/`resolve` |
| `search` | `search_code` | Лексика без `EMBEDDING_URL` |
| `query` / `execute` / `event_log` / `debug` | live | У нас live через **1c-ninja-mcp**; в Rust MCP onec-url не дублируем |

`references` — opt-in (`--enable-tool`); по умолчанию нет. Для «кто использует» хватает `symbol_info` usages + `graph callers`.

## Правила использования

- Предпочитай точечные вызовы (`file`, `callers` по одному id), не полный `analyze` / `diagnostics workspace`.
- Не подменяй `skill-syntax-check` диагностиками анализатора.
- Не путай project ninja (с URL ИБ) и user ninja (без URL — fail-closed).
- Имена/пути — только открытый проект; `path` для static ninja — абсолютный корень этого репозитория.
- Шумные правила глушатся в `bsl-analyzer.toml`; новые ложные срабатывания на типовой — не чинить весь cf, смотреть CFE/свои модули.

## Скиллы рядом

- `1c-ninja-mcp` — static + live ИБ  
- `1c-mcp-toolkit` — fallback live  
- `skill-project-context` — карта стека проекта
- `rule-bsl-senior-developer` (rule) — стиль кода + когда звать graph/diagnostics

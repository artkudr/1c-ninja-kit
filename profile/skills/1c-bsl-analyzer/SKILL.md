---
name: 1c-bsl-analyzer
description: >-
  Семантика BSL через MCP bsl-analyzer workspace: graph (callers/callees),
  symbol_info, diagnostics file, metadata, search; модель cf+cfe+epf/erf
  (externals, ≥0.2.77). Перед правкой метода/CFE/внешних — влияние вызовов и
  точечные диагностики; не путать с ninja live_* и vrunner syntax-check.
  Используй при анализе влияния, переименовании, ревью BSL, «кто вызывает»,
  недостижимый код / типы.
---

# bsl-analyzer (семантика кода по выгрузке)

Rust MCP **workspace** (itrous/bsl-analyzer, **≥0.2.77** / текущий 0.2.79+): модель исходников `src/cf` + `src/cfe` + внешние EPF/ERF (`src/epf`, `src/erf`), граф вызовов, диагностики.  
Не путать с ninja `live_*` (живая ИБ) и с CLI `bsl-analyzer analyze` (тяжёлый полный прогон).

## Где лежит

| Что | Путь / имя |
|-----|------------|
| Лаунчер | `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` (`--launcher-update` / `--launcher-self-update` / `--launcher-version`) |
| App | `~\.bsl-analyzer\bin\` (лаунчер качает нужную версию) |
| Project MCP | `<репозиторий>\.cursor\mcp.json` → `bsl-analyzer-workspace` и `bsl-analyzer-reference` (эталон скилла `1c-env-setup`) |
| User MCP | **без** `bsl-analyzer-*` (иначе дубли с проектом) |
| Конфиг диагностик | `<репозиторий>\bsl-analyzer.toml` |
| Кеш | `<репозиторий>\.build` (gitignore; graph/search DB; после сбоев чистить `.building.*`) |
| Namespace Cursor | `project-*-bsl-analyzer-workspace` — схемы через `GetDynamicTools` |

Прогрев: `metadata`/`graph` `action=status` → `ready` (на ecoladev graph cold ~5 мин). Пока `loading` — повтори, не трактуй как «пусто».

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

**Канон ecoladev — nested:** `src/epf/<Name>/<Name>.xml` + `src/epf/<Name>/<Name>/` (аналогично `src/erf`). Скиллы `epf-init` / `erf-init` создают сразу nested. Плоская выгрузка «много `Name.xml` + `Name/` прямо в `src/epf`» **не** подходит для auto-discovery. Пока объект не в индексе — BSL EPF/ERF через ninja `read_module` / `bsl_search` + `epf-validate`, не через graph/diagnostics анализатора.

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
| Компиляция платформой / сборка EPF | **vrunner** `validate_syntax-check` / `epf_compile` |
| Полный analyze всей конфигурации | CLI; **не** в обычном цикле правок |

## Базовый workflow перед правкой метода

1. `graph` / `metadata` → `action=status` (если не ready — подожди или скажи пользователю).
2. `symbol_info` с квалифицированным именем: `Модуль.Метод` или имя объекта CFE.
3. Из ответа возьми `usages.graph_id` (или `graph` `action=resolve` → id).
4. `graph` `action=callers` (и при необходимости `callees`) по `id`.
5. `diagnostics` `action=file`, `path` = относительный или абсолютный путь к `.bsl`, `min_severity` = `warning`.
6. Правишь код → снова `diagnostics file` на затронутые модули → при необходимости vrunner syntax-check по правилам проекта.

Пример (ecoladev CFE):  
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
- Не подменяй vrunner syntax-check диагностиками анализатора.
- Не путай project ninja (с URL ИБ) и user ninja (без URL — fail-closed).
- Имена/пути — только открытый проект; `path` для static ninja — абсолютный корень этого репозитория.
- Шумные правила глушатся в `bsl-analyzer.toml`; новые ложные срабатывания на типовой — не чинить весь cf, смотреть CFE/свои модули.

## Скиллы рядом

- `1c-ninja-mcp` — static + live ИБ  
- `1c-mcp-toolkit` — fallback live  
- `1c-project-context` — карта стека проекта  
- `bsl-senior-developer` (rule) — стиль кода + когда звать graph/diagnostics  

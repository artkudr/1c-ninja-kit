---
name: 1c-ninja-mcp
description: >-
  MCP 1c-ninja-mcp: static-поиск по выгрузке (bsl/xml, read_module, syntax_help),
  live-доступ к ИБ (live_*), список расширений ИБ — live_extensions_list (главный способ, не Предприятие),
  gated CF/EPF: cf_dump_xml, cf_load_git, extensions_dump_list, epf_decompile / epf_compile.
  Live URL — только из project .cursor/mcp.json. В user mcp.json ninja не дублировать.
  toolkit — fallback.
---

# 1c-ninja-mcp (static + live + gated)

Исходники сервера: `C:\1C\projects\1c-ninja-mcp`. Namespace Cursor: **1c-ninja-mcp**.  
Ранее: `mcp-1c-autumn` / скилл `1c-mcp-autumn`.

## Матрица владения (vrunner ↔ ninja)

| Контур | Владелец | Tools / операции |
|--------|----------|------------------|
| Load/unload CF·CFE (полный цикл), syntax-check, ИБ, repo | **vrunner** | `cf_load`, `cfe_load`, `validate_syntax_check`, `infobase_*`; repo — CLI `repo.ps1` / `repo-workflow` |
| Dump XML из ИБ / git→частичная загрузка | **1c-ninja-mcp** | `cf_dump_xml`, `cf_load_git` (gate `ibconnection`; не путать с прямым vrunner `cf_*`) |
| Static-поиск по выгрузке, offline-справка | **1c-ninja-mcp** | `bsl_search`, `xml_search`, `config_list`, `read_module`, `syntax_help_search` |
| Живые данные ИБ | **1c-ninja-mcp** | `live_*` (приоритет); toolkit — fallback |
| Разбор / сборка EPF·ERF | **1c-ninja-mcp** | `epf_decompile`, `epf_compile` (gate `ibconnection`; compile = pre-check + vrunner) |
| Список расширений ИБ (**главный способ**) | **1c-ninja-mcp** | `live_extensions_list` (HTTP `/hs/ninja-live`; CFE `NinjaLive` в ИБ). **Не** vrunner `extensions_list` / Предприятие. `extensions_dump_list` — Designer dump, не обзор состава |

**Агенту:** не вызывай напрямую `epf_decompile` / `epf_compile` / `erf` dump|build и не обходи gate через голый vrunner EPF. CF dump / git-partial load — через ninja (`cf_dump_xml`, `cf_load_git`), не сырой Designer. **ИБ обязательна** (`ibconnection` из `autumn-properties` / env / аргумент); пустая temp-ИБ запрещена.

## Scope MCP (важно)

| Уровень | Файл | Что там |
|---------|------|---------|
| Project (открытый репозиторий) | `<проект>\.cursor\mcp.json` | `1c-ninja-mcp` **с** URL/учётом этой ИБ (gitignore). Эталон — скилл `1c-env-setup`. |
| Пример без секретов | `<проект>\.cursor\mcp.json.example` | тот же состав, плейсхолдеры |
| User | `%USERPROFILE%\.cursor\mcp.json` | **без** `1c-ninja-mcp` (и без других 1С-серверов из шаблона скилла) |

Cursor читает user **и** project. Одно имя сервера в обоих файлах = два MCP у агента. **Не** копировать user `mcp.json` в проект и **не** класть live-URL эколы (или любой другой базы) в глобальный `mcp.json`.

Если `live_*` отвечает «не задан URL» — в этом workspace нет project `mcp.json` с `NINJA_URL`: возьми эталон скилла / `mcp.json.example` → `mcp.json` и заполни публикацию **этой** базы (`…/hs/ninja-live`). Либо передай явный параметр `url` на тул (не подставляй URL другого проекта «по памяти»).

## Контуры (не смешивать)

| Задача | Куда |
|--------|------|
| Поиск BSL/XML по выгрузке, модуль, offline-справка | **1c-ninja-mcp** static |
| Запросы / метаданные / журнал / код в **живой** ИБ | **1c-ninja-mcp** `live_*` (**приоритет**, URL = этот workspace) |
| То же, если NinjaLive / публикация недоступны | **1c-mcp-toolkit** (fallback; нужен EPF на `:6003`) |
| Семантика кода: граф, symbol_info, diagnostics по файлам | **bsl-analyzer** workspace — скилл `1c-bsl-analyzer` |
| Полная загрузка XML, хранилище, syntax-check | **vrunner** |
| Dump XML / git→частичная загрузка | **1c-ninja-mcp** `cf_dump_xml` / `cf_load_git` |
| Разбор / сборка EPF/ERF | **1c-ninja-mcp** `epf_decompile` / `epf_compile` |

Перед правкой метода с неочевидными вызовами — сначала `1c-bsl-analyzer` (`symbol_info` + `graph callers`), не только `bsl_search`.

## Live (реальные данные)

Требуется: веб-публикация с `publishExtensionsByDefault`, расширение `NinjaLive` в ИБ, env `NINJA_URL` (+ `NINJA_USER` / `NINJA_PASSWORD`) из **project** MCP.

| Tool | HTTP | Назначение |
|------|------|------------|
| `live_version` | GET `/version` | Smoke |
| `live_query` | POST `/query` | SELECT + опц. `limit`, `parameters` (JSON-строка) |
| `live_validate_query` | POST `/validate-query` | Синтаксис запроса |
| `live_check_syntax` | POST `/check-syntax` | Синтаксис BSL |
| `live_metadata_list` | POST `/metadata-list` | `meta_type`, опц. `name_mask` |
| `live_metadata_structure` | POST `/metadata-structure` | `meta_type` + `name` |
| `live_event_log` | POST `/event-log` | Журнал; HTTP-логин — `auth_user` |
| `live_execute` / `live_eval` | POST `/execute`, `/eval` | Код / выражение (осторожно; роль `NinjaLive_ВыполнениеКода`) |
| `live_extensions_list` | POST `/extensions-list` | **Главный способ** списка расширений ИБ; опц. `name_mask`. Не Предприятие, не MCP `extensions_list` |

**Workflow запроса:** при необходимости `live_metadata_*` → текст запроса (`composing-1c-queries`) → `live_validate_query` → `live_query`.

Если `live_version` / `live_query` недоступны и расширение `NinjaLive` в базу поставить нельзя — переключайся на скилл `1c-mcp-toolkit`.

## Static (выгрузка)

Предпочтительнее Grep с `-C` на широком поиске: ответ `путь:номер:фрагмент`.

| Tool | Назначение |
|------|------------|
| `bsl_search` | `path`, `query`, опц. `useRegex` |
| `xml_search` | `path`, `query` |
| `config_list` | `path`, `maxDepth` |
| `read_module` | `path`; `method` = пусто / `*` / имя |
| `syntax_help_search` | offline SQLite (`SHCNTX_HELP_DB`) |

Путь к выгрузке — **абсолютный** корень **открытого** проекта (`…\src\cf` и т.п.), не чужого репозитория. Схемы — `GetDynamicTools` / вызов — `CallDynamicTool`.

## Gated (все: `ibconnection`)

Общий gate: параметр / env `IBCONNECTION`|`VRUNNER_IBCONNECTION` / `autumn-properties.json` (`vrunner.ibconnection`). Без ИБ — отказ.

| Tool | Суть |
|------|------|
| `cf_dump_xml` | `out` + `mode` Full/Changes(по умолч.)/Partial/UpdateInfo; опц. `objects`, `extension`. Full без extension → `vrunner cf decompile`; иначе Designer `DumpConfigToFiles` |
| `cf_load_git` | `SRC` (git-каталог XML) → list → load. `source` All/Staged/Unstaged/Commit (+ `commit_range`); `dry_run`; опц. `extension` → Designer. CF без extension → `vrunner cf load --list` |
| `extensions_dump_list` | Designer `/DumpDBCfgList -AllExtensions`; опц. `name`. **Не** для обзора состава ИБ (канон — `live_extensions_list`) |
| `epf_decompile` | `SRC` обязателен; под капотом `vrunner epf decompile` |
| `epf_compile` | pre-check (`checks`: по умолч. `modules,handlers`; `off` — пропуск; stub+/CheckConfig) → `vrunner epf compile`. Temp-ИБ для сборки не создаётся |

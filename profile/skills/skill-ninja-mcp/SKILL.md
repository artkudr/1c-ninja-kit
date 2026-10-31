---
name: skill-ninja-mcp
description: >-
  MCP 1c-ninja-mcp: static-поиск по выгрузке (bsl/xml, read_module, syntax_help),
  live-доступ к ИБ (live_*), список расширений ИБ — live_extensions_list (главный способ, не Предприятие).
  Операции с ИБ (load/dump/update/EPF/хранилище) — скиллы контура db-*/epf-*/skill-repo-workflow.
  Live URL — только из project MCP-конфига. В user-конфиге ninja не дублировать.
  toolkit — fallback.
---

# 1c-ninja-mcp (static + live)

Исходники сервера: `C:\1C\projects\1c-ninja-kit\components\1c-ninja-mcp` (компонент кита). Namespace: **1c-ninja-mcp**.

## Матрица владения

| Контур | Владелец | Tools / операции |
|--------|----------|------------------|
| Load/unload CF·CFE, update БД, синтакс-контроль, хранилище | **скиллы контура** | `db-load-xml`, `db-dump-xml`, `db-update`, `db-repo`, `skill-repo-workflow`, `skill-syntax-check`, `db-cfe-admin` |
| Разбор / сборка EPF·ERF | **скиллы контура** | `epf-dump` / `epf-build`, `erf-dump` / `erf-build` |
| Static-поиск по выгрузке, offline-справка | **1c-ninja-mcp** | `bsl_search`, `xml_search`, `config_list`, `read_module`, `syntax_help_search` |
| Живые данные ИБ | **1c-ninja-mcp** | `live_*` (приоритет); toolkit — fallback |
| Список расширений ИБ (**главный способ**) | **1c-ninja-mcp** | `live_extensions_list` (HTTP `/hs/ninja-live`; CFE `NinjaLive` в ИБ). **Не** Предприятие |

**Агенту:** операции с ИБ — только скиллы контура (`db-*`, `skill-repo-workflow`); ninja — live-данные и static-поиск. EPF/ERF — `epf-dump`/`epf-build` (ИБ обязательна для dump).

## Scope MCP (важно)

| Уровень | Файл | Что там |
|---------|------|---------|
| Project (открытый репозиторий) | `<проект>\{{PROJECT_MCP}}` | `1c-ninja-mcp` **с** URL/учётом этой ИБ (gitignore). Эталон — скилл `skill-env-setup`. |
| Пример без секретов | `<проект>\{{PROJECT_MCP}}.example` | тот же состав, плейсхолдеры |
| User | `{{USER_MCP}}` | **без** `1c-ninja-mcp` (и без других 1С-серверов из шаблона скилла) |

Клиент читает user **и** project. Одно имя сервера в обоих файлах = два MCP у агента. **Не** копировать user-конфиг в проект и **не** класть live-URL проекта (или любой другой базы) в глобальный конфиг.

Если `live_*` отвечает «не задан URL» — в этом workspace нет project `opencode.jsonc` с `NINJA_URL`: создай его по шаблону скилла `skill-env-setup` и заполни публикацию **этой** базы (`…/hs/ninja-live`). Либо передай явный параметр `url` на тул (не подставляй URL другого проекта «по памяти»).

## Контуры (не смешивать)

| Задача | Куда |
|--------|------|
| Поиск BSL/XML по выгрузке, модуль, offline-справка | **1c-ninja-mcp** static |
| Запросы / метаданные / журнал / код в **живой** ИБ | **1c-ninja-mcp** `live_*` (**приоритет**, URL = этот workspace) |
| То же, если NinjaLive / публикация недоступны | **1c-mcp-toolkit** (fallback; нужен EPF на `:6003`) |
| Семантика кода: граф, symbol_info, diagnostics по файлам | **bsl-analyzer** workspace — скилл `skill-bsl-analyzer` |
| Полная загрузка XML, хранилище, синтакс-контроль | **скиллы контура** (`db-*`, `skill-repo-workflow`, `skill-syntax-check`) |
| Dump XML / git→частичная загрузка | **скиллы** `db-dump-xml` / `db-load-git` |
| Разбор / сборка EPF/ERF | **скиллы** `epf-dump`/`epf-build`, `erf-dump`/`erf-build` |

Перед правкой метода с неочевидными вызовами — сначала `skill-bsl-analyzer` (`symbol_info` + `graph callers`), не только `bsl_search`.

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
| `live_extensions_list` | POST `/extensions-list` | **Главный способ** списка расширений ИБ; опц. `name_mask`. Не Предприятие |

**Workflow запроса:** при необходимости `live_metadata_*` → текст запроса (`skill-query-composition`) → `live_validate_query` → `live_query`.

Если `live_version` / `live_query` недоступны и расширение `NinjaLive` в базу поставить нельзя — переключайся на скилл `skill-mcp-toolkit`.

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


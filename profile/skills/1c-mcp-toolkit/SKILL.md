---
name: 1c-mcp-toolkit
description: >-
  Fallback-доступ к живой базе 1С через MCP 1c-mcp-toolkit (EPF на :6003).
  Для реальных данных сначала 1c-ninja-mcp live_*; toolkit — если NinjaLive /
  веб-публикацию поднять нельзя или live_* недоступен.
---

# 1c-mcp-toolkit (живая ИБ, fallback)

MCP-сервер **1c-mcp-toolkit** — доступ к **работающей** информационной базе 1С через обработку `MCP_Toolkit.epf`.  
Не путать с **vrunner** (загрузка XML, хранилище) и с **1c-ninja-mcp** live (HTTP NinjaLive).

## Приоритет live-доступа

1. **Сначала** `1c-ninja-mcp` → `live_query` / `live_metadata_*` / `live_event_log` / `live_extensions_list` / …  
   (публикация `…/hs/ninja-live`, расширение `NinjaLive` в ИБ, env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD`). Часто уже настроено; не зависит от открытого Предприятия с EPF.
2. **1c-mcp-toolkit** — если расширение `NinjaLive` нельзя подключить/опубликовать, Apache/live падает, или нужны тулы только toolkit (`get_object_by_link`, screenshot и т.п.).

## Где лежит

| Что | Путь |
|-----|------|
| Обработка | `C:\1C\soft\MCP_Toolkit.epf` |
| MCP в Cursor | project `.cursor/mcp.json` → `http://127.0.0.1:6003/mcp` (эталон скилла `1c-env-setup`; не дублировать в user mcp.json) |
| Namespace MCP | `1c-mcp-toolkit` (имена tools — через `GetDynamicTools`) |
| Upstream | https://github.com/ROCTUP/1c-mcp-toolkit/releases |

## Запуск (встроенный сервер, без Python)

1. Открыть **Предприятие** на ИБ текущего проекта (`autumn-properties.json` → `default`).
2. Файл → Открыть → `C:\1C\soft\MCP_Toolkit.epf`.
3. Режим **«Встроенный сервер»** → **«Запустить сервер»** (порт **6003**).
4. Перезагрузить MCP в Cursor, если сервер только что подняли.

> Без запущенной обработки MCP недоступен — это нормально. Для запросов к ИБ предпочитай **1c-ninja-mcp** `live_*`. Для dev без живой базы — **vrunner** и skills `meta-*`.

## Когда использовать

| Задача | Инструмент |
|--------|------------|
| Структура метаданных из **XML** | `meta-info`, `cfe-diff` |
| Данные / запрос / метаданные ИБ (обычный путь) | **1c-ninja-mcp** `live_*` |
| Список расширений ИБ | **1c-ninja-mcp** `live_extensions_list` (**главный способ**; не Предприятие и не toolkit) |
| То же при недоступном BSL Analyzer | `execute_query`, `get_metadata`, `get_event_log` |
| Объект по навигационной ссылке | `get_object_by_link` / `get_link_of_object` |
| Справка по BSL (сеанс toolkit открыт) | `get_bsl_syntax_help` |
| Offline-справка / поиск по выгрузке | **1c-ninja-mcp** static |
| Граф / symbol_info / diagnostics файла | **bsl-analyzer** → скилл `1c-bsl-analyzer` |
| Загрузка CFE / update БД / syntax-check | **vrunner**, не toolkit |

**Workflow для запросов (toolkit):** `get_metadata` → составить запрос (`composing-1c-queries`) → `execute_query`.

## MCP-инструменты

| Tool | Назначение |
|------|------------|
| `execute_query` | Язык запросов 1С |
| `get_metadata` | Метаданные конфигурации в ИБ |
| `execute_code` | Произвольный код — **осторожно**, только с подтверждением |
| `get_event_log` | Журнал регистрации |
| `get_object_by_link` | Объект по ссылке |
| `get_link_of_object` | Ссылка на объект |
| `find_references_to_object` | Поиск ссылок |
| `get_access_rights` | Права |
| `get_bsl_syntax_help` | Справка BSL |
| `close_1c_session` | Закрыть сеанс (перед `infobase update` / конфигуратором) |
| `restart_1c_session` | Перезапуск после обновления конфигурации |

Имена и схемы — через `GetDynamicTools` / `CallDynamicTool` namespace `1c-mcp-toolkit`.

## Конфликты с vrunner

- Сеанс с **MCP_Toolkit.epf** держит базу открытой. Перед `repo-workflow` load, `infobase update`, конфигуратором — **закрыть обработку** или вызвать `close_1c_session`.
- После `repo-workflow` load + update конфигурации может понадобиться `restart_1c_session`.

## Безопасность

- Не вызывай `execute_code` без явной необходимости.
- Для проверки запросов достаточно `execute_query` + `get_metadata` (или autumn `live_*`).
- Bearer-токен на форме обработки — опционально; при включении добавь `Authorization` в `mcp.json`.

## Обновление

Скачать новый `MCP_Toolkit.epf` из [releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) в `C:\1C\soft\MCP_Toolkit.epf`.

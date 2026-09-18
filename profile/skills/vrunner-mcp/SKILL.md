---
name: vrunner-mcp
description: Операции 1С через MCP-сервер vrunner (vanessa-runner 3). Загрузка/выгрузка CF/CFE, сборка EPF/ERF, синтаксический контроль, ИБ. Используй когда нужна работа с платформой 1С без Platform Tools.
---

# vrunner-mcp (vanessa-runner 3)

Проверено на **vanessa-runner 3.0.0**. Документация: [autumn-library / vanessa-runner](https://autumn-library.github.io/single-page/vanessa-runner).

## Матрица владения (vrunner ↔ ninja)

| Контур | Владелец | Tools / операции |
|--------|----------|------------------|
| Load/unload CF·CFE, compile EPF/ERF, syntax-check, ИБ, repo | **vrunner** (этот скилл) | `cf_load`, `cfe_load`, `epf_compile`, `validate_syntax_check`, `infobase_*`; repo — CLI `repo.ps1` / `repo-workflow` |
| Static + live ИБ + gated decompile | **1c-ninja-mcp** | `live_*`, `bsl_search`/…, `epf_decompile` |

**Soft-запрет:** не вызывай голый `epf_decompile` (и аналог для ERF) через MCP vrunner без `ibconnection`. Предпочти **1c-ninja-mcp** `epf_decompile` (gate ИБ встроен). Если всё же vrunner — передай `ibconnection` из `autumn-properties.json` / явный аргумент; без ИБ — стоп.

## Контекст

- Чат привязан к **одному** корню проекта. ИБ и код — только из этого корня (`autumn-properties.json` или `env.json`).
- Общие skills: `%USERPROFILE%\.cursor\skills\`. Контекст проекта: скилл `1c-project-context`.
- **Платформа (load/unload/compile/syntax-check/ИБ/repo) — только этот контур.** MCP `vrunner` из project `.cursor/mcp.json` (namespace `project-*-vrunner`). Реестр PT и PT CLI **не использовать**.
- Для запросов к данным — скилл `1c-ninja-mcp` (`live_*`), не vrunner.
- Перед разрушающей загрузкой в ИБ покажи пользователю summary изменений.
- Имена tools сверяй с актуальным списком MCP. Соглашение autumn-mcpify: путь подкоманды через `_` (`cf load` → `cf_load`).
- Долгие операции: жди `task_status` / `task_result` по `taskId`; отмена — `task_cancel`.
- Кэш сессии MCP: при смене настроек/окружения — `nocache=true` на вызове или `cache_show` / `cache_clear`.
- Опционально `ibcmd=true` на tools (через ibcmd вместо Designer). Путь к ibcmd — из платформы/`v8version`, отдельного arg нет.
- `run designer` / `run enterprise` через MCP недоступны — только Shell из корня проекта:
  - `vrunner run designer`
  - `vrunner run enterprise`

## Типовые операции (пути по умолчанию)

| Задача | Tool / команда | Аргументы |
|--------|----------------|-----------|
| Загрузить конфигурацию | `cf_load` | SRC=`./src/cf` |
| Инкрементально | `cf_load` | SRC=`./src/cf`, increment=true |
| Обновление на поддержке | `cf_vendor_update` | SRC=…; опц. `update-settings` / `force` / `no-update-db` (разрушающая/длительная) |
| Синтакс-контроль | `validate_syntax_check` | `target`=main / AllExtensions / имя расширения |
| Собрать обработки | `epf_compile` | SRC=`./src/epf/<Имя>` (или `./src/epf` для всех), out=`./build/out/epf` |
| Собрать отчёты | `epf_compile` | SRC=`./src/erf/<Имя>` (или `./src/erf`), out=`./build/out/erf` |
| Разобрать EPF/ERF | **не vrunner** → `1c-ninja-mcp` `epf_decompile` | gate: `ibconnection`; см. скилл `1c-ninja-mcp` |
| Список расширений в ИБ | **не vrunner** → `1c-ninja-mcp` `live_extensions_list` | после `cfe_load` NinjaLive. MCP `extensions_list` / CLI `vrunner infobase extensions list` — устаревший fallback (запуск Предприятия), не использовать |
| Загрузить расширение (не из repository.json) | `cfe_load` | SRC=`./src/cfe/<Имя>`, extension-name=`<Имя>` |
| CFE из repository.json | скилл `repo-workflow` (`repo.ps1`; не MCP `repo_*`) | не `cfe_load` |
| Выгрузить DT | `infobase_dump_dt` | из tools/list |
| Загрузить DT | `infobase_restore_dt` | из tools/list |
| Инициализация ИБ | `infobase_init` | из tools/list |
| Обновление ИБ | `infobase_update` | из tools/list |

Список папок исходников расширений — каталог `src/cfe` или `repository.json` (без отдельного скилла).

## Запрещено

- Вызывать PT MCP (`configuration_*`, `extensions_*`, `externalProcs_*`, `test_syntaxCheck`, `env_status`).
- Использовать реестр PT / PT CLI.
- Обходить vrunner «запасным» CLI/скриптом платформы: если MCP/vrunner упал — **стоп и сообщение пользователю**, не искать другой скилл.
- Для CFE из `repository.json` использовать `cfe_load` вместо `repo-workflow` (`repo.ps1`).
- Снимать список расширений ИБ через `extensions_list` / `vrunner infobase extensions list` / запуск Предприятия. Канон: `live_extensions_list`.
- Править XML метаданных вручную — только `meta-*` / `form-*` / …
- Голый `epf_decompile` без `ibconnection` (предпочитай ninja).

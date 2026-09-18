---
name: 1c-project-context
description: >-
  Контекст открытого 1С-проекта: autumn-properties.json, env.json, repository.json, src/.
  Используй в начале задачи по конфигурации, расширениям, хранилищу или загрузке в ИБ.
---

# Контекст 1С-проекта

Все проекты на этой машине — 1С. Общие rules и skills — в профиле Cursor.

## Что прочитать из корня открытого проекта

1. `autumn-properties.json` — приоритетно (vrunner 3). Иначе `env.json`.
2. `repository.json` — если есть: CFE из хранилища (`repo-workflow`). Нет файла — CFE через `cfe_load`.
3. `src/cf`, `src/cfe` — состав конфигурации и расширений.
4. `docs/dev-stack.md` — если есть.
5. `bsl-analyzer.toml` — если есть: семантика MCP workspace / диагностики.
6. `tools/web-test/smoke.config.json` — UI smoke после `repo-workflow` load; сценарии в `tools/web-test/scenarios/after-load/` и `manual/`.

Реестр PT не используем. Контекст — autumn / vrunner.

## Активный маршрут (короткий список)

| Задача | Куда |
|--------|------|
| Load / dump / compile EPF / syntax-check / ИБ / repo_* | **только** `vrunner-mcp` (MCP `vrunner` из project `.cursor/mcp.json`) |
| Designer / enterprise | Shell: `vrunner run …` (тот же скилл) |
| Правка XML (meta/form/skd/…) | профильные `*-edit` / `*-compile` — файлы, не платформа |
| CFE из хранилища | `repo-workflow` |
| Семантика BSL | `1c-bsl-analyzer` |
| Данные живой ИБ | `1c-ninja-mcp` `live_*` |
| Список расширений ИБ | `1c-ninja-mcp` `live_extensions_list` (**главный способ**; не `extensions_list` / Предприятие) |
| Live, если ninja недоступен | `1c-mcp-toolkit` |
| Apache / публикация / web-smoke | Профильный Apache: `%USERPROFILE%\tools\apache-83` (порт **8083**) или `apache-85` (**8085**) по `v8version`. В проекте — `web.appName` + smoke `webUrl` с **`/ru_RU/`**. Не копировать Apache в проект. |

## Жёстко

- ИБ и исходники — **только** корень открытого проекта.
- Skills: `%USERPROFILE%\.cursor\skills\`.
- Rules: канон `%USERPROFILE%\.cursor\rules\`; Cursor читает только `.cursor/rules/*.mdc` **проекта** (file symlink или копия из канона; folder junction нельзя).
- MCP: все 1С-серверы **только** в `<репозиторий>\.cursor\mcp.json` (эталон — скилл `1c-env-setup`). User `%USERPROFILE%\.cursor\mcp.json` — без `vrunner` / `1c-ninja-mcp` / `1c-mcp-toolkit` / `bsl-analyzer-*` (иначе дубли).
- Платформенные операции **без фаллбека на другой скилл/CLI**: vrunner недоступен → стоп, сообщить.
- Локальные патчи ovm: скилл `cursor-local-patches` → `%USERPROFILE%\.cursor\docs\`.

## Сборка EPF / ERF (куда класть артефакты)

| Что | Исходники | Выход (обязательно) |
|-----|-----------|---------------------|
| Внешние обработки | `src/epf/<Имя>/` (nested) | **`build/out/epf/*.epf`** |
| Внешние отчёты | `src/erf/<Имя>/` (nested) | **`build/out/erf/*.erf`** |
| Расширения (бинарник при выгрузке) | `src/cfe/` | `build/out/cfe/` |

- MCP `epf_compile`: `out=./build/out/epf` или `out=./build/out/erf` — **не** в корень `build/`.
- Не оставляй `.epf`/`.erf` в `build/` рядом с `out/`, `tmp/`, `cache.json`.

## Контуры MCP (не смешивать)

| Задача | Куда |
|--------|------|
| Граф вызовов, symbol_info, diagnostics файла | **bsl-analyzer** workspace → скилл `1c-bsl-analyzer` |
| Grep/чтение модулей выгрузки | autumn static |
| Запросы / метаданные / журнал / список CFE живой ИБ | ninja `live_*` (project); список — `live_extensions_list` |
| Fallback live | toolkit |
| Загрузка / хранилище / syntax-check | **только** vrunner |

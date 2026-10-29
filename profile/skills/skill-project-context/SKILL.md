---
name: skill-project-context
description: >-
  Контекст открытого 1С-проекта: .v8-project.json, src/. Используй в начале задачи
  по конфигурации, расширениям, хранилищу или загрузке в ИБ.
---

# Контекст 1С-проекта

Все проекты на этой машине — 1С. Общие rules и skills — в профиле OpenCode.

## Что прочитать из корня открытого проекта

1. `.v8-project.json` — реестр баз: `v8path`, запись базы (`default`), `extensions[]` (+ `repository`), `web`.
2. `src/cf`, `src/cfe` — состав конфигурации и расширений.
3. `docs/dev-stack.md` — если есть.
4. `bsl-analyzer.toml` — если есть: семантика MCP workspace / диагностики.
5. `tools/web-test/smoke.config.json` — UI smoke; сценарии в `tools/web-test/scenarios/after-load/` и `manual/`.

Реестр PT не используем.

## Активный маршрут (короткий список)

| Задача | Куда |
|--------|------|
| Load / dump / update / синтакс-контроль / сборка EPF / хранилище | скиллы контура: `db-*`, `epf-build`/`erf-build`, `skill-repo-workflow`, `skill-syntax-check` |
| Запуск Предприятия | скилл `db-run` |
| Правка XML (meta/form/skd/…) | профильные `*-edit` / `*-compile` — файлы, не платформа |
| CFE с хранилищем | `skill-repo-workflow` |
| Семантика BSL | `skill-bsl-analyzer` |
| Данные живой ИБ | `1c-ninja-mcp` `live_*` |
| Список расширений ИБ | `1c-ninja-mcp` `live_extensions_list` (**главный способ**; не Предприятие) |
| Live, если ninja недоступен | `1c-mcp-toolkit` |
| Apache / публикация / web-smoke | Профильный Apache: `%USERPROFILE%\tools\apache-83` (порт **8083**) или `apache-85` (**8085**) по платформе из `.v8-project.json` (`v8path`). Публикация — `web.appName`; smoke `webUrl` с **`/ru_RU/`**. Не копировать Apache в проект. |

## Жёстко

- ИБ и исходники — **только** корень открытого проекта.
- Skills: `{{SKILLS_ROOT}}\`. Набор cc-1c-skills — `install/cc-skills.ps1`; kit-скиллы — `kit.ps1 apply`.
- Rules: канон `{{SKILLS_ROOT}}\kit\rules\` — править SoT кита (`profile/rules/`) и запускать `kit.ps1 apply`.
- MCP: все 1С-серверы **только** в `<репозиторий>\{{PROJECT_MCP}}` (эталон — скилл `skill-env-setup`). User-конфиг `{{USER_MCP}}` — без `1c-ninja-mcp` / `1c-mcp-toolkit` / `bsl-analyzer-*` / `v8std` (иначе дубли).
- Платформенные операции **без фаллбека на другой скилл/CLI**: скиллы контура недоступны → стоп, сообщить.


## Сборка EPF / ERF (куда класть артефакты)

| Что | Исходники | Выход (обязательно) |
|-----|-----------|---------------------|
| Внешние обработки | `src/epf/<Имя>/` (nested) | **`build/out/epf/*.epf`** |
| Внешние отчёты | `src/erf/<Имя>/` (nested) | **`build/out/erf/*.erf`** |
| Расширения (бинарник при выгрузке) | `src/cfe/` | `build/out/cfe/` |

- `epf-build` / `erf-build`: выход в `build/out/epf` / `build/out/erf` — **не** в корень `build/`.
- Не оставляй `.epf`/`.erf` в `build/` рядом с `out/`, `tmp/`, `cache.json`.

## Контуры MCP (не смешивать)

| Задача | Куда |
|--------|------|
| Граф вызовов, symbol_info, diagnostics файла | **bsl-analyzer** workspace → скилл `skill-bsl-analyzer` |
| Поиск по выгрузке (static) | ninja `bsl_search` / `xml_search` / `read_module` (или Grep точечно) |
| Запросы / метаданные / журнал / список CFE живой ИБ | ninja `live_*` (project); список — `live_extensions_list` |
| Fallback live | toolkit |
| Загрузка / хранилище / синтакс-контроль | скиллы `db-*` / `skill-repo-workflow` / `skill-syntax-check` |
| Стандарты ITS/v8 | `v8std` (`https://ai.v8std.ru/mcp`) |

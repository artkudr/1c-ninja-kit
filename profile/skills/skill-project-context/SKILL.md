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
5. `tools/web-test/smoke.config.json` — UI smoke; постоянные наборы — `tests/web-test/`, черновики круга — в папке задачи (`Задачи/<номер>/Проверки/`), каталог `tools/web-test/scenarios/` — старые проектные сценарии.

Реестр PT не используем.

## Куда смотреть

Карта MCP, роли и скиллы — в контексте кита (шапка `AGENTS.md`). Здесь только то, что зависит от конкретного проекта.

| Задача | Куда |
|--------|------|
| Load / dump / update / сборка EPF / хранилище | скиллы контура: `db-*`, `epf-build`/`erf-build`, `skill-repo-workflow` |
| Запуск Предприятия | скилл `db-run` |
| Правка XML (meta/form/skd/…) | профильные `*-edit` / `*-compile` — файлы, не платформа |
| Apache / публикация | профильный Apache: `%USERPROFILE%\tools\apache-83` (порт **8083**) или `apache-85` (**8085**) по платформе из `v8path`. Публикация — `web.appName`; smoke `webUrl` с **`/ru_RU/`**. Apache в проект не копировать |

## Жёстко

- ИБ и исходники — **только** корень открытого проекта.
- Skills: kit — из репозитория кита по путям в `%USERPROFILE%\.config\opencode\opencode.jsonc` (`skills`); внешние cc-1c-skills — `%USERPROFILE%\.config\opencode\skills\`. Набор cc-1c-skills — `install/cc-skills.ps1`; пути kit — `kit.ps1 apply`.
- Rules: канон в ките — `profile/rules/` (читается по `instructions` из того же конфига); править SoT и запускать `kit.ps1 apply`.
- MCP: все 1С-серверы **только** в `<репозиторий>\opencode.jsonc` (эталон — скилл `skill-env-setup`). User-конфиг — без `1c-ninja-mcp` / `1c-mcp-toolkit` / `bsl-analyzer-*` / `v8std` (иначе дубли); там только `skills` и `instructions`.
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

Граф и диагностики — `bsl-analyzer-workspace`; статический поиск по выгрузке и живые данные — `1c-ninja-mcp`; загрузка и хранилище — скиллы контура; стандарты — `v8std`. Подробная карта — в контексте кита.

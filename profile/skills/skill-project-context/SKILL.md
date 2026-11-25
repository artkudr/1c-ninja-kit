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

## `.v8-project.json` — поля

| Поле | Что |
|------|-----|
| `v8path` | bin платформы; из него же берётся `v8version` (`docs/stack-defaults.md`) |
| `databases[]` | записи баз: `id`, `name`, `type` (`file` / `server`), `path` или `server` + `ref`, `user`, `password`, `configSrc`, `extensions[]` (+ `src`, `repository`) |
| `default` | `id` базы по умолчанию |
| `web` | публикация: `appName`, `port` (**8083** для 8.3, **8085** для 8.5), `apachePath`, `poolServices` |

Ключи `web`:

| Ключ | Что |
|------|-----|
| `web.appName` | имя публикации в Apache |
| `web.apachePath` | корень Apache, если он не профильный (`%USERPROFILE%\tools\apache-83` или `apache-85`). Указывать на копию дерева можно: скрипт привязывает `Define SRVROOT` / `ServerRoot` и пути pid/log к этой копии, рабочая установка не затрагивается |
| `web.poolServices` | пул сеансов HTTP-сервисов: `[{ "name": "NinjaLive_Сервис", "rootUrl": "ninja-live" }]`. `rootUrl` обязателен — без него платформа пул не применяет |
| `web.poolSessionMaxAge` / `web.poolSize` / `web.poolTimeout` | необязательные числа пула (по умолчанию 20 / 4 / 5) |

`web.poolServices` снимает старт сеанса на каждый вызов HTTP-сервиса (ИБ, расширения, авторизация): серия `live_*` держит один сеанс вместо N. Публикует это `skill-web-publish` — там же семантика атрибутов и замеры.

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
- Skills: kit — из репозитория кита (скрипты запускаются из `{{KIT_ROOT}}`), в проект копия едет через `kit.ps1 stage`; внешние cc-1c-skills — `{{CC_SKILLS_ROOT}}\`. Набор cc-1c-skills — `install/cc-skills.ps1`; агенты, команды и `run.ps1` — `kit.ps1 apply`.
- Rules: канон в ките — `profile/rules/`; в проект копия едет через `kit.ps1 stage` (`instructions` в проектном `opencode.jsonc`). Править SoT и повторять `stage`.
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

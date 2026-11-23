# OpenCode V2 — единственный харнесс

Kit собирается только под **OpenCode V2**. Ядро — `profile/`, целевые пути описаны здесь.
Контракт имён — `docs/NAMING.md`.

## Контракт

1. **1С MCP только в project `opencode.jsonc`**, не в глобальном профиле с секретами чужой ИБ.
2. Пара **`components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`**.
3. Stack defaults: Apache **8083 ↔ 8.3**, **8085 ↔ 8.5**; webUrl с `/ru_RU/`.
4. Один процессный мозг: always-on правила из `profile/rules/always` + on-demand `rule-*` skills.
5. Список CFE в ИБ — `live_extensions_list`, не Предприятие.
6. Секреты не в git; пароли маскировать в логах и отчётах.

## Куда что ставится

Модель раздачи: **скиллы и правила — в проект копией, агенты и команды — глобально.**

| Слой kit | OpenCode V2 |
|----------|-------------|
| Kit skills | `profile/skills/<id>/SKILL.md` → `<проект>\.opencode\skills\<id>\` (копия, `kit.ps1 stage`) |
| On-demand rules | `profile/rules/on-demand/rule-*/SKILL.md` → `<проект>\.opencode\skills\rule-*\` (копия, `kit.ps1 stage`) |
| Always-on rules | `profile/rules/always/rule-*.md` → `<проект>\.opencode\rules\always\` + `instructions` в проектном `opencode.jsonc` |
| Agents | `profile/agents/*.md` → `~/.config/opencode/agents/*.md` (копия: OpenCode берёт их только из каталога) |
| Commands | `profile/commands/*.md` → `~/.config/opencode/commands/*.md` (копия) |
| Task framework | `profile/scripts/run.ps1` → `~/.config/opencode/scripts/run.ps1` (копия) |
| MCP | `profile/skills/skill-env-setup/scripts/templates/opencode.jsonc.tpl` → project `opencode.jsonc` |
| Project context | `profile/skills/skill-env-setup/scripts/templates/AGENTS.md.tpl` → project `AGENTS.md` |
| External skills | `cc-1c-skills` → `~/.config/opencode/skills/<id>/` (не переименовываются) |

Почему так: проектный `.opencode/skills` OpenCode находит сам (id — имя каталога,
`SKILL.md` до 6 уровней), а `instructions` из проектного конфига грузятся после
`AGENTS.md`. Глобальный конфиг скиллы и правила больше не раздаёт — иначе проект
не видит своей версии набора. Агентов и команды OpenCode принимает только из
каталогов профиля либо инлайном — ссылки на файл по пути нет, поэтому они
остаются глобальными (один набор ролей на машину).

## Apply и stage

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply
powershell -NoProfile -File .\install\kit.ps1 stage -ProjectRoot C:\1C\projects\<проект>
```

`apply` держит машинный слой:

1. Копирует `profile/agents/*.md` → `~/.config/opencode/agents`, `profile/commands/*.md` → `~/.config/opencode/commands`, `profile/scripts/*` → `~/.config/opencode/scripts` байт-в-байт.
2. Убирает из глобального `opencode.jsonc` пути кита в `skills`/`instructions`, если они остались от прежней модели; остальные настройки и записи пользователя не трогает.
3. Удаляет устаревшую копию `~/.config/opencode/skills/kit` и вырезает управляемый блок из `~/.config/opencode/AGENTS.md`.
4. Проверяет, что в глобальном `opencode.json(c)` нет 1С MCP-серверов.

`stage -ProjectRoot` ставит скиллы и правила в проект:

1. Копирует `profile/skills/*` и `profile/rules/on-demand/*` в `<проект>\.opencode\skills`, always-правила — в `<проект>\.opencode\rules\always`.
2. Пишет `<проект>\.opencode\kit-stage.json` — манифест: что поставлено. При следующем `stage` удалённые из профиля скиллы убираются из проекта.
3. Добавляет в проектный `opencode.jsonc` `instructions: [".opencode/rules/always/*.md"]`, не трогая MCP и прочие ключи.

`-DryRun` показывает план без записи. `verify` без аргументов сверяет машинный слой и отсутствие путей кита в глобальном конфиге; `verify -ProjectRoot <проект>` — совпадение проектной копии с профилем файл за файлом.

## Новый проект

Новый проект создаёт скилл **`skill-env-setup`** («разверни окружение»), а не CLI.

```powershell
powershell -NoProfile -File "C:\1C\projects\1c-ninja-kit\profile\skills\skill-env-setup\scripts\env-setup.ps1" `
  -Mode Init -ProjectRoot C:\1C\projects\unf-dev `
  -AppName unf-dev -V8Version 8.3 -WebPort 8083
```

Скрипт создаёт структуру каталогов, `.v8-project.json`, `AGENTS.md`, `opencode.jsonc`
(+ `.example`), `.ignore`, `docs/dev-stack.md`, smoke-config, пустую `Задачи/`,
копирует `NinjaLive` из `SourceProject` / kit-эталона / соседнего проекта и
вызывает `kit.ps1 stage` — в проект приезжают скиллы и правила. Каркаса задачи в
проекте нет: команды `Задача`/`Продолжить`/`Статус` глобальные (`kit.ps1 apply`),
состояние задач — в сервисе PiPa.

## Каркас задачи

Один на машину: команды `~/.config/opencode/commands/{Задача,Продолжить,Статус}.md`
→ слэш-команды `/Задача`, `/Продолжить`, `/Статус`. Состояние задачи живёт в
сервисе **PiPa** (PithosPandoras) и читается через MCP `pipa`; в проекте остаётся
только папка `Задачи/` с файлами. Имя проекта для сервиса — раздел «Сервис задач»
в `AGENTS.md`. Контракт вызовов — скилл `skill-pipa`, маршруты — `rule-routes`.

## Что OpenCode умеет нативно

| Возможность | Статус | Notes |
|-------------|--------|-------|
| `SKILL.md` on-demand | **да** | каталоги из `skills` в конфиге (путь кита) + `~/.config/opencode/skills/<id>/SKILL.md`; `SKILL.md` ищется до 6 уровней, id — имя каталога; в промпт идут только `id`/`name`/`description`, тело — по вызову `skill` |
| MCP tools | **да** | встроенный MCP-клиент, code mode по умолчанию |
| `AGENTS.md` | **да** | глобальный + project + вложенные; правится на лету; `instructions` из конфига грузится после него |
| Subagents | **да** | `~/.config/opencode/agents/<id>.md` + `mode: subagent`, запуск через tool `subagent` |
| Commands | **да** | `~/.config/opencode/commands/<name>.md` или `.opencode/commands/<name>.md`, `$ARGUMENTS`, frontmatter `agent` / `description` / `subagent` |

`CLAUDE.md` OpenCode V2 не использует как fallback: инструкции — только `AGENTS.md`.

## Правила и skills

- Always-on правила — короткие, только то, что нужно в каждой сессии. Файлы `profile/rules/always/*.md` подключены через `instructions`; в `AGENTS.md` их больше нет.
- On-demand правила — нативные skills `rule-*`. OpenCode показывает их `id` + `description`
  и загружает тело через `skill`; другого on-demand механизма в OpenCode нет.
- Kit skills — `skill-*`; внешние `cc-1c-skills` (`db-*`, `meta-*`, `form-*`, `cfe-*`, …)
  остаются с прежними ID.
- Пути в `skills` абсолютные и ведут в репозиторий кита: правка `profile/skills/**` и
  `profile/rules/**` видна без копирования, нужен только перезапуск OpenCode.

## Агенты

Агенты — обычные OpenCode Markdown-агенты:

```yaml
---
description: ...
mode: subagent
---
```

## Ограничения

- В OpenCode нет автоматического подключения правила по glob. Path-scoped правила —
  только вложенный `AGENTS.md` в нужной папке.
- Глобальный `opencode.jsonc` не содержит скиллов и правил: `kit.ps1 apply` только убирает из него пути кита, если они остались от прежней модели. Настройки пользователя не трогаются.
- MCP Resources/Prompts как контент для агента не используются.
- `browse` (живой Chrome) выключен в глобальном конфиге (`disabled: true`): GitLab и трекеры — `glab`/API, проверка 1С — `skill-web-test`. Включать под задачу, где человек прямо просит посмотреть живую страницу.
- Глобальные 1С MCP-серверы не поддерживаются: только project `opencode.jsonc`.

## Секреты

`opencode.jsonc` проекта содержит `NINJA_USER` / `NINJA_PASSWORD` → он в `.gitignore`.
В **глобальный** `~/.config/opencode/opencode.json(c)` 1С MCP не пишется никогда.

## Проверка

`docs/TEST-GUIDE-opencode.md` (doctor → apply → `skill-env-setup` → smoke MCP → live).

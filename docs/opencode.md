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

Модель раздачи: **скиллы и правила — путями в конфиге, остальное — копией.**

| Слой kit | OpenCode V2 |
|----------|-------------|
| Kit skills | `profile/skills/<id>/SKILL.md` → путь `profile/skills` в `skills` глобального `~/.config/opencode/opencode.jsonc` |
| On-demand rules | `profile/rules/on-demand/rule-*/SKILL.md` → путь `profile/rules` в том же `skills` |
| Always-on rules | `profile/rules/always/rule-*.md` → `instructions` (`<кит>/profile/rules/always/*.md`) |
| Agents | `profile/agents/*.md` → `~/.config/opencode/agents/*.md` (копия: OpenCode берёт их только из каталога) |
| Commands | `profile/commands/*.md` → `~/.config/opencode/commands/*.md` (копия) |
| Task framework | `profile/scripts/taskctl.ps1` → `~/.config/opencode/scripts/taskctl.ps1` (копия) |
| MCP | `profile/skills/skill-env-setup/scripts/templates/opencode.jsonc.tpl` → project `opencode.jsonc` |
| Project context | `profile/skills/skill-env-setup/scripts/templates/AGENTS.md.tpl` → project `AGENTS.md` |
| External skills | `cc-1c-skills` → `~/.config/opencode/skills/<id>/` (не переименовываются) |

Почему так: `skills` в OpenCode V2 — массив путей, `SKILL.md` ищется до 6 уровней, id — имя каталога; `instructions` — массив глобов, грузится после `AGENTS.md`. Агентов и команды OpenCode принимает только из каталогов профиля либо инлайном — ссылки на файл по пути нет. Симлинки в git на Windows не годятся (`core.symlinks=false`, Dev Mode выключен: клон получает текстовый файл с путём), junction не версионируется — поэтому именно пути, а не ссылки в репозитории.

## Apply

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply
```

Что делает:

1. Пишет/мержит глобальный `~/.config/opencode/opencode.jsonc`: `$schema`, `skills` = `<кит>/profile/skills` + `<кит>/profile/rules`, `instructions` = `<кит>/profile/rules/always/*.md`. Остальные ключи файла сохраняются, старый файл копируется рядом в `.bak-<метка>`, запись идёт через временный файл с проверкой разбора JSONC.
2. Копирует `profile/agents/*.md` → `~/.config/opencode/agents`, `profile/commands/*.md` → `~/.config/opencode/commands`, `profile/scripts/*` → `~/.config/opencode/scripts` байт-в-байт (`taskctl.ps1` — UTF-8 с BOM, иначе PowerShell 5.1 читает кириллицу как ANSI).
3. Удаляет устаревшую копию `~/.config/opencode/skills/kit` (только её) и вырезает управляемый блок из `~/.config/opencode/AGENTS.md` между маркерами `1c-ninja-kit` — правила теперь идут через `instructions`.
4. Проверяет, что в глобальном `opencode.json(c)` нет 1С MCP-серверов.

`-DryRun` показывает план без записи. Правка `profile/rules/always/*.md` видна сразу после перезапуска OpenCode — копии нет. Изменения в `profile/` после правки подтверждает `kit.ps1 verify` (пути, отсутствие старой копии, совпадение агентов/команд/скрипта с профилем).

## Новый проект

Новый проект создаёт скилл **`skill-env-setup`** («разверни окружение»), а не CLI.

```powershell
powershell -NoProfile -File "C:\1C\projects\1c-ninja-kit\profile\skills\skill-env-setup\scripts\env-setup.ps1" `
  -Mode Init -ProjectRoot C:\1C\projects\unf-dev `
  -AppName unf-dev -V8Version 8.3 -WebPort 8083
```

Скрипт создаёт структуру каталогов, `.v8-project.json`, `AGENTS.md`, `opencode.jsonc`
(+ `.example`), `.ignore`, `docs/dev-stack.md`, smoke-config, пустую `Задачи/`
и копирует `NinjaLive` из `SourceProject` / kit-эталона / соседнего проекта.
Каркаса задачи в проекте нет: `taskctl.ps1` и команды `Задача`/`Продолжить`/`Статус`
глобальные (`kit.ps1 apply`).

## Каркас задачи

Один на машину: `~/.config/opencode/scripts/taskctl.ps1` + `~/.config/opencode/commands/{Задача,Продолжить,Статус}.md` → слэш-команды `/Задача`, `/Продолжить`, `/Статус`. Корень проекта скрипт ищет вверх по текущему каталогу (признак — `Задачи\` или `.v8-project.json`), `--project <путь>` задаёт его явно. Старая раскладка `.opencode\scripts\taskctl.ps1` внутри проекта тоже работает, но дублирует глобальную и подлежит удалению.

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
- Глобальный `opencode.jsonc` правится `kit.ps1 apply` только в двух ключах (`skills`, `instructions`); остальные настройки пользователь держит сам.
- MCP Resources/Prompts как контент для агента не используются.
- Глобальные 1С MCP-серверы не поддерживаются: только project `opencode.jsonc`.

## Секреты

`opencode.jsonc` проекта содержит `NINJA_USER` / `NINJA_PASSWORD` → он в `.gitignore`.
В **глобальный** `~/.config/opencode/opencode.json(c)` 1С MCP не пишется никогда.

## Проверка

`docs/TEST-GUIDE-opencode.md` (doctor → apply → `skill-env-setup` → smoke MCP → live).

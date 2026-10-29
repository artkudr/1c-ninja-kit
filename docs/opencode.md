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

| Слой kit | OpenCode V2 |
|----------|-------------|
| Kit skills | `profile/skills/<id>/SKILL.md` → `~/.config/opencode/skills/kit/skills/<id>/SKILL.md` |
| Always-on rules | `profile/rules/always/rule-*.md` → managed-блок `~/.config/opencode/AGENTS.md` |
| On-demand rules | `profile/rules/on-demand/rule-*/SKILL.md` → `~/.config/opencode/skills/kit/rules/rule-*/SKILL.md` |
| Agents | `profile/agents/agent-*.md` → `~/.config/opencode/agents/agent-*.md` (`mode: subagent`) |
| MCP | `profile/skills/skill-env-setup/scripts/templates/opencode.jsonc.tpl` → project `opencode.jsonc` |
| Commands | `profile/skills/skill-env-setup/scripts/templates/commands` → project `.opencode/commands` |
| Project context | `profile/skills/skill-env-setup/scripts/templates/AGENTS.md.tpl` → project `AGENTS.md` |
| External skills | `cc-1c-skills` → `~/.config/opencode/skills/<id>/` (не переименовываются) |

## Apply

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply
```

Что делает:

1. Собирает `AGENTS.md` из статического блока и `profile/rules/always/*.md`.
2. Stage + mirror `profile/skills` → `~/.config/opencode/skills/kit/skills`.
3. Stage + mirror `profile/rules/on-demand` → `~/.config/opencode/skills/kit/rules`.
4. Копирует `profile/agents/agent-*.md` → `~/.config/opencode/agents`.
5. Разрешает `{{SKILLS_ROOT}}` / `{{AGENTS_ROOT}}` / `{{COMMANDS_ROOT}}` в kit skills.
6. Проверяет, что в глобальном `opencode.json(c)` нет 1С MCP-серверов.

`-DryRun` показывает план без записи. Mirror затрагивает только `skills/kit`; внешние
`cc-1c-skills` в `skills/<id>/` остаются как есть.

## Новый проект

Новый проект создаёт скилл **`skill-env-setup`** («разверни окружение»), а не CLI.

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.config\opencode\skills\kit\skills\skill-env-setup\scripts\env-setup.ps1" `
  -Mode Init -ProjectRoot C:\1C\projects\unf-dev `
  -AppName unf-dev -V8Version 8.3 -WebPort 8083
```

Скрипт создаёт структуру каталогов, `.v8-project.json`, `AGENTS.md`, `opencode.jsonc`
(+ `.example`), `.opencode/commands`, OpenSpec, `.ignore`, `docs/dev-stack.md`, smoke-config
и копирует `NinjaLive` из `SourceProject` / kit-эталона / соседнего проекта.

## Что OpenCode умеет нативно

| Возможность | Статус | Notes |
|-------------|--------|-------|
| `SKILL.md` on-demand | **да** | `~/.config/opencode/skills/<id>/SKILL.md`; в промпт идут только `id`/`name`/`description`, тело — по вызову `skill` |
| MCP tools | **да** | встроенный MCP-клиент, code mode по умолчанию |
| `AGENTS.md` | **да** | глобальный + project + вложенные; правится на лету |
| Subagents | **да** | `~/.config/opencode/agents/<id>.md` + `mode: subagent`, запуск через tool `subagent` |
| Commands | **да** | `.opencode/commands/<name>.md`, `$ARGUMENTS`, frontmatter `agent` / `description` / `subagent` |

`CLAUDE.md` OpenCode V2 не использует как fallback: инструкции — только `AGENTS.md`.

## Правила и skills

- Always-on правила — короткие, только то, что нужно в каждой сессии. Они лежат в `AGENTS.md`.
- On-demand правила — нативные skills `rule-*`. OpenCode показывает их `id` + `description`
  и загружает тело через `skill`; другого on-demand механизма в OpenCode нет.
- Kit skills — `skill-*`; внешние `cc-1c-skills` (`db-*`, `meta-*`, `form-*`, `cfe-*`, …)
  остаются с прежними ID.

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
- `instructions` в конфиге загружает файлы always-on, а не on-demand; для правил он не используется.
- MCP Resources/Prompts как контент для агента не используются.
- Глобальные 1С MCP-серверы не поддерживаются: только project `opencode.jsonc`.

## Секреты

`opencode.jsonc` проекта содержит `NINJA_USER` / `NINJA_PASSWORD` → он в `.gitignore`.
В **глобальный** `~/.config/opencode/opencode.json(c)` 1С MCP не пишется никогда.

## Проверка

`docs/TEST-GUIDE-opencode.md` (doctor → apply → `skill-env-setup` → smoke MCP → live).

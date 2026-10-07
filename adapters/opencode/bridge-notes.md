# OpenCode — bridge notes

## Нативно (v0.4, без эмуляции)

| Возможность | Статус | Notes |
|-------------|--------|-------|
| `SKILL.md` on-demand | **да** | `~/.config/opencode/skills/<id>/SKILL.md`; в промпт идёт только `id`/`name`/`description`, тело — по вызову `skill` |
| MCP tools | **да** | встроенный MCP-клиент, code mode по умолчанию |
| `AGENTS.md` | **да** | глобальный + project, вверх по дереву; правится на лету |
| Subagents | **да** | `~/.config/opencode/agents/<id>.md` + `mode: subagent`, запуск через tool `subagent` |
| Commands | **да** | `.opencode/commands/<name>.md`, `$ARGUMENTS`, frontmatter `agent` / `description` / `subagent` |

## Эмуляция Cursor-частей

| Cursor | Как в OpenCode |
|--------|----------------|
| `rules/*.mdc` `alwaysApply: true` | инлайн в managed-блок `~/.config/opencode/AGENTS.md` (`1c-orchestrator`, `1c-development-process`, `bsl-analyzer`, `1c-ninja-mcp`) |
| `rules/*.mdc` globs / on-demand | копии в `~/.config/opencode/kit-rules/<name>.md` + таблица-индекс в `AGENTS.md` («читай файл, когда задача в его теме») |
| `agents/*.md` frontmatter `tools` / `allowParallel` / `model: inherit` | отбрасываются при конвертации; остаётся `description` + `mode: subagent` (наследование модели — дефолт OpenCode) |
| `.cursor/rules` hardlink в проекте | не нужен: глобальный `AGENTS.md` + `kit-rules/` покрывают тот же сценарий |

## Конвертация агентов (почему она нужна)

Cursor-фронтматтер профиля выглядит так:

```yaml
name: 1c-architect
description: Expert 1C solution architect agent. …
model: inherit
tools: ["Read", "Write", "Edit", "Grep", "Glob", "Shell", "MCP"]
allowParallel: true
```

V2 не понимает `tools` / `allowParallel` / `model: inherit` — это V1-поля. `apply -Adapter opencode`
пересобирает фронтматтер в

```yaml
description: Expert 1C solution architect agent. …
mode: subagent
```

Заодно вычищается **мусор профиля**: в теле агентов блок `## Ecoladev stack (mandatory)`
вставлен многократно (результат неудачной расклейки при capture). Простое сравнение H2-секций
не помогает — вставка «съедает» абзац после себя, и копии перестают быть побайтово равны.
Конвертер поэтому ищет **повторяющиеся блоки, начинающиеся с заголовка** (нормализованные
строки, окно 6…80 строк) и удаляет все копии, кроме первой. SoT не меняется — чистится
только выдача адаптера. Эффект: `1c-architect.md` 630 → 224 строки.

## Чего нет / не обещаем

- Импорт `.mdc` с globs — эмуляция таблицей, а не поведением.
- `kit.ps1 capture` **не** поддерживает `-Adapter opencode`: конвертация lossy, capture из
  `~/.config/opencode/agents` записал бы обратно вычищенный текст в SoT. SoT-авторство остаётся за cursor.
- MCP Resources/Prompts как контент для агента не используются.

## Секреты

`opencode.jsonc` проекта содержит `NINJA_USER` / `NINJA_PASSWORD` → он в `.gitignore`,
в git идёт `opencode.jsonc.example` с `<user>` / `<password>`.
В **глобальный** `~/.config/opencode/opencode.json(c)` 1С MCP не пишется никогда (hard rule kit).

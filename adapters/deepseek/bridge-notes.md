# DeepSeek / DSH — bridge notes

## Что работает из коробки

- Копирование `profile/skills/*/SKILL.md` → `~/.agents/skills/<name>/`
- Имена skills уже kebab-case (`1c-env-setup`, …)
- MCP tools через DSH mcp-client → `mcp__1c-ninja-mcp__live_extensions_list` и т.п.

## Эмуляция Cursor rules

Always-on (`1c-orchestrator`, `1c-development-process`, `bsl-analyzer`, `1c-ninja-mcp`) вшиты в шаблон `AGENTS.md` (см. `adapters/shared/AGENTS.md.tpl`).  
On-demand methodology rules агент читает как skills / по ссылке из AGENTS.

## Чего нет в v0.3

- Нативный импорт `.mdc` globs
- Cursor `agents/*.md` frontmatter как DSH agent presets
- MCP Resources/Prompts (DSH — tools only)

## Laptop bare-metal

Сначала `docs/MACHINE-BOOTSTRAP.md` (OVM, vrunner, bsl-analyzer, Apache), затем apply + init-project.

# Cursor adapter

## Куда ставить

| Артефакт kit | Цель |
|--------------|------|
| `profile/skills/` | `%USERPROFILE%\.cursor\skills\` |
| `profile/rules/` | `%USERPROFILE%\.cursor\rules\` |
| `profile/agents/` | `%USERPROFILE%\.cursor\agents\` |
| `profile/docs-patches/` | `%USERPROFILE%\.cursor\docs\` |

Профиль: **`1c-ninja-kit`**.

## Project

| Артефакт | Цель |
|----------|------|
| templates mcp | `<project>\.cursor\mcp.json` (gitignore) + `.example` |
| NinjaLive | `<project>\src\cfe\NinjaLive\` |
| rules | `<project>\.cursor\rules\*.mdc` hardlink/symlink на канон профиля |

`AUTUMN_MAIN` = абсолютный путь к  
`{1c-ninja-kit}\components\1c-ninja-mcp\main.os`.

## Запреты

- Directory junction на `.cursor/rules`
- 1С MCP в user `mcp.json`
- Второй always-on оркестратор / полный upstream `AGENTS.md` рядом с ecoladev-форком

См. также: `install-profile.md`, `mcp-project.md`, `rules-hardlink.md`.

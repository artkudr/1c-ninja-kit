# Hermes — bridge notes

## Mapping

| Kit | Hermes |
|-----|--------|
| `profile/skills` | `~/.hermes/skills/<name>/SKILL.md` |
| always-on rules | project `.hermes.md` (from shared AGENTS tpl) |
| MCP | `mcp_servers` in `~/.hermes/config.yaml` |
| identity tip | `SOUL.1c-ninja-kit.md` fragment |

## MCP fragment

См. `mcp_servers.fragment.yaml`. Вставь под ключ `mcp_servers:` в config.yaml.  
Секреты — через env / локальный override, не коммить.

Hermes может фильтровать tools: `tools.include` / `exclude`. Для smoke достаточно defaults.

## Cursor rules

Hermes может подхватить `.cursorrules` в цепочке приоритета, но канон kit для Hermes — **`.hermes.md`**. Directory junction на `.cursor/rules` не используем.

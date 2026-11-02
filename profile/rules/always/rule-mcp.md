# MCP routes

| Нужно | Инструмент |
|--------|------------|
| Семантика / graph / diagnostics | `bsl-analyzer-workspace` |
| Live ИБ / static выгрузка | `1c-ninja-mcp` `live_*` |
| Load / dump / update / проверки / repo | скиллы `db-*`, `skill-repo-workflow` |
| Стандарты ITS/v8 | `v8std`; reference `bsl-analyzer-reference` |
| Live fallback | `1c-mcp-toolkit` (выключен по умолчанию) |

В OpenCode имена MCP-инструментов нормализованы: `1c-ninja-mcp` + `live_query` → `mcp_1c_ninja_mcp_live_query`.

Скиллы в таблице берутся по правам роли: если нужный закрыт, шаг выполняет ведущий агент или человек.

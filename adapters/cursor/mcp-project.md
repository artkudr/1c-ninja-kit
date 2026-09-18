# Project MCP (Cursor)

1. Скопировать `project-scaffold/templates/mcp.json.example.tpl` →  
   `<project>\.cursor\mcp.json.example` и заполненный `.cursor\mcp.json` (gitignore).
2. Подставить:
   - `{{AUTUMN_MAIN}}` → `C:\1C\projects\1c-ninja-kit\components\1c-ninja-mcp\main.os`
   - `{{SHCNTX_HELP_DB}}` → `...\components\1c-ninja-mcp\src\data\shcntx_help.db`
   - `{{WEB_PORT}}` → 8083 (платформа 8.3) или 8085 (8.5)
   - `{{APP_NAME}}`, `{{BSL_USER}}`, `{{BSL_PASSWORD}}`, `{{PROJECT_ROOT}}`, пути vrunner/bsl-analyzer
3. Optional pack `extras-mcp`: добавить `v8std`, `1c-code-check-mcp` как в ecoladev example.
4. User `%USERPROFILE%\.cursor\mcp.json` — без этих серверов.

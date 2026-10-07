{
  "$schema": "https://opencode.ai/config.json",

  // 1c-ninja-kit: project MCP. Файл содержит пароль ИБ -> в .gitignore.
  // Коммитится opencode.jsonc.example (то же самое с <user> / <password>).
  // В глобальный ~/.config/opencode/opencode.json(c) 1С MCP НЕ пишется никогда.
  "mcp": {
    "timeout": {
      "startup": 120000
    },
    "servers": {
      "vrunner": {
        "type": "local",
        "command": ["{{VRUNNER_MCP}}"]
      },

      "1c-ninja-mcp": {
        "type": "local",
        "command": ["oscript", "{{NINJA_MAIN}}"],
        "environment": {
          "SHCNTX_HELP_DB": "{{SHCNTX_HELP_DB}}",
          "NINJA_URL": "http://localhost:{{WEB_PORT}}/{{APP_NAME}}/hs/ninja-live",
          "NINJA_USER": "{{IB_USER}}",
          "NINJA_PASSWORD": "{{IB_PASSWORD}}",
          "AUTUMN_PROPERTIES": "{{AUTUMN_PROPERTIES}}"
        }
      },

      "bsl-analyzer-reference": {
        "type": "local",
        "command": ["{{BSL_ANALYZER_EXE}}", "mcp", "serve", "--profile", "reference"]
      },

      "bsl-analyzer-workspace": {
        "type": "local",
        "command": ["{{BSL_ANALYZER_EXE}}", "mcp", "serve", "--profile", "workspace", "--source-dir", "{{PROJECT_ROOT}}"]
      },

      // Стандарты ITS/v8. streamable-http без OAuth -> oauth: false обязателен.
      "v8std": {
        "type": "remote",
        "url": "https://ai.v8std.ru/mcp",
        "oauth": false
      },

      // Fallback live. Выключен по умолчанию: EPF не всегда запущена
      // (kit.ps1 doctor -> WARN). Включи disabled:false, когда MCP_Toolkit.epf поднята.
      "1c-mcp-toolkit": {
        "type": "remote",
        "url": "http://127.0.0.1:6003/mcp",
        "oauth": false,
        "disabled": true
      }
    }
  }
}

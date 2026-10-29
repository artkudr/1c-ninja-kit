{
  "$schema": "https://opencode.ai/config.json",

  // skill-env-setup: project MCP (OpenCode V2). Содержит пароль ИБ -> в .gitignore.
  // В глобальный ~/.config/opencode/opencode.json(c) 1С MCP НЕ пишется никогда.
  "mcp": {
    "timeout": {
      "startup": 120000
    },
    "servers": {
      "1c-ninja-mcp": {
        "type": "local",
        "command": ["oscript", "{{NINJA_MAIN}}"],
        "environment": {
          "SHCNTX_HELP_DB": "{{SHCNTX_HELP_DB}}",
          "NINJA_URL": "http://localhost:{{WEB_PORT}}/{{APP_NAME}}/hs/ninja-live",
          "NINJA_USER": "{{IB_USER}}",
          "NINJA_PASSWORD": "{{IB_PASSWORD}}"
        }
      },

      "bsl-analyzer-reference": {
        "type": "local",
        "command": ["{{BSL_ANALYZER_EXE}}", "mcp", "serve", "--profile", "reference"]
      },

      "bsl-analyzer-workspace": {
        "type": "local",
        // Общий backend (broker) без ручного запуска. Запускаем bsl-analyzer-app.exe, а не лаунчер:
        // лаунчер держит потомка в Windows Job с kill-on-close и убивает backend вместе с прокси
        // (upstream itrous/bsl-analyzer#345), после чего остаётся мёртвый writer.lease и граф
        // отвечает "graph busy". Без лаунчера backend переживает закрытие клиента.
        // TTL — сутки простоя вместо штатных 300 с; мёртвые аренды снимает задача
        // "bsl-analyzer lease clean" (см. скилл skill-env-setup, scripts/bsl-analyzer-lease-clean.ps1).
        "environment": {
          "BSL_MCP_IDLE_TTL_SECS": "86400",
          "BSL_MCP_ORPHAN_GRACE_SECS": "86400"
        },
        "command": ["{{BSL_ANALYZER_APP_EXE}}", "mcp", "serve", "--profile", "workspace", "--mode", "broker", "--source-dir", "{{PROJECT_ROOT}}", "--cache-dir", "{{PROJECT_ROOT}}\\.build"]
      },

      // Стандарты ITS/v8. streamable-http без OAuth -> oauth: false обязателен.
      "v8std": {
        "type": "remote",
        "url": "https://ai.v8std.ru/mcp",
        "oauth": false
      },

      // Fallback live. Выключен по умолчанию: EPF не всегда запущена.
      // Включи disabled:false, когда MCP_Toolkit.epf поднята на :6003.
      "1c-mcp-toolkit": {
        "type": "remote",
        "url": "http://127.0.0.1:6003/mcp",
        "oauth": false,
        "disabled": true
      }
    }
  }
}

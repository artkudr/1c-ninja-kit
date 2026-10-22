# 1c-ninja-mcp

MCP-сервер для 1С на [autumn-mcp](https://github.com/autumn-library/autumn-mcp):
**static** (поиск по выгрузке), **live** (HTTP расширения `NinjaLive` / `/hs/ninja-live`).

Логика static — производная [lekot/mcp-1c](https://github.com/lekot/mcp-1c) (GPL-3.0);
каркас — autumn-mcp (GPL-3.0).

## Подключение

В project `opencode.jsonc` (не в user-конфиг). Образец — шаблон скилла `1c-env-setup`:

```json
"1c-ninja-mcp": {
  "type": "local",
  "command": ["oscript", "C:\\1C\\projects\\1c-ninja-kit\\components\\1c-ninja-mcp\\main.os"],
  "environment": {
    "SHCNTX_HELP_DB": "C:\\1C\\projects\\1c-ninja-kit\\components\\1c-ninja-mcp\\src\\data\\shcntx_help.db",
    "NINJA_URL": "http://localhost:8083/<app>/hs/ninja-live",
    "NINJA_USER": "<пользователь_ИБ>",
    "NINJA_PASSWORD": "<пароль>"
  }
}
```

## Как пользоваться

Skill `1c-ninja-mcp` и rule `1c-ninja-mcp` — маршруты static/live, scope env, ограничения тулов.

**Список расширений ИБ (главный способ):** `live_extensions_list` (HTTP `/extensions-list`). Не запуск Предприятия.

# 1c-ninja-mcp

MCP-сервер для 1С на [autumn-mcp](https://github.com/autumn-library/autumn-mcp):
**static** (поиск по выгрузке), **live** (HTTP расширения `NinjaLive` / `/hs/ninja-live`), **gated** (EPF/CF при `ibconnection`).

Логика static — производная [lekot/mcp-1c](https://github.com/lekot/mcp-1c) (GPL-3.0);
каркас — autumn-mcp (GPL-3.0).

## Подключение

В project `.cursor/mcp.json` (не в user). Образец — [`mcp.json`](mcp.json):

```json
"1c-ninja-mcp": {
  "command": "oscript",
  "args": ["C:\\1C\\projects\\1c-ninja-mcp\\main.os"],
  "env": {
    "SHCNTX_HELP_DB": "C:\\1C\\projects\\1c-ninja-mcp\\src\\data\\shcntx_help.db",
    "NINJA_URL": "http://localhost:8081/<app>/hs/ninja-live",
    "NINJA_USER": "<пользователь_ИБ>",
    "NINJA_PASSWORD": "<пароль>"
  }
}
```

## Как пользоваться

Cursor skill `1c-ninja-mcp` и rule `1c-ninja-mcp` — маршруты static/live, scope env, ограничения тулов.

**Список расширений ИБ (главный способ):** `live_extensions_list` (HTTP `/extensions-list`). Не запуск Предприятия / не `vrunner infobase extensions list`.

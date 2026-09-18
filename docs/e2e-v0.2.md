# E2E protocol v0.2

Полная инструкция для агента: **`docs/AGENT-BRIEF-v0.2.md`** (копипаст в новый профиль).

## Карта

| Шаг | Команда | Ожидание |
|-----|---------|----------|
| doctor | `kit.ps1 doctor` | exit 0; required soft найден |
| verify | `kit.ps1 verify` | counts skills/rules/agents |
| apply | `kit.ps1 apply` | профиль в `%USERPROFILE%\.cursor` |
| init-project | `kit.ps1 init-project -ProjectPath ...` | новый проект ≠ ecoladev |
| live | NinjaLive load + `live_*` | optional если нет ИБ |

## Запреты

- init / правки **ecoladev**
- 1С MCP в user mcp.json
- junction на project rules
- пароли в логах

## Логи

Каталог: `logs/e2e-v0.2-*.md` (в `.gitignore`).

## Статусы

- `pass` — до live_extensions_list
- `partial` — профиль + scaffold, live отложен (needs-human IB)
- `fail` — нарушены запреты или doctor required

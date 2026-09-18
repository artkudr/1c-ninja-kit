# Слои 1c-ninja-kit

```text
Machine  →  Profile (~/.cursor)  →  Project  →  Adapter (Cursor / …)
                ↑
         SoT = этот репозиторий
```

| Слой | Что | Кто ставит |
|------|-----|------------|
| **Machine** | OVM, vrunner, bsl-analyzer, Apache tools, Toolkit EPF | человек + `kit doctor` (v0.2: install) |
| **Profile** | skills / rules / agents | `kit apply --profile 1c-ninja-kit` |
| **Project** | autumn, repository, mcp, NinjaLive, OpenSpec, hardlink rules | `1c-env-setup` / `kit init-project` |
| **Adapter** | как Cursor (или другой харнесс) читает skills/MCP | `adapters/<name>/` |

## Пара Ninja

| Часть | Путь в kit | Роль |
|-------|------------|------|
| MCP | `components/1c-ninja-mcp` | static + `live_*` |
| CFE | `project-scaffold/cfe/NinjaLive` | HTTP `/hs/ninja-live` в ИБ |

Это **одна поставка**, не два независимых репозитория.

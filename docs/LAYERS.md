# Слои 1c-ninja-kit

```text
Machine  →  Profile (~/.cursor)  →  Project  →  Adapter (Cursor / …)
                ↑
         SoT = этот репозиторий
```

| Слой | Что | Кто ставит |
|------|-----|------------|
| **Machine** | OVM/OneScript, bsl-analyzer, Apache tools, Toolkit EPF, cc-1c-skills | человек + `kit doctor` |
| **Profile** | skills / rules / agents | `kit apply --profile 1c-ninja-kit` |
| **Project** | `.v8-project.json`, mcp, NinjaLive, OpenSpec | `1c-env-setup` / `kit init-project` |
| **Adapter** | как харнесс (OpenCode) читает skills/MCP | `adapters/<name>/` |

## Пара Ninja

| Часть | Путь в kit | Роль |
|-------|------------|------|
| MCP | `components/1c-ninja-mcp` | static + `live_*` |
| CFE | `project-scaffold/cfe/NinjaLive` | HTTP `/hs/ninja-live` в ИБ |

Это **одна поставка**, не два независимых репозитория.

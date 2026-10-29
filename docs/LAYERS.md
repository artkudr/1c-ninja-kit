# Слои 1c-ninja-kit

```text
Machine  →  Profile  →  Project
                ↑
         SoT = этот репозиторий
```

| Слой | Что | Кто ставит |
|------|-----|------------|
| **Machine** | OVM/OneScript, bsl-analyzer, Apache tools, Toolkit EPF, cc-1c-skills | человек + `kit doctor` |
| **Profile** | skills / rules / agents | `kit apply` |
| **Project** | `.v8-project.json`, mcp, NinjaLive, OpenSpec, `AGENTS.md` | скилл `skill-env-setup` |

Харнесс один — **OpenCode V2**. Куда именно раскладываются skills/rules/agents и как
собирается `AGENTS.md`, описано в `docs/opencode.md`; контракт имён — `docs/NAMING.md`.

## Пара Ninja

| Часть | Путь в kit | Роль |
|-------|------------|------|
| MCP | `components/1c-ninja-mcp` | static + `live_*` |
| CFE | `project-scaffold/cfe/NinjaLive` | HTTP `/hs/ninja-live` в ИБ |

Это **одна поставка**, не два независимых репозитория.

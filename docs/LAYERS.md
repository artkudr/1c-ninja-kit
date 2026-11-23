# Слои 1c-ninja-kit

```text
Machine  →  Profile  →  Project
                ↑
         SoT = этот репозиторий
```

| Слой | Что | Кто ставит |
|------|-----|------------|
| **Machine** | OVM/OneScript, bsl-analyzer, Apache tools, Toolkit EPF, cc-1c-skills | человек + `kit doctor` |
| **Profile** | agents / commands / `run.ps1` — копией в `~/.config/opencode/` | `kit apply` |
| **Project** | skills / rules — копией в `<проект>\.opencode` + `instructions` в проектном `opencode.jsonc` | `kit stage` |
| **Project** | `.v8-project.json`, mcp, NinjaLive, `AGENTS.md`, `Задачи/` | скилл `skill-env-setup` |

Профиль один на машину: агенты, команды и скрипт каркаса задачи (`/Задача`,
`/Продолжить`, `/Статус`) лежат глобально, а состояние задачи — в проекте. Харнесс один — **OpenCode V2**. Куда именно раскладываются skills/rules/agents и почему пути, а не симлинки, описано в `docs/opencode.md`; контракт имён — `docs/NAMING.md`.

## Пара Ninja

| Часть | Путь в kit | Роль |
|-------|------------|------|
| MCP | `components/1c-ninja-mcp` | static + `live_*` |
| CFE | `project-scaffold/cfe/NinjaLive` | HTTP `/hs/ninja-live` в ИБ |

Это **одна поставка**, не два независимых репозитория.

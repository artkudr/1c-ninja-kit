# Architecture (v0.8)

Краткий снимок устройства кита.

## Ядро

- SoT профиля: этот репозиторий (`profile/`).
- Пара live: `components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`.
- Агрегат профиля: `1c-ninja-kit`.
- Харнесс: **только OpenCode V2**. Отображение путей и MCP — `docs/opencode.md`,
  контракт имён — `docs/NAMING.md`.

## Слои

```text
Machine  →  Profile  →  Project
                ↑
         SoT = этот репозиторий
```

| Слой | Что | Кто ставит |
|------|-----|------------|
| **Machine** | OVM/OneScript, bsl-analyzer, Apache tools, Toolkit EPF, cc-1c-skills | человек + `kit doctor` |
| **Profile** | skills / rules — путями в `~/.config/opencode/opencode.jsonc`; agents / commands / `taskctl.ps1` — копией | `kit apply` |
| **Project** | `.v8-project.json`, MCP, NinjaLive, `AGENTS.md`, `Задачи/` | скилл `skill-env-setup` |

## Инварианты

1. 1С MCP только в project `opencode.jsonc`, не в глобальном профиле.
2. Пара `components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`.
3. Apache 8083 ↔ 8.3, 8085 ↔ 8.5; webUrl с `/ru_RU/`.
4. Один процессный мозг: `profile/rules` (always-on + on-demand).
5. Список CFE — `live_extensions_list`, не Предприятие.
6. Секреты не в git; пароли маскировать в логах.

## CLI

```text
kit.ps1 doctor
kit.ps1 verify
kit.ps1 apply
kit.ps1 lock        # пересобрать lock/profile.lock.json из profile/
kit.ps1 deps        # внешние зависимости: ставит отсутствующее, версии — с upstream
```

Новый проект создаёт скилл `skill-env-setup`; `kit init-project` удалён в 0.8.0.

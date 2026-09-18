# DeepSeek Harness adapter (v0.3)

Совместимость: **SKILL.md** (Agent Skills) + **MCP tools** через DSH MCP client.  
Cursor Plugin / `.mdc` rules **не** ставятся as-is — процесс сжимается в `AGENTS.md`.

Офиц. skills roots (rank): project `.dsh/skills` → `.agents/skills` → user `~/.dsh/skills` → `~/.agents/skills`.

## Установка профиля

```powershell
powershell -NoProfile -File C:\1C\projects\1c-ninja-kit\install\kit.ps1 apply -Adapter deepseek
# or from cloned kit root:
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter deepseek
```

Кладёт skills в `%USERPROFILE%\.agents\skills\` (и зеркало `%USERPROFILE%\.dsh\skills\` если каталог есть / создаётся).

## Project

`kit.ps1 init-project -ProjectPath ... -Adapter deepseek` создаёт:

| Файл | Назначение |
|------|------------|
| `AGENTS.md` | оркестрация + stack defaults |
| `.agents/skills/` | опциональная project-копия core (или полагаться на user skills) |
| `.dsh/mcp.servers.example.json` | пример MCP (без секретов) |
| `src/cfe/NinjaLive` | CFE-пара |
| пути к `components/1c-ninja-mcp` | в MCP example |

## MCP

DSH регистрирует tools как `mcp__<server>__<tool>`. Подключи серверы из example (vrunner, 1c-ninja-mcp, bsl-analyzer, toolkit).  
Секреты (`NINJA_*`) — только локальный конфиг, не в git.

См. `mcp.example.json`, `bridge-notes.md`.

## Тест

`docs/TEST-GUIDE-deepseek.md`

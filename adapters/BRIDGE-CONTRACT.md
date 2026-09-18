# Bridge contract (Cursor / DeepSeek / Hermes)

Единый контракт поставки kit. Адаптер = **маппинг путей + MCP config + project context file**.  
Полноценный TypeScript plugin для DSH не обязателен в v0.3: достаточно skills (`SKILL.md`) + MCP tools bridge, уже встроенный в харнессы.

## Обязательные инварианты (все адаптеры)

1. **1С MCP только в project/session config**, не в глобальном профиле с секретами чужой ИБ.
2. Пара **`components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`**.
3. Stack defaults: Apache **8083↔8.3**, **8085↔8.5**; webUrl с `/ru_RU/`.
4. Один процессный мозг: правила оркестрации из `profile/rules` (через project context / always-on rules).
5. Список CFE в ИБ: `live_extensions_list`, не Предприятие.
6. Секреты не в git; пароли маскировать в логах тестов.

## Слои

| Слой | SoT в kit | Cursor | DeepSeek Harness | Hermes |
|------|-----------|--------|------------------|--------|
| Skills | `profile/skills/*/SKILL.md` | `~/.cursor/skills` | `~/.agents/skills` и/или `~/.dsh/skills`; project: `.agents/skills` | `~/.hermes/skills` |
| Rules / process | `profile/rules/*.mdc` | hardlink project `.cursor/rules` | сжать в `AGENTS.md` / `.dsh` context (mdc не native) | `.hermes.md` или `AGENTS.md` (+ опц. совместимость с cursor rules) |
| Agents | `profile/agents/*.md` | `~/.cursor/agents` | опционально как skills/prompts | опционально |
| MCP | templates | project `.cursor/mcp.json` | DSH MCP client config | `~/.hermes/config.yaml` → `mcp_servers` |
| Identity | — | — | — | `~/.hermes/SOUL.md` fragment |

## Runtime bridge (минимальный v0.3)

| Возможность | Статус v0.3 |
|-------------|-------------|
| MCP tools → native tools харнесса | **да** (встроенный MCP client DSH/Hermes) |
| Skills SKILL.md on-demand | **да** (оба харнесса умеют Agent Skills) |
| Cursor `.mdc` alwaysApply/globs | **эмуляция**: ключевые always-on правила → `AGENTS.md` / `.hermes.md` |
| Cursor agents frontmatter | **частично**: не требуется для smoke; опционально позже |
| MCP Resources/Prompts | не обещаем (DSH tools-only) |

## Apply API

```text
kit.ps1 apply -Adapter cursor|deepseek|hermes [-DryRun]
kit.ps1 init-project -ProjectPath PATH -Adapter cursor|deepseek|hermes ...
```

`init-project` пишет project context файл адаптера + mcp config example.

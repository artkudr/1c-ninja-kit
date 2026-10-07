# Bridge contract (OpenCode)

Единый контракт поставки kit. Адаптер = **маппинг путей + MCP config + project context file**.
Харнесс-адаптеров больше одного: профиль собирается только под OpenCode.

## Обязательные инварианты

1. **1С MCP только в project config**, не в глобальном профиле с секретами чужой ИБ.
2. Пара **`components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`**.
3. Stack defaults: Apache **8083↔8.3**, **8085↔8.5**; webUrl с `/ru_RU/`.
4. Один процессный мозг: правила оркестрации из `profile/rules` (always-on + on-demand).
5. Список CFE в ИБ: `live_extensions_list`, не Предприятие.
6. Секреты не в git; пароли маскировать в логах тестов.

## Слои

| Слой | SoT в kit | OpenCode (V2) |
|------|-----------|---------------|
| Skills | `profile/skills/*/SKILL.md` | `~/.config/opencode/skills`; project: `.opencode/skills` |
| Rules / process | `profile/rules/*.mdc` | always-on → managed-блок `~/.config/opencode/AGENTS.md`; on-demand → `~/.config/opencode/kit-rules/*.md` |
| Agents | `profile/agents/*.md` | `~/.config/opencode/agents/*.md` (`mode: subagent`, frontmatter конвертируется) |
| MCP | `adapters/opencode/opencode.jsonc.tpl` | project `opencode.jsonc` → `mcp.servers` (`type: local` / `remote`, у streamable-http обязателен `oauth: false`) |
| Commands | `project-scaffold/templates/commands` | project `.opencode/commands`; global `~/.config/opencode/commands` |
| Identity | — | — (инструкции = `AGENTS.md`) |

## Runtime bridge

| Возможность | Статус |
|-------------|--------|
| MCP tools → native tools харнесса | **да** (встроенный MCP client OpenCode) |
| Skills SKILL.md on-demand | **да** (Agent Skills) |
| `.mdc` alwaysApply/globs | **эмуляция**: always-on правила инлайнятся в managed-блок `AGENTS.md` |
| agents frontmatter | **частично**: конвертируется (`tools`/`allowParallel`/`model: inherit` → `mode: subagent`) |
| MCP Resources/Prompts | не обещаем (tools-only) |

## Apply API

```text
kit.ps1 apply -Adapter opencode [-DryRun]
kit.ps1 init-project -ProjectPath PATH -Adapter opencode ...
```

`init-project` пишет project context файл + `opencode.jsonc` (+ `.example`) + `.opencode/commands`.

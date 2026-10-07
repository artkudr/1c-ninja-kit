# Bridge contract (Cursor / DeepSeek / Hermes / OpenCode)

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

| Слой | SoT в kit | Cursor | DeepSeek Harness | Hermes | OpenCode (V2) |
|------|-----------|--------|------------------|--------|---------------|
| Skills | `profile/skills/*/SKILL.md` | `~/.cursor/skills` | `$DSH_HOME/skills` + `~/.agents/skills`; project: `.dsh/skills` (rank 100) | `~/.hermes/skills` | `~/.config/opencode/skills`; project: `.opencode/skills` |
| Rules / process | `profile/rules/*.mdc` | hardlink project `.cursor/rules` | managed-блок в `$DSH_HOME/AGENTS.md`; on-demand -> `$DSH_HOME/kit-rules/*.md` | `.hermes.md` или `AGENTS.md` (+ опц. совместимость с cursor rules) | always-on → managed-блок `~/.config/opencode/AGENTS.md`; on-demand → `~/.config/opencode/kit-rules/*.md` |
| Agents | `profile/agents/*.md` | `~/.cursor/agents` | роли как skills `1c-role-*` (файловых subagent-типов нет) | опционально | `~/.config/opencode/agents/*.md` (`mode: subagent`, frontmatter конвертируется) |
| MCP | templates | project `.cursor/mcp.json` | profile `cordis.patch.yml` -> rows `@deepseek-ai/dsh-mcp-client` (Cordis YAML) | `~/.hermes/config.yaml` → `mcp_servers` | project `opencode.jsonc` → `mcp.servers` (`type: local` / `remote`, у streamable-http обязателен `oauth: false`) |
| Commands | `project-scaffold/templates/commands` | project `.cursor/commands` | — | — | project `.opencode/commands`; global `~/.config/opencode/commands` |
| Identity | — | — | — | `~/.hermes/SOUL.md` fragment | — (инструкции = `AGENTS.md`) |

## Runtime bridge

| Возможность | Статус |
|-------------|--------|
| MCP tools → native tools харнесса | **да** (встроенный MCP client DSH/Hermes/OpenCode) |
| Skills SKILL.md on-demand | **да** (все три харнесса умеют Agent Skills) |
| Cursor `.mdc` alwaysApply/globs | **эмуляция**: ключевые always-on правила → `AGENTS.md` / `.hermes.md` / managed-блок `AGENTS.md` |
| Cursor agents frontmatter | **частично**: для OpenCode конвертируется (`tools`/`allowParallel`/`model: inherit` → `mode: subagent`) |
| MCP Resources/Prompts | не обещаем (DSH tools-only) |

## Apply API

```text
kit.ps1 apply -Adapter cursor|deepseek|hermes|opencode [-DryRun]
kit.ps1 init-project -ProjectPath PATH -Adapter cursor|deepseek|hermes|opencode ...
```

`init-project` пишет project context файл адаптера + mcp config example.
`capture` (живой профиль → SoT) поддерживает только `-Adapter cursor`: конвертация в OpenCode lossy.

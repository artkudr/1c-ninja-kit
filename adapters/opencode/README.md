# OpenCode adapter

Bridge для **OpenCode V2** (конфиг `opencode.json(c)`, инструкции `AGENTS.md`, skills, agents, commands, MCP).

| Слой | Target |
|------|--------|
| Skills | `~/.config/opencode/skills/<id>/SKILL.md` (ID = имя каталога, kebab-case совпадает с профилем) |
| Rules / process | `~/.config/opencode/AGENTS.md` — managed-блок `<!-- 1c-ninja-kit:begin --> … <!-- 1c-ninja-kit:end -->`; always-on правила **инлайнятся**, on-demand → `~/.config/opencode/kit-rules/<name>.md` |
| Agents | `~/.config/opencode/agents/<id>.md`, `mode: subagent` (frontmatter Cursor → OpenCode) |
| Commands | project `.opencode/commands/*.md` (`/opsx-propose`, `/opsx-apply`, `/opsx-archive`, `/opsx-explore`) |
| MCP | project `opencode.jsonc` → `mcp.servers` (`type: local` / `type: remote`) |
| Project context | project `AGENTS.md` (общий шаблон `adapters/shared/AGENTS.md.tpl`) |

## Apply (профиль → глобальный OpenCode)

```powershell
powershell -NoProfile -File C:\1C\projects\1c-ninja-kit\install\kit.ps1 apply -Adapter opencode
```

Что делает:

1. `profile/skills` → `~/.config/opencode/skills` (robocopy mirror).
2. `profile/agents/*.md` → `~/.config/opencode/agents/*.md` с конвертацией frontmatter
   (`tools` / `allowParallel` / `model: inherit` выбрасываются, добавляется `mode: subagent`).
3. `profile/rules/*.mdc` → `~/.config/opencode/kit-rules/*.md` (без frontmatter) + пересборка managed-блока в `AGENTS.md`.
4. Проверка: в глобальном `~/.config/opencode/opencode.json(c)` не должно быть 1С MCP-серверов.

Полезный флаг: `-DryRun`. Перезапись — по умолчанию: ручные правки
в `~/.config/opencode/{skills,agents,kit-rules}` и в managed-блоке `AGENTS.md` будут затёрты следующим `apply`.
Текст вне маркеров `<!-- 1c-ninja-kit:begin -->` / `<!-- 1c-ninja-kit:end -->` в `AGENTS.md` сохраняется.

## Init project

```powershell
powershell -NoProfile -File C:\1C\projects\1c-ninja-kit\install\kit.ps1 init-project `
  -ProjectPath C:\1C\projects\unf-dev -Adapter opencode `
  -AppName unf-dev -V8Version 8.3 -WebPort 8083
```

Кладёт в проект:

| Файл | Назначение |
|------|------------|
| `opencode.jsonc` | `mcp.servers` (vrunner, 1c-ninja-mcp, bsl-analyzer reference+workspace, v8std, toolkit выключен) — **секреты здесь, файл в gitignore** |
| `opencode.jsonc.example` | тот же конфиг с `<user>` / `<password>` — коммитится |
| `AGENTS.md` | project context из `adapters/shared/AGENTS.md.tpl` |
| `.opencode/commands/opsx-*.md` | OpenSpec slash-команды |
| `.gitignore` | + `opencode.jsonc` |

## Особенности V2, которые важны

- **MCP-имя нормализуется**: `1c-ninja-mcp` → инструменты `mcp_1c_ninja_mcp_live_query` и т.п. В коде-моде — `tools.mcp_1c_ninja_mcp.live_query(...)`.
- **MCP prompts** становятся командами `<server>:<prompt>`; в v0.4 не используем.
- **`.mdc` не нативны.** Always-on эмулируется инлайном в `AGENTS.md`, on-demand — файлами в `kit-rules/` + ссылкой в `AGENTS.md`.
- **Удалённые MCP по умолчанию OAuth.** Для `v8std` и `1c-mcp-toolkit` (streamable-http без OAuth) нужен явный `"oauth": false`, иначе OpenCode будет ждать авторизацию.
- **Инструкции — только `AGENTS.md`.** `CLAUDE.md` и `instructions` в конфиге V2 не подхватываются.
- **Агенты** — только `agents/` (не `agent/`), ID = путь без расширения.

## Проверка

`docs/TEST-GUIDE-opencode.md` (doctor → apply → init-project → smoke MCP → live).

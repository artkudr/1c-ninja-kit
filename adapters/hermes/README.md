# Hermes Agent adapter (v0.3)

Совместимость: **SKILL.md** → `~/.hermes/skills/`; **MCP** → `~/.hermes/config.yaml` (`mcp_servers`); project context → `.hermes.md` (приоритетнее `AGENTS.md`).

Docs: [Skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills), [MCP](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp), [Which file](https://hermes-agent.nousresearch.com/docs/user-guide/which-file-does-what).

## Установка профиля

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter hermes
```

- skills → `%USERPROFILE%\.hermes\skills\`
- optional fragment → `%USERPROFILE%\.hermes\SOUL.1c-ninja-kit.md` (влить в SOUL.md вручную или cat)

## Project

`init-project -Adapter hermes` создаёт `.hermes.md` + `mcp_servers.fragment.yaml` + NinjaLive.

После правки MCP: в сессии Hermes `/reload-mcp`.

## Тест

`docs/TEST-GUIDE-hermes.md`

# 1c-ninja-kit — project agent context

This project uses **1c-ninja-kit** for agentic 1C development.

## Stack defaults

- Platform **8.3** → Apache port **8083**, tools `%USERPROFILE%\tools\apache-83`
- Platform **8.5** → Apache port **8085**, tools `%USERPROFILE%\tools\apache-85`
- Web smoke URLs include `/ru_RU/`
- 1C MCP servers belong in **project** config only (not global user MCP with shared secrets)
- Ninja pair: kit `components/1c-ninja-mcp` + project `src/cfe/NinjaLive` (`/hs/ninja-live`)
- CFE list in IB: MCP `live_extensions_list` (not Enterprise / not vrunner extensions list as canon)
- Do not use Designer / raw `1cv8` / Platform Tools instead of vrunner
- Do not directory-junction `.cursor/rules`

## Triage

| Path | When |
|------|------|
| Quick-fix | One file/method; small BSL; no posting/public API/adopted CFE/RLS |
| Docs-fix | Markdown/rules/docs only |
| Full-cycle | Everything else; large → OpenSpec propose before code |

## MCP routes

| Need | Tooling |
|------|---------|
| BSL semantics / graph / diagnostics | bsl-analyzer-workspace |
| Live IB query/metadata/CFE list | 1c-ninja-mcp `live_*` |
| Load / syntax-check / repo | vrunner |
| Live fallback | 1c-mcp-toolkit |

## Skills

Install kit profile skills into the harness skill root, then use `1c-env-setup`, `repo-workflow`, `meta-*`, `form-*`, `cfe-*`, `1c-ninja-mcp`, `1c-bsl-analyzer`, `vrunner-mcp` as needed.

## Kit CLI

```text
kit.ps1 doctor
kit.ps1 verify
kit.ps1 apply -Adapter <cursor|deepseek|hermes>
kit.ps1 init-project -ProjectPath <dir> -Adapter <...>
```

Forbidden: init-project on ecoladev product tree unless explicitly intended.

## Secrets

Never commit `autumn-properties.json`, project mcp with passwords, or `NINJA_PASSWORD`.

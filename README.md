# 1c-ninja-kit

Агентная обвязка разработки 1С: skills, rules, MCP (**1c-ninja-mcp** + CFE **NinjaLive**), vrunner, bsl-analyzer, адаптеры **Cursor / DeepSeek Harness / Hermes**.

**VERSION:** 0.3.0

## Quick start

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git
cd 1c-ninja-kit
# If the machine has only the 1C platform installed:
# read docs/MACHINE-BOOTSTRAP.md first
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter cursor   # or deepseek | hermes
```

## Adapters

| Harness | Guide |
|---------|--------|
| Cursor | `adapters/cursor/` |
| DeepSeek Harness | `adapters/deepseek/` + **`docs/TEST-GUIDE-deepseek.md`** |
| Hermes | `adapters/hermes/` + **`docs/TEST-GUIDE-hermes.md`** |

Bridge contract: `adapters/BRIDGE-CONTRACT.md`.

## What is inside

| Path | Content |
|------|---------|
| `profile/` | skills / rules / agents |
| `components/1c-ninja-mcp/` | MCP server (part of kit) |
| `project-scaffold/cfe/NinjaLive/` | Live CFE pair |
| `install/kit.ps1` | doctor / apply / init-project |
| `docs/MACHINE-BOOTSTRAP.md` | bare PC: откуда скачать OVM, bsl-analyzer, toolkit |
| `companions/pins.json` | upstream GitHub URLs для companion-бинарников |

## Hard rules

- Do not put 1C MCP secrets in global user config committed to git
- Apache **8083** for platform 8.3, **8085** for 8.5
- CFE list via `live_extensions_list`
- See `NOTICE.md` for third-party attribution

## License / notice

See `NOTICE.md`. Third-party tools (OneScript, vanessa-runner, bsl-analyzer, Apache, platform 1C) remain under their own terms and are **not** vendored as binaries here.

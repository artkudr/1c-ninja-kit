# 1c-ninja-kit

Агентная обвязка разработки 1С: skills (kit + cc-1c-skills), rules, MCP (**1c-ninja-mcp** + CFE **NinjaLive**), bsl-analyzer, харнесс **OpenCode**.

**VERSION:** 0.10.0

## Quick start

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git
cd 1c-ninja-kit
# Платформа 1С — своим дистрибутивом; всё остальное ставит deps:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\kit.ps1 deps
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 apply
```

Подробности машинного слоя: `docs/MACHINE-BOOTSTRAP.md`.

## Harness

Харнесс один — **OpenCode V2**. Отображение профиля, MCP и `AGENTS.md`:
`docs/opencode.md`. Проверка доставки: `docs/TEST-GUIDE-opencode.md`.

## What is inside

| Path | Content |
|------|---------|
| `profile/` | skills / rules / agents |
| `components/1c-ninja-mcp/` | MCP server (part of kit) |
| `project-scaffold/cfe/NinjaLive/` | Live CFE pair |
| `install/kit.ps1` | doctor / verify / apply / deps |
| `install/deps.ps1` | установка внешних зависимостей (OneScript, bsl-analyzer, ripgrep, Node/Playwright, Apache, toolkit) |
| `docs/opencode.md` | единственный харнесс: пути, MCP, `AGENTS.md`, ограничения |
| `docs/NAMING.md` | контракт имён `skill-` / `rule-` / `agent-` |
| `docs/MACHINE-BOOTSTRAP.md` | bare PC: что ставит `kit.ps1 deps`, что остаётся руками |
| `companions/pins.json` | upstream GitHub URLs для companion-бинарников |

## Hard rules

- Do not put 1C MCP secrets in global user config committed to git
- Apache **8083** for platform 8.3, **8085** for 8.5
- CFE list via `live_extensions_list`
- See `NOTICE.md` for third-party attribution

## License / notice

See `NOTICE.md`. Third-party tools (OneScript, vanessa-runner, bsl-analyzer, Apache, platform 1C) remain under their own terms and are **not** vendored as binaries here.

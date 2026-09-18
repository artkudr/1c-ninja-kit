# Companions (внешние зависимости)

`1c-ninja-mcp` и `NinjaLive` — **часть kit**, не companions.

Всё остальное качается с **публичных upstream**, не с чужого `C:\1C\soft`.

| Компонент | Upstream | Куда поставить |
|-----------|----------|----------------|
| bsl-analyzer | [itrous/bsl-analyzer releases](https://github.com/itrous/bsl-analyzer/releases) → `bsl-analyzer-windows-amd64.exe` | `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` |
| MCP Toolkit | [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `MCP_Toolkit.epf` | `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` (рекомендуется) |
| OneScript/OVM | [oscript.io](https://oscript.io/) | `%LOCALAPPDATA%\ovm\current` |
| Apache | ваша поставка | `%USERPROFILE%\tools\apache-83` / `apache-85` |

Пошагово: `docs/MACHINE-BOOTSTRAP.md`.  
Машиночитаемо: `pins.json`.

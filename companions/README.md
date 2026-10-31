# Companions (внешние зависимости)

`1c-ninja-mcp` и `NinjaLive` — **часть kit**, не companions.

Всё остальное качается с **публичных upstream**, не с чужого `C:\1C\soft`.

| Компонент | Upstream | Куда поставить |
|-----------|----------|----------------|
| bsl-analyzer | [itrous/bsl-analyzer releases](https://github.com/itrous/bsl-analyzer/releases) → `bsl-analyzer-windows-amd64.exe` | `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` |
| MCP Toolkit | [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `MCP_Toolkit.epf` | `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` (рекомендуется) |
| OneScript/OVM | [oscript.io](https://oscript.io/), zip релиза [EvilBeaver/OneScript](https://github.com/EvilBeaver/OneScript/releases) | `%LOCALAPPDATA%\ovm\current` |
| Apache | [Apache Lounge](https://www.apachelounge.com/download/) Win64 | `%USERPROFILE%\tools\apache-83` / `apache-85` |
| Ripgrep | [BurntSushi/ripgrep releases](https://github.com/BurntSushi/ripgrep/releases) | `%USERPROFILE%\tools\ripgrep` + PATH |
| Node.js | [nodejs.org/dist](https://nodejs.org/dist/) (LTS win-x64 zip) | `%USERPROFILE%\tools\node` + PATH |
| Playwright + Chromium | `npm ci` в скилле `skill-web-test`, `playwright install chromium` | `node_modules` скилла + `%LOCALAPPDATA%\ms-playwright` |

Ставит всё это `install\kit.ps1 deps` (см. `install/deps.ps1`): качает с upstream,
сверяет версию после установки, пишет фактическое состояние в
`%LOCALAPPDATA%\1c-ninja-kit\deps-state.json`. Руками скачивать не нужно.

Пошагово: `docs/MACHINE-BOOTSTRAP.md`.  
Машиночитаемо: `pins.json`.

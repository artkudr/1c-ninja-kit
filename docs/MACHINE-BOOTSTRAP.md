# MACHINE BOOTSTRAP — голая Windows + только платформа 1С

Цель: довести машину до состояния, когда `kit.ps1 doctor` проходит required-проверки.  
Платформу 1С ставите вы (дистрибутив 1С). Остальное — ниже.

## 0. Проверка

```powershell
# Platform present? (example)
Get-ChildItem "C:\Program Files\1cv8\*" -ErrorAction SilentlyContinue | Select-Object -First 5 Name
```

## 1. OneScript / OVM

1. Установите [OneScript](https://oscript.io/) / OVM так, чтобы появился `%LOCALAPPDATA%\ovm\current`.
2. `opm install vanessa-runner@SNAPSHOT` (или зафиксированная 3.x).
3. Проверка: `vrunner --version` → ветка **3.x**.
4. Убедитесь, что есть `vrunner-mcp.bat` рядом с vrunner.

## 2. bsl-analyzer

1. Поставьте лаунчер/бинарник в `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` (по вашей поставке analyzer).
2. Проверка: файл существует; позже MCP `bsl-analyzer-workspace`.

## 3. Apache tools (web / ninja-live)

Не коммитить Apache в git. Разложите:

| Платформа | Порт | Каталог |
|-----------|------|---------|
| 8.3 | 8083 | `%USERPROFILE%\tools\apache-83` |
| 8.5 | 8085 | `%USERPROFILE%\tools\apache-85` |

Если 8.5 нет — doctor даст WARN, для 8.3 этого достаточно.

## 4. MCP Toolkit (optional fallback)

- EPF обычно: `C:\1C\soft\MCP_Toolkit.epf`
- HTTP MCP: `http://127.0.0.1:6003/mcp`

Без toolkit smoke возможен через ninja-live.

## 5. Node / Playwright (optional, web-test)

Нужен только для UI smoke `web-test`. Для live list — не обязателен.

## 6. Clone kit + doctor

```powershell
git clone <THIS_REPO_URL> C:\1C\projects\1c-ninja-kit
cd C:\1C\projects\1c-ninja-kit
powershell -NoProfile -File .\install\kit.ps1 doctor
```

Required FAIL → не идите в apply, пока не закроете пробелы.

## 7. Дальше по харнессу

- DeepSeek: `docs/TEST-GUIDE-deepseek.md`
- Hermes: `docs/TEST-GUIDE-hermes.md`
- Cursor: `adapters/cursor/` + `docs/ADAPTATION.md`

## Локальные патчи vrunner (optional)

См. `profile/docs-patches/vrunner-local-patches.md`.  
Для канона списка CFE через `live_extensions_list` EPF-патч extensions list **не** обязателен; MCPIFY INFO→tool result — желателен для Cursor sync MCP.

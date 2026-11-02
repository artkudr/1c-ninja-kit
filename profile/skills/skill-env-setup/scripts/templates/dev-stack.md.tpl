# Стек разработки (агент / CLI)

| Компонент | Где | Версия / заметка |
|-----------|-----|------------------|
| OneScript | OVM `%LOCALAPPDATA%\ovm\current` | ≥ 2.2.0 (движок MCP-серверов kit) |
| Skills (kit) | `C:\1C\projects\1c-ninja-kit\profile\skills`, `…\profile\rules` | пути в `~/.config/opencode/opencode.jsonc` (`skills`, `instructions`), ставит `kit.ps1 apply`; правка видна без копирования |
| Каркас задачи | `~/.config/opencode/scripts/taskctl.ps1`, `~/.config/opencode/commands` | глобальные `/Задача`, `/Продолжить`, `/Статус`; состояние — `Задачи/` проекта |
| Skills (cc-1c-skills) | `~/.config/opencode/skills/` | `db-*`, `meta-*`, `form-*`, `cfe-*`, `epf-*`, …; ставится `install/cc-skills.ps1` (обновление — `-Update`) |
| MCP (user) | `~/.config/opencode/opencode.json(c)` | **без** 1С-серверов (`mcp.servers`); иначе дубли с проектом |
| MCP (project) | `opencode.jsonc` (gitignore) | ninja live **этой** ИБ, bsl-analyzer reference+workspace, v8std, toolkit (fallback) |
| Настройки ИБ | `.v8-project.json` в корне проекта | реестр баз контура скиллов (`db-*`, `skill-web-*`) |
| Хранилища CFE | `.v8-project.json` → `extensions[].repository` | карта расширений → `skill-repo-workflow` |
| 1c-ninja-mcp live | project env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` | приоритет для запросов/метаданных ИБ; CFE `NinjaLive` + Apache `/hs/ninja-live`. Список CFE в ИБ: `live_extensions_list` (не Предприятие) |
| bsl-analyzer | workspace — `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe` (`--mode broker`), reference — лаунчер `%LOCALAPPDATA%\bsl-analyzer`; кеш `<проект>\.build` | MCP workspace (project) |
| 1c-mcp-toolkit | `http://127.0.0.1:6003/mcp` | fallback; EPF с [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` |
| skill-web-test | `tools/web-test/smoke.config.json` | UI smoke после `skill-repo-workflow` load |

ИБ и исходники — **только** в корне открытого проекта.

Развёртывание новой папки на этой машине: скилл `skill-env-setup` («разверни окружение»).

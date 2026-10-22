# Стек разработки (агент / CLI)

| Компонент | Где | Версия / заметка |
|-----------|-----|------------------|
| OneScript | OVM `%LOCALAPPDATA%\ovm\current` | ≥ 2.2.0 (движок MCP-серверов kit) |
| Skills (kit) | `~/.config/opencode/skills/` | профиль kit: `1c-*`, `web-*`, `repo-workflow`, `handoff`; ставится `kit.ps1 apply -Adapter opencode` |
| Skills (cc-1c-skills) | `~/.config/opencode/skills/` | `db-*`, `meta-*`, `form-*`, `cfe-*`, `epf-*`, …; ставится `install/cc-skills.ps1` (обновление — `-Update`) |
| MCP (user) | `~/.config/opencode/opencode.json(c)` | **без** 1С-серверов (`mcp.servers`); иначе дубли с проектом |
| MCP (project) | `opencode.jsonc` (gitignore; пример `opencode.jsonc.example`) | ninja live **этой** ИБ, bsl-analyzer reference+workspace, v8std, toolkit (fallback) |
| Настройки ИБ | `.v8-project.json` в корне проекта | реестр баз контура скиллов (`db-*`, `web-*`) |
| Хранилища CFE | `.v8-project.json` → `extensions[].repository` | карта расширений → `repo-workflow` |
| 1c-ninja-mcp live | project env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` | приоритет для запросов/метаданных ИБ; CFE `NinjaLive` + Apache `/hs/ninja-live`. Список CFE в ИБ: `live_extensions_list` (не Предприятие) |
| bsl-analyzer | лаунчер `%LOCALAPPDATA%\bsl-analyzer` ([itrous/bsl-analyzer releases](https://github.com/itrous/bsl-analyzer/releases)); кеш `<проект>\.build` | MCP workspace (project) |
| 1c-mcp-toolkit | `http://127.0.0.1:6003/mcp` | fallback; EPF с [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` |
| web-test | `tools/web-test/smoke.config.json` | UI smoke после `repo-workflow` load |
| OpenSpec | `openspec/` + `.opencode/commands/opsx-*.md` | крупные full-cycle фичи: propose → apply → archive; slash `/opsx-propose`, `/opsx-apply`, `/opsx-archive`, `/opsx-explore` |

ИБ и исходники — **только** в корне открытого проекта.

Развёртывание новой папки на этой машине: скилл `1c-env-setup` («разверни окружение»).

# Стек разработки (агент / CLI)

| Компонент | Где | Версия / заметка |
|-----------|-----|------------------|
| OneScript | OVM `%LOCALAPPDATA%\ovm\current` | ≥ 2.0.0 |
| vanessa-runner | глобально `opm install vanessa-runner@SNAPSHOT` | 3.x |
| Skills / rules | `%USERPROFILE%\.cursor\skills\`, `%USERPROFILE%\.cursor\rules\` | канон в профиле; в проекте обычная папка `.cursor/rules` + hardlink (`mklink /H`) каждого `.mdc` (не folder junction, gitignore) |
| MCP (user) | `%USERPROFILE%\.cursor\mcp.json` | **без** 1С-серверов (`mcpServers: {}`); иначе дубли с проектом |
| MCP (project) | `.cursor/mcp.json` (gitignore; пример `mcp.json.example`) | полный эталон скилла: vrunner, toolkit, autumn live **этой** ИБ, bsl-analyzer reference+workspace |
| Настройки ИБ | `autumn-properties.json` в корне проекта | vrunner 3 |
| Хранилища CFE | `repository.json` в корне проекта | карта расширений → `repo-workflow` |
| 1c-ninja-mcp live | project env `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` | приоритет для запросов/метаданных ИБ; CFE `NinjaLive` + Apache `/hs/ninja-live`. Список CFE в ИБ: `live_extensions_list` (не Предприятие) |
| bsl-analyzer | лаунчер `%LOCALAPPDATA%\bsl-analyzer` ([itrous/bsl-analyzer releases](https://github.com/itrous/bsl-analyzer/releases)); кеш `<проект>\.build` | MCP workspace (project) |
| 1c-mcp-toolkit | `http://127.0.0.1:6003/mcp` | fallback; EPF с [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` |
| web-test | `tools/web-test/smoke.config.json` | UI smoke после `repo-workflow` load |
| OpenSpec | `openspec/` + `.cursor/commands/opsx-*.md` | крупные full-cycle фичи: propose → apply → archive; slash `/opsx-propose`, `/opsx-apply`, `/opsx-archive`, `/opsx-explore` |

ИБ и исходники — **только** в корне открытого проекта.

Развёртывание новой папки на этой машине: скилл `1c-env-setup` («разверни окружение»).

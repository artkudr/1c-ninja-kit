# ADAPTATION — чеклист на месте

Агент проходит **по порядку**. Статусы: `ready` / `blocked` / `needs-human`.

## 1. Machine soft

| # | Проверка | Как | Кто |
|---|----------|-----|-----|
| 1.1 | OVM / oscript | `kit.ps1 doctor` | auto |
| 1.2 | vrunner 3.x | `vrunner --version` | auto |
| 1.3 | bsl-analyzer.exe | doctor; install from [itrous/bsl-analyzer releases](https://github.com/itrous/bsl-analyzer/releases) → `bsl-analyzer-windows-amd64.exe` as `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` | auto / needs-human |
| 1.4 | Apache tools 83/85 | `%USERPROFILE%\tools\apache-83` / `apache-85` | auto / needs-human если нет |
| 1.5 | Toolkit EPF (optional) | [ROCTUP/1c-mcp-toolkit releases](https://github.com/ROCTUP/1c-mcp-toolkit/releases) → `%USERPROFILE%\tools\1c-mcp-toolkit\MCP_Toolkit.epf` | needs-human |

v0.1: soft **assumed** — doctor только предупреждает.

## 2. Kit components

| # | Проверка | Как |
|---|----------|-----|
| 2.1 | `components/1c-ninja-mcp/main.os` | doctor |
| 2.2 | `project-scaffold/cfe/NinjaLive` | doctor |
| 2.3 | Профиль `profile/profiles/1c-ninja-kit.yaml` | `kit verify` |

## 3. Профиль Cursor

| # | Действие | Примечание |
|---|----------|------------|
| 3.1 | Apply профиля `1c-ninja-kit` | v0.1: см. `adapters/cursor/install-profile.md` |
| 3.2 | User mcp **без** 1С-серверов | иначе дубли |
| 3.3 | Docs-patches vrunner (optional) | `profile/docs-patches/` |

## 4. Проект

| # | Спросить у человека | Записать в |
|---|---------------------|------------|
| 4.1 | ИБ (`ibconnection`) | `autumn-properties.json` (gitignore) |
| 4.2 | Логин/пароль ИБ | туда же + `NINJA_USER`/`NINJA_PASSWORD` в project mcp |
| 4.3 | Имя публикации (`APP_NAME`) | autumn `web.appName` + mcp `NINJA_URL` |
| 4.4 | Порт Apache | **8083** если 8.3, **8085** если 8.5 (`docs/stack-defaults.md`) |
| 4.5 | Пользователь хранилища CFE | `repository.json` (без пароля в git если возможно) |

Затем:

1. Скопировать `NinjaLive` → `src/cfe/NinjaLive`
2. `cfe_load` через vrunner
3. Опубликовать `/hs/ninja-live`
4. Проверить `live_version` / `live_extensions_list`
5. Hardlink rules из профиля (не junction)

## 5. Не копировать из ecoladev

- Живой `.cursor/mcp.json` с паролями
- Product `openspec/changes/*` (opv, screens)
- `.build` / кэши
- `autumn-properties.json` с секретами

## 6. Готово

- [ ] doctor без критичных FAIL по ninja-паре
- [ ] project mcp указывает на kit `components/1c-ninja-mcp`
- [ ] live list работает
- [ ] secrets не в git status

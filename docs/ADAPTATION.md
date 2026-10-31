# ADAPTATION — чеклист на месте

Агент проходит **по порядку**. Статусы: `ready` / `blocked` / `needs-human`.

## 1. Machine soft

| # | Проверка | Как | Кто |
|---|----------|-----|-----|
| 1.1 | OneScript + пакеты `autumn`, `autumn-mcp`, `sql`, `1connector` | `kit.ps1 doctor`; поставить `kit.ps1 deps -What oscript` | auto |
| 1.2 | Платформа 1cv8 (8.3/8.5) | doctor: `C:\Program Files\1cv8\*\bin` | needs-human (дистрибутив) |
| 1.3 | bsl-analyzer (лаунчер + app) | doctor; `kit.ps1 deps -What bsl-analyzer` → `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe`; app кладёт лаунчер (min 0.4.0) | auto |
| 1.4 | Apache 83/85 | doctor; `kit.ps1 deps -What apache` (ветка по установленной платформе, `-All` — обе) | auto |
| 1.5 | Ripgrep | doctor; `kit.ps1 deps -What ripgrep` → `%USERPROFILE%\tools\ripgrep` + PATH | auto |
| 1.6 | Node.js + Playwright + Chromium | doctor; `kit.ps1 deps -What web-test` (Node LTS portable, `npm ci` скилла, `playwright install chromium`) | auto |
| 1.7 | Toolkit EPF (optional) | doctor; `kit.ps1 deps -What toolkit` | auto |

Всё, кроме платформы 1С, ставит `kit.ps1 deps` (версии — latest с upstream, откуда брать —
`companions/pins.json`, фактическое состояние — `%LOCALAPPDATA%\1c-ninja-kit\deps-state.json`).
`wsap24.dll` для Apache берётся из bin установленной платформы — поэтому 1.2 обязателен.

## 2. Kit components

| # | Проверка | Как |
|---|----------|-----|
| 2.1 | `components/1c-ninja-mcp/main.os` | doctor |
| 2.2 | `project-scaffold/cfe/NinjaLive` | doctor |
| 2.3 | Профиль `profile/profiles/1c-ninja-kit.yaml` | `kit verify` |

## 3. Профиль OpenCode

| # | Действие | Примечание |
|---|----------|------------|
| 3.1 | Apply профиля `1c-ninja-kit` | OpenCode: `docs/opencode.md` |
| 3.2 | User mcp **без** 1С-серверов | иначе дубли |
| 3.3 | cc-1c-skills установлен | `install/cc-skills.ps1` (`db-list` в skills root) |

## 4. Проект

| # | Спросить у человека | Записать в |
|---|---------------------|------------|
| 4.1 | ИБ (запись базы) | `.v8-project.json` (gitignore) |
| 4.2 | Логин/пароль ИБ | туда же + `NINJA_USER`/`NINJA_PASSWORD` в project mcp |
| 4.3 | Имя публикации (`APP_NAME`) | `web.appName` в `.v8-project.json` + mcp `NINJA_URL` |
| 4.4 | Порт Apache | **8083** если 8.3, **8085** если 8.5 (`docs/stack-defaults.md`) |
| 4.5 | Пользователь хранилища CFE | `extensions[].repository` в `.v8-project.json` (gitignore) |

Затем:

1. Скопировать `NinjaLive` → `src/cfe/NinjaLive`
2. `db-load-xml -ConfigDir "src\cfe\NinjaLive" -Mode Full -Extension "NinjaLive" -UpdateDB`
3. Опубликовать `/hs/ninja-live`
4. Проверить `live_version` / `live_extensions_list`
5. Правила: глобальный `AGENTS.md` + `skills/kit/rules` (`kit.ps1 apply`)

## 5. Не копировать из ecoladev

- Живой `opencode.jsonc` с паролями
- `.build` / кэши
- `.v8-project.json` с секретами

## 6. Готово

- [ ] doctor без критичных FAIL по ninja-паре
- [ ] project mcp указывает на kit `components/1c-ninja-mcp`
- [ ] live list работает
- [ ] secrets не в git status

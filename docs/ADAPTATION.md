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
| 1.8 | Сервис задач PiPa (PithosPandoras) | `GET http://127.0.0.1:8787/health` → `ok`; версия — `& "$env:PIPA_HOME\pithos-pandoras.exe" --version` (у `/health` версии нет). Ставится не из кита | needs-human |

Всё, кроме платформы 1С и PiPa, ставит `kit.ps1 deps` (версии — latest с upstream, откуда брать —
`companions/pins.json`, фактическое состояние — `%LOCALAPPDATA%\1c-ninja-kit\deps-state.json`).
`wsap24.dll` для Apache берётся из bin установленной платформы — поэтому 1.2 обязателен.

### 1.8. Где PiPa на этой машине

Каталог сервиса у каждой установки свой. Его можно записать один раз в машинный
профиль — `pipa.home` в `install/path-defaults.windows.yaml` — тогда `kit.ps1
apply` сам поставит переменную `PIPA_HOME` (user env), как `NINJA_KIT_ROOT`:
переменной нет — создаст, расходится с профилем — напишет `[WARN]` и исправит.
В staged-копию путь не попадает: в тексте остаётся `$env:PIPA_HOME`.

Либо задай переменные руками (после `setx` перезапусти OpenCode — переменные
читаются при старте процесса):

| Переменная | Что | Пример |
|------------|-----|--------|
| `PIPA_HOME` | каталог сервиса (там exe, база и ключ) | `setx PIPA_HOME "<каталог сервиса>"` |
| `PIPA_URL` | адрес MCP | `setx PIPA_URL "http://127.0.0.1:8787/mcp"` |
| `PIPA_KEY_FILE` | файл ключа | `setx PIPA_KEY_FILE "%PIPA_HOME%\pithos-pandoras.key"` |
| `PIPA_KEY` | сам ключ (альтернатива файлу) | `setx PIPA_KEY "<ключ>"` |

Это рантайм-контракт агента: значения переменных читает скилл `skill-pipa` при
работе. Подстановка в `stage`/`apply` берёт адрес и файл ключа из
`install/path-defaults.windows.yaml` (`pipa.url`, `pipa.keyFile`), поэтому
`PIPA_URL`/`PIPA_KEY_FILE` в процессе копию не меняют.

Не заданы — агент ищет так: env → адрес из раздела «Сервис задач» в `AGENTS.md`
проекта → `GET /health` на `127.0.0.1:8787` → вопрос человеку. Угадывать
`PIPA_HOME` по букве диска нельзя.

## 2. Kit components

| # | Проверка | Как |
|---|----------|-----|
| 2.1 | `components/1c-ninja-mcp/main.os` | doctor |
| 2.2 | `project-scaffold/cfe/NinjaLive` | doctor |
| 2.3 | Профиль `profile/profiles/1c-ninja-kit.yaml` | `kit verify` |

## 3. Профиль OpenCode

| # | Действие | Примечание |
|---|----------|------------|
| 3.1 | Apply профиля `1c-ninja-kit` | OpenCode: `docs/opencode.md`. Ставит `NINJA_KIT_ROOT` и `PIPA_HOME` (user env) |
| 3.2 | User mcp **без** 1С-серверов | иначе дубли |
| 3.3 | cc-1c-skills установлен | `install/cc-skills.ps1` (`db-list` в skills root) |
| 3.4 | Корень внешних скиллов | дефолт `%USERPROFILE%\.config\opencode\skills`; другой каталог — `setx CC_SKILLS_ROOT "<каталог>"` (агент в рантайме) и та же строка в `ccSkills.skillsRoot` машинного профиля (для подстановки), затем `install/cc-skills.ps1 -SkillsRoot "<каталог>"` |
| 3.5 | `NINJA_KIT_ROOT` | корень кита; профиль подставляет его вместо `{{KIT_ROOT}}`. Ставит `kit.ps1 apply` сам (user env); вручную — `setx NINJA_KIT_ROOT "<корень кита>"`. Нет переменной — `stage` печатает `[FAIL]` и ничего не копирует; `apply` не падает, а ставит её из своего расположения (неверное значение исправляет с `[WARN]`). Новую переменную видят только процессы, запущенные после apply — перезапусти OpenCode и терминал |
| 3.6 | `pipa.home` | каталог PiPa в машинном профиле — значение по умолчанию для `PIPA_HOME` (шаг 1.8). `apply` ставит переменную, если её нет, и исправляет расхождение с `[WARN]` |
| 3.7 | `mcpPolicy.projectMcp` | имя файла проектного MCP-конфига для `{{PROJECT_MCP}}`: задано — берётся оно, пусто — `stage` смотрит фактический файл проекта (`opencode.jsonc`, иначе `opencode.json`), без корня — `opencode.jsonc`. В него `stage` пишет `instructions` |

Значения плейсхолдеров подстановка берёт из `install/path-defaults.windows.yaml`
(`ccSkills.skillsRoot`, `pipa.url`, `pipa.keyFile`, `pipa.home`,
`mcpPolicy.userMcp`, `mcpPolicy.projectMcp`). Из переменных процесса на копию
влияет только `NINJA_KIT_ROOT` (токен `{{KIT_ROOT}}`); `CC_SKILLS_ROOT`,
`PIPA_URL`, `PIPA_HOME`, `PIPA_KEY_FILE` (шаги 1.8 и 3.4) читает агент в
рантайме — `pipa.home` лишь наполняет `PIPA_HOME` через `apply`.

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
5. Правила и скиллы: `kit.ps1 stage -ProjectRoot <проект>` копирует их в `.opencode` проекта
   **с подстановкой плейсхолдеров** (`{{KIT_ROOT}}` → `$env:NINJA_KIT_ROOT` и т. п., см.
   `docs/MCP-PLACEHOLDERS.md`); агенты, команды и `run.ps1` копируются в `~/.config/opencode/`
   командой `apply`. Копия не байт-в-байт — `kit.ps1 verify -ProjectRoot <проект>` сверяет
   отрендеренный текст.

## 5. Не копировать из ecoladev

- Живой `opencode.jsonc` с паролями
- `.build` / кэши
- `.v8-project.json` с секретами

## 6. Готово

- [ ] doctor без критичных FAIL по ninja-паре
- [ ] project mcp указывает на kit `components/1c-ninja-mcp`
- [ ] live list работает
- [ ] secrets не в git status

# Placeholders

Два разных семейства. Путать их нельзя: у первого значения подставляет
`kit.ps1`, у второго — `env-setup.ps1` при инициализации проекта.

## 1. Пути профиля (`kit.ps1 stage` / `apply`)

`profile/**` не содержит путей с буквой диска: такие пути верны только на
машине автора. Машинные каталоги подставляются в копию при `stage` и `apply`.

**Из машинного профиля берутся ровно четыре ключа.** Подстановка
(`Get-PlaceholderMap` в `install/kit.ps1`) читает
`install/path-defaults.windows.yaml` только по ключам `ccSkills.skillsRoot`,
`pipa.url`, `pipa.keyFile`, `mcpPolicy.userMcp`. Остальные значения карты —
константы renderer'а или вычисление по слою. Других ключей YAML подстановка не
читает: ни `pipa.home`, ни `mcpPolicy.projectMcp` она не смотрит. От переменных
процесса подстановка не зависит: `CC_SKILLS_ROOT`, `PIPA_URL`, `PIPA_HOME`,
`PIPA_KEY_FILE` — это рантайм-контракт для агента (скилл читает их при работе),
а не вход `stage`/`apply`. Значит, в YAML настраиваются только каталоги из этих
четырёх ключей; каталог PiPa задаётся переменной `PIPA_HOME` на машине, а не в
профиле. Переменные нужны агенту во время работы, а не копированию.

| Плейсхолдер | Значение | Источник |
|-------------|----------|----------|
| `{{KIT_ROOT}}` | `$env:NINJA_KIT_ROOT` | `NINJA_KIT_ROOT` как токен: `stage` проверяет, что переменная есть. Нет — `stage` печатает `[FAIL]` и ничего не копирует. `apply` не падает: ставит переменную сам из своего расположения (user env), а если она указывала на другой каталог — пишет `[WARN]` и исправляет |
| `{{CC_SKILLS_ROOT}}` | `$env:USERPROFILE\.config\opencode\skills` | `ccSkills.skillsRoot`; env `CC_SKILLS_ROOT` — рантайм-контракт агента, на подстановку не влияет |
| `{{SKILLS_ROOT}}` | в проекте — `.opencode/skills`; глобально — `$env:USERPROFILE\.config\opencode\skills` | вычисляется по слою |
| `{{AGENTS_ROOT}}` | `$env:USERPROFILE\.config\opencode\agents` | вычисляется |
| `{{COMMANDS_ROOT}}` | `$env:USERPROFILE\.config\opencode\commands` | вычисляется |
| `{{USER_MCP}}` | `$env:USERPROFILE\.config\opencode\opencode.json(c)` | `mcpPolicy.userMcp` |
| `{{PROJECT_MCP}}` | `opencode.jsonc` | константа: `opencode.jsonc` в корне проекта; ключ `mcpPolicy.projectMcp` renderer не читает |
| `{{PIPA_URL}}` | `http://127.0.0.1:8787/mcp` | `pipa.url`; env `PIPA_URL` — рантайм-контракт, на подстановку не влияет |
| `{{PIPA_HOME}}` | `$env:PIPA_HOME` | рантайм: env `PIPA_HOME` (в текст подставляется `$env:PIPA_HOME`); ключ `pipa.home` renderer не читает |
| `{{PIPA_KEY_FILE}}` | `$env:PIPA_HOME\pithos-pandoras.key` | `pipa.keyFile`; env `PIPA_KEY_FILE` — рантайм-контракт, на подстановку не влияет |

Правило значения: **env-форма (`$env:VAR`) или относительный путь**. Литеральный
`C:\…` в подстановке нарушил бы переносимость копии и линт `kit.ps1 verify`.
`%VAR%` из YAML превращается в `$env:VAR` — в PowerShell `%VAR%` не раскрывается.

Неизвестные `{{…}}` renderer не трогает: опечатка в имени плейсхолдера
останется в копии как есть, её видно глазами.

## 2. Шаблоны нового проекта (`env-setup.ps1`)

`profile/skills/skill-env-setup/scripts/templates/`:

- `{{NINJA_MAIN}}` = `<kit>\components\1c-ninja-mcp\main.os`
- `{{SHCNTX_HELP_DB}}` = `<kit>\components\1c-ninja-mcp\src\data\shcntx_help.db`
- `{{WEB_PORT}}` = 8083 (platform 8.3) or 8085 (platform 8.5)
- `{{BSL_ANALYZER_EXE}}` = launcher `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` (`bsl-analyzer-reference`)
- `{{BSL_ANALYZER_APP_EXE}}` = `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe`
  (`bsl-analyzer-workspace`; launcher не используется — его Windows Job убивает broker-backend)
- `{{PROJECT_ROOT}}`, `{{APP_NAME}}`, `{{IB_USER}}`, `{{IB_PASSWORD}}` — project MCP
- `{{PROJECT_NAME}}`, `{{V8_VERSION}}`, `{{IB_CONNECTION}}` — project `AGENTS.md`

Если добавить имя из этого семейства в `$script:KitPlaceholderNames` в
`install/kit.ps1`, `stage` развернёт шаблон раньше `env-setup` и создание нового
проекта сломается молча.

See `docs/stack-defaults.md`.

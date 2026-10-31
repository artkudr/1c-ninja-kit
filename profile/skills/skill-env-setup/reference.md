# skill-env-setup — справочник

## Имя и синоним

| | |
|--|--|
| Канон | `skill-env-setup` |
| Slash | `/skill-env-setup` |
| Основной синоним | **разверни окружение** |

## ibases.v8i

Путь по умолчанию: `%APPDATA%\1C\1CEStart\ibases.v8i` (часто UTF-16 LE).

Секции `[ИмяБазы]`, поля:

- `Connect=File="…"` или `Connect=Srvr="…";Ref="…"`
- `ID=`, `Order=`

Скрипт `read-ibases.ps1` проверяет файловые базы по наличию `1Cv8.1CD`. Серверные — только формат строки.

Преобразование в запись базы `.v8-project.json`:

- file → `"type": "file"`, `"path": "C:\\Bases\\MyDb"`
- server → `"type": "server"`, `"server": "srv"`, `"ref": "base"`

## .v8-project.json

```jsonc
{
  "v8path": "C:\\Program Files\\1cv8\\8.3.27.2130\\bin",
  "databases": [
    {
      "id": "main",
      "name": "<appName>",
      "type": "file",
      "path": "C:\\Bases\\MyDb",
      "user": "…",
      "password": "…",
      "configSrc": "src\\cf",
      "extensions": [
        {
          "name": "…",
          "src": "src\\cfe\\…",
          "repository": { "path": "Z:\\Хранилища\\…", "user": "…", "password": "", "adminUser": "Администратор" }
        }
      ]
    }
  ],
  "default": "main",
  "web": { "appName": "<appName>", "port": 8083 }
}
```

- Платформа: `v8path` — каталог bin, **полная** сборка (напр. `8.3.27.2130`, не просто `8.3`). Скрипты берут её для всех операций; если не задана — авто-определение старшей установленной.
- Секреты (`user` / `password`, `repository.*`) — файл в `.gitignore`.
- `web` — публикация: `appName`, `port` (8083/8085 по платформе), опционально `apachePath`.
- Список расширений ИБ — **не** через Предприятие (см. ниже).

## Расширения и хранилища

`sync-cfe.ps1` добавляет отсутствующие имена в `databases[0].extensions[]` как `{ name, src }` (1:1; исключения вроде `Компания_API_REST` → `API_REST` правит человек). Существующие записи (в т.ч. с `repository`) не трогаются. Без `-Prune` лишние имена не удаляются. `NinjaLive` в реестр расширений **не** добавляется (bootstrap live, вне хранилища).

Хранилище расширения — `extensions[].repository`: `path` (каталог хранилища), `user` / `password` (пользователь хранилища), `adminUser` (для `db-repo add-user`). Реквизиты подставляет `skill-repo-workflow` / `db-repo` из записи реестра.

## Project MCP

Эталон текста — шаблон скилла `scripts/templates/opencode.jsonc.tpl`. Setup **никогда** не копирует и не мержит user-конфиг.

| Файл | Git |
|------|-----|
| `opencode.jsonc` | нет (секреты + `--source-dir` и `--cache-dir` этой папки) |

Полный состав project MCP (все 1С-серверы здесь, не в user):

1. `1c-ninja-mcp` — `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` **этой** ИБ (`…/hs/ninja-live`, CFE `NinjaLive`)
2. `bsl-analyzer-reference` — справка платформы (без `--source-dir`)
3. `bsl-analyzer-workspace` — `--source-dir` = абсолютный путь **этой** папки, `--cache-dir` = `<эта папка>\.build` (кеш графа и поиска в проекте, `.build` в gitignore), `--mode broker`, запуск из `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe` (не из лаунчера: его Windows Job убивает backend вместе с прокси, #345), env `BSL_MCP_IDLE_TTL_SECS` / `BSL_MCP_ORPHAN_GRACE_SECS` = 86400
4. `v8std` — `https://ai.v8std.ru/mcp` (стандарты ITS/v8, streamable-http)
5. `1c-mcp-toolkit` — `http://127.0.0.1:6003/mcp` (fallback live, по умолчанию disabled)

User-конфиг (`~/.config/opencode/opencode.json(c)`) — **без** этих имён. Live-URL в user класть нельзя (чужая ИБ в другом чате).

## bsl-analyzer.toml

`[source] root = "src/cf"`, `extensions = ["src/cfe/*"]`. EPF/ERF (анализатор ≥0.2.77): omit `externals` → auto `src/epf/*`, `src/erf/*` (**nested**: `src/epf/<Name>/<Name>.xml` + `src/epf/<Name>/<Name>/`); явный список — `externals = [{ name, path, depends_on? }]` (path = каталог с одним `<Name>.xml` рядом с `<Name>/`; строки-glob `"src/epf/*"` в toml невалидны). Scaffold: `epf-init` / `erf-init` пишут nested. Кеш: `<проект>\.build` (`--cache-dir` в project MCP; gitignore).

## Каркас каталогов

```
src/cf, src/cfe, src/epf/<Имя>/…, src/erf/<Имя>/…
build/out/syntax-check/{junit,allure}
build/out/{cfe,epf,erf}

tools/syntax-check-excludes.txt
tools/web-test/smoke.config.json
tools/web-test/scenarios/{after-load,manual}
AGENTS.md            # память проекта: правила + невыводимые факты
.ignore              # ripgrep: артефакты и vendor вне поиска (работает без .git)
docs/dev-stack.md
```

Правила: always-on — глобальный `~/.config/opencode/AGENTS.md`, on-demand — `~/.config/opencode/skills/kit/rules/` (обновляет `kit.ps1 apply`). В проекте создаётся только корневой `AGENTS.md` — память проекта, не копия глобальных правил; setup его не перезаписывает.

## Память проекта (`AGENTS.md`)

- Назначение: короткие правила и невыводимые факты, которые нужны в каждой сессии. OpenCode загружает файл автоматически.
- Шаблон: `scripts/templates/AGENTS.md.tpl`; подстановки — `{{PROJECT_NAME}}`, `{{APP_NAME}}`, `{{PROJECT_ROOT}}`, `{{WEB_PORT}}`, `{{V8_VERSION}}`, `{{IB_CONNECTION}}`.
- Критерии записи: невыводимо из кода/конфигов/docs, стабильно, меняет поведение, не дублирует глобальные правила и `docs/`.
- Лимит — ~100 строк. Детали и runbook — в `docs/<тема>.md`, состояние — в `handoffs/`, история решений — в `docs/decisions.md`.

## Bootstrap NinjaLive и список расширений ИБ (главный способ)

**Не** запускать Предприятие для списка CFE.

Порядок:

1. Init копирует `src/cfe/NinjaLive` с эталона: SourceProject `src/cfe/NinjaLive`, иначе kit `project-scaffold/cfe/NinjaLive` (поиск через `NINJA_KIT_ROOT` / `C:\1C\projects\1c-ninja-kit`), иначе соседний проект.
2. Проверка входа = загрузка bootstrap: `db-load-xml -ConfigDir "src\cfe\NinjaLive" -Mode Full -Extension "NinjaLive"` + `db-cfe-admin set-properties -Name NinjaLive -Active on -SafeMode off`. Auth-ошибка → не оставлять битый пароль в `.v8-project.json`.
3. `skill-web-publish`. Project mcp: `NINJA_URL=…/hs/ninja-live`.
4. Smoke: `live_version`. **Список ИБ:** `live_extensions_list`.
5. Папки: `sync-cfe.ps1 -ProjectRoot . -ExtensionNames @(…)`. Скрипт **по умолчанию не** дергает Предприятие.

`NinjaLive` не класть в `extensions[]` с `repository` — bootstrap, вне хранилища.

## Check на эталоне

Отчёт `-Mode Check -ProjectRoot <папка>` проверяет:

- `1cv8` — платформа найдена; `cc-1c-skills` — `db-list` в skills root
- `bsl-analyzer.exe` — на месте
- каталоги src/*, tools/web-test, docs — ok
- `.v8-project.json`, `bsl-analyzer.toml`, mcp files — ok / skip exists
- `.gitignore` — required entries present
- `read-ibases.ps1` — читает `%APPDATA%\1C\1CEStart\ibases.v8i` (таблица баз)
- `sync-cfe.ps1 -DryRun` — fallback `.v8-project.json` + src/cfe работает (без Предприятия)
- `src/cfe/NinjaLive` — эталон на месте; Init в чужую папку копирует отсюда

`tools/syntax-check-excludes.txt` может отсутствовать — Check покажет `would-create`.

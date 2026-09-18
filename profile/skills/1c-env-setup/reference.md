# 1c-env-setup — справочник

## Имя и синоним

| | |
|--|--|
| Канон | `1c-env-setup` |
| Slash | `/1c-env-setup` |
| Основной синоним | **разверни окружение** |

## ibases.v8i

Путь по умолчанию: `%APPDATA%\1C\1CEStart\ibases.v8i` (часто UTF-16 LE).

Секции `[ИмяБазы]`, поля:

- `Connect=File="…"` или `Connect=Srvr="…";Ref="…"`
- `ID=`, `Order=`

Скрипт `read-ibases.ps1` проверяет файловые базы по наличию `1Cv8.1CD`. Серверные — только формат строки.

Преобразование в `ibconnection` vrunner:

- file → `/F"C:\Bases\MyDb"`
- server → `/S"server/ref"` (в JSON autumn часто пишут `/Sserver\ref` без кавычек — допустимо оба; скрипт пишет с кавычками в шаблоне)

## autumn-properties.json

Секция `vrunner`: `ibconnection`, `db-user`, `db-pwd`, `v8version`, `validate.syntax-check.*`.

Для `cfe_load` / Designer-операций предпочтительна **полная** сборка платформы в `v8version` (например `8.3.27.2130`), не только `8.3`. Список расширений ИБ — **не** через `vrunner infobase extensions list` (см. ниже).

## repository.json

```json
{
  "root": "Z:\\Экола\\Хранилища",
  "user": "ИмяВХранилище",
  "adminUser": "Администратор",
  "cfe": {
    "ИмяРасширенияВИб": "ПапкаХранилища"
  }
}
```

`sync-cfe.ps1` добавляет отсутствующие ключи как 1:1 (`Имя` → `Имя`). Исключения вроде `Экола_API_REST` → `API_REST` правит человек. Без `-Prune` лишние ключи не удаляются. `NinjaLive` в `cfe` **не** добавлять (не хранилище; bootstrap live).

## Project MCP

Эталон текста — шаблон скилла `scripts/templates/mcp.json.example.tpl`. Setup **никогда** не копирует и не мержит `%USERPROFILE%\.cursor\mcp.json`.

| Файл | Git |
|------|-----|
| `.cursor/mcp.json.example` | да (плейсхолдеры; тот же состав, что рабочий файл) |
| `.cursor/mcp.json` | нет (секреты + `--source-dir` этой папки) |

Полный состав project MCP (все 1С-серверы здесь, не в user):

1. `vrunner` — `vrunner-mcp.bat` с этой машины
2. `1c-mcp-toolkit` — `http://127.0.0.1:6003/mcp` (fallback live)
3. `1c-ninja-mcp` — `NINJA_URL` / `NINJA_USER` / `NINJA_PASSWORD` **этой** ИБ (`…/hs/ninja-live`, CFE `NinjaLive`)
4. `bsl-analyzer-reference` — справка платформы (без `--source-dir`)
5. `bsl-analyzer-workspace` — `--source-dir` = абсолютный путь **этой** папки

User MCP (`%USERPROFILE%\.cursor\mcp.json`) — **без** этих имён (`mcpServers: {}`). Cursor читает user **и** project: одинаковое имя сервера = дубль в агенте. Live-URL в user класть нельзя (чужая ИБ в другом чате).

## bsl-analyzer.toml

`[source] root = "src/cf"`, `extensions = ["src/cfe/*"]`. EPF/ERF (анализатор ≥0.2.77): omit `externals` → auto `src/epf/*`, `src/erf/*` (**nested**: `src/epf/<Name>/<Name>.xml` + `src/epf/<Name>/<Name>/`); явный список — `externals = [{ name, path, depends_on? }]` (path = каталог с одним `<Name>.xml` рядом с `<Name>/`; строки-glob `"src/epf/*"` в toml невалидны). Scaffold: `epf-init` / `erf-init` пишут nested. Кеш: `<проект>\.build` (gitignore).

## Каркас каталогов

```
src/cf, src/cfe, src/epf/<Имя>/…, src/erf/<Имя>/…
build/out/syntax-check/{junit,allure}
build/out/{epf,erf}

tools/syntax-check-excludes.txt
tools/web-test/smoke.config.json
tools/web-test/scenarios/{after-load,manual}
docs/dev-stack.md

.cursor/commands/opsx-{propose,apply,archive,explore}.md
openspec/{README.md,config.yaml,project.md,templates/,specs/,changes/archive/}
```

### OpenSpec scaffold

Setup разворачивает из шаблонов скилла (`scripts/templates/openspec/`, `scripts/templates/cursor-commands/`):

| Путь | Источник | Refresh без `-Force` |
|------|----------|----------------------|
| `.cursor/commands/opsx-*.md` | шаблоны скилла | skip if exists |
| `openspec/README.md`, `specs/README.md`, `changes/README.md` | шаблоны скилла | skip if exists |
| `openspec/templates/*.md` | шаблоны скилла | skip if exists |
| `openspec/config.yaml`, `openspec/project.md` | tpl с `{{PROJECT_NAME}}`, `{{COMPAT_MODE}}` | skip if exists |
| `openspec/changes/<name>/` (живые) | **только вручную / агентом** | **никогда** не копировать из SourceProject |
| `openspec/specs/<domain>/spec.md` | после archive | **никогда** не копировать из SourceProject |

`COMPAT_MODE` читается из `src/cf/Configuration.xml` при наличии; иначе `Version8_3_27`.

Канон правил — `%USERPROFILE%\.cursor\rules\`. Cursor применяет только project `.cursor/rules/*.mdc` (файлы). Setup **не** ставит folder junction (`/J` ≠ file symlink; `/J` не требует Developer Mode, но Cursor его плохо ест). Порядок: file symlink → **hardlink** `mklink /H` (канон на том же томе) → копия только другой диск. Править любой из двух путей hardlink. В git — gitignore.

## Bootstrap NinjaLive и список расширений ИБ (главный способ)

**Не** запускать Предприятие (`vrunner infobase extensions list` / MCP `extensions_list`) для списка CFE.

Порядок:

1. Init копирует `src/cfe/NinjaLive` с эталона: SourceProject `src/cfe/NinjaLive`, иначе `C:\1C\projects\ecoladev\src\cfe\NinjaLive`.
2. Проверка входа = загрузка bootstrap: MCP vrunner `cfe_load` `SRC=./src/cfe/NinjaLive` `extension-name=NinjaLive` `active=true` `safe-mode=false`. Auth-ошибка → не оставлять битый пароль в `autumn-properties.json`.
3. `web-publish` с `publishExtensionsByDefault`. Project mcp: `NINJA_URL=…/hs/ninja-live`.
4. Smoke: `live_version`. **Список ИБ:** `live_extensions_list`.
5. Папки: `sync-cfe.ps1 -ProjectRoot . -ExtensionNames @(…)`. Скрипт **по умолчанию не** дергает Предприятие. Устаревший `-UseVrunnerList` — только если live недоступен.

`NinjaLive` не класть в `repository.json` → `cfe`.

## Check на эталоне (ecoladev)

Проверено 2026-08-29 (`-Mode Check -ProjectRoot C:\1C\projects\ecoladev`):

- `vrunner` ok (`3.0.0_beta`)
- `bsl-analyzer.exe` ok
- каталоги src/*, tools/web-test, docs — ok; `.cursor/rules` — обычная папка, `.mdc` из канона (hardlink `/H`; не `/J`)
- `autumn-properties.json`, `repository.json`, `bsl-analyzer.toml`, mcp files — ok/skip exists
- `.gitignore` — required entries present
- `read-ibases.ps1` — читает `%APPDATA%\1C\1CEStart\ibases.v8i` (таблица баз)
- `sync-cfe.ps1 -SkipIb -DryRun` — fallback repository + src/cfe работает (без Предприятия)
- `src/cfe/NinjaLive` — эталон на месте; Init в чужую папку копирует отсюда

`tools/syntax-check-excludes.txt` на ecoladev может отсутствовать — Check покажет `would-create`.

OpenSpec: Check/Refresh добавляют `.cursor/commands/opsx-*.md` и недостающие шаблоны `openspec/`; живые `openspec/changes/*` и `config.yaml`/`project.md` без `-Force` не затираются.

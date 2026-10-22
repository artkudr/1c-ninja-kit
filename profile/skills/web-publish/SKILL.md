---
name: web-publish
description: Публикация информационной базы 1С через Apache. Используй когда пользователь просит опубликовать базу, сервисы, настроить веб-доступ, веб-клиент, открыть в браузере
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
---

# /web-publish — Публикация 1С через профильный Apache

Apache **не в проекте**. Два профиля на машине:

| `v8version` | Каталог | Порт |
|-------------|---------|------|
| `8.3*` | `%USERPROFILE%\tools\apache-83` | **8083** |
| `8.5*` | `%USERPROFILE%\tools\apache-85` | **8085** |

В воркспейсе — только `.v8-project.json` (`v8path` → платформа, `web.appName`, опционально `web.port` / `web.apachePath`) и `smoke.config.json` → `webUrl`.

Скрипт сам: резолвит bin платформы по `v8version`, пишет publish в профильный Apache, поднимает httpd.

**Не выдумывай AppName.** Не копируй Apache в `tools/` проекта.

## Параметры из проекта

1. `.v8-project.json`: запись базы (`path` / `server`+`ref`, `user`, `password`) → `-InfoBasePath` / `-InfoBaseServer`+`-Ref`; платформа — `v8path`.
2. Стабильный `web.appName` (и `webUrl` в smoke с тем же path, портом 8083/8085 и локалью **`/ru_RU/`**).
3. Реестр PT не используем.

```powershell
powershell.exe -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/web-publish.ps1" `
  -InfoBaseServer "k-server" -InfoBaseRef "my-ib-ref" `
  -UserName "..." -Password "..."
```

`-V8Path` / `-AppName` / `-Port` / `-ApachePath` — только оверрайды.

### Фрагмент `.v8-project.json`

```jsonc
"v8path": "C:\\Program Files\\1cv8\\8.3.27.2130\\bin",
"web": {
  "appName": "<appName>",
  "port": 8083
}
```

Для 8.5: `"v8path": "C:\\Program Files\\1cv8\\8.5.1.1343\\bin"`, `"port": 8085`, smoke `http://localhost:8085/<appName>/ru_RU/`.

## Локаль веб-клиента

По умолчанию — **русский**: `…/<appName>/ru_RU/`.

- В `tools/web-test/smoke.config.json` → `webUrl` всегда с `/ru_RU/` (явный `/en_US/` и т.п. не переписывать).
- HTTP-сервисы / OData / MCP (`…/hs/…`) — **без** сегмента локали.
- В `default.vrd` параметра языка нет: локаль задаётся URL (или `Accept-Language` браузера).

## После выполнения

URL веб-клиента: `http://localhost:{8083|8085}/{appName}/ru_RU/` — сверь smoke `webUrl`. MCP live URL — без локали (`…/hs/ninja-live`). Список расширений ИБ после публикации — `live_extensions_list` (NinjaLive уже в ИБ), не запуск Предприятия.

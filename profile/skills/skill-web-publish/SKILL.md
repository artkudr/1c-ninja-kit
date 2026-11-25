---
name: skill-web-publish
description: Публикация информационной базы 1С через Apache. Используй когда пользователь просит опубликовать базу, сервисы, настроить веб-доступ, веб-клиент, открыть в браузере
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
---

# /skill-web-publish — Публикация 1С через профильный Apache

Apache **не в проекте**. Два профиля на машине:

| `v8version` | Каталог | Порт |
|-------------|---------|------|
| `8.3*` | `%USERPROFILE%\tools\apache-83` | **8083** |
| `8.5*` | `%USERPROFILE%\tools\apache-85` | **8085** |

В воркспейсе — только `.v8-project.json` (`v8path` → платформа, `web.appName`, опционально `web.port` / `web.apachePath`) и `smoke.config.json` → `webUrl`.

Скрипт сам: резолвит bin платформы по `v8version`, пишет publish в профильный Apache, поднимает httpd.

`web.apachePath` может указывать на копию дерева Apache (temp-контур, второй порт):
скрипт привязывает `Define SRVROOT` / `ServerRoot` и абсолютные пути pid/log к этой
копии, поэтому рабочая установка не затрагивается — копия пишет свой
`logs/httpd.pid` и `logs/error_log`.

**Не выдумывай AppName.** Не копируй Apache в `tools/` проекта.

## Параметры из проекта

1. `.v8-project.json`: запись базы (`path` / `server`+`ref`, `user`, `password`) → `-InfoBasePath` / `-InfoBaseServer`+`-Ref`; платформа — `v8path`.
2. Стабильный `web.appName` (и `webUrl` в smoke с тем же path, портом 8083/8085 и локалью **`/ru_RU/`**).
3. Реестр PT не используем.

```powershell
powershell.exe -NoProfile -File "{{KIT_ROOT}}\profile\skills/skill-web-publish/scripts/web-publish.ps1" `
  -InfoBaseServer "k-server" -InfoBaseRef "my-ib-ref" `
  -UserName "..." -Password "..."
```

`-V8Path` / `-AppName` / `-Port` / `-ApachePath` — только оверрайды.

### Фрагмент `.v8-project.json`

```jsonc
"v8path": "%ProgramFiles%\\1cv8\\<версия>\\bin",
"web": {
  "appName": "<appName>",
  "port": 8083
}
```

Для 8.5: `"v8path": "%ProgramFiles%\\1cv8\\8.5.1.1343\\bin"`, `"port": 8085`, smoke `http://localhost:8085/<appName>/ru_RU/`.

## Пул сеансов HTTP-сервисов

Без пула каждый вызов HTTP-сервиса открывает новый сеанс: аутентификация,
загрузка конфигурации и расширений. Пул убирает этот старт — на devtools серия
из 10 `live_query` ускорилась с ~330 до ~110 мс, новых сеансов 0.

Пул включается per-service элементом `<service>` в `default.vrd`:

```xml
<httpServices publishByDefault="true" publishExtensionsByDefault="true">
    <service name="NinjaLive_Сервис" rootUrl="ninja-live" enable="true"
             reuseSessions="autouse" sessionMaxAge="20" poolSize="4" poolTimeout="5"/>
</httpServices>
```

Сервисы — `web.poolServices` в `.v8-project.json` (или `-PoolServices`):

```jsonc
"web": {
  "appName": "devtools",
  "port": 8085,
  "poolServices": [
    { "name": "NinjaLive_Сервис", "rootUrl": "ninja-live" }
  ],
  "poolSessionMaxAge": 20,   // необязательно
  "poolSize": 4,             // необязательно
  "poolTimeout": 5           // необязательно
}
```

### Формат `-PoolServices`

Элемент — `Имя=rootUrl`. Строка с разделителями `,` / `;` работает в обеих
версиях скрипта; как передать несколько элементов, зависит от версии: в
PowerShell это строка или массив, в Python — строка или повтор параметра.

PowerShell (`web-publish.ps1`) — строка или массив; повтора параметра нет:

```powershell
# строка: элементы через ',' или ';'
-PoolServices "NinjaLive_Сервис=ninja-live,Второй_Сервис=second"

# массив
-PoolServices @("NinjaLive_Сервис=ninja-live", "Второй_Сервис=second")
```

Python (`web-publish.py`) — та же строка или повтор параметра:

```bash
python web-publish.py ... -PoolServices "NinjaLive_Сервис=ninja-live" -PoolServices "Второй_Сервис=second"
```

Повтора параметра в PowerShell **нет и быть не может**: повтор именованного
параметра запрещён языком, `-PoolServices "A=a" -PoolServices "B=b"` падает с
`параметр 'PoolServices' указан более одного раза` и кодом 1 ещё до разбора
входа — даже для `[string[]]`. Два сервиса в PowerShell задаются массивом или
строкой с разделителем.

Строка без `=` (`"A"`), пустое имя (`"=a"`), пустой `rootUrl` (`"A="`) и пустая
строка — ошибка входа: скрипт печатает `Error: PoolServices: …` и выходит с кодом 1.
Молча испорченный `rootUrl` не публикуется: платформа сверяет его с сервисом и
не применяет пул. `web.poolServices` в `.v8-project.json` принимает те же строки
и объекты `{ "name", "rootUrl" }`.

`rootUrl` обязателен и должен совпадать с корневым URL сервиса в метаданных.
Без него vrd валиден и сервис отвечает, но платформа пул не применяет —
проверено замером: 10 `live_query` дали 10 стартов сеансов. Корневой URL
виден в метаданных сервиса (`RootUrl`) или в URL `/hs/<rootUrl>/`.

`publishByDefault="true"` сохраняется: перечисленные сервисы получают пул,
остальные публикуются как раньше. Пустой список — в vrd нет `<service>`,
публикация остаётся валидной. Имена не выдумывать: только сервисы, реально
существующие в базе (конфигурация или подключённое расширение).

Семантика:

- `sessionMaxAge` — секунды **простоя** сеанса пула до замены (не общее время жизни);
- `poolSize` — сколько сеансов держать в пуле;
- `poolTimeout` — сколько секунд ждать свободный сеанс из пула;
- `reuseSessions="autouse"` — сеансом управляет сервер, клиенту ничего хранить не нужно. `use` требует от клиента идентификатор сеанса: MCP-клиент и обычный HTTP получают 400;
- атрибуты допустимы только на `<service>`. На `<httpServices>` платформа 8.5 отвергает vrd: «Ошибка преобразования данных XDTO: НачалоСвойства: reuseSessions».

`default.vrd` читается при создании сеанса, перезапуск Apache ради правки не
нужен. Настройка живёт только в файле публикации: переопубликация из
Конфигуратора или `webinst` её снимет, поэтому шаблон и `web.poolServices`
держат её при повторном `web-publish`.

После загрузки новой версии расширения в ИБ публикацию нужно перезапустить:
пул держит сеансы со старым кодом, `live_*` до перезапуска отвечают старым
кодом. Пауза не помогает — см. `skill-repo-workflow`.

## Локаль веб-клиента

По умолчанию — **русский**: `…/<appName>/ru_RU/`.

- В `tools/web-test/smoke.config.json` → `webUrl` всегда с `/ru_RU/` (явный `/en_US/` и т.п. не переписывать).
- HTTP-сервисы / OData / MCP (`…/hs/…`) — **без** сегмента локали.
- В `default.vrd` параметра языка нет: локаль задаётся URL (или `Accept-Language` браузера).

## После выполнения

URL веб-клиента: `http://localhost:{8083|8085}/{appName}/ru_RU/` — сверь smoke `webUrl`. MCP live URL — без локали (`…/hs/ninja-live`). Список расширений ИБ после публикации — `live_extensions_list` (NinjaLive уже в ИБ), не запуск Предприятия.

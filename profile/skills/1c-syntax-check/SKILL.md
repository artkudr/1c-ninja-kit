---
name: 1c-syntax-check
description: >-
  Синтаксический контроль конфигурации 1С платформой (DESIGNER /CheckConfig).
  Используй после правок BSL в src/cf (основная конфигурация) и как гейт перед загрузкой.
  Режимы проверки и файл исключений — из .v8-project.json (validate.syntax-check).
  Для расширений — скилл db-cfe-admin check.
argument-hint: "[-Extension <Имя>] [-Modes <список>] [-ExceptionFile <путь>]"
---

# /1c-syntax-check — синтаксический контроль конфигурации

Обёртка платформенной проверки `1cv8 DESIGNER /CheckConfig` для **основной конфигурации** (`src/cf`). Расширения проверяет `db-cfe-admin check` (применимость + модули) — этот скилл нужен, когда менялись модули самой конфигурации.

## Параметры подключения

Из `.v8-project.json` проекта (скилл `1c-project-context`): `v8path` и запись базы (по умолчанию — `default`). Явные параметры (`-InfoBasePath` / `-InfoBaseServer` + `-InfoBaseRef`, `-UserName`, `-Password`) сильнее реестра.

Режимы и исключения — из реестра:

```jsonc
"validate": {
  "syntax-check": {
    "mode": ["ExtendedModulesCheck", "ThinClient", "WebClient", "Server", "ExternalConnection", "ThickClientOrdinaryApplication"],
    "exceptionFile": "tools/syntax-check-excludes.txt"
  }
}
```

- Без `mode` — дефолт: `ExtendedModulesCheck, ThinClient, WebClient, Server, ExternalConnection, ThickClientOrdinaryApplication`.
- `exceptionFile` — текстовый файл, по подстроке на строку; строки лога, содержащие любую из подстрок, не считаются ошибками. Отсутствует — проверка идёт без исключений.

## Команда

```powershell
powershell.exe -NoProfile -File "{{SKILLS_ROOT}}\1c-syntax-check\scripts\syntax-check.ps1"
```

### Параметры скрипта

| Параметр | Обязательный | Описание |
|----------|:------------:|----------|
| `-ProjectRoot <путь>` | нет | Корень проекта (по умолчанию — текущий каталог; реестр ищется вверх) |
| `-Extension <имя>` | нет | Проверить расширение (обычно не нужно — есть `db-cfe-admin check`) |
| `-Modes <список>` | нет | Оверрайд режимов через запятую |
| `-ExceptionFile <путь>` | нет | Оверрайд файла исключений |
| `-V8Path <путь>` | нет | Каталог bin платформы (иначе `v8path` реестра / авто-определение) |
| `-InfoBasePath` / `-InfoBaseServer` + `-InfoBaseRef` | нет | Явное подключение вместо записи реестра |
| `-UserName <имя>` / `-Password <пароль>` | нет | Пользователь ИБ |

## Результат

- Полный лог платформы печатается; строки-ошибки (после фильтра исключений) — сводкой.
- Код возврата: `0` — ошибок нет; `1` — есть ошибки (или сбой запуска).
- Для баз под хранилищем ключи `ConfigurationRepository*` подставляются из записи реестра.

## Связанные скиллы

- `db-cfe-admin check` — применимость и модули расширений (после load CFE).
- `db-load-xml` / `db-update` — загрузка правок в ИБ (гейт — до/после по `1c-development-process`).
- `repo-workflow` — полный цикл расширения с хранилищем.

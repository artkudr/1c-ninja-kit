# PiPa: справочник

Рабочая выжимка контракта MCP. При расхождении прав сервис, а не этот файл.
Полная схема — `docs/Сервис-задач-архитектура.md` в репозитории сервиса.

## Подключение

| Что | Значение |
|---|---|
| Адрес MCP | `http://127.0.0.1:8787/mcp` |
| Транспорт | Streamable HTTP, stateless, ответ JSON |
| Заголовок | `Authorization: Bearer <ключ>` |
| Ключ | файл `pithos-pandoras.key` рядом с базой; создаётся при первом `serve` |
| Порт | `PITHOS_PORT`, по умолчанию `8787` |
| Проверка | `GET /health` → `ok` |

Сервис поднимается вместе с приложением или треем. Имя проекта агент берёт
только из `AGENTS.md`; инструмента «покажи все проекты» у агента нет.

## Где взять сервис

- Репозиторий — `https://github.com/artkudr/pithos-pandoras`, сборки —
  `https://github.com/artkudr/pithos-pandoras/releases`. Разработка идёт на
  машине разработки; здесь сервис только работает.
- Сборка — только Releases: `pithos-pandoras-<версия>-windows-x64.zip`. Внутри
  два exe (сервис и трей), иконка, скрипт автозапуска и `docs/УСТАНОВКА.md`.
  Rust для установки не нужен: exe самодостаточны.
- Первый запуск: распаковать в постоянную папку, `pithos-pandoras.exe init
  --project <проект> --root .`, затем `pithos-pandoras-tray.exe`. Ключ печатает
  `pithos-pandoras.exe key`.
- Обновление: остановить трей, сделать копию базы (`pithos-pandoras.exe backup`),
  заменить exe из нового zip, запустить снова. База мигрирует вперёд сама.
- Полная документация — `docs/` репозитория: `УСТАНОВКА.md`,
  `Сервис-задач-архитектура.md`, `РАЗРАБОТКА.md`.

В OpenCode инструменты MCP получают префикс сервера: `pipa_task_create` или
в Code Mode — `tools.pipa.task_create`. Ниже имена без префикса.

## Инструменты

| Инструмент | Обязательные поля | Что делает |
|---|---|---|
| `project_get` | `project` | проект, роли, статусы, `config_json` |
| `task_create` | `project`, `role`, `title`, `statement`; `route?`, `resource?` | номер, папка, статус |
| `task_list` | `project` | список задач проекта |
| `task_get` | `project`, `task` | карточка: этап, отчёты, черновики, файлы, `folder_path`, предупреждения |
| `task_update` | `project`, `task`, `role`; `title?`, `statement?` | правка названия или постановки |
| `task_next` | `project`, `task` | механическая подсказка, что дальше |
| `task_set_status` | `project`, `task`, `role`, `status` | смена статуса |
| `stage_start` | `project`, `task`, `role` | открывает этап, отдаёт входы; повтор той же ролью — `resumed` |
| `stage_get` | `project`, `task` | открытый или последний этап, входы, отчёты, черновики |
| `stage_note` | `project`, `task`, `text`; `role?` | заметка в открытом этапе, обновляет `last_activity_at` |
| `stage_finish` | `project`, `task`, `role?`, `verdict`, `report_id`; `kind?` | закрывает этап по опубликованному отчёту |
| `report_add` | `project`, `task`, `role`, `kind`, `title`, `content` | отчёт к задаче без этапа |
| `report_put` | `project`, `task`, `role?`, `kind`, `title`, `content` | добавочный отчёт в открытый этап |
| `report_open` | `project`, `task`, `role?`; `kind?`, `title?` | открывает черновик в открытом этапе |
| `report_section` | `draft_id`, `key`, `body`; `title?`, `order?`, `expected_revision?`, `role?` | кладёт или переписывает раздел |
| `report_append` | `draft_id`, `text`; `expected_revision?`, `role?` | дописывает текст без заголовка |
| `report_draft` | `draft_id` | черновик, разделы и собранный Markdown |
| `report_publish` | `draft_id`; `role?`, `expected_revision?` | публикует черновик, отдаёт `report_id` |
| `report_discard` | `draft_id`; `role?` | удаляет неопубликованный черновик |
| `report_get` | `project`, `task`, `report_id` | полный текст отчёта |
| `task_close` | `project`, `task`, `role` | закрывает задачу |
| `task_block` | `project`, `task`, `role`, `reason`; `waiting_for?`, `waiting_ref?` | остановка или ожидание |
| `task_resume` | `project`, `task`, `role`, `reason` | снимает остановку или ожидание |
| `task_reopen` | `project`, `task`, `role`, `reason` | переоткрывает закрытую задачу |
| `task_note` | `project`, `task`, `role`, `text` | комментарий |
| `task_timeline` | `project`, `task` | события задачи, `seq` растёт на 1 |
| `task_stats` | `project` | агрегаты проекта |
| `task_search` | `project`, `query` | поиск по названиям, постановкам, отчётам, комментариям |
| `file_add` | `project`, `task`; `path?`, `file_name?`, `title?`, `role?`, `kind?`, `comment?` | регистрирует файл, отдаёт `file_id` и `/files/<id>` |
| `file_get` | `project`, `task`, `file` | путь и ссылка на файл |

`task` — строка: номер (`"12"`) или идентификатор (`"019..."`). Числом
не передавай. Мутации агента требуют `role`, только если её нельзя вывести из
открытого этапа; если этап открыт, роль можно не передавать. Действия человека
на странице идут с подписью `человек` и роль не требуют.

`report_id` — единственное имя идентификатора отчёта. Полей-алиасов `report`
и `id` нет: `report_get` и `stage_finish` принимают только `report_id`.

## Что возвращают

- `task_list` и `task_search` → `{ tasks: [...] }`, `task_timeline` →
  `{ events: [...] }`. Это объект с массивом внутри, а не голый массив.
  Элемент списка: `{ id, number, folder_name, title, status_id, status_title,
  current_role?, current_role_color?, waiting_for, updated_at }`.
- `task_create` → `{ task, folder_path, warning? }`; `task.number` — номер
  внутри проекта, `task.folder_name` — имя папки. Папку создаёт сервис.
  `warning: folder_exists` значит, что папка уже была; сервис её не
  перезаписывает.
- `stage_start` → `{ stage, inputs, resumed }`. `stage` содержит `role`, `round`,
  `started_at`, `last_activity_at?`, `note`. `inputs[]` — `{ role, round, kind,
  report_id, title, preview }`. Повтор той же ролью возвращает `resumed: true`.
- `stage_get` → `{ stage?, is_open, inputs, reports[], drafts[] }`. Если
  открытого этапа нет, отдаётся последний завершённый с `is_open: false`.
- `stage_note` → обновлённый `stage`; заметка видна в `note`, время — в
  `last_activity_at`.
- `stage_finish` → `{ stage, report }`: этап закрыт по `report_id`.
- `report_open` → `{ draft_id, task_id, stage_id, actor, kind, title, revision,
  created_at, updated_at }`.
- `report_section` и `report_append` → `{ draft_id, revision }`.
- `report_draft` → `{ draft, blocks[], rendered }`; `rendered` — тот Markdown,
  который уйдёт в отчёт.
- `report_publish` → `{ draft_id, report_id, report }`; повторный вызов
  возвращает тот же `report_id`.
- `task_next` → `{ action, role?, round?, reason }`, где `action` —
  `stage_start` или `stage_finish`. Роль и маршрут он не выбирает.
- `task_get` → `{ task, folder_path, status?, current_stage?, reports[],
  drafts[], files[], warnings[] }`. `reports[]` — `{ report_id, kind, round?,
  title, preview, ... }`; `drafts[]` — `{ draft_id, actor, kind, title,
  revision, preview, updated_at }`. `folder_missing` в `warnings` — папки нет
  на диске, хотя сервис её создавал.
- `task_block` → задача и `stage_closed`: `true`, если этим вызовом закрыт
  открытый этап.
- `file_add` → `{ file_id, url }`. Остальное о файле отдаёт `file_get`:
  `{ id, task_id, stage_id?, report_id?, actor, kind, title, comment, path,
  mime?, size?, created_at }`.

## Статусы

Создаются при инициализации проекта:

| id | Название | Вид |
|---|---|---|
| `new` | Новая | `active` |
| `active` | В работе | `active` |
| `waiting` | Ожидание | `waiting` |
| `blocked` | Остановлена | `blocked` |
| `done` | Закрыта | `done` |

Вид `active` обязателен: без него `task_create` не найдёт стартовый статус.
`task_close` ставит `done`, `task_reopen` возвращает в `active`.

## Виды отчётов

| Где | Допустимые виды |
|---|---|
| Этап (`report_open` → `report_publish`, `report_put`) | `report`, `plan`, `acceptance`, `guide` |
| Задача (`report_add`) | `report`, `plan`, `acceptance`, `guide`, `research`, `note` |

- Этап закрывается только по `report_id` опубликованного черновика.
- `stage_finish` не принимает текст `report`.
- В одном этапе одного вида — один отчёт; второй даёт `conflict`.
- Отчёт не редактируется и не удаляется.
- Отчёты задачи (`report_add`) этапов не открывают: так собирают параллельные
  исследования.
- Черновик не попадает в `reports[]` и во входы роли; он виден в `drafts[]`.
- Писать в черновик может только роль-владелец; читать — любой.
- Публикация приёмки требует непустых разделов `summary` и `checks`.

## Входы роли

`config_json` проекта:

```json
{
  "inputs": {
    "Исполнитель": [
      {"from": "Аналитик", "kind": "plan", "round": "latest", "required": true}
    ]
  }
}
```

Сервис читает только ключ `inputs`; другие ключи не исполняет. Правило
описывает, от кого (`from`), какой вид (`kind`), какой круг (`round`) и
обязателен ли вход (`required`).

| `round` | Что берёт |
|---|---|
| `latest` | последний завершённый круг указанной роли с отчётом этого вида |
| `same` | тот же круг, который открывается |
| `previous` | предыдущий круг **самой роли**; `from` в правиле игнорируется, но обязателен |
| `return` | отчёт этапа роли `from`, который вернул задачу (событие `stage_returned`) |

- `required: true` и отчёта нет → `input_missing`. `false` → вход просто не
  показывается.
- Отката на более старый круг нет.
- `latest` ищет отчёт именно в последнем завершённом круге источника. Если
  в нём отчёта нужного вида нет — ошибка, а не поиск в более раннем круге.

## Вердикты

Сервис распознаёт возврат по точному совпадению:

```text
return
returned
возврат
на доработку
```

Регистр и формулировка важны: «На доработку» или «доработка» возвратом не
считаются. Остальной текст — обычное завершение; договорись о словаре заранее.

## Ошибки

Формат: `{code, message, hint, allowed}`. `allowed` — допустимые значения,
если ошибка в имени или поле.

| Код | Смысл |
|---|---|
| `project_missing` | проект не передан |
| `project_unknown` | проекта нет; `allowed` — доступные |
| `role_missing` | роль не передана |
| `role_unknown` | роли нет; `allowed` — зарегистрированные |
| `task_missing` | задача не передана |
| `task_unknown` | задачи нет в проекте |
| `field_missing` | нет обязательного поля; `allowed` — допустимые значения |
| `field_invalid` | значение есть, но неверное или пустое |
| `input_missing` | нет обязательного входа роли |
| `conflict` | этап занят другой ролью, дубль вида, черновик опубликован |
| `not_found` | нет отчёта, черновика, файла или события |
| `file_not_found` | файла нет; `path` — как передали, `tried` — что искали |
| `io` | ошибка диска или базы |

Коды MCP: ошибки ввода → `INVALID_PARAMS`; неизвестные сущности →
`RESOURCE_NOT_FOUND`; `io` → `INTERNAL_ERROR`. Разбирайся по `code`, а не по
тексту сообщения.

## Чего сервис не делает

- Не проверяет маршрут, порядок ролей и качество работы.
- Не создаёт проекты, роли и статусы: это делает человек в настройках.
- Не закрывает этап по сырому тексту: только по опубликованному `report_id`.
- Не хранит черновик в отчётах и не отдаёт его во входы роли.
- Не ищет «последнюю» или «текущую» задачу.
- Не хранит картинки и код в базе: только тексты и пути к файлам.
- Не редактирует и не удаляет отчёты; удаления задачи нет.

## Время и идентификаторы

- Время в базе и MCP — RFC3339 UTC; на странице — местное без пояса.
- Идентификаторы — UUID v7. Номер задачи — целое внутри проекта.

# MCP routes

| Нужно | Инструмент |
|--------|------------|
| Задачи, этапы, отчёты, доска | `pipa` (PiPa / PithosPandoras) |
| Семантика / graph / diagnostics | `bsl-analyzer-workspace` |
| Live ИБ / static выгрузка | `1c-ninja-mcp` `live_*` |
| Load / dump / update / проверки / repo | скиллы `db-*`, `skill-repo-workflow` |
| Стандарты ITS/v8 | `v8std`; reference `bsl-analyzer-reference` |
| GitLab: issue, MR, notes, файлы | `glab` CLI (`glab issue view`, `glab issue note`, `--repo <группа/проект>`); репозиторий задач проекта назван в `AGENTS.md` |
| Живая веб-страница, только по прямой просьбе | MCP `browse` — по умолчанию выключен |
| Live fallback | `1c-mcp-toolkit` (выключен по умолчанию) |

В OpenCode имена MCP-инструментов нормализованы: `1c-ninja-mcp` + `live_query` → `mcp_1c_ninja_mcp_live_query`.

## Браузер

`browse` — реальный Chrome пользователя, не рабочий инструмент по умолчанию:

- GitLab, GitHub, трекеры, документация — только CLI и API (`glab`, `curl`), не браузер;
- проверка 1С в веб-клиенте — скилл `skill-web-test`, не `browse`;
- `browse` — только когда человек прямо просит посмотреть живую страницу, где нет
  CLI/API. Сервер выключен в конфиге (`disabled: true`); включать осознанно под задачу
  и выключать после.

Скиллы в таблице берутся по правам роли: если нужный закрыт, шаг выполняет ведущий агент или человек.

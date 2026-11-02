# Project scaffold

Здесь остаётся только эталон **NinjaLive** — пара к `components/1c-ninja-mcp`.

Создание нового проекта — скилл **`skill-env-setup`** («разверни окружение»): он создаёт структуру,
конфиги, `AGENTS.md` и копирует `NinjaLive` из `SourceProject` или из этого эталона.
Шаблоны проекта лежат в `profile/skills/skill-env-setup/scripts/templates/`.

`kit init-project` удалён в 0.8.0. CLI кита — `doctor`, `verify`, `apply`, `lock`, `deps`.

Каркас задачи (`taskctl.ps1` + команды `Задача`/`Продолжить`/`Статус`) — глобальный, один
на машину: `profile/scripts/` и `profile/commands/`, ставит `kit.ps1 apply`. В проект попадает
только папка `Задачи/` с состоянием.

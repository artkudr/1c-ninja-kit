# Stack defaults (преднастройки)

Канон, который агент обязан сохранять при развёртывании — не «забывать» и не угадывать заново.

## Apache ↔ платформа

| Платформа (major.minor) | Порт | Каталог tools |
|-------------------------|------|----------------|
| **8.3** | **8083** | `%USERPROFILE%\tools\apache-83` |
| **8.5** | **8085** | `%USERPROFILE%\tools\apache-85` |

- Apache **не** копировать в git проекта.
- Smoke / webUrl — с суффиксом **`/ru_RU/`**.
- Выбор порта в проекте: по платформе (`v8path`) / `web.port` в `.v8-project.json`.

## MCP

| Где | Правило |
|-----|---------|
| User `~/.config/opencode/opencode.json(c)` | **без** 1С-серверов (ninja, toolkit, bsl-analyzer-*) |
| Project `opencode.jsonc` | полный набор **этой** ИБ (gitignore) |
| Example | `opencode.jsonc.example` в git |

Путь к ninja MCP → **`{kit}/components/1c-ninja-mcp/main.os`** (не отдельный sibling).

## Rules

- Always-on — глобальный `~/.config/opencode/AGENTS.md`, on-demand — `~/.config/opencode/kit-rules/` (`kit.ps1 apply -Adapter opencode`). В проекте rules не создаются.

## Live CFE list

Главный способ: MCP `1c-ninja-mcp` → `live_extensions_list` (после load `NinjaLive` + публикация).  
Не канон: запуск Предприятия ради списка.

## Прочее

- ИБ и исходники — только корень открытого проекта.
- Кеш bsl-analyzer: `<project>\.build` (gitignore).
- OpenSpec scaffold — для крупных full-cycle; мелочи не тащить.
- Скиллы: kit-профиль + cc-1c-skills (`install/cc-skills.ps1`).

Машиночитаемо: `install/path-defaults.windows.yaml`, `manifest.yaml`.

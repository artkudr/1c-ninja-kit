# Stack defaults (преднастройки)

Канон, который агент обязан сохранять при развёртывании — не «забывать» и не угадывать заново.

## Apache ↔ платформа

| Платформа (major.minor) | Порт | Каталог tools |
|-------------------------|------|----------------|
| **8.3** | **8083** | `%USERPROFILE%\tools\apache-83` |
| **8.5** | **8085** | `%USERPROFILE%\tools\apache-85` |

- Apache **не** копировать в git проекта.
- Smoke / webUrl — с суффиксом **`/ru_RU/`**.
- Выбор порта в проекте: по `v8version` / `web.port` в `autumn-properties.json`.

## MCP

| Где | Правило |
|-----|---------|
| User `%USERPROFILE%\.cursor\mcp.json` | **без** 1С-серверов (`vrunner`, ninja, toolkit, bsl-analyzer-*) |
| Project `.cursor/mcp.json` | полный набор **этой** ИБ (gitignore) |
| Example | `.cursor/mcp.json.example` в git |

`AUTUMN_MAIN` / путь к ninja MCP → **`{kit}/components/1c-ninja-mcp/main.os`** (не отдельный sibling).

## Rules в проекте

- Обычная папка `.cursor/rules` + **hardlink** `mklink /H` или file symlink на каждый `.mdc`.
- **Запрещён** directory junction (`mklink /J`) на папку rules.

## Live CFE list

Главный способ: MCP `1c-ninja-mcp` → `live_extensions_list` (после load `NinjaLive` + публикация).  
Не канон: `vrunner infobase extensions list` / MCP `extensions_list` (запуск Предприятия).

## Прочее

- ИБ и исходники — только корень открытого проекта.
- Кеш bsl-analyzer: `<project>\.build` (gitignore).
- OpenSpec scaffold — для крупных full-cycle; мелочи не тащить.
- Локальные патчи vrunner: `profile/docs-patches/vrunner-local-patches.md`.

Машиночитаемо: `install/path-defaults.windows.yaml`, `manifest.yaml`.

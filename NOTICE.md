# NOTICE — атрибуция и границы поставки

Этот репозиторий собирает обвязку агентной разработки 1С (ecoladev / 1c-ninja-kit).

## Собственные / форкнутые компоненты

| Компонент | Где в kit | Примечание |
|-----------|-----------|------------|
| Rules / orchestration (ecoladev-форк) | `profile/rules/` | Процессный мозг: `1c-orchestrator` и спутники |
| Skills (профиль) | `profile/skills/` | В т.ч. meta/form/cfe и orchestration |
| Agents `1c-*` | `profile/agents/` | Cursor agent prompts |
| **1c-ninja-mcp** | `components/1c-ninja-mcp/` | MCP-сервер (часть kit) |
| **NinjaLive** | `project-scaffold/cfe/NinjaLive/` | CFE-пара к MCP live (`/hs/ninja-live`) |
| Stack defaults / install | `docs/`, `install/` | Порты Apache, MCP layout, doctor |

## Внешние зависимости (не vendor binary)

| Компонент | Лицензия / источник | В kit |
|-----------|---------------------|-------|
| OneScript / OVM | по условиям разработчика OneScript | только path-defaults + doctor |
| vanessa-runner | по условиям пакета opm | pins / doctor; локальные патчи — `profile/docs-patches/` |
| bsl-analyzer | по условиям поставщика бинарника | pin path `%LOCALAPPDATA%\bsl-analyzer` |
| Apache HTTP Server | Apache License 2.0 | только layout paths `apache-83` / `apache-85` |
| MCP Toolkit EPF | по условиям поставщика EPF | pin path (часто `C:\1C\soft\MCP_Toolkit.epf`) |
| v8std MCP | `https://ai.v8std.ru/mcp` | optional pack `extras-mcp` |
| cc-1c-skills lineage | исходный upstream Nikolay-Shirokov / port-cursor | skills в `profile/skills/` (meta/form/…); см. `sync-cc-1c-skills` |
| OpenSpec (Fission-AI) | MIT (upstream CLI опционален) | шаблоны scaffold; CLI не обязателен |
| itrous/ai_rules_1c | upstream reference | **не** тащить второй always-on оркестратор; канон — ecoladev-форк |

## Что намеренно НЕ входит

- Кэши: `.build`, browser-session, `__pycache__`, agent stores
- Секреты: `autumn-properties.json`, `.cursor/mcp.json` с паролями, `NINJA_PASSWORD`
- Бинарники платформы 1С, полные дистрибутивы Apache, бинарник bsl-analyzer
- Выгрузка конфигурации ecoladev / product OpenSpec changes

При публикации ~0.3 этот файл обязан быть актуализирован (полный THIRD_PARTY при необходимости).

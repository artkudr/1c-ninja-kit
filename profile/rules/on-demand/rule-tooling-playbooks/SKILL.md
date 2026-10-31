---
name: rule-tooling-playbooks
description: >-
  Per-task playbooks (BSL, forms, CFE, live, review) - contour skills/ninja, not manual Designer
---

<!-- kit-adapted from itrous/ai_rules_1c tooling-playbooks -->

# Tooling playbooks

Каталог MCP и fallback — правила `rule-bsl-analyzer`, `rule-ninja-mcp`, `rule-development-process`. Этот файл — последовательности по типу задачи. Операции с ИБ — только скиллы контура (`db-*`, `skill-repo-workflow`), не ручные вызовы Конфигуратора и не сторонние metadata-менеджеры.

## Minimum evidence

| Форма задачи | До правки | После |
|--------------|-----------|--------|
| Quick-fix BSL | Прочитать целевой метод | `diagnostics file` |
| Full-cycle BSL | `search`/`graph`/`metadata` (+ v8std при паттернах) | `diagnostics file` → Напарник (если есть) → impact `graph` при публичной поверхности |
| Метаданные / формы | `meta-info`/`form-info` + примеры; правки через `meta-*`/`form-*`/`cfe-*` | `*-validate` + `diagnostics file` на затронутый BSL |
| CFE с хранилищем | Захват `skill-repo-workflow` | Гейты `skill-repo-workflow` |
| Live данные | `live_*` ninja | — |
| Список расширений ИБ | `live_extensions_list` (после загрузки NinjaLive) | не Предприятие |
| Docs/rules без фактов 1С | Чтение файлов | Структурные проверки |
| BSL в EPF/ERF | Если объект в индексе bsl-analyzer — как Quick-fix BSL | `diagnostics file`; иначе ninja + `epf-validate` |

## Writing / editing BSL

1. `search_code` / `find_code` — паттерны в проекте; `v8std_search` — канон.
2. `metadata object` / `meta-info` — форма объекта.
3. `graph resolve` → `node` — точка вставки.
4. `syntax_help` / reference — API платформы.
5. БСП — поиск по проекту + `rule-bsp-developer`.
6. Правка → `diagnostics file`.
7. Напарник `check_1c_code` / `review_1c_code` — если MCP поднят; иначе не блокируй (отметь в отчёте).
8. Новый запрос — `query validate` или `live_validate_query`.

## Code review

1. Паттерны: `search` + `rule-anti-patterns` / `rule-platform-solutions`.
2. Impact: `graph callers` / `neighbors`.
3. Напарник review + `v8std` / `its_help` — по возможности.
4. Агент `agent-code-reviewer` — **только** по явной просьбе пользователя.

## Architecture

1. `metadata` / `graph` карта + правило `rule-architect`.
2. Не проектируй в обход onion-слоёв.
3. Напарник `ask_1c_ai` — только черновик, не авторитет.

## Error fixing

1. Воспроизведение: журнал (`live_event_log` / `event_log`), `rule-systematic-debugging`.
2. `diagnostics file` → локализация `graph`/`find_code`.
3. Live гипотезы: `live_query` / `live_eval` (осторожно).
4. Фикс → гейты development-process.

## Performance

1. Найти медленные паттерны (`search_code`, anti-patterns «запрос в цикле»).
2. `graph` hot paths; индексы через `metadata`.
3. Напарник check / rewrite — черновик + повторная валидация.

## Metadata / forms

1. Найти объект: `meta-info` / `form-info` / `metadata`.
2. Менять **только** скиллами: `meta-edit`/`meta-compile`, `form-edit`/`form-compile`, `cfe-borrow`/`cfe-patch-method`, `skd-*`, `role-*`, …
3. `*-validate` того же типа.
4. Load: скиллы контура (`db-load-xml` / `skill-repo-workflow`) — см. `rule-development-process`. **Запрещены** ручные вызовы Конфигуратора и сторонние metadata-менеджеры.

## Integrations

1. Существующие интеграции в проекте (`search_code`).
2. Правило `rule-integrations-add`.
3. Live smoke через ninja при необходимости.

## Docs

Структурные проверки; факты о 1С — подтверди MCP до записи в документ.

---
name: rule-tooling-playbooks
description: >-
  Per-task playbooks (BSL, forms, CFE, live, review) - contour skills/ninja, not manual Designer
---

<!-- kit-adapted from itrous/ai_rules_1c tooling-playbooks -->

# Tooling playbooks

Каталог MCP и fallback — правила `rule-bsl-analyzer`, `rule-ninja-mcp`, `rule-development-process`. Здесь — последовательности инструментов по типу задачи. Что должно быть зелёным после правки, бюджеты и отчёт — `rule-verification-checklist`; операции с ИБ — только скиллы контура (`db-*`, `skill-repo-workflow`).

## Что прочитать до правки

| Форма задачи | До правки |
|--------------|-----------|
| Quick-fix BSL | целевой метод: `symbol_info` или ninja `read_module` |
| Full-cycle BSL | `search`, `graph`, `metadata`; при выборе паттерна — `v8std` |
| Метаданные / формы | `meta-info` / `form-info` + примеры того же вида в проекте |
| CFE с хранилищем | захват `skill-repo-workflow`, список затрагиваемых объектов |
| Live данные | схема объектов в `live_metadata_structure`, а не угадывание имён |
| BSL в EPF/ERF | в индексе анализатора — `symbol_info`; иначе ninja `read_module` |

## Правка BSL

1. Паттерны в проекте — `search_code`; канон — `v8std_search`.
2. Форма объекта — `metadata object` / `meta-info`.
3. Точка вставки — `graph resolve` → `node`.
4. API платформы — `syntax_help` / `bsl-analyzer-reference`.
5. БСП — поиск по проекту + `rule-bsp-developer`.
6. Правка → гейты по `rule-verification-checklist`.

## Code review

1. Паттерны: `search` + `rule-anti-patterns` / `rule-platform-solutions`.
2. Impact: `graph callers` / `neighbors`.
3. Напарник review + `v8std` / `its_help` — по возможности.
4. Ревью — по явной просьбе пользователя; отдельного агента-ревьюера нет, смотрит Инквизитор по приёмке.

## Architecture

1. `metadata` / `graph` карта + правило `rule-architect`.
2. Не проектируй в обход onion-слоёв.
3. Напарник `ask_1c_ai` — только черновик, не авторитет.

## Error fixing

1. Воспроизведение: журнал (`live_event_log` / `event_log`), `rule-systematic-debugging`.
2. `diagnostics file` → локализация `graph` / `search`.
3. Live гипотезы: `live_query` / `live_eval` (осторожно).
4. Фикс → гейты `rule-verification-checklist`.

## Performance

1. Найти медленные паттерны (`search_code`, anti-patterns «запрос в цикле»).
2. `graph` hot paths; индексы через `metadata`.
3. Напарник check / rewrite — черновик + повторная валидация.

## Metadata / forms

1. Найти объект: `meta-info` / `form-info` / `metadata`.
2. Менять **только** скиллами: `meta-edit`/`meta-compile`, `form-edit`/`form-compile`, `cfe-borrow`/`cfe-patch-method`, `skd-*`, `role-*`, ….
3. Гейты — `rule-verification-checklist`; загрузка — `rule-development-process`. **Запрещены** ручные вызовы Конфигуратора и сторонние metadata-менеджеры.

## Integrations

1. Существующие интеграции в проекте (`search_code`).
2. Правило `rule-integrations-add`.
3. Live smoke через ninja при необходимости.

## Docs

Структурные проверки; факты о 1С — подтверди MCP до записи в документ.

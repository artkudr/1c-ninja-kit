---
name: rule-forms
description: >-
  Router for managed-form work — skills first, companion methodology rules on demand
---

<!-- kit-adapted cherry-pick of rule-forms; no forms-add / metadata-manage -->

# Managed forms — entry

Сначала этот роутер, затем только нужные companions. Структуру формы **не** правь руками — скиллы `form-info` / `form-edit` / `form-compile` / `form-validate` / `form-add`.

## Routing

| Задача | Действие |
|--------|----------|
| Создать / структурно менять форму | `form-add` / `form-edit` / `form-compile` → `form-validate` |
| Обработчики событий | `rule-forms-events-add` + логика в модуле |
| BSL модуля формы | `form-module` patterns в `rule-code-agent`; reserved names → `rule-form-reserved-names` |
| Регионы нового модуля | `rule-module-structure` |
| Client/server / round-trips | `rule-architect`, `rule-anti-patterns` |
| `Асинх` / `Ждать` | `rule-async-methods` |
| Adopted форма CFE | `rule-extension-patterns`, `cfe-patch-method` |

Не подгружай весь набор forms-* «на всякий случай». Не используй upstream `forms-add` / `1c-metadata-manage` — канон задаёт кит скиллов.

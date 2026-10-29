---
name: rule-verification-checklist
description: >-
  Closing verification gate for full-cycle 1C changes
---

<!-- kit-adapted from itrous/ai_rules_1c verification-checklist -->

# Verification checklist

Грузи перед объявлением non-trivial изменения «готово». Компаньоны: `rule-tooling-playbooks`, `rule-subagent-pipeline`, `rule-systematic-debugging`, `rule-development-process`.

## Hard gates (full-cycle)

### 1. Analyzer — `diagnostics file`

На каждый затронутый `.bsl`. Pass: нет `error`. Бюджет: 1 вызов на цикл правки; до 3 только после substantive дефекта. Без no-change повторов.

### 2. Напарник `check_1c_code` (если MCP доступен)

После gate 1. Pass: нет critical/error. Если сервер не поднят — **не блокируй**: зафиксируй в Risks «Напарник недоступен» и опирайся на diagnostics + syntax-check.

### 3. Напарник `review_1c_code` (если доступен)

Стиль / ITS. Та же деградация, что gate 2. Дополнительно: `v8std_explain_*` при разборе находки.

### 4. Impact (`graph`)

Обязателен, если менялась публичная поверхность / метаданные / экспорт. `resolve` → `callers` / `neighbors`. Если graph недоступен — явная строка в Risks, не молчаливый skip.

### 5. Metadata / form validation

Если трогали XML структуры: профильный `*-validate` (meta/form/skd/…). **Не** `1c-metadata-manage`. Для CFE с хранилищем — гейты `skill-repo-workflow`.

### 6. Platform / load gates

По `rule-development-process`: синтакс-контроль (`skill-syntax-check` для `src/cf`, `db-cfe-admin check` для расширений); load только скиллами контура (`db-load-xml` / `skill-repo-workflow`); перед load — summary пользователю.

## Soft gates

| Когда | Что |
|--------|-----|
| Debug | Reproduction case закрыт (`rule-systematic-debugging`) |
| Full-cycle с планом | План выполнен; нет файлов вне плана (`git diff --name-only`) |
| UI | `skill-web-test` / публикация — по явной просьбе |
| Code review | Только если пользователь просил |

## Delivery summary (обязательно)

- Что изменено и почему (пути в backticks)
- Какие гейты пройдены / пропущены и почему
- Risks / follow-ups

Объявлять «готово» при провале hard gate запрещено.

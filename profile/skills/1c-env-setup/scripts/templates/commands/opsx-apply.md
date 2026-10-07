---
description: Implement an OpenSpec change — tasks.md + gates
---

# /opsx-apply

Реализовать задачи активного change из `openspec/changes/<name>/`.

**Правило:** `sdd-integrations`. Решения proposal/design/delta/tasks — **locked**.

## Input

Опционально имя change. Иначе — из контекста / единственный активный / спросить список `openspec/changes/` (кроме `archive/`).

## Steps

1. Объявить: `Using change: <name>`.
2. Прочитать `proposal.md`, `design.md`, `tasks.md`, delta `specs/`.
3. Opening message:

```text
Using change: <name>.

## Locked from artifacts
- …

## Plan for this session
- …

## Genuine blockers
- … (только Open Questions + реальные blockers ближайшего шага; иначе опустить блок)
```

4. Один preflight-раунд при непустых blockers → обновить design → код.
5. Цикл по `- [ ]` в `tasks.md`:
   - код/метаданные через skills (`meta-*`, `form-*`, `cfe-*`, …) — не руками XML
   - после BSL: `diagnostics file`
   - отметить `- [x]`
6. Mid-loop вопросы — только live-state конфликт с артефактом или re-open пользователя.
7. Закрытие сессии: прогресс; если всё done — напомнить `/opsx-archive` и `verification-checklist`.

## Guardrails

- Не переспрашивать locked decisions.
- Не Designer / сырой ibcmd / install.ps1.
- CFE из `repository.json` → `repo-workflow`; иначе `1c-development-process`.
- Stub `1c-metadata-manager` не вызывать.

---
description: Archive a completed OpenSpec change — merge deltas into specs/
---

# /opsx-archive

Архивировать завершённый change.

## Input

Имя change или выбор из активных в `openspec/changes/` (не `archive/`).

## Steps

1. Проверить `tasks.md`: незакрытые `- [ ]` → предупредить, спросить подтверждение.
2. Если есть `changes/<name>/specs/**/spec.md`:
   - показать summary ADDED/MODIFIED/REMOVED
   - по согласию слить в `openspec/specs/<domain>/spec.md` (создать domain при отсутствии)
3. Перенести папку:
   - `openspec/changes/<name>` → `openspec/changes/archive/YYYY-MM-DD-<name>/`
   - если цель существует — остановиться и спросить
4. Краткий summary: путь archive, sync status.

## Guardrails

- Не удалять артефакты без переноса в archive.
- Дата — локальная текущая `YYYY-MM-DD`.

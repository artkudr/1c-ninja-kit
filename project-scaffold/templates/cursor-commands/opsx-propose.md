---
description: Propose a new OpenSpec change — proposal, design, tasks, delta specs
---

# /opsx-propose

Создать change в `openspec/changes/<kebab-name>/` со всеми артефактами до готовности к коду.

**Не писать прикладной код.** Правило: `sdd-integrations`. Шаблоны: `openspec/templates/`.

## Input

Аргумент = kebab-case имя **или** описание фичи. Нет ввода → спросить, что строить; имя вывести из описания.

## Steps

1. Убедиться, что задача **крупная** (иначе сказать, что OpenSpec не нужен, и остановиться — см. `1c-orchestrator`).
2. Создать каталог `openspec/changes/<name>/` и `openspec/changes/<name>/specs/<domain>/` (domain — короткое имя capability).
3. Скопировать/заполнить из templates:
   - `proposal.md`
   - `design.md`
   - `tasks.md`
   - `specs/<domain>/spec.md` ← из `templates/delta-spec.md`
4. **MCP-факты** до normative имён в спеке (`graph` / `metadata` / `search` / reference). Блок `## Context sources` в каждом нетривиальном файле.
5. Propose-фаза: агрессивно закрыть архитектурные вопросы (`CONFUSION` при неоднозначности). Не откладывать «на apply».
6. Pre-finalization gate из `sdd-integrations` (requirements / design / tasks / Open Questions).
7. Итог: путь change, список артефактов, «Ready for implementation» **только** после gate + (согласование пользователя или явного «спека ок»).

## Guardrails

- CLI `openspec` не обязателен.
- Forbidden: TBD по фактам MCP; «уточнить при реализации»; vague «при необходимости».
- Placement cf vs cfe зафиксировать в proposal/design.

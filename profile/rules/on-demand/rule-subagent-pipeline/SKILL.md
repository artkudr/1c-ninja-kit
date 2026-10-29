---
name: rule-subagent-pipeline
description: >-
  Full-cycle subagent pipeline — plan → implement → compliance → optional review → verification
---

<!-- kit-adapted from itrous/ai_rules_1c subagent-pipeline -->

# Subagent pipeline

Только для **full-cycle** (`rule-orchestrator` triage). Quick-fix: правка + `diagnostics file` (+ `*-validate`).

```
user → triage (parent)
       → full-cycle
            → 1b. OpenSpec propose (если крупная ветка — см. rule-orchestrator)
            → 2. Plan (agent-planner / agent-architect / agent-explorer / agent-analyst)
            → 3. Implement (agent-developer / …; метаданные — скиллы; только после согласования спеки / «кодируй»)
            → 4a. Spec-compliance (parent; против openspec/changes/ если есть)
            → 4b. Code review OPTIONAL (только по просьбе → agent-code-reviewer; на крупных — сверка со спекой)
            → 5. rule-verification-checklist + rule-development-process / skill-repo-workflow
            → 6. OpenSpec archive (если был change)
            → deliver
```

## Stage 1b — OpenSpec (крупные)

Если triage = full-cycle **и** крупная задача: артефакты в `openspec/changes/<name>/` по `rule-sdd-integrations` / `/opsx-propose`. Analytic → proposal+delta; architect → design; planner → tasks. Код не начинать до согласования границ.

Мелкий full-cycle / quick-fix — OpenSpec **не** обязателен (план в чате / `handoffs/` допустим).

## Stage 2 — Plan

Критерии приёмки плана: задачи ≤~1 файл/метод; точные пути и имена; шаг verification; risks/rollback; **approval пользователя** перед stage 3. При активном OpenSpec — `tasks.md` change = канон плана.

## Stage 3 — Implement

- BSL: `agent-developer` / `agent-error-fixer` / …
- XML структуры: **скиллы** `meta-*`, `form-*`, `cfe-*`, …
- Вне плана («заодно») запрещено — репорт родителю
- Pre-handoff: `diagnostics file` на каждый тронутый модуль

### Handoff между implementation-агентами

Upstream в начале финального отчёта:

```text
## Handoff (для следующего субагента)
### Artifacts
- <path> — <role> [stub|done|edited]
### Public surface
- <Module.Method(params) → type> — <purpose>
### Open TODOs / stubs
- <file:region> — <what>
### Locked decisions
- <decision> — <rationale>
### Open questions raised
- <id> — <summary> — <status>
```

Parent передаёт блок **дословно** в `## Upstream Handoff`. Downstream не перечитывает listed artifacts «для контекста».

## Stage 4a — Spec-compliance (parent)

План/`tasks.md` выполнен; нет лишних файлов; публичные сигнатуры/метаданные совпали; UUID не перегенерированы зря. Если был OpenSpec change — сверка с delta `### Requirement:` / scenarios.

## Stage 4b — Review

Только по явной просьбе. Иначе quality закрывают gates 2–3 checklist + process.

## Stage 5 — Verification

`rule-verification-checklist` + load/syntax по `rule-development-process` / `skill-repo-workflow`.

## Anti-patterns

- Skip plan «потому что мелко» — тогда это должен был быть quick-fix
- Parallel stage 3 на одной конфигурационной области
- Auto `agent-code-reviewer`
- Designer / ibcmd / install.ps1

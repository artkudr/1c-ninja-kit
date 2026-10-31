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
            → 1. Plan (agent-planner / agent-architect / agent-explorer / agent-analyst)
            → 2. Implement (agent-developer / …; метаданные — скиллы; только после согласования плана / «кодируй»)
            → 3a. Plan-compliance (parent; сверка с утверждённым планом)
            → 3b. Code review OPTIONAL (только по просьбе → agent-code-reviewer; на крупных — сверка с планом)
            → 4. rule-verification-checklist + rule-development-process / skill-repo-workflow
            → deliver
```

## Stage 1 — Plan

План фиксируется в чате или `handoffs/`; для крупной задачи его собирают `agent-analyst` / `agent-planner` / `agent-architect`. Код не начинать до согласования границ.

Критерии приёмки плана: задачи ≤~1 файл/метод; точные пути и имена; шаг verification; risks/rollback; **approval пользователя** перед stage 2.

## Stage 2 — Implement

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

## Stage 3a — Plan-compliance (parent)

План выполнен; нет лишних файлов; публичные сигнатуры/метаданные совпали; UUID не перегенерированы зря.

## Stage 3b — Review

Только по явной просьбе. Иначе quality закрывают gates 2–3 checklist + process.

## Stage 4 — Verification

`rule-verification-checklist` + load/syntax по `rule-development-process` / `skill-repo-workflow`.

## Anti-patterns

- Skip plan «потому что мелко» — тогда это должен был быть quick-fix
- Parallel stage 2 на одной конфигурационной области
- Auto `agent-code-reviewer`
- Designer / ibcmd

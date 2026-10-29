---
name: rule-subagents
description: >-
  Каталог субагентов `agent-*` и правила делегирования
---

<!-- kit-adapted from itrous/ai_rules_1c subagents -->

# Subagents — каталог и делегирование

Грузи, когда задача крупная / многомодульная и есть смысл делегировать. Промпты: `{{AGENTS_ROOT}}\agent-*.md`.

## Принцип

**Делегируй**, если: большой объём; риск раздуть контекст родителя; независимые проверки параллельно.

**Не делегируй** trivial single-file / Quick-fix — делай сам оркестратор.

Параллель правок **одной** метаданки запрещена (`rule-orchestrator`).

## Каталог

| Subagent | Когда звать | Когда НЕ |
|----------|-------------|----------|
| **agent-explorer** | Широкий read-only поиск / «где/как/кто вызывает» | Узкий lookup одним MCP-вызовом |
| **agent-analyst** | PRD / анализ области без кода | Нужно писать код |
| **agent-planner** | Многошаговый план до кода | План в 1–2 строки |
| **agent-architect** | Новая подсистема / интеграция / слои | Одна процедура |
| **agent-arch-reviewer** | Валидация уже есть дизайн | Дизайна ещё нет |
| **agent-developer** | Массовый BSL по нескольким модулям | Quick-fix |
| **agent-refactoring** | Кросс-модульный рефакторинг | Локальный метод |
| **agent-performance-optimizer** | Явная задача по скорости | Не просили |
| **agent-error-fixer** | Синтаксис / runtime без архитектуры | Нужен редизайн |
| **agent-code-reviewer** | **Только** явная просьба review | Автопосле правок — запрещено |
| **agent-doc-writer** | Пользовательские гайды | Inline-комментарии кода |
| **agent-tester** | Stub: `skill-repo-workflow` + `skill-web-test` | Не звать deploy/ibcmd из upstream |


Стек агентов: скиллы контура (`db-*`, `skill-repo-workflow`), ninja live, `bsl-analyzer-workspace`, профильные XML-скиллы. Наследуют triage/`CONFUSION` из `rule-orchestrator`.

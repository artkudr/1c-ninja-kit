---
name: rule-dev-standards-architecture
description: >-
  Thin architecture pointers — delegates to rule-architect; no coding-standards duplicate
---

<!-- kit cherry-pick: not full upstream dev-standards-*; coding standards already in rule-bsl-code-standards / rule-code-agent -->

# Dev-standards architecture (thin)

1. **Слои / onion** — always load `rule-architect` for design boundaries.
2. **Extensions** — `rule-extension-patterns` + `cfe-*` skills; `&Перед`/`&После` важнее тяжёлого `&ИзменениеИКонтроль` без нужды.
3. **Forms placement** — UI thin; business in domain modules (`rule-architect`).
4. **Registers / DCS / locks / logging** — on-demand: `rule-registers-design`, `rule-dcs-design`, `rule-locks-and-transactions`, `rule-logging-strategy`.
5. **Module regions** — `rule-module-structure`.
6. **Style / naming / BSP** — `rule-bsl-code-standards`, `rule-code-agent`, `rule-bsp-developer` (не тяни upstream `coding-standards.md`).

XML структуры — только через `rule-development-process` skills. Load — только скиллы контура / `skill-repo-workflow`.

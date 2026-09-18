# OpenSpec

Spec-driven workspace для **крупных** фич и проектов. Мелочи (quick-fix / docs-fix) сюда не тащат.

Формат совместим с [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) (OPSX). Адаптация под контур 1С: без `install.ps1`, без Designer/`ibcmd`, гейты через vrunner / `repo-workflow`, факты 1С — только из MCP.

Правило агента: `sdd-integrations` (on-demand / globs на `openspec/**`). Triage — `1c-orchestrator`.

## Layout

```
openspec/
├── README.md
├── config.yaml          # контекст проекта для агента
├── project.md           # снимок 1С-контекста (обновлять вручную / по задаче)
├── templates/           # шаблоны артефактов (без CLI)
├── specs/               # SoT: как система ведёт себя сейчас
│   └── <domain>/spec.md
└── changes/             # активные предложения
    ├── archive/
    └── <change-name>/
        ├── proposal.md
        ├── design.md
        ├── tasks.md
        └── specs/<domain>/spec.md   # delta: ADDED / MODIFIED / REMOVED
```

## Workflow (без обязательного CLI)

```
propose → (согласование границ) → apply → verify → archive
```

1. **propose** — папка `changes/<kebab-name>/` + артефакты из `templates/`. Slash: `/opsx-propose`.
2. **готовность к коду** — пользователь явно: «спека ок — кодируй» / «apply», либо закрыт clarification gate в правиле.
3. **apply** — код по `tasks.md`; гейты `1c-development-process` / `repo-workflow` / `verification-checklist`. Slash: `/opsx-apply`.
4. **archive** — слить delta в `specs/`, перенести change в `changes/archive/YYYY-MM-DD-<name>/`. Slash: `/opsx-archive`.

Explore (без кода): `/opsx-explore`.

## Когда включать

| Да (OpenSpec) | Нет |
|---------------|-----|
| Full-cycle + крупное: новая подсистема, многомодульная фича, интеграция, архитектурный рефакторинг, «крупный проект» | Quick-fix, docs-fix, мелкая правка одного метода/файла |

Критерий крупности и маршрутизация — в `1c-orchestrator` и `sdd-integrations`.

## CLI (опционально)

Контур **не требует** npm / OpenSpec CLI. Шаблоны и slash-команды проекта самодостаточны.

Если нужен официальный CLI (status/instructions schema):

```bash
npm install -g @fission-ai/openspec@latest
openspec --version
```

После установки `openspec new change` / `openspec status` можно использовать вместо ручного scaffold из `templates/`. Не обязательно для работы.

## Связанные правила / скиллы

- `sdd-integrations` — дисциплина спек, MCP-факты, фазы propose/apply
- `1c-orchestrator` — triage «включать / нет»
- `verification-checklist`, `1c-development-process`, `repo-workflow`
- Skills: `meta-*`, `form-*`, `cfe-*`, `1c-bsl-analyzer`, `1c-ninja-mcp`, `vrunner-mcp`

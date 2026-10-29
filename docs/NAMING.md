# Naming contract

Единый контракт имён kit-owned сущностей. Внешние `cc-1c-skills` не переименовываются.

| Тип | Префикс | Пример | SoT |
|-----|---------|--------|-----|
| Kit skill | `skill-` | `skill-env-setup` | `profile/skills/skill-env-setup/SKILL.md` |
| Always-on rule | `rule-` | `rule-orchestrator` | `profile/rules/always/rule-orchestrator.md` |
| On-demand rule | `rule-` | `rule-anti-patterns` | `profile/rules/on-demand/rule-anti-patterns/SKILL.md` |
| Agent | `agent-` | `agent-explorer` | `profile/agents/agent-explorer.md` |
| External skill | без изменений | `db-load-xml`, `meta-info` | `~/.config/opencode/skills/<id>/` |

## Правила

- `1c-` из kit-owned имён не используется.
- Always-on правила — обычный Markdown, собираются в `AGENTS.md`.
- On-demand правила — нативные OpenCode skills: в OpenCode нет отдельного on-demand типа «rule».
- Kit skills и rule-skills устанавливаются в `~/.config/opencode/skills/kit/`:
  - `skills/kit/skills/<skill-id>/SKILL.md`
  - `skills/kit/rules/<rule-id>/SKILL.md`
- Внешние `cc-1c-skills` лежат в `~/.config/opencode/skills/<id>/` и не затрагиваются `apply`.
- ID скилла/агента определяется путём/именем файла; `name:` в frontmatter — только display label.

## Почему так

OpenCode V2 нативно понимает:
- `AGENTS.md` — always-on;
- `skills` — on-demand;
- `agents` — субагенты;
- `instructions` — дополнительные always-on файлы.

Отдельной папки `rules` в OpenCode нет. Поэтому on-demand правила упакованы как skills,
а их ID начинаются с `rule-`, чтобы не путать с обычными skills и агентами.

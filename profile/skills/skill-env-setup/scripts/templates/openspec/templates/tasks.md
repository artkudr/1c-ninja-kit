# <change-name> — Tasks

Чеклист реализации. Код только после согласования proposal/design (или явного «спека ок — кодируй»).

## Spec / design
- [ ] proposal.md согласован
- [ ] design.md согласован (границы слоёв закрыты)
- [ ] delta specs написаны и без TBD по фактам MCP

## Implementation
- [ ] …
- [ ] …

## Gates (verification)
- [ ] `diagnostics file` на каждый изменённый `.bsl`
- [ ] профильный `*-validate` (meta/form/skd/cfe/…)
- [ ] CFE из `.v8-project.json` → гейты `skill-repo-workflow`; иначе `skill-syntax-check` / `db-load-xml` / `db-update` по process
- [ ] `rule-verification-checklist` для full-cycle

## Archive
- [ ] delta слита в `openspec/specs/`
- [ ] change в `openspec/changes/archive/YYYY-MM-DD-<name>/`

## Context sources
<!-- при существенном обновлении tasks -->

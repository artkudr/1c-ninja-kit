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
- [ ] CFE из repository.json → гейты `repo-workflow`; иначе syntax-check / `cfe_load` / `cf_load` по process
- [ ] `verification-checklist` для full-cycle

## Archive
- [ ] delta слита в `openspec/specs/`
- [ ] change в `openspec/changes/archive/YYYY-MM-DD-<name>/`

## Context sources
<!-- при существенном обновлении tasks -->

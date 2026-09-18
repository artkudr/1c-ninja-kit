# Changes — active proposals

Один change = одна подпапка.

```
changes/<change-name>/
├── proposal.md
├── design.md
├── tasks.md
└── specs/<domain>/spec.md   # delta
```

Scaffold: скопировать из `../templates/` или `/opsx-propose`.

## Delta format

```markdown
# Delta for <domain>

## ADDED Requirements
### Requirement: <name>
...

## MODIFIED Requirements
### Requirement: <name>
...

## REMOVED Requirements
### Requirement: <name>
...
```

При archive:

- ADDED → append в `../specs/<domain>/spec.md`
- MODIFIED → replace same-name requirement
- REMOVED → delete from main spec
- папка → `archive/YYYY-MM-DD-<change-name>/`

| File | Purpose |
|------|---------|
| `proposal.md` | why / what / scope |
| `design.md` | how / architecture |
| `tasks.md` | checklist `- [ ]` |
| `specs/` | delta requirements |

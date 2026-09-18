# Specs — source of truth

Авторитетные спецификации текущего поведения. Совместно люди + агенты.

## Conventions

- Одна подпапка на capability/domain (например `warehouse-picking/`).
- В папке ровно один `spec.md`.
- Требования: `### Requirement:` + сценарии `#### Scenario:` (Gherkin-style).

## Minimal template

```markdown
# <capability> Specification

## Purpose
<один абзац>

## Requirements

### Requirement: <name>
<MUST / SHALL / MAY>

#### Scenario: <name>
- GIVEN <precondition>
- WHEN <action>
- THEN <expected result>
```

## Updates

Обычно **не** правят `specs/` напрямую:

1. Change в `../changes/<name>/`
2. Delta в `../changes/<name>/specs/<domain>/spec.md` (`ADDED` / `MODIFIED` / `REMOVED`)
3. `/opsx-archive` сливает delta сюда и переносит change в `archive/`

См. [`../README.md`](../README.md).

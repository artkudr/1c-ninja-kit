---
name: skill-handoff
description: "Compact the current conversation into a self-contained handoff document so a fresh agent (new chat, another machine, another AI client) can continue the work without re-discovering the context. References durable artifacts (`openspec/changes/*`, `AGENTS.md`, `docs/decisions.md`, commits) instead of duplicating them. Use when the user says 'handoff', 'compact session', 'save context for continuation', or invokes `/handoff`."
argument-hint: "Optional: focus of the next session, or a target path/folder for the handoff file."
---

# handoff — session transfer to the next agent

Adapted from [`mattpocock/skills`](https://github.com/mattpocock/skills) (`skills/productivity/handoff`, MIT). Compresses the current conversation into a self-contained document for the next session. Principle: **reference durable artifacts, do not duplicate them**.

## Triggers

Use this skill when the user says:

- "handoff", "compact session", "/handoff"
- "save context for continuation", "brief the next session"
- equivalent Russian phrases such as "сделай handoff", "передай контекст", "сохрани контекст для продолжения"

## Argument

- If the argument looks like a path (ends with `.md` or points to an existing directory) → **target path**.
- Otherwise → **focus** of the next session (insert it into the handoff header).
- If both are present, treat the first token as the path and the rest as focus.
- Without an argument, ask the user for the focus in one line and continue with the default path.

## Where to write

1. Default directory: `handoffs/` at the project root. Create it if missing.
2. Default file name: `handoff-<YYYYMMDD-HHMMSS>.md` (local time).
3. If the user provided a path, use it (overwrite without confirmation).
4. **Before writing**, read the target file through Read. The expected "does not exist" error is fine; this is protection against overwriting an unrelated existing file with the same name.
5. If the project has `.gitignore` and `handoffs/` is not mentioned there, **offer** to add it (handoffs are session artifacts, not code), but **do not add it automatically**.

PowerShell conventions (`\` in paths, quotes around paths with spaces) — see the `powershell-windows` skill.

## Document structure

```markdown
# Handoff: <one-line session goal>

**When**: <YYYY-MM-DD HH:MM local>
**Branch / commit**: <branch>, latest commit <short SHA + subject>
**Next session focus**: <argument focus, if provided>

## Current State
1-3 sentences: what was done last, what remains unfinished, what is blocked.

## Open Questions
Bulleted list of real unresolved questions (architectural forks, waiting for the user, unclear contract). If empty, omit the section.

## Files Changed In This Session
- `path/to/file.bsl` — what changed and why.
- `path/to/file.xml` — same.
Only include the current session diff. If nothing changed, omit the section.

## Verification State
Which gates from `rule-verification-checklist` passed / failed / were skipped. Latest `diagnostics file` / `check_1c_code` / `review_1c_code` result in brief (error count, key messages).

## Next Steps
1-5 imperative items ("Check movements for `РегистрНакопления.<Имя>`", "Finish `ОбработкаПроведения` for document `<Имя>`").

## What To Load Next Session
- **Subagents**: `agent-<name>` when the task matches their role (see `rule-orchestrator`).
- **On-demand rules**: `rule-<name>` skills based on the task trigger (see `rule-orchestrator → Skills`).
- **MCP tools**: especially relevant tools (`metadata object` for X, `graph neighbors`/`callers` before refactoring Y, `search search_code` over the БСП modules for topic Z).
- **Slash commands**: `/opsx-propose` when the task needs a new OpenSpec proposal, cf dump via `db-dump-xml` / 1c-ninja-mcp for metadata re-export, etc.

## Links (DO NOT copy content)
- `openspec/changes/<id>/proposal.md`, `design.md`, `tasks.md`
- `AGENTS.md` — relevant sections (already loaded by the harness)
- `docs/decisions.md` — dated decision history, if the project keeps one
- Commits / PR / Issue
- ITS articles, platform documentation pages
```

## What NOT to write in the handoff

- Contents of existing artifacts (PRD, OpenSpec proposal/design/tasks, ADR, ITS page, commit, PR description). Link only.
- Full module code. Only include a short change description and path.
- Secrets, tokens, passwords, `.dev.env` contents, infobase connection strings.
- Long MCP output dumps. Include only the result and call parameters so the check can be repeated if needed.

## After writing

1. Tell the user the absolute path of the created file and its line count.
2. If the session produced corrections / facts that may qualify for long-term memory, **list them separately** as candidates:
   - a rule or non-inferable fact for `AGENTS.md`;
   - a dated decision for `docs/decisions.md`;
   - a detail for `docs/<topic>.md`.
   Do not save automatically — `AGENTS.md` stays short and curated (`rule-orchestrator → Память проекта`).

## Boundaries

- Handoff is a session artifact, not configuration and not code. Do not run `diagnostics file` / `check_1c_code` / `review_1c_code` against it.
- Handoff **does not replace** an OpenSpec proposal. If the task requires a proposal and it does not exist yet, additionally suggest `/opsx-propose` and reference the future ID from the handoff.
- Handoff **does not duplicate** `AGENTS.md` or `docs/decisions.md`. Memory and handoff are different channels (see `rule-orchestrator → Память проекта`).
- Handoff is written in normal grammar, not caveman style, so the next agent can read it without ambiguity.

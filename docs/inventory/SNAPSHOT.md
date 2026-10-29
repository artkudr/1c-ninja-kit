# Inventory snapshot

- Date: 2026-10-28
- Kit VERSION: 0.9.0
- Skills (kit): 19
- Skills (cc-1c-skills, внешний набор): 76 — ставится `install/cc-skills.ps1`; `skill-web-*` — kit-версии
- Rules: 33 (6 always + 27 on-demand)
- Agents: 12
- 1c-ninja-mcp: `components/1c-ninja-mcp` (in kit; static + live)
- NinjaLive: `project-scaffold/cfe/NinjaLive` (full reference copy)
- Excluded from copy: `.build`, `__pycache__`, `.browser-session.json`, `*.bak`, `node_modules`

## Skills (kit)

- skill-bsl-analyzer
- skill-env-setup
- skill-fresh-adaptation
- skill-fresh-cfe-audit
- skill-fresh-epf-audit
- skill-handoff
- skill-mcp-toolkit
- skill-ninja-mcp
- skill-project-context
- skill-query-composition
- skill-reference-data
- skill-repo-workflow
- skill-syntax-check
- skill-versioning
- skill-web-info
- skill-web-publish
- skill-web-stop
- skill-web-test
- skill-web-unpublish

## Rules

### Always-on (`profile/rules/always`)

- rule-development-process
- rule-ninja-mcp
- rule-orchestrator
- rule-bsl-analyzer
- rule-mcp-first-search
- rule-reply-style

### On-demand (`profile/rules/on-demand`)

- rule-anti-patterns
- rule-architect
- rule-async-methods
- rule-bsl-code-standards
- rule-bsl-senior-developer
- rule-bsp-developer
- rule-code-agent
- rule-dcs-design
- rule-dev-standards-architecture
- rule-extension-patterns
- rule-form-reserved-names
- rule-forms
- rule-forms-events-add
- rule-fresh
- rule-integrations-add
- rule-locks-and-transactions
- rule-logging-strategy
- rule-module-structure
- rule-platform-solutions
- rule-refactor-add
- rule-registers-design
- rule-sdd-integrations
- rule-subagent-pipeline
- rule-subagents
- rule-systematic-debugging
- rule-tooling-playbooks
- rule-verification-checklist

## Agents

- agent-analyst.md
- agent-arch-reviewer.md
- agent-architect.md
- agent-code-reviewer.md
- agent-developer.md
- agent-doc-writer.md
- agent-error-fixer.md
- agent-explorer.md
- agent-performance-optimizer.md
- agent-planner.md
- agent-refactoring.md
- agent-tester.md

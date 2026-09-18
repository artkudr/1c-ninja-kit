# Architecture (v0.1)

Краткий снимок. Полный design — в ecoladev `openspec/changes/1c-ninja-kit/design.md`.

- SoT профиля: этот репозиторий (`profile/`)
- Пара live: `components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`
- Агрегат профиля: `1c-ninja-kit`
- Stack defaults: Apache 8083/8085, MCP project-only, hardlink rules
- Public не раньше ~0.3 + bridge адаптеров

# OpenSpec project configuration ({{PROJECT_NAME}})

project:
  name: {{PROJECT_NAME}}
  description: >-
    1С-проект: основная конфигурация (`src/cf`) + расширения (`src/cfe`).
    Разработка в XML-выгрузке через скиллы контура, семантика BSL — bsl-analyzer,
    live — 1c-ninja-mcp.

context:
  tech_stack:
    - "1C:Enterprise 8.3 (CompatibilityMode {{COMPAT_MODE}})"
    - "Расширения конфигурации (src/cfe, часть в repository.json)"
    - ".v8-project.json (реестр баз) + скиллы db-*/meta-*/form-*"
  conventions:
    - "Не править XML метаданных руками — skills meta-*/form-*/cfe-*/skd-*"
    - "Load / синтакс-контроль — только скиллы контура (db-*, skill-repo-workflow, skill-syntax-check)"
    - "Семантика: bsl-analyzer-workspace; live данные: 1c-ninja-mcp live_*"
    - "OpenSpec только для крупных full-cycle задач (см. rule-orchestrator)"
    - "Факты о метаданных/API в спеках — только после MCP-подтверждения"
  constraints:
    - "Не использовать install.ps1 из ai_rules_1c"
    - "Не 1c-metadata-manage upstream"
    - "Не always-on OpenSpec на quick-fix"

# Artifact hints (file-based workflow; CLI optional)
artifacts:
  proposal:
    additional_sections:
      - "Placement (cf vs cfe)"
      - "Out of scope"
  design:
    additional_sections:
      - "Architecture decisions"
      - "Open Questions"
  tasks:
    additional_sections:
      - "Verification gates (diagnostics / validate / load)"

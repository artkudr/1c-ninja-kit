# OpenSpec project configuration ({{PROJECT_NAME}})

project:
  name: {{PROJECT_NAME}}
  description: >-
    1С-проект: основная конфигурация (`src/cf`) + расширения (`src/cfe`).
    Разработка в XML-выгрузке через autumn/vrunner, семантика BSL — bsl-analyzer,
    live — 1c-ninja-mcp.

context:
  tech_stack:
    - "1C:Enterprise 8.3 (CompatibilityMode {{COMPAT_MODE}})"
    - "Расширения конфигурации (src/cfe, часть в repository.json)"
    - "vanessa-runner 3 / autumn-properties.json"
  conventions:
    - "Не править XML метаданных руками — skills meta-*/form-*/cfe-*/skd-*"
    - "Load / syntax-check только через vrunner / repo-workflow (не Designer, не сырой ibcmd)"
    - "Семантика: bsl-analyzer-workspace; live данные: 1c-ninja-mcp live_*"
    - "OpenSpec только для крупных full-cycle задач (см. 1c-orchestrator)"
    - "Факты о метаданных/API в спеках — только после MCP-подтверждения"
  constraints:
    - "Не использовать install.ps1 из ai_rules_1c"
    - "Не 1c-metadata-manage upstream; metadata-manager agent — stub"
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

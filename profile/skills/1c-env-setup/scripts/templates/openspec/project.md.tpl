# Project Context ({{PROJECT_NAME}})

Снимок для агентов OpenSpec. Источник операционных параметров: `.v8-project.json` (не `.dev.env`). Обновляй при смене версии конфигурации или CompatibilityMode.

## Configuration

<!-- Заполнить вручную или по задаче. Для нормативных утверждений — MCP metadata/search, не память. -->

- Name: (имя конфигурации)
- CompatibilityMode: {{COMPAT_MODE}}
- Form mode: ManagedApplication
- Project kind: main configuration (`src/cf`) + extensions (`src/cfe`)

## Standard Subsystems Library

- BSP/SSL detected: (уточнить через MCP при необходимости)
- Version: (уточнить через MCP при нормативных утверждениях в спеке)

## Notes for AI Agents

- Операционка: `.v8-project.json` (запись базы, v8path, web.appName). Не угадывать URL чужой ИБ.
- CFE с хранилищем → цикл `repo-workflow`; прочие CFE → `db-load-xml -Extension` + `db-update`.
- Новые объекты в расширениях — с префиксом и `ObjectBelonging>Native` (см. `cfe-*`, `1c-versioning`).
- Если значение в этом файле устарело — проверить `src/cf/Configuration.xml` / MCP `metadata`, не выдумывать.

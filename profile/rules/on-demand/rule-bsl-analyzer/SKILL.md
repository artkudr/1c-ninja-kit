---
name: rule-bsl-analyzer
description: >-
  Семантика BSL через bsl-analyzer workspace: search, graph, symbol_info, diagnostics file.
  Load before editing an exported method or CFE, and when checking who calls what.
---

# bsl-analyzer workspace

Если в проекте подключён MCP `bsl-analyzer-workspace` — используй его для **семантики кода**, не подменяй grep/live.

Живые данные ИБ и static-поиск по выгрузке — `1c-ninja-mcp`. Синтаксис платформы и load — скиллы контура (`rule-development-process`); проверки — `rule-verification-checklist`.

## Маршрут

| Нужно | Инструмент |
|-------|------------|
| Поиск по имени/тексту в BSL | `search` `action=search_code` (см. `rule-mcp-first-search`) |
| Кто вызывает / влияние правки | `graph` (`resolve` → `callers`/`callees`) + `symbol_info` |
| Сигнатура, doc, usages | `symbol_info` (`Модуль.Метод`) |
| Замечания по модулю | `diagnostics` `file` (не весь workspace) |
| BSL во внешних EPF/ERF (если в индексе) | те же `diagnostics file` / `search` / `graph`; модель — `externals` или auto `src/epf/*`, `src/erf/*` (см. скилл) |

Перед правкой экспортного метода/CFE: `symbol_info` → `graph callers` → правка → `diagnostics file`.  
Перед правкой BSL в EPF/ERF: если объект в индексе анализатора — `diagnostics file` (+ search/graph по необходимости); иначе ninja `read_module` / `bsl_search` + `epf-validate`, не жди graph по внешнему.

Пока `graph`/`metadata` `status` = `loading` — подожди и повтори (cold graph на большой УТ ~минуты).

Скилл: `skill-bsl-analyzer`. Конфиг: `bsl-analyzer.toml` (`[source] root` / `extensions` / `externals`). Кеш: `.build`.

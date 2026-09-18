# TEST GUIDE — Hermes Agent (1c-ninja-kit v0.3)

Для аналитика на Hermes. Лог верни владельцу kit.

## Цель

Проверить развёртывание kit под **Hermes Agent**: skills в `~/.hermes/skills`, MCP в `config.yaml`, project `.hermes.md`.

## Запреты

- Не коммитить `NINJA_PASSWORD` / autumn с паролями
- В логе маскировать секреты
- Не init на чужие production-деревья без запроса

## Предусловия

1. `git clone <repo-url>`
2. При голой машине → `docs/MACHINE-BOOTSTRAP.md`
3. Hermes установлен; известен путь `~/.hermes/`

## Шаги

### 0. Лог

`logs/test-hermes-<YYYYMMDD-HHmm>.md`

### 1. Doctor / verify

```powershell
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 verify
```

### 2. Apply

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter hermes -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter hermes
```

Опционально: влить `adapters/hermes/SOUL.1c-ninja-kit.md` в `~/.hermes/SOUL.md`.

### 3. Init project

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-hermes-e2e | Out-Null
powershell -NoProfile -File .\install\kit.ps1 init-project `
  -ProjectPath C:\1C\projects\ninja-kit-hermes-e2e `
  -Adapter hermes `
  -AppName ninja-kit-hermes `
  -V8Version 8.3
```

Проверь `.hermes.md`, NinjaLive, mcp fragment в проекте.

### 4. MCP

Смержи `adapters/hermes/mcp_servers.fragment.yaml` в `~/.hermes/config.yaml` (или project overlay, если используете).  
В сессии: `/reload-mcp`. Спроси агента список MCP tools.

### 5. Live (optional)

NinjaLive load + publish + `live_version` / `live_extensions_list`.  
Иначе `partial`.

## Шаблон лога

```markdown
# TEST Hermes — 1c-ninja-kit

- Started:
- Host:
- Kit VERSION:
- Hermes version:
- Machine bootstrap done: yes/no

## doctor / verify
- exit:
- notes:

## apply -Adapter hermes
- skills under ~/.hermes/skills:
- SOUL fragment applied: yes/no

## init-project
- path:
- .hermes.md present:
- report status:

## MCP
- /reload-mcp done:
- tools visible:

## live
- skipped / results:

## Verdict
- pass | partial | fail
## Blockers
-
```

## Критерии

Как в DeepSeek guide: **pass** = apply+init+MCP+live; **partial** без ИБ; **fail** при поломке discovery/doctor.

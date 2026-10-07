# TEST GUIDE — OpenCode V2 (1c-ninja-kit v0.4)

Проверка доставки kit под **OpenCode**: глобальный профиль (`skills/`, `agents/`, `kit-rules/`, `AGENTS.md`) + project `opencode.jsonc`.

## Цель

Убедиться, что агент в OpenCode: видит always-on процессный мозг, умеет вызвать скилл по id, запускает `1c-*` субагентов и ходит в 1С MCP этого проекта.

## Запреты

- Не коммитить `opencode.jsonc` (пароль ИБ) — в git идёт `opencode.jsonc.example`
- В глобальном `~/.config/opencode/opencode.json(c)` не должно быть 1С MCP
- В логе маскировать секреты

## Предусловия

1. `kit.ps1 doctor` → `fail=0`
2. OpenCode установлен; `%USERPROFILE%\.config\opencode` существует (на Windows это и есть глобальный config dir)

## Шаги

### 0. Лог

`logs/test-opencode-<YYYYMMDD-HHmm>.md`

### 1. Doctor / verify

```powershell
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 verify
```

Ожидается `opencode profile installed: skills=<N>`.

### 2. Apply

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter opencode -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter opencode
```

Проверь руками:

| Путь | Ожидание |
|------|----------|
| `~/.config/opencode/skills/` | столько же каталогов, сколько в `profile/skills` |
| `~/.config/opencode/agents/*.md` | фронтматтер `mode: subagent` + `description`; **нет** `tools` / `allowParallel` / `model: inherit` |
| `~/.config/opencode/kit-rules/*.md` | по файлу на каждый `profile/rules/*.mdc`, без фронтматтера |
| `~/.config/opencode/AGENTS.md` | есть маркеры `<!-- 1c-ninja-kit:begin -->` / `<!-- 1c-ninja-kit:end -->`, внутри 4 always-on правила + индекс on-demand |

### 3. Init project

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-opencode-e2e | Out-Null
powershell -NoProfile -File .\install\kit.ps1 init-project `
  -ProjectPath C:\1C\projects\ninja-kit-opencode-e2e `
  -Adapter opencode `
  -AppName ninja-kit-opencode `
  -V8Version 8.3
```

Проверь: `AGENTS.md`, `opencode.jsonc`, `opencode.jsonc.example` (без секретов), `.opencode/commands/opsx-*.md`, `src/cfe/NinjaLive`, `kit-init-report.json`.

### 4. MCP

```powershell
opencode mcp list
```

Ожидается `vrunner`, `1c-ninja-mcp`, `bsl-analyzer-reference`, `bsl-analyzer-workspace`, `v8std` — `connected`.
`1c-mcp-toolkit` — `disabled` по умолчанию (EPF не всегда поднята).

В TUI: `/mcps` — те же статусы. В глобальном конфиге 1С-серверов быть не должно (doctor это проверяет).

### 5. Скиллы и агенты

В сессии попроси агента:

1. «вызови скилл `1c-env-setup`» → tool `skill` с id `1c-env-setup`
2. «вызови скилл `repo-workflow`»
3. «запусти субагента `1c-explorer`» → tool `subagent`
4. «запусти субагента `1c-architect`»

Негативные проверки: `1c-metadata-manager` и `1c-code-reviewer` не зовутся без явной просьбы.

### 6. Live (optional)

Заполнить реквизиты ИБ в `autumn-properties.json` + `opencode.jsonc` → `cfe_load NinjaLive` → publish Apache → `live_version`, `live_extensions_list`.
Без ИБ вердикт `partial`.

## Шаблон лога

```markdown
# TEST OpenCode — 1c-ninja-kit

- Started:
- Host:
- Kit VERSION:
- OpenCode version:
- Machine bootstrap done: yes/no

## doctor / verify
- fail/warn:
- notes:

## apply -Adapter opencode
- skills count:
- agents count / frontmatter clean: yes/no
- kit-rules count:
- AGENTS.md markers present: yes/no
- always-on rules inlined (4): yes/no

## init-project
- path:
- opencode.jsonc + example present:
- .opencode/commands:
- report status:

## MCP
- opencode mcp list:
- global opencode.json(c) clean: yes/no

## skills / subagents
- skill 1c-env-setup: ok/fail
- skill repo-workflow: ok/fail
- subagent 1c-explorer: ok/fail
- subagent 1c-architect: ok/fail

## live
- skipped / results:

## Verdict
- pass | partial | fail
## Blockers
-
```

## Критерии

- **pass** — apply + init + MCP connected + скилл по id + субагент + live
- **partial** — без живой ИБ (шаг 6)
- **fail** — doctor `fail>0`, скиллы не в каталоге, MCP не подключается, `AGENTS.md` без always-on правил

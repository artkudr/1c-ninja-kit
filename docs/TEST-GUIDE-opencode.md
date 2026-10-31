# TEST GUIDE — OpenCode V2 (1c-ninja-kit v0.10)

Проверка доставки kit под **OpenCode**: глобальный профиль (`skills/kit/`, `agents/`, `AGENTS.md`) + project `opencode.jsonc`.

## Цель

Убедиться, что агент в OpenCode: видит always-on процессный мозг, умеет вызвать скилл по id, запускает `agent-*` субагентов и ходит в 1С MCP этого проекта.

## Запреты

- Не коммитить `opencode.jsonc` (пароль ИБ) — он в `.gitignore`
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
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\kit.ps1 deps -DryRun
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 verify
```

`deps -DryRun` показывает план установки внешних зависимостей; `doctor` — версии и пути
уже стоящего (`fail=0 warn=0` на подготовленной машине).

Ожидается `opencode profile installed: skills=<N>`.

### 2. Apply

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply
```

Проверь руками:

| Путь | Ожидание |
|------|----------|
| `~/.config/opencode/skills/kit/skills/` | столько же каталогов, сколько в `profile/skills` |
| `~/.config/opencode/skills/kit/rules/` | on-demand правила `rule-*` |
| `~/.config/opencode/agents/agent-*.md` | фронтматтер `mode: subagent` + `description`; **нет** `tools` / `allowParallel` / `model: inherit` |
| `~/.config/opencode/skills\kit\rules/*.md` | по файлу на каждый `profile/rules/`, без фронтматтера |
| `~/.config/opencode/AGENTS.md` | есть маркеры `<!-- 1c-ninja-kit:begin -->` / `<!-- 1c-ninja-kit:end -->`, внутри always-on `rule-*`; индекса on-demand нет |

### 3. Init project

Новый проект создаёт скилл `skill-env-setup`.

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-opencode-e2e | Out-Null
powershell -NoProfile -File "$env:USERPROFILE\.config\opencode\skills\kit\skills\skill-env-setup\scripts\env-setup.ps1" `
  -Mode Init `
  -ProjectRoot C:\1C\projects\ninja-kit-opencode-e2e `
  -AppName ninja-kit-opencode `
  -V8Version 8.3 `
  -WebPort 8083 `
  -SkipSyncCfe
```

Проверь: `AGENTS.md`, `opencode.jsonc`, `src/cfe/NinjaLive`, `.ignore`, `build/out/cfe`, `docs/dev-stack.md`.

### 4. MCP

```powershell
opencode mcp list
```

Ожидается `1c-ninja-mcp`, `bsl-analyzer-reference`, `bsl-analyzer-workspace`, `v8std` — `connected`.
`1c-mcp-toolkit` — `disabled` по умолчанию (EPF не всегда поднята).

В TUI: `/mcps` — те же статусы. В глобальном конфиге 1С-серверов быть не должно (doctor это проверяет).

### 5. Скиллы и агенты

В сессии попроси агента:

1. «вызови скилл `skill-env-setup`» → tool `skill` с id `skill-env-setup`
2. «вызови скилл `skill-repo-workflow`»
3. «запусти субагента `agent-explorer`» → tool `subagent`
4. «запусти субагента `rule-architect`»

Негативная проверка: `agent-code-reviewer` не зовётся без явной просьбы.

### 6. Live (optional)

Заполнить реквизиты ИБ в `.v8-project.json` + `opencode.jsonc` → `db-load-xml -Extension "NinjaLive"` → publish Apache → `live_version`, `live_extensions_list`.
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

## apply
- skills count:
- agents count / frontmatter clean: yes/no
- skills\kit\rules count:
- AGENTS.md markers present: yes/no
- always-on rules inlined (4): yes/no

## env-setup
- path:
- opencode.jsonc + example present:
- .opencode/commands:
- AGENTS.md / .ignore / build/out/cfe:
- NinjaLive source:

## MCP
- opencode mcp list:
- global opencode.json(c) clean: yes/no

## skills / subagents
- skill skill-env-setup: ok/fail
- skill skill-repo-workflow: ok/fail
- subagent agent-explorer: ok/fail
- subagent agent-architect: ok/fail

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

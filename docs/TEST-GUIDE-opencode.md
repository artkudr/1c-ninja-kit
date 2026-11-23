# TEST GUIDE — OpenCode V2 (1c-ninja-kit v0.11)

Проверка доставки kit под **OpenCode**: пути скиллов/правил в `~/.config/opencode/opencode.jsonc`, копии `agents/`, `commands/`, `scripts/` + project `opencode.jsonc`.

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

### 2. Apply и stage

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply
powershell -NoProfile -File .\install\kit.ps1 stage -ProjectRoot <проект>
```

Проверь руками:

| Путь | Ожидание |
|------|----------|
| `~/.config/opencode/opencode.jsonc` | `$schema`; в `skills`/`instructions` нет путей кита (прежняя модель убрана) |
| `~/.config/opencode/skills/` | внешние `cc-1c-skills` (`db-*`, …), без каталога `kit` |
| `~/.config/opencode/agents/` | те же `*.md`, что в `profile/agents`, байт-в-байт |
| `~/.config/opencode/commands/` | `Задача.md`, `Продолжить.md`, `Статус.md` |
| `~/.config/opencode/scripts/run.ps1` | совпадает с `profile/scripts/run.ps1` |
| `~/.config/opencode/AGENTS.md` | без маркеров `1c-ninja-kit` (правила идут через `instructions`) |
| `<проект>/.opencode/skills` | 49 каталогов `skill-*`/`rule-*`, у каждого `SKILL.md`; без `node_modules` |
| `<проект>/.opencode/rules/always` | 8 файлов `rule-*.md` |
| `<проект>/opencode.jsonc` | `instructions` содержит `.opencode/rules/always/*.md`, MCP не тронут |

### 3. Init project

Новый проект создаёт скилл `skill-env-setup`.

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-opencode-e2e | Out-Null
powershell -NoProfile -File "C:\1C\projects\1c-ninja-kit\profile\skills\skill-env-setup\scripts\env-setup.ps1" `
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
3. «запусти субагента `Коммандер`» → tool `subagent`
4. «вызови правило `rule-architect`» → tool `skill`

Негативная проверка: роль `Бард` не зовётся без задачи (`/Задача` → `next`/`start`).

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

## apply / stage
- global opencode.jsonc: $schema yes/no; kit paths removed yes/no
- skills\kit removed: yes/no
- global AGENTS.md kit block removed: yes/no
- agents count / commands count / scripts count:
- project: skills count / always rules count / instructions in opencode.jsonc: yes/no
- skills paths point into kit repo: yes/no

## env-setup
- path:
- opencode.jsonc + example present:
- Задачи/ created:
- AGENTS.md / .ignore / build/out/cfe:
- NinjaLive source:

## MCP
- opencode mcp list:
- global opencode.json(c) clean: yes/no

## skills / subagents
- skill skill-env-setup: ok/fail
- skill skill-repo-workflow: ok/fail
- subagent Коммандер: ok/fail
- роль по `/Задача` (Коммандер → Колдун): ok/fail

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
- **fail** — doctor `fail>0`, скиллы не в каталоге, MCP не подключается, в `instructions` нет always-on правил

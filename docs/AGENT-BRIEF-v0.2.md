# AGENT BRIEF — 1c-ninja-kit v0.2 (чистый профиль Cursor)

Скопируй **весь этот файл** агенту в **новом** профиле Cursor.  
Цель: развернуть kit на чистом профиле, поднять **новый** тестовый проект (не ecoladev), записать лог.  
Лог верни человеку — он передаст в другой чат. **Не** пиши в `C:\1C\projects\ecoladev` и **не** запускай там init.

---

## Жёсткие запреты

1. **Не открывать / не менять** `C:\1C\projects\ecoladev` (и не `kit init-project` на него).
2. **Не** класть 1С MCP-серверы в `%USERPROFILE%\.cursor\mcp.json` (только project mcp).
3. **Не** делать directory junction на `.cursor/rules`.
4. **Не** коммитить секреты; в лог — без паролей (маскируй `***`).
5. **Не** публиковать kit на GitHub.

---

## Контекст

- Kit: `C:\1C\projects\1c-ninja-kit` (VERSION **0.2.0**)
- CLI: `powershell -NoProfile -File C:\1C\projects\1c-ninja-kit\install\kit.ps1 <cmd>`
- Пара live: `components/1c-ninja-mcp` + `project-scaffold/cfe/NinjaLive`
- Порты: платформа **8.3 → 8083** (`apache-83`), **8.5 → 8085** (`apache-85`)
- Docs: `docs/LAYERS.md`, `docs/stack-defaults.md`, `docs/ADAPTATION.md`, `docs/e2e-v0.2.md`

---

## Среда

Предполагается **та же Windows-машина** (софт уже стоит), но **новый профиль Cursor** (пустой/почти пустой `%USERPROFILE%\.cursor\skills|rules|agents`).

Если это другой USERPROFILE — пути `%USERPROFILE%` свои; kit путь тот же.

---

## Порядок работ (обязательный)

### Шаг 0 — лог

Создай файл лога:

`C:\1C\projects\1c-ninja-kit\logs\e2e-v0.2-<YYYYMMDD-HHmm>.md`

Пиши туда по шаблону в конце этого брифа **после каждого шага**.

### Шаг 1 — doctor / verify

```powershell
cd C:\1C\projects\1c-ninja-kit
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 verify
```

- doctor exit ≠ 0 → статус `blocked`, стоп, в лог вывод.
- WARN по apache-85 допустим, если тестируешь только 8.3.

### Шаг 2 — apply профиля

Сначала dry-run, потом apply:

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply
```

Проверь:

- появились skills/rules/agents в `%USERPROFILE%\.cursor\`
- user `mcp.json` **без** имён: `vrunner`, `1c-ninja-mcp`, `1c-mcp-toolkit`, `bsl-analyzer-*`  
  Если серверы есть — вычисти или сделай backup и оставь `mcpServers: {}`.

### Шаг 3 — новый проект (НЕ ecoladev)

Создай пустую папку, например:

`C:\1C\projects\ninja-kit-e2e`

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-e2e | Out-Null
powershell -NoProfile -File C:\1C\projects\1c-ninja-kit\install\kit.ps1 init-project `
  -ProjectPath C:\1C\projects\ninja-kit-e2e `
  -AppName ninja-kit-e2e `
  -V8Version 8.3
```

Если человек дал ИБ — добавь `-IbConnection '...' -DbUser '...' -DbPwd '...'` (в лог пароль не писать).

Проверь `kit-init-report.json` в проекте: `status` = `needs-human` или `ready-for-load`.

### Шаг 4 — live (только если есть ИБ и человек подтвердил)

Если credentials placeholder / нет ИБ → в лог `needs-human: IB` и **стоп** (это успешный partial E2E профиля+scaffold).

Если ИБ есть:

1. Загрузи CFE `NinjaLive` через vrunner MCP `cfe_load` (или CLI vrunner) из `src/cfe/NinjaLive`.
2. Опубликуй web на порту **8083** (для 8.3), appName как в init.
3. В Cursor подключи project MCP из `ninja-kit-e2e\.cursor\mcp.json`.
4. Вызови `live_version`, затем `live_extensions_list`.
5. Результат (без секретов) — в лог.

**Не** используй `vrunner infobase extensions list` / MCP `extensions_list` как канон.

### Шаг 5 — финальный лог

Закрой лог секцией `## Verdict` (`pass` / `partial` / `fail`) и списком `## Blockers`.

---

## Критерии успеха

| Уровень | Что |
|--------|-----|
| **partial (ок для первого прогона)** | doctor+verify+apply+init-project на `ninja-kit-e2e`; report написан; ecoladev не тронут |
| **pass** | + NinjaLive load + `live_version` + `live_extensions_list` |
| **fail** | init на ecoladev; сломан профиль; секреты в логе; doctor required fail без объяснения |

---

## Шаблон лога (копируй в файл)

```markdown
# E2E 1c-ninja-kit v0.2

- Started: <ISO datetime>
- Agent profile: <новый Cursor profile name / USERPROFILE>
- Kit path: C:\1C\projects\1c-ninja-kit
- Kit VERSION: (from file)
- Target project: C:\1C\projects\ninja-kit-e2e
- ecoladev touched: NO

## Step 1 doctor
- exit: 
- summary:
- notes:

## Step 1b verify
- exit:
- skills/rules/agents counts:

## Step 2 apply
- dry-run ok:
- apply ok:
- user mcp has 1C servers: yes/no

## Step 3 init-project
- command used (mask secrets):
- kit-init-report status:
- NinjaLive present:
- mcp points to kit components/1c-ninja-mcp: yes/no
- web port:

## Step 4 live (or skipped)
- skipped reason: / results live_version / live_extensions_list:

## Verdict
- pass | partial | fail
## Blockers
- 
## Artifacts paths
- log:
- kit-init-report.json:
```

---

## Что сказать человеку в конце

Одной фразой: путь к лог-файлу + verdict. Секреты не цитировать.

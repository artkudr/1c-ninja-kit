# TEST GUIDE — DeepSeek Harness (1c-ninja-kit v0.3)

Для прогона на ноутбуке / машине с DSH. Лог верни владельцу kit.

## Цель

Проверить, что агент на **DeepSeek Harness** разворачивает kit и доходит минимум до scaffold (+ live, если есть ИБ).

## Запреты

- Не пушить секреты
- Не ломать чужие профили без backup
- Пароли в логе → `***`

## Предусловия

1. Клон: `git clone <repo-url> 1c-ninja-kit && cd 1c-ninja-kit`
2. Если кроме 1С ничего нет → сначала `docs/MACHINE-BOOTSTRAP.md`
3. DSH установлен; skill roots: `~/.agents/skills` или `~/.dsh/skills`

## Шаги

### 0. Лог

Создай `logs/test-deepseek-<YYYYMMDD-HHmm>.md` по шаблону ниже.

### 1. Doctor / verify

```powershell
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 verify
```

### 2. Apply adapter

```powershell
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter deepseek -DryRun
powershell -NoProfile -File .\install\kit.ps1 apply -Adapter deepseek
```

Проверь наличие skills в `%USERPROFILE%\.agents\skills\` (или `.dsh\skills`).

### 3. Init project

```powershell
New-Item -ItemType Directory -Force -Path C:\1C\projects\ninja-kit-dsh-e2e | Out-Null
powershell -NoProfile -File .\install\kit.ps1 init-project `
  -ProjectPath C:\1C\projects\ninja-kit-dsh-e2e `
  -Adapter deepseek `
  -AppName ninja-kit-dsh `
  -V8Version 8.3
```

Проверь: `AGENTS.md`, NinjaLive, mcp example, `kit-init-report.json`.

### 4. MCP в DSH

Подключи серверы по `adapters/deepseek/mcp.example.json` (подставь KIT_ROOT / APP / credentials).  
Убедись, что tools видны как `mcp__...`.

### 5. Live (optional)

Если ИБ есть: load NinjaLive → publish → `live_version` → `live_extensions_list`.  
Иначе verdict=`partial`.

## Шаблон лога

```markdown
# TEST DeepSeek Harness — 1c-ninja-kit

- Started:
- Host: (laptop/desktop)
- Kit VERSION:
- DSH version / how installed:
- Machine bootstrap done: yes/no

## doctor / verify
- exit codes:
- notes:

## apply -Adapter deepseek
- skills count in ~/.agents/skills:
- issues:

## init-project
- path:
- AGENTS.md present:
- NinjaLive present:
- report status:

## MCP
- servers connected:
- sample tool name seen:

## live
- skipped / results (mask secrets):

## Verdict
- pass | partial | fail
## Blockers
-
```

## Критерии

| Verdict | Meaning |
|---------|---------|
| pass | apply + init + MCP tools visible + live_extensions_list |
| partial | apply + init OK; live/MCP blocked by missing IB/soft |
| fail | doctor required fail; skills not discovered; init broke |

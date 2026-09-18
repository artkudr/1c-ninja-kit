---
name: sync-cc-1c-skills
description: >-
  Синхронизация XML/мета-скиллов 1С из GitHub Nikolay-Shirokov/cc-1c-skills
  (ветка port-cursor) в глобальные Cursor skills. Используй когда нужно обновить
  cc-1c-skills, прогнать classify/purge, soft-rewrite (strip .v8-project) или
  promote из promote-whitelist без затирания overlay.
---

# sync-cc-1c-skills

Глобальный контур (не project skills):

| Роль | Путь |
|------|------|
| Этот скилл + политики | `%USERPROFILE%\.cursor\skills\sync-cc-1c-skills\` |
| Карантин | `%USERPROFILE%\.cursor\devccskills\` |
| Live skills | `%USERPROFILE%\.cursor\skills\` |
| Пути в SKILL.md после rewrite | `%USERPROFILE%\.cursor\skills\<name>\scripts\...` |

Канон: **vrunner + autumn**, без `.v8-project.json`. Апстримные `db-*` / `epf-build` / `erf-build` / `epf-dump` / `erf-dump` / апстримный `web-publish` — в `hard-drop` (dump заменён `1c-ninja-mcp` `epf_decompile`).

## Политики (`policies/`)

| Файл | Назначение |
|------|------------|
| `known-ccskills.json` | Снимок имён апстрима; вне списка = new → только отчёт |
| `hard-drop.json` | Чёрный список — purge из quarantine, не в live |
| `quarantine-study.json` | Не promote, держать в карантине |
| `overlay-preserve.json` | Локальные — никогда не затирать (`1c-*`, `vrunner-mcp`, `repo-workflow`, `web-*`, `sync-cc-1c-skills`, …) |
| `whitelist.json` | **Одобренные** кандидаты на rewrite (не live напрямую) |
| `soft-transform.json` | `stripV8Hooks` + `rewriteSkillOnly` + pathRewrite; `transformsDeferred: false` |
| `promote-whitelist.json` | **Готовы к live** — заполняет `rewrite.ps1`; `-Promote` копирует только их |

## Пайплайн

```
sync.ps1  →  rewrite.ps1  →  sync.ps1 -Promote
 (fetch,     (strip+path,      (только promote-whitelist
  purge,      promote-whitelist)  → live, overlay skip)
  classify)
```

1. **sync** (дефолт): fetch/mirror → purge hard-drop → classify относительно **whitelist** → `LAST-SYNC.md`. Live не трогает.
2. **rewrite**: strip v8-hooks (всегда deny) + path rewrite по quarantine → пишет `promote-whitelist.json` + `LAST-REWRITE.md`.
3. **Promote**: копирует в live **только** имена из `promote-whitelist.json`, которые есть в quarantine после rewrite. Overlay never overwrite. Whitelist без rewrite в live не идёт.

## Команды

```powershell
# 1) Обновить quarantine (live не трогает)
powershell -NoProfile -File "%USERPROFILE%\.cursor\skills\sync-cc-1c-skills\scripts\sync.ps1"
# опционально локальный клон:
# ...\sync.ps1 -SourcePath "%TEMP%\cc-1c-skills-port-cursor"

# 2) Soft-rewrite в quarantine
powershell -NoProfile -File "%USERPROFILE%\.cursor\skills\sync-cc-1c-skills\scripts\rewrite.ps1"

# 3) В live — только после rewrite, по отдельной просьбе
powershell -NoProfile -File "%USERPROFILE%\.cursor\skills\sync-cc-1c-skills\scripts\sync.ps1" -Promote
powershell -NoProfile -File "%USERPROFILE%\.cursor\skills\sync-cc-1c-skills\scripts\sync.ps1" -PromoteOnly
```

Опционально: `-SkipFetch`, `-SourcePath`.

## Что делает rewrite.ps1

Для **каждого** имени из `whitelist.json`, что есть в quarantine и не hard/study:

| Условие | Действие |
|---------|----------|
| в `stripV8Hooks` | Убрать `Find-V8Project` / `_sg_find_v8project`; `Get-EditMode` / `_sg_get_edit_mode` → всегда `"deny"`; `Get-NewObjectPosition` → всегда `"end"`; поправить offNote (без `.v8-project` / db-list) |
| иначе | Только path rewrite |
| все + `cfe-*` SKILL | Path → `%USERPROFILE%\.cursor\skills\<любое-имя>\` (cross-skill тоже, напр. erf→epf); убрать «прочитай .v8-project» → `1c-project-context` / `src/cf`; `__pycache__` удаляется при rewrite и не копируется при promote |

Успешно обработанные → `promote-whitelist.json`. Повторный запуск идемпотентен.

## Promote-правила

1. `hard-drop` — никогда в live из апстрима  
2. `overlay-preserve` — никогда не трогать  
3. имена вне `known-ccskills` — только отчёт (new)  
4. `quarantine-study` — не promote  
5. `promote-whitelist` — единственные, кого `-Promote` копирует (после rewrite)

## После прогона

Покажи краткий отчёт: `LAST-SYNC.md` и/или `LAST-REWRITE.md` (dropped / study / whitelist / promote-whitelist count / sample strip).

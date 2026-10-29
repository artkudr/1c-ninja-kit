---
name: skill-web-info
description: Статус Apache и веб-публикаций 1С — запущен ли сервер, какие базы опубликованы, ошибки. Используй когда пользователь спрашивает про статус веб-сервера, опубликованные базы, работает ли Apache
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
---

# /skill-web-info — Статус профильного Apache

По платформе из `.v8-project.json` (`v8path`): `%USERPROFILE%\tools\apache-83` (8083) или `apache-85` (8085).

```powershell
powershell.exe -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/skill-web-info.ps1"
```

Опционально `-ApachePath` / `-V8Version`.

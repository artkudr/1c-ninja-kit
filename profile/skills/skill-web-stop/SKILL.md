---
name: skill-web-stop
description: Остановка Apache HTTP Server. Используй когда пользователь просит остановить веб-сервер, Apache, прекратить веб-публикацию
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
---

# /skill-web-stop — Остановка профильного Apache

Останавливает httpd профиля (`apache-83` / `apache-85` по платформе из `.v8-project.json`).

```powershell
powershell.exe -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/skill-web-stop.ps1"
```

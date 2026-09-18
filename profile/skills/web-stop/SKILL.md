---
name: web-stop
description: Остановка Apache HTTP Server. Используй когда пользователь просит остановить веб-сервер, Apache, прекратить веб-публикацию
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Glob
---

# /web-stop — Остановка профильного Apache

Останавливает httpd профиля (`apache-83` / `apache-85` по `v8version` проекта).

```powershell
powershell.exe -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/web-stop.ps1"
```

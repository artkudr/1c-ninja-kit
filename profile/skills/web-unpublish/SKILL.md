---
name: web-unpublish
description: Удаление веб-публикации 1С из Apache. Используй когда пользователь просит убрать публикацию, удалить веб-доступ к базе
argument-hint: "<appname | --all>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
---

# /web-unpublish — Удаление публикации из профильного Apache

Удаляет блок из `httpd.conf` и каталог `publish/{appname}` в `%USERPROFILE%\tools\apache-83|85`.

```powershell
powershell.exe -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/web-unpublish.ps1" -AppName "ecoladev-agent-test"
# или -All
```

AppName по умолчанию из autumn `web.appName`, если не передан.

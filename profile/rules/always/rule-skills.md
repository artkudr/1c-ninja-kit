# Skills

Скиллы приходят из двух источников:

- kit — прямо из репозитория кита: `profile/skills/<id>/SKILL.md` и `profile/rules/on-demand/<id>/SKILL.md` (пути прописаны в `skills` глобального `~/.config/opencode/opencode.jsonc`, ставит `kit.ps1 apply`);
- внешние (`cc-1c-skills`) — `%USERPROFILE%\.config\opencode\skills\<id>\SKILL.md`, не переименовываются.

Скилл вызывается tool `skill` по точному id (это имя каталога). Набор роли ограничен правами: скилл вне набора не загружается, и это штатный ответ, а не сбой. Шаг, для которого у роли нет прав, выполняет ведущий агент или человек; обходить ограничение не нужно и нельзя.

Частые: `skill-env-setup`, `skill-project-context`, `skill-ninja-mcp`, `skill-bsl-analyzer`, `skill-repo-workflow`, `skill-web-test`, `skill-handoff`, `rule-anti-patterns`, `rule-forms`.

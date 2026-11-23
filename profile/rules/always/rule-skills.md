# Skills

Скиллы приходят из двух источников:

- kit — `profile/skills/<id>/SKILL.md` и `profile/rules/on-demand/<id>/SKILL.md`
  в репозитории кита; в проект они попадают копией в `.opencode/skills`
  командой `kit.ps1 stage` (её вызывает разворачивание окружения);
- внешние (`cc-1c-skills`) — `%USERPROFILE%\.config\opencode\skills\<id>\SKILL.md`,
  не переименовываются.

Скилл вызывается tool `skill` по точному id (это имя каталога). Набор роли ограничен правами: скилл вне набора не загружается, и это штатный ответ, а не сбой. Шаг, для которого у роли нет прав, выполняет ведущий агент или человек; обходить ограничение не нужно и нельзя.

Частые: `skill-env-setup`, `skill-project-context`, `skill-ninja-mcp`, `skill-bsl-analyzer`, `skill-repo-workflow`, `skill-web-test`, `skill-handoff`, `rule-anti-patterns`, `rule-forms`.

Новый скилл в ките: выдай его ролям в `profile/agents/*.md`, прогони `kit.ps1 lock`, `apply` и `stage -ProjectRoot <проект>`. Списки скиллов живут в файлах ролей; забытый грант — это `permission denied` уже в работе.

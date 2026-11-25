# Profile SoT

Канон skills / rules / agents / commands / scripts для поставки.

- Skills и rules едут **в проект**: `kit.ps1 stage -ProjectRoot <проект>` кладёт копию
  в `<проект>\.opencode\skills` и `<проект>\.opencode\rules\always`, а в проектном
  `opencode.jsonc` прописывает `instructions` на `.opencode/rules/always/*.md`.
  Глобальный конфиг путей кита не знает — `kit.ps1 apply` их оттуда убирает.
- Agents, commands и `run.ps1` копируются глобально: `{{AGENTS_ROOT}}`,
  `{{COMMANDS_ROOT}}`, `~/.config/opencode/scripts` — OpenCode берёт их только оттуда.
- Копии — не байт-в-байт: `stage` и `apply` подставляют плейсхолдеры
  (`{{KIT_ROOT}}`, `{{CC_SKILLS_ROOT}}`, `{{PIPA_*}}`, `{{SKILLS_ROOT}}`, …).
  Источник значений — машинный профиль `install/path-defaults.windows.yaml`
  по ключам `ccSkills.skillsRoot`, `pipa.url`, `pipa.keyFile`, `pipa.home`,
  `mcpPolicy.userMcp`, `mcpPolicy.projectMcp`; остальные значения — константы
  renderer'а или вычисление по слою. `pipa.home` — не подстановка, а дефолт для
  переменной `PIPA_HOME`: её ставит `apply`. `{{PROJECT_MCP}}` — имя файла
  проектного конфига: ключ `mcpPolicy.projectMcp`, иначе фактический
  `opencode.jsonc`/`opencode.json` проекта, иначе `opencode.jsonc`.
  Переменные процесса на подстановку не влияют (кроме токена `NINJA_KIT_ROOT`).
  `CC_SKILLS_ROOT`, `PIPA_URL`, `PIPA_HOME`, `PIPA_KEY_FILE` — рантайм-контракт
  агента, не вход подстановки. В текст попадает env-форма (`$env:VAR`) или
  относительный путь.
  Поэтому в `profile/**` нет путей с буквой диска, и `kit.ps1 verify` это проверяет.
- Агрегат: `profiles/1c-ninja-kit.yaml`
- Docs: `docs/`

Обновление SoT: правка `profile/`, затем `kit.ps1 lock` (если менялся состав),
`kit.ps1 apply` и `stage` в проекты; живой профиль не является источником.

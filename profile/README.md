# Profile SoT

Канон skills / rules / agents / commands / scripts для поставки.

- Skills и rules читаются OpenCode прямо из репозитория: пути прописаны в `skills` и `instructions` глобального `%USERPROFILE%\.config\opencode\opencode.jsonc` (`kit.ps1 apply`).
- Agents, commands и `run.ps1` копируются в `%USERPROFILE%\.config\opencode\{agents,commands,scripts}` — OpenCode берёт их только оттуда.
- Агрегат: `profiles/1c-ninja-kit.yaml`
- Docs: `%USERPROFILE%\.config\opencode\docs\`

Обновление SoT: правка `profile/` и `kit.ps1 apply`; живой профиль не является источником.

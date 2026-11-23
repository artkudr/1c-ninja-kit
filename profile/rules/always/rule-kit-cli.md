# Kit CLI

```text
kit.ps1 doctor
kit.ps1 verify [-ProjectRoot <проект>]
kit.ps1 stage -ProjectRoot <проект>
kit.ps1 apply
kit.ps1 lock
kit.ps1 deps
```

Модель раздачи — **проектная**. `kit.ps1 stage -ProjectRoot <проект>` копирует
скиллы `profile/skills` и on-demand правила `profile/rules/on-demand` в
`<проект>\.opencode\skills`, always-on правила — в `<проект>\.opencode\rules\always`,
и прописывает `instructions` в проектный `opencode.jsonc`. Дальше проект
самодостаточен: глобальный конфиг скиллы и правила не раздаёт.

`kit.ps1 apply` держит только машинный слой: копирует агентов, команды и
`run.ps1` в `~/.config/opencode/{agents,commands,scripts}` и убирает из
глобального конфига пути кита, если они остались от прежней модели.

Новый проект разворачивает `skill-env-setup` — он же вызывает `stage`. Правка
`profile/` доезжает до проекта повторным `stage`; `verify -ProjectRoot` сверяет
копию с профилем файл за файлом. `kit.ps1 lock` пересобирает
`lock/profile.lock.json`; `verify` падает, если снимок разошёлся (канон хеша —
`docs/versioning.md`).

Внешние зависимости машины (OneScript, bsl-analyzer, ripgrep, Node/Playwright,
Apache, toolkit) ставит `kit.ps1 deps`; версии и адреса — `companions/pins.json`.

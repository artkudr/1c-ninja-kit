# Kit CLI

```text
kit.ps1 doctor
kit.ps1 verify
kit.ps1 apply
kit.ps1 lock
kit.ps1 deps
```

`kit.ps1 apply` кладёт скиллы и правила путями в глобальный `~/.config/opencode/opencode.jsonc` (`skills`, `instructions`), а агентов, команды и `taskctl.ps1` копирует в `~/.config/opencode/{agents,commands,scripts}`. `verify` сверяет доставку с профилем.

`kit.ps1 lock` пересобирает `lock/profile.lock.json` из фактического состава `profile/`; `verify` падает, если снимок разошёлся (канон хеша — `docs/versioning.md`).

Внешние зависимости машины (OneScript, bsl-analyzer, ripgrep, Node/Playwright, Apache, toolkit) ставит `kit.ps1 deps`; версии и адреса — `companions/pins.json`.

Новый проект разворачивает `skill-env-setup` («разверни окружение»): структура, конфиги, `AGENTS.md`. Скилл есть не у каждой роли — если он закрыт, развёртывание делает человек.

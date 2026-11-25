# 1c-ninja-kit

Агентная обвязка разработки 1С: skills (kit + cc-1c-skills), rules, MCP (**1c-ninja-mcp** + CFE **NinjaLive**), bsl-analyzer, харнесс **OpenCode**.

**VERSION:** 0.13.4 (источник — файл `VERSION`)

## Quick start

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git
cd 1c-ninja-kit
# Платформа 1С — своим дистрибутивом; всё остальное ставит deps:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\kit.ps1 deps
powershell -NoProfile -File .\install\kit.ps1 doctor
powershell -NoProfile -File .\install\kit.ps1 apply
# скиллы и правила в конкретный проект:
powershell -NoProfile -File .\install\kit.ps1 stage -ProjectRoot C:\1C\projects\<проект>
```

Подробности машинного слоя: `docs/MACHINE-BOOTSTRAP.md`.

## Harness

Харнесс один — **OpenCode**. Скиллы и правила ставятся **в проект** командой
`kit.ps1 stage -ProjectRoot <проект>` (копия в `.opencode`, `instructions` в
проектном `opencode.jsonc`); глобально копируются только агенты, команды и
`run.ps1`. Почему так и что проверяет `verify` — `docs/opencode.md`. Проверка
доставки: `docs/TEST-GUIDE-opencode.md`.

Пути не зашиты в тексты: `stage` и `apply` подставляют их из машинного профиля
`install/path-defaults.windows.yaml` (плейсхолдеры `{{KIT_ROOT}}`,
`{{CC_SKILLS_ROOT}}`, `{{PIPA_*}}` и др.), а `apply` выставляет в пользовательскую
среду `NINJA_KIT_ROOT` и `PIPA_HOME`. Правило линта в `verify` не даёт вернуть в
профиль путь с буквой диска. Подробности — `docs/MCP-PLACEHOLDERS.md`.

## Каркас задачи

Один на машину, глобальный: команды `/Задача`, `/Продолжить`, `/Статус` в
`~/.config/opencode/commands`. Состояние задачи живёт в сервисе **PiPa**
(PithosPandoras, MCP `pipa`), в проекте — только папка `Задачи/` с файлами.
Имя проекта агент берёт из `AGENTS.md`.

Сам сервис в кит не входит: ставится из Releases
[`artkudr/pithos-pandoras`](https://github.com/artkudr/pithos-pandoras/releases)
(zip, Rust для установки не нужен), MCP — `http://127.0.0.1:8787/mcp`, ключ
печатает `pithos-pandoras.exe key`. Как агент находит сервис на машине
(`PIPA_URL`, `PIPA_HOME`, проверка `/health`) — скилл `skill-pipa`.

## What is inside

| Path | Content |
|------|---------|
| `profile/` | skills / rules / agents |
| `components/1c-ninja-mcp/` | MCP server (part of kit) |
| `project-scaffold/cfe/NinjaLive/` | Live CFE pair |
| `install/kit.ps1` | doctor / verify / apply / lock / deps |
| `profile/scripts/run.ps1` | единая точка запуска скриптов скиллов (`apply` копирует в `~/.config/opencode/scripts`) |
| `profile/commands/` | глобальные команды `/Задача`, `/Продолжить`, `/Статус` |
| `install/deps.ps1` | установка внешних зависимостей (OneScript, bsl-analyzer, ripgrep, Node/Playwright, Apache, toolkit) |
| `docs/opencode.md` | единственный харнесс: пути в конфиге, копии, MCP, ограничения |
| `docs/NAMING.md` | контракт имён `skill-` / `rule-` и ролей-агентов |
| `docs/MACHINE-BOOTSTRAP.md` | bare PC: что ставит `kit.ps1 deps`, что остаётся руками |
| `docs/MCP-PLACEHOLDERS.md` | плейсхолдеры путей, источник значений, линт профиля |
| `companions/pins.json` | upstream GitHub URLs для companion-бинарников |

## Hard rules

- Do not put 1C MCP secrets in global user config committed to git
- Apache **8083** for platform 8.3, **8085** for 8.5
- CFE list via `live_extensions_list`
- See `NOTICE.md` for third-party attribution

## License / notice

See `NOTICE.md`. Third-party tools (OneScript, vanessa-runner, bsl-analyzer, Apache, platform 1C) remain under their own terms and are **not** vendored as binaries here.

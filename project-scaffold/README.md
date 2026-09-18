# Project scaffold

Шаблоны из `1c-env-setup` + эталон **NinjaLive** + OpenSpec stubs.

## Использование (v0.1)

1. Возьми tpl из `templates/` (не hardcode ecoladev).
2. Скопируй `cfe/NinjaLive/` → `<project>/src/cfe/NinjaLive/`.
3. В mcp: `AUTUMN_MAIN` = `{kit}/components/1c-ninja-mcp/main.os`.
4. Порт web: 8083 (8.3) / 8085 (8.5) — `docs/stack-defaults.md`.
5. Либо вызови скилл `1c-env-setup` («разверни окружение»), указав SourceProject / kit как эталон NinjaLive.

`kit init-project` — полноценно в v0.2.

## Secrets

См. корневой `.gitignore` и `docs/SECRETS.md`. В шаблоны пароли не писать.

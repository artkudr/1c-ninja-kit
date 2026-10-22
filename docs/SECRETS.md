# SECRETS

## Никогда не коммитить

- `.v8-project.json` (часто содержит `db-pwd`, реквизиты хранилищ)
- `opencode.jsonc` проекта (`NINJA_PASSWORD`, пути с учётками)
- `env.json` / `.env` с паролями
- Живые URL прод с credentials в query

## В git — только шаблоны

- `*.example`, `*.tpl`, `opencode.jsonc.example`
- Placeholders: `{{BSL_USER}}`, `{{BSL_PASSWORD}}`, `<пароль>` и т.п.

## Политика MCP

- Секреты live — **только** project mcp (gitignore).
- User-конфиг — пустой по 1С-серверам.

## Скан перед коммитом

```powershell
rg -i "password|db-pwd|NINJA_PASSWORD|Secret" --glob "!NOTICE.md"
```

(или аналог Select-String). Совпадения в tpl/NOTICE — ок; реальные пароли — стоп.

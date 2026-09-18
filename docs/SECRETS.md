# SECRETS

## Никогда не коммитить

- `autumn-properties.json` (часто содержит `db-pwd`)
- `.cursor/mcp.json` (`NINJA_PASSWORD`, пути с учётками)
- `env.json` / `.env` с паролями
- Живые URL прод с credentials в query

## В git — только шаблоны

- `*.example`, `*.tpl`, `mcp.json.example`
- Placeholders: `{{BSL_USER}}`, `{{BSL_PASSWORD}}`, `<пароль>` и т.п.

## Политика MCP

- Секреты live — **только** project mcp (gitignore).
- User mcp — пустой по 1С-серверам.

## Скан перед коммитом

```powershell
rg -i "password|db-pwd|NINJA_PASSWORD|Secret" --glob "!NOTICE.md" --glob "!**/docs-patches/**"
```

(или аналог Select-String). Совпадения в tpl/NOTICE — ок; реальные пароли — стоп.

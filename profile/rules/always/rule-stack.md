# Stack defaults

- Платформа **8.3** → Apache **8083**, tools `%USERPROFILE%\tools\apache-83`; **8.5** → **8085**.
- Web-URL включают `/ru_RU/`.
- 1С MCP — **только** в project `opencode.jsonc`. Глобальный `~/.config/opencode/opencode.json(c)` без 1С-серверов и секретов.
- Ninja-пара: kit `components/1c-ninja-mcp` + project `src/cfe/NinjaLive` (`/hs/ninja-live`).
- Запрещено: внешние MCP и реестры для операций с конфигурацией и ИБ; ручные вызовы Конфигуратора в обход скиллов контура; правка XML метаданных вручную.
- Отвечать пользователю на **русском**; при неоднозначности — `CONFUSION` (варианты A/B → вопрос), не молчаливый выбор.

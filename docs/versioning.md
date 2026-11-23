# Versioning

| Что | Схема |
|-----|--------|
| Kit product | semver (`VERSION`, `manifest.yaml`); текущая — `0.12.1` |
| CFE / EPF в клиентских проектах | `X.Y.Z.W` по скиллу `skill-versioning` |
| Profile lock | `lock/profile.lock.json` (names hash) |

## Profile lock

`lock/profile.lock.json` — снимок состава профиля: списки `agents`, `skills`, `rules`, их `counts`, версия кита и дата съёмки. Пересобирается только командой:

```powershell
powershell -NoProfile -File .\install\kit.ps1 lock [-DryRun]
```

Что попадает в снимок (те же правила, что в `verify`):

- `agents` — базовые имена `profile/agents/*.md`;
- `skills` — каталоги `profile/skills/*` с `SKILL.md`;
- `rules` — базовые имена `profile/rules/always/*.md` + каталоги `profile/rules/on-demand/*` с `SKILL.md`.

Файл никто не читает как источник правды: единственный потребитель — `kit.ps1 verify`, который сравнивает снимок с фактическим `profile/` и падает, если снимок устарел (`run: kit.ps1 lock`).

### Канон `namesHashSha256`

1. Имена внутри каждого списка сортируются **ординарно** (`StringComparer.Ordinal`, коды UTF-16) — результат не зависит от локали машины.
2. Каноническая строка — одна строка JSON без пробелов, ключи по алфавиту `agents`, `rules`, `skills`, значения — массивы имён в двойных кавычках; кириллица — сырым UTF-8 (без `\u`-экранирования), экранируются только `\` и `"`:

   ```json
   {"agents":["Бард"],"rules":["rule-kit-cli"],"skills":["skill-env-setup"]}
   ```

3. К канонической строке добавляется один `LF` (`\n`), байты кодируются в UTF-8 **без BOM**.
4. Хеш — SHA-256 (`System.Security.Cryptography.SHA256`), в файл пишется hex в нижнем регистре.

`capturedAt` меняется при каждой пересборке и в хеш не входит. Пересобирать lock нужно в той же правке, что меняет `profile/`; вручную файл не правят.

Не смешивать semver kit с версией расширения NinjaLive.

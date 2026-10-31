# MACHINE BOOTSTRAP — голая Windows + только платформа 1С

Цель: довести машину до состояния, когда `kit.ps1 doctor` проходит без FAIL.

Руками ставится **только платформа 1С** (её дистрибутив). Всё остальное —
одна команда `kit.ps1 deps`. Версии и адреса загрузки живут в `companions/pins.json`,
поэтому на новой машине ничего не «выдумывается»: агент запускает команду, а не ищет ссылки.

## 1. Клон кита

```powershell
git clone https://github.com/artkudr/1c-ninja-kit.git C:\1C\projects\1c-ninja-kit
cd C:\1C\projects\1c-ninja-kit
```

## 2. Платформа 1С (единственный ручной шаг)

Проверка:

```powershell
Get-ChildItem "C:\Program Files\1cv8\*" -ErrorAction SilentlyContinue | Select-Object -First 5 Name
```

Нужен `bin\1cv8.exe` и `bin\wsap24.dll` — второй подключает Apache для веб-публикации.
Без платформы Apache ставить бессмысленно, поэтому `doctor` проверяет её первой.

## 3. Всё остальное

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\kit.ps1 deps
```

`deps` берёт **последние** версии с upstream (GitHub releases, Apache Lounge), ставит
только отсутствующее и в конце печатает фактическое состояние. Где upstream публикует
sha256 (ripgrep, bsl-analyzer) — архив проверяется по нему. Если hub требует движок
OneScript новее выпущенного, для пакетов берётся проверенный набор из `pins.json`.

| Компонент | Куда ставится | Кто ставит |
|-----------|---------------|------------|
| OneScript (latest релиз) + `opm` | `%LOCALAPPDATA%\ovm\current` (zip релиза, junction на слот) | `deps -What oscript` |
| Пакеты `autumn`, `autumn-mcp`, `sql`, `1connector` | `lib` движка | `deps -What oscript` (`opm install`) |
| bsl-analyzer лаунчер + app | `%LOCALAPPDATA%\bsl-analyzer\bsl-analyzer.exe` + `%USERPROFILE%\.bsl-analyzer\bin\bsl-analyzer-app.exe` | `deps -What bsl-analyzer` |
| Apache 2.4.x Win64 (Apache Lounge) | `%USERPROFILE%\tools\apache-83` / `apache-85` | `deps -What apache` |
| Ripgrep + PATH | `%USERPROFILE%\tools\ripgrep` | `deps -What ripgrep` |
| Node.js LTS (portable) | `%USERPROFILE%\tools\node` + PATH | `deps -What web-test` |
| Playwright + Chromium | `node_modules` скилла `skill-web-test` + `%LOCALAPPDATA%\ms-playwright` | `deps -What web-test` |
| MCP_Toolkit.epf (optional) | `%USERPROFILE%\tools\1c-mcp-toolkit` | `deps -What toolkit` |
| 1C:Enterprise | ваш дистрибутив | **руками** |

### Флаги

| Флаг | Что делает |
|------|------------|
| `-What all` | всё перечисленное (по умолчанию) |
| `-What required` | только OneScript + пакеты и bsl-analyzer |
| `-What oscript\|bsl-analyzer\|ripgrep\|web-test\|apache\|toolkit` | один компонент |
| `-Update` | переставить/обновить уже стоящее |
| `-All` | Apache обеих веток (8.3 и 8.5), а не только под установленную платформу |
| `-Platform 8.3\|8.5` | конкретная ветка Apache |
| `-Offline` | не ходить в сеть, брать из кеша |
| `-DryRun` | показать план без изменений |

Фактически установленные версии и даты пишутся в
`%LOCALAPPDATA%\1c-ninja-kit\deps-state.json`; скачанные архивы — в
`%LOCALAPPDATA%\1c-ninja-kit\cache` (поэтому `-Offline` на второй машине работает,
если кеш перенесли).

## 4. Проверка

```powershell
powershell -NoProfile -File .\install\kit.ps1 doctor
```

`doctor` показывает для каждого компонента версию и путь, а для отсутствующего — команду,
которая его ставит. `FAIL` — только обязательное (платформа, OneScript и его пакеты,
bsl-analyzer, ninja-пара). Apache, ripgrep и toolkit — `WARN`.

`kit.ps1 apply` дополнительно ставит задачу планировщика `bsl-analyzer lease clean`
(при входе и каждые 5 минут): снимает мёртвые `writer.lease`; окна не показывает.

## 5. Особые случаи

- **Лаунчер bsl-analyzer занят.** Если MCP-сервер запущен, Windows не даст заменить exe:
  `deps -What bsl-analyzer -Update` попросит остановить сервер. Штатный путь — переименовать
  старый файл в `*.bak` и положить новый (это `deps` и делает сам).
- **Пакеты OneScript впереди движка.** Hub бывает новее релизов OneScript: сейчас `autumn`
  требует движок 2.2.1, которого ещё нет. `deps` пробует latest, а при таком отказе ставит
  проверенный набор из `knownGood` в `pins.json` (`autumn 4.3.11`, `autumn-mcp 1.1.2`,
  `sql 1.3.3`, `1connector 2.3.3`) и пишет WARN. Проверено: с этим набором `1c-ninja-mcp`
  стартует и отдаёт `tools/list`.
- **Смена версии OneScript.** Пакеты живут в слоте движка. `deps` не переустанавливает
  движок, если `oscript.exe` уже есть, — иначе слетят пакеты. Новая версия: положить zip
  релиза в `%LOCALAPPDATA%\ovm\<ver>`, переключить junction `current` (или `ovm install` +
  `ovm use`, если OVM под рукой), затем `deps -What oscript`.
- **Node / Playwright.** `deps -What web-test` ставит Node LTS portable и делает `npm ci`
  в каталоге скилла `skill-web-test`, затем `playwright install chromium`. `node_modules`
  кладётся в глобальную копию скилла — она появляется после `kit.ps1 apply`. Если `deps`
  запускали до `apply`, он поставит пакет в исходники кита и попросит повторить команду
  после `apply` (это быстро, повторно ничего не качает).
- **MCP Toolkit EPF** необязателен: он fallback live, если NinjaLive недоступен.

## 6. Дальше по харнессу

- OpenCode: `docs/opencode.md` + `docs/ADAPTATION.md`
- Профиль: `kit.ps1 apply`

## Сводка «откуда брать»

| Компонент | Где взять |
|-----------|-----------|
| 1C:Enterprise | ваш дистрибутив 1С |
| OneScript | https://oscript.io/ , zip `OneScript-<ver>-win-x64.zip` из https://github.com/EvilBeaver/OneScript/releases |
| Пакеты контура | `opm install` (ставит `deps`) |
| bsl-analyzer | https://github.com/itrous/bsl-analyzer/releases |
| Apache | https://www.apachelounge.com/download/ (Win64) |
| Ripgrep | https://github.com/BurntSushi/ripgrep/releases |
| Node.js | https://nodejs.org/dist/ (LTS, `node-<ver>-win-x64.zip`) |
| Playwright + Chromium | `npm ci` и `playwright install chromium` (ставит `deps`) |
| MCP Toolkit EPF | https://github.com/ROCTUP/1c-mcp-toolkit/releases |
| 1c-ninja-mcp + NinjaLive | **внутри этого kit** (`components/`, `project-scaffold/cfe/`) |

Машиночитаемые пины и правила установки: `companions/pins.json`.

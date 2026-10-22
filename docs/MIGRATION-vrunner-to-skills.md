# План миграции: с vrunner на скиллы (kit + все проекты)

**Дата:** 14.10.2026  
**Статус:** рабочий документ. По завершении миграции — **удалить** (не оставлять в продукте).  
**Принцип:** целевые артефакты (правила, скиллы, конфиги, шаблоны, доки) описывают **только новый контур**. Никаких «раньше был vrunner» — ни в правилах, ни в скиллах, ни в шаблонах, ни в докax. Всё, что упоминает vrunner, — либо переписывается на новую механику, либо удаляется.

Основание: пробные прогоны на `devtools` (см. `devtools/docs/cc-1c-skills-trial-2026-10-14.md`): полный цикл правки расширения (load → update → проверки → live → dump) новым контуром пройден; эквивалентность подтверждена семантическим сравнением XML-дампов.

---

## 0. Целевой контур (что строим)

| Слой | Было | Станет |
|---|---|---|
| Операции с ИБ (load/dump/update/расширения/хранилище/EPF) | MCP `vrunner` + `repo.ps1` (`vrunner run designer`) | Скрипты скиллов (ветка `port-opencode` cc-1c-skills): `db-*`, `epf-build/dump`, `erf-build/dump` — прямые вызовы `1cv8.exe` DESIGNER / `ibcmd.exe` |
| Реестр баз | `autumn-properties.json` + `repository.json` | **`.v8-project.json`** (единый, с kit-расширениями; см. §1.3) |
| Синтакс-контроль основной конфигурации | MCP `validate_syntax_check` | Новый kit-скилл **`1c-syntax-check`** (обёртка `/CheckConfig` по режимам из реестра) |
| Синтакс-контроль расширений | `validate_syntax_check target=AllExtensions` | `db-cfe-admin check` (скилл) |
| Хранилище CFE | `repo-workflow` → `repo.ps1` (vrunner) | `repo-workflow` (переписан) → `db-repo` + `db-load-xml -Mode Partial` + гейты |
| EPF/ERF | MCP `epf_compile` / ninja-обёртки | `epf-build` / `epf-dump` (проверки + временная база с заглушками) |
| MCP `1c-ninja-mcp` | 20 инструментов, 5 из них завязаны на vrunner | 15 инструментов: `live_*` + статический поиск; DB-инструменты удаляются (их заменяют скиллы) |
| MCP `vrunner` | 61 инструмент | **Удаляется целиком** (конфиги, шаблоны, доки, движок) |
| Skills delivery | profile/skills (всё, включая cc-1c-skills) + промоут в live (Cursor-пути) | kit хранит **только свои** скиллы; cc-1c-skills ставится установщиком из репозитория в live |
| Тесты (vanessa/xunit/yaxunit) | `vrunner test` | Удаляются из правил; отдельная инициатива при необходимости |

Что сознательно **не** переносится (не используется контуром): кластер/сеансы/задания, пользователи ИБ, конвертеры EDT, сравнение/merge/поставка, обновление на поддержке, validate_edt. Уходят вместе с движком.

---

## 1. Решения по контуру (зафиксировать до работ)

### 1.1 Раздача скиллов: kit хранит только своё, cc-1c-skills скачивается

**Решение:** набор cc-1c-skills в ките **не хранится**. Он скачивается из репозитория (`Nikolay-Shirokov/cc-1c-skills`, ветка `port-opencode`) установщиком и ставится глобально в `~/.config/opencode/skills`. Кит хранит только свои скиллы и сам установщик.

Состав:

| Слой | Где | Состав |
|---|---|---|
| Kit-owned скиллы | `profile/skills` кита (SoT, git кита) | `1c-*` (10), `web-*` (5, профильный Apache), `repo-workflow`, `composing-1c-queries`, `cursor-local-patches`, `handoff`, новый `1c-syntax-check` — всего **20** |
| cc-1c-skills | скачивается, ставится в `~/.config/opencode/skills` | вся ветка `port-opencode` (81) **минус** `web-*` (5) = **76** скиллов, включая `db-*`, `epf-build/dump`, `erf-build/dump`, `v8-xsd-fetch`, `cf-*`, `meta-*`, `form-*`, … |

- Из `profile/skills` **удаляются 60 каталогов**: 58 апстрим-производных (`cf-*`, `cfe-*`, `epf-*`, `erf-*`, `form-*`, `meta-*`, `mxl-*`, `role-*`, `skd-*`, `subsystem-*`, `xdto-*`, `interface-*`, `help-add`, `img-grid`, `support-edit`, `template-*`) + `vrunner-mcp` + `sync-cc-1c-skills`. Итого live после миграции: 20 + 76 = **96 скиллов**, имена уникальны.
- `sync-cc-1c-skills` (скилл, policies, scripts, карантин) — **удаляется целиком**: его механика существовала ради port-cursor и старого канона «только vrunner»; у port-opencode пути уже для OpenCode, а `.v8-project.json` теперь канон — конвейеру нечего делать.
- `vrunner-mcp` — удаляется; маршрутизация операций переходит в `1c-project-context` и правило `1c-development-process`.

**Установщик `install/cc-skills.ps1` (единственное, что добавляется в кит):**

| Шаг | Действие |
|---|---|
| 1 | `git clone --depth 1 -b <branch>` (по умолчанию `port-opencode`) во временный каталог; фиксируется commit |
| 2 | Поиск корня скиллов в дереве (glob `skills/*/SKILL.md`) — без жёсткой привязки к глубине |
| 3 | Исключения: `web-*` (5 имён — остаются kit-овскими) |
| 4 | Path-fix: в **82 `.md`-файлах** (только `.md`; скрипты чистые) `.opencode/skills/` → `<skillsRoot>\` (абсолютный путь машины) |
| 5 | Копирование в `~/.config/opencode/skills` (robo `/E`) |
| 6 | Прунинг: имена из прошлого штампа, которых нет в новой версии, удаляются |
| 7 | Штамп `~/.config/opencode/skills/.cc-1c-skills.stamp.json`: repo, branch, commit, дата, список имён |

Режимы: без ключей — установить, если нет (`db-list` отсутствует); `-Update` — скачать и обновить; `-Ref <branch|commit>` — закрепиться на версии; `-SourcePath` — локальный клон (офлайн/тест); `-DryRun`. Источник и ветка — в `companions/pins.json` (новая секция `cc1cSkills`, `ref: null` = свежая версия). Автообновления нет: версия меняется только явным `-Update`.

### 1.2 Ninja-компонент (vrunner-free)

Удаляются 5 инструментов и их код (заменены скиллами):

| Инструмент | Замена |
|---|---|
| `cf_dump_xml` | `db-dump-xml` |
| `cf_load_git` | `db-load-git` |
| `epf_compile` | `epf-build` / `erf-build` |
| `epf_decompile` | `epf-dump` / `erf-dump` |
| `extensions_dump_list` | `db-cfe-admin list` / `live_extensions_list` |

Остаются: `live_*` (14 шт., включая `live_extensions_list`) + `config_list`, `xml_search`, `bsl_search`, `read_module`, `syntax_help_search`. Из кода уходят env `VRUNNER_*`, чтение `autumn-properties.json`, `epf-precheck.ps1`.

### 1.3 Схема `.v8-project.json` (базовая — апстрим + kit-расширения)

```jsonc
{
  "v8path": "C:\\Program Files\\1cv8\\8.3.27.2130\\bin",
  "databases": [
    {
      "id": "main",
      "name": "<имя проекта>",
      "type": "file",              // или "server"
      "path": "C:\\1C\\bases\\<x>", // для file; для server — "server" + "ref"
      "user": "<пользователь ИБ>",
      "password": "<пароль>",
      "configSrc": "src\\cf",
      "extensions": [
        {
          "name": "<Имя CFE>",
          "src": "src\\cfe\\<Имя>",
          "repository": {           // только для CFE с хранилищем
            "path": "<абсолютный путь хранилища>",
            "user": "<пользователь хранилища>",
            "password": "",
            "adminUser": "Администратор"   // kit-расширение (для add-user)
          }
        }
      ]
    }
  ],
  "default": "main",
  "web": { "appName": "<публикация>", "port": 8083, "apachePath": null },   // kit-расширение (apachePath — опционально)
  "validate": { "syntax-check": {                        // kit-расширение
    "mode": ["ExtendedModulesCheck", "ThinClient", "WebClient", "Server", "ExternalConnection", "ThickClientOrdinaryApplication"],
    "exceptionFile": "tools/syntax-check-excludes.txt"
  }}
}
```

- Апстрим-скиллы читают базовые поля и игнорируют kit-ключи; kit-скиллы (`web-*`, `1c-syntax-check`, `repo-workflow`) читают свои.
- Секреты → `.v8-project.json` в `.gitignore` (как раньше autumn).
- `v8args`/`ibcmdargs` — по необходимости; `additional`/`ordinaryapp`/`language` из autumn не переносим.
- `repository.adminUser` переносится из `repository.json.adminUser`; используется `repo-workflow` для `db-repo add-user` (передаётся явно).

### 1.4 Новый kit-скилл `1c-syntax-check`

- Обёртка `1cv8 DESIGNER /CheckConfig`: основная конфигурация (и опционально расширение — хотя расширения закрывает `db-cfe-admin check`).
- Режимы и файл исключений — из `validate.syntax-check` реестра; дефолт — kit-стандарт.
- Для баз под хранилищем — передаёт ключи `ConfigurationRepository*` из записи реестра.
- MVP без junit/allure (отчёты — отдельная задача, если понадобятся).

---

## 2. Фаза 1 — kit SoT (единый проход, до выключения движка)

### 2.1 Разделение kit-скиллов и cc-1c-skills

- Удалить `profile/skills/sync-cc-1c-skills/` целиком (SKILL.md, scripts, policies, карантин).
- Удалить из `profile/skills` 60 каталогов: 58 апстрим-производных + `vrunner-mcp` + `sync-cc-1c-skills` (состав — §1.1; остаются 19 kit-овских, добавляется `1c-syntax-check`).
- Добавить `install/cc-skills.ps1` (§1.1) и секцию `cc1cSkills` в `companions/pins.json`.
- Обновление cc-набора впредь — только установщиком: `cc-skills.ps1 -Update` (по явной просьбе или из `1c-env-setup`). Автообновления нет.

### 2.2 Правила (profile/rules) — 8 файлов

| Файл | Что меняем |
|---|---|
| `1c-development-process.mdc` | Полная замена платформенного раздела: load/dump/update — скиллы `db-*`; CFE из хранилища — `repo-workflow` (новый); syntax-check — `1c-syntax-check` / `db-cfe-admin check`; EPF/ERF — `epf-build/dump`; запрет — PT/`install.ps1`/ручная правка XML (без «через vrunner»); порядок задачи — по новым скиллам |
| `1c-orchestrator.mdc` | Таблица MCP-маршрутов: строка «Load / syntax-check / repo» → скиллы; «Запрещено» — переформулировать (без vrunner); строки про `extensions_list` — оставить только `live_extensions_list`; контекст проекта — `.v8-project.json` |
| `tooling-playbooks.mdc` | Playbooks: load — скиллы; «CFE из repository» — новый repo-workflow; убрать «vrunner / repo.ps1» |
| `verification-checklist.mdc` | Gate 6 «Platform / load gates» — новые инструменты; gate 5 — repo-workflow без vrunner |
| `1c-ninja-mcp.mdc` | Матрица владения: ninja = live + static; DB-операции — скиллы; убрать vrunner-упоминания |
| `bsl-analyzer.mdc` | «Компиляция платформой» → `1c-syntax-check`; не путать с анализатором |
| `subagents.mdc` | Упоминания vrunner → новые скиллы |
| `dev-standards-architecture.mdc` | 1 упоминание — заменить |

### 2.3 Агенты (profile/agents) — 12 файлов

Во всех: строка «Load / syntax-check / IB: MCP vrunner only …» → «Операции с ИБ — скиллы `db-*`; гейты — `1c-development-process`». У `1c-tester.md` — description и шаги (без «vrunner tests»; UI/IB-проверки — repo-workflow + web-test; автотесты — вне контура).

### 2.4 `install/kit.ps1` + пути/пины

- Генерация AGENTS.md: строки 280/298/307 — новая формулировка (запрещено PT/ручная правка XML; маршрут «Load / syntax-check / repo → скиллы»; список частых скиллов без `vrunner-mcp`).
- Doctor: убрать проверки `vrunner.bat` / `vrunner-mcp.bat` / `vrunner --version`; добавить: `1cv8.exe` (8.3/8.5) присутствует, скиллы `db-list`/`db-load-xml`/`db-cfe-admin` в skills root, `oscript`, `bsl-analyzer`, Apache-профили.
- `$bad`-списки (422/482): убрать `'vrunner'`; шаблон MCP: убрать `{{VRUNNER_MCP}}` и сервер `vrunner`; финальные подсказки (660): `db-load-xml NinjaLive` вместо `cfe_load`.
- `install/path-defaults.windows.yaml`: удалить `vrunner`, `vrunnerMcp`.
- `companions/pins.json`: удалить секцию `vanessaRunner`; note у `oneScript` — без патчей vrunner.
- `profile/packs/core/manifest.json`: привести к kit-составу — убрать `vrunner-mcp`, `sync-cc-1c-skills` и 58 апстрим-производных имён; добавить `1c-syntax-check` (cc-набор в манифесте не числится — он не часть кита).
- `lock/profile.lock.json` — перегенерировать (новый состав).
- Doctor (`kit.ps1`): проверять, что cc-набор установлен (`db-list` / `db-load-xml` в skills root) и штамп валиден; подсказка — «запусти `install/cc-skills.ps1`».

### 2.5 Шаблоны

- `profile/skills/1c-env-setup/scripts/templates/` и `project-scaffold/templates/`:
  - `autumn-properties.json.tpl` → **`.v8-project.json.tpl`** (новая схема);
  - `repository.json.tpl` → удалить;
  - `mcp.json.example.tpl` (cursor) / `opencode.jsonc.tpl` (env-setup) / `adapters/opencode/opencode.jsonc.tpl` — убрать сервер `vrunner` и плейсхолдер `{{VRUNNER_MCP}}`;
  - `dev-stack.md.tpl` — таблица стека: `.v8-project.json`, скиллы `db-*`, MCP без vrunner;
  - `gitignore-1c.snippet` — `+ .v8-project.json`, `+ .v8-xsd/`, `− autumn-properties.json`, `− repository.json`;
  - `openspec/README.md` (2 копии: project-scaffold и env-setup) — «гейты через скиллы `db-*`/repo-workflow»; список скиллов без `vrunner-mcp`.

### 2.6 `1c-env-setup` (основная переработка)

Файлы: `SKILL.md`, `reference.md`, `scripts/env-setup.ps1`, `scripts/sync-cfe.ps1`, `scripts/sync-ninja-properties.ps1`, `scripts/templates/*`.

- Sanity: вместо `vrunner --version` — проверка платформы (1cv8 выбранной версии) и наличия скиллов контура (`db-list`, `db-load-xml`, `db-cfe-admin`).
- cc-набор: если `db-list` не установлен — вызвать `install/cc-skills.ps1`; по явной просьбе — `-Update`.
- Запись файлов: `.v8-project.json` (вместо autumn + repository); `sync-cfe.ps1` пишет имена расширений в `extensions[]` реестра (и создаёт `src/cfe/<Имя>`); `-UseVrunnerList` удалить.
- Bootstrap NinjaLive: `db-load-xml -Mode Full -Extension "NinjaLive" -UpdateDB` → `db-cfe-admin set-properties -Active on -SafeMode off` → `web-publish` → `live_version` → `live_extensions_list` → `sync-cfe -ExtensionNames`.
- Проверка входа: успешная загрузка NinjaLive (как раньше), при ошибке — не оставлять битый пароль в реестре.
- «История скилла» — вычистить vrunner-упоминания.
- `sync-ninja-properties.ps1` — комментарии без vrunner.
- Reference: переписать разделы `autumn-properties.json` → `.v8-project.json` (форматы ibconnection, поля, выбор платформы).

### 2.7 `repo-workflow` (переписан) + `1c-syntax-check` (новый) + прочие скиллы

- `repo-workflow`: цикл остаётся (lock → правка → гейты → load → гейты → commit), движок — `db-repo` (lock/unlock/commit/update/connect/add-user) + `db-load-xml -Mode Partial -Files/-ListFile` (ключи хранилища подставляет скилл из реестра) + `db-update`. Скрипты `repo.ps1`, `repo-common.ps1`, `smoke-repo-engine.ps1` — удалить. Сохранить предупреждения: полная загрузка при хранилище запрещена; `Configuration.xml` в списке = полная загрузка; после lock/update — перевыгрузка названных объектов (`db-dump-xml -Mode Partial`); гейты после load: `db-cfe-admin check` + live + короткий web.
- Новый `1c-syntax-check` (§1.4).
- `web-*` остаются kit-овскими (машинная конвенция — профильный Apache 8083/8085; порт использует проектный Apache на 8081 — см. Приложение C). Адаптация под `.v8-project.json` — §2.7.1.
- Обновить упоминания: `1c-project-context` (маршруты, `.v8-project.json`, MCP-список без vrunner), `1c-ninja-mcp` (матрица и описания инструментов — после слима), `1c-mcp-toolkit` (роль fallback, без vrunner), `1c-bsl-analyzer`, `1c-fresh-cfe-audit`, `1c-spravochnye-dannye`, `handoff`, `web-test` (источник URL/платформы), `web-publish` (+ `scripts/Resolve-1cWebTargets.ps1`/`.py` — читать `.v8-project.json`: версия из `v8path`, `web.appName/port/apachePath`), `cursor-local-patches` (убрать vanessa-runner/autumn-mcpify/vrunner-mcp.bat; профильные доки → `%USERPROFILE%\.config\opencode\docs\`). `sync-cc-1c-skills` — удаляется (§2.1).
- Удалить: `profile/skills/vrunner-mcp/`, `profile/docs-patches/vrunner-local-patches.md`.

### 2.7.1 Адаптация `web-*` под `.v8-project.json`

Резолвер общий: `web-publish/scripts/Resolve-1cWebTargets.ps1` + `resolve_1c_web_targets.py` (его используют `web-info`, `web-stop`, `web-unpublish`). Меняем его — остальным остаются только справки.

| Файл | Что меняется |
|---|---|
| `web-publish/scripts/Resolve-1cWebTargets.ps1` + `resolve_1c_web_targets.py` | Корень проекта — по `.v8-project.json` (вместо autumn + env.json). Версия платформы — из `v8path` (имя каталога `…\8.3.27.2130\bin` или путь к `1cv8.exe`); если `v8path` нет — авто-определение старшей установленной (как в `db-*`). `web.appName` / `web.port` / `web.apachePath` — из секции `web`. Профили apache-83:8083 / apache-85:8085 и оверрайды (`-V8Version`, `-ApachePath`, `-Port`, `-AppName`) — без изменений |
| `web-publish/scripts/web-publish.ps1` + `.py` | Справка/комментарии (autumn → `.v8-project.json`); резолв платформы для `wsap24.dll` — через общий резолвер; удалить `web-publish.ps1.bak` |
| `web-info/scripts/web-info.ps1` + `.py`, `web-stop/scripts/web-stop.ps1` + `.py`, `web-unpublish/scripts/web-unpublish.ps1` + `.py` | Логика — через общий резолвер (правок нет); справки параметров: «по v8version проекта» → «по платформе из `.v8-project.json`» |
| `web-test/scripts/cli/test-runner/suite-root.mjs` | Границы поиска корня проекта: `'autumn-properties.json'` → `'.v8-project.json'` (строка 16 + комментарий) |
| SKILL.md всех пяти | Убрать autumn/env.json: `web-publish` («Фрагмент autumn» → фрагмент `.v8-project.json`; «IB params from …»; «только autumn / CLI»), `web-info`/`web-stop` («по v8version проекта»), `web-unpublish` («AppName по умолчанию из autumn `web.appName`»), `web-test` («только через autumn / smoke / vrunner» → «через `.v8-project.json` / smoke») |
| Плюс (из Приложения C) | Подтянуть движок `web-test` из порта (`fsutil.mjs` + правки `session.mjs`), сохранив kit-адаптацию SKILL.md; усилить документацию `web-info`/`web-unpublish` по образцу порта; в `web-publish` — раздел про сервисы расширений (`404 → /db-update -Extension`); почистить артефакт `web-test\error-shot.png` |

Порядок: адаптация входит в фазу 1, но **вступает в силу для проекта только после его миграции** (пока в проекте нет `.v8-project.json`, web-* работать не будут). Миграция проектов — сразу за фазой 1 (§4), окно рассинхрона короткое и управляемое.

### 2.8 Ninja-компонент

`components/1c-ninja-mcp/`: удалить `Классы\Инструмент{CfDumpXml,CfLoadGit,EpfCompile,EpfDecompile,ExtensionsDumpList}.os`, `scripts\epf-precheck.ps1`; почистить `main.os` (autumn), `README.md` (состав инструментов, env).

### 2.9 Документация кита

`README.md`, `NOTICE.md`, `profile/README.md`, `adapters/opencode/README.md`, `docs/{MACHINE-BOOTSTRAP,stack-defaults,ADAPTATION,LAYERS,TEST-GUIDE-opencode,AGENT-BRIEF-v0.2,inventory/SNAPSHOT}.md` — переписать разделы стека/шагов установки под новый контур (проверки doctor, шаги bootstrap, списки MCP-серверов; ссылки на `sync-cc-1c-skills` удалить).

### 2.10 Контрольная точка фазы 1

- `kit.ps1 apply` зелёный; `install/cc-skills.ps1` прогнан (первая установка cc-набора, штамп создан).
- В live ровно 96 скиллов (20 kit + 76 cc), дублей имён нет; `vrunner-mcp` и `sync-cc-1c-skills` удалены из live отдельным шагом (apply не удаляет).
- Правила/агенты/шаблоны/доки без vrunner-упоминаний (grep по kit, кроме этого плана).
- Быстрый смоук на devtools: `db-cfe-admin list`, `1c-syntax-check` на `src/cf`.

---

## 3. Фаза 2 — выключение движка (машина)

1. Удалить из ovm движок: `vrunner.bat`, `vrunner-mcp.bat` из `%LOCALAPPDATA%\ovm\current\bin`; пакеты `vanessa-runner`, `v8runner`, `v8storage`, `v8find`, `v8unpack`, `ibcmdrunner`, `coverage*`, `1testrunner`, `vanessa-automation-single`, `autumn-mcpify` (обе копии) и прочие из дерева vrunner. **Не трогать** пакеты, которыми живёт ninja-компонент (`fs`, `json`, `1connector`, `logos` и пр.) — точный список сверить по фактическим зависимостям; после удаления проверить, что ninja MCP поднимается и `live_*` работают.
2. Cursor-контур: подтвердить, что он больше не используется; при подтверждении — удалить `%USERPROFILE%\.cursor\skills` (81 каталог, устаревшее зеркало), `%USERPROFILE%\.cursor\devccskills` (карантин), `%USERPROFILE%\.cursor\docs\vrunner-local-patches.md`. Локальные доки-патчи впредь — `%USERPROFILE%\.config\opencode\docs\` (обновить скилл `cursor-local-patches`).
3. Удалить из `~/.config/opencode/skills` скиллы `vrunner-mcp` и `sync-cc-1c-skills` (apply их больше не приносит, но и не удаляет).
4. Обновить `docs/MACHINE-BOOTSTRAP.md`: чек-лист без `vrunner --version`/`vrunner-mcp.bat`; проверить `kit.ps1 doctor`.
5. Контрольная точка: `vrunner` не вызывается ниоткуда из живого контура (grep по kit/live skills/проектам — 0), ninja перезапущен и отдаёт 15 инструментов.

---

## 4. Фаза 3 — миграция проектов (8)

### 4.1 Скрипт миграции (одноразовый, `install/migrate-autumn-to-v8project.ps1`)

На каждый проект:
1. Читает `autumn-properties.json` (vrunner.ibconnection/db-user/db-pwd/v8version/validate; web) и `repository.json` (root/user/adminUser/cfe), сканирует `src/cfe`.
2. Пишет `.v8-project.json` по §1.3:
   - `v8path` — из v8version (короткое «8.3» → старшая установленная 8.3.x);
   - `databases[0]` — разбор ibconnection: `/F"…"`, `/F…` (без кавычек), `/Sserver\ref`, `/server/ref` → type/path|server/ref; user/password;
   - `configSrc: "src\\cf"`; `extensions[]` — все каталоги `src/cfe` + `repository` для тех, что есть в карте хранилищ (`path = root\папка`, `user`, `adminUser`);
   - `web`/`validate` — из autumn (exception-file → exceptionFile; junit/allure не переносим).
3. Правит `opencode.jsonc`: удаляет блок сервера `vrunner` (с проверкой парса JSONC), остальное не трогает.
4. Правит `.gitignore`: `+ .v8-project.json`, `+ .v8-xsd/`; удаляет строки autumn/repository.
5. Удаляет `autumn-properties.json`, `repository.json`.
6. Пишет отчёт по файлам; после прогона — проверка: JSON парсится, `db-cfe-admin list` работает.

Отдельно (руками/скриптом): `docs/dev-stack.md` каждого проекта — по новому шаблону; `memory.md` — строка про загрузку (devtools).

### 4.2 Таблица проектов

| Проект | Платформа | ИБ | web | Хранилищ CFE | Особенности |
|---|---|---|---|---|---|
| **devtools** (пилот, уже мигрирован) | 8.5.1.1343 | file `C:\1C\bases\devtools` | devtools:8085 | — (NinjaLive) | `.v8-project.json` уже есть — дополнить `web`/`validate`; удалить пробные `.opencode/skills` (18 дублей — cc-набор ставится глобально) |
| **dt-bp3** (пилот №2: сервер + хранилища) | 8.3.27.2130 | server `k-server\dt-bp3` | dt-bp3:8083 | 4 | первый смоук серверной базы и цикла хранилища |
| ecoladev | 8.3 (→ 8.3.27.2130) | server `k-server\ecola-aka-dev` | ecola-aka-dev:8083 | 24 | `.cursor/mcp.json` (убрать vrunner-блок), `tools/smoke-cursor-profile.ps1` (переписать), `tools/web-test/.../block-a-removal-check.js` (читает autumn → реестр) |
| neofamily-dev | 8.3.27.2130 | file `C:\1C\bases\neofamily-dev` | neofamily-dev:8083 | 1 | — |
| qbikdev | 8.3.27.2130 | server `k-server/qbik-dev` | qbikdev:8083 | 4 | `tests/epf/README.md` — формулировка формата разборки |
| sad-dev | 8.3.27.2130 | file `C:\1C\bases\sad-dev` | sad-dev:8083 | 27 | — |
| trans-dev | 8.3.27.2130 | file `C:\1C\bases\trans-dev` | trans-dev:8083 | — | — |
| unf-demo | 8.5.1.1343 | file `C:\1C\bases\unf-demo` | unf-demo:8085 | 1 | — |

### 4.3 Порядок

1. **Пилоты: devtools (дополнение) + dt-bp3** — мигрировать, прогнать смоуки (см. §5), убедиться в серверном и хранилищном путях.
2. Остальные 6 — пачкой скриптом, затем каждый проверяется `db-cfe-admin list` + открытием проекта.
3. Хвосты в проектах: `qbikdev/tests/epf/README.md`, ecoladev extras (§4.2), исторические `tasks/*.md` — **не трогаем** (архив прошлой работы, не инструмент).

---

## 5. Фаза 4 — приёмка

| Проверка | Критерий |
|---|---|
| Grep-чистота | `vrunner` = 0 в: kit (кроме этого плана), `~/.config/opencode/{skills,kit-rules,agents}`, все `opencode.jsonc`, `.v8-project.json`, `docs/*` стеков, шаблоны. Исключения: git-история, `devtools/docs/*отчёты*`, исторические `tasks/` |
| devtools полный цикл | правка → `db-load-xml` → `db-update` → `db-cfe-admin check` → live → `db-dump-cf` (уже отработано) |
| dt-bp3: серверная ИБ | `db-cfe-admin list`, `1c-syntax-check`, load/update расширения |
| dt-bp3: хранилище | `db-repo lock` → правка → `db-load-xml -Mode Partial` → `db-update` → гейты → `db-repo commit` (на малом CFE) |
| env-setup | `-Mode Check` на пустой папке; полный Init на тестовой папке с проверкой `live_version` |
| Ninja | 15 инструментов; live smoke (`live_version`, `live_validate_query`) |
| kit | `kit.ps1 doctor` / `verify` зелёные |
| cc-набор | штамп `.cc-1c-skills.stamp.json` есть; `db-list`/`db-load-xml`/`db-cfe-admin` в live; повторный `-Update` не плодит дубли, прунинг удаляет исчезнувшие имена |
| Уборка | удалить этот план; судьба отчётов `devtools/docs/cc-1c-skills-*` — по решению владельца |

---

## 6. Риски и оговорки

1. **Живые сессии vs `ibcmd`**: пока Apache опубликован и есть веб-сессии, `ibcmd`-часть `db-cfe-admin list` не берёт монопольную блокировку и показывает `—` по свойствам (молча). Не блокер; обход — смотреть свойства при остановленной публикации. Помнить при гейтах.
2. **Серверные базы** (`/S`) скиллами ещё не гонялись — обязательный пилот dt-bp3/ecoladev до массового переноса.
3. **Хранилище**: полная загрузка при базе-под-хранилищем запрещена платформой — новый repo-workflow обязан держать частичную загрузку по списку; `Configuration.xml` в списке запрещён.
4. **Имена скиллов уникальны**: после промоута в live проверить отсутствие дублей (особенно после удаления `vrunner-mcp` и с учётом проектных `.opencode/skills` — удалить их в devtools).
5. **Потеря отчётов синтакс-контроля** (junit/allure) — сознательно; если понадобится для CI — отдельная задача на `1c-syntax-check`.
6. **Тесты** (vanessa/xunit) уходят без замены — если нужны, отдельная инициатива.
7. **`disable-model-invocation`** у деструктивных апстрим-скиллов (напр. `db-load-dt`) в OpenCode не действует — при импорте добавить `metadata.opencode/autoinvoke: false` (опционально, при rewrite).
8. Параллельные сессии: правило «читаем параллельно, пишем последовательно» сохраняется; операции с ИБ сериализуются.

---

## Приложение A. Полный инвентарь упоминаний (по контурам)

- **kit / profile**: rules — 8 файлов; agents — 12; skills — `1c-env-setup` (SKILL+reference+env-setup.ps1+sync-cfe.ps1+sync-ninja-properties.ps1+openspec README), `repo-workflow` (SKILL+scripts), `vrunner-mcp` (удалить), `1c-project-context`, `1c-ninja-mcp`, `1c-mcp-toolkit`, `1c-bsl-analyzer`, `1c-fresh-cfe-audit`, `1c-spravochnye-dannye`, `handoff`, `web-test`, `web-publish` (+2 скрипта резолва), `sync-cc-1c-skills` (удалить целиком), `cursor-local-patches`; 58 апстрим-производных скиллов (удалить из profile — приходят из cc-набора); `profile/docs-patches/vrunner-local-patches.md` (удалить); `profile/packs/core/manifest.json` (убрать `vrunner-mcp`, `sync-cc-1c-skills` и 58 апстрим-имён); `profile/profiles/1c-ninja-kit.yaml` (без изменений); `profile/README.md`.
- **kit / install**: `kit.ps1`, `path-defaults.windows.yaml`, `lock/profile.lock.json` (перегенерация), `install/cc-skills.ps1` (новый — установщик cc-набора).
- **kit / components**: `1c-ninja-mcp` — 5 Инструмент-классов + `main.os` + `epf-precheck.ps1` + README.
- **kit / docs**: `README.md`, `docs/{MACHINE-BOOTSTRAP,stack-defaults,ADAPTATION,LAYERS,TEST-GUIDE-opencode,AGENT-BRIEF-v0.2,inventory/SNAPSHOT}.md`, `adapters/opencode/README.md`, `adapters/opencode/opencode.jsonc.tpl`.
- **kit / scaffold+templates**: `project-scaffold/templates/{autumn-properties.json.tpl→v8, repository.json.tpl→удалить, mcp.json.example.tpl, dev-stack.md.tpl, gitignore-1c.snippet}`, `project-scaffold/cfe/README.md`, `project-scaffold/templates/openspec/README.md`; `profile/skills/1c-env-setup/scripts/templates/{то же + opencode.jsonc.tpl}`.
- **проекты (8)**: `opencode.jsonc` (у всех), `.gitignore`, `docs/dev-stack.md` (у всех), `memory.md` (devtools), `ecoladev` — `.cursor/mcp.json`, `tools/smoke-cursor-profile.ps1`, `tools/web-test/scenarios/manual/block-a-removal-check.js`; `qbikdev` — `tests/epf/README.md`; `devtools` — удалить `.opencode/skills` (18 пробных), дополнить `.v8-project.json`.
- **машина**: `%LOCALAPPDATA%\ovm\current\bin\{vrunner,vrunner-mcp}.bat`, пакеты ovm, `%USERPROFILE%\.cursor\{skills,devccskills,docs\vrunner-local-patches.md}`.

## Приложение B. Критерий «вычищено»

```powershell
# 0 совпадений (кроме git-истории, этого плана и исторических tasks/ и отчётов devtools)
$paths = @("C:\1C\projects\1c-ninja-kit", "$env:USERPROFILE\.config\opencode")
Get-ChildItem $paths -Recurse -File -Include *.md,*.mdc,*.ps1,*.py,*.json,*.jsonc,*.yaml,*.yml,*.tpl,*.os |
  Where-Object { $_.FullName -notmatch '\\\.git\\|\\logs\\|\\\.build\\' } |
  Select-String -Pattern 'vrunner' -SimpleMatch
```

## Приложение C. Сравнение web-скиллов (kit ↔ port-opencode)

Основание для решения «web-* остаются kit-овскими» (§1.1).

### C.1 Модель (главное отличие)

| | Kit `web-*` | Порт `web-*` |
|---|---|---|
| Где Apache | Профильный, **вне проектов**: `%USERPROFILE%\tools\apache-83` (8083) / `apache-85` (8085) — по `v8version` проекта | **В проекте**: `tools/apache24` (по умолчанию); при отсутствии — авто-скачивание Apache Lounge, `-Manual` |
| Порт | 8083/8085 — жёстко по платформе | 8081 по умолчанию, `-Port` |
| Конфиг | `autumn-properties.json`: `v8version`, `web.appName`, `web.port`, `web.apachePath`; smoke `webUrl` | `.v8-project.json`: `webPath`; база разрешается из реестра |
| Локаль | Конвенция `/ru_RU/` (webUrl; live URL — без локали) | Без конвенции локали; URL вида `http://localhost:8081/<id>` |
| Скрипты | `ps1`+`py` + отдельный резолвер `Resolve-1cWebTargets.ps1/.py` | `ps1`+`py`, логика внутри `web-publish` |

### C.2 По скиллам

| Скилл | Kit | Порт | Вывод |
|---|---|---|---|
| `web-publish` | 63 стр.: обёртка профильного Apache; «Apache не в проекте», стабильный AppName | 106 стр.: самодостаточная публикация в проектный Apache (+скачивание), полный список URL, раздел про сервисы расширений (`/db-update -Extension` при 404), `-Manual` | Модели несовместимы; из порта взять идею раздела про расширения |
| `web-info` | 19 стр.: статус/публикации/ошибки профильного Apache | 70 стр.: то же + гайд по чтению вывода (сторонний Apache, теги WS/HTTP/OData/+ext, давность ошибок, «строка публикации ≠ база отвечает») | Документацию порта перенести в kit-скилл |
| `web-stop` | 17 стр. | 53 стр. (+ что сохраняется, что делать дальше) | Косметика |
| `web-unpublish` | 21 стр.; скрипт **умеет** удаление глобального блока и остановку (проверено, строки 109–152) | 63 стр. (+ предупреждения, сценарий «спроси, если имя не указано») | Функционал паритетен; взять документацию |
| `web-test` | Тот же движок; kit-адаптация (smoke.config.json, `/ru_RU/`), установленные `node_modules`, артефакт `error-shot.png` | Тот же движок, **новее**: `+scripts/engine/core/fsutil.mjs` (116 стр.), правки `session.mjs`, `npx playwright install chromium` в setup; конфиг из `.v8-project.json` | Движок подтянуть из порта (2 файла), SKILL.md оставить kit-адаптированным; почистить артефакты |

### C.3 Почему kit-версии остаются

1. Профильный Apache 8083/8085 — **машинная конвенция kit** (stack defaults): один сервер на все 8 проектов, порты привязаны к платформе. Порт-модель (Apache в каждом проекте, 8081) конфликтует с ней и с уже работающими публикациями (`unf-demo`, `devtools` на 8085 и т.д.).
2. Kit `web-*` связаны со smoke (`tools/web-test/smoke.config.json`, `/ru_RU/`) и live-конвенциями (`/hs/ninja-live` без локали).
3. Из порта берём точечно: движок `web-test`, документацию `web-info`/`web-unpublish`, раздел про сервисы расширений в `web-publish`.

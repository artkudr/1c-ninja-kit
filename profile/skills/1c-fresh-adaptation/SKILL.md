---
name: 1c-fresh-adaptation
description: >-
  Оркестратор подготовки средств адаптации для 1С:Фреш (расширения CFE и
  доп. отчёты/обработки EPF/ERF): выбор чеклиста, прогон проверок через скиллы
  валидации и поиск по исходникам, отчёт OK/Warning/Blocker и обязательный
  блок ручных шагов. Use when user mentions Фреш, 1cfresh, аудит расширения,
  публикация в сервисе, безопасный режим, комплект поставки, профили
  безопасности или подготовку CFE/EPF к облаку.
---

# 1С:Фреш — оркестратор адаптации

Отвечай на русском. Опирайся на официальные требования 1cfresh.com (версия статей от 18.10.2023 и рекомендации по аудиту).

## Когда запускать

- Пользователь готовит/проверяет расширение или доп. обработку/отчёт для Фреша
- Упоминаются аудит, публикация в сервисе, безопасный режим, разрешения, комплект поставки
- В проекте есть CFE/EPF, которые планируется выложить в облако

## Маршрутизация

1. Определи тип средства адаптации:
   - **CFE** (каталог расширения, `.cfe`, `Configuration.xml` расширения) → прочитай и выполни [1c-fresh-cfe-audit/SKILL.md](1c-fresh-cfe-audit/SKILL.md)
   - **EPF/ERF** (внешняя обработка/отчёт) → прочитай и выполни [1c-fresh-epf-audit/SKILL.md](1c-fresh-epf-audit/SKILL.md) и при необходимости правило `bsp-developer`
   - **Неясно** → спроси одним вопросом; если в workspace есть только CFE — начни с CFE
2. Общие запрещённые/рискованные паттерны ищи сразу (см. ниже), даже до детального чеклиста.
3. Ручные шаги — всегда из [manual-steps.md](manual-steps.md).

## Проверки (обязательный контур)

Используй доступные инструменты; если чего-то нет — отметь в отчёте `Skipped`, не имитируй результат.

| Задача | Инструменты |
|---|---|
| Структура CFE/EPF, свойства, validate | скиллы `cfe-validate`, `epf-validate`, `erf-validate`, `meta-info`, `cf-info` |
| Разбор макета/формы, поиск кода | `form-info`, `skd-info`, `mxl-info`; поиск по исходникам `src/` |
| Стандарты модели сервиса | требования в чеклистах; `v8std_search` / `v8std_get_page` — если доступны (`std760`, `std642`, `std669`, `DisableSafeMode`) |
| Правки метаданных | только через скиллы `meta-*`/`form-*`/`cfe-*` и т.п. (см. правило `1c-development-process`) |

### Паттерны для поиска в коде (Blocker / Warning)

Ищи и классифицируй по исходникам `src/cfe`, `src/epf`, `src/erf` (ищи во всех `.bsl`, `.os`, `Module.xml`):

| Паттерн | Уровень |
|---|---|
| `COMОбъект`, создание COM | Blocker |
| `Выполнить(` / `Вычислить(` | Blocker |
| Привилегированный режим без заявленного разрешения | Blocker |
| Хардкод путей (`"/tmp/`, `C:\`, каталог программы) вместо `ПолучитьИмяВременногоФайла` | Blocker |
| `ОбменДанными.Загрузка = Истина` без явной необходимости | Warning/Blocker |
| HTTP/FTP/интернет на сервере без разрешений | Blocker |
| Обращение `ВнешняяОбработка.<Имя>` / `ВнешнийОтчет.<Имя>` | Blocker (для EPF) |
| Длительные циклы/запросы без механизма длительных операций БСП | Warning |
| Универсальные перенумераторы / поиск-замена / удаление без контроля целостности | Blocker (аудит) |

## Формат итогового отчёта

Всегда выдавай отчёт в таком виде:

```markdown
## Аудит 1С:Фреш: <CFE|EPF> — <имя>

**Вердикт:** Ready | Ready with warnings | Not ready

### Blocker
- ...

### Warning
- ...

### OK
- ...

### Проверки
| Проверка | Результат | Комментарий |
|---|---|---|
| cfe-validate | OK/Fail/Skipped | ... |

## НУЖНА РУЧНАЯ НАСТРОЙКА
...см. manual-steps.md, только релевантные пункты...
```

Правила вердикта:

- Есть хотя бы один **Blocker** → `Not ready`
- Только Warning → `Ready with warnings`
- Blocker нет → `Ready` (но ручной блок всё равно обязателен)

## Источники (не выдумывать требования)

- https://www.1cfresh.com/articles/so_confext_req
- https://1cfresh.com/articles/so_addprocess_req
- https://1cfresh.com/articles/so_addprocess_fastaudit
- https://www.1cfresh.com/articles/so_addprocess_prep
- https://www.1cfresh.com/articles/so_validation_plugin
- https://www.1cfresh.com/articles/so_confext_load

## Связанные скиллы

- [manual-steps.md](manual-steps.md) — ручные действия пользователя
- [1c-fresh-cfe-audit/SKILL.md](1c-fresh-cfe-audit/SKILL.md)
- [1c-fresh-epf-audit/SKILL.md](1c-fresh-epf-audit/SKILL.md)
- правила `bsp-developer`, `1c-development-process`, `bsl-senior-developer`

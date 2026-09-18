---
name: erf-init
description: Создать пустой внешний отчёт 1С (scaffold XML-исходников). Используй когда нужно создать новый внешний отчёт с нуля
argument-hint: <Name> [Synonym] [--with-skd]
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# /erf-init — Создание нового отчёта

Генерирует минимальный набор XML-исходников для внешнего отчёта 1С в **nested**-раскладке (канон ecoladev / bsl-analyzer auto-discovery).

## Раскладка

```
src/erf/<Name>/
  <Name>.xml          ← корневой MetaDataObject
  <Name>/             ← каталог объекта (Ext, Forms, Templates, …)
    Ext/ObjectModule.bsl
```

Плоский вариант (`src/erf/<Name>.xml` рядом с `src/erf/<Name>/`) **не** создавать — auto-discovery `src/erf/*` его не подхватывает.
Вспомогательные файлы (skd-*.sql/json) — в `src/erf/<Name>/` рядом с корневым XML, не в `build/`.
Собранные `.erf` — только в `build/out/erf/`.

## Usage

```
/erf-init <Name> [Synonym] [SrcDir] [FormatVersion] [--with-skd]
```

| Параметр      | Обязательный | По умолчанию | Описание                              |
|---------------|:------------:|--------------|---------------------------------------|
| Name          | да           | —            | Имя отчёта (латиница/кириллица)       |
| Synonym       | нет          | = Name       | Синоним (отображаемое имя)            |
| SrcDir        | нет          | `src/erf`    | Корзина исходников; внутри создаётся `<Name>/` |
| FormatVersion | нет          | `2.17`       | Версия формата выгрузки — см. ниже              |
| --WithSKD     | нет          | —            | Создать пустую СКД и привязать к MainDataCompositionSchema |

`SrcDir` — каталог-корзина (`src/erf`), **не** путь `src/erf/<Name>`: скрипт сам добавляет уровень `<Name>/`.

`FormatVersion` — **не выше** версии формата платформы, на которой объект будут собирать и открывать:
8.3.24 — `2.17`, 8.3.25 — `2.18`, 8.3.26 — `2.19`, 8.3.27 — `2.20`, 8.5 — `2.21`. Ниже брать можно:
платформа читает свой формат и любой более старый, поэтому дефолт `2.17` подходит для всей линейки
8.3.24 и выше. Для более старых платформ счёт идёт так же, по одной версии на релиз (8.3.23 — `2.16`),
но на них навыки не проверялись — такое значение принимается с предупреждением.

## Команда

```powershell
powershell.exe -NoProfile -File "%USERPROFILE%\.cursor\skills\erf-init\scripts/init.ps1" -Name "<Name>" [-Synonym "<Synonym>"] [-SrcDir "src/erf"] [-FormatVersion "<версия>"] [-WithSKD]
```

## Дальнейшие шаги

- Добавить форму: `/form-add`
- Добавить макет: `/template-add`
- Добавить справку: `/help-add`
- Валидация: `/erf-validate` с `-ObjectPath "src/erf/<Name>"`
- Собрать ERF: MCP `epf_compile` (`SRC=./src/erf/<Name>`, `out=./build/out/erf`)

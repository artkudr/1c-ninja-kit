---
name: epf-init
description: Создать пустую внешнюю обработку 1С (scaffold XML-исходников). Используй когда нужно создать новую внешнюю обработку с нуля
argument-hint: <Name> [Synonym]
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# /epf-init — Создание новой обработки

Генерирует минимальный набор XML-исходников для внешней обработки 1С в **nested**-раскладке (канон ecoladev / bsl-analyzer auto-discovery).

## Раскладка

```
src/epf/<Name>/
  <Name>.xml          ← корневой MetaDataObject
  <Name>/             ← каталог объекта (Ext, Forms, Templates, …)
    Ext/ObjectModule.bsl
```

Плоский вариант (`src/epf/<Name>.xml` рядом с `src/epf/<Name>/`) **не** создавать — auto-discovery `src/epf/*` его не подхватывает.

## Usage

```
/epf-init <Name> [Synonym] [SrcDir] [FormatVersion]
```

| Параметр      | Обязательный | По умолчанию | Описание                                       |
|---------------|:------------:|--------------|------------------------------------------------|
| Name          | да           | —            | Имя обработки (латиница/кириллица)             |
| Synonym       | нет          | = Name       | Синоним (отображаемое имя)                     |
| SrcDir        | нет          | `src/epf`    | Корзина исходников; внутри создаётся `<Name>/` |
| FormatVersion | нет          | `2.17`       | Версия формата выгрузки — см. ниже              |

`SrcDir` — каталог-корзина (`src/epf`), **не** путь `src/epf/<Name>`: скрипт сам добавляет уровень `<Name>/`.

`FormatVersion` — **не выше** версии формата платформы, на которой объект будут собирать и открывать:
8.3.24 — `2.17`, 8.3.25 — `2.18`, 8.3.26 — `2.19`, 8.3.27 — `2.20`, 8.5 — `2.21`. Ниже брать можно:
платформа читает свой формат и любой более старый, поэтому дефолт `2.17` подходит для всей линейки
8.3.24 и выше. Для более старых платформ счёт идёт так же, по одной версии на релиз (8.3.23 — `2.16`),
но на них навыки не проверялись — такое значение принимается с предупреждением.

## Команда

```powershell
powershell.exe -NoProfile -File "%USERPROFILE%\.cursor\skills\epf-init\scripts/init.ps1" -Name "<Name>" [-Synonym "<Synonym>"] [-SrcDir "src/epf"] [-FormatVersion "<версия>"]
```

## Дальнейшие шаги

- Добавить форму: `/form-add` (пути внутри `src/epf/<Name>/<Name>/…`)
- Добавить макет: `/template-add`
- Добавить справку: `/help-add`
- Валидация: `/epf-validate` с `-ObjectPath "src/epf/<Name>"`
- Собрать EPF: MCP `epf_compile` (`SRC=./src/epf/<Name>`, `out=./build/out/epf`)

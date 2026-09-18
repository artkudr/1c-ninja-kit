# Локальные доработки vanessa-runner (ovm)

Машинные патчи поверх глобального `vanessa-runner` 3.x из OVM.  
**Не в upstream** — после `opm install` / обновления ovm нужно повторить по этому гайду.

База OVM: `%LOCALAPPDATA%\ovm\current\lib\vanessa-runner\`  
Дата фиксации: 2026-08-29 (ecoladev / ecola-aka-dev).  
Повтор после `opm install vanessa-runner@3.0.0`: **2026-09-17** (было `3.0.0_beta` → стало `3.0.0`; патчи 1 и 2 нанесены поверх стока 3.0.0, EPF пересобраны).

---

## Зачем

| Симптом | Причина | Патч |
|--------|---------|------|
| `vrunner infobase extensions list` / MCP `extensions_list`: платформа код 0, но «обработка не записала файл результата» на **серверной** ИБ | `ЗаписатьФайлРезультата` была `&НаСервереБезКонтекста` → JSON писался на сервере 1С, а runner ждал файл в локальном `%TEMP%` | **1. EPF** |
| MCP `extensions_list` (и другие sync-команды) отвечают только «… — выполнено» без полезного вывода | `autumn-mcpify`: `ВыполнитьСинхронно` всегда возвращал только эту фразу; INFO уходил в notifications, Cursor их агенту не показывает | **2. MCP** |
| `repo.ps1 -Action load`: «Ошибка чтения параметров команды» на **vrunner 3** | `--additional` начинался с `-Extension …` → CLI vrunner воспринимал `-Extension` как свой ключ, а не аргумент designer | **3. repo-workflow** (скилл, не ovm) |

Связанное (не патч ovm): скилл `cfe-list` удалён. **Главный способ** списка расширений ИБ — MCP `1c-ninja-mcp` `live_extensions_list` (CFE `NinjaLive`, без запуска Предприятия). MCP `extensions_list` / `vrunner infobase extensions list` — устаревший fallback; патчи ниже нужны только если кто-то всё же дергает этот путь.

---

## 1. EPF: запись результата на клиенте

### Файлы (исходники)

Корень: `...\vanessa-runner\epf\`

- `РаботаСРасширениями\РаботаСРасширениями\Forms\Форма\Ext\Form\Module.bsl` — обязательно  
- `СоздатьПользователей\...\Module.bsl` — тот же инфраструктурный кусок  
- `ШаблонОбработки\...\Module.bsl` — эталон для будущих обработок  

### Правка

У процедуры `ЗаписатьФайлРезультата`:

```bsl
// Было:
&НаСервереБезКонтекста
Процедура ЗаписатьФайлРезультата(...)

// Стало:
&НаКлиенте
Процедура ЗаписатьФайлРезультата(...)
```

Комментарий (по желанию): писать на клиенте, т.к. `ФайлРезультата=` указывает на локальный `%TEMP%` машины runner’а.

### Пересборка EPF

После правки исходников собрать бинарники в тот же `epf\`:

- `РаботаСРасширениями.epf`  
- `СоздатьПользователей.epf`  
- `ШаблонОбработки.epf` (по желанию)

Через MCP `epf_compile` (или CLI), например:

```
SRC = %LOCALAPPDATA%\ovm\current\lib\vanessa-runner\epf\РаботаСРасширениями
out = %LOCALAPPDATA%\ovm\current\lib\vanessa-runner\epf
v8version = 8.3.27.2130
nocache = true
```

Проверка содержимого бинарника: `epf_decompile` → в Module.bsl у `ЗаписатьФайлРезультата` должно быть `&НаКлиенте`.

### Проверка

```powershell
cd <корень-проекта-с-autumn-properties>
vrunner infobase extensions list --json --v8version=8.3.27.2130
```

Ожидание: JSON со списком расширений, **без** «Обработка не записала файл результата».

---

## 2. MCP: INFO в ответе tools/call

### Файлы

Корень: `...\vanessa-runner\oscript_modules\autumn-mcpify\src\internal\Классы\`

1. **`MCP_БуферАппендер.os`**
   - Массив `_Сообщения` + накопление в `ВывестиСобытие`
   - Метод `ПолучитьСообщения()` — тексты без префиксов уровня/логгера

2. **`MCP_ИнструментКоманды.os`** — функция `ВыполнитьСинхронно`
   - На время вызова: `MCP_БуферАппендер` на уровне `Информация` (`ПодключитьБуферИнформации` / `ОтключитьБуферИнформации`)
   - После успеха: если есть сообщения →  
     `"%Описание% - выполнено." + ПС + Вывод`  
     иначе как раньше только «выполнено»

Суть: Cursor показывает агенту результат tool call, а не MCP notifications — поэтому INFO нужно класть в return строки.

### Перезапуск MCP

Код OneScript грузится при старте процесса. После правки:

1. Убить `oscript ...\vanessa-runner\src\mcp.os` (или Toggle MCP **vrunner** в Cursor)
2. При следующем вызове сервер поднимется заново (`vrunner-mcp.bat` из project `.cursor/mcp.json`)

### Проверка

MCP `extensions_list` с `json=true` и подключением к ИБ → в ответе не только «выполнено», но и JSON списка (плюс служебные INFO вроде «Выполняю команду…»).

---

## 3. repo-workflow: load под vrunner 3

### Файл

`%USERPROFILE%\.cursor\skills\repo-workflow\scripts\repo.ps1` — блок `$Action -eq 'load'`.

### Правка

Строка `$additional` для `LoadConfigFromFiles` должна начинаться с `/DisplayAllFunctions`, **не** с `-Extension`:

```powershell
# Было (vrunner 2 / старый разбор — OK; vrunner 3 — «Ошибка чтения параметров команды»):
$additional = "-Extension `"$name`" /ConfigurationRepositoryF ..."

# Стало:
$additional = "/DisplayAllFunctions -Extension `"$name`" /ConfigurationRepositoryF ..."
```

### Проверка

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\.cursor\skills\repo-workflow\scripts\repo.ps1" -Action load -Extension "ИмяРасширения" -SkipWebTest
```

Не должно быть «Ошибка чтения параметров команды» до запуска Конфигуратора.

---

## После обновления vanessa-runner / ovm

1. Открыть этот файл.  
2. Проверить симптомы из таблицы «Зачем».  
3. Если снова сломано — повторить патчи **1** и/или **2**. Патч **3** — в скилле `repo-workflow`, переживает обновление ovm.  
4. Если в новом релизе уже есть фикс — патч не нужен (сверить директиву / наличие буфера INFO в ответе).

Не коммитить правки внутрь `%LOCALAPPDATA%\ovm\` в git проектов — это глобальная установка пакета.

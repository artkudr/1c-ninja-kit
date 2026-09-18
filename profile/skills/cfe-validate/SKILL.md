---
name: cfe-validate
description: Валидация расширения конфигурации 1С (CFE). Используй после создания или модификации расширения для проверки корректности
argument-hint: <ExtensionPath> [-ConfigPath <ConfigDir>] [-Detailed] [-MaxErrors 30]
allowed-tools:
  - Bash
  - Read
  - Glob
---

# /cfe-validate — валидация расширения конфигурации (CFE)

Проверяет структурную корректность расширения: XML-формат, свойства, состав, заимствованные объекты, права ролей. Аналог `/cf-validate`, но для расширений.

Проверяются исходники. Применимость — уже после загрузки в базу: `/db-cfe-admin check`.

## Параметры

| Параметр      | Обяз. | Умолч. | Описание                                        |
|---------------|:-----:|---------|-------------------------------------------------|
| ExtensionPath | да    | —       | Путь к каталогу или Configuration.xml расширения |
| ConfigPath    | нет   | —       | Каталог конфигурации, из которой заимствованы объекты |
| Detailed      | нет   | —       | Подробный вывод (все проверки, включая успешные)  |
| MaxErrors     | нет   | 30      | Остановиться после N ошибок                      |
| OutFile       | нет   | —       | Записать результат в файл                        |

### ConfigPath

Указывай всегда, когда конфигурация-источник доступна: без неё часть ошибок заимствованных форм не ловится, и расширение может пройти валидацию, а потом быть отвергнутым платформой при загрузке.

Если пользователь не указал путь — определи сам:
1. Прочитай скилл `1c-project-context` / корень проекта
2. Если есть `src/cf` (или `src/cf/Configuration.xml`) — используй как `-ConfigPath`
3. Иначе спроси у пользователя

## Команда

```powershell
powershell.exe -NoProfile -File "%USERPROFILE%\.cursor\skills\cfe-validate\scripts/cfe-validate.ps1" -ExtensionPath "src\cfe\extname"
powershell.exe -NoProfile -File "%USERPROFILE%\.cursor\skills\cfe-validate\scripts/cfe-validate.ps1" -ExtensionPath "src\cfe\extname\Configuration.xml"
powershell.exe -NoProfile -File "%USERPROFILE%\.cursor\skills\cfe-validate\scripts/cfe-validate.ps1" -ExtensionPath "src\cfe\extname" -ConfigPath "src\cf"
```

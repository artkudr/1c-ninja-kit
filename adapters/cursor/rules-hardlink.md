# Rules hardlink (Windows)

Канон правил: `%USERPROFILE%\.cursor\rules\`.  
Cursor в проекте читает только `<project>\.cursor\rules\*.mdc` как файлы.

## Порядок

1. Обычная папка `<project>\.cursor\rules` (не junction).
2. Для каждого `.mdc` из канона:
   - file symlink `mklink` — если есть право / Developer Mode;
   - иначе **hardlink** `mklink /H`;
   - копия — только другой диск.

## Запрещено

```text
mklink /J ...\.cursor\rules   ← НЕЛЬЗЯ
mklink /D ...\.cursor\rules   ← НЕЛЬЗЯ на папку
```

Снятие ошибочного junction: `cmd /c rmdir` на junction (без `/S`), затем создать обычную папку.

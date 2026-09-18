# Install profile (Cursor)

v0.1: полный `kit apply` ещё soft — используйте robocopy / сравнение, затем v0.2.

```powershell
$kit = 'C:\1C\projects\1c-ninja-kit'
$dst = Join-Path $env:USERPROFILE '.cursor'

# Preview
robocopy "$kit\profile\skills" "$dst\skills" /E /L /XD .git .build
robocopy "$kit\profile\rules"  "$dst\rules"  /E /L /XF *.bak
robocopy "$kit\profile\agents" "$dst\agents" /E /L

# Apply (осторожно на уже живом профиле — лучше diff)
# robocopy ... без /L
```

После sync: убедиться, что user `mcp.json` **не** содержит 1С-серверов.

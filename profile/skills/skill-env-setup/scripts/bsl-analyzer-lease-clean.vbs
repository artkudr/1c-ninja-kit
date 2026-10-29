' Silent launcher for bsl-analyzer-lease-clean.ps1.
'
' The scheduled task "bsl-analyzer lease clean" calls this file instead of pwsh.exe.
' Task Scheduler starts console programs in the interactive session, so calling pwsh.exe
' directly always shows a console window (pwsh -WindowStyle Hidden included - conhost
' shows the window before PowerShell hides it). wscript.exe is a GUI-subsystem process,
' and WshShell.Run with window style 0 starts pwsh with a hidden console from the start.
'
' The exit code of the PowerShell script is passed back to Task Scheduler.

Option Explicit

Dim fso, sh, baseDir, ps1, pwsh, cmd, rc

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(baseDir, "bsl-analyzer-lease-clean.ps1")
If Not fso.FileExists(ps1) Then WScript.Quit 2

pwsh = sh.ExpandEnvironmentStrings("%ProgramFiles%\PowerShell\7\pwsh.exe")
If Not fso.FileExists(pwsh) Then pwsh = "pwsh.exe"

cmd = """" & pwsh & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
rc = sh.Run(cmd, 0, True)
WScript.Quit rc

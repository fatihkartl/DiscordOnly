Option Explicit
' Launch the UI directly elevated: avoids first spawning an ordinary PowerShell
' merely to start a second elevated PowerShell. No visible console is created.
' Windows will still show the normal UAC approval prompt when required.
Dim shell, fso, root, launcher, exe, quote, arguments
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = fso.BuildPath(root, "app\launcher.ps1")
If Not fso.FileExists(launcher) Then
    MsgBox "app\launcher.ps1 missing. Extract the full ZIP.", 16, "DiscordOnly"
    WScript.Quit 1
End If
Set shell = CreateObject("Shell.Application")
exe = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
quote = Chr(34)
arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & quote & launcher & quote
On Error Resume Next
shell.ShellExecute exe, arguments, root, "runas", 0
If Err.Number <> 0 Then
    MsgBox "DiscordOnly could not start: " & Err.Description, 16, "DiscordOnly"
    WScript.Quit 1
End If

' Wrapper silencioso: chama o launch-claude-profile.ps1 sem piscar janela de console.
' Uso: wscript.exe launch-claude-profile.vbs <Slug>
' Resolve a propria pasta em tempo de execucao, entao nao guarda caminho nenhum.
Option Explicit
Dim fso, sh, dir, slug

If WScript.Arguments.Count < 1 Then
    MsgBox "Uso: launch-claude-profile.vbs <Slug>", 16, "Claude - perfil isolado"
    WScript.Quit 1
End If

slug = WScript.Arguments(0)
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\launch-claude-profile.ps1"" -Slug """ & slug & """", 0, False

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""W:\CodeDeX\Connect-Phone-ADB\bin\Connect-Engine.ps1""", 0, False

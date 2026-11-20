#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off

OnError((err, mode) => Fail(err.Message))
pid := DllCall("GetCurrentProcessId", "UInt")
Loop MonitorGetCount() {
    MonitorGetWorkArea(A_Index, &left, &top)
    editor := Gui(, "SQL editor test window")
    editor.AddEdit("w200")
    editor.Show("x" (left + 100) " y" (top + 100))
    CheckWarning(editor.Hwnd, FormatSqlSelection, "SQL Formatter", pid)
    CheckWarning(editor.Hwnd, ConvertSqlSelection, "SQL Log Converter", pid)
    editor.Destroy()
}

FileAppend("PASS (" A_PtrSize * 8 "-bit, " MonitorGetCount() " monitor(s))" Chr(10), "*")
ExitApp()

CheckWarning(editor, command, title, pid) {
    checked := false
    SetTimer(() => checked := VerifyWarning(editor, title, pid), -50)
    ; The fixture has no DBeaver SQL tab, so the command warns before copying.
    command.Call(editor)
    if !checked
        Fail(title " returned before its warning could be checked.")
}

VerifyWarning(editor, title, pid) {
    warning := WinWait(title " ahk_class #32770 ahk_pid " pid, , 3)
    if !warning
        Fail(title " did not show a warning.")
    if DllCall("MonitorFromWindow", "Ptr", warning, "UInt", 2, "Ptr")
        != DllCall("MonitorFromWindow", "Ptr", editor, "UInt", 2, "Ptr")
        Fail(title " opened on a different monitor than the editor.")
    if DllCall("GetWindow", "Ptr", warning, "UInt", 4, "Ptr") != editor ; GW_OWNER
        Fail(title " did not use the editor as its owner.")
    WinClose(warning)
    return true
}

Fail(message) {
    FileAppend("FAIL: " message Chr(10), "**")
    ExitApp(1)
}

#Include "..\SqlFormat.ahk"
#Include "..\SqlLogConvert.ahk"

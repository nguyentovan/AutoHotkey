#Requires AutoHotkey v2.0

if A_LineFile = A_ScriptFullPath
    ExitApp()

; Main includes this variant before the converter so both commands share Ctrl+K.
#HotIf IsSqlFormatEditor()
$^k:: {
    editor := WinActive("A")
    chord := InputHook("V T1.5")
    chord.KeyOpt("{All}", "E")
    chord.KeyOpt("{LControl}{RControl}", "-E +N")
    chord.KeyOpt("yf", "+S")
    chord.OnKeyUp := (hook, vk, sc) => hook.Stop()
    chord.Start()
    chord.Wait()
    key := chord.EndKey
    if (key != "Y" && key != "F") || !InStr(chord.EndMods, "^")
        return
    if !KeyWait(key, "T2")
        return
    KeyWait("Ctrl", "T2")
    if GetKeyState("Ctrl", "P") || !WinActive(editor)
        return
    if key = "Y"
        GetSqlConvertFunction("ConvertSqlSelection").Call(editor)
    else
        FormatSqlSelection(editor)
}
#HotIf

IsSqlFormatEditor() {
    return (WinActive("ahk_exe ssms.exe") || WinActive("ahk_exe dbeaver.exe"))
        && GetSqlConvertFunction("ConvertSqlSelection")
}

FormatSqlSelection(editor) {
    originalClipboard := ClipboardAll()
    errorMessage := ""
    clipboardHasWholeLine := GetSqlConvertFunction("ClipboardHasWholeLine")
    try {
        A_Clipboard := ""
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        Send("^c")
        copied := ClipWait(1)
        if copied
            clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        if !copied || clipboardHasWholeLine.Call()
            throw Error("Select the SQL to format first.")

        inputText := A_Clipboard
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        sql := FormatSqlText(inputText, A_ScriptDir)
        if !WinActive(editor)
            return

        ; Recheck the selection before replacing it.
        if DllCall("GetClipboardSequenceNumber", "UInt") != clipboardSequence
            return
        A_Clipboard := ""
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        Send("^c")
        copied := ClipWait(1)
        if copied
            clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        if !copied || clipboardHasWholeLine.Call()
            return
        selection := A_Clipboard
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        if selection !== inputText || !WinActive(editor)
            return

        A_Clipboard := sql
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        Send("^v")
        Sleep(250)
    } catch Error as err {
        errorMessage := err.Message
    } finally {
        if IsSet(clipboardSequence) && DllCall("GetClipboardSequenceNumber", "UInt") = clipboardSequence
            A_Clipboard := originalClipboard
    }
    if errorMessage != ""
        MsgBox(errorMessage, "SQL Formatter", "Icon!")
}

FormatSqlText(inputText, directory) {
    executable := directory "\Zea.SqlFormat.exe"
    if !FileExist(executable)
        throw Error("SQL Formatter not found: " executable)

    return GetSqlConvertFunction("ConvertSqlLogText").Call(inputText, executable)
}

GetSqlConvertFunction(name) {
    global
    return IsSet(%name%) ? %name% : false
}

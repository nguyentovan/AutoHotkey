#Requires AutoHotkey v2.0

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
        ConvertSqlSelection(editor)
    else
        FormatSqlSelection(editor)
}
#HotIf

IsSqlFormatEditor() {
    return WinActive("ahk_exe ssms.exe") || WinActive("ahk_exe dbeaver.exe")
}

FormatSqlSelection(editor) {
    originalClipboard := ClipboardAll()
    errorMessage := ""
    try {
        A_Clipboard := ""
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        Send("^c")
        copied := ClipWait(1)
        if copied
            clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        if !copied || ClipboardHasWholeLine()
            throw Error("Select the SQL to format first.")

        inputText := A_Clipboard
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        executable := A_ScriptDir "\Zea.SqlFormat.exe"
        sql := FormatSqlText(inputText, executable)
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
        if !copied || ClipboardHasWholeLine()
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

FormatSqlText(inputText, executable) {
    if !FileExist(executable)
        throw Error("SQL Formatter not found: " executable)

    return ConvertSqlLogText(inputText, executable)
}

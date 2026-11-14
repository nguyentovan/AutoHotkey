#Requires AutoHotkey v2.0

if A_LineFile = A_ScriptFullPath
    ExitApp()

#HotIf WinActive("ahk_exe ssms.exe") || WinActive("ahk_exe dbeaver.exe")
$^k:: {
    editor := WinActive("A")
    chord := InputHook("V T1.5")
    chord.KeyOpt("{All}", "E")
    chord.KeyOpt("{LControl}{RControl}", "-E +N")
    chord.KeyOpt("y", "+S")
    chord.OnKeyUp := (hook, vk, sc) => hook.Stop()
    chord.Start()
    chord.Wait()
    if chord.EndKey != "Y" || !InStr(chord.EndMods, "^")
        return
    if !KeyWait("y", "T2")
        return
    KeyWait("Ctrl", "T2")
    if !GetKeyState("Ctrl", "P") && WinActive(editor)
        ConvertSqlSelection(editor)
}
#HotIf

ConvertSqlSelection(editor) {
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
            throw Error("Select one SQL log block first.")

        log := A_Clipboard
        clipboardSequence := DllCall("GetClipboardSequenceNumber", "UInt")
        sql := ConvertAndFormatSqlText(log, A_ScriptDir)
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
        if selection !== log || !WinActive(editor)
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
        MsgBox(errorMessage, "SQL Log Converter", "Icon!")
}

ClipboardHasWholeLine() {
    for name in ["VisualStudioEditorOperationsLineCutCopyClipboardTag", "MSDEVLineSelect"] {
        format := DllCall("RegisterClipboardFormatW", "Str", name, "UInt")
        if format && DllCall("IsClipboardFormatAvailable", "UInt", format)
            return true
    }
    return false
}

ConvertAndFormatSqlText(log, directory) {
    sql := ConvertSqlLogText(log, directory "\Zea.SqlLogConvert.exe")
    formatter := directory "\Zea.SqlFormat.exe"
    if !FileExist(formatter)
        throw Error("SQL Formatter not found: " formatter)

    return ConvertSqlLogText(sql, formatter)
}

ConvertSqlLogText(log, executable) {
    if !FileExist(executable)
        throw Error("Converter not found: " executable)

    inputRead := inputWrite := outputRead := outputWrite := process := thread := 0
    try {
        security := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
        NumPut("UInt", security.Size, security)
        NumPut("Int", 1, security, 2 * A_PtrSize)
        if !DllCall("CreatePipe", "Ptr*", &inputRead, "Ptr*", &inputWrite, "Ptr", security, "UInt", 0)
            throw OSError()
        if !DllCall("CreatePipe", "Ptr*", &outputRead, "Ptr*", &outputWrite, "Ptr", security, "UInt", 0)
            throw OSError()
        if !DllCall("SetHandleInformation", "Ptr", inputWrite, "UInt", 1, "UInt", 0)
            || !DllCall("SetHandleInformation", "Ptr", outputRead, "UInt", 1, "UInt", 0)
            throw OSError()

        startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
        NumPut("UInt", startup.Size, startup)
        NumPut("UInt", 0x100, startup, A_PtrSize = 8 ? 60 : 44) ; STARTF_USESTDHANDLES
        NumPut("Ptr", inputRead, "Ptr", outputWrite, "Ptr", outputWrite, startup, startup.Size - 3 * A_PtrSize)
        processInfo := Buffer(2 * A_PtrSize + 8, 0)
        command := '"' executable '"'
        if !DllCall("CreateProcessW", "Str", executable, "Str", command, "Ptr", 0, "Ptr", 0,
            "Int", true, "UInt", 0x08000000, "Ptr", 0, "Ptr", 0, "Ptr", startup, "Ptr", processInfo)
            throw OSError()
        process := NumGet(processInfo, 0, "Ptr")
        thread := NumGet(processInfo, A_PtrSize, "Ptr")
        CloseSqlLogHandle(&inputRead)
        CloseSqlLogHandle(&outputWrite)

        ; The converter reads all stdin before producing either SQL or a diagnostic.
        input := Buffer(StrPut(log, "UTF-8"))
        size := StrPut(log, input, "UTF-8") - 1
        if size && (!DllCall("WriteFile", "Ptr", inputWrite, "Ptr", input, "UInt", size,
            "UInt*", &written := 0, "Ptr", 0) || written != size)
            throw OSError()
        CloseSqlLogHandle(&inputWrite)

        output := Buffer(4096)
        bytes := 0
        loop {
            if bytes = output.Size
                output.Size *= 2
            if !DllCall("ReadFile", "Ptr", outputRead, "Ptr", output.Ptr + bytes, "UInt", output.Size - bytes,
                "UInt*", &read := 0, "Ptr", 0) {
                if A_LastError != 109 ; ERROR_BROKEN_PIPE signals EOF.
                    throw OSError()
                break
            }
            bytes += read
        }

        if DllCall("WaitForSingleObject", "Ptr", process, "UInt", 5000, "UInt") != 0
            throw Error("The converter did not exit.")
        if !DllCall("GetExitCodeProcess", "Ptr", process, "UInt*", &exitCode := 0)
            throw OSError()
        result := bytes ? RTrim(StrGet(output.Ptr, bytes, "UTF-8"), Chr(13) Chr(10)) : ""
        if exitCode != 0 || result = ""
            throw Error(result != "" ? result : "The converter returned no SQL.")
        return result
    } finally {
        CloseSqlLogHandle(&inputRead)
        CloseSqlLogHandle(&inputWrite)
        CloseSqlLogHandle(&outputRead)
        CloseSqlLogHandle(&outputWrite)
        CloseSqlLogHandle(&thread)
        CloseSqlLogHandle(&process)
    }
}

CloseSqlLogHandle(&handle) {
    if handle {
        DllCall("CloseHandle", "Ptr", handle)
        handle := 0
    }
}

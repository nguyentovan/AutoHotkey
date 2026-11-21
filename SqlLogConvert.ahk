#Requires AutoHotkey v2.0

if A_LineFile = A_ScriptFullPath
    ExitApp()

#HotIf (WinActive("ahk_exe ssms.exe") || WinActive("ahk_exe dbeaver.exe")) && SqlChordKeys() != ""
$^k:: {
    editor := WinActive("A")
    keys := SqlChordKeys()
    chord := InputHook("V T1.5")
    chord.KeyOpt("{All}", "E")
    chord.KeyOpt("{LControl}{RControl}", "-E +N")
    chord.KeyOpt(keys, "+S")
    chord.OnKeyUp := (hook, vk, sc) => hook.Stop()
    chord.Start()
    chord.Wait()
    key := chord.EndKey
    if key = "" || !InStr(keys, key) || !InStr(chord.EndMods, "^")
        return
    if !KeyWait(key, "T2")
        return
    KeyWait("Ctrl", "T2")
    if GetKeyState("Ctrl", "P") || !WinActive(editor)
        return
    if key = "G"
        ConvertSqlSelection(editor)
    else
        FormatSqlSelection(editor)
}
#HotIf

SqlChordKeys() {
    global
    local keys := (sqlLogConvertEnabled ?? true) ? "g" : ""
    if GetEnabledSqlFormatter()
        keys .= "y"
    return keys
}

ConvertSqlSelection(editor) {
    originalClipboard := ClipboardAll()
    errorMessage := ""
    try {
        target := GetLogFormatTarget(editor)
        if !WinActive(editor)
            return
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
        sql := RunSqlWithProgress(editor, "Converting SQL log...",
            ConvertAndFormatSqlText.Bind(log, A_ScriptDir, target ? target.dialect : ""))
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

        if target && !IsSameSqlFormatTarget(editor, target, clipboardSequence)
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
        MsgBox(errorMessage, "SQL Log Converter", "Icon!" (WinExist(editor) ? " Owner" editor : ""))
}

ClipboardHasWholeLine() {
    for name in ["VisualStudioEditorOperationsLineCutCopyClipboardTag", "MSDEVLineSelect"] {
        format := DllCall("RegisterClipboardFormatW", "Str", name, "UInt")
        if format && DllCall("IsClipboardFormatAvailable", "UInt", format)
            return true
    }
    return false
}

GetEnabledSqlFormatter() {
    global
    local formatter := "FormatSqlText"
    return (sqlFormatEnabled ?? true) && IsSet(%formatter%) ? %formatter% : false
}

GetLogFormatTarget(editor) {
    return GetEnabledSqlFormatter() ? GetSqlFormatTarget(editor) : false
}

RunSqlWithProgress(editor, message, action) {
    window := Gui("+Owner" editor " +ToolWindow -Caption +E0x08000000", "SQL Tools") ; WS_EX_NOACTIVATE
    try {
        window.AddText("w250", message)
        progress := window.AddProgress("w250 h10 +0x8") ; PBS_MARQUEE
        window.Show("AutoSize Hide")

        ; Use the editor's monitor work area and screen coordinates, which can be negative.
        monitor := DllCall("MonitorFromWindow", "Ptr", editor, "UInt", 2, "Ptr") ; MONITOR_DEFAULTTONEAREST
        monitorInfo := Buffer(40) ; MONITORINFO
        NumPut("UInt", monitorInfo.Size, monitorInfo)
        windowRect := Buffer(16)
        position := "Center"
        if monitor && DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", monitorInfo)
            && DllCall("GetWindowRect", "Ptr", window.Hwnd, "Ptr", windowRect) {
            width := NumGet(windowRect, 8, "Int") - NumGet(windowRect, 0, "Int")
            height := NumGet(windowRect, 12, "Int") - NumGet(windowRect, 4, "Int")
            x := (NumGet(monitorInfo, 20, "Int") + NumGet(monitorInfo, 28, "Int") - width) // 2
            y := (NumGet(monitorInfo, 24, "Int") + NumGet(monitorInfo, 32, "Int") - height) // 2
            position := "x" x " y" y
        }
        window.Show("NoActivate " position)
        SendMessage(0x40A, 1, 0, progress.Hwnd) ; PBM_SETMARQUEE
        Sleep(-1)
        return action.Call()
    } finally {
        window.Destroy()
    }
}

ConvertAndFormatSqlText(log, directory, dialect) {
    sql := ConvertSqlLogText(log, directory "\Zea.SqlLogConvert.exe")
    if dialect != "" && (formatter := GetEnabledSqlFormatter())
        sql := formatter.Call(sql, directory, dialect)
    return sql
}

ConvertSqlLogText(log, executable, arguments := "") {
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
        if arguments != ""
            command .= " " arguments
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
            ; Keep the progress window responsive while the tool prepares output.
            if !DllCall("PeekNamedPipe", "Ptr", outputRead, "Ptr", 0, "UInt", 0,
                "Ptr", 0, "UInt*", &available := 0, "Ptr", 0) {
                if A_LastError != 109 ; ERROR_BROKEN_PIPE signals EOF.
                    throw OSError()
                break
            }
            if !available {
                Sleep(25)
                continue
            }
            if bytes = output.Size
                output.Size *= 2
            if !DllCall("ReadFile", "Ptr", outputRead, "Ptr", output.Ptr + bytes,
                "UInt", Min(available, output.Size - bytes), "UInt*", &read := 0, "Ptr", 0)
                throw OSError()
            bytes += read
        }

        deadline := DllCall("GetTickCount64", "UInt64") + 5000
        loop {
            waitResult := DllCall("WaitForSingleObject", "Ptr", process, "UInt", 0, "UInt")
            if waitResult = 0
                break
            if waitResult != 258 || DllCall("GetTickCount64", "UInt64") >= deadline ; WAIT_TIMEOUT
                throw Error("The converter did not exit.")
            Sleep(25)
        }
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

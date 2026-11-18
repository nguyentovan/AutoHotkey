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
    chord.KeyOpt("gy", "+S")
    chord.OnKeyUp := (hook, vk, sc) => hook.Stop()
    chord.Start()
    chord.Wait()
    key := chord.EndKey
    if (key != "G" && key != "Y") || !InStr(chord.EndMods, "^")
        return
    if !KeyWait(key, "T2")
        return
    KeyWait("Ctrl", "T2")
    if GetKeyState("Ctrl", "P") || !WinActive(editor)
        return
    if key = "G"
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
        target := GetSqlFormatTarget(editor)
        if !WinActive(editor)
            return
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
        sql := FormatSqlText(inputText, A_ScriptDir, target.dialect)
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
        MsgBox(errorMessage, "SQL Formatter", "Icon!")
}

FormatSqlText(inputText, directory, dialect) {
    executable := directory "\Zea.SqlFormat.exe"
    if !FileExist(executable)
        throw Error("SQL Formatter not found: " executable)

    return GetSqlConvertFunction("ConvertSqlLogText").Call(inputText, executable, "--dialect " dialect)
}

GetSqlConvertFunction(name) {
    global
    return IsSet(%name%) ? %name% : false
}

GetSqlFormatTarget(editor) {
    if WinGetProcessName(editor) = "ssms.exe"
        return {dialect: "tsql", control: 0, tab: 0, name: ""}

    tab := GetDBeaverSqlTab(editor)
    return {dialect: DBeaverSqlDialect(tab.helpText), control: tab.control, tab: tab.id, name: tab.name}
}

GetDBeaverSqlTab(editor) {
    iid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{618736E0-3C3D-11CF-810C-00AA00389B71}", "Ptr", iid)
    control := ControlGetFocus(editor)
    while control && control != editor {
        if RegExMatch(WinGetClass(control), "^SWT_Window\d+$") {
            tab := ReadDBeaverSqlTab(control, iid)
            if tab
                return tab
        }
        control := DllCall("GetParent", "Ptr", control, "Ptr")
    }
    throw Error("Could not identify a unique active SQL tab in DBeaver. Focus the SQL editor and try again.")
}

ReadDBeaverSqlTab(control, iid) {
    ; The returned COM object can use code in oleacc after DllCall returns.
    static oleacc := DllCall("LoadLibraryExW", "WStr", "oleacc.dll", "Ptr", 0,
        "UInt", 0x800, "Ptr") ; LOAD_LIBRARY_SEARCH_SYSTEM32
    if !oleacc
        return false

    ; OBJID_CLIENT exposes the SWT tab list via IAccessible.
    hr := DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", control, "UInt", 0xFFFFFFFC,
        "Ptr", iid, "Ptr*", &pointer := 0, "Int")
    if hr != 0 || !pointer
        return false

    tabs := ComValue(9, pointer, 1)
    try {
        if tabs.accRole(0) != 0x3C ; ROLE_SYSTEM_PAGETABLIST
            return false
        Loop tabs.accChildCount {
            id := A_Index
            if tabs.accRole(id) != 0x25 || !(tabs.accState(id) & 0x2) ; PAGETAB and SELECTED
                continue
            helpText := tabs.accHelp(id)
            if RegExMatch(helpText, "m)^Script:")
                return {control: control, id: id, name: tabs.accName(id), helpText: helpText}
        }
    }
    return false
}
DBeaverSqlDialect(helpText) {
    if !RegExMatch(helpText, "m)^Type:[ \t]*([^\r\n]+)", &type)
        throw Error("The active DBeaver SQL tab has no database type.")
    databaseType := Trim(type[1])
    ; DBeaver displays either the driver name or "provider / driver".
    driver := RegExReplace(databaseType, "^.* / ")
    switch driver, false {
        case "SQL Server", "MS SQL Server", "Microsoft SQL Server", "Azure SQL Server",
            "SQL Server (Deprecated)", "Azure SQL Server (Deprecated)",
            "SQL Server (Old driver, MS)", "SQL Server (Old driver, jTDS)":
            return "tsql"
        case "PostgreSQL", "PostgreSQL (Old)", "Google Cloud SQL - PostgreSQL":
            return "postgresql"
        case "MySQL", "MySQL 5 (Legacy)", "MySQL (Old)":
            return "mysql"
        case "MariaDB":
            return "mariadb"
        case "Oracle":
            return "oracle"
        case "SQLite":
            return "sqlite"
        case "DuckDB":
            return "duckdb"
        case "Athena", "Athena (Legacy)":
            return "athena"
        case "BigQuery", "BigQuery (Legacy)", "Google BigQuery":
            return "bigquery"
        case "ClickHouse", "ClickHouse (Legacy)":
            return "clickhouse"
        case "Databricks":
            return "databricks"
        case "Db2", "Db2 for LUW", "Db2 for LUW (Old 8.x)":
            return "db2"
        case "Apache Doris":
            return "doris"
        case "Exasol":
            return "exasol"
        case "Greenplum":
            return "greenplum"
        case "Apache Hive", "Apache Hive 2", "Apache Hive 4+":
            return "hive"
        case "Cloudera Impala":
            return "impala"
        case "Materialize":
            return "materialize"
        case "Redshift":
            return "redshift"
        case "Snowflake":
            return "snowflake"
        case "Apache Spark":
            return "sparksql"
        case "StarRocks":
            return "starrocks"
        case "Teradata":
            return "teradata"
        case "Trino":
            return "trino"
        case "Vertica":
            return "vertica"
        default:
            throw Error("Unsupported DBeaver database type: " databaseType)
    }
}

IsSameSqlFormatTarget(editor, target, clipboardSequence) {
    if !WinActive(editor)
        return false
    try current := GetSqlFormatTarget(editor)
    catch
        return false
    return WinActive(editor) && current.control = target.control && current.tab = target.tab
        && current.name == target.name && current.dialect = target.dialect
        && DllCall("GetClipboardSequenceNumber", "UInt") = clipboardSequence
}

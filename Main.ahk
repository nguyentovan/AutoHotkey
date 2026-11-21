#Requires AutoHotkey v2.0
#SingleInstance Force

featureSettingsPath := A_ScriptDir "\Main.ini"
explorerTabsEnabled := IniRead(featureSettingsPath, "Features", "ExplorerTab", 1) != "0"
sqlFormatEnabled := IniRead(featureSettingsPath, "Features", "SqlFormat", 1) != "0"
sqlLogConvertEnabled := IniRead(featureSettingsPath, "Features", "SqlLogConvert", 1) != "0"

Persistent()
A_TrayMenu.Insert("1&", "Chọn chức năng…", ShowFeatureSettings)

#Include "*i ExplorerTab.ahk"
#Include "*i SqlFormat.ahk"
#Include "*i SqlLogConvert.ahk"

ShowFeatureSettings(*) {
    global explorerTabsEnabled, sqlFormatEnabled, sqlLogConvertEnabled
    static window := 0
    if !window {
        window := Gui(, "Chọn chức năng")
        window.SetFont("s10", "Segoe UI")
        explorer := window.AddCheckbox("vExplorerTab", "Tab File Explorer (Win+E)")
        format := window.AddCheckbox("vSqlFormat", "Định dạng SQL (Ctrl+K, Ctrl+Y)")
        convert := window.AddCheckbox("vSqlLogConvert", "Chuyển log SQL (Ctrl+K, Ctrl+G)")
        explorer.Enabled := FileExist(A_ScriptDir "\ExplorerTab.ahk") != ""
        format.Enabled := FileExist(A_ScriptDir "\SqlFormat.ahk") && FileExist(A_ScriptDir "\SqlLogConvert.ahk")
        convert.Enabled := FileExist(A_ScriptDir "\SqlLogConvert.ahk") != ""
        window.AddButton("Default", "Lưu và nạp lại").OnEvent("Click", SaveFeatureSettings)
        window.AddButton("x+8 yp", "Hủy").OnEvent("Click", (button, *) => button.Gui.Hide())
        window.OnEvent("Escape", (gui) => gui.Hide())
    }
    if !DllCall("IsWindowVisible", "Ptr", window.Hwnd, "Int") {
        window["ExplorerTab"].Value := explorerTabsEnabled
        window["SqlFormat"].Value := sqlFormatEnabled
        window["SqlLogConvert"].Value := sqlLogConvertEnabled
    }
    window.Show()
}

SaveFeatureSettings(button, *) {
    global featureSettingsPath
    window := button.Gui
    choices := window.Submit(false)
    try {
        IniWrite("ExplorerTab=" choices.ExplorerTab "`nSqlFormat=" choices.SqlFormat
            . "`nSqlLogConvert=" choices.SqlLogConvert, featureSettingsPath, "Features")
    } catch Error as err {
        MsgBox("Không thể lưu cấu hình.`n" err.Message, window.Title, "Icon! Owner" window.Hwnd)
        return
    }
    Reload()
}

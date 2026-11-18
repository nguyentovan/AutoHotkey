#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off

OnError((err, mode) => Fail(err.Message))

window := Gui()
tab := window.AddTab3(, ["One", "Two"])
iid := Buffer(16)
DllCall("ole32\CLSIDFromString", "WStr", "{618736E0-3C3D-11CF-810C-00AA00389B71}", "Ptr", iid)

; The standard Windows tab exposes IAccessible but has no DBeaver SQL metadata.
if ReadDBeaverSqlTab(tab.Hwnd, iid)
    Fail("A standard Windows tab was identified as a DBeaver SQL tab.")
if !DllCall("GetModuleHandleW", "WStr", "oleacc.dll", "Ptr")
    Fail("oleacc.dll must stay loaded while its COM objects are in use.")

window.Destroy()
FileAppend("PASS (" A_PtrSize * 8 "-bit)" Chr(10), "*")
ExitApp()

Fail(message) {
    FileAppend("FAIL: " message Chr(10), "**")
    ExitApp(1)
}

#Include "..\SqlFormat.ahk"

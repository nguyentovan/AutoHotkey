#Requires AutoHotkey v2.0

WatchExplorerWindows()

#e:: {
    if explorer := WinExist("ahk_class CabinetWClass ahk_exe explorer.exe") {
        WinActivate(explorer)
        if WinWaitActive(explorer, , 1)
            Send("^t")
    } else {
        Run("explorer.exe")
    }
}

WatchExplorerWindows() {
    explorer := "ahk_class CabinetWClass ahk_exe explorer.exe"
    known := Map()
    for hwnd in WinGetList(explorer)
        known[hwnd] := 0

    SetTimer(CheckWindows, 250)

    CheckWindows() {
        windows := WinGetList(explorer)
        current := Map()
        target := 0
        for hwnd in windows {
            if known.Has(hwnd) && !known[hwnd] {
                target := hwnd
                break
            }
        }

        ; WinGetList lists the newest foreground windows first. If none were
        ; known, keep the bottommost window so there is still a destination.
        if !target && windows.Length
            target := windows[-1]

        for hwnd in windows {
            deadline := known.Get(hwnd, A_TickCount + 3000)
            if hwnd = target || A_TickCount >= deadline
                deadline := 0
            current[hwnd] := deadline
        }
        known := current

        if !target
            return

        for hwnd, deadline in current {
            if !deadline
                continue
            try {
                sourceTabs := GetExplorerTabs(hwnd)
                if sourceTabs.Count != 1 || GetExplorerTabHandles(hwnd).Count != 1
                    continue
                for sourceTab, source in sourceTabs {
                    path := ReadyFolderPath(source)
                    if path != "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}" && !DirExist(path)
                        continue
                    ; Preserve windows opened to reveal a selected file.
                    if source.Document.SelectedItems().Count
                        continue
                    before := GetExplorerTabHandles(target)
                    if !before.Count
                        continue
                    current[hwnd] := 0
                    MoveExplorerFolder(hwnd, sourceTab, target, before, path)
                }
            } catch {
                ; Explorer can still be loading or the user may have closed the window.
            }
        }
    }
}

MoveExplorerFolder(sourceWindow, sourceTab, targetWindow, before, path) {
    matchingTab := 0
    for tab, browser in GetExplorerTabs(targetWindow) {
        try {
            if before.Has(tab) && ReadyFolderPath(browser) = path {
                matchingTab := tab
                break
            }
        }
    }
    if matchingTab {
        if SelectExplorerTab(targetWindow, matchingTab, before.Count)
            CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, path)
        return
    }


    control := ControlGetHwnd("ShellTabWindowClass1", targetWindow)
    ; ponytail: Explorer uses an undocumented command for new tabs. Keep the source if it fails.
    SendMessage(0x0111, 0xA21B, 0, , control, , , , 500)

    deadline := A_TickCount + 2000
    destination := 0
    while A_TickCount < deadline {
        Sleep(50)
        handles := GetExplorerTabHandles(targetWindow)
        if handles.Count != before.Count + 1
            continue
        for tab in before {
            if !handles.Has(tab)
                return
        }
        for tab in handles {
            if !before.Has(tab) {
                destination := GetExplorerTabs(targetWindow).Get(tab, 0)
                break
            }
        }
        if destination
            break
    }
    if !destination
        return

    if SubStr(path, 1, 2) = "::"
        NavigateToShellFolder(destination, path)
    else
        destination.Navigate2(path)
    deadline := A_TickCount + 2000
    while A_TickCount < deadline {
        Sleep(50)
        if ReadyFolderPath(destination) = path {
            CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, path)
            return
        }
    }
}

NavigateToShellFolder(browser, path) {
    pidl := 0
    result := DllCall("Shell32\SHParseDisplayName", "WStr", path, "Ptr", 0, "Ptr*", &pidl, "UInt", 0, "Ptr", 0, "Int")
    if result < 0 || !pidl
        throw Error("Could not resolve the Explorer location")
    try {
        size := DllCall("Shell32\ILGetSize", "Ptr", pidl, "UInt")
        bytes := ComObjArray(0x11, size)
        result := DllCall("OleAut32\SafeArrayAccessData", "Ptr", ComObjValue(bytes), "Ptr*", &data := 0, "Int")
        if result < 0
            throw Error("Could not read the Explorer location")
        try DllCall("Kernel32\RtlMoveMemory", "Ptr", data, "Ptr", pidl, "UPtr", size)
        finally DllCall("OleAut32\SafeArrayUnaccessData", "Ptr", ComObjValue(bytes))
        browser.Navigate2(bytes)
    } finally DllCall("Ole32\CoTaskMemFree", "Ptr", pidl)
}

SelectExplorerTab(window, tab, count) {
    deadline := A_TickCount + 1000
    if ControlGetHwnd("ShellTabWindowClass1", window) = tab
        return true

    ; Explorer's tab handles are ordered by activation, so verify each index.
    Loop count {
        ; WM_COMMAND for the Explorer tab index, starting at 1.
        SendMessage(0x0111, 0xA221, A_Index, , window, , , , 200)
        waitUntil := Min(deadline, A_TickCount + 100)
        while A_TickCount < waitUntil {
            if ControlGetHwnd("ShellTabWindowClass1", window) = tab
                return true
            Sleep(15)
        }
        if A_TickCount >= deadline
            break
    }
    return false
}

CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, path) {
    tabs := GetExplorerTabs(sourceWindow)
    if tabs.Count = 1 && tabs.Has(sourceTab) && GetExplorerTabHandles(sourceWindow).Count = 1
        && ReadyFolderPath(tabs[sourceTab]) = path
        && !tabs[sourceTab].Document.SelectedItems().Count {
        WinClose(sourceWindow)
        WinActivate(targetWindow)
    }
}

GetExplorerTabs(window) {
    static shell := ComObject("Shell.Application")
    static shellBrowserId := "{000214E2-0000-0000-C000-000000000046}"
    tabs := Map()
    for browser in shell.Windows {
        try {
            if browser.HWND != window
                continue
            shellBrowser := ComObjQuery(browser, shellBrowserId, shellBrowserId)
            ComCall(3, shellBrowser, "Ptr*", &tab := 0)
            if tab
                tabs[tab] := browser
        }
    }
    return tabs
}

GetExplorerTabHandles(window) {
    handles := Map()
    for control in WinGetControlsHwnd(window) {
        if WinGetClass(control) = "ShellTabWindowClass"
            handles[control] := true
    }
    return handles
}

ReadyFolderPath(browser) {
    if browser.Busy || browser.ReadyState != 4
        return ""
    return browser.Document.Folder.Self.Path
}

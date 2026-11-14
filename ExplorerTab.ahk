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

; Let Windows receive both clicks. Only look up the icon after a double-click.
~LButton:: {
    static last := 0
    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y, &window, &control, 2)
    try {
        if !control || !RegExMatch(WinGetClass(window), "^(Progman|WorkerW)$")
            || WinGetClass(control) != "SysListView32" {
            last := 0
            return
        }
        now := A_TickCount
        if last && last.Control = control && now - last.Tick <= DllCall("GetDoubleClickTime", "UInt")
            && 2 * Abs(x - last.X) < SysGet(36) && 2 * Abs(y - last.Y) < SysGet(37) {
            last := 0
            path := DesktopFolderAt(control, x, y)
            if path
                SetTimer(FocusOpenedDesktopFolder.Bind(path), -150)
            return
        }
        last := {Control: control, X: x, Y: y, Tick: now}
    }
}

FocusOpenedDesktopFolder(path) {
    window := WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    if !window
        return false
    for tab, browser in GetExplorerTabs(window) {
        try {
            if ReadyFolderPath(browser) = path
                return SelectExplorerTab(window, tab, browser)
        }
    }
    return false
}

DesktopFolderAt(control, x, y) {
    static shell := ComObject("Shell.Application")
    selected := shell.Windows.Item(ComValue(0x13, 8)).Document.SelectedItems()
    if selected.Count != 1
        return ""
    item := selected.Item(0)
    path := item.IsLink ? item.GetLink.Path : item.Path
    if SubStr(path, 1, 2) != "::" && !DirExist(path)
        return ""

    items := GetExplorerElements(control, 50007) ; UIA_ListItemControlTypeId
    ComCall(3, items, "Int*", &count := 0)
    Loop count {
        ComCall(4, items, "Int", A_Index - 1, "Ptr*", &element := 0)
        element := ComValue(13, element, 1)
        if ExplorerElementName(element) != item.Name
            continue
        rect := Buffer(16)
        ComCall(43, element, "Ptr", rect) ; IUIAutomationElement::get_CurrentBoundingRectangle
        if x >= NumGet(rect, 0, "Int") && x < NumGet(rect, 8, "Int")
            && y >= NumGet(rect, 4, "Int") && y < NumGet(rect, 12, "Int")
            return path
    }
    return ""
}

WatchExplorerWindows() {
    explorer := "ahk_class CabinetWClass ahk_exe explorer.exe"
    known := Map()
    merge := 0
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
            if merge && merge.Source = hwnd
                deadline := merge.Deadline
            if hwnd = target || A_TickCount >= deadline
                deadline := 0
            current[hwnd] := deadline
        }
        known := current

        if merge && !current.Get(merge.Source, 0)
            merge := 0

        if !target
            return

        for hwnd, deadline in current {
            if !deadline || (merge && merge.Source != hwnd)
                continue
            try {
                sourceTabs := GetExplorerTabs(hwnd)
                if sourceTabs.Count != 1 || GetExplorerTabHandles(hwnd).Count != 1
                    continue
                for sourceTab, source in sourceTabs {
                    path := ReadyFolderPath(source)
                    if SubStr(path, 1, 2) != "::" && !DirExist(path)
                        continue
                    ; Preserve windows opened to reveal a selected file.
                    if source.Document.SelectedItems().Count
                        continue
                    if MoveExplorerFolder(hwnd, sourceTab, target, path, &merge) {
                        current[hwnd] := 0
                        merge := 0
                    }
                }
            } catch {
                ; Explorer can still be loading or the user may have closed the window.
            }
        }
    }
}

MoveExplorerFolder(sourceWindow, sourceTab, targetWindow, path, &merge) {
    if !merge {
        input := LastExplorerInput()
        before := GetExplorerTabHandles(targetWindow)
        tabs := GetExplorerTabs(targetWindow)
        complete := before.Count > 0
        for tab in before {
            location := ""
            if tabs.Has(tab)
                try location := ReadyFolderPath(tabs[tab])
            if location = path {
                if SelectExplorerTab(targetWindow, tab, tabs[tab])
                    return CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, path)
                return false
            }
            if !location
                complete := false
        }
        if !complete || input = -1 || ExplorerInputChanged(targetWindow, input)
            return false

        control := ControlGetHwnd("ShellTabWindowClass1", targetWindow)
        ; A message timeout can still create a tab, so keep the request even if it throws.
        merge := {Deadline: A_TickCount + 4000, Source: sourceWindow, SourceTab: sourceTab, Target: targetWindow,
            Path: path, Before: before, Input: input, Tab: 0, Navigating: false, Cancelled: false}
        SendMessage(0x0111, 0xA21B, 0, , control, , , , 500)
        return false
    }

    if merge.Cancelled || merge.SourceTab != sourceTab || merge.Path != path
        return false
    handles := GetExplorerTabHandles(merge.Target)
    if ExplorerInputChanged(merge.Target, merge.Input) || handles.Count > merge.Before.Count + 1 {
        merge.Cancelled := true
        return false
    }
    for tab in merge.Before {
        if !handles.Has(tab) {
            merge.Cancelled := true
            return false
        }
    }
    if handles.Count != merge.Before.Count + 1
        return false
    for tab in handles {
        if merge.Before.Has(tab)
            continue
        if merge.Tab && merge.Tab != tab {
            merge.Cancelled := true
            return false
        }
        merge.Tab := tab
        break
    }

    destination := GetExplorerTabs(merge.Target).Get(merge.Tab, 0)
    if !destination
        return false
    location := ReadyFolderPath(destination)
    if !location
        return false
    if location = path
        return CloseMergedExplorerWindow(sourceWindow, sourceTab, merge.Target, path)
    if !merge.Navigating {
        if ExplorerInputChanged(merge.Target, merge.Input) || GetExplorerTabHandles(merge.Target).Count != handles.Count || ControlGetHwnd("ShellTabWindowClass1", merge.Target) != merge.Tab {
            merge.Cancelled := true
            return false
        }
        if SubStr(path, 1, 2) = "::"
            NavigateToShellFolder(destination, path)
        else
            destination.Navigate2(path)
        merge.Navigating := true
    }
    return false
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

SelectExplorerTab(window, tab, browser) {
    if ControlGetHwnd("ShellTabWindowClass1", window) = tab
        return true

    name := browser.LocationName
    if !name
        return false
    if WinGetMinMax(window) = -1
        WinRestore(window)
    items := GetExplorerTabItems(window)
    ComCall(3, items, "Int*", &count := 0)
    match := 0
    Loop count {
        ComCall(4, items, "Int", A_Index - 1, "Ptr*", &item := 0)
        item := ComValue(13, item, 1)
        if ExplorerElementName(item) != name
            continue
        ; Identical tab labels can represent different folders.
        if match
            return false
        match := item
    }
    if !match
        return false

    ; UIA_SelectionItemPatternId, then IUIAutomationSelectionItemPattern::Select.
    ComCall(16, match, "Int", 10010, "Ptr*", &pattern := 0)
    if !pattern
        return false
    ComCall(3, ComValue(13, pattern, 1))
    Loop 10 {
        if ControlGetHwnd("ShellTabWindowClass1", window) = tab
            return true
        Sleep(20)
    }
    return false
}

ExplorerInputChanged(window, input) {
    return WinActive(window) && LastExplorerInput() != input
}

LastExplorerInput() {
    info := Buffer(8, 0)
    NumPut("UInt", info.Size, info)
    if !DllCall("GetLastInputInfo", "Ptr", info)
        return -1
    return NumGet(info, 4, "UInt")
}

ExplorerAutomation() {
    static automation := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}",
        "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
    return automation
}

GetExplorerTabItems(window) {
    return GetExplorerElements(window, 50019) ; UIA_TabItemControlTypeId
}

GetExplorerElements(window, controlType) {
    automation := ExplorerAutomation()
    ; UIA_ControlTypePropertyId = 30003.
    value := Buffer(24, 0)
    NumPut("UShort", 3, value)
    NumPut("Int", controlType, value, 8)
    if A_PtrSize = 8
        ComCall(23, automation, "Int", 30003, "Ptr", value, "Ptr*", &condition := 0)
    else
        ComCall(23, automation, "Int", 30003, "Int64", NumGet(value, "Int64"), "Int64", NumGet(value, 8, "Int64"), "Ptr*", &condition := 0)
    condition := ComValue(13, condition, 1)
    ComCall(6, automation, "Ptr", window, "Ptr*", &root := 0)
    root := ComValue(13, root, 1)
    ComCall(6, root, "Int", 4, "Ptr", condition, "Ptr*", &items := 0)
    return ComValue(13, items, 1)
}
ExplorerElementName(item) {
    ComCall(23, item, "Ptr*", &name := 0)
    try return name ? StrGet(name, "UTF-16") : ""
    finally DllCall("OleAut32\SysFreeString", "Ptr", name)
}

CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, path) {
    tabs := GetExplorerTabs(sourceWindow)
    if tabs.Count = 1 && tabs.Has(sourceTab) && GetExplorerTabHandles(sourceWindow).Count = 1
        && ReadyFolderPath(tabs[sourceTab]) = path
        && !tabs[sourceTab].Document.SelectedItems().Count {
        WinClose(sourceWindow)
        if WinWaitClose(sourceWindow, , 0.2) {
            try WinActivate(targetWindow)
            return true
        }
    }
    return false
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

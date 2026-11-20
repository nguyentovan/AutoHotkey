#Requires AutoHotkey v2.0

if A_LineFile = A_ScriptFullPath
    ExitApp()

desktopFolderOpen := 0
WatchExplorerWindows()

#e:: {
    for explorer in WinGetList("ahk_class CabinetWClass ahk_exe explorer.exe") {
        if !HasReadyExplorerTab(explorer)
            continue
        WinActivate(explorer)
        if WinWaitActive(explorer, , 1)
            Send("^t")
        return
    }
    Run("explorer.exe")
}

; Let Windows receive both clicks. Only look up the icon after a double-click.
~LButton:: {
    global desktopFolderOpen
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
            if path {
                desktopFolderOpen := {Path: path, Expires: A_TickCount + 5000}
                SetTimer(FocusOpenedDesktopFolder.Bind(path), -150)
            }
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
    unusedTabs := []
    for hwnd in WinGetList(explorer)
        known[hwnd] := 0

    SetTimer(CheckWindows, 250)

    CancelSourceMerge() {
        known[merge.Source] := 0
        merge.Deadline := Min(merge.Deadline, A_TickCount + 750)
        unusedTabs.Push(merge)
        merge := 0
    }

    CheckWindows() {
        windows := WinGetList(explorer)
        current := Map()
        target := 0
        if windows.Length = 1 {
            target := windows[1]
        } else {
            for hwnd in windows {
                if !known.Has(hwnd) || known[hwnd] {
                    target := FindExplorerTarget(windows, known)
                    break
                }
            }
        }

        for hwnd in windows {
            deadline := known.Get(hwnd, A_TickCount + 3000)
            if merge && merge.Source = hwnd
                deadline := merge.Deadline
            if hwnd = target || A_TickCount >= deadline
                deadline := 0
            current[hwnd] := deadline
        }
        known := current

        ; A cancelled source must not keep other windows waiting for tab cleanup.
        Loop unusedTabs.Length {
            pending := unusedTabs.RemoveAt(1)
            if A_TickCount >= pending.Deadline || !DllCall("IsWindowVisible", "Ptr", pending.Target)
                continue
            cleaned := false
            try cleaned := CloseUnusedMergeTab(pending, true)
            if !cleaned
                unusedTabs.Push(pending)
        }

        if merge && !DllCall("IsWindowVisible", "Ptr", merge.Target) {
            if current.Has(merge.Source)
                current[merge.Source] := 0
            merge := 0
        }

        if merge && !current.Get(merge.Source, 0) {
            cleaned := false
            try cleaned := CloseUnusedMergeTab(merge)
            if cleaned || A_TickCount >= merge.Deadline
                merge := 0
        }

        if !target
            return

        ; Keep the next merge's tab snapshot stable until this target is done with cleanup.
        for pending in unusedTabs {
            if pending.Target = target && !merge
                return
        }

        for hwnd, deadline in current {
            if !deadline || (merge && merge.Source != hwnd)
                continue
            try {
                sourceTabs := GetExplorerTabs(hwnd)
                handles := GetExplorerTabHandles(hwnd)
                if merge && handles.Count > 1 {
                    CancelSourceMerge()
                    return
                }
                if sourceTabs.Count != 1 || handles.Count != 1
                    continue
                for sourceTab, source in sourceTabs {
                    path := ReadyFolderPath(source)
                    if merge && (merge.SourceTab != sourceTab || (path != "" && merge.Path != path)) {
                        CancelSourceMerge()
                        return
                    }
                    if !path || (SubStr(path, 1, 2) != "::" && !DirExist(path))
                        continue
                    ; Preserve windows opened to reveal a selected file.
                    if source.Document.SelectedItems().Count {
                        if merge {
                            CancelSourceMerge()
                            return
                        }
                        continue
                    }
                    result := MoveExplorerFolder(hwnd, sourceTab, target, path, &merge)
                    if merge && result = "source-changed" {
                        CancelSourceMerge()
                        return
                    }
                    if result {
                        current[hwnd] := 0
                        merge := 0
                    }
                }
            } catch {
                ; Explorer can still be loading or the user may have closed the window.
            } finally {
                if merge && (merge.Cancelled || !DllCall("IsWindowVisible", "Ptr", merge.Target)) {
                    current[merge.Source] := 0
                    merge := 0
                }
            }
        }
    }
}

FindExplorerTarget(windows, known) {
    fallback := 0
    for hwnd in windows {
        if !HasReadyExplorerTab(hwnd)
            continue
        if known.Has(hwnd) && !known[hwnd]
            return hwnd
        ; If none were known, keep the bottommost eligible window.
        fallback := hwnd
    }
    return fallback
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
                    return CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, tab, path)
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
            Path: path, Before: before, Input: input, Tab: 0, InitialPath: "", Navigating: false,
            Cancelled: false, SourceCloseRequested: false, CreateConfirmed: false,
            TargetWasActive: ExplorerForegroundRoot() = targetWindow}
        SendMessage(0x0111, 0xA21B, 0, , control, , , , 500)
        merge.CreateConfirmed := true
        Loop 8 {
            if ExplorerInputChanged(targetWindow, input) || TrackMergeTab(merge, GetExplorerTabHandles(targetWindow))
                break
            Sleep(15)
        }
        return false
    }

    if merge.Cancelled || !HasReadyExplorerTab(merge.Target)
        return false
    handles := GetExplorerTabHandles(merge.Target)
    if ExplorerInputChanged(merge.Target, merge.Input) {
        merge.Cancelled := true
        return false
    }
    if !TrackMergeTab(merge, handles)
        return false
    merge.TargetWasActive := ExplorerForegroundRoot() = merge.Target

    destination := GetExplorerTabs(merge.Target).Get(merge.Tab, 0)
    if !destination
        return false
    location := ReadyFolderPath(destination)
    if !location
        return false
    if !merge.InitialPath
        merge.InitialPath := location
    if location = path
        return CloseMergedExplorerWindow(sourceWindow, sourceTab, merge.Target, merge.Tab, path, merge)
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

TrackMergeTab(merge, handles) {
    for tab in merge.Before {
        if !handles.Has(tab) {
            merge.Cancelled := true
            return false
        }
    }
    if handles.Count > merge.Before.Count + 1 || (merge.Tab && !handles.Has(merge.Tab)) {
        merge.Cancelled := true
        return false
    }
    if handles.Count != merge.Before.Count + 1
        return false
    for tab in handles {
        if !merge.Before.Has(tab) {
            merge.Tab := tab
            return true
        }
    }
    return false
}

CloseUnusedMergeTab(merge, sourceChanged := false) {
    if merge.Cancelled || merge.SourceCloseRequested || !merge.CreateConfirmed
        || !merge.Tab || !WinExist(merge.Target)
        return true
    if sourceChanged && merge.HasOwnProp("CleanupSent")
        return !GetExplorerTabHandles(merge.Target).Has(merge.Tab)
    ; Closing the foreground source can make the target active without
    ; any interaction with its tabs. Preserve it if it was already active.
    input := LastExplorerInput()
    if input = -1
        return true
    if input != merge.Input && (merge.TargetWasActive
        || (sourceChanged ? (!merge.InitialPath || ExplorerForegroundRoot() != merge.Source)
            : DllCall("IsWindowVisible", "Ptr", merge.Source)))
        return true
    handles := GetExplorerTabHandles(merge.Target)
    if !TrackMergeTab(merge, handles)
        return true
    if ControlGetHwnd("ShellTabWindowClass1", merge.Target) != merge.Tab
        return true
    browser := GetExplorerTabs(merge.Target).Get(merge.Tab, 0)
    if !browser || !(path := ReadyFolderPath(browser))
        return false
    if browser.Document.SelectedItems().Count || (merge.InitialPath && path != merge.InitialPath && path != merge.Path)
        return true
    if LastExplorerInput() != input || ControlGetHwnd("ShellTabWindowClass1", merge.Target) != merge.Tab
        return false
    ControlSend("{Ctrl down}w{Ctrl up}", merge.Tab)
    if sourceChanged {
        merge.CleanupSent := true
        return !GetExplorerTabHandles(merge.Target).Has(merge.Tab)
    }
    return true
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
        return SelectExplorerTabByIndex(window, tab)
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
            return SelectExplorerTabByIndex(window, tab)
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

SelectExplorerTabByIndex(window, tab) {
    original := ControlGetHwnd("ShellTabWindowClass1", window)
    handles := GetExplorerTabHandles(window)
    if !handles.Has(tab)
        return false
    originalIndex := 0
    Loop handles.Count {
        ; Explorer's tab index command uses visual order. Verify the selected HWND.
        SendMessage(0x0111, 0xA221, A_Index, , window, , , , 200)
        Loop 5 {
            active := ControlGetHwnd("ShellTabWindowClass1", window)
            if active = tab
                return true
            Sleep(20)
        }
        if active = original && !originalIndex
            originalIndex := A_Index
    }
    if originalIndex
        SendMessage(0x0111, 0xA221, originalIndex, , window, , , , 200)
    return false
}

ExplorerInputChanged(window, input) {
    return ExplorerForegroundRoot() = window && LastExplorerInput() != input
}

ExplorerForegroundRoot(foreground := DllCall("GetForegroundWindow", "Ptr")) {
    ; Explorer can report its tab HWND as foreground during a merge.
    return DllCall("GetAncestor", "Ptr", foreground, "UInt", 2, "Ptr") ; GA_ROOT
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

CloseMergedExplorerWindow(sourceWindow, sourceTab, targetWindow, targetTab, path, merge := 0) {
    global desktopFolderOpen
    if GetClosableExplorerSource(sourceWindow, sourceTab, path) {
        input := LastExplorerInput()
        foreground := DllCall("GetForegroundWindow", "Ptr")
        foregroundRoot := ExplorerForegroundRoot(foreground)
        open := desktopFolderOpen
        fromDesktop := open && open.Path = path && A_TickCount <= open.Expires
        desktopIsActive := foregroundRoot
            && RegExMatch(WinGetClass(foregroundRoot), "^(Progman|WorkerW)$")
            && WinGetProcessName(foregroundRoot) = "explorer.exe"
        SplitPath(path, , &parent)
        showTarget := foregroundRoot = sourceWindow
            || (fromDesktop && foregroundRoot = targetWindow)
            || (desktopIsActive && (fromDesktop || parent = A_Desktop || parent = A_DesktopCommon))
        ; Transfer foreground while the source still exists and the destination is ready.
        if showTarget && input != -1 && LastExplorerInput() = input
            && DllCall("GetForegroundWindow", "Ptr") = foreground
            try WinActivate(targetWindow)
        source := GetClosableExplorerSource(sourceWindow, sourceTab, path)
        if !source
            return "source-changed"
        try {
            destination := GetExplorerTabs(targetWindow).Get(targetTab, 0)
            if !destination || ReadyFolderPath(destination) != path
                return "cancelled"
            if ReadyFolderPath(source) != path || source.Document.SelectedItems().Count
                || GetExplorerTabHandles(sourceWindow).Count != 1
                || ExplorerForegroundRoot(sourceTab) != sourceWindow
                return "source-changed"
            if ReadyFolderPath(destination) != path
                return "cancelled"
        } catch {
            ; Explorer can disconnect a COM object while a tab is closing.
            return "cancelled"
        }
        if !DllCall("IsWindowVisible", "Ptr", targetWindow)
            || ExplorerForegroundRoot(targetTab) != targetWindow
            return "cancelled"
        WinClose(sourceWindow)
        if merge
            merge.SourceCloseRequested := true
        if WinWaitClose(sourceWindow, , 0.2) {
            if fromDesktop && desktopFolderOpen = open
                desktopFolderOpen := 0
            return true
        }
    }
    return false
}

GetClosableExplorerSource(window, tab, path) {
    tabs := GetExplorerTabs(window)
    if tabs.Count != 1 || !tabs.Has(tab) || GetExplorerTabHandles(window).Count != 1
        return 0
    browser := tabs[tab]
    return ReadyFolderPath(browser) = path && !browser.Document.SelectedItems().Count ? browser : 0
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

HasReadyExplorerTab(window) {
    try {
        tab := ControlGetHwnd("ShellTabWindowClass1", window)
        browser := GetExplorerTabs(window).Get(tab, 0)
        return browser && ReadyFolderPath(browser) != ""
    }
    return false
}

ReadyFolderPath(browser) {
    if browser.Busy || browser.ReadyState != 4
        return ""
    path := browser.Document.Folder.Self.Path
    ; Control Panel views share Explorer's window class but navigation can
    ; open another standalone window instead of staying in the target tab.
    if RegExMatch(path, "i)(^|\\)::\{(21EC2020-3AEA-1069-A2DD-08002B30309D|26EE0668-A00A-44D7-9371-BEB064C98683)\}(\\|$)")
        return ""
    return path
}

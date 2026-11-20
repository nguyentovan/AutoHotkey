#Requires AutoHotkey v2.0
#Warn All, StdOut

OnError((err, mode) => Fail(err.Message))

shell := ComObject("Shell.Application")
CheckFolder(shell.NameSpace(3), false) ; All Control Panel Items
CheckFolder(shell.NameSpace(4), false) ; Printers, under the classic Control Panel root
CheckFolder(shell.NameSpace(17), true) ; This PC
CheckFolder(shell.NameSpace(A_WinDir), true)
CheckFolder(shell.NameSpace("::{26EE0668-A00A-44D7-9371-BEB064C98683}"), false)

FileAppend("PASS" Chr(10), "*")
ExitApp()

CheckFolder(folder, expected) {
    path := folder.Self.Path
    browser := {Busy: false, ReadyState: 4, Document: {Folder: folder}}
    if ReadyFolderPath(browser) != (expected ? path : "")
        Fail("Unexpected Explorer eligibility for " path)
}

Fail(message) {
    FileAppend("FAIL: " message Chr(10), "**")
    ExitApp(1)
}

#Include "..\ExplorerTab.ahk"

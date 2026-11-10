#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  Clip Stack - keeps every Ctrl+C (text), lets you cycle/pick
;    Ctrl+Shift+C        cycle saved copies onto the clipboard (then Ctrl+V)
;    Ctrl+Alt+Shift+V    open the history list (also: left-click tray icon)
;  In the list: type to search, Enter/double-click = paste,
;               Del = remove item, Esc = close
; ============================================================

global MAX_ITEMS  := 100
global DATA_FILE  := A_ScriptDir "\clip-stack-history.dat"
global SEP        := Chr(30)
global CYCLE_MS   := 2500          ; pause longer than this = cycle restarts at newest
global History    := []
global Ignore     := false
global CycleIdx   := 0
global LastCycle  := 0
global LastWin    := 0
global Gui1 := "", LV := "", SearchBox := "", HintTxt := ""

LoadHistory()
SetupTray()
OnClipboardChange(ClipChanged)

; Ctrl+Shift+C is left alone in terminals (it is "copy" there)
#HotIf !WinActive("ahk_exe WindowsTerminal.exe") && !WinActive("ahk_exe mintty.exe")
^+c:: CycleNext()
#HotIf

^!+v:: ShowHistory()

#HotIf GuiActive() && LVFocused()
Del:: RemoveSelected()
#HotIf GuiActive() && SearchFocused()
Down:: (LV.Focus(), LV.GetCount() && LV.Modify(1, "Select Focus"))
#HotIf

; ---------------- clipboard capture ----------------
ClipChanged(type) {
    global Ignore
    if Ignore || type != 1 || IsExcluded()
        return
    txt := A_Clipboard
    if (txt = "")
        return
    AddItem(txt)
}

; password managers mark their copies "don't record"
IsExcluded() {
    for name in ["ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore"] {
        fmt := DllCall("RegisterClipboardFormat", "Str", name, "UInt")
        if DllCall("IsClipboardFormatAvailable", "UInt", fmt)
            return true
    }
    return false
}

AddItem(txt) {
    global History
    for i, v in History
        if (v == txt) {
            History.RemoveAt(i)
            break
        }
    History.InsertAt(1, txt)
    while History.Length > MAX_ITEMS
        History.Pop()
    SaveHistory()
    RefreshList()
}

SetClip(txt) {
    global Ignore
    Ignore := true
    A_Clipboard := txt
    ClipWait(1)
    SetTimer(ClearIgnore, -300)
}
ClearIgnore() {
    global Ignore := false
}

; ---------------- Ctrl+Shift+C cycle ----------------
CycleNext() {
    global CycleIdx, LastCycle, History
    n := History.Length
    if !n {
        Tip("Clip Stack is empty - copy something first")
        return
    }
    if (A_TickCount - LastCycle > CYCLE_MS)
        CycleIdx := 1                       ; first press jumps to the previous copy
    LastCycle := A_TickCount
    CycleIdx := Mod(CycleIdx, n) + 1
    SetClip(History[CycleIdx])

    s := "Clip " CycleIdx " / " n "     Ctrl+V to paste`n"
    Loop Min(6, n) {
        i := Mod(CycleIdx - 1 + A_Index - 1, n) + 1
        s .= (A_Index = 1 ? ">> " : "     ") i ".  " Preview(History[i], 60) "`n"
    }
    Tip(RTrim(s, "`n"), CYCLE_MS)
}

; ---------------- history window ----------------
ShowHistory(*) {
    global Gui1, LastWin, SearchBox
    hwnd := WinExist("A")
    if !(IsObject(Gui1) && hwnd = Gui1.Hwnd)
        LastWin := hwnd
    if !IsObject(Gui1)
        BuildGui()
    SearchBox.Value := ""
    RefreshList()
    Gui1.Show("w640 h440")
    SearchBox.Focus()
}

BuildGui() {
    global Gui1, LV, SearchBox, HintTxt
    Gui1 := Gui("+AlwaysOnTop +Resize +MinSize400x250", "Clip Stack")
    Gui1.SetFont("s10", "Segoe UI")
    Gui1.Add("Text", "xm ym+3", "Search:")
    SearchBox := Gui1.Add("Edit", "x+6 ym w330")
    SearchBox.OnEvent("Change", (*) => RefreshList())
    Gui1.Add("Button", "x+10 ym-1", "Clear all").OnEvent("Click", ClearAll)
    LV := Gui1.Add("ListView", "xm w620 h360 -Multi Grid", ["#", "Text"])
    LV.OnEvent("DoubleClick", (*) => PickSelected())
    HintTxt := Gui1.Add("Text", "xm w620 cGray", "Enter / double-click = paste     Del = remove     Esc = close     Ctrl+Shift+C = cycle")
    Gui1.Add("Button", "Default Hidden w0 h0", "OK").OnEvent("Click", (*) => PickSelected())
    Gui1.OnEvent("Escape", (*) => Gui1.Hide())
    Gui1.OnEvent("Close", (*) => Gui1.Hide())
    Gui1.OnEvent("Size", GuiSize)
}

GuiSize(g, minMax, w, h) {
    if (minMax = -1)
        return
    LV.Move(, , w - 20, h - 75)
    LV.ModifyCol(2, w - 80)
    HintTxt.Move(, h - 28, w - 20)
}

RefreshList() {
    global Gui1, LV, SearchBox, History
    if !IsObject(Gui1)
        return
    q := SearchBox.Value
    LV.Opt("-Redraw")
    LV.Delete()
    for i, v in History
        if (q = "" || InStr(v, q))
            LV.Add(, i, Preview(v, 300))
    LV.ModifyCol(1, "40 Integer")
    if LV.GetCount()
        LV.Modify(1, "Select Focus")
    LV.Opt("+Redraw")
}

SelectedIndex() {
    row := LV.GetNext()
    if !row && LV.GetCount()
        row := 1
    return row ? Integer(LV.GetText(row, 1)) : 0
}

PickSelected() {
    global LastWin
    idx := SelectedIndex()
    if !idx
        return
    txt := History[idx]
    Gui1.Hide()
    SetClip(txt)
    AddItem(txt)                        ; picked item moves to the top
    if LastWin && WinExist(LastWin) {
        WinActivate(LastWin)
        if WinWaitActive(LastWin, , 1) {
            Sleep(60)
            Send("^v")
        }
    }
}

RemoveSelected() {
    global History
    idx := SelectedIndex()
    if !idx
        return
    History.RemoveAt(idx)
    SaveHistory()
    RefreshList()
}

ClearAll(*) {
    global History
    if MsgBox("Delete all " History.Length " saved copies?", "Clip Stack", "YesNo Icon? 262144") != "Yes"
        return
    History := []
    SaveHistory()
    RefreshList()
}

GuiActive() => IsObject(Gui1) && WinActive("ahk_id " Gui1.Hwnd)
LVFocused() => IsObject(LV) && ControlGetFocus("A") = LV.Hwnd
SearchFocused() => IsObject(SearchBox) && ControlGetFocus("A") = SearchBox.Hwnd

; ---------------- storage / helpers ----------------
LoadHistory() {
    global History
    if !FileExist(DATA_FILE)
        return
    for v in StrSplit(FileRead(DATA_FILE, "UTF-8"), SEP)
        if (v != "")
            History.Push(v)
}

SaveHistory() {
    s := ""
    for v in History
        s .= (A_Index > 1 ? SEP : "") v
    f := FileOpen(DATA_FILE, "w", "UTF-8")
    f.Write(s)
    f.Close()
}

Preview(s, n) {
    s := Trim(RegExReplace(s, "\s+", " "))
    return StrLen(s) > n ? SubStr(s, 1, n) "..." : s
}

Tip(msg, ms := 2000) {
    ToolTip(msg)
    SetTimer(HideTip, -ms)
}
HideTip() => ToolTip()

SetupTray() {
    try TraySetIcon("imageres.dll", 242)
    A_IconTip := "Clip Stack`nCtrl+Shift+C = cycle`nCtrl+Alt+Shift+V = list"
    m := A_TrayMenu
    m.Delete()
    m.Add("Show history  (Ctrl+Alt+Shift+V)", ShowHistory)
    m.Add("Clear history", ClearAll)
    m.Add()
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Show history  (Ctrl+Alt+Shift+V)"
    m.ClickCount := 1                   ; single left-click on tray icon opens the list
}

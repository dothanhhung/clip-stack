#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent

; ---- one instance; desktop icon / right-click menu pass /history or /typed to it ----
global MSG_CMD := 0x5C57
global StartCmd := A_Args.Length ? A_Args[1] : ""
DetectHiddenWindows(true)
for hw in WinGetList(A_ScriptFullPath " ahk_class AutoHotkey") {
    if (hw = A_ScriptHwnd)
        continue
    if (StartCmd = "/history" || StartCmd = "/typed") {
        try DllCall("AllowSetForegroundWindow", "UInt", WinGetPID(hw))
        PostMessage(MSG_CMD, StartCmd = "/history" ? 1 : 2, 0, , hw)
        ExitApp
    }
    WinClose(hw)                        ; plain start = replace the old copy (it saves on exit)
    WinWaitClose(hw, , 3)
}
DetectHiddenWindows(false)
OnMessage(MSG_CMD, RemoteCmd)
RemoteCmd(wParam, *) {
    SetTimer(wParam = 1 ? ShowHistory : ShowTyped, -1)
    return 1
}

; ============================================================
;  Clip Stack - keeps every Ctrl+C (text) + a short-term log of what you type
;
;  All shortcuts = hold Ctrl+Shift+Z, then tap a letter:
;    Ctrl+Shift+Z + C   cycle saved copies onto the clipboard (then Ctrl+V)
;    Ctrl+Shift+Z + V   open the clipboard history list (also: left-click tray icon)
;    Ctrl+Shift+Z + T   open "Typed text" recovery (what you typed lately)
;  Ctrl+Shift+Z alone still works as Redo (sent when you let go of Z).
;
;  Clipboard list: type to search, Enter/double-click = paste, Del = remove, Esc = close
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

; ---- typing recorder ----
global TYPED_MAX_CHARS := 60000    ; ~10,000 words; oldest text is dropped past this
global TYPED_FILE  := A_ScriptDir "\typed-recovery.txt"
global TYPED_GAP_MS := 120000      ; 2 min without typing = new entry
global SKIP_EXE   := ["KeePass.exe", "KeePassXC.exe", "1Password.exe", "Bitwarden.exe", "mstsc.exe"]
global SKIP_TITLE := "i)password|passcode|mật khẩu|sign ?in|log ?in|đăng nhập"
global Typed := [], TypedChars := 0, TypedDirty := false, TypedPaused := false
global CurHwnd := 0, CurTitle := "", LastTypeTick := 0, TypeHook := ""
global Gui2 := "", TLV := "", TEdit := "", TSearch := "", TPauseBtn := ""

; ---- Z chord state ----
global ZHeld := false, ZUsed := false, ZTick := 0

LoadHistory()
LoadTyped()
SetupTray()
OnClipboardChange(ClipChanged)
StartTypingRecorder()
SetTimer(SaveTypedIfDirty, 3000)
OnExit((*) => SaveTyped())
if (StartCmd = "/history")
    SetTimer(ShowHistory, -300)
else if (StartCmd = "/typed")
    SetTimer(ShowTyped, -300)

; ---------------- Ctrl+Shift+Z chord ----------------
$^+z:: {
    global ZHeld, ZUsed, ZTick
    if ZHeld                         ; key auto-repeat
        return
    ZHeld := true, ZUsed := false, ZTick := A_TickCount
    Send("{Blind}{vkE8}")            ; stops UniKey reading this as a bare Ctrl+Shift (language switch)
}
~*z up:: {
    global ZHeld, ZUsed
    if !ZHeld
        return
    ZHeld := false
    if ZUsed
        return
    ; plain Ctrl+Shift+Z = Redo, passed on at release. {Blind} + only the modifiers that are
    ; really up get pressed/released, so Ctrl/Shift can never be left stuck down.
    c := GetKeyState("Ctrl"), s := GetKeyState("Shift")
    Send("{Blind}" (c ? "" : "{Ctrl down}") (s ? "" : "{Shift down}") "{z}" (s ? "" : "{Shift up}") (c ? "" : "{Ctrl up}"))
}
ZChord() => ZHeld && (A_TickCount - ZTick < 10000) && GetKeyState("Ctrl") && GetKeyState("Shift")
UseZ() {
    global ZUsed := true, ZTick := A_TickCount
}

#HotIf ZChord()
*c:: (UseZ(), CycleNext())
*v:: (UseZ(), ShowHistory())
*t:: (UseZ(), ShowTyped())
#HotIf

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

; ---------------- cycle (Ctrl+Shift+Z + C) ----------------
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

; ---------------- clipboard history window (Ctrl+Shift+Z + V) ----------------
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
    LV.OnEvent("ContextMenu", ClipMenu)
    HintTxt := Gui1.Add("Text", "xm w620 cGray", "Enter / double-click = paste     Del = remove     Esc = close     Ctrl+Shift+Z+C = cycle")
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
    cls := ""
    try cls := WinGetClass(LastWin)
    if (cls ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$") || !cls {
        Tip("Copied - paste it with Ctrl+V")    ; opened from the desktop: nowhere to paste
        return
    }
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

; right-click on a row of the clipboard list
ClipMenu(ctrl, item, isRightClick, x, y) {
    if !item
        return
    LV.Modify(0, "-Select"), LV.Modify(item, "Select Focus")
    m := Menu()
    m.Add("Paste", (*) => PickSelected())
    m.Add("Copy", ClipCopySel)
    m.Add("Delete", (*) => RemoveSelected())
    m.Add()
    m.Add("Clear all", ClearAll)
    m.Default := "Paste"
    m.Show()
}
ClipCopySel(*) {
    idx := SelectedIndex()
    if !idx
        return
    SetClip(History[idx])
    AddItem(History[idx])
    Tip("Copied - paste it with Ctrl+V")
}

GuiActive() => IsObject(Gui1) && WinActive("ahk_id " Gui1.Hwnd)
LVFocused() => IsObject(LV) && ControlGetFocus("A") = LV.Hwnd
SearchFocused() => IsObject(SearchBox) && ControlGetFocus("A") = SearchBox.Hwnd

; ---------------- typing recorder ----------------
StartTypingRecorder() {
    global TypeHook
    TypeHook := InputHook("V L0")       ; V = keys still reach the app; L0 = we keep our own buffer
    TypeHook.KeyOpt("{Backspace}{Enter}{NumpadEnter}{Tab}", "N")
    TypeHook.OnChar := TypedChar
    TypeHook.OnKeyDown := TypedKey
    TypeHook.Start()
}

TypedChar(ih, ch) {
    if (Ord(ch) < 32)                   ; Ctrl+letter, Enter, Tab, Backspace come as control chars
        return
    TypedAdd(ch)
}

TypedKey(ih, vk, sc) {
    if (vk = 8)
        TypedBack(GetKeyState("Ctrl"))
    else if (vk = 13) && !GetKeyState("Ctrl") && !GetKeyState("Alt")
        TypedAdd("`n")
    else if (vk = 9) && !GetKeyState("Ctrl") && !GetKeyState("Alt")
        TypedAdd("`t")
}

TypedWindow(&exe, &title) {
    try {
        exe := WinGetProcessName("A"), title := WinGetTitle("A")
    } catch
        return false
    if TypedPaused
        return false
    for e in SKIP_EXE
        if (e = exe)
            return false
    if RegExMatch(title, SKIP_TITLE)
        return false
    if (IsObject(Gui1) && WinActive("ahk_id " Gui1.Hwnd)) || (IsObject(Gui2) && WinActive("ahk_id " Gui2.Hwnd))
        return false
    try {                               ; classic password boxes (ES_PASSWORD)
        h := ControlGetFocus("A")
        if h && (ControlGetStyle(h) & 0x20) && InStr(WinGetClass(h), "Edit")
            return false
    }
    return true
}

TypedAdd(s) {
    global Typed, TypedChars, TypedDirty, CurHwnd, CurTitle, LastTypeTick
    if !TypedWindow(&exe, &title)
        return
    hwnd := WinExist("A")
    if !Typed.Length || hwnd != CurHwnd || title != CurTitle || (A_TickCount - LastTypeTick > TYPED_GAP_MS) {
        if !(Typed.Length && Typed[-1].text = "")
            Typed.Push({})
        Typed[-1] := {t: FormatTime(, "yyyy-MM-dd HH:mm:ss"), app: exe, title: title, text: ""}
        CurHwnd := hwnd, CurTitle := title
    }
    LastTypeTick := A_TickCount
    Typed[-1].text .= s
    TypedChars += StrLen(s)
    while (TypedChars > TYPED_MAX_CHARS) {
        if (Typed.Length > 1) {
            TypedChars -= StrLen(Typed[1].text)
            Typed.RemoveAt(1)
        } else {
            cut := TypedChars - TYPED_MAX_CHARS
            Typed[1].text := SubStr(Typed[1].text, cut + 1)
            TypedChars -= cut
        }
    }
    TypedDirty := true
}

TypedBack(ctrl) {
    global TypedChars, TypedDirty
    if !Typed.Length || WinExist("A") != CurHwnd
        return
    e := Typed[-1]
    if (e.text = "")
        return
    before := StrLen(e.text)
    e.text := ctrl ? RegExReplace(e.text, "(\S+\s*|\s+)$") : SubStr(e.text, 1, -1)
    TypedChars -= before - StrLen(e.text)
    TypedDirty := true
}

SaveTypedIfDirty() {
    if TypedDirty
        SaveTyped()
}

SaveTyped() {
    global TypedDirty := false
    s := ""
    for e in Typed
        if (e.text != "")
            s .= SEP "===== " e.t " | " e.app " | " StrReplace(e.title, "`n", " ") " =====`n" e.text "`n"
    try {
        f := FileOpen(TYPED_FILE, "w", "UTF-8")
        f.Write(s)
        f.Close()
    }
}

LoadTyped() {
    global Typed, TypedChars
    if !FileExist(TYPED_FILE)
        return
    for block in StrSplit(FileRead(TYPED_FILE, "UTF-8"), SEP) {
        if !RegExMatch(block, "s)^===== (.*?) \| (.*?) \| (.*?) =====`n(.*)`n$", &m)
            continue
        Typed.Push({t: m[1], app: m[2], title: m[3], text: m[4]})
        TypedChars += StrLen(m[4])
    }
}

; ---------------- typed-text recovery window (Ctrl+Shift+Z + T) ----------------
ShowTyped(*) {
    global Gui2
    if !IsObject(Gui2)
        BuildTypedGui()
    TSearch.Value := ""
    RefreshTyped()
    Gui2.Show("w900 h620")
    TSearch.Focus()
}

BuildTypedGui() {
    global Gui2, TLV, TEdit, TSearch, TPauseBtn
    Gui2 := Gui("+AlwaysOnTop +Resize +MinSize600x400", "Clip Stack - Typed text recovery")
    Gui2.SetFont("s10", "Segoe UI")
    Gui2.Add("Text", "xm ym+3", "Search:")
    TSearch := Gui2.Add("Edit", "x+6 ym w300")
    TSearch.OnEvent("Change", (*) => RefreshTyped())
    Gui2.Add("Button", "x+10 ym-1", "Copy selected").OnEvent("Click", TypedCopySel)
    Gui2.Add("Button", "x+6", "Copy all").OnEvent("Click", TypedCopyAll)
    TPauseBtn := Gui2.Add("Button", "x+6 w120", TypedPaused ? "Resume recording" : "Pause recording")
    TPauseBtn.OnEvent("Click", TogglePause)
    Gui2.Add("Button", "x+6", "Clear all").OnEvent("Click", TypedClear)
    TLV := Gui2.Add("ListView", "xm w880 h210 -Multi Grid", ["#", "Time", "App", "Words", "Start of text"])
    TLV.OnEvent("ItemSelect", (*) => ShowTypedSel())
    TLV.OnEvent("DoubleClick", TypedCopySel)
    TLV.OnEvent("ContextMenu", TypedMenu)
    TEdit := Gui2.Add("Edit", "xm w880 h340 ReadOnly Multi VScroll WantReturn")
    Gui2.OnEvent("Escape", (*) => Gui2.Hide())
    Gui2.OnEvent("Close", (*) => Gui2.Hide())
    Gui2.OnEvent("Size", TypedSize)
}

TypedSize(g, minMax, w, h) {
    if (minMax = -1)
        return
    TLV.Move(, , w - 20)
    TLV.ModifyCol(5, w - 380)
    TEdit.Move(, , w - 20, h - 270)
}

RefreshTyped() {
    if !IsObject(Gui2)
        return
    q := TSearch.Value
    TLV.Opt("-Redraw")
    TLV.Delete()
    i := Typed.Length
    while (i >= 1) {                    ; newest first
        e := Typed[i]
        if (e.text != "") && (q = "" || InStr(e.text, q) || InStr(e.title, q)) {
            RegExReplace(e.text, "\S+", "", &words)
            TLV.Add(, i, e.t, e.app, words, Preview(e.text, 200))
        }
        i--
    }
    TLV.ModifyCol(1, "40 Integer"), TLV.ModifyCol(2, 150), TLV.ModifyCol(3, 120), TLV.ModifyCol(4, "60 Integer")
    TLV.ModifyCol(5, 500)
    TLV.Opt("+Redraw")
    if TLV.GetCount()
        TLV.Modify(1, "Select Focus")
    ShowTypedSel()
}

TypedSelIndex() {
    row := TLV.GetNext()
    return row ? Integer(TLV.GetText(row, 1)) : 0
}

ShowTypedSel() {
    idx := TypedSelIndex()
    if !idx || idx > Typed.Length {
        TEdit.Value := ""
        return
    }
    e := Typed[idx]
    TEdit.Value := e.title "`r`n" e.t "  |  " e.app "`r`n------------------------------`r`n" StrReplace(StrReplace(e.text, "`r`n", "`n"), "`n", "`r`n")
}

TypedCopySel(*) {
    idx := TypedSelIndex()
    if !idx
        return
    SetClip(Typed[idx].text)
    Tip("Copied - paste it with Ctrl+V")
}

; right-click on a row of the typed-text list
TypedMenu(ctrl, item, isRightClick, x, y) {
    if !item
        return
    TLV.Modify(0, "-Select"), TLV.Modify(item, "Select Focus")
    ShowTypedSel()
    m := Menu()
    m.Add("Copy this text", TypedCopySel)
    m.Add("Copy all", TypedCopyAll)
    m.Add("Delete this entry", TypedDeleteSel)
    m.Add()
    m.Add(TypedPaused ? "Resume recording" : "Pause recording", TogglePause)
    m.Add("Clear all", TypedClear)
    m.Default := "Copy this text"
    m.Show()
}

TypedDeleteSel(*) {
    global Typed, TypedChars
    idx := TypedSelIndex()
    if !idx || idx > Typed.Length
        return
    TypedChars -= StrLen(Typed[idx].text)
    Typed.RemoveAt(idx)
    SaveTyped()
    RefreshTyped()
}

TypedCopyAll(*) {
    s := ""
    for e in Typed
        if (e.text != "")
            s .= "===== " e.t " | " e.app " | " e.title " =====`n" e.text "`n`n"
    SetClip(s)
    Tip("All typed text copied")
}

TypedClear(*) {
    global Typed, TypedChars
    if MsgBox("Delete all recorded typing?", "Clip Stack", "YesNo Icon? 262144") != "Yes"
        return
    Typed := [], TypedChars := 0
    SaveTyped()
    RefreshTyped()
}

TogglePause(*) {
    global TypedPaused := !TypedPaused
    try TPauseBtn.Text := TypedPaused ? "Resume recording" : "Pause recording"
    A_TrayMenu.ToggleCheck("Pause typing recorder")
    Tip(TypedPaused ? "Typing recorder paused" : "Typing recorder on")
}

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
    A_IconTip := "Clip Stack - hold Ctrl+Shift+Z, then:`nC = cycle   V = clipboard list`nT = typed text recovery"
    m := A_TrayMenu
    m.Delete()
    m.Add("Clipboard history  (Ctrl+Shift+Z+V)", ShowHistory)
    m.Add("Typed text recovery  (Ctrl+Shift+Z+T)", ShowTyped)
    m.Add()
    m.Add("Pause typing recorder", TogglePause)
    m.Add("Clear clipboard history", ClearAll)
    m.Add()
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Clipboard history  (Ctrl+Shift+Z+V)"
    m.ClickCount := 1                   ; single left-click on tray icon opens the list
}

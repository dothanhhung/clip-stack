# Clip Stack

A small AutoHotkey v2 script for Windows that remembers everything you copy with Ctrl+C, so you can paste older copies again.

## What it does
- **Ctrl+C** works as normal. Every text copy is also saved (the last 100, kept after a reboot).
- **Ctrl+Shift+C** steps through your saved copies and puts each one on the clipboard. A tooltip shows which one you're on. Press **Ctrl+V** to paste it. Stop for more than 2.5 s and the next press starts again from your previous copy.
- **Ctrl+Alt+Shift+V**, or a left-click on the tray icon, opens the history list:
  - type to search
  - **Enter** or double-click pastes the item into the window you were in
  - **Del** removes an item, **Esc** closes the list, **Clear all** empties it

## Notes
- Ctrl+Shift+C is left alone in Windows Terminal and mintty (Git Bash), where it means copy. Elsewhere the script takes it over, for example Chrome/Edge DevTools "Inspect element" and VS Code "Open external terminal". Add an app to the `#HotIf` line to keep its own Ctrl+Shift+C.
- Copies that password managers mark as private (`ExcludeClipboardContentFromMonitorProcessing`) are not saved. Anything else, including a password you copy by hand, is stored as plain text in `clip-stack-history.dat` beside the script.
- Text only. Images and files are not saved.

## Install
1. Install [AutoHotkey v2](https://www.autohotkey.com/) (or `winget install AutoHotkey.AutoHotkey`).
2. Download `clip-stack.ahk` and double-click it. A tray icon appears (it may be under the **^** arrow).
3. **Start with Windows:** press Win + R, type `shell:startup`, and put a shortcut to the script in that folder.

To stop it: right-click the tray icon → **Exit**.

## License
MIT

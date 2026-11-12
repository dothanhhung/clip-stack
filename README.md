# Clip Stack

A small AutoHotkey v2 script for Windows that:
- remembers everything you copy with Ctrl+C, so you can paste older copies again;
- keeps a short-term log of what you type (about the last 10,000 words), so text you forgot to save, or lost when an app or browser tab closed, can be recovered.

## Shortcuts
Every shortcut is **hold Ctrl+Shift+Z, then tap a letter**:

| Keys | What it does |
|---|---|
| Ctrl+Shift+Z + **C** | Step through saved copies. A tooltip shows which one is on the clipboard; press Ctrl+V to paste. Stop for 2.5 s and the next press starts again from your previous copy. |
| Ctrl+Shift+Z + **V** | Open the clipboard history list (or left-click the tray icon). |
| Ctrl+Shift+Z + **T** | Open "Typed text recovery". |

Ctrl+Shift+Z on its own still works as **Redo**. It is passed on when you let go of Z.

Why this chord: single shortcuts such as Ctrl+Shift+C or Ctrl+Shift+V are already used by browsers, VS Code, terminals and "paste as plain text". Holding Z as a third key gives a combination no common app uses.

## Clipboard history list
Type to search. **Enter** or double-click pastes the item into the window you were in. **Del** removes an item, **Esc** closes the list, and **Clear all** empties it. The last 100 text copies are kept, also after a reboot.

## Typed text recovery
- Everything you type is logged, one entry per window, with the time, app and window title. A new entry starts when you switch windows or after 2 minutes without typing.
- Backspace and Ctrl+Backspace are applied, so the log reads like what you wrote. Arrow keys and mouse clicks are not tracked, so text you edited in the middle may read out of order.
- About 60,000 characters (~10,000 words) are kept; the oldest text is dropped first. The log is saved to disk every 3 s, so it survives a crash or reboot.
- In the window: pick an entry to read it in full, then **Copy selected** (or double-click) and paste it back where it belongs. **Copy all**, **Pause recording** and **Clear all** are there too. Pause is also in the tray menu.

## Privacy - read this
- The typing log is stored as **plain text** in `typed-recovery.txt` beside the script. Clipboard history is in `clip-stack-history.dat`. Nothing leaves your PC.
- Typing is **not** recorded in: password managers (KeePass, KeePassXC, 1Password, Bitwarden), Remote Desktop, classic Windows password boxes, and any window whose title contains "password", "sign in", "log in", "mật khẩu" or "đăng nhập".
- Browsers do not tell other programs that a box is a password box. A password typed on a page whose title doesn't match the list above **will be recorded**. Use **Pause recording** when needed, and **Clear all** if something slipped in.
- Copies that password managers mark as private are not saved to the clipboard history.

## Install
1. Install [AutoHotkey v2](https://www.autohotkey.com/) (or `winget install AutoHotkey.AutoHotkey`).
2. Download `clip-stack.ahk` and double-click it. A tray icon appears (it may be under the **^** arrow).
3. **Start with Windows:** press Win + R, type `shell:startup`, and put a shortcut to the script in that folder.

To stop it: right-click the tray icon → **Exit**.

## Notes
- If you use UniKey with Ctrl+Shift as the language switch: the script sends a harmless dummy key when the chord starts, so holding Ctrl+Shift+Z doesn't switch your input language.
- Vietnamese typed through UniKey/EVKey should be logged as finished text (accents included), because those tools retype each word through the same keyboard stream. This has not been checked with real typing yet.

## License
MIT

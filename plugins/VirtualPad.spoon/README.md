# VirtualPad

Controller input simulation for macros. On macOS it requires SIP off and the boot-arg
`amfi_get_out_of_my_way=0x1`, because the virtual HID device entitlement is
restricted and only an AMFI-disabled system lets an ad-hoc signed helper use it.

## How it works

On load the plugin compiles `bin/ms_vpad.swift` to `~/.local/bin/ms_vpad` and
signs it with `bin/ms_vpad.entitlements`. The helper waits for a gamepad, opens
it and creates a virtual copy with the same vendor ID, name and report
descriptor. Every real input report is forwarded through the copy with macro
input merged on top. Bluetooth PlayStation pads keep their full report format,
with the checksum recomputed after patching.

Seizing the real pad does not hide it from other processes on current macOS, so
games would see two controllers. For PlayStation pads the copy takes a sibling
product ID (DS4 v1 and v2 swap, DualSense and DualSense Edge swap), and the
helper publishes the real pad's ID in `SDL_GAMECONTROLLER_IGNORE_DEVICES` and
`SDL_HIDAPI_IGNORE_DEVICES` with `launchctl setenv`. SDL games launched after
that, Roblox included, see only the copy. The helper clears both on exit, so
relaunch the game after arming or disarming the plugin. Unplugging the pad tears the copy down, and quitting the helper
hands the real pad back to the system.

The helper saves the pad's identity to `~/.hammerspoon/data/ms_vpad_pad.json`.
On the next start it creates the copy from that file before the real pad
appears, and keeps the copy alive when the real pad disconnects. The copy then
connects before the real pad, so games that take the first controller pick
the copy.

On macOS the helper runs detached and talks to the plugin over the Unix socket
`~/.hammerspoon/data/ms_vpad.sock`, so it survives Hammerspoon reloads and the
copy keeps its place ahead of the real pad. When the plugin disconnects, the
helper drops any macro input and keeps forwarding the real pad. The plugin
replaces the helper only when the compiled binary is newer than the running
one. Disarming or disabling the plugin quits it.

## Windows

On Windows the plugin needs the ViGEmBus driver (`winget install
ViGEm.ViGEmBus`). On load it copies `bin/ms_vpad.exe` and `bin/SDL2.dll` to
`~/.local/bin`. The helper reads the real pad through SDL2 and clones it with
the same input type, so games do not switch prompts. PlayStation pads become a
virtual DualShock 4 (a DS4 keeps its own vendor and product ID, a DualSense
appears as a DS4 v2) and Xbox pads become a virtual Xbox 360 controller.
ViGEmBus has no Switch target, so Switch and generic pads also clone as Xbox
360.

With HidHide installed (`winget install Nefarius.HidHide`) the helper hides the
real pad from every other process while the clone is live and unhides it on
exit. Without HidHide games see both pads. The helper records hidden devices in
`~/.local/bin/ms_vpad.hidden`, so a crash never leaves the pad hidden: the
plugin runs `ms_vpad.exe --unhide` after any abnormal exit, and every helper
start restores leftovers first.

Rebuild the helper with `bin/build.bat`. It finds gcc on `PATH`, MSYS2, or a
winget WinLibs install, and installs WinLibs with winget when none is present.

## API

```lua
ms.vpad.available()
ms.vpad.controller()
ms.vpad.press("a")
ms.vpad.release("a")
ms.vpad.tap("a", 50)
ms.vpad.stick("left", 0, -1)
ms.vpad.stick("left")
ms.vpad.trigger("r2", 1)
ms.vpad.trigger("r2")
ms.vpad.releaseAll()
ms.vpad.status()
```

Button names match `ms.padstate`: `a b x y l1 r1 l2 r2 l3 r3 up down left right
menu options home`. Stick values run from -1 to 1, trigger values from 0 to 1.
Passing no value hands the stick or trigger back to the real controller.
Cancelling a macro releases whatever it held.

While the clone is live the helper decodes the real controller's reports and
becomes the gamepad source for core, so `ms.padstate`, `ms.padaxis` and gamepad
binds see only physical input. Simulated presses never trigger binds or combo
gates. Stick Y follows `ms.padaxis`: positive is up.

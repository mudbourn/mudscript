# VirtualPad

Controller input simulation for macros. Requires SIP off and the boot-arg
`amfi_get_out_of_my_way=0x1`, because the virtual HID device entitlement is
restricted and only an AMFI-disabled system lets an ad-hoc signed helper use it.

## How it works

On load the plugin compiles `bin/ms_vpad.swift` to `~/.local/bin/ms_vpad` and
signs it with `bin/ms_vpad.entitlements`. The helper waits for a gamepad, seizes
it so games stop seeing it directly, and creates a virtual copy with the same
vendor ID, product ID, name and report descriptor. Every real input report is
forwarded through the copy with macro input merged on top, so the game sees one
controller. Unplugging the pad tears the copy down, and quitting the helper
hands the real pad back to the system.

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

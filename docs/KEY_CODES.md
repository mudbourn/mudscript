# Key Code Reference

macOS virtual key codes for use with `ms.keystate(code, true)`, `ms.press(key)`, `ms.release(key)`, and `ms.type(key)`.

---

## Custom Mappings (mudscript)

These are defined in `ms_core.lua` and take priority over Hammerspoon's built-in map:

| Name | Code | Description |
|---|---|---|
| `left` | 123 | Left arrow |
| `right` | 124 | Right arrow |
| `down` | 125 | Down arrow |
| `up` | 126 | Up arrow |
| `shift` | 56 | Left shift |
| `lshift` | 56 | Left shift |
| `rshift` | 62 | Right shift |
| `ctrl` | 59 | Left control |
| `lctrl` | 59 | Left control |
| `rctrl` | 61 | Right control |
| `alt` | 58 | Left option/alt |
| `lalt` | 58 | Left option/alt |
| `ralt` | 61 | Right option/alt |
| `cmd` | 55 | Left command |
| `lcmd` | 55 | Left command |
| `rcmd` | 54 | Right command |
| `f1` | 122 | F1 |
| `f2` | 120 | F2 |
| `f3` | 99 | F3 |
| `f4` | 118 | F4 |
| `f5` | 96 | F5 |
| `f6` | 97 | F6 |
| `f7` | 98 | F7 |
| `f8` | 100 | F8 |
| `f9` | 101 | F9 |
| `f10` | 109 | F10 |
| `f11` | 103 | F11 |
| `f12` | 111 | F12 |
| `leftclick` / `mouse1` | 997 | Virtual: left mouse button |
| `rightclick` / `mouse2` | 999 | Virtual: right mouse button |
| `middleclick` / `mouse3` | 998 | Virtual: middle mouse button |
| `mouse4` / `mouseback` | 996 | Virtual: thumb button (back) |
| `mouse5` / `mouseforward` | 995 | Virtual: thumb button (forward) |

These virtual codes are live-tracked and can be read with `ms.keystate` (by name) or, more legibly, with `ms.mousestate`.

---

## Common Keys (via `hs.keycodes.map`)

These are resolved automatically when you pass a string name:

| Name | Code | Description |
|---|---|---|
| `a` | 0 | A |
| `b` | 11 | B |
| `c` | 8 | C |
| `d` | 2 | D |
| `e` | 14 | E |
| `f` | 3 | F |
| `g` | 5 | G |
| `h` | 4 | H |
| `i` | 34 | I |
| `j` | 38 | J |
| `k` | 40 | K |
| `l` | 37 | L |
| `m` | 46 | M |
| `n` | 45 | N |
| `o` | 31 | O |
| `p` | 35 | P |
| `q` | 12 | Q |
| `r` | 15 | R |
| `s` | 1 | S |
| `t` | 17 | T |
| `u` | 32 | U |
| `v` | 9 | V |
| `w` | 13 | W |
| `x` | 7 | X |
| `y` | 16 | Y |
| `z` | 6 | Z |
| `0` | 29 | 0 |
| `1` | 18 | 1 |
| `2` | 19 | 2 |
| `3` | 20 | 3 |
| `4` | 21 | 4 |
| `5` | 23 | 5 |
| `6` | 22 | 6 |
| `7` | 26 | 7 |
| `8` | 28 | 8 |
| `9` | 25 | 9 |
| `space` | 49 | Spacebar |
| `return` | 36 | Return/Enter |
| `tab` | 48 | Tab |
| `escape` | 53 | Escape |
| `delete` | 51 | Delete (backspace) |
| `forwarddelete` | 117 | Forward delete |
| `home` | 115 | Home |
| `end` | 119 | End |
| `pageup` | 116 | Page up |
| `pagedown` | 121 | Page down |
| `` ` `` | 50 | Backtick/tilde |
| `-` | 27 | Minus/underscore |
| `=` | 24 | Equals/plus |
| `[` | 33 | Left bracket |
| `]` | 30 | Right bracket |
| `\` | 42 | Backslash |
| `;` | 41 | Semicolon |
| `'` | 39 | Quote |
| `,` | 43 | Comma |
| `.` | 47 | Period |
| `/` | 44 | Slash |
| `keypad.` | 65 | Keypad decimal |
| `keypad*` | 67 | Keypad multiply |
| `keypad+` | 69 | Keypad plus |
| `keypad/` | 75 | Keypad divide |
| `keypad-` | 78 | Keypad minus |
| `keypad=` | 81 | Keypad equals |
| `keypad0` | 82 | Keypad 0 |
| `keypad1` | 83 | Keypad 1 |
| `keypad2` | 84 | Keypad 2 |
| `keypad3` | 85 | Keypad 3 |
| `keypad4` | 86 | Keypad 4 |
| `keypad5` | 87 | Keypad 5 |
| `keypad6` | 88 | Keypad 6 |
| `keypad7` | 89 | Keypad 7 |
| `keypad8` | 91 | Keypad 8 |
| `keypad9` | 92 | Keypad 9 |
| `keypadenter` | 76 | Keypad enter |
| `keypadclear` | 71 | Keypad clear |

---

## Usage

```lua
-- By name (recommended)
ms.press("space")
ms.type("a", { "shift" })  -- capital A
ms.type("return")

-- By numeric code
ms.press(49)        -- same as ms.press("space")
ms.keystate(56)     -- check if left shift is held

-- With raw code flag (for hardware-specific codes)
ms.keystate(49, true)  -- check space by raw code
```

---

## Mouse Buttons

| Code | Button |
|---|---|
| 0 | Left |
| 1 | Right |
| 2 | Middle (scroll wheel click) |
| 3 | Back (side button) |
| 4 | Forward (side button) |

Used with `ms.mouse(button, swallow, clickFn)`:
```lua
ms.mouse(0, true, function() print("left click") end)   -- left
ms.mouse(1, true, function() print("right click") end)  -- right
ms.mouse(2, true, function() print("middle click") end) -- middle
```

To poll whether a button is currently held (rather than react to a click), use `ms.mousestate`. It takes the same button numbers plus friendly names (`left`, `right`, `middle`, `back`, `forward`):
```lua
if ms.mousestate("back") then ... end   -- thumb button held
```

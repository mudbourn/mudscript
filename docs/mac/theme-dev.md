# Theme, Capabilities & Developer Tools

## Theme System

The panel UI is fully themeable via `~/.hammerspoon/data/ms_theme.json`. Edit the file directly, then use **Developer > Reload Theme** in the settings panel (or `hs.reload()`) to apply changes.

---

### `data/ms_theme.json`

```json
{
    "bg":           "#0d0f09",
    "surface":      "#141810",
    "surface2":     "#1c2116",
    "hover":        "#2d3523",
    "accent":       "#6b8c3a",
    "accentHi":     "#8db84e",
    "success":      "#7aa63c",
    "dangerBg":     "#1c130f",
    "danger":       "#c0492e",
    "warning":      "#c4a030",
    "text":         "#d4cfb6",
    "radius":       8,
    "windowRadius": 8,
    "font":         "Arial",
    "fadeMs":       250
}
```

---

### Color fields

All color values must be valid hex strings (`#rgb`, `#rrggbb`, or `#rrggbbaa`). Non-hex values are silently ignored and the default is kept.

| Key | Default | Description |
|-----|---------|-------------|
| `bg` | `#0d0f09` | Panel background (void) |
| `surface` | `#141810` | Section / card surface |
| `surface2` | `#1c2116` | Raised surface (rows, inputs) |
| `hover` | `#2d3523` | Row hover state |
| `accent` | `#6b8c3a` | Primary accent, active borders, chevrons |
| `accentHi` | `#8db84e` | Accent highlight (focus, flash) |
| `success` | `#7aa63c` | Success state (active profile pill) |
| `dangerBg` | `#1c130f` | Danger element background |
| `danger` | `#c0492e` | Danger foreground (destructive buttons) |
| `warning` | `#c4a030` | Warning / notice colour |
| `text` | `#d4cfb6` | Primary text |

---

### `radius`

Integer, `0`-`40`. Controls `--radius` (and derives `--radius-s` as `radius - 1`). Default: `8`.

```json
{ "radius": 8 }
```

---

### `windowRadius`

Integer, `0`-`40`. Optional override for the rounded corner applied to each webview panel window frame (via `ms.theme.applyWindowRadius`). When unset the window frame follows the theme `radius` (the Appearance "Corner radius" value), so the frame and the inner content round to the same value. Set this only to make the window frame differ from the content radius.

```json
{ "windowRadius": 8 }
```

---

### `fadeMs`

Integer, `0`-`500`. Duration in milliseconds for panel fade-in / fade-out animations. Affects the settings panel, all four developer panels, and the startup loading screen. Set to `0` to disable fades completely. Default: `250`.

```json
{ "fadeMs": 300 }
```

---

### `font`

A system font name or a relative path (from `~/.hammerspoon/`) to a local font file.

```json
{ "font": "Georgia" }
{ "font": "ui/fonts/MyFont.ttf" }
```

Supported file extensions: `.ttf`, `.otf`, `.woff`, `.woff2`. If a file path is given, a `@font-face` rule is injected dynamically. The font name in CSS falls back to `Almendra to Palatino to Georgia to serif`.

---

### `ms.loadTheme()`

Reads and validates `data/ms_theme.json`. Called automatically at startup after `ms.loadSettings()`. Also triggered by **Developer > Reload Theme** in the panel.

---

## Capability Detection, `ms.has`

`ms.has(feature)` returns `true` if the named feature is present and configured. Call it from anywhere in `ms_macros.lua` to guard optional behaviour so packs degrade gracefully when a user hasn't set something up, or when running on an older mudscript install.

```lua
if ms.has("theme") then
    -- user has a custom data/ms_theme.json loaded
end

if ms.has("userSettings") then
    ms.settings.define({ ... })   -- safe on any version
end
```

### Flag reference

| Flag | Returns `true` when |
|------|--------------------|
| `"theme"` | `data/ms_theme.json` was loaded from disk (not just built-in defaults) |
| `"sound"` | sound is enabled (`ms.soundEnabled`) and at least one file is indexed |
| `"socd"` | SOCD engine is currently enabled (`ms.socdEnabled`) |
| `"trackpad"` | trackpad mode is currently active (`ms.trackpadMode`) |
| `"profiles"` | at least one valid profile exists in `profiles/` |
| `"userSettings"` | `ms.settings.define` API is present, use for version compatibility |
| `"userMenu"` | `ms.menu.define` API is present, use for version compatibility |
| `"integrity"` | `ms_core.lua` matches its trusted hash (system integrity) (`ms.integrity.check() == "trusted"`) |

> **Note:** `"integrity"` runs a `shasum` check and is slightly heavier than the others. Avoid calling it inside a hot macro loop.

---

## Developer Tools, `ms.dev`

Four floating panels for live monitoring and interactive debugging. Open them from **Settings > Developer** or call the API directly. All panels share the active `data/ms_theme.json` theme, colors, font, and radius update automatically when the panel first loads.

The panels open near the top-right of the screen, staggered horizontally so they don't stack exactly on top of each other: Console is at the rightmost position, Macro Monitor 30 px further left, Input Monitor 60 px further left, and Window Monitor 90 px further left. All four panels fade in when opened and fade out when closed (150 ms, 6 steps). The open/close state is set immediately so `toggle()` works correctly during the animation.

> `ms.dev` is not accessible from `ms_macros.lua`. These tools are for the developer only.

---

### Console, `ms.dev.console`

A 360x640 REPL panel. Captures all `print()` output, errors, macro fires, and execution results as they happen.

- **Input field**: type any Lua expression or statement, press Enter or Run. Return values appear in green, and errors in red.
- **KEY and MOUSE badges**: key and mouse events appear inline as styled type badges: amber **KEY** and orange **MOUSE**. Consecutive same-type entries are collapsed, only the first KEY badge appears until a MOUSE or MACRO entry interrupts, after which the next KEY badge is shown again. Full event detail (key names, button, position) is in the Input Monitor.
- **Toolbar buttons**: open Macro Monitor and Input Monitor without leaving the console.

```lua
ms.dev.console.show()
ms.dev.console.hide()
ms.dev.console.toggle()
```

---

### Macro Monitor, `ms.dev.watcher`

A floating panel. Shows every macro execution with timestamp and label as it fires. Also surfaces `print()` output and errors.

**Step traces**, when the Macro Monitor is open, every action call automatically appends a dim step trace row. The following calls all produce traces:

| Call | Trace format |
|------|-------------|
| `ms.wait(n)` | `wait Nms` (all durations, no threshold) |
| `ms.press(key)` | `down key` |
| `ms.release(key)` | `up key` |
| `ms.type(key)` | `type key` |
| `ms.Mouse(op, btn, ...)` | `Mouse Op Button` |
| `ms.scroll(dir, n)` | `scroll dir` |
| `ms.sound(path)` | `sound filename` |
| `ms.copy(text)` | `copy` |
| `ms.cam(dx, dy)` | accumulated as `cam.move xN`, individual calls are batched and flushed as a single entry when the next different action fires |

Call `ms.dev.step(msg)` from any macro to log a named checkpoint manually:

```lua
ms.dev.step("before camera sweep")
ms.cam(-3145, 0)
ms.dev.step("done")
```

```lua
ms.dev.watcher.show()
ms.dev.watcher.hide()
ms.dev.watcher.toggle()
```

---

### Filter button

A **filter** button sits in the bottom-right corner of the panel. Clicking it opens a popup with per-category toggles:

| Category | Hides entries matching |
|----------|----------------------|
| Waits | `wait Nms` |
| Sound calls | `sound ...` |
| Camera moves | `cam.move xN` |
| Key presses | `down key`, `up key`, `type key` |
| Mouse actions | `Mouse ...` |
| Scrolls | `scroll ...` |
| Clipboard | `copy` |

Each toggle is independent. The bottom of the popup shows **"hide all"** when nothing is muted (clicking mutes every category) or **"show all"** when every category is muted (clicking unmutes all). The button label updates to `filter (N)` with an accent highlight when N categories are active.

Filtered entries remain in the DOM, they reappear instantly when the filter is cleared, without re-running the macro.

---

### Input Monitor, `ms.dev.keys`

A 360x640 floating panel with three sections:

- **Flag row**: two competing pills at the top showing the most recently pressed key and the most recently pressed mouse button. Whichever fired last is highlighted in the accent color, and the other dims. Updates in real time on every input event.
- **Keyboard tab**: active key pills (currently held keys) plus a scrolling log of all key events with timestamps. Each entry carries an amber **KEY** badge.
- **Mouse tab**: current cursor position plus a scrolling log of all mouse button down/up events. Each entry carries an orange **MOUSE** badge. A **SCROLL** (teal) badge appears for scroll events.
- **Coordinate reference dropdown**: in the mouse tab's Position header, a dropdown controls what coordinate system the cursor position is shown in:

  | Option | Origin |
  |--------|--------|
  | Screen | Absolute screen pixels |
  | Window | Pixels from the Roblox window's top-left corner |
  | REF 1680x1044 | Scaled into the 1680x1044 reference space used by `ms.Mouse(WindowTL, ...)` |
  | Screen center | Offset from the screen centre (negative = left/up) |

Mouse button events are logged regardless of whether macros are enabled (`BindValidity`), so the monitor works even when macros are off.

```lua
ms.dev.keys.show()
ms.dev.keys.hide()
ms.dev.keys.toggle()
```

---

### Window Monitor, `ms.dev.window`

A 360x480 floating panel. Tracks the focused window in real time by polling every 400 ms.

- **Current window**: shows the active app name, window title, and dimensions (width x height px) at the top.
- **Log**: appends an entry each time the focused window changes: `- App > Title [WxH]` with a Unix timestamp.
- **History**: up to 80 entries are kept in memory and restored when the panel is reopened.

```lua
ms.dev.window.show()
ms.dev.window.hide()
ms.dev.window.toggle()
```

---

### `ms.dev.step(msg)`

Manually append a named step trace to the Macro Monitor. No-op when the Macro Monitor is not open. Safe to call from inside any `ms.fn()`-wrapped function.

```lua
local MyMacro = ms.fn(function()
    ms.dev.step("phase 1, setup")
    ms.press("w")
    ms.wait(50)
    ms.dev.step("phase 2, jump")
    ms.type("space")
    ms.wait(600)
    ms.dev.step("done")
end)
```

---

### UI sounds

The developer panels use the same sound slots as the main Settings panel:

| Action | Slot |
|--------|------|
| Panel opens | `settingsOpen` |
| Panel closes | `settingsClose` |
| Button hover | `hover` |
| Button click | `interact` |

Assign sounds to these slots via **Settings > Sound**. The `hover` and `interact` slots are shared with the native menu bar. Any sound assigned there is also used for developer panel buttons.

---

### Log file

All events are appended to `~/Documents/ms_dev.log` as newline-delimited JSON:

```json
{"ts":"14:23:45","type":"print","msg":"Hello world"}
{"ts":"14:23:46","type":"macro","id":"superJump","label":"High Leap Assist"}
{"ts":"14:23:47","type":"key","key":"space","down":true}
{"ts":"14:23:48","type":"mouse","button":1,"down":false}
{"ts":"14:23:49","type":"step","msg":"[High Leap Assist] wait 600ms"}
```

History is loaded from this file whenever a panel is reopened. The **Clear** button in any panel truncates the file. The file lives outside the repository and is never committed.

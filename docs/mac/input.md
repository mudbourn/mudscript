# Input: Keyboard, Mouse & Camera

## Keyboard Actions

### `ms.press(key, mods)`

Sends a key-down event. Does not send key-up.

```lua
ms.press("w")
ms.press("shift")
ms.press("space")
ms.press("v", {"cmd"})        -- Cmd+V down
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `key` | string/number | — | Key name or numeric keycode. |
| `mods` | table | `{}` | Modifier keys, e.g. `{"cmd", "shift"}`. |

**Key names:** any single character, or named keys: `"space"`, `"escape"`, `"return"`, `"tab"`, `"left"`, `"right"`, `"up"`, `"down"`, `"shift"`, `"ctrl"`, `"alt"`, `"cmd"`, `"f1"`–`"f12"`. Numeric keycodes are also accepted.

---

### `ms.release(key, mods)`

Sends a key-up event.

```lua
ms.release("w")
ms.release("shift")
```

Same parameters as `ms.press`.

---

### `ms.forgetHeld(key)`

Drops a key from the macro-held ledger **without** sending a key-up. Returns `true` if an entry was cleared, `false` if the key was not being held by a macro.

```lua
ms.forgetHeld("w")
```

Every `ms.press` records the key so `ms.cancelMacros()` can release it later. That ledger normally clears itself on `ms.release`, but there is one case where you must not send the key-up: the player has physically pressed the same key you are holding. Sending it would cut their own input mid-game, while their hardware key-up releases the key for you anyway.

Leaving the entry in place instead is not an option — the next panic or disable would fire a stray key-up into the game long after your macro ended. `ms.forgetHeld` is the way out: surrender the key without touching the event stream.

```lua
if ms.keystate("w") then
    ms.forgetHeld("w")   -- player took over; their key-up will do the work
else
    ms.release("w")
end
```

---

### `ms.type(key, mods [, holdMs])`

Press + hold (default 15 ms) + release. Use for single keystrokes.

```lua
ms.type("e")
ms.type("space")
ms.type("escape")
ms.type("v", {"cmd"})         -- Cmd+V tap
ms.type("e", nil, 5)          -- 5 ms hold
```

---

### `ms.hold(key, mods, durationMs)`

Presses and holds a key. With a `durationMs`, it also reproduces OS key-repeat the way a real physical hold does — a synthetic key-down does not auto-repeat on its own, so without this a "hold to spam a key" step would only ever type one character. Without a `durationMs`, it just holds indefinitely, leaving the matching release to the caller (e.g. a movement hold paired with a later `ms.release`).

```lua
ms.hold("w", nil, 500)         -- hold W for 500ms, with repeat events, then release
ms.hold("space", nil)          -- hold space indefinitely — call ms.release("space") later
```

The first repeat begins after a 250 ms initial delay (macOS's default), then repeats every ~33 ms (~30/s), matching the default OS repeat rate.

---

### `ms.key(mods, key, swallow, pressFn, releaseFn)`

Registers a persistent keybind listener. Returns a handle with a `delete()` method.

| Parameter | Type | Description |
|-----------|------|-------------|
| `mods` | table | Modifier keys, e.g. `{"alt", "shift"}`. |
| `key` | string/number | Key name or keycode. |
| `swallow` | bool | `true` = consume the event (Roblox never sees it). |
| `pressFn` | function | Called on key-down. |
| `releaseFn` | function | Called on key-up. Optional. |

```lua
local handle = ms.key({"alt"}, "z", true, function()
    -- fires on alt+z down
end)

-- later, to unregister:
handle:delete()
```

Macro binds registered through `ms.bind.define` use this internally; you rarely need to call it directly.

---

### `ms.keyCombo(mods, keys, swallow, pressFn)`

Registers a chord: fires when the **last** key of `keys` goes down while every other key in the chord (and any required `mods`) is already held. Order-independent — whichever key completes the chord is the one that fires. Returns a handle with a `delete()` method.

```lua
local handle = ms.keyCombo(nil, {"v", "k"}, true, function()
    -- fires when V and K are both held, however they were pressed
end)

handle:delete()
```

`hs.hotkey` can't express a two-normal-key chord like V+K; `ms.keyCombo` bypasses it entirely by matching off the same live key-tracking table `ms.keystate` and the SOCD/trackpad holds read. A `keys` table with fewer than two entries falls back to a plain `ms.key` bind.

---

### `ms.copy(text)`

Sets the system clipboard contents.

```lua
ms.copy("/spawn l")
ms.type("v", {"cmd"})   -- paste
```

### `ms.toggle(key [, mods])`

Toggles a key: if the key is currently held, releases it; if not held, presses it. Useful for toggle-style actions (e.g. crouch toggle).

```lua
ms.toggle("c")          -- toggle crouch
ms.toggle("shift")      -- toggle sprint
```

### `ms.multiPress(keys [, delayMs [, mods]])`

Presses a sequence of keys in order, with an optional delay between each press. Useful for combo sequences or rapid-fire inputs.

```lua
ms.multiPress({"e", "e", "q"})           -- press E, E, Q
ms.multiPress({"1", "2", "3"}, 50)       -- press 1, 2, 3 with 50ms gaps
ms.multiPress({"a", "b"}, 100, {"shift"}) -- Shift+A, Shift+B
```

---

## Mouse Actions

### `ms.Mouse(operation, button, reference [, Unscaled,] x1, y1 [, x2, y2])`

Unified, named-constant mouse API. All arguments are validated at call time — typos error immediately.

#### Operations (first argument)

| Constant | Description |
|----------|-------------|
| `Move` | Move cursor to the position. No click. |
| `Click` | Move then click (down + wait + up). |
| `DoubleClick` | Two clicks in quick succession. |
| `TripleClick` | Three clicks in quick succession. |
| `Drag` | Click-and-drag from `(x1,y1)` to `(x2,y2)`. |
| `Press` | Move to position then send mouse-down only. |
| `Release` | Send mouse-up at the position without moving. |

#### Buttons (second argument)

`Left`, `Right`, `Center`, `Button4`, `Button5`

#### References (third argument)

| Constant | Coordinate origin |
|----------|-------------------|
| `Absolute` | Raw screen pixels. |
| `Mouse` | Offset from current cursor position. |
| `WindowTL` | From Roblox window top-left. |
| `WindowTR` | From Roblox window top-right. |
| `WindowBL` | From Roblox window bottom-left. |
| `WindowBR` | From Roblox window bottom-right. |
| `WindowCenter` | From Roblox window center. |
| `ScreenTL` | Offset from screen top-left. |
| `ScreenTR` | Offset from screen top-right. |
| `ScreenBL` | Offset from screen bottom-left. |
| `ScreenBR` | Offset from screen bottom-right. |
| `ScreenCenter` | Offset from screen center. |

`Window*` references scale `(x, y)` through the 1680×1044 → actual window size transform by default. Pass the `Unscaled` flag to use raw pixel offsets instead (see below).

#### `Unscaled` flag (optional, between reference and coordinates)

Pass the global constant `Unscaled` between the reference and the first coordinate to treat `(x, y)` as raw pixel offsets from the reference origin rather than REF-space scaled values. Only affects `Window*` references; ignored for `Absolute`, `Mouse`, and `Screen*`.

```lua
ms.Mouse(Click, Left, WindowTL, 900, 660)             -- REF-space (scaled to window)
ms.Mouse(Click, Left, WindowTL, Unscaled, 445, 37)    -- raw pixels from window TL
```

#### Examples

```lua
ms.Mouse(Click,   Left,  WindowTL, 900, 660)
ms.Mouse(Move,    Left,  Mouse,    0,   0)
ms.Mouse(Drag,    Left,  Absolute, 100, 100, 300, 300)
ms.Mouse(Press,   Left,  WindowTL, Unscaled, 467, 52)
ms.Mouse(Release, Right, WindowCenter, 0, 0)
```

---

### `ms.mouse(button, swallow, clickFn)`

Registers a persistent mouse-button listener. When the specified button is clicked, `clickFn` is called inside a coroutine.

| Parameter | Type | Description |
|-----------|------|-------------|
| `button` | number | Button number: `0` = left, `1` = right, `2+` = other. |
| `swallow` | bool | `true` = consume the click (the target app never sees it). |
| `clickFn` | function | Called when the button fires. |

```lua
ms.mouse(0, true, function()
    -- fires on left-click
end)

ms.mouse(1, true, function()
    -- fires on right-click
end)
```

---

### `ms.scroll(direction, clicks)`

Posts a scroll event at the current cursor position.

```lua
ms.scroll("up",    2000)
ms.scroll("down",  2000)
ms.scroll("left",  5)
ms.scroll("right", 5)
```

---

### `ms.resolvePoint(x, y, reference [, unscaled])`

Converts `(x, y)` in the given reference space to absolute screen coordinates. Used internally by `ms.Mouse` and `ms.pixelColor`. Useful when you need the resolved position for other purposes.

```lua
local ax, ay = ms.resolvePoint(900, 660, WindowTL)
local ax, ay = ms.resolvePoint(445, 37,  WindowTL, true)   -- unscaled
```

### `ms.moveMouse(x, y, ref [, durationMs])`

Moves the mouse cursor to the target position with smooth interpolation. The movement uses an ease-out curve for natural-looking motion.

```lua
ms.moveMouse(900, 540, "Absolute")           -- move to screen position, 200ms default
ms.moveMouse(900, 540, "WindowTL", 500)      -- move relative to window, 500ms duration
ms.moveMouse(840, 104, "Absolute", 100)      -- fast move (100ms)
```

Returns a timer object that can be cancelled with `timer:stop()`.

### `ms.dragPath(points, button [, ref [, delayMs]])`

Drags the mouse through a sequence of points. Presses at the first point, drags through each subsequent point, then releases.

```lua
-- Drag from (100,100) to (200,200) to (300,100)
ms.dragPath({{100,100}, {200,200}, {300,100}}, "Left", "Absolute")

-- Right-button drag with 20ms delay between points
ms.dragPath({{500,300}, {600,400}}, "Right", "WindowTL", 20)
```

### `ms.saveCursor()` / `ms.restoreCursor()`

Save and restore the mouse cursor position. Useful for macros that need to move the mouse and then return it to its original position.

```lua
ms.saveCursor()              -- remember current position
ms.Mouse(Click, Left, WindowTL, 900, 540)  -- click somewhere
ms.wait(100)
ms.restoreCursor()           -- move cursor back
```

---

### `ms.scrollBind(direction, fn)`

Registers a callback that fires whenever the scroll wheel moves in the given `direction` (`"up"` or `"down"`). Returns a handle with a `delete()` method. Only one callback can be registered per direction at a time — binding the same direction again replaces the previous callback.

```lua
local handle = ms.scrollBind("up", function()
    ms.type("e")   -- scroll up triggers E
end)

handle:delete()
```

Each callback runs in its own coroutine, so it can safely call `ms.wait` and other yielding functions.

---

### Gamepad — `ms.gamepadStart()` / `ms.gamepadStop()` / `ms.gamepadBind(button, fn)`

Reads gamepad input via a background helper process (`ms_gc_read`) and dispatches button presses to registered callbacks.

```lua
ms.gamepadStart()   -- start the background reader (no-op if already running)
ms.gamepadStop()    -- stop it and clear all registered callbacks

local handle = ms.gamepadBind("a", function()
    ms.type("space")   -- gamepad A button triggers Space
end)

handle:delete()
```

- **`ms.gamepadStart()`** launches the reader task if it isn't already running. It parses each JSON line the helper emits, tracking connect/disconnect events (`ms._gamepadConnected`) and routing `press` events to the callback registered for that button.
- **`ms.gamepadStop()`** terminates the reader task and clears all registered callbacks and connection state.
- **`ms.gamepadBind(button, fn)`** registers a callback for a named button. Requires `ms.gamepadEnabled` to be set — returns an inert handle (`delete()` is a no-op) otherwise. Automatically calls `ms.gamepadStart()` on first use if the reader isn't already running. Returns a handle with a `delete()` method that unregisters just that button's callback.

Each button callback runs in its own coroutine, same as `ms.scrollBind`. While a rebind capture is active, button-press events are routed to the capture instead of any bound callback.

---

## Camera Engine — `ms.cam`

The camera engine drives Roblox's camera using synthetic button-5 drag events, bypassing the user's mouse entirely. All macros that move the camera use this.

### `ms.cam.move(dy, dx)`

Post a single camera drag delta. Both values are in Roblox sensitivity units; the engine scales them by `cachedMult` to compensate for the user's configured sensitivity.

```lua
ms.cam.move(0,    -3145)   -- pan up sharply
ms.cam.move(-60,  0)       -- pan left
ms.cam.move(0,    8)       -- nudge down
```

Note: parameters are `(dy, dx)` — **vertical first, horizontal second**.

---

### `ms.cam.enable()` / `ms.cam.disable()`

Start or stop the camera engine. Called automatically by the app watcher when Roblox is focused/unfocused. You should not need to call these manually.

---

### `ms.cam.updateAnchor()`

Re-reads the Roblox window frame and recalculates the anchor point (window center) and the sensitivity multiplier. Called automatically on window move/resize. Can be called manually if camera moves are going to the wrong position.

---

### `ms.cam.updateMultiplier()`

Recalculates `ms.cam.cachedMult` from `CUR_CAM_SENS` and `REF_SENS`. Called automatically after sensitivity changes.

---

### `ms.cam.scheduleUpdate()`

Debounced `updateAnchor` — waits 0.5 s before calling it. Used by the UI watcher to avoid rapid recalculation during window resize animations.

---

### `ms.flick(dx, dy, opts)`

Posts a deterministic, tightly-bunched burst of camera deltas that sum exactly to `(dx, dy)` — a synchronous alternative to `ms.cam.sweep` for snap-turns and flicks where you want the whole movement to land in one uninterrupted burst rather than spread across an async pump.

```lua
ms.flick(1200, 0)                       -- flick right, delta count auto-derived from dx
ms.flick(-800, 40, { count = 12 })      -- flick left+down over exactly 12 deltas
ms.flick(600, 0,  { gapUs = 500 })      -- tighter spacing between deltas (500 µs)
```

Options (`opts`, all optional):

| Key | Default | Description |
|-----|---------|-------------|
| `count` | `max(1, round(\|dx\| / 100))` | Number of individual `ms.cam` deltas to split the movement into |
| `gapUs` | `ms._flickGapUs` or `1000` | Microseconds to sleep between each delta |

The total is split Bresenham-style so the emitted deltas sum to exactly `dx`/`dy` — no rounding drift even with an odd `count`. Unlike `ms.wait`, this runs synchronously via `hs.timer.usleep` and does **not** yield, so it blocks the calling coroutine for the full duration of the burst; it does not need to run inside an `ms.fn`-wrapped function the way `ms.wait` does.

---


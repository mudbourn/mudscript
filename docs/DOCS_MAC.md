# mudscript Utility Library — Reference

> **Scope:** everything exposed through the `ms` table and related globals in `ms_core.lua`.  
> **Macro file:** `ms_macros.lua` — loaded automatically on every reload; the only file you normally edit.

---

## 1. Macro File Structure

`ms_macros.lua` has four sections in order:

```lua
-- 1. Metadata (required)
ms.macroMeta = {
    name    = "My Macro Pack",   -- used as the profile folder name
    author  = "yourname",
    website = "https://...",
}

-- 1b. Target application (optional — default "Roblox")
ms.setTargetApp("Roblox")   -- macros enable when this app is focused; nil = global mode

-- 2. Pack settings (optional — declare before macro functions)
ms.settings.define({ key="myToggle", type="toggle", label="My Toggle",
    default=false, onChange=function(v) end })
ms.menu.define({ id="mySection", title="My Section", items={ ... } })
ms.features.hide("socd")

-- 3. Function definitions
local MyFunction = ms.fn(function()
    -- ...
end)

-- 4. Bind declarations
ms.bind.define("myMacro", MyFunction, { group="main", label="My Macro" })
```

See **Section 22** for the full User Settings & Menu API reference.

---

## 2. Declaring Macros — `ms.bind.define`

```lua
ms.bind.define(id, fn, opts)   -- preferred: function first, config last
ms.bind.define(id, opts, fn)   -- legacy order, still accepted
ms.bind.define(id, fn)         -- no opts
ms.bind.define(id, opts)       -- register without wiring a function
```

Both `fn` and `opts` are optional; types are detected automatically.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Unique identifier for this macro. Used in all API calls. |
| `fn` | function | The function to run when the macro fires. Wrap with `ms.fn()` if it uses `ms.wait`. |
| `opts` | table | Configuration table — all fields optional. |

### `opts` fields

| Field | Default | Description |
|-------|---------|-------------|
| `label` | auto ("Macro1", "Macro2", …) | Display name in the Settings menu. |
| `group` | `"main"` | `"main"` or `"optional"` appear in the menu. `nil` = hidden. |
| `enabled` | `true` | Initial enabled state. |
| `cooldown` | `1000` | Fire-based lockout in ms. Shared across the entire sub-item family. `0` = no cooldown. |
| `default` | `nil` | Default keybind: `{type="mouse", button=N}` or `{type="key", mods={…}, key="…"}` |
| `sub` | `nil` | Parent macro `id`. Makes this a sub-item of that parent. Parent must be defined first. |
| `mod` | `nil` | Default modifier key for this sub-item (e.g. `"alt"`, `"v"`). |
| `shared` | `nil` | Explicit cooldown group key. Overrides the auto-derived `"G_<rootId>"`. |
| `info` | `nil` | Description string written to `ms_macro_info.txt` (Settings › Macro Info). |

### Examples

```lua
-- Root macro with a mouse bind
ms.bind.define("superJump", myJumpFn, {
    group   = "main",
    label   = "High Leap Assist",
    default = {type="mouse", button=3},
    cooldown = 1500,
})

-- Root macro with a key bind
ms.bind.define("quickReset", QuickResetFunction, {
    group   = "optional",
    label   = "Quick Reset",
    default = {type="key", mods={"alt"}, key="escape"},
})

-- Disabled by default
ms.bind.define("spawnAlt", SpawnAltFunction, {
    group   = "optional",
    label   = "Load Second Account",
    default = {type="key", mods={"alt"}, key="="},
    enabled = false,
})
```

---

## 3. Sub-item System

Sub-items let a single root bind dispatch to different variants depending on which modifier key is held at fire time.

### Defining sub-items

> **Registration order matters.** `ms.bind.define` asserts that a sub-item's parent already exists in the registry. Always define the root bind before any sub-items. Sub-items of sub-items (two levels deep) work the same way.
>
> **LuaJIT upvalue note.** When a closure references a local function that is declared *after* the closure in the same chunk loaded via `setfenv`, LuaJIT can miscompile the reference as a global lookup instead of an upvalue. If a function `F` is defined on line 155 and a closure on line 140 tries to call `F()`, `F` will be `nil` at call time. The robust workaround is to look up `F` through `ms.bind._wires["id"]` at call time — a table field access is never affected by this issue.

```lua
-- Root bind must be defined before any sub-items that reference it.
-- For cross-references to functions defined later in the file, look them up
-- via ms.bind._wires at call time rather than capturing them as closure upvalues.
-- LuaJIT setfenv chunks can miscompile upvalue references across certain distances
-- as globals; _wires is a table access and is not subject to that issue.
ms.bind.define("superJump", function()
    if ms.modHeld("superThrow") then
        local fn = ms.bind._wires.superThrow   -- safe late-binding lookup
        if fn then fn() end
    else HighLeapAssistFunction() end
end, { group="main", label="High Leap Assist", default={type="mouse", button=3} })

-- Sub-items — fire when parent fires and their mod key is held.
-- These must be registered AFTER the parent ("superJump") because ms.bind.define
-- asserts that the parent id already exists in the registry.
ms.bind.define("superThrow", ThrowTrickFunction,     { sub="superJump",  label="Throw Trick", mod="alt" })
ms.bind.define("throwLow",   ThrowTrickFunction,     { sub="superThrow", label="Throw Low",   mod="v"   })
ms.bind.define("jumpHigh",   HighLeapAssistFunction, { sub="superJump",  label="Jump High",   mod="v"   })
ms.bind.define("jumpLow",    HighLeapAssistFunction, { sub="superJump",  label="Jump Low",    mod="x"   })
```

### Checking which sub-item should run — inside a function

```lua
-- ms.modHeld(id) — true if the sub-item's modifier is currently held
if ms.modHeld("superThrow") then ... end

-- ms.isSub(id) — true if this specific sub-item is the active one
--   Self-clears on match, so only one variant fires per call sequence.
--   Handles both modifier-key routing and independent-bind routing.
local function myFn()
    if ms.isSub("jumpHigh") then
        -- do high jump
        return true
    end
    if ms.isSub("jumpLow") then
        -- do low jump
        return true
    end
    -- default behavior
end
```

### Independent binds

When **Settings › Keybinds › Independent Binds** is enabled, sub-items can also have their own dedicated keybind configured from the menu. They then fire that sub-item directly, bypassing the parent's modifier check.

**UI in independent bind mode.** When this mode is active, sub-item rows in the Settings panel switch presentation: the independent bind becomes the primary pill (shown in accent colour), or an **"unbound"** warning pill appears if no independent bind has been set yet.

**Auto-clear on enable.** When independent binds is toggled on, any sub bind that conflicts with an existing root bind is automatically cleared so `rebind()` starts from a clean state.

**Auto-disable on clear.** If you clear a sub-item's independent bind while independent bind mode is active, that macro is automatically disabled — it has no way to fire.

### Two-level sub-items in the Settings panel

Sub-items that have their own sub-items (e.g. `throwLow` is a sub of `superThrow` which is itself a sub of `superJump`) appear as small dim chips below their parent sub-item row. Right-clicking a chip opens the same context menu as a regular sub-item row: **Change Modifier**, **Clear Modifier**, and (when independent binds is enabled) **Rebind Independent** / **Clear Independent Bind**.

### `ms.getMod(id)`

Returns the active modifier key for a sub-item — the user-configured value from `ms.modConfig`, or the code default from `opts.mod`, or `nil`.

---

## 4. Wrapping Functions — `ms.fn`

```lua
local MyFunction = ms.fn(fn)
local MyFunction = ms.fn(fn, false)  -- skip wrap (synchronous)
```

Wraps `fn` so it always runs inside a coroutine. Required for any function that calls `ms.wait`. Without it, `ms.wait` falls back to a blocking `usleep`.

```lua
local ThrowTrickFunction = ms.fn(function()
    ms.press("x")
    ms.wait(50)
    ms.release("x")
end)
```

Pass `false` as the second argument to skip wrapping (rarely needed).

**Cancellation:** every `ms.fn` coroutine is tracked. Calling `ms.cancelMacros()` — which happens automatically on every `ms.setMacros(0)` — marks all live coroutines as cancelled and prevents any pending `ms.wait` or `ms.sound` callbacks from resuming them. Keys and mouse buttons held at the time are released automatically.

---

## 5. Keyboard Actions

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

## 6. Mouse Actions

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

## 7. Camera Engine — `ms.cam`

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

## 8. Timing — `ms.wait`

```lua
ms.wait(milliseconds)
```

Yields the current coroutine for the given duration, then resumes. Non-blocking — the Hammerspoon event loop continues running while waiting.

```lua
ms.wait(50)    -- 50 ms
ms.wait(1)     -- 1 ms (minimum resolution ~1 ms)
ms.wait(0.5)   -- sub-millisecond durations accepted
ms.wait(2000)  -- 2 seconds
```

Must be called from a coroutine context (i.e. inside an `ms.fn`-wrapped function). Outside a coroutine it falls back to a blocking `usleep`.

> **Macro Monitor integration.** When the Macro Monitor panel is open, every `ms.wait` call produces a dim step trace entry in the log regardless of duration — there is no minimum threshold. See **Section 25** for the full list of functions that generate step traces.

### `ms.after(milliseconds, fn)`

Runs `fn` once after the given delay and returns the timer handle. Does not yield, so unlike `ms.wait` it is safe outside a coroutine — use it for background loops and deferred cleanup.

```lua
local t = ms.after(300, function() ms.release("w") end)
t:stop()   -- cancel before it fires
```

> **Units.** `ms.after` takes **milliseconds**, matching `ms.wait`. `hs.timer.doAfter` underneath it takes seconds, so a value copied from Hammerspoon examples is off by a factor of 1000. `ms.after(0.3, fn)` is not "300 ms" — it is a third of a millisecond, and in a self-rearming loop that means thousands of timers a second.

### Background loops

A loop built from `ms.after` outlives the macro that started it. It is not an `ms.fn` coroutine, so `ms.cancelMacros()` cannot reach it and `ms.setMacros(0)` will not stop it. Anything long-running needs three guards:

```lua
local Loop = {
    running = false,
    timer   = nil,
    gen     = 0,
}

local function start()
    if Loop.running then
        return
    end

    Loop.running = true
    Loop.gen     = Loop.gen + 1

    local myGen = Loop.gen

    local function tick()
        if not Loop.running or Loop.gen ~= myGen then
            return
        end

        if BindValidity ~= 1 or not ms._robloxActive then
            Loop.running = false
            Loop.timer   = nil
            stop()
            return
        end

        Loop.timer = ms.after(300, tick)
    end

    tick()
end
```

| Guard | Prevents |
|-------|----------|
| Generation counter | A timer still in flight from a previous run ticking into the current one |
| `BindValidity` / focus check | A cancelled or disabled macro leaving the loop running forever |
| Idempotent stop | Double-stops and stops with no matching start, both common when several macros share one loop |

Release any keys the loop is holding on every exit path, including the self-stop path — see `ms.forgetHeld` in **Section 5** for the case where the player has taken the key over.

### `ms.randWait(min, max)`

Waits a random duration between `min` and `max` milliseconds. Useful for adding human-like variation to macro timing.

```lua
ms.randWait(50, 150)   -- wait between 50 and 150 ms
ms.randWait(100, 300)  -- wait between 100 and 300 ms
```

### `ms.jitter(base, jitterMs)`

Waits `base` milliseconds plus or minus a random offset of `jitterMs`. More predictable than `randWait` while still adding variation.

```lua
ms.jitter(100, 20)   -- wait 80–120 ms (100 ± 20)
ms.jitter(500, 50)   -- wait 450–550 ms (500 ± 50)
```

### `ms.waitApp(appName [, timeout])`

Waits until the named application is running. Returns `true` if found, `false` on timeout (default 10 seconds).

```lua
local found = ms.waitApp("Roblox", 5000)
if found then ms.alert("Roblox launched!") end
```

### `ms.waitNotApp(appName [, timeout])`

Waits until the named application is no longer running. Returns `true` if the app exits, `false` on timeout.

```lua
ms.waitNotApp("Roblox")  -- wait for Roblox to close
```

---

## 9. State Queries

### `ms.keystate(key [, ...])`

Returns `true` if any of the named keys are currently held, according to the live key-tracking table.

```lua
ms.keystate("shift")
ms.keystate("w")
ms.keystate("w", "a", "s", "d")   -- true if any movement key is held
```

Pass `true` as the second argument to treat the first argument as a raw keycode:

```lua
ms.keystate(56, true)   -- checks shift by keycode
```

Mouse buttons are tracked in the same table and can be queried here by name: `leftclick`/`mouse1`, `rightclick`/`mouse2`, `middleclick`/`mouse3`, `mouse4`/`mouseback`, `mouse5`/`mouseforward`. For clearer intent, prefer `ms.mousestate` (below) — it accepts friendlier names and covers the same buttons.

---

### `ms.mousestate(button [, ...])`

Returns `true` if any of the named mouse buttons are currently held, mirroring `ms.keystate` for the pointer. Button state is tracked from startup, so this works without first registering an `ms.mouse` callback.

```lua
ms.mousestate("left")
ms.mousestate("right")
ms.mousestate("left", "right")   -- true if either is held
ms.mousestate()                  -- defaults to left
```

Accepted names (case-insensitive), with the button number in parentheses:

| Button | Names |
|--------|-------|
| Left (0) | `left`, `l`, `0` |
| Right (1) | `right`, `r`, `1` |
| Middle (2) | `middle`, `center`, `m`, `2` |
| Thumb back (3) | `back`, `thumb`, `thumb1`, `3` |
| Thumb forward (4) | `forward`, `thumb2`, `4` |

```lua
if ms.mousestate("back") then ms.type("z") end   -- thumb button → undo
```

> Thumb buttons only register if macOS delivers them as button 3/4. Vendor mouse software (Logitech Options, Razer Synapse, SteelSeries GG) that remaps the thumb buttons to keystrokes intercepts them before the event tap sees them, so they won't be tracked while that remapping is active.

---

### `ms.held(id)`

Returns `true` only if **every** identifier modifier of the bind `id` is currently held — used to route a shared trigger among multiple binds that claim it. A bind with no identifier modifiers (the fallback bind) always returns `false`.

```lua
if ms.held("sprint") then
    -- the modifiers that identify the "sprint" bind are all currently held
end
```

Reads the same effective bind config as `ms.bind.define` (via `ms.effectiveBind`), so it stays in sync with rebinds made from the settings panel.

---

### `ms.app()`

Returns the name of the frontmost application.

```lua
if string.find(ms.app(), "Roblox") then ... end
```

### `ms.appRunning(appName)`

Returns `true` if the named application is currently running.

```lua
if ms.appRunning("Roblox") then
    ms.alert("Roblox is running")
end
```

### `ms.appIsFront(appName)`

Returns `true` if the named application is the frontmost (active) application.

```lua
if ms.appIsFront("Roblox") then
    ms.type("e")  -- only type when Roblox is focused
end
```

### `ms.focus(appName)`

Activates (brings to front) the named application. Returns `true` on success, `false` if the app is not running.

```lua
ms.focus("Roblox")       -- switch to Roblox
ms.focus("Hammerspoon")  -- switch to Hammerspoon
```

### `ms.windowPos(appName)`

Returns the window position of the named application as `{x, y, w, h}`, or `nil` if the app is not running or has no window.

```lua
local pos = ms.windowPos("Roblox")
if pos then
    print("Window at " .. pos.x .. ", " .. pos.y)
    print("Size: " .. pos.w .. " x " .. pos.h)
end
```

---

### `ms.mousePos()`

Returns the cursor position in 1680×1044 reference-space coordinates relative to the Roblox window. Returns raw screen coordinates if Roblox is not found.

```lua
local x, y = ms.mousePos()
ms.alert(string.format("Mouse: %.0f, %.0f", x, y), 3)
```

---

### `ms.modHeld(id)`

Returns `true` if the modifier key configured for sub-item `id` is currently held.

```lua
if ms.modHeld("superThrow") then ThrowTrickFunction() end
```

---

### `ms.isSub(id)`

Returns `true` if sub-item `id` is the active variant for this invocation — either because it was fired by an independent bind, or because its modifier key is held. Self-clears on match.

```lua
if ms.isSub("jumpHigh") then
    -- high jump path
    return true
end
```

---

### `ms.getMod(id)`

Returns the active modifier key string for sub-item `id`, or `nil` if none is configured.

```lua
local mod = ms.getMod("superThrow")  -- e.g. "alt"
```

---

### `ms.getRobloxWin()`

Returns the main Roblox `hs.window` object, or `nil` if Roblox is not running.

---

### `ms.winCenter()`

Returns `(x, y)` screen coordinates of the center of the Roblox window (falls back to focused window).

---

### `ms.getScaled(targetX, targetY)`

Converts a 1680×1044 reference-space coordinate to absolute screen pixels, accounting for the actual Roblox window size and position.

```lua
local sx, sy = ms.getScaled(900, 660)
```

---

### `ms.pixelColor(x, y [, reference])`

Returns the colour of a single screen pixel at `(x, y)` in the given reference space. Uses the same coordinate system as `ms.Mouse`. `reference` defaults to `Absolute` if omitted.

Returns a table `{ r, g, b, a }` with integer values in `[0, 255]`, or `nil` if the position is off-screen or the capture fails.

```lua
local c = ms.pixelColor(900, 540, WindowTL)
if c then
    print(c.r, c.g, c.b)   -- e.g. 255  80  0
end

-- At absolute screen coordinates:
local c = ms.pixelColor(1200, 400)
```

---

### `ms.pixelMatch(x, y, reference, r, g, b [, tolerance])`

Returns `true` if the pixel at `(x, y)` is within `tolerance` of the target colour on every channel. `tolerance` defaults to `10`; all values are `[0, 255]`.

```lua
-- Is the pixel at WindowTL (900, 540) roughly orange?
if ms.pixelMatch(900, 540, WindowTL, 255, 80, 0) then
    -- ...
end

-- Tighter match for a specific UI element:
if ms.pixelMatch(445, 37, WindowTL, 12, 200, 64, 5) then
    -- ...
end
```

### `ms.waitPixel(x, y, ref, r, g, b [, tolerance [, timeout]])`

Waits until a pixel matches the expected color. Polls every 50ms. Returns `true` when matched, `false` on timeout (default 5 seconds).

```lua
-- Wait for a button to appear (green pixel at known position)
local found = ms.waitPixel(900, 540, WindowTL, 0, 255, 0, 10, 3000)
if found then ms.type("e") end
```

### `ms.waitNotPixel(x, y, ref, r, g, b [, tolerance [, timeout]])`

Waits until a pixel does NOT match the expected color. Inverse of `waitPixel`. Returns `true` when the pixel changes, `false` on timeout.

```lua
-- Wait for a loading screen to disappear (white pixel turns dark)
ms.waitNotPixel(960, 540, "Absolute", 255, 255, 255, 10, 10000)
```

---

## 10. Macro Control

### `BindValidity`

Global integer. `1` = macros active; `0` = macros disabled. All bind handlers check this before firing.

---

### `ms.setMacros(state [, silent])`

```lua
ms.setMacros(1)          -- enable
ms.setMacros(0)          -- disable + show alert
ms.setMacros(0, true)    -- disable silently
```

Enabling starts the camera engine. Disabling calls `ms.cancelMacros()`, clears `ms.keytrack`, cancels all running cooldown timers, and stops the camera engine.

---

### `ms.cancelMacros()`

Cancels all active `ms.fn` coroutines and releases any keys or mouse buttons currently held by macro presses. Called automatically on every `ms.setMacros(0)`.

Safe to call manually if you need to abort running macros without disabling the system.

```lua
ms.cancelMacros()
```

---

### App watcher behavior

The app watcher monitors focus changes and enables/disables macros based on the **target application** set via `ms.setTargetApp()`. By default this is `"Roblox"`. Pass `nil` for global mode — macros stay enabled regardless of the focused app.

| Event | Action |
|-------|--------|
| Target app activated | `BindValidity = 1`, camera enabled (Roblox only), enable notification queued |
| Target app activated (returning from a settings dialog) | `BindValidity = 1`, notification suppressed |
| Any other app activated | `ms.setMacros(0)` — disables and notifies |
| Hammerspoon activated while target was in front | `ms.setMacros(0, true)` — disables silently (settings dialog cycle) |
| Target app launched | Camera watcher set up (Roblox only) |

The in-game keys `/` (disable) and `Enter` (enable) toggle macros while the target app is focused (Roblox mode only).

---

## 11. Cooldown Helpers

### `ms.bind.group(id)`

Returns the cooldown group key for `id`. All macros in the same group share a single cooldown timer — firing any one of them locks out all others for the cooldown duration.

- If `opts.shared` is set on `id` or its root, that value is used directly.
- Otherwise auto-derives `"G_<rootId>"` by walking the `sub` chain.

```lua
local g = ms.bind.group("superThrow")  -- → "G_superJump"
```

---

### `ms.pause([id])` / `ms.resume([id])`

Pauses and resumes a running macro by id (the first argument to `ms.bind.define`). When paused, the macro's current `ms.wait()` expires but does not resume until `ms.resume()` is called. Any already-expired wait time is consumed — the macro picks up immediately from the next instruction.

Pass no argument to pause or resume all running macros.

```lua
ms.pause("throwTrick")     -- pause a specific macro
ms.wait(500)
ms.resume("throwTrick")    -- resume it

ms.pause()                  -- pause everything
ms.wait(100)
ms.resume()                 -- resume everything
```

> Cancelled macros cannot be resumed. Use `ms.cancelMacros()` to abort permanently.

---

### `ms.done(id)`

Manually clears the cooldown for `id`'s group before the timer expires. Useful at the end of a long macro that uses time-based internal logic rather than the cooldown timer.

```lua
ms.done("superJump")
```

---

## 12. Audio — `ms.sound`

### `ms.sound(path [, async [, device]])`

Plays a sound file.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `path` | — | A file path string or a `ms.sounds.*` table entry. Must be the **value**, not a variable name. |
| `async` | `true` | `true` = fire-and-forget. `false` = yield coroutine until playback completes. |
| `device` | `nil` | Output device name. `nil` = system default. |

**Three correct ways to pass a path:**

```lua
-- 1. A local variable holding a path built with SoundLib
local MySound = SoundLib .. "MySound.wav"
ms.sound(MySound)                     -- correct: pass the variable

-- 2. An inline path
ms.sound(SoundLib .. "MySound.wav")   -- correct: pass the concatenated string

-- 3. A discovered sound from ms.sounds
ms.sound(ms.sounds.alert)             -- correct: pass the table value
```

**Common mistake — passing a variable name as a string:**

```lua
local MySound = SoundLib .. "MySound.wav"
ms.sound("MySound")        -- WRONG: this is a string literal, not the variable
ms.sound("MySound.wav")    -- WRONG: filename only, not a full path
ms.sound("MySound", true)  -- WRONG: quoted name, async flag ignored because path fails
```

Passing a quoted name silently fails — `hs.sound` cannot find a file called `"MySound"` and returns nothing. Always pass the variable itself (no quotes) or the full path.

Volume is set automatically from `ms.soundVolume` (0–100).

---

### `ms._discoverSounds()`

Scans `~/.hammerspoon/sounds/` and populates `ms.sounds` — a table keyed by filename without extension. Called once at startup; call again if you add sound files without reloading.

Only audio files are indexed. `ms.soundExtensions` is the list (`wav`, `aiff`, `aif`, `mp3`, `m4a`, `caf`, `aac`), and `ms.isSoundFile(filename)` is the test — the same one the auto-sorter and the importer use, so a file cannot be indexed but unfiled or filed but unindexed.

```lua
-- After adding alert.mp3 to the sounds folder:
ms._discoverSounds()
ms.sound(ms.sounds.alert)
```

---

### `ms.playSlot(slotId)`

Plays the sound assigned to a named slot. Returns `true` if a sound was found and played, `false` otherwise.

Resolution runs in three steps, and the first that produces a file wins:

1. whatever `ms.soundAssign[slotId]` names, if it still resolves to a sound in the library
2. a file named `<slotId>.*` auto-discovered in `SoundLib`
3. the slot's default sample, as declared in `ms.soundSlots`

If all three come up empty and the slot declares a `fallback`, the whole sequence runs again for that slot. An assignment pointing at a sound that no longer exists is *skipped*, not treated as a path — so a stale assignment costs you the default sound, never silence.

Playback timing is recorded against the slot that was asked for, whichever slot's sample ended up playing.

Calls within 50 ms of the previous call for the same slot are silently suppressed to prevent double-play (e.g. a keyboard shortcut and the action's `fn` both firing simultaneously).

```lua
ms.playSlot("update")   -- plays whatever is assigned to the "update" slot
ms.playSlot("hover")    -- plays the menu hover sound
```

---

### Sound event slots

`ms.soundAssign` maps slot names to sound names from `ms.sounds`. Configured via **Settings › Sound**. Drop a file named after the slot (e.g. `hover.wav`) into `~/.hammerspoon/sounds/` for auto-assignment without any configuration.

**`ms.soundSlots` is the definition of the list below** — id, label, group, default sample (`d`), themed sample (`a`), and any `fallback`. It is the only place the built-in slots are enumerated. `ms.playSlot`, the custom-theming reset, the preset builder and the Sounds tab all derive from it and none of them keep a copy, so adding a slot is a single edit. Helpers: `ms.soundSlot(id)`, `ms.soundSlotChain(id)`, `ms.soundSlotDefaults()`, `ms.buildSoundPresets()`.

> **Loading-sequence slots:** `themeLoaded`, `load` and `launch` are the three loading-sequence slots. They are exempt from the startup sound gate — they can fire before the gate opens, while the loading screen is still active.

| Slot | Default sample | Fires when |
|------|----------------|------------|
| `themeLoaded` | `d_ThemeLoaded` | The theme has been applied on the loading screen |
| `load` | `d_LoadEnd` | Loading screen fades out |
| `launch` | `d_Launch` | First toast fires after loading completes |
| `updateAvailable` | `d_UpdateAvailable` | An update is found |
| `alert` | `d_Alert` | `ms.alert()` is called without `noDefaultSound = true` and `loadfinish == 1` |
| `enabled` | `d_MacrosOn` | Macros are enabled |
| `disabled` | `d_MacrosOff` | Macros are disabled |
| `toggleOn` | `d_ToggleOn` | A toggle is switched on |
| `toggleOff` | `d_ToggleOff` | A toggle is switched off |
| `update` | `d_Update` | A setting is successfully changed |
| `reset` | `d_Reset` | A reset action is confirmed |
| `interact` | `d_Interact` | A menu item is activated |
| `hover` | `d_Hover` | The cursor or keyboard moves to a new menu item |
| `back` | `d_Back` | Left arrow closes a submenu |
| `settingsOpen` | `d_SettingsOpen` | The settings panel or a developer panel opens |
| `settingsClose` | `d_SettingsClose` | The settings panel or a developer panel closes |
| `shutdown` | `d_Shutdown` | The exit curtain fades in on a shutdown |
| `restart` | — (falls back to `shutdown`) | The exit curtain fades in on a restart |

#### Reserved names

Every `d_*` and `a_*` name in the table above, plus its numbered preset variants (`a_Shutdown2` … `a_Shutdown9`), belongs to the theme system. Imported sounds are renamed away from these on the way in — `ms.safeSoundName(stem, prefix)` strips any `d_`/`a_`/`m_` prefix the file arrived with, re-prefixes it, and suffixes `-2`, `-3` … on collision. The dash matters: a bare trailing digit is how a preset variant is spelled, so a file called `Shutdown2.wav` would otherwise become preset 2's send-off. Nothing an import does can overwrite a shipped sample.

### `ms.setVolume(level)`

Sets the system output volume (0–100).

```lua
ms.setVolume(50)   -- set to 50%
ms.setVolume(0)    -- mute (by setting volume to 0)
```

### `ms.mute()` / `ms.unmute()`

Mute or unmute the system audio output.

```lua
ms.mute()          -- mute
ms.wait(1000)
ms.unmute()        -- unmute
```

---

## 13. Utilities

### `ms.screenshot([path])`

Takes a screenshot of the main screen and saves it to a file. Returns the file path, or `nil` on failure.

```lua
local path = ms.screenshot()                          -- save to Desktop with timestamp
local path = ms.screenshot("~/Desktop/test.png")      -- save to specific path
```

### `ms.clipChanged(callback)`

Watches for clipboard changes and calls the callback when the clipboard content changes. Returns a watcher object that can be stopped with `watcher:stop()`.

```lua
local watcher = ms.clipChanged(function()
    local content = hs.pasteboard.getContents()
    print("Clipboard changed: " .. tostring(content))
end)

-- Later, stop watching:
watcher:stop()
```

### `ms.notify(title [, subTitle [, infoText]])`

Shows a native macOS notification. Unlike `ms.alert` (which is a toast overlay), this uses the system notification center.

```lua
ms.notify("mudscript", "Macros enabled", "Ready to go")
ms.notify("Update available", "", "v1.4.0 is ready to install")
```

---

## 14. Settings & Defaults

### `ms.saveSettings()`

Writes all current runtime state to `ms_settings.json`. Called automatically after every settings menu action.

---

### `ms.loadSettings()`

Reads `ms_settings.json` (falls back to `ms_settings_default.json`, then auto-builds from registry). Applies the loaded values to the live runtime state.

---

### `ms.reloadSettings()`

Convenience wrapper that runs the full settings-reload sequence in one call: `loadSettings` → rebind → cam anchor → cam multiplier → SOCD → play update sound → show confirmation alert. Called by both the Settings menu item and the `alt+]` hotkey.

---

### `ms.saveDefault()`

Promotes the current `ms_settings.json` to `ms_settings_default.json`. Archives the previous default to `backups/` with a timestamp.

---

### `ms.resetToDefault()`

Clears all per-macro customisations (`bindConfig`, `subBinds`, `modConfig`, `cooldowns`), applies `ms_settings_default.json` as a full replacement, saves back to `ms_settings.json`, and rebinds everything. Returns `true` on success.

Unlike `ms.loadSettings()`, this is a **replace** — any custom keybind or cooldown not present in the default file is removed, not preserved.

---

### `ms._applySettings(data)`

Internal. Applies a decoded settings table to live runtime state. You do not need to call this directly.

---

### Settings files

| File | Purpose |
|------|-------|
| `data/ms_settings.json` | Current user settings — written on every change |
| `data/ms_settings_default.json` | The "reset to default" target |
| `data/ms_theme.json` | UI theme — colors, font, border radius, UI Frame Cosmetic |
| `backups/` | Timestamped archives of previous defaults |

Settings and theme files live in `~/.hammerspoon/data/`. They are gitignored — each install generates its own. Existing files at the old root location are automatically migrated to `data/` on the first reload after upgrading.

### User settings persistence

Settings declared with `ms.settings.define` are persisted under a `user` sub-table inside `data/ms_settings.json`:

```json
{
  "sensitivity": 1.8,
  "user": {
    "myToggle": true,
    "mySlider": 120
  }
}
```

`ms.settings.get(key)` reads this value. `ms.settings.set(key, value)` writes it, saves the file, and fires `onChange`.

---

## 15. SOCD Engine

Simultaneous Opposing Cardinal Directions cleaning. When enabled, prevents both keys in an axis pair (`W`/`S`, `A`/`D`) from being registered as held at the same time.

### `ms.socdMode`

| Value | Behavior |
|-------|----------|
| `"lastWins"` | The most recently pressed key wins; releases the opposite. On release, re-presses the opposite if still physically held. *(default)* |
| `"firstWins"` | The first key pressed wins; the second is swallowed. |
| `"neutral"` | Both keys are released when both are held simultaneously. |

---

### `ms.socdStart()` / `ms.socdStop()`

Start or stop the SOCD eventtap listener. Use `ms.socdApply()` instead to respect the current `ms.socdEnabled` setting.

---

### `ms.socdApply()`

Starts or stops the SOCD listener based on `ms.socdEnabled`. Call this after changing `ms.socdEnabled` or `ms.socdMode`.

---

## 16. Trackpad / Pen Mode

When enabled, re-routes root macro binds through `ms.trackpadBindOverrides` instead of their normal `default` bind. The default overrides move `superJump` from mouse button 3 to a keyboard key.

```lua
-- Defined at the top of ms_core.lua; edit to change trackpad bind overrides:
ms.trackpadBindOverrides = {
    superJump = {type="key", mods={}, key="k"},
}
```

The trackpad hold listeners (`ms._trackpadLeftListener`, `ms._trackpadRightListener`) simulate a held left or right mouse button while their configured key is held. Hold keys are set via Settings › Trackpad Hold Keys; defaults are `n` (left) and `j` (right).

---

## 17. Profiles

A profile is a folder in `~/.hammerspoon/profiles/<name>/` containing `ms_macros.lua` and optionally `ms_settings.json`, `ms_settings_default.json`, and `ms_theme.json`.

**Switching profiles** (Settings › Profiles):
1. Archives the active `ms_macros.lua` + settings files into `profiles/<currentName>/`.
2. Copies the target profile's files into the active positions.
3. Reloads after 3 seconds.

**Importing a profile** (Settings › Profiles › Import Profile):
- Opens a file picker for `.mspkg` files.
- The package is extracted, `ms_macros.lua` is security-audited, and the full bundle is installed into `profiles/<name>/`.
- Bundled sounds are copied into `~/.hammerspoon/sounds/` automatically. Files that already exist are never overwritten.

**Exporting a profile** (Settings › Profiles › Export Profile):
- Packages the current active profile as a `.mspkg` file and saves it to `~/Downloads/`.
- Reveals the file in Finder on completion.
- Sounds referenced in `ms.soundAssign` that came from `ms.importedSounds` are bundled automatically.

### .mspkg format

A `.mspkg` file is a standard zip archive with a defined internal layout:

```
ms_macros.lua                  (required)
ms_settings.json               (optional — current keybinds, mods, sensitivity, sound slots)
ms_settings_default.json       (optional — pack's preferred defaults)
ms_theme.json                  (optional — pack's theme)
sounds/                        (optional — bundled sound files)
```

Any sounds in `sounds/` are added to the user's library on import. If a sound with the same filename already exists it is skipped.

**Security:** both import and profile switch run `auditMacros()` on `ms_macros.lua` before any disk operations. A file that fails the static scan is rejected with an alert and never activated.

---

## 18. Utility Functions

### `ms.alert(msg [, duration [, noDefaultSound]])`

Displays a floating toast notification on screen. Up to 4 alerts stack vertically with animated entry/exit.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `msg` | — | String to display. `\n` for line breaks. |
| `duration` | `2` | Seconds before the toast fades out. |
| `noDefaultSound` | `false` | Pass `true` to suppress the automatic `alert` slot sound for this call. |

```lua
ms.alert("Macros: ENABLED", 3)
ms.alert("Multi-line\nMessage", 5)
ms.alert("Silent confirmation", 2, true)   -- no alert sound
```

### `ms.alert.dismissAll()`

Instantly clears all active toasts without animation. Used internally by the macro state notification system to cut off a previous ENABLED/DISABLED toast before showing the new one.

---

### `ms.debugTarget()`

Prints target window info (resolution, position, aspect ratio, sensitivity) to the Hammerspoon console and shows alerts. Also warns if the aspect ratio is too narrow for macros to work correctly. Available as a Lua call; the **Settings › Developer** button now opens the **Window Monitor** instead.

---

## 19. Global Hotkeys

These hotkeys only fire when the **target application** is focused (set via `ms.setTargetApp()`). They are silently ignored in all other apps.

| Hotkey | Action |
|--------|--------|
| `alt+[` | Quick Reload — granular reload of macros/theme/settings/UI per the Quick Reload dropdown options |
| `alt+]` | Full Reload — tears down and restarts Hammerspoon (`ms.restart()`, falling back to `hs.reload()`) |
| `alt+p` | Toggle the Settings panel |
| `alt+o` | Toggle Octane Mode |
| `alt+F10` | Emergency reset — disables macros immediately |

### Tap resilience

Every hotkey runs on its own `hs.eventtap`. macOS disables an event tap whose callback overruns its time budget (`kCGEventTapDisabledByTimeout`), and a disabled tap is silent — the bind simply stops working, with no error, until Hammerspoon reloads.

Two mechanisms keep that from happening:

- **Handlers run off the tap callback.** A hotkey action is deferred to the next runloop turn rather than called inline, so the callback returns immediately no matter how much work the action does. The enable/disable/toggle actions play a sound, raise an alert and refresh the UI, which is more than enough to trip the timeout.
- **The watchdog revives disabled taps.** `ms._tapWatchdog` polls every 2 seconds and restarts any tap in `ms._resilientTaps` that has been disabled. Hotkey taps register themselves as they are created in `ms._bindHotkeys`, and rebinding drops the previous generation from the list.

### Latch recovery

A hotkey fires on key-down and arms again on key-up. If that key-up never arrives the bind stays latched down and never fires again — the failure mode behind "the macro toggles stopped re-enabling my macros."

A key-up can go missing when the tap is disabled mid-hold, when focus moves to an app that swallows it, or when `ms.setMacros(0)` clears `ms.keytrack` underneath the hold.

Two recoveries cover it:

- A key-down that is **not** an autorepeat proves the key came back up at some point, so any latch still standing is stale and gets cleared before the fire check. A 10-second age ceiling backstops anything the autorepeat flag misses.
- When the watchdog revives a hotkey tap, all latches and cooldowns are cleared — every event during the dead window was dropped, so none of that state can be trusted.

Neither recovery can double-fire a bind: a genuine held key produces autorepeat key-downs, which are left latched.

### Octane Mode — `ms.octane`

A low-overhead performance toggle, bound to `alt+o`. Octane Mode strips logging, animations, idle pollers, and (optionally) sounds while macros keep running unchanged — for when the developer panels and UI polish aren't worth their overhead.

```lua
ms.octane.on()       -- enable
ms.octane.off()      -- disable
ms.octane.toggle()   -- flip current state
```

Turning it on:

- Pauses all `ms.dev.log` channels
- Stops idle pollers (mouse, shell mouse, window spy)
- Stops the menu hover watcher
- Forces Window Monitor element-inspect off (expensive pixel + AX reads)

Turning it off restores all of the above — logging resumes, pollers restart for any panel that's currently active, and the menu hover watcher restarts if the menu is visible.

The toggle state (`ms._octaneMode`) persists across reloads via settings, so it's re-applied automatically on load if it was left on. A separate **Octane mute sounds** setting (`ms._octaneMuteSounds`) can additionally silence sound playback while Octane is active, independent of the master toggle.

---

## 20. Global Constants

### Camera / scaling

| Constant | Value | Description |
|----------|-------|-------------|
| `REF_W` | `1680` | Reference resolution width used for coordinate scaling |
| `REF_H` | `1044` | Reference resolution height |
| `REF_SENS` | `1.5` | Reference camera sensitivity (used to derive `cachedMult`) |
| `CUR_CAM_SENS` | *(user setting)* | Current in-game sensitivity. Set via Settings › Camera Sensitivity |

---

### Target application

| API | Description |
|-----|-------------|
| `ms.setTargetApp(name)` | Set the target app by bundle name (e.g. `"Roblox"`, `"Minecraft"`). Pass `nil` for global mode — macros stay enabled regardless of focused app. Default: `"Roblox"`. |
| `ms.getTargetWin()` | Returns the target app's main window, or `nil` if the app isn't running. Fallback to `hs.window.focusedWindow()` in coordinate functions. |
| `ms.app()` | Returns the bundle name of the currently focused app. |

Call `ms.setTargetApp()` at the top of `ms_macros.lua`, right after `ms.macroMeta`. The app watcher, window lookups, and focus restoration all follow this setting.

---

### `ms.Mouse` named constants

These are plain globals available from `ms_macros.lua`.

**Operations:** `Move`, `Click`, `DoubleClick`, `TripleClick`, `Drag`, `Press`, `Release`

**Buttons:** `Left`, `Right`, `Center`, `Button4`, `Button5`

**References:** `Absolute`, `Mouse`, `WindowTL`, `WindowTR`, `WindowBL`, `WindowBR`, `WindowCenter`, `ScreenTL`, `ScreenTR`, `ScreenBL`, `ScreenBR`, `ScreenCenter`

**Flag:** `Unscaled` (`true`) — pass between the reference and the first coordinate in `ms.Mouse` to use raw pixel window offsets instead of REF-space scaled values.

---

### Sound

| Constant | Description |
|----------|-------------|
| `SoundLib` | Path to `~/.hammerspoon/sounds/` (trailing slash included) |
| `ms.sounds` | Table of discovered sounds, keyed by filename-without-extension |
| `ms.soundEnabled` | Master on/off (bool) |
| `ms.soundVolume` | Volume 0–100 |
| `ms.soundAssign` | Per-slot sound overrides: `{ load=name, update=name, hover=name, … }`. See §12 for all slot names. |
| `ms._updateManifestURL` | URL of the `MANIFEST.json` used by the update system. Points to the GitHub repo by default. |

---

### Internal state (read-only — do not modify directly)

| Variable | Description |
|----------|-------------|
| `BindValidity` | `1` if macros are active, `0` if disabled |
| `ms.keytrack` | Live key-held table: `{[keycode] = true/false}` |
| `ms.running` | Active cooldown timers: `{[groupId] = timerHandle}` |
| `ms.binds` | Enabled state overrides per id |
| `ms.bindConfig` | User keybind overrides per root id |
| `ms.modConfig` | User modifier key overrides per sub-item id |
| `ms.subBinds` | Independent bind configs per sub-item id |
| `ms.cooldowns` | User cooldown overrides per id |
| `ms.registry._defs` | Full definition table by id |
| `ms.registry._defList` | Ordered list of all ids as declared |
| `ms.bind._wires` | Registered functions by id |


## 21. System Integrity & Updates

### Overview

The system integrity check detects unauthorised modifications to `ms_core.lua` by comparing its SHA-256 hash to a stored baseline. The update system fetches a new `ms_core.lua` from GitHub, verifies its RSA-2048 signature and hash before installing, backs up the old file, and reloads automatically.

The trusted hash is stored in `~/.hammerspoon/data/.ms_trusted_hash` — one line, 64 hex characters. It is seeded automatically from `MANIFEST.json` on a clean install, and updated after every successful update. Normal reloads never change it.

> **Note:** `ms.integrity` is read-only from `ms_macros.lua`. Macro code cannot call `deleteTrustedHash()` or `writeTrustedHash()`. Use **Settings › Developer › Trust Current Version** for all trust management.

---

### `ms.integrity.check()`

Hashes the live `ms_core.lua` and compares it to the stored baseline.

Returns three values: `status, currentHash, trustedHash`

| `status` | Meaning |
|----------|--------|
| `"trusted"` | File matches the stored baseline |
| `"mismatch"` | File has changed since it was last trusted |
| `"uninitialized"` | No baseline has been stored yet |

```lua
local status, cur, trusted = ms.integrity.check()
if status == "mismatch" then
    ms.alert("ms_core.lua has changed!", 6)
end
```

---

### `ms.integrity.hashFile(path)`

Synchronously SHA-256 hashes a file via `shasum -a 256`. Returns the 64-character lowercase hex string, or `nil` on failure.

---

### `ms.integrity.readTrustedHash()` / `ms.integrity.writeTrustedHash(hash)`

Read or write the baseline hash file at `~/.hammerspoon/data/.ms_trusted_hash`.

---

### `ms.integrity.trustCurrent()`

Seals the running `ms_core.lua` as the new trusted baseline. Writes its hash to `.ms_trusted_hash` and shows a confirmation alert.

Available via **Settings › Developer › Trust Current Version**. The item is greyed out when the file already matches the stored hash.

---

### `ms.integrity.update()`

Full async update flow. Triggered via **Settings › Help › Check for Update**.

1. Fetches `MANIFEST.json` from `ms._updateManifestURL` over HTTPS (HTTP is rejected)
2. Verifies the RSA-2048 signature in the manifest against the built-in public key — aborts on invalid signature
3. Downloads `ms_core.lua` from the `url` field in the manifest
4. Compares the downloaded file's SHA-256 to the `sha256` field — installs regardless (logs a warning if stale)
5. Backs up the current `ms_core.lua` to `backups/ms_core_<timestamp>.lua.bak`
6. Installs the new file, updates `.ms_trusted_hash`, re-stamps the local `MANIFEST.json`, reloads after 3 seconds

---

### MANIFEST.json format

```json
{
  "version": "1.2.3",
  "sha256": "<64-char lowercase hex of ms_core.lua>",
  "url":    "https://raw.githubusercontent.com/you/repo/main/ms_core.lua",
  "signature": "<RSA-2048 SHA-256 signature of the sha256 field, base64-encoded>"
}
```

**The `signature` field is generated automatically** by the GitHub Actions workflow (`.github/workflows/release.yml`) whenever `ms_core.lua` is pushed to `main`. You do not sign manually.

To stamp the hash and bump the version locally before pushing:

```sh
bash bin/make_release.sh [version]
```

---

### `ms._updateManifestURL`

Pre-configured to point to the GitHub repository's `MANIFEST.json`. Override in `ms_core.lua` if self-hosting:

```lua
ms._updateManifestURL = "https://raw.githubusercontent.com/you/repo/main/MANIFEST.json"
```

---

### Release workflow

The GitHub Actions workflow (`.github/workflows/release.yml`) triggers on any push that touches `ms_core.lua` or `ms_core.ahk` (path filter: `paths: [ms_core.lua, ms_core.ahk]`). When triggered it always stamps — there is no step-level condition gating the stamp on which file changed:

1. Computes the SHA-256 of `ms_core.lua`
2. Signs it with the RSA private key stored in GitHub Secrets (`MS_SIGNING_KEY`)
3. Commits an updated `MANIFEST.json` with the new hash and signature

The public key is embedded in `ms_core.lua` (`ms._updatePublicKey`). The private key never leaves GitHub Secrets.

**Rotating the signing key** — if the private key is ever compromised or needs replacing:

```bash
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem
```

Paste the contents of `public.pem` into `ms._updatePublicKey` in `ms_core.lua`, then replace the `MS_SIGNING_KEY` GitHub Secret with `private.pem`. The next push that touches `ms_core.lua` will sign `MANIFEST.json` with the new key automatically.

---

## 22. User Settings & Menu API

Macro packs can declare their own settings, panel sections, and hide unused built-in features. These calls belong in the **Pack Settings** zone of `ms_macros.lua` — after `ms.macroMeta`, before macro functions.

---

### `ms.settings.define(def)`

Registers a setting or visual item in the **Settings** section of the panel. Items appear in declaration order.

**Common fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | `"toggle"` \| `"slider"` \| `"seg"` \| `"action"` \| `"soundSlot"` \| `"group"` \| `"divider"` \| `"groupLabel"` |
| `key` | yes (except divider/groupLabel) | Unique identifier. Used for storage and `ms.settings.get`. For `soundSlot` items the key names the sound slot; `ms.settings.get` returns the currently assigned sound name rather than a value from settings storage. |
| `label` | — | Row label shown in the panel. |
| `hint` | — | Optional subtitle shown below the label. |
| `save` | — | `false` to skip persisting to `ms_settings.json`. Default: `true`. |
| `default` | — | Initial value used when no saved value exists. |
| `onChange(value)` | — | Called when the user changes the value. Also called once at startup with `default` — **only if `default` is not `nil`**. If a saved value exists, a second call follows with the saved value. |

**Type-specific fields:**

| Type | Extra fields |
|------|-------------|
| `slider` | `min`, `max`, `step`, `unit` (display string e.g. `"ms"`) |
| `seg` | `options = { {label, value}, ... }` |
| `action` | `btnLabel`, `danger` (bool), `onAction()` |
| `group` | `items = { ... }` (array of nested item definitions) |
| `groupLabel` | `label` (the heading text) |

#### `type = "soundSlot"`

Registers a user-defined sound event slot that appears in **Settings › Sound** alongside the built-in slots (`hover`, `update`, `settingsOpen`, etc.). The user assigns an audio file to the slot from the sound picker.

```lua
ms.settings.define({
    key   = "myHitSound",
    type  = "soundSlot",
    label = "Hit Sound",
})
```

Play the assigned sound at runtime:

```lua
ms.playSlot("myHitSound")   -- plays whatever the user assigned
```

`ms.settings.get("myHitSound")` returns the currently assigned sound name (from `ms.soundAssign`), or `default` if nothing has been assigned. `ms.settings.set` is not supported for `soundSlot` keys — use the Sound section UI to assign sounds.

`soundSlot` items can also be declared inside `ms.menu.define` item lists; they appear in the custom section **and** are extracted into the Sound section automatically.

---

#### `type = "group"`

A collapsible group of nested setting items. Requires an `items` array. The group renders as a labelled, expandable container in the settings panel. Nested items support the same types as top-level `ms.settings.define` entries.

```lua
ms.settings.define({
    key   = "advancedGroup",
    type  = "group",
    label = "Advanced",
    items = {
        { type = "toggle", key = "debugMode",  label = "Debug Mode",  default = false,
          onChange = function(v) end },
        { type = "slider", key = "frameDelay", label = "Frame Delay",
          min = 0, max = 100, step = 1, unit = "ms", default = 16,
          onChange = function(v) end },
    },
})
```

**Examples:**

```lua
-- Toggle
ms.settings.define({
    key = "fastMode", label = "Fast Mode", type = "toggle",
    default = false,
    onChange = function(v)
        -- v is true or false
    end,
})

-- Slider
ms.settings.define({
    key = "holdTime", label = "Hold Duration", hint = "Milliseconds",
    type = "slider", min = 10, max = 500, step = 5, unit = "ms",
    default = 100,
    onChange = function(v) end,
})

-- Segmented control
ms.settings.define({
    key = "jumpStyle", label = "Jump Style", type = "seg",
    options = {
        { label = "Low",    value = "low"    },
        { label = "Normal", value = "normal" },
        { label = "High",   value = "high"   },
    },
    default = "normal",
    onChange = function(v) end,
})

-- Action button
ms.settings.define({
    key = "runCalibration", label = "Calibration",
    type = "action", btnLabel = "Run",
    onAction = function() ms.alert("Calibrating…", 2, true) end,
})

-- Visual divider
ms.settings.define({ type = "divider" })

-- Group label
ms.settings.define({ type = "groupLabel", label = "Timing" })
```

---

### `ms.settings.get(key)`

Returns the current value of a user setting, or its declared `default` if no value has been saved. Safe to call inside `ms.fn()` macro bodies at any time.

```lua
local t = ms.settings.get("holdTime")   -- number
local f = ms.settings.get("fastMode")   -- boolean
```

---

### `ms.settings.set(key, value)`

Programmatically updates a user setting. Validates the value, persists to `data/ms_settings.json` (unless `save = false`), and fires `onChange`.

```lua
ms.settings.set("holdTime", 200)
```

---

### `ms.menu.define(def)`

Registers a custom panel section that appears **below the Tools section** in declaration order.

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique section identifier. |
| `title` | yes | Header text shown in the panel. |
| `icon` | — | Emoji prepended to the title. |
| `items` | yes | Array of item definitions — same fields as `ms.settings.define`. |

Items inside `items` with a `key` are automatically reachable via `ms.settings.get` / `ms.settings.set`.

`onAction` on `action` items inside `ms.menu.define` is validated and must be a function (same as in `ms.settings.define`). All other item fields behave identically to `ms.settings.define` entries.

```lua
ms.menu.define({
    id = "combatOptions", title = "Combat Options", icon = "⚔",
    items = {
        { type = "toggle",     key = "autoParry",   label = "Auto Parry",   default = false,
          onChange = function(v) end },
        { type = "divider" },
        { type = "slider",     key = "parryWindow", label = "Parry Window",
          min = 10, max = 200, step = 5, default = 80, unit = "ms",
          onChange = function(v) end },
    },
})
```

---

### `ms.features.hide(name)`

Hides a built-in panel feature for the current macro pack session. Purely cosmetic — the underlying system keeps working. The item reappears if the call is removed and Hammerspoon reloads.

```lua
ms.features.hide("sensitivity")       -- Camera Sensitivity slider in Tools
ms.features.hide("socd")              -- SOCD Cleaning + Mode rows in Tools
ms.features.hide("trackpad")          -- Trackpad / Pen Mode row in Tools
ms.features.hide("independentBinds")  -- Independent Binds row in Tools
```

> `"sound"` and `"profiles"` cannot be hidden — they are required for core functionality.

---

### `ms.setClickLevel(n)` *(internal)*

> **Internal API.** `ms.setClickLevel` was a legacy bridge function and is not part of the public API. Do not call it from macro packs. To expose a click-level setting, use `ms.settings.define` with a `seg` type and manage the value in your own `onChange` callback.

---

## 23. Theme System

The panel UI is fully themeable via `~/.hammerspoon/data/ms_theme.json`. Edit the file directly, then use **Developer › Reload Theme** in the settings panel (or `hs.reload()`) to apply changes.

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
| `accent` | `#6b8c3a` | Primary accent — active borders, chevrons |
| `accentHi` | `#8db84e` | Accent highlight (focus, flash) |
| `success` | `#7aa63c` | Success state (active profile pill) |
| `dangerBg` | `#1c130f` | Danger element background |
| `danger` | `#c0492e` | Danger foreground (destructive buttons) |
| `warning` | `#c4a030` | Warning / notice colour |
| `text` | `#d4cfb6` | Primary text |

---

### `radius`

Integer, `0`–`40`. Controls `--radius` (and derives `--radius-s` as `radius - 1`). Default: `8`.

```json
{ "radius": 8 }
```

---

### `windowRadius`

Integer, `0`–`40`. Optional override for the rounded corner applied to each webview panel window frame (via `ms.theme.applyWindowRadius`). When unset the window frame follows the theme `radius` (the Appearance "Corner radius" value), so the frame and the inner content round to the same value. Set this only to make the window frame differ from the content radius.

```json
{ "windowRadius": 8 }
```

---

### `fadeMs`

Integer, `0`–`500`. Duration in milliseconds for panel fade-in / fade-out animations. Affects the settings panel, all four developer panels, and the startup loading screen. Set to `0` to disable fades completely. Default: `250`.

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

Supported file extensions: `.ttf`, `.otf`, `.woff`, `.woff2`. If a file path is given, a `@font-face` rule is injected dynamically. The font name in CSS falls back to `Almendra → Palatino → Georgia → serif`.

---

### `ms.loadTheme()`

Reads and validates `data/ms_theme.json`. Called automatically at startup after `ms.loadSettings()`. Also triggered by **Developer › Reload Theme** in the panel.

---

## 24. Capability Detection — `ms.has`

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
| `"userSettings"` | `ms.settings.define` API is present — use for version compatibility |
| `"userMenu"` | `ms.menu.define` API is present — use for version compatibility |
| `"integrity"` | `ms_core.lua` matches its trusted hash (system integrity) (`ms.integrity.check() == "trusted"`) |

> **Note:** `"integrity"` runs a `shasum` check and is slightly heavier than the others. Avoid calling it inside a hot macro loop.

---

## 25. Developer Tools — `ms.dev`

Four floating panels for live monitoring and interactive debugging. Open them from **Settings › Developer** or call the API directly. All panels share the active `data/ms_theme.json` theme — colors, font, and radius update automatically when the panel first loads.

The panels open near the top-right of the screen, staggered horizontally so they don't stack exactly on top of each other: Console is at the rightmost position, Macro Monitor 30 px further left, Input Monitor 60 px further left, and Window Monitor 90 px further left. All four panels fade in when opened and fade out when closed (150 ms, 6 steps). The open/close state is set immediately so `toggle()` works correctly during the animation.

> `ms.dev` is not accessible from `ms_macros.lua`. These tools are for the developer only.

---

### Console — `ms.dev.console`

A 360×640 REPL panel. Captures all `print()` output, errors, macro fires, and execution results as they happen.

- **Input field** — type any Lua expression or statement, press Enter or Run. Return values appear in green; errors in red.
- **KEY and MOUSE badges** — key and mouse events appear inline as styled type badges: amber **KEY** and orange **MOUSE**. Consecutive same-type entries are collapsed — only the first KEY badge appears until a MOUSE or MACRO entry interrupts, after which the next KEY badge is shown again. Full event detail (key names, button, position) is in the Input Monitor.
- **Toolbar buttons** — open Macro Monitor and Input Monitor without leaving the console.

```lua
ms.dev.console.show()
ms.dev.console.hide()
ms.dev.console.toggle()
```

---

### Macro Monitor — `ms.dev.watcher`

A floating panel. Shows every macro execution with timestamp and label as it fires. Also surfaces `print()` output and errors.

**Step traces** — when the Macro Monitor is open, every action call automatically appends a dim step trace row. The following calls all produce traces:

| Call | Trace format |
|------|-------------|
| `ms.wait(n)` | `wait Nms` (all durations, no threshold) |
| `ms.press(key)` | `↓ key` |
| `ms.release(key)` | `↑ key` |
| `ms.type(key)` | `type key` |
| `ms.Mouse(op, btn, ...)` | `Mouse Op Button` |
| `ms.scroll(dir, n)` | `scroll dir` |
| `ms.sound(path)` | `sound filename` |
| `ms.copy(text)` | `copy` |
| `ms.cam.move(dy, dx)` | accumulated as `cam.move ×N` — individual calls are batched and flushed as a single entry when the next different action fires |

Call `ms.dev.step(msg)` from any macro to log a named checkpoint manually:

```lua
ms.dev.step("before camera sweep")
ms.cam.move(0, -3145)
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
| Sound calls | `sound …` |
| Camera moves | `cam.move ×N` |
| Key presses | `↓ key`, `↑ key`, `type key` |
| Mouse actions | `Mouse …` |
| Scrolls | `scroll …` |
| Clipboard | `copy` |

Each toggle is independent. The bottom of the popup shows **"hide all"** when nothing is muted (clicking mutes every category) or **"show all"** when every category is muted (clicking unmutes all). The button label updates to `filter (N)` with an accent highlight when N categories are active.

Filtered entries remain in the DOM — they reappear instantly when the filter is cleared, without re-running the macro.

---

### Input Monitor — `ms.dev.keys`

A 360×640 floating panel with three sections:

- **Flag row** — two competing pills at the top showing the most recently pressed key and the most recently pressed mouse button. Whichever fired last is highlighted in the accent color; the other dims. Updates in real time on every input event.
- **Keyboard tab** — active key pills (currently held keys) plus a scrolling log of all key events with timestamps. Each entry carries an amber **KEY** badge.
- **Mouse tab** — current cursor position plus a scrolling log of all mouse button down/up events. Each entry carries an orange **MOUSE** badge. A **SCROLL** (teal) badge appears for scroll events.
- **Coordinate reference dropdown** — in the mouse tab's Position header, a dropdown controls what coordinate system the cursor position is shown in:

  | Option | Origin |
  |--------|--------|
  | Screen | Absolute screen pixels |
  | Window | Pixels from the Roblox window's top-left corner |
  | REF 1680×1044 | Scaled into the 1680×1044 reference space used by `ms.Mouse(WindowTL, …)` |
  | Screen center | Offset from the screen centre (negative = left/up) |

Mouse button events are logged regardless of whether macros are enabled (`BindValidity`), so the monitor works even when macros are off.

```lua
ms.dev.keys.show()
ms.dev.keys.hide()
ms.dev.keys.toggle()
```

---

### Window Monitor — `ms.dev.window`

A 360×480 floating panel. Tracks the focused window in real time by polling every 400 ms.

- **Current window** — shows the active app name, window title, and dimensions (width × height px) at the top.
- **Log** — appends an entry each time the focused window changes: `● App › Title [W×H]` with a Unix timestamp.
- **History** — up to 80 entries are kept in memory and restored when the panel is reopened.

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
    ms.dev.step("phase 1 — setup")
    ms.press("w")
    ms.wait(50)
    ms.dev.step("phase 2 — jump")
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

Assign sounds to these slots via **Settings › Sound**. The `hover` and `interact` slots are shared with the native menu bar; any sound assigned there is also used for developer panel buttons.

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

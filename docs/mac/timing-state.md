# Timing, State & Control

## Timing, `ms.wait`

```lua
ms.wait(milliseconds)
```

Yields the current coroutine for the given duration, then resumes. Non-blocking, the Hammerspoon event loop continues running while waiting.

```lua
ms.wait(50)    -- 50 ms
ms.wait(1)     -- 1 ms (minimum resolution ~1 ms)
ms.wait(0.5)   -- sub-millisecond durations accepted
ms.wait(2000)  -- 2 seconds
```

Must be called from a coroutine context (i.e. inside an `ms.fn`-wrapped function). Outside a coroutine it falls back to a blocking `usleep`.

> **Macro Monitor integration.** When the Macro Monitor panel is open, every `ms.wait` call produces a dim step trace entry in the log regardless of duration, with no minimum threshold. See [Developer Tools](?p=theme-dev) for the full list of functions that generate step traces.

### `ms.after(milliseconds, fn)`

Runs `fn` once after the given delay and returns the timer handle. Does not yield, so unlike `ms.wait` it is safe outside a coroutine, use it for background loops and deferred cleanup.

```lua
local t = ms.after(300, function() ms.release("w") end)
t:stop()   -- cancel before it fires
```

> **Units.** `ms.after` takes **milliseconds**, matching `ms.wait`. `hs.timer.doAfter` underneath it takes seconds, so a value copied from Hammerspoon examples is off by a factor of 1000. `ms.after(0.3, fn)` is not "300 ms", it is a third of a millisecond, and in a self-rearming loop that means thousands of timers a second.

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

        if BindValidity ~= 1 or not ms._targetActive then
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

Release any keys the loop is holding on every exit path, including the self-stop path. See `ms.forgetHeld` under [Input](?p=input) for the case where the player has taken the key over.

### `ms.randWait(min, max)`

Waits a random duration between `min` and `max` milliseconds. Useful for adding human-like variation to macro timing.

```lua
ms.randWait(50, 150)   -- wait between 50 and 150 ms
ms.randWait(100, 300)  -- wait between 100 and 300 ms
```

### `ms.jitter(base, jitterMs)`

Waits `base` milliseconds plus or minus a random offset of `jitterMs`. More predictable than `randWait` while still adding variation.

```lua
ms.jitter(100, 20)   -- wait 80-120 ms (100 +/- 20)
ms.jitter(500, 50)   -- wait 450-550 ms (500 +/- 50)
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

## State Queries

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

Mouse buttons are tracked in the same table and can be queried here by name: `leftclick`/`mouse1`, `rightclick`/`mouse2`, `middleclick`/`mouse3`, `mouse4`/`mouseback`, `mouse5`/`mouseforward`. For clearer intent, prefer `ms.mousestate` (below), it accepts friendlier names and covers the same buttons.

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
if ms.mousestate("back") then ms.type("z") end   -- thumb button to undo
```

> Thumb buttons only register if macOS delivers them as button 3/4. Vendor mouse software (Logitech Options, Razer Synapse, SteelSeries GG) that remaps the thumb buttons to keystrokes intercepts them before the event tap sees them, so they won't be tracked while that remapping is active.

---

### `ms.held(id)`

Returns `true` only if **every** identifier modifier of the bind `id` is currently held, used to route a shared trigger among multiple binds that claim it. A bind with no identifier modifiers (the fallback bind) always returns `false`.

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

Returns the cursor position in 1680x1044 reference-space coordinates relative to the Roblox window. Returns raw screen coordinates if Roblox is not found.

```lua
local x, y = ms.mousePos()
ms.alert(string.format("Mouse: %.0f, %.0f", x, y), 3)
```

---

### `ms.getTargetWin()`

Returns the main `hs.window` object of the target app (see `ms.setTargetApp`), or `nil` if it is not running.

---

### `ms.winCenter()`

Returns `(x, y)` screen coordinates of the center of the Roblox window (falls back to focused window).

---

### `ms.getScaled(targetX, targetY)`

Converts a 1680x1044 reference-space coordinate to absolute screen pixels, accounting for the actual Roblox window size and position.

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

Returns `true` if the pixel at `(x, y)` is within `tolerance` of the target colour on every channel. `tolerance` defaults to `10`. All values are `[0, 255]`.

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

## Macro Control

### `BindValidity`

Global integer. `1` means macros active, `0` means macros disabled. All bind handlers check this before firing.

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

The app watcher monitors focus changes and enables/disables macros based on the **target application** set via `ms.setTargetApp()`. By default this is `"Roblox"`. Pass `nil` for global mode, macros stay enabled regardless of the focused app.

| Event | Action |
|-------|--------|
| Target app activated | `BindValidity = 1`, camera enabled (Roblox only), enable notification queued |
| Target app activated (returning from a settings dialog) | `BindValidity = 1`, notification suppressed |
| Any other app activated | `ms.setMacros(0)`, disables and notifies |
| Hammerspoon activated while target was in front | `ms.setMacros(0, true)`, disables silently (settings dialog cycle) |
| Target app launched | Camera watcher set up (Roblox only) |

The in-game keys `/` (disable) and `Enter` (enable) toggle macros while the target app is focused (Roblox mode only).

---

## Cooldown Helpers

### `ms.bind.group(id)`

Returns the cooldown group key for `id`. All macros in the same group share a single cooldown timer, firing any one of them locks out all others for the cooldown duration.

- If `opts.shared` is set on `id` or its root, that value is used directly.
- Otherwise auto-derives `"G_<rootId>"` by walking the `sub` chain.

```lua
local g = ms.bind.group("superThrow")  -- to "G_superJump"
```

---

### `ms.pause([id])` / `ms.resume([id])`

Pauses and resumes a running macro by id (the first argument to `ms.bind.define`). When paused, the macro's current `ms.wait()` expires but does not resume until `ms.resume()` is called. Any already-expired wait time is consumed, the macro picks up immediately from the next instruction.

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


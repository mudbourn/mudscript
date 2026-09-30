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

### `ms.padstate(button [, ...])`

Returns `true` if any of the named controller buttons are currently held, mirroring `ms.keystate` for gamepads. Needs the controller toggle on in Settings. Buttons are named by position, so `a` is the bottom face button on every controller.

```lua
ms.padstate("r2")
ms.padstate("l3", "l2")   -- true if either is held
if ms.padstate("l3") and ms.padstate("l2") then ... end   -- both held
```

Names are case-insensitive, and a leading `pad` is ignored (`padL3` is `l3`):

| Button | Names |
|--------|-------|
| Face | `a`, `b`, `x`, `y` (also `cross`, `circle`, `square`, `triangle`) |
| Shoulders | `l1`, `r1` (also `lb`, `rb`) |
| Triggers | `l2`, `r2` (also `lt`, `rt`) |
| Stick clicks | `l3`, `r3` (also `ls`, `rs`) |
| D-pad | `up`, `down`, `left`, `right` (also `dup`, `ddown`, `dleft`, `dright`) |
| System | `menu` (`start`), `options` (`select`, `back`, `view`, `share`), `home` |

A loop that polls controller state must yield (`ms.wait`) every pass. Controller events arrive on the same thread as macros, so a loop without a wait never sees the button release and never ends.

```lua
while ms.padstate("l3") and ms.padstate("l2") do
    ms.type("f")
    ms.wait(50)
end
```

---

### `ms.padaxis(axis)`

Reads an analog input. A stick returns `x, y` from -1 to 1 (up is positive `y`, 0.05 deadzone). A trigger returns how far it is pulled, from 0 to 1.

```lua
local x, y = ms.padaxis("right")   -- right stick
local x, y = ms.padaxis("left")    -- left stick (l3/ls also work)
local pull = ms.padaxis("r2")      -- right trigger
if pull > 0.5 then ... end
```

Note that `left`/`right` mean the sticks here and the d-pad in `ms.padstate`.

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

Returns the cursor position in pixels relative to the target window. Returns raw screen coordinates if no window is found.

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

Converts a pixel offset from the target window top-left to absolute screen pixels.

```lua
local sx, sy = ms.getScaled(900, 660)
```

---

### `ms.pixelColor(x, y [, reference])`

Returns the colour of a single screen pixel at `(x, y)` in the given reference space as a hex string such as `"#FF5000"`. Uses the same coordinate system as `ms.Mouse`. `reference` defaults to `Absolute` if omitted.

The red, green and blue channels come back as extra return values in `[0, 255]`. Returns `nil` if the position is off-screen or the capture fails.

```lua
local hex = ms.pixelColor(900, 540, WindowTL)
if hex == "#FF5000" then
    -- ...
end

local hex, r, g, b = ms.pixelColor(1200, 400)
```

The Window panel's element inspector shows the hex of the pixel under the cursor, ready to paste.

---

### `ms.pixelMatch(x, y, reference, color [, tolerance])`

Returns `true` if the pixel at `(x, y)` is within `tolerance` of `color` on every channel. `color` is a hex string: `"#FF5000"`, `"FF5000"` and the short form `"#F50"` all work. `tolerance` is per channel in `[0, 255]` and defaults to `10`.

```lua
if ms.pixelMatch(900, 540, WindowTL, "#FF5000") then
    -- ...
end

if ms.pixelMatch(445, 37, WindowTL, "#0CC840", 5) then
    -- ...
end
```

### `ms.waitPixel(x, y, ref, color [, tolerance [, timeout]])`

Waits until a pixel matches the hex colour. Polls every 50ms. Returns `true` when matched, `false` on timeout (default 5 seconds). A `timeout` of `0` waits with no limit.

```lua
local found = ms.waitPixel(900, 540, WindowTL, "#00FF00", 10, 3000)
if found then ms.type("e") end
```

### `ms.waitNotPixel(x, y, ref, color [, tolerance [, timeout]])`

Waits until a pixel no longer matches the hex colour. Inverse of `waitPixel`. Returns `true` when the pixel changes, `false` on timeout.

```lua
ms.waitNotPixel(960, 540, "Absolute", "#FFFFFF", 10, 10000)
```

### `ms.parseHex(hex)`

Converts a hex colour string to `r, g, b` integers, or `nil` if the string is not a valid colour.

```lua
local r, g, b = ms.parseHex("#FF5000")
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

### `ms.cancelMacros([macro])`

With no argument, cancels every running `ms.fn` coroutine and releases any keys or mouse buttons held by macro presses. Called automatically on every `ms.setMacros(0)`.

Pass a macro id or label to cancel only that macro. Only the keys and buttons that macro is holding are released, and other macros keep running. When a macro cancels itself it stops at that line.

```lua
ms.cancelMacros()
ms.cancelMacros("Auto_Farm")
```

In the visual builder, the Cancel Macros module has a Macro dropdown. Leave it on All macros to cancel everything.

The builder also has a Break module. Inside a loop it exits the innermost loop. Outside any loop it ends the macro.

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


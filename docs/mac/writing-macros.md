# Writing Macros

## Macro File Structure

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

See [Settings & Menu API](?p=system) for the full User Settings & Menu API reference.

---

## Declaring Macros — `ms.bind.define`

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

## Sub-item System

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

## Wrapping Functions — `ms.fn`

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


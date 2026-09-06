# Utility Functions, Hotkeys & Constants

## Utility Functions

### `ms.alert(msg [, duration [, noDefaultSound]])`

Displays a floating toast notification on screen. Up to 4 alerts stack vertically with animated entry/exit.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `msg` | - | String to display. `\n` for line breaks. |
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

Prints target window info (resolution, position, aspect ratio, sensitivity) to the Hammerspoon console and shows alerts. Also warns if the aspect ratio is too narrow for macros to work correctly. Available as a Lua call. The **Settings > Developer** button now opens the **Window Monitor** instead.

---

## Global Hotkeys

These hotkeys only fire when the **target application** is focused (set via `ms.setTargetApp()`). They are silently ignored in all other apps.

| Hotkey | Action |
|--------|--------|
| `alt+[` | Quick Reload, granular reload of macros/theme/settings/UI per the Quick Reload dropdown options |
| `alt+]` | Full Reload, tears down and restarts Hammerspoon (`ms.restart()`, falling back to `hs.reload()`) |
| `alt+p` | Toggle the Settings panel |
| `alt+o` | Toggle Octane Mode |
| `alt+F10` | Emergency reset, disables macros immediately |

### Tap resilience

Every hotkey runs on its own `hs.eventtap`. macOS disables an event tap whose callback overruns its time budget (`kCGEventTapDisabledByTimeout`), and a disabled tap is silent, the bind simply stops working, with no error, until Hammerspoon reloads.

Two mechanisms keep that from happening:

- **Handlers run off the tap callback.** A hotkey action is deferred to the next runloop turn rather than called inline, so the callback returns immediately no matter how much work the action does. The enable/disable/toggle actions play a sound, raise an alert and refresh the UI, which is more than enough to trip the timeout.
- **The watchdog revives disabled taps.** `ms._tapWatchdog` polls every 2 seconds and restarts any tap in `ms._resilientTaps` that has been disabled. Hotkey taps register themselves as they are created in `ms._bindHotkeys`, and rebinding drops the previous generation from the list.

### Latch recovery

A hotkey fires on key-down and arms again on key-up. If that key-up never arrives the bind stays latched down and never fires again, the failure mode behind "the macro toggles stopped re-enabling my macros."

A key-up can go missing when the tap is disabled mid-hold, when focus moves to an app that swallows it, or when `ms.setMacros(0)` clears `ms.keytrack` underneath the hold.

Two recoveries cover it:

- A key-down that is **not** an autorepeat proves the key came back up at some point, so any latch still standing is stale and gets cleared before the fire check. A 10-second age ceiling backstops anything the autorepeat flag misses.
- When the watchdog revives a hotkey tap, all latches and cooldowns are cleared, every event during the dead window was dropped, so none of that state can be trusted.

Neither recovery can double-fire a bind: a genuine held key produces autorepeat key-downs, which are left latched.

### Octane Mode, `ms.octane`

A low-overhead performance toggle, bound to `alt+o`. Octane Mode strips logging, animations, idle pollers, and (optionally) sounds while macros keep running unchanged, for when the developer panels and UI polish aren't worth their overhead.

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

Turning it off restores all of the above, logging resumes, pollers restart for any panel that's currently active, and the menu hover watcher restarts if the menu is visible.

The toggle state (`ms._octaneMode`) persists across reloads via settings, so it's re-applied automatically on load if it was left on. A separate **Octane mute sounds** setting (`ms._octaneMuteSounds`) can additionally silence sound playback while Octane is active, independent of the master toggle.

---

## Global Constants

### Camera / scaling

| Constant | Value | Description |
|----------|-------|-------------|
| `REF_W` | `1680` | Reference resolution width used for coordinate scaling |
| `REF_H` | `1044` | Reference resolution height |
| `REF_SENS` | `1.5` | Reference camera sensitivity (used to derive `cachedMult`) |
| `CUR_CAM_SENS` | *(user setting)* | Current in-game sensitivity. Set via Settings > Camera Sensitivity |

---

### Target application

| API | Description |
|-----|-------------|
| `ms.setTargetApp(name)` | Set the target app by bundle name (e.g. `"Roblox"`, `"Minecraft"`). Pass `nil` for global mode, macros stay enabled regardless of focused app. Default: `"Roblox"`. |
| `ms.getTargetWin()` | Returns the target app's main window, or `nil` if the app isn't running. Fallback to `hs.window.focusedWindow()` in coordinate functions. |
| `ms.app()` | Returns the bundle name of the currently focused app. |

Call `ms.setTargetApp()` at the top of `ms_macros.lua`, right after `ms.macroMeta`. The app watcher, window lookups, and focus restoration all follow this setting.

---

### `ms.Mouse` named constants

These are plain globals available from `ms_macros.lua`.

**Operations:** `Move`, `Click`, `DoubleClick`, `TripleClick`, `Drag`, `Press`, `Release`

**Buttons:** `Left`, `Right`, `Center`, `Button4`, `Button5`

**References:** `Absolute`, `Mouse`, `WindowTL`, `WindowTR`, `WindowBL`, `WindowBR`, `WindowCenter`, `ScreenTL`, `ScreenTR`, `ScreenBL`, `ScreenBR`, `ScreenCenter`

**Flag:** `Unscaled` (`true`), pass between the reference and the first coordinate in `ms.Mouse` to use raw pixel window offsets instead of REF-space scaled values.

---

### Sound

| Constant | Description |
|----------|-------------|
| `SoundLib` | Path to `~/.hammerspoon/sounds/` (trailing slash included) |
| `ms.sounds` | Table of discovered sounds, keyed by filename-without-extension |
| `ms.soundEnabled` | Master on/off (bool) |
| `ms.soundVolume` | Volume 0-100 |
| `ms.soundAssign` | Per-slot sound overrides: `{ load=name, update=name, hover=name, ... }`. See [Audio](?p=audio) for all slot names. |
| `ms._updateManifestURL` | URL of the `MANIFEST.json` used by the update system. Points to the GitHub repo by default. |

---

### Internal state (read-only, do not modify directly)

| Variable | Description |
|----------|-------------|
| `BindValidity` | `1` if macros are active, `0` if disabled |
| `ms.keytrack` | Live key-held table: `{[keycode] = true/false}` |
| `ms.running` | Active cooldown timers: `{[groupId] = timerHandle}` |
| `ms.binds` | Enabled state overrides per id |
| `ms.bindConfig` | User keybind overrides per root id |
| `ms.cooldowns` | User cooldown overrides per id |
| `ms.registry._defs` | Full definition table by id |
| `ms.registry._defList` | Ordered list of all ids as declared |
| `ms.bind._wires` | Registered functions by id |



# Roblox

Starter Roblox plugin for mudscript. Two jobs: declare Roblox as the macro
**target app** (core no longer hardcodes a game, so a plugin or pack must say
which app the camera engine and system binds key off), and expose Roblox's own
saved settings to macros as a **live reader**.

Everything registers through the proxied `ms`, so `ms.plugins.unload` can take it
back out; `:stop()` handles the state the proxy never saw (target app, the
anti-timeout timer) and drops the `ms.roblox` namespace.

## Live reader - `ms.roblox`

Reads `~/Library/Roblox/GlobalBasicSettings_13.xml` (a flat
`<TYPE name="KEY">VALUE</TYPE>` dump) **fresh on every call** - no caching, so a
macro never acts on last session's numbers.

| Function | Returns |
|----------|---------|
| `ms.roblox.setting(key)` / `.settingNumber(key)` / `.settingBool(key)` | Any UserGameSettings key. |
| `ms.roblox.sensitivity()` | `MouseSensitivity` |
| `ms.roblox.gamepadSens()` | `GamepadCameraSensitivity` |
| `ms.roblox.framerateCap()` | `FramerateCap` |
| `ms.roblox.graphicsQuality()` / `.savedQuality()` | quality levels |
| `ms.roblox.masterVolume()` | `MasterVolume` |
| `ms.roblox.fullscreen()` / `.cameraInverted()` | booleans |
| `ms.roblox.isFocused()` | `true` when Roblox is the active target |
| `ms.roblox.activate()` | focus the Roblox window |

## Sensitivity Tether

The combat macros scale every camera move by `refSens / curSens`, where `curSens`
is `ms._camSens`. Left alone that only tracks the manual **Camera Sensitivity**
slider, so a player whose real in-game sensitivity differs silently mis-rotates
every spin (the classic "super jump won't land"). The **Sync Sensitivity From
Roblox** toggle ties `ms._camSens` to Roblox's live saved sensitivity so the
calibration always matches the setting actually in effect, and mirrors the value
onto the visible `cameraSensitivity` slider when a pack defines one.

Reading the live value: the in-game slider writes the legacy scalar
`MouseSensitivity`, which Roblox mirrors into per-view `Vector2` blocks
(`MouseSensitivityThirdPerson` / `MouseSensitivityFirstPerson`, stored as nested
`<X>`/`<Y>`). `effectiveSensitivity()` reads the scalar first and falls back to
the third-person `Vector2` X (Combat Warriors' default), then first-person. If a
live slider change does not move `curSens` in mudscript, the effective key is the
`Vector2` instead, so swap the fallback order.

Freshness: a path watcher on the settings file reacts the instant Roblox flushes
it (menu close / focus loss, which Roblox controls and mudscript cannot force). A
slow 10s poll backstops the atomic-rename case FSEvents may report differently.
Both call the same sync, which no-ops when the value is unchanged.

## Anti-Timeout

Roblox kicks idle sessions after ~20 minutes. The core mechanism
(`ms.antiTimeout`) is generic; this plugin supplies the action (a harmless `f15`
keystroke) and exposes an on/off toggle plus an interval slider.

## Cache Cleaner

A launchd agent that purges Roblox micro-profiler dumps and stale caches every
6h. Assets ship in `bin/`. The **Roblox Cache Cleaner** toggle installs the agent
(expanding the plist's `%%AGENT_PATH%%` placeholder to the bundled script) when
on, and unloads/removes it when off. This used to live in base mudscript; it now
belongs to the plugin, so uninstalling removes the agent path entirely.

# Audio

## Audio, `ms.sound`

### `ms.sound(path [, async [, device]])`

Plays a sound file.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `path` | - | A file path string or a `ms.sounds.*` table entry. Must be the **value**, not a variable name. |
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

**Common mistake, passing a variable name as a string:**

```lua
local MySound = SoundLib .. "MySound.wav"
ms.sound("MySound")        -- WRONG: this is a string literal, not the variable
ms.sound("MySound.wav")    -- WRONG: filename only, not a full path
ms.sound("MySound", true)  -- WRONG: quoted name, async flag ignored because path fails
```

Passing a quoted name silently fails, `hs.sound` cannot find a file called `"MySound"` and returns nothing. Always pass the variable itself (no quotes) or the full path.

Volume is set automatically from `ms.soundVolume` (0-100).

---

### `ms._discoverSounds()`

Scans `~/.hammerspoon/sounds/` and populates `ms.sounds`, a table keyed by filename without extension. Called once at startup. Call again if you add sound files without reloading.

Only audio files are indexed. `ms.soundExtensions` is the list (`wav`, `aiff`, `aif`, `mp3`, `m4a`, `caf`, `aac`), and `ms.isSoundFile(filename)` is the test, the same one the auto-sorter and the importer use, so a file cannot be indexed but unfiled or filed but unindexed.

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

If all three come up empty and the slot declares a `fallback`, the whole sequence runs again for that slot. An assignment pointing at a sound that no longer exists is *skipped*, not treated as a path, so a stale assignment costs you the default sound, never silence.

Playback timing is recorded against the slot that was asked for, whichever slot's sample ended up playing.

Calls within 50 ms of the previous call for the same slot are silently suppressed to prevent double-play (e.g. a keyboard shortcut and the action's `fn` both firing simultaneously).

```lua
ms.playSlot("update")   -- plays whatever is assigned to the "update" slot
ms.playSlot("hover")    -- plays the menu hover sound
```

---

### Sound event slots

`ms.soundAssign` maps slot names to sound names from `ms.sounds`. Configured via **Settings > Sound**. Drop a file named after the slot (e.g. `hover.wav`) into `~/.hammerspoon/sounds/` for auto-assignment without any configuration.

**`ms.soundSlots` is the definition of the list below**, id, label, group, default sample (`d`), themed sample (`a`), and any `fallback`. It is the only place the built-in slots are enumerated. `ms.playSlot`, the custom-theming reset, the preset builder and the Sounds tab all derive from it and none of them keep a copy, so adding a slot is a single edit. Helpers: `ms.soundSlot(id)`, `ms.soundSlotChain(id)`, `ms.soundSlotDefaults()`, `ms.buildSoundPresets()`.

> **Loading-sequence slots:** `themeLoaded`, `load` and `launch` are the three loading-sequence slots. They are exempt from the startup sound gate, they can fire before the gate opens, while the loading screen is still active.

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
| `restart` | - (falls back to `shutdown`) | The exit curtain fades in on a restart |

#### Reserved names

Every `d_*` and `a_*` name in the table above, plus its numbered preset variants (`a_Shutdown2` ... `a_Shutdown9`), belongs to the theme system. Imported sounds are renamed away from these on the way in, `ms.safeSoundName(stem, prefix)` strips any `d_`/`a_`/`m_` prefix the file arrived with, re-prefixes it, and suffixes `-2`, `-3` ... on collision. The dash matters: a bare trailing digit is how a preset variant is spelled, so a file called `Shutdown2.wav` would otherwise become preset 2's send-off. Nothing an import does can overwrite a shipped sample.

### `ms.setVolume(level)`

Sets the system output volume (0-100).

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


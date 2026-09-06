# Settings, Modes & Profiles

## Utilities

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

## Settings & Defaults

### `ms.saveSettings()`

Writes all current runtime state to `ms_settings.json`. Called automatically after every settings menu action.

---

### `ms.loadSettings()`

Reads `ms_settings.json` (falls back to `ms_settings_default.json`, then auto-builds from registry). Applies the loaded values to the live runtime state.

---

### `ms.reloadSettings()`

Convenience wrapper that runs the full settings-reload sequence in one call: `loadSettings` to rebind to cam anchor to cam multiplier to SOCD to play update sound to show confirmation alert. Called by both the Settings menu item and the `alt+]` hotkey.

---

### `ms.saveDefault()`

Promotes the current `ms_settings.json` to `ms_settings_default.json`. Archives the previous default to `backups/` with a timestamp.

---

### `ms.resetToDefault()`

Clears all per-macro customisations (`bindConfig`, `subBinds`, `modConfig`, `cooldowns`), applies `ms_settings_default.json` as a full replacement, saves back to `ms_settings.json`, and rebinds everything. Returns `true` on success.

Unlike `ms.loadSettings()`, this is a **replace**, any custom keybind or cooldown not present in the default file is removed, not preserved.

---

### `ms._applySettings(data)`

Internal. Applies a decoded settings table to live runtime state. You do not need to call this directly.

---

### Settings files

| File | Purpose |
|------|-------|
| `data/ms_settings.json` | Current user settings, written on every change |
| `data/ms_settings_default.json` | The "reset to default" target |
| `data/ms_theme.json` | UI theme, colors, font, border radius, UI Frame Cosmetic |
| `backups/` | Timestamped archives of previous defaults |

Settings and theme files live in `~/.hammerspoon/data/`. They are gitignored, each install generates its own. Existing files at the old root location are automatically migrated to `data/` on the first reload after upgrading.

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

## SOCD Engine

Simultaneous Opposing Cardinal Directions cleaning. When enabled, prevents both keys in an axis pair (`W`/`S`, `A`/`D`) from being registered as held at the same time.

### `ms.socdMode`

| Value | Behavior |
|-------|----------|
| `"lastWins"` | The most recently pressed key wins, releasing the opposite. On release, re-presses the opposite if still physically held. *(default)* |
| `"firstWins"` | The first key pressed wins, and the second is swallowed. |
| `"neutral"` | Both keys are released when both are held simultaneously. |

---

### `ms.socdStart()` / `ms.socdStop()`

Start or stop the SOCD eventtap listener. Use `ms.socdApply()` instead to respect the current `ms.socdEnabled` setting.

---

### `ms.socdApply()`

Starts or stops the SOCD listener based on `ms.socdEnabled`. Call this after changing `ms.socdEnabled` or `ms.socdMode`.

---

## Trackpad / Pen Mode

Trackpad / Pen Mode lets a keyboard key stand in for a held mouse button, for setups without a physical mouse. Toggling `ms.trackpadMode` starts or stops the two trackpad hold listeners (`ms._trackpadLeftListener`, `ms._trackpadRightListener`), which simulate a held left or right mouse button while their configured key is held. Hold keys are set via Settings > Trackpad Hold Keys. Defaults are `n` (left) and `j` (right).

---

## Profiles

A profile is a folder in `~/.hammerspoon/profiles/<name>/` containing `ms_macros.lua` and optionally `ms_settings.json`, `ms_settings_default.json`, and `ms_theme.json`.

**Switching profiles** (Settings > Profiles):
1. Archives the active `ms_macros.lua` + settings files into `profiles/<currentName>/`.
2. Copies the target profile's files into the active positions.
3. Reloads after 3 seconds.

**Importing a profile** (Settings > Profiles > Import Profile):
- Opens a file picker for `.mspkg` files.
- The package is extracted, `ms_macros.lua` is security-audited, and the full bundle is installed into `profiles/<name>/`.
- Bundled sounds are copied into `~/.hammerspoon/sounds/` automatically. Files that already exist are never overwritten.

**Exporting a profile** (Settings > Profiles > Export Profile):
- Packages the current active profile as a `.mspkg` file and saves it to `~/Downloads/`.
- Reveals the file in Finder on completion.
- Sounds referenced in `ms.soundAssign` that came from `ms.importedSounds` are bundled automatically.

### .mspkg format

A `.mspkg` file is a standard zip archive with a defined internal layout:

```
ms_macros.lua                  (required)
ms_settings.json               (optional, current keybinds, mods, sensitivity, sound slots)
ms_settings_default.json       (optional, pack's preferred defaults)
ms_theme.json                  (optional, pack's theme)
sounds/                        (optional, bundled sound files)
```

Any sounds in `sounds/` are added to the user's library on import. If a sound with the same filename already exists it is skipped.

**Security:** both import and profile switch run `auditMacros()` on `ms_macros.lua` before any disk operations. A file that fails the static scan is rejected with an alert and never activated.

---


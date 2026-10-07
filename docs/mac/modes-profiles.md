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

Writes all current runtime state to the active profile's `data/ms_settings.json`. Called automatically after every settings menu action.

---

### `ms.loadSettings()`

Reads the active profile's `data/ms_settings.json` (falls back to `data/ms_settings_default.json`, then auto-builds from registry). Applies the loaded values to the live runtime state.

---

### `ms.reloadSettings()`

Convenience wrapper that runs the full settings-reload sequence in one call: `loadSettings` to rebind to cam anchor to cam multiplier to SOCD to play update sound to show confirmation alert. Called by both the Settings menu item and the `alt+]` hotkey.

---

### `ms.saveDefault()`

Promotes the active profile's `data/ms_settings.json` to `data/ms_settings_default.json`. Archives the previous default to `backups/settings/` with a timestamp.

---

### `ms.resetToDefault()`

Clears all per-macro customisations (`bindConfig`, `subBinds`, `modConfig`, `cooldowns`), applies the profile's `data/ms_settings_default.json` as a full replacement, saves back to `data/ms_settings.json`, and rebinds everything. Returns `true` on success.

Unlike `ms.loadSettings()`, this is a **replace**, any custom keybind or cooldown not present in the default file is removed, not preserved.

---

### `ms._applySettings(data)`

Internal. Applies a decoded settings table to live runtime state. You do not need to call this directly.

---

### Settings files

Each profile holds its own copy of these files. Paths are relative to `~/.hammerspoon/profiles/<name>/`.

| File | Purpose |
|------|-------|
| `data/ms_settings.json` | Current user settings, written on every change |
| `data/ms_settings_default.json` | The "reset to default" target |
| `data/ms_theme.json` | UI theme, colors, font, border radius, UI Frame Cosmetic |
| `backups/settings/` | Timestamped archives of previous defaults (global, under `~/.hammerspoon/`) |

Profile files are gitignored in each install. Nothing profile-specific lives at the root of `~/.hammerspoon/`.

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

A profile is a self-contained folder. Everything the profile owns lives inside it, and the active profile is a pointer, so switching never moves a file.

```
~/.hammerspoon/profiles/
    .layout                    "2"
    .active                    name of the active profile folder
    <Name>/
        profile.json
        ms_macros.lua
        data/
            ms_settings.json
            ms_settings_default.json
            ms_theme.json
            ms_macros_visual.json
            ms_macros_visual.lua
            ms_authored.json
            ms_authored_menus.json
            ms_helpervars.json
        sounds/
            active/
            macro/
```

Global and shared across profiles: `sounds/defaults/`, `ui/fonts/`, `data/library/`, `data/registry_index.json`, the trust and plugin ledgers, backups, logs and `Spoons/`.

### profile.json

```json
{
  "formatVersion": 2,
  "name": "Combat",
  "version": "1.0.0",
  "author": "You",
  "created": "2026-10-07T12:00:00Z",
  "updated": "2026-10-07T12:00:00Z",
  "origin": "local",
  "owner": "registry-id",
  "requires": { "mudscript": "1.4.0", "plugins": ["roblox"] },
  "packs": { "theme": { "slug": "dark", "version": "1.0.0", "owner": "registry-id" } }
}
```

`origin` is `local`, `registry` or `import`. `owner` is the registry id for a registry install. `requires.plugins` is computed from the profile's Lua whenever the profile is saved or exported. `packs` records which library pack each kind was last activated from.

### ms.profile

| Function | Description |
|---|---|
| `ms.profile.active()` | Name of the active profile |
| `ms.profile.setActive(name)` | Writes `profiles/.active` |
| `ms.profile.dir([name])` | Folder of a profile, default the active one |
| `ms.profile.path(rel [, name])` | Absolute path of a file inside a profile |
| `ms.profile.file(key [, name])` | Path by key: `macros`, `settings`, `defaults`, `theme`, `visualJson`, `visualLua`, `authored`, `authoredMenus`, `helperVars`, `meta` |
| `ms.profile.list()` | Names of all profile folders |
| `ms.profile.readMeta(name)` / `ms.profile.writeMeta(name, tbl)` | Read and write `profile.json` |
| `ms.profile.repoint()` | Re-reads the pointer and updates the sound folders and compiler paths |

### Menu actions

**Switching profiles** (Settings > Profiles):
1. Scans the target profile's `ms_macros.lua` with `auditMacros()`.
2. Saves the current settings into the current profile.
3. Writes the target name to `profiles/.active` and repoints every path.
4. Hotswaps macros, settings, theme, sounds and authored content live and offers any missing plugins.

**Creating a profile** copies the active profile into a new folder, or builds a blank one.

**Renaming** renames the folder, and the pointer follows when the profile is active. **Deleting** removes the folder and refuses the active profile.

**Importing a macro file** (Settings > Profiles > Import Profile) audits an `ms_macros.lua` and creates a profile from it.

**Importing a package** reads a `.mspkg` through `ms.package.install`. A profile package always creates a new profile folder and never touches the active one. A name clash gets a numbered suffix. The macros are audited, compatibility warnings are shown and missing plugins are offered. Sounds in the package go into the new profile's own `sounds/` folders and bundled fonts go into `ui/fonts/`.

**Updating a registry profile** keeps `origin` and `owner`, snapshots the profile through the backup system, builds the new folder aside, keeps the profile's `data/ms_settings.json` and swaps the folders. The previous folder is kept in `backups/updates/`.

**Exporting a profile** (Settings > Profiles > Export Profile) packages the active profile as a `.mspkg` in `~/Downloads/`.

### Library packs

Themes, sounds and macros installed from Browse or imported land in `data/library/<kind>/<slug>/` as read-only sources. Activating a pack copies its files into the active profile and records it in `profile.json` under `packs`. Capturing saves the active profile's slice back to the library as a new pack. Packs are never applied by switching profiles.

### .mspkg format

A `.mspkg` file is a standard zip archive. A profile package (`formatVersion` 2) mirrors the profile folder and adds a manifest:

```
mspkg.json                     (manifest)
profile.json
ms_macros.lua
data/ms_settings.json
data/ms_settings_default.json
data/ms_theme.json
data/ms_macros_visual.json
data/ms_macros_visual.lua
data/ms_authored.json
data/ms_authored_menus.json
data/ms_helpervars.json
sounds/active/
sounds/macro/
ui/fonts/
```

Version 1 profile packages and manifest-less zips are still read. Their flat files (`ms_macros.lua`, `ms_*.json`, `sounds/`, `sound_assign.json`) are mapped into the new folder layout on import.

**Security:** import, install and profile switch run `auditMacros()` on `ms_macros.lua` before the profile is used. A file that fails the static scan is rejected with an alert and never activated.

### Layout migration

On the first boot of a version that uses this layout, a missing or older `profiles/.layout` triggers an automatic move. A full copy of the old root files, the old `profiles/` folder and the library markers is saved to `backups/migration-<date>/safety/`. The new tree is built and verified byte for byte in `profiles.migrating/`, then swapped into place, and the old files are moved into the same backup folder. Nothing is deleted. A failed verification discards the scratch folder and the install keeps running on the old layout. An interrupted move resumes on the next boot.

---

## Backups

All backups live under `~/.hammerspoon/backups/`:

| Folder | Contents |
|---|---|
| `auto/` | Profile snapshots (`YYYY-MM-DD_HHMMSS.mspkg`) and `index.json` |
| `updates/` | Copies of files replaced by an update |
| `settings/` | Archived defaults and the old settings text file |
| `logs/` | Dev log session archives |
| `tmp/` | Staging for export, import, restore and update downloads |

A snapshot is a zip of a profile folder: macros, settings, theme, builder content, the profile's sounds and theme fonts. Every snapshot is self-contained and carries the profile name.

Before writing, mudscript fingerprints the staged files. If the fingerprint matches the newest snapshot, no new file is written and that entry's `lastChecked` time moves forward. A manual backup of an unchanged setup reports "No changes since" the last snapshot date.

Settings > Backups sets `backupIntervalHours` (0 = off, 1, 3, 6, 12 or 24, default 12) and `backupKeep` (1 to 50, default 10). Oldest snapshots beyond the keep count are removed. On boot, a snapshot is taken after a short delay when the newest one is older than the interval.

### ms.backups

| Function | Description |
|---|---|
| `ms.backups.snapshot(reason, onDone [, protectId [, profileName]])` | Reason is `"auto"`, `"manual"`, `"pre-restore"` or `"pre-update"`. The profile is staged immediately. `onDone(ok, info)` runs when finished |
| `ms.backups.list()` | Entries `{id, file, time, lastChecked, profile, reason, size, hash}`, newest first |
| `ms.backups.restore(id)` | Confirms in a modal, takes a `pre-restore` snapshot, audits the macros, then restores and hot-reloads. A backup of the active profile restores in place. A backup of another profile restores into a new folder named `<Name> (restored <date>)` and switches to it |
| `ms.backups.delete(id)` | Removes one snapshot |
| `ms.backups.prune()` | Applies the keep count |
| `ms.backups.schedule()` | Re-arms the timer from `backupIntervalHours` |
| `ms.backups.dir(sub)` | Path of a backup subfolder, created on demand |

The Time Machine button in Settings > Backups lists the snapshots and restores or deletes one. Restoring only copies sounds and fonts that are missing. Backups made before the folder layout are still restorable.

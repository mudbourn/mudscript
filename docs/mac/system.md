# System Integrity & Settings API

## System Integrity & Updates

### Overview

The system integrity check detects unauthorised modifications to `ms_core.lua` by comparing its SHA-256 hash to a stored baseline. The update system fetches a new `ms_core.lua` from GitHub, verifies its RSA-2048 signature and hash before installing, backs up the old file, and reloads automatically.

The trusted hash is stored in `~/.hammerspoon/data/.ms_trusted_hash`, one line, 64 hex characters. It is seeded automatically from `MANIFEST.json` on a clean install, and updated after every successful update. Normal reloads never change it.

> **Note:** `ms.integrity` is read-only from `ms_macros.lua`. Macro code cannot call `deleteTrustedHash()` or `writeTrustedHash()`. Use **Settings > Developer > Trust Current Version** for all trust management.

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

Available via **Settings > Developer > Trust Current Version**. The item is greyed out when the file already matches the stored hash.

---

### `ms.integrity.update()`

Full async update flow. Triggered via **Settings > Help > Check for Update**.

1. Fetches `MANIFEST.json` from `ms._updateManifestURL` over HTTPS (HTTP is rejected)
2. Verifies the RSA-2048 signature in the manifest against the built-in public key, aborts on invalid signature
3. Downloads `ms_core.lua` from the `url` field in the manifest
4. Compares the downloaded file's SHA-256 to the `sha256` field, installs regardless (logs a warning if stale)
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

The GitHub Actions workflow (`.github/workflows/release.yml`) triggers on any push that touches `ms_core.lua` or `ms_core.ahk` (path filter: `paths: [ms_core.lua, ms_core.ahk]`). When triggered it always stamps, there is no step-level condition gating the stamp on which file changed:

1. Computes the SHA-256 of `ms_core.lua`
2. Signs it with the RSA private key stored in GitHub Secrets (`MS_SIGNING_KEY`)
3. Commits an updated `MANIFEST.json` with the new hash and signature

The public key is embedded in `ms_core.lua` (`ms._updatePublicKey`). The private key never leaves GitHub Secrets.

**Rotating the signing key**, if the private key is ever compromised or needs replacing:

```bash
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem
```

Paste the contents of `public.pem` into `ms._updatePublicKey` in `ms_core.lua`, then replace the `MS_SIGNING_KEY` GitHub Secret with `private.pem`. The next push that touches `ms_core.lua` will sign `MANIFEST.json` with the new key automatically.

---

## User Settings & Menu API

Macro packs can declare their own settings, panel sections, and hide unused built-in features. These calls belong in the **Pack Settings** zone of `ms_macros.lua`, after `ms.macroMeta`, before macro functions.

---

### `ms.settings.define(def)`

Registers a setting or visual item in the **Settings** section of the panel. Items appear in declaration order.

**Common fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | `"toggle"` \| `"slider"` \| `"seg"` \| `"action"` \| `"soundSlot"` \| `"group"` \| `"divider"` \| `"groupLabel"` |
| `key` | yes (except divider/groupLabel) | Unique identifier. Used for storage and `ms.settings.get`. For `soundSlot` items the key names the sound slot, and `ms.settings.get` returns the currently assigned sound name rather than a value from settings storage. |
| `label` | - | Row label shown in the panel. |
| `hint` | - | Optional subtitle shown below the label. |
| `save` | - | `false` to skip persisting to `ms_settings.json`. Default: `true`. |
| `default` | - | Initial value used when no saved value exists. |
| `onChange(value)` | - | Called when the user changes the value. Also called once at startup with `default`, **only if `default` is not `nil`**. If a saved value exists, a second call follows with the saved value. |

**Type-specific fields:**

| Type | Extra fields |
|------|-------------|
| `slider` | `min`, `max`, `step`, `unit` (display string e.g. `"ms"`) |
| `seg` | `options = { {label, value}, ... }` |
| `action` | `btnLabel`, `danger` (bool), `onAction()` |
| `group` | `items = { ... }` (array of nested item definitions) |
| `groupLabel` | `label` (the heading text) |

#### `type = "soundSlot"`

Registers a user-defined sound event slot that appears in **Settings > Sound** alongside the built-in slots (`hover`, `update`, `settingsOpen`, etc.). The user assigns an audio file to the slot from the sound picker.

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

`ms.settings.get("myHitSound")` returns the currently assigned sound name (from `ms.soundAssign`), or `default` if nothing has been assigned. `ms.settings.set` is not supported for `soundSlot` keys, use the Sound section UI to assign sounds.

`soundSlot` items can also be declared inside `ms.menu.define` item lists. They appear in the custom section **and** are extracted into the Sound section automatically.

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
    onAction = function() ms.alert("Calibrating...", 2, true) end,
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
| `icon` | - | Emoji prepended to the title. |
| `items` | yes | Array of item definitions, same fields as `ms.settings.define`. |

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

Hides a built-in panel feature for the current macro pack session. Purely cosmetic, the underlying system keeps working. The item reappears if the call is removed and Hammerspoon reloads.

```lua
ms.features.hide("sensitivity")       -- Camera Sensitivity slider in Tools
ms.features.hide("socd")              -- SOCD Cleaning + Mode rows in Tools
ms.features.hide("trackpad")          -- Trackpad / Pen Mode row in Tools
ms.features.hide("independentBinds")  -- Independent Binds row in Tools
```

> `"sound"` and `"profiles"` cannot be hidden, they are required for core functionality.

---

### `ms.setClickLevel(n)` *(internal)*

> **Internal API.** `ms.setClickLevel` was a legacy bridge function and is not part of the public API. Do not call it from macro packs. To expose a click-level setting, use `ms.settings.define` with a `seg` type and manage the value in your own `onChange` callback.

---


# mudscript plugins (source)

Plugin **source** bundles. A plugin is a Hammerspoon Spoon
(`<Name>.spoon/init.lua`) that registers through the `ms` it is loaded with, so
`ms.plugins` can load and cleanly unload it (see `mac/lib/ms_plugins.lua`).

These do **not** ship with `deploy.sh` - `~/.hammerspoon/Spoons` is the
*installed-plugin* directory, populated by the plugin import flow, which records
each bundle in Guardian's ledger and hash-verifies it on boot. To try one during
development, enable dev mode (the import gate's escape hatch) and copy the bundle
into `~/.hammerspoon/Spoons/`:

```bash
cp -R plugins/Roblox.spoon ~/.hammerspoon/Spoons/
```

Then reload Hammerspoon and enable it in Settings >> Plugins.

## Contract every plugin follows

- Register only through `ms` (`ms.bind`, `ms.bus`, `ms.key`, `ms.settings`,
  `ms.tools`, `ms.setTargetApp`, `ms.cam.setTransform`, ...). A plugin's
  `ms.setTargetApp` only offers the app: the user's choice in Macros > Manager
  and a handwritten `ms_macros.lua` declaration both outrank it. Anything registered directly with
  Hammerspoon (`hs.hotkey.bind`, `hs.timer.new`) is invisible to teardown and
  keeps firing after the plugin is switched off.
- Do setup in `obj:init()` and undo the rest in `obj:stop()` - the proxy unwinds
  binds/settings/tools automatically; `:stop()` handles state it never saw
  (target app, timers, namespaces).

## Bundles

- **Roblox.spoon** - declares Roblox as the macro target; live reader for
  Roblox's saved settings (`ms.roblox.sensitivity()`, `.framerateCap()`, ...);
  anti-timeout keep-alive; and the cache-cleaner launchd agent (assets in
  `Roblox.spoon/bin/`, toggle "Roblox Cache Cleaner").
- **HIDInject.spoon** - opt-in HID injection: `ms.hid.*` input functions that
  post directly to the target app process, for games that ignore global event
  posts. Not present in base mudscript; uninstalling removes the capability.
- **Minecraft.spoon** - declares Minecraft as target; live client data
  (`ms.mc.health()`, `.durabilityPct(slot)`, `.hasItem(id)`, ...) via the
  `ms-mc-bridge` mod over a loopback WebSocket. Requires that mod running in the
  client (see `../../ms-mc-bridge`).

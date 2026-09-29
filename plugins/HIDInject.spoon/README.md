# HIDInject

Opt-in HID injection for mudscript. **Not part of base mudscript** - the core
input API always posts to the global event stream. This plugin adds a parallel
`ms.hid.*` namespace that posts input **directly to the target app process**
(`event:post(app)` / `CGEventPostToPSN`), for games that ignore global posts.

Installing the plugin is the opt-in; removing it takes the capability out of the
process entirely. A runtime **"HID Injection Armed"** toggle disarms it without
uninstalling.

## API

| Function | Description |
|----------|-------------|
| `ms.hid.press(key, mods)`   | Key-down, posted to the target app. |
| `ms.hid.release(key, mods)` | Key-up. |
| `ms.hid.type(key, mods, holdMs)` | press + hold + release. |
| `ms.hid.click(button)`      | Mouse click at the cursor (`0`=left, `1`=right, `2+`=other). |
| `ms.hid.releaseAll()`       | Release everything this plugin is holding. |
| `ms.hid.available()`        | `true` when armed and the target app is running. |

The target app is whatever `ms.setTargetApp()` set (read live each call).

## Migrating from the old core parameter

Base mudscript used to accept a `hidinject` boolean on `ms.press`/`ms.type`/
`ms.Mouse`/`ms.mouse`. That parameter is gone. Replace injected calls with the
`ms.hid.*` equivalents:

```lua
-- before (base, removed):
ms.press("w", {}, true)
ms.type("e", {}, true)

-- after (this plugin):
ms.hid.press("w")
ms.hid.type("e")
```

Non-injected calls are unchanged - keep using `ms.press`, `ms.type`, `ms.Mouse`.

## A note on intent

HID injection can bypass anti-cheat that filters global input. It exists because
some games don't respond to global posts at all. Don't use it against a game
whose terms prohibit input automation.

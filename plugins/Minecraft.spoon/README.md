# Minecraft

Starter Minecraft plugin for mudscript. Declares Minecraft as the macro target
and bridges to the [`ms-mc-bridge`](../../../ms-mc-bridge) client mod, which
serves live game state over a loopback WebSocket (`ws://127.0.0.1:47600`). Macros
read the player's health, inventory, armor durability, held item, options, and
crosshair target through `ms.mc.*`.

Requires the `ms-mc-bridge` mod running in the client. Registers through the
proxied `ms`; `:stop()` closes the socket, clears the target, and drops the
`ms.mc` namespace.

## Freshness - two modes

Macros have two needs, so there are two paths:

- **Point-of-use** (`ms.mc.health()` and friends): sends a request and waits for
  the reply, so the value is the one true for that instant. Valid only inside a
  running macro - it yields the coroutine.
- **Non-blocking** (`ms.mc.cached(topic)`): returns the last value pushed by the
  mod's per-tick subscription (~50 ms old at worst). Safe anywhere, including
  outside a macro.

The convenience readers prefer a fresh query inside a macro and fall back to the
cache otherwise, so a call from an action button still returns something rather
than erroring.

## API

| Function | Description |
|----------|-------------|
| `ms.mc.health()` / `.maxHealth()` / `.hunger()` | player vitals |
| `ms.mc.heldItem()` / `.armor()` | item objects (id, count, durability) |
| `ms.mc.position()` / `.target()` / `.options()` | pos, crosshair target, settings |
| `ms.mc.durabilityPct(slot)` | `"main"`/`"off"`/`"head"`/`"chest"`/`"legs"`/`"feet"` |
| `ms.mc.hasItem(id)` / `.countItem(id)` | inventory queries |
| `ms.mc.query(q [, timeoutMs])` | raw point-of-use query |
| `ms.mc.cached(topic)` / `.isConnected()` | non-blocking read / status |

## Notes

- The frontmost app name is assumed to be `"Minecraft"` (Prism/Modrinth set it);
  adjust `ms.setTargetApp` if focus detection misses (it may be `"java"`).
- Queries return `nil` when the bridge is offline, so macros degrade gracefully.

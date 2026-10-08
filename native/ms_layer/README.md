# ms_layer

`ms_layer` is the native input layer. It runs one OS input hook and decides
pass or swallow for every key, mouse button and scroll event itself. The host
sends it the bind table and hears about matches after the fact, so no Lua runs
inside the hook.

It handles:

- key binds, combos and modifier-only binds
- mouse button and scroll binds
- the panic hotkey
- SOCD cleaning (`lastWins`, `firstWins`, `neutral`)
- trackpad holds, including retyping moves as drags on macOS
- held-key tracking, kept across macro enable and disable

If macOS disables the hook for timing out, the daemon re-arms it at once.

## Layout

```
src/engine.rs        platform-independent logic and its unit tests
src/keys.rs          key names (the same names as hs.keycodes.map)
src/protocol.rs      wire protocol types
src/platform/        macos.rs (CGEventTap)
                     windows.rs (WH_KEYBOARD_LL and WH_MOUSE_LL)
                     unsupported.rs (every other OS: builds, reports "unsupported")
```

Synthetic events carry the tag `999` (`eventSourceUserData` on macOS,
`dwExtraInfo` on Windows). Hammerspoon's `ms.press` uses the same tag, so
neither side reacts to the other's injected input.

## Build and install

```
cd native/ms_layer
cargo test
cargo build --release
mkdir -p ~/.local/bin
cp target/release/ms_layer ~/.local/bin/
```

`mac/lib/core/native_layer.lua` starts the daemon when
`~/.local/bin/ms_layer` exists, and `deploy.sh` rebuilds it once it is
installed. Hammerspoon launches the daemon, so macOS normally counts it under
Hammerspoon's Accessibility and Input Monitoring grant. If the hook cannot be
created, the daemon reports a `permission` error and the Lua eventtaps stay in
charge.

The Lua eventtaps are only stopped after the daemon reports `ready`. If the
daemon exits more than three times after that, mudscript reloads once on the
Lua eventtaps and tries the daemon again on the next manual reload.

Console controls: `ms.layer.disable()` and `ms.layer.enable()`.

## Protocol

Newline-delimited JSON. Commands go to stdin with a `"c"` tag, events come out
of stdout with an `"e"` tag. The daemon exits when stdin closes, so it never
outlives its host with a hook installed.

Commands:

```
{"c":"config","binds":[...],"panic":{"key":"p","mods":["ctrl"]},"swallow_hotkeys":true,
 "socd":{"on":true,"mode":"lastWins","pairs":[["a","d"],["w","s"]]},
 "trackpad":{"on":true,"left":"n","right":"j"}}
{"c":"state","enabled":true,"target":true}
{"c":"ping"}
{"c":"quit"}
```

A bind:

```
{"id":7,"t":"key","key":"e","mods":["shift"],"mode":"exact","also":["z"],
 "swallow":true,"system":false,"release":true}
```

- `t`: `key`, `mods` (modifier-only), `mouse` or `scroll`
- `mode`: `exact`, `subset` or `any`
- `button` for mouse: 0 left, 1 right, 2 middle, 3 back, 4 forward
- `dir` for scroll: `up` or `down`
- every field except `id` and `t` is optional

Events:

| Event | Meaning |
| --- | --- |
| `{"e":"ready","version":"0.1.0","platform":"macos"}` | the hook is live |
| `{"e":"fire","id":7,"edge":"down","m":8}` | a bind matched, `m` is cmd 1, alt 2, ctrl 4, shift 8 |
| `{"e":"panic"}` | the panic hotkey was pressed, the host decides what to do |
| `{"e":"k","k":"w","d":true,"m":0}` | a physical key went down or up |
| `{"e":"m","b":0,"d":true}` | a physical mouse button went down or up |
| `{"e":"revived"}` | the OS disabled the hook and the daemon re-armed it |
| `{"e":"warn","msg":"..."}` | a bad bind or command was skipped |
| `{"e":"error","code":"permission","msg":"..."}` | the hook could not start |
| `{"e":"pong"}` | reply to `ping` |

## Platform status

- macOS and Windows backends compile but are untested on hardware.
- Windows has no Lua host wired to the daemon yet.
- Linux needs an evdev and uinput backend.
- `ms.systemBinds` and the open-menu hotkey still use Lua eventtaps.

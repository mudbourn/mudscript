# ms_layer - native input layer

`ms_layer` is a small Rust daemon that runs **one** OS input hook and makes
every pass/swallow decision itself. The host (Hammerspoon Lua on macOS today)
mirrors its bind tables to the daemon and only hears about events after the
fact, so Lua is never on the per-keystroke critical path.

It replaces these Lua eventtaps with a single native one:

| Lua tap (before)                      | Daemon (now)              |
|---------------------------------------|---------------------------|
| `ms._keyListener` (key + modifier binds) | `engine::on_key_bind`, `on_modifiers_changed` |
| panic hotkey watcher (`_makeKeyWatcher`) | `engine::on_panic`        |
| `ms._socdListener`                    | `engine::on_socd`         |
| trackpad left/right hold listeners + drag tap | `engine::on_trackpad` + drag retype |
| `ms._mouseListener`                   | `engine::on_button`       |
| `ms._scrollListener`                  | `engine::on_scroll`       |

Up to five Lua callbacks per keypress become zero. Since nothing slow runs
inside the hook, macOS has no reason to disable it for timing out (the daemon
re-arms it if it ever does), and the 2 s tap watchdog has nothing left to do
for these taps.

Held-key tracking survives enable/disable, so a key held through an alt-tab
still counts when you come back.

## Layout

```
src/engine.rs     platform-independent logic + unit tests (cargo test)
src/keys.rs       key vocabulary (Hammerspoon hs.keycodes.map names)
src/protocol.rs   wire protocol types
src/platform/     macos.rs (CGEventTap), windows.rs (WH_KEYBOARD_LL/WH_MOUSE_LL),
                  unsupported.rs (Linux and others: builds, reports "unsupported")
```

The engine and protocol are shared across platforms, so a backend only maps
native codes to key names, reports events, and posts synthetic ones. Synthetic
events carry the tag `999` (`eventSourceUserData` on macOS, `dwExtraInfo` on
Windows), the same value Hammerspoon's `ms.press` uses, so neither side
reacts to the other's injected input.

## Build & install

```
cd native/ms_layer
cargo test
cargo build --release
mkdir -p ~/.local/bin && cp target/release/ms_layer ~/.local/bin/      # macOS
copy target\release\ms_layer.exe %USERPROFILE%\.local\bin\             # Windows
```

On macOS, `mac/lib/core/native_layer.lua` starts the daemon automatically
when `~/.local/bin/ms_layer` exists. Because Hammerspoon launches it, macOS
normally attributes the tap to Hammerspoon's existing Accessibility / Input
Monitoring grant. If the tap can't be created, the daemon reports a
`permission` error, the Lua taps stay in charge, and an alert explains what to
allow.

Opt out without uninstalling: `ms.layer.disable()` from the console
(`ms.layer.enable()` to undo). If the daemon dies more than three times after
taking over, mudscript reloads once on the Lua taps and tries native again on
the next manual reload.

## Protocol

Newline-delimited JSON. Host to daemon on stdin (`"c"`), daemon to host on
stdout (`"e"`). The daemon exits when stdin closes, so it can never outlive
its host with a hook still installed.

Commands:

```
{"c":"config","binds":[...],"panic":{"key":"p","mods":["ctrl"]},"swallow_hotkeys":true,
 "socd":{"on":true,"mode":"lastWins","pairs":[["a","d"],["w","s"]]},
 "trackpad":{"on":true,"left":"n","right":"j"}}
{"c":"state","enabled":true,"target":true}
{"c":"ping"}  {"c":"quit"}
```

Binds: `{"id":7,"t":"key","key":"e","mods":["shift"],"mode":"exact|subset|any",
"also":["z"],"swallow":true,"system":false,"release":true}`, with `t` one of
`key`, `mods` (modifier-only), `mouse` (`button`: 0 left, 1 right, 2 middle,
3 back, 4 forward) and `scroll` (`dir`: `up`/`down`). Every field except `id`
and `t` is optional.

Events:

```
{"e":"ready","version":"0.1.0","platform":"macos"}   hook is live
{"e":"fire","id":7,"edge":"down","m":8}              bind matched (m: cmd 1, alt 2, ctrl 4, shift 8)
{"e":"panic"}                                        panic hotkey; the host decides
{"e":"k","k":"w","d":true,"m":0}                     physical key transition
{"e":"m","b":0,"d":true}                             physical mouse button transition
{"e":"revived"}  {"e":"warn","msg":"..."}  {"e":"error","code":"permission","msg":"..."}  {"e":"pong"}
```

## Status

- macOS and Windows backends type-check (`cargo clippy --target
  aarch64-apple-darwin` / `x86_64-pc-windows-gnu`) but haven't been run on
  real hardware yet.
- Windows has no Lua host yet. The daemon is ready for whichever host the
  Windows port uses, and `win/bin/ms_gc_read` keeps handling gamepads.
- Linux needs an evdev grab + uinput backend.
- Still on Lua taps: `ms.systemBinds` and the `hs.hotkey` open-menu hotkey.

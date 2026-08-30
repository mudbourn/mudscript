# ms_gc_read — Windows gamepad reader

Cross-platform SDL2 port of `mac/bin/ms_gc_read.swift`. It detects connected
controllers and streams button / stick / connect / disconnect events as
newline-delimited JSON on stdout. The host (`ms_core.lua` → `ms.gamepadStart`)
consumes these lines the same way on every platform — **the wire protocol is
identical to the macOS reader**, so all binding, chord, and conflict-detection
logic in Lua/JS is unchanged.

## Protocol

One JSON object per line:

```
{"e":"press","b":"x","c":"ds4","p":0}
{"e":"release","b":"x","c":"ds4","p":0}
{"e":"move","b":"left","x":0.5,"y":-0.3,"c":"ds4","p":0}
{"e":"connect","c":"ds4","p":0}
{"e":"disconnect","c":"ds4","p":0}
```

- **Buttons** (`b`): `a b x y l1 r1 l2 r2 l3 r3 up down left right menu options home`
- **`c`** controller type: `ds4 | xbox | switch | generic`
- **`p`** player slot (0-based)
- Sticks emit `move` with `x`/`y` in `[-1,1]`, **up-positive**, 0.05 deadzone.
- Triggers (`l2`/`r2`) report as press/release, not analog (matches macOS).

Chord bindings need no reader changes: the host tracks held buttons across
these press/release events and matches the most specific combo (e.g. `l1+x`
beats a bare `x`), exactly as on macOS.

## Modes

```
ms_gc_read            daemon mode — stream events (one JSON line each)
ms_gc_read --list     list connected controllers, then exit
```

## Building

Needs SDL2 development libraries (2.0.14+ recommended for full controller-type
detection) and either MSVC or MinGW-w64.

```
set SDL2_DIR=C:\path\to\SDL2-devel
build.bat
```

`build.bat` auto-detects `cl.exe` (Developer Command Prompt) or `gcc.exe`,
produces `ms_gc_read.exe`, and copies `SDL2.dll` alongside it. Ship
`ms_gc_read.exe` **and** `SDL2.dll` together on the host's PATH — the host
launches the bare name `ms_gc_read`.

The same source also builds on macOS/Linux for testing:

```
cc -O2 ms_gc_read.c $(pkg-config --cflags --libs sdl2) -o ms_gc_read
```

## SDL3

The GameController API used here is SDL2. SDL3 renamed it to the Gamepad API
(`SDL_Gamepad*`, `SDL_EVENT_GAMEPAD_*`); porting is mechanical but the symbol
names differ, so build against SDL2 unless you also migrate the identifiers.

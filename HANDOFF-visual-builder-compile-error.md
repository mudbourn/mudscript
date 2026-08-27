# RESOLVED — Visual Builder wipeout on compile error

**Status: fixed 2026-08-27.** Root cause found and corrected on both sides.
Left in place as a record; safe to delete.

## Root cause (worse than the original hypothesis)
The builder compiles **every** visual macro into ONE file
(`~/.hammerspoon/data/ms_macros_visual.lua`) which `ms.compiler.load` runs as a
**single chunk**. `pcall(ms.compiler.compile, def)` only catches errors thrown by
the *emitter* — it does **not** catch syntax errors in the *emitted text*. A raw
`code` step or a hand-typed `condition` (both pass through verbatim) can emit
broken Lua that compiles "successfully" into the file. Then the whole-file
`load()` fails, so **none** of the macros register — every bind flips to "Unset",
every visual macro disappears, and save looks successful. That's the wipeout.

The JSON store was never actually corrupted: `ms.compiler.list`/`get` read the
JSON directly, so the data survived — the damage was entirely in the compiled
runtime.

## The fix
**`mac/lib/ms_compiler.lua`**
- New `syntaxError(src)` parses each macro's emitted source on its own
  (`loadstring` on LuaJIT / `load(...,"t")` on 5.2+) — parse only, never executed.
- New `ms._brokenMacro(spec)` runtime helper + `brokenMacroSource()` emitter:
  a macro that fails to parse is replaced by a stub that **still registers via
  `ms.bind.define`** (keeps its list slot AND key bind) but alerts + errors when
  run. Failure is isolated to the one macro and made visible.
- `rebuild` records failures in `ms.compiler._errors[id]`. Function tools get the
  same per-chunk validation (fallback to a comment, which stays loadable).

**`mac/ms_core.lua`** — `ui:macros:saveMacro` handler now reads
`ms.compiler._errors[id]` and, on failure, sends
`shellReceive('macros','saveError',{id,err})` instead of silently succeeding.

**`ui/modules/panel-macros.js`** — `saveMacro()` no longer optimistically clears
`_macroDirty`; it waits for the host ack. New `saveError` handler keeps the macro
dirty + selected and shows the compile error via `showTestToast` (Test is no
longer the only signal).

## Verified
Headless LuaJIT smoke test: a good macro + a deliberately broken `code`-step
macro → rebuild catches the broken one with a precise syntax error, the generated
file **loads as one chunk**, and **both** macros register (broken one quarantined,
bind intact). Before the fix this load failed wholesale and neither registered.
Real user data (`Combat Warriors Macros`, 2 macros + 2 function tools) regenerated
clean and left intact.

## The user's real goal: re-entrancy guard — DON'T hand-wire a flag
A per-group re-entrancy guard already exists: `ms_core.lua` `firedFn` (~L4976) —
if `ms.running[group]` is set the fire returns immediately; firing arms a timer
that clears after `cooldown` ms (default 1000). So "am I already running?" is
built in, keyed off the macro's `cooldown`, and **self-heals** (a dead run can't
wedge it — unlike a disk-persistent `ms.vars` flag would).

Open items for the picking-up session (discuss with user first):
1. The guard is **per group**, and all visual macros share `visual - main` /
   `visual - optional` — so one macro's cooldown blocks its siblings. Per-macro
   isolation would be a small change (key `ms.running` by id, or by group+id).
2. The builder has **no UI to set cooldown** — `panel-macros.js` only carries an
   existing `_currentMacroDef.cooldown` through a save. Adding a cooldown field is
   the clean way to let the user tune the guard for a longer-running macro.

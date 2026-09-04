# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Writing and code style

`ignore/writing_style.txt` governs how **code** is formatted in this repo (table layout, section-fold markers, blank lines, the no-comments rule) as well as prose. Read it before editing ANY file — Lua, JS, HTML/CSS, docs, commit messages — not only when writing prose. Its examples are Lua but every rule applies to all scripts.

It is not scoped to the lines you add. Per its "ALWAYS CHECK ON WORK" rule, any region you touch — the code you change plus its immediate surroundings — must leave more compliant than you found it: strip pre-existing comment monologues, delete values you have overridden rather than stacking new ones on top, and do not add comments explaining why a change was made.

## What this is

mudscript is a macro lab for games, built on **Hammerspoon** (macOS, Lua) with an early **AutoHotkey v2** (Windows) port. macOS is the mature platform; Windows is maintainer-testing only. Both share the same directory layout, the same `ms.*` macro API, and the shared `ui/` web assets, so macro logic ports between them with minimal change. There is no build step for the Lua/AHK code — it runs interpreted in the host runtime.

## Working on the codebase

**There is no npm/package manager, no compiler, and no unit-test suite.** The verification loop is: edit → `deploy` → reload in Hammerspoon → observe. Key facts:

- **Deploy to the live install:** `bash mac/bin/deploy.sh` copies the repo into `~/.hammerspoon/` (core, `lib/`, `ui/`, sounds, registry index, guardian agent) and re-seeds the trust baseline so the Guardian doesn't kill Hammerspoon on the changed files. It also compiles the Swift helper binaries (`ms_gc_read`, `ms_ocr_read`) to `~/.local/bin`. Always deploy through this script — a raw `cp` of `ms_core.lua` trips tamper detection. There is also an in-app `ms.deploy`.
- **UI lint (CI-enforced, runs on every push):** `node bin/ui-lint.mjs`. It blocks (1) hardcoded theme color/font literals in `ui/modules/*.js` — read `var(--accent)`, `var(--font-mono)`, etc. instead — and (2) native macOS controls (`<select>`, `confirm`/`alert`/`prompt`, `type=date/color/file`) in `ui/`. Escape hatch: `ui-lint-allow` in a comment on or directly above the line. Run this before pushing UI changes.
- **`deploy.sh` preflight also blocks native macOS dialogs** (`hs.dialog.blockAlert`, `hs.alert.show`, `hs.chooser`) in `mac/lib` and `mac/*.lua` — they draw *behind* the always-on-top shell and softlock. Use `ms.ui.modal` instead. Guardian is the sole exception.
- **LuaJIT-clean requirement:** Hammerspoon runs LuaJIT (5.1). No 5.3+ syntax — no integer division `//`, no bitwise operators `& | ~`; use `bit.*` or arithmetic instead.

## Architecture

### Boot and the shared `ms` table
`mac/init.lua` (locked `chmod 444`) is a thin stub. It `require`s `lib/ms_guardian.lua` first — that module hashes `ms_core.lua` and only then `dofile`s it — so Guardian runs *before* `ms` exists and is the one lib module that takes no `ms` argument.

`mac/ms_core.lua` (~7000 lines) builds a single shared table `ms` and hands it to each `lib/` module: `package.loaded["lib.ms_<name>"] = nil; require("lib.ms_<name>")(ms)`. The cache-clear lets a deploy+reload pick up edited modules without a full Lua reset. To extract a module, write `return function(ms) ... ms.<name> = {...} ... end`, keeping the body hermetic (only `ms.*`, `hs.*`, Lua stdlib, module locals — no upvalues from core). See `docs/ARCHITECTURE.md` "Extracting a Lua module" for the full recipe and the stub-completeness rule (core's fallback branch must define every method it calls so a failed load degrades instead of crashing).

`mac/lib/` modules: `ms_guardian` (pre-load tamper check), `ms_loading`, `ms_devtools` (logging/tracing/dev panels — on nearly every macro path), `ms_alert` (`ms.alert` toasts), `ms_settings`, `ms_ui` (webview settings panel), `ms_shell` (panel host), `ms_compiler` (visual macro JSON → sandboxed Lua), `ms_package` (`.mspkg` format), `ms_registry` (signed package index client).

### UI (shared web assets in `ui/`)
The settings/dev UI is a Hammerspoon webview loading `ui/ms_shell.html` plus HTML dev panels (`ms_console`, `ms_watcher`, `ms_keys`, `ms_window`). Logic lives in ES modules under `ui/modules/`: `panel-*.js` per shell tab (settings, theme, macros, browse, plugins, console, keys, watcher, window), `log-panel.js` (shared LogPanel factory), plus `tool-*.js` and `ui-select.js`/`ui-tabs.js` shared widgets. Lua↔JS crosses via the webview usercontent bridge — push to the shell with `shellReceive` (not `shellDispatch`, which loops back to Lua). `ms.bus` emits `(topic, payload)` so handlers are `function(_, body)`.

> Note: `docs/ARCHITECTURE.md`'s `ui/modules/` listing is stale — it predates the `panel-*.js` split. Trust the directory over that doc section.

### Macros
Two coexisting formats. Handwritten Lua lives in `ms_macros.lua` (a restricted sandbox — no `hs`, `os`, `io`, shell, or `_G`). The visual builder writes JSON macro definitions to `data/ms_macros_visual.json`, which `ms_compiler.lua` compiles to `data/ms_macros_visual.lua`. Both load at boot; on id collision the handwritten macro wins. Compilation is isolated per-macro — one bad macro is quarantined to a stub rather than sinking the whole file.

### Security / Guardian
Multi-layer integrity model (see `docs/ARCHITECTURE.md` "Security layers"): load-time hash check, an OS-level launchd agent that watches `ms_core.lua` and kills Hammerspoon on mismatch, a locked `init.lua` stub, an RSA-2048-signed `MANIFEST.json` per release, the macro sandbox, and a signed per-file manifest covering all shipped Lua/HTML/scripts. **Integrity is two-sided:** the tracked-file set is defined in *both* `mac/guardian_patterns.json` (CI, drives the signed manifest) and `lib/ms_guardian.lua` `_trackedFiles()` (runtime walk) — a new tracked *directory* must be taught to both or a released build breaks. Third-party plugins live only in `~/.hammerspoon/Spoons/` (never shipped, never first-party) and are gated by the signed `data/.ms_plugin_ledger.json`.

### Plugins
Opt-in `.spoon` bundles that (1) declare the target app whose focus arms keybindings (`ms.setTargetApp`) and (2) add live capabilities macros can read. Shipped: `Roblox`, `Minecraft`, `HIDInject` (direct-to-process input, plugin-only — never in core). They register only through the `ms.*` API so disabling one in Settings cleanly removes what it added; **disabling must not move `.spoon` files** (moving one blocks boot). Nothing in base mudscript depends on any plugin.

### Registry / Browse
"Browse" is the in-app storefront backed by a signed package index. `registry/index.json` in-tree is the source of truth; `mac/bin/registry_*.sh` publish/sign/go-live packages. Every `.mspkg` is verified against the signed index before install; partial ("by the slice") installs pull single assets without duplicating bytes. Client caches for 6h and the CDN can lag.

## Native helpers
Swift sources in `mac/bin/`: `ms_ocr_read.swift` (Vision-framework OCR behind `ms.screen.ocr`; note the Retina coordinate fold) and `ms_gc_read.swift` (GameController input). Compiled by `deploy.sh` when `swiftc` is present. A Rust HID-injection crate lives under `mac/bin/hidinject-rs/` (gitignored `target/`).

## Release
Maintainer runs the **Release** GitHub Actions workflow with a version string; it packages the bundle, signs the hash with `MS_SIGNING_KEY`, stamps `MANIFEST.json`, and cuts a release. Every push to `main` touching `ms_core.lua`/`ms_core_v2.ahk` auto-cuts a `pre-{build}` testing pre-release. Manual bump: `bash mac/bin/make_release.sh <version>`.

## Docs worth reading
- `docs/ARCHITECTURE.md` — directory layout, security layers, module-extraction recipe, update channels, macOS↔Windows differences.
- `docs/DOCS_MAC.md` — full `ms.*` macOS API reference (~1,600 lines).
- `docs/KEY_CODES.md` — key names for binds/captures.

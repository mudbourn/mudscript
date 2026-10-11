# Troubleshooting & Diagnostics

mudscript has three separate switches in **Settings > Developer**. They do different jobs and you can turn on any of them without the others.

| Switch | What it is for | Needs admin | Lowers security |
|--------|----------------|-------------|-----------------|
| **Debug Mode** | Recording a bug the normal logs miss | No | No |
| **Command Line Access** | Inspecting mudscript from Terminal with `mscli` | Yes | Yes, while on |
| **Developer Mode** | Building and testing plugins | Yes | Yes, while on |

---

## Debug Mode

Turn this on when something goes wrong and the Console or Watcher shows nothing useful: a freeze, a reload that hangs, a macro that silently stops, a panel that never opens.

Debug Mode writes its own log, separate from the normal macro and console logs:

```
~/.hammerspoon/logs/debug/ms_debug.log
~/.hammerspoon/logs/debug/ms_debug.prev.log
```

Each reload starts a new log and keeps the previous one as `ms_debug.prev.log`. A log is capped at 4 MB.

### What it records

| Tag | Meaning |
|-----|---------|
| `env` | mudscript, Hammerspoon and macOS versions, screens, frontmost app, accessibility |
| `boot` | Every loading step with its time, and how long boot took |
| `stall` | The app was frozen for more than about a second |
| `console` | Everything printed to the Hammerspoon console, including errors no macro caught |
| `bus` | Internal events, such as buttons pressed in the settings window |
| `app` | Apps launching, quitting and gaining focus |
| `power` | Sleep, wake, screen lock and unlock |
| `screen` | Displays added, removed or rearranged |
| `beat` | A status line every 30 seconds: memory, busy macros, plugins, shell |

Each line reads `time +seconds-since-boot [tag] message`:

```
14:02:11.482 +3.10s [boot] 60% Loading plugins...
14:02:19.007 +10.63s [stall] main thread blocked for 2.41s
```

### Reporting a bug

1. Turn on **Settings > Developer > Debug Mode**.
2. Reload, then make the bug happen again.
3. Press **Copy Debug Report** and paste it into your bug report.
4. Turn Debug Mode off.

Debug Mode stays on across reloads, so it also records the next boot. Beta testers can switch it on from the installer.

### `ms.debug`

| Function | Returns |
|----------|---------|
| `ms.debug.isOn()` | `true` while recording |
| `ms.debug.log(tag, message)` | Adds a line, ignored when off |
| `ms.debug.path()` | Path of the current log |
| `ms.debug.copyReport()` | Copies both logs to the clipboard, returns the byte count |

---

## Command Line Access

Lets you, or a tool you trust such as a coding agent, look inside a running mudscript from Terminal. It starts Hammerspoon's `hs.ipc` listener and nothing else. Guardian and the plugin gate stay on.

> **Warning:** while it is on, any program running as you can send Lua to Hammerspoon, which can press keys and move the mouse. Turn it off when you are done.

Turning it on or off asks for administrator permission, so a program cannot quietly switch it on.

### `mscli`

Deploying installs `mscli` into `~/.local/bin`. It needs Hammerspoon's `hs` tool. If `hs` is missing, run `hs.ipc.cliInstall()` in the Hammerspoon console once.

```
mscli help
mscli status
mscli macros
mscli log 80
```

| Command | Shows |
|---------|-------|
| `help` | The command list |
| `status` | Versions, target app, frontmost app, which modes are on, memory |
| `macros` | Every macro with its group, on or off, and whether it is running |
| `plugins` | Loaded plugins, and failed ones with their error |
| `settings` | The current value of every macro setting |
| `screens` | Displays, sizes, positions and Retina scale |
| `log [lines]` | The end of the debug log |
| `console [lines]` | The end of the Hammerspoon console |
| `debug on`, `debug off`, `debug report` | Control Debug Mode |
| `reload` | Reload mudscript |

### Raw Lua

`hs -c` runs any Lua and prints what it returns, for anything `mscli` does not cover:

```
hs -c 'return ms._targetApp'
hs -c 'return hs.inspect(ms.registry._defs.myMacro)'
```

---

## Developer Mode

For plugin authors. It turns off the integrity check at boot, stops the Guardian agent from killing Hammerspoon over changed files, and lets plugins load from outside the verified library. It does not start `hs.ipc`. Turn on Command Line Access separately if you also want `mscli`.

Turn it off and use **Trust Current Version** before going back to normal use.

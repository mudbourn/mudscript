# mudscript

**A robust macro lab built for games.**

mudscript lets you write, test, and run macros on macOS, with a visual builder, live debugging tools, and a settings panel that actually makes sense. It's built on [Hammerspoon](https://www.hammerspoon.org/), a well-known, open-source automation platform.

The primary use case is game macros: automating repetitive actions, building complex input sequences, and testing them in a safe sandbox. Expanding beyond game-specific automation is planned for a much later phase of development, once real demand for it emerges.

> **Windows support is in active development.** The Windows version built using AutoHotkey has been discontinued. For all future Windows related information, check out this port of the macOS macro tool mudscript is built on made by me for running the macOS version on Windows. Do keep in mind: I am just one guy and this port is still rough, so please don't harass me with issues related to it. Instead, I would greatly appreciate any patience and proper reporting of genuine bugs found. **If you're looking for a visual macro building tool on Windows, [mudscript is finally almost there](https://github.com/mudbourn/mudspoon)!**

---

## What it does

- **Write macros in plain Lua**: no proprietary scripting language to learn
- **Visual macro builder**: drag-and-drop steps, inline editors, test-run with one click
- **Live debugging**: console, macro monitor, input monitor, window monitor
- **Profiles**: save, switch, export, and import macro packs
- **Plugins**: opt-in bundles that set the target game and add live capabilities (Roblox, Minecraft and more in development), each reviewed and removable
- **Browse**: install profiles, themes, sounds, macros, and plugins from a signed package library, in whole or by the slice
- **Theming**: customize colors, fonts, window radius (icons and language changes planned)
- **Sound system**: assign sounds to macro events, import custom audio
- **Settings panel**: everything in one place, no config file editing required

---

## Who it's for

mudscript is for gamers who want to automate repetitive in-game actions, whether that's farming, combo sequences, inventory management, or testing game mechanics. It's designed to be:

- **Transparent**: you can read every line of code. No obfuscation, no hidden behavior.
- **Safe**: macros run in a sandbox. The tool can't access your files, network, or system without your explicit permission.
- **Maintained**: regular updates, documented API, active development.

---

## Philosophy

I built mudscript to serve the user, not the other way around.

There are a lot of macro tools out there that are either too complicated, too limited, or just plain suspicious. I wanted something that:

1. **Does what it says.** No hidden features, no phone-home, no data collection.
2. **Protects you from bad actors.** The Guardian system verifies that the code you're running is the code I released. If someone tries to modify it and redistribute it as their own, you'll know.
3. **Respects your time.** The visual builder means you don't have to write code if you don't want to. The live tools mean you can see exactly what's happening.
4. **Grows with you.** Start with the visual builder, graduate to writing Lua. The same API supports both.
5. **FOSS, first and foremost.** Software can and should be free and open source for anyone to do what they wish with it. I used to struggle to find good macro software for macOS that was free when I was younger, that never needed to be the case then, and I intend for it to not be now.

I'm not interested in building a tool that hides what it does. If you can't understand what a macro tool is doing, you shouldn't trust it.

## Video Preview

[mudscript utilities 1.3 UI preview](https://www.youtube.com/watch?v=6tPdLf3M5QY)

---

## Getting started

### macOS

```bash
curl -L https://raw.githubusercontent.com/mudbourn/mudscript/main/mac/install.sh | bash
```

This installs mudscript to `~/.hammerspoon/`, sets up the Guardian, and reloads Hammerspoon. You'll be up and running in under a minute.

> **Existing Hammerspoon users, be careful!** The mudscript installer command clears out the install directory. If you don't want to lose your macros, **back up your existing setup by selecting everything in the directory and compressing it into a zip file.** Feel free to leave that zip file somewhere safe outside of the directory afterwards.

**Requirements:** [cURL](https://curl.se/) (free, open-source)

---

## Keybindings

These work when your target app is focused. The target is set by an installed plugin (Roblox, Minecraft, and so on). Base mudscript ships without one:

| Key | Action |
|---|---|
| `Alt/Opt + P` | Open settings / macro builder |
| `Alt/Opt + [` | Quick reload |
| `Alt/Opt + F10` | Panic, disable all macros |

System hotkeys also work in Hammerspoon, Activity Monitor, and popped-out panels.

---

## Visual macro builder

The macro builder lets you create macros without writing code:

- **Drag and drop** steps to reorder them
- **Nest blocks**: if/else, for loops, while loops
- **Inline editors**: type values, capture keys, pick modifiers
- **Test run**: execute your macro in a sandbox with live feedback
- **Record mode**: capture your inputs and convert them to macro steps

Find it in the **Macros** panel.

---

## Profiles

Save and switch between macro packs:

- **Save** your current setup (macros, settings, theme)
- **Export** a profile to share with others
- **Import** profiles from `.mspkg` files

Profiles include sounds, themes, and settings, everything you need to switch contexts. Install them yourself, or pull them from **Browse** (below).

---

## Plugins

Plugins are opt-in bundles that extend mudscript for a specific game. A plugin does two things: it declares the **target app** (the window whose focus arms your keybindings), and it adds **live capabilities** macros can read.

- **Roblox**: targets Roblox, exposes its saved settings (sensitivity, framerate cap, graphics quality) to macros, plus an anti-timeout keep-alive.
- **Minecraft**: targets Minecraft, exposes live client data (health, item durability, inventory) over a loopback bridge.
- **HIDInject**: opt-in direct-to-process input for games that ignore global event posts (see the note below).

Every plugin is written or personally reviewed before it can be published, and it registers only through mudscript's own API, so turning one **off** in Settings → **Plugins** cleanly removes everything it added, and uninstalling it removes the capability entirely. Nothing in base mudscript depends on any plugin.

---

## Browse

Browse is the in-app package library. Open it with `Alt+P` → **Browse**.

- **Install by type**: profiles, themes, sounds, macros, and plugins, each in its own section
- **Whole or by the slice**: install a full profile, or pull just its theme, sounds, or macros without duplicating anything
- **Signed and verified**: every package is checked against a signed registry index before it installs. A package that doesn't verify is never offered
- **Curated**: published packages are author-reviewed, so what you install is what was released

---

## Sound system

Assign sounds to macro events:

- **Built-in slots**: startup, load, alert, hover, interact, and more
- **Custom sounds**: import your own `.wav` files
- **Per-macro sounds**: assign specific sounds to individual macros
- **Volume control**: adjust globally or per-sound

---

## Theming

Customize the look and feel:

- **Colors**: background, surface, accent, text, and more
- **Font**: use any installed font
- **Window radius**: round the corners of all panels
- **Live preview**: changes apply instantly

Edit `data/ms_theme.json` or use the Settings panel.

---

## Updates

mudscript checks for updates automatically:

- **Stable channel**: tested releases with signed manifests
- **Testing channel**: latest builds from the development branch

Switch channels from Settings → Developer → Update Channel.

---

## What mudscript is NOT

- **Not a cheat tool.** mudscript is a macro framework. It provides tools to automate input, nothing more. What you choose to automate, how you use it, and any consequences of doing so are entirely your responsibility.
- **Not an endorsement of exploits.** I do not condone using mudscript to develop hacks, exploits, or cheats for games. I have no intention of supporting or encouraging that kind of use. If a game's terms of service prohibit automation, respect that. mudscript exists for games where macros are welcome.
- **Not malware.** Every line of code is readable. The Guardian system protects *you* from tampered versions, not the other way around.
- **Not a data collector.** mudscript doesn't phone home, doesn't track you, and doesn't send anything anywhere.
- **Not a black box.** If you want to understand how it works, read the code. It's all there.

---

## A note on HID injection

HID injection is the ability to send input events directly to a specific application process, bypassing the global event stream. On macOS, it posts to the target app via `CGEventPostToPSN` instead of the standard event system. Some games don't respond to global event posts, so this is the only way to make macros work at all. It can also be used to bypass anti-cheat that filters global input. I understand how it looks.

My position:

- **HID injection is not in base mudscript.** Core key and mouse functions post to the global event stream, full stop. There is no `hidinject` parameter and no direct-to-process path anywhere in the core API.
- **It is available only as an opt-in, removable plugin.** Users who need it install the HIDInject plugin explicitly (see [Plugins](#plugins)). Uninstalling the plugin removes the capability entirely. Nothing in the base codebase references it.
- **I don't condone using this to cheat.** If a game's terms of service prohibit input automation, don't use mudscript for that game. The tool exists for games where macros are welcome.
- **I won't pretend the feature doesn't exist.** Keeping it a clearly-labelled, self-contained plugin is the honest arrangement: present for those who need it, absent for everyone else.

---

## Documentation

- **[Is mudscript safe?](docs/TRUST.md)**: a plain-language look at what mudscript does and does not do
- **[macOS API Reference](docs/DOCS_MAC.md)**: every `ms.*` function documented
- **[Windows API Reference](docs/DOCS_WINDOWS.md)**: Windows-specific API
- **[Key Codes](docs/KEY_CODES.md)**: key name reference for binds and captures
- **[Architecture](docs/ARCHITECTURE.md)**: technical details, directory layout, security model

---

## Contributing

mudscript is open-source under the [MIT License](LICENSE). Contributions are welcome:

- **Bug reports**: open an issue with steps to reproduce
- **Feature requests**: describe what you want and why
- **Code**: fork, branch, PR
- **Documentation**: help improve the docs
- **Macro packs**: share your profiles and macros

---

## License

[MIT License](LICENSE). Use it however you want.

---

## Credits

Built with [Hammerspoon](https://www.hammerspoon.org/) and [AutoHotkey](https://www.autohotkey.com/).

Icons from [Lucide](https://lucide.dev/).

### Sound credits

Sound effects sourced from [The Spriters Resource](https://www.spriters-resource.com/):

- **Custom/macro sounds**: [Devil May Cry 3 (PS2)](https://sounds.spriters-resource.com/playstation_2/dmc3/asset/393835/)
- **Default sound pack**: [Windows 10 Beta Sound Effects](https://sounds.spriters-resource.com/pc_computer/windows10builtinapplications/asset/565854/), [PS2 System BIOS](https://sounds.spriters-resource.com/playstation_2/systembios/asset/430102/), [PSP System BIOS](https://sounds.spriters-resource.com/psp/systembios/asset/446911/), [PS4 System BIOS](https://sounds.spriters-resource.com/playstation_4/systembios/asset/520633/), [Xbox 360 System BIOS](https://sounds.spriters-resource.com/xbox_360/systembios/asset/493534/)

Font: [Almendra](https://fonts.google.com/specimen/Almendra) by Ana Sanfelippo, via [Google Fonts](https://fonts.google.com/) (OFL).

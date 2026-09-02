# Is mudscript safe?

**Short answer: yes, the software is safe to run.** You can read all of it, it keeps to itself, and it does what it says. Nothing calls home, nothing hides from you, and the plain install does not include any of the scary-sounding parts.

There is one real risk, and it is not about the code. If you point input automation at a game that does not allow it, you can get your **game account** banned. That is a choice you make. It is not something the tool does to you. The rest of this page keeps the two things apart so you can tell them apart too.

---

## Pros

- **You can read all of it.** Every line is open source. No hidden code, no scrambled blobs, no "just trust me."
- **The plain install keeps to itself.** `mac/install.sh` copies only the necessities. That is the macro engine, the interface, settings, and sounds. It does not include any game plugins or any input-injection code.
- **No tracking, no calling home.** There is only one piece of code that goes out to the internet, the package library client. It only talks to a fixed list of GitHub addresses. Nothing tracks you and nothing reports back.
- **Everything you download is checked.** The package list is signed, and mudscript checks that signature every time. Every package you download is checked by its hash before it installs. If a package does not check out, you never see it.
- **The risky powers are opt-in and easy to remove.** Anything that could carry risk lives in a separate plugin. You install it on purpose, and you can remove it fully. The plain install needs none of them.

---

## Concerns and Cons

### "It has a system watching my files."

This one is there to protect you. The Guardian system checks the core against a signed list from each release, and it refuses to start a changed copy. The whole point is this. If someone takes mudscript, slips something into it, and hands it to you as "mudscript," you find out. It is a way to be sure the code you run is the code that was released. It is not a way to hide things from you. It watches the install. It does not watch you.

### "It can reach the internet."

Only in one place, and only to fetch the package library from GitHub. The list of addresses is fixed in the code, so a bad entry in the package list cannot send it somewhere else. Every list is checked for a valid signature, and every package is checked by its hash. There is no tracking address, no crash reporting, no account, and nothing that sends your data anywhere.

### "It can send input straight into a game. Is that a hack?"

It is an opt-in plugin. It is not part of plain mudscript. Sending input straight to an app, instead of through the normal system, exists for games that ignore normal automation. It ships as a **separate plugin, HIDInject**, that you install on purpose. Remove the plugin and the power is gone. Nothing in the plain install even mentions it.

It is real, and the project does not pretend it is not. Its own README warns that it can get past anti-cheat and tells you not to use it where automation breaks a game's rules. That honesty is the point. This is where the real risk lives, and it is a behavior risk, not a bad-code risk. See [the real risk](#the-one-real-risk-and-why-it-is-your-call) below.

### "The Roblox plugin reads my Roblox settings. What is it doing with them?"

Reading them, and nothing more. The Roblox plugin opens your saved-settings file **read only**. That is your sensitivity, FPS cap, graphics quality, volume, fullscreen, and camera setting. Macros use them to match your real settings. There is no code that writes to that file. You can check this in the source. It would also be pointless, since you cannot change those settings mid-game.

Its two features that can write anything are both normal and both off until you turn them on:
- A **cache cleaner** that only removes throwaway Roblox cache and log files. It sets up a small helper under **your own** `~/Library/LaunchAgents/` folder. It never touches the game, your settings, or anything Roblox cares about. I have personally seen it save gigabytes of storage that would be hard to track down and free without special tools built for looking around your entire drive.
- An **anti-timeout** helper that sends one harmless `F15` key press on a timer to avoid the idle kick. Off unless you turn it on.

### Punishment Risks (per-game)

Everything above is about whether the software can be trusted. It can. This part is the real risk, and it has nothing to do with the code being safe.

**Automating input in a game that does not allow it can get your game account banned.**

This is true of any macro. It is true of mudscript, of a macro key on a keyboard, of anything. Modern anti-cheat watches how you act, not your files. It does not matter how clean the tool is. If you aim automation at a game whose rules say no, that is the risk you take, and it is on you.

Keep two things straight:

- **Reading game data and changing your own settings or cache**, the kind of thing the plain tool and the Roblox reader do, is low risk. It is the same sort of thing as alternate launchers and config tools.
- **Automating input**, meaning macros, and above all HID injection, is a higher risk. It is exactly what behavior-based anti-cheat looks for. The method under the hood does not change that.

So here it is. mudscript will not harm your computer, take your data, or do anything behind your back. Whether you should aim it at a given game is a different question. The honest answer is to read that game's rules and decide for yourself. mudscript is made for games where macros are welcome.

---

## Do not take my word for it

- **Read the code.** It is all here. Start with `mac/install.sh` to see exactly what the plain install copies.
- **Check the internet part** in `mac/lib/ms_registry.lua`. The address list and the signature checks are right there.
- **Check the injection claim.** Search the plain `mac/` folder for any straight-to-app input path. There is none. It lives only in the HIDInject plugin.
- **Read the [Architecture](ARCHITECTURE.md) page** for the full security model.

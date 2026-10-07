(function() {
    "use strict";

    // Enum option sets //
        var MOUSE_OPS = ["Move", "Click", "DoubleClick", "TripleClick", "Drag", "Press", "Release"];
        var MOUSE_BTNS = ["Left", "Right", "Center", "Button4", "Button5"];
        var MOUSE_REFS = [
            { value: "Absolute",     label: "Absolute (screen coords)" },
            { value: "Mouse",        label: "Mouse (relative to cursor)" },
            { value: "Follow",       label: "Follow cursor (no move)" },
            { value: "WindowTL",     label: "Window - Top-Left" },
            { value: "WindowTR",     label: "Window - Top-Right" },
            { value: "WindowBL",     label: "Window - Bottom-Left" },
            { value: "WindowBR",     label: "Window - Bottom-Right" },
            { value: "WindowCenter", label: "Window - Center" },
            { value: "ScreenTL",     label: "Screen - Top-Left" },
            { value: "ScreenTR",     label: "Screen - Top-Right" },
            { value: "ScreenBL",     label: "Screen - Bottom-Left" },
            { value: "ScreenBR",     label: "Screen - Bottom-Right" },
            { value: "ScreenCenter", label: "Screen - Center" }
        ];
        var SCROLL_DIRS = ["up", "down", "left", "right"];
        var WINDOW_OPS = ["Move", "Resize", "Frame"];
    // END Enum option sets //

    // Function Registry //
        var REGISTRY = [
            {
                id: "ms.type",
                name: "ms.type",
                label: "Type Key",
                sig: "ms.type(key, mods)",
                desc: "Type a key with optional modifiers. Full keypress cycle (down+up).",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.press",
                name: "ms.press",
                label: "Press Key",
                sig: "ms.press(key, mods)",
                desc: "Send key-down only.",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.release",
                name: "ms.release",
                label: "Release Key",
                sig: "ms.release(key)",
                desc: "Send key-up only.",
                category: "input",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.hold",
                name: "ms.hold",
                label: "Hold Key",
                sig: "ms.hold(key)",
                desc: "Hold a key down without releasing.",
                category: "input",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.toggle",
                name: "ms.toggle",
                label: "Toggle Key",
                sig: "ms.toggle(key, mods)",
                desc: "Toggle a key: if held, release; if not held, press.",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.multiPress",
                name: "ms.multiPress",
                label: "Press Key Sequence",
                sig: "ms.multiPress(keys, delayMs, mods)",
                desc: "Press a sequence of keys in order with optional delay.",
                category: "input",
                params: [
                    { name: "keys",    type: "string", label: "Keys (comma-separated)", required: true },
                    { name: "delayMs", type: "number", label: "Delay (ms)",             required: false },
                    { name: "mods",    type: "mods",   label: "Modifiers",              required: false }
                ]
            },

            {
                id: "ms.copy",
                name: "ms.copy",
                label: "Copy Text",
                sig: "ms.copy(text)",
                desc: "Copy text to system clipboard.",
                category: "clipboard",
                params: [
                    { name: "text", type: "string", label: "Text", required: true }
                ]
            },
            {
                id: "ms.paste",
                name: "ms.paste",
                label: "Paste Text",
                sig: "ms.paste()",
                desc: "Paste current clipboard contents.",
                category: "clipboard",
                params: []
            },

            {
                id: "ms.wait",
                name: "ms.wait",
                label: "Wait",
                sig: "ms.wait(ms)",
                desc: "Pause macro execution for N milliseconds.",
                category: "timing",
                params: [
                    { name: "ms", type: "number", label: "Milliseconds", required: true }
                ]
            },
            {
                id: "action_delay",
                name: "action_delay",
                label: "Step Delay",
                sig: "set action delay (ms)",
                desc: "Keyboard-Maestro style: auto-insert this pause between all following steps (0 = off).",
                category: "timing",
                params: [
                    { name: "delayMs", type: "number", label: "Delay between steps (ms)", required: true }
                ]
            },
            {
                id: "ms.randWait",
                name: "ms.randWait",
                label: "Random Wait",
                sig: "ms.randWait(min, max)",
                desc: "Wait a random duration between min and max ms.",
                category: "timing",
                params: [
                    { name: "min", type: "number", label: "Min (ms)", required: true },
                    { name: "max", type: "number", label: "Max (ms)", required: true }
                ]
            },
            {
                id: "ms.jitter",
                name: "ms.jitter",
                label: "Jittered Wait",
                sig: "ms.jitter(base, jitterMs)",
                desc: "Wait base ms plus/minus random jitter.",
                category: "timing",
                params: [
                    { name: "base",     type: "number", label: "Base (ms)",   required: true },
                    { name: "jitterMs", type: "number", label: "Jitter (ms)", required: true }
                ]
            },
            {
                id: "ms.waitApp",
                name: "ms.waitApp",
                label: "Wait for App",
                sig: "ms.waitApp(appName, timeout)",
                desc: "Wait until an app is running.",
                category: "timing",
                params: [
                    { name: "appName", type: "string", label: "App Name",  required: true },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },
            {
                id: "ms.waitNotApp",
                name: "ms.waitNotApp",
                label: "Wait for App to Leave",
                sig: "ms.waitNotApp(appName, timeout)",
                desc: "Wait until an app stops running.",
                category: "timing",
                params: [
                    { name: "appName", type: "string", label: "App Name",  required: true },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            {
                id: "ms.Mouse",
                name: "ms.Mouse",
                label: "Mouse Action",
                sig: "ms.Mouse(operation, button, reference, x1, y1, x2, y2, holdMs)",
                desc: "Unified mouse API (click, move, drag at coordinates).",
                category: "mouse",
                params: [
                    { name: "operation", type: "enum", options: MOUSE_OPS,  label: "Operation", required: true },
                    { name: "button",    type: "enum", options: MOUSE_BTNS, label: "Button",    required: true },
                    { name: "hold",      type: "number", unit: "ms", default: 50, label: "Hold (ms)", required: false },
                    { name: "reference", type: "enum", options: MOUSE_REFS, label: "Reference", required: true },
                    { name: "x1",        type: "number",  label: "X1",                          required: true },
                    { name: "y1",        type: "number",  label: "Y1",                          required: true },
                    { name: "x2",        type: "number",  label: "X2",                          required: false },
                    { name: "y2",        type: "number",  label: "Y2",                          required: false }
                ]
            },
            {
                id: "ms.scroll",
                name: "ms.scroll",
                label: "Scroll",
                sig: "ms.scroll(direction, clicks)",
                desc: "Post a scroll event.",
                category: "mouse",
                params: [
                    { name: "direction", type: "enum", options: SCROLL_DIRS, label: "Direction", required: true },
                    { name: "clicks",    type: "number", label: "Clicks",                        required: true }
                ]
            },
            {
                id: "ms.moveMouse",
                name: "ms.moveMouse",
                label: "Move Mouse",
                sig: "ms.moveMouse(x, y, ref, durationMs)",
                desc: "Smooth mouse movement.",
                category: "mouse",
                params: [
                    { name: "x",          type: "number", label: "X",          required: true },
                    { name: "y",          type: "number", label: "Y",          required: true },
                    { name: "ref",        type: "enum", options: MOUSE_REFS, label: "Reference",  required: false },
                    { name: "durationMs", type: "number", label: "Duration (ms)", required: false }
                ]
            },
            {
                id: "ms.dragPath",
                name: "ms.dragPath",
                label: "Drag Along Path",
                sig: "ms.dragPath(points, button, ref, delayMs)",
                desc: "Drag through a sequence of points.",
                category: "mouse",
                params: [
                    { name: "points", type: "string", label: "Points (x,y;x,y)", required: true },
                    { name: "button", type: "enum", options: MOUSE_BTNS, label: "Button",     required: false },
                    { name: "ref",    type: "enum", options: MOUSE_REFS, label: "Reference",  required: false },
                    { name: "delayMs",type: "number", label: "Delay (ms)",       required: false }
                ]
            },
            {
                id: "ms.saveCursor",
                name: "ms.saveCursor",
                label: "Save Cursor",
                sig: "ms.saveCursor()",
                desc: "Save current mouse position.",
                category: "mouse",
                params: []
            },
            {
                id: "ms.restoreCursor",
                name: "ms.restoreCursor",
                label: "Restore Cursor",
                sig: "ms.restoreCursor()",
                desc: "Restore saved mouse position.",
                category: "mouse",
                params: []
            },

            {
                id: "ms.window",
                name: "ms.window",
                label: "Move or Resize Window",
                sig: "ms.window(operation, x, y, w, h)",
                desc: "Move or resize the focused window. Move uses (x,y); Resize uses (x=width, y=height); Frame uses all four.",
                category: "window",
                params: [
                    { name: "operation", type: "enum", options: WINDOW_OPS, label: "Operation", required: true },
                    { name: "x", type: "number", label: "X / Width",  required: true },
                    { name: "y", type: "number", label: "Y / Height", required: true },
                    { name: "w", type: "number", label: "Width (Frame)",  required: false },
                    { name: "h", type: "number", label: "Height (Frame)", required: false }
                ]
            },
            {
                id: "ms.windowPos",
                name: "ms.windowPos",
                label: "Window Position",
                sig: "ms.windowPos(appName)",
                desc: "Get the position of an app's window.",
                category: "window",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },

            {
                id: "ms.cam",
                name: "ms.cam",
                label: "Move Camera",
                sig: "ms.cam(dy, dx)",
                desc: "Move camera by delta. Note: params are (dy, dx), vertical first.",
                category: "camera",
                params: [
                    { name: "dy", type: "number", label: "Delta Y", required: true },
                    { name: "dx", type: "number", label: "Delta X", required: true }
                ]
            },
            {
                id: "ms.cam.rebalance",
                name: "ms.cam.rebalance",
                label: "Rebalance Camera",
                sig: "ms.cam.rebalance()",
                desc: "Rebalance camera to neutral.",
                category: "camera",
                params: []
            },
            {
                id: "ms.cam.reset",
                name: "ms.cam.reset",
                label: "Reset Camera",
                sig: "ms.cam.reset()",
                desc: "Reset camera to default.",
                category: "camera",
                params: []
            },

            {
                id: "ms.pixelColor",
                name: "ms.pixelColor",
                label: "Pixel Color",
                sig: "ms.pixelColor(x, y, reference)",
                desc: "Get pixel hex color at position.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "reference", type: "enum", options: MOUSE_REFS, label: "Reference", required: false }
                ]
            },
            {
                id: "ms.pixelMatch",
                name: "ms.pixelMatch",
                label: "Pixel Matches",
                sig: "ms.pixelMatch(x, y, reference, color, tolerance)",
                desc: "Check if pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "reference", type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "color",     type: "string", label: "Color (hex)", required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false }
                ]
            },
            {
                id: "ms.waitPixel",
                name: "ms.waitPixel",
                label: "Wait for Pixel",
                sig: "ms.waitPixel(x, y, ref, color, tolerance, timeout)",
                desc: "Wait until pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "color",     type: "string", label: "Color (hex)", required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },
            {
                id: "ms.waitNotPixel",
                name: "ms.waitNotPixel",
                label: "Wait for Pixel to Change",
                sig: "ms.waitNotPixel(x, y, ref, color, tolerance, timeout)",
                desc: "Wait until pixel changes.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "color",     type: "string", label: "Color (hex)", required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            {
                id: "ms.ocr",
                name: "ms.ocr",
                label: "Read Screen Text",
                sig: "ms.ocr(x, y, w, h)",
                desc: "OCR a screen region and return its text. Blank W/H = whole screen.",
                category: "ocr",
                params: [
                    { name: "x", type: "number", label: "X",          required: false },
                    { name: "y", type: "number", label: "Y",          required: false },
                    { name: "w", type: "number", label: "Width",      required: false },
                    { name: "h", type: "number", label: "Height",     required: false }
                ]
            },
            {
                id: "ms.readNumber",
                name: "ms.readNumber",
                label: "Read Number",
                sig: "ms.readNumber(x, y, w, h)",
                desc: "OCR a region and return the first number in it.",
                category: "ocr",
                params: [
                    { name: "x", type: "number", label: "X",          required: false },
                    { name: "y", type: "number", label: "Y",          required: false },
                    { name: "w", type: "number", label: "Width",      required: false },
                    { name: "h", type: "number", label: "Height",     required: false }
                ]
            },
            {
                id: "ms.findText",
                name: "ms.findText",
                label: "Find Text",
                sig: "ms.findText(text, x, y, w, h)",
                desc: "Find text on screen; returns its center {x,y} to click.",
                category: "ocr",
                params: [
                    { name: "text", type: "string", label: "Text",    required: true },
                    { name: "x",    type: "number", label: "X",        required: false },
                    { name: "y",    type: "number", label: "Y",        required: false },
                    { name: "w",    type: "number", label: "Width",    required: false },
                    { name: "h",    type: "number", label: "Height",   required: false }
                ]
            },
            {
                id: "ms.waitText",
                name: "ms.waitText",
                label: "Wait for Text",
                sig: "ms.waitText(text, x, y, w, h, timeout)",
                desc: "Wait until text appears in a region; returns its {x,y}.",
                category: "ocr",
                params: [
                    { name: "text",    type: "string", label: "Text",       required: true },
                    { name: "x",       type: "number", label: "X",          required: false },
                    { name: "y",       type: "number", label: "Y",          required: false },
                    { name: "w",       type: "number", label: "Width",      required: false },
                    { name: "h",       type: "number", label: "Height",     required: false },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            {
                id: "ms.app",
                name: "ms.app",
                label: "Frontmost App",
                sig: "ms.app()",
                desc: "Get frontmost app name.",
                category: "state",
                params: []
            },
            {
                id: "ms.appRunning",
                name: "ms.appRunning",
                label: "App Is Running",
                sig: "ms.appRunning(appName)",
                desc: "Check if app is running.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.appIsFront",
                name: "ms.appIsFront",
                label: "App Is Frontmost",
                sig: "ms.appIsFront(appName)",
                desc: "Check if app is frontmost.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.focus",
                name: "ms.focus",
                label: "Focus App",
                sig: "ms.focus(appName)",
                desc: "Bring app to front.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.keystate",
                name: "ms.keystate",
                label: "Key Is Held",
                sig: "ms.keystate(key)",
                desc: "Check if a key is currently held.",
                category: "state",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.mousePos",
                name: "ms.mousePos",
                label: "Mouse Position",
                sig: "ms.mousePos()",
                desc: "Get cursor position in reference-space.",
                category: "state",
                params: []
            },
            {
                id: "ms.mousestate",
                name: "ms.mousestate",
                label: "Mouse Button Is Held",
                sig: "ms.mousestate(button)",
                desc: "Check if a mouse button is currently held (left/right/middle).",
                category: "state",
                params: [
                    { name: "button", type: "string", label: "Button (left/right/middle)", required: true }
                ]
            },
            {
                id: "ms.padstate",
                name: "ms.padstate",
                label: "Pad Button Is Held",
                sig: "ms.padstate(button)",
                desc: "Check if a controller button is currently held.",
                category: "state",
                params: [
                    { name: "button", type: "string", label: "Button (a/l2/r3/up...)", required: true }
                ]
            },
            {
                id: "ms.padaxis",
                name: "ms.padaxis",
                label: "Pad Axis Value",
                sig: "ms.padaxis(axis)",
                desc: "Read a stick (x, y from -1 to 1) or trigger (0 to 1).",
                category: "state",
                params: [
                    { name: "axis", type: "string", label: "Axis (left/right/l2/r2)", required: true }
                ]
            },

            {
                id: "ms.sound",
                name: "ms.sound",
                label: "Play Sound",
                sig: "ms.sound(path, async)",
                desc: "Play a sound file.",
                category: "audio",
                params: [
                    { name: "path",  type: "string", label: "Path",  required: true },
                    { name: "async", type: "number", label: "Async", required: false }
                ]
            },
            {
                id: "ms.playSlot",
                name: "ms.playSlot",
                label: "Play Sound Slot",
                sig: "ms.playSlot(slotId)",
                desc: "Play a named sound slot.",
                category: "audio",
                params: [
                    { name: "slotId", type: "string", label: "Slot ID", required: true }
                ]
            },
            {
                id: "ms.setVolume",
                name: "ms.setVolume",
                label: "Set Volume",
                sig: "ms.setVolume(level)",
                desc: "Set system volume (0-100).",
                category: "audio",
                params: [
                    { name: "level", type: "number", label: "Level (0-100)", required: true }
                ]
            },
            {
                id: "ms.mute",
                name: "ms.mute",
                label: "Mute",
                sig: "ms.mute()",
                desc: "Mute system audio.",
                category: "audio",
                params: []
            },
            {
                id: "ms.unmute",
                name: "ms.unmute",
                label: "Unmute",
                sig: "ms.unmute()",
                desc: "Unmute system audio.",
                category: "audio",
                params: []
            },

            {
                id: "ms.alert",
                name: "ms.alert",
                label: "Show Alert",
                sig: "ms.alert(msg, duration)",
                desc: "Show a floating toast notification.",
                category: "utility",
                params: [
                    { name: "msg",      type: "string", label: "Message",       required: true },
                    { name: "duration", type: "number", label: "Duration (ms)", required: false }
                ]
            },
            {
                id: "ms.screenshot",
                name: "ms.screenshot",
                label: "Screenshot",
                sig: "ms.screenshot(path)",
                desc: "Take a screenshot.",
                category: "utility",
                params: [
                    { name: "path", type: "string", label: "Path", required: false }
                ]
            },
            {
                id: "ms.notify",
                name: "ms.notify",
                label: "Notification",
                sig: "ms.notify(title, subTitle, infoText)",
                desc: "Show native macOS notification.",
                category: "utility",
                params: [
                    { name: "title",    type: "string", label: "Title",    required: true },
                    { name: "subTitle", type: "string", label: "Subtitle", required: false },
                    { name: "infoText", type: "string", label: "Info",     required: false }
                ]
            },

            {
                id: "ms.setMacros",
                name: "ms.setMacros",
                label: "Enable or Disable Macros",
                sig: "ms.setMacros(state)",
                desc: "Enable (1) or disable (0) macros.",
                category: "flow",
                params: [
                    { name: "state", type: "number", label: "State (0/1)", required: true }
                ]
            },
            {
                id: "ms.cancelMacros",
                name: "ms.cancelMacros",
                label: "Cancel Macros",
                sig: "ms.cancelMacros(macro)",
                desc: "Cancel a running macro. Leave Macro on All to cancel every running macro, including this one.",
                category: "flow",
                params: [
                    { name: "macro", type: "choice", source: "macros", label: "Macro", required: false }
                ]
            },
            {
                id: "ms.pause",
                name: "ms.pause",
                label: "Pause Macro",
                sig: "ms.pause()",
                desc: "Pause the current macro.",
                category: "flow",
                params: []
            },
            {
                id: "ms.resume",
                name: "ms.resume",
                label: "Resume Macro",
                sig: "ms.resume()",
                desc: "Resume a paused macro.",
                category: "flow",
                params: []
            },
            {
                id: "ms.done",
                name: "ms.done",
                label: "Mark Macro Done",
                sig: "ms.done()",
                desc: "Signal macro completion.",
                category: "flow",
                params: []
            },
            {
                id: "ms.switchProfile",
                name: "ms.switchProfile",
                label: "Switch Profile",
                sig: "ms.switchProfile(name)",
                desc: "Switch to another profile by name. Hotswaps its macros, settings, theme, and sounds live.",
                category: "flow",
                params: [
                    { name: "name", type: "choice", source: "profiles", label: "Profile", required: true }
                ]
            },
            {
                id: "ms.switchPack",
                name: "ms.switchPack",
                label: "Switch Pack",
                sig: "ms.switchPack(slug, kind)",
                desc: "Activate an installed library pack. Kind picks which slice (macro / theme / sound) is swapped in.",
                category: "flow",
                params: [
                    { name: "kind", type: "enum", options: ["macro", "theme", "sound"], label: "Kind", required: true },
                    { name: "slug", type: "choice", source: "pack", dependsOn: "kind", kind: "macro", label: "Pack", required: true }
                ]
            },

            {
                id: "if",
                name: "if",
                label: "If",
                sig: "if <condition> then ... else ... end",
                desc: "Branch: run the nested modules when a Lua condition is true, otherwise the else branch.",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Condition", required: false }
                ]
            },
            {
                id: "for",
                name: "for",
                label: "For Loop",
                sig: "for i = from, to do ... end",
                desc: "Numeric loop: run the nested modules once per step from `from` to `to`.",
                category: "logic",
                params: [
                    { name: "var",  type: "string", label: "Variable", required: false },
                    { name: "from", type: "number", label: "From",     required: false },
                    { name: "to",   type: "number", label: "To",       required: false },
                    { name: "step", type: "number", label: "Step",     required: false }
                ]
            },
            {
                id: "while",
                name: "while",
                label: "While Loop",
                sig: "while <condition> do ... end",
                desc: "Loop the nested modules while a Lua condition holds true.",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Condition", required: false }
                ]
            },
            {
                id: "repeat",
                name: "repeat",
                label: "Repeat Until",
                sig: "repeat ... until <condition>",
                desc: "Loop the nested modules until a Lua condition becomes true (runs at least once). A plain number runs that many times.",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Until or count", required: false }
                ]
            },
            {
                id: "break",
                name: "break",
                label: "Break Loop",
                sig: "break",
                desc: "Exit the innermost loop. Outside a loop, it ends the macro.",
                category: "logic",
                params: []
            },
            {
                id: "var_set",
                name: "var_set",
                label: "Set Variable",
                sig: "local name = value",
                desc: "Declare or set a local variable.",
                category: "logic",
                params: [
                    { name: "name",  type: "string", label: "Name",  required: true },
                    { name: "value", type: "string", label: "Value", required: false }
                ]
            },
            {
                id: "var_add",
                name: "var_add",
                label: "Add to Variable",
                sig: "name = name + amount",
                desc: "Increment a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "var_sub",
                name: "var_sub",
                label: "Subtract from Variable",
                sig: "name = name - amount",
                desc: "Decrement a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "var_mul",
                name: "var_mul",
                label: "Multiply Variable",
                sig: "name = name * amount",
                desc: "Multiply a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "call_fn",
                name: "call_fn",
                label: "Call Function",
                sig: "ms.callFn(name)",
                desc: "Run a function tool or pack macro by name. Author functions in the Tools panel's Function tab.",
                category: "logic",
                params: [
                    { name: "name", type: "string", label: "Function", required: true }
                ]
            },
            {
                id: "hvar_set",
                name: "hvar_set",
                label: "Set Helper Variable",
                sig: "ms.vars.set(name, value)",
                desc: "Write a shared, disk-persistent helper variable. Declare it in the Tools panel's Variable tab; read it by wiring a Value field to it.",
                category: "logic",
                params: [
                    { name: "name",  type: "string", label: "Variable", required: true },
                    { name: "value", type: "string", label: "Value",    required: false }
                ]
            },
            {
                id: "comment",
                name: "comment",
                label: "Comment",
                sig: "-- text",
                desc: "A Lua comment. Documents the macro; emits nothing at runtime.",
                category: "logic",
                params: [
                    { name: "text", type: "string", label: "Text", required: false }
                ]
            },
            {
                id: "code",
                name: "code",
                label: "Lua Code",
                sig: "<raw Lua>",
                desc: "Raw Lua escape hatch, emitted verbatim. Use for coroutines or anything the modules don't cover.",
                category: "logic",
                params: [
                    { name: "source", type: "code", label: "Lua source", required: false }
                ]
            }
        ];

        var MOD_LIST = ["ctrl", "alt", "shift", "cmd"];

        var BINDABLE = { number: true, string: true };
    // END Function Registry //

        function enumDefault(p) {
            var o = (p.options || [])[0];
            if (o == null) return "";
            return (typeof o === "object") ? o.value : o;
        }

        window.msMacroRegistry = {
            REGISTRY,
            MOD_LIST,
            BINDABLE,
            enumDefault,
        };
    })();

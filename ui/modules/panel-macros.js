(function() {
    "use strict";
(function() {
        "use strict";

        /* -- Enum option sets (mirror the constants ms_core.lua asserts on;
           keep these in exact sync with ms.Mouse's OPS/BTNS/REFS, ms.scroll's
           directions, and ms.window's ops, or the compiled call will error) -- */
        var MOUSE_OPS = ["Move", "Click", "DoubleClick", "TripleClick", "Drag", "Press", "Release"];
        var MOUSE_BTNS = ["Left", "Right", "Center", "Button4", "Button5"];
        var MOUSE_REFS = [
            { value: "Absolute",     label: "Absolute (screen coords)" },
            { value: "Mouse",        label: "Mouse (relative to cursor)" },
            { value: "WindowTL",     label: "Window · Top-Left" },
            { value: "WindowTR",     label: "Window · Top-Right" },
            { value: "WindowBL",     label: "Window · Bottom-Left" },
            { value: "WindowBR",     label: "Window · Bottom-Right" },
            { value: "WindowCenter", label: "Window · Center" },
            { value: "ScreenTL",     label: "Screen · Top-Left" },
            { value: "ScreenTR",     label: "Screen · Top-Right" },
            { value: "ScreenBL",     label: "Screen · Bottom-Left" },
            { value: "ScreenBR",     label: "Screen · Bottom-Right" },
            { value: "ScreenCenter", label: "Screen · Center" }
        ];
        var SCROLL_DIRS = ["up", "down", "left", "right"];
        var WINDOW_OPS = ["Move", "Resize", "Frame"];

        /* -- Function Registry -- */
        var REGISTRY = [
            /* -- input -- */
            {
                id: "ms.type",
                name: "ms.type",
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
                sig: "ms.multiPress(keys, delayMs, mods)",
                desc: "Press a sequence of keys in order with optional delay.",
                category: "input",
                params: [
                    { name: "keys",    type: "string", label: "Keys (comma-separated)", required: true },
                    { name: "delayMs", type: "number", label: "Delay (ms)",             required: false },
                    { name: "mods",    type: "mods",   label: "Modifiers",              required: false }
                ]
            },

            /* -- clipboard -- */
            {
                id: "ms.copy",
                name: "ms.copy",
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
                sig: "ms.paste()",
                desc: "Paste current clipboard contents.",
                category: "clipboard",
                params: []
            },

            /* -- timing -- */
            {
                id: "ms.wait",
                name: "ms.wait",
                sig: "ms.wait(ms)",
                desc: "Pause macro execution for N milliseconds.",
                category: "timing",
                params: [
                    { name: "ms", type: "number", label: "Milliseconds", required: true }
                ]
            },
            {
                // Compiler construct, value must be a literal.
                id: "action_delay",
                name: "action_delay",
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
                sig: "ms.waitNotApp(appName, timeout)",
                desc: "Wait until an app stops running.",
                category: "timing",
                params: [
                    { name: "appName", type: "string", label: "App Name",  required: true },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            /* -- mouse -- */
            {
                id: "ms.Mouse",
                name: "ms.Mouse",
                sig: "ms.Mouse(operation, button, reference, x1, y1, x2, y2)",
                desc: "Unified mouse API (click, move, drag at coordinates).",
                category: "mouse",
                params: [
                    { name: "operation", type: "enum", options: MOUSE_OPS,  label: "Operation", required: true },
                    { name: "button",    type: "enum", options: MOUSE_BTNS, label: "Button",    required: true },
                    { name: "reference", type: "enum", options: MOUSE_REFS, label: "Reference", required: true },
                    { name: "unscaled",  type: "boolean", label: "Unscaled (bypass scaling)", required: false },
                    { name: "x1",        type: "number",  label: "X1",                          required: true },
                    { name: "y1",        type: "number",  label: "Y1",                          required: true },
                    { name: "x2",        type: "number",  label: "X2",                          required: false },
                    { name: "y2",        type: "number",  label: "Y2",                          required: false }
                ]
            },
            {
                id: "ms.scroll",
                name: "ms.scroll",
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
                sig: "ms.saveCursor()",
                desc: "Save current mouse position.",
                category: "mouse",
                params: []
            },
            {
                id: "ms.restoreCursor",
                name: "ms.restoreCursor",
                sig: "ms.restoreCursor()",
                desc: "Restore saved mouse position.",
                category: "mouse",
                params: []
            },

            /* -- window -- */
            {
                id: "ms.window",
                name: "ms.window",
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
                sig: "ms.windowPos(appName)",
                desc: "Get the position of an app's window.",
                category: "window",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },

            /* -- camera -- */
            {
                id: "ms.cam",
                name: "ms.cam",
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
                sig: "ms.cam.rebalance()",
                desc: "Rebalance camera to neutral.",
                category: "camera",
                params: []
            },
            {
                id: "ms.cam.reset",
                name: "ms.cam.reset",
                sig: "ms.cam.reset()",
                desc: "Reset camera to default.",
                category: "camera",
                params: []
            },

            /* -- pixel -- */
            {
                id: "ms.pixelColor",
                name: "ms.pixelColor",
                sig: "ms.pixelColor(x, y, reference)",
                desc: "Get pixel color at position.",
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
                sig: "ms.pixelMatch(x, y, reference, r, g, b, tolerance)",
                desc: "Check if pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "reference", type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false }
                ]
            },
            {
                id: "ms.waitPixel",
                name: "ms.waitPixel",
                sig: "ms.waitPixel(x, y, ref, r, g, b, tolerance, timeout)",
                desc: "Wait until pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },
            {
                id: "ms.waitNotPixel",
                name: "ms.waitNotPixel",
                sig: "ms.waitNotPixel(x, y, ref, r, g, b, tolerance, timeout)",
                desc: "Wait until pixel changes.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "enum", options: MOUSE_REFS, label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            /* -- ocr (screen text) -- */
            {
                id: "ms.ocr",
                name: "ms.ocr",
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

            /* -- state -- */
            {
                id: "ms.app",
                name: "ms.app",
                sig: "ms.app()",
                desc: "Get frontmost app name.",
                category: "state",
                params: []
            },
            {
                id: "ms.appRunning",
                name: "ms.appRunning",
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
                sig: "ms.mousePos()",
                desc: "Get cursor position in reference-space.",
                category: "state",
                params: []
            },
            {
                id: "ms.mousestate",
                name: "ms.mousestate",
                sig: "ms.mousestate(button)",
                desc: "Check if a mouse button is currently held (left/right/middle).",
                category: "state",
                params: [
                    { name: "button", type: "string", label: "Button (left/right/middle)", required: true }
                ]
            },

            /* -- audio -- */
            {
                id: "ms.sound",
                name: "ms.sound",
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
                sig: "ms.mute()",
                desc: "Mute system audio.",
                category: "audio",
                params: []
            },
            {
                id: "ms.unmute",
                name: "ms.unmute",
                sig: "ms.unmute()",
                desc: "Unmute system audio.",
                category: "audio",
                params: []
            },

            /* -- utility -- */
            {
                id: "ms.alert",
                name: "ms.alert",
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
                sig: "ms.notify(title, subTitle, infoText)",
                desc: "Show native macOS notification.",
                category: "utility",
                params: [
                    { name: "title",    type: "string", label: "Title",    required: true },
                    { name: "subTitle", type: "string", label: "Subtitle", required: false },
                    { name: "infoText", type: "string", label: "Info",     required: false }
                ]
            },

            /* -- flow -- */
            {
                id: "ms.setMacros",
                name: "ms.setMacros",
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
                sig: "ms.cancelMacros()",
                desc: "Cancel all active macro coroutines.",
                category: "flow",
                params: []
            },
            {
                id: "ms.pause",
                name: "ms.pause",
                sig: "ms.pause()",
                desc: "Pause the current macro.",
                category: "flow",
                params: []
            },
            {
                id: "ms.resume",
                name: "ms.resume",
                sig: "ms.resume()",
                desc: "Resume a paused macro.",
                category: "flow",
                params: []
            },
            {
                id: "ms.done",
                name: "ms.done",
                sig: "ms.done()",
                desc: "Signal macro completion.",
                category: "flow",
                params: []
            },
            {
                id: "ms.switchProfile",
                name: "ms.switchProfile",
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
                sig: "ms.switchPack(slug, kind)",
                desc: "Activate an installed library pack. Kind picks which slice (macro / theme / sound) is swapped in.",
                category: "flow",
                params: [
                    { name: "kind", type: "enum", options: ["macro", "theme", "sound"], label: "Kind", required: true },
                    { name: "slug", type: "choice", source: "pack", dependsOn: "kind", kind: "macro", label: "Pack", required: true }
                ]
            },

            /* -- logic -- */
            {
                id: "if",
                name: "if",
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
                sig: "repeat ... until <condition>",
                desc: "Loop the nested modules until a Lua condition becomes true (runs at least once).",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Until", required: false }
                ]
            },
            {
                id: "var_set",
                name: "var_set",
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
                sig: "<raw Lua>",
                desc: "Raw Lua escape hatch, emitted verbatim. Use for coroutines or anything the modules don't cover.",
                category: "logic",
                params: [
                    { name: "source", type: "code", label: "Lua source", required: false }
                ]
            }
        ];

        var MOD_LIST = ["ctrl", "alt", "shift", "cmd"];

        // Parameter types that can be wired to a tool.
        var BINDABLE = { number: true, string: true };

        /* -- State -- */
        var _selectedId  = null;
        var _paramValues = {};   // { paramName: value }
        var _paramBind   = {};   // { paramName: toolKey }, params wired to a tool
        var _modState    = {};   // { ctrl: false, alt: false, ... }
        var _keyCapture  = null; // param name currently capturing
        var _toastTimer  = null;
        var _tools       = [];   // current tools (authored settings + pack settings)
        var _fnList      = [];   // callable function tools (authored / pack / plugin)
        var _view        = "module"; // "module" | "tool"

        // Live lists for "choice" params (switch-profile / switch-pack). Filled
        // by the shell clients and kept fresh; _choiceSelects tracks the
        // currently mounted selects so a late push (or a kind change) can refill
        // their options in place. Subscribed once, below the DOM build.
        var _profilesData = [];                        // [{ name, active }]
        var _packData     = { macro: [], theme: [], sound: [] }; // [{ name, slug, active }]
        var _choiceSelects = [];  // [{ sel, param }] for the open detail

        // Subscribe once to the shell clients; a push refreshes local data and
        // refills any mounted choice selects in place. subscribe() fires with
        // the cache immediately when present, so opening the panel after the
        // data has landed is populated at once.
        if (window.msProfilesClient) {
            window.msProfilesClient.subscribe(function(entries) {
                _profilesData = entries || [];
                refillChoiceSelects();
            });
        }
        if (window.msLibraryClient && window.msLibraryClient.subscribe) {
            ["macro", "theme", "sound"].forEach(function(kind) {
                window.msLibraryClient.subscribe(kind, function(entries) {
                    _packData[kind] = entries || [];
                    refillChoiceSelects();
                });
            });
        }

        // Kick a fresh request for whatever a just-opened module needs, so its
        // dropdowns reflect the current profiles/packs even if they changed
        // since the last push.
        function requestChoiceData(fn) {
            var wantProfiles = false, wantKinds = {};
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                if (p.type !== "choice") continue;
                if (p.source === "profiles") wantProfiles = true;
                else if (p.source === "pack") {
                    // Request every kind the param could switch to, not just the
                    // current one, so changing the kind enum is instant.
                    ["macro", "theme", "sound"].forEach(function(k) { wantKinds[k] = true; });
                }
            }
            if (wantProfiles && window.msProfilesClient) window.msProfilesClient.request();
            if (window.msLibraryClient) {
                Object.keys(wantKinds).forEach(function(k) { window.msLibraryClient.request(k); });
            }
        }

        /* -- Build DOM -- */
        var slot = document.getElementById("slot-macros");
        if (!slot) return;

        var root = document.createElement("div");
        root.className = "fn-picker";

        // Left: list
        var listPane = document.createElement("div");
        listPane.className = "fn-picker-list";

        var searchBox = document.createElement("div");
        searchBox.className = "fn-picker-search";
        var searchInput = document.createElement("input");
        searchInput.type = "text";
        searchInput.placeholder = "Search modules\u2026";
        searchInput.setAttribute("spellcheck", "false");
        searchInput.setAttribute("autocomplete", "off");
        searchInput.setAttribute("autocorrect", "off");
        searchInput.setAttribute("autocapitalize", "off");
        searchBox.appendChild(searchInput);
        listPane.appendChild(searchBox);

        var entriesDiv = document.createElement("div");
        entriesDiv.className = "fn-picker-entries";
        listPane.appendChild(entriesDiv);

        // Right: detail
        var detailPane = document.createElement("div");
        detailPane.className = "fn-picker-detail";
        detailPane.innerHTML = '<div class="fn-detail-empty"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>Select a module from the list</div>';

        root.appendChild(listPane);
        root.appendChild(detailPane);
        slot.appendChild(root);

        // Toast
        var toast = document.createElement("div");
        toast.className = "fn-toast";
        document.body.appendChild(toast);

        /* -- Render Function List -- */
        var _catCollapsed = {};   // category -> true when folded shut

        function makeEntryRow(fn) {
            var row = document.createElement("div");
            row.className = "fn-entry" + (_selectedId === fn.id ? " active" : "");
            row.setAttribute("data-fn-id", fn.id);

            var sigSpan = document.createElement("span");
            sigSpan.className = "fn-entry-sig";
            sigSpan.textContent = fn.name;
            row.appendChild(sigSpan);

            // Draggable onto the canvas as a new module (default params).
            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-fn", fn.id);
                e.dataTransfer.setData("text/plain", fn.name);
            });

            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                selectFunction(fn.id);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            return row;
        }

        // Build one draggable tool row (a shared-setting reference).
        function makeToolRow(t) {
            var row = document.createElement("div");
            row.className = "fn-entry fn-tool-entry"
                + (_view === "tool" && _selectedId === t.key ? " active" : "");
            row.setAttribute("data-tool-key", t.key);

            var sig = document.createElement("span");
            sig.className = "fn-entry-sig";
            sig.textContent = t.label || t.key;
            row.appendChild(sig);

            var tag = document.createElement("span");
            tag.className = "fn-tool-tag fn-tool-tag-" + (t.source || "pack");
            tag.textContent = t.type;
            row.appendChild(tag);

            // Draggable onto the canvas as a shared-setting reference block.
            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-tool", t.key);
                e.dataTransfer.setData("text/plain", t.label || t.key);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                selectTool(t.key);
            });
            return row;
        }

        // Build one draggable function row. Dropping (or clicking) it drops a
        // "Call function" step preset to this function's id, so authored/pack/
        // plugin functions are usable from the builder, not just the Tools panel.
        function makeFnCallRow(fn) {
            var id  = fn.id || fn.name;
            var row = document.createElement("div");
            row.className = "fn-entry fn-tool-entry";
            row.setAttribute("data-fn-call", id);

            var sig = document.createElement("span");
            sig.className = "fn-entry-sig";
            sig.textContent = fn.name || id;
            row.appendChild(sig);

            var tag = document.createElement("span");
            tag.className = "fn-tool-tag fn-tool-tag-" + (fn.source || "builder");
            tag.textContent = "function";
            row.appendChild(tag);

            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-callfn", id);
                e.dataTransfer.setData("text/plain", fn.name || id);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                if (window.macroLab && window.macroLab.addTool) {
                    window.macroLab.addTool({ action: "call_fn", params: { name: id } });
                }
            });
            return row;
        }

        // Group tools by their section into collapsible headings. Functions are
        // tools too, so they ride in the default "tools" section alongside
        // settings and helper vars rather than in their own group.
        function renderToolsGroup(filter, searching) {
            var q = (filter || "").toLowerCase();
            var matches = _tools.filter(function(t) {
                if (!q) return true;
                return (t.label || "").toLowerCase().indexOf(q) !== -1
                    || (t.key || "").toLowerCase().indexOf(q) !== -1
                    || (t.section || "").toLowerCase().indexOf(q) !== -1
                    || "tool".indexOf(q) !== -1;
            });
            var fnMatches = _fnList.filter(function(f) {
                if (!q) return true;
                return (String(f.name || f.id)).toLowerCase().indexOf(q) !== -1
                    || "function tool".indexOf(q) !== -1;
            });
            var searchingTools = q && "tool".indexOf(q) === -1
                && "function".indexOf(q) === -1;

            // With nothing to show, keep the default header and a hint so tools
            // stay discoverable.
            if (matches.length === 0 && fnMatches.length === 0) {
                if (searchingTools) return;
                renderToolSection("tools", [], [], filter, searching, true);
                return;
            }

            // Group by section in first-seen order, default "tools" group leads.
            var order = [];
            var groups = {};
            matches.forEach(function(t) {
                var s = (t.section && String(t.section)) || "tools";
                if (!groups[s]) { groups[s] = []; order.push(s); }
                groups[s].push(t);
            });
            // Functions always live in the default "tools" section.
            if (fnMatches.length && !groups["tools"]) { groups["tools"] = []; order.push("tools"); }
            if (groups["tools"]) {
                order = ["tools"].concat(order.filter(function(s) { return s !== "tools"; }));
            }
            order.forEach(function(s) {
                renderToolSection(s, groups[s], s === "tools" ? fnMatches : [], filter, searching, false);
            });
        }

        // Render one Tools sub-section: a category-style header keyed by section
        // name, with its own independent collapse state, then its tool rows.
        function renderToolSection(section, rows, fns, filter, searching, emptyHint) {
            fns = fns || [];
            var key = "__tools:" + section;
            var collapsed = searching ? false : (_catCollapsed[key] !== false);

            var head = document.createElement("div");
            head.className = "fn-cat-head fn-cat-tools" + (collapsed ? " collapsed" : "");

            var chev = document.createElement("span");
            chev.className = "fn-cat-chev";
            chev.innerHTML = (typeof window.icon === "function"
                && window.ICONS && window.ICONS.chevdown)
                ? window.icon("chevdown") : "";
            head.appendChild(chev);

            var name = document.createElement("span");
            name.className = "fn-cat-name";
            name.textContent = section;
            head.appendChild(name);

            var count = document.createElement("span");
            count.className = "fn-cat-count";
            count.textContent = String(rows.length + fns.length);
            head.appendChild(count);

            head.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            if (!searching) {
                head.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    _catCollapsed[key] = !(_catCollapsed[key] !== false);
                    renderList(filter);
                });
            }
            entriesDiv.appendChild(head);

            if (collapsed) return;

            rows.forEach(function(t) { entriesDiv.appendChild(makeToolRow(t)); });
            fns.forEach(function(f) { entriesDiv.appendChild(makeFnCallRow(f)); });

            // A hint points at the Tools panel when none exist yet.
            if (emptyHint && rows.length === 0 && fns.length === 0) {
                var hint = document.createElement("div");
                hint.className = "fn-entry fn-tool-hint";
                hint.innerHTML = '<span class="fn-entry-sig">No tools, add one in the Tools panel</span>';
                entriesDiv.appendChild(hint);
            }
        }

        function renderList(filter) {
            entriesDiv.innerHTML = "";
            var q = (filter || "").toLowerCase();
            var searching = q.length > 0;

            renderToolsGroup(filter, searching);

            // Group visible entries by category, preserving REGISTRY order.
            var order = [];
            var groups = {};
            for (var i = 0; i < REGISTRY.length; i++) {
                var fn = REGISTRY[i];
                if (q && fn.name.toLowerCase().indexOf(q) === -1
                       && fn.desc.toLowerCase().indexOf(q) === -1
                       && fn.category.toLowerCase().indexOf(q) === -1) {
                    continue;
                }
                var c = fn.category || "other";
                if (!groups[c]) { groups[c] = []; order.push(c); }
                groups[c].push(fn);
            }

            order.forEach(function(cat) {
                var collapsed = searching ? false : (_catCollapsed[cat] !== false);

                var head = document.createElement("div");
                head.className = "fn-cat-head" + (collapsed ? " collapsed" : "");

                var chev = document.createElement("span");
                chev.className = "fn-cat-chev";
                chev.innerHTML = (typeof window.icon === "function"
                    && window.ICONS && window.ICONS.chevdown)
                    ? window.icon("chevdown") : "";
                head.appendChild(chev);

                var name = document.createElement("span");
                name.className = "fn-cat-name";
                name.textContent = cat;
                head.appendChild(name);

                var count = document.createElement("span");
                count.className = "fn-cat-count";
                count.textContent = String(groups[cat].length);
                head.appendChild(count);

                head.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                // While searching, sections are forced open so the header is inert.
                if (!searching) {
                    head.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        _catCollapsed[cat] = !(_catCollapsed[cat] !== false);
                        renderList(filter);
                    });
                }
                entriesDiv.appendChild(head);

                if (!collapsed) {
                    groups[cat].forEach(function(fn) {
                        entriesDiv.appendChild(makeEntryRow(fn));
                    });
                }
            });
        }

        /* -- Select Function -- */
        function selectFunction(id) {
            _selectedId = id;
            _view = "module";
            _paramValues = {};
            _paramBind = {};
            _modState = {};
            _keyCapture = null;

            // Update list highlight
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active", items[i].getAttribute("data-fn-id") === id);
            }

            // Find function definition
            var fn = null;
            for (var j = 0; j < REGISTRY.length; j++) {
                if (REGISTRY[j].id === id) { fn = REGISTRY[j]; break; }
            }
            if (!fn) return;

            // Initialize defaults
            for (var k = 0; k < fn.params.length; k++) {
                var p = fn.params[k];
                if (p.type === "mods") {
                    _paramValues[p.name] = [];
                    _modState = { ctrl: false, alt: false, shift: false, cmd: false };
                } else if (p.type === "number") {
                    _paramValues[p.name] = 0;
                } else if (p.type === "boolean") {
                    _paramValues[p.name] = false;
                } else if (p.type === "enum") {
                    _paramValues[p.name] = enumDefault(p);
                } else {
                    _paramValues[p.name] = "";
                }
            }

            renderDetail(fn);
        }

        /* -- Tools -- */
        function findTool(key) {
            for (var i = 0; i < _tools.length; i++) {
                if (_tools[i].key === key) return _tools[i];
            }
            return null;
        }

        // Canvas step for a tool reference, keeps only key/label/type.
        function settingDefFor(t) {
            return {
                action: "setting",
                params: { key: t.key, label: t.label || t.key, type: t.type },
            };
        }

        function selectTool(key) {
            _view = "tool";
            _selectedId = key;
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active",
                    items[i].getAttribute("data-tool-key") === key);
            }
            renderToolDetail(findTool(key));
        }

        function renderToolDetail(t) {
            if (!t) { detailPane.innerHTML = ''; return; }
            var html = '';
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(t.label || t.key) + '</div>';
            html += '<div class="fn-detail-desc">'
                + esc(t.hint || 'A ' + t.type + ' tool. Wire it into a module parameter to read its value live.')
                + '</div>';
            html += '</div>';

            html += '<div class="fn-detail-body"><div class="fn-params">';
            html += toolMetaRow("Key", t.key);
            html += toolMetaRow("Type", t.type);
            html += toolMetaRow("Source",
                t.source === "builder" ? "Authored here" : "Declared in the pack");
            if (t.type === "slider") {
                html += toolMetaRow("Range", (t.min != null ? t.min : "?")
                    + " – " + (t.max != null ? t.max : "?")
                    + (t.step ? " (step " + t.step + ")" : ""));
            }
            if (t.type === "seg" && t.options) {
                var labels = t.options.map(function(o) { return o.label; }).join(", ");
                html += toolMetaRow("Options", labels);
            }
            if (t.default !== undefined && t.default !== null && t.default !== "") {
                html += toolMetaRow("Default", String(t.default));
            }
            html += '<div class="fn-tool-usehint">Reads as <code>ms.settings.get("'
                + esc(t.key) + '")</code>. To use it, add a module and switch any '
                + 'value field to <b>Tool</b>, then pick this.</div>';
            html += '</div></div>';

            html += '<div class="fn-detail-footer">';
            // Add the tool to the macro as a shared-setting reference block.
            html += '<button class="fn-add-btn" id="fn-tool-add">Add to Macro</button>';
            if (t.source === "builder") {
                html += '<button class="fn-add-btn fn-tool-delete" id="fn-tool-delete">Delete Tool</button>';
            }
            html += '</div>';

            detailPane.innerHTML = html;

            var add = document.getElementById("fn-tool-add");
            if (add) {
                add.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                add.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    if (window.macroLab && window.macroLab.addTool) {
                        window.macroLab.addTool(settingDefFor(t));
                    }
                });
            }

            var del = document.getElementById("fn-tool-delete");
            if (del) {
                del.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                del.addEventListener("click", function() {
                    if (window.playSlot) playSlot("back");
                    if (window.macroLab && window.macroLab.deleteTool) {
                        window.macroLab.deleteTool(t.key);
                    }
                });
            }
        }

        function toolMetaRow(label, value) {
            return '<div class="fn-param-group fn-tool-meta"><div class="fn-param-label">'
                + esc(label) + '</div><div class="fn-tool-meta-val">'
                + esc(String(value)) + '</div></div>';
        }

        /* -- Render Detail Panel -- */
        function renderDetail(fn) {
            var html = '';

            // Header
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(fn.name) + '</div>';
            html += '<div class="fn-detail-desc">' + esc(fn.desc) + '</div>';
            html += '</div>';

            // Body (params)
            html += '<div class="fn-detail-body">';
            if (fn.params.length === 0) {
                html += '<div class="fn-no-params">This function takes no parameters.</div>';
            } else {
                html += '<div class="fn-params">';
                for (var i = 0; i < fn.params.length; i++) {
                    var p = fn.params[i];
                    html += renderParamField(p);
                }
                html += '</div>';
            }
            html += '</div>';

            // Footer
            html += '<div class="fn-detail-footer">';
            html += '<button class="fn-add-btn" id="fn-add-btn">Add Module</button>';
            html += '<span class="fn-tool-preview" id="fn-tool-preview"></span>';
            html += '</div>';

            detailPane.innerHTML = html;

            // Wire up param inputs
            wireParamInputs(fn);

            // Wire add button
            var addBtn = document.getElementById("fn-add-btn");
            if (addBtn) {
                addBtn.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                addBtn.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    addToMacro(fn);
                });
            }

            updatePreview(fn);
        }

        /* -- Render a single parameter field -- */
        // Option list for the tool picker, the empty row is the placeholder.
        function toolSelectOptions() {
            if (_tools.length === 0) {
                return [{ value: "", label: "No tools, create one first" }];
            }
            var opts = [{ value: "", label: "Pick a tool..." }];
            _tools.forEach(function(t) {
                opts.push({ value: t.key, label: (t.label || t.key) + "  ·  " + t.type });
            });
            return opts;
        }

        // Live createSelect nodes for the currently rendered param fields, keyed
        // by param name, so setToolList can refresh their options in place.
        var _toolSelects = {};

        // Header line above the bound tool's value editor, names the tool type.
        function setToolInfo(name, key) {
            var el = detailPane.querySelector('[data-toolinfo="' + name + '"]');
            if (!el) return;
            var t = key && findTool(key);
            el.innerHTML = t ? ("Sets the <b>" + esc(t.type) + "</b> tool's value:") : "";
        }

        // The tool's live value, falling back to its authored default.
        function currentToolValue(t) {
            if (t.value !== undefined && t.value !== null) return t.value;
            return (t.default !== undefined) ? t.default : null;
        }

        // Persist a tool value to the host (the same setting the Tools panel
        // edits) and keep the local copy in sync so the control stays live.
        function commitToolValue(t, value, name) {
            t.value = value;
            if (window.shellPost) {
                shellPost("macros", "userSettingChange", {
                    action: "userSettingChange",
                    key: t.key,
                    value: value,
                });
            }
        }

        // Inline value editor under the tool picker, one control per tool type
        // (toggle / seg / slider), so a bound tool can be set here directly.
        function mountToolValue(name, key) {
            var wrap = detailPane.querySelector('[data-toolval="' + name + '"]');
            if (!wrap) return;
            wrap.innerHTML = "";
            var t = key && findTool(key);
            if (!t) return;
            var val = currentToolValue(t);

            if (t.type === "toggle") {
                var on = (val === true || val === "true");
                var lab = document.createElement("label");
                lab.className = "toggle fn-param-toggle";
                var cb = document.createElement("input");
                cb.type = "checkbox";
                cb.checked = on;
                var track = document.createElement("span");
                track.className = "toggle-track";
                var thumb = document.createElement("span");
                thumb.className = "toggle-thumb";
                lab.appendChild(cb);
                lab.appendChild(track);
                lab.appendChild(thumb);
                cb.addEventListener("change", function() {
                    if (window.playSlot) playSlot(cb.checked ? "toggleOn" : "toggleOff");
                    commitToolValue(t, cb.checked, name);
                });
                wrap.appendChild(lab);

            } else if (t.type === "seg") {
                var seg = document.createElement("div");
                seg.className = "fn-tool-seg";
                (t.options || []).forEach(function(o) {
                    var b = document.createElement("button");
                    b.className = "fn-tool-seg-opt" + (o.value === val ? " on" : "");
                    b.textContent = o.label;
                    b.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    b.addEventListener("click", function() {
                        var opts = seg.querySelectorAll(".fn-tool-seg-opt");
                        for (var i = 0; i < opts.length; i++) opts[i].classList.remove("on");
                        b.classList.add("on");
                        if (window.playSlot) playSlot("interact");
                        commitToolValue(t, o.value, name);
                    });
                    seg.appendChild(b);
                });
                wrap.appendChild(seg);

            } else if (t.type === "slider") {
                var row = document.createElement("div");
                row.className = "fn-tool-slider";
                var range = document.createElement("input");
                range.type = "range";
                range.min = (t.min != null ? t.min : 0);
                range.max = (t.max != null ? t.max : 100);
                range.step = (t.step != null ? t.step : 1);
                var num = (typeof val === "number") ? val : parseFloat(val);
                if (isNaN(num)) num = Number(range.min);
                range.value = num;
                var read = document.createElement("span");
                read.className = "fn-tool-slider-val";
                var fmt = function(v) { return String(v) + (t.unit ? (" " + t.unit) : ""); };
                read.textContent = fmt(num);
                // Live read-out on drag, commit to the host on release, so a drag
                // does not flood the host with a set per frame.
                range.addEventListener("input", function() {
                    read.textContent = fmt(parseFloat(range.value));
                });
                range.addEventListener("change", function() {
                    commitToolValue(t, parseFloat(range.value), name);
                });
                row.appendChild(range);
                row.appendChild(read);
                wrap.appendChild(row);
            }
        }

        // Refresh both the header and the value editor for a param's tool pick.
        function refreshToolBind(name, key) {
            setToolInfo(name, key);
            mountToolValue(name, key);
        }

        // Replace each tool-select mount point with a themed createSelect. Falls
        // back to a native <select> only if createSelect isn't loaded.
        function mountToolSelects(fn) {
            _toolSelects = {};
            if (typeof window.createSelect !== "function") return;
            var mounts = detailPane.querySelectorAll(".fn-tool-select-mount");
            for (var i = 0; i < mounts.length; i++) {
                (function(mount) {
                    var name = mount.getAttribute("data-toolmount");
                    var sel = window.createSelect({
                        options: toolSelectOptions(),
                        value: _paramBind[name] || "",
                        className: "fn-tool-select",
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramBind[name] = v;
                            _paramValues[name] = { __toolRef: v };
                            refreshToolBind(name, v);
                            updatePreview(fn);
                        },
                    });
                    // The Value/Tool switch reads the current pick via this attr.
                    sel.setAttribute("data-toolsel", name);
                    mount.appendChild(sel);
                    _toolSelects[name] = sel;
                    refreshToolBind(name, _paramBind[name] || "");
                })(mounts[i]);
            }
        }

        // First option's value for an enum param (options are strings or
        // {value,label} objects). Used to seed a valid default.
        function enumDefault(p) {
            var o = (p.options || [])[0];
            if (o == null) return "";
            return (typeof o === "object") ? o.value : o;
        }

        function renderParamField(p) {
            var bindable = !!BINDABLE[p.type];
            var bound = bindable && !!_paramBind[p.name];

            var html = '<div class="fn-param-group fn-param' + (bound ? ' bound' : '')
                + '" data-pname="' + esc(p.name) + '">';
            html += '<div class="fn-param-label">' + esc(p.label);
            html += ' <span class="fn-param-type">' + esc(p.type) + '</span>';
            if (p.required) html += ' <span style="color:var(--danger)">*</span>';
            if (bindable) {
                html += '<span class="fn-bind-switch">'
                    + '<button class="fn-bind-opt' + (bound ? '' : ' on') + '" data-bindmode="literal" data-param="'
                    + esc(p.name) + '">Value</button>'
                    + '<button class="fn-bind-opt' + (bound ? ' on' : '') + '" data-bindmode="tool" data-param="'
                    + esc(p.name) + '">Tool</button></span>';
            }
            html += '</div>';

            html += '<div class="fn-param-literal" data-lit="' + esc(p.name) + '"'
                + (bound ? ' style="display:none"' : '') + '>';
            switch (p.type) {
                case "string":
                    html += '<input type="text" data-param="' + esc(p.name) + '" placeholder="Enter text\u2026" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">';
                    break;

                case "number":
                    html += '<input type="number" data-param="' + esc(p.name) + '" value="0" step="1">';
                    break;

                case "enum":
                    // A fixed constant set (mouse button, reference, etc.).
                    // Rendered as a themed createSelect, mounted after the HTML
                    // lands, so an invalid value can't be typed in the first place.
                    html += '<div class="fn-enum-select-mount" data-enummount="' + esc(p.name) + '"></div>';
                    break;

                case "choice":
                    // A live-sourced dropdown (profiles / packs). Options are
                    // fetched from the shell clients when mounted and refreshed
                    // as pushes land; see mountChoiceSelects.
                    html += '<div class="fn-choice-select-mount" data-choicemount="' + esc(p.name)
                        + '" data-choicesrc="' + esc(p.source || "")
                        + '" data-choicekind="' + esc(p.kind || "")
                        + '" data-choicedep="' + esc(p.dependsOn || "") + '"></div>';
                    break;

                case "boolean":
                    // Shared .toggle markup (hidden checkbox behind track/thumb),
                    // same styling as the settings/macro toggles.
                    html += '<label class="toggle fn-param-toggle">'
                        + '<input type="checkbox" data-param="' + esc(p.name) + '">'
                        + '<span class="toggle-track"></span>'
                        + '<span class="toggle-thumb"></span></label>';
                    break;

                case "key":
                    html += '<div class="fn-key-capture">';
                    html += '<button class="fn-key-btn" data-param="' + esc(p.name) + '" data-key-capture>Click to set</button>';
                    html += '<span class="fn-key-hint">press a key\u2026</span>';
                    html += '</div>';
                    break;

                case "mods":
                    html += '<div class="fn-mods-row">';
                    for (var i = 0; i < MOD_LIST.length; i++) {
                        html += '<button class="fn-mod-chip" data-mod="' + MOD_LIST[i] + '">' + MOD_LIST[i] + '</button>';
                    }
                    html += '</div>';
                    break;

                case "condition":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="1" placeholder="Lua expression..." spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;

                case "code":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="3" placeholder="Lua source..." spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;
            }
            html += '</div>';

            if (bindable) {
                html += '<div class="fn-param-tool" data-toolwrap="' + esc(p.name) + '"'
                    + (bound ? '' : ' style="display:none"') + '>';
                // Themed createSelect mounted after the HTML lands.
                html += '<div class="fn-tool-select-mount" data-toolmount="' + esc(p.name) + '"></div>';
                html += '<div class="fn-tool-info" data-toolinfo="' + esc(p.name) + '"></div>';
                html += '<div class="fn-tool-value" data-toolval="' + esc(p.name) + '"></div>';
                html += '</div>';
            }

            html += '</div>';
            return html;
        }

        /* -- Wire up input events -- */
        function wireParamInputs(fn) {
            // Text and number inputs, plus condition/code textareas.
            var inputs = detailPane.querySelectorAll("input[data-param], textarea[data-param]");
            for (var i = 0; i < inputs.length; i++) {
                (function(inp) {
                    var name = inp.getAttribute("data-param");
                    // Checkboxes commit their state on "change", not "input".
                    var evt = (inp.type === "checkbox") ? "change" : "input";
                    inp.addEventListener(evt, function() {
                        if (inp.type === "checkbox") {
                            _paramValues[name] = inp.checked;
                            if (window.playSlot) playSlot(inp.checked ? "toggleOn" : "toggleOff");
                        } else if (inp.type === "number") {
                            _paramValues[name] = parseFloat(inp.value) || 0;
                        } else {
                            _paramValues[name] = inp.value;
                        }
                        updatePreview(fn);
                    });
                    // Textareas capture typing that would otherwise reach the
                    // canvas/key-capture handlers.
                    if (inp.tagName === "TEXTAREA") {
                        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
                    }
                })(inputs[i]);
            }

            // Key capture buttons
            var keyBtns = detailPane.querySelectorAll("[data-key-capture]");
            for (var j = 0; j < keyBtns.length; j++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    btn.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    btn.addEventListener("click", function(e) {
                        e.stopPropagation();
                        if (window.playSlot) playSlot("interact");
                        startKeyCapture(name, btn, fn);
                    });
                })(keyBtns[j]);
            }

            // Modifier chips
            var modChips = detailPane.querySelectorAll("[data-mod]");
            for (var k = 0; k < modChips.length; k++) {
                (function(chip) {
                    var mod = chip.getAttribute("data-mod");
                    chip.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    chip.addEventListener("click", function() {
                        _modState[mod] = !_modState[mod];
                        if (window.playSlot) playSlot(_modState[mod] ? "toggleOn" : "toggleOff");
                        chip.classList.toggle("on", _modState[mod]);
                        // Update mods param value
                        var mods = [];
                        for (var m = 0; m < MOD_LIST.length; m++) {
                            if (_modState[MOD_LIST[m]]) mods.push(MOD_LIST[m]);
                        }
                        // Find the mods param name
                        for (var n = 0; n < fn.params.length; n++) {
                            if (fn.params[n].type === "mods") {
                                _paramValues[fn.params[n].name] = mods;
                                break;
                            }
                        }
                        updatePreview(fn);
                    });
                })(modChips[k]);
            }

            // Value/Tool switch: flips a parameter between a literal and a tool binding.
            var switches = detailPane.querySelectorAll(".fn-bind-opt");
            for (var s = 0; s < switches.length; s++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    var mode = btn.getAttribute("data-bindmode");
                    btn.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        var group = detailPane.querySelector('.fn-param[data-pname="' + name + '"]');
                        if (!group) return;
                        var lit  = group.querySelector('[data-lit="' + name + '"]');
                        var tool = group.querySelector('[data-toolwrap="' + name + '"]');
                        var opts = group.querySelectorAll('.fn-bind-opt');
                        opts.forEach(function(o) {
                            o.classList.toggle("on", o.getAttribute("data-bindmode") === mode);
                        });
                        if (mode === "tool") {
                            group.classList.add("bound");
                            if (lit)  lit.style.display  = "none";
                            if (tool) tool.style.display = "";
                            var selEl = group.querySelector('[data-toolsel="' + name + '"]');
                            _paramBind[name] = (selEl && selEl.value) ? selEl.value : "";
                            if (_paramBind[name]) {
                                _paramValues[name] = { __toolRef: _paramBind[name] };
                            }
                            refreshToolBind(name, _paramBind[name] || "");
                        } else {
                            group.classList.remove("bound");
                            if (lit)  lit.style.display  = "";
                            if (tool) tool.style.display = "none";
                            delete _paramBind[name];
                            var litInput = group.querySelector('[data-param="' + name + '"]');
                            if (litInput) {
                                _paramValues[name] = (litInput.type === "number")
                                    ? (parseFloat(litInput.value) || 0) : litInput.value;
                            } else {
                                _paramValues[name] = "";
                            }
                        }
                        updatePreview(fn);
                    });
                })(switches[s]);
            }

            // Enum selects, a fixed constant set per param.
            mountEnumSelects(fn);

            // Choice selects (profiles / packs), sourced from the live shell
            // lists. Reset the tracker first so it only holds this detail's
            // selects. A request is kicked so the lists are fresh on open.
            _choiceSelects = [];
            mountChoiceSelects(fn);
            requestChoiceData(fn);

            // Tool selects, pick which tool a bound parameter reads from.
            // Mounted as themed createSelect nodes (each wires its own onChange).
            mountToolSelects(fn);
        }

        // Replace each enum mount point with a themed createSelect. The value is
        // seeded from _paramValues (set to the first option in selectFunction),
        // so a required enum is always valid without any user interaction.
        function mountEnumSelects(fn) {
            if (typeof window.createSelect !== "function") return;
            var byName = {};
            for (var i = 0; i < fn.params.length; i++) byName[fn.params[i].name] = fn.params[i];
            var mounts = detailPane.querySelectorAll(".fn-enum-select-mount");
            for (var m = 0; m < mounts.length; m++) {
                (function(mount) {
                    var name = mount.getAttribute("data-enummount");
                    var p = byName[name];
                    if (!p) return;
                    var sel = window.createSelect({
                        options: p.options || [],
                        value: _paramValues[name] || "",
                        className: "fn-enum-select",
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramValues[name] = v;
                            // A choice param may key its options off this enum
                            // (switch-pack's slug depends on kind); refresh them.
                            refillChoiceSelects();
                            updatePreview(fn);
                        },
                    });
                    mount.appendChild(sel);
                })(mounts[m]);
            }
        }

        // Options for a "choice" param, built from the live shell lists. An
        // "active" entry is tagged so the user can see the current selection;
        // the stored value that isn't in the list any more (a removed pack /
        // renamed profile) is preserved as its own row so editing never drops it.
        function choiceOptions(p) {
            var opts = [];
            var seen = {};
            function add(value, label) {
                if (value == null || seen[value]) return;
                seen[value] = true;
                opts.push({ value: String(value), label: label });
            }
            if (p.source === "profiles") {
                for (var i = 0; i < _profilesData.length; i++) {
                    var e = _profilesData[i];
                    add(e.name, e.active ? e.name + " (active)" : e.name);
                }
            } else if (p.source === "pack") {
                var kind = (p.dependsOn && _paramValues[p.dependsOn]) || p.kind || "macro";
                var list = _packData[kind] || [];
                for (var j = 0; j < list.length; j++) {
                    var pk = list[j];
                    add(pk.slug, pk.active ? pk.name + " (active)" : pk.name);
                }
            }
            var cur = _paramValues[p.name];
            if (cur && !seen[cur]) add(cur, cur + " (not installed)");
            if (!opts.length) add("", "None available");
            return opts;
        }

        // Replace each choice mount point with a live-sourced createSelect. The
        // select is tracked in _choiceSelects so refillChoiceSelects can update
        // its options in place when a push lands or a dependency changes.
        function mountChoiceSelects(fn) {
            if (typeof window.createSelect !== "function") return;
            var byName = {};
            for (var i = 0; i < fn.params.length; i++) byName[fn.params[i].name] = fn.params[i];
            var mounts = detailPane.querySelectorAll(".fn-choice-select-mount");
            for (var m = 0; m < mounts.length; m++) {
                (function(mount) {
                    var name = mount.getAttribute("data-choicemount");
                    var p = byName[name];
                    if (!p) return;
                    var opts = choiceOptions(p);
                    // Seed a valid value: keep the stored one if present, else
                    // adopt the first real option so a required choice is valid.
                    if (!_paramValues[name] && opts.length && opts[0].value) {
                        _paramValues[name] = opts[0].value;
                    }
                    var sel = window.createSelect({
                        options: opts,
                        value: _paramValues[name] || "",
                        className: "fn-choice-select",
                        searchable: opts.length > 8,
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramValues[name] = v;
                            updatePreview(fn);
                        },
                    });
                    mount.appendChild(sel);
                    _choiceSelects.push({ sel: sel, param: p, fn: fn });
                })(mounts[m]);
            }
        }

        // Refresh the options of every mounted choice select from current data,
        // preserving each select's value where it still exists.
        function refillChoiceSelects() {
            for (var i = 0; i < _choiceSelects.length; i++) {
                var c = _choiceSelects[i];
                if (!c.sel.isConnected) continue;
                var opts = choiceOptions(c.param);
                var keep = c.sel.value;
                c.sel.setOptions(opts);
                var has = false;
                for (var j = 0; j < opts.length; j++) if (opts[j].value === keep) { has = true; break; }
                if (has) c.sel.value = keep;
                _paramValues[c.param.name] = c.sel.value;
            }
        }

        /* -- Key Capture -- */
        function startKeyCapture(paramName, btn, fn) {
            // Cancel any existing capture
            if (_keyCapture) {
                var prevBtn = detailPane.querySelector(".fn-key-btn.capturing");
                if (prevBtn) prevBtn.classList.remove("capturing");
                document.removeEventListener("keydown", _keyCaptureHandler, true);
            }

            _keyCapture = paramName;
            btn.classList.add("capturing");
            btn.textContent = "\u2026";

            function handler(e) {
                e.preventDefault();
                e.stopPropagation();

                // Build key name
                var key = normalizeKey(e);
                _paramValues[paramName] = key;

                btn.classList.remove("capturing");
                btn.textContent = key || "???";
                btn.classList.remove("fn-key-btn");
                btn.classList.add("fn-key-btn");

                document.removeEventListener("keydown", handler, true);
                _keyCapture = null;
                _keyCaptureHandler = null;
                updatePreview(fn);
            }

            _keyCaptureHandler = handler;
            document.addEventListener("keydown", handler, true);
        }

        var _keyCaptureHandler = null;

        function normalizeKey(e) {
            // Map common keys to ms naming
            var map = {
                " ": "space",
                "ArrowUp": "up",
                "ArrowDown": "down",
                "ArrowLeft": "left",
                "ArrowRight": "right",
                "Backspace": "delete",
                "Escape": "escape",
                "Enter": "return",
                "Tab": "tab"
            };
            if (map[e.key]) return map[e.key];
            if (e.key.length === 1) return e.key.toLowerCase();
            return e.key.toLowerCase();
        }

        /* -- Step Preview -- */
        function updatePreview(fn) {
            var el = document.getElementById("fn-tool-preview");
            if (!el) return;

            var parts = [];
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                if (val && typeof val === "object" && val.__toolRef) {
                    // A bound parameter previews as the call it compiles to.
                    parts.push(p.name + ':ms.settings.get("' + val.__toolRef + '")');
                } else if (p.type === "mods") {
                    parts.push(p.name + ":[" + (val || []).join(",") + "]");
                } else if (p.type === "string" || p.type === "enum") {
                    parts.push(p.name + ':"' + (val || "") + '"');
                } else {
                    parts.push(p.name + ":" + (val !== undefined ? val : ""));
                }
            }
            el.textContent = fn.name + "(" + parts.join(", ") + ")";
        }

        /* -- Add to Macro -- */
        function addToMacro(fn) {
            var params = {};
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                // A parameter switched to Tool but never given one is unfinished.
                if (_paramBind[p.name] !== undefined && !_paramBind[p.name]) {
                    showToast("Pick a tool for: " + p.label);
                    return;
                }
                if (val && typeof val === "object" && val.__toolRef) {
                    params[p.name] = { __toolRef: val.__toolRef };
                    continue;
                }
                if (p.required && p.type === "string" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.required && p.type === "key" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.type === "mods") {
                    params[p.name] = val || [];
                } else {
                    params[p.name] = val;
                }
            }

            // Add step directly to canvas via macroLab API
            if (window.macroLab && window.macroLab.addTool) {
                window.macroLab.addTool({ action: fn.name, params: params });
            }
            // Also send to Lua for bus event
            window.shellPost("macros", "addTool", {
                action: fn.name,
                params: params
            });

            showToast("Added: " + fn.name);
        }

        /* -- Toast -- */
        function showToast(msg) {
            toast.textContent = msg;
            toast.classList.add("show");
            if (_toastTimer) clearTimeout(_toastTimer);
            _toastTimer = setTimeout(function() {
                toast.classList.remove("show");
                _toastTimer = null;
            }, 1800);
        }

        /* -- Escape HTML -- */
        function esc(s) {
            var d = document.createElement("div");
            d.appendChild(document.createTextNode(s));
            return d.innerHTML;
        }

        /* -- Search Input Handler -- */
        searchInput.addEventListener("input", function() {
            renderList(searchInput.value);
        });

        // Prevent key capture from swallowing search input keystrokes
        searchInput.addEventListener("keydown", function(e) {
            e.stopPropagation();
        });

        // Refresh the callable-function list pushed from Lua (setFunctionList).
        function setFunctionList(list) {
            _fnList = Array.isArray(list) ? list : [];
            renderList(searchInput.value);
        }

        /* -- Panel handler (called by consolidated registerPanel below) -- */
        function _fnPickerHandler(action, body) {
            if (action === "functions" && Array.isArray(body)) {
                setFunctionList(body);
            }
            if (action === "selectFunction" && body && body.name) {
                selectFunction(body.name);
            }
        }

        // Refresh the tool list pushed from Lua.
        function setToolList(list) {
            _tools = Array.isArray(list) ? list : [];
            window.msMacroTools = _tools;
            renderList(searchInput.value);
            if (_view === "tool" && _selectedId) {
                var t = findTool(_selectedId);
                if (t) renderToolDetail(t); else { detailPane.innerHTML = ''; _view = "module"; }
            } else {
                for (var name in _toolSelects) {
                    if (!_toolSelects.hasOwnProperty(name)) continue;
                    var picked = _paramBind[name] || "";
                    _toolSelects[name].setOptions(toolSelectOptions());
                    _toolSelects[name].value = picked;
                }
            }
        }

        /* -- External API: allow ms.shell.eval to call in -- */
        window.fnPicker = {
            select: selectFunction,
            registry: REGISTRY,
            showToast: showToast,
            setToolList: setToolList,
            setFunctionList: setFunctionList,
            settingDef: settingDefFor,
            handler: _fnPickerHandler
        };

        /* -- Initial Render -- */
        renderList("");

    })();

(function() {
    "use strict";

    if (typeof window !== "undefined") window.ToolCanvas = ToolCanvas;

    var _svgCache = {};

    // SVG loader //
      function _fetchSVG(name) {
          if (_svgCache[name]) return Promise.resolve(_svgCache[name]);
          if (window.ICONS && window.ICONS[name]) {
              _svgCache[name] = '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' + window.ICONS[name] + '</svg>';
              return Promise.resolve(_svgCache[name]);
          }
          return Promise.resolve("");
      }
    // END SVG loader //

    // Action to icon mapping //
      var ACTION_ICON = {
          "ms.type":"keyboard","ms.press":"keyboard","ms.hold":"keyboard","ms.release":"keyboard",
          "ms.wait":"timer","ms.copy":"clipboard","ms.paste":"clipboard",
          "ms.cam":"camera","ms.cam.rebalance":"camera","ms.cam.reset":"camera",
          "ms.Mouse":"click","ms.click":"click","ms.scroll":"scroll","ms.move":"move","ms.select":"select",
          "ms.search":"search","ms.record":"record","ms.stop":"stop","ms.pause":"pause",
          "ms.play":"play","ms.save":"save","ms.load":"upload","ms.alert":"alert",
          "ms.refresh":"refresh","ms.pixelScan":"pixelscan","ms.window":"window",
          "ms.input":"inputs","ms.variable":"variable","ms.watch":"watcher",
          "ms.sound":"sound","ms.gamepad":"controller","ms.gamepadStart":"controller","ms.gamepadBind":"controller",
          "ms.setMacros":"power","ms.enable":"power","ms.disable":"power",
          "ms.switchProfile":"settings","ms.switchPack":"macros",
          "ms.screenshot":"camera","ms.clipChanged":"clipboard",
          "ms.randWait":"timer","ms.jitter":"timer","ms.waitPixel":"pixelscan","ms.waitNotPixel":"pixelscan",
          "ms.ocr":"ocr","ms.readNumber":"ocr","ms.findText":"ocr","ms.waitText":"ocr",
          "ms.waitApp":"search","ms.waitNotApp":"search",
          "ms.focus":"window","ms.appRunning":"window","ms.appIsFront":"window",
          "ms.toggle":"keyboard","ms.multiPress":"keyboard",
          "ms.saveCursor":"select","ms.restoreCursor":"select",
          "ms.setVolume":"sound","ms.mute":"sound","ms.unmute":"sound",
          "ms.drag":"drag",
          "if":"branch","for":"loop","while":"repeat","repeat":"repeat","else":"branch",
          "var_set":"variable","var_add":"variable","var_sub":"variable","var_mul":"variable",
          "comment":"inputs","code":"macros","setting":"settings"
      };

      function iconFor(action) { return ACTION_ICON[action] || "macros"; }

      function condSummary(c) {
          if (c && typeof c === "object") {
              if (typeof c.__toolRef === "string") return 'ms.settings.get("' + c.__toolRef + '")';
              if (typeof c.__varRef === "string")  return 'ms.vars.get("' + c.__varRef + '")';
              return "";
          }
          return c || "";
      }
    // END Action to icon mapping //

    // Tool-ref label //
        function toolRefLabel(key) {
            var list = window.msMacroTools || [];
            for (var i = 0; i < list.length; i++) {
                var t = list[i];
                if (t && t.key === key) {
                    return (t.type || "tool") + " " + (t.label || t.key);
                }
            }
            return key;
        }
    // END //

    /* -- Param summary -- */
    function paramSummary(action, params) {
        if (!params) return "";
        var keys = Object.keys(params);
        if (keys.length === 0) return "";
        if (action === "if" || action === "while" || action === "repeat") return condSummary(params.condition);
        if (action === "for") return (params.var||"i") + " = " + (params.from||1) + " -> " + (params.to||1);
        if (action === "comment") return params.text || "";
        if (action === "code") return (params.source||"").split("\n")[0] || "";
        if (action === "setting") return 'ms.settings.get("' + (params.key || "") + '")';
        if (action === "ms.dragPath") {
            var pts = (typeof params.points === "string" && params.points.trim())
                ? params.points.split(";").filter(function(s){ return s.trim(); }).length : 0;
            return (params.button || "Left") + " drag · " + pts + " pts";
        }
        if (action === "ms.switchProfile") return "profile: " + (params.name || "?");
        if (action === "ms.switchPack") return (params.kind || "macro") + " pack: " + (params.slug || "?");
        if (action === "var_set") return (params.name||"v") + " = " + (params.value!==undefined?params.value:"");
        if (action === "var_add" || action === "var_sub" || action === "var_mul") {
            var op = action==="var_add"?"+":action==="var_sub"?"-":"*";
            return (params.name||"v") + " " + op + "= " + (params.amount!==undefined?params.amount:1);
        }
        var parts = [];
        for (var i = 0; i < Math.min(keys.length, 2); i++) {
            var k = keys[i], v = params[k];
            if (v && typeof v === "object" && (v.__toolRef || v.__varRef)) {
                parts.push(k + ": " + toolRefLabel(v.__toolRef || v.__varRef));
                continue;
            }
            if (Array.isArray(v)) { if (v.length === 0) continue; v = v.join("+"); }
            if (typeof v === "string" && v.length > 16) v = v.slice(0,14) + "...";
            parts.push(k + ": " + v);
        }
        return parts.join(", ");
    }

    /* -- Step ID generator -- */
    var _toolIdCounter = 0;
    function nextToolId() { return "_s" + (++_toolIdCounter) + "_" + Date.now().toString(36); }

    function deepClone(o) { return JSON.parse(JSON.stringify(o)); }

    /* -- ToolCanvas class (IIFE version) -- */
    function ToolCanvas(container, opts) {
        this._el = container;
        this._onChange = (opts && opts.onChange) || function(){};
        this._onSelect = (opts && opts.onSelect) || function(){};
        // The parameter editor opens on right-click, not on selection.
        this._onContext = (opts && opts.onContext) || function(){};
        this._tools = [];
        this._map = {};
        // Selection model: _selSet (all selected), _anchorId (shift pivot),
        // _selId (primary, non-null only for one block).
        this._selSet   = {};
        this._anchorId = null;
        this._selId    = null;
        this._dragId = null;
        this._dragGroup = null;  // sids being dragged together (doc order)
        this._root = document.createElement("div");
        this._root.className = "tool-canvas";
        this._el.appendChild(this._root);
        this._renderEmpty();
        this._preloadIcons();

        var self = this;
        this._root.gpReorderSelection = function(dir) {
            var sel = self._selList();
            if (!sel.length) return false;
            var order = self._docOrder();
            var selSet = {};
            for (var s = 0; s < sel.length; s++) selSet[sel[s]] = true;
            if (dir < 0) {
                for (var i = order.indexOf(sel[0]) - 1; i >= 0; i--) {
                    if (!selSet[order[i]]) { self.moveTools(sel, order[i], "above"); return true; }
                }
            } else {
                for (var j = order.indexOf(sel[sel.length - 1]) + 1; j < order.length; j++) {
                    if (!selSet[order[j]]) { self.moveTools(sel, order[j], "below"); return true; }
                }
            }
            return false;
        };
        this._root.gpDuplicateSelection = function() { return self.duplicateSelected(); };
        this._root.gpDeleteSelection = function() { return self.removeSelected(); };

        // The canvas often renders while the Builder tab is hidden (Binds is the
        // landing tab), so widths measure as zero and the marquee never arms.
        // Re-measure whenever the canvas gains or changes size.
        if (window.ResizeObserver) {
            this._ro = new ResizeObserver(function() { self._updateParamMarquee(); });
            this._ro.observe(this._root);
        }
    }

    ToolCanvas.prototype._preloadIcons = function() {
        var needed = ["drag","close","chevdown","macros","copy","paste"];
        for (var a in ACTION_ICON) { if (needed.indexOf(ACTION_ICON[a]) === -1) needed.push(ACTION_ICON[a]); }
        var self = this;
        var chain = Promise.resolve();
        needed.forEach(function(n) { chain = chain.then(function(){ return _fetchSVG(n); }); });
    };

    ToolCanvas.prototype._assignIds = function(steps) {
        for (var i = 0; i < steps.length; i++) {
            var s = steps[i];
            if (!s._sid) s._sid = nextToolId();
            this._map[s._sid] = s;
            if (s.then) this._assignIds(s.then);
            if (s.else) this._assignIds(s.else);
            if (s.body) this._assignIds(s.body);
        }
    };

    ToolCanvas.prototype.load = function(steps) {
        this._tools = steps || [];
        this._map = {};
        this._assignIds(this._tools);
        this._clearSelection();
        this._render();
    };

    // Container actions carry nested child lists. Seed them on insert so the
    // block renders its droppable "then/else/body" nests immediately, even
    // before anything is dropped in.
    function seedContainer(step) {
        if (step.action === "if") {
            if (!step.then) step.then = [];
            if (!step.else) step.else = [];
        } else if (step.action === "for" || step.action === "while" || step.action === "repeat") {
            if (!step.body) step.body = [];
        }
    }

    ToolCanvas.prototype.addTool = function(def, afterId) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        if (afterId) {
            var idx = this._findIdx(this._tools, afterId);
            if (idx !== -1) this._tools.splice(idx+1, 0, step);
            else this._tools.push(step);
        } else {
            this._tools.push(step);
        }
        this._render();
        this._fireChange();
        return step._sid;
    };

    // Insert a new top-level module before `beforeSid` (or at the end when
    // null), selecting it. Used by the picker->canvas drag; keeps insertion at
    // the top level so an external drop can never land inside a container it
    // has no context for.
    ToolCanvas.prototype.insertDefAt = function(def, beforeSid) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        var idx = beforeSid ? this._findIdx(this._tools, beforeSid) : -1;
        if (idx !== -1) this._tools.splice(idx, 0, step);
        else this._tools.push(step);
        this._setSelection([step._sid]);
        this._render();
        this._fireChange();
        return step._sid;
    };

    ToolCanvas.prototype.removeTool = function(sid) {
        if (this._removeFrom(this._tools, sid)) {
            delete this._map[sid];
            this._deselectOne(sid);
            this._render();
            this._emitSelection();
            this._fireChange();
        }
    };

    ToolCanvas.prototype._removeFrom = function(list, sid) {
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) { list.splice(i,1); return true; }
            var s = list[i];
            if (s.then && this._removeFrom(s.then, sid)) return true;
            if (s.else && this._removeFrom(s.else, sid)) return true;
            if (s.body && this._removeFrom(s.body, sid)) return true;
        }
        return false;
    };

    ToolCanvas.prototype._findIdx = function(list, sid) {
        for (var i = 0; i < list.length; i++) { if (list[i]._sid === sid) return i; }
        return -1;
    };

    ToolCanvas.prototype.moveTool = function(dragId, targetId, pos) {
        var step = this._map[dragId];
        if (!step) return;
        this._removeFrom(this._tools, dragId);
        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                if (tgt.action === "if") { if(!tgt.then) tgt.then=[]; tgt.then.push(step); }
                else { if(!tgt.body) tgt.body=[]; tgt.body.push(step); }
            }
        } else {
            var ti = this._findIdx(this._tools, targetId);
            if (ti !== -1) this._tools.splice(pos==="above"?ti:ti+1, 0, step);
            else this._tools.push(step);
        }
        this._render();
        this._fireChange();
    };

    // Locate the list a sid lives in and its index within that list.
    ToolCanvas.prototype._locate = function(sid, list) {
        list = list || this._tools;
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) return { list: list, idx: i };
            var s = list[i];
            var r = (s.then && this._locate(sid, s.then))
                 || (s.else && this._locate(sid, s.else))
                 || (s.body && this._locate(sid, s.body));
            if (r) return r;
        }
        return null;
    };

    // Move a group of blocks (given in document order) to a target, keeping
    // their relative order. A single-element group behaves exactly like
    // moveTool, so both drag paths share this code.
    ToolCanvas.prototype.moveTools = function(dragIds, targetId, pos) {
        if (!dragIds || !dragIds.length) return;
        if (dragIds.indexOf(targetId) !== -1) return;   // never drop onto self
        // Collect the step objects, then detach them all from the tree.
        var steps = [];
        for (var i = 0; i < dragIds.length; i++) {
            var s = this._map[dragIds[i]];
            if (s) { steps.push(s); this._removeFrom(this._tools, dragIds[i]); }
        }
        if (!steps.length) return;

        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                var branch = tgt.action === "if"
                    ? (tgt.then || (tgt.then = []))
                    : (tgt.body || (tgt.body = []));
                for (var j = 0; j < steps.length; j++) branch.push(steps[j]);
            }
        } else {
            // Re-locate the target AFTER detaching, since indices shifted.
            var loc = this._locate(targetId);
            if (loc) {
                var at = pos === "above" ? loc.idx : loc.idx + 1;
                Array.prototype.splice.apply(loc.list, [at, 0].concat(steps));
            } else {
                for (var k = 0; k < steps.length; k++) this._tools.push(steps[k]);
            }
        }
        // The moved blocks stay selected so the group can be nudged again.
        this._setSelection(dragIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        this._fireChange();
    };

    ToolCanvas.prototype.serialize = function() {
        return this._strip(deepClone(this._tools));
    };

    ToolCanvas.prototype._strip = function(steps) {
        for (var i=0;i<steps.length;i++) {
            delete steps[i]._sid;
            if (steps[i].then) this._strip(steps[i].then);
            if (steps[i].else) this._strip(steps[i].else);
            if (steps[i].body) this._strip(steps[i].body);
        }
        return steps;
    };

    ToolCanvas.prototype._fireChange = function() { this._onChange(this.serialize()); };

    ToolCanvas.prototype._render = function() {
        this._root.innerHTML = "";
        if (this._tools.length === 0) { this._renderEmpty(); return; }
        for (var i=0;i<this._tools.length;i++) {
            this._root.appendChild(this._renderTool(this._tools[i]));
        }
        this._updateParamMarquee();
        var self = this;
        requestAnimationFrame(function() { self._updateParamMarquee(); });
    };

    ToolCanvas.prototype._updateParamMarquee = function(el) {
        if (!this._root.offsetParent || this._root.clientWidth === 0) {
            var self = this;
            if (window.requestAnimationFrame) {
                requestAnimationFrame(function() {
                    requestAnimationFrame(function() {
                        if (self._root.offsetParent && self._root.clientWidth > 0) self._updateParamMarquee(el);
                    });
                });
            }
            return;
        }
        var params = el
            ? [el.querySelector(".tool-params")]
            : Array.prototype.slice.call(this._root.querySelectorAll(".tool-params"));
        for (var i = 0; i < params.length; i++) {
            var p = params[i];
            if (!p) continue;
            var shift = p.scrollWidth - p.clientWidth;
            if (shift > 2) {
                p.style.setProperty("--mq", "-" + shift + "px");
                p.classList.add("has-mq");
            } else {
                p.style.removeProperty("--mq");
                p.classList.remove("has-mq");
            }
        }
    };

    ToolCanvas.prototype._renderEmpty = function() {
        this._root.innerHTML = "";
        var d = document.createElement("div");
        d.className = "tool-canvas-empty";
        d.innerHTML = '<span class="tool-canvas-empty-icon"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></span>No modules yet<br><span style="font-size:10px">Click <b>+ Add Module</b> to begin</span>';
        this._root.appendChild(d);
    };

    ToolCanvas.prototype._isContainer = function(s) {
        return s.action==="if" || s.action==="for" || s.action==="while" || s.action==="repeat";
    };

    ToolCanvas.prototype._renderTool = function(step) {
        return this._isContainer(step) ? this._renderContainer(step) : this._renderLeaf(step);
    };

    ToolCanvas.prototype._renderLeaf = function(step) {
        var self = this;
        var isSetting = step.action === "setting";
        var el = document.createElement("div");
        el.className = "tool-block" + (this._isSelected(step._sid)?" selected":"")
            + (isSetting ? " tool-block-setting" : "");
        el.setAttribute("data-sid", step._sid);
        // No draggable="true": reordering is pointer-based (see _wireDrag). The
        // HTML5 DnD API dropped drops in this WKWebView, so blocks are dragged
        // with plain mouse events instead.

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        el.appendChild(h);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        el.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        // A setting block is a reference to a shared tool, not a code action, so
        // it reads "Setting · <label>" rather than the bare "setting" action.
        nm.textContent = isSetting
            ? ("Setting · " + ((step.params && (step.params.label || step.params.key)) || "?"))
            : step.action;
        el.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        el.appendChild(pm);

        el.appendChild(this._buildToolActions(step));

        el.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
            self._updateParamMarquee(el);
        });
        el.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn") || e.target.closest(".tool-drag-handle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        // Right-click opens the parameter editor for just this module. Select
        // it first so the editor and the highlight agree.
        el.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
        });

        this._wireDrag(el, step);
        return el;
    };

    // Copy / paste / delete controls shared by leaf and container blocks.
    // Copy loads this module onto the clipboard; Paste (revealed only once
    // the clipboard holds a module) drops a copy directly after this one.
    ToolCanvas.prototype._buildToolActions = function(step) {
        var self = this;
        var acts = document.createElement("div");
        acts.className = "tool-actions";

        var cp = document.createElement("div");
        cp.className = "tool-action-btn copy";
        cp.title = "Copy module";
        cp.innerHTML = _svgCache["copy"] || (window.icon ? window.icon("copy") : "");
        cp.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        cp.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.copyStep(step._sid);
        });
        acts.appendChild(cp);

        var pt = document.createElement("div");
        pt.className = "tool-action-btn paste";
        pt.title = "Paste module after this one";
        pt.innerHTML = _svgCache["paste"] || (window.icon ? window.icon("paste") : "");
        pt.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        pt.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.pasteAfterId(step._sid);
        });
        acts.appendChild(pt);

        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.title = "Delete module";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        db.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("back");
            self.removeTool(step._sid);
        });
        acts.appendChild(db);

        return acts;
    };

    ToolCanvas.prototype._renderContainer = function(step) {
        var self = this;
        var wrap = document.createElement("div");
        wrap.className = "tool-block-container";
        wrap.setAttribute("data-sid", step._sid);

        var header = document.createElement("div");
        header.className = "tool-block" + (this._isSelected(step._sid)?" selected":"");
        header.setAttribute("data-sid", step._sid);
        // Pointer-based drag; no native draggable (see _wireDrag / _renderLeaf).

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        header.appendChild(h);

        var tg = document.createElement("div");
        tg.className = "tool-nest-toggle";
        tg.innerHTML = _svgCache["chevdown"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7 13L12 18L17 13M7 6L12 11L17 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        tg.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        tg.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            var collapsed = tg.classList.toggle("collapsed");
            // Collapse every branch of THIS container, an `if` has both a
            // "then" and an "else" nest, each with its own label. A plain
            // querySelector(".tool-nest-body") stopped at "then" and left the
            // "else" nest (and both labels) showing. Only direct children are
            // touched, so a nested block keeps its own collapse state.
            for (var ci = 0; ci < wrap.children.length; ci++) {
                var child = wrap.children[ci];
                if (child.classList.contains("tool-nest-body")
                    || child.classList.contains("tool-nest-label")) {
                    child.classList.toggle("collapsed", collapsed);
                }
            }
        });
        header.appendChild(tg);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        header.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        nm.textContent = step.action;
        header.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        header.appendChild(pm);

        header.appendChild(this._buildToolActions(step));

        header.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
            self._updateParamMarquee(header);
        });
        header.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn")||e.target.closest(".tool-drag-handle")||e.target.closest(".tool-nest-toggle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        // Right-click opens the parameter editor for this container.
        header.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
        });
        this._wireDrag(header, step);

        wrap.appendChild(header);

        if (step.action === "if") {
            var tl = document.createElement("div"); tl.className="tool-nest-label"; tl.textContent="then"; wrap.appendChild(tl);
            wrap.appendChild(this._renderNest(step.then||[], "then", step));
            var el2 = document.createElement("div"); el2.className="tool-nest-label"; el2.textContent="else"; wrap.appendChild(el2);
            wrap.appendChild(this._renderNest(step.else||[], "else", step));
        } else {
            wrap.appendChild(this._renderNest(step.body||[], "body", step));
        }
        return wrap;
    };

    ToolCanvas.prototype._renderNest = function(steps, branch, parent) {
        var self = this;
        var body = document.createElement("div");
        body.className = "tool-nest-body";
        body.setAttribute("data-nest-parent", parent._sid);
        body.setAttribute("data-nest-branch", branch);

        if (steps.length === 0) {
            var emp = document.createElement("div");
            emp.className = "tool-nest-body-empty";
            emp.textContent = "empty";
            body.appendChild(emp);
        } else {
            for (var i=0;i<steps.length;i++) body.appendChild(this._renderTool(steps[i]));
        }

        // Dropping a block INTO this branch is handled by the pointer-drag
        // hit-test (see _beginPointerDrag / _commitNest), which targets this
        // element via its data-nest-parent / data-nest-branch attributes. No
        // HTML5 drop wiring here, that API is unreliable in this WKWebView.
        return body;
    };

    /* -- Selection engine -- */

    ToolCanvas.prototype._isSelected = function(sid) {
        return !!this._selSet[sid];
    };
    ToolCanvas.prototype._selCount = function() {
        return Object.keys(this._selSet).length;
    };
    // Selected sids in document (visual) order, the order the user sees, and
    // the order a group keeps when dragged or copied.
    ToolCanvas.prototype._selList = function() {
        var self = this, out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (self._selSet[sid] && out.indexOf(sid) === -1) out.push(sid);
            });
        }
        // Fall back to insertion order for any selected id not currently in the
        // DOM (shouldn't happen, but keeps the set from silently dropping ids).
        for (var sid in this._selSet) { if (out.indexOf(sid) === -1) out.push(sid); }
        return out;
    };
    // All sids in document order, the flat visual sequence shift-range walks.
    ToolCanvas.prototype._docOrder = function() {
        var out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (out.indexOf(sid) === -1) out.push(sid);
            });
        }
        return out;
    };

    // Update state only (no DOM, no emit). Primary/_selId is set iff exactly
    // one block is selected.
    ToolCanvas.prototype._setSelection = function(ids) {
        this._selSet = {};
        for (var i = 0; i < ids.length; i++) { if (ids[i]) this._selSet[ids[i]] = true; }
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
        if (ids.length) this._anchorId = ids[ids.length - 1];
    };
    ToolCanvas.prototype._clearSelection = function() {
        this._selSet = {};
        this._selId = null;
        this._anchorId = null;
    };
    ToolCanvas.prototype._deselectOne = function(sid) {
        delete this._selSet[sid];
        if (this._anchorId === sid) this._anchorId = null;
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
    };

    // Repaint .selected on every block from _selSet without a full re-render.
    ToolCanvas.prototype._applySelectionClasses = function() {
        var self = this;
        if (!this._root) return;
        this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
            var sid = el.getAttribute("data-sid");
            el.classList.toggle("selected", !!self._selSet[sid]);
        });
    };

    // Tell the host what the primary (single) selection is. null ⇒ hide params
    // (nothing selected, or a multi-selection).
    ToolCanvas.prototype._emitSelection = function() {
        this._onSelect(this._selId, this._selId ? this._map[this._selId] : null);
    };

    // Click routing: plain / ⌘(⌃)-toggle / ⇧-range, text-editor semantics.
    ToolCanvas.prototype._clickSelect = function(sid, e) {
        var meta  = e && (e.metaKey || e.ctrlKey);
        var shift = e && e.shiftKey;

        if (meta) {
            // Toggle this block in/out of the selection.
            if (this._selSet[sid]) this._deselectOne(sid);
            else { this._selSet[sid] = true; this._anchorId = sid;
                   var k = Object.keys(this._selSet); this._selId = k.length === 1 ? k[0] : null; }
        } else if (shift && this._anchorId && this._anchorId !== sid) {
            // Select the contiguous visual range between the anchor and here.
            var order = this._docOrder();
            var a = order.indexOf(this._anchorId), b = order.indexOf(sid);
            if (a === -1 || b === -1) { this._setSelection([sid]); }
            else {
                var lo = Math.min(a, b), hi = Math.max(a, b);
                this._selSet = {};
                for (var i = lo; i <= hi; i++) this._selSet[order[i]] = true;
                this._selId = (hi - lo === 0) ? order[lo] : null;
                // keep _anchorId where it was so the range can be re-dragged
            }
        } else {
            // Plain click: if this block is already the sole selection, toggle
            // it off (clears the params); otherwise select just this one.
            if (this._selId === sid && this._selCount() === 1) this._clearSelection();
            else this._setSelection([sid]);
        }

        this._applySelectionClasses();
        this._emitSelection();
    };

    // Public: select exactly these ids and refresh the view + editor.
    ToolCanvas.prototype.select = function(ids) {
        this._setSelection(ids || []);
        this._applySelectionClasses();
        this._emitSelection();
    };
    ToolCanvas.prototype.clearSelection = function() {
        this._clearSelection();
        this._applySelectionClasses();
        this._emitSelection();
    };

    ToolCanvas.prototype._isDesc = function(pid, cid) {
        var p = this._map[pid]; if (!p) return false;
        var ch = [].concat(p.then||[], p.else||[], p.body||[]);
        for (var i=0;i<ch.length;i++) {
            if (ch[i]._sid===cid) return true;
            if (this._isDesc(ch[i]._sid, cid)) return true;
        }
        return false;
    };

    // Pointer-based reorder (mousedown -> mousemove -> mouseup).
    ToolCanvas.prototype._wireDrag = function(el, step) {
        var self = this;
        el.addEventListener("mousedown", function(e) {
            if (e.button !== 0) return;                          // left button only
            if (e.target.closest(".tool-action-btn")) return;    // copy/paste/delete
            if (e.target.closest(".tool-nest-toggle")) return;   // collapse arrow
            // Suppress the native text-selection drag.
            e.preventDefault();
            self._beginPointerDrag(el, step, e);
        });
    };

    // Runs a single reorder gesture (drag begins past a small threshold).
    ToolCanvas.prototype._beginPointerDrag = function(el, step, downEvt) {
        var self = this;
        var startX = downEvt.clientX, startY = downEvt.clientY;
        var THRESH = 4;
        var started = false;
        var ghost = null, offX = 0, offY = 0;
        var group = null;
        var target = null;   // { kind:"block", sid, pos } | { kind:"nest", parent, branch }
        var scroller = self._el;

        function begin() {
            started = true;
            // Single block, or the whole multi-selection when the grabbed block is part of one.
            if (self._isSelected(step._sid) && self._selCount() > 1) {
                group = self._selList();
            } else {
                group = [step._sid];
                if (!self._isSelected(step._sid)) self.select([step._sid]);
            }
            self._dragId = step._sid;
            self._dragGroup = group;
            group.forEach(function(sid) {
                var d = self._root.querySelector('.tool-block[data-sid="'+sid+'"]');
                if (d) d.classList.add("dragging");
            });
            ghost = el.cloneNode(true);
            ghost.classList.add("tool-drag-ghost");
            ghost.style.width = el.offsetWidth + "px";
            var r = el.getBoundingClientRect();
            offX = startX - r.left; offY = startY - r.top;
            if (group.length > 1) {
                var badge = document.createElement("div");
                badge.className = "tool-drag-badge";
                badge.textContent = group.length;
                ghost.appendChild(badge);
            }
            document.body.appendChild(ghost);
            document.body.classList.add("tool-dragging-active");
            moveGhost(startX, startY);
            if (window.playSlot) playSlot("interact");
        }

        function moveGhost(x, y) {
            if (ghost) { ghost.style.left = (x - offX) + "px"; ghost.style.top = (y - offY) + "px"; }
        }

        // Figure out where a drop at (x,y) would land and paint the marker.
        // The ghost is pointer-events:none, so elementFromPoint sees through it.
        function hitTest(x, y) {
            self._clearDrops();
            target = null;
            var under = document.elementFromPoint(x, y);
            if (!under || !under.closest) return;

            var blockEl = under.closest(".tool-block[data-sid]");
            if (blockEl && group.indexOf(blockEl.getAttribute("data-sid")) !== -1) {
                blockEl = null;   // a block in the drag group is not a target
            }
            if (blockEl) {
                var tid = blockEl.getAttribute("data-sid");
                var tstep = self._map[tid];
                var rect = blockEl.getBoundingClientRect();
                var ry = y - rect.top, h = rect.height;
                var pos;
                if (tstep && self._isContainer(tstep) && ry > h*0.3 && ry < h*0.7) pos = "nest";
                else if (ry < h/2) pos = "above";
                else pos = "below";
                if (pos === "nest") {
                    for (var i = 0; i < group.length; i++) {
                        if (group[i] === tid || self._isDesc(group[i], tid)) return;
                    }
                }
                blockEl.classList.add(pos === "nest" ? "drag-over-nest"
                    : pos === "above" ? "drag-over-above" : "drag-over-below");
                target = { kind: "block", sid: tid, pos: pos };
                return;
            }

            // Not over any block, maybe over an (empty) container branch.
            var nestEl = under.closest(".tool-nest-body");
            if (nestEl) {
                var psid = nestEl.getAttribute("data-nest-parent");
                for (var j = 0; j < group.length; j++) {
                    if (group[j] === psid || self._isDesc(group[j], psid)) return;
                }
                nestEl.classList.add("drag-target");
                target = { kind: "nest", parent: psid, branch: nestEl.getAttribute("data-nest-branch") };
            }
        }

        function autoscroll(y) {
            if (!scroller) return;
            var r = scroller.getBoundingClientRect(), M = 28;
            if (y < r.top + M) scroller.scrollTop -= 10;
            else if (y > r.bottom - M) scroller.scrollTop += 10;
        }

        function onMove(e) {
            if (!started) {
                if (Math.abs(e.clientX - startX) < THRESH && Math.abs(e.clientY - startY) < THRESH) return;
                begin();
            }
            e.preventDefault();
            moveGhost(e.clientX, e.clientY);
            autoscroll(e.clientY);
            hitTest(e.clientX, e.clientY);
        }

        function commit() {
            if (!target) return;
            if (target.kind === "block") self.moveTools(group, target.sid, target.pos);
            else self._commitNest(group, target.parent, target.branch);
        }

        function cleanup() {
            document.removeEventListener("mousemove", onMove, true);
            document.removeEventListener("mouseup", onUp, true);
            document.removeEventListener("keydown", onKey, true);
            if (ghost) ghost.remove();
            ghost = null;
            document.body.classList.remove("tool-dragging-active");
            self._root.querySelectorAll(".tool-block.dragging").forEach(function(d) {
                d.classList.remove("dragging");
            });
            self._clearDrops();
            self._dragId = null; self._dragGroup = null;
        }

        function onUp(e) {
            if (started) {
                e.preventDefault(); e.stopPropagation();
                commit();
                // Swallow the click that a mouseup would otherwise synthesise,
                // so a drag never doubles as a select.
                var swallow = function(ev) {
                    ev.stopPropagation(); ev.preventDefault();
                    document.removeEventListener("click", swallow, true);
                };
                document.addEventListener("click", swallow, true);
            }
            cleanup();
        }
        function onKey(e) { if (e.key === "Escape") { target = null; cleanup(); } }

        document.addEventListener("mousemove", onMove, true);
        document.addEventListener("mouseup", onUp, true);
        document.addEventListener("keydown", onKey, true);
    };

    // Drop a group into a container branch (then/else/body), keeping the explicit branch.
    ToolCanvas.prototype._commitNest = function(group, parentSid, branch) {
        var parent = this._map[parentSid];
        if (!parent) return;
        for (var i = 0; i < group.length; i++) {
            if (group[i] === parentSid || this._isDesc(group[i], parentSid)) return;
        }
        var steps = [];
        for (var g = 0; g < group.length; g++) {
            var st = this._map[group[g]];
            if (st) { steps.push(st); this._removeFrom(this._tools, group[g]); }
        }
        if (!steps.length) return;
        var dst = branch === "then" ? (parent.then || (parent.then = []))
                : branch === "else" ? (parent.else || (parent.else = []))
                : (parent.body || (parent.body = []));
        for (var k = 0; k < steps.length; k++) dst.push(steps[k]);
        this._setSelection(group);
        this._render(); this._applySelectionClasses(); this._emitSelection(); this._fireChange();
    };

    ToolCanvas.prototype._clearDrops = function() {
        this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(function(el) {
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
        });
        this._root.querySelectorAll(".drag-target").forEach(function(el) { el.classList.remove("drag-target"); });
    };

    ToolCanvas.prototype.updateTool = function(sid, params, opts) {
        var s = this._map[sid]; if (!s) return;
        for (var k in params) { if (params.hasOwnProperty(k)) s.params[k] = params[k]; }
        // Live typing passes { quiet:true } to patch the summary without re-rendering.
        if (opts && opts.quiet) {
            this._patchSummary(sid);
            this._fireChange();
            return;
        }
        this._render(); this._fireChange();
    };

    // Update just the on-canvas parameter summary for one block, without
    // re-rendering. Direct-child selector so a container's summary isn't
    // confused with a nested child's.
    ToolCanvas.prototype._patchSummary = function(sid) {
        var s = this._map[sid]; if (!s || !this._root) return;
        var block = this._root.querySelector('.tool-block[data-sid="' + sid + '"]');
        if (!block) return;
        var el = block.querySelector(":scope > .tool-params");
        if (el) el.textContent = paramSummary(s.action, s.params);
    };

    ToolCanvas.prototype.getSelectedId = function() { return this._selId; };
    ToolCanvas.prototype.getSelectedTool = function() { return this._selId ? this._map[this._selId] : null; };
    ToolCanvas.prototype.hasSelection = function() { return this._selCount() > 0; };
    ToolCanvas.prototype.getSelectedIds = function() { return this._selList(); };
    // Select every top-level block (⌘A). Nested blocks come along visually via
    // their containers, so a select-all of the top level is the useful default.
    ToolCanvas.prototype.selectAll = function() {
        var ids = this._tools.map(function(s) { return s._sid; });
        this.select(ids);
    };

    /* -- Clipboard (copy / cut / paste) -- */
    // Copy a module onto the clipboard (an array of stripped defs). The
    // .has-clip class on the root reveals every paste button.
    ToolCanvas.prototype._setClipboard = function(steps) {
        var clones = deepClone(steps);
        this._strip(clones);
        try { navigator.clipboard.writeText(JSON.stringify(clones.length === 1 ? clones[0] : clones)); } catch(e) {}
        this._clipboard = clones;
        if (this._root) this._root.classList.add("has-clip");
        return true;
    };
    ToolCanvas.prototype.copyStep = function(sid) {
        var step = sid ? this._map[sid] : null;
        if (!step) return false;
        return this._setClipboard([step]);
    };
    ToolCanvas.prototype.copySelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        var steps = [];
        for (var i = 0; i < ids.length; i++) { if (this._map[ids[i]]) steps.push(this._map[ids[i]]); }
        if (!steps.length) return false;
        return this._setClipboard(steps);
    };
    ToolCanvas.prototype.cutSelected = function() {
        if (!this.copySelected()) return false;
        this.removeSelected();
        return true;
    };
    // Remove every selected block (a grouped delete). Detaches all, then
    // clears the selection and repaints once.
    ToolCanvas.prototype.removeSelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        for (var i = 0; i < ids.length; i++) {
            if (this._removeFrom(this._tools, ids[i])) delete this._map[ids[i]];
        }
        this._clearSelection();
        this._render();
        this._emitSelection();
        this._fireChange();
        return true;
    };
    // Paste the clipboard modules after `afterId` (or at the end when null),
    // preserving their order and selecting the pasted block(s).
    ToolCanvas.prototype.pasteAfterId = function(afterId) {
        if (!this._clipboard) return false;
        var entries = Array.isArray(this._clipboard) ? this._clipboard : [this._clipboard];
        if (!entries.length) return false;
        var newIds = [];
        var insertAt = afterId ? this._findIdx(this._tools, afterId) : -1;
        // No anchor pastes at the top, with an anchor directly after it.
        var atTop = (insertAt === -1);
        for (var i = 0; i < entries.length; i++) {
            var clone = deepClone(entries[i]);
            clone._sid = nextToolId();
            this._map[clone._sid] = clone;
            if (clone.then) this._assignIds(clone.then);
            if (clone.else) this._assignIds(clone.else);
            if (clone.body) this._assignIds(clone.body);
            if (atTop) this._tools.splice(i, 0, clone);
            else this._tools.splice(insertAt + 1 + i, 0, clone);
            newIds.push(clone._sid);
        }
        this._setSelection(newIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        if (this._root) this._root.classList.add("has-clip");
        this._fireChange();
        return true;
    };
    ToolCanvas.prototype.pasteAfter = function() {
        // Paste after the last selected block so a group paste lands in order.
        var ids = this._selList();
        return this.pasteAfterId(ids.length ? ids[ids.length - 1] : null);
    };
    // Clone the selected blocks in place, directly after the last one, without
    // touching the clipboard. The copies become the new selection.
    ToolCanvas.prototype.duplicateSelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        var afterId = ids[ids.length - 1];
        var insertAt = this._findIdx(this._tools, afterId);
        var atTop = (insertAt === -1);
        var newIds = [];
        for (var i = 0; i < ids.length; i++) {
            var src = this._map[ids[i]];
            if (!src) continue;
            var clone = deepClone(src);
            this._strip([clone]);
            clone._sid = nextToolId();
            this._map[clone._sid] = clone;
            if (clone.then) this._assignIds(clone.then);
            if (clone.else) this._assignIds(clone.else);
            if (clone.body) this._assignIds(clone.body);
            if (atTop) this._tools.splice(newIds.length, 0, clone);
            else this._tools.splice(insertAt + 1 + newIds.length, 0, clone);
            newIds.push(clone._sid);
        }
        if (!newIds.length) return false;
        this._setSelection(newIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        this._fireChange();
        return true;
    };

    /* -- Macro Management State -- */
    var _currentMacroId = null;
    var _currentMacroDef = null;
    var _macroDirty = false;
    var _canvas = null;
    var _mtabs = null;

    /* -- Layout Setup -- */
    var slot = document.getElementById("slot-macros");
    if (!slot) return;

    // The existing function picker is already in slot-macros as a .fn-picker child.
    // We restructure: wrap it in a layout with toolbar + step canvas + overlay.

    var existingPicker = slot.querySelector(".fn-picker");

    // Create the macros layout wrapper
    var layout = document.createElement("div");
    layout.className = "macros-layout";

    // -- Toolbar --
    var toolbar = document.createElement("div");
    toolbar.className = "macro-toolbar";

    var macroLabel = document.createElement("span");
    macroLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-right:4px";
    macroLabel.textContent = "Macro";
    toolbar.appendChild(macroLabel);

    // Custom dropdown rather than <select>, exposing .value + "change".
    var macroSelect = (function() {
        var root = document.createElement("div");
        root.className = "macro-select";
        root.tabIndex = 0;

        var label = document.createElement("span");
        label.className = "macro-select-label";
        root.appendChild(label);

        var arrow = document.createElement("span");
        arrow.className = "macro-select-arrow";
        // chevdown from the shell's ICONS rather than a typographic arrow.
        arrow.innerHTML = (typeof window.icon === "function" && window.ICONS
            && window.ICONS.chevdown)
            ? window.icon("chevdown")
            : "";
        root.appendChild(arrow);

        var menu = document.createElement("div");
        menu.className = "macro-select-menu";
        root.appendChild(menu);

        var _opts = [];
        var _value = "";
        // Shown on the closed button when nothing is selected, never a menu row.
        var PLACEHOLDER = "Select";

        function labelFor(v) {
            for (var i = 0; i < _opts.length; i++) {
                if (_opts[i].value === v) return _opts[i].label;
            }
            return "";
        }
        function close() { root.classList.remove("open"); }
        function render() {
            // Empty value -> the button reads "Select"; the menu never carries a
            // "Select" row (it's a placeholder, not a real choice).
            var lbl = _value ? labelFor(_value) : "";
            label.textContent = lbl || PLACEHOLDER;
            menu.innerHTML = "";
            // Real, selectable options only, anything with an empty value is a
            // placeholder and is dropped from the list.
            var choices = _opts.filter(function(o) { return o.value !== ""; });
            if (choices.length === 0) {
                // Nothing created yet: a single, non-selecting "None" row so the
                // open menu isn't blank. It's replaced by the first real entry
                // as soon as one exists.
                var none = document.createElement("div");
                none.className = "macro-select-item macro-select-empty";
                none.textContent = "None";
                menu.appendChild(none);
                return;
            }
            choices.forEach(function(o) {
                var item = document.createElement("div");
                item.className = "macro-select-item" + (o.value === _value ? " active" : "");
                item.textContent = o.label;
                item.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                item.addEventListener("click", function(e) {
                    e.stopPropagation();
                    if (window.playSlot) playSlot("interact");
                    close();
                    if (o.value === _value) return;
                    _value = o.value;
                    render();
                    root.dispatchEvent(new Event("change"));
                });
                menu.appendChild(item);
            });
        }

        root.setOptions = function(list) { _opts = list; render(); };
        Object.defineProperty(root, "value", {
            get: function() { return _value; },
            set: function(v) { _value = v == null ? "" : String(v); render(); },
        });

        root.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        root.addEventListener("click", function(e) {
            e.stopPropagation();
            if (!root.classList.contains("open")) {
                if (window.playSlot) playSlot("interact");
                _gpIndex = -1;
                menu.querySelectorAll(".gp-hi").forEach(function(it) { it.classList.remove("gp-hi"); });
            }
            root.classList.toggle("open");
        });
        root.addEventListener("keydown", function(e) {
            if (e.key === "Escape") close();
        });
        document.addEventListener("click", close);

        var _gpIndex = -1;
        function gpItems() {
            return Array.prototype.slice.call(
                menu.querySelectorAll(".macro-select-item:not(.macro-select-empty)"));
        }
        function gpHighlight(i) {
            var items = gpItems();
            if (!items.length) { _gpIndex = -1; return; }
            _gpIndex = ((i % items.length) + items.length) % items.length;
            items.forEach(function(it, idx) { it.classList.toggle("gp-hi", idx === _gpIndex); });
            items[_gpIndex].scrollIntoView({ block: "nearest" });
        }
        root.gpIsOpen = function() { return root.classList.contains("open"); };
        root.gpMove = function(dir) {
            var items = gpItems();
            if (!items.length) return;
            var start = _gpIndex;
            if (start < 0) start = items.findIndex(function(it) { return it.classList.contains("active"); });
            gpHighlight(start < 0 ? 0 : start + dir);
            if (window.playSlot) playSlot("hover");
        };
        root.gpPick = function() {
            var items = gpItems();
            var it = items[_gpIndex];
            if (!it) it = items.filter(function(x) { return x.classList.contains("active"); })[0] || items[0];
            if (it) it.click();
        };
        root.gpClose = function() { _gpIndex = -1; close(); };

        // No options until the macro list arrives from Lua. The button reads
        // "Select" on its own, and the open menu shows "None".
        root.setOptions([]);
        return root;
    })();
    toolbar.appendChild(macroSelect);

    var nameInput = document.createElement("input");
    nameInput.className = "macro-name-input";
    nameInput.type = "text";
    nameInput.placeholder = "Macro name";
    nameInput.setAttribute("spellcheck", "false");
    nameInput.setAttribute("autocomplete", "off");
    nameInput.setAttribute("autocorrect", "off");
    nameInput.setAttribute("autocapitalize", "off");
    // Shell sounds: hover on enter, interact on focus (a click into the field).
    // Guarded on playSlot so it no-ops in a bus-less context.
    nameInput.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    nameInput.addEventListener("focus", function() {
        if (window.playSlot) playSlot("interact");
    });
    toolbar.appendChild(nameInput);

    // Bind field, sets macroDef.bind for the compiler.
    var bindLabel = document.createElement("span");
    bindLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    bindLabel.textContent = "Bind";
    toolbar.appendChild(bindLabel);

    var bindBtn = document.createElement("button");
    bindBtn.className = "bind-pill unset";
    bindBtn.textContent = "UNSET";
    bindBtn.title = "Click to capture a bind for this macro";
    toolbar.appendChild(bindBtn);

    // Class field: marks the macro MAIN or OPTIONAL, driving its bind group.
    var _currentMacroClass = "main";   // "main" | "optional"
    var _currentMacroCooldown = null;
    var _currentMacroShared = "";

    var classLabel = document.createElement("span");
    classLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    classLabel.textContent = "Class";
    toolbar.appendChild(classLabel);

    // Two-button segmented control, reusing the param Value/Tool switch styling.
    var classSeg = document.createElement("span");
    classSeg.className = "fn-bind-switch macro-class-seg";
    function buildClassOpt(value, text) {
        var b = document.createElement("button");
        b.className = "fn-bind-opt" + (_currentMacroClass === value ? " on" : "");
        b.setAttribute("data-class", value);
        b.textContent = text;
        b.title = value === "main"
            ? "Main macro, grouped under VISUAL - MAIN"
            : "Optional macro, grouped under VISUAL - OPTIONAL";
        b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        b.addEventListener("click", function() {
            if (_currentMacroClass === value) return;
            if (window.playSlot) playSlot("interact");
            setMacroClass(value);
            _macroDirty = true;
            updateSaveBtnState();
        });
        return b;
    }
    classSeg.appendChild(buildClassOpt("main", "Main"));
    classSeg.appendChild(buildClassOpt("optional", "Optional"));
    toolbar.appendChild(classSeg);

    // Reflect the current class onto the segmented control.
    function setMacroClass(value) {
        _currentMacroClass = (value === "optional") ? "optional" : "main";
        var opts = classSeg.querySelectorAll(".fn-bind-opt");
        opts.forEach(function(o) {
            o.classList.toggle("on", o.getAttribute("data-class") === _currentMacroClass);
        });
    }
    // Derive the class from a stored macro group string ("visual - optional").
    function classFromGroup(group) {
        return (typeof group === "string" && /optional/i.test(group)) ? "optional" : "main";
    }

    // Right-side action cluster, margin-left:auto pins it right.
    var actions = document.createElement("div");
    actions.className = "macro-toolbar-actions";

    // New macro button
    var newBtn = document.createElement("button");
    newBtn.className = "macro-toolbar-btn";
    newBtn.textContent = "New";
    actions.appendChild(newBtn);

    // Save button
    var saveBtn = document.createElement("button");
    saveBtn.className = "macro-toolbar-btn primary";
    saveBtn.textContent = "Save";
    actions.appendChild(saveBtn);

    // Secondary actions live under an overflow menu so the toolbar never clips them. New/Save/Bind stay inline.
    var overflowWrap = document.createElement("div");
    overflowWrap.className = "macro-overflow";
    var overflowBtn = document.createElement("button");
    overflowBtn.className = "macro-toolbar-btn macro-overflow-btn";
    overflowBtn.textContent = "⋯"; // ⋯
    overflowBtn.title = "More actions";
    var overflowMenu = document.createElement("div");
    overflowMenu.className = "macro-overflow-menu";
    overflowWrap.appendChild(overflowBtn);
    overflowWrap.appendChild(overflowMenu);

    function closeOverflow() { overflowWrap.classList.remove("open"); }
    overflowBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    overflowBtn.addEventListener("click", function(e) {
        e.stopPropagation();
        if (!overflowWrap.classList.contains("open") && window.playSlot) playSlot("interact");
        overflowWrap.classList.toggle("open");
    });
    // A menu item's own handler still runs; close the menu after any click in it.
    overflowMenu.addEventListener("click", function() { closeOverflow(); });
    document.addEventListener("click", closeOverflow);

    // Every overflow item is icon + label so the menu reads as one consistent list.
    function menuLabel(name, text) {
        return (window.icon ? window.icon(name) : "") + '<span>' + text + '</span>';
    }

    var flowCooldownRow = document.createElement("div");
    flowCooldownRow.className = "macro-flow-row";
    var cooldownLbl = document.createElement("label");
    cooldownLbl.textContent = "Cooldown (ms)";
    var cooldownInput = document.createElement("input");
    cooldownInput.className = "macro-flow-input";
    cooldownInput.type = "number";
    cooldownInput.min = "0";
    cooldownInput.step = "50";
    cooldownInput.placeholder = "1000";
    cooldownInput.title = "Milliseconds the macro stays locked after it fires. Re-triggers within this window are ignored. Blank uses the default of 1000.";
    cooldownInput.setAttribute("spellcheck", "false");
    cooldownInput.addEventListener("input", function() {
        var raw = cooldownInput.value.trim();
        _currentMacroCooldown = raw === "" ? null : Math.max(0, parseInt(raw, 10) || 0);
        _macroDirty = true;
        updateSaveBtnState();
    });
    flowCooldownRow.appendChild(cooldownLbl);
    flowCooldownRow.appendChild(cooldownInput);

    var flowGroupRow = document.createElement("div");
    flowGroupRow.className = "macro-flow-row";
    var sharedLbl = document.createElement("label");
    sharedLbl.textContent = "Group";
    var sharedInput = document.createElement("input");
    sharedInput.className = "macro-flow-input";
    sharedInput.type = "text";
    sharedInput.placeholder = "solo";
    sharedInput.title = "Macros sharing a group name never run at the same time. Blank keeps this macro isolated to itself.";
    sharedInput.setAttribute("spellcheck", "false");
    sharedInput.setAttribute("autocomplete", "off");
    sharedInput.addEventListener("input", function() {
        var clean = sharedInput.value.replace(/[^A-Za-z0-9_ -]/g, "");
        if (clean !== sharedInput.value) sharedInput.value = clean;
        _currentMacroShared = clean.trim();
        _macroDirty = true;
        updateSaveBtnState();
    });
    flowGroupRow.appendChild(sharedLbl);
    flowGroupRow.appendChild(sharedInput);

    [flowCooldownRow, flowGroupRow].forEach(function(row) {
        row.addEventListener("click", function(e) { e.stopPropagation(); });
    });

    var flowDivider = document.createElement("div");
    flowDivider.className = "macro-overflow-divider";

    overflowMenu.appendChild(flowCooldownRow);
    overflowMenu.appendChild(flowGroupRow);
    overflowMenu.appendChild(flowDivider);

    // Test Run button
    var testBtn = document.createElement("button");
    testBtn.className = "macro-toolbar-btn";
    testBtn.innerHTML = menuLabel("play", "Test");
    testBtn.title = "Test Run current macro";
    overflowMenu.appendChild(testBtn);

    // Record button, with a paired menu button for recording settings.
    var recordRow = document.createElement("div");
    recordRow.className = "macro-record-row";
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = menuLabel("record", "Record");
    recordBtn.title = "Record user actions into modules";
    recordRow.appendChild(recordBtn);

    var recSettingsBtn = document.createElement("button");
    recSettingsBtn.className = "macro-toolbar-btn macro-record-settings-btn";
    recSettingsBtn.textContent = "⋯"; // ⋯
    recSettingsBtn.title = "Recording settings";
    recSettingsBtn.setAttribute("aria-label", "Recording settings");
    recordRow.appendChild(recSettingsBtn);

    overflowMenu.appendChild(recordRow);

    // Delete button
    var delMacroBtn = document.createElement("button");
    delMacroBtn.className = "macro-toolbar-btn danger";
    delMacroBtn.innerHTML = menuLabel("trash", "Delete");
    delMacroBtn.title = "Delete macro";
    overflowMenu.appendChild(delMacroBtn);

    // Edit raw macro file, the escape hatch for anything the builder doesn't cover.
    var editFileBtn = document.createElement("button");
    editFileBtn.className = "macro-toolbar-btn";
    editFileBtn.innerHTML = menuLabel("edit", "Edit File");
    editFileBtn.title = "Open ms_macros.lua in your editor";
    overflowMenu.appendChild(editFileBtn);

    // Change the app "Edit File" opens in.
    var editorBtn = document.createElement("button");
    editorBtn.className = "macro-toolbar-btn";
    editorBtn.innerHTML = menuLabel("settings", "Change Editor");
    editorBtn.title = "Pick which app opens ms_macros.lua";
    overflowMenu.appendChild(editorBtn);

    actions.appendChild(overflowWrap);
    toolbar.appendChild(actions);

    // -- Main area --
    var mainArea = document.createElement("div");
    mainArea.className = "macros-main";

    // Tool canvas area
    var toolArea = document.createElement("div");
    toolArea.className = "macros-tool-area";
    // Canvas container (ToolCanvas will be mounted here)
    var canvasContainer = document.createElement("div");
    // overflow-y:auto so the module list scrolls.
    canvasContainer.className = "macros-canvas-scroll";
    canvasContainer.style.cssText = "flex:1;overflow-y:auto;overflow-x:hidden;position:relative";
    toolArea.appendChild(canvasContainer);

    mainArea.appendChild(toolArea);

    // Floating add-tool button
    var addToolBtn = document.createElement("button");
    addToolBtn.className = "macros-add-tool-btn";
    addToolBtn.innerHTML = (_svgCache["add"] || "+") + " Add Module";
    toolArea.appendChild(addToolBtn);

    // Test run / recording toast
    var testToast = document.createElement("div");
    testToast.className = "macro-test-toast";
    toolArea.appendChild(testToast);

    // Fn-picker overlay (the existing picker, restructured)
    var overlay = document.createElement("div");
    overlay.className = "fn-picker-overlay";

    var overlayHeader = document.createElement("div");
    overlayHeader.className = "fn-picker-overlay-header";
    var overlayTitle = document.createElement("span");
    overlayTitle.className = "fn-picker-overlay-title";
    overlayTitle.textContent = "Add Module";
    overlayHeader.appendChild(overlayTitle);
    var overlayClose = document.createElement("div");
    overlayClose.className = "fn-picker-overlay-close";
    overlayClose.innerHTML = (_svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>');
    overlayClose.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    overlayClose.addEventListener("click", function() {
        if (window.playSlot) playSlot("back");
        closeFnOverlay();
    });
    overlayHeader.appendChild(overlayClose);
    overlay.appendChild(overlayHeader);

    // Move existing picker into overlay
    if (existingPicker) {
        existingPicker.style.width = "100%";
        existingPicker.style.height = "100%";
        existingPicker.style.flex = "1";
        overlay.appendChild(existingPicker);
    }
    mainArea.appendChild(overlay);

    // -- Tab strip: Builder | Binds --
    // Rebinding lives here, this panel owns every macro.
    var mtabs = document.createElement("div");
    mtabs.className = "mtabs";

    // Binds is the landing tab.
    var builderSection = document.createElement("div");
    builderSection.className = "mtab-section";
    builderSection.setAttribute("data-msec", "builder");

    var bindsSection = document.createElement("div");
    bindsSection.className = "mtab-section active";
    bindsSection.setAttribute("data-msec", "binds");

    var bindsScroll = document.createElement("div");
    bindsScroll.className = "binds-scroll";
    bindsSection.appendChild(bindsScroll);

    // Rebuilt by renderBindList; the cards inserted above it persist.
    var bindList = document.createElement("div");
    bindsScroll.appendChild(bindList);

    /* -- Pack Info (ms.macroMeta) editor -- */
    var _metaLoaded  = false;   // suppress dirty-marking during programmatic fill
    var _metaDirty   = false;
    var _metaOwned   = false;   // true when handwritten ms_macros.lua owns the meta

    function metaField(labelText, placeholder) {
        var wrap = document.createElement("label");
        wrap.className = "meta-field";
        var lb = document.createElement("span");
        lb.className = "meta-field-label";
        lb.textContent = labelText;
        var inp = document.createElement("input");
        inp.type = "text";
        inp.className = "meta-input";
        inp.placeholder = placeholder || "";
        // Keydown must not bubble to the canvas shortcut handler (⌘A/Delete etc.)
        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
        inp.addEventListener("input", function() {
            if (_metaLoaded) { _metaDirty = true; updateMetaSaveBtn(); }
        });
        wrap.appendChild(lb);
        wrap.appendChild(inp);
        return { wrap: wrap, input: inp };
    }

    // Pack Info: credits editor, standard always-open section (msUI kit).
    var _kit = window.msUI;
    var _metaName    = metaField("Name",    "My Macros");
    var _metaVersion = metaField("Version", "1.0.0");
    var _metaAuthor  = metaField("Author",  "You");
    var _metaWebsite = metaField("Website", "https://...");

    var metaSaveBtn = _kit.actionBtn("Save Pack Info", "", function() {
        if (!_metaDirty) return;
        if (window.shellPost) {
            shellPost("macros", "setMeta", {
                name:    _metaName.input.value.trim(),
                version: _metaVersion.input.value.trim(),
                author:  _metaAuthor.input.value.trim(),
                website: _metaWebsite.input.value.trim(),
            });
        }
        _metaDirty = false;
        updateMetaSaveBtn();
    });
    var metaSaveRow = _kit.btnRow(metaSaveBtn);

    var metaCard = _kit.section("macro-meta", "Pack Info", function(body) {
        var form = _kit.h("div", { cls: "meta-form" });
        form.appendChild(_metaName.wrap);
        form.appendChild(_metaVersion.wrap);
        form.appendChild(_metaAuthor.wrap);
        form.appendChild(_metaWebsite.wrap);
        form.appendChild(metaSaveRow);
        body.appendChild(form);
    }, "Credits baked into your visual macros (ms.macroMeta)");
    var metaDesc = metaCard.querySelector(".section-desc");
    bindsScroll.insertBefore(metaCard, bindList);

    // Installed Macro Packs: hotswap library, mirrors the theme/sound managers.
    // Full parity with the profiles panel: ⋯ menu per pack, plus a single
    // Manage sub-section (Create New / Save current / Import / Export).
    var _macroLib = [];
    var packList;

    // Per-pack actions, matching libMenuItems in panel-theme and the profiles
    // panel's profileMenuItems so all three surfaces share one menu shape.
    function macroMenuItems(e) {
        var items = [];
        if (!e.active) items.push({
            icon: "", label: "Activate this macro pack",
            action: function() { window.msLibraryClient.activate("macro", e.slug, e.name); },
        });
        items.push({
            icon: "", label: "Export this macro pack...",
            action: function() {
                if (window.sendToHost) window.sendToHost({
                    action: "exportPackage", type: "macro", slug: e.slug, name: e.name,
                });
            },
        });
        items.push({
            icon: "", label: "Rename...",
            action: async function() {
                var r = await window.openModal(
                    "Rename macro pack",
                    "New name for \"" + e.name + "\".",
                    "Rename", "Cancel", true, e.name);
                var v = (r.value || "").trim();
                if (r.confirmed && v) window.msLibraryClient.rename("macro", e.slug, v);
            },
        });
        items.push({
            icon: "", label: "Remove from library", danger: true,
            action: async function() {
                var r = await window.openModal(
                    "Delete " + e.name + "?",
                    "Removes it from your library. Macros already applied stay in place.",
                    "Delete", "Cancel");
                if (r.confirmed) window.msLibraryClient.remove("macro", e.slug);
            },
        });
        return items;
    }

    var packCreateBtn = _kit.actionBtn("Create New macro pack", "", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        // Name the pack, then choose seed-or-blank — the mirror of Create New
        // Profile. Macro packs seed their whole slice, ms_macros.lua included.
        var r = await window.openModal(
            "Create New macro pack",
            "Name a fresh macro pack.",
            "Next", "Cancel", true, "");
        var v = (r.value || "").trim();
        if (!r.confirmed || !v) return;
        var s = await window.openModal(
            "Create \"" + v + "\"",
            "Start it from your current macros, or blank?",
            "Seed from current", "Start blank");
        window.msLibraryClient.createEmpty("macro", v, s.confirmed);
    });
    var packSaveBtn = _kit.actionBtn("Save current macros...", "", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        var r = await window.openModal(
            "Save current macros",
            "Name this macro pack so you can hotswap back to it later.",
            "Save", "Cancel", true, "");
        if (r.confirmed) window.msLibraryClient.capture("macro", (r.value || "").trim());
    });

    // Import routes by the package's manifest; Export here is the live pack
    // (per-pack export lives in each row's ⋯ menu).
    var packImportBtn = _kit.actionBtn("Import macro pack...", "", function() {
        if (window.sendToHost) window.sendToHost({ action: "importPackage" });
    });
    var packExportBtn = _kit.actionBtn("Export current macros...", "", function() {
        if (window.sendToHost) window.sendToHost({ action: "exportPackage", type: "macro" });
    });

    var packCard = _kit.section("installed-macro", "Installed Macro Packs", function(body) {
        packList = _kit.h("div", { id: "library-list-macro", cls: "library-list" });
        body.appendChild(packList);
    }, "Hotswap a saved macro set");
    // Clear every stored pack except the active one, mirroring the profiles
    // panel. Always rendered (manage section is not repainted per push); the
    // host clears only non-active entries.
    var packClearBtn = _kit.actionBtn("Clear Saved macro packs", "danger", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        var r = await window.openModal(
            "Clear Saved macro packs",
            "Delete all saved macro packs except the active one?"
            + "\n\nThis cannot be undone.",
            "Delete All", "Cancel");
        if (r.confirmed) window.msLibraryClient.clear("macro");
    });
    var packManageCard = _kit.section("manage-macro", "Manage", function(body) {
        body.appendChild(_kit.btnRow(packCreateBtn, packSaveBtn));
        body.appendChild(_kit.btnRow(packImportBtn, packExportBtn));
        body.appendChild(_kit.btnRow(packClearBtn));
    }, "Creating, saving and moving macro packs");
    // Managers sit at the bottom, matching the theme/sound panels' order.
    bindsScroll.appendChild(packCard);
    bindsScroll.appendChild(packManageCard);

    function fillMacroLib() {
        var kit = window.msUI;
        packList.innerHTML = "";
        if (!kit) return;

        if (!_macroLib.length) {
            packList.appendChild(kit.h("div", { cls: "theme-note" },
                "Nothing here yet. Install a macro pack from Browse, or save "
                + "your current one below."));
            return;
        }

        for (var i = 0; i < _macroLib.length; i++) {
            (function(e) {
                var meta = [e.origin, e.version].filter(Boolean).join(" · ");
                var r = kit.h("div", { cls: "row",
                    onmouseenter: function() { if (window.playSlot) playSlot("hover"); } });
                var lbl = kit.h("div", { cls: "row-label" }, e.name);
                if (meta) lbl.appendChild(kit.h("small", {}, meta));
                r.appendChild(lbl);
                if (e.active) r.appendChild(kit.h("span", { cls: "pill success" }, "Active"));

                var menuBtn = kit.h("button", {
                    cls: "row-menu-btn", title: "macro pack actions",
                    onmouseenter: function() { if (window.playSlot) playSlot("hover"); },
                }, "⋯");
                var openMenu = function(x, y) {
                    if (window.playSlot) playSlot("interact");
                    kit.showCtxMenu(x, y, macroMenuItems(e), e.name);
                };
                menuBtn.addEventListener("click", function(ev) {
                    ev.preventDefault(); ev.stopPropagation();
                    var rect = menuBtn.getBoundingClientRect();
                    openMenu(rect.right, rect.bottom);
                });
                r.appendChild(menuBtn);

                if (!e.active) r.addEventListener("click", function() {
                    window.msLibraryClient.activate("macro", e.slug, e.name);
                });
                r.addEventListener("contextmenu", function(ev) {
                    ev.preventDefault(); ev.stopImmediatePropagation();
                    openMenu(ev.clientX, ev.clientY);
                });
                packList.appendChild(r);
            })(_macroLib[i]);
        }
    }

    if (window.msLibraryClient) {
        window.msLibraryClient.on("macro", function(entries) {
            _macroLib = entries || [];
            fillMacroLib();
        });
        window.msLibraryClient.request("macro");
    }

    function updateMetaSaveBtn() {
        var on = _metaDirty && !_metaOwned;
        metaSaveBtn.disabled = !on;
        metaSaveBtn.style.opacity = on ? "1" : "0.5";
    }
    updateMetaSaveBtn();

    function refreshMeta() {
        if (window.shellPost) shellPost("macros", "getMeta", {});
    }

    function setMeta(meta) {
        meta = meta || {};
        _metaLoaded = false;
        _metaName.input.value    = meta.name    || "";
        _metaVersion.input.value = meta.version || "";
        _metaAuthor.input.value  = meta.author  || "";
        _metaWebsite.input.value = meta.website || "";
        _metaLoaded = true;
        _metaDirty  = false;

        // Handwritten ms_macros.lua credits are shown read-only.
        _metaOwned = meta.owned === true;
        [_metaName, _metaVersion, _metaAuthor, _metaWebsite].forEach(function(f) {
            f.input.readOnly = _metaOwned;
            f.input.classList.toggle("meta-input-locked", _metaOwned);
        });
        metaDesc.textContent = _metaOwned
            ? "Sourced from your handwritten ms_macros.lua (read-only)"
            : "Credits baked into your visual macros (ms.macroMeta)";
        metaSaveRow.style.display = _metaOwned ? "none" : "";
        updateMetaSaveBtn();
    }

    ["builder", "binds"].forEach(function(id) {
        var b = document.createElement("button");
        b.className = "mtab" + (id === "binds" ? " active" : "");
        b.setAttribute("data-mtab", id);
        b.textContent = id === "builder" ? "Builder" : "Manager";
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function() {
            if (_mtabs) _mtabs.switch(id);
        });
        mtabs.appendChild(b);
    });

    // Assemble layout
    builderSection.appendChild(toolbar);
    builderSection.appendChild(mainArea);
    layout.appendChild(mtabs);
    layout.appendChild(builderSection);
    layout.appendChild(bindsSection);
    slot.appendChild(layout);

    // Shared tab model, same switch/sound behaviour as every other panel.
    _mtabs = window.createTabs && window.createTabs({
        root: layout,
        tabSelector: ".mtab",
        sectionSelector: ".mtab-section",
        tabKey: function(el) { return el.getAttribute("data-mtab"); },
        sectionKey: function(el) { return el.getAttribute("data-msec"); },
        onSame: function() { if (window.playSlot) playSlot("back"); },
        onSwitch: function(tab) {
            if (window.playSlot) playSlot("interact");
            if (tab === "binds") {
                refreshBindList();
                refreshMeta();
                // Re-fetch the library each time the tab is shown so a request
                // dropped at boot (host bridge not ready yet) self-heals rather
                // than leaving Installed Macro Packs permanently empty.
                if (window.msLibraryClient) window.msLibraryClient.request("macro");
            } else if (tab === "builder" && _canvas) {
                requestAnimationFrame(function() {
                    requestAnimationFrame(function() { _canvas._updateParamMarquee(); });
                });
            }
        },
    });

    // -- Tool Canvas instance --
    _canvas = new ToolCanvas(canvasContainer, {
        onChange: function(steps) {
            _macroDirty = true;
            updateSaveBtnState();
        },
        onSelect: function(sid, step) {
            if (!_toolEditor) return;
            // Selecting only closes a stale editor when the block is no longer the sole selection. Opening is the right-click gesture.
            if (_toolEditor._open && (!sid || _toolEditor._toolSid !== sid)) {
                _toolEditor.close();
            }
        },
        onContext: function(sid) {
            if (!_toolEditor || !sid) return;
            // Right-click toggles the parameter editor open or closed for this module.
            if (_toolEditor._open && _toolEditor._toolSid === sid) {
                _toolEditor.close();
            } else {
                _toolEditor.open(sid);
            }
        }
    });

    // -- Picker -> canvas drag-drop --
    // Dropping a picker module onto the canvas inserts a new top-level module.
    (function() {
        var FN_MIME     = "application/x-ms-fn";
        var TOOL_MIME   = "application/x-ms-tool";
        var CALLFN_MIME = "application/x-ms-callfn";
        function hasType(e, mime) {
            var types = e.dataTransfer && e.dataTransfer.types;
            if (!types) return false;
            return Array.prototype.indexOf.call(types, mime) !== -1;
        }
        function hasFn(e)   { return hasType(e, FN_MIME) || hasType(e, TOOL_MIME) || hasType(e, CALLFN_MIME); }
        // Build a "Call function" step preset to a dragged function id.
        function buildCallFnDef(id) {
            if (!id) return null;
            return { action: "call_fn", params: { name: id } };
        }
        // Build a shared-setting reference step for a dragged tool key.
        function buildToolDef(key) {
            var tools = window.msMacroTools || [];
            for (var i = 0; i < tools.length; i++) {
                if (tools[i].key === key) {
                    return (window.fnPicker && window.fnPicker.settingDef)
                        ? window.fnPicker.settingDef(tools[i])
                        : { action: "setting", params: { key: tools[i].key, label: tools[i].label || tools[i].key, type: tools[i].type } };
                }
            }
            return null;
        }
        // Build a module def with default params from the shared registry.
        function buildDefaultDef(fnId) {
            var reg = window.fnPicker && window.fnPicker.registry;
            if (!reg) return null;
            var fn = null;
            for (var i = 0; i < reg.length; i++) {
                if (reg[i].id === fnId) { fn = reg[i]; break; }
            }
            if (!fn) return null;
            var params = {};
            (fn.params || []).forEach(function(p) {
                if (p.type === "mods") params[p.name] = [];
                else if (p.type === "number") params[p.name] = 0;
                else if (p.type === "enum") params[p.name] = enumDefault(p);
                else params[p.name] = "";
            });
            return { action: fn.name, params: params };
        }
        // Which existing top-level block should the new one land before? The
        // first whose vertical midpoint is below the cursor; else append.
        function beforeSidAt(clientY) {
            var root = _canvas._root;
            var blocks = root.children;
            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i];
                if (!b.getAttribute) continue;
                var sid = b.getAttribute("data-sid");
                if (!sid) continue;
                var r = b.getBoundingClientRect();
                if (clientY < r.top + r.height / 2) return sid;
            }
            return null;
        }
        canvasContainer.addEventListener("dragenter", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
        }, true);
        canvasContainer.addEventListener("dragover", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            e.dataTransfer.dropEffect = "copy";
            _canvas._root.classList.add("fn-drop-target");
        }, true);
        canvasContainer.addEventListener("dragleave", function(e) {
            if (!hasFn(e)) return;
            // Only clear when the pointer actually leaves the container, not on
            // every crossing between child blocks.
            if (e.target === canvasContainer || !canvasContainer.contains(e.relatedTarget)) {
                _canvas._root.classList.remove("fn-drop-target");
            }
        }, true);
        canvasContainer.addEventListener("drop", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            _canvas._root.classList.remove("fn-drop-target");
            var def = null;
            if (hasType(e, TOOL_MIME)) {
                def = buildToolDef(e.dataTransfer.getData(TOOL_MIME));
            } else if (hasType(e, CALLFN_MIME)) {
                def = buildCallFnDef(e.dataTransfer.getData(CALLFN_MIME));
            } else {
                def = buildDefaultDef(e.dataTransfer.getData(FN_MIME));
            }
            if (!def) return;
            _canvas.insertDefAt(def, beforeSidAt(e.clientY));
            _macroDirty = true;
            updateSaveBtnState();
            if (window.playSlot) playSlot("interact");
            closeFnOverlay();
        }, true);
    })();

    // -- Tool keyboard shortcuts (copy/cut/paste/delete) --
    // Bound on document, gated on the builder being visible and a module selected.
    document.addEventListener("keydown", function(e) {
        if (!builderSection.classList.contains("active")) return;
        var t = e.target;
        if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
        var mod = e.metaKey || e.ctrlKey;
        // Cmd-A selects all top-level blocks. Paste works with nothing selected, everything else needs a selection.
        if (mod && (e.key === "a" || e.key === "A")) {
            e.preventDefault();
            _canvas.selectAll();
            return;
        }
        if (mod && (e.key === "v" || e.key === "V")) {
            e.preventDefault();
            _canvas.pasteAfter();
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (e.key === "Escape" && _canvas.hasSelection()) {
            e.preventDefault();
            _canvas.clearSelection();
            return;
        }
        if (!_canvas.hasSelection()) return;
        if (mod && (e.key === "c" || e.key === "C")) {
            e.preventDefault();
            _canvas.copySelected();
        } else if (mod && (e.key === "x" || e.key === "X")) {
            e.preventDefault();
            _canvas.cutSelected();
            _macroDirty = true;
            updateSaveBtnState();
        } else if (e.key === "Delete" || e.key === "Backspace") {
            e.preventDefault();
            _canvas.removeSelected();
            _macroDirty = true;
            updateSaveBtnState();
        }
    });

    // Inline tool parameter editor
    var _toolEditor = null;
    if (window.ToolEditor) {
        _toolEditor = new ToolEditor({ canvas: _canvas });
    } else {
        console.warn("[macros] ToolEditor not loaded, inline editing disabled");
    }

    /* -- Preload add icon -- */
    _fetchSVG("add").then(function(svg) {
        if (svg) addToolBtn.innerHTML = svg + " Add Module";
    });
    _fetchSVG("close").then(function(svg) {
        if (svg) overlayClose.innerHTML = svg;
    });

    /* -- Fn-picker overlay toggle -- */
    // Closed by default, slid off-screen and marked inert so it leaves the tab order.
    overlay.inert = true;
    function openFnOverlay() {
        overlay.classList.add("open");
        overlay.inert = false;
        // Pull the current tool list every time it opens.
        refreshToolList();
    }
    function closeFnOverlay() {
        overlay.classList.remove("open");
        overlay.inert = true;
    }
    addToolBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    addToolBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        openFnOverlay();
    });

    function refreshToolList() {
        if (window.shellPost) shellPost("macros", "listTools", {});
    }

    /* -- Macro select / management -- */
    function refreshMacroList() {
        // Ask Lua for the list of macros
        if (window.shellPost) {
            shellPost("macros", "listMacros", {});
        }
    }

    /* -- Binds tab -- */
    var _bindList = [];

    function refreshBindList() {
        if (window.shellPost) shellPost("macros", "listBinds", {});
    }

    // Themed delete confirmation -> Promise<boolean>, using the shell modal.
    function confirmDelete(name) {
        var msg = 'Delete "' + name + '"? This cannot be undone.';
        if (typeof window.openModal === "function") {
            return window.openModal("Delete macro", msg, "Delete", "Cancel")
                .then(function(r) { return !!(r && r.confirmed); });
        }
        // ui-lint-allow-native: last-resort fallback if the shell modal is absent.
        var ok = (typeof window.confirm !== "function") || window.confirm(msg);
        return Promise.resolve(ok);
    }

    function bindPill(text, onClick, title) {
        var b = document.createElement("button");
        b.className = "bind-pill" + (text ? "" : " unset");
        b.textContent = text || "Unset";
        if (title) b.title = title;
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            onClick();
        });
        return b;
    }

    // Candidate macros this one can be tethered to: every real, non-system
    // bind except itself and its own descendants (which would loop). The host
    // re-checks for cycles, this just keeps obviously-bad picks out of the menu.
    function linkTargets(m) {
        var exclude = {};
        exclude[m.id] = true;
        (function walk(node) {
            (node.subs || []).forEach(function(s) { exclude[s.id] = true; walk(s); });
        })(m);
        var out = [];
        _bindList.forEach(function(top) {
            function consider(x) {
                if (exclude[x.id]) return;
                if (x.group === "system" || x.systemBind) return;
                out.push({ value: x.id, label: x.label || x.id, group: top.label || top.id });
            }
            consider(top);
            (top.subs || []).forEach(consider);
        });
        return out;
    }


    // Builds the target list for the "Link to another macro" submenu, mapping
    // each candidate to a bindToMacro action. A ✓ marks the current parent.
    function linkMenuItems(m) {
        return linkTargets(m).map(function(o) {
            return {
                icon:  "",
                label: (m.parent === o.value ? "✓ " : "") + o.label,
                action: function() {
                    shellPost("macros", "bindToMacro", {
                        action:   "bindToMacro",
                        id:       m.id,
                        targetId: o.value,
                    });
                },
            };
        });
    }

    // Opens the per-bind "⋯" options menu at (x, y). `mode` is the sub-bind's
    // shared rebind-mode closure so the menu can flip it and the inline chord
    // pill reads the same value on its next click.
    function openBindMenu(m, isSub, mode, x, y) {
        var kit = window.msUI;
        if (!kit || typeof kit.showCtxMenu !== "function") return;
        var items = [];

        // Enable / disable (was the inline toggle). System binds are always live.
        // The host guards the "no bind set" case with its own alert, so we can
        // always post and let it decide.
        if (m.group !== "system" && !m.systemBind) {
            items.push({
                icon:  "",
                label: m.enabled ? "Disable macro" : "Enable macro",
                action: function() {
                    shellPost("macros", "setMacroEnabled", {
                        action: "setMacroEnabled",
                        id:     m.id,
                        value:  !m.enabled,
                    });
                    if (window.playSlot) playSlot(m.enabled ? "toggleOff" : "toggleOn");
                },
            });
        }

        // Reset / clear (was the inline refresh icon). A sub drops its modifier
        // and re-attaches to its parent; everything else resets to its default.
        if (isSub) {
            items.push({
                icon:  "",
                label: "Re-attach to parent",
                action: function() {
                    shellPost("macros", "clearModifier", {
                        action: "clearModifier",
                        id:     m.id,
                    });
                },
            });
        } else {
            items.push({
                icon:  "",
                label: "Reset to default bind",
                action: function() {
                    shellPost("macros", "resetBind", {
                        action:     "resetBind",
                        id:         m.id,
                        systemBind: m.systemBind || false,
                    });
                },
            });
        }

        // Sub-bind rebind mode (was the inline "Mod/Full" toggle). Governs what
        // clicking the chord pill captures: just a modifier, or a full trigger.
        if (isSub) {
            items.push({
                icon:  "",
                label: mode.full ? "Switch to modifier only" : "Switch to full trigger",
                action: function() { mode.full = !mode.full; },
            });
        }

        // Ignore extra modifiers (subset match). Only meaningful for key/combo
        // triggers: device binds already tolerate extras and mods-only binds
        // have no base key.
        if (m.group !== "system" && !m.systemBind
            && (m.bindType === "key" || m.bindType === "combo")) {
            items.push({
                icon:  "",
                label: (m.ignoreMods ? "✓ " : "") + "Ignore extra modifiers",
                action: function() {
                    shellPost("macros", "setBindIgnoreMods", {
                        action: "setBindIgnoreMods",
                        id:     m.id,
                        value:  !m.ignoreMods,
                    });
                },
            });
        }

        // Link this macro to follow another macro's trigger.
        if (m.group !== "system" && !m.systemBind) {
            var targets = linkMenuItems(m);
            if (targets.length) {
                items.push({
                    icon:  "",
                    label: (m.parent ? "Change linked macro…" : "Link to another macro…"),
                    action: function() { kit.showCtxMenu(x, y, targets, m.label || m.id); },
                });
            }
        }

        // Delete. Only user-authored macros can be removed.
        if (m.group !== "system" && !m.systemBind) {
            items.push({
                icon:  "",
                label: "Delete macro",
                danger: true,
                action: function() {
                    confirmDelete(m.label || m.id).then(function(ok) {
                        if (!ok) return;
                        if (window.playSlot) playSlot("back");
                        shellPost("macros", "deleteMacro", { id: m.id });
                        _bindList = _bindList.filter(function(x) { return x.id !== m.id; });
                        renderBindList();
                    });
                },
            });
        }

        if (!items.length) return;
        if (window.playSlot) playSlot("interact");
        kit.showCtxMenu(x, y, items, m.label || m.id);
    }

    function bindRow(m, isSub) {
        var r = document.createElement("div");
        r.className = "bind-row" + (isSub ? " bind-row-sub" : "");
        // Row-level hover, matching the log-panel list rows. mouseenter does not
        // bubble, so moving onto a pill/toggle inside the row fires only that
        // child's hover, no double-trigger.
        r.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });

        var lbl = document.createElement("div");
        lbl.className = "bind-label";
        lbl.textContent = m.label || m.id;
        r.appendChild(lbl);

        var acts = document.createElement("div");
        acts.className = "bind-acts";

        // Inline is just the two the user asked for: the chord pill (click to
        // rebind) and the ⋯ button. Enable/disable, reset, rebind mode, link,
        // ignore-modifiers and delete all live in the ⋯ menu.
        var mode = { full: false };
        acts.appendChild(bindPill(m.bind, function() {
            if (isSub && !mode.full) {
                shellPost("macros", "startModRebind", {
                    action: "startModRebind",
                    id:     m.id,
                });
            } else {
                shellPost("macros", "startRebind", {
                    action:     "startRebind",
                    id:         m.id,
                    systemBind: m.systemBind || false,
                });
            }
        }, isSub
            ? "Click to rebind · capture mode is set in the ⋯ menu"
            : "Click to rebind"));

        // The ⋯ options menu. Rendered for every row — even system binds, whose
        // only option is Reset — so the row layout stays uniform.
        var moreBtn = document.createElement("button");
        moreBtn.className = "bind-act bind-more";
        moreBtn.textContent = "⋯";
        moreBtn.title = "Bind options";
        moreBtn.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        moreBtn.addEventListener("click", function(e) {
            e.preventDefault();
            e.stopPropagation();
            var rect = moreBtn.getBoundingClientRect();
            openBindMenu(m, isSub, mode, rect.right, rect.bottom);
        });
        acts.appendChild(moreBtn);

        r.appendChild(acts);
        return r;
    }

    function renderBindList() {
        bindList.innerHTML = "";

        if (!_bindList.length) {
            var empty = document.createElement("div");
            empty.className = "binds-empty";
            empty.textContent = "No macros registered.";
            bindList.appendChild(empty);
            return;
        }

        // Group in registration order, same grouping the macro list uses.
        var order = [];
        var groups = {};
        _bindList.forEach(function(m) {
            var g = m.group || "ungrouped";
            if (!groups[g]) { groups[g] = []; order.push(g); }
            groups[g].push(m);
        });

        // A group is a settings section: a sticky heading and its binds in a card.
        order.forEach(function(g) {
            var rows = [];
            groups[g].forEach(function(m) {
                rows.push(bindRow(m, false));
                (m.subs || []).forEach(function(sub) {
                    rows.push(bindRow(sub, true));
                });
            });
            var sec = bindSection(
                titleCaseGroup(g),
                g === "system" ? "Always live, these cannot be disabled" : null,
                rows,
            );
            sec.setAttribute("data-bind-group", g);
            bindList.appendChild(sec);
        });
    }

    function focusSystemBinds() {
        if (_mtabs) _mtabs.switch("binds");
        refreshBindList();
        setTimeout(function() {
            var sec = bindList.querySelector('[data-bind-group="system"]');
            if (sec && sec.scrollIntoView) sec.scrollIntoView({ block: "start" });
        }, 90);
    }

    // Title-case each word of a group key so compound groups read cleanly:
    // "visual - main" -> "Visual - Main", "system" -> "System".
    function titleCaseGroup(g) {
        return String(g).replace(/[A-Za-z]+/g, function(w) {
            return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
        });
    }

    // Same markup as msUI.section(), built from a row array.
    function bindSection(title, desc, rows) {
        var wrap = document.createElement("div");
        wrap.className = "section";
        var head = document.createElement("div");
        head.className = "section-head";
        var t = document.createElement("span");
        t.className = "section-title";
        t.textContent = title;
        head.appendChild(t);
        if (desc) {
            var d = document.createElement("span");
            d.className = "section-desc";
            d.textContent = desc;
            head.appendChild(d);
        }
        var body = document.createElement("div");
        body.className = "section-body";
        rows.forEach(function(r) { body.appendChild(r); });
        wrap.appendChild(head);
        wrap.appendChild(body);
        return wrap;
    }

    function setBindList(list) {
        _bindList = Array.isArray(list) ? list : [];
        renderBindList();
        updateBindBtn();
    }

    function setMacroList(ids) {
        // Real macro ids only, the "Select" placeholder lives on the button,
        // not as a menu row, and an empty list renders as "None".
        var opts = [];
        for (var i = 0; i < ids.length; i++) {
            opts.push({ value: ids[i], label: ids[i] });
        }
        macroSelect.setOptions(opts);

        if (_currentMacroId) {
            macroSelect.value = _currentMacroId;
        }
    }

    function loadMacro(macroId) {
        if (!macroId) {
            _currentMacroId = null;
            _currentMacroDef = null;
            _canvas.load([]);
            nameInput.value = "";
            setMacroClass("main");
            _currentMacroCooldown = null;
            cooldownInput.value = "";
            _currentMacroShared = "";
            sharedInput.value = "";
            _macroDirty = false;
            updateSaveBtnState();
            updateBindBtn();
            return;
        }
        // Ask Lua for the macro definition
        if (window.shellPost) {
            shellPost("macros", "getMacro", { id: macroId });
        }
    }

    function setMacroDef(def) {
        _currentMacroId = def.id;
        _currentMacroDef = def;
        nameInput.value = def.name || def.id || "";
        _canvas.load(def.steps || []);
        setMacroClass(classFromGroup(def.group));
        _currentMacroCooldown = def.cooldown != null ? def.cooldown : null;
        cooldownInput.value = _currentMacroCooldown != null ? String(_currentMacroCooldown) : "";
        _currentMacroShared = def.shared || "";
        sharedInput.value = _currentMacroShared;
        _macroDirty = false;
        updateSaveBtnState();
        macroSelect.value = def.id;
        updateBindBtn();
    }

    // Show the macro's effective bind, preferring the live value from the
    // binds tab (which reflects user overrides) over the compiled default.
    function updateBindBtn() {
        var text = "";
        for (var i = 0; i < _bindList.length; i++) {
            if (_bindList[i].id === _currentMacroId) { text = _bindList[i].bind || ""; break; }
        }
        if (!text && _currentMacroDef && _currentMacroDef.bind) {
            var b = _currentMacroDef.bind;
            if (b.type === "mouse") text = "Mouse " + b.button;
            else if (b.type === "mods") text = (b.mods || []).join("+");
            else if (b.key) text = (b.mods || []).concat([b.key]).join("+");
        }
        bindBtn.textContent = text || "Unset";
        bindBtn.className = "bind-pill" + (text ? "" : " unset");
    }

    bindBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    bindBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        // Capture targets a registered bind id, which only exists once the
        // macro has been compiled, so it must be saved first.
        if (!_currentMacroId || _macroDirty) {
            showTestToast("Save the macro before binding it", "error");
            return;
        }
        shellPost("macros", "startRebind", {
            action: "startRebind",
            id:     _currentMacroId,
        });
    });

    function saveMacro() {
        if (!_currentMacroId) {
            // Create new
            var name = nameInput.value.trim();
            if (!name) {
                nameInput.focus();
                return;
            }
            _currentMacroId = name.replace(/[^a-zA-Z0-9_]/g, "_");
        }

        var name = nameInput.value.trim() || _currentMacroId;
        var def = {
            id: _currentMacroId,
            name: name,
            author: "User",
            // Group the compiled bind under VISUAL - MAIN / VISUAL - OPTIONAL
            // per the toolbar Class control.
            group: "visual - " + _currentMacroClass,
            steps: _canvas.serialize()
        };
        // Carry the compiled default bind through a save, the compiler reads
        // macroDef.bind, so dropping it here would silently unbind the macro.
        if (_currentMacroDef && _currentMacroDef.bind) {
            def.bind = _currentMacroDef.bind;
        }
        if (_currentMacroCooldown != null) {
            def.cooldown = _currentMacroCooldown;
        }
        if (_currentMacroShared) {
            def.shared = _currentMacroShared;
        }
        _currentMacroDef = def;

        if (window.shellPost) {
            shellPost("macros", "saveMacro", { id: _currentMacroId, def: def });
        }
        // Do NOT optimistically mark clean here. The host acks with either
        // "macroSaved" (clears dirty) or "saveError" (keeps it dirty and shows
        // the compile error). Clearing now would strand the builder looking
        // "saved" while the macro actually failed to compile.
        updateSaveBtnState();
    }

    function deleteMacro() {
        if (!_currentMacroId) return;
        if (window.shellPost) {
            shellPost("macros", "deleteMacro", { id: _currentMacroId });
        }
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        setMacroClass("main");
        _currentMacroCooldown = null;
        cooldownInput.value = "";
        _currentMacroShared = "";
        sharedInput.value = "";
        _macroDirty = false;
        updateSaveBtnState();
        refreshMacroList();
    }

    function updateSaveBtnState() {
        saveBtn.style.opacity = _macroDirty ? "1" : "0.5";
    }

    /* -- Wire toolbar buttons -- */
    newBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    newBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        nameInput.focus();
        setMacroClass("main");
        _currentMacroCooldown = null;
        cooldownInput.value = "";
        _currentMacroShared = "";
        sharedInput.value = "";
        _macroDirty = false;
        updateSaveBtnState();
        macroSelect.value = "";
        updateBindBtn();
    });

    saveBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    saveBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        saveMacro();
    });

    editFileBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editFileBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        // The action router keys on body.action, so include it.
        if (window.shellPost) shellPost("macros", "editMacros", { action: "editMacros" });
    });

    editorBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editorBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) shellPost("macros", "chooseMacroEditor", { action: "chooseMacroEditor" });
    });

    /* -- Test Run -- */
    var _testRunning = false;
    var _testToastTimer = null;

    function showTestToast(msg, type, iconName) {
        // Icon path builds via DOM so msg stays inert text (some callers pass
        // interpolated error strings) while the leading glyph becomes real SVG.
        if (iconName && window.icon) {
            testToast.innerHTML = window.icon(iconName);
            testToast.appendChild(document.createTextNode(" " + msg));
        } else {
            testToast.textContent = msg;
        }
        testToast.className = "macro-test-toast show"
            + (type === "error" ? " error-toast" : "")
            + (type === "success" ? " success-toast" : "");
        if (_testToastTimer) clearTimeout(_testToastTimer);
        _testToastTimer = setTimeout(function() {
            testToast.className = "macro-test-toast";
            _testToastTimer = null;
        }, type === "error" ? 5000 : 2500);
    }

    function _resetTestBtn() {
        testBtn.className = "macro-toolbar-btn";
        testBtn.innerHTML = menuLabel("play", "Test");
        testBtn.disabled = false;
        _testRunning = false;
    }

    testBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    testBtn.addEventListener("click", function() {
        if (_testRunning) return;
        var steps = _canvas.serialize();
        if (!steps || steps.length === 0) {
            if (window.playSlot) playSlot("back");
            showTestToast("No steps to run", "error");
            return;
        }
        if (window.playSlot) playSlot("interact");

        // Build macro def for test run
        var macroId = _currentMacroId || ("_test_" + Date.now().toString(36));
        var macroDef = {
            id: macroId,
            name: nameInput.value.trim() || macroId,
            steps: steps,
        };

        // Set running state
        _testRunning = true;
        testBtn.className = "macro-toolbar-btn running";
        testBtn.innerHTML = menuLabel("timer", "Running\u2026");
        testBtn.disabled = true;

        // Send to Lua
        if (window.shellPost) {
            shellPost("macros", "testRun", macroDef);
        }

        // Safety timeout, reset after 30s if no response
        setTimeout(function() {
            if (_testRunning) {
                _resetTestBtn();
                showTestToast("Test run timed out", "error");
            }
        }, 30000);
    });

    /* -- Record Mode -- */
    var _isRecording = false;

    // Recording options, persisted so a chosen style survives a reload.
    var _REC_OPTS_KEY = "ms.macroRecordOpts";
    var _recOptDefaults = {
        recordDelays:       true,   // emit ms.wait for idle gaps
        pressMode:          "type", // "type" | "press" | "pressRelease"
        recordDrags:        true,   // capture mouse drags as Drag ops
        dragGranularity:    5,      // 1 (coarse) ... 10 (near 1:1) path fidelity
        recordMouseMoves:   false,  // capture free cursor motion as moveMouse steps
        moveGranularity:    5,      // 1 (coarse) ... 10 (near 1:1) move-path fidelity
        recordMouseButtons: true,   // capture mouse-button clicks
        recordWindowMove:   false,  // capture focused-window moves
        recordWindowResize: false,  // capture focused-window resizes
        waitThreshold:      50      // ms, gaps shorter than this are noise
    };
    var _recOpts = (function() {
        var o = {};
        for (var k in _recOptDefaults) o[k] = _recOptDefaults[k];
        try {
            var saved = JSON.parse(localStorage.getItem(_REC_OPTS_KEY) || "{}");
            for (var k2 in saved) if (k2 in o) o[k2] = saved[k2];
            // Fold any stored down-only value into the press+release mode.
            if (o.pressMode === "press") o.pressMode = "pressRelease";
        } catch (e) { /* corrupt/absent, fall back to defaults */ }
        return o;
    })();
    function _saveRecOpts() {
        try { localStorage.setItem(_REC_OPTS_KEY, JSON.stringify(_recOpts)); }
        catch (e) { /* private mode / quota, options just won't persist */ }
    }

    function _setRecordingState(on) {
        _isRecording = on;
        if (on) {
            recordBtn.className = "macro-toolbar-btn recording";
            recordBtn.innerHTML = menuLabel("stop", "Stop");
            recordBtn.title = "Stop recording";
            showTestToast("Recording, perform actions, then click Stop\u2026", null, "record");
        } else {
            recordBtn.className = "macro-toolbar-btn";
            recordBtn.innerHTML = menuLabel("record", "Record");
            recordBtn.title = "Record user actions into tools";
        }
    }

    recordBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recordBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (!_isRecording) {
            // Start recording, carry the current options through so the Lua
            // recorder captures exactly what the user asked for.
            if (window.shellPost) {
                shellPost("macros", "startRecording", {
                    waitThreshold: _recOpts.waitThreshold,
                    options: _recOpts
                });
            }
            _setRecordingState(true);
        } else {
            // Stop recording
            if (window.shellPost) {
                shellPost("macros", "stopRecording", {});
            }
            _setRecordingState(false);
            showTestToast("Recording stopped", "success");
        }
    });

    /* -- Recording settings menu --
       A small modal in the same visual language as the rebind / warning
       prompts: an accent-topped card over a dimmed backdrop. Built lazily
       on first open, then reused. */
    var _recModal = null;

    function _buildRecModal() {
        var overlayEl = document.createElement("div");
        overlayEl.className = "rec-settings-overlay";
        overlayEl.style.cssText =
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;" +
            "align-items:center;justify-content:center;z-index:320;opacity:0;" +
            "pointer-events:none;transition:opacity 0.2s;";

        var card = document.createElement("div");
        card.style.cssText =
            "background:var(--surface);border-top:2px solid var(--accent);" +
            "border-radius:var(--radius);padding:18px 20px;width:340px;" +
            "max-height:82vh;overflow-y:auto;box-shadow:0 16px 48px rgba(0,0,0,0.7)," +
            "0 0 0 1px var(--border);transform:scale(0.96);transition:transform 0.2s;";
        overlayEl.appendChild(card);

        var title = document.createElement("div");
        title.style.cssText = "font-size:14px;font-weight:700;margin-bottom:2px;";
        title.textContent = "Recording Settings";
        card.appendChild(title);

        var sub = document.createElement("div");
        sub.style.cssText = "font-size:11px;color:var(--text2);margin-bottom:14px;line-height:1.5;";
        sub.textContent = "Choose what a recording captures. Applied to the next recording you start.";
        card.appendChild(sub);

        // Row scaffold shared by toggle + segmented rows.
        function row(label, hint, control) {
            var r = document.createElement("div");
            r.style.cssText =
                "display:flex;align-items:center;justify-content:space-between;" +
                "gap:12px;padding:9px 0;border-bottom:1px solid var(--border-dim,var(--border));";
            var lwrap = document.createElement("div");
            lwrap.style.cssText = "min-width:0;flex:1;";
            var l = document.createElement("div");
            l.style.cssText = "font-size:12px;color:var(--text);";
            l.textContent = label;
            lwrap.appendChild(l);
            if (hint) {
                var h = document.createElement("div");
                h.style.cssText = "font-size:10px;color:var(--text3);margin-top:2px;line-height:1.4;";
                h.textContent = hint;
                lwrap.appendChild(h);
            }
            r.appendChild(lwrap);
            r.appendChild(control);
            card.appendChild(r);
            return r;
        }

        function toggle(key) {
            var wrap = document.createElement("label");
            wrap.className = "toggle";
            var input = document.createElement("input");
            input.type = "checkbox";
            input.checked = !!_recOpts[key];
            var track = document.createElement("span"); track.className = "toggle-track";
            var thumb = document.createElement("span"); thumb.className = "toggle-thumb";
            wrap.appendChild(input); wrap.appendChild(track); wrap.appendChild(thumb);
            input.addEventListener("change", function() {
                _recOpts[key] = input.checked;
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            return wrap;
        }

        // Integer slider for drag fidelity (RDP retention steps).
        function slider(key, min, max) {
            var wrap = document.createElement("div");
            wrap.style.cssText = "display:flex;align-items:center;gap:10px;";
            var input = document.createElement("input");
            input.type = "range";
            input.min = String(min); input.max = String(max); input.step = "1";
            input.value = String(_recOpts[key] != null ? _recOpts[key] : min);
            input.style.cssText = "flex:1;min-width:110px;accent-color:var(--accent);";
            var val = document.createElement("span");
            val.style.cssText = "font-size:12px;color:var(--text2);min-width:20px;text-align:right;font-variant-numeric:tabular-nums;";
            val.textContent = input.value;
            input.addEventListener("input", function() {
                val.textContent = input.value;
            });
            input.addEventListener("change", function() {
                _recOpts[key] = parseInt(input.value, 10);
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            wrap.appendChild(input);
            wrap.appendChild(val);
            return wrap;
        }

        function seg(key, opts) {
            var s = document.createElement("div");
            s.className = "seg";
            opts.forEach(function(o) {
                var b = document.createElement("button");
                b.className = "seg-btn" + (_recOpts[key] === o.value ? " active" : "");
                b.textContent = o.label;
                b.title = o.hint || "";
                b.addEventListener("click", function() {
                    _recOpts[key] = o.value;
                    _saveRecOpts();
                    if (window.playSlot) playSlot("interact");
                    Array.prototype.forEach.call(s.children, function(c) {
                        c.classList.remove("active");
                    });
                    b.classList.add("active");
                });
                b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
                s.appendChild(b);
            });
            return s;
        }

        row("Record delays", "Insert wait modules for idle gaps between actions.", toggle("recordDelays"));
        row("Key presses", "How keystrokes are captured.",
            seg("pressMode", [
                { value: "type",         label: "Type",    hint: "Full press+release keystroke (ms.type)" },
                { value: "pressRelease", label: "Press",   hint: "Separate press and release with real hold timing" }
            ]));
        row("Record mouse buttons", "Capture left/right/middle clicks.", toggle("recordMouseButtons"));
        row("Record mouse drags", "Capture press-move-release as a drag gesture.", toggle("recordDrags"));
        row("Drag fidelity", "How closely a recorded drag follows your real path. Lower is coarser; higher tracks curves near 1:1. The whole gesture stays one module either way.", slider("dragGranularity", 1, 10));
        row("Record mouse movement", "Capture free cursor motion (no button held) as moveMouse steps.", toggle("recordMouseMoves"));
        row("Movement fidelity", "How closely recorded movement follows your real path. Lower is coarser, higher tracks curves near 1:1.", slider("moveGranularity", 1, 10));
        row("Record window moves", "Capture moving the focused window.", toggle("recordWindowMove"));
        var lastRow =
        row("Record window resizes", "Capture resizing the focused window.", toggle("recordWindowResize"));
        lastRow.style.borderBottom = "none";

        // Buttons
        var btns = document.createElement("div");
        btns.className = "modal-btns";
        btns.style.cssText = "display:flex;gap:8px;margin-top:16px;";
        var resetBtn = document.createElement("button");
        resetBtn.textContent = "Reset";
        resetBtn.style.cssText = "flex:0 0 auto;padding:8px 12px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--surface2);color:var(--text2);";
        var doneBtn = document.createElement("button");
        doneBtn.className = "primary";
        doneBtn.textContent = "Done";
        doneBtn.style.cssText = "flex:1;padding:8px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--accent);color:var(--bg);";
        btns.appendChild(resetBtn);
        btns.appendChild(doneBtn);
        card.appendChild(btns);

        function close() {
            overlayEl.style.opacity = "0";
            overlayEl.style.pointerEvents = "none";
            card.style.transform = "scale(0.96)";
        }
        resetBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        resetBtn.addEventListener("click", function() {
            for (var k in _recOptDefaults) _recOpts[k] = _recOptDefaults[k];
            _saveRecOpts();
            if (window.playSlot) playSlot("back");
            // Rebuild reflects the reset values cleanly.
            _recModal = null;
            card.remove(); overlayEl.remove();
            _openRecModal();
        });
        doneBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        doneBtn.addEventListener("click", function() { if (window.playSlot) playSlot("interact"); close(); });
        overlayEl.addEventListener("click", function(e) {
            if (e.target === overlayEl) { if (window.playSlot) playSlot("back"); close(); }
        });

        document.body.appendChild(overlayEl);
        _recModal = { overlay: overlayEl, card: card };
        return _recModal;
    }

    function _openRecModal() {
        var m = _recModal || _buildRecModal();
        // Force reflow so the opening transition runs from the closed state.
        m.overlay.getBoundingClientRect();
        m.overlay.style.opacity = "1";
        m.overlay.style.pointerEvents = "all";
        m.card.style.transform = "scale(1)";
    }

    recSettingsBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recSettingsBtn.addEventListener("click", function() {
        // Let the click bubble so the overflow menu closes behind the modal.
        if (window.playSlot) playSlot("interact");
        _openRecModal();
    });

    delMacroBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    delMacroBtn.addEventListener("click", function() {
        if (_currentMacroId) {
            if (window.playSlot) playSlot("back");
            deleteMacro();
        }
    });

    macroSelect.addEventListener("change", function() {
        var id = macroSelect.value;
        loadMacro(id);
    });

    nameInput.addEventListener("keydown", function(e) { e.stopPropagation(); });
    nameInput.addEventListener("input", function() {
        _macroDirty = true;
        updateSaveBtnState();
    });

    /* -- Panel handler (consolidated Lua -> JS dispatch) -- */
    var _libSelfHealed = false;
    window.registerPanel("macros", function(action, body) {
        // The Installed Macro Packs list is filled by a request() fired during
        // eager panel build, which can beat the host's library subscription and
        // be dropped, leaving the shelf empty until a reload. The first host
        // push to this panel proves the bridge is live, so re-request once then
        // — a boot-race self-heal that does not depend on the early request or
        // the host's own ready-time re-push landing.
        if (!_libSelfHealed && window.msLibraryClient) {
            _libSelfHealed = true;
            window.msLibraryClient.request("macro");
        }
        // Function picker messages
        if (window.fnPicker && window.fnPicker.handler) {
            window.fnPicker.handler(action, body);
        }
        // Tool-canvas messages
        if (action === "addTool" && body) {
            _canvas.addTool(body);
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (action === "macroList" && Array.isArray(body)) {
            setMacroList(body);
            return;
        }
        if (action === "macroDef" && body) {
            setMacroDef(body);
            return;
        }
        if (action === "macroSaved") {
            _macroDirty = false;
            updateSaveBtnState();
            refreshMacroList();
            // A saved macro may have gained or changed its bind.
            refreshBindList();
            return;
        }
        if (action === "saveError") {
            // The JSON store was written, but the macro failed to compile and
            // was quarantined host-side. Keep the editor dirty and selected so
            // the user can fix and re-save, and surface the compile error the
            // same way Test does — it's no longer the only signal.
            _macroDirty = true;
            updateSaveBtnState();
            // Binds/list still refresh: the macro survives (quarantined) so it
            // stays listed and keeps its bind instead of vanishing.
            refreshMacroList();
            refreshBindList();
            showTestToast("\u2717 Save failed to compile: "
                + ((body && body.err) || "Unknown error"), "error");
            return;
        }
        if (action === "bindList" && Array.isArray(body)) {
            setBindList(body);
            return;
        }
        if (action === "packMeta" && body) {
            setMeta(body);
            return;
        }
        if (action === "setToolList" && Array.isArray(body)) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(body);
            }
            return;
        }
        if (action === "testRunResult" && body) {
            _resetTestBtn();
            if (body.ok) {
                testBtn.className = "macro-toolbar-btn success";
                showTestToast("\u2713 Macro ran successfully", "success");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 2500);
            } else {
                testBtn.className = "macro-toolbar-btn error";
                showTestToast("\u2717 " + (body.err || "Unknown error"), "error");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 5000);
            }
            return;
        }
        if (action === "recordStep" && body) {
            _canvas.addTool({ action: body.action, params: body.params });
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
    });

    /* -- External API -- */
    window.macroLab = {
        canvas: _canvas,
        editor: _toolEditor,
        loadMacro: loadMacro,
        saveMacro: saveMacro,
        refreshList: refreshMacroList,
        setMacroList: setMacroList,
        setMacroDef: setMacroDef,
        setBindList: setBindList,
        refreshBinds: refreshBindList,
        focusSystemBinds: focusSystemBinds,
        setMeta: setMeta,
        refreshMeta: refreshMeta,
        addTool: function(def) { _canvas.addTool(def); closeFnOverlay(); },
        // Tools list is pushed from Lua, create/delete round-trip through the host.
        setToolList: function(list) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(list);
            }
            // The Tools panel's Variable tab renders from the same list.
            if (typeof window.renderToolVariablesTab === "function") {
                window.renderToolVariablesTab();
            }
        },
        // Function tools (authored on the step canvas in the Tools panel).
        // Stored globally so both the "Call function" picker block and the
        // Tools panel's Function tab read one source.
        setFunctionList: function(list) {
            window.msMacroFunctions = Array.isArray(list) ? list : [];
            // Surface them in the builder's picker (Functions group) too, not
            // just the Tools panel's Function tab.
            if (window.fnPicker && window.fnPicker.setFunctionList) {
                window.fnPicker.setFunctionList(window.msMacroFunctions);
            }
            if (typeof window.renderToolFunctionsTab === "function") {
                window.renderToolFunctionsTab();
            }
        },
        createTool: function(def) {
            if (!window.shellPost) return;
            shellPost("macros", "addUserSetting", { action: "addUserSetting", def: def });
            // The host has no create-ack, so re-pull the list shortly after so
            // the new tool appears in the picker.
            setTimeout(refreshToolList, 250);
        },
        deleteTool: function(key) {
            if (!window.shellPost) return;
            shellPost("macros", "removeUserSetting", { action: "removeUserSetting", key: key });
            setTimeout(refreshToolList, 250);
        },
        // Test Run & Record Mode
        testRun: function() { testBtn.click(); },
        startRecording: function() { if (!_isRecording) recordBtn.click(); },
        stopRecording: function() { if (_isRecording) recordBtn.click(); },
        isRecording: function() { return _isRecording; },
    };

    /* -- Close panel (called by header pop-out button) -- */
    window.closePanel = function() {
        if (window.shellPost) shellPost("macros", "close", {});
    };

    /* -- Macro-engine (bind validity) header toggle -- */
    // Mirrors the enable/disable hotkey: flips BindValidity via the same
    // setMacros host action the Settings master switch uses. The lit state is
    // driven only by the real macrosEnabled the host reports, so it stays
    // correct when the state is changed elsewhere — the hotkey, the Settings
    // toggle, or target focus/blur — not just by this button.
    window._macrosEnabled = window._macrosEnabled || false;
    window.updateMacrosToggleBtn = function(enabled) {
        window._macrosEnabled = !!enabled;
        var btn = document.getElementById("macrosEnabledToggle");
        if (!btn) return;
        btn.classList.toggle("active", !!enabled);
        btn.textContent = enabled ? "On" : "Off";
    };
    window.toggleMacrosEnabled = function() {
        if (window.shellPost) {
            shellPost("settings", "setMacros", {
                action: "setMacros",
                value: window._macrosEnabled ? 0 : 1,
            });
        }
    };

    /* -- Initial state -- */
    updateSaveBtnState();
    refreshMacroList();
    refreshBindList();
    refreshMeta();

    /* -- Header drag -- */
    (function() {
        let _drag = null;
        const panel = document.querySelector(".panel-macros");
        if (!panel) return;
        const header = panel.querySelector("#header");
        if (!header) return;
        header.style.cursor = "-webkit-grab";
        header.addEventListener("mousedown", (e) => {
            if (e.button !== 0) return;
            if (e.target.closest(".header-btns")) return;
            _drag = { ox: e.screenX, oy: e.screenY };
            const onMove = (ev) => {
                if (!_drag) return;
                if (window.shellPost) {
                    shellPost("macros", "move", {
                        dx: ev.screenX - _drag.ox,
                        dy: ev.screenY - _drag.oy,
                    });
                }
                _drag.ox = ev.screenX;
                _drag.oy = ev.screenY;
            };
            const onUp = () => {
                _drag = null;
                window.removeEventListener("mousemove", onMove);
                window.removeEventListener("mouseup", onUp);
            };
            window.addEventListener("mousemove", onMove);
            window.addEventListener("mouseup", onUp);
        });
    })();

    })();


    })();

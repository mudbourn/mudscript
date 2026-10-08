-- core/bind_system (Bind System & Settings Panel) --
    return function(ms)
        ms.bind.define = function(id, a, b)
            assert(type(id) == "string", "ms.bind.define: id must be a string")
            local fn   = type(a) == "function" and a or (type(b) == "function" and b or nil)
            local opts = type(a) == "table"    and a or (type(b) == "table"    and b or {})
            if opts.sub or opts.mod then
                error("bind '" .. id .. "' uses deprecated sub/mod syntax. "
                    .. "Update to: default = { type = \"<parentID>\", mods = {\"<mod>\"} }. "
                    .. "See documentation for the unified bind model.", 2)
            end
            local label, group
            if opts.default and type(opts.default) == "table" and opts.default.type
                and ms.registry._defs[opts.default.type] then
                label = opts.label or id
                group = opts.group
            else
                if opts.label then
                    label = opts.label
                else
                    ms.bind._autoCount = ms.bind._autoCount + 1
                    label = "Macro" .. ms.bind._autoCount
                end
                group = opts.group or "main"
            end
            ms.registry._defs[id] = {
                label    = label,
                group    = group,
                enabled  = (opts.enabled ~= false),
                cooldown = opts.cooldown or 1000,
                shared   = opts.shared,
                info     = opts.info,
                default  = opts.default,
                system   = opts.system or false,
            }
            table.insert(ms.registry._defList, id)
            if fn ~= nil then
                assert(type(fn) == "function",
                    "ms.bind.define: fn must be a function for id '" .. id .. "'")
                ms.bind._wires[id] = fn
            end
        end

        ms.bind._registerSystemBinds = function()
            ms.bind.define("__panicButton", nil, {
                label      = "Panic Button / Stop All",
                group      = "system",
                enabled    = true,
                system     = true,
                default    = {
                    type = "key",
                    mods = {"alt"},
                    key = "F10",
                },
            })
            ms.bind.define("__quickReload", nil, {
                label      = "Quick Reload",
                group      = "system",
                enabled    = true,
                system     = true,
                default    = {
                    type = "key",
                    mods = {"alt"},
                    key = "[",
                },
            })
            ms.bind.define("__fullReload", nil, {
                label      = "Full Reload",
                group      = "system",
                enabled    = true,
                system     = true,
                default    = {
                    type = "key",
                    mods = {"alt"},
                    key = "]",
                },
            })
            ms.bind.define("__openMenu", nil, {
                label      = "Open Menu",
                group      = "system",
                enabled    = true,
                system     = true,
                default    = {
                    type = "key",
                    mods = {"alt"},
                    key = "p",
                },
            })
        end

        local function modsMatch(bindMods, eventMods)
            if bindMods == "any" then
                return true
            end
            return ms.util.modsEqual(bindMods, eventMods)
        end

        ms.systemBinds._defs = {
            enable  = {
                label = "Enable Macros",
                default = {
                    type = "key",
                    mods = "any",
                    key = "return",
                },
            },
            disable = {
                label = "Disable Macros",
                default = {
                    type = "key",
                    mods = "any",
                    key = "/",
                },
            },
            toggle  = {
                label = "Toggle Macros",
                default = {
                    type = "key",
                    mods = "any",
                    key = "escape",
                },
            },
            octane  = {
                label = "Toggle Octane Mode",
                default = {
                    type = "key",
                    mods = {"alt"},
                    key = "o",
                },
            },
            zoomIn  = {
                label = "Zoom UI In",
                ungated = true,
                default = {
                    type = "key",
                    mods = {"alt"},
                    key = "=",
                },
            },
            zoomOut = {
                label = "Zoom UI Out",
                ungated = true,
                default = {
                    type = "key",
                    mods = {"alt"},
                    key = "-",
                },
            },
            zoomReset = {
                label = "Reset UI Zoom",
                ungated = true,
                default = {
                    type = "key",
                    mods = {"alt"},
                    key = "0",
                },
            },
        }

        local function _applyUiZoom(target)
            if ms.shell and ms.shell.applyZoom then
                ms.shell.applyZoom(target)
            else
                ms._uiZoom = math.max(0.5, math.min(2.0, target))
            end
            if ms.saveSettings then ms.saveSettings() end
            if ms.ui and ms.ui.refresh then ms.ui.refresh() end
        end

        ms.systemBinds._actions = {
            enable  = function() ms.setMacros(1) end,
            disable = function() ms.setMacros(0) end,
            toggle  = function() ms.setMacros(BindValidity == 1 and 0 or 1) end,
            octane  = function() ms.octane.toggle() end,
            zoomIn    = function() _applyUiZoom((ms._uiZoom or 1.0) + 0.1) end,
            zoomOut   = function() _applyUiZoom((ms._uiZoom or 1.0) - 0.1) end,
            zoomReset = function() _applyUiZoom(1.0) end,
        }

        ms.systemBinds.effective = function(id)
            return ms.systemBinds._config[id]
                or (ms.systemBinds._defs[id] and ms.systemBinds._defs[id].default)
        end

        ms.systemBinds.bindStr = function(id)
            local c = ms.systemBinds.effective(id)
            if not c then return "( unset )" end
            if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
            if c.type == "scroll" then
                local d = c.direction or "?"
                return "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
            end
            if c.type == "gamepad" then return "Pad " .. ms.gpLabel(c) end
            -- c.mods may be the "any" string sentinel, not a list
            local parts = {}
            if type(c.mods) == "table" then
                for _, m in ipairs(c.mods) do table.insert(parts, m:sub(1, 1):upper() .. m:sub(2)) end
            elseif c.mods == "any" then
                table.insert(parts, "Any")
            end
            table.insert(parts, (c.key or ""):upper())
            return table.concat(parts, "+")
        end

        ms.systemBinds.rebind = function()
            for _, h in pairs(ms.systemBinds._handles) do
                if h and h.delete then h:delete() end
            end
            ms.systemBinds._handles = {}

            for id, action in pairs(ms.systemBinds._actions) do
                local c = ms.systemBinds.effective(id)
                if not c then goto sysBindContinue end
                local ungated = ms.systemBinds._defs[id] and ms.systemBinds._defs[id].ungated
                local function fire()
                    if not ungated and not ms._targetActive and not ms._isSafeZone() then return end
                    if c.type == "key" and not ungated and not ms._targetActive and ms._ownUiFocused() then return end
                    local co = coroutine.create(action)
                    local ok, err = coroutine.resume(co)
                    if not ok then print("ms.systemBind error: " .. tostring(err)) end
                end
                if c.type == "key" then
                    ms.systemBinds._handles[id] = ms.key(c.mods, c.key, false, function()
                        hs.timer.doAfter(0, fire)
                    end, nil, true)
                elseif c.type == "mouse" then
                    ms.systemBinds._handles[id] = ms.mouse(c.button, false, fire, true)
                elseif c.type == "scroll" then
                    ms.systemBinds._handles[id] = ms.scrollBind(c.direction, fire)
                elseif c.type == "gamepad" then
                    ms.systemBinds._handles[id] = ms.gamepadBind(ms.gpButtons(c), fire)
                end
                ::sysBindContinue::
            end
        end

        ms.bind.group = function(id)
            local def = ms.registry._defs[id]
            if not def then return "G_" .. tostring(id) end
            if def.shared then return def.shared end
            local current, seen = id, {}
            while true do
                local d = ms.registry._defs[current]
                if not d or not d.default or type(d.default) ~= "table"
                    or not d.default.type or not ms.registry._defs[d.default.type]
                    or seen[current] then break end
                seen[current] = true
                current = d.default.type
            end
            local rootDef = ms.registry._defs[current]
            if rootDef and rootDef.shared then return rootDef.shared end
            return "G_" .. current
        end

        ms.done = function(id)
            local group = ms.bind.group(id)
            local timer = ms.running[group]
            if timer then
                timer:stop()
                ms.running[group] = nil
            end
        end

        ms.fn.define("ms.press", ms.press, {
            label  = "Press Key",
            group  = "input",
            info   = "Press and release a key",
            params = {
                {
                    name = "key",
                    type = "string",
                },
                {
                    name = "mods",
                    type = "table",
                },
            },
            icon   = "inputs",
        })
        ms.fn.define("ms.release", ms.release, {
            label  = "Release Key",
            group  = "input",
            info   = "Release a held key",
            params = {
                {
                    name = "key",
                    type = "string",
                },
                {
                    name = "mods",
                    type = "table",
                },
            },
            icon   = "inputs",
        })
        ms.fn.define("ms.type", ms.type, {
            label  = "Type Key",
            group  = "input",
            info   = "Type a key with modifiers and optional hold duration",
            params = {
                {
                    name = "key",
                    type = "string",
                },
                {
                    name = "mods",
                    type = "table",
                },
                {
                    name = "holdMs",
                    type = "number",
                },
            },
            icon   = "inputs",
        })
        ms.fn.define("ms.toggle", ms.toggle, {
            label  = "Toggle Key",
            group  = "input",
            info   = "Toggle a key on/off",
            params = {
                {
                    name = "key",
                    type = "string",
                },
                {
                    name = "mods",
                    type = "table",
                },
            },
            icon   = "inputs",
        })
        ms.fn.define("ms.multiPress", ms.multiPress, {
            label  = "Multi Press",
            group  = "input",
            info   = "Press multiple keys in sequence",
            params = {
                {
                    name = "keys",
                    type = "table",
                },
                {
                    name = "delayMs",
                    type = "number",
                },
                {
                    name = "mods",
                    type = "table",
                },
            },
            icon   = "inputs",
        })
        ms.fn.define("ms.Mouse", ms.Mouse, {
            label  = "Mouse",
            group  = "mouse",
            info   = "Full mouse control (Click, Drag, Move, etc.)",
            params = {
                {
                    name = "operation",
                    type = "string",
                },
                {
                    name = "button",
                    type = "string",
                },
                {
                    name = "reference",
                    type = "string",
                },
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
            },
            icon   = "move",
        })
        ms.fn.define("ms.scroll", ms.scroll, {
            label  = "Scroll",
            group  = "mouse",
            info   = "Scroll the mouse wheel",
            params = {
                {
                    name = "direction",
                    type = "string",
                },
                {
                    name = "clicks",
                    type = "number",
                },
            },
            icon   = "scroll",
        })
        ms.fn.define("ms.moveMouse", ms.moveMouse, {
            label  = "Move Mouse",
            group  = "mouse",
            info   = "Move mouse to position with optional duration",
            params = {
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
                {
                    name = "ref",
                    type = "string",
                },
                {
                    name = "durationMs",
                    type = "number",
                },
            },
            icon   = "move",
        })
        ms.fn.define("ms.dragPath", ms.dragPath, {
            label  = "Drag Path",
            group  = "mouse",
            info   = "Drag mouse through a series of points",
            params = {
                {
                    name = "points",
                    type = "string",
                },
                {
                    name = "button",
                    type = "string",
                },
                {
                    name = "ref",
                    type = "string",
                },
                {
                    name = "delayMs",
                    type = "number",
                },
            },
            icon   = "move",
        })
        ms.fn.define("ms.cam", ms.cam, {
            label  = "Camera",
            group  = "mouse",
            info   = "Move camera by delta",
            params = {
                {
                    name = "dx",
                    type = "number",
                },
                {
                    name = "dy",
                    type = "number",
                },
            },
            icon   = "move",
        })

        ms.fn.define("ms.wait", ms.wait, {
            label  = "Wait",
            group  = "timing",
            info   = "Wait for a duration in milliseconds",
            params = { {
                name = "ms",
                type = "number",
                default = 100,
            } },
            icon   = "pause",
        })
        ms.fn.define("ms.randWait", ms.randWait, {
            label  = "Random Wait",
            group  = "timing",
            info   = "Wait for a random duration between min and max",
            params = {
                {
                    name = "min",
                    type = "number",
                },
                {
                    name = "max",
                    type = "number",
                },
            },
            icon   = "pause",
        })
        ms.fn.define("ms.jitter", ms.jitter, {
            label  = "Jitter",
            group  = "timing",
            info   = "Wait with random jitter around a base duration",
            params = {
                {
                    name = "base",
                    type = "number",
                },
                {
                    name = "jitterMs",
                    type = "number",
                },
            },
            icon   = "pause",
        })

        ms.fn.define("ms.pixelColor", ms.pixelColor, {
            label  = "Pixel Color",
            group  = "sensing",
            info   = "Get the hex color of a pixel",
            params = {
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
                {
                    name = "ref",
                    type = "string",
                },
            },
            icon   = "pixelscan",
        })
        ms.fn.define("ms.pixelMatch", ms.pixelMatch, {
            label  = "Pixel Match",
            group  = "sensing",
            info   = "Check if a pixel matches a hex color",
            params = {
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
                {
                    name = "ref",
                    type = "string",
                },
                {
                    name = "color",
                    type = "string",
                },
                {
                    name = "tol",
                    type = "number",
                },
            },
            icon   = "pixelscan",
        })
        ms.fn.define("ms.waitPixel", ms.waitPixel, {
            label  = "Wait for Pixel",
            group  = "sensing",
            info   = "Wait until a pixel matches a hex color",
            params = {
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
                {
                    name = "ref",
                    type = "string",
                },
                {
                    name = "color",
                    type = "string",
                },
                {
                    name = "tol",
                    type = "number",
                },
                {
                    name = "timeout",
                    type = "number",
                },
            },
            icon   = "pixelscan",
        })
        ms.fn.define("ms.waitNotPixel", ms.waitNotPixel, {
            label  = "Wait for Pixel Change",
            group  = "sensing",
            info   = "Wait until a pixel no longer matches a hex color",
            params = {
                {
                    name = "x",
                    type = "number",
                },
                {
                    name = "y",
                    type = "number",
                },
                {
                    name = "ref",
                    type = "string",
                },
                {
                    name = "color",
                    type = "string",
                },
                {
                    name = "tol",
                    type = "number",
                },
                {
                    name = "timeout",
                    type = "number",
                },
            },
            icon   = "pixelscan",
        })
        ms.fn.define("ms.mousePos", ms.mousePos, {
            label  = "Mouse Position",
            group  = "sensing",
            info   = "Get current mouse position",
            params = {},
            icon   = "move",
        })
        ms.fn.define("ms.keystate", ms.keystate, {
            label  = "Key State",
            group  = "sensing",
            info   = "Check if a key is currently held",
            params = { {
                name = "key",
                type = "string",
            } },
            icon   = "inputs",
        })
        ms.fn.define("ms.mousestate", ms.mousestate, {
            label  = "Mouse State",
            group  = "sensing",
            info   = "Check if a mouse button is currently held (left/right/middle)",
            params = { {
                name = "button",
                type = "string",
            } },
            icon   = "inputs",
        })
        ms.fn.define("ms.padstate", ms.padstate, {
            label  = "Controller State",
            group  = "sensing",
            info   = "Check if a controller button is currently held (a, l2, r3, up...)",
            params = { {
                name = "button",
                type = "string",
            } },
            icon   = "inputs",
        })
        ms.fn.define("ms.padaxis", ms.padaxis, {
            label  = "Controller Axis",
            group  = "sensing",
            info   = "Read a stick (left/right -> x, y) or trigger (l2/r2 -> 0 to 1)",
            params = { {
                name = "axis",
                type = "string",
            } },
            icon   = "inputs",
        })
        ms.fn.define("ms.ocr", ms.ocr, {
            label  = "Read Text",
            group  = "sensing",
            info   = "OCR a screen region (x,y,w,h); blank size = whole screen",
            params = {
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "w", type = "number" },
                { name = "h", type = "number" },
            },
            icon   = "ocr",
        })
        ms.fn.define("ms.readNumber", ms.readNumber, {
            label  = "Read Number",
            group  = "sensing",
            info   = "OCR a region and return the first number in it",
            params = {
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "w", type = "number" },
                { name = "h", type = "number" },
            },
            icon   = "ocr",
        })
        ms.fn.define("ms.findText", ms.findText, {
            label  = "Find Text",
            group  = "sensing",
            info   = "Find text on screen; returns its center {x,y} to click",
            params = {
                { name = "text", type = "string" },
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "w", type = "number" },
                { name = "h", type = "number" },
            },
            icon   = "ocr",
        })
        ms.fn.define("ms.waitText", ms.waitText, {
            label  = "Wait for Text",
            group  = "sensing",
            info   = "Wait until text appears in a region; returns its {x,y}",
            params = {
                { name = "text", type = "string" },
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "w", type = "number" },
                { name = "h", type = "number" },
                { name = "timeout", type = "number" },
            },
            icon   = "ocr",
        })

        ms.fn.define("ms.copy", ms.copy, {
            label  = "Copy",
            group  = "clipboard",
            info   = "Copy text to clipboard",
            params = { {
                name = "text",
                type = "string",
            } },
            icon   = "save",
        })

        ms.fn.define("ms.paste", ms.paste, {
            label  = "Paste",
            group  = "clipboard",
            info   = "Paste the clipboard (" .. (ms.windowsMode and "Ctrl+V" or "Cmd+V") .. ")",
            params = {},
            icon   = "save",
        })

        ms.fn.define("ms.appRunning", ms.appRunning, {
            label  = "App Running",
            group  = "app",
            info   = "Check if an app is running",
            params = { {
                name = "appName",
                type = "string",
            } },
            icon   = "window",
        })
        ms.fn.define("ms.appIsFront", ms.appIsFront, {
            label  = "App in Front",
            group  = "app",
            info   = "Check if an app is the frontmost",
            params = { {
                name = "appName",
                type = "string",
            } },
            icon   = "window",
        })
        ms.fn.define("ms.focus", ms.focus, {
            label  = "Focus App",
            group  = "app",
            info   = "Bring an app to the front",
            params = { {
                name = "appName",
                type = "string",
            } },
            icon   = "window",
        })
        ms.fn.define("ms.windowPos", ms.windowPos, {
            label  = "Window Position",
            group  = "app",
            info   = "Get the position of an app's window",
            params = { {
                name = "appName",
                type = "string",
            } },
            icon   = "window",
        })
        ms.fn.define("ms.window", ms.window, {
            label  = "Window Move/Resize",
            group  = "app",
            info   = "Move or resize the focused window (Move/Resize/Frame)",
            params = {
                {
                    name = "operation",
                    type = "string",
                },
                {
                    name = "x",
                    type = "number",
                }, {
                    name = "y",
                    type = "number",
                },
                {
                    name = "w",
                    type = "number",
                }, {
                    name = "h",
                    type = "number",
                },
            },
            icon   = "window",
        })

        ms.fn.define("ms.sound", ms.sound, {
            label  = "Play Sound",
            group  = "system",
            info   = "Play a sound file",
            params = { {
                name = "path",
                type = "string",
            } },
            icon   = "play",
        })
        ms.fn.define("ms.alert", ms.alert, {
            label  = "Alert",
            group  = "system",
            info   = "Show a toast notification",
            params = {
                {
                    name = "msg",
                    type = "string",
                },
                {
                    name = "duration",
                    type = "number",
                },
            },
            icon   = "alert",
        })
        ms.fn.define("ms.notify", ms.notify, {
            label  = "Notify",
            group  = "system",
            info   = "Show a system notification",
            params = {
                {
                    name = "title",
                    type = "string",
                },
                {
                    name = "subTitle",
                    type = "string",
                },
                {
                    name = "infoText",
                    type = "string",
                },
            },
            icon   = "alert",
        })
        ms.fn.define("ms.screenshot", ms.screenshot, {
            label  = "Screenshot",
            group  = "system",
            info   = "Take a screenshot",
            params = { {
                name = "path",
                type = "string",
            } },
            icon   = "record",
        })
        ms.fn.define("ms.setVolume", ms.setVolume, {
            label  = "Set Volume",
            group  = "system",
            info   = "Set system volume (0-100)",
            params = { {
                name = "level",
                type = "number",
            } },
            icon   = "play",
        })
        ms.fn.define("ms.mute", ms.mute, {
            label  = "Mute",
            group  = "system",
            info   = "Mute system audio",
            params = {},
            icon   = "stop",
        })
        ms.fn.define("ms.unmute", ms.unmute, {
            label  = "Unmute",
            group  = "system",
            info   = "Unmute system audio",
            params = {},
            icon   = "play",
        })
        ms.fn.define("ms.clipChanged", ms.clipChanged, {
            label  = "Clipboard Changed",
            group  = "system",
            info   = "Register a callback for clipboard changes",
            params = { {
                name = "callback",
                type = "function",
            } },
            icon   = "watcher",
        })
        ms.fn.define("ms.saveCursor", ms.saveCursor, {
            label  = "Save Cursor",
            group  = "system",
            info   = "Save current cursor position",
            params = {},
            icon   = "save",
        })
        ms.fn.define("ms.restoreCursor", ms.restoreCursor, {
            label  = "Restore Cursor",
            group  = "system",
            info   = "Restore saved cursor position",
            params = {},
            icon   = "upload",
        })

        ms.fn.define("ms.cancelMacros", ms.cancelMacros, {
            label  = "Cancel Macros",
            group  = "control",
            info   = "Cancel one running macro, or all of them",
            params = {
                {
                    name = "macro",
                    type = "string",
                },
            },
            icon   = "stop",
        })
        ms.fn.define("ms.pause", ms.pause, {
            label  = "Pause",
            group  = "control",
            info   = "Pause current macro",
            params = {},
            icon   = "pause",
        })
        ms.fn.define("ms.resume", ms.resume, {
            label  = "Resume",
            group  = "control",
            info   = "Resume paused macro",
            params = {},
            icon   = "play",
        })
        ms.fn.define("ms.done", ms.done, {
            label  = "Done",
            group  = "control",
            info   = "Signal macro completion",
            params = {},
            icon   = "stop",
        })

        ms.bind.teardown = function()
            for id, handle in pairs(ms.bindHandles) do
                if handle and handle.delete then handle:delete() end
            end
            ms.bindHandles = {}
            ms._modBindings = {}
            ms._mouseCallbacks = {}
            ms._scrollCallbacks = {}
            if ms._scrollListener then
                ms._scrollListener:stop()
                ms._scrollListener = nil
            end
            ms._gamepadCallbacks = {}
            ms.gamepadStop()
        end

        ms.bind.rebind = function()
            ms.bind.teardown()

            local function bindKey(c)
                if not c then return nil end
                local mods = {}
                for _, m in ipairs(c.mods or {}) do mods[#mods+1] = m end
                table.sort(mods)
                local modStr = #mods > 0 and (":" .. table.concat(mods, ",")) or ""
                if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) .. modStr end
                if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") .. modStr end
                if c.type == "gamepad" then return "gamepad:" .. ms.gpToken(c) .. modStr end
                if c.type == "combo"   then
                    local ks = {}
                    for _, k in ipairs(c.keys or {}) do ks[#ks+1] = k end
                    table.sort(ks)
                    return "combo:" .. table.concat(ks, "+") .. modStr
                end
                if c.type == "mods"    then return "mods:" .. table.concat(mods, ",") end
                return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
            end

            local function triggerKey(c)
                if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) end
                if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") end
                if c.type == "gamepad" then return "gamepad:" .. ms.gpToken(c) end
                return nil
            end

            local function modCount(c)
                if not c then return 0 end
                local n = 0
                for _ in ipairs(c.mods or {}) do n = n + 1 end
                if c.type == "combo" then
                    for _ in ipairs(c.keys or {}) do n = n + 1 end
                end
                return n
            end

            local conflicted = {}

            local rootUsed = {}
            for _, id in ipairs(ms.registry._defList) do
                local def = ms.registry._defs[id]
                if not def then goto c1 end
                if ms._suppressedMacros and ms._suppressedMacros[id] then goto c1 end
                local enabled = ms.binds[id]
                if enabled == nil then enabled = def.enabled end
                if not enabled then goto c1 end
                local key = bindKey(ms.effectiveBind(id))
                if key then
                    if rootUsed[key] then
                        local other = rootUsed[key]
                        local visual = (ms.compiler and ms.compiler._registeredIds) or {}
                        local l1 = ms.registry._defs[id].label
                        local l2 = ms.registry._defs[other].label
                        if visual[id] and not visual[other] then
                            conflicted[id] = true
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l1 .. "\" shares its input with \"" .. l2
                                    .. "\" from ms_macros.lua.\nThe visual macro is disabled. Rebind it in the Macros panel.", 10)
                            end)
                        elseif visual[other] and not visual[id] then
                            conflicted[other] = true
                            rootUsed[key] = id
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l2 .. "\" shares its input with \"" .. l1
                                    .. "\" from ms_macros.lua.\nThe visual macro is disabled. Rebind it in the Macros panel.", 10)
                            end)
                        else
                            conflicted[id] = true
                            conflicted[other] = true
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l1 .. "\" and \"" .. l2
                                    .. "\" share the same input.\nBoth disabled. Right-click the macro in the Macros panel > Rebind to resolve.", 10)
                            end)
                        end
                    else
                        rootUsed[key] = id
                    end
                end
                ::c1::
            end

            local sortedIds = {}
            for _, id in ipairs(ms.registry._defList) do
                sortedIds[#sortedIds + 1] = id
            end
            table.sort(sortedIds, function(a, b)
                local ca = modCount(ms.effectiveBind(a))
                local cb = modCount(ms.effectiveBind(b))
                return ca > cb
            end)

            local deviceGroups = {}
            local deviceOrder  = {}

            for _, id in ipairs(sortedIds) do
                if conflicted[id] then goto continue end
                local fn  = ms.bind._wires[id]
                local def = ms.registry._defs[id]
                if not fn or not def then goto continue end
                if ms._suppressedMacros and ms._suppressedMacros[id] then goto continue end

                local group    = ms.bind.group(id)
                local cooldown = ms.cooldowns[id] or def.cooldown or 1000

                local enabled = ms.binds[id]
                if enabled == nil then enabled = def.enabled end
                if not enabled then goto continue end
                local c = ms.effectiveBind(id)
                if not c then goto continue end
                local function firedFn()
                    if ms.running[group] then return end
                    ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                        ms.running[group] = nil
                    end)
                    if ms.dev then
                        local _trig = (function()
                            if c.type == "mouse" then return "M" .. c.button end
                            if c.type == "scroll" then return "S:" .. (c.direction or "?") end
                            if c.type == "gamepad" then return "G:" .. ms.gpLabel(c, "+") end
                            if c.type == "combo" then
                                local _p = {}
                                for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                for _, k in ipairs(c.keys or {}) do _p[#_p+1] = k end
                                return table.concat(_p, "+")
                            end
                            local _p = {}
                            for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                            _p[#_p+1] = c.key or ""
                            return table.concat(_p, "+")
                        end)()
                        pcall(ms.dev._onMacroFire, id, def.label, nil, nil, _trig)
                    end
                    ms._pendingLabel = def.label
                    fn()
                end
                local ignoreMods = ms.bindIgnoreMods and ms.bindIgnoreMods[id] or false
                if c.type == "key" then
                    ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn, nil, false, ignoreMods)
                elseif c.type == "mods" then
                    local modSet = {}
                    for _, m in ipairs(c.mods or {}) do modSet[m] = true end
                    -- Ignore an empty set (would fire on every key release).
                    if next(modSet) then
                        ms._modBindings[#ms._modBindings + 1] = {
                            modSet  = modSet,
                            firedFn = firedFn,
                            fired   = false,
                        }
                    end
                elseif c.type == "combo" then
                    ms.bindHandles[id] = ms.keyCombo(c.mods, c.keys, false, firedFn, false, ignoreMods)
                elseif c.type == "mouse" or c.type == "scroll" or c.type == "gamepad" then
                    local tkey = triggerKey(c)
                    local grp  = deviceGroups[tkey]
                    if not grp then
                        grp = {
                            ctype = c.type,
                            button = c.button,
                            buttons = c.type == "gamepad" and ms.gpButtons(c) or nil,
                            direction = c.direction,
                            claimants = {},
                        }
                        deviceGroups[tkey] = grp
                        deviceOrder[#deviceOrder + 1] = tkey
                    end
                    grp.claimants[#grp.claimants + 1] = {
                        mods = c.mods or {},
                        firedFn = firedFn,
                    }
                end

                ::continue::
            end

            for _, tkey in ipairs(deviceOrder) do
                local grp       = deviceGroups[tkey]
                local claimants = grp.claimants
                local function dispatch()
                    for _, cl in ipairs(claimants) do
                        local match = (#cl.mods == 0)
                        if not match then
                            match = true
                            for _, m in ipairs(cl.mods) do
                                if not ms.keystate(m) then match = false
                                break end
                            end
                        end
                        if match then cl.firedFn()
                        return end
                    end
                end
                if grp.ctype == "mouse" then
                    ms.mouse(grp.button, false, dispatch)
                elseif grp.ctype == "scroll" then
                    ms.bindHandles["_disp:" .. tkey] = ms.scrollBind(grp.direction, dispatch)
                elseif grp.ctype == "gamepad" then
                    ms.bindHandles["_disp:" .. tkey] = ms.gamepadBind(grp.buttons or grp.button, dispatch)
                end
            end

            if ms.trackpadMode then
                if ms._trackpadLeftListener  then ms._trackpadLeftListener:start()  end
                if ms._trackpadRightListener then ms._trackpadRightListener:start() end
            else
                if ms._trackpadLeftListener  then ms._trackpadLeftListener:stop()  end
                if ms._trackpadRightListener then ms._trackpadRightListener:stop() end
            end
            ms.bind.rebindSystem()

            if ms.gamepadEnabled and ms.shell then
                if ms.shell.gpClearOpenBind then ms.shell.gpClearOpenBind() end
                if ms.shell.gpEnsureOpenBind then ms.shell.gpEnsureOpenBind() end
                if ms._shellState and ms._shellState.visible and ms.shell._gpNavHandler then
                    ms._gamepadCallbacks = ms._gamepadCallbacks or {}
                    ms._gamepadCallbacks._nav = ms.shell._gpNavHandler
                end
            end
        end

        ms.suppressMacro = function(id)
            if type(id) ~= "string" or id == "" then return false end
            local def = ms.registry._defs and ms.registry._defs[id]
            if not def or def.system then return false end
            ms._suppressedMacros = ms._suppressedMacros or {}
            ms._suppressedMacros[id] = true
            ms.binds[id] = false
            if ms.bind and ms.bind.rebind then pcall(ms.bind.rebind) end
            if ms.saveSettings then pcall(ms.saveSettings) end
            return true
        end

        ms.bind.rebindSystem = function()
            if ms._systemBindHandles then
                for _, h in pairs(ms._systemBindHandles) do
                    if h and h.delete then h:delete() end
                end
            end
            ms._systemBindHandles = {}

            for _, id in ipairs(ms.registry._defList) do
                local def = ms.registry._defs[id]
                if not def or not def.system then goto sysContinue end
                local enabled = ms.binds[id]
                if enabled == nil then enabled = def.enabled end
                if not enabled then goto sysContinue end
                local c = ms.effectiveBind(id)
                if not c then goto sysContinue end
                local fn = ms.bind._wires[id]
                if not fn then goto sysContinue end
                print("rebindSystem: registering " .. id .. " as system bind")
                if c.type == "key" then
                    local tap = ms._makeKeyWatcher(c.mods, c.key, function()
                        if not ms._targetActive and not ms._isSafeZone() then return end
                        local co = coroutine.create(fn)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("ms.systemBind error: " .. tostring(err)) end
                    end)
                    if tap then ms._systemBindHandles[id] = tap
                    tap:start() end
                elseif c.type == "mouse" then
                    ms._systemBindHandles[id] = ms.mouse(c.button, false, function()
                        if not ms._targetActive and not ms._isSafeZone() then return end
                        local co = coroutine.create(fn)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("ms.systemBind error: " .. tostring(err)) end
                    end, true)
                elseif c.type == "scroll" then
                    ms._systemBindHandles[id] = ms.scrollBind(c.direction, function()
                        if not ms._targetActive and not ms._isSafeZone() then return end
                        local co = coroutine.create(fn)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("ms.systemBind error: " .. tostring(err)) end
                    end)
                elseif c.type == "gamepad" then
                    ms._systemBindHandles[id] = ms.gamepadBind(ms.gpButtons(c), function()
                        if not ms._targetActive and not ms._isSafeZone() then return end
                        local co = coroutine.create(fn)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("ms.systemBind error: " .. tostring(err)) end
                    end)
                end
                ::sysContinue::
            end
            ms.systemBinds.rebind()
        end

        ms.bind.siblingConflict = function(id, c)
            local def = ms.registry._defs[id]
            if not def or def.default or not c then return nil end
            local function key(cfg)
                if not cfg then return nil end
                if cfg.type == "mouse" then return "mouse:" .. tostring(cfg.button) end
                if cfg.type == "scroll" then return "scroll:" .. (cfg.direction or "up") end
                if cfg.type == "gamepad" then return "gamepad:" .. ms.gpToken(cfg) end
                local mods = {}
                for _, m in ipairs(cfg.mods or {}) do table.insert(mods, m) end
                table.sort(mods)
                if cfg.type == "combo" then
                    local ks = {}
                    for _, k in ipairs(cfg.keys or {}) do ks[#ks+1] = k end
                    table.sort(ks)
                    return "combo:" .. table.concat(mods, ",") .. ":" .. table.concat(ks, "+")
                end
                if cfg.type == "mods" then return "mods:" .. table.concat(mods, ",") end
                return "key:" .. table.concat(mods, ",") .. ":" .. (cfg.key or "")
            end
            local ck = key(c)
            if not ck then return nil end
            for _, sibId in ipairs(ms.registry._defList) do
                if sibId ~= id then
                    local sibDef = ms.registry._defs[sibId]
                    if sibDef and not sibDef.default then
                        local sibEnabled = ms.binds[sibId]
                        if sibEnabled == nil then sibEnabled = sibDef.enabled end
                        if sibEnabled and key(ms.effectiveBind(sibId)) == ck then
                            return sibId
                        end
                    end
                end
            end
            return nil
        end

        local _tpModMap = {
            shift=56,
            ctrl=59,
            alt=58,
            cmd=55,
        }

        ms._trackpadHeld = ms._trackpadHeld or {}
        if not ms._trackpadDragTap then
            local T = hs.eventtap.event.types
            ms._trackpadDragTap = hs.eventtap.new({ T.mouseMoved }, function(event)
                local held = ms._trackpadHeld
                if held[1] then
                    event:setType(T.rightMouseDragged)
                    event:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, 1)
                elseif held[0] then
                    event:setType(T.leftMouseDragged)
                end
                return false
            end)
        end
        local function setTrackpadHeld(btn, isHeld)
            ms._trackpadHeld[btn] = isHeld or nil
            if next(ms._trackpadHeld) then
                ms._trackpadDragTap:start()
            else
                ms._trackpadDragTap:stop()
            end
        end

        ms._trackpadReleasers = ms._trackpadReleasers or {}
        ms._releaseTrackpadHolds = function()
            for _, release in pairs(ms._trackpadReleasers) do
                release()
            end
        end

        local function makeTrackpadListener(side, mouseBtn, heldIdx)
            local active = false
            local cachedName = nil
            local cachedCode = nil
            local function holdCode()
                local name = ms.trackpadHoldKeys[side]
                if name ~= cachedName then
                    cachedName = name
                    cachedCode = _tpModMap[name] or hs.keycodes.map[name]
                end
                return cachedCode
            end
            local function release()
                if not active then return end
                active = false
                setTrackpadHeld(heldIdx, false)
                ms._runInCoroutine(ms.Mouse, Release, mouseBtn, Mouse, 0, 0)
            end
            ms._trackpadReleasers[side] = release
            return hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
            }, function(event)
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end
                local code = holdCode()
                if not code then return false end
                if event:getKeyCode() ~= code then return false end
                local isDown = event:getType() == hs.eventtap.event.types.keyDown
                if not isDown then release() end
                ms.keytrack[code] = isDown
                if BindValidity ~= 1 then return false end
                if isDown and not active and ms._targetActive then
                    active = true
                    ms._runInCoroutine(function()
                        ms.Mouse(Press, mouseBtn, Mouse, 0, 0)
                        setTrackpadHeld(heldIdx, true)
                    end)
                end
                return true
            end)
        end

        if not ms._trackpadLeftListener then
            ms._trackpadLeftListener = makeTrackpadListener("left", Left, 0)
        end

        if not ms._trackpadRightListener then
            ms._trackpadRightListener = makeTrackpadListener("right", Right, 1)
        end
    end
-- END core/bind_system --

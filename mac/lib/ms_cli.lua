return function(ms)
    -- Command Line Access (ms.cli) --
        ms.cli = ms.cli or {}

        local _flag = ms.devmode and ms.devmode.rootFlag and ms.devmode.rootFlag("cli") or nil
        local _on   = false

        -- IPC --
            local function _ipcStart()
                if package.loaded["hs.ipc"] and hs.ipc and hs.ipc.__default then return true end
                package.loaded["hs.ipc"] = nil
                local ok, mod = pcall(require, "hs.ipc")
                if not ok then
                    print("MsCli: hs.ipc failed to load: " .. tostring(mod))
                    return false
                end
                hs.ipc = mod
                return true
            end

            local function _ipcStop()
                local mod = package.loaded["hs.ipc"]
                if type(mod) == "table" and mod.__default then
                    pcall(function() mod.__default:delete() end)
                    mod.__default = nil
                end
                package.loaded["hs.ipc"] = nil
            end
        -- END IPC --

        -- State --
            ms.cli.isOn = function()
                return _on
            end

            ms.cli.running = function()
                local mod = package.loaded["hs.ipc"]
                return type(mod) == "table" and mod.__default ~= nil
            end

            ms.cli.enable = function(onDone)
                if not _flag then
                    if onDone then onDone(false) end
                    return
                end
                _flag.set(function(ok)
                    _on = _flag.authorized()
                    if _on then _ipcStart() end
                    if ms.debug then ms.debug.log("cli", "command line access " .. (_on and "on" or "still off")) end
                    if onDone then onDone(ok and _on) end
                end)
            end

            ms.cli.disable = function(onDone)
                if not _flag then
                    if onDone then onDone(true) end
                    return
                end
                _flag.clear(function(off)
                    _on = _flag.authorized()
                    if not _on then _ipcStop() end
                    if ms.debug then ms.debug.log("cli", "command line access " .. (_on and "still on" or "off")) end
                    if onDone then onDone(off) end
                end)
            end
        -- END State --

        -- Formatting --
            local function _yn(v)
                return v and "on" or "off"
            end

            local function _pad(s, n)
                s = tostring(s)
                if #s >= n then return s end
                return s .. string.rep(" ", n - #s)
            end

            local function _tail(text, n)
                local lines = {}
                for l in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = l end
                local first = math.max(1, #lines - n + 1)
                local out = {}
                for i = first, #lines do out[#out + 1] = lines[i] end
                return table.concat(out, "\n")
            end
        -- END Formatting --

        -- Commands --
            local cmds = {}
            local order = {}

            local function def(name, args, about, fn)
                cmds[name] = {
                    args  = args,
                    about = about,
                    fn    = fn,
                }
                order[#order + 1] = name
            end

            def("help", "", "List these commands", function()
                local out = {
                    "mudscript command line",
                    "",
                }
                for _, name in ipairs(order) do
                    local c = cmds[name]
                    out[#out + 1] = "  " .. _pad(name .. (c.args ~= "" and (" " .. c.args) or ""), 22) .. c.about
                end
                return table.concat(out, "\n")
            end)

            def("status", "", "Versions, modes and what is running", function()
                local running = 0
                for _ in pairs(ms.running or {}) do running = running + 1 end
                local front = "?"
                pcall(function() front = hs.application.frontmostApplication():name() end)
                local loaded = 0
                for _ in pairs(ms.plugins and ms.plugins.loaded or {}) do loaded = loaded + 1 end
                return table.concat({
                    "mudscript     " .. tostring(ms.version or "?"),
                    "hammerspoon   " .. tostring(hs.processInfo and hs.processInfo.version or "?"),
                    "target app    " .. tostring(ms._targetApp or "none"),
                    "frontmost     " .. tostring(front),
                    "boot done     " .. tostring(ms._loadComplete == true),
                    "shell open    " .. tostring(ms._shellState and ms._shellState.visible or false),
                    "macros busy   " .. running,
                    "plugins       " .. loaded .. " loaded",
                    "debug mode    " .. _yn(ms.debug and ms.debug.isOn()),
                    "developer     " .. _yn(ms.devmode and ms.devmode.isOn()),
                    string.format("lua memory    %.0f KB", collectgarbage("count")),
                }, "\n")
            end)

            def("macros", "", "Every macro with its group and on/off state", function()
                local reg = ms.registry or {}
                local out = {
                    _pad("ID", 24) .. _pad("GROUP", 12) .. _pad("STATE", 8) .. "LABEL",
                }
                for _, id in ipairs(reg._defList or {}) do
                    local d = reg._defs[id] or {}
                    local on = ms.binds and ms.binds[id]
                    if on == nil then on = d.enabled end
                    local state = on and "on" or "off"
                    if ms.running and ms.running[d.group] then state = state .. "*" end
                    out[#out + 1] = _pad(id, 24) .. _pad(d.group or "", 12) .. _pad(state, 8) .. tostring(d.label or "")
                end
                out[#out + 1] = ""
                out[#out + 1] = "* = its group is running right now"
                return table.concat(out, "\n")
            end)

            def("plugins", "", "Loaded and failed plugins", function()
                local out = {}
                for k in pairs(ms.plugins and ms.plugins.loaded or {}) do out[#out + 1] = "loaded  " .. tostring(k) end
                for k, err in pairs(ms.plugins and ms.plugins.failed or {}) do
                    out[#out + 1] = "FAILED  " .. tostring(k) .. "  " .. tostring(err)
                end
                table.sort(out)
                if #out == 0 then return "No plugins loaded." end
                return table.concat(out, "\n")
            end)

            def("settings", "", "Current value of every macro setting", function()
                local out = {}
                for key in pairs(ms._userSettingIndex or {}) do
                    local ok, v = pcall(ms.settings.get, key)
                    out[#out + 1] = _pad(key, 28) .. tostring(ok and v or "?")
                end
                table.sort(out)
                if #out == 0 then return "No settings defined." end
                return table.concat(out, "\n")
            end)

            def("screens", "", "Displays, sizes and Retina scale", function()
                local out = {}
                for i, s in ipairs(hs.screen.allScreens()) do
                    local f = s:fullFrame()
                    local m = s:currentMode() or {}
                    out[#out + 1] = string.format("%d  %s  %dx%d at %d,%d  scale %s",
                        i, tostring(s:name()), f.w, f.h, f.x, f.y, tostring(m.scale or "?"))
                end
                return table.concat(out, "\n")
            end)

            def("log", "[lines]", "End of the debug log (default 40 lines)", function(n)
                if not (ms.debug and ms.debug.isOn()) then
                    return "Debug mode is off. Turn it on with: mscli debug on"
                end
                local f = io.open(ms.debug.path(), "r")
                if not f then return "Debug log is empty." end
                local text = f:read("*all")
                f:close()
                return _tail(text, tonumber(n) or 40)
            end)

            def("console", "[lines]", "End of the Hammerspoon console (default 40 lines)", function(n)
                local ok, text = pcall(hs.console.getConsole)
                if not ok then return "Could not read the console." end
                return _tail(text, tonumber(n) or 40)
            end)

            def("debug", "on|off|report", "Turn debug mode on or off, or copy a report", function(arg)
                if not ms.debug then return "Debug mode is not available." end
                if arg == "on" then
                    ms.debug.enable()
                    return "Debug mode on. Log: " .. ms.debug.path()
                elseif arg == "off" then
                    ms.debug.disable()
                    return "Debug mode off."
                elseif arg == "report" then
                    local n = ms.debug.copyReport()
                    return "Debug report copied to the clipboard (" .. math.floor(n / 1024) .. " KB)."
                end
                return "Debug mode is " .. _yn(ms.debug.isOn()) .. ". Use: mscli debug on|off|report"
            end)

            def("reload", "", "Reload mudscript", function()
                hs.timer.doAfter(0.2, hs.reload)
                return "Reloading."
            end)

            ms.cli.run = function(line)
                local words = {}
                for w in tostring(line or ""):gmatch("%S+") do words[#words + 1] = w end
                local name = words[1] or "help"
                local c = cmds[name]
                if not c then return "Unknown command: " .. name .. "\nRun: mscli help" end
                local ok, res = pcall(c.fn, words[2], words[3])
                if not ok then return "Error in " .. name .. ": " .. tostring(res) end
                return tostring(res)
            end
        -- END Commands --

        _on = _flag ~= nil and _flag.authorized() or false
        if _on then
            _ipcStart()
            hs.timer.doAfter(3, function()
                ms.alert("Command line access is on.\nPrograms running as you can send Lua to Hammerspoon.", 6)
            end)
        end
    -- END Command Line Access --
end

return function(ms)
    -- Debug Mode (ms.debug) --
        local home    = os.getenv("HOME")
        local flag    = home .. "/.hammerspoon/data/.ms_debug_on"
        local dir     = home .. "/.hammerspoon/logs/debug/"
        local logPath = dir .. "ms_debug.log"
        local prevPath = dir .. "ms_debug.prev.log"

        local MAX_BYTES     = 4 * 1024 * 1024
        local PAYLOAD_CHARS = 400
        local STALL_TICK    = 0.5
        local STALL_LIMIT   = 1.0
        local BEAT_EVERY    = 30
        local CONSOLE_EVERY = 2

        ms.debug = ms.debug or {}

        local _on       = false
        local _fh       = nil
        local _bootT    = hs.timer.secondsSinceEpoch()
        local _hooks    = {}
        local _busFn    = nil
        local _conLen   = 0
        local _origLoad = nil

        -- File --
            local function _open()
                if _fh then return _fh end
                hs.fs.mkdir(home .. "/.hammerspoon/logs")
                hs.fs.mkdir(dir)
                _fh = io.open(logPath, "a")
                return _fh
            end

            local function _close()
                if _fh then pcall(function() _fh:close() end) end
                _fh = nil
            end

            local function _rotate()
                _close()
                if hs.fs.attributes(logPath) then
                    os.remove(prevPath)
                    os.rename(logPath, prevPath)
                end
            end

            local function _write(kind, msg)
                if not _on then return end
                local h = _open()
                if not h then return end
                local t = hs.timer.secondsSinceEpoch()
                local ms3 = math.floor((t - math.floor(t)) * 1000)
                local line = string.format("%s.%03d +%.2fs [%s] %s\n",
                    os.date("%H:%M:%S", math.floor(t)), ms3, t - _bootT,
                    tostring(kind), tostring(msg))
                h:write(line)
                h:flush()
                local size = h:seek("end")
                if size and size > MAX_BYTES then _rotate() end
            end

            local function _brief(v)
                if v == nil then return "" end
                local s
                if type(v) == "table" then
                    local ok, j = pcall(hs.json.encode, v)
                    s = ok and j or tostring(v)
                else
                    s = tostring(v)
                end
                s = s:gsub("\n", " ")
                if #s > PAYLOAD_CHARS then s = s:sub(1, PAYLOAD_CHARS) .. "...(" .. #s .. " chars)" end
                return s
            end
        -- END File --

        -- Environment --
            local function _header()
                local lines = {
                    "==== mudscript debug session " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====",
                    "mudscript: " .. tostring(ms.version or "?"),
                    "hammerspoon: " .. tostring(hs.processInfo and hs.processInfo.version or "?"),
                    "macos: " .. tostring((hs.host.operatingSystemVersionString and hs.host.operatingSystemVersionString()) or "?"),
                    "devmode: " .. tostring(_G._guardianDevMode == true),
                }
                pcall(function()
                    for i, s in ipairs(hs.screen.allScreens()) do
                        local f = s:fullFrame()
                        local m = s:currentMode() or {}
                        lines[#lines + 1] = string.format("screen %d: %s %dx%d scale %s",
                            i, tostring(s:name()), f.w, f.h, tostring(m.scale or "?"))
                    end
                end)
                pcall(function()
                    local app = hs.application.frontmostApplication()
                    lines[#lines + 1] = "frontmost: " .. tostring(app and app:name())
                end)
                lines[#lines + 1] = "accessibility: " .. tostring(hs.accessibilityState())
                for _, l in ipairs(lines) do _write("env", l) end
            end

            local function _snapshot()
                local parts = {
                    string.format("lua %.0fKB", collectgarbage("count")),
                }
                pcall(function()
                    local app = hs.application.frontmostApplication()
                    parts[#parts + 1] = "front " .. tostring(app and app:name())
                end)
                if ms.running then
                    local n = 0
                    for _ in pairs(ms.running) do n = n + 1 end
                    parts[#parts + 1] = "running " .. n
                end
                if ms.plugins and ms.plugins.loaded then
                    local names = {}
                    for k in pairs(ms.plugins.loaded) do names[#names + 1] = tostring(k) end
                    table.sort(names)
                    parts[#parts + 1] = "plugins [" .. table.concat(names, ",") .. "]"
                end
                parts[#parts + 1] = "shell " .. tostring(ms._shellState and ms._shellState.visible or false)
                return table.concat(parts, "  ")
            end
        -- END Environment --

        -- Hooks --
            local function _startHooks()
                local last = hs.timer.secondsSinceEpoch()
                _hooks.stall = hs.timer.doEvery(STALL_TICK, function()
                    local now = hs.timer.secondsSinceEpoch()
                    local late = now - last - STALL_TICK
                    last = now
                    if late > STALL_LIMIT then
                        _write("stall", string.format("main thread blocked for %.2fs", late))
                    end
                end)

                _hooks.beat = hs.timer.doEvery(BEAT_EVERY, function()
                    _write("beat", _snapshot())
                end)

                pcall(function() _conLen = #(hs.console.getConsole() or "") end)
                _hooks.console = hs.timer.doEvery(CONSOLE_EVERY, function()
                    local ok, text = pcall(hs.console.getConsole)
                    if not ok or type(text) ~= "string" then return end
                    if #text < _conLen then _conLen = 0 end
                    if #text == _conLen then return end
                    local chunk = text:sub(_conLen + 1)
                    _conLen = #text
                    for l in chunk:gmatch("[^\n]+") do _write("console", l) end
                end)

                _hooks.app = hs.application.watcher.new(function(name, ev)
                    local names = {
                        [hs.application.watcher.activated]   = "activated",
                        [hs.application.watcher.deactivated] = "deactivated",
                        [hs.application.watcher.launched]    = "launched",
                        [hs.application.watcher.terminated]  = "terminated",
                    }
                    if names[ev] then _write("app", tostring(name) .. " " .. names[ev]) end
                end)
                _hooks.app:start()

                _hooks.power = hs.caffeinate.watcher.new(function(ev)
                    for k, v in pairs(hs.caffeinate.watcher) do
                        if v == ev and type(k) == "string" then
                            _write("power", k)
                            return
                        end
                    end
                end)
                _hooks.power:start()

                _hooks.screen = hs.screen.watcher.new(function()
                    _write("screen", "layout changed, " .. #hs.screen.allScreens() .. " screen(s)")
                end)
                _hooks.screen:start()

                if ms.bus and not _busFn then
                    _busFn = function(topic, payload)
                        _write("bus", topic .. " " .. _brief(payload))
                    end
                    ms.bus.on("*", _busFn)
                end
            end

            local function _stopHooks()
                for _, k in ipairs({
                    "stall",
                    "beat",
                    "console",
                    "app",
                    "power",
                    "screen",
                }) do
                    if _hooks[k] then pcall(function() _hooks[k]:stop() end) end
                    _hooks[k] = nil
                end
                if _busFn and ms.bus then ms.bus.off("*", _busFn) end
                _busFn = nil
            end
        -- END Hooks --

        -- API --
            ms.debug.isOn = function()
                return _on
            end

            ms.debug.path = function()
                return logPath
            end

            ms.debug.size = function()
                local a = hs.fs.attributes(logPath)
                return a and a.size or 0
            end

            ms.debug.log = function(kind, msg)
                _write(kind or "note", msg)
            end

            ms.debug.enable = function()
                if _on then return true end
                local f = io.open(flag, "w")
                if f then f:write("1") f:close() end
                _on = true
                _header()
                _write("debug", "enabled from settings")
                _startHooks()
                return true
            end

            ms.debug.disable = function()
                if not _on then return true end
                _write("debug", "disabled from settings")
                _stopHooks()
                _on = false
                _close()
                os.remove(flag)
                return true
            end

            ms.debug.openFolder = function()
                hs.fs.mkdir(home .. "/.hammerspoon/logs")
                hs.fs.mkdir(dir)
                hs.execute("/usr/bin/open " .. "'" .. dir:gsub("'", "'\\''") .. "'")
            end

            ms.debug.copyReport = function()
                _write("debug", "report copied " .. _snapshot())
                local parts = {}
                for _, p in ipairs({
                    prevPath,
                    logPath,
                }) do
                    local f = io.open(p, "r")
                    if f then
                        parts[#parts + 1] = f:read("*all")
                        f:close()
                    end
                end
                local text = table.concat(parts, "\n")
                local cap = 400 * 1024
                if #text > cap then text = text:sub(-cap) end
                hs.pasteboard.setContents(text)
                return #text
            end

            ms.debug.bootDone = function()
                if not _on then return end
                if ms.loading and _origLoad then ms.loading.update = _origLoad end
                _origLoad = nil
                _write("boot", string.format("complete in %.2fs", hs.timer.secondsSinceEpoch() - _bootT))
                _write("beat", _snapshot())
            end
        -- END API --

        if hs.fs.attributes(flag) then
            _rotate()
            _on = true
            _header()
            _write("boot", "debug mode active from boot")
            if ms.loading and ms.loading.update then
                _origLoad = ms.loading.update
                ms.loading.update = function(pct, msg)
                    _write("boot", tostring(pct) .. "% " .. tostring(msg))
                    return _origLoad(pct, msg)
                end
            end
            _startHooks()
        end
    -- END Debug Mode --
end

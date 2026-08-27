-- MsDevTools --
return function(ms)
-- MsDevTools --
    local MsDevTools = {}

    MsDevTools.name    = "MsDevTools"
    MsDevTools.version = "1.0"

    MsDevTools.archiveLimit = 15
    MsDevTools.logDir       = "~/Documents/ms_dev_logs/"
    MsDevTools.branchTrace  = true

    local function _pushToPanel(panelView, panelId, js)
        local ms = _G.ms

        if ms and ms.shell and ms.shell.getPopOutView then
            local popView = ms.shell.getPopOutView(panelId)
            if popView then
                pcall(function() popView:evaluateJavaScript(js) end)
                return
            end
        end

        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            local fnName, argStr = js:match("^(%w+)%((.+)%)$")
            if fnName and argStr then
                local receiveJs = "shellReceive(\"" .. panelId .. "\",\"" .. fnName .. "\"," .. argStr .. ")"
                pcall(function() ms.shell.eval(receiveJs) end)
                return
            end
        end

        if panelView then
            pcall(function() panelView:evaluateJavaScript(js) end)
        end
    end
-- END MsDevTools --

-- State --
    local _home       = os.getenv("HOME")
    local _devLogDir  = _home .. "/Documents/"
    local _devBaseDir = _devLogDir .. "ms_dev_logs/"
    local _devArchDir = _devBaseDir .. "backups/"
    local _devBase    = "file://" .. _home .. "/.hammerspoon/ui/"

    local _jsonDir, _readDir
    local _catPaths, _readablePaths
    -- Forward-declared at file scope: defined inside :start() but also called from
    -- :showConsole()/:hideConsole()/etc. As a start()-local it was a nil global at
    -- those sites (a latent bug on every platform), which husked the shell when
    -- console open ran ms.shell.eval('showPanel(console)') then threw before loading.
    local _loadDevHistory

    local _typeToCategory = {
        key       = "input",
        mouse     = "input",
        scroll    = "input",
        mousemove = "input",
        macro     = "macro",
        system    = "system",
        error     = "error",
        warn      = "error",
        print     = "console",
        result    = "console",
        input     = "console",
    }

    local _typeToChannel = {
        key = "keys",
        mouse = "keys",
        scroll = "keys",
        mousemove = "keys",
        macro = "watcher",
        sound = "watcher",
        system = "console",
        print = "console",
        result = "console",
        input = "console",
        error = "console",
    }

    local _devBusy            = false
    local _devLastConsoleType = nil

    local _catHandles  = {}
    local _readHandles = {}
    local _dirsEnsured = false

    local function _ensureDirs()
        if _dirsEnsured then return end
        hs.fs.mkdir(_devBaseDir)
        if _jsonDir then hs.fs.mkdir(_jsonDir) end
        if _readDir then hs.fs.mkdir(_readDir) end
        _dirsEnsured = true
    end

    local function _handleFor(tbl, path)
        local h = tbl[path]
        if h then return h end
        _ensureDirs()
        h = io.open(path, "a")
        if h then tbl[path] = h end
        return h
    end

    function MsDevTools:closeLogHandles()
        for path, h in pairs(_catHandles) do pcall(function() h:close() end) end
        for path, h in pairs(_readHandles) do pcall(function() h:close() end) end
        _catHandles = {}
        _readHandles = {}
    end

    local _HIST_MAX            = 500
    local _WRITE_TRIM_INTERVAL = 200
    local _writeCounter        = 0
    local function _trimLogFile(path, keep)
        keep = tonumber(keep) or _HIST_MAX
        local lines = {}
        local f = io.open(path, "r")
        if not f then return end
        for line in f:lines() do lines[#lines + 1] = line end
        f:close()
        if #lines <= keep then return end
        local g = io.open(path, "w")
        if not g then return end
        for i = #lines - keep + 1, #lines do
            g:write(lines[i])
            g:write("\n")
        end
        g:close()
    end
    local _lastReadLine       = nil
    local _consoleSkip = {
        target_focus=1,
        target_blur=1,
        macros_enabled=1,
        macros_disabled=1,
    }
    local _lastReadType       = nil
    local _lastReadCategory   = nil

    local function _flushReadLine()
        if not _lastReadLine then return end

        local catPath = _readablePaths and _readablePaths[_lastReadCategory]

        if catPath then
            local h = _handleFor(_readHandles, catPath)
            if h then
                h:write(_lastReadLine .. "\n")
                h:flush()
            end
        end

        _lastReadLine     = nil
        _lastReadType     = nil
        _lastReadCategory = nil
    end

    local _consolePanel, _watcherPanel, _keysPanel, _windowPanel
    local _consolePanelPos, _watcherPanelPos, _keysPanelPos, _windowPanelPos
    local _consoleOpen, _watcherOpen, _keysOpen, _windowOpen
    local _keysReady, _activeKeys, _activeButtons, _coordMode
    local _mousePos, _mousePoller, _windowPoller
    local _windowHistory, _windowLast, _windowMaxHistory
    local _pushMouseState
    local _winAppWatcher, _winUiWatcher, _winMonitor
    local _winDirty, _winMoveN, _winResizeN, _winLastMouse, _winLastInspectAt
    local _winRead, _winPush
    local _axTimeoutSet = false
    local _devDragTap
    local function _devDragEnd(getView)
        if _devDragTap then _devDragTap:stop()
        _devDragTap = nil end
        local v = getView and getView()
        if v then pcall(function() v:shadow(true) end) end
    end
    local function _devDragStart(getView, pos)
        if _devDragTap then _devDragTap:stop()
        _devDragTap = nil end
        local view = getView()
        if not view then return end
        local startFrame = view:frame()
        local startMouse = hs.mouse.absolutePosition()
        local topLimit = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame().y
        pcall(function() view:shadow(false) end)
        local et = hs.eventtap.event.types
        _devDragTap = hs.eventtap.new({
            et.leftMouseDragged,
            et.leftMouseUp,
        }, function(ev)
            local v = getView()
            if not v then return false end
            if ev:getType() == et.leftMouseUp then
                _devDragEnd(getView)
                return false
            end
            local mp = hs.mouse.absolutePosition()
            local nx = startFrame.x + (mp.x - startMouse.x)
            local ny = math.max(startFrame.y + (mp.y - startMouse.y), topLimit)
            if pos then pos.x = nx
            pos.y = ny end
            pcall(function() v:frame({
                x = nx,
                y = ny,
                w = startFrame.w,
                h = startFrame.h,
            }) end)
            return false
        end)
        _devDragTap:start()
    end
    local _activePanel, _shellMousePoller
    local _winElementTab = true
    local _winElementInspect = false
    local _winPendingEvent, _winWatchedAppName

    local _traceSuppress = false

    local function _shellActive()
        local m = _G.ms
        return m and m.shell and m.shell.isReady and m.shell.isReady() or false
    end
    local _branchState   = {}

    local _devFadeTimers = {}
    local _htmlCache = {}

    local _logEnabled = {
        console = true,
        watcher = true,
        keys = true,
        window = true,
    }

    local function _cacheDevHTML()
        local files = {
            console = _home .. "/.hammerspoon/ui/ms_console.html",
            watcher = _home .. "/.hammerspoon/ui/ms_watcher.html",
            keys    = _home .. "/.hammerspoon/ui/ms_keys.html",
            window  = _home .. "/.hammerspoon/ui/ms_window.html",
        }
        for name, path in pairs(files) do
            local f = io.open(path, "r")
            if f then
                _htmlCache[name] = f:read("*all")
                f:close()
            end
        end
    end
-- END State --

-- Lifecycle --
    function MsDevTools:init()
        _jsonDir = _devBaseDir .. "json/"
        _readDir = _devBaseDir .. "readable/"

        _catPaths = {}
        _readablePaths = {}

        for _, cat in ipairs({
            "input",
            "macro",
            "system",
            "error",
            "console",
        }) do
            _catPaths[cat]      = _jsonDir .. "ms_dev_" .. cat .. ".log"
            _readablePaths[cat] = _readDir .. "ms_dev_" .. cat .. ".txt"
        end

        self:_archiveOnReload()

        _activeKeys       = {}
        _activeButtons    = {}
        _coordMode        = "screen"
        _keysReady        = false
        _windowHistory    = {}
        _windowLast       = nil
        _windowMaxHistory = 80
    end

    function MsDevTools:start()
        if not ms then return end
        if ms.checkGuardian and not ms.checkGuardian("MsDevTools") then return end

        if not _axTimeoutSet then
            _axTimeoutSet = pcall(function()
                hs.axuielement.systemWideElement():setTimeout(0.15)
            end)
        end

        _cacheDevHTML()

        ms.dev = {
            _consolePanel    = nil,
            _watcherPanel    = nil,
            _keysPanel       = nil,
            _consolePanelPos = nil,
            _watcherPanelPos = nil,
            _keysPanelPos    = nil,
            _activeKeys      = _activeKeys,
            _activeButtons   = _activeButtons,
            _coordMode       = _coordMode,
            _keysReady       = false,
        }

        setmetatable(ms.dev, {
            __index = function(t, k)
                if     k == "_consolePanel" then return _consolePanel
                elseif k == "_watcherPanel" then return _watcherPanel
                elseif k == "_keysPanel"    then return _keysPanel
                elseif k == "_keysReady"    then return _keysReady
                elseif k == "_consoleOpen"  then return _consoleOpen
                elseif k == "_watcherOpen"  then return _watcherOpen
                elseif k == "_keysOpen"     then return _keysOpen
                elseif k == "_windowOpen"   then return _windowOpen
                elseif k == "recolor"       then return function() self:recolor() end
                elseif k == "rezoom"        then return function(_, a, b, c) return self:rezoom(a, b, c) end
                end
            end,
        })

        ms.dev.log = setmetatable({
            pause = function(channel)
                _logEnabled[channel] = false
            end,
            resume = function(channel)
                _logEnabled[channel] = true
            end,
            only = function(channel)
                for ch, _ in pairs(_logEnabled) do
                    _logEnabled[ch] = (ch == channel)
                end
            end,
            pauseAll = function()
                for ch, _ in pairs(_logEnabled) do
                    _logEnabled[ch] = false
                end
            end,
            resumeAll = function()
                for ch, _ in pairs(_logEnabled) do
                    _logEnabled[ch] = true
                end
            end,
            isEnabled = function(channel)
                return _logEnabled[channel] == true
            end,
        }, {
            __call = function(_, entry)
                self:log(entry)
            end,
        })

        ms.dev._onMacroFire = function(...)
            self:onMacroFire(...)
        end

        ms.dev._onKeyEvent = function(...)
            self:onKeyEvent(...)
        end

        ms.dev._onMouseEvent = function(...)
            self:onMouseEvent(...)
        end

        ms.dev._wantsMouseEvents = function()
            return _keysPanel or _shellActive() or _logEnabled.keys
        end
        ms.dev._wantsKeyEvents = function()
            return _keysPanel or _shellActive() or _logEnabled.keys
        end

        ms.dev.console = {}
        ms.dev.console.show   = function() self:showConsole() end
        ms.dev.console.hide   = function() self:hideConsole() end
        ms.dev.console.toggle = function() self:toggleConsole() end

        ms.dev.watcher = {}
        ms.dev.watcher.show   = function() self:showWatcher() end
        ms.dev.watcher.hide   = function() self:hideWatcher() end
        ms.dev.watcher.toggle = function() self:toggleWatcher() end

        ms.dev.keys = {}
        ms.dev.keys.show   = function() self:showKeys() end
        ms.dev.keys.hide   = function() self:hideKeys() end
        ms.dev.keys.toggle = function() self:toggleKeys() end

        ms.dev.window = {}
        ms.dev.window.show   = function() self:showWindow() end
        ms.dev.window.hide   = function() self:hideWindow() end
        ms.dev.window.toggle = function() self:toggleWindow() end

        ms.dev.prewarm     = function() self:prewarm() end
        ms.dev.prewarmStep = function(which) self:prewarmStep(which) end
        ms.dev.step        = function(msg) self:step(msg) end

        ms.dev._pushMouseState = function(x, y)
            self:pushMouseState(x, y)
        end
        _pushMouseState = ms.dev._pushMouseState

        self._origPrint = print

        _G.print = function(...)
            self._origPrint(...)

            local parts = {}

            for i = 1, select('#', ...) do
                parts[i] = tostring(select(i, ...))
            end

            self:log({
                type = "print",
                msg  = table.concat(parts, "\t"),
            })
        end

        local _consoleSrc = nil

        local function _logConsole(entry)
            pcall(function() self:log(entry) end)
        end

        _G.__msConsoleEval = function()
            local src = _consoleSrc
            _consoleSrc = nil

            if type(src) ~= "string" then return end

            local fn, err = load("return " .. src)
            if not fn then fn, err = load(src) end

            if not fn then
                _logConsole({
                    type = "error",
                    msg = tostring(err),
                })
                return tostring(err)
            end

            local res = table.pack(xpcall(fn, debug.traceback))

            if not res[1] then
                _logConsole({
                    type = "error",
                    msg = tostring(res[2]),
                })
                return res[2]
            end

            if res.n > 1 then
                local parts = {}

                for i = 2, res.n do
                    parts[#parts + 1] = tostring(res[i])
                end

                _logConsole({
                    type = "result",
                    msg  = table.concat(parts, "\t"):sub(1, 2000),
                })
            end

            return table.unpack(res, 2, res.n)
        end

        local _prevPreparser = hs._consoleInputPreparser

        hs._consoleInputPreparser = function(s)
            if _prevPreparser then
                local ok, s2 = pcall(_prevPreparser, s)
                if ok and type(s2) == "string" then s = s2 end
            end

            if type(s) ~= "string" or s:match("^%s*$") then return s end

            _logConsole({
                type = "input",
                msg = s,
            })

            _consoleSrc = s

            return "__msConsoleEval()"
        end

        -- Assigns the file-scope upvalue (declared above), not a start()-local, so
        -- sibling methods (:showConsole etc.) can call it. All upvalues it closes over
        -- (_catPaths/_readablePaths/_HIST_MAX/_pushToPanel) are themselves file-level.
        function _loadDevHistory(panel, categories, shellPanelId, skipEvents)
            local entries = {}
            -- Insertion order per entry, so the merge below is a *stable* sort:
            -- entries sharing a timestamp keep their real arrival order instead
            -- of being shuffled by table.sort (which is not stable).
            local order = {}
            for _, cat in ipairs(categories) do
                local path = _catPaths[cat]
                if path then
                    local f = io.open(path, "r")
                    if f then
                        local rawLines = {}
                        for line in f:lines() do
                            rawLines[#rawLines + 1] = line
                        end
                        f:close()
                        local start = math.max(1, #rawLines - _HIST_MAX + 1)
                        for i = start, #rawLines do
                            local ok, entry = pcall(hs.json.decode, rawLines[i])
                            if ok and entry then
                                if not skipEvents or not (entry.event and skipEvents[entry.event]) then
                                    entries[#entries + 1] = entry
                                    order[entry] = #entries
                                end
                            end
                        end
                    end
                end
            end
            if #entries == 0 then return end
            -- Merge the per-category streams into one timeline. Without this the
            -- panel shows every console entry, then every system entry, so the
            -- clock jumps backwards at each category boundary. entry.ts is a
            -- zero-padded "%H:%M:%S" string, so a lexicographic compare orders
            -- correctly (within a single day).
            table.sort(entries, function(a, b)
                local ta, tb = a.ts or "", b.ts or ""
                if ta == tb then return order[a] < order[b] end
                return ta < tb
            end)
            local ok, json = pcall(hs.json.encode, entries)
            if ok then
                if shellPanelId then
                    _pushToPanel(nil, shellPanelId, "loadHistory(" .. json .. ")")
                elseif panel then
                    pcall(function()
                        panel:evaluateJavaScript("loadHistory(" .. json .. ")")
                    end)
                end
            end
        end

        if ms.bus then
            ms.bus.on("ui:console:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "execute" and body.code then
                    local fn, err = load("return " .. body.code)
                    if not fn then fn, err = load(body.code) end
                    if not fn then
                        self:_devWrite({
                            type = "error",
                            msg = err or "syntax error",
                        })
                    else
                        local res = table.pack(pcall(fn))
                        local success = table.remove(res, 1)
                        if not success then
                            self:_devWrite({
                                type = "error",
                                msg = tostring(res[1]),
                            })
                        elseif #res > 0 then
                            local parts = {}
                            for _, v in ipairs(res) do parts[#parts + 1] = tostring(v) end
                            self:_devWrite({
                                type = "result",
                                msg = table.concat(parts, "\t"),
                            })
                        end
                    end
                elseif action == "clear" then
                    for _, cat in ipairs({
                        "console",
                        "error",
                        "system",
                    }) do
                        local p = _catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end
                        local r = _readablePaths[cat]
                        if r then local f = io.open(r, "w")
                        if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ackDanger" then
                    ms._consoleDangerAck = true
                    if ms.saveSettings then ms.saveSettings() end
                elseif action == "ready" then
                    _loadDevHistory(nil, {
                        "console",
                        "error",
                        "system",
                    }, "console", _consoleSkip)
                    _pushToPanel(_consolePanel, "console",
                        "setDangerAck(" .. (ms._consoleDangerAck and "true" or "false") .. ")")
                end
            end)

            ms.bus.on("ui:watcher:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    for _, cat in ipairs({
                        "macro",
                        "error",
                    }) do
                        local p = _catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end
                        local r = _readablePaths[cat]
                        if r then local f = io.open(r, "w")
                        if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    _loadDevHistory(nil, {
                        "macro",
                        "error",
                    }, "watcher")
                end
            end)

            local function _pushRefDims()
                if not (_keysPanel or _shellActive()) then return end
                local w = ms._refW or 1680
                local h = ms._refH or 1044
                pcall(function()
                    _pushToPanel(_keysPanel, "keys",
                        "setRefDims({\"w\":" .. w .. ",\"h\":" .. h .. "})")
                end)
            end
            ms.dev.pushRefDims = _pushRefDims

            ms.bus.on("ui:keys:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    local p = _catPaths["input"]
                    if p then local f = io.open(p, "w")
                    if f then f:close() end end
                    local r = _readablePaths["input"]
                    if r then local f = io.open(r, "w")
                    if f then f:close() end end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    if not _keysReady then
                        _keysReady = true
                        local _p = hs.mouse.absolutePosition()
                        _mousePos = {
                            x = math.floor(_p.x),
                            y = math.floor(_p.y),
                        }
                    end
                    _loadDevHistory(nil, {"input"}, "keys")
                    _pushRefDims()
                elseif action == "setCoordMode" then
                    _coordMode = body.mode or "screen"
                end
            end)

            ms.bus.on("ui:window:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    _windowHistory = {}
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "tab" then
                    _winElementTab = (body.tab == "window")
                    if _winElementTab then _winLastMouse = nil end
                elseif action == "setInspect" then
                    _winElementInspect = (body.enabled == true)
                    if not _winElementInspect then _winLastMouse = nil end
                elseif action == "ready" then
                    hs.timer.doAfter(0.05, function()
                        if _windowOpen then
                            local st = _winRead(hs.window.focusedWindow())
                            if st then _winPush("updateCurrentWindow", st) end
                            if #_windowHistory > 0 then
                                local ok, j = pcall(hs.json.encode, _windowHistory)
                                if ok then pcall(function()
                                    _pushToPanel(_windowPanel, "window", "loadHistory(" .. j .. ")")
                                end) end
                            end
                        end
                    end)
                end
            end)

            ms.bus.on("panel:poppedOut", function(_, body)
                if not body or body.id ~= "window" then return end
                _windowOpen = true
                if not (_G.ms and _G.ms._octaneMode) then
                    self:_winEngineStart()
                end
            end)

            ms.bus.on("ui:_shell:navigate", function(_, data)
                if not data or not data.panel then return end
                local p = data.panel

                local _octaneActive = _G.ms and _G.ms._octaneMode
                if _octaneActive then
                    local _panelToChannel = {
                        console="console",
                        watcher="watcher",
                        keys="keys",
                        window="window",
                    }
                    local prevCh = _panelToChannel[_activePanel]
                    if prevCh then _logEnabled[prevCh] = false end
                    local newCh = _panelToChannel[p]
                    if newCh then _logEnabled[newCh] = true end
                end

                _activePanel = p
                if p ~= "window" then
                    _winElementTab = false
                    self:_winEngineStop()
                end
                if p == "console" then
                    _consoleOpen = true
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {
                            "console",
                            "error",
                            "system",
                        }, "console", _consoleSkip)
                    end)
                elseif p == "watcher" then
                    _watcherOpen = true
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {
                            "macro",
                            "error",
                        }, "watcher")
                    end)
                elseif p == "keys" then
                    if not _keysReady then _keysReady = true end
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {"input"}, "keys")
                    end)
                    if not _octaneActive then
                        if _shellMousePoller then _shellMousePoller:stop() end
                        _shellMousePoller = hs.timer.doEvery(0.08, function()
                        if not _shellActive() then
                            if _shellMousePoller then _shellMousePoller:stop()
                            _shellMousePoller = nil end
                            return
                        end
                        if _activePanel ~= "keys" then return end
                        local _sst = _G.ms and _G.ms._shellState
                        if _sst and _sst.visible == false then return end
                        local _p = hs.mouse.absolutePosition()
                        local _x, _y = math.floor(_p.x), math.floor(_p.y)
                        local prev = _mousePos
                        if not prev or _x ~= prev.x or _y ~= prev.y then
                            _mousePos = {
                                x = _x,
                                y = _y,
                            }
                            pcall(function() _pushMouseState(_x, _y) end)
                        end
                    end)
                    end
                elseif p == "window" then
                    _windowOpen = true
                    hs.timer.doAfter(0.15, function()
                        if #_windowHistory > 0 then
                            local ok, j = pcall(hs.json.encode, _windowHistory)
                            if ok then pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end) end
                        end
                    end)
                    if not _octaneActive then
                        self:_winEngineStart()
                    end
                end
            end)

            ms.bus.on("macroLab:toggled", function(_, body)
                if body and body.visible and _activePanel == "window" and _windowOpen
                    and not (_G.ms and _G.ms._octaneMode) then
                    self:_winEngineStart()
                end
                if body and not body.visible and _G.ms and _G.ms._octaneMode then
                    local _panelToChannel = {
                        console="console",
                        watcher="watcher",
                        keys="keys",
                        window="window",
                    }
                    local ch = _panelToChannel[_activePanel]
                    if ch then _logEnabled[ch] = false end
                end
            end)
        end
    end
-- END Lifecycle --

-- Archive Helpers --
    function MsDevTools:_archiveLog(path, stamp, subdir)
        if not hs.fs.attributes(path) then return end

        local sessionDir = _devArchDir .. "session_" .. stamp .. "/"
        local destDir    = sessionDir .. subdir .. "/"

        hs.fs.mkdir(_devBaseDir)
        hs.fs.mkdir(_devArchDir)
        hs.fs.mkdir(sessionDir)
        hs.fs.mkdir(destDir)

        local filename = path:match("([^/]+)$")

        if filename then
            os.rename(path, destDir .. filename)
        end
    end

    function MsDevTools:_pruneSessionArchives(limit)
        if not hs.fs.attributes(_devArchDir) then return end

        local list = {}

        for name in hs.fs.dir(_devArchDir) do
            if name:match("^session_%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d$") then
                table.insert(list, name)
            end
        end

        table.sort(list)

        local pruned = 0

        while #list > limit and pruned < 5 do
            local dir = _devArchDir .. list[1]

            for _, sub in ipairs({
                "json",
                "readable",
            }) do
                local sp = dir .. "/" .. sub

                if hs.fs.attributes(sp) then
                    for fname in hs.fs.dir(sp) do
                        if fname ~= "." and fname ~= ".." then
                            os.remove(sp .. "/" .. fname)
                        end
                    end

                    hs.fs.rmdir(sp)
                end
            end

            hs.fs.rmdir(dir)
            table.remove(list, 1)
            pruned = pruned + 1
        end
    end

    function MsDevTools:_archiveOnReload()
        _flushReadLine()

        local limit = (type(self.archiveLimit) == "number" and self.archiveLimit >= 0)
            and self.archiveLimit or 15

        self:_pruneSessionArchives(limit)

        local stamp = os.date("%Y-%m-%d_%H%M%S")

        hs.fs.mkdir(_jsonDir)
        hs.fs.mkdir(_readDir)

        for _, p in pairs(_catPaths) do
            self:_archiveLog(p, stamp, "json")
        end

        for _, p in pairs(_readablePaths) do
            self:_archiveLog(p, stamp, "readable")
        end
    end
-- END Archive Helpers --

-- Core Logging --
    function MsDevTools:_devWrite(entry)
        if _devBusy then return end
        if entry.type == "step" then return end

        local ch = _typeToChannel[entry.type]
        if ch and not _logEnabled[ch] then
            local alsoChannel = nil
            if entry.type == "error" then alsoChannel = "watcher" end
            if not alsoChannel or not _logEnabled[alsoChannel] then
                _devBusy = false
                return
            end
        end

        _devBusy = true

        _flushReadLine()

        entry.ts = os.date("%H:%M:%S")

        if not entry.category then
            entry.category = _typeToCategory[entry.type] or "system"
        end

        if not entry.msg or entry.msg == "" then
            local headline = entry.event or entry.key or entry.type or "log"
            local details  = {}

            if entry.source then table.insert(details, "  source: " .. entry.source) end
            if entry.reason then table.insert(details, "  reason: " .. entry.reason) end
            if entry.output then table.insert(details, "  output: " .. tostring(entry.output):sub(1, 200)) end

            if #details > 0 then
                entry.msg = headline .. "\n" .. table.concat(details, "\n")
            else
                entry.msg = headline
            end
        end

        local ok, json = pcall(hs.json.encode, entry)

        if not ok then
            _devBusy = false
            return
        end

        local catPath = _catPaths[entry.category]

        if catPath then
            local h = _handleFor(_catHandles, catPath)
            if h then
                h:write(json .. "\n")
                h:flush()
            end

            _writeCounter = _writeCounter + 1
            if _writeCounter % _WRITE_TRIM_INTERVAL == 0 then
                _trimLogFile(catPath, _HIST_MAX)
                if _catHandles[catPath] then _catHandles[catPath]:close()
                _catHandles[catPath] = nil end
            end
        end

        local readPath = _readablePaths[entry.category]

        if readPath then
            local h = _handleFor(_readHandles, readPath)
            if h then
                local t    = entry.type
                local line

                if t == "key" then
                    local arrow = entry.down and "\226\134\147" or "\226\134\145"

                    line = "[" .. entry.ts .. "] " .. arrow .. " "
                        .. (entry.key or "?") .. " (" .. tostring(entry.keyCode or "?") .. ")"

                elseif t == "mouse" then
                    local arrow = entry.down and "\226\134\147" or "\226\134\145"
                    local pos   = ""

                    if entry.x and entry.y then
                        pos = "  " .. entry.x .. "," .. entry.y
                    end

                    line = "[" .. entry.ts .. "] " .. arrow .. " mouse:"
                        .. tostring(entry.button or "?") .. pos

                elseif t == "scroll" then
                    line = "[" .. entry.ts .. "] \226\134\165 scroll " .. (entry.direction or "")

                elseif t == "mousemove" then
                    line = "[" .. entry.ts .. "] \226\134\146 " .. (entry.x or "?") .. ", " .. (entry.y or "?")

                else
                    local parts = {}

                    local function add(label, val)
                        if val ~= nil and val ~= "" then
                            parts[#parts + 1] = "  " .. label .. ": " .. tostring(val)
                        end
                    end

                    local headline = entry.msg or entry.label or entry.event or entry.type or "log"
                    local first, rest = headline:match("^([^\n]+)\n(.*)$")

                    if first then
                        headline = first
                        add("detail", rest:gsub("\n", " | "))
                    end

                    add("fromDialog", entry.fromDialog)
                    add("to",          entry.to)
                    add("status",      entry.status)
                    add("cur",         entry.cur)
                    add("trusted",     entry.trusted)
                    add("code",        entry.code)
                    add("version",     entry.version)
                    add("channel",     entry.channel)
                    add("target",      entry.target)
                    add("format",      entry.format)
                    add("id",          entry.id)
                    add("label",       entry.label)
                    add("parent",      entry.parentLabel)
                    add("trigger",     entry.trigger)

                    line = "[" .. entry.ts .. "] " .. headline

                    if #parts > 0 then
                        line = line .. "\n" .. table.concat(parts, "\n")
                    end
                end

                if _lastReadType == entry.type then
                else
                    if _lastReadLine then
                        h:write(_lastReadLine .. "\n")
                    end
                    _lastReadLine     = line
                    _lastReadType     = entry.type
                    _lastReadCategory = entry.category
                end
                h:flush()
            end
        end

        local t = entry.type

        if (_consolePanel or _shellActive()) and _logEnabled.console and t ~= "mousemove" and t ~= "step" then
            local send = false

            local _consoleDedicated = {
                key=1,
                mouse=1,
                sound=1,
                macro=1,
            }
            if t == "system" and entry.event and _consoleSkip[entry.event] then
                send = false
            elseif _consoleDedicated[t] then
                send = false
            else
                _devLastConsoleType = nil
                send = true
            end

            if send then
                pcall(function()
                    _pushToPanel(_consolePanel, "console", "appendEntry(" .. json .. ")")
                end)
            end
        end

        if (_watcherPanel or _shellActive()) and _logEnabled.watcher and (t == "macro" or t == "error" or t == "sound") then
            pcall(function()
                _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. json .. ")")
            end)
        end

        if (_keysPanel or _shellActive()) and _logEnabled.keys and _keysReady
            and (t == "key" or t == "mouse" or t == "scroll" or t == "mousemove") then
            pcall(function()
                _pushToPanel(_keysPanel, "keys", "appendEntry(" .. json .. ")")
            end)
        end

        _devBusy = false
    end

    function MsDevTools:log(entry)
        self:_devWrite(entry)
    end
-- END Core Logging --

-- Event Hooks --
    function MsDevTools:onMacroFire(id, label, parentId, parentLabel, trigger)
        if parentLabel then
            self:_devWrite({
                type  = "step",
                category = "macro",
                msg   = "[" .. (parentLabel or "macro") .. "] -> " .. (label or id),
            })
        end
        self:_devWrite({
            type        = "macro",
            id          = id,
            label       = label or id,
            parentLabel = parentLabel,
            trigger     = trigger,
        })
    end

    function MsDevTools:onKeyEvent(keyCode, keyName, isDown)
        self:_devWrite({
            type    = "key",
            key     = keyName or ("code:" .. tostring(keyCode)),
            keyCode = keyCode,
            down    = isDown,
        })

        if isDown then
            _activeKeys[keyCode] = keyName or tostring(keyCode)
        else
            _activeKeys[keyCode] = nil
        end

        if _keysPanel or _shellActive() then
            local active = {}

            for code, name in pairs(_activeKeys) do
                table.insert(active, {
                    name = name,
                    code = code,
                })
            end

            local aok, aj = pcall(hs.json.encode, active)

            if aok then
                pcall(function()
                    _pushToPanel(_keysPanel, "keys", "updateActiveKeys(" .. aj .. ")")
                end)
            end
        end
    end

    function MsDevTools:onMouseEvent(button, isDown, x, y)
        self:_devWrite({
            type   = "mouse",
            button = button,
            down   = isDown,
            x      = x,
            y      = y,
        })

        if isDown then
            _activeButtons[button] = true
        else
            _activeButtons[button] = nil
        end

        if (_keysPanel or _shellActive()) and _keysReady then
            local active = {}

            for btn in pairs(_activeButtons) do
                table.insert(active, btn)
            end

            local aok, aj = pcall(hs.json.encode, {
                x       = x,
                y       = y,
                buttons = active,
            })

            if aok then
                pcall(function()
                    _pushToPanel(_keysPanel, "keys", "updateMouseState(" .. aj .. ")")
                end)
            end
        end
    end
-- END Event Hooks --

-- Watcher Helpers --
    local function _buildDisplayLabel(label)
        if label then return label end
        if not (ms and ms._getCallChain) then return nil end
        return ms._getCallChain()
    end

    function MsDevTools:watcherStep(msg, label)
        if not _watcherPanel then return end

        local displayLabel = _buildDisplayLabel(label)
        if not displayLabel then return end

        local ok, j = pcall(hs.json.encode, {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = "[" .. displayLabel .. "] " .. msg,
        })

        if ok then
            pcall(function()
                _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
            end)
        end
    end

    function MsDevTools:macroLog(msg, label)
        local displayLabel = _buildDisplayLabel(label)
        if not displayLabel then return end

        self:log({
            type     = "step",
            category = "macro",
            msg      = "[" .. displayLabel .. "] " .. msg,
        })
    end

    function MsDevTools:accCamMove(dx, dy, label)
        if _traceSuppress then return end
        if dx == nil or dy == nil then return end
        local msg = "cam(" .. dx .. ", " .. dy .. ")"
        if _watcherPanel then self:watcherStep(msg, label) end
        self:macroLog(msg, label)
    end

    function MsDevTools:accWait(duration, label)
        if _traceSuppress then return end
        local msg = "wait " .. (tonumber(duration) or 0) .. "ms"
        if _watcherPanel then self:watcherStep(msg, label) end
        self:macroLog(msg, label)
    end

    function MsDevTools:flushCam(label) end
    function MsDevTools:flushWait(label) end
    function MsDevTools:flushAll(label) end

    function MsDevTools:setTraceSuppress(val)
        _traceSuppress = val
    end

    function MsDevTools:getTraceSuppress()
        return _traceSuppress
    end
-- END Watcher Helpers --

-- Branch Tracing --
    function MsDevTools:_traceLog(co, msg)
        local st = _branchState[co]

        if not st then return end

        table.insert(st.buffer, "[" .. os.date("%H:%M:%S") .. "] [" .. st.label .. "] " .. msg)
    end

    function MsDevTools:flushTraceBuffer(co)
        local st = _branchState[co]

        if not st or #st.buffer == 0 then return end

        local h = _handleFor(_readHandles, _readablePaths and _readablePaths["macro"])
        if h then
            for _, line in ipairs(st.buffer) do
                h:write(line .. "\n")
            end
            h:flush()
        end

        if _watcherPanel then
            for _, line in ipairs(st.buffer) do
                local ok, j = pcall(hs.json.encode, {
                    type = "step",
                    ts   = os.date("%H:%M:%S"),
                    msg  = line,
                })

                if ok then
                    pcall(function()
                        _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
                    end)
                end
            end
        end

        st.buffer = {}
    end

    function MsDevTools:startTrace(co, label)
        if not co then return end

        _branchState[co] = {
            label  = label or "macro",
            buffer = {},
        }
    end

    function MsDevTools:stopTrace(co)
        self:flushTraceBuffer(co)

        _branchState[co] = nil
    end
-- END Branch Tracing --

-- Panel Helpers --

    local function _devThemeJS()
        local t = ms._theme or {}

        local safe = {}
        for _, k in ipairs({
            "bg",
            "surface",
            "surface2",
            "hover",
            "accent",
            "accentHi",
            "success","dangerBg","danger","warning","text","text2","text3",
            "border","borderDim","accentGlow","accentGlowFaint","dangerGlow",
            "dangerBorder","mouse","scroll","key","radius","font"}) do
            if t[k] ~= nil then safe[k] = t[k] end
        end

        if type(t.font) == "string" and t.font:match("%.[ot]tf$") then
            local fp = hs.configdir .. "/sounds/" .. t.font
            local f = io.open(fp, "r")
            if not f then
                fp = _home .. "/.hammerspoon/sounds/" .. t.font
                f = io.open(fp, "r")
            end
            if f then f:close()
            safe.fontURL = "file://" .. fp end
        end

        local ok, json = pcall(hs.json.encode, safe)
        if not ok or json == "{}" then return "" end

        return "applyTheme(" .. json .. ")"
    end

    local function _makeDevPanel(ucName, w, h, xOff, yOff)
        local uc     = hs.webview.usercontent.new(ucName)
        local screen = hs.screen.mainScreen():frame()
        local x      = screen.x + screen.w - w - xOff
        local y      = screen.y + yOff
        local panel  = hs.webview.new(
            {
                x = x,
                y = y,
                w = w,
                h = h,
            },
            { developerExtrasEnabled = true },
            uc
        )

        if not panel then return nil, uc end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:allowTextEntry(true) end)
        pcall(function() panel:shadow(true) end)

        return panel, uc, {
            x = x,
            y = y,
            w = w,
            h = h,
        }
    end

    local function _setupDevPanelTheme(panel, timerKey, onReady)
        if ms and ms.theme and ms.theme.applyWindowRadius then ms.theme.applyWindowRadius(panel) end
        if ms and ms.theme and ms.theme.onChanged then
            ms.theme.onChanged(function()
                if ms and ms.theme and ms.theme._pushWindowRadius then ms.theme._pushWindowRadius(panel) end
            end)
        end

        panel:navigationCallback(function(_, action)
            if action == "navigating" then return end

            _devFadeTimers[timerKey] = hs.timer.doAfter(0, function()
                _devFadeTimers[timerKey] = nil
                local tj = _devThemeJS()

                if tj ~= "" then
                    pcall(function() panel:evaluateJavaScript(tj) end)
                end
                -- Freshly opened popout inherits the current UI zoom.
                local z = ms and ms._uiZoom or 1.0
                if z ~= 1.0 then
                    pcall(function()
                        panel:evaluateJavaScript(
                            "if(window.applyZoom)applyZoom(" .. z .. ")")
                    end)
                end
            end)

            if onReady then onReady() end
        end)
    end

    local function _devFadeIn(panel, key)
        if _devFadeTimers[key] then
            _devFadeTimers[key]:stop()
            _devFadeTimers[key] = nil
        end

        if ms and ms._octaneMode then
            pcall(function() panel:alpha(1) end)
            return
        end

        pcall(function() panel:alpha(0) end)

        local step, steps = 0, 6

        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
            step = step + 1

            pcall(function() panel:alpha(step / steps) end)

            if step >= steps then
                _devFadeTimers[key]:stop()
                _devFadeTimers[key] = nil
            end
        end)
    end

    local function _devFadeOut(panel, key, onDone)
        if _devFadeTimers[key] then
            _devFadeTimers[key]:stop()
            _devFadeTimers[key] = nil
        end

        if ms and ms._octaneMode then
            pcall(function() panel:alpha(0) end)
            if onDone then onDone() end
            return
        end

        local step, steps = 0, 6

        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
            step = step + 1

            pcall(function() panel:alpha(1 - (step / steps)) end)

            if step >= steps then
                _devFadeTimers[key]:stop()
                _devFadeTimers[key] = nil

                if onDone then onDone() end
            end
        end)
    end

    function MsDevTools:pushMouseState(x, y)
        if not _keysPanel and not _shellActive() then return end

        local _x   = x or (_mousePos and _mousePos.x) or 0
        local _y   = y or (_mousePos and _mousePos.y) or 0
        local mode = _coordMode or "screen"
        local tx, ty = _x, _y

        if mode == "window" or mode == "windowTR" or mode == "windowBL"
            or mode == "windowBR" or mode == "windowCenter" or mode == "ref" then

            local win = ms.getTargetWin()

            if win then
                local f = win:frame()

                if mode == "window" then
                    tx = _x - f.x
                    ty = _y - f.y

                elseif mode == "windowTR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - f.y

                elseif mode == "windowBL" then
                    tx = _x - f.x
                    ty = _y - (f.y + f.h)

                elseif mode == "windowBR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - (f.y + f.h)

                elseif mode == "windowCenter" then
                    tx = _x - (f.x + f.w / 2)
                    ty = _y - (f.y + f.h / 2)

                elseif mode == "ref" then
                    tx = _x - f.x
                    ty = _y - f.y
                    tx = math.floor(tx * (1680 / f.w) + 0.5)
                    ty = math.floor(ty * (1044 / f.h) + 0.5)
                end
            end

        elseif mode == "screenCenter" then
            local sf = hs.screen.mainScreen():frame()

            tx = _x - math.floor(sf.w / 2)
            ty = _y - math.floor(sf.h / 2)
        end

        local j = string.format('{"x":%d,"y":%d}', math.floor(tx), math.floor(ty))

        pcall(function()
            _pushToPanel(_keysPanel, "keys", "updateMouseState(" .. j .. ")")
        end)
    end
-- END Panel Helpers --

-- Console Panel --
    function MsDevTools:_buildConsolePanel()
        local panel, ucCon, pos = _makeDevPanel("console", 360, 480, 20, 20)

        if not panel then return nil end

        ucCon:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "execute" and data.code then
                local fn, err = load("return " .. data.code)

                if not fn then fn, err = load(data.code) end

                if not fn then
                    self:_devWrite({
                        type = "error",
                        msg  = err or "syntax error",
                    })
                else
                    local res     = table.pack(pcall(fn))
                    local success = table.remove(res, 1)

                    if not success then
                        self:_devWrite({
                            type = "error",
                            msg  = tostring(res[1]),
                        })
                    elseif #res > 0 then
                        local parts = {}

                        for _, v in ipairs(res) do
                            parts[#parts + 1] = tostring(v)
                        end

                        self:_devWrite({
                            type = "result",
                            msg  = table.concat(parts, "\t"),
                        })
                    end
                end

            elseif data.action == "clear" then
                for _, cat in ipairs({
                    "console",
                    "error",
                    "system",
                }) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w")
                    if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w")
                    if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideConsole()

            elseif data.action == "openWatcher" then
                self:showWatcher()

            elseif data.action == "openKeys" then
                self:showKeys()

            elseif data.action == "dragStart" then
                _devDragStart(function() return _consolePanel end, _consolePanelPos)

            elseif data.action == "moveEnd" then
                _devDragEnd(function() return _consolePanel end)

            elseif data.action == "move" and _consolePanelPos then
                _consolePanelPos.x = _consolePanelPos.x + (data.dx or 0)
                _consolePanelPos.y = _consolePanelPos.y + (data.dy or 0)

                if _consolePanel then
                    pcall(function() _consolePanel:frame(_consolePanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _consolePanelPos = pos
        _setupDevPanelTheme(panel, "_themeConsole")

        if _htmlCache["console"] then
            panel:html(_htmlCache["console"], _devBase)
        end

        return panel
    end

    function MsDevTools:showConsole()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _consoleOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('console')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {
                    "console",
                    "error",
                    "system",
                }, "console", _consoleSkip)
            end)
            return
        end

        if not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

            if not _consolePanel then return end
        end

        _consoleOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        ms.safeShow(_consolePanel)

        pcall(function() _consolePanel:bringToFront(true) end)

        _devFadeIn(_consolePanel, "console")

        _devFadeTimers["_histConsole"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histConsole"] = nil
            if not _consolePanel or not _consoleOpen then return end

            _loadDevHistory(_consolePanel, {
                "console",
                "error",
                "system",
            }, nil, _consoleSkip)
        end)
    end

    function MsDevTools:hideConsole()
        _consoleOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _consolePanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_consolePanel, "console", function()
                if _consolePanel then _consolePanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleConsole()
        if _consoleOpen then
            self:hideConsole()
        else
            self:showConsole()
        end
    end
-- END Console Panel --

-- Watcher Panel --
    function MsDevTools:_buildWatcherPanel()
        local panel, ucWatcher, pos = _makeDevPanel("watcher", 360, 480, 50, 44)

        if not panel then return nil end

        ucWatcher:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                for _, cat in ipairs({
                    "macro",
                    "error",
                }) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w")
                    if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w")
                    if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideWatcher()

            elseif data.action == "dragStart" then
                _devDragStart(function() return _watcherPanel end, _watcherPanelPos)

            elseif data.action == "moveEnd" then
                _devDragEnd(function() return _watcherPanel end)

            elseif data.action == "move" and _watcherPanelPos then
                _watcherPanelPos.x = _watcherPanelPos.x + (data.dx or 0)
                _watcherPanelPos.y = _watcherPanelPos.y + (data.dy or 0)

                if _watcherPanel then
                    pcall(function() _watcherPanel:frame(_watcherPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _watcherPanelPos = pos
        _setupDevPanelTheme(panel, "_themeWatcher")

        if _htmlCache["watcher"] then
            panel:html(_htmlCache["watcher"], _devBase)
        end

        return panel
    end

    function MsDevTools:showWatcher()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _watcherOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('watcher')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {
                    "macro",
                    "error",
                }, "watcher")
            end)
            return
        end

        if not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

            if not _watcherPanel then return end
        end

        _watcherOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        ms.safeShow(_watcherPanel)

        pcall(function() _watcherPanel:bringToFront(true) end)

        _devFadeIn(_watcherPanel, "watcher")

        _devFadeTimers["_histWatcher"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histWatcher"] = nil
            if not _watcherPanel or not _watcherOpen then return end

            _loadDevHistory(_watcherPanel, {
                "macro",
                "error",
            })
        end)
    end

    function MsDevTools:hideWatcher()
        _watcherOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _watcherPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_watcherPanel, "watcher", function()
                if _watcherPanel then _watcherPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWatcher()
        if _watcherOpen then
            self:hideWatcher()
        else
            self:showWatcher()
        end
    end
-- END Watcher Panel --

-- Inputs Panel --
    function MsDevTools:_buildKeysPanel()
        local panel, ucKeys, pos = _makeDevPanel("keys", 360, 480, 80, 68)

        if not panel then return nil end

        ucKeys:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                local p = _catPaths["input"]
                if p then local f = io.open(p, "w")
                if f then f:close() end end

                local r = _readablePaths["input"]
                if r then local f = io.open(r, "w")
                if f then f:close() end end

            elseif data.action == "close" then
                self:hideKeys()

            elseif data.action == "ready" then
                if not _keysReady then
                    _keysReady = true

                    local _p = hs.mouse.absolutePosition()

                    _mousePos = {
                        x = math.floor(_p.x),
                        y = math.floor(_p.y),
                    }
                end

            elseif data.action == "setCoordMode" then
                _coordMode = data.mode or "screen"

                _devFadeTimers["_coordPush"] = hs.timer.doAfter(0.01, function()
                    _devFadeTimers["_coordPush"] = nil
                    if _keysPanel then
                        pcall(function() _pushMouseState() end)
                    end
                end)

            elseif data.action == "dragStart" then
                _devDragStart(function() return _keysPanel end, _keysPanelPos)

            elseif data.action == "moveEnd" then
                _devDragEnd(function() return _keysPanel end)

            elseif data.action == "move" and _keysPanelPos then
                _keysPanelPos.x = _keysPanelPos.x + (data.dx or 0)
                _keysPanelPos.y = _keysPanelPos.y + (data.dy or 0)

                if _keysPanel then
                    pcall(function() _keysPanel:frame(_keysPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        if not _htmlCache["keys"] then return nil end

        _keysPanelPos = pos
        _keysReady    = false

        local function keysOnReady()
            if not _keysReady then
                _keysReady = true

                local _p = hs.mouse.absolutePosition()

                _mousePos = {
                    x = math.floor(_p.x),
                    y = math.floor(_p.y),
                }
            end
        end

        _setupDevPanelTheme(panel, "_themeKeys", keysOnReady)

        panel:html(_htmlCache["keys"], _devBase)

        return panel
    end

    function MsDevTools:showKeys()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _keysOpen = true
            _keysReady = true
            ms.shell.show()
            ms.shell.eval("showPanel('keys')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {"input"}, "keys")
            end)
            return
        end

        if not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

            if not _keysPanel then return end
        end

        _keysOpen  = true
        _keysReady = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        ms.safeShow(_keysPanel)

        pcall(function() _keysPanel:bringToFront(true) end)

        _devFadeIn(_keysPanel, "keys")

        _devFadeTimers["_histKeys"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histKeys"] = nil
            if not _keysPanel or not _keysOpen then return end

            _loadDevHistory(_keysPanel, {"input"})

            pcall(function() _pushMouseState() end)
        end)

        if _mousePoller then _mousePoller:stop() end

        _mousePoller = hs.timer.doEvery(0.1, function()
            if not _keysPanel then
                if _mousePoller then
                    _mousePoller:stop()
                    _mousePoller = nil
                end

                return
            end

            local _p      = hs.mouse.absolutePosition()
            local _x, _y  = math.floor(_p.x), math.floor(_p.y)
            local prev    = _mousePos

            if not prev or _x ~= prev.x or _y ~= prev.y then
                _mousePos = {
                    x = _x,
                    y = _y,
                }

                _pushMouseState(_x, _y)
            end
        end)
    end

    function MsDevTools:hideKeys()
        if _mousePoller then
            _mousePoller:stop()
            _mousePoller = nil
        end

        _keysReady = false
        _keysOpen  = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _keysPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_keysPanel, "keys", function()
                if _keysPanel then _keysPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleKeys()
        if _keysOpen then
            self:hideKeys()
        else
            self:showKeys()
        end
    end

    function MsDevTools:stopAllPollers()
        if _mousePoller then _mousePoller:stop()
        _mousePoller = nil end
        if _shellMousePoller then _shellMousePoller:stop()
        _shellMousePoller = nil end
        self:_winEngineStop()
    end

    function MsDevTools:restartPollersIfActive()
        if _keysOpen and _keysPanel and not _mousePoller then
            _mousePoller = hs.timer.doEvery(0.1, function()
                if not _keysPanel then
                    if _mousePoller then _mousePoller:stop()
                    _mousePoller = nil end
                    return
                end
                local _p      = hs.mouse.absolutePosition()
                local _x, _y  = math.floor(_p.x), math.floor(_p.y)
                local prev    = _mousePos
                if not prev or _x ~= prev.x or _y ~= prev.y then
                    _mousePos = {
                        x = _x,
                        y = _y,
                    }
                    _pushMouseState(_x, _y)
                end
            end)
        end
        if _windowOpen and _activePanel == "window" then
            self:_winEngineStart()
        end
    end
-- END Inputs Panel --

-- Window Panel --
    local function _winG(fn) local ok, v = pcall(fn)
    if ok then return v end end

    function _winRead(win)
        if not win then return nil end
        local appObj = _winG(function() return win:application() end)
        local f = _winG(function() return win:frame() end)
        return {
            app        = appObj and _winG(function() return appObj:name() end) or nil,
            pid        = appObj and _winG(function() return appObj:pid() end) or nil,
            bundleID   = appObj and _winG(function() return appObj:bundleID() end) or nil,
            title      = _winG(function() return win:title() end),
            role       = _winG(function() return win:role() end),
            subrole    = _winG(function() return win:subrole() end),
            frame      = f and {
                x = math.floor(f.x),
                y = math.floor(f.y),
                w = math.floor(f.w),
                h = math.floor(f.h),
            } or nil,
            screen     = _winG(function()
                local s = win:screen()
                return s and s:name()
            end),
            id         = _winG(function() return win:id() end),
            standard   = _winG(function() return win:isStandard() end),
            minimized  = _winG(function() return win:isMinimized() end),
            fullscreen = _winG(function() return win:isFullscreen() end),
            visible    = _winG(function() return win:isVisible() end),
        }
    end

    local function _winReadLight(win)
        if not win then return nil end
        local f = _winG(function() return win:frame() end)
        return {
            frame      = f and {
                x = math.floor(f.x),
                y = math.floor(f.y),
                w = math.floor(f.w),
                h = math.floor(f.h),
            } or nil,
            standard   = _winG(function() return win:isStandard() end),
            minimized  = _winG(function() return win:isMinimized() end),
            fullscreen = _winG(function() return win:isFullscreen() end),
            visible    = _winG(function() return win:isVisible() end),
        }
    end

    function _winPush(fn, payload)
        local ok, j = pcall(hs.json.encode, payload)
        if ok then pcall(function() _pushToPanel(_windowPanel, "window", fn .. "(" .. j .. ")") end) end
    end

    local function _axStr(v)
        local t = type(v)
        if t == "string" then return #v > 120 and (v:sub(1, 120) .. "\u{2026}") or v end
        if t == "number" or t == "boolean" then return tostring(v) end
        return nil
    end

    local function _winStillOpen()
        if _windowPanel ~= nil then return _windowOpen end
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isPoppedOut and ms.shell.isPoppedOut("window") then
            return _windowOpen
        end
        if not (_windowOpen and _shellActive() and _activePanel == "window") then
            return false
        end
        local st = _G.ms and _G.ms._shellState
        return not (st and st.visible == false)
    end

    function MsDevTools:_winEngineStop()
        if _winAppWatcher then pcall(function() _winAppWatcher:stop() end)
        _winAppWatcher = nil end
        if _winUiWatcher  then pcall(function() _winUiWatcher:stop()  end)
        _winUiWatcher  = nil end
        if _winMonitor then _winMonitor:stop()
        _winMonitor = nil end
        _winElementInspect = false
    end

    function MsDevTools:setWinElementInspect(enabled)
        _winElementInspect = (enabled == true)
        if not _winElementInspect then _winLastMouse = nil end
    end

    function MsDevTools:_winEngineStart()
        self:_winEngineStop()
        _winDirty, _winMoveN, _winResizeN, _winLastMouse = false, 0, 0, nil
        _winElementTab = true
        local _winLastFullState = nil

        local _winLastWin = nil

        local function _winSubject()
            local w = hs.window.focusedWindow()
            if w then _winLastWin = w
            return w end
            return _winLastWin
        end

        local function pushState(win, light)
            local st
            if win then _winLastWin = win end
            if light then
                st = _winReadLight(win or _winSubject())
                if st and _winLastFullState then
                    for k, v in pairs(_winLastFullState) do
                        if st[k] == nil then st[k] = v end
                    end
                end
            else
                st = _winRead(win or _winSubject())
                _winLastFullState = st
            end
            if st then _winPush("updateCurrentWindow", st) end
            return st
        end

        local function watchApp(app)
            if _winUiWatcher then pcall(function() _winUiWatcher:stop() end)
            _winUiWatcher = nil end
            if not app then _winWatchedAppName = nil
            return end
            _winWatchedAppName = _winG(function() return app:name() end)
            _winUiWatcher = _winG(function()
                local w = app:newWatcher(function(el, ev)
                    if _G.ms and _G.ms._shellDragging then return end
                    if ev == hs.uielement.watcher.windowMinimized then
                        _winPendingEvent = {
                            type = "minimize",
                            app = _winWatchedAppName,
                            win = _winG(function() return el:asHSWindow() end) }
                    elseif ev == hs.uielement.watcher.windowUnminimized then
                        _winPendingEvent = {
                            type = "unminimize",
                            app = _winWatchedAppName,
                            win = _winG(function() return el:asHSWindow() end) }
                    elseif ev == hs.uielement.watcher.windowResized then
                        _winResizeN = _winResizeN + 1
                    else
                        _winMoveN = _winMoveN + 1
                    end
                    _winDirty = true
                end)
                w:start({
                    hs.uielement.watcher.windowMoved,
                    hs.uielement.watcher.windowResized,
                    hs.uielement.watcher.windowCreated,
                    hs.uielement.watcher.mainWindowChanged,
                    hs.uielement.watcher.windowMinimized,
                    hs.uielement.watcher.windowUnminimized,
                })
                return w
            end)
        end

        _winAppWatcher = hs.application.watcher.new(function(_, ev, app)
            if not _winStillOpen() then self:_winEngineStop()
            return end
            if ev == hs.application.watcher.activated then
                local st = pushState()
                if st then
                    self:_pushWindowEvent({
                        type = "focus",
                        ts = os.date("%H:%M:%S"),
                        app = st.app,
                        title = st.title,
                    })
                end
                watchApp(app)
            elseif ev == hs.application.watcher.hidden or ev == hs.application.watcher.unhidden then
                local nm = _winG(function() return app:name() end)
                self:_pushWindowEvent({
                    type = ev == hs.application.watcher.hidden and "hide" or "show",
                    ts = os.date("%H:%M:%S"),
                    app = nm,
                })
                pushState(_winG(function() return app:mainWindow() end))
            end
        end)
        pcall(function() _winAppWatcher:start() end)

        _winMonitor = hs.timer.doEvery(0.2, function()
            if not _winStillOpen() then self:_winEngineStop()
            return end
            if _G.ms and _G.ms._shellDragging then return end

            local payload = {}
            local hasData = false

            if _winDirty then
                _winDirty = false
                local st = _winReadLight(
                    (_winPendingEvent and _winPendingEvent.win) or _winSubject()
                )
                if st and _winLastFullState then
                    for k, v in pairs(_winLastFullState) do
                        if st[k] == nil then st[k] = v end
                    end
                end
                if st then
                    payload.window = st
                    hasData = true
                end
                local f = st and st.frame
                local events = {}
                if _winPendingEvent then
                    local entry = {
                        type = _winPendingEvent.type,
                        ts = os.date("%H:%M:%S"),
                        app = _winPendingEvent.app }
                    table.insert(_windowHistory, entry)
                    if #_windowHistory > _windowMaxHistory then table.remove(_windowHistory, 1) end
                    table.insert(events, entry)
                    _winPendingEvent = nil
                end
                if _winMoveN > 0 then
                    local entry = {
                        type = "move",
                        ts = os.date("%H:%M:%S"),
                        count = _winMoveN,
                        x = f and f.x or nil,
                        y = f and f.y or nil,
                    }
                    table.insert(_windowHistory, entry)
                    if #_windowHistory > _windowMaxHistory then table.remove(_windowHistory, 1) end
                    table.insert(events, entry)
                    _winMoveN = 0
                end
                if _winResizeN > 0 then
                    local entry = {
                        type = "resize",
                        ts = os.date("%H:%M:%S"),
                        count = _winResizeN,
                        w = f and f.w or nil,
                        h = f and f.h or nil,
                    }
                    table.insert(_windowHistory, entry)
                    if #_windowHistory > _windowMaxHistory then table.remove(_windowHistory, 1) end
                    table.insert(events, entry)
                    _winResizeN = 0
                end
                if #events > 0 then
                    payload.events = events
                    hasData = true
                end
            end

            if _winElementInspect and _winElementTab and hs.accessibilityState() then
                local p = hs.mouse.absolutePosition()
                local _now = hs.timer.secondsSinceEpoch()
                local _stationaryDue = (not _winLastInspectAt) or (_now - _winLastInspectAt) >= 0.5
                if _stationaryDue or not (_winLastMouse and p.x == _winLastMouse.x and p.y == _winLastMouse.y) then
                    _winLastMouse = p
                    _winLastInspectAt = _now
                    -- Shared sampler (ms.screen.sampleAt) is the single source of
                    -- truth so inspect and macro pixelColor can never drift apart.
                    local pixel = _winG(function()
                        return ms.screen and ms.screen.sampleAt
                           and ms.screen.sampleAt(p.x, p.y) or nil
                    end)
                    local win = hs.window.focusedWindow()
                    local wf = win and _winG(function() return win:frame() end)
                    payload.mouse = {
                        sx = math.floor(p.x),
                        sy = math.floor(p.y),
                        wx = wf and math.floor(p.x - wf.x) or nil,
                        wy = wf and math.floor(p.y - wf.y) or nil,
                        pixel = pixel,
                    }
                    local el = _winG(function() return hs.axuielement.systemElementAtPosition(p.x, p.y) end)
                    if el then
                        local function ga(a) return _axStr(_winG(function() return el:attributeValue(a) end)) end
                        local fr = _winG(function() return el:attributeValue("AXFrame") end)
                        local frame
                        if type(fr) == "table" and fr.x then
                            frame = {
                                x = math.floor(fr.x),
                                y = math.floor(fr.y),
                                w = math.floor(fr.w),
                                h = math.floor(fr.h),
                            }
                        end
                        payload.element = {
                            axPermission    = true,
                            role            = ga("AXRole"),
                            roleDescription = ga("AXRoleDescription"),
                            title           = ga("AXTitle"),
                            value           = ga("AXValue"),
                            identifier      = ga("AXIdentifier"),
                            frame           = frame,
                        }
                    end
                    hasData = true
                end
            end

            if hasData then
                _winPush("updateAll", payload)
            end
        end)

        if not hs.accessibilityState() then
            _winPush("updateElement", { axPermission = false })
        end

        hs.timer.doAfter(0.02, function()
            if not _winStillOpen() then return end
            local win = hs.window.focusedWindow()
            pushState(win)
            if win then watchApp(_winG(function() return win:application() end)) end
        end)
        hs.timer.doAfter(0.2, function()
            if _winStillOpen() then pushState() end
        end)
    end

    function MsDevTools:_pushWindowEvent(entry)
        table.insert(_windowHistory, entry)

        if #_windowHistory > _windowMaxHistory then
            table.remove(_windowHistory, 1)
        end

        if _windowPanel or _shellActive() then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _pushToPanel(_windowPanel, "window", "appendEntry(" .. j .. ")")
                end)
            end
        end
    end

    function MsDevTools:_buildWindowPanel()
        local panel, ucWindow, pos = _makeDevPanel("window", 360, 480, 110, 68)

        if not panel then return nil end

        ucWindow:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                _windowHistory = {}

            elseif data.action == "close" then
                self:hideWindow()

            elseif data.action == "dragStart" then
                _devDragStart(function() return _windowPanel end, _windowPanelPos)

            elseif data.action == "moveEnd" then
                _devDragEnd(function() return _windowPanel end)

            elseif data.action == "move" and _windowPanelPos then
                _windowPanelPos.x = _windowPanelPos.x + (data.dx or 0)
                _windowPanelPos.y = _windowPanelPos.y + (data.dy or 0)

                if _windowPanel then
                    pcall(function() _windowPanel:frame(_windowPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _windowPanelPos = pos
        _setupDevPanelTheme(panel, "_themeWindow")

        if _htmlCache["window"] then
            panel:html(_htmlCache["window"], _devBase)
        end

        _devFadeTimers["_histWindow"] = hs.timer.doAfter(0.05, function()
            _devFadeTimers["_histWindow"] = nil
            if not _windowPanel then return end

            if #_windowHistory > 0 then
                local ok, j = pcall(hs.json.encode, _windowHistory)
                if ok then
                    pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end)
                end
            end

            local st = _winRead(hs.window.focusedWindow())
            if st then
                local ok2, j2 = pcall(hs.json.encode, st)
                if ok2 then
                    pcall(function() panel:evaluateJavaScript("updateCurrentWindow(" .. j2 .. ")") end)
                end
            end
        end)

        return panel
    end

    function MsDevTools:showWindow()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _windowOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('window')")
            hs.timer.doAfter(0.15, function()
                if #_windowHistory > 0 then
                    local ok, j = pcall(hs.json.encode, _windowHistory)
                    if ok then
                        pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end)
                    end
                end
                _winPush("updateCurrentWindow", _winRead(hs.window.focusedWindow()))
            end)
            self:_winEngineStart()
            return
        end

        if not _windowPanel then
            _windowPanel = self:_buildWindowPanel()

            if not _windowPanel then return end
        end

        _windowOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        ms.safeShow(_windowPanel)

        pcall(function() _windowPanel:bringToFront(true) end)

        _devFadeIn(_windowPanel, "window")

        self:_winEngineStart()
    end

    function MsDevTools:hideWindow()
        self:_winEngineStop()
        if _windowPoller then
            _windowPoller:stop()
            _windowPoller = nil
        end

        _windowOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _windowPanel then
            ms.playSlot("settingsClose")

            local panel = _windowPanel

            _windowPanel = nil

            _devFadeOut(panel, "window", function()
                if panel then panel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWindow()
        if _windowOpen then
            self:hideWindow()
        else
            self:showWindow()
        end
    end
-- END Window Panel --

-- Prewarm --
    function MsDevTools:prewarm()
        if not _consolePanel then _consolePanel = self:_buildConsolePanel() end
        if not _watcherPanel then _watcherPanel = self:_buildWatcherPanel() end
        if not _keysPanel    then _keysPanel    = self:_buildKeysPanel() end
        if not _windowPanel  then _windowPanel  = self:_buildWindowPanel() end
    end

    function MsDevTools:recolor()
        local js = _devThemeJS()
        if js == "" then return end
        if _consolePanel then pcall(function() _consolePanel:evaluateJavaScript(js) end) end
        if _watcherPanel then pcall(function() _watcherPanel:evaluateJavaScript(js) end) end
        if _keysPanel    then pcall(function() _keysPanel:evaluateJavaScript(js) end) end
        if _windowPanel  then pcall(function() _windowPanel:evaluateJavaScript(js) end) end
    end

    -- Apply a new UI zoom to every open popout: rescale its frame by `ratio`
    -- (so apparent content size holds and nothing clips), clamped to the
    -- zoom-scaled popout minimum, then set CSS zoom via applyZoom(z).
    function MsDevTools:rezoom(z, ratio, noRescale)
        z = tonumber(z) or 1.0
        ratio = tonumber(ratio) or 1.0
        local minW = (ms._popBaseMin and ms._popBaseMin.w or 460) * z
        local minH = (ms._popBaseMin and ms._popBaseMin.h or 320) * z
        local js = "if(window.applyZoom)applyZoom(" .. z .. ")"
        local function apply(panel)
            if not panel then return end
            if not noRescale and math.abs(ratio - 1) > 0.001 then
                pcall(function()
                    local f = panel:frame()
                    local nf = { x = f.x, y = f.y,
                                 w = f.w * ratio, h = f.h * ratio }
                    if nf.w < minW then nf.w = minW end
                    if nf.h < minH then nf.h = minH end
                    panel:frame(nf)
                end)
            end
            pcall(function() panel:evaluateJavaScript(js) end)
        end
        apply(_consolePanel)
        apply(_watcherPanel)
        apply(_keysPanel)
        apply(_windowPanel)
    end

    function MsDevTools:prewarmStep(which)
        if     which == "console" and not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

        elseif which == "watcher" and not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

        elseif which == "keys" and not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

        elseif which == "window" and not _windowPanel then
            _windowPanel = self:_buildWindowPanel()
        end
    end

    function MsDevTools:step(msg)
        local entry = {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = tostring(msg or ""),
        }

        self:log(entry)

        if _watcherPanel or _shellActive() then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
                end)
            end
        end
    end
-- END Prewarm --

-- Public Accessors --
    function MsDevTools:getPanel(name)
        if     name == "console" then return _consolePanel
        elseif name == "watcher" then return _watcherPanel
        elseif name == "keys"    then return _keysPanel
        elseif name == "window"  then return _windowPanel
        end
    end
-- END Public Accessors --

return MsDevTools

end

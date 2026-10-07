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
    local S = {}

    local _home       = os.getenv("HOME")
    local _devLogDir  = _home .. "/Documents/"
    local _devBaseDir = _devLogDir .. "ms_dev_logs/"
    local _devBase    = "file://" .. _home .. "/.hammerspoon/ui/"

    local _jsonDir, _readDir

    local function _archDir()
        return ms.backups.dir("logs")
    end

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

        local catPath = S.readablePaths and S.readablePaths[_lastReadCategory]

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

    S.axTimeoutSet = false
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
    S.winElementTab = true
    S.winElementInspect = false

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

        S.catPaths = {}
        S.readablePaths = {}

        for _, cat in ipairs({
            "input",
            "macro",
            "system",
            "error",
            "console",
        }) do
            S.catPaths[cat]      = _jsonDir .. "ms_dev_" .. cat .. ".log"
            S.readablePaths[cat] = _readDir .. "ms_dev_" .. cat .. ".txt"
        end

        self:_archiveOnReload()

        S.activeKeys       = {}
        S.activeButtons    = {}
        S.coordMode        = "screen"
        S.keysReady        = false
        S.windowHistory    = {}
        S.windowLast       = nil
        S.windowMaxHistory = 80
    end

    function MsDevTools:start()
        if not ms then return end
        if ms.checkGuardian and not ms.checkGuardian("MsDevTools") then return end

        if not S.axTimeoutSet then
            S.axTimeoutSet = pcall(function()
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
            _activeKeys      = S.activeKeys,
            _activeButtons   = S.activeButtons,
            _coordMode       = S.coordMode,
            _keysReady       = false,
        }

        setmetatable(ms.dev, {
            __index = function(t, k)
                if     k == "_consolePanel" then return S.consolePanel
                elseif k == "_watcherPanel" then return S.watcherPanel
                elseif k == "_keysPanel"    then return S.keysPanel
                elseif k == "_keysReady"    then return S.keysReady
                elseif k == "_consoleOpen"  then return S.consoleOpen
                elseif k == "_watcherOpen"  then return S.watcherOpen
                elseif k == "_keysOpen"     then return S.keysOpen
                elseif k == "_windowOpen"   then return S.windowOpen
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
            return S.keysPanel or _shellActive() or _logEnabled.keys
        end
        ms.dev._wantsKeyEvents = function()
            return S.keysPanel or _shellActive() or _logEnabled.keys
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
        S.pushMouseState = ms.dev._pushMouseState

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
        -- (S.catPaths/S.readablePaths/_HIST_MAX/_pushToPanel) are themselves file-level.
        function S.loadDevHistory(panel, categories, shellPanelId, skipEvents)
            local entries = {}
            -- Insertion order per entry, so the merge below is a *stable* sort:
            -- entries sharing a timestamp keep their real arrival order instead
            -- of being shuffled by table.sort (which is not stable).
            local order = {}
            for _, cat in ipairs(categories) do
                local path = S.catPaths[cat]
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
                        local p = S.catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end
                        local r = S.readablePaths[cat]
                        if r then local f = io.open(r, "w")
                        if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ackDanger" then
                    ms._consoleDangerAck = true
                    if ms.saveSettings then ms.saveSettings() end
                elseif action == "ready" then
                    S.loadDevHistory(nil, {
                        "console",
                        "error",
                        "system",
                    }, "console", _consoleSkip)
                    _pushToPanel(S.consolePanel, "console",
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
                        local p = S.catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end
                        local r = S.readablePaths[cat]
                        if r then local f = io.open(r, "w")
                        if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    S.loadDevHistory(nil, {
                        "macro",
                        "error",
                    }, "watcher")
                end
            end)

            ms.bus.on("ui:keys:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    local p = S.catPaths["input"]
                    if p then local f = io.open(p, "w")
                    if f then f:close() end end
                    local r = S.readablePaths["input"]
                    if r then local f = io.open(r, "w")
                    if f then f:close() end end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    if not S.keysReady then
                        S.keysReady = true
                        local _p = hs.mouse.absolutePosition()
                        S.mousePos = {
                            x = math.floor(_p.x),
                            y = math.floor(_p.y),
                        }
                    end
                    S.loadDevHistory(nil, {"input"}, "keys")
                elseif action == "setCoordMode" then
                    S.coordMode = body.mode or "screen"
                end
            end)

            ms.bus.on("ui:window:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    S.windowHistory = {}
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "tab" then
                    S.winElementTab = (body.tab == "window")
                    if S.winElementTab then S.winLastMouse = nil end
                elseif action == "setInspect" then
                    S.winElementInspect = (body.enabled == true)
                    if not S.winElementInspect then S.winLastMouse = nil end
                elseif action == "ready" then
                    hs.timer.doAfter(0.05, function()
                        if S.windowOpen then
                            local st = S.winRead(hs.window.focusedWindow())
                            if st then S.winPush("updateCurrentWindow", st) end
                            if #S.windowHistory > 0 then
                                local ok, j = pcall(hs.json.encode, S.windowHistory)
                                if ok then pcall(function()
                                    _pushToPanel(S.windowPanel, "window", "loadHistory(" .. j .. ")")
                                end) end
                            end
                        end
                    end)
                end
            end)

            ms.bus.on("panel:poppedOut", function(_, body)
                if not body or body.id ~= "window" then return end
                S.windowOpen = true
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
                    local prevCh = _panelToChannel[S.activePanel]
                    if prevCh then _logEnabled[prevCh] = false end
                    local newCh = _panelToChannel[p]
                    if newCh then _logEnabled[newCh] = true end
                end

                S.activePanel = p
                if p ~= "window"
                    and not (ms.shell and ms.shell.isPoppedOut and ms.shell.isPoppedOut("window")) then
                    S.winElementTab = false
                    self:_winEngineStop()
                end
                if p == "console" then
                    S.consoleOpen = true
                    hs.timer.doAfter(0.1, function()
                        S.loadDevHistory(nil, {
                            "console",
                            "error",
                            "system",
                        }, "console", _consoleSkip)
                    end)
                elseif p == "watcher" then
                    S.watcherOpen = true
                    hs.timer.doAfter(0.1, function()
                        S.loadDevHistory(nil, {
                            "macro",
                            "error",
                        }, "watcher")
                    end)
                elseif p == "keys" then
                    if not S.keysReady then S.keysReady = true end
                    hs.timer.doAfter(0.1, function()
                        S.loadDevHistory(nil, {"input"}, "keys")
                    end)
                    if not _octaneActive then
                        if S.shellMousePoller then S.shellMousePoller:stop() end
                        S.shellMousePoller = hs.timer.doEvery(0.08, function()
                        if not _shellActive() then
                            if S.shellMousePoller then S.shellMousePoller:stop()
                            S.shellMousePoller = nil end
                            return
                        end
                        if S.activePanel ~= "keys" then return end
                        local _sst = _G.ms and _G.ms._shellState
                        if _sst and _sst.visible == false then return end
                        local _p = hs.mouse.absolutePosition()
                        local _x, _y = math.floor(_p.x), math.floor(_p.y)
                        local prev = S.mousePos
                        if not prev or _x ~= prev.x or _y ~= prev.y then
                            S.mousePos = {
                                x = _x,
                                y = _y,
                            }
                            pcall(function() S.pushMouseState(_x, _y) end)
                        end
                    end)
                    end
                elseif p == "window" then
                    S.windowOpen = true
                    hs.timer.doAfter(0.15, function()
                        if #S.windowHistory > 0 then
                            local ok, j = pcall(hs.json.encode, S.windowHistory)
                            if ok then pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end) end
                        end
                    end)
                    if not _octaneActive then
                        self:_winEngineStart()
                    end
                end
            end)

            ms.bus.on("macroLab:toggled", function(_, body)
                if body and body.visible and S.activePanel == "window" and S.windowOpen
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
                    local ch = _panelToChannel[S.activePanel]
                    if ch then _logEnabled[ch] = false end
                end
            end)
        end
    end
-- END Lifecycle --

-- Archive Helpers --
    function MsDevTools:_archiveLog(path, stamp, subdir)
        if not hs.fs.attributes(path) then return end

        local sessionDir = _archDir() .. "session_" .. stamp .. "/"
        local destDir    = sessionDir .. subdir .. "/"

        hs.fs.mkdir(_devBaseDir)
        hs.fs.mkdir(_archDir())
        hs.fs.mkdir(sessionDir)
        hs.fs.mkdir(destDir)

        local filename = path:match("([^/]+)$")

        if filename then
            os.rename(path, destDir .. filename)
        end
    end

    function MsDevTools:_pruneSessionArchives(limit)
        if not hs.fs.attributes(_archDir()) then return end

        local list = {}

        for name in hs.fs.dir(_archDir()) do
            if name:match("^session_%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d$") then
                table.insert(list, name)
            end
        end

        table.sort(list)

        local pruned = 0

        while #list > limit and pruned < 5 do
            local dir = _archDir() .. list[1]

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

        for _, p in pairs(S.catPaths) do
            self:_archiveLog(p, stamp, "json")
        end

        for _, p in pairs(S.readablePaths) do
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

        local catPath = S.catPaths[entry.category]

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

        local readPath = S.readablePaths[entry.category]

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

        if (S.consolePanel or _shellActive()) and _logEnabled.console and t ~= "mousemove" and t ~= "step" then
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
                    _pushToPanel(S.consolePanel, "console", "appendEntry(" .. json .. ")")
                end)
            end
        end

        if (S.watcherPanel or _shellActive()) and _logEnabled.watcher and (t == "macro" or t == "error" or t == "sound") then
            pcall(function()
                _pushToPanel(S.watcherPanel, "watcher", "appendEntry(" .. json .. ")")
            end)
        end

        if (S.keysPanel or _shellActive()) and _logEnabled.keys and S.keysReady
            and (t == "key" or t == "mouse" or t == "scroll" or t == "mousemove") then
            pcall(function()
                _pushToPanel(S.keysPanel, "keys", "appendEntry(" .. json .. ")")
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
            S.activeKeys[keyCode] = keyName or tostring(keyCode)
        else
            S.activeKeys[keyCode] = nil
        end

        if S.keysPanel or _shellActive() then
            local active = {}

            for code, name in pairs(S.activeKeys) do
                table.insert(active, {
                    name = name,
                    code = code,
                })
            end

            local aok, aj = pcall(hs.json.encode, active)

            if aok then
                pcall(function()
                    _pushToPanel(S.keysPanel, "keys", "updateActiveKeys(" .. aj .. ")")
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
            S.activeButtons[button] = true
        else
            S.activeButtons[button] = nil
        end

        if (S.keysPanel or _shellActive()) and S.keysReady then
            local active = {}

            for btn in pairs(S.activeButtons) do
                table.insert(active, btn)
            end

            local aok, aj = pcall(hs.json.encode, {
                x       = x,
                y       = y,
                buttons = active,
            })

            if aok then
                pcall(function()
                    _pushToPanel(S.keysPanel, "keys", "updateMouseState(" .. aj .. ")")
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
        if not S.watcherPanel then return end

        local displayLabel = _buildDisplayLabel(label)
        if not displayLabel then return end

        local ok, j = pcall(hs.json.encode, {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = "[" .. displayLabel .. "] " .. msg,
        })

        if ok then
            pcall(function()
                _pushToPanel(S.watcherPanel, "watcher", "appendEntry(" .. j .. ")")
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
        if S.watcherPanel then self:watcherStep(msg, label) end
        self:macroLog(msg, label)
    end

    function MsDevTools:accWait(duration, label)
        if _traceSuppress then return end
        local msg = "wait " .. (tonumber(duration) or 0) .. "ms"
        if S.watcherPanel then self:watcherStep(msg, label) end
        self:macroLog(msg, label)
    end

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

        local h = _handleFor(_readHandles, S.readablePaths and S.readablePaths["macro"])
        if h then
            for _, line in ipairs(st.buffer) do
                h:write(line .. "\n")
            end
            h:flush()
        end

        if S.watcherPanel then
            for _, line in ipairs(st.buffer) do
                local ok, j = pcall(hs.json.encode, {
                    type = "step",
                    ts   = os.date("%H:%M:%S"),
                    msg  = line,
                })

                if ok then
                    pcall(function()
                        _pushToPanel(S.watcherPanel, "watcher", "appendEntry(" .. j .. ")")
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

-- Submodules --
    local ctx = {
        S = S,
        MsDevTools = MsDevTools,
        home = _home,
        devBase = _devBase,
        pushToPanel = _pushToPanel,
        shellActive = _shellActive,
        devDragStart = _devDragStart,
        devDragEnd = _devDragEnd,
        devFadeTimers = _devFadeTimers,
        htmlCache = _htmlCache,
        consoleSkip = _consoleSkip,
    }

    for _, name in ipairs({
        "panel_kit",
        "panels",
        "window",
    }) do
        package.loaded["lib.devtools." .. name] = nil
        require("lib.devtools." .. name)(ms, ctx)
    end
-- END Submodules --

return MsDevTools

end

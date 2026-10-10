return function(ms, ctx)
    -- Context --
        local S = ctx.S

        local MsDevTools = ctx.MsDevTools

        local _devBase = ctx.devBase

        local _htmlCache = ctx.htmlCache

        local _devFadeTimers = ctx.devFadeTimers

        local _devDragStart = ctx.devDragStart

        local _devDragEnd = ctx.devDragEnd

        local _makeDevPanel = ctx.makeDevPanel

        local _setupDevPanelTheme = ctx.setupDevPanelTheme

        local _devFadeIn = ctx.devFadeIn

        local _devFadeOut = ctx.devFadeOut

        local _consoleSkip = ctx.consoleSkip
    -- END Context --

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
                        local p = S.catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end

                        local r = S.readablePaths[cat]
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
                    _devDragStart(function() return S.consolePanel end, S.consolePanelPos)

                elseif data.action == "moveEnd" then
                    _devDragEnd(function() return S.consolePanel end)

                elseif data.action == "move" and S.consolePanelPos then
                    S.consolePanelPos.x = S.consolePanelPos.x + (data.dx or 0)
                    S.consolePanelPos.y = S.consolePanelPos.y + (data.dy or 0)

                    if S.consolePanel then
                        pcall(function() S.consolePanel:frame(S.consolePanelPos) end)
                    end

                elseif data.action == "playSlot" and data.slot then
                    ms.playSlot(data.slot)
                end
            end)

            S.consolePanelPos = pos
            _setupDevPanelTheme(panel, "_themeConsole")

            if _htmlCache["console"] then
                panel:html(_htmlCache["console"], _devBase)
            end

            return panel
        end

        function MsDevTools:showConsole()
            local ms = _G.ms
            if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
                S.consoleOpen = true
                ms.shell.show()
                ms.shell.eval("showPanel('console')")
                hs.timer.doAfter(0.15, function()
                    S.loadDevHistory(nil, {
                        "console",
                        "error",
                        "system",
                    }, "console", _consoleSkip)
                end)
                return
            end

            if not S.consolePanel then
                S.consolePanel = self:_buildConsolePanel()

                if not S.consolePanel then return end
            end

            S.consoleOpen = true

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            ms.playSlot("settingsOpen")

            ms.safeShow(S.consolePanel)

            pcall(function() S.consolePanel:bringToFront(true) end)

            _devFadeIn(S.consolePanel, "console")

            _devFadeTimers["_histConsole"] = hs.timer.doAfter(0.1, function()
                _devFadeTimers["_histConsole"] = nil
                if not S.consolePanel or not S.consoleOpen then return end

                S.loadDevHistory(S.consolePanel, {
                    "console",
                    "error",
                    "system",
                }, nil, _consoleSkip)
            end)
        end

        function MsDevTools:hideConsole()
            S.consoleOpen = false

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            if S.consolePanel then
                ms.playSlot("settingsClose")

                _devFadeOut(S.consolePanel, "console", function()
                    if S.consolePanel then S.consolePanel:hide() end
                end)
            end
        end

        function MsDevTools:toggleConsole()
            if S.consoleOpen then
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
                        local p = S.catPaths[cat]
                        if p then local f = io.open(p, "w")
                        if f then f:close() end end

                        local r = S.readablePaths[cat]
                        if r then local f = io.open(r, "w")
                        if f then f:close() end end
                    end

                elseif data.action == "close" then
                    self:hideWatcher()

                elseif data.action == "dragStart" then
                    _devDragStart(function() return S.watcherPanel end, S.watcherPanelPos)

                elseif data.action == "moveEnd" then
                    _devDragEnd(function() return S.watcherPanel end)

                elseif data.action == "move" and S.watcherPanelPos then
                    S.watcherPanelPos.x = S.watcherPanelPos.x + (data.dx or 0)
                    S.watcherPanelPos.y = S.watcherPanelPos.y + (data.dy or 0)

                    if S.watcherPanel then
                        pcall(function() S.watcherPanel:frame(S.watcherPanelPos) end)
                    end

                elseif data.action == "playSlot" and data.slot then
                    ms.playSlot(data.slot)
                end
            end)

            S.watcherPanelPos = pos
            _setupDevPanelTheme(panel, "_themeWatcher")

            if _htmlCache["watcher"] then
                panel:html(_htmlCache["watcher"], _devBase)
            end

            return panel
        end

        function MsDevTools:showWatcher()
            local ms = _G.ms
            if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
                S.watcherOpen = true
                ms.shell.show()
                ms.shell.eval("showPanel('watcher')")
                hs.timer.doAfter(0.15, function()
                    S.loadDevHistory(nil, {
                        "macro",
                        "error",
                    }, "watcher")
                end)
                return
            end

            if not S.watcherPanel then
                S.watcherPanel = self:_buildWatcherPanel()

                if not S.watcherPanel then return end
            end

            S.watcherOpen = true

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            ms.playSlot("settingsOpen")

            ms.safeShow(S.watcherPanel)

            pcall(function() S.watcherPanel:bringToFront(true) end)

            _devFadeIn(S.watcherPanel, "watcher")

            _devFadeTimers["_histWatcher"] = hs.timer.doAfter(0.1, function()
                _devFadeTimers["_histWatcher"] = nil
                if not S.watcherPanel or not S.watcherOpen then return end

                S.loadDevHistory(S.watcherPanel, {
                    "macro",
                    "error",
                })
            end)
        end

        function MsDevTools:hideWatcher()
            S.watcherOpen = false

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            if S.watcherPanel then
                ms.playSlot("settingsClose")

                _devFadeOut(S.watcherPanel, "watcher", function()
                    if S.watcherPanel then S.watcherPanel:hide() end
                end)
            end
        end

        function MsDevTools:toggleWatcher()
            if S.watcherOpen then
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
                    local p = S.catPaths["input"]
                    if p then local f = io.open(p, "w")
                    if f then f:close() end end

                    local r = S.readablePaths["input"]
                    if r then local f = io.open(r, "w")
                    if f then f:close() end end

                elseif data.action == "close" then
                    self:hideKeys()

                elseif data.action == "ready" then
                    if not S.keysReady then
                        S.keysReady = true

                        local _p = hs.mouse.absolutePosition()

                        S.mousePos = {
                            x = math.floor(_p.x),
                            y = math.floor(_p.y),
                        }
                    end

                elseif data.action == "setCoordMode" then
                    S.coordMode = data.mode or "screen"

                    _devFadeTimers["_coordPush"] = hs.timer.doAfter(0.01, function()
                        _devFadeTimers["_coordPush"] = nil
                        if S.keysPanel then
                            pcall(function() S.pushMouseState() end)
                        end
                    end)

                elseif data.action == "dragStart" then
                    _devDragStart(function() return S.keysPanel end, S.keysPanelPos)

                elseif data.action == "moveEnd" then
                    _devDragEnd(function() return S.keysPanel end)

                elseif data.action == "move" and S.keysPanelPos then
                    S.keysPanelPos.x = S.keysPanelPos.x + (data.dx or 0)
                    S.keysPanelPos.y = S.keysPanelPos.y + (data.dy or 0)

                    if S.keysPanel then
                        pcall(function() S.keysPanel:frame(S.keysPanelPos) end)
                    end

                elseif data.action == "playSlot" and data.slot then
                    ms.playSlot(data.slot)
                end
            end)

            if not _htmlCache["keys"] then return nil end

            S.keysPanelPos = pos
            S.keysReady    = false

            local function keysOnReady()
                if not S.keysReady then
                    S.keysReady = true

                    local _p = hs.mouse.absolutePosition()

                    S.mousePos = {
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
                S.keysOpen = true
                S.keysReady = true
                ms.shell.show()
                ms.shell.eval("showPanel('keys')")
                hs.timer.doAfter(0.15, function()
                    S.loadDevHistory(nil, {"input"}, "keys")
                end)
                return
            end

            if not S.keysPanel then
                S.keysPanel = self:_buildKeysPanel()

                if not S.keysPanel then return end
            end

            S.keysOpen  = true
            S.keysReady = true

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            ms.playSlot("settingsOpen")

            ms.safeShow(S.keysPanel)

            pcall(function() S.keysPanel:bringToFront(true) end)

            _devFadeIn(S.keysPanel, "keys")

            _devFadeTimers["_histKeys"] = hs.timer.doAfter(0.1, function()
                _devFadeTimers["_histKeys"] = nil
                if not S.keysPanel or not S.keysOpen then return end

                S.loadDevHistory(S.keysPanel, {"input"})

                S.pushInputState(S.keysPanel)

                pcall(function() S.pushMouseState() end)
            end)

            if S.mousePoller then S.mousePoller:stop() end

            S.mousePoller = hs.timer.doEvery(0.1, function()
                if not S.keysPanel then
                    if S.mousePoller then
                        S.mousePoller:stop()
                        S.mousePoller = nil
                    end

                    return
                end

                local _p      = hs.mouse.absolutePosition()
                local _x, _y  = math.floor(_p.x), math.floor(_p.y)
                local prev    = S.mousePos

                if not prev or _x ~= prev.x or _y ~= prev.y then
                    S.mousePos = {
                        x = _x,
                        y = _y,
                    }

                    S.pushMouseState(_x, _y)
                end
            end)
        end

        function MsDevTools:hideKeys()
            if S.mousePoller then
                S.mousePoller:stop()
                S.mousePoller = nil
            end

            S.keysReady = false
            S.keysOpen  = false

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            if S.keysPanel then
                ms.playSlot("settingsClose")

                _devFadeOut(S.keysPanel, "keys", function()
                    if S.keysPanel then S.keysPanel:hide() end
                end)
            end
        end

        function MsDevTools:toggleKeys()
            if S.keysOpen then
                self:hideKeys()
            else
                self:showKeys()
            end
        end

        function MsDevTools:stopAllPollers()
            if S.mousePoller then S.mousePoller:stop()
            S.mousePoller = nil end
            if S.shellMousePoller then S.shellMousePoller:stop()
            S.shellMousePoller = nil end
            self:_winEngineStop()
        end

        function MsDevTools:restartPollersIfActive()
            if S.keysOpen and S.keysPanel and not S.mousePoller then
                S.mousePoller = hs.timer.doEvery(0.1, function()
                    if not S.keysPanel then
                        if S.mousePoller then S.mousePoller:stop()
                        S.mousePoller = nil end
                        return
                    end
                    local _p      = hs.mouse.absolutePosition()
                    local _x, _y  = math.floor(_p.x), math.floor(_p.y)
                    local prev    = S.mousePos
                    if not prev or _x ~= prev.x or _y ~= prev.y then
                        S.mousePos = {
                            x = _x,
                            y = _y,
                        }
                        S.pushMouseState(_x, _y)
                    end
                end)
            end
            if S.windowOpen and S.activePanel == "window" then
                self:_winEngineStart()
            end
        end
    -- END Inputs Panel --
end

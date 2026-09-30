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

        local _pushToPanel = ctx.pushToPanel

        local _shellActive = ctx.shellActive
    -- END Context --

    -- Window Panel --
        local function _winG(fn) local ok, v = pcall(fn)
        if ok then return v end end

        function S.winRead(win)
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

        function S.winPush(fn, payload)
            local ok, j = pcall(hs.json.encode, payload)
            if ok then pcall(function() _pushToPanel(S.windowPanel, "window", fn .. "(" .. j .. ")") end) end
        end

        local function _axStr(v)
            local t = type(v)
            if t == "string" then return #v > 120 and (v:sub(1, 120) .. "\u{2026}") or v end
            if t == "number" or t == "boolean" then return tostring(v) end
            return nil
        end

        local function _winStillOpen()
            if S.windowPanel ~= nil then return S.windowOpen end
            local ms = _G.ms
            if ms and ms.shell and ms.shell.isPoppedOut and ms.shell.isPoppedOut("window") then
                return S.windowOpen
            end
            if not (S.windowOpen and _shellActive() and S.activePanel == "window") then
                return false
            end
            local st = _G.ms and _G.ms._shellState
            return not (st and st.visible == false)
        end

        function MsDevTools:_winEngineStop()
            if S.winAppWatcher then pcall(function() S.winAppWatcher:stop() end)
            S.winAppWatcher = nil end
            if S.winUiWatcher  then pcall(function() S.winUiWatcher:stop()  end)
            S.winUiWatcher  = nil end
            if S.winMonitor then S.winMonitor:stop()
            S.winMonitor = nil end
            S.winElementInspect = false
        end

        function MsDevTools:setWinElementInspect(enabled)
            S.winElementInspect = (enabled == true)
            if not S.winElementInspect then S.winLastMouse = nil end
        end

        function MsDevTools:_winEngineStart()
            self:_winEngineStop()
            S.winDirty, S.winMoveN, S.winResizeN, S.winLastMouse = false, 0, 0, nil
            S.winElementTab = true
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
                    st = S.winRead(win or _winSubject())
                    _winLastFullState = st
                end
                if st then S.winPush("updateCurrentWindow", st) end
                return st
            end

            local function watchApp(app)
                if S.winUiWatcher then pcall(function() S.winUiWatcher:stop() end)
                S.winUiWatcher = nil end
                if not app then S.winWatchedAppName = nil
                return end
                S.winWatchedAppName = _winG(function() return app:name() end)
                S.winUiWatcher = _winG(function()
                    local w = app:newWatcher(function(el, ev)
                        if _G.ms and _G.ms._shellDragging then return end
                        if ev == hs.uielement.watcher.windowMinimized then
                            S.winPendingEvent = {
                                type = "minimize",
                                app = S.winWatchedAppName,
                                win = _winG(function() return el:asHSWindow() end) }
                        elseif ev == hs.uielement.watcher.windowUnminimized then
                            S.winPendingEvent = {
                                type = "unminimize",
                                app = S.winWatchedAppName,
                                win = _winG(function() return el:asHSWindow() end) }
                        elseif ev == hs.uielement.watcher.windowResized then
                            S.winResizeN = S.winResizeN + 1
                        else
                            S.winMoveN = S.winMoveN + 1
                        end
                        S.winDirty = true
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

            S.winAppWatcher = hs.application.watcher.new(function(_, ev, app)
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
            pcall(function() S.winAppWatcher:start() end)

            S.winMonitor = hs.timer.doEvery(0.2, function()
                if not _winStillOpen() then self:_winEngineStop()
                return end
                if _G.ms and _G.ms._shellDragging then return end

                local payload = {}
                local hasData = false

                if S.winDirty then
                    S.winDirty = false
                    local st = _winReadLight(
                        (S.winPendingEvent and S.winPendingEvent.win) or _winSubject()
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
                    if S.winPendingEvent then
                        local entry = {
                            type = S.winPendingEvent.type,
                            ts = os.date("%H:%M:%S"),
                            app = S.winPendingEvent.app }
                        table.insert(S.windowHistory, entry)
                        if #S.windowHistory > S.windowMaxHistory then table.remove(S.windowHistory, 1) end
                        table.insert(events, entry)
                        S.winPendingEvent = nil
                    end
                    if S.winMoveN > 0 then
                        local entry = {
                            type = "move",
                            ts = os.date("%H:%M:%S"),
                            count = S.winMoveN,
                            x = f and f.x or nil,
                            y = f and f.y or nil,
                        }
                        table.insert(S.windowHistory, entry)
                        if #S.windowHistory > S.windowMaxHistory then table.remove(S.windowHistory, 1) end
                        table.insert(events, entry)
                        S.winMoveN = 0
                    end
                    if S.winResizeN > 0 then
                        local entry = {
                            type = "resize",
                            ts = os.date("%H:%M:%S"),
                            count = S.winResizeN,
                            w = f and f.w or nil,
                            h = f and f.h or nil,
                        }
                        table.insert(S.windowHistory, entry)
                        if #S.windowHistory > S.windowMaxHistory then table.remove(S.windowHistory, 1) end
                        table.insert(events, entry)
                        S.winResizeN = 0
                    end
                    if #events > 0 then
                        payload.events = events
                        hasData = true
                    end
                end

                if S.winElementInspect and S.winElementTab and hs.accessibilityState() then
                    local p = hs.mouse.absolutePosition()
                    local _now = hs.timer.secondsSinceEpoch()
                    local _stationaryDue = (not S.winLastInspectAt) or (_now - S.winLastInspectAt) >= 0.5
                    if _stationaryDue or not (S.winLastMouse and p.x == S.winLastMouse.x and p.y == S.winLastMouse.y) then
                        S.winLastMouse = p
                        S.winLastInspectAt = _now
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
                    S.winPush("updateAll", payload)
                end
            end)

            if not hs.accessibilityState() then
                S.winPush("updateElement", { axPermission = false })
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
            table.insert(S.windowHistory, entry)

            if #S.windowHistory > S.windowMaxHistory then
                table.remove(S.windowHistory, 1)
            end

            if S.windowPanel or _shellActive() then
                local ok, j = pcall(hs.json.encode, entry)

                if ok then
                    pcall(function()
                        _pushToPanel(S.windowPanel, "window", "appendEntry(" .. j .. ")")
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
                    S.windowHistory = {}

                elseif data.action == "close" then
                    self:hideWindow()

                elseif data.action == "dragStart" then
                    _devDragStart(function() return S.windowPanel end, S.windowPanelPos)

                elseif data.action == "moveEnd" then
                    _devDragEnd(function() return S.windowPanel end)

                elseif data.action == "move" and S.windowPanelPos then
                    S.windowPanelPos.x = S.windowPanelPos.x + (data.dx or 0)
                    S.windowPanelPos.y = S.windowPanelPos.y + (data.dy or 0)

                    if S.windowPanel then
                        pcall(function() S.windowPanel:frame(S.windowPanelPos) end)
                    end

                elseif data.action == "playSlot" and data.slot then
                    ms.playSlot(data.slot)
                end
            end)

            S.windowPanelPos = pos
            _setupDevPanelTheme(panel, "_themeWindow")

            if _htmlCache["window"] then
                panel:html(_htmlCache["window"], _devBase)
            end

            _devFadeTimers["_histWindow"] = hs.timer.doAfter(0.05, function()
                _devFadeTimers["_histWindow"] = nil
                if not S.windowPanel then return end

                if #S.windowHistory > 0 then
                    local ok, j = pcall(hs.json.encode, S.windowHistory)
                    if ok then
                        pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end)
                    end
                end

                local st = S.winRead(hs.window.focusedWindow())
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
                S.windowOpen = true
                ms.shell.show()
                ms.shell.eval("showPanel('window')")
                hs.timer.doAfter(0.15, function()
                    if #S.windowHistory > 0 then
                        local ok, j = pcall(hs.json.encode, S.windowHistory)
                        if ok then
                            pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end)
                        end
                    end
                    S.winPush("updateCurrentWindow", S.winRead(hs.window.focusedWindow()))
                end)
                self:_winEngineStart()
                return
            end

            if not S.windowPanel then
                S.windowPanel = self:_buildWindowPanel()

                if not S.windowPanel then return end
            end

            S.windowOpen = true

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            ms.playSlot("settingsOpen")

            ms.safeShow(S.windowPanel)

            pcall(function() S.windowPanel:bringToFront(true) end)

            _devFadeIn(S.windowPanel, "window")

            self:_winEngineStart()
        end

        function MsDevTools:hideWindow()
            self:_winEngineStop()
            if S.windowPoller then
                S.windowPoller:stop()
                S.windowPoller = nil
            end

            S.windowOpen = false

            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

            if S.windowPanel then
                ms.playSlot("settingsClose")

                local panel = S.windowPanel

                S.windowPanel = nil

                _devFadeOut(panel, "window", function()
                    if panel then panel:hide() end
                end)
            end
        end

        function MsDevTools:toggleWindow()
            if S.windowOpen then
                self:hideWindow()
            else
                self:showWindow()
            end
        end
    -- END Window Panel --
end

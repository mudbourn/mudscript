return function(ms, ctx)
    -- Context --
        local S = ctx.S

        local MsDevTools = ctx.MsDevTools

        local _home = ctx.home

        local _pushToPanel = ctx.pushToPanel

        local _shellActive = ctx.shellActive

        local _devFadeTimers = ctx.devFadeTimers
    -- END Context --

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
            pcall(function() panel:level((hs.canvas.windowLevels.popUpMenu or 101) + 1) end)
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
            if not S.keysPanel and not _shellActive() then return end

            local _x   = x or (S.mousePos and S.mousePos.x) or 0
            local _y   = y or (S.mousePos and S.mousePos.y) or 0
            local mode = S.coordMode or "screen"
            local tx, ty = _x, _y

            if mode == "window" or mode == "windowTR" or mode == "windowBL"
                or mode == "windowBR" or mode == "windowCenter" then

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

                    end
                end

            elseif mode == "screenCenter" then
                local sf = hs.screen.mainScreen():frame()

                tx = _x - math.floor(sf.w / 2)
                ty = _y - math.floor(sf.h / 2)
            end

            local j = string.format('{"x":%d,"y":%d}', math.floor(tx), math.floor(ty))

            pcall(function()
                _pushToPanel(S.keysPanel, "keys", "updateMouseState(" .. j .. ")")
            end)
        end
    -- END Panel Helpers --

    -- Prewarm --
        function MsDevTools:prewarm()
            if not S.consolePanel then S.consolePanel = self:_buildConsolePanel() end
            if not S.watcherPanel then S.watcherPanel = self:_buildWatcherPanel() end
            if not S.keysPanel    then S.keysPanel    = self:_buildKeysPanel() end
            if not S.windowPanel  then S.windowPanel  = self:_buildWindowPanel() end
        end

        function MsDevTools:recolor()
            local js = _devThemeJS()
            if js == "" then return end
            if S.consolePanel then pcall(function() S.consolePanel:evaluateJavaScript(js) end) end
            if S.watcherPanel then pcall(function() S.watcherPanel:evaluateJavaScript(js) end) end
            if S.keysPanel    then pcall(function() S.keysPanel:evaluateJavaScript(js) end) end
            if S.windowPanel  then pcall(function() S.windowPanel:evaluateJavaScript(js) end) end
        end

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
            apply(S.consolePanel)
            apply(S.watcherPanel)
            apply(S.keysPanel)
            apply(S.windowPanel)
        end

        function MsDevTools:prewarmStep(which)
            if     which == "console" and not S.consolePanel then
                S.consolePanel = self:_buildConsolePanel()

            elseif which == "watcher" and not S.watcherPanel then
                S.watcherPanel = self:_buildWatcherPanel()

            elseif which == "keys" and not S.keysPanel then
                S.keysPanel = self:_buildKeysPanel()

            elseif which == "window" and not S.windowPanel then
                S.windowPanel = self:_buildWindowPanel()
            end
        end

        function MsDevTools:step(msg)
            local entry = {
                type = "step",
                ts   = os.date("%H:%M:%S"),
                msg  = tostring(msg or ""),
            }

            self:log(entry)

            if S.watcherPanel or _shellActive() then
                local ok, j = pcall(hs.json.encode, entry)

                if ok then
                    pcall(function()
                        _pushToPanel(S.watcherPanel, "watcher", "appendEntry(" .. j .. ")")
                    end)
                end
            end
        end
    -- END Prewarm --

    -- Public Accessors --
        function MsDevTools:getPanel(name)
            if     name == "console" then return S.consolePanel
            elseif name == "watcher" then return S.watcherPanel
            elseif name == "keys"    then return S.keysPanel
            elseif name == "window"  then return S.windowPanel
            end
        end
    -- END Public Accessors --

    -- Exports --
        ctx.makeDevPanel = _makeDevPanel

        ctx.setupDevPanelTheme = _setupDevPanelTheme

        ctx.devFadeIn = _devFadeIn

        ctx.devFadeOut = _devFadeOut
    -- END Exports --
end

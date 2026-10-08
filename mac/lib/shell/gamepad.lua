return function(ms, ctx)
    -- Gamepad Nav --
        ms._gpNav = ms._gpNav or {}

        local GP_DZ = 0.5

        local function _gpEvalInto(view, js)
            if not view then return end
            pcall(function() view:evaluateJavaScript(js) end)
        end

        local function _gpTargetView()
            local t = ms._gpNav.target
            if t and t ~= "shell" and ms.shell.getPopOutView then
                return ms.shell.getPopOutView(t)
            end
            return nil
        end

        local function _gpEval(cmd, arg, arg2)
            local js
            if arg2 ~= nil then
                js = string.format("if(window.gpNav)gpNav('%s',%d,%d)", cmd, arg, arg2)
            elseif arg ~= nil then
                js = string.format("if(window.gpNav)gpNav('%s',%d)", cmd, arg)
            else
                js = string.format("if(window.gpNav)gpNav('%s')", cmd)
            end
            local view = _gpTargetView()
            if view then
                _gpEvalInto(view, js)
            elseif ms.shell and ms.shell.eval then
                ms.shell.eval(js)
            end
        end

        local function _gpNavAlert(text)
            pcall(function() ms.alert(text, 2.2, true, { state = true }) end)
        end

        local function _gpTypeJs()
            local t = "xbox"
            local list = ms._gamepadControllers
            if list and list[1] and list[1].type then t = list[1].type end
            return "window.__gpType='" .. t .. "';"
        end

        local function _gpFocusWindow(target)
            ms._gpNav.target = target
            local init = "if(window.gpNavInit)gpNavInit()"
            if target and target ~= "shell" then
                local view = ms.shell.getPopOutView and ms.shell.getPopOutView(target)
                if view then
                    ms.safeShow(view)
                    pcall(function() view:bringToFront(true) end)
                    _gpEvalInto(view, _gpTypeJs() .. init)
                    _gpNavAlert("Focused pop-out")
                end
            elseif ms.shell then
                if ctx.view() then pcall(function() ctx.view():bringToFront(true) end) end
                if ms.shell.eval then ms.shell.eval(_gpTypeJs() .. init) end
                _gpNavAlert("Focused shell")
            end
        end

        local function _gpSwitchWindow()
            local n = ms._gpNav
            if n.target and n.target ~= "shell" and _gpTargetView() then
                _gpFocusWindow("shell")
                return
            end
            local pid = n.popPanel
            if pid and ms.shell.getPopOutView and ms.shell.getPopOutView(pid) then
                _gpFocusWindow(pid)
            else
                if ms.shell and ms.shell.eval then
                    ms.shell.eval("if(window.gpNav)gpNav('popOut')")
                end
            end
        end
        ms.shell._gpSwitchWindow = _gpSwitchWindow
        ms.shell._gpFocusWindow = _gpFocusWindow

        local function _gpZoom(delta)
            if ms.ui and ms.ui._actions and ms.ui._actions.setUiZoom then
                pcall(ms.ui._actions.setUiZoom, { delta = delta })
            end
        end

        local function _gpStopTimers()
            local n = ms._gpNav
            for _, k in ipairs({
                "lsTimer",
                "rsTimer",
                "holdTimer",
                "holdTimerX",
                "tapTimer",
            }) do
                if n[k] then n[k]:stop() n[k] = nil end
            end
            n.lsDir = nil
            n.rsActive = false
            n.xGrab = false
            n.selectHeld = false
            n.tapPending = false
            n.chordConsumed = false
        end

        local function _gpCloseViaChord(n)
            n.chordConsumed = true
            if n.holdTimer then n.holdTimer:stop() n.holdTimer = nil end
            if n.tapTimer then n.tapTimer:stop() n.tapTimer = nil end
            n.selectHeld = false
            n.tapPending = false
            if ms.shell and ms.shell.toggle then ms.shell.toggle() end
        end

        local function _gpLsDir(x, y)
            local ax, ay = math.abs(x), math.abs(y)
            if ax < GP_DZ and ay < GP_DZ then return nil end
            if ay >= ax then return y > 0 and "itemUp" or "itemDown" end
            return x > 0 and "itemRight" or "itemLeft"
        end

        ms.shell._gpNavHandler = function(kind, button, a, b)
            local n = ms._gpNav
            if n.target == "shell" and not ms._ownUiHeld then
                _gpStopTimers()
                n.lsDir = nil
                return
            end

            if kind == "move" then
                if button == "left" then
                    local dir = _gpLsDir(a or 0, b or 0)
                    if dir ~= n.lsDir then
                        n.lsDir = dir
                        if n.lsTimer then n.lsTimer:stop() n.lsTimer = nil end
                        if dir then
                            _gpEval(dir)
                            n.lsTimer = hs.timer.doEvery(0.18, function() _gpEval(dir) end)
                        end
                    end
                elseif button == "right" then
                    n.rsX = a or 0
                    n.rsY = b or 0
                    local active = math.abs(n.rsX) >= GP_DZ or math.abs(n.rsY) >= GP_DZ
                    if active and not n.rsActive then
                        n.rsActive = true
                        n.rsTimer = hs.timer.doEvery(0.05, function()
                            _gpEval("rstick",
                                math.floor((n.rsX or 0) * 100),
                                math.floor((n.rsY or 0) * 100))
                        end)
                    elseif not active and n.rsActive then
                        n.rsActive = false
                        if n.rsTimer then n.rsTimer:stop() n.rsTimer = nil end
                    end
                end
                return true
            end

            if kind == "release" then
                if button == "a" then
                    if n.holdTimerA then n.holdTimerA:stop() n.holdTimerA = nil end
                    if n.aGrab then
                        n.aGrab = false
                        _gpEval("grabDrop")
                    else
                        _gpEval("activate")
                    end
                    return true
                end
                if button == "x" then
                    if n.holdTimerX then n.holdTimerX:stop() n.holdTimerX = nil end
                    if n.xGrab then
                        n.xGrab = false
                    else
                        _gpEval("selectAll")
                    end
                    return true
                end
                if button == "options" then
                    if n.holdTimer then n.holdTimer:stop() n.holdTimer = nil end
                    if n.chordConsumed then
                        n.chordConsumed = false
                        n.selectHeld = false
                        n.tapPending = false
                        if n.tapTimer then n.tapTimer:stop() n.tapTimer = nil end
                        return true
                    end
                    if n.selectHeld then
                        n.selectHeld = false
                    elseif n.tapPending then
                        n.tapPending = false
                        if n.tapTimer then n.tapTimer:stop() n.tapTimer = nil end
                        _gpSwitchWindow()
                    else
                        n.tapPending = true
                        n.tapTimer = hs.timer.doAfter(0.28, function()
                            n.tapPending = false
                            n.tapTimer = nil
                            _gpEval("focusTopbar")
                        end)
                    end
                end
                return true
            end

            if button == "home" then
                if a and a.menu then _gpCloseViaChord(n) end
                return true
            elseif button == "options" then
                n.holdTimer = hs.timer.doAfter(0.35, function()
                    n.selectHeld = true
                    n.holdTimer = nil
                end)
                return true
            elseif button == "a" then
                n.aGrab = false
                n.holdTimerA = hs.timer.doAfter(0.30, function()
                    n.aGrab = true
                    n.holdTimerA = nil
                    _gpEval("grab")
                end)
                return true
            elseif button == "b" then
                _gpEval("back")
                return true
            elseif button == "x" then
                n.xGrab = false
                n.holdTimerX = hs.timer.doAfter(0.4, function()
                    n.xGrab = true
                    n.holdTimerX = nil
                    _gpEval("deleteSel")
                end)
                return true
            elseif button == "y" then
                _gpEval("copy")
                return true
            elseif button == "l1" then
                _gpEval("panelPrev")
                return true
            elseif button == "r1" then
                _gpEval("panelNext")
                return true
            elseif button == "l2" then
                _gpEval("tabPrev")
                return true
            elseif button == "r2" then
                _gpEval("tabNext")
                return true
            elseif button == "menu" then
                if a and a.home then _gpCloseViaChord(n) return true end
                _gpEval("toggleRail")
                return true
            elseif button == "up" or button == "down" or button == "left" or button == "right" then
                if n.selectHeld then
                    if button == "up" or button == "right" then _gpZoom(0.1) else _gpZoom(-0.1) end
                else
                    local map = {
                        up = "itemUp",
                        down = "itemDown",
                        left = "itemLeft",
                        right = "itemRight",
                    }
                    _gpEval(map[button])
                end
                return true
            end

            return false
        end

        ms.shell.gpEnsureOpenBind = function()
            if not ms.gamepadEnabled then return end
            if ms._gpOpenBind or not ms.gamepadBind then return end
            local function _toggle()
                if not ms._hotkeysReady then return end
                if ms.shell and ms.shell.toggle then ms.shell.toggle() end
            end
            ms._gpOpenBind = ms.gamepadBind({
                "menu",
                "home",
            }, _toggle)
        end

        ms.shell.gpClearOpenBind = function()
            if ms._gpOpenBind and ms._gpOpenBind.delete then pcall(ms._gpOpenBind.delete) end
            ms._gpOpenBind = nil
        end

        local function _gpAttach()
            _gpStopTimers()
            ms._gpNav.target = "shell"
            ms._gamepadCallbacks = ms._gamepadCallbacks or {}
            ms._gamepadCallbacks._nav = ms.shell._gpNavHandler
            local function _init()
                if ms.shell.eval then ms.shell.eval(_gpTypeJs() .. "if(window.gpNavInit)gpNavInit()") end
            end
            _init()
            hs.timer.doAfter(0.25, _init)
        end

        local function _gpDetach()
            _gpStopTimers()
            if ms._gamepadCallbacks then ms._gamepadCallbacks._nav = nil end
        end

        if not ms._gpNavBusHooked then
            ms._gpNavBusHooked = true
            ms.bus.on("macroLab:toggled", function(_, body)
                if body and body.visible and ms.gamepadEnabled then
                    _gpAttach()
                else
                    _gpDetach()
                end
            end)
        end
    -- END --
end

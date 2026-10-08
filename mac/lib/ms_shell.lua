-- ms_shell (Shell Infrastructure: webview window, dispatch, popouts) --
    return function(ms)
        local _shellView     = nil
        local _shellChannel  = nil
        local _shellReady    = false
        local _shellHydrated = false
        local _shellEvalQ    = {}
        local _shellFadeTimer = nil
        local _shellReadyWait = nil
        local _shellFadeInStarted = false

        local function _stopFade()
            if _shellFadeTimer then
                _shellFadeTimer:stop()
                _shellFadeTimer = nil
            end
        end

        local function _fade(view, fromAlpha, toAlpha, onDone)
            _stopFade()
            local step, steps = 0, 30
            local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
            local timer = nil
            timer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                step = step + 1
                pcall(function() view:alpha(fromAlpha + (toAlpha - fromAlpha) * (step / steps)) end)
                if step >= steps then
                    timer:stop()
                    if _shellFadeTimer == timer then _shellFadeTimer = nil end
                    if onDone then onDone() end
                end
            end)
            _shellFadeTimer = timer
        end

        local function _fadeIn(view)
            if _shellFadeInStarted then return end
            _shellFadeInStarted = true
            _fade(view, 0, 1)
        end

        local ctx = {
            view = function() return _shellView end,
            stopFade = _stopFade,
        }

        local function _loadPart(name)
            package.loaded["lib.shell." .. name] = nil
            require("lib.shell." .. name)(ms, ctx)
        end

        ms.shell = {}

        _loadPart("osk")

        -- Flush queued JS and push host-owned content into the panels, once.
        local function _hydrateShell()
            if _shellHydrated then return end
            _shellHydrated = true
            _shellReady = true
            for _, js in ipairs(_shellEvalQ) do
                pcall(function() if _shellView then _shellView:evaluateJavaScript(js) end end)
            end
            _shellEvalQ = {}
            hs.timer.doAfter(0.1, function()
                if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                -- Re-push every installed-library kind now the bus is wired.
                if ms.ui and ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end)
        end
        ms.shell._hydrate = _hydrateShell

        -- Base (100%-zoom) minimum window sizes, scaled live by ms._uiZoom.
        local BASE_SHELL_W, BASE_SHELL_H = 800, 500
        local BASE_POP_W,   BASE_POP_H   = 460, 320
        ms._shellBaseMin = {
            w = BASE_SHELL_W,
            h = BASE_SHELL_H,
        }
        ms._popBaseMin = {
            w = BASE_POP_W,
            h = BASE_POP_H,
        }

        -- applyZoom --
            -- Set the global UI zoom on shell and popouts, rescaling open frames. Range 0.5-2.0.
            ms.shell.applyZoom = function(newZoom, opts)
                opts = opts or {}
                local old = ms._uiZoom or 1.0
                newZoom = math.max(0.5, math.min(2.0, tonumber(newZoom) or 1.0))
                ms._uiZoom = newZoom
                local ratio = (old ~= 0) and (newZoom / old) or 1

                if _shellView and not opts.noRescale
                and math.abs(ratio - 1) > 0.001 then
                    pcall(function()
                        local f = _shellView:frame()
                        local nf = { x = f.x, y = f.y,
                                     w = f.w * ratio, h = f.h * ratio }
                        local minW = BASE_SHELL_W * newZoom
                        local minH = BASE_SHELL_H * newZoom
                        if nf.w < minW then nf.w = minW end
                        if nf.h < minH then nf.h = minH end
                        _shellView:frame(nf)
                    end)
                end

                ms.shell.eval("if(window.applyZoom)applyZoom(" .. newZoom .. ")")
                if ms.dev then
                    pcall(function() ms.dev:rezoom(newZoom, ratio, opts.noRescale) end)
                end
                if ms.shell._rezoomPopouts then
                    pcall(function()
                        ms.shell._rezoomPopouts(newZoom, ratio, opts.noRescale)
                    end)
                end
            end
        -- END --

        -- eval --
            ms.shell.eval = function(js)
                if type(js) ~= "string" then return end
                if _shellView and _shellReady then
                    local ok, err = pcall(function() _shellView:evaluateJavaScript(js) end)
                    if not ok then print("[shell] eval failed: " .. tostring(err):sub(1, 200)) end
                else
                    _shellEvalQ[#_shellEvalQ + 1] = js
                end
            end
        -- END --

        -- probe --
            ms.shell.probe = function(expr, cb, panelId)
                local out = os.getenv("HOME") .. "/.hammerspoon/data/probe.txt"
                local js = "(function(){try{var r=(" .. tostring(expr) .. ");"
                    .. "return typeof r==='string'?r:JSON.stringify(r,null,1);}"
                    .. "catch(e){return 'probe error: '+e;}})()"
                local view = _shellView
                if panelId then
                    view = ms.shell.getPopOutView and ms.shell.getPopOutView(panelId)
                    if not view then
                        if cb then cb("probe: no popout for " .. tostring(panelId)) end
                        return
                    end
                elseif not _shellReady then
                    view = nil
                end
                if not view then
                    if cb then cb("probe: shell not ready") end
                    return
                end
                view:evaluateJavaScript(js, function(result, err)
                    local text = tostring(result or (err and err.NSLocalizedDescription) or err or "")
                    local f = io.open(out, "w")
                    if f then
                        f:write(text, "\n")
                        f:close()
                    end
                    print("[probe] " .. text:sub(1, 2000))
                    if cb then cb(text) end
                end)
            end
        -- END --

        -- isReady --
            ms.shell.isReady = function() return _shellReady end
            ms.shell.webview = function() return _shellView end
            -- Whether the shell window is actually on screen right now.
            ms.shell.isVisible = function()
                if not _shellView then return false end
                local ok, w = pcall(function() return _shellView:hswindow() end)
                return ok and w ~= nil and w:isVisible() == true
            end
        -- END --

        -- resizeEdgeMath --
            ms._resizeEdgeMath = function(edge, sf, dx, dy, minW, minH)
                local x, y, w, h = sf.x, sf.y, sf.w, sf.h
                local hasE = edge:find("e") ~= nil
                local hasW = edge:find("w") ~= nil
                local hasN = edge:find("n") ~= nil
                local hasS = edge:find("s") ~= nil
                if hasE then w = sf.w + dx end
                if hasW then
                    w = sf.w - dx
                    if w < minW then
                        x = sf.x + sf.w - minW
                        w = minW
                    else
                        x = sf.x + dx
                    end
                end
                if hasS then h = sf.h + dy end
                if hasN then
                    h = sf.h - dy
                    if h < minH then
                        y = sf.y + sf.h - minH
                        h = minH
                    else
                        y = sf.y + dy
                    end
                end
                w = math.max(w, minW)
                h = math.max(h, minH)
                return {
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                }
            end
        -- END --

        -- init --
            ms.shell.init = function()
                if _shellView then return end
                require("hs.webview")
                require("hs.webview.usercontent")

                _shellChannel = hs.webview.usercontent.new("msShell")
                _shellChannel:setCallback(function(message)
                    local raw = tostring(message.body or "")
                    local ok, data = pcall(hs.json.decode, raw)
                    if not ok or type(data) ~= "table" then
                        return
                    end
                    local panel  = data.panel  or "_shell"
                    local action = data.action or "unknown"
                    local body   = data.body

                    if action == "osk" then
                        if ms.shell.osk and ms.shell.osk._recv then
                            ms.shell.osk._recv(body, _shellView)
                        end
                        return
                    end

                    if panel == "_shell" and action == "jsError" then
                        local b = body or {}
                        local where = tostring(b.src or "?")
                        if b.line and b.line ~= 0 then where = where .. ":" .. tostring(b.line) end
                        print("[shell JS " .. tostring(b.kind or "error") .. "] "
                            .. tostring(b.msg or "") .. "  (" .. where .. ")")
                        if b.stack and b.stack ~= "" then
                            print("  stack: " .. tostring(b.stack))
                        end
                        return
                    end

                    if panel == "_shell" and action == "ready" then
                        _hydrateShell()
                        if ms._shellState and ms._shellState.visible and _shellView then
                            _fadeIn(_shellView)
                        end
                    end
                    if action == "close" then
                        pcall(function() ms.shell.hide() end)
                        return
                    end
                    if action == "dragStart" then
                        pcall(function()
                            if ms._shellDragTap then ms._shellDragTap:stop() end
                            ms._shellDragging = true
                            local startFrame = _shellView:frame()
                            local startMouse = hs.mouse.absolutePosition()
                            local w, h = startFrame.w, startFrame.h
                            local topLimit = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame().y
                            pcall(function() _shellView:shadow(false) end)
                            local et = hs.eventtap.event.types
                            ms._shellDragTap = hs.eventtap.new(
                                {
                                    et.leftMouseDragged,
                                    et.leftMouseUp,
                                },
                                function(ev)
                                    if not _shellView then return false end
                                    if ev:getType() == et.leftMouseUp then
                                        if ms._shellDragTap then
                                            ms._shellDragTap:stop()
                                            ms._shellDragTap = nil
                                        end
                                        ms._shellDragging = false
                                        pcall(function() _shellView:shadow(true) end)
                                        pcall(ms.shell.saveState)
                                        return false
                                    end
                                    local mp = hs.mouse.absolutePosition()
                                    pcall(function()
                                        _shellView:frame({
                                            x = startFrame.x + (mp.x - startMouse.x),
                                            y = math.max(startFrame.y + (mp.y - startMouse.y), topLimit),
                                            w = w,
                                            h = h,
                                        })
                                    end)
                                    return false
                                end)
                            ms._shellDragTap:start()
                        end)
                        return
                    end
                    if action == "resizeStart" and body and body.edge then
                        pcall(function()
                            if ms._shellResizeTap then ms._shellResizeTap:stop() end
                            ms._shellDragging = true
                            local edge = body.edge
                            local startFrame = _shellView:frame()
                            local startMouse = hs.mouse.absolutePosition()
                            local _z = ms._uiZoom or 1.0
                            local MIN_W, MIN_H = BASE_SHELL_W * _z, BASE_SHELL_H * _z
                            ms.shell.eval("window.__msResizing = true")
                            pcall(function() _shellView:shadow(false) end)
                            local et = hs.eventtap.event.types
                            ms._shellResizeTap = hs.eventtap.new(
                                {
                                    et.leftMouseDragged,
                                    et.leftMouseUp,
                                },
                                function(ev)
                                    if not _shellView then return false end
                                    if ev:getType() == et.leftMouseUp then
                                        if ms._shellResizeTap then
                                            ms._shellResizeTap:stop()
                                            ms._shellResizeTap = nil
                                        end
                                        ms._shellDragging = false
                                        pcall(function() _shellView:shadow(true) end)
                                        ms.shell.eval("window.__msResizing = false")
                                        pcall(ms.shell.saveState)
                                        return false
                                    end
                                    local mp = hs.mouse.absolutePosition()
                                    local dx = mp.x - startMouse.x
                                    local dy = mp.y - startMouse.y
                                    local nf = ms._resizeEdgeMath(edge, startFrame, dx, dy, MIN_W, MIN_H)
                                    pcall(function() _shellView:frame(nf) end)
                                    return false
                                end)
                            ms._shellResizeTap:start()
                        end)
                        return
                    end
                    if action == "moveEnd" then
                        pcall(function()
                            if ms._shellDragTap then
                                ms._shellDragTap:stop()
                                ms._shellDragTap = nil
                            end
                            ms._shellDragging = false
                            pcall(function() _shellView:shadow(true) end)
                            local f = _shellView:frame()
                            local sf = hs.screen.mainScreen():frame()
                            local visW = math.max(0, math.min(f.x + f.w, sf.x + sf.w) - math.max(f.x, sf.x))
                            local visH = math.max(0, math.min(f.y + f.h, sf.y + sf.h) - math.max(f.y, sf.y))
                            if visW < f.w * 0.5 or visH < f.h * 0.5 then
                                local nx = math.max(sf.x - f.w * 0.4, math.min(f.x, sf.x + sf.w - f.w * 0.4))
                                local ny = math.max(sf.y, math.min(f.y, sf.y + sf.h - f.h * 0.4))
                                local sx, sy = f.x, f.y
                                local step, steps = 0, 5
                                local view = _shellView
                                _shellView:alpha(0.85)
                                hs.timer.doEvery(0.016, function()
                                    step = step + 1
                                    local t = step / steps
                                    t = 1 - (1 - t) * (1 - t)
                                    pcall(function()
                                        view:frame({
                                            x = sx + (nx - sx) * t,
                                            y = sy + (ny - sy) * t,
                                            w = f.w,
                                            h = f.h,
                                        })
                                    end)
                                    if step >= steps then
                                        pcall(function()
                                            view:frame({
                                                x = nx,
                                                y = ny,
                                                w = f.w,
                                                h = f.h,
                                            })
                                        end)
                                        pcall(function() view:alpha(1) end)
                                        ms.shell.saveState()
                                        return false
                                    end
                                end)
                            else
                                pcall(ms.shell.saveState)
                            end
                        end)
                        return
                    end
                    if action == "clampSize" and body and body.w and body.h then
                        pcall(function()
                            local f = _shellView:frame()
                            if f.w < body.w or f.h < body.h then
                                _shellView:frame({
                                    x = f.x,
                                    y = f.y,
                                    w = math.max(f.w, body.w),
                                    h = math.max(f.h, body.h),
                                })
                            end
                        end)
                        return
                    end
                    if action == "quickReload" then
                        pcall(ms.reload)
                        return
                    end
                    if action == "reloadMacros" then
                        if ms.ui and ms.ui._actions and ms.ui._actions.reloadMacros then
                            pcall(ms.ui._actions.reloadMacros)
                        end
                        return
                    end
                    if action == "reloadTheme" then
                        if ms.ui and ms.ui._actions and ms.ui._actions.reloadTheme then
                            pcall(ms.ui._actions.reloadTheme)
                        end
                        return
                    end
                    if action == "reloadSettings" then
                        if ms.ui and ms.ui._actions and ms.ui._actions.reloadSettings then
                            pcall(ms.ui._actions.reloadSettings)
                        end
                        return
                    end
                    if action == "reloadUI" then
                        if ms.ui and ms.ui._actions and ms.ui._actions.reloadUI then
                            pcall(ms.ui._actions.reloadUI)
                        end
                        return
                    end
                    if action == "popOut" and body and body.panel then
                        local pid = body.panel
                        local ok = ms.shell.popOut(pid)
                        if ok then
                            ms.shell.eval("shellReceive('" .. pid .. "', 'poppedOut')")
                            -- Follow controller focus into the freshly popped window.
                            if ms._gamepadCallbacks and ms._gamepadCallbacks._nav then
                                ms._gpNav.popPanel = pid
                                if ms.shell._gpFocusWindow then
                                    hs.timer.doAfter(0.05, function()
                                        ms.shell._gpFocusWindow(pid)
                                    end)
                                end
                            end
                        end
                        return
                    end
                    if action == "popIn" and body and body.panel then
                        ms.shell.popIn(body.panel)
                        return
                    end
                    if action == "focusPopOut" and body and body.panel then
                        if ms.shell and ms.shell.getPopOutView then
                            local popView = ms.shell.getPopOutView(body.panel)
                            if popView then
                                ms.safeShow(popView)
                                pcall(function() popView:bringToFront(true) end)
                                hs.timer.doAfter(0.15, function()
                                    pcall(function() popView:bringToFront(true) end)
                                end)
                            end
                        end
                        return
                    end
                    if action == "playSlot" and body and body.slot then
                        pcall(function() ms.playSlot(body.slot) end)
                        return
                    end
                    if action == "announce" and body and body.text then
                        pcall(function()
                            ms.alert(body.text, 2.2, true, { state = true })
                        end)
                        return
                    end
                    if ms.bus then
                        local topic = "ui:" .. panel .. ":" .. action
                        ms.bus.emit(topic, body)
                    end
                end)

                local sf = hs.screen.mainScreen():frame()
                local maxW = math.floor(sf.w * 0.85)
                local maxH = math.floor(sf.h * 0.85)
                local w = math.min(820, maxW)
                local h = math.min(520, maxH)
                local x = sf.x + math.floor((sf.w - w) / 2)
                local y = sf.y + math.floor((sf.h - h) / 2)
                local st = ms._shellState
                if st and st.x and st.y then
                    x, y = st.x, st.y
                    if st.w then w = st.w end
                    if st.h then h = st.h end
                end

                _shellView = hs.webview.new({
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                }, {}, _shellChannel)
                pcall(function()
                    local M = hs.webview.windowMasks or {}
                    _shellView:windowStyle((M.borderless or 0) + (M.nonactivating or 128))
                end)
                pcall(function() _shellView:transparent(true) end)
                pcall(function() _shellView:allowResizing(true) end)
                pcall(function()
                    _shellView:minimumSize({
                        w = 800,
                        h = 500,
                    })
                end)
                pcall(function() _shellView:level(hs.canvas.windowLevels.popUpMenu or 101) end)
                pcall(function() _shellView:allowTextEntry(true) end)
                pcall(function() _shellView:shadow(true) end)
                pcall(function()
                    _shellView:windowCallback(function(action, _, hasFocus)
                        if action == "focusChange" and ms._ownUiFocus then
                            ms._ownUiFocus(hasFocus)
                        end
                    end)
                end)
                _shellView:alpha(0)

                local htmlPath = hs.configdir .. "/ui/ms_shell.html"
                local baseURL  = "file://" .. hs.configdir .. "/ui/"
                local f = io.open(htmlPath, "r")
                if f then
                    local html = f:read("*all")
                    f:close()
                    local r = (ms._theme and (ms._theme.windowRadius or ms._theme.radius))
                        or (ms._themeDefaults and (ms._themeDefaults.windowRadius or ms._themeDefaults.radius))
                        or 0
                    local inject = string.format(
                        '<style>html{background:transparent!important;--ms-window-radius:%dpx;}</style>',
                        r
                    )
                    html = html:gsub("</head>", inject .. "</head>", 1)
                    html = html:gsub('<script src="%./modules/([%w%-%._]+)"></script>', function(fname)
                        local mf = io.open(hs.configdir .. "/ui/modules/" .. fname, "r")
                        if not mf then return "" end
                        local js = mf:read("*all")
                        mf:close()
                        return "<script>\n" .. js .. "\n</script>"
                    end)
                    html = html:gsub('<link rel="stylesheet" href="%./modules/([%w%-%._]+%.css)">', function(fname)
                        local cf = io.open(hs.configdir .. "/ui/modules/" .. fname, "r")
                        if not cf then return "" end
                        local css = cf:read("*all")
                        cf:close()
                        return "<style>\n" .. css .. "\n</style>"
                    end)
                    _shellView:html(html, baseURL)
                end

                if ms.theme and ms.theme.applyWindowRadius then
                    ms.theme.applyWindowRadius(_shellView)
                end
                pcall(function() _shellView:shadow(true) end)

                ms.shell._buildOsk()

                hs.timer.doAfter(0.05, function()
                    if not _shellView then return end
                    local themeJson = hs.json.encode(ms.theme.effective())
                    _shellView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                end)

                if ms.bus then
                    ms.bus.on("panel:poppedIn", function(data)
                        if data and data.id then
                            ms.shell.eval("shellReceive('" .. data.id .. "', 'poppedIn')")
                            hs.timer.doAfter(0.1, function()
                                pcall(function()
                                    ms.bus.emit("ui:" .. data.id .. ":ready", { action = "ready" })
                                end)
                            end)
                        end
                    end)
                end
            end
        -- END --

        -- saveState --
            ms.shell.saveState = function()
                if not _shellView then return end
                local ok, frame = pcall(function() return _shellView:frame() end)
                if ok and frame then
                    ms._shellState = ms._shellState or {}
                    ms._shellState.x = math.floor(frame.x)
                    ms._shellState.y = math.floor(frame.y)
                    ms._shellState.w = math.floor(frame.w)
                    ms._shellState.h = math.floor(frame.h)
                    if ms.saveSettings then pcall(ms.saveSettings) end
                end
                if ms.syncExitCurtainFrame then pcall(ms.syncExitCurtainFrame) end
            end
        -- END --

        -- _restoreFrame --
            ms.shell._restoreFrame = function()
                if not _shellView then return end
                local st = ms._shellState
                if not st or not st.x or not st.y then return end
                pcall(function()
                    local w = st.w or 820
                    local h = st.h or 520
                    local screenObj = hs.screen.mainScreen()
                    local cx, cy = st.x + w / 2, st.y + h / 2
                    for _, s in ipairs(hs.screen.allScreens()) do
                        local sf = s:frame()
                        if cx >= sf.x and cx < sf.x + sf.w and cy >= sf.y and cy < sf.y + sf.h then
                            screenObj = s
                            break
                        end
                    end
                    local sf = screenObj:frame()
                    w = math.min(w, sf.w)
                    h = math.min(h, sf.h)
                    local x = math.max(sf.x, math.min(st.x, sf.x + sf.w - w))
                    local y = math.max(sf.y, math.min(st.y, sf.y + sf.h - h))
                    _shellView:frame({
                        x = x,
                        y = y,
                        w = w,
                        h = h,
                    })
                end)
            end
        -- END --

        ms.shell._activePanel = "macros"
        -- setActivePanel --
            ms.shell.setActivePanel = function(id)
                if type(id) ~= "string" then return end
                ms.shell._activePanel = id
                ms._shellState = ms._shellState or {}
                ms._shellState.lastPanel = id
            end
        -- END --

        -- show --
            ms.shell.show = function()
                if ms._restarting or ms._shuttingDown then return end
                if not (ms._shellState and ms._shellState.visible) then
                    local front = hs.application.frontmostApplication()
                    if front and front:bundleID() ~= hs.processInfo.bundleID then
                        ms._shellPrevApp = front
                    end
                end
                if not _shellView then ms.shell.init() end
                _stopFade()
                _shellFadeInStarted = false
                ms.shell._restoreFrame()
                if ms.syncExitCurtainFrame then pcall(ms.syncExitCurtainFrame) end
                pcall(function() ms.playSlot("settingsOpen") end)
                _shellView:alpha(0)
                ms.safeShow(_shellView)
                pcall(function() _shellView:bringToFront(true) end)
                pcall(hs.focus)
                if ms._ownUiFocus then pcall(ms._ownUiFocus, true) end
                ms._shellState = ms._shellState or {}
                ms._shellState.visible = true
                if ms.ui then ms.ui._open = true end
                if ms.bus then ms.bus.emit("macroLab:toggled", { visible = true }) end
<<<<<<< ours
<<<<<<< ours
=======
                if _shellReady and ms.ui and ms.ui.needsRefresh and ms.ui.needsRefresh() then
                    pcall(ms.ui.refresh)
                end

>>>>>>> theirs
=======
>>>>>>> theirs
                local view = _shellView
                if _shellReady then
                    _fadeIn(view)
                    if ms.ui and ms.ui.needsRefresh and ms.ui.needsRefresh() then
                        hs.timer.doAfter(0, function() pcall(ms.ui.refresh) end)
                    end
                else
                    if _shellReadyWait then _shellReadyWait:stop() end
                    local waited = 0
                    _shellReadyWait = hs.timer.doEvery(0.1, function()
                        waited = waited + 0.1
                        if _shellReady then
                            if _shellReadyWait then
                                _shellReadyWait:stop()
                                _shellReadyWait = nil
                            end
                            _fadeIn(view)
                        elseif waited >= 1.5 then
                            if _shellReadyWait then
                                _shellReadyWait:stop()
                                _shellReadyWait = nil
                            end
                            print("[shell] ready handshake timed out (1.5s) -- forcing "
                                .. "visible and hydrating anyway; page->Lua bridge may be slow")
                            _hydrateShell()
                            _fadeIn(view)
                        end
                    end)
                end
            end
        -- END --

        -- hide --
            ms.shell.hide = function()
                pcall(function() ms.shell.osk.hide() end)
                if _shellView then
                    _stopFade()
                    _shellFadeInStarted = false
                    if ms._shellState and ms._shellState.visible then
                        pcall(function() ms.playSlot("settingsClose") end)
                    end
                    ms.shell.saveState()
                    ms._shellState = ms._shellState or {}
                    ms._shellState.visible = false
                    ms._ownUiHeld = false
                    if ms.ui then ms.ui._open = false end
                    local view = _shellView
                    local startAlpha = 1
                    pcall(function() startAlpha = view:alpha() or 1 end)
                    _fade(view, startAlpha, 0, function()
                        pcall(function() view:hide() end)
                        if ms._shellPrevApp then
                            pcall(function() ms._shellPrevApp:activate() end)
                            ms._shellPrevApp = nil
                        end
                    end)
                    if ms.bus then ms.bus.emit("macroLab:toggled", { visible = false }) end
                end
            end
        -- END --

        -- toggle --
            ms.shell.toggle = function()
                local isOpen = ms._shellState and ms._shellState.visible
                if _shellView and isOpen then
                    ms.shell.hide()
                else
                    ms.shell.show()
                end
            end
        -- END --

        _loadPart("gamepad")

        -- destroy --
            ms.shell.destroy = function()
                _stopFade()
                if ms._shellDragTap then
                    ms._shellDragTap:stop()
                    ms._shellDragTap = nil
                end
                if ms._shellResizeTap then
                    ms._shellResizeTap:stop()
                    ms._shellResizeTap = nil
                end
                ms._shellDragging = false
                if ms.shell.osk and ms.shell.osk._destroy then ms.shell.osk._destroy() end
                if _shellView then
                    pcall(function() _shellView:delete() end)
                    _shellView = nil
                end
                _shellChannel  = nil
                _shellReady    = false
                _shellHydrated = false
                _shellEvalQ    = {}
            end
        -- END --

        -- dispatch --
            ms.shell.dispatch = function(panel, action, body)
                if ms.bus then
                    ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                end
            end
        -- END --

        _loadPart("popout")
    end
-- END ms_shell --

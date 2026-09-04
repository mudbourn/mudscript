-- ms_shell (Shell Infrastructure: webview window, dispatch, popouts) --
    return function(ms)
        local _shellView     = nil
        local _shellChannel  = nil
        local _shellReady    = false
        local _shellHydrated = false
        local _shellEvalQ    = {}
        local _shellFadeTimer = nil
        local _shellReadyWait = nil
        local _oskView       = nil

        ms.shell = {}

        -- On-screen keyboard window --
            -- A standalone, screen-level webview holding just the controller
            -- keyboard, so it can be dragged clear of the shell frame. Baked at
            -- shell boot (hidden, alpha 0) so the first open never flashes white.
            -- The keys are painted from a board the focused window streams over
            -- the "_osk" message; that window keeps the cursor and the edits.
            local function _oskTheme()
                if _oskView and ms._theme then
                    pcall(function()
                        _oskView:evaluateJavaScript(
                            "if(window.OSK)OSK.applyTheme(" .. hs.json.encode(ms.theme.effective()) .. ")")
                    end)
                end
            end

            ms.shell._buildOsk = function()
                if _oskView then return end
                require("hs.webview")

                local sf = hs.screen.mainScreen():frame()
                local w, h = 620, 320
                _oskView = hs.webview.new({
                    x = sf.x + math.floor((sf.w - w) / 2),
                    y = sf.y + sf.h - h - 40,
                    w = w,
                    h = h,
                })
                pcall(function()
                    local M = hs.webview.windowMasks or {}
                    _oskView:windowStyle((M.borderless or 0) + (M.nonactivating or 128))
                end)
                pcall(function() _oskView:transparent(true) end)
                pcall(function() _oskView:shadow(false) end)
                pcall(function() _oskView:level((hs.canvas.windowLevels.popUpMenu or 101) + 3) end)
                _oskView:alpha(0)

                local htmlPath = hs.configdir .. "/ui/ms_osk.html"
                local baseURL  = "file://" .. hs.configdir .. "/ui/"
                local f = io.open(htmlPath, "r")
                if f then
                    local html = f:read("*all")
                    f:close()
                    _oskView:html(html, baseURL)
                end

                hs.timer.doAfter(0.1, _oskTheme)
            end

            ms.shell.osk = {}

            ms.shell.osk.render = function(payload)
                if not _oskView then return end
                pcall(function()
                    _oskView:evaluateJavaScript(
                        "if(window.OSK)OSK.render(" .. hs.json.encode(payload) .. ")")
                end)
            end

            ms.shell.osk.show = function(senderView, payload)
                ms.shell._buildOsk()
                if not _oskView then return end

                local f = _oskView:frame()
                local w, h = f.w, f.h
                local sf = hs.screen.mainScreen():frame()
                local x = sf.x + math.floor((sf.w - w) / 2)
                local y = sf.y + sf.h - h - 40
                local ok, tf = pcall(function() return senderView and senderView:frame() end)
                if ok and tf then
                    x = tf.x + math.floor((tf.w - w) / 2)
                    y = tf.y + tf.h - h + 20
                end
                x = math.max(sf.x, math.min(sf.x + sf.w - w, x))
                y = math.max(sf.y, math.min(sf.y + sf.h - h, y))
                pcall(function() _oskView:frame({ x = x, y = y, w = w, h = h }) end)

                pcall(function()
                    _oskView:evaluateJavaScript(
                        "if(window.OSK)OSK.show(" .. hs.json.encode(payload) .. ")")
                end)
                if ms.safeShow then ms.safeShow(_oskView) else pcall(function() _oskView:show() end) end
                _oskView:alpha(1)
                pcall(function() _oskView:bringToFront(true) end)
            end

            ms.shell.osk.hide = function()
                if not _oskView then return end
                pcall(function() _oskView:evaluateJavaScript("if(window.OSK)OSK.hide()") end)
                _oskView:alpha(0)
                pcall(function() _oskView:hide() end)
            end

            ms.shell.osk.move = function(dx, dy)
                if not _oskView then return end
                pcall(function()
                    local f = _oskView:frame()
                    local sf = hs.screen.mainScreen():frame()
                    local nx = math.max(sf.x, math.min(sf.x + sf.w - f.w, f.x + (dx or 0)))
                    local ny = math.max(sf.y, math.min(sf.y + sf.h - f.h, f.y + (dy or 0)))
                    _oskView:frame({ x = nx, y = ny, w = f.w, h = f.h })
                end)
            end

            ms.shell.osk._recv = function(body, senderView)
                if type(body) ~= "table" or not body.op then return end
                local op = body.op
                if op == "open" then ms.shell.osk.show(senderView, body)
                elseif op == "render" then ms.shell.osk.render(body)
                elseif op == "close" then ms.shell.osk.hide()
                elseif op == "move" then ms.shell.osk.move(body.dx, body.dy) end
            end

            ms.shell.osk._retheme = _oskTheme
        -- END --

        -- Bring the shell out of its "js husk" state: flush any JS queued while the
        -- bridge was still coming up, then push the host-owned content (settings and
        -- the theme/sound/macro shelves) into the panels. Idempotent -- guarded by
        -- _shellHydrated so it runs exactly once per shell instance no matter how many
        -- signals fire it.
        --
        -- Why more than one caller: the page's own `ready` post (ms_shell.html
        -- DOMContentLoaded) is a single fire-and-forget that races the WebView2 bring-up
        -- AND waits on the whole inlined UI bundle parsing first, so it can be dropped or
        -- land after the show() timeout -- and when it's lost, hydration never ran and the
        -- shell sat as a bare frame. The `selfTest` diagnostic, by contrast, round-trips
        -- reliably every session, so it (and the show() timeout fallback) also drive this.
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
                -- Proactively push every installed-library kind now that the bus is
                -- definitely wired. The manager panels each fire a one-shot request()
                -- during HTML load, which can beat the host's "ui:library:*" subscription
                -- and be dropped -- leaving Installed Macro Packs (and the theme/sound
                -- shelves) empty until a reload. This re-push does not depend on that
                -- early request landing.
                if ms.ui and ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end)
        end
        ms.shell._hydrate = _hydrateShell

        -- Base (100%-zoom) minimum window sizes. The live floor is these
        -- scaled by ms._uiZoom, so a zoomed-in UI needs a bigger window and a
        -- zoomed-out one can go smaller. Shared by the resize math and the
        -- zoom rescaler below.
        local BASE_SHELL_W, BASE_SHELL_H = 800, 500
        local BASE_POP_W,   BASE_POP_H   = 460, 320
        ms._shellBaseMin = { w = BASE_SHELL_W, h = BASE_SHELL_H }
        ms._popBaseMin   = { w = BASE_POP_W,   h = BASE_POP_H }

        -- applyZoom --
            -- Set the global UI zoom, applied uniformly to the shell and every
            -- popout via CSS `zoom` (documentElement). Rescales open window
            -- frames proportionally so apparent content size is preserved, and
            -- clamps to the new zoom-scaled minimum. Range 0.5–2.0.
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

        -- isReady --
            ms.shell.isReady = function() return _shellReady end
            ms.shell.webview = function() return _shellView end
            -- Whether the shell window is actually on screen right now. Used so
            -- a live settings reload (profile switch / pack hotswap) reflects the
            -- shell's real state instead of forcing it "closed" — otherwise the
            -- shell stays visible but its toggle thinks it is hidden and re-runs
            -- the open sequence on the next Alt+P.
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

                    -- DIAGNOSTIC: bridge self-test. Driven from the Lua side via a
                    -- direct window.chrome.webview.postMessage (see the probe eval after
                    -- :html), bypassing the app's window.webkit API. If this branch
                    -- prints, page->Lua transport WORKS and the payload tells us whether
                    -- our webkit-shim installed; if it never prints, the COM receive path
                    -- is broken despite correct vtable offsets.
                    if panel == "_shell" and action == "selfTest" then
                        local b = body or {}
                        print(string.format(
                            "[shell] BRIDGE SELF-TEST RECEIVED: hasChrome=%s webkitType=%s hasMsgHandlers=%s",
                            tostring(b.hasChrome), tostring(b.webkitType), tostring(b.hasMsgHandlers)))
                        -- The self-test proves the page->Lua bridge is live. If the page's
                        -- own `ready` post was lost in the bring-up race, this is our
                        -- reliable second signal to hydrate the panels.
                        _hydrateShell()
                        return
                    end

                    if panel == "_shell" and action == "ready" then
                        _hydrateShell()
                        if ms._shellState and ms._shellState.visible and _shellView then
                            local view = _shellView
                            local step, steps = 0, 30
                            local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                            _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                                step = step + 1
                                pcall(function() view:alpha(step / steps) end)
                                if step >= steps then
                                    if _shellFadeTimer then
                                        _shellFadeTimer:stop()
                                        _shellFadeTimer = nil
                                    end
                                end
                            end)
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
                            -- Follow controller focus into the freshly popped
                            -- window so the same bind that opened it lands there.
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

                -- DIAGNOSTIC: bridge self-test probe. evaluateJavaScript (Lua->page) is
                -- known to work; this pushes a message back OUT through WebView2's native
                -- window.chrome.webview.postMessage, bypassing the app's window.webkit
                -- API entirely, and reports whether our webkit-shim installed. Handled in
                -- the channel callback above (action "selfTest"). Runs late enough that
                -- the page (and any AddScriptToExecuteOnDocumentCreated) has initialized.
                hs.timer.doAfter(0.6, function()
                    if not _shellView then return end
                    pcall(function() _shellView:evaluateJavaScript([[
                        (function(){
                          try{
                            var cw = window.chrome && window.chrome.webview;
                            var payload = {
                              hasChrome: !!cw,
                              webkitType: typeof window.webkit,
                              hasMsgHandlers: !!(window.webkit && window.webkit.messageHandlers)
                            };
                            if(cw){ cw.postMessage(JSON.stringify(
                              {panel:'_shell', action:'selfTest', body:payload})); }
                          }catch(e){}
                        })();
                    ]]) end)
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
                print("[shell] TRACE show() ENTER visible=" .. tostring(ms._shellState and ms._shellState.visible))
                if not (ms._shellState and ms._shellState.visible) then
                    local front = hs.application.frontmostApplication()
                    if front and front:bundleID() ~= hs.processInfo.bundleID then
                        ms._shellPrevApp = front
                    end
                end
                if not _shellView then ms.shell.init() end
                if _shellFadeTimer then
                    _shellFadeTimer:stop()
                    _shellFadeTimer = nil
                end
                ms.shell._restoreFrame()
                if ms.syncExitCurtainFrame then pcall(ms.syncExitCurtainFrame) end
                pcall(function() ms.playSlot("settingsOpen") end)
                _shellView:alpha(0)
                ms.safeShow(_shellView)
                pcall(function() _shellView:bringToFront(true) end)
                pcall(hs.focus)
                ms._shellState = ms._shellState or {}
                ms._shellState.visible = true
                if ms.ui then ms.ui._open = true end
                if ms.bus then ms.bus.emit("macroLab:toggled", { visible = true }) end

                local view = _shellView
                local function _fadeIn()
                    local step, steps = 0, 30
                    local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                    _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                        step = step + 1
                        pcall(function() view:alpha(step / steps) end)
                        if step >= steps then
                            if _shellFadeTimer then
                                _shellFadeTimer:stop()
                                _shellFadeTimer = nil
                            end
                        end
                    end)
                end

                -- The window is shown at alpha 0 above; it only becomes visible when we
                -- fade it in. Originally that was gated on `_shellReady` (the page's JS
                -- "ready" post). If the page->Lua bridge never delivers that message
                -- (e.g. a broken WKWebView-vs-WebView2 transport), the shell would stay
                -- invisible FOREVER despite being open. So: fade in now if ready, else
                -- poll briefly and fall back to fading in anyway after a timeout -- and
                -- log it, so a missing handshake is diagnosable instead of silent.
                if _shellReady then
                    _fadeIn()
                else
                    if _shellReadyWait then _shellReadyWait:stop() end
                    local waited = 0
                    _shellReadyWait = hs.timer.doEvery(0.1, function()
                        waited = waited + 0.1
                        if _shellReady then
                            if _shellReadyWait then _shellReadyWait:stop(); _shellReadyWait = nil end
                            _fadeIn()
                        elseif waited >= 1.5 then
                            if _shellReadyWait then _shellReadyWait:stop(); _shellReadyWait = nil end
                            print("[shell] ready handshake timed out (1.5s) -- forcing "
                                .. "visible and hydrating anyway; page->Lua bridge may be slow")
                            -- Last-resort: neither `ready` nor `selfTest` reached us in
                            -- time, but the bridge may simply be slow. Hydrate now so the
                            -- shell isn't left a bare frame; idempotent if a signal lands
                            -- moments later.
                            _hydrateShell()
                            _fadeIn()
                        end
                    end)
                end
            end
        -- END --

        -- hide --
            ms.shell.hide = function()
                print("[shell] TRACE hide() ENTER visible=" .. tostring(ms._shellState and ms._shellState.visible))
                pcall(function() ms.shell.osk.hide() end)
                if _shellView then
                    if _shellFadeTimer then
                        _shellFadeTimer:stop()
                        _shellFadeTimer = nil
                    end
                    if ms._shellState and ms._shellState.visible then
                        pcall(function() ms.playSlot("settingsClose") end)
                    end
                    ms.shell.saveState()
                    ms._shellState = ms._shellState or {}
                    ms._shellState.visible = false
                    if ms.ui then ms.ui._open = false end
                    local view = _shellView
                    local startAlpha = 1
                    pcall(function() startAlpha = view:alpha() or 1 end)
                    local step, steps = 0, 30
                    local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                    _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                        step = step + 1
                        pcall(function() view:alpha(startAlpha * (1 - (step / steps))) end)
                        if step >= steps then
                            if _shellFadeTimer then
                                _shellFadeTimer:stop()
                                _shellFadeTimer = nil
                            end
                            pcall(function() view:hide() end)
                            if ms._shellPrevApp then
                                pcall(function() ms._shellPrevApp:activate() end)
                                ms._shellPrevApp = nil
                            end
                        end
                    end)
                    if ms.bus then ms.bus.emit("macroLab:toggled", { visible = false }) end
                end
            end
        -- END --

        -- toggle --
            ms.shell.toggle = function()
                local isOpen = ms._shellState and ms._shellState.visible
                -- DIAGNOSTIC: live timer count + toggle wall-time. If the count climbs
                -- every toggle, a repeating timer is leaking onto the single pump (which
                -- would make every toggle progressively laggier). Flat count => the lag
                -- is on the WebView2 / pump-wake side, not a timer leak.
                local _tc = (hs.timer._activeCount and hs.timer._activeCount()) or -1
                local _t0 = hs.timer.secondsSinceEpoch()
                if _shellView and isOpen then
                    ms.shell.hide()
                else
                    ms.shell.show()
                end
                local _dt = (hs.timer.secondsSinceEpoch() - _t0) * 1000
                print(string.format("[shell] toggle %s: liveTimers=%d, took %.1fms",
                    isOpen and "hide" or "show", _tc, _dt))
            end
        -- END --

        -- Gamepad Nav --
            ms._gpNav = ms._gpNav or {}

            local GP_DZ = 0.5

            -- Controller focus routes to one window at a time: the shell, or a
            -- popped-out panel (ms._gpNav.target holds its panel id). Every nav
            -- command is evaluated into whichever window currently holds focus.
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

            -- Reset a window's nav state and take controller focus into it,
            -- raising it so the user sees where the cursor went.
            local function _gpNavAlert(text)
                pcall(function() ms.alert(text, 2.2, true, { state = true }) end)
            end

            -- Tell a window which controller is driving so the on-screen keyboard
            -- legend can show the right face-button glyphs (Xbox / PlayStation /
            -- Nintendo). Prepended to the nav-init eval on attach and focus.
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
                    if _shellView then pcall(function() _shellView:bringToFront(true) end) end
                    if ms.shell.eval then ms.shell.eval(_gpTypeJs() .. init) end
                    _gpNavAlert("Focused shell")
                end
            end

            -- The pop-out / window-switch bind (Options double-tap). Toggle
            -- controller focus between the shell and a popped-out panel; if none
            -- is open yet, pop the current shell panel out and follow it.
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
                    -- Nothing popped yet: ask the shell to pop its current panel.
                    -- The popOut dispatch handler follows focus into the new window.
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
                for _, k in ipairs({ "lsTimer", "rsTimer", "holdTimer", "holdTimerX", "tapTimer" }) do
                    if n[k] then n[k]:stop() n[k] = nil end
                end
                n.lsDir = nil
                n.rsActive = false
                n.xGrab = false
                n.selectHeld = false
                n.tapPending = false
                n.chordConsumed = false
            end

            -- Menu+Options is the open/close toggle. While the shell is open the
            -- nav handler consumes both buttons (for the rail and the top bar), so
            -- the global open chord can't see them — the close has to happen here,
            -- cancelling any pending single-button action so it doesn't also fire.
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

                if button == "options" then
                    if a and a.menu then _gpCloseViaChord(n) return true end
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
                    if a and a.options then _gpCloseViaChord(n) return true end
                    _gpEval("toggleRail")
                    return true
                elseif button == "up" or button == "down" or button == "left" or button == "right" then
                    if n.selectHeld then
                        if button == "up" or button == "right" then _gpZoom(0.1) else _gpZoom(-0.1) end
                    else
                        local map = { up = "itemUp", down = "itemDown", left = "itemLeft", right = "itemRight" }
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
                    if ms.shell and ms.shell.toggle then ms.shell.toggle() end
                end
                ms._gpOpenBind = ms.gamepadBind({ "menu", "options" }, _toggle)
                ms._gpOpenBind2 = ms.gamepadBind({ "home" }, _toggle)
            end

            ms.shell.gpClearOpenBind = function()
                if ms._gpOpenBind and ms._gpOpenBind.delete then pcall(ms._gpOpenBind.delete) end
                if ms._gpOpenBind2 and ms._gpOpenBind2.delete then pcall(ms._gpOpenBind2.delete) end
                ms._gpOpenBind = nil
                ms._gpOpenBind2 = nil
            end

            local function _gpAttach()
                _gpStopTimers()
                ms._gpNav.target = "shell"
                ms._gamepadCallbacks = ms._gamepadCallbacks or {}
                ms._gamepadCallbacks._nav = ms.shell._gpNavHandler
                -- Force out of top-bar mode on every open. Eval once now and once
                -- after a beat: if show() just reloaded the webview, gpNavInit may
                -- not exist yet at this instant, so the delayed call is what
                -- actually clears a persisted top-bar state.
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

        -- destroy --
            ms.shell.destroy = function()
                if _shellFadeTimer then
                    _shellFadeTimer:stop()
                    _shellFadeTimer = nil
                end
                if ms._shellDragTap then
                    ms._shellDragTap:stop()
                    ms._shellDragTap = nil
                end
                if ms._shellResizeTap then
                    ms._shellResizeTap:stop()
                    ms._shellResizeTap = nil
                end
                ms._shellDragging = false
                if _oskView then
                    pcall(function() _oskView:delete() end)
                    _oskView = nil
                end
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

        local _popouts = {}
        local _popResizeTaps = {}
        local _popDragTaps = {}

        -- Broadcasts to the general panel popouts (browse, appearance, tools,
        -- profiles, macros …). These live in _popouts and, unlike the four dev
        -- panels, are NOT covered by ms.dev:recolor / ms.dev:rezoom — so theme
        -- changes and zoom changes must be pushed to them here too. Called
        -- from applyZoom above (via ms.shell) and from the theme-change sites.
        ms.shell.recolorPopouts = function()
            local themeJson = hs.json.encode(ms.theme.effective())
            for _, pop in pairs(_popouts) do
                if pop and pop.view then
                    pcall(function()
                        pop.view:evaluateJavaScript(
                            "applyTheme(" .. themeJson .. ")")
                    end)
                end
            end
        end

        -- Re-round the shell window and every open popout to the current theme
        -- corner radius. Called after a live theme change so the native window
        -- frame tracks the Appearance "Corner radius" slider instead of staying
        -- at the value baked in when the window was first opened.
        ms.shell.applyWindowRadius = function()
            if not (ms.theme and ms.theme.applyWindowRadius) then return end
            if _shellView then
                pcall(function() ms.theme.applyWindowRadius(_shellView) end)
            end
            for _, pop in pairs(_popouts) do
                if pop and pop.view then
                    pcall(function() ms.theme.applyWindowRadius(pop.view) end)
                end
            end
        end

        ms.shell._rezoomPopouts = function(z, ratio, noRescale)
            z = tonumber(z) or 1.0
            ratio = tonumber(ratio) or 1.0
            local minW, minH = BASE_POP_W * z, BASE_POP_H * z
            local js = "if(window.applyZoom)applyZoom(" .. z .. ")"
            for _, pop in pairs(_popouts) do
                if pop and pop.view then
                    if not noRescale and math.abs(ratio - 1) > 0.001 then
                        pcall(function()
                            local f = pop.view:frame()
                            local nf = { x = f.x, y = f.y,
                                         w = f.w * ratio, h = f.h * ratio }
                            if nf.w < minW then nf.w = minW end
                            if nf.h < minH then nf.h = minH end
                            pop.view:frame(nf)
                        end)
                    end
                    pcall(function() pop.view:evaluateJavaScript(js) end)
                end
            end
        end

        -- finderInterlude --
        -- Runs `fn` (a blocking Finder panel) with the shell and popouts hidden,
        -- then restores them.
        ms.shell.finderInterlude = function(fn)
            local restore = {}
            if _shellView and ms._shellState and ms._shellState.visible then
                if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                pcall(function() _shellView:hide() end)
                restore.shell = true
            end
            for _, pop in pairs(_popouts) do
                if pop and pop.view then
                    local vis = false
                    pcall(function()
                        local w = pop.view:hswindow()
                        vis = w ~= nil and w:isVisible()
                    end)
                    if vis then
                        pcall(function() pop.view:hide() end)
                        restore[#restore + 1] = pop.view
                    end
                end
            end

            hs.focus()  -- bring the panel's host (Hammerspoon) frontmost
            local ok, a, b, c = pcall(fn)

            if restore.shell then
                pcall(function() ms.safeShow(_shellView) end)
                pcall(function() _shellView:bringToFront(true) end)
            end
            for _, view in ipairs(restore) do
                pcall(function() ms.safeShow(view) end)
                pcall(function() view:bringToFront(true) end)
            end

            if not ok then error(a) end
            return a, b, c
        end

        -- Route every Finder file/folder panel through the interlude, once.
        if hs.dialog and type(hs.dialog.chooseFileOrFolder) == "function"
            and not hs.dialog._msFinderShimInstalled then
            local _origChoose = hs.dialog.chooseFileOrFolder
            hs.dialog.chooseFileOrFolder = function(...)
                local args = table.pack(...)
                return ms.shell.finderInterlude(function()
                    return _origChoose(table.unpack(args, 1, args.n))
                end)
            end
            hs.dialog._msFinderShimInstalled = true
        end
        local _panelFiles = {
            console = "ms_console.html",
            watcher = "ms_watcher.html",
            keys    = "ms_keys.html",
            window  = "ms_window.html",
        }

        local _popAnimTimers = {}
        -- animatePopWindow --
            -- easing: p (0..1) -> eased t. Defaults to ease-out cubic, which
            -- decelerates into the final frame — the gentle settle lands while
            -- the window is fully visible, so it reads well for growing OUT.
            -- The close animation is the temporal reverse, so it passes an
            -- ease-IN instead (see popIn) to keep the gentle motion on the
            -- still-visible end rather than after it has faded away.
            local function animatePopWindow(panelId, view, fromFrame, toFrame, fromAlpha, toAlpha, onDone, easing)
                if _popAnimTimers[panelId] then
                    _popAnimTimers[panelId]:stop()
                    _popAnimTimers[panelId] = nil
                end

                local step, steps = 0, 30
                local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                local ease = easing or function(p) return 1 - (1 - p) ^ 3 end

                _popAnimTimers[panelId] = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                    step = step + 1
                    local t = ease(step / steps)

                    pcall(function()
                        view:frame({
                            x = fromFrame.x + (toFrame.x - fromFrame.x) * t,
                            y = fromFrame.y + (toFrame.y - fromFrame.y) * t,
                            w = fromFrame.w + (toFrame.w - fromFrame.w) * t,
                            h = fromFrame.h + (toFrame.h - fromFrame.h) * t,
                        })
                        view:alpha(fromAlpha + (toAlpha - fromAlpha) * t)
                    end)

                    if step >= steps then
                        if _popAnimTimers[panelId] then
                            _popAnimTimers[panelId]:stop()
                            _popAnimTimers[panelId] = nil
                        end
                        if onDone then onDone() end
                    end
                end)
            end
        -- END --

        -- _buildThemeCSS --
            local function _buildThemeCSS()
                local t = ms._theme or {}
                local d = ms._themeDefaults or {}
                local function v(k) return t[k] or d[k] end
                local parts = {}
                local map = {
                    bg = "--bg", surface = "--surface", surface2 = "--surface2",
                    hover = "--hover", accent = "--accent", accentHi = "--accent-hi",
                    success = "--success", dangerBg = "--danger-bg", danger = "--danger",
                    warning = "--warning", text = "--text",
                    accentGlow = "--accent-glow", accentGlowFaint = "--accent-glow-faint",
                    dangerGlow = "--danger-glow", dangerBorder = "--danger-border",
                    mouse = "--mouse", scroll = "--scroll", key = "--key",
                    recording = "--recording", recordingText = "--recording-text",
                    recordingBg = "--recording-bg", running = "--running",
                    runningText = "--running-text", runningBg = "--running-bg",
                    borderFaint = "--border-faint", surface3 = "--surface3",
                    successBg = "--success-bg", successState = "--success-state",
                    successText = "--success-text", errorBg = "--error-bg",
                    errorState = "--error-state", errorText = "--error-text",
                    fontMono = "--font-mono",
                }
                for k, cssVar in pairs(map) do
                    local val = v(k)
                    if val then parts[#parts + 1] = cssVar .. ":" .. val end
                end
                local function hexRgb(hex)
                    if not hex or type(hex) ~= "string" then return nil end
                    hex = hex:gsub("#", "")
                    if #hex == 3 then
                        hex = hex:sub(1,1):rep(2) .. hex:sub(2,2):rep(2) .. hex:sub(3,3):rep(2)
                    end
                    if #hex ~= 6 and #hex ~= 8 then return nil end
                    local r = tonumber(hex:sub(1,2), 16)
                    local g = tonumber(hex:sub(3,4), 16)
                    local b = tonumber(hex:sub(5,6), 16)
                    if not r or not g or not b then return nil end
                    local a = 1
                    if #hex == 8 then
                        local av = tonumber(hex:sub(7,8), 16)
                        if av then a = av / 255 end
                    end
                    return r, g, b, a
                end
                local tr, tg, tb, ta = hexRgb(v("text"))
                if tr then
                    if not t.text2 then parts[#parts + 1] = ("--text2:rgba(%d,%d,%d,%g)"):format(tr, tg, tb, 0.85 * ta) end
                    if not t.text3 then parts[#parts + 1] = ("--text3:rgba(%d,%d,%d,%g)"):format(tr, tg, tb, 0.55 * ta) end
                end
                if not t.accentGlow then
                    local ar2, ag2, ab2, aa2 = hexRgb(v("accent"))
                    if ar2 then parts[#parts + 1] = ("--accent-glow:rgba(%d,%d,%d,%g)"):format(ar2, ag2, ab2, 0.4 * aa2) end
                end
                if not t.accentGlowFaint then
                    local ar3, ag3, ab3, aa3 = hexRgb(v("accent"))
                    if ar3 then parts[#parts + 1] = ("--accent-glow-faint:rgba(%d,%d,%d,%g)"):format(ar3, ag3, ab3, 0.12 * aa3) end
                end
                if not t.dangerGlow then
                    local dr2, dg2, db2, da2 = hexRgb(v("danger"))
                    if dr2 then parts[#parts + 1] = ("--danger-glow:rgba(%d,%d,%d,%g)"):format(dr2, dg2, db2, 0.6 * da2) end
                end
                if not t.dangerBorder then
                    local dr3, dg3, db3, da3 = hexRgb(v("danger"))
                    if dr3 then parts[#parts + 1] = ("--danger-border:rgba(%d,%d,%d,%g)"):format(dr3, dg3, db3, 0.3 * da3) end
                end
                if not t.border then
                    local ar, ag, ab, aa = hexRgb(v("accent"))
                    local hr, hg, hb, ha = hexRgb(v("hover"))
                    if ar and hr then
                        local mr, mg, mb = math.floor((ar+hr)/2), math.floor((ag+hg)/2), math.floor((ab+hb)/2)
                        local ma = (aa + ha) / 2
                        parts[#parts + 1] = ("--border:rgba(%d,%d,%d,%g)"):format(mr, mg, mb, 0.55 * ma)
                        parts[#parts + 1] = ("--border-dim:rgba(%d,%d,%d,%g)"):format(mr, mg, mb, 0.18 * ma)
                        if not t.borderFaint then
                            parts[#parts + 1] = ("--border-faint:rgba(%d,%d,%d,%g)"):format(mr, mg, mb, 0.07 * ma)
                        end
                    end
                end
                if not t.surface3 then
                    local sr, sg, sb = hexRgb(v("surface2"))
                    local hr2, hg2, hb2 = hexRgb(v("hover"))
                    if sr and hr2 then
                        local mr2 = math.floor((sr + hr2) / 2)
                        local mg2 = math.floor((sg + hg2) / 2)
                        local mb2 = math.floor((sb + hb2) / 2)
                        parts[#parts + 1] = ("--surface3:#%02x%02x%02x"):format(mr2, mg2, mb2)
                    end
                end
                if not t.successBg then
                    local sur, sug, sub, sua = hexRgb(v("success"))
                    if sur then parts[#parts + 1] = ("--success-bg:rgba(%d,%d,%d,%g)"):format(sur, sug, sub, 0.15 * sua) end
                end
                if not t.successState then
                    parts[#parts + 1] = "--success-state:" .. v("success")
                end
                if not t.successText then
                    parts[#parts + 1] = "--success-text:" .. v("accentHi")
                end
                if not t.errorBg then
                    local dr4, dg4, db4, da4 = hexRgb(v("danger"))
                    if dr4 then parts[#parts + 1] = ("--error-bg:rgba(%d,%d,%d,%g)"):format(dr4, dg4, db4, 0.15 * da4) end
                end
                if not t.errorState then
                    parts[#parts + 1] = "--error-state:" .. v("danger")
                end
                if not t.errorText then
                    parts[#parts + 1] = "--error-text:" .. v("danger")
                end
                local radius = v("radius") or 4
                parts[#parts + 1] = "--radius:" .. radius .. "px"
                parts[#parts + 1] = "--radius-s:" .. math.max(0, radius - 1) .. "px"
                local font = v("font")
                if font then
                    parts[#parts + 1] = "--font:\"" .. font .. "\",Almendra,Palatino,Georgia,serif"
                end
                return ":root{" .. table.concat(parts, ";") .. "}"
            end
        -- END --

        -- bakePopOuts --
            ms.shell.bakePopOuts = function()
                local themeCSS = _buildThemeCSS()
                local r = (ms._theme and (ms._theme.windowRadius or ms._theme.radius))
                    or (ms._themeDefaults and (ms._themeDefaults.windowRadius or ms._themeDefaults.radius))
                    or 0
                for pid, fileName in pairs(_panelFiles) do
                    local srcPath = hs.configdir .. "/ui/" .. fileName
                    local f = io.open(srcPath, "r")
                    if f then
                        local html = f:read("*all")
                        f:close()
                        local inject = string.format(
                            '<style>html,body{background:transparent!important;overflow:hidden;}'
                            .. '#popout-root{display:flex;flex-direction:column;'
                            .. 'width:100%%;height:100%%;'
                            .. 'background:var(--bg);border-radius:%dpx;overflow:hidden;'
                            .. 'box-shadow:inset 0 0 0 1px var(--border,rgba(255,255,255,0.09));}'
                            .. ':root{--ms-window-radius:%dpx;}'
                            .. '.resize-zone{position:fixed;z-index:9999;background:transparent;'
                            .. 'transition:background 0.12s ease;}'
                            .. '.resize-zone:hover{background:var(--accent-glow-faint);}'
                            .. '.resize-n{top:0;left:18px;right:18px;height:9px;cursor:ns-resize;}'
                            .. '.resize-s{bottom:0;left:18px;right:18px;height:9px;cursor:ns-resize;}'
                            .. '.resize-e{right:0;top:18px;bottom:18px;width:9px;cursor:ew-resize;}'
                            .. '.resize-w{left:0;top:18px;bottom:18px;width:9px;cursor:ew-resize;}'
                            .. '.resize-ne{top:0;right:0;width:18px;height:18px;cursor:nesw-resize;}'
                            .. '.resize-nw{top:0;left:0;width:18px;height:18px;cursor:nwse-resize;}'
                            .. '.resize-se{bottom:0;right:0;width:18px;height:18px;cursor:nwse-resize;}'
                            .. '.resize-sw{bottom:0;left:0;width:18px;height:18px;cursor:nesw-resize;}'
                            .. 'body.resizing *{pointer-events:none!important;}'
                            .. '%s</style>',
                            r, r, themeCSS
                        )
                        html = html:gsub("</head>", inject:gsub("%%", "%%%%") .. "</head>", 1)
                        local resizeZones =
                            '<div class="resize-zone resize-n" data-edge="n"></div>'
                            .. '<div class="resize-zone resize-s" data-edge="s"></div>'
                            .. '<div class="resize-zone resize-e" data-edge="e"></div>'
                            .. '<div class="resize-zone resize-w" data-edge="w"></div>'
                            .. '<div class="resize-zone resize-ne" data-edge="ne"></div>'
                            .. '<div class="resize-zone resize-nw" data-edge="nw"></div>'
                            .. '<div class="resize-zone resize-se" data-edge="se"></div>'
                            .. '<div class="resize-zone resize-sw" data-edge="sw"></div>'
                        html = html:gsub("(<body[^>]*>)", "%1" .. resizeZones .. "<div id='popout-root'>")
                        html = html:gsub("(</body>)", "</div>%1")
                        local tmpName = hs.configdir .. "/ui/_popout_" .. pid .. ".html"
                        local wf = io.open(tmpName, "w")
                        if wf then
                            wf:write(html)
                            wf:close()
                        end
                    end
                end
            end
        -- END --

        ms.shell.bakePopOuts()

        if ms.loadTheme then
            local _origLoadTheme = ms.loadTheme
            ms.loadTheme = function()
                _origLoadTheme()
                pcall(ms.shell.bakePopOuts)
                pcall(ms.shell.osk._retheme)
            end
        end

        -- getPopOutView --
            ms.shell.getPopOutView = function(panelId)
                local pop = _popouts[panelId]
                return pop and pop.view or nil
            end
        -- END --

        -- popOut --
            ms.shell.popOut = function(panelId)
                if _popouts[panelId] then
                    ms.safeShow(_popouts[panelId].view)
                    pcall(function() _popouts[panelId].view:bringToFront(true) end)
                    hs.timer.doAfter(0.1, function()
                        pcall(function() _popouts[panelId].view:bringToFront(true) end)
                    end)
                    return true
                end
                local tmpName = hs.configdir .. "/ui/_popout_" .. panelId .. ".html"
                local f = io.open(tmpName, "r")
                if not f then
                    ms.shell.bakePopOuts()
                    f = io.open(tmpName, "r")
                    if not f then
                        print("[popOut] no baked file for panel: " .. tostring(panelId))
                        return false
                    end
                end
                f:close()

                require("hs.webview")
                require("hs.webview.usercontent")

                local sf = hs.screen.mainScreen():frame()
                local w, h = 650, 450
                local x = sf.x + math.floor((sf.w - w) / 2) + 40
                local y = sf.y + math.floor((sf.h - h) / 2) + 40

                local popChannel = hs.webview.usercontent.new(panelId)
                local popView
                popChannel:setCallback(function(message)
                    local ok, data = pcall(hs.json.decode, message.body or "")
                    if not ok or type(data) ~= "table" then return end
                    local panel  = data.panel  or panelId
                    local action = data.action or "unknown"
                    local body   = data.body or data
                    if action == "playSlot" and body and body.slot then
                        pcall(function() ms.playSlot(body.slot) end)
                        return
                    end
                    if action == "osk" then
                        if ms.shell.osk and ms.shell.osk._recv then
                            ms.shell.osk._recv(body, popView)
                        end
                        return
                    end
                    if action == "close" then
                        -- Hand controller focus back to the shell when the window
                        -- it was pointing at closes (e.g. Back at the popout root).
                        if ms._gpNav then
                            if ms._gpNav.popPanel == panelId then ms._gpNav.popPanel = nil end
                            if ms._gpNav.target == panelId and ms.shell._gpFocusWindow
                                and ms._gamepadCallbacks and ms._gamepadCallbacks._nav then
                                ms.shell._gpFocusWindow("shell")
                            end
                        end
                        if _popResizeTaps and _popResizeTaps[panelId] then
                            _popResizeTaps[panelId]:stop()
                            _popResizeTaps[panelId] = nil
                        end
                        if _popDragTaps and _popDragTaps[panelId] then
                            _popDragTaps[panelId]:stop()
                            _popDragTaps[panelId] = nil
                        end
                        ms._shellDragging = false
                        _popouts[panelId] = nil

                        local endFrame = nil
                        pcall(function() endFrame = popView:frame() end)
                        if _shellView then
                            pcall(function()
                                local sf = _shellView:frame()
                                if sf then endFrame = sf end
                            end)
                        end
                        if endFrame then
                            pcall(function()
                                animatePopWindow(panelId, popView, popView:frame(), endFrame, 1, 0, function()
                                    pcall(function() popView:hide() end)
                                end, function(p) return p ^ 3 end)
                            end)
                        else
                            pcall(function() popView:hide() end)
                        end

                        if ms.shell and ms.shell.eval then
                            ms.shell.eval("shellReceive('" .. panelId .. "', 'poppedIn')")
                            hs.timer.doAfter(0.1, function()
                                pcall(function()
                                    ms.bus.emit("ui:" .. panelId .. ":ready", { action = "ready" })
                                end)
                            end)
                        end
                        hs.timer.doAfter(((ms._theme and ms._theme.fadeMs) or 250) / 1000 + 0.1, function()
                            pcall(function() popView:delete() end)
                        end)
                        return
                    end
                    if action == "move" and body and body.dx and body.dy then
                        pcall(function()
                            local f2 = popView:frame()
                            popView:frame({
                                x = f2.x + body.dx,
                                y = f2.y + body.dy,
                                w = f2.w,
                                h = f2.h,
                            })
                        end)
                        return
                    end
                    if action == "dragStart" then
                        pcall(function()
                            local popDragTap = _popDragTaps[panelId]
                            if popDragTap then popDragTap:stop() end
                            ms._shellDragging = true
                            local startFrame = popView:frame()
                            local startMouse = hs.mouse.absolutePosition()
                            local w2, h2 = startFrame.w, startFrame.h
                            local topLimit = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame().y
                            pcall(function() popView:shadow(false) end)
                            local et = hs.eventtap.event.types
                            local tap = hs.eventtap.new(
                                {
                                    et.leftMouseDragged,
                                    et.leftMouseUp,
                                },
                                function(ev)
                                    if not popView then return false end
                                    if ev:getType() == et.leftMouseUp then
                                        if _popDragTaps and _popDragTaps[panelId] then
                                            _popDragTaps[panelId]:stop()
                                            _popDragTaps[panelId] = nil
                                        end
                                        ms._shellDragging = false
                                        pcall(function() popView:shadow(true) end)
                                        return false
                                    end
                                    local mp = hs.mouse.absolutePosition()
                                    pcall(function()
                                        popView:frame({
                                            x = startFrame.x + (mp.x - startMouse.x),
                                            y = math.max(startFrame.y + (mp.y - startMouse.y), topLimit),
                                            w = w2,
                                            h = h2,
                                        })
                                    end)
                                    return false
                                end)
                            _popDragTaps[panelId] = tap
                            tap:start()
                        end)
                        return
                    end
                    if action == "moveEnd" then
                        pcall(function()
                            if _popDragTaps and _popDragTaps[panelId] then
                                _popDragTaps[panelId]:stop()
                                _popDragTaps[panelId] = nil
                            end
                            ms._shellDragging = false
                            pcall(function() popView:shadow(true) end)
                        end)
                        return
                    end
                    if action == "resizeStart" and body and body.edge then
                        pcall(function()
                            local popResizeTap = _popResizeTaps[panelId]
                            if popResizeTap then popResizeTap:stop() end
                            ms._shellDragging = true
                            local edge = body.edge
                            local startFrame = popView:frame()
                            local startMouse = hs.mouse.absolutePosition()
                            local _z = ms._uiZoom or 1.0
                            local MIN_W, MIN_H = BASE_POP_W * _z, BASE_POP_H * _z
                            local resScreen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
                            local topLimit = resScreen:frame().y
                            pcall(function() popView:shadow(false) end)
                            local et = hs.eventtap.event.types
                            local tap = hs.eventtap.new(
                                {
                                    et.leftMouseDragged,
                                    et.leftMouseUp,
                                },
                                function(ev)
                                    if not popView then return false end
                                    if ev:getType() == et.leftMouseUp then
                                        if _popResizeTaps and _popResizeTaps[panelId] then
                                            _popResizeTaps[panelId]:stop()
                                            _popResizeTaps[panelId] = nil
                                        end
                                        ms._shellDragging = false
                                        pcall(function() popView:shadow(true) end)
                                        return false
                                    end
                                    local mp = hs.mouse.absolutePosition()
                                    local dx = mp.x - startMouse.x
                                    local dy = mp.y - startMouse.y
                                    local nf = ms._resizeEdgeMath(edge, startFrame, dx, dy, MIN_W, MIN_H)
                                    if nf.y < topLimit then
                                        nf.h = nf.h - (topLimit - nf.y)
                                        nf.y = topLimit
                                        if nf.h < MIN_H then nf.h = MIN_H end
                                    end
                                    pcall(function() popView:frame(nf) end)
                                    return false
                                end)
                            _popResizeTaps[panelId] = tap
                            tap:start()
                        end)
                        return
                    end
                    if action == "clampSize" and body and body.w and body.h then
                        pcall(function()
                            local f2 = popView:frame()
                            if f2.w < body.w or f2.h < body.h then
                                popView:frame({
                                    x = f2.x,
                                    y = f2.y,
                                    w = math.max(f2.w, body.w),
                                    h = math.max(f2.h, body.h),
                                })
                            end
                        end)
                        return
                    end
                    if ms.bus then
                        ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                    end
                end)

                local startFrame = {
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                }
                if _shellView then
                    pcall(function()
                        local sf = _shellView:frame()
                        if sf then startFrame = sf end
                    end)
                end

                popView = hs.webview.new(startFrame, {}, popChannel)
                if not popView then
                    print("[popOut] hs.webview.new returned nil")
                    return false
                end
                pcall(function()
                    local M = hs.webview.windowMasks or {}
                    popView:windowStyle((M.borderless or 0) + (M.nonactivating or 128))
                end)
                pcall(function() popView:transparent(true) end)
                pcall(function() popView:level((hs.canvas.windowLevels.popUpMenu or 101) + 1) end)
                pcall(function() popView:allowTextEntry(true) end)
                pcall(function() popView:shadow(true) end)
                pcall(function()
                    popView:minimumSize({
                        w = 400,
                        h = 300,
                    })
                end)
                pcall(function() popView:allowResizing(true) end)

                local _grewIn = false
                local function _growIn()
                    if _grewIn or not popView then return end
                    _grewIn = true
                    animatePopWindow(panelId, popView, startFrame, {
                        x = x,
                        y = y,
                        w = w,
                        h = h,
                    }, 0, 1, nil)
                end
                pcall(function()
                    popView:navigationCallback(function(act)
                        if act == "didFinishNavigation" then _growIn() end
                    end)
                end)
                popView:url("file://" .. tmpName)
                popView:alpha(0)
                ms.safeShow(popView)
                hs.timer.doAfter(0.6, _growIn)
                hs.timer.doAfter(0.15, function()
                    pcall(function() popView:bringToFront(true) end)
                end)

                hs.timer.doAfter(0.5, function()
                    if not popView then return end
                    local themeJson = hs.json.encode(ms.theme.effective())
                    pcall(function() popView:evaluateJavaScript("applyTheme(" .. themeJson .. ")") end)
                    -- Inherit the current UI zoom, same as the dev panels do.
                    local z = ms._uiZoom or 1.0
                    if z ~= 1.0 then
                        pcall(function()
                            popView:evaluateJavaScript(
                                "if(window.applyZoom)applyZoom(" .. z .. ")")
                        end)
                    end
                end)

                _popouts[panelId] = {
                    view = popView,
                    channel = popChannel,
                }
                if ms.bus then ms.bus.emit("panel:poppedOut", { id = panelId }) end
                return true
            end
        -- END --

        -- popIn --
            ms.shell.popIn = function(panelId)
                local pop = _popouts[panelId]
                if not pop then return false end
                _popouts[panelId] = nil

                local endFrame = nil
                pcall(function() endFrame = pop.view:frame() end)
                if _shellView then
                    pcall(function()
                        local sf = _shellView:frame()
                        if sf then endFrame = sf end
                    end)
                end
                if endFrame then
                    pcall(function()
                        animatePopWindow(panelId, pop.view, pop.view:frame(), endFrame, 1, 0, function()
                            pcall(function() pop.view:hide() end)
                        end)
                    end)
                else
                    pcall(function() pop.view:hide() end)
                end

                if ms.shell and ms.shell.eval then
                    ms.shell.eval("shellReceive('" .. panelId .. "', 'poppedIn')")
                    hs.timer.doAfter(0.1, function()
                        pcall(function()
                            ms.bus.emit("ui:" .. panelId .. ":ready", { action = "ready" })
                        end)
                    end)
                end
                hs.timer.doAfter(((ms._theme and ms._theme.fadeMs) or 250) / 1000 + 0.1, function()
                    pcall(function() pop.view:delete() end)
                end)
                return true
            end
        -- END --

        -- isPoppedOut --
            ms.shell.isPoppedOut = function(panelId)
                return _popouts[panelId] ~= nil
            end
        -- END --

        -- closePopOuts --
            ms.shell.closePopOuts = function()
                local shellFrame = nil
                if _shellView then pcall(function() shellFrame = _shellView:frame() end) end
                for panelId, pop in pairs(_popouts) do
                    if _popResizeTaps[panelId] then
                        pcall(function() _popResizeTaps[panelId]:stop() end)
                        _popResizeTaps[panelId] = nil
                    end
                    if _popDragTaps[panelId] then
                        pcall(function() _popDragTaps[panelId]:stop() end)
                        _popDragTaps[panelId] = nil
                    end
                    local view = pop.view
                    local target = shellFrame
                    if view and not target then pcall(function() target = view:frame() end) end
                    local function _kill()
                        pcall(function() view:hide() end)
                        pcall(function() view:delete() end)
                    end
                    if view and target then
                        local from = nil
                        pcall(function() from = view:frame() end)
                        if from then
                            pcall(function()
                                animatePopWindow(panelId, view, from, target, 1, 0, _kill)
                            end)
                        else
                            _kill()
                        end
                    elseif view then
                        _kill()
                    end
                    _popouts[panelId] = nil
                end
            end
        -- END --
    end
-- END ms_shell --

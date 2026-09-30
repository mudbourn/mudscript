return function(ms, ctx)
    local _popouts = {}
    local _popResizeTaps = {}
    local _popDragTaps = {}

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

    ms.shell.applyWindowRadius = function()
        if not (ms.theme and ms.theme.applyWindowRadius) then return end
        if ctx.view() then
            pcall(function() ms.theme.applyWindowRadius(ctx.view()) end)
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
        local minW, minH = ms._popBaseMin.w * z, ms._popBaseMin.h * z
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

    ms.shell.finderInterlude = function(fn)
        local restore = {}
        if ctx.view() and ms._shellState and ms._shellState.visible then
            ctx.stopFade()
            pcall(function() ctx.view():hide() end)
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

        hs.focus()
        local ok, a, b, c = pcall(fn)

        if restore.shell then
            pcall(function() ms.safeShow(ctx.view()) end)
            pcall(function() ctx.view():bringToFront(true) end)
        end
        for _, view in ipairs(restore) do
            pcall(function() ms.safeShow(view) end)
            pcall(function() view:bringToFront(true) end)
        end

        if not ok then error(a) end
        return a, b, c
    end

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
                parts[#parts + 1] = "--font:\"" .. font .. "\",Arial,Helvetica,sans-serif"
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
                    if ctx.view() then
                        pcall(function()
                            local sf = ctx.view():frame()
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
                        local MIN_W, MIN_H = ms._popBaseMin.w * _z, ms._popBaseMin.h * _z
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
            if ctx.view() then
                pcall(function()
                    local sf = ctx.view():frame()
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
            if ctx.view() then
                pcall(function()
                    local sf = ctx.view():frame()
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
            if ctx.view() then pcall(function() shellFrame = ctx.view():frame() end) end
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

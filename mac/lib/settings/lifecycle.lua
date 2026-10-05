return function(ms, ctx)
    -- Lifecycle --
        local function _teardown(reason)
            ms._quickReloading = true

            local function step(name, fn)
                local ok, err = pcall(fn)
                if not ok then
                    ms.dev.log({
                        type = "error",
                        event = reason .. "_step_error",
                        step = name,
                        msg = tostring(err),
                    })
                end
            end

            step("macros", function() ms.setMacros(0, true) end)
            step("binds", function() ms.bind.teardown() end)

            step("save", function() ms.saveSettings() end)

            local handles = {
                "_keyListener", "_mouseListener", "_scrollListener",
                "_trackpadLeftListener", "_trackpadRightListener",
                "_appWatcher", "_tapWatchdog", "_menuHoverWatcher",
            }
            for _, key in ipairs(handles) do
                step(key, function()
                    local h = ms[key]
                    if not h then return end
                    if h.stop then h:stop() end
                    if h.delete then h:delete() end
                    ms[key] = nil
                end)
            end
            step("systemBinds", function()
                for _, tap in pairs((ms.systemBinds or {})._handles or {}) do
                    if tap and tap.stop then tap:stop() end
                end
            end)

            step("windows", function()
                if ms.shell and ms.shell.closePopOuts then ms.shell.closePopOuts() end
                if ms.shell and ms.shell.hide then ms.shell.hide() end
                if ms.ui and ms.ui.hide then ms.ui.hide() end
                pcall(function() ms.dev.console.hide() end)
                pcall(function() ms.dev.watcher.hide() end)
                pcall(function() ms.dev.keys.hide() end)
                pcall(function() ms.dev.window.hide() end)
            end)

            step("logs", function() ms.dev:closeLogHandles() end)
        end

        local SLOT_HOLD_MAX = 4.0

        local function _waitForSlot(slotId)
            local wait  = 0.25
            local sound = (ms._slotHandles or {})[slotId]
            local began = (ms._slotStartedAt or {})[slotId]

            if sound and began then
                local ok, dur = pcall(function() return sound:duration() end)
                if ok and type(dur) == "number" and dur == dur
                    and dur > 0 and dur < math.huge then
                    local left = dur - (hs.timer.secondsSinceEpoch() - began)
                    if left > wait then wait = left end
                end
            end

            return math.min(wait, SLOT_HOLD_MAX)
        end

        local function _slotRemaining(slotId)
            local sound = (ms._slotHandles or {})[slotId]
            local began = (ms._slotStartedAt or {})[slotId]
            if sound and began then
                local ok, dur = pcall(function() return sound:duration() end)
                if ok and type(dur) == "number" and dur == dur
                    and dur > 0 and dur < math.huge then
                    local left = dur - (hs.timer.secondsSinceEpoch() - began)
                    if left > 0 then return math.min(left, SLOT_HOLD_MAX) end
                end
            end
            return 0
        end

        local CURTAIN_IN_MS   = 600
        local CURTAIN_FADE_MS = 350

        local CURTAIN_SETTLE_MS = 60

        local CURTAIN_SOUND_FALLBACK_MS = 1400

        local function _shellFrame()
            local view = ms.shell and ms.shell.webview and ms.shell.webview()
            if view then
                local ok, f = pcall(function() return view:frame() end)
                if ok and f and f.w and f.w > 0 and f.h and f.h > 0 then
                    return f
                end
            end

            local sf = hs.screen.mainScreen():frame()
            local w  = math.min(820, math.floor(sf.w * 0.85))
            local h  = math.min(520, math.floor(sf.h * 0.85))
            local st = ms._shellState
            if st and st.w and st.h then
                w, h = math.min(st.w, sf.w), math.min(st.h, sf.h)
            end

            local x = sf.x + math.floor((sf.w - w) / 2)
            local y = sf.y + math.floor((sf.h - h) / 2)
            if st and st.x and st.y then
                x = math.max(sf.x, math.min(st.x, sf.x + sf.w - w))
                y = math.max(sf.y, math.min(st.y, sf.y + sf.h - h))
            end

            return {
                x = x,
                y = y,
                w = w,
                h = h,
            }
        end

        local _CURTAIN_LEVEL = (hs.canvas.windowLevels.screenSaver or 1000) + 1

        local _warmView, _warmLive

        local _onFading

        local function _fading()
            local fn = _onFading
            _onFading = nil
            if fn then pcall(fn) end
        end


        local function _buildCurtain()
            local uc = hs.webview.usercontent.new("curtain")
            uc:setCallback(function(message)
                local decoded, data = pcall(hs.json.decode, message.body)
                if not decoded or type(data) ~= "table" then return end
                if data.action == "ready" then
                    _warmLive = true
                elseif data.action == "fading" then
                    _fading()
                elseif data.action == "forceExit" then
                    if ms.forceExit then ms.forceExit() end
                end
            end)

            local sf = _shellFrame()
            local v = hs.webview.new(
                {
                    x = sf.x,
                    y = sf.y,
                    w = sf.w,
                    h = sf.h,
                }, {}, uc
            )
            pcall(function() v:windowStyle(0) end)
            pcall(function() v:transparent(true) end)
            pcall(function() v:level(_CURTAIN_LEVEL) end)
            pcall(function() v:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
            pcall(function() v:allowTextEntry(false) end)
            pcall(function() v:shadow(true) end)

            local htmlPath = hs.configdir .. "/ui/ms_curtain.html"
            local baseURL  = "file://" .. hs.configdir .. "/ui/"
            local f = io.open(htmlPath, "r")
            if not f then return nil end
            local html = f:read("*all")
            f:close()
            v:html(html, baseURL)

            return v
        end

        ms.prewarmExitCurtain = function()
            if _warmView then return end
            local ok, v = pcall(_buildCurtain)
            if ok and v then _warmView = v end
        end

        local function _matchShellFrame(view)
            local moved = false
            pcall(function()
                local sf  = _shellFrame()
                local cur = view:frame()
                if not cur
                    or math.abs(cur.x - sf.x) > 1 or math.abs(cur.y - sf.y) > 1
                    or math.abs(cur.w - sf.w) > 1 or math.abs(cur.h - sf.h) > 1
                then
                    view:frame({
                        x = sf.x,
                        y = sf.y,
                        w = sf.w,
                        h = sf.h,
                    })
                    moved = true
                end
            end)
            return moved
        end

        ms.syncExitCurtainFrame = function()
            if not _warmView then return end
            _matchShellFrame(_warmView)
        end

        local function _exitCurtain(mode, onShow, onReady, detail)
            local function finishReady()
                pcall(onReady)
            end

            local _t0 = hs.timer.secondsSinceEpoch()

            local function armFading()
                _onFading = function()
                    ms.dev.log({
                        type    = "system",
                        event   = mode .. "_curtain_fading",
                        afterMs = math.floor(
                            (hs.timer.secondsSinceEpoch() - _t0) * 1000
                        ),
                    })
                    pcall(onShow)
                    if ms._exitCurtainLive then
                        hs.timer.doAfter(CURTAIN_IN_MS / 1000, finishReady)
                    else
                        finishReady()
                    end
                end
            end

            local view    = _warmView
            local wasWarm = view ~= nil
            if not view then
                local ok, v = pcall(_buildCurtain)
                if not ok or not v then
                    ms.dev.log({
                        type  = "error",
                        event = mode .. "_curtain_error",
                        msg   = tostring(v),
                    })
                    pcall(onShow)
                    finishReady()
                    return nil
                end
                view = v
            end

            ms._exitCurtainView = view
            _warmView = nil

            local resized = _matchShellFrame(view)

            local octane = ms._octaneMode and "true" or "false"
            local theme  = hs.json.encode(ms._theme or {})
            local note   = string.format("%q", detail or "")

            local function present()
                armFading()

                ms.safeShow(view)

                pcall(function() view:alpha(1) end)

                pcall(function() view:bringToFront(true) end)
                pcall(function() view:level(_CURTAIN_LEVEL) end)

                local shown = pcall(function()
                    view:evaluateJavaScript("applyTheme(" .. theme .. ");"
                        .. string.format("showCurtain(%q, %s, %s);", mode, octane, note))
                end)

                ms._exitCurtainLive = shown and _warmLive and not ms._octaneMode

                if ms._exitCurtainLive then
                    hs.timer.doAfter(CURTAIN_SOUND_FALLBACK_MS / 1000, _fading)
                else
                    _fading()
                end
            end

            if wasWarm then
                if resized then
                    hs.timer.doAfter(CURTAIN_SETTLE_MS / 1000, present)
                else
                    present()
                end
                return view
            end

            local waited = 0
            local poll
            poll = hs.timer.doEvery(0.05, function()
                waited = waited + 0.05
                if _warmLive or waited >= 0.6 then
                    poll:stop()
                    present()
                end
            end)

            return view
        end

        local function _dropCurtain(finish)
            local view = ms._exitCurtainView

            if not view or not ms._exitCurtainLive or ms._octaneMode then
                return finish()
            end

            local ok = pcall(function()
                view:evaluateJavaScript("hideCurtain();")
            end)
            if not ok then return finish() end

            hs.timer.doAfter(CURTAIN_FADE_MS / 1000, finish)
        end

        local EXIT_CLEANUP_S = 0.4

        local EXIT_WATCHDOG_S = 6.0

        local _activeFinish
        local _activeMode
        local _forcingExit = false

        local function _exit(mode, slot, finish, detail)
            local _finished = false
            local function finishOnce()
                if _finished then return end
                _finished = true
                _activeFinish = nil

                local v = ms._exitCurtainView
                if v then pcall(function() v:hide() end) end
                ms._exitCurtainView = nil

                finish()
            end

            _activeMode   = mode
            _activeFinish = finishOnce

            hs.timer.doAfter(EXIT_WATCHDOG_S, function()
                if _finished then return end
                pcall(function()
                    ms.dev.log({
                        type  = "error",
                        event = mode .. "_watchdog",
                        msg   = "exit did not complete in "
                            .. EXIT_WATCHDOG_S .. "s; forcing",
                    })
                end)
                finishOnce()
            end)

            _exitCurtain(mode, function()
                ms.playSlot(slot)

                pcall(function() ms.alert:expireAll() end)
            end, function()
                pcall(_teardown, mode)
                local hold = math.max(_slotRemaining(slot), EXIT_CLEANUP_S) + 0.2
                hs.timer.doAfter(hold, function()
                    _dropCurtain(finishOnce)
                end)
            end, detail)
        end

        local RESTART_SENTINEL   = hs.configdir .. "/data/.ms_restart_pending"
        local SHUTDOWN_SENTINEL  = hs.configdir .. "/data/.ms_shutdown_pending"
        local HARDKILL_SHUTDOWN_S = 4
        local HARDKILL_RESTART_S  = 15

        local function _resolvePid()
            local pid = hs.processInfo and hs.processInfo.processID
            if pid then return pid end
            local ok, app = pcall(hs.application.get, "Hammerspoon")
            if ok and app then
                local ok2, p = pcall(function() return app:pid() end)
                if ok2 then return p end
            end
            return nil
        end

        local WATCHDOG_SCRIPT = hs.configdir .. "/data/.ms_exit_watchdog.sh"

        local function _spawnDetached(cmd)
            local f = io.open(WATCHDOG_SCRIPT, "w")
            if not f then error("cannot write watchdog script") end
            f:write("#!/bin/sh\n" .. cmd .. "\n")
            f:close()
            os.execute("nohup sh '" .. WATCHDOG_SCRIPT .. "' >/dev/null 2>&1 &")
        end

        local function _armExternalHardKill(mode)
            local ok = pcall(function()
                local pid = _resolvePid()
                if not pid then error("no pid") end
                if mode == "restart" then
                    local f = io.open(RESTART_SENTINEL, "w")
                    if f then f:write(tostring(pid))
                    f:close() end
                    _spawnDetached(
                        "sleep " .. HARDKILL_RESTART_S ..
                        "; if [ -f '" .. RESTART_SENTINEL .. "' ]; then " ..
                            "kill -9 " .. pid .. " 2>/dev/null; " ..
                            "rm -f '" .. RESTART_SENTINEL .. "'; " ..
                            "sleep 1; open -a Hammerspoon; " ..
                        "fi"
                    )
                else
                    local f = io.open(SHUTDOWN_SENTINEL, "w")
                    if f then f:write(tostring(pid))
                    f:close() end
                    _spawnDetached(
                        "sleep " .. HARDKILL_SHUTDOWN_S ..
                        "; if [ -f '" .. SHUTDOWN_SENTINEL .. "' ]; then " ..
                            "kill -9 " .. pid .. " 2>/dev/null; " ..
                            "rm -f '" .. SHUTDOWN_SENTINEL .. "'; " ..
                        "fi"
                    )
                end
            end)
            if not ok then
                pcall(function()
                    ms.dev.log({
                        type = "error",
                        event = mode .. "_hardkill_arm_failed",
                    })
                end)
            end
        end

        ms.shutdown = function()
            if ms._shuttingDown or ms._restarting then return end
            ms._shuttingDown = true
            ms.dev.log({
                type = "system",
                event = "shutdown_start",
            })

            _armExternalHardKill("shutdown")

            _exit("shutdown", "shutdown", function()
                pcall(function()
                    local app = hs.application.get("Hammerspoon")
                    if app then app:kill() end
                end)
                hs.timer.doAfter(0.5, function() os.exit(0) end)
            end)
        end

        ms.restart = function(opts)
            if ms._restarting or ms._shuttingDown then return end
            ms._restarting = true
            local mode = (opts and opts.update) and "update" or "restart"
            ms.dev.log({
                type = "system",
                event = mode .. "_start",
            })

            _armExternalHardKill("restart")

            _exit(mode, "restart", function()
                if hs.relaunch then hs.relaunch() else hs.reload() end
            end, opts and opts.update and tostring(opts.update) or nil)
        end

        ms.forceExit = function()
            if _forcingExit or not _activeFinish then return end
            _forcingExit = true
            ms.dev.log({
                type  = "system",
                event = (_activeMode or "exit") .. "_force",
            })
            pcall(function() os.remove(RESTART_SENTINEL) end)
            pcall(function() os.remove(SHUTDOWN_SENTINEL) end)
            local finish = _activeFinish
            local function drop()
                _dropCurtain(finish)
            end
            if ms.fadeOutSounds then
                ms.fadeOutSounds(300, drop)
            else
                drop()
            end
        end

        ms.reload = function(opts)
            ms.dev.log({
                type = "system",
                event = "reload_start",
            })

            pcall(function() ms.setMacros(0, true) end)

            if ms._tapWatchdog then ms._tapWatchdog:stop()
            ms._tapWatchdog = nil end

            ms._quickReloading = true

            ms._pendingUserSettings = ms._pendingUserSettings or {}
            ms._userSettingDefs     = ms._userSettingDefs     or {}
            ms._userSettingIndex    = ms._userSettingIndex    or {}
            ms._userSettingVals     = ms._userSettingVals     or {}

            ms.saveSettings()

            local qr = opts or ms._qrOptions or {
                macros   = true,
                theme    = true,
                settings = true,
                ui       = true,
            }

            local reloadOk = true

            if qr.macros then
                local ok, result = pcall(ms.ui._actions.reloadMacros)
                if not ok then
                    reloadOk = false
                    ms.dev.log({
                        type = "error",
                        event = "reload_error",
                        msg = tostring(result),
                    })
                    pcall(function()
                        ms.bind._registerSystemBinds()
                        ms.bind.rebindSystem()
                    end)
                elseif result == false then
                    reloadOk = false
                else
                    if ms._loadAuthoredSettings then pcall(ms._loadAuthoredSettings) end
                    if ms._defineAuthoredSettings then pcall(ms._defineAuthoredSettings) end
                    if ms._loadAuthoredMenus then pcall(ms._loadAuthoredMenus) end
                end
            end

            if qr.theme then
                local ok, err = pcall(function()
                    ms.loadTheme()
                    pcall(function() ms.alert:recolor() end)
                    pcall(function() ms.dev:recolor() end)
                    pcall(function() ms.shell.recolorPopouts() end)
                    if ms._macroLabEnabled and ms.shell and ms.shell.eval then
                        ms.shell.eval("applyTheme(" .. hs.json.encode(ms.theme.effective()) .. ")")
                    else
                        ms.ui.hide()
                        hs.timer.doAfter(0.15, function() ms.ui.show() end)
                    end
                end)
                if not ok then
                    reloadOk = false
                    ms.dev.log({
                        type = "error",
                        event = "reload_theme_error",
                        msg = tostring(err),
                    })
                end
            end

            if qr.settings and not qr.macros then
                pcall(function() ms.reloadSettings() end)
            end

            if qr.ui and not qr.macros then
                pcall(function() ms.reloadUI() end)
            end

            if ms._macroLabEnabled and ms.shell and ms.shell.hide then
                pcall(function() ms.shell.hide() end)
                if ms.ui and ms.ui._open then pcall(function() ms.ui.hide() end) end
            elseif not qr.theme then
                pcall(function() ms.ui.hide() end)
            end
            pcall(function() ms.dev.console.hide() end)
            pcall(function() ms.dev.watcher.hide() end)
            pcall(function() ms.dev.keys.hide() end)
            pcall(function() ms.dev.window.hide() end)

            ms._quickReloading = false

            ms._quickReloaded = 0
            ms.saveSettings()

            hs.timer.doAfter(0.15, function()
                pcall(function()
                    local app = ms._targetApp and hs.application.get(ms._targetApp)
                    if app then
                        app:hide()
                        hs.timer.doAfter(0.15, function()
                            pcall(function() app:activate() end)
                        end)
                    end
                end)
            end)

            hs.timer.doAfter(0.3, function()
                if reloadOk then
                    ms.playSlot("update")
                    ms.alert("Reload complete.", 4, true, { priority = "low" })
                else
                    ms.alert("Reload failed, see console.", 6, false, { priority = "low" })
                end
            end)
        end

        ms.quickReload = function() ms.reload() end
    -- END Lifecycle --
end

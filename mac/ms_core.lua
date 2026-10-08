-- Core System --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Bootstrap & Spoons --
            if _G.__ms_core_running then
                -- In-process reload: keep existing ms, clear only exit-lifecycle flags
                if ms then
                    ms._restarting = false
                    ms._shuttingDown = false
                    ms._quickReloading = false
                end
                return
            end
            _G.__ms_core_running = true
            ms = {}
            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

            -- Safe webview show --
                ms.safeShow = function(view)
                    if not view then return false end
                    local ok = pcall(function() view:show() end)
                    if ok then return true end
                    hs.timer.doAfter(0.05, function()
                        pcall(function() view:show() end)
                    end)
                    return false
                end
            -- END Safe webview show --

            -- Loading Screen boot-completion locals --
                local _loadAnnounced, _announceLoad
                local _needsIntegrityWarning = false
            -- END Loading Screen boot-completion locals --

            -- Loading Screen (webview mechanism) --
                package.loaded["lib.ms_loading"] = nil
                require("lib.ms_loading")(ms)
            -- END Loading Screen --

            -- One-time migration (move settings/hash to data/) --
                do
                    local _h = os.getenv("HOME") .. "/.hammerspoon"
                    os.execute("mkdir -p '" .. _h .. "/data'")
                    local function _mvToData(name)
                        local src = _h .. "/" .. name
                        local dst = _h .. "/data/" .. name
                        if hs.fs.attributes(dst) then return end
                        if not hs.fs.attributes(src) then return end
                        local f = io.open(src, "rb")
                        if not f then return end
                        local c = f:read("*all")
                        f:close()
                        local g = io.open(dst, "wb")
                        if not g then return end
                        g:write(c)
                        g:close()
                        os.remove(src)
                    end
                    local _layoutF = io.open(_h .. "/profiles/.layout", "r")
                    local _layoutV = _layoutF and tonumber(_layoutF:read("*l")) or 0
                    if _layoutF then _layoutF:close() end
                    if _layoutV < 2 then
                        _mvToData("ms_settings.json")
                        _mvToData("ms_settings_default.json")
                    end
                    _mvToData(".ms_trusted_hash")
                end
            -- END One-time migration --

            -- Profile Paths & Layout Migration --
                do
                    local _ppOk, _ppErr = pcall(function()
                        package.loaded["lib.core.profile_paths"] = nil
                        require("lib.core.profile_paths")(ms)
                    end)
                    if _ppOk then
                        local _pmOk, _pmErr = pcall(function()
                            package.loaded["lib.core.profile_migrate"] = nil
                            require("lib.core.profile_migrate")(ms)
                        end)
                        if not _pmOk then
                            print("ProfileMigrate: load failed, " .. tostring(_pmErr))
                        end
                        ms.profile.repoint()
                    else
                        print("ProfilePaths: load failed, " .. tostring(_ppErr))
                        local _hs = os.getenv("HOME") .. "/.hammerspoon"
                        local _files = {
                            macros = "ms_macros.lua",
                            settings = "data/ms_settings.json",
                            defaults = "data/ms_settings_default.json",
                            theme = "data/ms_theme.json",
                            visualJson = "data/ms_macros_visual.json",
                            visualLua = "data/ms_macros_visual.lua",
                            authored = "data/ms_authored.json",
                            authoredMenus = "data/ms_authored_menus.json",
                            helperVars = "data/ms_helpervars.json",
                            meta = "profile.json",
                        }
                        ms.profile = {
                            FILES = _files,
                            CONTENT_FILES = {},
                            SOUND_DIRS = {
                                "sounds/active/",
                                "sounds/macro/",
                            },
                            relFor = function(flat) return flat end,
                            flatFor = function(rel) return rel end,
                            safeName = function(name) return name end,
                            refresh = function() end,
                            layout = function() return 1 end,
                            isV2 = function() return false end,
                            root = function() return _hs .. "/profiles" end,
                            list = function() return {} end,
                            active = function() return "" end,
                            dir = function() return _hs end,
                            path = function(rel) return _hs .. "/" .. tostring(rel or "") end,
                            file = function(key) return _files[key] and (_hs .. "/" .. _files[key]) or nil end,
                            exists = function() return false end,
                            ensure = function() return _hs end,
                            setActive = function() return false end,
                            readMeta = function() return nil end,
                            writeMeta = function() return false end,
                            updateMeta = function() return false end,
                            packs = function() return {} end,
                            repoint = function()
                                SoundActiveDir = _hs .. "/sounds/active/"
                                SoundMacroDir = _hs .. "/sounds/macro/"
                            end,
                        }
                        ms.profile.repoint()
                    end
                end
            -- END Profile Paths & Layout Migration --

            -- Font installation --
                do
                    local _h       = os.getenv("HOME") .. "/.hammerspoon"
                    local _srcDir  = _h .. "/ui/fonts/"
                    local _dstDir  = os.getenv("HOME") .. "/Library/Fonts/"
                    local _installed = false
                    hs.fs.mkdir(_dstDir)
                    if hs.fs.attributes(_srcDir) then
                        for _file in hs.fs.dir(_srcDir) do
                            if _file ~= "." and _file ~= ".." then
                                local _ext = _file:match("%.([^%.]+)$")
                                if _ext == "ttf" or _ext == "otf" or _ext == "woff" or _ext == "woff2" then
                                    local _dst = _dstDir .. _file
                                    if not hs.fs.attributes(_dst) then
                                        local _f = io.open(_srcDir .. _file, "rb")
                                        if _f then
                                            local _c = _f:read("*all")
                                            _f:close()
                                            local _g = io.open(_dst, "wb")
                                            if _g then _g:write(_c)
                                            _g:close()
                                            _installed = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if _installed then
                        hs.reload()
                        return
                    end
                end
            -- END Font installation --

            -- MsGuardian (integrity check) --
                ms.loading.update(3, "Configuring Guardian...")
                ms.checkGuardian = function(name)
                    if _G._guardianPassed then return true end
                    print("INTEGRITY ERROR: " .. (name or "module") .. " halted, Guardian did not pass.")
                    ms.alert("Integrity Error\n" .. (name or "Module") .. " refused to start.\nGuardian check did not pass.", 10)
                    return false
                end
            -- END MsGuardian (integrity check) --

            -- Event Bus --
                do
                    local _busSubs = {}

                    ms.bus = {}

                    ms.bus.on = function(topic, fn)
                        assert(type(topic) == "string", "ms.bus.on: topic must be a string")
                        assert(type(fn) == "function", "ms.bus.on: fn must be a function")
                        if not _busSubs[topic] then _busSubs[topic] = {} end
                        _busSubs[topic][fn] = true
                    end

                    ms.bus.off = function(topic, fn)
                        assert(type(topic) == "string", "ms.bus.off: topic must be a string")
                        assert(type(fn) == "function", "ms.bus.off: fn must be a function")
                        if _busSubs[topic] then
                            _busSubs[topic][fn] = nil
                        end
                    end

                    ms.bus.emit = function(topic, payload)
                        assert(type(topic) == "string", "ms.bus.emit: topic must be a string")
                        local subs = _busSubs[topic]
                        if subs then
                            for fn, _ in pairs(subs) do
                                local ok, err = pcall(fn, topic, payload)
                                if not ok then
                                    print("ms.bus handler error [" .. topic .. "]: " .. tostring(err))
                                end
                            end
                        end
                        for pattern, fns in pairs(_busSubs) do
                            if pattern ~= topic and pattern:find("*", 1, true) then
                                local lp = pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
                                lp = lp:gsub("%*$", "\1"):gsub("%*", "[^:]*"):gsub("\1$", ".*")
                                if topic:match("^" .. lp .. "$") then
                                    for fn, _ in pairs(fns) do
                                        local ok, err = pcall(fn, topic, payload)
                                        if not ok then
                                            print("ms.bus handler error [" .. pattern .. "]: " .. tostring(err))
                                        end
                                    end
                                end
                            end
                        end
                    end

                    ms.bus._subscribers = _busSubs
                end
            -- END Event Bus --

            -- MsBackups (snapshots & backup folders) --
                ms._backupRoot = os.getenv("HOME") .. "/.hammerspoon/backups/"
                ms._backupIntervalHours = 12
                ms._backupKeep = 10
                ms._backupIntervalChoices = {
                    [0] = true,
                    [1] = true,
                    [3] = true,
                    [6] = true,
                    [12] = true,
                    [24] = true,
                }
                local _msBackupsOk, _msBackupsErr = pcall(function()
                    package.loaded["lib.ms_backups"] = nil
                    require("lib.ms_backups")(ms)
                end)

                if not _msBackupsOk then
                    print("MsBackups: load failed, " .. tostring(_msBackupsErr))
                    ms.backups = {
                        dir        = function(sub)
                            local path = ms._backupRoot .. (sub and (sub .. "/") or "")
                            os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "'")
                            return path
                        end,
                        list       = function() return {} end,
                        snapshot   = function(_, onDone) if onDone then onDone(false, "unavailable") end end,
                        restore    = function() end,
                        delete     = function() return false end,
                        prune      = function() return 0 end,
                        schedule   = function() end,
                        bootCheck  = function() end,
                        openFolder = function() end,
                    }
                end
            -- END MsBackups --

            -- MsDevTools (logging & dev panels) --
                ms.loading.update(6, "Configuring Dev Tools...")
                local _msDevOk, _msDevErr = pcall(function()
                    package.loaded["lib.ms_devtools"] = nil
                    ms.devtools = require("lib.ms_devtools")(ms)
                    ms.devtools:init()
                end)

                if not _msDevOk then
                    print("MsDevTools: load failed, " .. tostring(_msDevErr))
                    ms.devtools = nil
                end

                if ms.devtools then
                    ms.devtools:start()
                else
                    ms.dev = {
                        _consolePanel    = nil,
                        _watcherPanel    = nil,
                        _keysPanel       = nil,
                        _consolePanelPos = nil,
                        _watcherPanelPos = nil,
                        _keysPanelPos    = nil,
                        _activeKeys      = {},
                        _activeButtons   = {},
                        _coordMode       = "screen",
                        _keysReady       = false,
                    }

                    ms.dev.log = setmetatable({
                        pause      = function() end,
                        resume     = function() end,
                        only       = function() end,
                        pauseAll   = function() end,
                        resumeAll  = function() end,
                        isEnabled  = function() return true end,
                    }, { __call = function() end })
                    ms.dev._onMacroFire  = function() end
                    ms.dev._onKeyEvent   = function() end
                    ms.dev._onMouseEvent = function() end

                    ms.dev.console = {
                        show = function() end,
                        hide = function() end,
                        toggle = function() end,
                    }
                    ms.dev.watcher = {
                        show = function() end,
                        hide = function() end,
                        toggle = function() end,
                    }
                    ms.dev.keys    = {
                        show = function() end,
                        hide = function() end,
                        toggle = function() end,
                    }
                    ms.dev.window  = {
                        show = function() end,
                        hide = function() end,
                        toggle = function() end,
                    }

                    ms.dev.prewarm     = function() end
                    ms.dev.prewarmStep = function() end
                    ms.dev.step        = function() end
                    ms.dev._pushMouseState = function() end

                    ms.devtools = {
                        flushKey         = function() end,
                        watcherStep      = function() end,
                        macroLog         = function() end,
                        accCamMove       = function() end,
                        accWait          = function() end,
                        accKey           = function() end,
                        startTrace       = function() end,
                        stopTrace        = function() end,
                        flushTraceBuffer = function() end,
                        setTraceSuppress = function() end,
                        getTraceSuppress = function() return false end,
                        stopAllPollers         = function() end,
                        restartPollersIfActive = function() end,
                    }

                    print("MsDevTools: running without dev panels (module not loaded)")
                end
            -- END MsDevTools (logging & dev panels) --

            -- MsAlert (toast notifications) --
                ms.loading.update(9, "Configuring Alerts...")
                local _msAlert
                local _msAlertOk, _msAlertErr = pcall(function()
                    package.loaded["lib.ms_alert"] = nil
                    _msAlert = require("lib.ms_alert")(ms)
                end)

                if not _msAlertOk then
                    print("MsAlert: load failed, " .. tostring(_msAlertErr))
                end

                if _msAlert then
                    ms.alert = _msAlert
                else
                    ms.alert = setmetatable({
                        dismissAll   = function() end,
                        dismissById  = function() end,
                    }, {
                        __call = function(_, msg) print("MsAlert stub: " .. tostring(msg)) end,
                    })

                    print("MsAlert: running without toast system (module not loaded)")
                end
            -- END MsAlert (toast notifications) --

            -- MsSettings (settings menu & profiles) --
                ms.loading.update(15, "Configuring Settings...")
                local _msSettings
                local _msSettingsOk, _msSettingsErr = pcall(function()
                    package.loaded["lib.ms_settings"] = nil
                    _msSettings = require("lib.ms_settings")(ms)
                end)

                if not _msSettingsOk then
                    print("MsSettings: load failed, " .. tostring(_msSettingsErr))
                end

                if _msSettings then
                    ms.settings = ms.settings or {}
                    ms.menu     = ms.menu or {}
                    ms.features = ms.features or {}
                    ms.tools    = ms.tools or {}
                    ms.builder  = ms.builder or {}
                    _msSettings:start()
                else
                    ms.settings = ms.settings or {}
                    ms.menu     = ms.menu or {}
                    ms.features = ms.features or {}
                    ms.tools    = ms.tools or {}
                    ms.builder  = ms.builder or {}

                    ms.builder.define  = function() end

                    ms.settings.define = function() end
                    ms.settings.get    = function() return nil end
                    ms.settings.set    = function() end
                    ms.menu.define     = function() end
                    ms.features.hide   = function() end
                    ms.tools.define    = function() end
                    ms.tools.get       = function() return nil end
                    ms.tools.set       = function() end

                    ms.saveSettings    = function() end
                    ms.loadSettings    = function() end
                    ms._loadAuthoredSettings   = function() end
                    ms._defineAuthoredSettings = function() end
                    ms._loadAuthoredMenus      = function() end
                    ms.addAuthoredSetting      = function() return false, "settings unavailable" end
                    ms.removeAuthoredSetting   = function() return false, "settings unavailable" end
                    ms.updateAuthoredSetting   = function() return false, "settings unavailable" end
                    ms.addAuthoredMenu         = function() return false, "settings unavailable" end
                    ms.updateAuthoredMenu      = function() return false, "settings unavailable" end
                    ms.removeAuthoredMenu      = function() return false, "settings unavailable" end
                    ms.saveDefault     = function() end
                    ms.resetToDefault  = function() return false end
                    ms.reloadSettings  = function() end
                    ms.reloadUI        = function() end
                    ms.quickReload     = function() end
                    ms.reload          = function() end
                    ms.loadTheme       = function() end
                    ms.has             = function() return false end
                    ms.parseBind       = function() return nil end
                    ms.effectiveBind   = function() return nil end
                    ms.showGuardian    = function() end

                    ms._applySettings       = function() end
                    ms._convertFlatSettings  = function() return {}, {} end
                    ms._buildDefaultSettings = function() end

                    ms.socdStart  = function() end
                    ms.socdStop   = function() end
                    ms.socdApply  = function() end

                    ms.integrity = {
                        check              = function() return "uninitialized" end,
                        trustCurrent       = function() return false end,
                        hashFile           = function() return nil end,
                        readTrustedHash    = function() return nil end,
                        writeTrustedHash   = function() return false end,
                        deleteTrustedHash  = function() return false end,
                        invalidateCache    = function() end,
                        update             = function() end,
                        updateBeta         = function() end,
                        checkForUpdate     = function() end,
                        checkForUpdateBeta = function() end,
                    }

                    ms._menubar = nil

                    print("MsSettings: running without settings menu (module not loaded)")
                end
            -- END MsSettings (settings menu & profiles) --

            -- MsUI (webview settings panel) --
                ms.loading.update(18, "Configuring UI...")
                local _msUI
                local _msUIOk, _msUIErr = pcall(function()
                    package.loaded["lib.ms_ui"] = nil
                    _msUI = require("lib.ms_ui")(ms)
                end)

                if not _msUIOk then
                    print("MsUI: load failed, " .. tostring(_msUIErr))
                end

                if _msUI then
                    _msUI:start()
                else
                    ms.ui = {
                        _panel     = nil,
                        _open      = false,
                        _modalCallback = nil,
                        _panelPos  = nil,
                        _uiFadeTimer = nil,
                    }

                    ms.ui.show        = function() end
                    ms.ui.hide        = function() end
                    ms.ui.toggle      = function() end
                    ms.ui.refresh     = function() end
                    ms.ui.markDirty   = function() end
                    ms.ui.needsRefresh = function() return false end
                    ms.ui.prebuild    = function() end
                    ms.ui.prewarm     = function() end
                    ms.ui.modal       = function(_, cb) if cb then pcall(cb, { confirmed = false }) end end
                    ms.ui.prompt      = function(_, cb) if cb then pcall(cb, { confirmed = false }) end end
                    ms.ui._actions    = {
                        ready        = function() end,
                        reloadMacros = function() end,
                        navigate     = function() end,
                        close        = function() end,
                        drag         = function() end,
                        resize       = function() end,
                    }

                    print("MsUI: running without webview panel (module not loaded)")
                end
            -- END MsUI (webview settings panel) --
        -- END 0. Bootstrap & Spoons --

        -- 0b. Startup Sanity Checks --
        do
            local modKeys = {
                55,
                58,
                59,
                56,
                63,
            }
            for _, kc in ipairs(modKeys) do
                pcall(function()
                    local ev = hs.eventtap.event.newKeyEvent({}, kc, false)
                    if ev then ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post() end
                end)
            end

            local commonKeys = {
                13,
                0,
                1,
                2,
                12,
                14,
                15,
                3,
                49,
            }
            for _, kc in ipairs(commonKeys) do
                pcall(function()
                    local ev = hs.eventtap.event.newKeyEvent({}, kc, false)
                    if ev then ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post() end
                end)
            end

            for btn = 0, 5 do
                pcall(function()
                    local pos = {
                        0,
                        0,
                    }
                    local ev
                    if btn == 0 then
                        ev = hs.eventtap.event.newMouseEvent(2, pos)
                    elseif btn == 1 then
                        ev = hs.eventtap.event.newMouseEvent(4, pos)
                    else
                        ev = hs.eventtap.event.newMouseEvent(26, pos)
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if ev then
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end)
            end

            if _G._loadTimers then
                for _, t in pairs(_G._loadTimers) do pcall(function() t:stop() end) end
            end
            _G._loadTimers = {}

            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end
        end
        -- END 0b. Startup Sanity Checks --

        -- 1. State & Config --
            package.loaded["lib.core.state"] = nil
            require("lib.core.state")(ms)
        -- END 1. State & Config --

        -- 2. Settings, Profiles & UI --
            ms.app = function() return hs.application.frontmostApplication():name() end

        -- END 2. Settings, Profiles & UI --

        -- 3. Keyboard Actions --
            package.loaded["lib.core.keyboard"] = nil
            require("lib.core.keyboard")(ms)
        -- END 3. Keyboard Actions --

        -- 4. Mouse Actions --
            package.loaded["lib.core.mouse"] = nil
            require("lib.core.mouse")(ms)
        -- END 4. Mouse Actions --

        -- 5. Timing --
            ms.after = function(ms_time, fn)
                local capturedStack = nil
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack then
                        capturedStack = { table.unpack(ctx.callStack) }
                    end
                elseif ms._capturedStack then
                    capturedStack = { table.unpack(ms._capturedStack) }
                end
                return hs.timer.doAfter(ms_time / 1000, function()
                    if capturedStack then
                        ms._capturedStack = capturedStack
                    end
                    ms._runInCoroutine(fn)
                    ms._capturedStack = nil
                end)
            end

            ms._runInCoroutine = function(fn, ...)
                local co, isMain = coroutine.running()
                if co and not isMain then return fn(...) end
                local runner = coroutine.create(fn)
                local ok, err = coroutine.resume(runner, ...)
                if not ok then
                    print("ms._runInCoroutine error: " .. tostring(err))
                end
            end

            ms._waitWarned = {}

            ms.wait = function(ms_time)
                local co, isMain = coroutine.running()
                if co and not isMain then
                    local ctx = ms._coroContext[co]
                    if ms.dev then
                        ms.devtools:accWait(tonumber(ms_time) or 0, ms._getCallChain())
                    end
                    hs.timer.doAfter(ms_time / 1000, function()
                        if ctx and (ctx.cancelled or ctx.paused) then return end
                        local ok, err = coroutine.resume(co)
                        if not ok then
                            print("ms.wait resume error: " .. tostring(err))
                        end
                        if coroutine.status(co) == "dead" then
                            ms._coroContext[co] = nil
                            if ctx then ms._activeContexts[ctx] = nil end
                            if ms.dev then ms.devtools:stopTrace(co) end
                        end
                    end)
                    if ms._branchTrace then ms.devtools:flushTraceBuffer(co) end
                    coroutine.yield()
                else
                    local chain = tostring(ms._getCallChain and ms._getCallChain() or "unknown")
                    if not ms._waitWarned[chain] then
                        ms._waitWarned[chain] = true
                        print("ms.wait called outside a coroutine in macro " .. chain
                            .. ", skipping\n" .. debug.traceback("", 2))
                    end
                end
            end
        -- END 5. Timing --

        -- 6. Resolution & Window Scaling --
            ms.winCenter = function()
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then return 0, 0 end
                local f = win:frame()
                return f.x + (f.w / 2), f.y + (f.h / 2)
            end

            ms.getScaled = function(targetX, targetY)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then return targetX, targetY end
                local f = win:frame()
                return f.x + targetX, f.y + targetY
            end

            ms.resolvePoint = function(x, y, reference)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                local f   = win and win:frame()
                local s   = hs.screen.mainScreen():frame()
                if     reference == "Absolute"     then return x, y
                elseif reference == "Mouse" or reference == "Follow" then
                    local p = hs.mouse.absolutePosition()
                    return p.x + (x or 0), p.y + (y or 0)
                elseif reference == "WindowTL"     then
                    if not f then return x, y end
                    return f.x + x,         f.y + y
                elseif reference == "WindowTR"     then
                    if not f then return x, y end
                    return f.x + f.w + x,   f.y + y
                elseif reference == "WindowBL"     then
                    if not f then return x, y end
                    return f.x + x,         f.y + f.h + y
                elseif reference == "WindowBR"     then
                    if not f then return x, y end
                    return f.x + f.w + x,   f.y + f.h + y
                elseif reference == "WindowCenter" then
                    if not f then return x, y end
                    return f.x + f.w/2 + x, f.y + f.h/2 + y
                elseif reference == "ScreenTL"     then return s.x + x,         s.y + y
                elseif reference == "ScreenTR"     then return s.x + s.w + x,   s.y + y
                elseif reference == "ScreenBL"     then return s.x + x,         s.y + s.h + y
                elseif reference == "ScreenBR"     then return s.x + s.w + x,   s.y + s.h + y
                elseif reference == "ScreenCenter" then return s.x + s.w/2 + x, s.y + s.h/2 + y
                end
                return x, y
            end

            ms.debugTarget = function()
                local win = ms.getTargetWin()
                    or (ms._targetApp and hs.window.find(ms._targetApp))
                if win then
                    local f = win:frame()
                    local screen = win:screen():frame()
                    local currentRatio = f.w / f.h
                    local output = {
                        "--- TARGET WINDOW DEBUG INFO ---",
                        string.format("Window Title: %s", win:title()),
                        string.format("Resolution (Points): %.1f x %.1f", f.w, f.h),
                        string.format("Position: x=%.1f, y=%.1f", f.x, f.y),
                        string.format("Full Screen: %s", tostring(win:isFullScreen())),
                        "-------------------------",
                        string.format("Monitor Size: %.0f x %.0f", screen.w, screen.h),
                        string.format("Aspect Ratio: %.2f", currentRatio),
                        "-------------------------"
                    }
                    print(table.concat(output, "\n"))
                    ms.alert(string.format("Window: %.0f x %.0f | Ratio: %.2f", f.w, f.h, currentRatio), 4)
                    if currentRatio < 4/3 then
                        ms.alert("Warning: Ratio too narrow.", 8)
                    end
                else
                    print("DEBUG ERROR: target window not found.")
                    ms.alert("Target window not found.", 2)
                end
            end
        -- END 6. Resolution & Window Scaling --

        -- 7. Macro Bind Controller --
            package.loaded["lib.core.bind_controller"] = nil
            require("lib.core.bind_controller")(ms)
        -- END 7. Macro Bind Controller --

        -- 8. Utilities --
            package.loaded["lib.core.utilities"] = nil
            require("lib.core.utilities")(ms)
        -- END 8. Utilities --

        -- 9. Bind System & Settings Panel --
            package.loaded["lib.core.bind_system"] = nil
            require("lib.core.bind_system")(ms)
        -- END 9. Bind System & Settings Panel --

        -- 10. Native Input Layer (ms_layer daemon, if installed) --
            package.loaded["lib.core.native_layer"] = nil
            require("lib.core.native_layer")(ms)
        -- END 10. Native Input Layer --

        -- 11. Documentation Accessor (ms.docs) --
            do
                local _docsCache = nil
                local _docsPath = os.getenv("HOME") .. "/.hammerspoon/data/DOCS_MAC.md"

                local function _parseDocs()
                    if _docsCache then return _docsCache end
                    _docsCache = {}
                    local f = io.open(_docsPath, "r")
                    if not f then
                        print("ms.docs: cannot open " .. _docsPath)
                        return _docsCache
                    end
                    local src = f:read("*all")
                    f:close()
                    local currentName = nil
                    local currentBody = {}
                    for line in src:gmatch("([^\n]*)\n?") do
                        local h2 = line:match("^##%s+(.+)$")
                        if h2 then
                            if currentName then
                                _docsCache[currentName] = table.concat(currentBody, "\n"):match("^%s*(.-)%s*$")
                            end
                            currentName = h2
                            currentBody = {}
                        elseif currentName then
                            currentBody[#currentBody + 1] = line
                        end
                    end
                    if currentName then
                        _docsCache[currentName] = table.concat(currentBody, "\n"):match("^%s*(.-)%s*$")
                    end
                    return _docsCache
                end

                ms.docs = {}

                ms.docs.get = function(name)
                    assert(type(name) == "string", "ms.docs.get: name must be a string")
                    local cache = _parseDocs()
                    return cache[name] or nil
                end

                ms.docs.reload = function()
                    _docsCache = nil
                    return _parseDocs()
                end

                ms.docs.sections = function()
                    local cache = _parseDocs()
                    local list = {}
                    for k, _ in pairs(cache) do list[#list + 1] = k end
                    table.sort(list)
                    return list
                end
            end
        -- END 11. Documentation Accessor (ms.docs) --

        -- 12. Shell Infrastructure (ms.shell) --
            package.loaded["lib.ms_shell"] = nil
            require("lib.ms_shell")(ms)
        -- END 12. Shell Infrastructure (ms.shell) --

        -- 12a. Shell Bus Listeners --
            do
                if ms.bus then
                    ms.bus.on("ui:_shell:navigate", function(data)
                        if data and data.panel then
                            ms.shell.setActivePanel(data.panel)
                        end
                    end)
                    ms.bus.on("ui:_shell:popOut", function(data)
                        if data and data.panel then
                            pcall(function() ms.shell.popOut(data.panel) end)
                        end
                    end)
                    ms.bus.on("ui:*:close", function()
                        pcall(function() ms.shell.hide() end)
                    end)
                    ms.bus.on("ui:*:clipboard", function(_, body)
                        if body and body.text then
                            pcall(function() hs.pasteboard.setContents(body.text) end)
                        end
                    end)
                end
            end
        -- END 12a --

        -- 13. Visual Macro Compiler (ms.compiler) --
            package.loaded["lib.ms_compiler"] = nil
            require("lib.ms_compiler")(ms)
        -- END 13. Visual Macro Compiler --

        -- 13a. Macro Lab Shell <-> Compiler bridge --
            package.loaded["lib.core.compiler_bridge"] = nil
            require("lib.core.compiler_bridge")(ms)
        -- END 13a. Macro Lab Shell <-> Compiler bridge --

        -- 13b. Install Version (ms.version) --
            do
                local f = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if f then
                    local ok, m = pcall(hs.json.decode, f:read("*all"))
                    f:close()
                    if ok and type(m) == "table" and m.version then ms.version = m.version end
                end
            end
        -- END 13b. Install Version --

        -- 13c. Package Format (ms.package) --
            package.loaded["lib.ms_package"] = nil
            require("lib.ms_package")(ms)
        -- END 13c. Package Format --

        -- 13d. Package Registry (ms.registry) --
            package.loaded["lib.ms_registry"] = nil
            require("lib.ms_registry")(ms)
        -- END 13d. Package Registry --

        -- 13e. Plugins (Spoons/) --
            package.loaded["lib.ms_plugins"] = nil
            require("lib.ms_plugins")(ms)
            ms.plugins.loadAll()
        -- END 13e. Plugins --

        -- 13f. Developer Mode (ms.devmode) --
            package.loaded["lib.ms_devmode"] = nil
            local _devOk, _devErr = pcall(function() require("lib.ms_devmode")(ms) end)
            if not _devOk then
                print("MsDevmode: failed to load: " .. tostring(_devErr))
                ms.devmode = {
                    isOn            = function() return false end,
                    ipcRunning      = function() return false end,
                    bootedInDevMode = function() return false end,
                    enable          = function() return false end,
                    disable         = function() return false end,
                }
            end
        -- END 13f. Developer Mode --

        -- 14. Safety Nets --
            package.loaded["lib.core.safety_nets"] = nil
            require("lib.core.safety_nets")(ms)
        -- END 14. Safety Nets --
    -- END Hammerspoon mudscript Utility Library --

    -- Startup Executions --
        ms._systemActions = {}
        if ms._userSettingIndex["showTamperWarning"] then
            ms._systemActions["showTamperWarning"] = function()
                ms.showGuardian()
            end
            ms._systemActions["showIntegrityError"] = function()
                ms.showGuardian()
            end
        end

        for _, id in ipairs(ms.registry._defList) do
            local def = ms.registry._defs[id]
            if def and not def.default and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._devArchiveLimit   = 15
        ms._loadComplete   = false
        ms._hotkeysReady   = false
        _G._bootChoreographyStarted = false
        ms.loadSettings()
        ms._loadAuthoredSettings()
        ms._defineAuthoredSettings()
        ms._loadAuthoredMenus()
        ms.backups.schedule()
        ms.backups.bootCheck()
        if ms._customThemeDisabled then
            for sid, def in pairs(ms.soundSlotDefaults()) do
                ms.soundAssign[sid] = def
            end
        end
        ms._soundsDirty = true
        ms._discoverSounds()

        os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
        ms.bind._registerSystemBinds()
        ms.bind.rebind()
        ms.socdApply()
        if ms.gamepadSync then ms.gamepadSync() end
        BindValidity = 0
        ms._startupSoundDone = false

        -- Loading Screen Announce & Boot Completion --
            -- App version label for the loading screen; on the testing channel derives -pre.N
            ms._bootVersionLabel = function()
                local p = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                local f = io.open(p, "r")
                if not f then return nil end
                local ok, m = pcall(hs.json.decode, f:read("*all"))
                f:close()
                local base = (ok and m and m.version) or nil
                if not base then return nil end
                if ms._updateChannel == "testing" then
                    local maj, min, pat = base:match("^(%d+)%.(%d+)%.(%d+)$")
                    if maj and min and pat then
                        local nextVer = maj .. "." .. min .. "." .. tostring(tonumber(pat) + 1)
                        local buildPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_build_num"
                        local bf = io.open(buildPath, "r")
                        local buildNum = 0
                        if bf then buildNum = tonumber(bf:read("*all")) or 0
                        bf:close() end
                        return nextVer .. "-pre." .. tostring(buildNum)
                    end
                end
                return base
            end

            ms.loading.create()

            _announceLoad = function()
                if _loadAnnounced then return end
                _loadAnnounced = true
                pcall(function() ms.playSlot("load") end)
                local _TOAST_LEAD = 1.0
                local _TOAST_HOLD = 2.5
                _G._loadTimers.announceBody = hs.timer.doAfter(0.4, function()
                    ms._startupSoundDone = true
                    _G._loadTimers.announce0 = hs.timer.doAfter(_TOAST_LEAD, function()
                        ms._hotkeysReady = true
                        pcall(function() ms.playSlot("launch") end)
                        local _openHint = ms.windowsMode and "Alt and P" or "Option and P"
                        ms.alert("Macros loaded. Press " .. _openHint .. " to open settings.", _TOAST_HOLD, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce3 = hs.timer.doAfter(_TOAST_LEAD + 3, function()
                        ms.alert("mudscript HS utilities\nBy: mudbourn - https://mudbourn.info", _TOAST_HOLD, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce6 = hs.timer.doAfter(_TOAST_LEAD + 6, function()
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            local author  = ms.macroMeta.author  ~= "" and ms.macroMeta.author  or nil
                            local website = ms.macroMeta.website ~= "" and ms.macroMeta.website or nil
                            if author then msg = msg .. "By: " .. author end
                            if author and website then msg = msg .. " - " end
                            if website then msg = msg .. website end
                            ms.alert(msg, _TOAST_HOLD, true, { priority = "low" })
                        end
                    end)
                    _G._loadTimers.announceDeps = hs.timer.doAfter(_TOAST_LEAD + 9, function()
                        if ms.plugins and ms.plugins.noticeMissing then pcall(ms.plugins.noticeMissing) end
                    end)
                    ms.loading.applyTheme()
                    ms._loadComplete = true
                    loadfinish = 1
                    pcall(function() ms.prewarmExitCurtain() end)
                    ms.dev.log({
                        type = "system",
                        event = "startup_complete",
                    })
                    if ms._octaneMode and ms.octane and ms.octane._apply then
                        pcall(ms.octane._apply)
                    end
                    if ms._targetActive then ms.setMacros(1, true) end
                    _G._loadTimers.integrityWarn = hs.timer.doAfter(10, function()
                        if _needsIntegrityWarning then
                            ms.alert("Integrity Error\nNo trusted manifest on record.\nSettings > Developer > Trust Current Version.", 10)
                        elseif not ms._updateAlertsDisabled then
                            local _checkFn = (ms._updateChannel == "testing")
                                and ms.integrity.checkForUpdateBeta
                                or  ms.integrity.checkForUpdate
                            -- Combine the app-version check with an installed package/plugin scan into one alert
                            _checkFn(function(u)
                                local function announce(items)
                                    items = items or {}
                                    local lines = {}
                                    if u then
                                        lines[#lines + 1] = "- mudscript " .. (u.version or "?") .. " (app)"
                                    end
                                    for _, it in ipairs(items) do
                                        lines[#lines + 1] = "- " .. (it.name or it.id)
                                            .. " " .. (it.to or "?")
                                    end
                                    if #lines == 0 then return end
                                    ms.playSlot("updateAvailable")
                                    local header = (#lines == 1) and "Update available:"
                                        or (#lines .. " updates available:")
                                    ms.alert(header .. "\n" .. table.concat(lines, "\n")
                                        .. "\n\nOpen Browse or Settings to install. Turn these off under Help.",
                                        9, true)
                                end
                                if ms.integrity and ms.integrity.checkContentUpdates then
                                    ms.integrity.checkContentUpdates(announce)
                                else
                                    announce({})
                                end
                            end)
                        end
                    end)
                end)
            end

            -- Single-instance guard --
                -- Announce {pid, bootTime} over distributed notifications; older instance SIGKILLs the newcomer
                pcall(function()
                    if not hs.distributednotifications then return end
                    local NOTE   = "info.mudbourn.mudscript.instanceAnnounce"
                    local myPid   = (hs.processInfo and hs.processInfo.processID) or 0
                    local myBoot  = hs.timer.secondsSinceEpoch()
                    ms._instancePid  = myPid
                    ms._instanceBoot = myBoot
                    ms._instanceEvicted = ms._instanceEvicted or {}

                    if _G.__ms_instanceWatcher then
                        pcall(function() _G.__ms_instanceWatcher:stop() end)
                    end

                    local watcher = hs.distributednotifications.new(function(_, object, userInfo)
                        -- Payload "pid:bootTime": prefer the object string, fall back to userInfo
                        local theirPid, theirBoot
                        if type(object) == "string" then
                            local p, b = object:match("^(%d+):([%d%.]+)$")
                            theirPid  = tonumber(p)
                            theirBoot = tonumber(b)
                        end
                        if not theirPid and type(userInfo) == "table" then
                            theirPid  = tonumber(userInfo.pid)
                            theirBoot = tonumber(userInfo.boot)
                        end
                        if not theirPid or theirPid == myPid then return end
                        -- Only the strictly-older instance evicts, ties break on lower pid
                        local iAmOlder
                        if theirBoot and theirBoot ~= myBoot then
                            iAmOlder = myBoot < theirBoot
                        else
                            iAmOlder = myPid < theirPid
                        end
                        if not iAmOlder then return end
                        if ms._instanceEvicted[theirPid] then return end
                        ms._instanceEvicted[theirPid] = true
                        os.execute("kill -9 " .. tostring(math.floor(theirPid))
                            .. " >/dev/null 2>&1")
                        print("[instance-guard] evicted duplicate Hammerspoon pid "
                            .. tostring(theirPid))
                        -- "error" is a real event slot resolved by playSlot
                        pcall(function() ms.playSlot("error") end)
                        pcall(function()
                            ms.alert("Hammerspoon is already running. "
                                .. "Closed the duplicate instance.", 6, true)
                        end)
                    end, NOTE)
                    watcher:start()
                    _G.__ms_instanceWatcher = watcher
                    ms._instanceWatcher = watcher

                    -- Announce ourselves so any incumbent can evict us, reposted a few times
                    local myBootStr = string.format("%.4f", myBoot)
                    local payload   = tostring(myPid) .. ":" .. myBootStr
                    local function announce()
                        pcall(function()
                            hs.distributednotifications.post(NOTE, payload, {
                                pid  = tostring(myPid),
                                boot = myBootStr,
                            })
                        end)
                    end
                    announce()
                    hs.timer.doAfter(0.4, announce)
                    hs.timer.doAfter(1.2, announce)
                end)
            -- END Single-instance guard --

            _G._timers = {}

            local BOOT_ANCHOR_CAP = 5.0
            local _initSeqArmed   = false

            local function _runInitSequence()
            local steps = {
                function()
                    ms.loading.update(20, "Initializing...")
                end,
                function()
                    print("[startup] prebuild")
                    pcall(function() ms.ui.prebuild() end)
                    pcall(function() ms.ui._precacheHTML() end)
                    ms.loading.update(25, "Building UI state cache...")
                end,
                function()
                    print("[startup] prep settings")
                    ms.loading.update(32, "Preparing settings panel...")
                end,
                function()
                    print("[startup] prewarm")
                    pcall(function() ms.ui.prewarm() end)
                    ms.loading.update(40, "Loading settings panel...")
                end,
                function()
                    print("[startup] theme")
                    ms.loading.update(48, "Applying theme...")
                    ms.loading.onContent(function()
                        if ms.loading.isVisible() then
                            local themeJson = hs.json.encode(ms._theme or {})
                            pcall(function() ms.loading.eval("applyTheme(" .. themeJson .. ")") end)
                            local ver = ms._bootVersionLabel and ms._bootVersionLabel()
                            if ver then
                                pcall(function() ms.loading.eval("setVersion('" .. ver:gsub("'", "\\'") .. "')") end)
                            end
                            pcall(function() ms.loading.eval("showProfile()") end)
                            pcall(function() ms.loading.eval("showCreator()") end)
                            pcall(function() ms.loading.eval("showVersion()") end)
                        end
                        local okSnd, themeSnd = pcall(function() return ms.playSlot("themeLoaded") end)
                        if okSnd then ms.loading.holdForSound(themeSnd) end
                    end)
                end,
                function()
                    print("[startup] integrity seed")
                    ms.loading.update(55, "Seeding integrity hash...")
                end,
                function()
                    print("[startup] console")
                    ms.loading.update(62, "Loading console...")
                    pcall(function() ms.dev.prewarmStep("console") end)
                end,
                function()
                    print("[startup] watcher")
                    ms.loading.update(72, "Loading macro monitor...")
                    pcall(function() ms.dev.prewarmStep("watcher") end)
                end,
                function()
                    print("[startup] keys")
                    ms.loading.update(82, "Loading input monitor...")
                    pcall(function() ms.dev.prewarmStep("keys") end)
                end,
                function()
                    print("[startup] window")
                    ms.loading.update(90, "Loading window monitor...")
                    pcall(function() ms.dev.prewarmStep("window") end)
                    print("[startup] prewarm complete")
                    if not ms.loading.isFadingOut() then
                        ms.loading.update(100, "Ready.")
                        print("[startup] fade out")
                        pcall(function() ms.loading.fadeOut(_announceLoad) end)
                    end
                end,
            }
            local function runStep(i)
                local ok, err = pcall(steps[i])
                if not ok then print("[startup] step " .. i .. " failed: " .. tostring(err)) end
                if steps[i + 1] then
                    _G._timers.initStep = hs.timer.doAfter(0, function() runStep(i + 1) end)
                end
            end
            runStep(1)
            _G._timers.guard = hs.timer.doAfter(8, function()
                print("[startup] t=8: GUARD fired")
                pcall(function()
                    if ms.loading.isVisible() and not ms.loading.isFadingOut() then ms.loading.fadeOut(_announceLoad) end
                end)
                ms._startupSoundDone = true
                print("[startup] t=8: startupSoundDone set to", ms._startupSoundDone)
            end)
            _G._timers.integrity = hs.timer.doAfter(3, function()
                print("[startup] t=3: integrity check")
                pcall(function()
                    if ms.integrity.check() ~= "uninitialized" then return end
                    local _mPath = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                    local _mf    = io.open(_mPath, "r")
                    if _mf then
                        local _ok, _manifest = pcall(hs.json.decode, _mf:read("*all"))
                        _mf:close()
                        if _ok and type(_manifest) == "table"
                            and type(_manifest.sha256) == "string"
                            and #_manifest.sha256 == 64 then
                            local _cur = ms.integrity.hashFile(corePath)
                            if _cur and _cur:lower() == _manifest.sha256:lower() then
                                ms.integrity.trustCurrent()
                                return
                            end
                        end
                    end
                    _needsIntegrityWarning = true
                end)
            end)


            notice = 0
            loadfinish = 0

            _G._integrityPollTimer = hs.timer.doEvery(180, function()
                if loadfinish ~= 1 then return end
                if ms._updateInProgress then return end
                ms.integrity.check()
            end)

            if notice ~= 1 then
                _G._announceTimer = hs.timer.doAfter(8.5, function()
                    _G._announceTimer = nil
                    if _loadAnnounced then return end
                    pcall(function() _announceLoad() end)
                    _G._announceGuardTimer = hs.timer.doAfter(1, function()
                        _G._announceGuardTimer = nil
                        ms._startupSoundDone = true
                        ms._hotkeysReady = true
                        if not ms._loadComplete then
                            ms._loadComplete = true
                            loadfinish = 1
                            if ms._targetActive then pcall(function() ms.setMacros(1, true) end) end
                        end
                    end)
                end)
                notice = 1
            end
            end

            local function _armInitSequence()
                if _initSeqArmed then return end
                _initSeqArmed = true
                _runInitSequence()
            end
            ms._onBootAnchor = _armInitSequence
            if _G._bootChoreographyStarted then _armInitSequence() end
            _G._timers.animGateCap = hs.timer.doAfter(BOOT_ANCHOR_CAP, _armInitSequence)

            local _migration = ms._profileMigration
            if _migration and (_migration.warning or (_migration.status ~= "current" and _migration.status ~= "fresh")) then
                _G._timers.profileMigration = hs.timer.doAfter(10, function()
                    pcall(function()
                        ms.dev.log({
                            type    = _migration.status == "failed" and "error" or "system",
                            event   = "profile_layout_migration",
                            status  = _migration.status,
                            backup  = _migration.backup,
                            message = _migration.error or _migration.warning,
                        })
                    end)
                    if ms._profileMigrationNotice then
                        ms.alert(ms._profileMigrationNotice, 8, true)
                    elseif _migration.warning then
                        ms.alert(_migration.warning, 8)
                    elseif _migration.status == "failed" then
                        ms.alert("Profile layout move failed. Running on the old layout, see the console.", 8)
                    end
                end)
            end
        -- END Loading Screen Announce & Boot Completion --
    -- END Startup Executions --
-- END Core System --

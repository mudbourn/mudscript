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
                    _mvToData("ms_settings.json")
                    _mvToData("ms_settings_default.json")
                    _mvToData(".ms_trusted_hash")
                end
            -- END One-time migration --

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
                ms.loading.update(3, "Configuring Guardian\u{2026}")
                ms.checkGuardian = function(name)
                    if _G._guardianPassed then return true end
                    print("INTEGRITY ERROR: " .. (name or "module") .. " halted, Guardian did not pass.")
                    ms.alert("\u{26a0} Integrity Error\n" .. (name or "Module") .. " refused to start.\nGuardian check did not pass.", 10)
                    return false
                end
            -- END MsGuardian (integrity check) --

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
                            local starPos = pattern:find("%*$")
                            if starPos then
                                local prefix = pattern:sub(1, starPos - 1)
                                if topic:sub(1, #prefix) == prefix then
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

            -- MsDevTools (logging & dev panels) --
                ms.loading.update(6, "Configuring Dev Tools\u{2026}")
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
                        flushCam         = function() end,
                        flushWait        = function() end,
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
                ms.loading.update(9, "Configuring Alerts\u{2026}")
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
                ms.loading.update(15, "Configuring Settings\u{2026}")
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
                    _msSettings:start()
                else
                    ms.settings = ms.settings or {}
                    ms.menu     = ms.menu or {}
                    ms.features = ms.features or {}
                    ms.tools    = ms.tools or {}

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
                ms.loading.update(18, "Configuring UI\u{2026}")
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
            ms.vars = {}
            ms.keytrack = {}
            ms._keyBindings = {}
            ms._keyBindingsByCode = {}
            ms.bindConfig = {}
            ms.bindHandles = {}
            -- Per-macro subset-match flags (id -> true) for ignoring extra modifiers
            ms.bindIgnoreMods = ms.bindIgnoreMods or {}
            -- Modifier-only triggers, evaluated in the flagsChanged branch
            ms._modBindings = {}
            ms.systemBinds             = {
                _config = {},
                _handles = {},
            }

            ms.trackpadMode          = false
            ms.trackpadHoldKeys      = {
                left = "n",
                right = "j",
            }
            ms.socdMode              = "lastWins"
            ms.socdEnabled           = false
            ms.windowsMode           = (package.config:sub(1, 1) == "\\")
            ms.binds                 = {}
            ms._suppressedMacros     = {}
            ms.running   = {}
            ms.cooldowns = {}
            ms._targetActive = false
            ms._safeApps = {
                ["Hammerspoon"]      = true,
                ["Activity Monitor"] = true,
            }
            ms._isSafeZone = function()
                local front = hs.application.frontmostApplication()
                return front and ms._safeApps[front:name()] or false
            end
            ms._ownUiFocused = function()
                local front = hs.application.frontmostApplication()
                return front ~= nil and front:bundleID() == hs.processInfo.bundleID
            end
            ms._menuOpen     = false
            ms._menuVisible  = false
            ms._menuFnFired  = false
            ms._menuHoverWatcher = nil
            ms._slotHandles      = {}
            ms._currentFlags     = {}
            ms._pendingReopenToSound = false
            ms._inputOpen    = false
            ms._macroHeldKeys    = {}
            ms._macroHeldButtons = {}
            ms._coroContext      = {}
            ms._activeContexts   = {}
            ms.registry              = {
                _defs = {},
                _defList = {},
            }
            ms.bind                  = {
                _wires = {},
                _autoCount = 0,
            }

            ms._targetApp     = TARGET_APP or nil
            ms._targetHandle  = ms._targetApp and hs.application.get(ms._targetApp) or nil
            ms._targetActive  = false
            ms._qrOptions = {
                macros = true,
                theme = true,
                settings = true,
                ui = true,
            }
            ms._pluginsDisabled = {}
            ms.getTargetWin = function()
                local app = hs.application.get(ms._targetApp)
                if not app then return nil end
                local ok, win = pcall(function() return app:mainWindow() end)
                return (ok and win) or nil
            end

            ms.setTargetApp = function(name)
                ms._targetApp    = name or nil
                ms._targetHandle = name and hs.application.get(name) or nil
                if ms._targetHandle then
                    ms._targetActive = true
                end
            end
            notice = 0
            loadfinish = 0
            REF_SENS = REF_SENS or 1.5
            Move        = "Move"
            Click       = "Click"
            DoubleClick = "DoubleClick"
            TripleClick = "TripleClick"
            Drag   = "Drag"
            Press       = "Press"
            Release     = "Release"
            Left        = "Left"
            Right       = "Right"
            Center      = "Center"
            Button4     = "Button4"
            Button5     = "Button5"
            Unscaled    = true
            Absolute     = "Absolute"
            Mouse        = "Mouse"
            Follow       = "Follow"
            WindowTL     = "WindowTL"
            WindowTR     = "WindowTR"
            WindowBL     = "WindowBL"
            WindowBR     = "WindowBR"
            WindowCenter = "WindowCenter"
            ScreenTL     = "ScreenTL"
            ScreenTR     = "ScreenTR"
            ScreenBL     = "ScreenBL"
            ScreenBR     = "ScreenBR"
            ScreenCenter = "ScreenCenter"
            BindValidity = 1
            SoundLib = os.getenv("HOME") .. "/.hammerspoon/sounds/"
            SoundDefaultsDir = SoundLib .. "defaults/"
            SoundActiveDir   = SoundLib .. "active/"
            SoundMacroDir    = SoundLib .. "macro/"
            ms.sounds          = {}
            ms.macroSounds     = {}
            ms.importedSounds  = {}
            ms.soundEnabled    = true
            ms.soundVolume     = 100
            ms.bundleSoundsWithTheme = true
            ms.soundAssign     = {}

            -- Sound Slot Registry --
                ms.soundSlots = {
                    {
                        id = "themeLoaded",
                        label = "Theme Applied",
                        group = "load",
                        d = "d_ThemeLoaded",
                        a = "a_ThemeLoaded",
                    },
                    {
                        id = "load",
                        label = "Loading Screen End",
                        group = "load",
                        d = "d_LoadEnd",
                        a = "a_LoadEnd",
                    },
                    {
                        id = "launch",
                        label = "Launch Announcement",
                        group = "load",
                        d = "d_Launch",
                        a = "a_Launch",
                    },

                    {
                        id = "updateAvailable",
                        label = "Update Available",
                        group = "event",
                        d = "d_UpdateAvailable",
                        a = "a_UpdateAvailable",
                    },
                    {
                        id = "alert",
                        label = "Alert / Notice",
                        group = "event",
                        d = "d_Alert",
                        a = "a_Alert",
                    },
                    {
                        id = "error",
                        label = "Error",
                        group = "event",
                        d = "d_Error",
                        a = "a_Error",
                    },
                    {
                        id = "enabled",
                        label = "Macros Enabled",
                        group = "event",
                        d = "d_MacrosOn",
                        a = "a_MacrosOn",
                    },
                    {
                        id = "disabled",
                        label = "Macros Disabled",
                        group = "event",
                        d = "d_MacrosOff",
                        a = "a_MacrosOff",
                    },
                    {
                        id = "toggleOn",
                        label = "Toggle On",
                        group = "event",
                        d = "d_ToggleOn",
                        a = "a_ToggleOn",
                    },
                    {
                        id = "toggleOff",
                        label = "Toggle Off",
                        group = "event",
                        d = "d_ToggleOff",
                        a = "a_ToggleOff",
                    },
                    {
                        id = "update",
                        label = "Setting Updated",
                        group = "event",
                        d = "d_Update",
                        a = "a_Update",
                    },
                    {
                        id = "reset",
                        label = "Setting Reset",
                        group = "event",
                        d = "d_Reset",
                        a = "a_Reset",
                    },
                    {
                        id = "interact",
                        label = "Menu Interact",
                        group = "event",
                        d = "d_Interact",
                        a = "a_Interact",
                    },
                    {
                        id = "hover",
                        label = "Menu Hover",
                        group = "event",
                        d = "d_Hover",
                        a = "a_Hover",
                    },
                    {
                        id = "back",
                        label = "Menu Back",
                        group = "event",
                        d = "d_Back",
                        a = "a_Back",
                    },
                    {
                        id = "settingsOpen",
                        label = "Settings Open",
                        group = "event",
                        d = "d_SettingsOpen",
                        a = "a_SettingsOpen",
                    },
                    {
                        id = "settingsClose",
                        label = "Settings Close",
                        group = "event",
                        d = "d_SettingsClose",
                        a = "a_SettingsClose",
                    },
                    {
                        id = "shutdown",
                        label = "Shutdown",
                        group = "event",
                        d = "d_Shutdown",
                        a = "a_Shutdown",
                    },

                    {
                        id = "restart",
                        label = "Restart",
                        group = "event",
                        d = "d_Restart",
                        a = "a_Restart",
                        fallback = "shutdown",
                    },
                }

                ms.soundSlot = function(id)
                    for _, slot in ipairs(ms.soundSlots) do
                        if slot.id == id then return slot end
                    end
                    return nil
                end

                ms.soundSlotChain = function(id)
                    local chain, seen = {}, {}
                    local cur = id
                    while cur and not seen[cur] and #chain < 8 do
                        seen[cur] = true
                        table.insert(chain, cur)
                        local def = ms.soundSlot(cur)
                        cur = def and def.fallback or nil
                    end
                    return chain
                end

                ms.soundSlotDefaults = function()
                    local out = {}
                    for _, slot in ipairs(ms.soundSlots) do
                        if slot.d then out[slot.id] = slot.d end
                    end
                    return out
                end

                ms.soundSlotReserved = function()
                    local out = {}
                    for _, slot in ipairs(ms.soundSlots) do
                        for _, base in ipairs({
                            slot.d,
                            slot.a,
                        }) do
                            if base then
                                out[base] = true
                                for n = 1, 9 do out[base .. n] = true end
                            end
                        end
                    end
                    return out
                end

                ms.buildSoundPresets = function()
                    local all = ms.sounds or {}
                    local function variant(base, num)
                        if not base then return nil end
                        local name = num and (base .. num) or base
                        return all[name] and name or nil
                    end

                    local presets = {}
                    for num = 1, 3 do
                        local assigns = {}
                        for _, slot in ipairs(ms.soundSlots) do
                            if slot.a or slot.d then
                                if num > 1 then
                                    assigns[slot.id] = variant(slot.a, tostring(num))
                                        or variant(slot.a, nil)
                                        or variant(slot.d, tostring(num))
                                        or slot.d
                                else
                                    assigns[slot.id] = variant(slot.a, nil) or slot.d
                                end
                            end
                        end
                        table.insert(presets, {
                            num = num,
                            assigns = assigns,
                        })
                    end
                    return presets
                end

                ms.safeSoundName = function(stem, prefix)
                    prefix = prefix or "a_"
                    stem = (stem or ""):gsub('[/\\:*?"<>|%c]', "_")
                    stem = stem:gsub("^%s+", ""):gsub("%s+$", "")
                    stem = stem:gsub("^[dam]_", "")
                    if stem == "" then stem = "Sound" end

                    local reserved = ms.soundSlotReserved()
                    local function taken(name)
                        return reserved[name]
                            or (ms.sounds or {})[name] ~= nil
                            or (ms.macroSounds or {})[name] ~= nil
                    end

                    if not taken(prefix .. stem) then return prefix .. stem end
                    for n = 2, 99 do
                        local try = prefix .. stem .. "-" .. n
                        if not taken(try) then return try end
                    end
                    return prefix .. stem .. "-"
                        .. tostring(math.floor(hs.timer.secondsSinceEpoch()))
                end
            -- END Sound Slot Registry --

            ms._docsURL           = "https://docs-ms.mudbourn.info"
            ms._updateManifestURL = "https://raw.githubusercontent.com/mudbourn/mudscript/main/MANIFEST.json"
            ms._updateChannel     = "stable"
            ms._branchTrace       = true
            ms._testingWorkflow   = "testing"
            ms._testingRepo       = "mudbourn/mudscript"

            ms._updatePublicKey = [[
            -----BEGIN PUBLIC KEY-----
            MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
            QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
            FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
            OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
            iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
            /952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
            YQIDAQAB
            -----END PUBLIC KEY-----
            ]]

            -- User Settings & Menu API State --
                ms.settings          = ms.settings or {}
                ms.menu              = ms.menu or {}
                ms._menubar          = nil
                ms.features          = ms.features or {}
                ms._userSettingDefs  = {}
                ms._userSettingIndex = {}
                ms._userSettingVals  = {}
                ms._userMenuDefs     = {}
                ms._hiddenFeatures   = {}
                ms.tools             = ms.tools or {}
                ms._toolDefs         = {}
                ms._toolIndex        = {}
                ms._themeDefaults = {
                    bg       = "#0d0f09",
                    surface  = "#141810cc",
                    surface2 = "#1c2116cc",
                    hover    = "#2d3523",
                    accent   = "#6b8c3a",
                    accentHi = "#8db84e",
                    success  = "#7aa63c",
                    dangerBg = "#1c130f",
                    danger   = "#c0492e",
                    warning  = "#c4a030",
                    text     = "#d4cfb6",
                    radius       = 8,
                    font         = "Arial",
                    fadeMs       = 250,
                    alertAnimMs   = 250,
                    alertAnimSteps = 30,
                }
                ms._theme = {}
                for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                ms._themeLoaded = false

            -- Window Radius Helper [ms.theme] --
                ms.theme = ms.theme or {}

                ms.theme.applyWindowRadius = function(panel)
                    if not panel then return end
                    -- Host frame follows the theme Corner radius; explicit windowRadius overrides
                    local r = (ms._theme and (ms._theme.windowRadius or ms._theme.radius))
                        or (ms._themeDefaults and (ms._themeDefaults.windowRadius or ms._themeDefaults.radius))
                        or 0
                    if ms._octaneMode then r = 0 end
                    if r > 0 then
                        pcall(function() panel:transparent(true) end)
                        pcall(function() panel:shadow(false) end)
                    end
                    -- Windows: round the host frame via cornerRadius; no-op on mac
                    pcall(function()
                        if panel.cornerRadius then panel:cornerRadius(r) end
                    end)
                    local js = string.format(
                        "document.documentElement.style.setProperty('--ms-window-radius', '%dpx');"
                        .. "document.documentElement.style.background='transparent';"
                        .. "document.body.style.background='transparent';",
                        r
                    )
                    hs.timer.doAfter(0.05, function()
                        pcall(function() panel:evaluateJavaScript(js) end)
                    end)
                end
            -- END Window Radius Helper --

            -- Effective theme [ms.theme] --
                -- Flattens surface alpha to opaque under octane or the transparency toggle
                ms.theme.effective = function()
                    local t = {}
                    for k, v in pairs(ms._theme or {}) do t[k] = v end
                    if ms._uiTransparencyOff or ms._octaneMode then
                        local function opaque(hx)
                            if type(hx) ~= "string" then return hx end
                            local six = hx:match("^(#%x%x%x%x%x%x)%x%x$")
                            if six then return six end
                            local three = hx:match("^(#%x%x%x)%x$")
                            if three then return three end
                            return hx
                        end
                        t.bg = opaque(t.bg)
                        t.surface = opaque(t.surface)
                        t.surface2 = opaque(t.surface2)
                        t.hover = opaque(t.hover)
                    end
                    return t
                end

                -- Re-push the effective theme and window radius to every live window
                ms.theme.repaint = function()
                    if ms._macroLabEnabled and ms.shell and ms.shell.eval then
                        pcall(function()
                            ms.shell.eval("applyTheme(" .. hs.json.encode(ms.theme.effective()) .. ")")
                        end)
                    end
                    if ms.shell then
                        if ms.shell.recolorPopouts then pcall(ms.shell.recolorPopouts) end
                        if ms.shell.osk and ms.shell.osk._retheme then pcall(ms.shell.osk._retheme) end
                        if ms.shell.applyWindowRadius then pcall(ms.shell.applyWindowRadius) end
                    end
                end
            -- END Effective theme --

                require("hs.eventtap")
                require("hs.mouse")
                require("hs.uielement")
                require("hs.timer")
                require("hs.hotkey")
                require("hs.json")
                require("hs.keycodes")
                require("hs.canvas")
                require("hs.window")
                require("hs.window.filter")
                require("hs.screen")
                require("hs.menubar")
                require("hs.application")

                hs.timer.doAfter(0.3, function()
                    local targetApp = hs.application.get(ms._targetApp)
                    if targetApp then
                        ms._targetActive = true

                        local hs_app = hs.application.get("Hammerspoon")
                        if hs_app then hs_app:activate() end

                        hs.timer.doAfter(0.25, function()
                            local app = hs.application.get(ms._targetApp) or targetApp
                            local ok, win = pcall(function() return app:mainWindow() end)
                            if ok and win then pcall(function() win:focus() end) end
                            pcall(function() app:activate() end)
                        end)
                    end
                end)
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
                    fn()
                    ms._capturedStack = nil
                end)
            end

            ms.wait = function(ms_time)
                local co, isMain = coroutine.running()
                if co and not isMain then
                    local ctx = ms._coroContext[co]
                    if ms.dev and not ms.devtools:getTraceSuppress() then
                        ms.devtools:flushCam()
                    end

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
                    hs.timer.usleep(ms_time * 1000)
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
                    local currentSens = ms._camSens or 1.5
                    local output = {
                        "--- TARGET WINDOW DEBUG INFO ---",
                        string.format("Window Title: %s", win:title()),
                        string.format("Resolution (Points): %.1f x %.1f", f.w, f.h),
                        string.format("Position: x=%.1f, y=%.1f", f.x, f.y),
                        string.format("Full Screen: %s", tostring(win:isFullScreen())),
                        "-------------------------",
                        string.format("Monitor Size: %.0f x %.0f", screen.w, screen.h),
                        string.format("Aspect Ratio: %.2f", currentRatio),
                        string.format("Camera Sensitivity: %.2f", currentSens),
                        "-------------------------"
                    }
                    print(table.concat(output, "\n"))
                    ms.alert(string.format("Window: %.0f x %.0f | Ratio: %.2f", f.w, f.h, currentRatio), 4)
                    ms.alert("Camera Sensitivity: " .. string.format("%.2f", currentSens), 4)
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
                        local _openHint = ms.windowsMode and "Alt and P" or "\xe2\x8c\xa5 and P"
                        ms.alert("Macros loaded. Press " .. _openHint .. " to open settings.", _TOAST_HOLD, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce3 = hs.timer.doAfter(_TOAST_LEAD + 3, function()
                        ms.alert("mudscript HS utilities\nBy: mudbourn \xe2\x80\x94 https://mudbourn.info", _TOAST_HOLD, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce6 = hs.timer.doAfter(_TOAST_LEAD + 6, function()
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author  then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. " \xe2\x80\x94 " .. ms.macroMeta.website end
                            ms.alert(msg, _TOAST_HOLD, true, { priority = "low" })
                        end
                    end)
                    ms.loading.applyTheme()
                    ms._loadComplete = true
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
                            ms.alert("\u{26a0} Integrity Error\nNo trusted manifest on record.\nSettings \u{2192} Developer \u{2192} Trust Current Version.", 10)
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
                                        lines[#lines + 1] = "\xe2\x80\xa2 mudscript " .. (u.version or "?") .. " (app)"
                                    end
                                    for _, it in ipairs(items) do
                                        lines[#lines + 1] = "\xe2\x80\xa2 " .. (it.name or it.id)
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

            -- Boot sequence anchored to the loading choreography start, with a safety cap
            local BOOT_ANCHOR_LEAD = 2.9
            local BOOT_ANCHOR_CAP  = 5.0
            local _initSeqArmed    = false

            local function _runInitSequence()
            ms.loading.update(20, "Initializing\u{2026}")
            local t1 = 0.3
            local t2 = 0.5
            local t3 = 0.8
            local t4 = 1.3
            local t5 = 2.0
            local t6 = 2.6
            local t7 = 3.2
            local t8 = 3.8
            local t9 = 4.2
            local t10 = 4.6
            _G._timers[1] = hs.timer.doAfter(0, function()
                print("[startup] t=0: prebuild")
                pcall(function() ms.ui.prebuild() end)
                pcall(function() ms.ui._precacheHTML() end)
                ms.loading.update(25, "Building UI state cache\u{2026}")
            end)
            _G._timers[2] = hs.timer.doAfter(t1, function()
                print("[startup] t=" .. t1 .. ": prep settings")
                ms.loading.update(32, "Preparing settings panel\u{2026}")
            end)
            _G._timers[3] = hs.timer.doAfter(t2, function()
                print("[startup] t=" .. t2 .. ": prewarm")
                pcall(function() ms.ui.prewarm() end)
                ms.loading.update(40, "Loading settings panel\u{2026}")
            end)
            _G._timers[4] = hs.timer.doAfter(t3, function()
                print("[startup] t=" .. t3 .. ": theme")
                ms.loading.update(48, "Applying theme\u{2026}")
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
                pcall(function() ms.playSlot("themeLoaded") end)
            end)
            _G._timers[5] = hs.timer.doAfter(t4, function()
                print("[startup] t=" .. t4 .. ": integrity seed")
                ms.loading.update(55, "Seeding integrity hash\u{2026}")
            end)
            _G._timers[6] = hs.timer.doAfter(t5, function()
                print("[startup] t=" .. t5 .. ": console")
                ms.loading.update(62, "Loading console\u{2026}")
                _G._timers[60] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("console") end)
                end)
            end)
            _G._timers[7] = hs.timer.doAfter(t6, function()
                print("[startup] t=" .. t6 .. ": watcher")
                ms.loading.update(72, "Loading macro monitor\u{2026}")
                _G._timers[70] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("watcher") end)
                end)
            end)
            _G._timers[8] = hs.timer.doAfter(t7, function()
                print("[startup] t=" .. t7 .. ": keys")
                ms.loading.update(82, "Loading input monitor\u{2026}")
                _G._timers[80] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("keys") end)
                end)
            end)
            _G._timers[9] = hs.timer.doAfter(t8, function()
                print("[startup] t=" .. t8 .. ": window")
                ms.loading.update(90, "Loading window monitor\u{2026}")
                _G._timers[90] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("window") end)
                end)
            end)
            _G._timers[10] = hs.timer.doAfter(t9, function()
                print("[startup] t=" .. t9 .. ": finalize")
                if not ms.loading.isFadingOut() then ms.loading.update(96, "Finalizing\u{2026}") end
            end)
            _G._timers[11] = hs.timer.doAfter(t10, function()
                print("[startup] t=" .. t10 .. ": fade start")
                if not ms.loading.isFadingOut() then
                    ms.loading.update(100, "Ready.")
                    _G._timers[12] = hs.timer.doAfter(0.8, function()
                        print("[startup] fade out")
                        pcall(function() ms.loading.fadeOut(_announceLoad) end)
                    end)
                end
            end)
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


            if ms._targetHandle then pcall(function() ms._targetHandle:activate() end) end

            notice = 0
            loadfinish = 0

            _G._loadfinishTimer = hs.timer.doAfter(3000 / 1000, function()
                _G._loadfinishTimer = nil
                loadfinish = 1
            end)

            _G._integrityPollTimer = hs.timer.doEvery(180, function()
                if loadfinish ~= 1 then return end
                if ms._updateInProgress then return end
                ms.integrity.check()
            end)

            if notice ~= 1 then
                _G._announceTimer = hs.timer.doAfter(7.0, function()
                    _G._announceTimer = nil
                    pcall(function() _announceLoad() end)
                    _G._announceGuardTimer = hs.timer.doAfter(1, function()
                        _G._announceGuardTimer = nil
                        ms._startupSoundDone = true
                        ms._hotkeysReady = true
                        if not ms._loadComplete then
                            ms._loadComplete = true
                            if ms._targetActive then pcall(function() ms.setMacros(1, true) end) end
                        end
                    end)
                end)
                notice = 1
            end
            end

            -- Arm the sequence once, on the first anchor to fire
            local function _armInitSequence()
                if _initSeqArmed then return end
                _initSeqArmed = true
                _G._timers.animGate = hs.timer.doAfter(BOOT_ANCHOR_LEAD, _runInitSequence)
            end
            ms._onBootAnchor = _armInitSequence
            -- If the choreography already started (fast re-entry), arm immediately.
            if _G._bootChoreographyStarted then _armInitSequence() end
            -- Safety net: a webview that never handshakes must not strand the boot.
            _G._timers.animGateCap = hs.timer.doAfter(BOOT_ANCHOR_CAP, _armInitSequence)
        -- END Loading Screen Announce & Boot Completion --
    -- END Startup Executions --
-- END Core System --

-- Core System (PLEASE EDIT CAREFULLY) --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Bootstrap & Spoons --
            if _G.__ms_core_running then return end
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

            -- Guardian (lives in lib/ms_guardian.lua, runs before this file) --
            -- END Guardian --

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
                        flushAll         = function() end,
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

            -- MsCamera removed (ms.cam uses CGEvent directly) --

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
            -- Per-macro "ignore extra modifiers" flags (id -> true). When set, a
            -- key/combo bind matches as long as its DECLARED modifiers are held,
            -- tolerating any additional modifiers held at the time (subset match)
            -- instead of demanding an exact modifier set. Persisted in settings.
            ms.bindIgnoreMods = ms.bindIgnoreMods or {}
            -- Modifier-only triggers ({ type="mods", mods={...} }). Evaluated in
            -- the keyboard listener's flagsChanged branch, not via keycode.
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
            REF_W = REF_W or 1680
            REF_H = REF_H or 1044
            REF_SENS = REF_SENS or 1.5
            ms._refW       = ms._refW or REF_W
            ms._refH       = ms._refH or REF_H
            if ms._refScaling == nil then ms._refScaling = true end
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
                    surface  = "#141810",
                    surface2 = "#1c2116",
                    hover    = "#2d3523",
                    accent   = "#6b8c3a",
                    accentHi = "#8db84e",
                    success  = "#7aa63c",
                    dangerBg = "#1c130f",
                    danger   = "#c0492e",
                    warning  = "#c4a030",
                    text     = "#d4cfb6",
                    radius       = 8,
                    windowRadius = 8,
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
                    local r = (ms._theme and ms._theme.windowRadius)
                        or (ms._themeDefaults and ms._themeDefaults.windowRadius)
                        or 0
                    if r > 0 then
                        pcall(function() panel:transparent(true) end)
                        pcall(function() panel:shadow(false) end)
                    end
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
            local hskeymap = {
                left = 123, right = 124, down = 125, up = 126,
                shift = 56, lshift = 56, rshift = 62,
                ctrl = 59, lctrl = 59, rctrl = 61,
                alt = 58, lalt = 58, ralt = 61,
                cmd = 55, lcmd = 55, rcmd = 54,
                f1 = 122, f2 = 120, f3 = 99, f4 = 118,
                f5 = 96, f6 = 97, f7 = 98, f8 = 100,
                f9 = 101, f10 = 109, f11 = 103, f12 = 111,
                leftclick = 997, mouse1 = 997,
                rightclick = 999, mouse2 = 999,
                middleclick = 998, mouse3 = 998,
                mouse4 = 996, mouseback = 996,
                mouse5 = 995, mouseforward = 995,
            }

            local function getCode(key)
                if type(key) == "number" then return key end
                local k = tostring(key):lower()
                return hskeymap[k] or hs.keycodes.map[k]
            end

            local _KEY_NAME_EXTRA = { [179] = "fn" }
            local _keyNameCache   = {}
            local function keyName(code)
                if code == nil then return nil end
                local hit = _keyNameCache[code]
                if hit ~= nil then
                    if hit == false then return nil end
                    return hit
                end
                local name = _KEY_NAME_EXTRA[code]
                if name == nil then
                    local ok, v = pcall(function() return hs.keycodes.map[code] end)
                    name = ok and v or nil
                end
                _keyNameCache[code] = (name == nil) and false or name
                return name
            end
            ms._keyName = keyName

            ms.keystate = function(...)
                local args = { ... }
                if args[2] == true then
                    local code = args[1]
                    return code and ms.keytrack[code] == true or false
                end
                for _, key in ipairs(args) do
                    local code = getCode(key)
                    if code and ms.keytrack[code] then
                        return true
                    end
                end
                return false
            end

            ms.held = function(id)
                local c = ms.effectiveBind and ms.effectiveBind(id)
                if not c or not c.mods or #c.mods == 0 then return false end
                for _, m in ipairs(c.mods) do
                    if not ms.keystate(m) then return false end
                end
                return true
            end

            local _prevModFlags = {
                shift = false,
                alt = false,
                ctrl = false,
                cmd = false,
            }

            -- Keycodes that are themselves modifiers, so a modifier-only bind can
            -- tell "just Option held" from "Option + a real key held".
            local _MOD_CODES = {
                [54] = true, [55] = true,             -- cmd
                [56] = true, [60] = true, [62] = true, -- shift
                [58] = true, [61] = true,             -- alt / right-ctrl slot
                [59] = true,                          -- ctrl
            }
            local function _anyRealKeyHeld()
                for kc, down in pairs(ms.keytrack) do
                    if down and not _MOD_CODES[kc] then return true end
                end
                return false
            end

            ms._keyListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
                hs.eventtap.event.types.flagsChanged
            }, function(event)
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end

                local type = event:getType()
                local keyCode = event:getKeyCode()
                local flags = event:getFlags()

                if type == hs.eventtap.event.types.flagsChanged then
                    ms.keytrack[56] = flags.shift
                    ms.keytrack[62] = flags.shift
                    ms.keytrack[58] = flags.alt
                    ms.keytrack[59] = flags.ctrl
                    ms.keytrack[61] = flags.ctrl
                    ms.keytrack[55] = flags.cmd
                    ms.keytrack[54] = flags.cmd
                    -- Modifier-only binds fire on the rising edge when the active
                    -- modifier set exactly matches, once per press (the `fired`
                    -- latch clears when the set no longer matches). Only when no
                    -- ordinary key is held, so Alt+K never trips an Alt bind.
                    if ms._modBindings and #ms._modBindings > 0 and not _anyRealKeyHeld() then
                        for _, mb in ipairs(ms._modBindings) do
                            local exact =
                                ((not mb.modSet.cmd)   == (not flags.cmd)) and
                                ((not mb.modSet.alt)   == (not flags.alt)) and
                                ((not mb.modSet.ctrl)  == (not flags.ctrl)) and
                                ((not mb.modSet.shift) == (not flags.shift))
                            if exact and not mb.fired then
                                mb.fired = true
                                if BindValidity == 1 or mb.system then
                                    local co = coroutine.create(mb.firedFn)
                                    local ok, err = coroutine.resume(co)
                                    if not ok then print("ms.modBind error: " .. tostring(err)) end
                                end
                            elseif not exact then
                                mb.fired = false
                            end
                        end
                    end
                    if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        local now = {
                            shift = flags.shift and true or false,
                            alt   = flags.alt   and true or false,
                            ctrl  = flags.ctrl  and true or false,
                            cmd   = flags.cmd   and true or false,
                        }
                        local modNames = {
                            {
                                k="shift",
                                code=56,
                                name="shift",
                            },
                            {
                                k="alt",
                                code=58,
                                name="alt",
                            },
                            {
                                k="ctrl",
                                code=59,
                                name="ctrl",
                            },
                            {
                                k="cmd",
                                code=55,
                                name="cmd",
                            },
                        }
                        for _, m in ipairs(modNames) do
                            if now[m.k] ~= _prevModFlags[m.k] then
                                pcall(ms.dev._onKeyEvent, m.code, m.name, now[m.k])
                            end
                        end
                        _prevModFlags = now
                    end
                    return false
                end

                if type == hs.eventtap.event.types.keyDown then
                    local isRepeat = (event:getProperty(
                        hs.eventtap.event.properties.keyboardEventAutorepeat) or 0) ~= 0
                    ms.keytrack[keyCode] = true
                    if not isRepeat and ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        pcall(ms.dev._onKeyEvent, keyCode, keyName(keyCode), true)
                    end
                    if not isRepeat and ms._keyBindingsByCode then
                        ms._currentFlags = flags
                        local bucket = ms._keyBindingsByCode[keyCode]
                        if bucket then
                        for _, binding in ipairs(bucket) do
                            if binding then
                                local modsMatch = true
                                if binding.modsAny then
                                    -- Fire on the keycode regardless of modifiers.
                                elseif binding.subsetMods then
                                    -- Declared modifiers must be held; extras are
                                    -- tolerated (so plain-key binds fire even while
                                    -- an unrelated modifier is down).
                                    if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                    if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                    if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                    if binding.mods.shift and not flags.shift then modsMatch = false end
                                else
                                    -- Exact: declared set must equal held set.
                                    if (not binding.mods.cmd)   ~= (not flags.cmd)   then modsMatch = false end
                                    if (not binding.mods.alt)   ~= (not flags.alt)   then modsMatch = false end
                                    if (not binding.mods.ctrl)  ~= (not flags.ctrl)  then modsMatch = false end
                                    if (not binding.mods.shift) ~= (not flags.shift) then modsMatch = false end
                                end
                                local heldMatch = true
                                if binding.alsoHeld then
                                    for _, oc in ipairs(binding.alsoHeld) do
                                        if not ms.keytrack[oc] then heldMatch = false
                                        break end
                                    end
                                end
                                if modsMatch and heldMatch then
                                    if BindValidity == 1 or binding.system then
                                        if binding.pressFn then
                                            local co = coroutine.create(binding.pressFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                        end
                    end
                elseif type == hs.eventtap.event.types.keyUp then
                    ms.keytrack[keyCode] = false
                    if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        pcall(ms.dev._onKeyEvent, keyCode, keyName(keyCode), false)
                    end
                    local bucketUp = ms._keyBindingsByCode and ms._keyBindingsByCode[keyCode]
                    if bucketUp then
                        for _, binding in ipairs(bucketUp) do
                            if binding then
                                local modsMatch = true
                                if not binding.modsAny then
                                    if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                    if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                    if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                    if binding.mods.shift and not flags.shift then modsMatch = false end
                                end
                                if modsMatch then
                                    if BindValidity == 1 or binding.system then
                                        if binding.releaseFn then
                                            local co = coroutine.create(binding.releaseFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                    end
                end

                return false
            end):start()

            ms._resilientTaps = { ms._keyListener }


            local function _keyLog(msg)
                if ms.dev and ms.devtools then
                    local label = ms._getCallChain()
                    ms.devtools:macroLog(msg, label)
                    if ms.dev._watcherPanel then
                        ms.devtools:watcherStep(msg, label)
                    end
                end
            end
            local _keyFlush = function() end
            -- END Key logging --

                ms.press = function(key, mods)
                    if ms.dev then ms.devtools:flushAll()
                    _keyFlush() end
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end
                    ms._keyHoldStarts = ms._keyHoldStarts or {}
                    local alreadyHeld = ms._macroHeldKeys[keyCode]
                    if not alreadyHeld then
                        ms._keyHoldStarts[keyCode] = hs.timer.absoluteTime()
                        if ms.dev and not ms.devtools:getTraceSuppress() then
                            local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                            local msg = "↓ " .. tostring(key) .. modsStr
                            _keyLog(msg)
                        end
                    end
                    ms._macroHeldKeys[keyCode] = { mods = mods or {} }
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.release = function(key, mods)
                    if ms.dev then ms.devtools:flushAll()
                    _keyFlush() end
                    local keyCode = getCode(key)
                    if not keyCode then return end
                    local durationStr = ""
                    ms._keyHoldStarts = ms._keyHoldStarts or {}
                    local startTime = ms._keyHoldStarts[keyCode]
                    if startTime then
                        local elapsedNs = hs.timer.absoluteTime() - startTime
                        local elapsedMs = math.floor(elapsedNs / 1000000)
                        if elapsedMs >= 1000 then
                            durationStr = string.format(" (%.1fs)", elapsedMs / 1000)
                        elseif elapsedMs > 0 then
                            durationStr = string.format(" (%dms)", elapsedMs)
                        end
                        ms._keyHoldStarts[keyCode] = nil
                    end
                    if ms.dev and not ms.devtools:getTraceSuppress() then
                        local msg = "↑ " .. tostring(key) .. durationStr
                        _keyLog(msg)
                    end
                    ms._macroHeldKeys[keyCode] = nil
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, false)
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.forgetHeld = function(key)
                    local keyCode = getCode(key)
                    if not keyCode then return false end
                    if ms._macroHeldKeys[keyCode] == nil then return false end
                    ms._macroHeldKeys[keyCode] = nil
                    if ms._keyHoldStarts then ms._keyHoldStarts[keyCode] = nil end
                    return true
                end

                ms.type = function(key, mods, holdMs)
                    if ms.dev then ms.devtools:flushAll()
                    _keyFlush() end
                    local _hold = holdMs or 15
                    if ms.dev then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        local msg = "type " .. tostring(key) .. modsStr .. " (" .. _hold .. "ms)"
                        _keyLog(msg)
                    end
                    local _saved = ms.devtools:getTraceSuppress()
                    ms.devtools:setTraceSuppress(true)
                    ms.press(key, mods)
                    ms.wait(_hold)
                    ms.release(key, mods)
                    ms.devtools:setTraceSuppress(_saved)
                end

                local HOLD_INITIAL_MS = 250
                local HOLD_REPEAT_MS  = 33
                ms.hold = function(key, mods, durationMs)
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end
                    ms.press(key, mods)
                    local dur = tonumber(durationMs)
                    if not dur or dur <= 0 then return end

                    if dur <= HOLD_INITIAL_MS then
                        ms.wait(dur)
                    else
                        ms.wait(HOLD_INITIAL_MS)
                        local elapsed = HOLD_INITIAL_MS
                        while elapsed < dur do
                            local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                            ev:setProperty(hs.eventtap.event.properties.keyboardEventAutorepeat, 1)
                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            ev:post()
                            ms.wait(HOLD_REPEAT_MS)
                            elapsed = elapsed + HOLD_REPEAT_MS
                        end
                    end
                    ms.release(key, mods)
                end

                ms.key = function(mods, key, swallow, pressFn, releaseFn, isSystem, subsetMods)
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end

                    local modsAny = (mods == "any")
                    local modSet = {}
                    if not modsAny then
                        for _, m in ipairs(mods or {}) do modSet[m] = true end
                    end

                    local binding = {
                        keyCode = keyCode,
                        mods = modSet,
                        modsAny = modsAny,
                        subsetMods = subsetMods or false,
                        swallow = swallow,
                        pressFn = pressFn,
                        releaseFn = releaseFn,
                        system = isSystem or false,
                    }

                    table.insert(ms._keyBindings, binding)
                    local bucket = ms._keyBindingsByCode[keyCode]
                    if not bucket then bucket = {}
                    ms._keyBindingsByCode[keyCode] = bucket end
                    bucket[#bucket + 1] = binding

                    return { delete = function()
                        for i, b in ipairs(ms._keyBindings) do
                            if b == binding then
                                table.remove(ms._keyBindings, i)
                                break
                            end
                        end
                        local bcBucket = ms._keyBindingsByCode[keyCode]
                        if bcBucket then
                            for i, b in ipairs(bcBucket) do
                                if b == binding then
                                    table.remove(bcBucket, i)
                                    break
                                end
                            end
                            if #bcBucket == 0 then ms._keyBindingsByCode[keyCode] = nil end
                        end
                    end}
                end

                ms.keyCombo = function(mods, keys, swallow, pressFn, isSystem, subsetMods)
                    local codes = {}
                    for _, k in ipairs(keys or {}) do
                        local c = getCode(k)
                        if not c then
                            print("Error: keyCombo could not resolve " .. tostring(k))
                            return { delete = function() end }
                        end
                        codes[#codes + 1] = c
                    end
                    if #codes < 2 then
                        return ms.key(mods, keys and keys[1], swallow, pressFn, nil, isSystem, subsetMods)
                    end

                    local modSet = {}
                    for _, m in ipairs(mods or {}) do modSet[m] = true end

                    local handles = {}
                    for i, code in ipairs(codes) do
                        local others = {}
                        for j, oc in ipairs(codes) do
                            if j ~= i then others[#others + 1] = oc end
                        end
                        local binding = {
                            keyCode  = code,
                            mods     = modSet,
                            modsAny  = false,
                            subsetMods = subsetMods or false,
                            swallow  = swallow,
                            pressFn  = pressFn,
                            alsoHeld = others,
                            system   = isSystem or false,
                        }
                        table.insert(ms._keyBindings, binding)
                        local bucket = ms._keyBindingsByCode[code]
                        if not bucket then bucket = {}
                        ms._keyBindingsByCode[code] = bucket end
                        bucket[#bucket + 1] = binding
                        handles[#handles + 1] = binding
                    end

                    return { delete = function()
                        for _, binding in ipairs(handles) do
                            for i, b in ipairs(ms._keyBindings) do
                                if b == binding then table.remove(ms._keyBindings, i)
                                break end
                            end
                            local bc = ms._keyBindingsByCode[binding.keyCode]
                            if bc then
                                for i, b in ipairs(bc) do
                                    if b == binding then table.remove(bc, i)
                                    break end
                                end
                                if #bc == 0 then ms._keyBindingsByCode[binding.keyCode] = nil end
                            end
                        end
                    end }
                end
        -- END 3. Keyboard Actions --

        -- 4. Mouse Actions --
            ms.scroll = function(direction, clicks)
                if ms.dev._watcherPanel then
                    ms.devtools:flushCam()
                    _keyFlush()
                    ms.devtools:watcherStep("scroll " .. tostring(direction)
                        .. (clicks and clicks > 1 and " \xc3\x97" .. clicks or ""))
                end
                clicks = clicks or 1
                local dx, dy = 0, 0
                if direction == "up" then dy = clicks
                elseif direction == "down" then dy = -clicks
                elseif direction == "left" then dx = -clicks
                elseif direction == "right" then dx = clicks
                end
                local ev = hs.eventtap.event.newScrollEvent({
                    dx,
                    dy,
                }, {}, "pixel")
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            -- Button number (0 = left, 1 = right, 2 = middle) -> keytrack code.
            -- These magic codes let ms.keystate / ms.mousestate read live button
            -- state the same way keyboard keys are tracked.
            local _MOUSE_TRACK_CODE = {
                [0] = 997,  -- left
                [1] = 999,  -- right
                [2] = 998,  -- middle
                [3] = 996,  -- thumb back
                [4] = 995,  -- thumb forward
            }

            ms._ensureMouseListener = function()
                if ms._mouseListener then return end
                ms._mouseCallbacks = {}
                local types = {
                    hs.eventtap.event.types.leftMouseDown,
                    hs.eventtap.event.types.leftMouseUp,
                    hs.eventtap.event.types.rightMouseDown,
                    hs.eventtap.event.types.rightMouseUp,
                    hs.eventtap.event.types.otherMouseDown,
                    hs.eventtap.event.types.otherMouseUp,
                }
                ms._mouseListener = hs.eventtap.new(types, function(event)
                        local type = event:getType()
                        local b
                        local isDown

                        if type == hs.eventtap.event.types.leftMouseDown then
                            b = 0
                            isDown = true
                        elseif type == hs.eventtap.event.types.leftMouseUp then
                            b = 0
                            isDown = false
                        elseif type == hs.eventtap.event.types.rightMouseDown then
                            b = 1
                            isDown = true
                        elseif type == hs.eventtap.event.types.rightMouseUp then
                            b = 1
                            isDown = false
                        elseif type == hs.eventtap.event.types.otherMouseDown then
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = true
                        else
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = false
                        end

                        local trackCode = _MOUSE_TRACK_CODE[b]
                        if trackCode then ms.keytrack[trackCode] = isDown end

                        if ms.dev and ms.dev._wantsMouseEvents and ms.dev._wantsMouseEvents() then
                            local _mp = hs.mouse.absolutePosition()
                            pcall(ms.dev._onMouseEvent, b, isDown,
                                math.floor(_mp.x), math.floor(_mp.y))
                        end

                        if BindValidity ~= 1 then
                            if not (callbackData and callbackData.system) then return false end
                        end

                        if not isDown then return false end

                        local callbackData = ms._mouseCallbacks[b]
                        if callbackData then
                            local co = coroutine.create(callbackData.fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then
                                print("ms.mouse callback error: " .. tostring(err))
                            end
                            return callbackData.swallow
                        end

                        return false
                    end):start()
                ms._resilientTaps[#ms._resilientTaps+1] = ms._mouseListener
            end

            ms.mouse = function(button, swallow, clickFn, isSystem)
                ms._ensureMouseListener()
                ms._mouseCallbacks[button] = {
                    fn = clickFn,
                    swallow = swallow,
                    system = isSystem or false,
                }
            end

            -- Live mouse button state, mirroring ms.keystate for the keyboard.
            -- Accepts "left"/"right"/"middle", 0/1/2, or the click aliases.
            local _MOUSE_NAME_CODE = {
                left    = 997,
                l       = 997,
                ["0"]   = 997,
                right   = 999,
                r       = 999,
                ["1"]   = 999,
                middle  = 998,
                center  = 998,
                m       = 998,
                ["2"]   = 998,
                back    = 996,
                thumb   = 996,
                thumb1  = 996,
                ["3"]   = 996,
                forward = 995,
                thumb2  = 995,
                ["4"]   = 995,
            }
            ms.mousestate = function(...)
                ms._ensureMouseListener()
                local args = { ... }
                if #args == 0 then args = { "left" } end
                for _, btn in ipairs(args) do
                    local code
                    if type(btn) == "number" then
                        code = _MOUSE_TRACK_CODE[btn]
                    else
                        code = _MOUSE_NAME_CODE[tostring(btn):lower()]
                    end
                    if code and ms.keytrack[code] then return true end
                end
                return false
            end
            ms._ensureMouseListener()

            ms._scrollCallbacks = ms._scrollCallbacks or {}
            ms.scrollBind = function(direction, fn)
                if not ms._scrollListener then
                    ms._scrollCallbacks = {}
                    ms._scrollListener = hs.eventtap.new({
                        hs.eventtap.event.types.scrollWheel,
                    }, function(event)
                        if BindValidity ~= 1 then return false end
                        local dy = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                        local dir = dy > 0 and "up" or "down"
                        local cb = ms._scrollCallbacks[dir]
                        if cb then
                            local co = coroutine.create(cb)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.scrollBind callback error: " .. tostring(err)) end
                        end
                        return false
                    end):start()
                    ms._resilientTaps[#ms._resilientTaps+1] = ms._scrollListener
                end
                ms._scrollCallbacks[direction] = fn
                return {
                    delete = function()
                        ms._scrollCallbacks[direction] = nil
                    end,
                }
            end

            ms._gamepadTask = nil
            ms._gamepadCallbacks = {}
            ms._gamepadConnected = false

            ms.gamepadStart = function()
                if ms._gamepadTask then return end
                local bin = os.getenv("HOME") .. "/.local/bin/ms_gc_read"
                ms._gamepadCallbacks = {}
                ms._gamepadTask = hs.task.new(bin, function() end, function(task, stdOut, stdErr)
                    if not stdOut or stdOut == "" then return true end
                    local ok, ev = pcall(function() return hs.json.decode(stdOut) end)
                    if not ok or not ev or not ev.e then return true end
                    if ev.e == "connect" then
                        ms._gamepadConnected = true
                        if ms.dev and ms.dev._watcherPanel then
                            ms.devtools:watcherStep("gamepad connected: " .. (ev.c or "?"))
                        end
                    elseif ev.e == "disconnect" then
                        ms._gamepadConnected = false
                    elseif ev.e == "press" then
                        local rebindCb = ms._gamepadCallbacks._rebind
                        if rebindCb then
                            rebindCb(ev.b)
                        else
                            local cb = ms._gamepadCallbacks[ev.b]
                            if cb then
                                local co = coroutine.create(cb)
                                local ok2, err = coroutine.resume(co)
                                if not ok2 then print("ms.gamepad callback error: " .. tostring(err)) end
                            end
                        end
                    end
                    return true
                end)
                ms._gamepadTask:start()
            end

            ms.gamepadStop = function()
                if ms._gamepadTask then
                    ms._gamepadTask:terminate()
                    ms._gamepadTask = nil
                    ms._gamepadCallbacks = {}
                    ms._gamepadConnected = false
                end
            end

            ms.gamepadBind = function(button, fn)
                if not ms.gamepadEnabled then
                    return { delete = function() end }
                end
                if not ms._gamepadTask then ms.gamepadStart() end
                ms._gamepadCallbacks[button] = fn
                return {
                    delete = function()
                        ms._gamepadCallbacks[button] = nil
                    end,
                }
            end


            ms.Mouse = function(operation, button, reference, ...)
                local OPS  = {
                    Move=true,
                    Click=true,
                    DoubleClick=true,
                    TripleClick=true,
                    Drag=true,
                    Press=true,
                    Release=true,
                }
                local BTNS = {
                    Left=0,
                    Right=1,
                    Center=2,
                    Button4=3,
                    Button5=4,
                }
                local REFS = {
                    Absolute=true,   Mouse=true,
                    WindowTL=true,   WindowTR=true,  WindowBL=true,
                    WindowBR=true,   WindowCenter=true,
                    ScreenTL=true,   ScreenTR=true,  ScreenBL=true,
                    ScreenBR=true,   ScreenCenter=true,
                }
                if ms.dev then ms.devtools:flushAll() end
                assert(OPS[operation],     "ms.Mouse: unknown operation '"  .. tostring(operation)  .. "'")
                assert(BTNS[button] ~= nil, "ms.Mouse: unknown button '"      .. tostring(button)     .. "'")
                assert(REFS[reference],    "ms.Mouse: unknown reference '"   .. tostring(reference)  .. "'")

                local unscaled, x1, y1, x2, y2
                local _a, _b, _c, _d, _e = ...
                if type(_a) == "boolean" then
                    unscaled        = _a
                    x1, y1, x2, y2 = _b, _c, _d, _e
                else
                    unscaled        = false
                    x1, y1, x2, y2 = _a, _b, _c, _d
                end

                do
                    local parts = {
                        "Mouse ",
                        tostring(operation),
                        " ",
                        tostring(button),
                        " ",
                        tostring(reference),
                    }
                    if x1 then parts[#parts + 1] = " " .. tostring(x1) .. "," .. tostring(y1) end
                    if x2 then parts[#parts + 1] = " -> " .. tostring(x2) .. "," .. tostring(y2) end
                    local msg = table.concat(parts)
                    if ms.dev and ms.dev._watcherPanel then
                        ms.devtools:watcherStep(msg)
                    end
                    if ms.dev then
                        ms.devtools:macroLog(msg)
                    end
                end

                local btn  = BTNS[button]

                local function resolve(x, y) return ms.resolvePoint(x, y, reference, unscaled) end

                local ax1, ay1 = resolve(x1, y1)
                local ax2, ay2
                if x2 ~= nil and y2 ~= nil then
                    ax2, ay2 = resolve(x2, y2)
                else
                    ax2, ay2 = ax1, ay1
                end
                local pos1 = {
                    x = ax1,
                    y = ay1,
                }
                local pos2 = {
                    x = ax2,
                    y = ay2,
                }

                local downT, upT, dragT
                if btn == 0 then
                    downT = hs.eventtap.event.types.leftMouseDown
                    upT   = hs.eventtap.event.types.leftMouseUp
                    dragT = hs.eventtap.event.types.leftMouseDragged
                elseif btn == 1 then
                    downT = hs.eventtap.event.types.rightMouseDown
                    upT   = hs.eventtap.event.types.rightMouseUp
                    dragT = hs.eventtap.event.types.rightMouseDragged
                else
                    downT = hs.eventtap.event.types.otherMouseDown
                    upT   = hs.eventtap.event.types.otherMouseUp
                    dragT = hs.eventtap.event.types.otherMouseDragged
                end

                local function post(evType, pos)
                    local ev = hs.eventtap.event.newMouseEvent(evType, pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                local function moveTo(pos)
                    local mv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos)
                    mv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    mv:post()
                    hs.mouse.absolutePosition(pos)
                end

                local function singleClick(pos)
                    post(downT, pos)
                    ms.wait(50)
                    post(upT, pos)
                end

                if     operation == "Move"        then moveTo(pos1)
                elseif operation == "Click"       then moveTo(pos1)
                ms.wait(50)
                singleClick(pos1)
                elseif operation == "DoubleClick" then
                    moveTo(pos1)
                    ms.wait(50)
                    singleClick(pos1)
                    ms.wait(50)
                    singleClick(pos1)
                elseif operation == "TripleClick" then
                    moveTo(pos1)
                    ms.wait(50)
                    for i = 1, 3 do singleClick(pos1)
                    if i < 3 then ms.wait(50) end end
                elseif operation == "Drag"        then
                    moveTo(pos1)
                    ms.wait(50)
                    post(downT, pos1)
                    ms.wait(50)
                    post(dragT, pos2)
                    hs.mouse.absolutePosition(pos2)
                    ms.wait(50)
                    post(upT, pos2)
                elseif operation == "Press"       then
                    moveTo(pos1)
                    post(downT, pos1)
                    ms._macroHeldButtons[btn] = {
                        upT = upT,
                        pos = pos1,
                    }
                elseif operation == "Release"     then
                    post(upT, pos1)
                    ms._macroHeldButtons[btn] = nil
                end
            end

            -- ms.cam camera drag via CGEvent --

            local _camEvType  = hs.eventtap.event.types.otherMouseDragged
            local _camBtn     = hs.eventtap.event.properties.mouseEventButtonNumber
            local _camDx      = hs.eventtap.event.properties.mouseEventDeltaX
            local _camDy      = hs.eventtap.event.properties.mouseEventDeltaY
            local _camTotalX  = 0
            local _camTotalY  = 0
            local _camRebalancing = false
            local _camAnchor  = nil
            local _camActivated = false

            local function _updateCamAnchor()
                local win = ms.getTargetWin()
                if win then
                    local f = win:frame()
                    _camAnchor = {
                        x = f.x + (f.w / 2),
                        y = f.y + (f.h / 2),
                    }
                end
            end

            local function _activateCam()
                if _camActivated then return end
                local pos = hs.mouse.absolutePosition()
                local downEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, pos)
                local upEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseUp, pos)
                downEv:setProperty(_camBtn, 5)
                upEv:setProperty(_camBtn, 5)
                downEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                upEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                downEv:post()
                hs.timer.usleep(10000)
                upEv:post()
                _camActivated = true
            end

            ms._updateCamAnchor = _updateCamAnchor
            ms._activateCam = _activateCam
            ms._resetCamActivated = function() _camActivated = false end

            ms.cam = setmetatable({}, {
                __call = function(_, dx, dy)
                    if not _camActivated then _activateCam() end

                    local refSens = ms.settings and ms.settings.get("refSensitivity") or 1.5
                    local curSens = ms._camSens or 1.5
                    if refSens > 0 and curSens > 0 and refSens ~= curSens then
                        local scale = refSens / curSens
                        dx = dx * scale
                        dy = dy * scale
                    end

                    dx = math.floor(dx + 0.5)
                    dy = math.floor(dy + 0.5)

                    local pos = hs.mouse.absolutePosition()
                    local ev  = hs.eventtap.event.newMouseEvent(_camEvType, pos)
                    ev:setProperty(_camBtn, 5)
                    ev:setProperty(_camDx, dx)
                    ev:setProperty(_camDy, dy)
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()


                    if not _camRebalancing then
                        _camTotalX = _camTotalX + dx
                        _camTotalY = _camTotalY + dy
                    end
                end,
            })

            ms.bus.on("ui:_shell:navigate", function(data)
                if data and data.panel then
                    _updateCamAnchor()
                end
            end)
            local _origCamCall = getmetatable(ms.cam).__call
            getmetatable(ms.cam).__call = function(self, dx, dy)
                dx = math.floor(dx + 0.5)
                dy = math.floor(dy + 0.5)
                local saved = ms.dev and ms.devtools and ms.devtools:getTraceSuppress()
                if saved ~= nil then ms.devtools:setTraceSuppress(true) end
                _origCamCall(self, dx, dy)
                if saved ~= nil then ms.devtools:setTraceSuppress(saved) end
                if ms.dev and ms.devtools then
                    ms.devtools:accCamMove(dx, dy, ms._getCallChain())
                end
            end

            ms.cam.rebalance = function(granularity)
                if granularity == nil then
                    granularity = 4
                end
                if _camTotalX == 0 and _camTotalY == 0 then return end
                _camRebalancing = true
                div1 = 1/granularity
                div2 = div1/2
                for i = 1, granularity * 2 do
                    ms.cam(-_camTotalX * div2, -_camTotalY * div2)
                    ms.wait(2)
                end
                _camTotalX = 0
                _camTotalY = 0
                _camRebalancing = false
            end

            ms.cam.reset = function()
                _camTotalX = 0
                _camTotalY = 0
            end

            ms.flick = function(dx, dy, opts)
                opts = opts or {}
                local count = opts.count or math.max(1, math.floor(math.abs(dx) / 100 + 0.5))
                local gapUs = opts.gapUs or ms._flickGapUs or 1000
                local perX, remX = math.floor(dx / count), dx % count
                local perY, remY = math.floor(dy / count), dy % count
                local accX, accY = 0, 0
                for i = 1, count do
                    local ex = perX
                    accX = accX + remX
                    if accX >= count then ex = ex + 1
                    accX = accX - count end
                    local ey = perY
                    accY = accY + remY
                    if accY >= count then ey = ey + 1
                    accY = accY - count end
                    ms.cam(ex, ey)
                    if i < count then hs.timer.usleep(gapUs) end
                end
            end

            local _sweepQueue = {}
            local _sweepTimer = nil
            local _SWEEP_HZ   = 120

            local function _sweepTick()
                if #_sweepQueue == 0 then
                    if _sweepTimer then _sweepTimer:stop()
                    _sweepTimer = nil end
                    return
                end
                local job = _sweepQueue[1]
                if job.ticksLeft <= 0 then
                    table.remove(_sweepQueue, 1)
                    if #_sweepQueue == 0 then
                        if _sweepTimer then _sweepTimer:stop()
                        _sweepTimer = nil end
                    end
                    return
                end
                local perTickX = job.dx / job.totalTicks
                local perTickY = job.dy / job.totalTicks
                local ex = math.floor(perTickX * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickX * (job.totalTicks - job.ticksLeft))
                local ey = math.floor(perTickY * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickY * (job.totalTicks - job.ticksLeft))
                if ex == 0 and ey == 0 then ex = perTickX >= 0 and 1 or -1
                ey = 0 end
                ms.cam(ex, ey)
                job.ticksLeft = job.ticksLeft - 1
            end

            ms.cam.sweep = function(dx, dy, durationMs)
                local ticks = math.max(1, math.floor((durationMs / 1000) * _SWEEP_HZ + 0.5))
                _sweepQueue[#_sweepQueue + 1] = {
                    dx = dx,
                    dy = dy,
                    ticksLeft = ticks,
                    totalTicks = ticks,
                }
                if not _sweepTimer then
                    _sweepTimer = hs.timer.doEvery(1 / _SWEEP_HZ, _sweepTick)
                end
            end

            ms.cam.sweepBlocking = function(dx, dy, durationMs)
                ms.cam.sweep(dx, dy, durationMs)
                ms.wait(durationMs)
            end

            ms.cam.sweepCancel = function()
                _sweepQueue = {}
                if _sweepTimer then _sweepTimer:stop()
                _sweepTimer = nil end
            end

            -- END ms.cam --

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
                        _keyFlush()
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
                            if _keyFlushTimer then _keyFlushTimer:stop()
                            _keyFlushTimer = nil end
                            _keyFlush()
                            local flushLabel = ctx and ctx.callStack and ctx.callStack[1]
                            if ms.dev then ms.devtools:flushAll(flushLabel) end
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

            ms.setReferenceResolution = function(w, h)
                if type(w) == "number" and w > 0 then ms._refW = w
                REF_W = w end
                if type(h) == "number" and h > 0 then ms._refH = h
                REF_H = h end
                if ms.dev and ms.dev.pushRefDims then
                    pcall(ms.dev.pushRefDims)
                end
            end

            ms.setReferenceScaling = function(on)
                ms._refScaling = (on ~= false)
            end

            ms.getScaled = function(targetX, targetY)
                local RW, RH = ms._refW or REF_W, ms._refH or REF_H
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then
                    if ms._refScaling == false then return targetX, targetY end
                    local screen = hs.screen.mainScreen():frame()
                    return targetX * (screen.w / RW), targetY * (screen.h / RH)
                end
                local f = win:frame()
                if ms._refScaling == false then return f.x + targetX, f.y + targetY end
                local finalX = f.x + (targetX * (f.w / RW))
                local finalY = f.y + (targetY * (f.h / RH))
                return finalX, finalY
            end

            ms.resolvePoint = function(x, y, reference, unscaled)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                local f   = win and win:frame()
                local s   = hs.screen.mainScreen():frame()
                local RW, RH = ms._refW or REF_W, ms._refH or REF_H
                local scaled = (ms._refScaling ~= false) and not unscaled
                if     reference == "Absolute"     then return x, y
                elseif reference == "Mouse"        then
                    local p = hs.mouse.absolutePosition()
                    return p.x + x, p.y + y
                elseif reference == "WindowTL"     then
                    if not f then return x, y end
                    if not scaled then return f.x + x,         f.y + y         end
                    return f.x + (x * f.w / RW), f.y + (y * f.h / RH)
                elseif reference == "WindowTR"     then
                    if not f then return x, y end
                    if not scaled then return f.x + f.w + x,   f.y + y         end
                    return f.x + f.w + (x * f.w / RW), f.y + (y * f.h / RH)
                elseif reference == "WindowBL"     then
                    if not f then return x, y end
                    if not scaled then return f.x + x,         f.y + f.h + y   end
                    return f.x + (x * f.w / RW), f.y + f.h + (y * f.h / RH)
                elseif reference == "WindowBR"     then
                    if not f then return x, y end
                    if not scaled then return f.x + f.w + x,   f.y + f.h + y   end
                    return f.x + f.w + (x * f.w / RW), f.y + f.h + (y * f.h / RH)
                elseif reference == "WindowCenter" then
                    if not f then return x, y end
                    if not scaled then return f.x + f.w/2 + x, f.y + f.h/2 + y end
                    return f.x + f.w/2 + (x * f.w / RW), f.y + f.h/2 + (y * f.h / RH)
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
                        string.format("Reference Target: %d x %d (scaling %s)",
                            ms._refW or REF_W or 1680, ms._refH or REF_H or 1044,
                            (ms._refScaling ~= false) and "on" or "off"),
                        "-------------------------",
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
            local _debounceTimer = nil
            local _stateSound    = nil

            local function _doNotify(state)
                if loadfinish ~= 1 then return end
                if _debounceTimer then _debounceTimer:stop()
                _debounceTimer = nil end
                _debounceTimer = hs.timer.doAfter(0.05, function()
                    _debounceTimer = nil
                    if _stateSound then pcall(function() _stateSound:stop() end)
                    _stateSound = nil end
                    if state == 1 then
                        _stateSound = ms.playSlot("enabled")
                        ms.alert("Macros enabled!",  3, true, {
                            id = "_state",
                            source = "system",
                        })
                    else
                        _stateSound = ms.playSlot("disabled")
                        ms.alert("Macros disabled.", 3, true, {
                            id = "_state",
                            source = "system",
                        })
                    end
                end)
            end

            ms.setMacros = function(state, silent)
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                if state == 1 and BindValidity ~= 1 then
                    BindValidity = 1
                    if ms._updateCamAnchor then ms._updateCamAnchor() end
                    ms.dev.log({
                        type = "system",
                        event = "macros_enabled",
                    })
                    if not silent then _doNotify(1) end
                elseif state == 0 and BindValidity ~= 0 then
                    BindValidity = 0
                    ms.cancelMacros()
                    ms.keytrack = {}
                    for _, timer in pairs(ms.running) do
                        if timer and timer.stop then timer:stop() end
                    end
                    ms.running = {}
                    ms.dev.log({
                        type = "system",
                        event = "macros_disabled",
                    })
                    if not silent then _doNotify(0) end
                end
                if ms.ui and ms.ui._open then ms.ui.refresh() end
            end

            ms._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
                if eventType == hs.application.watcher.activated then
                    if appName == (ms._targetApp) then
                        local fromDialog = ms._inputOpen
                        ms._inputOpen = false
                        ms._targetActive = true
                        ms.dev.log({
                            type = "system",
                            event = "target_focus",
                            fromDialog = fromDialog or false,
                        })
                        if ms._updateCamAnchor then ms._updateCamAnchor() end
                        if ms._resetCamActivated then ms._resetCamActivated() end
                        if not ms._loadComplete then return end
                        if fromDialog then
                            BindValidity = 1
                        else
                            ms.setMacros(1)
                        end
                    else
                        local shellOpen = ms._shellState and ms._shellState.visible
                        if (ms.ui._open or shellOpen) and appName == "Hammerspoon" then return end
                        ms._inputOpen    = (appName == "Hammerspoon") and ms._targetActive
                        ms._targetActive = false
                        ms.dev.log({
                            type = "system",
                            event = "target_blur",
                            to = appName,
                        })
                        if ms._camActivated ~= nil then ms._camActivated = false end
                        if BindValidity == 1 then
                            ms.setMacros(0, ms._inputOpen)
                        end
                    end
                end
            end):start()
            _G.__ms_appWatcher = ms._appWatcher

            _G._initTimer = hs.timer.doAfter(0.3, function()
                local frontApp = hs.application.frontmostApplication()
                if ms._targetApp and frontApp and frontApp:name() == ms._targetApp then
                    ms._targetActive = true
                end
            end)

            ms.octane = ms.octane or {}
            -- A visible pulse whenever octane flips, so a bind toggle (easy to
            -- hit by accident) never silently changes behaviour. Styled to match
            -- the macro bind-state alert (same id-replace + system source), with
            -- the toggle sounds.
            ms.octane._notify = function(on)
                if ms.playSlot then pcall(ms.playSlot, on and "toggleOn" or "toggleOff") end
                if not ms.alert then return end
                pcall(ms.alert,
                    on and "Octane enabled!" or "Octane disabled.",
                    3, true, { id = "octane_state", source = "system" })
            end
            ms.octane.on = function()
                if ms._octaneMode then return end
                ms._octaneMode = true
                if ms.saveSettings then pcall(ms.saveSettings) end
                ms.octane._apply()
                ms.octane._notify(true)
                if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
            end
            ms.octane.off = function()
                if not ms._octaneMode then return end
                ms._octaneMode = false
                if ms.saveSettings then pcall(ms.saveSettings) end
                ms.octane._remove()
                ms.octane._notify(false)
                if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
            end
            ms.octane.toggle = function()
                if ms._octaneMode then ms.octane.off() else ms.octane.on() end
            end
            ms.octane._apply = function()
                if ms.dev and ms.dev.log and ms.dev.log.pauseAll then
                    pcall(ms.dev.log.pauseAll)
                end
                if ms.devtools and ms.devtools.stopAllPollers then
                    pcall(function() ms.devtools:stopAllPollers() end)
                end
                if ms._menuHoverWatcher then
                    ms._menuHoverWatcher:stop()
                    ms._menuHoverWatcher = nil
                end
                if ms.devtools and ms.devtools.setWinElementInspect then
                    pcall(function() ms.devtools:setWinElementInspect(false) end)
                end
            end
            ms.octane._remove = function()
                if ms.dev and ms.dev.log and ms.dev.log.resumeAll then
                    pcall(ms.dev.log.resumeAll)
                end
                if ms.devtools and ms.devtools.restartPollersIfActive then
                    pcall(function() ms.devtools:restartPollersIfActive() end)
                end
                if ms._menuVisible and ms._menuHoverStart then
                    pcall(ms._menuHoverStart)
                end
            end

            ms._hotkeys = {
                panic       = {
                    mods = {"alt"},
                    key = "F10",
                },
                quickReload = {
                    mods = {"alt"},
                    key = "[",
                },
                fullReload  = {
                    mods = {"alt"},
                    key = "]",
                },
                openMenu    = {
                    mods = {"alt"},
                    key = "p",
                },
            }
            ms._hotkeyHandles = {}

            local _hotkeyCooldowns = {}
            local _hotkeyDown = {}
            local _hotkeyDownAt = {}
            local _hotkeyTapSet = {}
            local _HOTKEY_LATCH_MAX = 10

            local function _clearStaleLatch(id, isRepeat)
                if not _hotkeyDown[id] then return end

                local since = _hotkeyDownAt[id]
                local aged  = (not since) or (hs.timer.secondsSinceEpoch() - since) > _HOTKEY_LATCH_MAX

                if (not isRepeat) or aged then
                    _hotkeyDown[id]      = false
                    _hotkeyCooldowns[id] = false
                    _hotkeyDownAt[id]    = nil
                end
            end

            local function _resetHotkeyLatches()
                _hotkeyDown      = {}
                _hotkeyCooldowns = {}
                _hotkeyDownAt    = {}
            end

            ms._makeKeyWatcher = function(mods, key, onDown)
                local keyCode = hs.keycodes.map[key]
                if not keyCode then return nil end

                local modsAny = (mods == "any")
                local modSet = {}
                if not modsAny then
                    for _, m in ipairs(mods or {}) do modSet[m] = true end
                end

                local function modsMatch(flags)
                    if modsAny then return true end
                    for m, _ in pairs(modSet) do
                        if not flags[m] then return false end
                    end
                    return true
                end
                local function modsExact(flags)
                    if modsAny then return true end
                    if not modsMatch(flags) then return false end
                    if flags.cmd   and not modSet.cmd   then return false end
                    if flags.alt   and not modSet.alt   then return false end
                    if flags.ctrl  and not modSet.ctrl  then return false end
                    if flags.shift and not modSet.shift then return false end
                    return true
                end
                local id = (modsAny and "any" or table.concat(mods or {}, ",")) .. ":" .. key
                local tap = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                    hs.eventtap.event.types.flagsChanged,
                }, function(e)
                    local type = e:getType()
                    local flags = e:getFlags()
                    local kc = e:getKeyCode()
                    if type == hs.eventtap.event.types.flagsChanged then
                        if not modsAny and not modsMatch(flags) then
                            _hotkeyDown[id] = false
                            _hotkeyCooldowns[id] = false
                            _hotkeyDownAt[id] = nil
                        end
                        return false
                    end
                    if type == hs.eventtap.event.types.keyDown then
                        if kc == keyCode then
                            local isRepeat = (e:getProperty(
                                hs.eventtap.event.properties.keyboardEventAutorepeat) or 0) ~= 0
                            _clearStaleLatch(id, isRepeat)
                            if modsExact(flags) and not _hotkeyDown[id] and not _hotkeyCooldowns[id] then
                                _hotkeyDown[id]   = true
                                _hotkeyDownAt[id] = hs.timer.secondsSinceEpoch()
                                hs.timer.doAfter(0, onDown)
                            end
                        end
                        return ms._swallowHotkeys and true or false
                    end
                    if type == hs.eventtap.event.types.keyUp then
                        if kc == keyCode then
                            _hotkeyDown[id]   = false
                            _hotkeyDownAt[id] = nil
                            _hotkeyCooldowns[id] = true
                            hs.timer.doAfter(0.15, function()
                                _hotkeyCooldowns[id] = false
                            end)
                            return ms._swallowHotkeys and true or false
                        end
                        return false
                    end
                    return false
                end)
                return tap
            end

            ms._bindHotkeys = function()
                for _, h in pairs(ms._hotkeyHandles) do
                    if h and h.stop then h:stop() end
                end
                ms._hotkeyHandles = {}
                _resetHotkeyLatches()

                local kept = {}
                for _, t in ipairs(ms._resilientTaps) do
                    if not _hotkeyTapSet[t] then kept[#kept+1] = t end
                end
                ms._resilientTaps = kept
                _hotkeyTapSet = {}

                local function _register(name, t)
                    ms._hotkeyHandles[name] = t
                    _hotkeyTapSet[t] = true
                    ms._resilientTaps[#ms._resilientTaps+1] = t
                    t:start()
                end

                local hk = ms._hotkeys.panic
                local tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._hotkeysReady then return end
                    if not ms._targetActive and not ms._isSafeZone() then return end
                    ms.setMacros(0)
                end)
                if tap then _register("panic", tap) end

                if ms._quickReloadHotkey then
                    pcall(function() ms._quickReloadHotkey:delete() end)
                    ms._quickReloadHotkey = nil
                end
                hk = ms._hotkeys.quickReload
                do
                    local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                        if not ms._hotkeysReady then return end
                        if ms._qrCooldown then return end
                        ms._qrCooldown = true
                        if ms._qrCooldownTimer then ms._qrCooldownTimer:stop() end
                        ms._qrCooldownTimer = hs.timer.doAfter(1.0, function() ms._qrCooldown = false end)
                        pcall(ms.reload)
                    end)
                    if ok and hotkey then ms._quickReloadHotkey = hotkey end
                end

                if ms._fullReloadHotkey then
                    pcall(function() ms._fullReloadHotkey:delete() end)
                    ms._fullReloadHotkey = nil
                end
                hk = ms._hotkeys.fullReload
                do
                    local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                        if not ms._hotkeysReady then return end
                        if ms.restart then ms.restart() else hs.reload() end
                    end)
                    if ok and hotkey then ms._fullReloadHotkey = hotkey end
                end

                if ms._openMenuHotkey then
                    pcall(function() ms._openMenuHotkey:delete() end)
                    ms._openMenuHotkey = nil
                end
                hk = ms._hotkeys.openMenu
                do
                    local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                        if not ms._hotkeysReady then return end
                        if ms._macroLabEnabled and ms.shell and ms.shell.toggle then
                            ms.shell.toggle()
                        elseif ms.ui and ms.ui.toggle then
                            ms.ui.toggle()
                        end
                    end)
                    if ok and hotkey then ms._openMenuHotkey = hotkey end
                end

            end

            ms._tapWatchdog = hs.timer.doEvery(2, function()
                local revivedHotkey = false

                for _, tap in ipairs(ms._resilientTaps) do
                    if tap and not tap:isEnabled() then
                        tap:start()
                        if _hotkeyTapSet[tap] then revivedHotkey = true end
                        if ms.dev then print("ms: revived a disabled eventtap") end
                    end
                end

                if revivedHotkey then _resetHotkeyLatches() end
            end)

            ms._bindHotkeys()

        -- END 7. Macro Bind Controller --

        -- 8. Utilities --

            ms.log = function(kind, a, b)
                if not ms.dev then return end
                local msg
                if kind == "if" then
                    msg = "if (" .. tostring(a) .. ") -> " .. tostring(b)
                elseif kind == "for" then
                    msg = "for " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                elseif kind == "while" then
                    msg = "while " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                elseif kind == "repeat" then
                    msg = "repeat until " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                else
                    msg = tostring(kind) .. (a and (" " .. tostring(a)) or "")
                end
                if spoon and ms.devtools then
                    ms.devtools:macroLog(msg)
                end
            end

            ms._fnAccum = {
                lastLabel = nil,
                count = 0,
                startTime = 0,
                timer = nil,
            }
            local _fnFlush = function()
                local a = ms._fnAccum
                if a.count > 0 and a.lastLabel then
                    local dur = math.floor((hs.timer.absoluteTime() - a.startTime) / 1e6)
                    local msg = a.lastLabel
                    if a.count > 1 then msg = msg .. " \195\151" .. a.count end
                    if dur > 0 then msg = msg .. " (" .. dur .. "ms)" end
                    if ms.dev and ms.dev.log then
                        ms.dev.log({
                            type = "step",
                            category = "macro",
                            msg = "[" .. a.lastLabel .. "] " .. msg,
                        })
                    end
                end
                a.count = 0
                a.lastLabel = nil
                a.timer = nil
            end

            local _msFnWrap = function(fn, labelOrAsync)
                assert(type(fn) == "function", "ms.fn: fn must be a function")
                if labelOrAsync == false then return fn end

                local fnLabel = type(labelOrAsync) == "string" and labelOrAsync or nil

                return function(...)
                    local label = fnLabel or ms._pendingLabel or "macro"
                    ms._pendingLabel = nil

                    local a = ms._fnAccum
                    if a.lastLabel == label then
                        a.count = a.count + 1
                    else
                        _fnFlush()
                        a.lastLabel = label
                        a.count = 1
                        a.startTime = hs.timer.absoluteTime()
                    end
                    if a.timer then a.timer:stop() end
                    a.timer = hs.timer.doAfter(0.05, _fnFlush)

                    local ctx = {
                        cancelled  = false,
                        paused     = false,
                        callStack  = { label },
                    }

                    local coBody = function(...)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({
                                type = "step",
                                category = "macro",
                                msg = "[" .. label .. "] ▶",
                            })
                        end
                        local xok, xerr = xpcall(fn, debug.traceback, ...)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({
                                type = "step",
                                category = "macro",
                                msg = "[" .. label .. "] ■",
                            })
                        end
                        if not xok then
                            local tb = tostring(xerr)
                            print("=== ms.fn error [" .. label .. "] ===\n" .. tb)
                            if ms.dev and ms.dev.log then
                                ms.dev.log({
                                    type = "error",
                                    event = "macro_error",
                                    macro = label,
                                    msg = tb,
                                })
                            end
                            ms.alert("Macro error [" .. label .. "], see console", 6)
                        end
                    end
                    local co = coroutine.create(coBody)
                    ms._coroContext[co]    = ctx
                    ms._activeContexts[ctx] = true

                    if ms.dev and ms._branchTrace then ms.devtools:startTrace(co, label) end

                    local ok, err = coroutine.resume(co, ...)
                    if not ok then
                        print("=== ms.fn resume error [" .. label .. "] ===\n" .. tostring(err))
                    end

                    if coroutine.status(co) == "dead" then
                        if ms.dev then ms.devtools:stopTrace(co) end
                        ms._coroContext[co]    = nil
                        ms._activeContexts[ctx] = nil
                        if _keyFlushTimer then _keyFlushTimer:stop()
                        _keyFlushTimer = nil end
                        _keyFlush()
                        if ms.dev then ms.devtools:flushAll(ctx and ctx.callStack and ctx.callStack[1]) end
                    end
                end
            end

            ms.fn = setmetatable({
                registry = {
                    _defs = {},
                    _defList = {},
                },

                define = function(id, fn, opts)
                    assert(type(id) == "string", "ms.fn.define: id must be a string")
                    local fnType = type(fn)
                    assert(fnType == "function" or (fnType == "table" and getmetatable(fn) and getmetatable(fn).__call),
                        "ms.fn.define: fn must be a function or callable table")
                    assert(not ms.fn.registry._defs[id],
                        "ms.fn.define: '" .. id .. "' is already registered")
                    opts = opts or {}
                    ms.fn.registry._defs[id] = {
                        fn      = fn,
                        label   = opts.label or id,
                        group   = opts.group or "user",
                        info    = opts.info,
                        params  = opts.params,
                        icon    = opts.icon,
                        cleared = opts.cleared ~= false,
                    }
                    table.insert(ms.fn.registry._defList, id)
                end,

                lookup = function(id)
                    return ms.fn.registry._defs[id]
                end,

                list = function()
                    return ms.fn.registry._defList
                end,
            }, {
                __call = function(_, fn, labelOrAsync)
                    return _msFnWrap(fn, labelOrAsync)
                end,
            })

            ms._capturedStack = nil

            ms._getLabel = function()
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack and #ctx.callStack > 0 then
                        return ctx.callStack[#ctx.callStack]
                    end
                end
                if ms._capturedStack and #ms._capturedStack > 0 then
                    return ms._capturedStack[#ms._capturedStack]
                end
                return nil
            end

            -- ms.callFn(id) — invoke a named function tool (an authored ms.fn)
            -- from inside a macro. Compiled macros call this via emitStep's
            -- "call_fn". Runs the tool's body inline in the current coroutine so
            -- its ms.wait calls yield just like the caller's.
            ms.callFn = function(id)
                if type(id) ~= "string" then return end
                local function callable(f)
                    return type(f) == "function"
                        or (type(f) == "table" and getmetatable(f)
                            and getmetatable(f).__call)
                end
                -- First a registered function tool (builder-authored).
                local def = ms.fn and ms.fn.registry and ms.fn.registry._defs[id]
                if def and callable(def.fn) then return def.fn() end
                -- Then any bound macro from the pack, by its bind id. This is
                -- what lets a macro call the pack's own functions (which are
                -- authored as `local X = ms.fn(...)` and bound, not registered).
                local wired = ms.bind and ms.bind._wires and ms.bind._wires[id]
                if callable(wired) then return wired() end
                -- Then a tool registered via ms.tools.define (e.g. a plugin's
                -- open-folder/open-file action). These surface in the Functions
                -- list, so a Call-function block can invoke them by id.
                local tool = ms._toolIndex and ms._toolIndex[id]
                if tool and callable(tool.run) then return tool.run() end
                print("ms.callFn: no function tool or macro named '" .. tostring(id) .. "'")
            end

            -- ms.vars — disk-persistent, explicitly-declared shared variables.
            -- Unlike a macro's `local` (function-scoped) variables, a helper var
            -- is intentionally visible to every macro and survives reloads, so
            -- sharing state across macros is a deliberate act, never an accident
            -- of a name colliding. Declarations + values live together in
            -- data/ms_helpervars.json, written at runtime like ms_authored.json.
            do
                local varsPath = os.getenv("HOME")
                    .. "/.hammerspoon/data/ms_helpervars.json"
                local store = { defs = {}, vals = {} }
                local loaded = false

                local function coerce(def, v)
                    if not def then return v end
                    if def.type == "number" then
                        local n = tonumber(v)
                        return n or tonumber(def.default) or 0
                    elseif def.type == "boolean" then
                        return v == true or v == "true"
                    end
                    return v
                end

                local function persist()
                    local ok, enc = pcall(hs.json.encode, store, true)
                    if not ok then return end
                    local f = io.open(varsPath, "w")
                    if f then f:write(enc); f:close() end
                end

                local function ensureLoaded()
                    if loaded then return end
                    loaded = true
                    local f = io.open(varsPath, "r")
                    if not f then return end
                    local raw = f:read("*all"); f:close()
                    local ok, data = pcall(hs.json.decode, raw)
                    if ok and type(data) == "table" then
                        store.defs = type(data.defs) == "table" and data.defs or {}
                        store.vals = type(data.vals) == "table" and data.vals or {}
                    end
                end

                ms.vars = {}

                -- Read a helper var live. Falls back to the declared default,
                -- then nil for an undeclared name.
                ms.vars.get = function(name)
                    ensureLoaded()
                    if type(name) ~= "string" then return nil end
                    local v = store.vals[name]
                    if v == nil then
                        local def = store.defs[name]
                        return def and def.default or nil
                    end
                    return v
                end

                -- Write a helper var and persist. Auto-declares an untyped var
                -- on first write so a macro can use one without a prior def,
                -- but coerces to the declared type when one exists.
                ms.vars.set = function(name, value)
                    ensureLoaded()
                    if type(name) ~= "string"
                        or not name:match("^[%a_][%w_]*$") then return end
                    store.vals[name] = coerce(store.defs[name], value)
                    persist()
                    return store.vals[name]
                end

                -- Declare (or update) a helper var from the Tools panel.
                ms.vars.define = function(def)
                    ensureLoaded()
                    if type(def) ~= "table" then return false, "definition must be a table" end
                    local name = type(def.name) == "string" and def.name or ""
                    if not name:match("^[%a_][%w_]*$") then
                        return false, "name must be a valid identifier"
                    end
                    local t = def.type
                    if t ~= "number" and t ~= "string" and t ~= "boolean" then
                        t = "string"
                    end
                    store.defs[name] = {
                        type    = t,
                        default = def.default,
                        label   = type(def.label) == "string" and def.label or name,
                        hint    = type(def.hint) == "string" and def.hint or nil,
                        -- Where the declaration came from, for the Tools filter:
                        -- "pack" while ms_macros.lua runs, "plugin" during a
                        -- plugin load, else the user's own builder.
                        origin  = def.origin or ms._defineOrigin or "user",
                    }
                    if store.vals[name] == nil then
                        store.vals[name] = coerce(store.defs[name], def.default)
                    end
                    persist()
                    return true
                end

                ms.vars.remove = function(name)
                    ensureLoaded()
                    if store.defs[name] == nil and store.vals[name] == nil then
                        return false, "'" .. tostring(name) .. "' is not a helper var"
                    end
                    store.defs[name] = nil
                    store.vals[name] = nil
                    persist()
                    return true
                end

                -- List declarations (with live values) for the builder.
                ms.vars.list = function()
                    ensureLoaded()
                    local out = {}
                    for name, def in pairs(store.defs) do
                        out[#out + 1] = {
                            name    = name,
                            type    = def.type,
                            default = def.default,
                            label   = def.label,
                            hint    = def.hint,
                            value   = store.vals[name],
                            origin  = def.origin or "user",
                        }
                    end
                    table.sort(out, function(a, b) return a.name < b.name end)
                    return out
                end
            end

            ms._getRootLabel = function()
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack and #ctx.callStack > 0 then
                        return ctx.callStack[1]
                    end
                end
                if ms._capturedStack and #ms._capturedStack > 0 then
                    return ms._capturedStack[1]
                end
                return nil
            end

            ms._getCallChain = function()
                local co = coroutine.running()
                local stack = nil
                if co then
                    local ctx = ms._coroContext[co]
                    stack = ctx and ctx.callStack
                end
                if not stack and ms._capturedStack then
                    stack = ms._capturedStack
                end
                if stack and #stack > 0 then
                    if #stack == 1 then
                        return stack[1]
                    else
                        return stack[1] .. " > " .. stack[#stack]
                    end
                end
                return nil
            end

            ms.sub = function(label, fn)
                assert(type(fn) == "function", "ms.sub: fn must be a function")
                return function(...)
                    local co = coroutine.running()
                    local ctx = co and ms._coroContext[co]
                    if ctx then
                        if not ctx.callStack then ctx.callStack = {} end
                        table.insert(ctx.callStack, label)
                        local results = { fn(...) }
                        table.remove(ctx.callStack)
                        return table.unpack(results)
                    end
                    if ms._capturedStack then
                        table.insert(ms._capturedStack, label)
                        local results = { fn(...) }
                        table.remove(ms._capturedStack)
                        return table.unpack(results)
                    end
                    return fn(...)
                end
            end

            ms.pause = function(id)
                if not id then
                    for _, ctx in pairs(ms._activeContexts) do ctx.paused = true end
                    return
                end
                for _, ctx in pairs(ms._activeContexts) do
                    if ctx.callStack and ctx.callStack[1] == id then ctx.paused = true
                    return end
                end
            end

            ms.resume = function(id)
                local function _resume(co)
                    local ctx = ms._coroContext[co]
                    if not ctx then return end
                    ctx.paused = false
                    if coroutine.status(co) ~= "suspended" then return end
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        print("=== ms.resume error [" .. (ctx.callStack and ctx.callStack[1] or "?") .. "] ===\n" .. tostring(err))
                    end
                    if coroutine.status(co) == "dead" then
                        if ms.dev then ms.devtools:stopTrace(co) end
                        ms._coroContext[co] = nil
                        ms._activeContexts[ctx] = nil
                        if _keyFlushTimer then _keyFlushTimer:stop()
                        _keyFlushTimer = nil end
                        _keyFlush()
                        if ms.dev then ms.devtools:flushAll(ctx.callStack and ctx.callStack[1]) end
                    end
                end
                if not id then
                    for co in pairs(ms._coroContext) do _resume(co) end
                    return
                end
                for co, ctx in pairs(ms._coroContext) do
                    if ctx.callStack and ctx.callStack[1] == id then _resume(co)
                    return end
                end
            end

            ms.copy = function(text)
                if ms.dev then ms.devtools:flushAll() end
                if ms.dev._watcherPanel then
                    ms.devtools:watcherStep("copy")
                end
                if ms.dev then
                    ms.devtools:macroLog("copy")
                end
                hs.pasteboard.setContents(text)
            end

            ms.paste = function()
                if ms.dev then ms.devtools:flushAll() end
                if ms.dev._watcherPanel then
                    ms.devtools:watcherStep("paste")
                end
                if ms.dev then
                    ms.devtools:macroLog("paste")
                end
                -- Cmd+V through the synthetic event source (userData 999), so
                -- the app's own eventtaps ignore it like every other injected key.
                ms.type("v", { "cmd" })
            end

            -- Expand {name} tokens in a string at runtime against helper vars.
            -- Literal builder fields are interpolated at compile time (their
            -- braces are gone by the time they run), but a value read out of a
            -- helper var or setting still carries raw {name} tokens — this is
            -- what resolves those. Non-strings pass through untouched; bounded
            -- passes let a var reference another var without looping forever.
            ms.interp = function(s)
                if type(s) ~= "string" then return s end
                if not s:find("{", 1, true) then return s end
                local depth = 0
                while depth < 8 and s:find("{[%a_][%w_]*}") do
                    local changed = false
                    s = s:gsub("{([%a_][%w_]*)}", function(name)
                        changed = true
                        local v = ms.vars and ms.vars.get and ms.vars.get(name)
                        if v == nil then return "" end
                        return tostring(v)
                    end)
                    depth = depth + 1
                    if not changed then break end
                end
                return s
            end

            ms.cancelMacros = function()
                for co, ctx in pairs(ms._coroContext) do
                    ctx.cancelled = true
                    if ms.dev then ms.devtools:stopTrace(co) end
                end

                ms._activeContexts = {}
                ms._coroContext     = {}

                if ms.dev then ms.devtools:flushAll() end

                for keyCode, entry in pairs(ms._macroHeldKeys) do
                    local ev = hs.eventtap.event.newKeyEvent(entry.mods, keyCode, false)
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end
                ms._macroHeldKeys = {}

                for btn, entry in pairs(ms._macroHeldButtons) do
                    local ev = hs.eventtap.event.newMouseEvent(entry.upT, entry.pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end
                ms._macroHeldButtons = {}
            end

            ms._soundsDirty = true

            ms.soundExtensions = {
                "wav",
                "aiff",
                "aif",
                "mp3",
                "m4a",
                "caf",
                "aac",
            }

            ms.isSoundFile = function(file)
                local ext = file:match("%.([^%.]+)$")
                if not ext then return false end
                ext = ext:lower()
                for _, e in ipairs(ms.soundExtensions) do
                    if e == ext then return true end
                end
                return false
            end

            ms._autoSortSounds = function()
                local SoundLib = hs.configdir .. "/sounds/"
                local dirs = {
                    {
                        dir = SoundLib .. "defaults/",
                        prefix = "d_",
                    },
                    {
                        dir = SoundLib .. "active/",
                        prefix = "a_",
                    },
                    {
                        dir = SoundLib .. "macro/",
                        prefix = "m_",
                    },
                }
                for _, info in ipairs(dirs) do
                    if hs.fs.attributes(info.dir) then
                        for file in hs.fs.dir(info.dir) do
                            if file ~= "." and file ~= ".." and ms.isSoundFile(file) then
                                for _, dest in ipairs(dirs) do
                                    if file:sub(1, #dest.prefix) == dest.prefix
                                        and dest.dir ~= info.dir then
                                        local src = info.dir .. file
                                        local dst = dest.dir .. file
                                        if not hs.fs.attributes(dst) then
                                            os.rename(src, dst)
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end

            ms._discoverSounds = function()
                if not ms._soundsDirty then return end
                ms._soundsDirty = false
                ms.sounds      = {}
                ms.macroSounds = {}

                pcall(ms._autoSortSounds)

                local function scanDir(dir, target)
                    target = target or ms.sounds
                    if not hs.fs.attributes(dir) then return end
                    for file in hs.fs.dir(dir) do
                        if file ~= "." and file ~= ".." and ms.isSoundFile(file) then
                            local name = file:match("^(.+)%.[^%.]+$")
                            if name then
                                target[name] = dir .. file
                            end
                        end
                    end
                end

                scanDir(SoundDefaultsDir)

                if not ms._customThemeDisabled then
                    scanDir(SoundActiveDir)
                end

                scanDir(SoundMacroDir, ms.macroSounds)

                for name, filename in pairs(ms.importedSounds or {}) do
                    if not ms._customThemeDisabled and not ms.sounds[name] then
                        local path = SoundLib .. filename
                        if hs.fs.attributes(path) then
                            ms.sounds[name] = path
                        end
                    end
                end

                -- Health catch: if the active-sound folder was emptied or
                -- misplaced (e.g. a broken pack switch loses the custom sound
                -- library), assignments point at samples that no longer resolve.
                -- Surface ONE clear, de-duplicated warning instead of leaving
                -- playSlot to print a quiet per-file "could not load sound" line
                -- forever. _resolveSlot already falls back to the default sample
                -- so playback keeps working — this just tells the user why.
                local missing = 0
                for _, name in pairs(ms.soundAssign or {}) do
                    if type(name) == "string" and name ~= ""
                        and not ms.sounds[name] and not ms.macroSounds[name] then
                        missing = missing + 1
                    end
                end
                if missing > 0 then
                    local sig = missing .. "@" .. SoundActiveDir
                    if sig ~= ms._missingSoundsSig then
                        ms._missingSoundsSig = sig
                        local msg = missing .. " assigned sound"
                            .. (missing == 1 and "" or "s")
                            .. " could not be found — active sound folder may be "
                            .. "empty or misplaced (" .. SoundActiveDir
                            .. "). Falling back to defaults."
                        print("ms.sound: " .. msg)
                        if ms.dev and ms.dev.log then
                            pcall(ms.dev.log, {
                                type  = "warning",
                                event = "active_sounds_missing",
                                msg   = msg,
                                count = missing,
                            })
                        end
                        if ms.alert and ms.shell and ms.shell.isReady
                            and ms.shell.isReady() then
                            pcall(ms.alert, "Missing sounds\n" .. msg, 6)
                        end
                    end
                else
                    ms._missingSoundsSig = nil
                end
            end

            ms.sound = function(path, async, device)
                if ms.dev then ms.devtools:flushAll() end
                if path and not path:match("[/\\]") then
                    path = ms.sounds[path] or ms.macroSounds[path] or path
                end
                if path then
                    local fname = tostring(path):match("([^/\\]+)$") or tostring(path)
                    if fname ~= ms._lastSoundLog then
                        ms._lastSoundLog = fname
                        if ms.dev then
                            local displayLabel = ms._getCallChain()
                            if displayLabel then
                                ms.dev.log({
                                    type = "sound",
                                    msg = "[" .. displayLabel .. "] " .. fname,
                                    category = "macro"
                                })
                            end
                        end
                    end
                end
                if not ms.soundEnabled then return end
                if not path then return end
                local s = hs.sound.getByFile(path) or hs.sound.getByName(path)
                if not s then
                    print("ms.sound: could not load sound: " .. tostring(path))
                    return
                end
                if ms.soundVolume ~= nil then
                    s:volume(ms.soundVolume / 100)
                end
                if device then
                    local dev = hs.audiodevice.findOutputByName(device)
                    if dev then s:device(dev:uid()) end
                end
                async = (async ~= false)
                if not async then
                    local co  = coroutine.running()
                    local ctx = co and ms._coroContext[co]
                    if co then
                        s:setCallback(function(snd, state)
                            if state == "stop" then
                                snd:setCallback(nil)
                                if ctx and ctx.cancelled then return end
                                local ok, err = coroutine.resume(co)
                                if not ok then
                                    print("ms.sound resume error: " .. tostring(err))
                                end
                                if coroutine.status(co) == "dead" then
                                    if ms.dev then ms.devtools:stopTrace(co) end
                                    ms._coroContext[co] = nil
                                    if ctx then ms._activeContexts[ctx] = nil end
                                    if _keyFlushTimer then _keyFlushTimer:stop()
                                    _keyFlushTimer = nil end
                                    _keyFlush()
                                    if ms.dev then ms.devtools:flushAll() end
                                end
                            end
                        end)
                        s:play()
                        coroutine.yield()
                        return
                    end
                end
                s:play()
                return s
            end

            -- Only accept a resolved path that still exists on disk. The map
            -- ms.sounds is built at discovery time; if the active-sound folder
            -- is later emptied or misplaced (e.g. a broken pack switch), its
            -- entries point at files that are now gone. Verifying here lets
            -- resolution fall through to the built-in default sample instead of
            -- handing ms.sound a dead path (which only printed a per-sound
            -- "could not load sound" line, once per file, forever).
            local function _slotPathExists(p)
                return type(p) == "string" and hs.fs.attributes(p) ~= nil
            end

            local function _resolveSlot(id)
                local assigned = ms.soundAssign and ms.soundAssign[id]
                if assigned then
                    local p = (ms.sounds and ms.sounds[assigned])
                        or (ms.macroSounds and ms.macroSounds[assigned])
                    if not p and assigned:find("/", 1, true)
                        and hs.fs.attributes(assigned) then
                        p = assigned
                    end
                    if _slotPathExists(p) then return p end
                end

                local p = (ms.sounds and ms.sounds[id])
                    or (ms.macroSounds and ms.macroSounds[id])
                if _slotPathExists(p) then return p end

                local def = ms.soundSlot(id)
                if def and def.d then
                    local dp = ms.sounds and ms.sounds[def.d]
                    if _slotPathExists(dp) then return dp end
                end
                return nil
            end

            ms.playSlot = function(slotId)
                if not ms.soundEnabled then return false end
                if ms._quickReloading then return false end
                if ms._octaneMode and ms._octaneMuteSounds then return false end
                if not ms._startupSoundDone and slotId ~= "load" and slotId ~= "themeLoaded" and slotId ~= "updateAvailable" and slotId ~= "settingsOpen" and slotId ~= "settingsClose" then return false end
                ms._slotHandles = ms._slotHandles or {}
                if ms._slotHandles[slotId] then
                    pcall(function() ms._slotHandles[slotId]:stop() end)
                    ms._slotHandles[slotId] = nil
                end
                local path
                for _, id in ipairs(ms.soundSlotChain(slotId)) do
                    path = _resolveSlot(id)
                    if path then break end
                end
                if not path then return false end
                local handle = ms.sound(path) or false
                if handle then
                    ms._slotHandles[slotId] = handle
                    ms._slotStartedAt = ms._slotStartedAt or {}
                    ms._slotStartedAt[slotId] = hs.timer.secondsSinceEpoch()
                end
                return handle
            end

            ms._biasedMenuPt = function(raw)
                local p  = raw or hs.mouse.absolutePosition()
                local sf = hs.screen.mainScreen():frame()
                return {
                    x = p.x * 0.75 + (sf.x + sf.w * 0.2) * 0.12,
                    y = p.y * 0.75 + (sf.y + sf.h * 0.2) * 0.12,
                }
            end

            ms._menuHoverStart = function()
                if ms._menuHoverWatcher then return end
                local lastKey = nil
                ms._menuHoverWatcher = hs.timer.doEvery(0.025, function()
                    if not ms._menuVisible then return end
                    local el = hs.uielement.focusedElement()
                    if not el then return end
                    local ok, frame = pcall(function() return el:frame() end)
                    if not ok or not frame then return end
                    local key = frame.x .. "," .. frame.y
                    if key ~= lastKey then
                        lastKey = key
                        ms.playSlot("hover")
                    end
                end)
            end

            ms._menuHoverStop = function()
                if ms._menuHoverWatcher then
                    ms._menuHoverWatcher:stop()
                    ms._menuHoverWatcher = nil
                end
            end

            ms.mousePos = function()
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                local pos = hs.mouse.absolutePosition()
                if not win then return pos.x, pos.y end
                local f = win:frame()
                local relX = (pos.x - f.x) * (REF_W / f.w)
                local relY = (pos.y - f.y) * (REF_H / f.h)
                return relX, relY
            end

            -- Single source of truth for reading one screen pixel.
            -- Mirrors the window-monitor inspect sampler exactly: snapshot a
            -- 1x1 rect at absolute (ax, ay) and read colorAt(0, 0). Reading the
            -- top-left subpixel (not scale/2) keeps macro samples identical to
            -- what the inspect eyedropper reports on Retina displays.
            ms.screen = ms.screen or {}
            ms.screen.sampleAt = function(ax, ay)
                if not ax or not ay then return nil end

                local scr = hs.screen.mainScreen()
                for _, s in ipairs(hs.screen.allScreens()) do
                    local f = s:frame()
                    if ax >= f.x and ax < f.x + f.w
                    and ay >= f.y and ay < f.y + f.h then
                        scr = s
                        break
                    end
                end
                if not scr then return nil end

                local snap = scr:snapshot(hs.geometry.rect(ax, ay, 1, 1))
                if not snap then return nil end
                local c = snap:colorAt({ x = 0, y = 0 })
                if not c or c.red == nil then return nil end

                local r = math.floor((c.red   or 0) * 255 + 0.5)
                local g = math.floor((c.green or 0) * 255 + 0.5)
                local b = math.floor((c.blue  or 0) * 255 + 0.5)
                local a = math.floor((c.alpha or 1) * 255 + 0.5)
                return {
                    r = r, g = g, b = b, a = a,
                    hex = string.format("#%02X%02X%02X", r, g, b),
                }
            end

            ms.pixelColor = function(x, y, reference)
                reference = reference or "Absolute"
                local ax, ay = ms.resolvePoint(x, y, reference)
                if not ax or not ay then return nil end
                return ms.screen.sampleAt(ax, ay)
            end

            ms.pixelMatch = function(x, y, reference, r, g, b, tolerance)
                tolerance = tolerance or 10
                local c = ms.pixelColor(x, y, reference)
                if not c then return false end
                return math.abs(c.r - r) <= tolerance
                   and math.abs(c.g - g) <= tolerance
                   and math.abs(c.b - b) <= tolerance
            end

            ms.randWait = function(min, max)
                ms.wait(math.random(min, max))
            end

            ms.jitter = function(base, jitterMs)
                ms.wait(base + math.random(-jitterMs, jitterMs))
            end

            local _savedCursor = nil
            ms.saveCursor = function()
                _savedCursor = hs.mouse.absolutePosition()
                return _savedCursor
            end
            ms.restoreCursor = function()
                if _savedCursor then
                    hs.mouse.absolutePosition(_savedCursor)
                end
            end

            ms.appRunning = function(appName)
                return hs.application.get(appName) ~= nil
            end

            ms.appIsFront = function(appName)
                local front = hs.application.frontmostApplication()
                return front and front:name() == appName
            end

            ms.focus = function(appName)
                local app = hs.application.get(appName)
                if app then
                    pcall(function() app:activate() end)
                    return true
                end
                return false
            end

            ms.toggle = function(key, mods)
                if ms.keystate(key) then
                    ms.release(key, mods)
                else
                    ms.press(key, mods)
                end
            end

            ms.waitPixel = function(x, y, ref, r, g, b, tol, timeout)
                timeout = timeout or 5000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if ms.pixelMatch(x, y, ref, r, g, b, tol or 10) then return true end
                    ms.wait(50)
                end
                return false
            end

            ms.waitNotPixel = function(x, y, ref, r, g, b, tol, timeout)
                timeout = timeout or 5000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if not ms.pixelMatch(x, y, ref, r, g, b, tol or 10) then return true end
                    ms.wait(50)
                end
                return false
            end

            -- ── Screen text (OCR) ────────────────────────────────────
            -- Backed by the Vision helper binary (~/.local/bin/ms_ocr_read,
            -- compiled from mac/bin/ms_ocr_read.swift at deploy). Each call
            -- captures the region, hands the PNG to the helper, and maps the
            -- returned image-pixel boxes back to absolute screen points.
            -- Synchronous (~100ms) — same spirit as screen:snapshot.
            ms.screen._ocrBin = os.getenv("HOME") .. "/.local/bin/ms_ocr_read"

            -- Normalise a region arg into an absolute {x,y,w,h} in screen
            -- points. nil -> whole main screen. A region may carry `ref` to
            -- resolve its origin the way pixelColor does (e.g. "WindowTL").
            local function _resolveRegion(region)
                local f = hs.screen.mainScreen():frame()
                if type(region) ~= "table" then
                    return { x = f.x, y = f.y, w = f.w, h = f.h }
                end
                local x, y = region.x or 0, region.y or 0
                if region.ref then
                    x, y = ms.resolvePoint(x, y, region.ref)
                end
                return {
                    x = x, y = y,
                    w = region.w or f.w,
                    h = region.h or f.h,
                }
            end

            -- Capture a region to a temp PNG. Returns path, resolvedRegion
            -- or nil on failure.
            ms.screen.capture = function(region)
                local rg = _resolveRegion(region)
                if not rg.w or not rg.h or rg.w < 1 or rg.h < 1 then return nil end
                -- Pick the screen the region originates on (multi-monitor).
                local scr = hs.screen.mainScreen()
                for _, s in ipairs(hs.screen.allScreens()) do
                    local f = s:frame()
                    if rg.x >= f.x and rg.x < f.x + f.w
                    and rg.y >= f.y and rg.y < f.y + f.h then
                        scr = s
                        break
                    end
                end
                local snap = scr:snapshot(hs.geometry.rect(rg.x, rg.y, rg.w, rg.h))
                if not snap then return nil end
                -- os.tmpname() creates the base file; we want the .png sibling,
                -- so drop the empty base to avoid leaking one per call.
                local base = os.tmpname()
                os.remove(base)
                local path = base .. ".png"
                if not snap:saveToFile(path) then return nil end
                return path, rg
            end

            -- OCR a region. Returns { text = "line\nline", blocks = { ... } }
            -- where each block carries text, conf, an absolute-screen center
            -- {x, y} ready to click, corner {left, top}, and {w, h} — all in
            -- screen points. Returns nil if OCR is unavailable or failed.
            ms.screen.ocr = function(region, opts)
                opts = opts or {}
                local path, rg = ms.screen.capture(region)
                if not path then return nil end

                local cmd = "'" .. ms.screen._ocrBin .. "' '" .. path .. "'"
                    .. (opts.fast and " fast" or "")
                local out = hs.execute(cmd)
                os.remove(path)
                if not out or out == "" then return nil end

                local ok, data = pcall(function() return hs.json.decode(out) end)
                if not ok or type(data) ~= "table"
                or type(data.blocks) ~= "table" then
                    return nil
                end
                if data.error then
                    print("ms.screen.ocr: " .. tostring(data.error))
                    return nil
                end

                -- Pixels-per-point: helper's reported pixel width over the
                -- region's point width folds out the Retina backing scale
                -- without us having to query it.
                local sx = (data.w or rg.w) / rg.w
                local sy = (data.h or rg.h) / rg.h
                if sx == 0 then sx = 1 end
                if sy == 0 then sy = 1 end

                local blocks, texts = {}, {}
                for _, b in ipairs(data.blocks) do
                    local left = rg.x + (b.x or 0) / sx
                    local top  = rg.y + (b.y or 0) / sy
                    local w    = (b.w or 0) / sx
                    local h    = (b.h or 0) / sy
                    blocks[#blocks + 1] = {
                        text = b.text or "",
                        conf = b.conf or 0,
                        x    = left + w / 2,
                        y    = top + h / 2,
                        left = left, top = top, w = w, h = h,
                    }
                    texts[#texts + 1] = b.text or ""
                end
                return { text = table.concat(texts, "\n"), blocks = blocks }
            end

            -- OCR a region and pull the first number out of it. Drops commas
            -- and any non-numeric decoration (currency glyphs, "HP", etc.).
            -- Returns a Lua number or nil.
            ms.screen.readNumber = function(region, opts)
                local res = ms.screen.ocr(region, opts)
                if not res then return nil end
                local cleaned = res.text:gsub(",", "")
                local match = cleaned:match("%-?%d+%.?%d*")
                return match and tonumber(match) or nil
            end

            -- Find on-screen text (case-insensitive substring). Returns the
            -- center {x, y} of the first matching block (and the block), or
            -- nil.
            ms.screen.findText = function(text, region, opts)
                if not text or text == "" then return nil end
                local res = ms.screen.ocr(region, opts)
                if not res then return nil end
                local needle = tostring(text):lower()
                for _, b in ipairs(res.blocks) do
                    if b.text:lower():find(needle, 1, true) then
                        return { x = b.x, y = b.y }, b
                    end
                end
                return nil
            end

            -- Poll until `text` appears in the region (or disappears, with
            -- opts.gone). Returns the match coords {x, y} on success — false
            -- on timeout.
            ms.screen.waitText = function(text, region, timeout, opts)
                opts = opts or {}
                timeout = timeout or 5000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    local hit = ms.screen.findText(text, region, opts)
                    if opts.gone then
                        if not hit then return true end
                    elseif hit then
                        return hit
                    end
                    ms.wait(200)
                end
                return false
            end

            -- Pixel scanning is also exposed under ms.screen.* as its
            -- canonical home; the bare ms.pixelColor/etc. names stay as
            -- back-compat aliases (the macro registry and existing packs
            -- still call them).
            ms.screen.pixelColor   = ms.pixelColor
            ms.screen.pixelMatch   = ms.pixelMatch
            ms.screen.waitPixel    = ms.waitPixel
            ms.screen.waitNotPixel = ms.waitNotPixel

            -- Flat positional wrappers for the visual builder, whose step
            -- params are individual numbers rather than a region table. A
            -- zero/omitted w or h means "whole screen". Handwritten macros
            -- use the richer ms.screen.* region-table API directly.
            local function _regionFromArgs(x, y, w, h)
                if not w or w <= 0 or not h or h <= 0 then return nil end
                return { x = x or 0, y = y or 0, w = w, h = h }
            end
            ms.ocr = function(x, y, w, h)
                local res = ms.screen.ocr(_regionFromArgs(x, y, w, h))
                return res and res.text or nil
            end
            ms.readNumber = function(x, y, w, h)
                return ms.screen.readNumber(_regionFromArgs(x, y, w, h))
            end
            ms.findText = function(text, x, y, w, h)
                return ms.screen.findText(text, _regionFromArgs(x, y, w, h))
            end
            ms.waitText = function(text, x, y, w, h, timeout)
                return ms.screen.waitText(text, _regionFromArgs(x, y, w, h), timeout)
            end

            ms.waitApp = function(appName, timeout)
                timeout = timeout or 10000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if hs.application.get(appName) then return true end
                    ms.wait(100)
                end
                return false
            end

            ms.waitNotApp = function(appName, timeout)
                timeout = timeout or 10000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if not hs.application.get(appName) then return true end
                    ms.wait(100)
                end
                return false
            end

            ms.windowPos = function(appName)
                local app = hs.application.get(appName)
                if not app then return nil end
                local win = app:mainWindow()
                if not win then return nil end
                local f = win:frame()
                return {
                    x = f.x,
                    y = f.y,
                    w = f.w,
                    h = f.h,
                }
            end

            ms.window = function(operation, a, b, c, d)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then return false end
                local op = tostring(operation or "Move"):lower()
                local ok = pcall(function()
                    if op == "resize" then
                        win:setSize({
                            w = tonumber(a) or 0,
                            h = tonumber(b) or 0,
                        })
                    elseif op == "frame" then
                        win:setFrame({
                            x = tonumber(a) or 0,
                            y = tonumber(b) or 0,
                            w = tonumber(c) or 0,
                            h = tonumber(d) or 0,
                        })
                    else
                        win:setTopLeft({
                            x = tonumber(a) or 0,
                            y = tonumber(b) or 0,
                        })
                    end
                end)
                return ok
            end

            ms.multiPress = function(keys, delayMs, mods)
                delayMs = delayMs or 15
                for i, key in ipairs(keys) do
                    ms.type(key, mods)
                    if i < #keys then ms.wait(delayMs) end
                end
            end

            ms.setVolume = function(level)
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setVolume(level) end
            end

            ms.mute = function()
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setMuted(true) end
            end

            ms.unmute = function()
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setMuted(false) end
            end

            ms.screenshot = function(path)
                path = path or os.getenv("HOME") .. "/Desktop/screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
                local screen = hs.screen.mainScreen()
                if not screen then return nil end
                local img = screen:snapshot()
                if not img then return nil end
                img:saveToFile(path)
                return path
            end

            local _clipWatcher = nil
            ms.clipChanged = function(callback)
                if _clipWatcher then _clipWatcher:stop() end
                _clipWatcher = hs.pasteboard.watcher.new(callback)
                _clipWatcher:start()
                return _clipWatcher
            end

            ms.moveMouse = function(x, y, ref, durationMs)
                durationMs = tonumber(durationMs) or 200
                local targetX, targetY = ms.resolvePoint(x, y, ref or "Absolute")
                local startPos = hs.mouse.absolutePosition()
                local startX, startY = startPos.x, startPos.y
                local dx = targetX - startX
                local dy = targetY - startY
                -- Zero-distance or near-instant move: jump and return. Recorded
                -- move steps use a tiny durationMs (~8), so they land here.
                if durationMs <= 16 or (dx == 0 and dy == 0) then
                    hs.mouse.absolutePosition({ x = targetX, y = targetY })
                    return
                end
                -- Animate synchronously: block this coroutine (via ms.wait)
                -- frame-by-frame so playback stays ordered. The old async
                -- timer returned immediately, so a macro's move steps all
                -- fired at once (teleport at start, replay-fast at the end).
                local frameMs = 16
                local steps = math.max(1, math.floor(durationMs / frameMs + 0.5))
                for step = 1, steps do
                    local t = step / steps
                    t = 1 - (1 - t) ^ 3
                    hs.mouse.absolutePosition({
                        x = startX + dx * t,
                        y = startY + dy * t,
                    })
                    if step < steps then ms.wait(frameMs) end
                end
                hs.mouse.absolutePosition({ x = targetX, y = targetY })
            end

            ms.dragPath = function(points, button, ref, delayMs)
                if type(points) == "string" then
                    local parsed = {}
                    for pair in points:gmatch("[^;]+") do
                        local sx, sy = pair:match("^%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
                        local nx, ny = tonumber(sx), tonumber(sy)
                        if nx and ny then parsed[#parsed + 1] = {
                            nx,
                            ny,
                        } end
                    end
                    points = parsed
                end
                if type(points) ~= "table" or #points < 2 then return end
                button = button or "Left"
                delayMs = delayMs or 10
                local btnNum = button == "Right" and 1
                    or ((button == "Middle" or button == "Center") and 2 or 0)
                local downType = btnNum == 1 and hs.eventtap.event.types.rightMouseDown
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseDown
                    or hs.eventtap.event.types.leftMouseDown)
                local upType = btnNum == 1 and hs.eventtap.event.types.rightMouseUp
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseUp
                    or hs.eventtap.event.types.leftMouseUp)
                local dragType = btnNum == 1 and hs.eventtap.event.types.rightMouseDragged
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseDragged
                    or hs.eventtap.event.types.leftMouseDragged)

                local x1, y1 = ms.resolvePoint(points[1][1], points[1][2], ref or "Absolute")
                hs.mouse.absolutePosition({
                    x = x1,
                    y = y1,
                })
                local downEv = hs.eventtap.event.newMouseEvent(downType, {
                    x = x1,
                    y = y1,
                })
                if btnNum > 0 then downEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                downEv:post()
                ms.wait(delayMs)

                for i = 2, #points do
                    local px, py = ms.resolvePoint(points[i][1], points[i][2], ref or "Absolute")
                    hs.mouse.absolutePosition({
                        x = px,
                        y = py,
                    })
                    local dragEv = hs.eventtap.event.newMouseEvent(dragType, {
                        x = px,
                        y = py,
                    })
                    if btnNum > 0 then dragEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                    dragEv:post()
                    ms.wait(delayMs)
                end

                local finalPos = hs.mouse.absolutePosition()
                local upEv = hs.eventtap.event.newMouseEvent(upType, finalPos)
                if btnNum > 0 then upEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                upEv:post()
            end

            ms.notify = function(title, subTitle, infoText)
                local note = hs.notify.new({
                    title = title or "mudscript",
                    subTitle = subTitle or "",
                    informativeText = infoText or "",
                }):send()
                return note
            end

                ms._antiTimeout = {
                    fn = nil,
                    interval = 900,
                    timer = nil,
                    running = false,
                }

                ms.antiTimeout = function(config)
                    assert(type(config) == "table", "ms.antiTimeout: config must be a table")
                    assert(type(config.action) == "function", "ms.antiTimeout: config.action must be a function")

                    ms._antiTimeout.fn       = config.action
                    ms._antiTimeout.interval = tonumber(config.interval) or 900

                    local enabled  = config.enabled
                    if enabled == nil then enabled = true end
                    if ms._antiTimeoutEnabled == true then
                        enabled = true
                    elseif ms._antiTimeoutEnabled == false then
                        enabled = false
                    end

                    if ms._antiTimeout.timer then
                        ms._antiTimeout.timer:stop()
                        ms._antiTimeout.timer = nil
                    end

                    if enabled then
                        ms._antiTimeout.running = true
                        local wrappedFn = ms.fn(ms._antiTimeout.fn)
                        ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                            if not ms._antiTimeout.running then return end
                            if not ms._targetActive then return end
                            pcall(wrappedFn)
                        end)
                    else
                        ms._antiTimeout.running = false
                    end
                end

                ms.antiTimeoutStop = function()
                    ms._antiTimeout.running = false
                    if ms._antiTimeout.timer then
                        ms._antiTimeout.timer:stop()
                        ms._antiTimeout.timer = nil
                    end
                end

                ms.antiTimeoutStart = function()
                    if not ms._antiTimeout.fn then return end
                    ms._antiTimeout.running = true
                    if not ms._antiTimeout.timer then
                        local wrappedFn = ms.fn(ms._antiTimeout.fn)
                        ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                            if not ms._antiTimeout.running then return end
                            if not ms._targetActive then return end
                            pcall(wrappedFn)
                        end)
                    end
                end

                ms.antiTimeoutToggle = function()
                    if ms._antiTimeout.running then
                        ms.antiTimeoutStop()
                    else
                        ms.antiTimeoutStart()
                    end
                    return ms._antiTimeout.running
                end
            -- END Anti-Timeout --

        -- END 8. Utilities --

        -- 9. Bind System & Settings Panel --
            ms.bind.define = function(id, a, b)
                assert(type(id) == "string", "ms.bind.define: id must be a string")
                local fn   = type(a) == "function" and a or (type(b) == "function" and b or nil)
                local opts = type(a) == "table"    and a or (type(b) == "table"    and b or {})
                if opts.sub or opts.mod then
                    error("bind '" .. id .. "' uses deprecated sub/mod syntax. "
                        .. "Update to: default = { type = \"<parentID>\", mods = {\"<mod>\"} }. "
                        .. "See documentation for the unified bind model.", 2)
                end
                local label, group
                if opts.default and type(opts.default) == "table" and opts.default.type
                    and ms.registry._defs[opts.default.type] then
                    label = opts.label or id
                    group = opts.group
                else
                    if opts.label then
                        label = opts.label
                    else
                        ms.bind._autoCount = ms.bind._autoCount + 1
                        label = "Macro" .. ms.bind._autoCount
                    end
                    group = opts.group or "main"
                end
                ms.registry._defs[id] = {
                    label    = label,
                    group    = group,
                    enabled  = (opts.enabled ~= false),
                    cooldown = opts.cooldown or 1000,
                    shared   = opts.shared,
                    info     = opts.info,
                    default  = opts.default,
                    system   = opts.system or false,
                }
                table.insert(ms.registry._defList, id)
                if fn ~= nil then
                    assert(type(fn) == "function",
                        "ms.bind.define: fn must be a function for id '" .. id .. "'")
                    ms.bind._wires[id] = fn
                end
            end

            ms.bind._registerSystemBinds = function()
                ms.bind.define("__panicButton", nil, {
                    label      = "Panic Button / Stop All",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = {
                        type = "key",
                        mods = {"alt"},
                        key = "F10",
                    },
                })
                ms.bind.define("__quickReload", nil, {
                    label      = "Quick Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = {
                        type = "key",
                        mods = {"alt"},
                        key = "[",
                    },
                })
                ms.bind.define("__fullReload", nil, {
                    label      = "Full Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = {
                        type = "key",
                        mods = {"alt"},
                        key = "]",
                    },
                })
                ms.bind.define("__openMenu", nil, {
                    label      = "Open Menu",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = {
                        type = "key",
                        mods = {"alt"},
                        key = "p",
                    },
                })
            end

            local function modsMatch(bindMods, eventMods)
                if bindMods == "any" then
                    return true
                end
                return ms.util.modsEqual(bindMods, eventMods)
            end

            ms.systemBinds._defs = {
                enable  = {
                    label = "Enable Macros",
                    default = {
                        type = "key",
                        mods = "any",
                        key = "return",
                    },
                },
                disable = {
                    label = "Disable Macros",
                    default = {
                        type = "key",
                        mods = "any",
                        key = "/",
                    },
                },
                toggle  = {
                    label = "Toggle Macros",
                    default = {
                        type = "key",
                        mods = "any",
                        key = "escape",
                    },
                },
                octane  = {
                    label = "Toggle Octane Mode",
                    default = {
                        type = "key",
                        mods = {"alt"},
                        key = "o",
                    },
                },
            }

            ms.systemBinds._actions = {
                enable  = function() ms.setMacros(1) end,
                disable = function() ms.setMacros(0) end,
                toggle  = function() ms.setMacros(BindValidity == 1 and 0 or 1) end,
                octane  = function() ms.octane.toggle() end,
            }

            ms.systemBinds.effective = function(id)
                return ms.systemBinds._config[id]
                    or (ms.systemBinds._defs[id] and ms.systemBinds._defs[id].default)
            end

            ms.systemBinds.bindStr = function(id)
                local c = ms.systemBinds.effective(id)
                if not c then return "( unset )" end
                if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                if c.type == "scroll" then
                    local d = c.direction or "?"
                    return "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
                end
                if c.type == "gamepad" then return "Pad " .. (c.button or "?"):upper() end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do table.insert(parts, m:sub(1, 1):upper() .. m:sub(2)) end
                table.insert(parts, (c.key or ""):upper())
                return table.concat(parts, "+")
            end

            ms.systemBinds.rebind = function()
                for _, h in pairs(ms.systemBinds._handles) do
                    if h and h.delete then h:delete() end
                end
                ms.systemBinds._handles = {}

                for id, action in pairs(ms.systemBinds._actions) do
                    local c = ms.systemBinds.effective(id)
                    if not c then goto sysBindContinue end
                    if c.type == "key" then
                        ms.systemBinds._handles[id] = ms.key(c.mods, c.key, false, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, nil, true)
                    elseif c.type == "mouse" then
                        ms.systemBinds._handles[id] = ms.mouse(c.button, false, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms.systemBinds._handles[id] = ms.scrollBind(c.direction, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms.systemBinds._handles[id] = ms.gamepadBind(c.button, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    end
                    ::sysBindContinue::
                end
            end

            ms.bind.group = function(id)
                local def = ms.registry._defs[id]
                if not def then return "G_" .. tostring(id) end
                if def.shared then return def.shared end
                local current, seen = id, {}
                while true do
                    local d = ms.registry._defs[current]
                    if not d or not d.default or type(d.default) ~= "table"
                        or not d.default.type or not ms.registry._defs[d.default.type]
                        or seen[current] then break end
                    seen[current] = true
                    current = d.default.type
                end
                local rootDef = ms.registry._defs[current]
                if rootDef and rootDef.shared then return rootDef.shared end
                return "G_" .. current
            end

            ms.done = function(id)
                local group = ms.bind.group(id)
                local timer = ms.running[group]
                if timer then
                    timer:stop()
                    ms.running[group] = nil
                end
            end

            ms.fn.define("ms.press", ms.press, {
                label  = "Press Key",
                group  = "input",
                info   = "Press and release a key",
                params = {
                    {
                        name = "key",
                        type = "string",
                    },
                    {
                        name = "mods",
                        type = "table",
                    },
                },
                icon   = "inputs",
            })
            ms.fn.define("ms.release", ms.release, {
                label  = "Release Key",
                group  = "input",
                info   = "Release a held key",
                params = {
                    {
                        name = "key",
                        type = "string",
                    },
                    {
                        name = "mods",
                        type = "table",
                    },
                },
                icon   = "inputs",
            })
            ms.fn.define("ms.type", ms.type, {
                label  = "Type Key",
                group  = "input",
                info   = "Type a key with modifiers and optional hold duration",
                params = {
                    {
                        name = "key",
                        type = "string",
                    },
                    {
                        name = "mods",
                        type = "table",
                    },
                    {
                        name = "holdMs",
                        type = "number",
                    },
                },
                icon   = "inputs",
            })
            ms.fn.define("ms.toggle", ms.toggle, {
                label  = "Toggle Key",
                group  = "input",
                info   = "Toggle a key on/off",
                params = {
                    {
                        name = "key",
                        type = "string",
                    },
                    {
                        name = "mods",
                        type = "table",
                    },
                },
                icon   = "inputs",
            })
            ms.fn.define("ms.multiPress", ms.multiPress, {
                label  = "Multi Press",
                group  = "input",
                info   = "Press multiple keys in sequence",
                params = {
                    {
                        name = "keys",
                        type = "table",
                    },
                    {
                        name = "delayMs",
                        type = "number",
                    },
                    {
                        name = "mods",
                        type = "table",
                    },
                },
                icon   = "inputs",
            })
            ms.fn.define("ms.Mouse", ms.Mouse, {
                label  = "Mouse",
                group  = "mouse",
                info   = "Full mouse control (Click, Drag, Move, etc.)",
                params = {
                    {
                        name = "operation",
                        type = "string",
                    },
                    {
                        name = "button",
                        type = "string",
                    },
                    {
                        name = "reference",
                        type = "string",
                    },
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                },
                icon   = "move",
            })
            ms.fn.define("ms.scroll", ms.scroll, {
                label  = "Scroll",
                group  = "mouse",
                info   = "Scroll the mouse wheel",
                params = {
                    {
                        name = "direction",
                        type = "string",
                    },
                    {
                        name = "clicks",
                        type = "number",
                    },
                },
                icon   = "scroll",
            })
            ms.fn.define("ms.moveMouse", ms.moveMouse, {
                label  = "Move Mouse",
                group  = "mouse",
                info   = "Move mouse to position with optional duration",
                params = {
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                    {
                        name = "durationMs",
                        type = "number",
                    },
                },
                icon   = "move",
            })
            ms.fn.define("ms.dragPath", ms.dragPath, {
                label  = "Drag Path",
                group  = "mouse",
                info   = "Drag mouse through a series of points",
                params = {
                    {
                        name = "points",
                        type = "string",
                    },
                    {
                        name = "button",
                        type = "string",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                    {
                        name = "delayMs",
                        type = "number",
                    },
                },
                icon   = "move",
            })
            ms.fn.define("ms.cam", ms.cam, {
                label  = "Camera",
                group  = "mouse",
                info   = "Move camera by delta",
                params = {
                    {
                        name = "dx",
                        type = "number",
                    },
                    {
                        name = "dy",
                        type = "number",
                    },
                },
                icon   = "move",
            })

            ms.fn.define("ms.wait", ms.wait, {
                label  = "Wait",
                group  = "timing",
                info   = "Wait for a duration in milliseconds",
                params = { {
                    name = "ms",
                    type = "number",
                    default = 100,
                } },
                icon   = "pause",
            })
            ms.fn.define("ms.randWait", ms.randWait, {
                label  = "Random Wait",
                group  = "timing",
                info   = "Wait for a random duration between min and max",
                params = {
                    {
                        name = "min",
                        type = "number",
                    },
                    {
                        name = "max",
                        type = "number",
                    },
                },
                icon   = "pause",
            })
            ms.fn.define("ms.jitter", ms.jitter, {
                label  = "Jitter",
                group  = "timing",
                info   = "Wait with random jitter around a base duration",
                params = {
                    {
                        name = "base",
                        type = "number",
                    },
                    {
                        name = "jitterMs",
                        type = "number",
                    },
                },
                icon   = "pause",
            })

            ms.fn.define("ms.pixelColor", ms.pixelColor, {
                label  = "Pixel Color",
                group  = "sensing",
                info   = "Get the RGB color of a pixel",
                params = {
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.pixelMatch", ms.pixelMatch, {
                label  = "Pixel Match",
                group  = "sensing",
                info   = "Check if a pixel matches a color",
                params = {
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                    {
                        name = "r",
                        type = "number",
                    },
                    {
                        name = "g",
                        type = "number",
                    },
                    {
                        name = "b",
                        type = "number",
                    },
                    {
                        name = "tol",
                        type = "number",
                    },
                },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.waitPixel", ms.waitPixel, {
                label  = "Wait for Pixel",
                group  = "sensing",
                info   = "Wait until a pixel matches a color",
                params = {
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                    {
                        name = "r",
                        type = "number",
                    },
                    {
                        name = "g",
                        type = "number",
                    },
                    {
                        name = "b",
                        type = "number",
                    },
                    {
                        name = "tol",
                        type = "number",
                    },
                    {
                        name = "timeout",
                        type = "number",
                    },
                },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.waitNotPixel", ms.waitNotPixel, {
                label  = "Wait for Pixel Change",
                group  = "sensing",
                info   = "Wait until a pixel no longer matches a color",
                params = {
                    {
                        name = "x",
                        type = "number",
                    },
                    {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "ref",
                        type = "string",
                    },
                    {
                        name = "r",
                        type = "number",
                    },
                    {
                        name = "g",
                        type = "number",
                    },
                    {
                        name = "b",
                        type = "number",
                    },
                    {
                        name = "tol",
                        type = "number",
                    },
                    {
                        name = "timeout",
                        type = "number",
                    },
                },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.mousePos", ms.mousePos, {
                label  = "Mouse Position",
                group  = "sensing",
                info   = "Get current mouse position",
                params = {},
                icon   = "move",
            })
            ms.fn.define("ms.keystate", ms.keystate, {
                label  = "Key State",
                group  = "sensing",
                info   = "Check if a key is currently held",
                params = { {
                    name = "key",
                    type = "string",
                } },
                icon   = "inputs",
            })
            ms.fn.define("ms.mousestate", ms.mousestate, {
                label  = "Mouse State",
                group  = "sensing",
                info   = "Check if a mouse button is currently held (left/right/middle)",
                params = { {
                    name = "button",
                    type = "string",
                } },
                icon   = "inputs",
            })
            ms.fn.define("ms.ocr", ms.ocr, {
                label  = "Read Text",
                group  = "sensing",
                info   = "OCR a screen region (x,y,w,h); blank size = whole screen",
                params = {
                    { name = "x", type = "number" },
                    { name = "y", type = "number" },
                    { name = "w", type = "number" },
                    { name = "h", type = "number" },
                },
                icon   = "ocr",
            })
            ms.fn.define("ms.readNumber", ms.readNumber, {
                label  = "Read Number",
                group  = "sensing",
                info   = "OCR a region and return the first number in it",
                params = {
                    { name = "x", type = "number" },
                    { name = "y", type = "number" },
                    { name = "w", type = "number" },
                    { name = "h", type = "number" },
                },
                icon   = "ocr",
            })
            ms.fn.define("ms.findText", ms.findText, {
                label  = "Find Text",
                group  = "sensing",
                info   = "Find text on screen; returns its center {x,y} to click",
                params = {
                    { name = "text", type = "string" },
                    { name = "x", type = "number" },
                    { name = "y", type = "number" },
                    { name = "w", type = "number" },
                    { name = "h", type = "number" },
                },
                icon   = "ocr",
            })
            ms.fn.define("ms.waitText", ms.waitText, {
                label  = "Wait for Text",
                group  = "sensing",
                info   = "Wait until text appears in a region; returns its {x,y}",
                params = {
                    { name = "text", type = "string" },
                    { name = "x", type = "number" },
                    { name = "y", type = "number" },
                    { name = "w", type = "number" },
                    { name = "h", type = "number" },
                    { name = "timeout", type = "number" },
                },
                icon   = "ocr",
            })

            ms.fn.define("ms.copy", ms.copy, {
                label  = "Copy",
                group  = "clipboard",
                info   = "Copy text to clipboard",
                params = { {
                    name = "text",
                    type = "string",
                } },
                icon   = "save",
            })

            ms.fn.define("ms.paste", ms.paste, {
                label  = "Paste",
                group  = "clipboard",
                info   = "Paste the clipboard (Cmd+V)",
                params = {},
                icon   = "save",
            })

            ms.fn.define("ms.appRunning", ms.appRunning, {
                label  = "App Running",
                group  = "app",
                info   = "Check if an app is running",
                params = { {
                    name = "appName",
                    type = "string",
                } },
                icon   = "window",
            })
            ms.fn.define("ms.appIsFront", ms.appIsFront, {
                label  = "App in Front",
                group  = "app",
                info   = "Check if an app is the frontmost",
                params = { {
                    name = "appName",
                    type = "string",
                } },
                icon   = "window",
            })
            ms.fn.define("ms.focus", ms.focus, {
                label  = "Focus App",
                group  = "app",
                info   = "Bring an app to the front",
                params = { {
                    name = "appName",
                    type = "string",
                } },
                icon   = "window",
            })
            ms.fn.define("ms.windowPos", ms.windowPos, {
                label  = "Window Position",
                group  = "app",
                info   = "Get the position of an app's window",
                params = { {
                    name = "appName",
                    type = "string",
                } },
                icon   = "window",
            })
            ms.fn.define("ms.window", ms.window, {
                label  = "Window Move/Resize",
                group  = "app",
                info   = "Move or resize the focused window (Move/Resize/Frame)",
                params = {
                    {
                        name = "operation",
                        type = "string",
                    },
                    {
                        name = "x",
                        type = "number",
                    }, {
                        name = "y",
                        type = "number",
                    },
                    {
                        name = "w",
                        type = "number",
                    }, {
                        name = "h",
                        type = "number",
                    },
                },
                icon   = "window",
            })

            ms.fn.define("ms.sound", ms.sound, {
                label  = "Play Sound",
                group  = "system",
                info   = "Play a sound file",
                params = { {
                    name = "path",
                    type = "string",
                } },
                icon   = "play",
            })
            ms.fn.define("ms.alert", ms.alert, {
                label  = "Alert",
                group  = "system",
                info   = "Show a toast notification",
                params = {
                    {
                        name = "msg",
                        type = "string",
                    },
                    {
                        name = "duration",
                        type = "number",
                    },
                },
                icon   = "alert",
            })
            ms.fn.define("ms.notify", ms.notify, {
                label  = "Notify",
                group  = "system",
                info   = "Show a system notification",
                params = {
                    {
                        name = "title",
                        type = "string",
                    },
                    {
                        name = "subTitle",
                        type = "string",
                    },
                    {
                        name = "infoText",
                        type = "string",
                    },
                },
                icon   = "alert",
            })
            ms.fn.define("ms.screenshot", ms.screenshot, {
                label  = "Screenshot",
                group  = "system",
                info   = "Take a screenshot",
                params = { {
                    name = "path",
                    type = "string",
                } },
                icon   = "record",
            })
            ms.fn.define("ms.setVolume", ms.setVolume, {
                label  = "Set Volume",
                group  = "system",
                info   = "Set system volume (0-100)",
                params = { {
                    name = "level",
                    type = "number",
                } },
                icon   = "play",
            })
            ms.fn.define("ms.mute", ms.mute, {
                label  = "Mute",
                group  = "system",
                info   = "Mute system audio",
                params = {},
                icon   = "stop",
            })
            ms.fn.define("ms.unmute", ms.unmute, {
                label  = "Unmute",
                group  = "system",
                info   = "Unmute system audio",
                params = {},
                icon   = "play",
            })
            ms.fn.define("ms.clipChanged", ms.clipChanged, {
                label  = "Clipboard Changed",
                group  = "system",
                info   = "Register a callback for clipboard changes",
                params = { {
                    name = "callback",
                    type = "function",
                } },
                icon   = "watcher",
            })
            ms.fn.define("ms.saveCursor", ms.saveCursor, {
                label  = "Save Cursor",
                group  = "system",
                info   = "Save current cursor position",
                params = {},
                icon   = "save",
            })
            ms.fn.define("ms.restoreCursor", ms.restoreCursor, {
                label  = "Restore Cursor",
                group  = "system",
                info   = "Restore saved cursor position",
                params = {},
                icon   = "upload",
            })

            ms.fn.define("ms.cancelMacros", ms.cancelMacros, {
                label  = "Cancel Macros",
                group  = "control",
                info   = "Cancel all running macros",
                params = {},
                icon   = "stop",
            })
            ms.fn.define("ms.pause", ms.pause, {
                label  = "Pause",
                group  = "control",
                info   = "Pause current macro",
                params = {},
                icon   = "pause",
            })
            ms.fn.define("ms.resume", ms.resume, {
                label  = "Resume",
                group  = "control",
                info   = "Resume paused macro",
                params = {},
                icon   = "play",
            })
            ms.fn.define("ms.done", ms.done, {
                label  = "Done",
                group  = "control",
                info   = "Signal macro completion",
                params = {},
                icon   = "stop",
            })

            ms.bind.teardown = function()
                for id, handle in pairs(ms.bindHandles) do
                    if handle and handle.delete then handle:delete() end
                end
                ms.bindHandles = {}
                ms._modBindings = {}
                ms._mouseCallbacks = {}
                ms._scrollCallbacks = {}
                if ms._scrollListener then
                    ms._scrollListener:stop()
                    ms._scrollListener = nil
                end
                ms._gamepadCallbacks = {}
                ms.gamepadStop()
            end

            ms.bind.rebind = function()
                ms.bind.teardown()

                local function bindKey(c)
                    if not c then return nil end
                    local mods = {}
                    for _, m in ipairs(c.mods or {}) do mods[#mods+1] = m end
                    table.sort(mods)
                    local modStr = #mods > 0 and (":" .. table.concat(mods, ",")) or ""
                    if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) .. modStr end
                    if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") .. modStr end
                    if c.type == "gamepad" then return "gamepad:" .. (c.button or "?")  .. modStr end
                    if c.type == "combo"   then
                        local ks = {}
                        for _, k in ipairs(c.keys or {}) do ks[#ks+1] = k end
                        table.sort(ks)
                        return "combo:" .. table.concat(ks, "+") .. modStr
                    end
                    if c.type == "mods"    then return "mods:" .. table.concat(mods, ",") end
                    return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                end

                local function triggerKey(c)
                    if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) end
                    if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") end
                    if c.type == "gamepad" then return "gamepad:" .. (c.button or "?") end
                    return nil
                end

                local function modCount(c)
                    if not c then return 0 end
                    local n = 0
                    for _ in ipairs(c.mods or {}) do n = n + 1 end
                    if c.type == "combo" then
                        for _ in ipairs(c.keys or {}) do n = n + 1 end
                    end
                    return n
                end

                local conflicted = {}

                local rootUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def then goto c1 end
                    if ms._suppressedMacros and ms._suppressedMacros[id] then goto c1 end
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto c1 end
                    local key = bindKey(ms.effectiveBind(id))
                    if key then
                        if rootUsed[key] then
                            local other = rootUsed[key]
                            conflicted[id] = true
                            conflicted[other] = true
                            local l1 = ms.registry._defs[id].label
                            local l2 = ms.registry._defs[other].label
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l1 .. "\" and \"" .. l2
                                    .. "\" share the same input.\nBoth disabled. Right-click the macro in the Macros panel > Rebind to resolve.", 10)
                            end)
                        else
                            rootUsed[key] = id
                        end
                    end
                    ::c1::
                end

                local sortedIds = {}
                for _, id in ipairs(ms.registry._defList) do
                    sortedIds[#sortedIds + 1] = id
                end
                table.sort(sortedIds, function(a, b)
                    local ca = modCount(ms.effectiveBind(a))
                    local cb = modCount(ms.effectiveBind(b))
                    return ca > cb
                end)

                local deviceGroups = {}
                local deviceOrder  = {}

                for _, id in ipairs(sortedIds) do
                    if conflicted[id] then goto continue end
                    local fn  = ms.bind._wires[id]
                    local def = ms.registry._defs[id]
                    if not fn or not def then goto continue end
                    if ms._suppressedMacros and ms._suppressedMacros[id] then goto continue end

                    local group    = ms.bind.group(id)
                    local cooldown = ms.cooldowns[id] or def.cooldown or 1000

                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto continue end
                    local c = ms.effectiveBind(id)
                    if not c then goto continue end
                    local function firedFn()
                        if ms.running[group] then return end
                        ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                            ms.running[group] = nil
                        end)
                        if ms.dev then
                            local _trig = (function()
                                if c.type == "mouse" then return "M" .. c.button end
                                if c.type == "scroll" then return "S:" .. (c.direction or "?") end
                                if c.type == "gamepad" then return "G:" .. (c.button or "?") end
                                if c.type == "combo" then
                                    local _p = {}
                                    for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                    for _, k in ipairs(c.keys or {}) do _p[#_p+1] = k end
                                    return table.concat(_p, "+")
                                end
                                local _p = {}
                                for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                _p[#_p+1] = c.key or ""
                                return table.concat(_p, "+")
                            end)()
                            pcall(ms.dev._onMacroFire, id, def.label, nil, nil, _trig)
                        end
                        ms._pendingLabel = def.label
                        fn()
                    end
                    local ignoreMods = ms.bindIgnoreMods and ms.bindIgnoreMods[id] or false
                    if c.type == "key" then
                        ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn, nil, false, ignoreMods)
                    elseif c.type == "mods" then
                        local modSet = {}
                        for _, m in ipairs(c.mods or {}) do modSet[m] = true end
                        -- Ignore an empty set (would fire on every key release).
                        if next(modSet) then
                            ms._modBindings[#ms._modBindings + 1] = {
                                modSet  = modSet,
                                firedFn = firedFn,
                                fired   = false,
                            }
                        end
                    elseif c.type == "combo" then
                        ms.bindHandles[id] = ms.keyCombo(c.mods, c.keys, false, firedFn, false, ignoreMods)
                    elseif c.type == "mouse" or c.type == "scroll" or c.type == "gamepad" then
                        local tkey = triggerKey(c)
                        local grp  = deviceGroups[tkey]
                        if not grp then
                            grp = {
                                ctype = c.type,
                                button = c.button,
                                direction = c.direction,
                                claimants = {},
                            }
                            deviceGroups[tkey] = grp
                            deviceOrder[#deviceOrder + 1] = tkey
                        end
                        grp.claimants[#grp.claimants + 1] = {
                            mods = c.mods or {},
                            firedFn = firedFn,
                        }
                    end

                    ::continue::
                end

                for _, tkey in ipairs(deviceOrder) do
                    local grp       = deviceGroups[tkey]
                    local claimants = grp.claimants
                    local function dispatch()
                        for _, cl in ipairs(claimants) do
                            local match = (#cl.mods == 0)
                            if not match then
                                match = true
                                for _, m in ipairs(cl.mods) do
                                    if not ms.keystate(m) then match = false
                                    break end
                                end
                            end
                            if match then cl.firedFn()
                            return end
                        end
                    end
                    if grp.ctype == "mouse" then
                        ms.mouse(grp.button, false, dispatch)
                    elseif grp.ctype == "scroll" then
                        ms.bindHandles["_disp:" .. tkey] = ms.scrollBind(grp.direction, dispatch)
                    elseif grp.ctype == "gamepad" then
                        ms.bindHandles["_disp:" .. tkey] = ms.gamepadBind(grp.button, dispatch)
                    end
                end

                if ms.trackpadMode then
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:start()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:start() end
                else
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:stop()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:stop() end
                end
                ms.bind.rebindSystem()
            end

            ms.suppressMacro = function(id)
                if type(id) ~= "string" or id == "" then return false end
                local def = ms.registry._defs and ms.registry._defs[id]
                if not def or def.system then return false end
                ms._suppressedMacros = ms._suppressedMacros or {}
                ms._suppressedMacros[id] = true
                ms.binds[id] = false
                if ms.bind and ms.bind.rebind then pcall(ms.bind.rebind) end
                if ms.saveSettings then pcall(ms.saveSettings) end
                return true
            end

            ms.bind.rebindSystem = function()
                if ms._systemBindHandles then
                    for _, h in pairs(ms._systemBindHandles) do
                        if h and h.delete then h:delete() end
                    end
                end
                ms._systemBindHandles = {}

                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or not def.system then goto sysContinue end
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto sysContinue end
                    local c = ms.effectiveBind(id)
                    if not c then goto sysContinue end
                    local fn = ms.bind._wires[id]
                    if not fn then goto sysContinue end
                    print("rebindSystem: registering " .. id .. " as system bind")
                    if c.type == "key" then
                        local tap = ms._makeKeyWatcher(c.mods, c.key, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                        if tap then ms._systemBindHandles[id] = tap
                        tap:start() end
                    elseif c.type == "mouse" then
                        ms._systemBindHandles[id] = ms.mouse(c.button, false, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms._systemBindHandles[id] = ms.scrollBind(c.direction, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms._systemBindHandles[id] = ms.gamepadBind(c.button, function()
                            if not ms._targetActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    end
                    ::sysContinue::
                end
                ms.systemBinds.rebind()
            end

            ms.bind.siblingConflict = function(id, c)
                local def = ms.registry._defs[id]
                if not def or def.default or not c then return nil end
                local function key(cfg)
                    if not cfg then return nil end
                    if cfg.type == "mouse" then return "mouse:" .. tostring(cfg.button) end
                    if cfg.type == "scroll" then return "scroll:" .. (cfg.direction or "up") end
                    if cfg.type == "gamepad" then return "gamepad:" .. (cfg.button or "?") end
                    local mods = {}
                    for _, m in ipairs(cfg.mods or {}) do table.insert(mods, m) end
                    table.sort(mods)
                    if cfg.type == "combo" then
                        local ks = {}
                        for _, k in ipairs(cfg.keys or {}) do ks[#ks+1] = k end
                        table.sort(ks)
                        return "combo:" .. table.concat(mods, ",") .. ":" .. table.concat(ks, "+")
                    end
                    if cfg.type == "mods" then return "mods:" .. table.concat(mods, ",") end
                    return "key:" .. table.concat(mods, ",") .. ":" .. (cfg.key or "")
                end
                local ck = key(c)
                if not ck then return nil end
                for _, sibId in ipairs(ms.registry._defList) do
                    if sibId ~= id then
                        local sibDef = ms.registry._defs[sibId]
                        if sibDef and not sibDef.default then
                            local sibEnabled = ms.binds[sibId]
                            if sibEnabled == nil then sibEnabled = sibDef.enabled end
                            if sibEnabled and key(ms.effectiveBind(sibId)) == ck then
                                return sibId
                            end
                        end
                    end
                end
                return nil
            end

            local _tpModMap = {
                shift=56,
                ctrl=59,
                alt=58,
                cmd=55,
            }

            if not ms._trackpadLeftListener then
                local leftPhysicallyHeld = false
                local leftActive = false
                ms._trackpadLeftListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local leftHoldCode = _tpModMap[ms.trackpadHoldKeys.left] or hs.keycodes.map[ms.trackpadHoldKeys.left]
                    if not leftHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= leftHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    leftPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not leftActive then
                        leftActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Left, Mouse, 0, 0)
                            while leftPhysicallyHeld and BindValidity == 1 and ms._targetActive do ms.wait(1) end
                            ms.Mouse(Release, Left, Mouse, 0, 0)
                            ms.wait(50)
                            leftActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end

            if not ms._trackpadRightListener then
                local rightPhysicallyHeld = false
                local rightActive = false
                ms._trackpadRightListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local rightHoldCode = _tpModMap[ms.trackpadHoldKeys.right] or hs.keycodes.map[ms.trackpadHoldKeys.right]
                    if not rightHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= rightHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    rightPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not rightActive then
                        rightActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Right, Mouse, 0, 0)
                            while rightPhysicallyHeld and BindValidity == 1 and ms._targetActive do ms.wait(1) end
                            ms.Mouse(Release, Right, Mouse, 0, 0)
                            ms.wait(50)
                            rightActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end
        -- END 9. Bind System & Settings Panel --

        -- 10. Event Bus (ms.bus) --
        -- END 10. Event Bus (ms.bus) --

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

        -- 13a. Macro Lab Shell ↔ Compiler bridge --
            do
                local function _macroShellEval(js)
                    if ms.shell and ms.shell.eval then
                        ms.shell.eval(js)
                    end
                end

                if ms.bus then
                    ms.bus.on("ui:macros:listMacros", function(body)
                        local ids = ms.compiler.list()
                        local json = hs.json.encode(ids)
                        _macroShellEval("if(window.macroLab)macroLab.setMacroList(" .. json .. ")")
                    end)

                    ms.bus.on("ui:macros:listBinds", function()
                        if ms.ui and ms.ui.pushBindList then
                            pcall(ms.ui.pushBindList)
                        end
                    end)

                    ms.bus.on("ui:macros:getMacro", function(_, body)
                        if not body or not body.id then return end
                        local def = ms.compiler.get(body.id)
                        if def then
                            local json = hs.json.encode(def)
                            _macroShellEval("if(window.macroLab)macroLab.setMacroDef(" .. json .. ")")
                        end
                    end)

                    local function _registerAndNotify()
                        pcall(ms.compiler.load)
                        if ms.bind and ms.bind.rebind then pcall(ms.bind.rebind) end
                        _macroShellEval("if(window.shellReceive)shellReceive('macros','macroSaved',{})")
                        if ms.ui and ms.ui.pushBindList then pcall(ms.ui.pushBindList) end
                    end

                    ms.bus.on("ui:macros:saveMacro", function(_, body)
                        if not body or not body.id or not body.def then
                            return
                        end
                        local ok, err = pcall(ms.compiler.write, body.id, body.def)
                        if ok then
                            -- write() preserves the JSON store even when a macro
                            -- fails to compile — rebuild quarantines the broken
                            -- one rather than dropping it. Surface that compile
                            -- error to the builder so the save isn't silently
                            -- "successful" while the macro can't actually run.
                            local compileErr = ms.compiler._errors
                                and ms.compiler._errors[body.id]
                            _registerAndNotify()
                            if compileErr then
                                print("ms.compiler.saveMacro: '" .. tostring(body.id)
                                    .. "' saved but failed to compile: " .. tostring(compileErr))
                                local payload = hs.json.encode({
                                    id  = body.id,
                                    err = tostring(compileErr),
                                })
                                _macroShellEval("if(window.shellReceive)shellReceive('macros','saveError',"
                                    .. payload .. ")")
                            else
                                print("ms.compiler.saveMacro: '" .. tostring(body.id) .. "' saved and registered")
                            end
                        else
                            print("ms.compiler.saveMacro error: " .. tostring(err))
                            local payload = hs.json.encode({
                                id  = body.id,
                                err = tostring(err),
                            })
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','saveError',"
                                .. payload .. ")")
                        end
                    end)

                    ms.bus.on("ui:macros:deleteMacro", function(_, body)
                        if not body or not body.id then return end
                        local id = body.id

                        local isVisual = false
                        if ms.compiler and ms.compiler.list then
                            local okL, ids = pcall(ms.compiler.list)
                            if okL and type(ids) == "table" then
                                for _, vid in ipairs(ids) do
                                    if vid == id then isVisual = true
                                    break end
                                end
                            end
                        end

                        if isVisual then
                            local ok, err = pcall(ms.compiler.delete, id)
                            if ok then
                                print("ms.compiler.deleteMacro: '" .. tostring(id) .. "' removed")
                                _registerAndNotify()
                            else
                                print("ms.compiler.deleteMacro error: " .. tostring(err))
                            end
                        elseif ms.suppressMacro and ms.suppressMacro(id) then
                            print("deleteMacro: suppressed handwritten macro '" .. tostring(id) .. "'")
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','macroSaved',{})")
                            if ms.ui and ms.ui.pushBindList then pcall(ms.ui.pushBindList) end
                        else
                            print("deleteMacro: '" .. tostring(id) .. "' is neither a visual macro nor a suppressible bind")
                        end
                    end)

                    ms.bus.on("ui:macros:getMeta", function()
                        local ok, meta = pcall(ms.compiler.getMeta)
                        local json = hs.json.encode(ok and meta or {})
                        _macroShellEval("if(window.macroLab)macroLab.setMeta(" .. json .. ")")
                    end)

                    ms.bus.on("ui:macros:setMeta", function(_, body)
                        if type(body) ~= "table" then return end
                        local ok, err = pcall(ms.compiler.setMeta, {
                            name    = body.name,
                            version = body.version,
                            author  = body.author,
                            website = body.website,
                        })
                        if ok then
                            print("ms.compiler.setMeta: pack meta updated")
                            _registerAndNotify()
                        else
                            print("ms.compiler.setMeta error: " .. tostring(err))
                        end
                    end)

                    ms.bus.on("ui:macros:testRun", function(_, body)
                        local reported = false
                        local function report(ok, err)
                            if reported then return end
                            reported = true
                            local res = hs.json.encode({
                                ok = ok and true or false,
                                err = err or "",
                            })
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','testRunResult'," .. res .. ")")
                        end
                        if not body then report(false, "no macro definition")
                        return end
                        local callOk, cerr = pcall(ms.compiler.testRun, body, report)
                        if not callOk then report(false, tostring(cerr)) end
                    end)

                    do
                        local rec = {
                            tap = nil, winFilter = nil, lastTs = nil,
                            threshold = 50, opts = {}, drag = nil, winFrames = {},
                            move = nil, _inFlush = false, _resample = nil,
                            _moveFlushTimer = nil,
                        }
                        ms._macroRecord = rec

                        local function pushStep(action, params)
                            local json = hs.json.encode({
                                action = action,
                                params = params,
                            })
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','recordStep'," .. json .. ")")
                        end

                        local flushMoves

                        local function maybeWait()
                            if not rec._inFlush then flushMoves() end
                            local now = hs.timer.secondsSinceEpoch()
                            if rec.opts.recordDelays ~= false and rec.lastTs then
                                local dt = math.floor((now - rec.lastTs) * 1000 + 0.5)
                                if dt >= rec.threshold then
                                    pushStep("ms.wait", { ms = dt })
                                end
                            end
                            rec.lastTs = now
                        end

                        local function inShell(pt)
                            if not pt then return false end
                            local ok, frame = pcall(function()
                                if ms.shell and ms.shell.webview and ms.shell.webview() then
                                    return ms.shell.webview():frame()
                                end
                            end)
                            if ok and frame then
                                return pt.x >= frame.x and pt.x <= frame.x + frame.w
                                    and pt.y >= frame.y and pt.y <= frame.y + frame.h
                            end
                            return false
                        end

                        local function modsOf(ev)
                            local f = ev:getFlags()
                            local mods = {}
                            if f.cmd   then mods[#mods + 1] = "cmd"   end
                            if f.alt   then mods[#mods + 1] = "alt"   end
                            if f.ctrl  then mods[#mods + 1] = "ctrl"  end
                            if f.shift then mods[#mods + 1] = "shift" end
                            return mods
                        end

                        local function buttonOf(t, et)
                            if t == et.rightMouseDown or t == et.rightMouseUp
                                or t == et.rightMouseDragged then return "Right" end
                            if t == et.otherMouseDown or t == et.otherMouseUp
                                or t == et.otherMouseDragged then return "Center" end
                            return "Left"
                        end

                        local function emitClick(button, pt)
                            pushStep("ms.Mouse", {
                                operation = "Click", button = button, reference = "Absolute",
                                x = math.floor((pt and pt.x or 0) + 0.5),
                                y = math.floor((pt and pt.y or 0) + 0.5),
                            })
                        end

                        -- Emit any buffered free-cursor movement as a run of
                        -- moveMouse steps, resampled by moveGranularity.
                        flushMoves = function()
                            if rec._moveFlushTimer then
                                rec._moveFlushTimer:stop()
                                rec._moveFlushTimer = nil
                            end
                            local m = rec.move
                            rec.move = nil
                            if not m or not m.points or #m.points < 2 then return end
                            local resample = rec._resample
                            local path = resample
                                and resample(m.points, rec.opts.moveGranularity) or m.points
                            if not path or #path < 2 then return end
                            rec._inFlush = true
                            maybeWait()
                            for i = 2, #path do
                                pushStep("ms.moveMouse", {
                                    x = math.floor(path[i][1] + 0.5),
                                    y = math.floor(path[i][2] + 0.5),
                                    ref = "Absolute",
                                    durationMs = 8,
                                })
                            end
                            rec._inFlush = false
                        end

                        rec.start = function(threshold, opts)
                            if rec.tap then return end
                            rec.threshold = tonumber(threshold) or 50
                            rec.opts = opts or {}
                            rec.lastTs = nil
                            rec.drag = nil
                            rec.move = nil
                            rec._inFlush = false
                            if rec._moveFlushTimer then
                                rec._moveFlushTimer:stop()
                                rec._moveFlushTimer = nil
                            end
                            local et = hs.eventtap.event.types

                            local mode  = rec.opts.pressMode or "type"
                            local types = { et.keyDown }
                            if mode == "pressRelease" then
                                types[#types + 1] = et.keyUp
                            end
                            if rec.opts.recordMouseButtons ~= false or rec.opts.recordDrags then
                                types[#types + 1] = et.leftMouseDown
                                types[#types + 1] = et.rightMouseDown
                                types[#types + 1] = et.otherMouseDown
                            end
                            if rec.opts.recordDrags then
                                types[#types + 1] = et.leftMouseUp
                                types[#types + 1] = et.rightMouseUp
                                types[#types + 1] = et.otherMouseUp
                                types[#types + 1] = et.leftMouseDragged
                                types[#types + 1] = et.rightMouseDragged
                                types[#types + 1] = et.otherMouseDragged
                            end
                            if rec.opts.recordMouseMoves then
                                types[#types + 1] = et.mouseMoved
                            end

                            local function resampleDrag(pts, granularity)
                                local n = #pts
                                if n <= 2 then return pts end
                                local g = tonumber(granularity) or 5
                                if g < 1 then g = 1 elseif g > 10 then g = 10 end
                                local epsilon = 40 / g

                                local keep = {}
                                keep[1] = true
                                keep[n] = true
                                local stack = { {
                                    1,
                                    n,
                                } }
                                while #stack > 0 do
                                    local seg = table.remove(stack)
                                    local first, last = seg[1], seg[2]
                                    local ax, ay = pts[first][1], pts[first][2]
                                    local bx, by = pts[last][1], pts[last][2]
                                    local dx, dy = bx - ax, by - ay
                                    local len2 = dx * dx + dy * dy
                                    local maxD, idx = -1, nil
                                    for i = first + 1, last - 1 do
                                        local px, py = pts[i][1], pts[i][2]
                                        local dist
                                        if len2 == 0 then
                                            local ex, ey = px - ax, py - ay
                                            dist = math.sqrt(ex * ex + ey * ey)
                                        else
                                            local t = ((px - ax) * dx + (py - ay) * dy) / len2
                                            if t < 0 then t = 0 elseif t > 1 then t = 1 end
                                            local cx, cy = ax + t * dx, ay + t * dy
                                            local ex, ey = px - cx, py - cy
                                            dist = math.sqrt(ex * ex + ey * ey)
                                        end
                                        if dist > maxD then maxD, idx = dist, i end
                                    end
                                    if idx and maxD > epsilon then
                                        keep[idx] = true
                                        stack[#stack + 1] = {
                                            first,
                                            idx,
                                        }
                                        stack[#stack + 1] = {
                                            idx,
                                            last,
                                        }
                                    end
                                end

                                local out = {}
                                for i = 1, n do if keep[i] then out[#out + 1] = pts[i] end end

                                local CAP = 200
                                if #out > CAP then
                                    local trimmed, stepN, acc = {}, #out / CAP, 1
                                    for i = 1, CAP do
                                        trimmed[i] = out[math.floor(acc + 0.5)] or out[#out]
                                        acc = acc + stepN
                                    end
                                    trimmed[1] = out[1]
                                    trimmed[CAP] = out[#out]
                                    out = trimmed
                                end
                                return out
                            end

                            rec._resample = resampleDrag

                            rec.tap = hs.eventtap.new(types, function(ev)
                                local ok = pcall(function()
                                    local t = ev:getType()

                                    if t == et.keyDown then
                                        local key = hs.keycodes.map[ev:getKeyCode()]
                                        if type(key) ~= "string" or key == "" then return end
                                        local mods = modsOf(ev)
                                        maybeWait()
                                        if mode == "press" or mode == "pressRelease" then
                                            pushStep("ms.press", {
                                                key = key,
                                                mods = mods,
                                            })
                                        else
                                            pushStep("ms.type", {
                                                key = key,
                                                mods = mods,
                                            })
                                        end
                                        return
                                    end
                                    if t == et.keyUp then
                                        local key = hs.keycodes.map[ev:getKeyCode()]
                                        if type(key) ~= "string" or key == "" then return end
                                        maybeWait()
                                        pushStep("ms.release", { key = key })
                                        return
                                    end

                                    if t == et.mouseMoved then
                                        if rec.drag then return end
                                        local pt = ev:location()
                                        if inShell(pt) then return end
                                        if not rec.move then rec.move = { points = {} } end
                                        local pts = rec.move.points
                                        if #pts < 4000 then
                                            pts[#pts + 1] = {
                                                pt.x,
                                                pt.y,
                                            }
                                        end
                                        -- Commit a movement run once the cursor
                                        -- goes idle, so pure movement streams into
                                        -- steps instead of waiting for a button.
                                        if rec._moveFlushTimer then
                                            rec._moveFlushTimer:stop()
                                        end
                                        rec._moveFlushTimer = hs.timer.doAfter(0.15, function()
                                            rec._moveFlushTimer = nil
                                            pcall(flushMoves)
                                        end)
                                        return
                                    end

                                    if t == et.leftMouseDown or t == et.rightMouseDown
                                        or t == et.otherMouseDown then
                                        local pt = ev:location()
                                        if inShell(pt) then return end
                                        local button = buttonOf(t, et)
                                        if rec.opts.recordDrags then
                                            -- Commit any free movement leading up
                                            -- to the press so the drag doesn't
                                            -- absorb or reorder it.
                                            flushMoves()
                                            rec.drag = {
                                                button = button, moved = false,
                                                x1 = pt.x, y1 = pt.y, x2 = pt.x, y2 = pt.y,
                                                points = { {
                                                    pt.x,
                                                    pt.y,
                                                } },
                                            }
                                        elseif rec.opts.recordMouseButtons ~= false then
                                            maybeWait()
                                            emitClick(button, pt)
                                        end
                                        return
                                    end

                                    if t == et.leftMouseDragged or t == et.rightMouseDragged
                                        or t == et.otherMouseDragged then
                                        if rec.drag then
                                            local pt = ev:location()
                                            rec.drag.moved = true
                                            rec.drag.x2, rec.drag.y2 = pt.x, pt.y
                                            local pts = rec.drag.points
                                            if pts and #pts < 4000 then
                                                pts[#pts + 1] = {
                                                    pt.x,
                                                    pt.y,
                                                }
                                            end
                                        end
                                        return
                                    end
                                    if t == et.leftMouseUp or t == et.rightMouseUp
                                        or t == et.otherMouseUp then
                                        local d = rec.drag
                                        rec.drag = nil
                                        if not d then return end
                                        local pt = ev:location()
                                        d.x2, d.y2 = pt.x, pt.y
                                        if d.moved then
                                            maybeWait()
                                            if d.points then d.points[#d.points + 1] = {
                                                d.x2,
                                                d.y2,
                                            } end
                                            local path = d.points
                                                and resampleDrag(d.points, rec.opts.dragGranularity)
                                                or nil
                                            if path and #path >= 3 then
                                                local parts = {}
                                                for _, p in ipairs(path) do
                                                    parts[#parts + 1] = math.floor(p[1] + 0.5)
                                                        .. "," .. math.floor(p[2] + 0.5)
                                                end
                                                pushStep("ms.dragPath", {
                                                    points  = table.concat(parts, ";"),
                                                    button  = d.button,
                                                    ref     = "Absolute",
                                                    delayMs = 10,
                                                })
                                            else
                                                pushStep("ms.Mouse", {
                                                    operation = "Drag", button = d.button,
                                                    reference = "Absolute",
                                                    x  = math.floor(d.x1 + 0.5), y  = math.floor(d.y1 + 0.5),
                                                    x2 = math.floor(d.x2 + 0.5), y2 = math.floor(d.y2 + 0.5),
                                                })
                                            end
                                        elseif rec.opts.recordMouseButtons ~= false
                                            and not inShell({
                                                x = d.x1,
                                                y = d.y1,
                                            }) then
                                            maybeWait()
                                            emitClick(d.button, {
                                                x = d.x1,
                                                y = d.y1,
                                            })
                                        end
                                        return
                                    end
                                end)
                                if not ok then print("ms.macroRecord: capture error") end
                                return false
                            end)

                            if rec.tap then rec.tap:start() end

                            if rec.opts.recordWindowMove or rec.opts.recordWindowResize then
                                rec.winFrames = {}
                                local wf = hs.window.filter.new(nil)
                                rec.winFilter = wf
                                local function onWinChange(win)
                                    local okw = pcall(function()
                                        if not win then return end
                                        local app = win:application()
                                        if app and app:name() == "Hammerspoon" then return end
                                        local id = win:id()
                                        local f  = win:frame()
                                        local prev = rec.winFrames[id]
                                        rec.winFrames[id] = {
                                            x = f.x,
                                            y = f.y,
                                            w = f.w,
                                            h = f.h,
                                        }
                                        if not prev then return end
                                        local moved   = (f.x ~= prev.x) or (f.y ~= prev.y)
                                        local resized = (f.w ~= prev.w) or (f.h ~= prev.h)
                                        if resized and rec.opts.recordWindowResize then
                                            maybeWait()
                                            pushStep("ms.window", {
                                                operation = "Resize",
                                                x = math.floor(f.w + 0.5), y = math.floor(f.h + 0.5),
                                            })
                                        elseif moved and rec.opts.recordWindowMove then
                                            maybeWait()
                                            pushStep("ms.window", {
                                                operation = "Move",
                                                x = math.floor(f.x + 0.5), y = math.floor(f.y + 0.5),
                                            })
                                        end
                                    end)
                                    if not okw then print("ms.macroRecord: window capture error") end
                                end
                                pcall(function()
                                    for _, w in ipairs(wf:getWindows()) do
                                        if w and w.id and w:id() then
                                            local f = w:frame()
                                            rec.winFrames[w:id()] = {
                                                x = f.x,
                                                y = f.y,
                                                w = f.w,
                                                h = f.h,
                                            }
                                        end
                                    end
                                end)
                                local wEvents = { hs.window.filter.windowMoved }
                                if hs.window.filter.windowsChanged then
                                    wEvents[#wEvents + 1] = hs.window.filter.windowsChanged
                                end
                                wf:subscribe(wEvents, onWinChange)
                            end

                            print("ms.macroRecord: started (threshold "
                                .. rec.threshold .. "ms, mode " .. mode .. ")")
                        end

                        rec.stop = function()
                            if rec._moveFlushTimer then
                                rec._moveFlushTimer:stop()
                                rec._moveFlushTimer = nil
                            end
                            flushMoves()
                            if rec.tap then rec.tap:stop()
                            rec.tap = nil end
                            if rec.winFilter then
                                pcall(function() rec.winFilter:unsubscribeAll() end)
                                rec.winFilter = nil
                            end
                            rec.drag = nil
                            rec.move = nil
                            rec._inFlush = false
                            rec.lastTs = nil
                            rec.winFrames = {}
                            print("ms.macroRecord: stopped")
                        end

                        ms.bus.on("ui:macros:startRecording", function(_, body)
                            rec.start(body and body.waitThreshold, body and body.options)
                        end)
                        ms.bus.on("ui:macros:stopRecording", function()
                            rec.stop()
                        end)
                    end

                    local _TOOL_TYPES = {
                        toggle = true,
                        slider = true,
                        seg = true,
                    }
                    ms.bus.on("ui:macros:listTools", function()
                        local tools = {}
                        for _, def in ipairs(ms._userSettingDefs or {}) do
                            if type(def) == "table" and def.key
                                and _TOOL_TYPES[def.type] then
                                tools[#tools + 1] = {
                                    key     = def.key,
                                    label   = def.label or def.key,
                                    type    = def.type,
                                    hint    = def.hint,
                                    min     = def.min,
                                    max     = def.max,
                                    step    = def.step,
                                    unit    = def.unit,
                                    options = def.options,
                                    default = def.default,
                                    value   = ms.settings.get(def.key),
                                    section = def.section,
                                    source  = def.authored and "builder" or "pack",
                                }
                            end
                        end
                        -- Helper vars are bindable too: a Value->Tool field can
                        -- read one live. They carry kind="var" so the editor
                        -- emits {__varRef} (ms.vars.get) rather than a setting.
                        if ms.vars and ms.vars.list then
                            local okV, vlist = pcall(ms.vars.list)
                            if okV and type(vlist) == "table" then
                                for _, v in ipairs(vlist) do
                                    tools[#tools + 1] = {
                                        key     = v.name,
                                        label   = v.label or v.name,
                                        type    = v.type or "string",
                                        default = v.default,
                                        value   = v.value,
                                        hint    = v.hint,
                                        kind    = "var",
                                        source  = "helpervar",
                                    }
                                end
                            end
                        end
                        local json = hs.json.encode(tools)
                        _macroShellEval("if(window.macroLab)macroLab.setToolList(" .. json .. ")")

                        -- Function tools go to a separate list, consumed by the
                        -- "Call function" block and the Tools panel Function tab.
                        -- Two sources: builder-authored function tools (editable)
                        -- and the current pack's bound macros (reference-only,
                        -- callable via ms.callFn by their bind id).
                        local fns = {}
                        local seenFn = {}
                        if ms.compiler and ms.compiler.listFunctions then
                            local okF, flist = pcall(ms.compiler.listFunctions)
                            if okF and type(flist) == "table" then
                                for _, f in ipairs(flist) do
                                    f.source = "builder"
                                    seenFn[f.id] = true
                                    fns[#fns + 1] = f
                                end
                            end
                        end
                        if ms.registry and ms.registry._defList then
                            for _, id in ipairs(ms.registry._defList) do
                                local d = ms.registry._defs[id]
                                if d and not d.system and not seenFn[id]
                                    and ms.bind and ms.bind._wires
                                    and ms.bind._wires[id] then
                                    fns[#fns + 1] = {
                                        id     = id,
                                        name   = d.label or id,
                                        group  = d.group,
                                        source = "pack",
                                    }
                                end
                            end
                        end
                        -- Tools registered via ms.tools.define with a run fn
                        -- (e.g. a plugin's "open folder/file" actions) are
                        -- callable, function-like items — surface them in the
                        -- Functions list so they show up and can be invoked from
                        -- a macro (ms.callFn resolves them, see ms_core callFn).
                        if ms._toolDefs then
                            for _, def in ipairs(ms._toolDefs) do
                                if type(def) == "table" and def.id
                                    and type(def.run) == "function"
                                    and not seenFn[def.id] then
                                    seenFn[def.id] = true
                                    fns[#fns + 1] = {
                                        id     = def.id,
                                        name   = def.name or def.id,
                                        source = def._origin or "plugin",
                                    }
                                end
                            end
                        end
                        local fjson = hs.json.encode(fns)
                        _macroShellEval("if(window.macroLab&&window.macroLab.setFunctionList)macroLab.setFunctionList(" .. fjson .. ")")
                    end)

                    -- Function tool authoring (reuses the macro step canvas).
                    ms.bus.on("ui:tools:saveFunction", function(_, body)
                        if type(body) ~= "table" or not body.id or not body.def then return end
                        local ok, err = pcall(ms.compiler.writeFunction, body.id, body.def)
                        if ok then
                            print("ms.compiler.saveFunction: '" .. tostring(body.id) .. "' saved")
                            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{})")
                        else
                            print("ms.compiler.saveFunction error: " .. tostring(err))
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{error:" .. hs.json.encode(tostring(err)) .. "})")
                        end
                    end)

                    ms.bus.on("ui:tools:getFunction", function(_, body)
                        if type(body) ~= "table" or not body.id then return end
                        local def = ms.compiler.getFunction(body.id)
                        if def then
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','functionDef',"
                                .. hs.json.encode(def) .. ")")
                        end
                    end)

                    ms.bus.on("ui:tools:deleteFunction", function(_, body)
                        if type(body) ~= "table" or not body.id then return end
                        local ok, err = pcall(ms.compiler.deleteFunction, body.id)
                        if ok then
                            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{})")
                        else
                            print("ms.compiler.deleteFunction error: " .. tostring(err))
                        end
                    end)

                    -- Helper var declaration (disk-persistent shared variables).
                    ms.bus.on("ui:tools:saveHelperVar", function(_, body)
                        if type(body) ~= "table" or not body.def then return end
                        local ok, err = ms.vars.define(body.def)
                        if ok then
                            print("ms.vars.define: '" .. tostring(body.def.name) .. "' saved")
                            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                            -- Rebuild + push UI state so S.userVariables (the source
                            -- the Variable list renders from) includes the new var;
                            -- without this the list re-renders from stale state.
                            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                            if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{})")
                        else
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{error:" .. hs.json.encode(tostring(err)) .. "})")
                        end
                    end)

                    ms.bus.on("ui:tools:deleteHelperVar", function(_, body)
                        if type(body) ~= "table" or not body.name then return end
                        local ok = ms.vars.remove(body.name)
                        if ok then
                            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                            if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                            _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{})")
                        end
                    end)
                end
            end
        -- END 13a. Macro Lab Shell ↔ Compiler bridge --

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
            do
                local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"

                local frozenMs = setmetatable({}, {
                    __index    = function(t, k)
                        if k == "integrity" or k == "dev" or k == "showGuardian" or k == "_systemActions"
                       or k == "bus" or k == "docs" or k == "shell" or k == "compiler"
                       or k == "registry" or k == "devtools" then
                            error("ms_macros.lua: ms." .. k .. " is not accessible from macros.", 2)
                        end
                        if k == "key" then
                            return function(mods, key, swallow, pressFn, releaseFn)
                                return ms.key(mods, key, swallow, pressFn, releaseFn, false)
                            end
                        elseif k == "mouse" then
                            return function(button, swallow, clickFn)
                                return ms.mouse(button, swallow, clickFn, false)
                            end
                        elseif k == "bind" then
                            return setmetatable({}, {
                                __index = function(_, bk)
                                    if bk == "define" then
                                        return function(id, a, b)
                                            local opts = type(a) == "table" and a or (type(b) == "table" and b or {})
                                            opts.system = false
                                            if type(id) == "string"
                                                and ms.registry and ms.registry._defs
                                                and ms.registry._defs[id] then
                                                print("ms.bind.define: skipping duplicate id '"
                                                    .. id .. "', already registered "
                                                    .. "(handwritten macros win over visual).")
                                                return
                                            end
                                            return ms.bind.define(id, a, b)
                                        end
                                    end
                                    return ms.bind[bk]
                                end,
                            })
                        elseif k == "fn" then
                            local origFn = ms.fn
                            return setmetatable({}, {
                                __call = function(_, fn, label)
                                    return origFn(fn, label)
                                end,
                                __index = function(_, bk)
                                    if bk == "define" then
                                        return function(id, fn, opts)
                                            opts = opts or {}
                                            opts.group = "user"
                                            return ms.fn.define(id, fn, opts)
                                        end
                                    end
                                    return ms.fn[bk]
                                end,
                            })
                        end
                        if k == "alert" then
                            return setmetatable({}, {
                                __call = function(_, msg, duration, noDefaultSound)
                                    return ms.alert(msg, duration, noDefaultSound, { source = "macro" })
                                end,
                                __index = function(_, bk)
                                    if bk == "dismissById" then
                                        return ms.alert[bk]
                                    end
                                    return nil
                                end,
                            })
                        end
                        return ms[k]
                    end,
                    __newindex = function(t, k, v)
                        if k == "macroMeta" then
                            if ms._macroMetaLocked then return end
                            rawset(ms, k, v)
                        else
                            error("ms_macros.lua: unauthorized write to ms." .. tostring(k)
                                .. ". Only ms.macroMeta and ms.bind.define are permitted.", 2)
                        end
                    end,
                })

                local BLOCKED = {
                    hs=true, require=true, os=true, io=true,
                    _G=true, load=true, loadfile=true, loadstring=true,
                    dofile=true, rawget=true, rawset=true,
                    debug=true, package=true, collectgarbage=true,
                    setfenv=true, getfenv=true,
                    setmetatable=true, getmetatable=true,
                    __ms_appWatcher=true,
                    _integrityPollTimer=true,
                    _initTimer=true,
                }

                local sandbox = {
                    ms        = frozenMs,
                    math      = math,
                    string    = string,
                    table     = table,
                    coroutine = coroutine,
                    ipairs    = ipairs,
                    pairs     = pairs,
                    next      = next,
                    select    = select,
                    pcall     = pcall,
                    xpcall    = xpcall,
                    tostring  = tostring,
                    tonumber  = tonumber,
                    type      = type,
                    unpack    = table.unpack or unpack,
                    error     = error,
                    assert    = assert,
                    print     = print,
                    sub       = ms.sub,
                    Move        = Move,        Click       = Click,       DoubleClick  = DoubleClick,
                    TripleClick = TripleClick, Drag        = Drag,        Press        = Press,
                    Release     = Release,
                    Left        = Left,        Right       = Right,       Center       = Center,
                    Button4     = Button4,     Button5     = Button5,
                    Unscaled     = Unscaled,
                    Absolute     = Absolute,   Mouse        = Mouse,
                    WindowTL     = WindowTL,   WindowTR     = WindowTR,
                    WindowBL     = WindowBL,   WindowBR     = WindowBR,   WindowCenter = WindowCenter,
                    ScreenTL     = ScreenTL,   ScreenTR     = ScreenTR,
                    ScreenBL     = ScreenBL,   ScreenBR     = ScreenBR,   ScreenCenter = ScreenCenter,
                }

                setmetatable(sandbox, {
                    __index = function(t, k)
                        if BLOCKED[k] then
                            error("ms_macros.lua: access to '" .. tostring(k)
                                .. "' is not permitted.", 2)
                        end
                        local v = rawget(_G, k)
                        local vt = type(v)
                        if vt == "string" or vt == "number" or vt == "boolean" or v == nil then
                            return v
                        end
                        error("ms_macros.lua: access to '" .. tostring(k)
                            .. "' is not permitted (non-primitive globals are not accessible from macros).", 2)
                    end,
                    __newindex = function(t, k, v)
                        error("ms_macros.lua: cannot write global '" .. tostring(k)
                            .. "', use 'local' for all variables.", 2)
                    end,
                })

                ms._macroSandbox = sandbox

                ms._wrapMacroFunctions = function(src)
                    local srcLines = {}
                    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                        srcLines[#srcLines + 1] = line
                    end

                    local out = {}
                    local i = 1
                    while i <= #srcLines do
                        local line = srcLines[i]
                        local indent, name, rest = line:match("^(%s*)local%s+(%w+)%s*=%s*(function%s*%(.*)$")
                        if name and rest then
                            out[#out + 1] = indent .. 'local ' .. name .. ' = sub("' .. name .. '", ' .. rest
                            local depth = 1
                            i = i + 1
                            while i <= #srcLines and depth > 0 do
                                local l = srcLines[i]
                                for kw in l:gmatch("(%w+)") do
                                    if kw == "function" or kw == "if" or kw == "for"
                                    or kw == "while" or kw == "repeat" then
                                        depth = depth + 1
                                    end
                                end
                                local stripped = l:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
                                for kw in stripped:gmatch("(%w+)") do
                                    if kw == "end" then
                                        depth = depth - 1
                                    end
                                end
                                if depth > 0 then
                                    out[#out + 1] = l
                                else
                                    local endIndent = l:match("^(%s*)") or ""
                                    out[#out + 1] = endIndent .. "end)"
                                end
                                i = i + 1
                            end
                        else
                            out[#out + 1] = line
                            i = i + 1
                        end
                    end
                    return table.concat(out, "\n")
                end

                local rawSrc
                do
                    local af = io.open(macrosPath, "r")
                    if not af then
                        -- A missing ms_macros.lua must not take down all of
                        -- Hammerspoon. It can be absent mid-move (an interrupted
                        -- profile switch or pack activate) or for a freshly
                        -- created empty profile. Seed a minimal valid stub and
                        -- carry on with an empty macro set instead of error()ing
                        -- out of boot; the user can re-activate a pack from the
                        -- Installed Library once the shell is up.
                        print("ms_macros.lua missing at boot; seeding an empty stub: " .. macrosPath)
                        rawSrc = "-- ms_macros.lua was missing at boot and has been reset.\n"
                            .. "-- Activate a macro pack from the Installed Library to restore your macros.\n"
                            .. "ms.macroMeta = { name = \"Recovered\", author = \"\" }\n"
                        local seed = io.open(macrosPath, "w")
                        if seed then seed:write(rawSrc); seed:close() end
                    else
                        rawSrc = af:read("*all")
                        af:close()
                    end
                    local auditErrs = ms.auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        local msg = "ms_macros.lua failed security audit ("
                            .. #auditErrs .. " violation"
                            .. (#auditErrs > 1 and "s" or "") .. "):\n"
                        for _, e in ipairs(auditErrs) do
                            msg = msg .. "  \xe2\x80\xa2 " .. e .. "\n"
                        end
                        error(msg, 0)
                    end
                end

                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    chunk, loadErr = load(rawSrc, "@ms_macros.lua", "bt", sandbox)
                else
                    chunk, loadErr = loadstring(rawSrc, "@ms_macros.lua")
                    if chunk then setfenv(chunk, sandbox) end
                end
                if not chunk then
                    error("ms_macros.lua: failed to load: " .. tostring(loadErr))
                end
                ms._defineOrigin = "pack"
                local ok, runErr = pcall(chunk)
                ms._defineOrigin = nil
                if not ok then
                    error("ms_macros.lua: error during execution: " .. tostring(runErr))
                end

                ms._macroMetaFromHand = ms.macroMeta ~= nil
                if not ms.macroMeta then
                    print("Warning: ms_macros.lua did not set ms.macroMeta.")
                    hs.timer.doAfter(0.5, function()
                        ms.alert("Warning: ms_macros.lua did not declare ms.macroMeta.", 6)
                    end)
                end
                ms.loading.pushMeta()
                if not next(ms.registry._defs) then
                    -- A bindless file is a legitimately empty profile (see
                    -- createNewProfile), not necessarily malformed — warn, don't
                    -- fault, matching the tolerant hotswap reload path.
                    print("Warning: ms_macros.lua declared no ms.bind.define calls (empty profile?).")
                    hs.timer.doAfter(0.5, function()
                        ms.alert("This profile has no macros yet. Add some in the Macros panel.", 5)
                    end)
                end
            end

            -- 14a. Visual Macros (builder-authored) --
                if ms.compiler and ms.compiler.paths
                    and hs.fs.attributes(ms.compiler.paths.json) then
                    local rebOk, rebErr = pcall(ms.compiler.rebuild)
                    if not rebOk then
                        print("ms.compiler.rebuild (boot): " .. tostring(rebErr))
                    end
                    local ldOk, ldErr = pcall(ms.compiler.load)
                    if not ldOk then
                        print("ms.compiler.load (boot): " .. tostring(ldErr))
                    end
                end
            -- END 14a. Visual Macros --

            -- 14b. Macro Pack Library Migration --
                -- Surface the live pack and every saved profile's pack in the
                -- Installed Macro Packs library (one-time, non-destructive). Runs
                -- here because ms.package (13c) and ms.macroMeta (14/14a) are both
                -- ready. Never let a migration hiccup block boot.
                if ms.package and ms.package.migrateMacroPacks then
                    local migOk, migErr = pcall(ms.package.migrateMacroPacks)
                    if not migOk then
                        print("ms.package.migrateMacroPacks (boot): " .. tostring(migErr))
                    end
                end
                -- Backfill packs.json links for legacy profiles (idempotent).
                if ms.package and ms.package.migrateProfilePacks then
                    local mpOk, mpErr = pcall(ms.package.migrateProfilePacks)
                    if not mpOk then
                        print("ms.package.migrateProfilePacks (boot): " .. tostring(mpErr))
                    end
                end
                -- Keep each kind's active marker tracking whatever slice is live,
                -- by content fingerprint. switchProfile activates a profile's packs
                -- (copying their files live), so live == pack and reconcile re-flags
                -- them here on every boot. The fingerprint now canonicalizes JSON
                -- and ignores profile-owned macro binds, so macro packs reconcile as
                -- reliably as theme/sound. A live slice that matches no stored pack
                -- (a custom/edited mix) simply leaves that kind's badge clear.
                if ms.package and ms.package.reconcileActive then
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        local rcOk, rcErr = pcall(ms.package.reconcileActive, k)
                        if not rcOk then
                            print("ms.package.reconcileActive(" .. k .. ") (boot): " .. tostring(rcErr))
                        end
                    end
                end
            -- END 14b. Macro Pack Library Migration --

            ms.macroDefaults = {
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
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
        BindValidity = 0
        ms._startupSoundDone = false

        -- Loading Screen Announce & Boot Completion --
            -- The app version label shown on the loading screen. Extracted from the
            -- old t3 beat so the loading choreography can own the profile/creator/
            -- version reveal on a SINGLE clock (anchored to the brand-dock chain),
            -- instead of a second init-anchored timer that raced it -- on mudspoon the
            -- two clocks drift and the profile appeared before the brand finished
            -- docking. Reads MANIFEST.json; on the testing channel derives the -pre.N
            -- label from the patch bump + build number.
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
                        ms.alert("Macros loaded. Press \xe2\x8c\xa5 and P to open settings.", _TOAST_HOLD, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce3 = hs.timer.doAfter(_TOAST_LEAD + 3, function()
                        ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn \xe2\x80\x94 https://mudbourn.info", _TOAST_HOLD, true, { priority = "low" })
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
                            -- Combine the app-version check with a scan of every
                            -- installed package / plugin, then announce them all
                            -- in one alert. Content items report to Settings
                            -- \u{2192} Browse; the app to Help \u{2192} Check for Update.
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
                -- Hammerspoon is meant to run as ONE process. The watchdog /
                -- relaunch machinery (and a stray manual launch) can spin up a
                -- second instance that fights the first over the shared
                -- ~/.hammerspoon state. Two instances are two OS processes, so an
                -- in-process flag can't see across them -- announce over
                -- NSDistributedNotificationCenter instead. Every instance
                -- announces {pid, bootTime} on boot; whichever instance is OLDER
                -- evicts the newcomer with SIGKILL (so the duplicate never runs
                -- teardown against the shared files -- see the exit-curtain /
                -- init.lua-perms hazards), plays the error chime and tells the
                -- user. The newcomer does nothing itself; the incumbent evicts
                -- it. Runs synchronously here, before the deferred boot chain
                -- below, so a duplicate is killed long before it arms hotkeys.
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
                        -- Prefer the `object` string (always delivered across
                        -- processes); fall back to userInfo, whose cross-process
                        -- delivery is less reliable. Payload is "pid:bootTime".
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
                        -- Only the strictly-older instance evicts; a boot-time
                        -- tie (near-simultaneous launch) breaks on the lower pid.
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
                        -- "error" is a real event slot, so playSlot resolves it
                        -- like any other system sound: user assignment > active
                        -- pack (a_Error) > built-in default (d_Error).
                        pcall(function() ms.playSlot("error") end)
                        pcall(function()
                            ms.alert("Hammerspoon is already running. "
                                .. "Closed the duplicate instance.", 6, true)
                        end)
                    end, NOTE)
                    watcher:start()
                    _G.__ms_instanceWatcher = watcher
                    ms._instanceWatcher = watcher

                    -- Announce ourselves so any incumbent can evict us. Repost a
                    -- couple of times in case the incumbent's listener was not up
                    -- at the exact instant of the first post -- comparison is on
                    -- boot times, so a repost can never make the newcomer win.
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
            _G._timers.animGate = hs.timer.doAfter(2.9, function()
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
                end
                -- The themeLoaded chime overlaps the boot sound on mudspoon, where a
                -- single MCI wave device is shared; the device-busy (rc=320) retry now
                -- lives in the sound layer (mudspoon hs/sound.lua), so this can fire
                -- unconditionally -- the play self-heals once d_Boot frees the device.
                pcall(function() ms.playSlot("themeLoaded") end)
                -- Profile / creator / version reveal moved OUT of this init-anchored
                -- beat into the loading choreography chain (ms_loading _startBoot-
                -- Choreography), which is anchored to the same clock as the brand dock.
                -- Driving them here raced the brand-shift transition on mudspoon, so the
                -- profile text appeared before the logo finished docking.
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
            end)
        -- END Loading Screen Announce & Boot Completion --
    -- END Startup Executions --
-- END Core System --

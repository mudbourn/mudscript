return function(ms)
    -- State & Config --
        ms.vars = {}
        ms.keytrack = {}
        ms._keyBindings = {}
        ms._keyBindingsByCode = {}
        ms.bindConfig = {}
        ms.bindHandles = {}
        ms.bindIgnoreMods = ms.bindIgnoreMods or {}
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
        ms.windowsHost           = (package.config:sub(1, 1) == "\\")
        ms.windowsMode           = ms.windowsHost
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

        ms._targetApp         = nil
        ms._targetAppSetting  = nil
        ms._targetAppDeclared = nil
        ms._targetAppOffers   = {}
        ms._targetHandle      = nil
        ms._targetActive      = false
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

        local function _cleanAppName(name)
            if type(name) ~= "string" then return nil end
            name = name:match("^%s*(.-)%s*$")
            return name ~= "" and name or nil
        end

        ms._applyTargetApp = function()
            local name = ms._targetAppDeclared
            if not name then
                if ms._targetAppSetting == false then
                    name = nil
                else
                    name = ms._targetAppSetting or ms._targetAppOffers[1]
                end
            end
            ms._targetApp    = name
            ms._targetHandle = name and hs.application.get(name) or nil
            if ms._targetHandle then ms._targetActive = true end
            if ms._updateCamAnchor then pcall(ms._updateCamAnchor) end
        end

        ms.setTargetApp = function(name)
            ms._targetAppSetting = _cleanAppName(name) or false
            ms._applyTargetApp()
            if ms._loadComplete and ms.saveSettings then ms.saveSettings() end
        end

        ms._declareTargetApp = function(name)
            ms._targetAppDeclared = _cleanAppName(name)
            ms._applyTargetApp()
        end

        ms.offerTargetApp = function(name)
            name = _cleanAppName(name)
            if not name then return end
            for _, n in ipairs(ms._targetAppOffers) do
                if n == name then return end
            end
            table.insert(ms._targetAppOffers, name)
            ms._applyTargetApp()
        end

        ms.withdrawTargetApp = function(name)
            for i, n in ipairs(ms._targetAppOffers) do
                if n == name then
                    table.remove(ms._targetAppOffers, i)
                    ms._applyTargetApp()
                    return
                end
            end
        end

        ms._targetAppState = function()
            local seen = {}
            local options = {}
            local function add(n)
                if n and not seen[n] then
                    seen[n] = true
                    table.insert(options, n)
                end
            end
            add(ms._targetAppSetting or nil)
            for _, n in ipairs(ms._targetAppOffers) do add(n) end
            local running = {}
            for _, app in ipairs(hs.application.runningApplications()) do
                local ok, kind = pcall(function() return app:kind() end)
                local name = app:name()
                if ok and kind == 1 and name and name ~= "Hammerspoon" then
                    table.insert(running, name)
                end
            end
            table.sort(running)
            for _, n in ipairs(running) do add(n) end
            return {
                current  = ms._targetApp,
                setting  = ms._targetAppSetting or nil,
                declared = ms._targetAppDeclared,
                options  = options,
            }
        end
        notice = 0
        loadfinish = 0
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
        -- END User Settings & Menu API State --

        -- Window Radius Helper [ms.theme] --
            ms.theme = ms.theme or {}

            ms.theme.applyWindowRadius = function(panel)
                if not panel then return end
                local r = (ms._theme and (ms._theme.windowRadius or ms._theme.radius))
                    or (ms._themeDefaults and (ms._themeDefaults.windowRadius or ms._themeDefaults.radius))
                    or 0
                if ms._octaneMode then r = 0 end
                if r > 0 then
                    pcall(function() panel:transparent(true) end)
                    pcall(function() panel:shadow(false) end)
                end
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
    -- END State & Config --
end

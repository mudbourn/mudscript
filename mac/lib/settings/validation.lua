return function(ms, ctx)
    -- User Settings validation helpers --
        local settingsPath = ctx.settingsPath
        local jsonPath = ctx.jsonPath
        local defaultPath = ctx.defaultPath
        local archivePath = ctx.archivePath
        local macrosPath = ctx.macrosPath

        local _SETTING_TYPES = {
            toggle = true,
            slider    = true,
            seg       = true,
            action = true,
            divider   = true,
            groupLabel = true,
            soundSlot = true,
            group     = true,
        }
        local _HIDEABLE_FEATURES = {
            socd             = true,
            trackpad         = true,
            sensitivity      = true,
            gamepad          = true,
        }
        local function _validateUserValue(def, value)
            if def.type == "toggle" then
                if value == true or value == false then return value end
            elseif def.type == "slider" then
                local n = tonumber(value)
                if not n or n ~= n then return nil end
                local lo, hi = def.min or 0, def.max or 100
                local step = tonumber(def.step)
                if step and step > 0 then
                    n = lo + math.floor((n - lo) / step + 0.5) * step
                    n = tonumber(string.format("%.6g", n))
                end
                return math.max(lo, math.min(hi, n))
            elseif def.type == "seg" then
                if type(def.options) == "table" then
                    for _, opt in ipairs(def.options) do
                        if opt.value == value then return value end
                    end
                end
            end
            return nil
        end

        ms._stashUserSettings = function()
            ms._pendingUserSettings = ms._pendingUserSettings or {}
            for k, v in pairs(ms._userSettingVals or {}) do
                ms._pendingUserSettings[k] = v
            end
            ms._userSettingVals = {}
        end

        ms._adoptUserSetting = function(key, def)
            local saved = ms._pendingUserSettings and ms._pendingUserSettings[key]
            if saved ~= nil then
                local validated = _validateUserValue(def, saved)
                if validated ~= nil then
                    ms._pendingUserSettings[key] = nil
                    return validated
                end
            end
            return def.default
        end

        local function _userSnapshot()
            local out = {}
            for k, v in pairs(ms._pendingUserSettings or {}) do out[k] = v end
            for k, v in pairs(ms._userSettingVals or {}) do out[k] = v end
            return out
        end

        ms._applySettings = function(data)
            if not data then return end
            if data.sensitivity ~= nil then
                local num = tonumber(data.sensitivity)
                if num and num >= 0.1 and num <= 4 then
                    ms._pendingUserSettings = ms._pendingUserSettings or {}
                    ms._pendingUserSettings["cameraSensitivity"] = num
                end
            end
            if data.frameLevel ~= nil then
                data.user = data.user or {}
                if data.user.clickLevel == nil then
                    local num = tonumber(data.frameLevel)
                    if num and num >= 1 and num <= 4 then
                        data.user.clickLevel = num
                    end
                end
            end
            if data.trackpadMode     ~= nil then ms.trackpadMode           = (data.trackpadMode     == true) end
            if data.gamepadEnabled   ~= nil then ms.gamepadEnabled         = (data.gamepadEnabled   == true) end
            if data.socdEnabled      ~= nil then ms.socdEnabled            = (data.socdEnabled      == true) end
            if data.windowsMode      ~= nil then ms.windowsMode            = (data.windowsMode      == true) end

            if data.socdMode then
                if data.socdMode == "lastWins" or data.socdMode == "neutral" or data.socdMode == "firstWins" then
                    ms.socdMode = data.socdMode
                end
            end
            if data.trackpadHoldKeys and ms.trackpadHoldKeys then
                if data.trackpadHoldKeys.left  then ms.trackpadHoldKeys.left  = data.trackpadHoldKeys.left  end
                if data.trackpadHoldKeys.right then ms.trackpadHoldKeys.right = data.trackpadHoldKeys.right end
            end
            if data.soundEnabled ~= nil then ms.soundEnabled = (data.soundEnabled == true) end
            if data.bundleSoundsWithTheme ~= nil then
                ms.bundleSoundsWithTheme = (data.bundleSoundsWithTheme == true)
            end
            if data.soundVolume  ~= nil then
                local v = tonumber(data.soundVolume)
                if v and v >= 0 and v <= 100 then ms.soundVolume = math.floor(v) end
            end
            if data.soundAssign and type(data.soundAssign) == "table" then
                local _sa = {}
                for k, v in pairs(data.soundAssign) do
                    if type(k) == "string" and type(v) == "string"
                        and not v:find("[/\\]") and not v:find("%.%.")
                    then
                        _sa[k] = v
                    end
                end
                ms.soundAssign = _sa
            end
            if data.importedSounds and type(data.importedSounds) == "table" then
                local _is = {}
                for k, v in pairs(data.importedSounds) do
                    if type(k) == "string" and type(v) == "string"
                        and not v:find("[/\\]") and not v:find("%.%.")
                    then
                        _is[k] = v
                    end
                end
                ms.importedSounds = _is
            end
            if data.consoleDangerAck ~= nil then ms._consoleDangerAck = (data.consoleDangerAck == true) end
            if data.editMacrosAck ~= nil then ms._editMacrosAck = (data.editMacrosAck == true) end
            if data.quickReloaded ~= nil then ms._quickReloaded = tonumber(data.quickReloaded) or 0 end
            if data.qrOptions and type(data.qrOptions) == "table" then
                local qr = ms._qrOptions
                if data.qrOptions.macros   ~= nil then qr.macros   = (data.qrOptions.macros   == true) end
                if data.qrOptions.theme    ~= nil then qr.theme    = (data.qrOptions.theme    == true) end
                if data.qrOptions.settings ~= nil then qr.settings = (data.qrOptions.settings == true) end
                if data.qrOptions.ui       ~= nil then qr.ui       = (data.qrOptions.ui       == true) end
            end
            if data.pluginsDisabled and type(data.pluginsDisabled) == "table" then
                local off = {}
                for k, v in pairs(data.pluginsDisabled) do
                    if v == true and type(k) == "string"
                        and k:match("^[%w%-%._ ]+%.spoon$")
                        and not k:find("%.%.") and not k:find("^%.")
                    then
                        off[k] = true
                    end
                end
                ms._pluginsDisabled = off
            end
            if data.customThemeDisabled ~= nil then ms._customThemeDisabled = (data.customThemeDisabled == true) end
            if data.soundPreset ~= nil then ms._soundPreset = data.soundPreset end
            if data.devArchiveLimit ~= nil then
                local n = tonumber(data.devArchiveLimit)
                if n and n >= 0 and n <= 50 then ms._devArchiveLimit = math.floor(n) end
            end
            if data.updateChannel == "testing" or data.updateChannel == "stable" then
                ms._updateChannel = data.updateChannel
            end
            if data.uiZoom ~= nil then
                local z = tonumber(data.uiZoom)
                if z then ms._uiZoom = math.max(0.5, math.min(2.0, z)) end
            end
            if data.octaneMode ~= nil then ms._octaneMode = (data.octaneMode == true) end
            if data.octaneMuteSounds ~= nil then ms._octaneMuteSounds = (data.octaneMuteSounds == true) end
            if data.uiTransparencyOff ~= nil then ms._uiTransparencyOff = (data.uiTransparencyOff == true) end
            if data.swallowHotkeys ~= nil then ms._swallowHotkeys = (data.swallowHotkeys == true) end
            if data.updateAlertsDisabled ~= nil then ms._updateAlertsDisabled = (data.updateAlertsDisabled == true) end
            if data.antiTimeoutEnabled ~= nil then
                ms._pendingUserSettings = ms._pendingUserSettings or {}
                ms._pendingUserSettings["antiTimeoutEnabled"] = (data.antiTimeoutEnabled == true)
            end
            if data.macroLabEnabled ~= nil then ms._macroLabEnabled = (data.macroLabEnabled == true) end
            if type(data.targetApp) == "string" and data.targetApp ~= "" then
                ms._targetAppSetting = data.targetApp
            elseif data.targetApp == false then
                ms._targetAppSetting = false
            end
            if ms._applyTargetApp then ms._applyTargetApp() end
            if data.testingSource == "release" or data.testingSource == "artifact" then
                ms._testingSource = data.testingSource
            end
            if data.macros then
                ms._suppressedMacros = ms._suppressedMacros or {}
                for id, entry in pairs(data.macros) do
                    if entry.suppressed then
                        ms._suppressedMacros[id] = true
                    end
                    if entry.enabled ~= nil then
                        ms.binds[id] = entry.enabled
                    end
                    -- Load a stored bind regardless of registry membership
                    if type(entry.bind) == "table" and entry.bind.type then
                        ms.bindConfig[id] = entry.bind
                    end
                    if entry.cooldown ~= nil then
                        local n = tonumber(entry.cooldown)
                        if n and n >= 0 then ms.cooldowns[id] = math.floor(n) end
                    end
                    if entry.ignoreMods then
                        ms.bindIgnoreMods[id] = true
                    end
                end
            end
            if data.systemBinds and type(data.systemBinds) == "table" then
                ms.systemBinds._config = {}
                for id, cfg in pairs(data.systemBinds) do
                    if cfg.type and (cfg.key or cfg.button) then
                        ms.systemBinds._config[id] = cfg
                    end
                end
            end
            if data.shell and type(data.shell) == "table" then
                ms._shellState = ms._shellState or {}
                local s = data.shell
                if s.x ~= nil then ms._shellState.x = tonumber(s.x) end
                if s.y ~= nil then ms._shellState.y = tonumber(s.y) end
                if s.w ~= nil then ms._shellState.w = tonumber(s.w) end
                if s.h ~= nil then ms._shellState.h = tonumber(s.h) end
                if s.lastPanel ~= nil then ms._shellState.lastPanel = tostring(s.lastPanel) end
                -- Force shell hidden on cold boot, preserve real state on hotswap
                if ms._quickReloading then
                    ms._shellState.visible =
                        (ms.shell and ms.shell.isVisible and ms.shell.isVisible()) or false
                else
                    ms._shellState.visible = false
                end
            end
            if data.user and type(data.user) == "table" then
                for key, value in pairs(data.user) do
                    local uDef = ms._userSettingIndex[key]
                    if uDef and uDef.type ~= "action" then
                        local validated = _validateUserValue(uDef, value)
                        if validated ~= nil then
                            ms._userSettingVals[key] = validated
                            if type(uDef.onChange) == "function" then
                                pcall(uDef.onChange, validated)
                            end
                        end
                    else
                        ms._pendingUserSettings = ms._pendingUserSettings or {}
                        ms._pendingUserSettings[key] = value
                    end
                end
            end
        end

        ms._convertFlatSettings = function(file)
            local data    = { macros = {} }
            local skipped = {}
            for line in file:lines() do
                local key, val = line:match("^(.-)=(.+)$")
                if not key then
                elseif key == "sensitivity" then
                    local num = tonumber(val)
                    if num and num >= 0.1 and num <= 4 then data.sensitivity = num end
                elseif key == "clickLevel" or key == "frameLevel" then
                    local num = tonumber(val)
                    if num and num >= 1 and num <= 4 then
                        data.user = data.user or {}
                        if not data.user.clickLevel then
                            data.user.clickLevel = num
                        end
                    end
                elseif key == "binds" then
                    local decoded = hs.json.decode(val)
                    if decoded then
                        for id, enabled in pairs(decoded) do
                            data.macros[id] = data.macros[id] or {}
                            data.macros[id].enabled = enabled
                        end
                    end
                elseif key == "trackpadMode"     then data.trackpadMode     = (val == "true")
                elseif key == "socdEnabled"      then data.socdEnabled      = (val == "true")
                elseif key == "windowsMode"      then data.windowsMode      = (val == "true")

                elseif key == "socdMode" then
                    if val == "lastWins" or val == "neutral" or val == "firstWins" then
                        data.socdMode = val
                    end
                elseif key == "trackpadHoldLeft" then
                    data.trackpadHoldKeys = data.trackpadHoldKeys or {}
                    data.trackpadHoldKeys.left = val
                elseif key == "trackpadHoldRight" then
                    data.trackpadHoldKeys = data.trackpadHoldKeys or {}
                    data.trackpadHoldKeys.right = val
                elseif key:sub(1, 5) == "bind_" then
                    local id = key:sub(6)
                    local parsed = ms.parseBind(val)
                    if parsed then
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].bind = parsed
                    end
                elseif key:sub(1, 4) == "mod_" then
                    local id = key:sub(5)
                    data.macros[id] = data.macros[id] or {}
                    data.macros[id].mod = (val == "") and nil or val
                elseif key:sub(1, 8) == "subbind_" then
                    local id = key:sub(9)
                    local parsed = ms.parseBind(val)
                    if parsed then
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].bind = parsed
                    end
                else
                    table.insert(skipped, key)
                end
            end
            return data, skipped
        end

        ms.saveSettings = function()
            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            local data = {
                trackpadMode     = ms.trackpadMode,
                gamepadEnabled   = ms.gamepadEnabled,
                socdEnabled      = ms.socdEnabled,
                windowsMode      = ms.windowsMode,
                socdMode         = ms.socdMode or "lastWins",

                trackpadHoldKeys = {
                    left  = ms.trackpadHoldKeys and ms.trackpadHoldKeys.left  or "n",
                    right = ms.trackpadHoldKeys and ms.trackpadHoldKeys.right or "j",
                },
                soundEnabled     = ms.soundEnabled,
                soundVolume      = ms.soundVolume,
                soundAssign      = ms.soundAssign,
                bundleSoundsWithTheme = ms.bundleSoundsWithTheme ~= false,
                soundPreset      = ms._soundPreset,
                importedSounds   = ms.importedSounds or {},
                customThemeDisabled = ms._customThemeDisabled or false,
                pluginsDisabled  = ms._pluginsDisabled or {},
                devArchiveLimit  = ms._devArchiveLimit or 15,
                updateChannel    = ms._updateChannel or "stable",
                testingSource    = ms._testingSource or "release",
                uiZoom             = ms._uiZoom or 1.0,
                octaneMode         = ms._octaneMode or false,
                octaneMuteSounds   = ms._octaneMuteSounds or false,
                uiTransparencyOff  = ms._uiTransparencyOff or false,
                swallowHotkeys     = ms._swallowHotkeys or false,
                updateAlertsDisabled = ms._updateAlertsDisabled or false,
                macroLabEnabled    = ms._macroLabEnabled ~= false,
                targetApp          = ms._targetAppSetting,
                consoleDangerAck = ms._consoleDangerAck or false,
                editMacrosAck    = ms._editMacrosAck or false,
                quickReloaded    = ms._quickReloaded or 0,
                qrOptions        = ms._qrOptions or {
                    macros   = true,
                    theme    = true,
                    settings = true,
                    ui       = true,
                },
                user             = _userSnapshot(),
                systemBinds      = {},
                macros = {},
            }
            for id, cfg in pairs(ms.systemBinds._config or {}) do
                data.systemBinds[id] = cfg
            end
            for id, enabled in pairs(ms.binds or {}) do
                data.macros[id] = data.macros[id] or {}
                data.macros[id].enabled = enabled
            end
            local function canonBind(x)
                if type(x) ~= "table" then return tostring(x) end
                local mods = {}
                for _, m in ipairs(x.mods or {}) do mods[#mods + 1] = m end
                table.sort(mods)
                local keys = {}
                for _, k in ipairs(x.keys or {}) do keys[#keys + 1] = k end
                table.sort(keys)
                return table.concat({
                    tostring(x.type), tostring(x.key), tostring(x.button),
                    tostring(x.direction), table.concat(mods, "+"),
                    table.concat(keys, "+"),
                }, "|")
            end
            for id, cfg in pairs(ms.bindConfig or {}) do
                local regEntry = ms.registry._defs and ms.registry._defs[id]
                local def = regEntry and regEntry.default
                local persist = def and (canonBind(cfg) ~= canonBind(def))
                    or (not def and cfg ~= nil)
                if persist then
                    data.macros[id] = data.macros[id] or {}
                    data.macros[id].bind = cfg
                end
            end
            for id, cooldown in pairs(ms.cooldowns or {}) do
                data.macros[id] = data.macros[id] or {}
                data.macros[id].cooldown = cooldown
            end
            for id, ignore in pairs(ms.bindIgnoreMods or {}) do
                if ignore then
                    data.macros[id] = data.macros[id] or {}
                    data.macros[id].ignoreMods = true
                end
            end
            for id in pairs(ms._suppressedMacros or {}) do
                data.macros[id] = data.macros[id] or {}
                data.macros[id].suppressed = true
            end
            -- Phase 6: Macro Lab & Shell State --
            data.shell = ms._shellState or {
                x = nil,
                y = nil,
                w = 900,
                h = 600,
                lastPanel = "macros",
                visible = false,
            }
            -- END Phase 6 --
            local f = io.open(jsonPath, "w")
            if f then
                f:write(hs.json.encode(data, true))
                f:close()
            end
        end

        ms.loadSettings = function()
            ms.dev.log({
                type = "system",
                event = "settings_load_start",
            })
            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            local f = io.open(jsonPath, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local data = hs.json.decode(content)
                if data then
                    local df = io.open(defaultPath, "r")
                    if df then
                        local defContent = df:read("*all")
                        df:close()
                        local defData = hs.json.decode(defContent)
                        if defData then
                            if (not data.soundAssign or next(data.soundAssign) == nil)
                                and defData.soundAssign then
                                data.soundAssign = defData.soundAssign
                            end
                        end
                    end
                    ms._applySettings(data)
                    ms._settingsLoaded = true
                    ms.dev.log({
                        type   = "system",
                        event  = "settings_loaded",
                        source = "json",
                    })
                    return
                end
                ms.dev.log({
                    type   = "error",
                    event  = "settings_parse_failed",
                    source = "json",
                })
            end
            local oldF = io.open(settingsPath, "r")
            if oldF then
                local data, skipped = ms._convertFlatSettings(oldF)
                oldF:close()
                ms._applySettings(data)
                ms._settingsLoaded = true
                ms.saveSettings()
                os.rename(settingsPath, archivePath .. "ms_settings_txt.bak")
                hs.timer.doAfter(1, function()
                    if #skipped > 0 then
                        ms.alert("Settings converted to JSON.\nSkipped unknown keys: " .. table.concat(skipped, ", "), 8)
                    else
                        ms.alert("Settings converted to JSON format.\nOld file backed up to backups/ms_settings_txt.bak.", 6)
                    end
                end)
                return
            end
            local df = io.open(defaultPath, "r")
            if df then
                local content = df:read("*all")
                df:close()
                local data = hs.json.decode(content)
                if data then
                    ms._applySettings(data)
                    ms._settingsLoaded = true
                    return
                end
            end
            ms._buildDefaultSettings()
            local df2 = io.open(defaultPath, "r")
            if df2 then
                local content2 = df2:read("*all")
                df2:close()
                local data2 = hs.json.decode(content2)
                if data2 then ms._applySettings(data2) end
            end
            ms._settingsLoaded = true
        end

        ms.saveDefault = function()
            ms.saveSettings()
            local sf = io.open(jsonPath, "r")
            if not sf then ms.alert("Could not read current settings.", 3)
            return end
            local content = sf:read("*all")
            sf:close()
            local existingDf = io.open(defaultPath, "r")
            if existingDf then
                local oldContent = existingDf:read("*all")
                existingDf:close()
                os.execute("mkdir -p '" .. archivePath .. "'")
                local timestamp = os.date("%Y-%m-%d_%H%M")
                local archiveFile = archivePath .. "ms_settings_default_" .. timestamp .. ".json"
                local af = io.open(archiveFile, "w")
                if af then af:write(oldContent)
                af:close() end
            end
            local df = io.open(defaultPath, "w")
            if df then
                df:write(content)
                df:close()
                ms.alert("Default settings saved.", 3)
            end
        end

        ms.resetToDefault = function()
            local f = io.open(defaultPath, "r")
            if not f then
                ms.alert("No default settings file found.", 3)
                return false
            end
            local content = f:read("*all")
            f:close()
            local data = hs.json.decode(content)
            if not data then
                ms.alert("Default settings file could not be decoded.", 3)
                return false
            end
            ms.bindConfig = {}
            ms.cooldowns  = {}
            ms.bindIgnoreMods = {}
            ms._applySettings(data)
            for key, def in pairs(ms._userSettingIndex) do
                if def.type ~= "action" and def.default ~= nil then
                    ms._userSettingVals[key] = def.default
                    if type(def.onChange) == "function" then
                        pcall(def.onChange, def.default)
                    end
                end
            end
            ms.saveSettings()
            ms.bind.rebind()
            ms.socdApply()
            return true
        end

        ms.reloadSettings = function()
            ms.loadSettings()
            ms.bind.rebind()
            ms.socdApply()
            if ms.gamepadSync then ms.gamepadSync() end
            if not ms._quickReloading then
                ms.playSlot("update")
                ms.alert("Settings reloaded.", 5, true)
            end
        end

        ms.reloadUI = function()
            ms.bind.teardown()
            ms.registry._defs    = {}
            ms.registry._defList = {}
            ms.bind._wires    = {}
            ms.bind._autoCount = 0
            ms.macroMeta       = nil
            ms._userSettingDefs  = {}
            ms._userSettingIndex = {}
            ms._stashUserSettings()

            local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
            local af = io.open(macrosPath, "r")
            if af then
                local rawSrc = af:read("*all")
                af:close()
                local chunk = load(
                    rawSrc,
                    "@ms_macros.lua",
                    "bt",
                    ms._macroSandbox
                )
                if chunk then pcall(chunk) end
            end
            for _, id in ipairs(ms.registry._defList) do
                local def = ms.registry._defs[id]
                if def and not (def.default and def.default.type) and ms.binds[id] == nil then
                    ms.binds[id] = def.enabled
                end
            end
            ms._systemActions = {}
            if ms._userSettingIndex["showTamperWarning"] then
                ms._systemActions["showTamperWarning"] = function()
                    ms.showGuardian()
                end
                ms._systemActions["showIntegrityError"] = function()
                    ms.showGuardian()
                end
            end
            ms.loadSettings()
            ms._loadAuthoredSettings()
            ms._defineAuthoredSettings()
            ms._loadAuthoredMenus()
            ms.loadTheme()
            if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
            ms.bind.rebind()
            ms.socdApply()
            if ms._macroLabEnabled and ms.shell and ms.shell.hide then
                ms.shell.hide()
                if ms.ui and ms.ui._open then pcall(function() ms.ui.hide() end) end
            else
                ms.ui.hide()
            end
            pcall(function() ms.dev.console.hide() end)
            pcall(function() ms.dev.watcher.hide() end)
            pcall(function() ms.dev.keys.hide() end)
            pcall(function() ms.dev.window.hide() end)
            if not ms._quickReloading then
                ms.playSlot("update")
                ms.alert("UI reloaded.", 4, true)
            end
        end

        ctx._SETTING_TYPES = _SETTING_TYPES
        ctx._HIDEABLE_FEATURES = _HIDEABLE_FEATURES
        ctx._validateUserValue = _validateUserValue
    -- END User Settings validation helpers --
end

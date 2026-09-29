return function(ms, ctx)
    -- User Settings validation helpers --
        local settingsPath = ctx.settingsPath
        local jsonPath = ctx.jsonPath
        local defaultPath = ctx.defaultPath
        local authoredPath = ctx.authoredPath
        local authoredMenusPath = ctx.authoredMenusPath
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
                if n then return math.max(def.min or 0, math.min(def.max or 100, n)) end
            elseif def.type == "seg" then
                if type(def.options) == "table" then
                    for _, opt in ipairs(def.options) do
                        if opt.value == value then return value end
                    end
                end
            end
            return nil
        end

        ms._applySettings = function(data)
            if not data then return end
            if data.sensitivity ~= nil then
                local num = tonumber(data.sensitivity)
                if num and num >= 0.1 and num <= 4 then
                    ms._pendingUserSettings = ms._pendingUserSettings or {}
                    ms._pendingUserSettings["cameraSensitivity"] = num
                    ms._camSens = num
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
                consoleDangerAck = ms._consoleDangerAck or false,
                quickReloaded    = ms._quickReloaded or 0,
                qrOptions        = ms._qrOptions or {
                    macros   = true,
                    theme    = true,
                    settings = true,
                    ui       = true,
                },
                user             = ms._userSettingVals or {},
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

        local _AUTHORED_TYPES = {
            toggle = true,
            slider = true,
            seg = true,
            action = true,
            groupLabel = true,
            divider = true,
        }
        local function _trim(s)
            return (type(s) == "string") and s:match("^%s*(.-)%s*$") or ""
        end
        -- Stable id every authored item carries for reorder and keyless delete
        local _uidSeq = 0
        local function _newUid()
            _uidSeq = _uidSeq + 1
            return string.format("a%d_%d_%d", os.time(), _uidSeq,
                math.random(0, 999999))
        end
        ms._sanitizeAuthoredDef = function(raw)
            if type(raw) ~= "table" then return nil, "definition must be a table" end
            local t = raw.type
            if not _AUTHORED_TYPES[t] then return nil, "unsupported type" end

            local def = {
                type = t,
                authored = true,
            }
            -- Carry a caller-supplied uid through
            if type(raw.uid) == "string" and raw.uid ~= "" then
                def.uid = raw.uid
            end
            -- Resolve placement section, with `target` as a legacy alias
            local placement = raw.section
            if placement == nil or placement == "" then placement = raw.target end
            if type(placement) == "string"
                and placement ~= "" and placement ~= "settings" then
                def.section = placement
            end

            if t == "divider" then return def end
            if t == "groupLabel" then
                def.label = _trim(raw.label)
                if def.label == "" then return nil, "a label is required" end
                return def
            end

            local key = _trim(raw.key)
            if key == "" then return nil, "a key is required" end
            if not key:match("^[%a_][%w_]*$") then
                return nil, "key must be a valid identifier (letters, digits, _)"
            end
            def.key   = key
            def.label = _trim(raw.label) ~= "" and _trim(raw.label) or key
            local hint = _trim(raw.hint)
            if hint ~= "" then def.hint = hint end
            def.save = true

            if t == "toggle" then
                def.default = raw.default == true
            elseif t == "slider" then
                local mn = tonumber(raw.min) or 0
                local mx = tonumber(raw.max) or 100
                if mx <= mn then mx = mn + 1 end
                local st = tonumber(raw.step) or 1
                if st <= 0 then st = 1 end
                local d = tonumber(raw.default)
                if d == nil then d = mn end
                if d < mn then d = mn elseif d > mx then d = mx end
                def.min, def.max, def.step, def.default = mn, mx, st, d
                local unit = _trim(raw.unit)
                if unit ~= "" then def.unit = unit end
            elseif t == "seg" then
                local opts = {}
                if type(raw.options) == "table" then
                    for _, o in ipairs(raw.options) do
                        if type(o) == "table" and _trim(o.label) ~= "" then
                            local val = o.value
                            if val == nil or val == "" then val = _trim(o.label) end
                            table.insert(opts, {
                                label = _trim(o.label),
                                value = val,
                            })
                        end
                    end
                end
                if #opts == 0 then return nil, "at least one option is required" end
                def.options = opts
                def.default = raw.default ~= nil and raw.default or opts[1].value
            elseif t == "action" then
                local bl = _trim(raw.btnLabel)
                def.btnLabel = bl ~= "" and bl or "Run"
                def.danger   = raw.danger == true
            end
            return def
        end

        ms._loadAuthoredSettings = function()
            ms._authoredSettings = {}
            local f = io.open(authoredPath, "r")
            if not f then return end
            local content = f:read("*all")
            f:close()
            local ok, data = pcall(hs.json.decode, content)
            if ok and type(data) == "table" then
                for _, def in ipairs(data) do
                    local clean = ms._sanitizeAuthoredDef(def)
                    if clean then
                        -- Mint a uid for legacy items that predate them
                        if not clean.uid then clean.uid = _newUid() end
                        table.insert(ms._authoredSettings, clean)
                    end
                end
            end
        end

        ms._saveAuthoredSettings = function()
            local f = io.open(authoredPath, "w")
            if f then
                f:write(hs.json.encode(ms._authoredSettings or {}, true))
                f:close()
            end
        end

        ms._defineAuthoredSettings = function()
            for _, def in ipairs(ms._authoredSettings or {}) do
                local key = def.key
                if not (key and ms._userSettingIndex[key]) then
                    local copy = {}
                    for k, v in pairs(def) do copy[k] = v end
                    if def.options then
                        copy.options = {}
                        for i, o in ipairs(def.options) do
                            copy.options[i] = {
                                label = o.label,
                                value = o.value,
                            }
                        end
                    end
                    pcall(ms.settings.define, copy)
                end
            end
        end

        ms.addAuthoredSetting = function(raw)
            local def, err = ms._sanitizeAuthoredDef(raw)
            if not def then return false, err end
            if def.key and ms._userSettingIndex[def.key] then
                return false, "a setting named '" .. def.key .. "' already exists"
            end
            if not def.uid then def.uid = _newUid() end
            ms._authoredSettings = ms._authoredSettings or {}
            table.insert(ms._authoredSettings, def)
            local ok = pcall(ms.settings.define, def)
            if not ok then
                table.remove(ms._authoredSettings)
                return false, "could not register the setting"
            end
            ms._saveAuthoredSettings()
            ms.saveSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        ms.removeAuthoredSetting = function(key)
            if type(key) ~= "string" or key == "" then
                return false, "a key is required"
            end
            ms._authoredSettings = ms._authoredSettings or {}
            local foundAt
            for i, def in ipairs(ms._authoredSettings) do
                if def.key == key then foundAt = i
                break end
            end
            if not foundAt then
                return false, "'" .. key .. "' is not an authored setting"
            end

            table.remove(ms._authoredSettings, foundAt)

            if ms._userSettingIndex then ms._userSettingIndex[key] = nil end
            if ms._userSettingVals  then ms._userSettingVals[key]  = nil end
            if ms._userSettingDefs then
                for i = #ms._userSettingDefs, 1, -1 do
                    local d = ms._userSettingDefs[i]
                    if type(d) == "table" and d.key == key then
                        table.remove(ms._userSettingDefs, i)
                    end
                end
            end

            ms._saveAuthoredSettings()
            ms.saveSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        -- Re-register every authored def so render order follows the authored list
        ms._reregisterAuthored = function()
            ms._pendingUserSettings = ms._pendingUserSettings or {}
            for _, d in ipairs(ms._authoredSettings or {}) do
                if d.key and ms._userSettingVals
                    and ms._userSettingVals[d.key] ~= nil then
                    ms._pendingUserSettings[d.key] = ms._userSettingVals[d.key]
                end
            end
            if ms._userSettingDefs then
                for i = #ms._userSettingDefs, 1, -1 do
                    local d = ms._userSettingDefs[i]
                    if type(d) == "table" and d.authored then
                        if d.key then
                            if ms._userSettingIndex then ms._userSettingIndex[d.key] = nil end
                            if ms._userSettingVals  then ms._userSettingVals[d.key]  = nil end
                        end
                        table.remove(ms._userSettingDefs, i)
                    end
                end
            end
            ms._defineAuthoredSettings()
        end

        -- Remove an authored item by its stable uid
        ms.removeAuthoredSettingByUid = function(uid)
            if type(uid) ~= "string" or uid == "" then
                return false, "a uid is required"
            end
            ms._authoredSettings = ms._authoredSettings or {}
            local foundAt
            for i, def in ipairs(ms._authoredSettings) do
                if def.uid == uid then foundAt = i break end
            end
            if not foundAt then return false, "no authored item with that id" end
            table.remove(ms._authoredSettings, foundAt)
            ms._reregisterAuthored()
            ms._saveAuthoredSettings()
            ms.saveSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        -- Reorder the authored list to match `order`, an array of uids
        ms.reorderAuthoredSettings = function(order)
            if type(order) ~= "table" then
                return false, "order must be a list of ids"
            end
            local list = ms._authoredSettings or {}
            local byUid = {}
            for _, d in ipairs(list) do
                if d.uid then byUid[d.uid] = d end
            end
            local newList, seen = {}, {}
            for _, uid in ipairs(order) do
                local d = byUid[uid]
                if d and not seen[uid] then
                    seen[uid] = true
                    table.insert(newList, d)
                end
            end
            for _, d in ipairs(list) do
                if not (d.uid and seen[d.uid]) then
                    table.insert(newList, d)
                end
            end
            ms._authoredSettings = newList
            ms._reregisterAuthored()
            ms._saveAuthoredSettings()
            ms.saveSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        -- Replace an authored setting's definition in place
        ms.updateAuthoredSetting = function(oldKey, raw)
            if type(oldKey) ~= "string" or oldKey == "" then
                return false, "a key is required"
            end
            local def, err = ms._sanitizeAuthoredDef(raw)
            if not def then return false, err end
            if not def.key then
                return false, "this setting type cannot be edited"
            end

            ms._authoredSettings = ms._authoredSettings or {}
            local foundAt
            for i, d in ipairs(ms._authoredSettings) do
                if d.key == oldKey then foundAt = i break end
            end
            if not foundAt then
                return false, "'" .. oldKey .. "' is not an authored setting"
            end
            if def.key ~= oldKey and ms._userSettingIndex
                and ms._userSettingIndex[def.key] then
                return false, "a setting named '" .. def.key .. "' already exists"
            end

            -- Snapshot the live value so a same-key edit doesn't reset it.
            local prevVal = ms._userSettingVals and ms._userSettingVals[oldKey]

            -- Tear down the old registration, remembering its slot
            if ms._userSettingIndex then ms._userSettingIndex[oldKey] = nil end
            if ms._userSettingVals  then ms._userSettingVals[oldKey]  = nil end
            local defsPos
            if ms._userSettingDefs then
                for i = #ms._userSettingDefs, 1, -1 do
                    local d = ms._userSettingDefs[i]
                    if type(d) == "table" and d.key == oldKey then
                        defsPos = i
                        table.remove(ms._userSettingDefs, i)
                    end
                end
            end

            -- Seed the retained value so define() adopts it
            if def.key == oldKey and prevVal ~= nil then
                ms._pendingUserSettings = ms._pendingUserSettings or {}
                ms._pendingUserSettings[def.key] = prevVal
            end

            local prevDef = ms._authoredSettings[foundAt]
            -- Keep the item's identity stable across an edit
            def.uid = prevDef.uid or def.uid or _newUid()
            ms._authoredSettings[foundAt] = def
            local ok = pcall(ms.settings.define, def)
            if not ok then
                ms._authoredSettings[foundAt] = prevDef
                return false, "could not register the setting"
            end

            -- Move the appended def back to the slot the old def held
            if defsPos and ms._userSettingDefs then
                local last = #ms._userSettingDefs
                if last > defsPos then
                    local moved = table.remove(ms._userSettingDefs, last)
                    table.insert(ms._userSettingDefs, defsPos, moved)
                end
            end

            ms._saveAuthoredSettings()
            ms.saveSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        -- Turn a display title into a stable, collision-free section id.
        local function _sectionIdFromTitle(title, taken)
            local base = (title or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
            if base == "" then base = "section" end
            base = "user_" .. base
            local id, n = base, 1
            while taken[id] do n = n + 1 id = base .. "_" .. n end
            return id
        end

        ms._loadAuthoredMenus = function()
            ms._authoredMenus = {}
            local f = io.open(authoredMenusPath, "r")
            if not f then return end
            local content = f:read("*all")
            f:close()
            local ok, data = pcall(hs.json.decode, content)
            if ok and type(data) == "table" then
                for _, m in ipairs(data) do
                    if type(m) == "table"
                        and type(m.id) == "string" and #m.id > 0
                        and type(m.title) == "string" then
                        table.insert(ms._authoredMenus, {
                            id    = m.id,
                            title = m.title,
                            icon  = type(m.icon) == "string" and m.icon or nil,
                            hint  = type(m.hint) == "string" and m.hint or nil,
                        })
                    end
                end
            end
        end

        ms._saveAuthoredMenus = function()
            local f = io.open(authoredMenusPath, "w")
            if f then
                f:write(hs.json.encode(ms._authoredMenus or {}, true))
                f:close()
            end
        end

        ms.addAuthoredMenu = function(raw)
            ms._authoredMenus = ms._authoredMenus or {}
            -- Only one user-created section is allowed
            if #ms._authoredMenus >= 1 then
                return false, "a custom section already exists"
            end
            local title = _trim(raw and raw.title or "")
            if title == "" then title = "New Section" end
            local taken = {}
            for _, m in ipairs(ms._authoredMenus) do taken[m.id] = true end
            local id = _sectionIdFromTitle(title, taken)
            table.insert(ms._authoredMenus, {
                id    = id,
                title = title,
                icon  = _trim(raw and raw.icon or "") ~= "" and _trim(raw.icon) or nil,
                hint  = _trim(raw and raw.hint or "") ~= "" and _trim(raw.hint) or nil,
            })
            ms._saveAuthoredMenus()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true, id
        end

        ms.updateAuthoredMenu = function(id, raw)
            if type(id) ~= "string" or id == "" then
                return false, "a section id is required"
            end
            ms._authoredMenus = ms._authoredMenus or {}
            local found
            for _, m in ipairs(ms._authoredMenus) do
                if m.id == id then found = m break end
            end
            if not found then return false, "not a user-created section" end
            if raw.title ~= nil then
                local title = _trim(raw.title)
                found.title = title ~= "" and title or found.title
            end
            if raw.icon ~= nil then
                local icon = _trim(raw.icon)
                found.icon = icon ~= "" and icon or nil
            end
            if raw.hint ~= nil then
                local hint = _trim(raw.hint)
                found.hint = hint ~= "" and hint or nil
            end
            ms._saveAuthoredMenus()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
        end

        ms.removeAuthoredMenu = function(id)
            if type(id) ~= "string" or id == "" then
                return false, "a section id is required"
            end
            ms._authoredMenus = ms._authoredMenus or {}
            local foundAt
            for i, m in ipairs(ms._authoredMenus) do
                if m.id == id then foundAt = i break end
            end
            if not foundAt then return false, "not a user-created section" end
            table.remove(ms._authoredMenus, foundAt)

            -- Settings that lived here fall back to the default Settings group.
            for _, def in ipairs(ms._authoredSettings or {}) do
                if def.section == id then def.section = nil end
            end
            for _, def in ipairs(ms._userSettingDefs or {}) do
                if type(def) == "table" and def.section == id then
                    def.section = nil
                end
            end
            ms._saveAuthoredMenus()
            ms._saveAuthoredSettings()
            if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
            return true
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
            ms._userSettingVals  = {}
            ms._pendingUserSettings = {}

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

        local function _exitCurtain(mode, onShow, onReady)
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

            local function present()
                armFading()

                ms.safeShow(view)

                pcall(function() view:alpha(1) end)

                pcall(function() view:bringToFront(true) end)
                pcall(function() view:level(_CURTAIN_LEVEL) end)

                local shown = pcall(function()
                    view:evaluateJavaScript("applyTheme(" .. theme .. ");"
                        .. string.format("showCurtain(%q, %s);", mode, octane))
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

        local function _exit(mode, slot, finish)
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
            end)
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

        ms.restart = function()
            if ms._restarting or ms._shuttingDown then return end
            ms._restarting = true
            ms.dev.log({
                type = "system",
                event = "restart_start",
            })

            _armExternalHardKill("restart")

            _exit("restart", "restart", function()
                if hs.relaunch then hs.relaunch() else hs.reload() end
            end)
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
                    -- Restore authored settings without letting reloadUI run below
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

            -- Skip reloadUI when macros were reloaded; it would brick plugins
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

        ctx._SETTING_TYPES = _SETTING_TYPES
        ctx._HIDEABLE_FEATURES = _HIDEABLE_FEATURES
        ctx._validateUserValue = _validateUserValue
    -- END User Settings validation helpers --
end

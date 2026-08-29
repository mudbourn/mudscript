-- MsSettings --
return function(ms)
-- MsSettings --
    local MsSettings = {}

    MsSettings.name    = "MsSettings"
    MsSettings.version = "1.0"
-- END MsSettings --

-- Init --
    function MsSettings:init()
    end
-- END Init --

-- Start --
    function MsSettings:start()
        if not _G.ms then return end
        local ms = _G.ms
        if ms.checkGuardian and not ms.checkGuardian("MsSettings") then return end

        self:_initSettingsMenu(ms)
    end
-- END Start --

-- Settings Menu --
    -- Panel State & Builders --
        function MsSettings:_initSettingsMenu(ms)
        local settingsPath    = os.getenv("HOME") .. "/.hammerspoon/ms_settings.txt"
        local jsonPath        = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings.json"
        local defaultPath     = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings_default.json"
        local authoredPath    = os.getenv("HOME") .. "/.hammerspoon/data/ms_authored.json"
        local authoredMenusPath = os.getenv("HOME") .. "/.hammerspoon/data/ms_authored_menus.json"
        local archivePath     = os.getenv("HOME") .. "/.hammerspoon/backups/"
        local macrosPath      = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
        local profilesPath    = os.getenv("HOME") .. "/.hammerspoon/profiles/"
        local corePath        = os.getenv("HOME") .. "/.hammerspoon/ms_core.lua"
        local trustedHashPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_trusted_hash"
        local themePath       = os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json"
        local visualJsonPath  = os.getenv("HOME") .. "/.hammerspoon/data/ms_macros_visual.json"
        local visualLuaPath   = os.getenv("HOME") .. "/.hammerspoon/data/ms_macros_visual.lua"
        local helperVarsPath  = os.getenv("HOME") .. "/.hammerspoon/data/ms_helpervars.json"

        -- Builder content that belongs to a profile beyond ms_macros.lua: the
        -- visual macro source + its compiled output, authored tools, and helper
        -- vars. Each rides with the profile like ms_theme.json — otherwise it
        -- lives in the global data/ dir and leaks across every profile.
        local function profileContentFiles()
            return {
                { live = visualJsonPath, name = "ms_macros_visual.json" },
                { live = visualLuaPath,  name = "ms_macros_visual.lua" },
                { live = authoredPath,   name = "ms_authored.json" },
                { live = authoredMenusPath, name = "ms_authored_menus.json" },
                { live = helperVarsPath, name = "ms_helpervars.json" },
            }
        end

        ms.bindConfig = {}
        ms.bindHandles = {}
        ms.bindIgnoreMods = ms.bindIgnoreMods or {}

        ms.parseBind = function(str)
            local btn = str:match("^mouse:(%d+)$")
            if btn then return {
                type="mouse",
                button=tonumber(btn),
            } end
            local dir = str:match("^scroll:(%w+)$")
            if dir and (dir == "up" or dir == "down") then return {
                type="scroll",
                direction=dir,
            } end
            -- gamepad:<btn> for a single button, or gamepad:<b1>+<b2>+... for a
            -- chord. Single binds keep the legacy {button=} shape; chords use
            -- {buttons={}} so older single-button configs round-trip unchanged.
            local gp = str:match("^gamepad:([%w+]+)$")
            if gp then
                local list = {}
                for b in gp:gmatch("[^+]+") do list[#list + 1] = b end
                if #list == 1 then
                    return { type = "gamepad", button = list[1] }
                elseif #list > 1 then
                    return { type = "gamepad", buttons = list }
                end
            end
            local mods = {}
            local parts = {}
            for part in str:gmatch("[^+]+") do
                table.insert(parts, part:lower())
            end
            local modkeys = {
                cmd   = true,
                alt   = true,
                ctrl  = true,
                shift = true,
            }
            local key = nil
            for _, part in ipairs(parts) do
                if modkeys[part] then
                    table.insert(mods, part)
                else
                    key = part
                end
            end
            if key then return {
                type = "key",
                mods = mods,
                key  = key,
            }end
            return nil
        end
    -- END Panel State & Builders --

    -- User Settings validation helpers --
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
                    -- Load a stored bind regardless of whether the macro is
                    -- registered right now. The old `def and ...` gate dropped
                    -- the bind for any macro not in the registry at load time —
                    -- which, for a VISUAL macro (whose bind lives ONLY here in
                    -- settings, never as a define() default), meant a load run
                    -- while ms_macros_visual.json was mid-hotswap or its compile
                    -- transiently failed would strip the bind from bindConfig,
                    -- and the next saveSettings would then erase it from disk for
                    -- good. Round-tripping the raw bind keeps it alive across
                    -- such windows; an orphan entry is harmless (rebind iterates
                    -- the registry, save just writes it back) and is cleaned up
                    -- properly when the macro is actually deleted.
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
            if data.macroLabEnabled ~= nil then ms._macroLabEnabled = (data.macroLabEnabled == true) end
            if data.shell and type(data.shell) == "table" then
                ms._shellState = ms._shellState or {}
                local s = data.shell
                if s.x ~= nil then ms._shellState.x = tonumber(s.x) end
                if s.y ~= nil then ms._shellState.y = tonumber(s.y) end
                if s.w ~= nil then ms._shellState.w = tonumber(s.w) end
                if s.h ~= nil then ms._shellState.h = tonumber(s.h) end
                if s.lastPanel ~= nil then ms._shellState.lastPanel = tostring(s.lastPanel) end
                -- Shell visibility: force hidden on a COLD boot (the loading
                -- screen owns the screen then, and the shell starts closed).
                -- Only during a live hotswap (profile switch / pack activate,
                -- flagged by _quickReloading) do we preserve the shell's REAL
                -- on-screen state — otherwise the toggle forgets it is open and
                -- replays the open sequence on the next Alt+P. Calling
                -- ms.shell.isVisible() at boot also perturbed the loading
                -- choreography, so it must stay out of the cold-boot path.
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
        -- Stable id every authored item carries so the Arrange list can reorder
        -- and the UI can delete keyless items (dividers/labels have no key).
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
            -- Carry a stable uid through when the caller supplied one (edits,
            -- reorders, on-disk defs); addAuthoredSetting/load mint one otherwise.
            if type(raw.uid) == "string" and raw.uid ~= "" then
                def.uid = raw.uid
            end
            -- "settings"/nil is default, "calibration" the built-in group, any
            -- other value a user-created section id to render inside. The rest of
            -- the system (disk, UI push, tools list, grouping) names this field
            -- `section`; `target` is a legacy alias kept so older callers/payloads
            -- still resolve. Reading only `target` here silently dropped the
            -- placement on every load and edit, since sanitize is the shared choke
            -- point for both save and load.
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
                        -- Legacy files predate uids; mint one so every item is
                        -- addressable. Persisted on the next save.
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

        -- Tear down every authored def from the live registry and re-register
        -- them from ms._authoredSettings, so the render order (which follows
        -- ms._userSettingDefs) matches the authored list after a reorder. Current
        -- values are snapshotted into the pending map so keyed settings keep them.
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

        -- Remove an authored item by its stable uid — the only way to delete
        -- keyless items (dividers, labels), which carry no key.
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

        -- Reorder the authored list to match `order` (an array of uids). Uids the
        -- caller omits keep their current relative order, appended after the ones
        -- it named, so a partial order never drops an item.
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

        -- Replace an authored setting's definition in place, keeping its slot in
        -- the list. A same-key edit preserves the user's current value (when it
        -- still validates against the new def). Renaming the key starts fresh at
        -- the new default. Renaming onto an existing key is refused.
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

            -- Tear down the old registration (index / value / defs), mirroring
            -- removeAuthoredSetting, remembering where the def sat so the new
            -- one can take the same slot.
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

            -- Seed the retained value so define() adopts it (same-key edits
            -- only, and only when it still validates against the new def).
            if def.key == oldKey and prevVal ~= nil then
                ms._pendingUserSettings = ms._pendingUserSettings or {}
                ms._pendingUserSettings[def.key] = prevVal
            end

            local prevDef = ms._authoredSettings[foundAt]
            -- Keep the item's identity stable across an edit so the Arrange list
            -- and any pending reorder still address it.
            def.uid = prevDef.uid or def.uid or _newUid()
            ms._authoredSettings[foundAt] = def
            local ok = pcall(ms.settings.define, def)
            if not ok then
                ms._authoredSettings[foundAt] = prevDef   -- roll back
                return false, "could not register the setting"
            end

            -- define() appends to _userSettingDefs; move it back to the slot the
            -- old def held so the setting keeps its position in the list.
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

        -- Section metadata (user-created Tuning-tab sections) --
        -- A section is just the `section` field a setting carries; a setting
        -- groups under whatever name it names. This store only holds the title
        -- and icon for sections the user made in the UI, so an empty one still
        -- shows and can be renamed. Pack sections (calibration and any other
        -- section= a pack uses) need no entry; their title is derived.

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
            -- Only one user-created section is allowed; the UI hides the creator
            -- once any section exists, and this guards against a stale caller.
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

                pcall(function() view:level(_CURTAIN_LEVEL) end)
                pcall(function() view:bringToFront(true) end)

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

        local function _exit(mode, slot, finish)
            local _finished = false
            local function finishOnce()
                if _finished then return end
                _finished = true
                finish()
            end

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
                    _spawnDetached(
                        "sleep " .. HARDKILL_SHUTDOWN_S ..
                        "; kill -9 " .. pid .. " 2>/dev/null"
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

            _exit("restart", "restart", function() hs.reload() end)
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
                    -- reloadMacros re-runs the macro chunk and plugins.loadAll,
                    -- but not the authored settings — the macro-slice hotswap
                    -- path (ms_ui.lua) pairs it with these two for that reason.
                    -- Run them here so authored settings survive without letting
                    -- reloadUI run below (which would wipe the setting/tool defs
                    -- reloadMacros just restored and never re-load plugins).
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
                        ms.shell.eval("applyTheme(" .. hs.json.encode(ms._theme or {}) .. ")")
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

            -- When macros were reloaded, reloadMacros already rebuilt every UI
            -- surface (registry, binds, settings, plugins). Running reloadUI on
            -- top of that tears down the plugin-registered tools and setting
            -- modules and never re-loads the plugins (they stay flagged loaded,
            -- so plugins.load early-returns) — bricking installed plugins until
            -- a full hs.reload. Same guard the settings block above uses.
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
    -- END User Settings validation helpers --

    -- User Settings & Menu API --
        -- ms.settings.define(def) --
            ms.settings.define = function(def)
                assert(type(def) == "table",
                    "ms.settings.define: argument must be a table")
                -- Stamp where this def came from so the Tools panel can filter by
                -- origin. ms._defineOrigin is set to "pack" while ms_macros.lua
                -- runs and "plugin" while a plugin loads; a runtime define with no
                -- context (the authored-setting builder) is the user's own.
                if def._origin == nil then def._origin = ms._defineOrigin or "user" end
                local t = def.type
                assert(_SETTING_TYPES[t],
                    "ms.settings.define: unknown type '" .. tostring(t) .. "'")
                if t == "divider" or t == "groupLabel" then
                    table.insert(ms._userSettingDefs, def)
                    return
                end
                if t == "group" then
                    assert(type(def.items) == "table",
                        "ms.settings.define: 'items' is required for type 'group'")
                    for _, subDef in ipairs(def.items) do
                        if type(subDef) == "table"
                            and type(subDef.key) == "string" and #subDef.key > 0 then
                            assert(not ms._userSettingIndex[subDef.key],
                                "ms.settings.define: duplicate key '" .. subDef.key .. "' in group")
                            ms._userSettingIndex[subDef.key] = subDef
                            local st = subDef.type
                            if st ~= "action" and st ~= "soundSlot"
                                and st ~= "divider" and st ~= "groupLabel" then
                                ms._userSettingVals[subDef.key] = subDef.default
                                if subDef.default ~= nil
                                    and type(subDef.onChange) == "function" then
                                    pcall(subDef.onChange, subDef.default)
                                end
                            end
                        end
                    end
                    table.insert(ms._userSettingDefs, def)
                    return
                end
                if t == "soundSlot" then
                    local key = def.key
                    assert(type(key) == "string" and #key > 0,
                        "ms.settings.define: 'key' is required for type 'soundSlot'")
                    assert(not ms._userSettingIndex[key],
                        "ms.settings.define: duplicate key '" .. key .. "'")
                    ms._userSettingIndex[key] = def
                    table.insert(ms._userSettingDefs, def)
                    return
                end
                local key = def.key
                assert(type(key) == "string" and #key > 0,
                    "ms.settings.define: 'key' is required for type '" .. t .. "'")
                assert(not ms._userSettingIndex[key],
                    "ms.settings.define: duplicate key '" .. key .. "'")
                if def.onChange then
                    assert(type(def.onChange) == "function",
                        "ms.settings.define: onChange must be a function")
                end
                if def.onAction then
                    assert(type(def.onAction) == "function",
                        "ms.settings.define: onAction must be a function")
                end
                ms._userSettingIndex[key] = def
                table.insert(ms._userSettingDefs, def)
                if t == "action" then return end
                local savedVal = ms._pendingUserSettings and ms._pendingUserSettings[key]
                if savedVal ~= nil then
                    local validated = _validateUserValue(def, savedVal)
                    if validated ~= nil then
                        ms._userSettingVals[key] = validated
                        ms._pendingUserSettings[key] = nil
                        if type(def.onChange) == "function" then
                            pcall(def.onChange, validated)
                        end
                        return
                    end
                end
                ms._userSettingVals[key] = def.default
                if def.default ~= nil and type(def.onChange) == "function" then
                    pcall(def.onChange, def.default)
                end
            end
        -- END ms.settings.define --

        -- ms.settings.get(key) --
            ms.settings.get = function(key)
                assert(type(key) == "string", "ms.settings.get: key must be a string")
                local def = ms._userSettingIndex[key]
                if not def then return nil end
                if def.type == "soundSlot" then
                    return (ms.soundAssign and ms.soundAssign[key]) or def.default
                end
                local v = ms._userSettingVals[key]
                return v ~= nil and v or def.default
            end
        -- END ms.settings.get --

        -- ms.settings.set(key, value) --
            ms.settings.set = function(key, value)
                assert(type(key) == "string", "ms.settings.set: key must be a string")
                local def = ms._userSettingIndex[key]
                if not def then
                    print("ms.settings.set: unknown key '" .. tostring(key) .. "'")
                    return
                end
                if def.type == "action" then
                    print("ms.settings.set: action items have no value (key='" .. key .. "')")
                    return
                end
                if def.type == "soundSlot" then
                    print("ms.settings.set: '" .. key .. "' is a soundSlot, assign sounds via Settings \xc2\xbb Sound.")
                    return
                end
                local validated = _validateUserValue(def, value)
                if validated == nil then
                    print("ms.settings.set: invalid value " .. tostring(value)
                        .. " for key '" .. key .. "'")
                    return
                end
                ms._userSettingVals[key] = validated
                if def.save ~= false then ms.saveSettings() end
                if type(def.onChange) == "function" then
                    pcall(def.onChange, validated)
                end
            end
        -- END ms.settings.set --

        -- ms.menu.define(def) --
            ms.menu.define = function(def)
                assert(type(def) == "table",
                    "ms.menu.define: argument must be a table")
                assert(type(def.id) == "string" and #def.id > 0,
                    "ms.menu.define: 'id' is required")
                assert(type(def.title) == "string" and #def.title > 0,
                    "ms.menu.define: 'title' is required")
                assert(type(def.items) == "table",
                    "ms.menu.define: 'items' must be a table")
                if def._origin == nil then def._origin = ms._defineOrigin or "user" end
                for _, item in ipairs(def.items) do
                    if type(item) == "table"
                        and type(item.key) == "string" and #item.key > 0
                        and not ms._userSettingIndex[item.key] then
                        if item.onChange then
                            assert(type(item.onChange) == "function",
                                "ms.menu.define: item onChange must be a function")
                        end
                        if item.onAction then
                            assert(type(item.onAction) == "function",
                                "ms.menu.define: item onAction must be a function")
                        end
                        ms._userSettingIndex[item.key] = item
                        if item.type ~= "action" then
                            ms._userSettingVals[item.key] = item.default
                            if item.default ~= nil and type(item.onChange) == "function" then
                                pcall(item.onChange, item.default)
                            end
                        end
                    end
                end
                table.insert(ms._userMenuDefs, def)
            end
        -- END ms.menu.define --

        -- ms.tools.define(def) --
            ms.tools.define = function(def)
                assert(type(def) == "table",
                    "ms.tools.define: argument must be a table")
                if def._origin == nil then def._origin = ms._defineOrigin or "user" end
                assert(type(def.id) == "string" and #def.id > 0,
                    "ms.tools.define: 'id' is required")
                assert(def.id:match("^[%a_][%w_%.]*$"),
                    "ms.tools.define: invalid id '" .. def.id
                        .. "' (must be a Lua-callable path, e.g. 'myPkg.doThing')")
                assert(not ms._toolIndex[def.id],
                    "ms.tools.define: duplicate tool id '" .. def.id .. "'")
                if def.run ~= nil then
                    assert(type(def.run) == "function",
                        "ms.tools.define: 'run' must be a function")
                end
                assert(def.params == nil or type(def.params) == "table",
                    "ms.tools.define: 'params' must be a table")
                assert(def.settings == nil or type(def.settings) == "table",
                    "ms.tools.define: 'settings' must be a table")

                for _, item in ipairs(def.settings or {}) do
                    assert(type(item) == "table",
                        "ms.tools.define: each entry in 'settings' must be a table")
                    assert(_SETTING_TYPES[item.type],
                        "ms.tools.define: unknown setting type '"
                            .. tostring(item.type) .. "'")
                    if item.type ~= "divider" and item.type ~= "groupLabel" then
                        assert(type(item.key) == "string" and #item.key > 0,
                            "ms.tools.define: setting 'key' is required for type '"
                                .. item.type .. "'")
                        local nsKey = "tool." .. def.id .. "." .. item.key
                        assert(not ms._userSettingIndex[nsKey],
                            "ms.tools.define: duplicate setting key '"
                                .. item.key .. "' on tool '" .. def.id .. "'")
                        item._nsKey  = nsKey
                        item._toolId = def.id
                        ms._userSettingIndex[nsKey] = item
                        if item.type ~= "action" then
                            local savedVal = ms._pendingUserSettings
                                and ms._pendingUserSettings[nsKey]
                            if savedVal ~= nil then
                                local validated = _validateUserValue(item, savedVal)
                                if validated ~= nil then
                                    ms._userSettingVals[nsKey] = validated
                                    ms._pendingUserSettings[nsKey] = nil
                                else
                                    ms._userSettingVals[nsKey] = item.default
                                end
                            else
                                ms._userSettingVals[nsKey] = item.default
                            end
                            local v = ms._userSettingVals[nsKey]
                            if v ~= nil and type(item.onChange) == "function" then
                                pcall(item.onChange, v)
                            end
                        end
                    end
                end

                ms._toolIndex[def.id] = def
                table.insert(ms._toolDefs, def)
            end
        -- END ms.tools.define --

        -- ms.tools.get(toolId, key) / ms.tools.set(toolId, key, value) --
            ms.tools.get = function(toolId, key)
                assert(type(toolId) == "string", "ms.tools.get: toolId must be a string")
                assert(type(key) == "string",    "ms.tools.get: key must be a string")
                return ms.settings.get("tool." .. toolId .. "." .. key)
            end

            ms.tools.set = function(toolId, key, value)
                assert(type(toolId) == "string", "ms.tools.set: toolId must be a string")
                assert(type(key) == "string",    "ms.tools.set: key must be a string")
                return ms.settings.set("tool." .. toolId .. "." .. key, value)
            end
        -- END ms.tools.get / ms.tools.set --

        -- ms.features.hide(name) --
            ms.features.hide = function(name)
                if not _HIDEABLE_FEATURES[name] then
                    print("ms.features.hide: '" .. tostring(name)
                        .. "' is not a hideable feature. "
                        .. "Accepted: sensitivity, socd, trackpad")
                    return
                end
                ms._hiddenFeatures[name] = true
            end
        -- END ms.features.hide --
    -- END User Settings & Menu API --

    -- Theme System --
        ms.loadTheme = function()
            ms.dev.log({
                type = "system",
                event = "theme_load",
            })
            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
            if ms._customThemeDisabled then return end
            local f = io.open(themePath, "r")
            if not f then return end
            local content = f:read("*all")
            f:close()
            local data = hs.json.decode(content)
            if not data then return end
            ms._themeLoaded = true
            local colorKeys = {
                "bg","surface","surface2","hover",
                "accent","accentHi","success","dangerBg",
                "danger","warning","text",
            }
            for _, k in ipairs(colorKeys) do
                if type(data[k]) == "string"
                    and data[k]:match("^#[0-9a-fA-F]+$")
                then
                    ms._theme[k] = data[k]
                end
            end
            if type(data.radius) == "number" then
                ms._theme.radius = math.max(0, math.min(40, math.floor(data.radius)))
            end
            if type(data.windowRadius) == "number" then
                ms._theme.windowRadius = math.max(0, math.min(40, math.floor(data.windowRadius)))
            end
            if type(data.fadeMs) == "number" then
                ms._theme.fadeMs = math.max(0, math.min(500, math.floor(data.fadeMs)))
            end
            if type(data.alertAnimMs) == "number" then
                ms._theme.alertAnimMs = math.max(50, math.min(1000, math.floor(data.alertAnimMs)))
            end
            if type(data.alertAnimSteps) == "number" then
                ms._theme.alertAnimSteps = math.max(2, math.min(60, math.floor(data.alertAnimSteps)))
            end
            if type(data.font) == "string" and #data.font > 0 then
                local clean = data.font:gsub("[;{}()<>\"']", "")
                if #clean > 0 then ms._theme.font = clean end
            end
            local overrideKeys = {
                "text2","text3","border",
                "accentGlow","accentGlowFaint",
                "dangerGlow","dangerBorder",
                "mouse","scroll","key",
            }
            for _, k in ipairs(overrideKeys) do
                if type(data[k]) == "string" and #data[k] > 0 then
                    ms._theme[k] = data[k]
                end
            end
        end

        ms.readThemeFile = function()
            local f = io.open(themePath, "r")
            if not f then return {} end
            local content = f:read("*all")
            f:close()
            local data = hs.json.decode(content or "")
            return type(data) == "table" and data or {}
        end

        ms.saveTheme = function(patch)
            if type(patch) ~= "table" then return false end
            local data = ms.readThemeFile()
            for k, v in pairs(patch) do
                if v == "" then data[k] = nil else data[k] = v end
            end
            local f = io.open(themePath, "w")
            if not f then return false end
            f:write(hs.json.encode(data, true))
            f:close()
            ms.loadTheme()
            return true
        end

        ms.resetTheme = function()
            if hs.fs.attributes(themePath) then
                os.rename(themePath, themePath .. ".bak")
            end
            ms.loadTheme()
            return true
        end
    -- END Theme System --

    -- Capability Detection --
        ms.has = function(feature)
            local home = os.getenv("HOME") .. "/.hammerspoon"

            if feature == "theme" then
                return ms._themeLoaded == true

            elseif feature == "sound" then
                return ms.soundEnabled == true
                    and next(ms.sounds or {}) ~= nil

            elseif feature == "socd" then
                return ms.socdEnabled == true

            elseif feature == "trackpad" then
                return ms.trackpadMode == true

            elseif feature == "profiles" then
                local pPath = home .. "/profiles/"
                if not hs.fs.attributes(pPath) then return false end
                for entry in hs.fs.dir(pPath) do
                    if entry ~= "." and entry ~= ".." then
                        if hs.fs.attributes(pPath .. entry .. "/ms_macros.lua") then
                            return true
                        end
                    end
                end
                return false

            elseif feature == "userSettings" then
                return type(ms.settings) == "table"
                    and type(ms.settings.define) == "function"

            elseif feature == "userMenu" then
                return type(ms.menu) == "table"
                    and type(ms.menu.define) == "function"

            elseif feature == "integrity" then
                return ms.integrity ~= nil
                    and ms.integrity.check() == "trusted"

            end
            return false
        end
    -- END Capability Detection --

    -- Profile Management --
        ms._buildDefaultSettings = function()
            local data = {
                sensitivity      = 1.5,
                trackpadMode     = false,
                gamepadEnabled   = false,
                socdEnabled      = false,
                socdMode         = "lastWins",

                trackpadHoldKeys = {
                    left = "n",
                    right = "j",
                },
                soundEnabled     = true,
                soundVolume      = 100,
                soundAssign      = {},
                bundleSoundsWithTheme = true,
                macros           = {},
                macroLabEnabled  = true,
                shell            = {
                    x = nil,
                    y = nil,
                    w = 900,
                    h = 600,
                    lastPanel = "macros",
                    visible = false,
                },
            }
            if ms.macroDefaults then
                for k, v in pairs(ms.macroDefaults) do
                    if k ~= "macros" then data[k] = v end
                end
                if ms.macroDefaults.macros then
                    for id, entry in pairs(ms.macroDefaults.macros) do
                        data.macros[id] = data.macros[id] or {}
                        for k, v in pairs(entry) do data.macros[id][k] = v end
                    end
                end
            end
            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not (def.default and def.default.type) then
                    data.macros[id] = data.macros[id] or {}
                    if data.macros[id].enabled == nil then
                        data.macros[id].enabled = def.enabled
                    end
                end
            end
            local f = io.open(defaultPath, "w")
            if f then
                f:write(hs.json.encode(data, true))
                f:close()
            end
        end

        local function sanitizeName(name)
            return (name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", ""))
        end

        local function moveFile(src, dst)
            local f = io.open(src, "r")
            if not f then return false, "cannot read " .. src end
            local content = f:read("*all")
            f:close()
            local g = io.open(dst, "w")
            if not g then return false, "cannot write " .. dst end
            g:write(content)
            g:close()
            os.remove(src)
            return true
        end

        local function moveDirContents(src, dst)
            if not hs.fs.attributes(src) then return 0 end
            os.execute("mkdir -p '" .. dst:gsub("'", "'\\''") .. "'")
            local moved = 0
            for file in hs.fs.dir(src) do
                if file ~= "." and file ~= ".." then
                    if os.rename(src .. file, dst .. file) then
                        moved = moved + 1
                    end
                end
            end
            return moved
        end

        -- Copy (not move) a dir's contents into dst — used to bank sounds into a
        -- profile folder on save/seed while leaving the live copies in place.
        -- Skips .bak scratch files so profile folders stay clean.
        local function copyDirContents(src, dst)
            if not hs.fs.attributes(src) then return 0 end
            local q = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            os.execute("mkdir -p " .. q(dst))
            local copied = 0
            for file in hs.fs.dir(src) do
                if file ~= "." and file ~= ".." and not file:find("%.bak$") then
                    local _, ok = hs.execute("/bin/cp -R " .. q(src .. file) .. " " .. q(dst .. file))
                    if ok then copied = copied + 1 end
                end
            end
            return copied
        end

        local function readMacroMeta(filePath)
            local captured = {}
            local dummyFn  = function() end
            local dummyTbl = setmetatable({}, {
                __index    = function() return dummyFn end,
                __newindex = function() end,
                __call     = function() end,
            })
            local proxy = setmetatable({}, {
                __index    = function(t, k)
                    if k == "macroMeta" then return captured.macroMeta end
                    return dummyTbl
                end,
                __newindex = function(t, k, v)
                    if k == "macroMeta" then captured.macroMeta = v end
                end,
            })
            local env = setmetatable({ ms = proxy }, {
                __index    = function() return nil end,
                __newindex = function() end,
            })
            local chunk, err
            if setfenv then
                chunk, err = loadfile(filePath)
                if chunk then setfenv(chunk, env) end
            else
                chunk, err = loadfile(filePath, "bt", env)
            end
            if not chunk then
                print("readMacroMeta: parse error in " .. filePath .. ": " .. tostring(err))
                return nil
            end
            if jit then pcall(jit.off, chunk, true) end

            local _co = coroutine.create(chunk)
            local _hookFires = 0

            debug.sethook(
                _co,
                function()
                    _hookFires = _hookFires + 1
                    if _hookFires > 2000 then
                        error("readMacroMeta: instruction limit exceeded (possible infinite loop in " .. filePath .. ")")
                    end
                end,
                "",
                1000
            )

            coroutine.resume(_co)
            return captured.macroMeta
        end

        ms._profilesDirty = true
        local _profilesCache = nil
        local function getProfiles()
            if not ms._profilesDirty and _profilesCache then return _profilesCache end
            ms._profilesDirty = false
            local list = {}
            if not hs.fs.attributes(profilesPath) then _profilesCache = list
            return list end
            for entry in hs.fs.dir(profilesPath) do
                if entry ~= "." and entry ~= ".." then
                    local attr = hs.fs.attributes(profilesPath .. entry)
                    if attr and attr.mode == "directory" then
                        if hs.fs.attributes(profilesPath .. entry .. "/ms_macros.lua")
                            or hs.fs.attributes(profilesPath .. entry .. "/ms_settings.json") then
                            table.insert(list, entry)
                        end
                    end
                end
            end
            local activeName = ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
            if activeName ~= "" and hs.fs.attributes(profilesPath .. activeName) then
                local found = false
                for _, p in ipairs(list) do
                    if p == activeName then found = true
                    break end
                end
                if not found then
                    table.insert(list, activeName)
                end
            end
            table.sort(list)
            _profilesCache = list
            return list
        end

        local auditMacros
        ms.auditMacros = function(src) return auditMacros(src) end

        local function switchProfile(targetName)
            ms.dev.log({
                type   = "system",
                event  = "profile_switch_start",
                target = targetName,
            })
            local targetFile = profilesPath .. targetName .. "/ms_macros.lua"
            local hasMacros = hs.fs.attributes(targetFile) ~= nil
            local targetSrc, switchErrs
            if hasMacros then
                local tf = io.open(targetFile, "r")
                if not tf then
                    ms.dev.log({
                        type   = "error",
                        event  = "profile_switch_failed",
                        reason = "cannot_read",
                        target = targetName,
                    })
                    ms.alert("Profile switch failed: cannot read target profile.", 5)
                    return
                end
                targetSrc = tf:read("*all")
                tf:close()
                switchErrs = auditMacros(targetSrc)
                if #switchErrs > 0 then
                    ms.alert("Profile switch rejected, security scan failed:\n  - "
                        .. table.concat(switchErrs, "\n  - "), 8)
                    return
                end
            end
            local currentName = sanitizeName(
                (ms.macroMeta and ms.macroMeta.name) or "unnamed"
            )
            -- Flush live state (binds, enabled flags, cooldowns, ...) to
            -- ms_settings.json BEFORE archiving it below. Without this, a bind
            -- set since the last save is written to disk only by the target's
            -- reload — i.e. never for the profile we are leaving — so the
            -- archived copy is stale and the bind is lost on switch-back.
            pcall(ms.saveSettings)
            hs.fs.mkdir(profilesPath)
            hs.fs.mkdir(profilesPath .. currentName)

            local currentHasMacros = hs.fs.attributes(macrosPath) ~= nil
            if currentHasMacros then
                local ok, err = moveFile(macrosPath, profilesPath .. currentName .. "/ms_macros.lua")
                if not ok then
                    ms.alert("Profile switch failed: could not archive current profile.\n" .. tostring(err), 5)
                    return
                end
            end
            local hadSettings = hs.fs.attributes(jsonPath)   and moveFile(jsonPath,    profilesPath .. currentName .. "/ms_settings.json")
            local hadDefaults = hs.fs.attributes(defaultPath) and moveFile(defaultPath, profilesPath .. currentName .. "/ms_settings_default.json")
            local hadTheme    = hs.fs.attributes(themePath)   and moveFile(themePath,   profilesPath .. currentName .. "/ms_theme.json")
            local curSoundsDir = profilesPath .. currentName .. "/sounds/"
            moveDirContents(SoundActiveDir, curSoundsDir .. "active/")
            moveDirContents(SoundMacroDir,  curSoundsDir .. "macro/")
            -- Archive the current profile's visual macros, tools, and vars so
            -- they do not leak into the target. Moving clears the live copies;
            -- a target with none stays cleared (a fresh profile is empty).
            for _, cf in ipairs(profileContentFiles()) do
                if hs.fs.attributes(cf.live) then
                    moveFile(cf.live, profilesPath .. currentName .. "/" .. cf.name)
                end
            end

            if hasMacros then
                local ok, err = moveFile(profilesPath .. targetName .. "/ms_macros.lua", macrosPath)
                if not ok then
                    if currentHasMacros then moveFile(profilesPath .. currentName .. "/ms_macros.lua", macrosPath) end
                    if hadSettings then moveFile(profilesPath .. currentName .. "/ms_settings.json",         jsonPath)    end
                    if hadDefaults then moveFile(profilesPath .. currentName .. "/ms_settings_default.json", defaultPath) end
                    if hadTheme    then moveFile(profilesPath .. currentName .. "/ms_theme.json",            themePath)   end
                    moveDirContents(profilesPath .. currentName .. "/sounds/active/", SoundActiveDir)
                    moveDirContents(profilesPath .. currentName .. "/sounds/macro/",  SoundMacroDir)
                    for _, cf in ipairs(profileContentFiles()) do
                        local arch = profilesPath .. currentName .. "/" .. cf.name
                        if hs.fs.attributes(arch) then moveFile(arch, cf.live) end
                    end
                    ms.alert("Profile switch failed: could to activate \"" .. targetName .. "\".\n" .. tostring(err), 5)
                    return
                end
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings.json") then
                moveFile(profilesPath .. targetName .. "/ms_settings.json",         jsonPath)
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings_default.json") then
                moveFile(profilesPath .. targetName .. "/ms_settings_default.json", defaultPath)
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_theme.json") then
                moveFile(profilesPath .. targetName .. "/ms_theme.json", themePath)
            end
            local tgtSoundsDir = profilesPath .. targetName .. "/sounds/"
            moveDirContents(tgtSoundsDir .. "active/", SoundActiveDir)
            moveDirContents(tgtSoundsDir .. "macro/",  SoundMacroDir)
            -- Restore the target's visual macros, tools, and vars (if any).
            for _, cf in ipairs(profileContentFiles()) do
                local arch = profilesPath .. targetName .. "/" .. cf.name
                if hs.fs.attributes(arch) then moveFile(arch, cf.live) end
            end

            -- Safety net: never leave the live ms_macros.lua absent. If the
            -- target profile had no ms_macros.lua (a freshly created empty
            -- profile), the archive step above removed the current one and
            -- nothing replaced it — which would hard-crash the next cold boot's
            -- security audit. Seed the same minimal stub boot uses so the live
            -- install always has a valid, auditable macros file.
            if not hs.fs.attributes(macrosPath) then
                local stub = io.open(macrosPath, "w")
                if stub then
                    stub:write(
                        "-- New profile — add your macros below.\n"
                        .. "ms.macroMeta = { name = \"" .. targetName .. "\", author = \"\" }\n"
                    )
                    stub:close()
                end
            end

            -- Bring the live content in line with the profile's same-named
            -- packs so the profile counts as aligned ("Active"). Activating each
            -- pack (content + marker) BEFORE the hotswap means the follow-on
            -- reloadMacros/loadSettings pick up the applied state, and — because
            -- the live content now matches the pack — the boot-time fingerprint
            -- reconcile keeps the profile aligned across restarts (a plain
            -- marker set would drift back on reboot, e.g. sound assignments).
            -- Kinds with no same-named pack are left to fingerprint reconcile
            -- after the hotswap; they will not match the profile slug, so the
            -- profile stays unaligned there until the user sets that pack, which
            -- is exactly the intended "mix = not a specific profile" behaviour.
            local alignedKinds = {}
            if ms.package and ms.package.librarySlug
                and ms.package.libraryActivate and ms.package.libraryHasEntry then
                -- Authoritative: the target profile's explicit component-pack
                -- links (packs.json). Fall back per-kind to the same-name slug
                -- convention for legacy profiles that predate packs.json.
                local links = ms.package.getProfilePacks
                    and ms.package.getProfilePacks(targetName) or nil
                local pslug = ms.package.librarySlug(targetName)
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    local slug = (links and links[k]) or pslug
                    if slug and ms.package.libraryHasEntry(k, slug) then
                        local ok, res = pcall(ms.package.libraryActivate, k, slug)
                        if ok and res then alignedKinds[k] = true end
                    end
                end
            end

            ms.dev.log({
                type   = "system",
                event  = "profile_switch_complete",
                target = targetName,
            })

            -- Hotswap the running state in place instead of a full hs.reload().
            -- Everything the target profile just moved onto disk is re-read
            -- here, the same surfaces boot rebuilds: macros (handwritten +
            -- visual) + plugins + settings + binds via reloadMacros, then
            -- theme, sounds, and authored settings. Quiet-flagged so the
            -- individual reloads suppress their own toasts and refocus dance;
            -- our single "Switched" toast stands in for all of them.
            local wasQuick = ms._quickReloading
            ms._quickReloading = true
            if ms.ui and ms.ui._actions and ms.ui._actions.reloadMacros then
                pcall(ms.ui._actions.reloadMacros)
            end
            if ms.loadTheme then pcall(ms.loadTheme) end
            pcall(function() ms.alert:recolor() end)
            pcall(function() ms.dev:recolor() end)
            ms._soundsDirty = true
            if ms._discoverSounds then pcall(ms._discoverSounds) end
            if ms._loadAuthoredSettings then pcall(ms._loadAuthoredSettings) end
            if ms._defineAuthoredSettings then pcall(ms._defineAuthoredSettings) end
            if ms._loadAuthoredMenus then pcall(ms._loadAuthoredMenus) end
            ms._quickReloading = wasQuick

            -- Kinds already aligned above (a same-named pack was activated) keep
            -- that marker. Any remaining kind is reconciled to whatever slice is
            -- now live by content fingerprint — which won't match the profile
            -- slug, leaving the profile intentionally unaligned there.
            if ms.package and ms.package.reconcileActive then
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    if not alignedKinds[k] then
                        pcall(ms.package.reconcileActive, k)
                    end
                end
            end

            -- Record the live setup as "on" this profile. Set last, after the
            -- internal libraryActivate calls above, so it is the final word (a
            -- manual pack hotswap later clears it — see ms_ui libraryActivate).
            if ms.package and ms.package.setActiveProfile then
                pcall(ms.package.setActiveProfile, targetName)
            end

            ms.playSlot("update")
            ms.alert("Switched to \"" .. targetName .. "\".", 3, true)
            ms.ui.markDirty()
            ms.ui.refresh()
            -- Repaint the Installed Library shelves so the reconciled markers
            -- show up as moved badges without waiting for a panel re-open.
            if ms.ui._actions and ms.ui._actions.libraryList then
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    pcall(ms.ui._actions.libraryList, { kind = k })
                end
            end
        end

        auditMacros = function(src)

                local function blank(s) return s:gsub("[^\n]", " ") end
                local out = {}
                local i, n = 1, #src

                while i <= n do
                    local c = src:sub(i, i)

                    if c == '"' or c == "'" then
                        -- Short quoted string --
                            local j = i + 1
                            while j <= n do
                                local ch = src:sub(j, j)
                                if ch == "\\" then
                                    j = j + 2
                                elseif ch == c then
                                    break
                                elseif ch == "\n" then
                                    break
                                else
                                    j = j + 1
                                end
                            end
                            out[#out + 1] = blank(src:sub(i, j))
                            i = j + 1

                        -- END Short quoted string --

                    elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
                        -- Comment --
                            local j      = i + 2
                            local isLong = false
                            if src:sub(j, j) == "[" then
                                local eq = 0
                                while src:sub(j + 1 + eq, j + 1 + eq) == "=" do eq = eq + 1 end
                                if src:sub(j + 1 + eq, j + 1 + eq) == "[" then
                                    local closer = "]" .. string.rep("=", eq) .. "]"
                                    local _, ce  = src:find(closer, j + 2 + eq, true)
                                    out[#out + 1] = blank(src:sub(i, ce or n))
                                    i = ce and ce + 1 or n + 1
                                    isLong = true
                                end
                            end
                            if not isLong then
                                local nl = src:find("\n", j)
                                if nl then
                                    out[#out + 1] = blank(src:sub(i, nl - 1)) .. "\n"
                                    i = nl + 1
                                else
                                    out[#out + 1] = blank(src:sub(i))
                                    i = n + 1
                                end
                            end

                        -- END Comment --

                    elseif c == "[" then
                        -- Long string [=*[...]=*] --
                            local eq = 0
                            while src:sub(i + 1 + eq, i + 1 + eq) == "=" do eq = eq + 1 end
                            if src:sub(i + 1 + eq, i + 1 + eq) == "[" then
                                local closer = "]" .. string.rep("=", eq) .. "]"
                                local _, ce  = src:find(closer, i + 2 + eq, true)
                                out[#out + 1] = blank(src:sub(i, ce or n))
                                i = ce and ce + 1 or n + 1
                            else
                                out[#out + 1] = c
                                i = i + 1
                            end

                        -- END Long string [=*[...]=*] --

                    else
                        out[#out + 1] = c
                        i = i + 1
                    end
                end

                local clean = " " .. table.concat(out)
                local errs  = {}
                local function deny(pat, label)
                    if clean:find(pat) then table.insert(errs, label) end
                end

                deny("[^%w%.]hs%.[%a_]",      "direct hs.* API access")

                deny("[^%w%.]load%s*%(",       "load()")
                deny("loadfile%s*%(",           "loadfile()")
                deny("loadstring%s*%(",         "loadstring()")
                deny("[^%w%.]dofile%s*%(",      "dofile()")
                deny("[^%w%.]require%s*%(",     "require()")

                deny("[^%w%.]os%.[%a_]",        "os.* access")
                deny("[^%w%.]io%.[%a_]",        "io.* access")
                deny("[^%w%.]popen%s*%(",       "popen()")

                deny("[^%w%.]debug%.[%a_]",     "debug.* access")
                deny("[^%w%.]package%.[%a_]",   "package.* access")
                deny("collectgarbage%s*%(",     "collectgarbage()")

                deny("setmetatable%s*%(",       "setmetatable()")
                deny("getmetatable%s*%(",       "getmetatable()")
                deny("[^%w_]rawget%s*%(",       "rawget()")
                deny("[^%w_]rawset%s*%(",       "rawset()")
                deny("setfenv%s*%(",            "setfenv()")
                deny("getfenv%s*%(",            "getfenv()")
                deny("%f[%w_]_G%f[^%w_]",      "_G global-environment access")

                deny(":launch%s*%(",            ":launch()")
                deny(":activate%s*%(",          ":activate()")
                deny("openURL%s*%(",            "openURL()")

                local mediaExts = {
                    "%.mp3","%.wav","%.aiff","%.m4a","%.ogg","%.flac",
                    "%.caf","%.aac","%.mp4","%.mov","%.avi",
                    "%.jpg","%.jpeg","%.png","%.gif","%.webp","%.bmp","%.tiff",
                }
                local function nearMedia(pos)
                    local ctx = clean:sub(math.max(1, pos-10), math.min(#clean, pos+120))
                    for _, ext in ipairs(mediaExts) do
                        if ctx:find(ext) then return true end
                    end
                    return false
                end
                for _, sysPath in ipairs({
                    "/Users/","/home/","/Applications/",
                    "/usr/","/var/","/etc/","/bin/","/sbin/",
                    "/opt/","/tmp/","/System/","/Library/",
                    "~/","%.hammerspoon",
                }) do
                    local pos = 1
                    while true do
                        local found = clean:find(sysPath, pos)
                        if not found then break end
                        if not nearMedia(found) then
                            local snip = clean:sub(found, math.min(#clean, found+35))
                                            :gsub("%s+", " ")
                            table.insert(errs, "disallowed path: " .. snip)
                            break
                        end
                        pos = found + 1
                    end
                end

                for line in clean:gmatch("[^\n]+") do
                    local name = line:match("^%s*function%s+([%a_][%w_]*)%s*%(")
            -- END Lexer pass --

                if name then
                    table.insert(errs, "non-local global function definition: " .. name .. "()")
                end
            end

            return errs
        end

        local function importProfile()
            ms.playSlot("alert")
            hs.focus()
            local result = hs.dialog.chooseFileOrFolder(
                "Select an ms_macros.lua file to import",
                os.getenv("HOME") .. "/Downloads/",
                true, false, false
            )
            local target = hs.application.get(ms._targetApp)
            local selectedPath
            for _, v in pairs(result or {}) do
                if type(v) == "string" then selectedPath = v
                break end
            end
            if not selectedPath then
                if target then pcall(function() target:activate() end) end
                return
            end
            local meta = readMacroMeta(selectedPath)
            if not meta or not meta.name or meta.name == "" then
                if target then pcall(function() target:activate() end) end
                ms.alert("Could not read profile name.\nMake sure the file has ms.macroMeta = { name = \"...\" }.", 6)
                return
            end
            local folderName = sanitizeName(meta.name)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end

            local function _commit()
                hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                if not hs.fs.attributes(profilesPath .. folderName) then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not create profile folder.", 3)
                    return
                end
                local f = io.open(selectedPath, "rb")
                if not f then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not read the selected file.", 3)
                    return
                end
                local content = f:read("*all")
                f:close()
                local auditErrs = auditMacros(content)
                if #auditErrs > 0 then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 "
                        .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                    return
                end
                local dst    = profilesPath .. folderName .. "/ms_macros.lua"
                local copied = false
                local g = io.open(dst, "wb")
                if g then
                    g:write(content)
                    g:close()
                    copied = true
                end
                if not copied then
                    local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                end
                if not copied then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                    return
                end
                ms.playSlot("update")
                ms._profilesDirty = true
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                ms.ui.refresh()
                if target then pcall(function() target:activate() end) end
                hs.timer.doAfter(0.2, function()
                    ms.alert("Profile \"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles.", 5, true)
                end)
            end

            if hs.fs.attributes(profilesPath .. folderName) then
                ms.ui.modal({
                    title   = "Overwrite Profile?",
                    msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this file?",
                    confirm = "Replace",
                    cancel  = "Cancel",
                }, function(r)
                    if r.confirmed then
                        _commit()
                    else
                        if target then pcall(function() target:activate() end) end
                    end
                end)
            else
                _commit()
            end
        end

        -- Create a fresh, bare-bones profile entry (credits only, no macros)
        -- without touching or reloading the active profile. The name auto-indexes
        -- ("New Profile 1", "New Profile 2", …) so repeated creates never collide;
        -- the index climbs until the user renames one.
        local function createNewProfile(seed)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            hs.fs.mkdir(profilesPath)

            local base, n, folderName = "New Profile", 0, nil
            repeat
                n = n + 1
                folderName = base .. " " .. n
            until not hs.fs.attributes(profilesPath .. folderName)

            local dir = profilesPath .. folderName
            hs.execute("mkdir -p " .. sq(dir))
            if not hs.fs.attributes(dir) then
                ms.alert("Could not create profile folder.", 3)
                return
            end

            -- Empty-but-valid macros: just credits, no binds. The boot loader
            -- treats a bindless file as an empty profile (a warning, not a fault).
            -- Uses the same canonical stub the blank macro PACK is seeded with,
            -- so the two are byte-identical and the pack reconciles as active.
            local blankSrc = (ms.package and ms.package.blankMacroSrc
                and ms.package.blankMacroSrc(folderName))
                or table.concat({
                    "-- New profile — add your macros below.",
                    "ms.macroMeta = {",
                    "    name   = \"" .. folderName .. "\",",
                    "    author = \"\",",
                    "}",
                    "",
                }, "\n")

            local mf = io.open(dir .. "/ms_macros.lua", "w")
            if not mf then
                ms.alert("Could not write the new profile.", 3)
                return
            end
            mf:write(blankSrc)
            mf:close()

            -- Seed from the current setup so a new profile need not come up
            -- default/silent. This is the "save my current combination of
            -- theme + sound + macro packs as a profile" path, so it must capture
            -- the live MACROS too — not just the look + settings + sounds.
            -- Dropping macros here was the root of two bugs: a seeded profile
            -- could never bundle the macro pack you had live, and switching to
            -- it equipped the blank stub. Mirror saveCurrentProfile's file set.
            if seed then
                if hs.fs.attributes(jsonPath) then
                    hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(dir .. "/ms_settings.json"))
                end
                if hs.fs.attributes(defaultPath) then
                    hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(dir .. "/ms_settings_default.json"))
                end
                if hs.fs.attributes(themePath) then
                    hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(dir .. "/ms_theme.json"))
                end
                copyDirContents(SoundActiveDir, dir .. "/sounds/active/")
                copyDirContents(SoundMacroDir,  dir .. "/sounds/macro/")
                -- Live handwritten macros overwrite the blank stub written above
                -- so the profile carries the current macro pack, not an empty one.
                if hs.fs.attributes(macrosPath) then
                    hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(dir .. "/ms_macros.lua"))
                end
                -- Visual macros, authored tools, and helper vars travel too, the
                -- same content saveCurrentProfile banks (see profileContentFiles).
                for _, cf in ipairs(profileContentFiles()) do
                    if hs.fs.attributes(cf.live) then
                        hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(dir .. "/" .. cf.name))
                    end
                end
                -- Bank the seeded slices as profile-named component packs so the
                -- profile is an explicit collection of packs from creation. Import
                -- (copy-only) rather than capture: creating a profile must not flip
                -- the live per-kind .active markers (we are not switching to it).
                if ms.package and ms.package.libraryImportDir then
                    for _, k in ipairs({ "macro", "theme", "sound" }) do
                        pcall(ms.package.libraryImportDir, k, dir,
                            { name = folderName, origin = "profile" })
                    end
                end
            end

            -- Parity: a blank profile spawns matching blank theme + sound packs
            -- in their libraries, so a fresh profile's look and sounds can be
            -- hotswapped the same way its macros can. Seeded profiles skip this
            -- (they already carry the live theme/sounds). Best-effort — a name
            -- clash just leaves the existing pack in place.
            if not seed and ms.package and ms.package.libraryCreateEmpty then
                for _, k in ipairs({ "macro", "theme", "sound" }) do
                    local ok, rec, err = pcall(ms.package.libraryCreateEmpty, k, folderName)
                    -- Surface a failed pack creation instead of swallowing it —
                    -- a silent pcall here is what let a missing macro pack go
                    -- unnoticed. rec==nil means the create declined (name clash)
                    -- or errored; log both so a real failure is diagnosable.
                    if not ok or not rec then
                        local why = (not ok) and tostring(rec) or tostring(err)
                        print("createNewProfile: libraryCreateEmpty(" .. k
                            .. ") did not create a pack: " .. why)
                        if ms.dev and ms.dev.log then
                            pcall(ms.dev.log, {
                                type  = "warning",
                                event = "profile_pack_create_failed",
                                kind  = k,
                                msg   = why,
                            })
                        end
                    end
                end
            end

            -- Record the profile's explicit component-pack links (packs.json) for
            -- whichever kinds now have a same-named pack — blank profiles created
            -- them above, seeded profiles imported them. switchProfile and boot
            -- read this as the authoritative link instead of the name convention.
            if ms.package and ms.package.setProfilePacks
                and ms.package.libraryHasEntry and ms.package.librarySlug then
                local slug = ms.package.librarySlug(folderName)
                local refs = {}
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    if ms.package.libraryHasEntry(k, slug) then refs[k] = slug end
                end
                pcall(ms.package.setProfilePacks, folderName, refs)
            end

            ms._profilesDirty = true

            -- A blank profile switches to itself: its three same-named packs
            -- all become active together, so the profile reads as aligned
            -- ("Active") in one step. switchProfile runs the full hotswap and
            -- its own toast, so return here rather than double-toasting. Seeded
            -- profiles are left inactive (creating != switching for those).
            if not seed then
                ms.playSlot("update")
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                switchProfile(folderName)
                return
            end

            ms.playSlot("update")
            ms.alert("Created \"" .. folderName .. "\".", 3)
            -- markDirty forces refresh to rebuild the pushed state (which reads
            -- getProfiles); without it refresh re-sends the stale cache and the
            -- new entry only shows after a reload.
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
            end
        end

        local function saveCurrentProfile()
            local name = ms.macroMeta and ms.macroMeta.name
            if not name or name == "" then
                ms.alert("Cannot save: current profile has no name.\nSet ms.macroMeta = { name = \"...\" } in your macros file.", 5)
                return
            end
            local folderName = sanitizeName(name)
            local existing = getProfiles()
            local found = false
            for _, p in ipairs(existing) do
                if p == folderName then found = true
                break end
            end
            if not found then
                ms.alert("No saved profile named \"" .. name .. "\" found.\nUse Save as New Profile instead.", 4)
                return
            end
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            local dst = profilesPath .. folderName .. "/ms_macros.lua"
            local _, st = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(dst))
            if st ~= true then
                ms.alert("Could not update profile.", 3)
                return
            end
            if hs.fs.attributes(jsonPath) then
                hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
            end
            if hs.fs.attributes(defaultPath) then
                hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
            end
            if hs.fs.attributes(themePath) then
                hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
            end
            -- Sounds travel with the profile too. Previously omitted, which
            -- silently dropped a profile's sound set on save and left switches
            -- promoting nothing (root cause of the lost theme+sounds recovery).
            local sndDst = profilesPath .. folderName .. "/sounds/"
            copyDirContents(SoundActiveDir, sndDst .. "active/")
            copyDirContents(SoundMacroDir,  sndDst .. "macro/")
            -- Visual macros, authored tools, and helper vars travel too.
            for _, cf in ipairs(profileContentFiles()) do
                if hs.fs.attributes(cf.live) then
                    hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(profilesPath .. folderName .. "/" .. cf.name))
                end
            end
            -- A profile is a collection of component packs. Capture the live slice
            -- of each kind into a profile-named library pack (overwriting in place),
            -- mark it active, and record the links in packs.json — so the shelves
            -- show the profile's own packs as active and a later switch restores
            -- them explicitly (not by fragile fingerprint). This is the explicit
            -- save the "don't auto-save on hotswap" model defers to.
            if ms.package and ms.package.libraryCapture and ms.package.setProfilePacks then
                local refs = {}
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    local rec = ms.package.libraryCapture(k, name)
                    if rec and rec.slug then refs[k] = rec.slug end
                end
                pcall(ms.package.setProfilePacks, folderName, refs)
                if ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end
            ms.playSlot("update")
            ms._profilesDirty = true
            ms.ui.markDirty()
            ms.ui.refresh()
            hs.timer.doAfter(0.2, function()
                ms.alert("Profile \"" .. name .. "\" updated.", 3, true)
            end)
        end

        -- Rewrite the name field inside a macros file's ms.macroMeta table, so a
        -- renamed profile's credits (and the name saveCurrentProfile looks up)
        -- stay in step with its folder. Scoped to the first name= after
        -- macroMeta; strips quotes/backslashes from the value so the result is
        -- always valid, auditable Lua.
        local function rewriteMacroMetaName(path, newName)
            local f = io.open(path, "r")
            if not f then return false end
            local src = f:read("*all"); f:close()
            local i = src:find("macroMeta")
            if not i then return false end
            local safe = tostring(newName):gsub('[\\"]', "")
            local repl = "name%1\"" .. (safe:gsub("%%", "%%%%")) .. "\""
            local head, tail = src:sub(1, i - 1), src:sub(i)
            local newTail, n = tail:gsub('name(%s*=%s*)"[^"]*"', repl, 1)
            if n == 0 then return false end
            local g = io.open(path, "w")
            if not g then return false end
            g:write(head .. newTail); g:close()
            return true
        end

        -- Rename a profile: its folder, its live/stored macros credit, and its
        -- three same-named packs (so the alignment slug follows). Works for the
        -- active profile (whose files are live) and inactive ones alike.
        local function renameProfile(oldName, newName)
            local oldFolder = sanitizeName(oldName or "")
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            local newFolder = sanitizeName(newName)
            if oldFolder == "" or newFolder == "" then
                ms.alert("Rename failed: invalid name.", 4)
                return
            end
            if newFolder ~= oldFolder then
                for _, p in ipairs(getProfiles()) do
                    if p == newFolder then
                        ms.alert("A profile named \"" .. newFolder .. "\" already exists.", 4)
                        return
                    end
                end
            end

            local activeName = ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
            local isActive = (oldFolder == activeName)

            if isActive then
                rewriteMacroMetaName(macrosPath, newFolder)
                ms.macroMeta = ms.macroMeta or {}
                ms.macroMeta.name = newFolder
            end
            if newFolder ~= oldFolder and hs.fs.attributes(profilesPath .. oldFolder) then
                os.rename(profilesPath .. oldFolder, profilesPath .. newFolder)
            end
            if not isActive then
                rewriteMacroMetaName(profilesPath .. newFolder .. "/ms_macros.lua", newFolder)
            end

            -- Keep the profile's same-named packs aligned (slug follows the
            -- folder). Pass newFolder so the pack slug derives from the same
            -- sanitized base the alignment check uses.
            if ms.package and ms.package.libraryRenameEntry and ms.package.librarySlug then
                for _, k in ipairs({ "macro", "theme", "sound" }) do
                    pcall(ms.package.libraryRenameEntry, k,
                        ms.package.librarySlug(oldFolder), newFolder)
                end
            end

            -- Carry the active-profile marker to the new name if this was the
            -- profile the live setup is on, so it stays "Active" after a rename.
            if ms.package and ms.package.getActiveProfile and ms.package.setActiveProfile then
                local cur = ms.package.getActiveProfile()
                if cur and sanitizeName(cur) == oldFolder then
                    pcall(ms.package.setActiveProfile, newFolder)
                end
            end

            ms._profilesDirty = true
            ms.playSlot("update")
            ms.alert("Renamed to \"" .. newFolder .. "\".", 3, true)
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
                if ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "macro", "theme", "sound" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end
        end
        ms.renameProfile = renameProfile

        local function exportProfilePkg()
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            local name = sanitizeName((ms.macroMeta and ms.macroMeta.name) or "unnamed")
            local outName = name .. ".mspkg"
            local outPath = os.getenv("HOME") .. "/Downloads/" .. outName
            local tmpDir  = archivePath .. "mspkg_export/"
            os.execute("mkdir -p " .. sq(archivePath))
            os.execute("rm -rf " .. sq(tmpDir))
            os.execute("mkdir -p " .. sq(tmpDir))
            local _, cpOk = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(tmpDir .. "ms_macros.lua"))
            if not hs.fs.attributes(tmpDir .. "ms_macros.lua") then
                ms.alert("Export failed: could not read ms_macros.lua.", 4)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            if hs.fs.attributes(jsonPath) then
                hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(tmpDir .. "ms_settings.json"))
            end
            if hs.fs.attributes(defaultPath) then
                hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(tmpDir .. "ms_settings_default.json"))
            end
            if hs.fs.attributes(themePath) then
                hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(tmpDir .. "ms_theme.json"))
            end
            -- Visual macros, authored tools, and helper vars travel with the
            -- profile package too, matching ms.package.collect.
            for _, cf in ipairs(profileContentFiles()) do
                if hs.fs.attributes(cf.live) then
                    hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(tmpDir .. cf.name))
                end
            end
            local soundsDir = tmpDir .. "sounds/"
            local soundsCopied = 0
            local bundledPaths = {}
            for _, soundName in pairs(ms.soundAssign or {}) do
                if type(soundName) == "string" and ms.sounds then
                    local soundPath = ms.sounds[soundName]
                    if soundPath and hs.fs.attributes(soundPath) then
                        local filename = soundPath:match("([^/\\]+)$")
                        local subdir = ""
                        pcall(function()
                            if soundPath:sub(1, #SoundActiveDir) == SoundActiveDir then
                                subdir = "active/"
                            elseif soundPath:sub(1, #SoundDefaultsDir) == SoundDefaultsDir then
                                subdir = "defaults/"
                            end
                        end)
                        local relPath = subdir .. filename
                        if filename and not bundledPaths[relPath] then
                            local destDir = soundsDir .. subdir
                            os.execute("mkdir -p " .. sq(destDir))
                            hs.execute("/bin/cp " .. sq(soundPath) .. " " .. sq(destDir .. filename))
                            bundledPaths[relPath] = true
                            soundsCopied = soundsCopied + 1
                        end
                    end
                end
            end
            local macroCopied = 0
            local usedMacroSounds = {}
            for _, soundName in pairs(ms.soundAssign or {}) do
                if type(soundName) == "string" and ms.macroSounds and ms.macroSounds[soundName] then
                    usedMacroSounds[soundName] = ms.macroSounds[soundName]
                end
            end
            for _, soundPath in pairs(usedMacroSounds) do
                if hs.fs.attributes(soundPath) then
                    local filename = soundPath:match("([^/\\]+)$")
                    local relPath = "macro/" .. filename
                    if filename and not bundledPaths[relPath] then
                        local destDir = soundsDir .. "macro/"
                        os.execute("mkdir -p " .. sq(destDir))
                        hs.execute("/bin/cp " .. sq(soundPath) .. " " .. sq(destDir .. filename))
                        bundledPaths[relPath] = true
                        macroCopied = macroCopied + 1
                    end
                end
            end
            local fontsCopied = 0
            do
                local fontName = (ms._theme and ms._theme.font) or nil
                if type(fontName) == "string" and #fontName > 0 and not fontName:find("[/\\]") then
                    local fontsSrc = hs.configdir .. "/ui/fonts/"
                    if hs.fs.attributes(fontsSrc) then
                        local fontsDir = tmpDir .. "fonts/"
                        local pattern = fontName:lower():gsub("%-", "%%-")
                        for file in hs.fs.dir(fontsSrc) do
                            if file ~= "." and file ~= ".." then
                                local lower = file:lower()
                                if lower:match("^" .. pattern) and (lower:match("%.ttf$") or lower:match("%.otf$")) then
                                    os.execute("mkdir -p " .. sq(fontsDir))
                                    hs.execute("/bin/cp " .. sq(fontsSrc .. file) .. " " .. sq(fontsDir .. file))
                                    fontsCopied = fontsCopied + 1
                                end
                            end
                        end
                    end
                end
            end
            hs.execute("cd " .. sq(tmpDir) .. " && zip -r " .. sq(outPath) .. " . 2>/dev/null")
            os.execute("rm -rf " .. sq(tmpDir))
            if hs.fs.attributes(outPath) then
                ms.playSlot("alert")
                local msg = "Exported " .. outName .. " to ~/Downloads/"
                if soundsCopied > 0 then
                    msg = msg .. "\n" .. soundsCopied .. " sound" .. (soundsCopied > 1 and "s" or "") .. " bundled."
                end
                if macroCopied > 0 then
                    msg = msg .. "\n" .. macroCopied .. " macro sound" .. (macroCopied > 1 and "s" or "") .. " bundled."
                end
                if fontsCopied > 0 then
                    msg = msg .. "\n" .. fontsCopied .. " font" .. (fontsCopied > 1 and "s" or "") .. " bundled."
                end
                ms.alert(msg, 5, true)
            else
                ms.alert("Export failed: could not create " .. outName .. ".", 4)
            end
        end

        local function importProfilePkg()
            hs.focus()
            local result = hs.dialog.chooseFileOrFolder(
                "Select a .mspkg profile package to import",
                os.getenv("HOME") .. "/Downloads/",
                true, false, false, {
                    "mspkg",
                    "zip",
                }
            )
            local target = hs.application.get(ms._targetApp)
            local selectedPath
            for _, v in pairs(result or {}) do
                if type(v) == "string" then selectedPath = v
                break end
            end
            if not selectedPath then
                if target then pcall(function() target:activate() end) end
                return
            end
            local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
            local tmpDir = archivePath .. "mspkg_import/"
            os.execute("mkdir -p " .. sq(archivePath))
            os.execute("rm -rf " .. sq(tmpDir))
            os.execute("mkdir -p " .. sq(tmpDir))
            hs.execute("unzip -o " .. sq(selectedPath) .. " -d " .. sq(tmpDir) .. " 2>/dev/null")
            local baseDir = tmpDir
            local macroSrc = tmpDir .. "ms_macros.lua"
            if not hs.fs.attributes(macroSrc) then
                local found = false
                for entry in hs.fs.dir(tmpDir) do
                    if entry ~= "." and entry ~= ".." then
                        local sub = tmpDir .. entry .. "/"
                        if hs.fs.attributes(sub) and hs.fs.attributes(sub .. "ms_macros.lua") then
                            baseDir = sub
                            macroSrc = sub .. "ms_macros.lua"
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    for entry in hs.fs.dir(tmpDir) do
                        if entry ~= "." and entry ~= ".." then
                            local sub = tmpDir .. entry .. "/"
                            if hs.fs.attributes(sub) and hs.fs.attributes(sub .. "ms_settings.json") then
                                baseDir = sub
                                found = true
                                break
                            end
                        end
                    end
                    if not found and hs.fs.attributes(tmpDir .. "ms_settings.json") then
                        baseDir = tmpDir
                        found = true
                    end
                    if found then
                        local zipName = selectedPath:match("([^/]+)%.mspkg$") or selectedPath:match("([^/]+)%.zip$") or "imported"
                        local folderName = sanitizeName(zipName)
                        hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                        local settingsSrc = baseDir .. "ms_settings.json"
                        if hs.fs.attributes(settingsSrc) then
                            hs.execute("/bin/cp " .. sq(settingsSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                        end
                        local defSrc = baseDir .. "ms_settings_default.json"
                        if hs.fs.attributes(defSrc) then
                            hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                        end
                        local themeSrc = baseDir .. "ms_theme.json"
                        if hs.fs.attributes(themeSrc) then
                            hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                        end
                        if target then pcall(function() target:activate() end) end
                        ms.alert("Imported settings as \"" .. zipName .. "\".\n(no macros in package)", 4)
                        os.execute("rm -rf " .. sq(tmpDir))
                        return
                    end
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import failed: package does not contain ms_macros.lua or ms_settings.json.", 5)
                    os.execute("rm -rf " .. sq(tmpDir))
                    return
                end
            end
            local mf = io.open(macroSrc, "rb")
            if not mf then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import failed: could not read ms_macros.lua from package.", 4)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local content = mf:read("*all")
            mf:close()
            local auditErrs = auditMacros(content)
            if #auditErrs > 0 then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 " .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local meta = readMacroMeta(macroSrc)
            if not meta or not meta.name or meta.name == "" then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import failed: could not read profile name from ms_macros.lua.", 5)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local folderName = sanitizeName(meta.name)

            local function _commit()
                hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                local dst = profilesPath .. folderName .. "/ms_macros.lua"
                local copied = false
                local gf = io.open(dst, "wb")
                if gf then gf:write(content)
                gf:close()
                copied = true end
                if not copied then
                    local _, st = hs.execute("/bin/cp " .. sq(macroSrc) .. " " .. sq(dst))
                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                end
                if not copied then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import failed: could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                    os.execute("rm -rf " .. sq(tmpDir))
                    return
                end
                local settingsSrc = baseDir .. "ms_settings.json"
                if hs.fs.attributes(settingsSrc) then
                    hs.execute("/bin/cp " .. sq(settingsSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                end
                local defSrc = baseDir .. "ms_settings_default.json"
                if hs.fs.attributes(defSrc) then
                    hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                end
                local themeSrc = baseDir .. "ms_theme.json"
                if hs.fs.attributes(themeSrc) then
                    hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                end
                local soundsAdded = {}
                local macroAdded = {}
                local _sndDirPrefix = {
                    [SoundDefaultsDir] = "d_",
                    [SoundActiveDir]   = "a_",
                    [SoundMacroDir]    = "m_",
                }
                local _sndVariantSlots = 3
                local _sndConflicts = {}

                local function _readFile(path)
                    local f = io.open(path, "rb")
                    if not f then return nil end
                    local d = f:read("*all")
                    f:close()
                    return d
                end
                local function _writeFile(path, data)
                    local f = io.open(path, "wb")
                    if not f then return false end
                    f:write(data)
                    f:close()
                    return true
                end

                local function _placeSnd(srcSnd, dstDir, file, added)
                    if hs.fs.attributes(srcSnd, "mode") ~= "file" then return end
                    if not hs.fs.attributes(dstDir) then
                        hs.execute("mkdir -p " .. sq(dstDir))
                    end
                    local pfx  = _sndDirPrefix[dstDir]
                    local stem = file:match("^(.+)%.[^%.]+$") or file
                    local ext  = file:match("%.([^%.]+)$")
                    ext = ext and ("." .. ext) or ""
                    if pfx and stem:sub(1, #pfx) ~= pfx then stem = pfx .. stem end
                    local base = stem:match("^(.-)%d+$") or stem

                    local function slotName(i)
                        return base .. (i > 1 and tostring(i) or "") .. ext
                    end

                    local data = _readFile(srcSnd)
                    if not data then return end

                    local free
                    for i = 1, _sndVariantSlots do
                        local p = dstDir .. slotName(i)
                        if not hs.fs.attributes(p) then
                            free = free or i
                        elseif _readFile(p) == data then
                            return
                        end
                    end
                    if free then
                        local name = slotName(free)
                        if _writeFile(dstDir .. name, data) then
                            table.insert(added, name:match("^(.+)%.[^%.]+$") or name)
                        end
                    else
                        table.insert(_sndConflicts, {
                            data = data,
                            dir = dstDir,
                            base = base,
                            ext = ext,
                            added = added,
                        })
                    end
                end

                local function _importSndDir(srcDir, dstDir, added)
                    if not hs.fs.attributes(srcDir) then return end
                    for file in hs.fs.dir(srcDir) do
                        if file ~= "." and file ~= ".." then
                            _placeSnd(srcDir .. file, dstDir, file, added)
                        end
                    end
                end
                local soundsDir = baseDir .. "sounds/"
                if hs.fs.attributes(soundsDir) then
                    local hasSubdirs = hs.fs.attributes(soundsDir .. "active/")
                        or hs.fs.attributes(soundsDir .. "defaults/")
                        or hs.fs.attributes(soundsDir .. "macro/")
                    if hasSubdirs then
                        _importSndDir(soundsDir .. "active/",   SoundActiveDir,   soundsAdded)
                        pcall(function() _importSndDir(soundsDir .. "defaults/", SoundDefaultsDir, soundsAdded) end)
                        _importSndDir(soundsDir .. "macro/",    SoundMacroDir,    macroAdded)
                    else
                        local hasSounds = false
                        local legacyFiles = {}
                        for file in hs.fs.dir(soundsDir) do
                            if file ~= "." and file ~= ".." then
                                if hs.fs.attributes(soundsDir .. file, "mode") == "file" then
                                    hasSounds = true
                                    table.insert(legacyFiles, file)
                                end
                            end
                        end
                        if hasSounds then
                            for _, f in ipairs(legacyFiles) do
                                local name = f:match("^(.+)%.[^%.]+$") or f
                                local dest = SoundActiveDir
                                if name:sub(1, 2) == "d_" then
                                    dest = SoundDefaultsDir
                                elseif name:sub(1, 2) == "m_" then
                                    dest = SoundMacroDir
                                elseif name:sub(1, 2) == "a_" then
                                    dest = SoundActiveDir
                                end
                                local added = (dest == SoundMacroDir) and macroAdded or soundsAdded
                                _placeSnd(soundsDir .. f, dest, f, added)
                            end
                        end
                    end
                end
                local macroSrc = baseDir .. "macro/"
                if hs.fs.attributes(macroSrc) then
                    _importSndDir(macroSrc, SoundMacroDir, macroAdded)
                end
                if #soundsAdded > 0 or #macroAdded > 0 then
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                end

                local function _resolveSndConflicts(idx)
                    local c = _sndConflicts[idx]
                    if not c then
                        if idx > 1 then
                            ms.saveSettings()
                            ms._soundsDirty = true
                            ms._discoverSounds()
                            ms.ui.refresh()
                        end
                        return
                    end
                    local slots = {}
                    for i = 1, _sndVariantSlots do
                        slots[#slots + 1] = "  " .. i .. ". "
                            .. c.base .. (i > 1 and tostring(i) or "")
                    end
                    ms.ui.prompt({
                        title   = "Replace a Sound Variant?",
                        msg     = "\"" .. c.base .. "\" already has "
                            .. _sndVariantSlots .. " variants:\n"
                            .. table.concat(slots, "\n")
                            .. "\n\nEnter 1-" .. _sndVariantSlots
                            .. " to replace one, or cancel to skip this sound:",
                        confirm = "Replace",
                        cancel  = "Skip",
                        default = "",
                    }, function(r)
                        local n = r.confirmed and tonumber(r.value)
                        if n and n >= 1 and n <= _sndVariantSlots then
                            local name = c.base .. (n > 1 and tostring(n) or "") .. c.ext
                            if _writeFile(c.dir .. name, c.data) then
                                table.insert(c.added, name:match("^(.+)%.[^%.]+$") or name)
                            end
                        elseif r.confirmed then
                            ms.alert("Invalid slot, skipped \"" .. c.base .. "\".", 2)
                        end
                        _resolveSndConflicts(idx + 1)
                    end)
                end
                if #_sndConflicts > 0 then _resolveSndConflicts(1) end
                local fontsAdded = 0
                do
                    local fontsDir = baseDir .. "fonts/"
                    if hs.fs.attributes(fontsDir) then
                        local dstDir = os.getenv("HOME") .. "/Library/Fonts/"
                        hs.fs.mkdir(dstDir)
                        for file in hs.fs.dir(fontsDir) do
                            if file ~= "." and file ~= ".." then
                                local ext = file:match("%.([^%.]+)$")
                                if ext == "ttf" or ext == "otf" or ext == "woff" or ext == "woff2" then
                                    local srcFont = fontsDir .. file
                                    local dstFont = dstDir .. file
                                    if not hs.fs.attributes(dstFont) then
                                        local ff = io.open(srcFont, "rb")
                                        if ff then
                                            local fdata = ff:read("*all")
                                            ff:close()
                                            local of = io.open(dstFont, "wb")
                                            if of then of:write(fdata)
                                            of:close()
                                            fontsAdded = fontsAdded + 1 end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                os.execute("rm -rf " .. sq(tmpDir))
                if target then pcall(function() target:activate() end) end
                ms.playSlot("update")
                hs.timer.doAfter(0.2, function()
                    local msg = "\"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles."
                    if #soundsAdded > 0 then
                        msg = msg .. "\n" .. #soundsAdded .. " sound" .. (#soundsAdded > 1 and "s" or "") .. " added to library."
                    end
                    if #macroAdded > 0 then
                        msg = msg .. "\n" .. #macroAdded .. " macro sound" .. (#macroAdded > 1 and "s" or "") .. " added."
                    end
                    if fontsAdded > 0 then
                        msg = msg .. "\n" .. fontsAdded .. " font" .. (fontsAdded > 1 and "s" or "") .. " installed."
                    end
                    ms.alert(msg, 6, true)
                    ms._profilesDirty = true
                    ms.ui.markDirty()
                    ms.ui.refresh()
                end)
            end

            if hs.fs.attributes(profilesPath .. folderName) then
                ms.ui.modal({
                    title   = "Overwrite Profile?",
                    msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this package?",
                    confirm = "Replace",
                    cancel  = "Cancel",
                }, function(r)
                    if r.confirmed then
                        _commit()
                    else
                        os.execute("rm -rf " .. sq(tmpDir))
                        if target then pcall(function() target:activate() end) end
                    end
                end)
            else
                _commit()
            end
        end

        -- The profile the live setup is "on". Read from the explicit marker a
        -- profile switch records (ms.package.setActiveProfile), NOT inferred from
        -- the three pack markers — those are named per-pack and rarely share the
        -- profile's slug, so the old all-three-must-match rule left every profile
        -- reading as unaligned. A manual single-pack hotswap clears the marker
        -- (the live state is then a custom mix, no profile). Validated against
        -- the profiles that still exist so a stale marker can't claim a deleted
        -- profile. Returns the profile folder name, or "" when nothing is active.
        local function alignedProfile()
            if not (ms.package and ms.package.getActiveProfile) then return "" end
            local active = ms.package.getActiveProfile()
            if not active or active == "" then return "" end
            active = sanitizeName(active)
            for _, p in ipairs(getProfiles()) do
                if p == active then return p end
            end
            return ""
        end

        ms.sanitizeName       = sanitizeName
        ms.getProfiles        = getProfiles
        ms.alignedProfile     = alignedProfile
        ms.switchProfile      = switchProfile
        ms.importProfile      = importProfile
        ms.importProfilePkg   = importProfilePkg
        ms.exportProfilePkg   = exportProfilePkg
        ms.createNewProfile   = createNewProfile
        ms.saveCurrentProfile = saveCurrentProfile
    -- END Profile Management --

    -- System Integrity --
        ms.integrity = {}

        local _integrityFiles = nil
        ms.integrity.trackedFiles = function()
            if _integrityFiles then return _integrityFiles end
            local hsDir = os.getenv("HOME") .. "/.hammerspoon/"
            _integrityFiles = { hsDir .. "ms_core.lua" }
            local spoonDir = hsDir .. "Spoons/"
            local ok, iter, dir_obj = pcall(hs.fs.dir, spoonDir)
            if ok and iter then
                for entry in iter, dir_obj do
                    if entry ~= "." and entry ~= ".." then
                        local init = spoonDir .. entry .. "/init.lua"
                        if hs.fs.attributes(init) then
                            _integrityFiles[#_integrityFiles + 1] = init
                        end
                    end
                end
                dir_obj:close()
            end
            table.sort(_integrityFiles)
            return _integrityFiles
        end

        ms.integrity.hashFile = function(path)
            local escaped = "'" .. path:gsub("'", "'\\''") .. "'"
            local out = hs.execute("shasum -a 256 " .. escaped .. " 2>/dev/null")
            if out and #out >= 64 then return out:sub(1, 64):lower() end
            return nil
        end

        ms.integrity.readTrustedManifest = function()
            local f = io.open(trustedHashPath, "r")
            if not f then return nil end
            local raw = f:read("*all")
            f:close()
            if not raw or raw == "" then return nil end

            local single = raw:match("^%s*([0-9a-fA-F]+)%s*$")
            if single and #single == 64 then
                return { ["ms_core.lua"] = single:lower() }
            end

            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then
                local norm = {}
                for k, v in pairs(tbl) do
                    if type(v) == "string" and #v == 64 then
                        local rel = k:gsub(".*/%.hammerspoon/", "")
                        norm[rel] = v:lower()
                    end
                end
                return next(norm) and norm or nil
            end

            return nil
        end

        ms.integrity.writeTrustedManifest = function(manifest)
            local ok, json = pcall(hs.json.encode, manifest)
            if not ok then
                ms.dev.log({
                    type = "error",
                    event = "hash_seed_failed",
                })
                return false
            end
            local f = io.open(trustedHashPath, "w")
            if f then
                f:write(json .. "\n")
                f:close()
                local n = 0
                for _ in pairs(manifest) do n = n + 1 end
                ms.dev.log({
                    type    = "system",
                    event   = "manifest_seeded",
                    files   = n,
                })
                return true
            end
            ms.dev.log({
                type = "error",
                event = "hash_seed_failed",
            })
            return false
        end

        ms.integrity.readTrustedHash = function()
            local m = ms.integrity.readTrustedManifest()
            return m and m["ms_core.lua"] or nil
        end

        ms.integrity.writeTrustedHash = function(hash)
            return ms.integrity.writeTrustedManifest({ ["ms_core.lua"] = hash })
        end

        ms.integrity.deleteTrustedHash = function()
            return os.remove(trustedHashPath) ~= nil
        end

        local _intCache         = {
            status  = nil,
            details = nil,
            t       = 0,
        }
        local _intHashInProgress = false

        ms.integrity.invalidateCache = function()
            _intCache.t = 0
            ms.dev.log({
                type = "system",
                event = "integrity_cache_invalidated",
            })
        end

        ms.integrity.check = function()
            local now = os.time()
            if _intCache.status ~= nil and (now - _intCache.t) < 60 then
                local d = _intCache.details and _intCache.details["ms_core.lua"]
                return _intCache.status, d and d.cur, d and d.trusted
            end
            if _intHashInProgress then
                local d = _intCache.details and _intCache.details["ms_core.lua"]
                return _intCache.status or "uninitialized", d and d.cur, d and d.trusted
            end

            _intHashInProgress = true
            local files = ms.integrity.trackedFiles()
            local trusted = ms.integrity.readTrustedManifest()
            local details = {}
            local allOk = true
            local anyMismatch = false
            local pending = #files
            local done = false

            if pending == 0 then
                _intHashInProgress = false
                _intCache = {
                    status = "uninitialized",
                    details = {},
                    t = now,
                }
                return "uninitialized"
            end

            for _, absPath in ipairs(files) do
                local rel = absPath:gsub(".*/%.hammerspoon/", "")
                local _t = hs.task.new("/usr/bin/shasum", function(_, out, _)
                    local cur = (out and #out >= 64) and out:sub(1, 64):lower() or nil
                    local tru = trusted and trusted[rel] or nil
                    local fileStatus
                    if not tru then
                        fileStatus = "unknown"
                    elseif cur == tru then
                        fileStatus = "ok"
                    else
                        fileStatus = "mismatch"
                        anyMismatch = true
                        allOk = false
                    end
                    details[rel] = {
                        cur = cur,
                        trusted = tru,
                        status = fileStatus,
                    }

                    pending = pending - 1
                    if pending == 0 and not done then
                        done = true
                        _intHashInProgress = false
                        local status
                        if not trusted then
                            status = "uninitialized"
                        elseif anyMismatch then
                            status = "mismatch"
                        else
                            status = "trusted"
                        end
                        _intCache = {
                            status  = status,
                            details = details,
                            t       = os.time(),
                        }
                        ms.dev.log({
                            type    = "system",
                            event   = "integrity_check",
                            status  = status,
                            files   = #files,
                            matched = not anyMismatch,
                        })
                        if status == "mismatch" then hs.reload() end
                    end
                end, {
                    "-a",
                    "256",
                    absPath,
                })
                if _t then
                    _t:start()
                else
                    details[rel] = {
                        cur = nil,
                        trusted = trusted and trusted[rel] or nil,
                        status = "error",
                    }
                    allOk = false
                    pending = pending - 1
                end
            end

            return _intCache.status or "uninitialized"
        end

        ms.integrity.trustCurrent = function()
            local files = ms.integrity.trackedFiles()
            local manifest = {}
            local failed = false
            for _, absPath in ipairs(files) do
                local hash = ms.integrity.hashFile(absPath)
                if not hash then
                    failed = true
                    break
                end
                local rel = absPath:gsub(".*/%.hammerspoon/", "")
                manifest[rel] = hash
            end
            if failed then
                ms.alert("System integrity: could not hash one or more files.", 4)
                return false
            end
            if ms.integrity.writeTrustedManifest(manifest) then
                ms.integrity.invalidateCache()
                local n = 0
                for _ in pairs(manifest) do n = n + 1 end
                ms.alert("Trusted manifest saved.\n" .. n .. " files sealed.", 4, true)
                return true
            end
            ms.alert("System integrity: could not write trusted manifest.", 4)
            return false
        end


        local function _applyBundleUpdate(bundleDir, timestamp)
            local hsDir = os.getenv("HOME") .. "/.hammerspoon/"

            local topDir = nil
            local dh = io.popen("ls -d '" .. bundleDir .. "'/mudscript-* 2>/dev/null | head -1")
            if dh then topDir = dh:read("*l")
            dh:close() end
            if not topDir or topDir == "" then
                topDir = bundleDir
            end
            if not topDir:match("/$") then topDir = topDir .. "/" end

            -- Wholesale-replaceable install artifacts. These MUST mirror what a
            -- fresh install.sh lays down: install copies the entire bundle, so an
            -- update that omits any of these leaves a stale copy against the new
            -- ms_core.lua. `lib` was missing here — an update shipped the new core
            -- against the OLD lib/ (e.g. ms_core calling _loadAuthoredMenus() that
            -- only the new ms_settings.lua defines), crashing on reload. `templates`
            -- had the same latent gap. User data (ms_macros.lua, profiles) stays in
            -- templateList so it is never clobbered.
            local replaceList = {
                "ms_core.lua",
                "init.lua",
                "lib",
                "templates",
                "ui",
                "bin",
                "Spoons",
            }
            local templateList = {
                "ms_macros.lua",
                "profiles/Default",
            }

            os.execute("mkdir -p '" .. archivePath .. "'")

            for _, name in ipairs(replaceList) do
                local src = topDir .. name
                local dst = hsDir .. name
                if hs.fs.attributes(src) then
                    if hs.fs.attributes(dst) then
                        local safeName = name:gsub("/", "_")
                        local bak = archivePath .. safeName .. "_" .. timestamp
                            .. (hs.fs.attributes(dst).mode == "directory" and ".d.bak" or ".bak")
                        os.execute("rm -rf '" .. bak .. "'")
                        os.execute("cp -R '" .. dst .. "' '" .. bak .. "'")
                    end
                    os.execute("rm -rf '" .. dst .. "'")
                    os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                end
            end

            local _fmSrc = topDir .. "data/.ms_file_manifest.json"
            local _fmDst = hsDir .. "data/.ms_file_manifest.json"
            if hs.fs.attributes(_fmSrc) then
                os.execute("mkdir -p '" .. hsDir .. "data'")
                os.execute("cp '" .. _fmSrc .. "' '" .. _fmDst .. "'")
            end

            local _mfSrc = topDir .. "MANIFEST.json"
            local _mfDst = hsDir .. "MANIFEST.json"
            if hs.fs.attributes(_mfSrc) then
                os.execute("cp '" .. _mfSrc .. "' '" .. _mfDst .. "'")
            end

            for _, name in ipairs(templateList) do
                local src = topDir .. name
                local dst = hsDir .. name
                if hs.fs.attributes(src) and not hs.fs.attributes(dst) then
                    os.execute("mkdir -p '" .. dst:match("(.+)/[^/]+$") .. "'")
                    os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                end
            end

            return true
        end

        local function _verifySignature(manifest)
            if not manifest.signature or manifest.signature == ""
                or not ms._updatePublicKey
                or ms._updatePublicKey:find("PLACEHOLDER") then
                return true
            end
            local _tmpDir  = archivePath
            local _keyPath = _tmpDir .. "upd_pub.pem"
            local _sigPath = _tmpDir .. "upd_sig.bin"
            local _msgPath = _tmpDir .. "upd_msg.bin"
            os.execute("mkdir -p '" .. _tmpDir .. "'")
            local _keyContent = ms._updatePublicKey
                :gsub("^[%s\n]+", "")
                :gsub("\n[%s]+", "\n")
                :gsub("[%s]+$", "\n")
            local _kf = io.open(_keyPath, "w")
            if _kf then _kf:write(_keyContent)
            _kf:close() end
            local _sf = io.open(_sigPath .. ".b64", "w")
            if _sf then _sf:write(manifest.signature)
            _sf:close() end
            hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
            os.remove(_sigPath .. ".b64")
            local _signTarget = manifest.bundle and manifest.bundle.sha256 or manifest.sha256
            local _mf = io.open(_msgPath, "w")
            if _mf then _mf:write(_signTarget:lower())
            _mf:close() end
            local _out, _ok = hs.execute(
                "openssl dgst -sha256 -verify '" .. _keyPath ..
                "' -signature '" .. _sigPath ..
                "' '" .. _msgPath .. "' 2>&1"
            )
            os.remove(_keyPath)
            os.remove(_sigPath)
            os.remove(_msgPath)
            if not _ok then
                ms.dev.log({
                    type   = "error",
                    event  = "signature_failed",
                    output = tostring(_out),
                })
                ms.alert("Update aborted: signature verification failed.\n" .. tostring(_out), 12)
                return false
            end
            ms.dev.log({
                type = "system",
                event = "signature_verified",
            })
            return true
        end

        -- Version comparison helpers (used by _fetchReleaseInfo and check functions) --
        local function _parseVersion(v)
            local t = {}
            if type(v) == "string" then
                local base = v:match("^[%d%.]+")
                if base then
                    for n in base:gmatch("%d+") do t[#t + 1] = tonumber(n) or 0 end
                end
                t._pre = v:find("%-pre") ~= nil or v:find("%-beta") ~= nil
                    or v:find("%-rc") ~= nil
                local preNum = v:match("%-pre%.(%d+)")
                t._preNum = preNum and tonumber(preNum) or 0
            end
            return t
        end

        local function _remoteIsNewer(localV, remoteV)
            local a, b = _parseVersion(localV), _parseVersion(remoteV)
            local len = math.max(#a, #b)
            for i = 1, len do
                local la, ra = a[i] or 0, b[i] or 0
                if ra > la then return true  end
                if ra < la then return false end
            end
            if a._pre and not b._pre then return true  end
            if not a._pre and b._pre then return false end
            if a._pre and b._pre then
                return (b._preNum or 0) > (a._preNum or 0)
            end
            return false
        end
        -- END Version comparison helpers --

        -- _fetchReleaseInfo [GitHub Releases API helper] --
        local function _fetchReleaseInfo(channel, callback)
            local repo = ms._testingRepo or "mudbourn/mudscript"
            local apiURL
            if channel == "stable" then
                apiURL = "https://api.github.com/repos/" .. repo .. "/releases/latest"
            else
                apiURL = "https://api.github.com/repos/" .. repo .. "/releases?per_page=5"
            end
            hs.http.asyncGet(apiURL, {
                ["Accept"] = "application/vnd.github+json",
            }, function(code, body, _)
                if code ~= 200 or not body then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_fetch_failed",
                        channel = channel,
                        code    = code,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local ok, data = pcall(hs.json.decode, body)
                if not ok or not data then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local release
                if channel == "stable" then
                    release = data
                else
                    if type(data) ~= "table" or #data == 0 then
                        ms.dev.log({
                            type    = "error",
                            event   = "release_parse_failed",
                            channel = channel,
                            reason  = "empty_array",
                        })
                        if callback then pcall(callback, nil) end
                        return
                    end
                    release = data[1]
                    local bestIdx = 1
                    for i = 2, #data do
                        if _remoteIsNewer(
                            data[bestIdx].tag_name or "",
                            data[i].tag_name or ""
                        ) then
                            bestIdx = i
                        end
                    end
                    release = data[bestIdx]
                end
                if not release or not release.tag_name then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                        reason  = "no_tag",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local downloadUrl
                local assets = release.assets or {}
                for _, asset in ipairs(assets) do
                    if asset.name and asset.name:match("^mudscript%-macos%-.*%.zip$") then
                        downloadUrl = asset.browser_download_url
                        break
                    end
                end
                if not downloadUrl then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                        reason  = "no_asset",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local tagName = release.tag_name
                local version = tagName:gsub("^v", "")
                if callback then pcall(callback, {
                    version     = version,
                    downloadUrl = downloadUrl,
                    tagName     = tagName,
                }) end
            end)
        end
        -- END _fetchReleaseInfo --

        -- _fetchArtifactInfo [GitHub Actions artifact helper] --
        local function _fetchArtifactInfo(callback)
            local repo = ms._testingRepo or "mudbourn/mudscript"
            local workflow = ms._testingWorkflow or "testing"
            local token = ms._githubToken
            if not token or token == "" then
                local tokenPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token"
                local f = io.open(tokenPath, "r")
                if f then token = f:read("*l")
                f:close() end
                if token and token ~= "" then ms._githubToken = token end
            end
            if not token or token == "" then
                ms.dev.log({
                    type = "error",
                    event = "artifact_fetch_failed",
                    reason = "no_token",
                })
                if callback then pcall(callback, nil) end
                return
            end

            local baseVersion = "0.0.0"
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then
                        baseVersion = lm.version:gsub("%-pre[%.%-]%d+$", "")
                    end
                end
            end

            local runsURL = "https://api.github.com/repos/" .. repo
                .. "/actions/workflows/" .. workflow .. ".yml/runs?per_page=1&status=completed"
            local headers = {
                ["Accept"] = "application/vnd.github+json",
                ["Authorization"] = "Bearer " .. token,
            }
            hs.http.asyncGet(runsURL, headers, function(code, body, _)
                if code ~= 200 or not body then
                    ms.dev.log({
                        type = "error",
                        event = "artifact_fetch_failed",
                        reason = "runs_http",
                        code = code,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local ok, data = pcall(hs.json.decode, body)
                if not ok or not data or not data.workflow_runs or #data.workflow_runs == 0 then
                    if callback then pcall(callback, nil) end
                    return
                end
                local run = data.workflow_runs[1]
                local runId = run.id
                local runNumber = run.run_number

                local artURL = "https://api.github.com/repos/" .. repo
                    .. "/actions/runs/" .. runId .. "/artifacts"
                hs.http.asyncGet(artURL, headers, function(code2, body2, _)
                    if code2 ~= 200 or not body2 then
                        ms.dev.log({
                            type = "error",
                            event = "artifact_fetch_failed",
                            reason = "artifacts_http",
                            code = code2,
                        })
                        if callback then pcall(callback, nil) end
                        return
                    end
                    local ok2, artData = pcall(hs.json.decode, body2)
                    if not ok2 or not artData or not artData.artifacts then
                        if callback then pcall(callback, nil) end
                        return
                    end
                    for _, art in ipairs(artData.artifacts) do
                        if art.name and art.name:match("macos") then
                            local downloadURL = "https://api.github.com/repos/" .. repo
                                .. "/actions/artifacts/" .. art.id .. "/zip"
                            ms.dev.log({
                                type = "system",
                                event = "artifact_found",
                                name = art.name,
                                run = runNumber,
                            })
                            if callback then
                                pcall(callback, {
                                    version = baseVersion .. "-pre." .. runNumber,
                                    downloadUrl = downloadURL,
                                    headers = headers,
                                    format = "zip",
                                })
                            end
                            return
                        end
                    end
                    for _, art in ipairs(artData.artifacts) do
                        if art.name then
                            local downloadURL = "https://api.github.com/repos/" .. repo
                                .. "/actions/artifacts/" .. art.id .. "/zip"
                            if callback then
                                pcall(callback, {
                                    version = baseVersion .. "-pre." .. runNumber,
                                    downloadUrl = downloadURL,
                                    headers = headers,
                                    format = "zip",
                                })
                            end
                            return
                        end
                    end
                    ms.dev.log({
                        type = "error",
                        event = "artifact_fetch_failed",
                        reason = "no_artifact",
                    })
                    if callback then pcall(callback, nil) end
                end)
            end)
        end
        -- END _fetchArtifactInfo --

        -- Update [stable channel] --
        ms.integrity.update = function()
            ms.dev.log({
                type    = "system",
                event   = "update_start",
                channel = "stable",
            })
            ms.alert("Checking for stable update\xe2\x80\xa6", 4, true)
            _fetchReleaseInfo("stable", function(info)
                if not info then
                    ms.dev.log({
                        type   = "error",
                        event  = "update_failed",
                        reason = "release_fetch",
                    })
                    ms.alert("Update failed: could not fetch release info.", 5)
                    return
                end
                local newVersion = info.version
                local bundleURL  = info.downloadUrl
                ms.alert("Downloading v" .. newVersion .. " bundle\xe2\x80\xa6", 4, true)
                ms.dev.log({
                    type    = "system",
                    event   = "update_download_start",
                    version = newVersion,
                    format  = "bundle",
                })
                hs.http.asyncGet(bundleURL, nil, function(fCode, fBody, _)
                    if fCode ~= 200 or not fBody then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "download_http",
                            code    = fCode,
                            version = newVersion,
                        })
                        ms.alert("Update failed: bundle download returned " .. tostring(fCode) .. ".", 5)
                        return
                    end
                    os.execute("mkdir -p '" .. archivePath .. "'")
                    local isZip = bundleURL:match("%.zip$")
                    local tmpArchive = archivePath .. (isZip and "ms_bundle_update.zip" or "ms_bundle_update.tar.gz")
                    local tmpF = io.open(tmpArchive, "wb")
                    if not tmpF then
                        ms.alert("Update failed: could not write temp file.", 4)
                        return
                    end
                    tmpF:write(fBody)
                    tmpF:close()
                    local tmpExtract = archivePath .. "ms_bundle_extract/"
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    os.execute("mkdir -p '" .. tmpExtract .. "'")
                    local _, extractOk
                    if isZip then
                        _, extractOk = hs.execute("unzip -o '" .. tmpArchive .. "' -d '" .. tmpExtract .. "' 2>&1")
                    else
                        _, extractOk = hs.execute("tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1")
                    end
                    os.remove(tmpArchive)
                    if not extractOk then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "extract_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not extract bundle.", 5)
                        return
                    end
                    local manifestPath = tmpExtract .. "MANIFEST.json"
                    local topDir = nil
                    local dh = io.popen("ls -d '" .. tmpExtract .. "'/mudscript-* 2>/dev/null | head -1")
                    if dh then topDir = dh:read("*l")
                    dh:close() end
                    if topDir and topDir ~= "" then
                        if not topDir:match("/$") then topDir = topDir .. "/" end
                        local altManifest = topDir .. "MANIFEST.json"
                        if hs.fs.attributes(altManifest) then manifestPath = altManifest end
                    end
                    local manifest = nil
                    local mf = io.open(manifestPath, "r")
                    if mf then
                        local ok, m = pcall(hs.json.decode, mf:read("*all"))
                        mf:close()
                        if ok then manifest = m end
                    end
                    if manifest and not _verifySignature(manifest) then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        return
                    end
                    local timestamp = os.date("%Y-%m-%d_%H%M")
                    ms._updateInProgress = true
                    os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                    local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                    if _sp then _sp:close() end
                    local ok = _applyBundleUpdate(tmpExtract, timestamp)
                    ms._updateInProgress = false
                    os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if not ok then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "apply_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not apply bundle.", 5)
                        return
                    end
                    ms.dev.log({
                        type    = "system",
                        event   = "update_applied",
                        version = newVersion,
                        format  = "bundle",
                    })
                    ms.integrity.trustCurrent()
                    ms.integrity.invalidateCache()
                    ms.alert("Updated to v" .. newVersion .. ".\\nReloading in 3 seconds\\xe2\\x80\\xa6", 5, true)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end)
            end)
        end
        -- END Update --

        -- Update Beta [testing channel] --
        ms.integrity.updateBeta = function()
            ms.dev.log({
                type    = "system",
                event   = "update_start",
                channel = "testing",
                source  = ms._testingSource or "release",
            })
            ms.alert("Checking for testing update\\xe2\\x80\\xa6", 4, true)

            local fetchFn = (ms._testingSource == "artifact") and _fetchArtifactInfo
                or function(cb) _fetchReleaseInfo("testing", cb) end

            fetchFn(function(info)
                if not info then
                    ms.dev.log({
                        type   = "error",
                        event  = "update_failed",
                        reason = (ms._testingSource == "artifact") and "artifact_fetch" or "release_fetch",
                    })
                    if ms._testingSource == "artifact" then
                        if not ms._githubToken or ms._githubToken == "" then
                            ms.alert("Update failed: no GitHub token configured.\\nSet one in Settings \\xe2\\x86\\x92 Developer.", 6)
                        else
                            ms.alert("Update failed: could not fetch artifact.\\nCheck your GitHub token has actions:read permission.", 6)
                        end
                    else
                        ms.alert("Update failed: could not fetch testing release info.", 5)
                    end
                    return
                end
                local newVersion = info.version

                local _localVer
                do
                    local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                    if lf then
                        local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                        lf:close()
                        if ok and lm and lm.version then _localVer = lm.version end
                    end
                end
                if _localVer and not _remoteIsNewer(_localVer, newVersion) then
                    ms.alert("Already on the latest testing version (v" .. _localVer .. ").", 4, true)
                    return
                end

                local bundleURL  = info.downloadUrl
                ms.alert("Downloading v" .. newVersion .. " bundle\xe2\x80\xa6", 4, true)
                ms.dev.log({
                    type    = "system",
                    event   = "update_download_start",
                    version = newVersion,
                    format  = "bundle",
                })
                hs.http.asyncGet(bundleURL, info.headers or nil, function(fCode, fBody, _)
                    if fCode ~= 200 or not fBody then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "download_http",
                            code    = fCode,
                            version = newVersion,
                        })
                        ms.alert("Update failed: bundle download returned " .. tostring(fCode) .. ".", 5)
                        return
                    end
                    os.execute("mkdir -p '" .. archivePath .. "'")
                    local isZip = bundleURL:match("%.zip$")
                    local tmpArchive = archivePath .. (isZip and "ms_bundle_update.zip" or "ms_bundle_update.tar.gz")
                    local tmpF = io.open(tmpArchive, "wb")
                    if not tmpF then
                        ms.alert("Update failed: could not write temp file.", 4)
                        return
                    end
                    tmpF:write(fBody)
                    tmpF:close()
                    local tmpExtract = archivePath .. "ms_bundle_extract/"
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    os.execute("mkdir -p '" .. tmpExtract .. "'")
                    local _, extractOk
                    if isZip then
                        _, extractOk = hs.execute("unzip -o '" .. tmpArchive .. "' -d '" .. tmpExtract .. "' 2>&1")
                    else
                        _, extractOk = hs.execute("tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1")
                    end
                    os.remove(tmpArchive)
                    if not extractOk then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "extract_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not extract bundle.", 5)
                        return
                    end
                    local manifestPath = tmpExtract .. "MANIFEST.json"
                    local topDir = nil
                    local dh = io.popen("ls -d '" .. tmpExtract .. "'/mudscript-* 2>/dev/null | head -1")
                    if dh then topDir = dh:read("*l")
                    dh:close() end
                    if topDir and topDir ~= "" then
                        if not topDir:match("/$") then topDir = topDir .. "/" end
                        local altManifest = topDir .. "MANIFEST.json"
                        if hs.fs.attributes(altManifest) then manifestPath = altManifest end
                    end
                    local manifest = nil
                    local mf = io.open(manifestPath, "r")
                    if mf then
                        local ok, m = pcall(hs.json.decode, mf:read("*all"))
                        mf:close()
                        if ok then manifest = m end
                    end
                    if manifest and not _verifySignature(manifest) then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        return
                    end
                    local timestamp = os.date("%Y-%m-%d_%H%M")
                    ms._updateInProgress = true
                    os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                    local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                    if _sp then _sp:close() end
                    local ok = _applyBundleUpdate(tmpExtract, timestamp)
                    ms._updateInProgress = false
                    os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if not ok then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "apply_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not apply bundle.", 5)
                        return
                    end
                    ms.dev.log({
                        type    = "system",
                        event   = "update_applied",
                        version = newVersion,
                        format  = "bundle",
                    })
                    ms.integrity.trustCurrent()
                    ms.integrity.invalidateCache()
                    ms.alert("Updated to v" .. newVersion .. ".\\nReloading in 3 seconds\\xe2\\x80\\xa6", 5, true)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end)
            end)
        end
        -- END Update Beta --

        -- Check For Update [stable channel] --
        ms.integrity.checkForUpdate = function(callback)
            local localVersion
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then localVersion = lm.version end
                end
            end
            _fetchReleaseInfo("stable", function(info)
                if not info then
                    ms.dev.log({
                        type    = "error",
                        event   = "update_check_failed",
                        channel = "stable",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local remoteVersion = info.version
                if _remoteIsNewer(localVersion, remoteVersion) then
                    ms.dev.log({
                        type     = "system",
                        event    = "update_available",
                        local_v  = localVersion,
                        remote_v = remoteVersion,
                        channel  = "stable",
                    })
                    if callback then
                        pcall(callback, {
                            version = remoteVersion or "?",
                            sha256  = info.sha256,
                        })
                    end
                    return
                end
                if callback then pcall(callback, nil) end
            end)
        end
        -- END Check For Update --

        -- Check For Update Beta [testing channel] --
        ms.integrity.checkForUpdateBeta = function(callback)
            local localVersion
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then localVersion = lm.version end
                end
            end
            _fetchReleaseInfo("testing", function(info)
                if not info then
                    if callback then pcall(callback, nil) end
                    return
                end
                local remoteVersion = info.version
                if _remoteIsNewer(localVersion, remoteVersion) then
                    ms.dev.log({
                        type     = "system",
                        event    = "update_available",
                        local_v  = localVersion,
                        remote_v = remoteVersion,
                        channel  = "testing",
                    })
                    if callback then
                        pcall(callback, {
                            version = remoteVersion or "?",
                            sha256  = info.sha256,
                        })
                    end
                else
                    if callback then pcall(callback, nil) end
                end
            end)
        end
        -- END Check For Update Beta --

        -- Check For Content Updates [installed packages & plugins] --
        -- Compares the version of every installed plugin / content item against
        -- the registry catalog and returns the ones the registry now advertises
        -- a newer version for. Forces a registry refresh first (bypassing the
        -- CACHE_TTL) so a freshly published bump is actually seen -- a non-forced
        -- refresh returns the up-to-6h-old cache and would silently miss the new
        -- version, dropping no alert. Then reuses the same _remoteIsNewer
        -- comparator the app-update check uses.
        ms.integrity.checkContentUpdates = function(callback)
            local function scan()
                local installed = {}   -- id -> { version, type, name }
                if ms.package and ms.package.listPlugins then
                    local okP, plugins = pcall(ms.package.listPlugins)
                    if okP and type(plugins) == "table" then
                        for _, p in ipairs(plugins) do
                            if p.id and type(p.version) == "string" then
                                installed[p.id] = {
                                    version = p.version,
                                    type    = "plugin",
                                    name    = p.name or p.id,
                                }
                            end
                        end
                    end
                end
                if ms.package and ms.package.listContent then
                    local okC, content = pcall(ms.package.listContent)
                    if okC and type(content) == "table" then
                        for id, rec in pairs(content) do
                            if installed[id] == nil and type(rec) == "table"
                                and type(rec.version) == "string" then
                                installed[id] = {
                                    version = rec.version,
                                    type    = rec.type or "content",
                                    name    = rec.name or id,
                                }
                            end
                        end
                    end
                end
                local entries = (ms.registry and ms.registry.list)
                    and ms.registry.list({}) or {}
                local out = {}
                for _, e in ipairs(entries) do
                    local inst = e.id and installed[e.id]
                    if inst and type(e.version) == "string"
                        and _remoteIsNewer(inst.version, e.version) then
                        out[#out + 1] = {
                            id   = e.id,
                            name = e.name or inst.name or e.id,
                            type = e.type or inst.type,
                            from = inst.version,
                            to   = e.version,
                        }
                    end
                end
                return out
            end
            if ms.registry and ms.registry.refresh then
                ms.registry.refresh({ force = true }, function()
                    if callback then pcall(callback, scan()) end
                end)
            else
                if callback then pcall(callback, scan()) end
            end
        end
        -- END Check For Content Updates --
    -- END System Integrity --

    -- ms.showGuardian --
        ms.showGuardian = function(trusted, current)
            trusted = trusted or ("a3f8" .. string.rep("0", 12))
            current = current or ("9c1e" .. string.rep("f", 12))
            local _home = os.getenv("HOME")
            local _htmlPath = _home .. "/.hammerspoon/ui/ms_guardian.html"
            local _baseURL  = "file://" .. _home .. "/.hammerspoon/ui/"
            local _uc = hs.webview.usercontent.new("guardianPreview")
            local _panel = nil
            local _pos   = nil
            _uc:setCallback(function(msg)
                local body = msg.body
                if body == "keepBlocked" or body == "confirmDelete" then
                    pcall(function() if _panel then _panel:delete() end end)
                else
                    local ok, data = pcall(hs.json.decode, body)
                    if ok and data and data.action == "move" and _pos then
                        _pos.x = _pos.x + (data.dx or 0)
                        _pos.y = _pos.y + (data.dy or 0)
                        pcall(function() _panel:frame(_pos) end)
                    end
                end
            end)
            local sf = hs.screen.mainScreen():frame()
            local w, h = 360, 300
            local x = sf.x + math.floor((sf.w - w) / 2)
            local y = sf.y + math.floor((sf.h - h) / 2)
            _pos   = {
                x = x,
                y = y,
                w = w,
                h = h,
            }
            _panel = hs.webview.new(_pos, {}, _uc)
            if not _panel then return end
            pcall(function() _panel:windowStyle(0) end)
            pcall(function() _panel:level(hs.canvas.windowLevels.popUpMenu or 101) end)
            pcall(function() _panel:shadow(true) end)
            if ms and ms.theme and ms.theme.applyWindowRadius then ms.theme.applyWindowRadius(_panel) end
            if ms and ms.theme and ms.theme.onChanged then
                ms.theme.onChanged(function()
                    if ms and ms.theme and ms.theme._pushWindowRadius then ms.theme._pushWindowRadius(_panel) end
                end)
            end
            local f = io.open(_htmlPath, "r")
            if not f then return end
            _panel:html(f:read("*all"), _baseURL)
            f:close()
            ms.safeShow(_panel)
            local _errSound = (not ms._customThemeDisabled and ms.sounds and ms.sounds["a_Error"])
                or (ms.sounds and ms.sounds["d_Error"])
            if _errSound then pcall(function() ms.sound(_errSound) end) end
            _panel:navigationCallback(function()
                pcall(function()
                    local t = trusted:sub(1, 16) .. "\xe2\x80\xa6"
                    local c = current:sub(1, 16)  .. "\xe2\x80\xa6"
                    _panel:evaluateJavaScript(
                        "setHashes('" .. t .. "', '" .. c .. "')"
                    )
                    _panel:evaluateJavaScript("setPreviewMode()")
                    if not ms._customThemeDisabled then
                        local tj = hs.json.encode(ms._theme or {})
                        if tj then
                            _panel:evaluateJavaScript("applyTheme(" .. tj .. ")")
                        end
                    end
                end)
            end)
        end

        -- A trackpad has left (1) and right/two-finger (2) clicks but none of
        -- the extra mouse buttons, so a resolved trigger on Mouse 3+ can never
        -- fire there. When trackpad mode is on, swap such a trigger for the
        -- owning bind's declared fallback key (opts.trackpad on ms.bind.define).
        -- If no fallback is declared the trigger is left as-is: the bind simply
        -- can't fire on a trackpad, rather than being silently hijacked.
        local TRACKPAD_MAX_BUTTON = 2
        local function trackpadFallback(bind, rootId)
            if not ms.trackpadMode or type(bind) ~= "table" then return bind end
            if bind.type ~= "mouse" then return bind end
            local n = tonumber(bind.button)
            if not (n and n > TRACKPAD_MAX_BUTTON) then return bind end
            local rootDef = ms.registry._defs and ms.registry._defs[rootId]
            local fb = rootDef and rootDef.trackpad
            if type(fb) ~= "table" or not fb.key then return bind end
            -- Keep the resolved bind's own modifiers (so V+Mouse3 -> V+key),
            -- unless the fallback explicitly overrides them.
            return { type = "key", key = fb.key, mods = fb.mods or bind.mods or {} }
        end

        ms.effectiveBind = function(id)
            local def = ms.registry._defs and ms.registry._defs[id]
            local raw = ms.bindConfig[id] or (def and def.default)
            local resolved, rootId = raw, id
            if raw and type(raw) == "table" and raw.type and ms.registry._defs[raw.type] then
                local visited = {}
                local accum = {}
                local function addMods(mods)
                    for _, m in ipairs(mods or {}) do
                        local dup = false
                        for _, e in ipairs(accum) do
                            if e == m then dup = true
                            break end
                        end
                        if not dup then accum[#accum+1] = m end
                    end
                end
                addMods(raw.mods)
                local current = raw
                while current and type(current) == "table" and current.type
                    and ms.registry._defs[current.type] and not visited[current.type] do
                    visited[current.type] = true
                    rootId = current.type
                    local parentDef = ms.registry._defs[current.type]
                    local parentBind = ms.bindConfig[current.type] or (parentDef and parentDef.default)
                    if parentBind and type(parentBind) == "table" and parentBind.type
                        and not ms.registry._defs[parentBind.type] then
                        addMods(parentBind.mods)
                        resolved = {
                            type = parentBind.type,
                            key = parentBind.key,
                                 button = parentBind.button,
                                 direction = parentBind.direction,
                                 mods = accum }
                        break
                    end
                    addMods(parentBind and parentBind.mods)
                    current = parentBind
                end
            end
            return trackpadFallback(resolved, rootId)
        end
    -- END ms.showGuardian --

    -- SOCD Engine --
        ms._socdListener = nil
        ms._socdHeld = {
            a = false,
            d = false,
            w = false,
            s = false,
        }

        local socdKeyCodes = {
            a = hs.keycodes.map["a"],
            d = hs.keycodes.map["d"],
            w = hs.keycodes.map["w"],
            s = hs.keycodes.map["s"],
        }

        local socdCodeToKey = {}
        for name, code in pairs(socdKeyCodes) do
            socdCodeToKey[code] = name
        end

        local function socdAxis(neg, pos, axisKey)
            local negHeld = ms._socdHeld[neg]
            local posHeld = ms._socdHeld[pos]
            local mode = ms.socdMode or "lastWins"

            if not negHeld and not posHeld then return end
            if negHeld and not posHeld then return end
            if posHeld and not negHeld then return end

            if mode == "neutral" then
                local negCode = socdKeyCodes[neg]
                local posCode = socdKeyCodes[pos]
                local evNeg = hs.eventtap.event.newKeyEvent({}, negCode, false)
                local evPos = hs.eventtap.event.newKeyEvent({}, posCode, false)
                evNeg:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                evPos:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                evNeg:post()
                evPos:post()
            elseif mode == "lastWins" then
            elseif mode == "firstWins" then
            end
        end

        ms.socdStart = function()
            if ms._socdListener then return end
            ms._socdHeld  = {
                a = false,
                d = false,
                w = false,
                s = false,
            }

            ms._socdListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
            }, function(event)
                if BindValidity ~= 1 then return false end
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end

                local keyCode = event:getKeyCode()
                local key = socdCodeToKey[keyCode]
                if not key then return false end

                local isDown = event:getType() == hs.eventtap.event.types.keyDown
                local mode = ms.socdMode or "lastWins"

                if isDown then
                    ms._socdHeld[key] = true

                    if key == "a" or key == "d" then
                        local opp = (key == "a") and "d" or "a"
                        if ms._socdHeld[opp] then
                            if mode == "lastWins" then
                                local oppCode = socdKeyCodes[opp]
                                local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev:post()
                                ms.keytrack[oppCode] = false
                            elseif mode == "firstWins" then
                                ms._socdHeld[key] = false
                                return true
                            elseif mode == "neutral" then
                                local oppCode = socdKeyCodes[opp]
                                local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev1:post()
                                ev2:post()
                                ms.keytrack[oppCode] = false
                                ms.keytrack[keyCode] = false
                                return true
                            end
                        end

                    elseif key == "w" or key == "s" then
                        local opp = (key == "w") and "s" or "w"
                        if ms._socdHeld[opp] then
                            if mode == "lastWins" then
                                local oppCode = socdKeyCodes[opp]
                                local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev:post()
                                ms.keytrack[oppCode] = false
                            elseif mode == "firstWins" then
                                ms._socdHeld[key] = false
                                return true
                            elseif mode == "neutral" then
                                local oppCode = socdKeyCodes[opp]
                                local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev1:post()
                                ev2:post()
                                ms.keytrack[oppCode] = false
                                ms.keytrack[keyCode] = false
                                return true
                            end
                        end
                    end

                else
                    ms._socdHeld[key] = false

                    if mode == "lastWins" then
                        local opp
                        if key == "a" then opp = "d"
                        elseif key == "d" then opp = "a"
                        elseif key == "w" then opp = "s"
                        elseif key == "s" then opp = "w"
                        end
                        if opp and ms._socdHeld[opp] then
                            local oppCode = socdKeyCodes[opp]
                            local ev = hs.eventtap.event.newKeyEvent({}, oppCode, true)
                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            ev:post()
                            ms.keytrack[oppCode] = true
                        end
                    end
                end

                return false
            end):start()
        end

        ms.socdStop = function()
            if ms._socdListener then
                ms._socdListener:stop()
                ms._socdListener = nil
            end
            ms._socdHeld  = {
                a = false,
                d = false,
                w = false,
                s = false,
            }
        end

        ms.socdApply = function()
            if ms.socdEnabled then
                ms.socdStart()
            else
                ms.socdStop()
            end
        end
    -- END SOCD Engine --

    -- Native Menu Builder --
        -- Menubar & Bind Collection --
            if ms._menubar then pcall(function() ms._menubar:delete() end) end
            ms._menubar = hs.menubar.new()
            ms._menubar:setIcon(os.getenv("HOME") .. "/.hammerspoon/ui/icons/ms_icon_gen.tiff", true)
            local _legacyNativeMenuBuilder = function()
                local mainBindDefs, optionalBindDefs = {}, {}
                for _, id in ipairs(ms.registry._defList or {}) do
                    local def = ms.registry._defs[id]
                    if def and not (def.default and def.default.type) then
                        local entry = {
                            id    = id,
                            label = def.label,
                            info  = def.info,
                        }
                        if def.group == "main" then
                            table.insert(mainBindDefs, entry)
                        elseif def.group == "optional" then
                            table.insert(optionalBindDefs, entry)
                        end
                    end
                end
        -- END Menubar & Bind Collection --

        -- Shared helpers --
            local function bindStr(c)
                if not c then return "( unset )" end
                if c.type == "mouse" then return "( Mouse " .. c.button .. " )" end
                if c.type == "scroll" then
                    local d = c.direction or "?"
                    return "( Scroll " .. d:sub(1,1):upper() .. d:sub(2) .. " )"
                end
                if c.type == "gamepad" then return "( Pad " .. ms.gpLabel(c) .. " )" end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                table.insert(parts, c.key)
                return "( " .. table.concat(parts, "+") .. " )"
            end

            local function currentBindStr(id)
                return bindStr(ms.effectiveBind(id))
            end
        -- END Shared helpers --

        -- Rebind capture --
            local function makeRebindFn(bind)
                return function()
                    ms.alert("Rebinding: " .. bind.label .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                    local capture
                    local cancelTimer

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.otherMouseDown,
                    }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()

                        local parsed = nil
                        local bindStr2 = ""
                        local t = event:getType()

                        if t == hs.eventtap.event.types.keyDown then
                            local keyCode = event:getKeyCode()
                            local flags = event:getFlags()
                            if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                ms.alert("Rebind cancelled.", 2)
                                return true
                            end
                            local mods = {}
                            if flags.cmd   then table.insert(mods, "cmd")   end
                            if flags.alt   then table.insert(mods, "alt")   end
                            if flags.ctrl  then table.insert(mods, "ctrl")  end
                            if flags.shift then table.insert(mods, "shift") end
                            local keyStr = hs.keycodes.map[keyCode]
                            if keyStr then
                                parsed = {
                                    type = "key",
                                    mods = mods,
                                    key  = keyStr,
                                }
                                local parts = {}
                                for _, m in ipairs(mods) do table.insert(parts, m) end
                                table.insert(parts, keyStr)
                                bindStr2 = table.concat(parts, "+")
                            end
                        else
                            local btn
                            if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                            elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                            else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                            parsed = {
                                type="mouse",
                                button=btn,
                            }
                            bindStr2 = "Mouse " .. btn
                        end

                        if parsed then
                            local conflictId = ms.bind.siblingConflict(bind.id, parsed)
                            if conflictId then
                                ms.playSlot("alert")
                                local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                                ms.alert("Bind Conflict: \"" .. bindStr2 .. "\" is already used by \"" .. cLabel .. "\". Try a different input.", 4)
                                return true
                            end
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set \"" .. bind.label .. "\" to:  " .. bindStr2,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.bindConfig[bind.id] = parsed
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.bind.rebind()
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert(bind.label .. " rebound to: " .. bindStr2, 3, true)
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2, true)
                                end
                            end)
                        else
                            ms.alert("Could not read input. Try again.", 2)
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop()
                            capture = nil
                            ms.alert("Rebind timed out.", 2)
                        end
                    end)
                end
            end

        -- END Rebind capture --

        -- Section builder --
            local function buildBindSection(defs)
                local section = {}
                local rebindSub = {}

                for _, bind in ipairs(defs) do
                    local enabled = ms.binds[bind.id]
                    table.insert(section, {
                        title = (enabled and "✓ " or "✗ ") .. bind.label .. "  " .. currentBindStr(bind.id),
                        fn = function()
                            ms.binds[bind.id] = not ms.binds[bind.id]
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("update")
                            ms.alert(bind.label .. ": " .. (ms.binds[bind.id] and "ON" or "OFF"), 2, true)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Rebind: " .. bind.label,
                        fn = makeRebindFn(bind),
                    })
                    table.insert(rebindSub, {
                        title = "Set Cooldown: " .. bind.label,
                        fn = function()
                            ms.playSlot("interact")
                            local codeDef = ms.registry._defs[bind.id]
                            local codeDefault = (codeDef and codeDef.cooldown) or 1000
                            local current = ms.cooldowns[bind.id] or codeDefault
                            ms.ui.prompt({
                                title   = "Set Cooldown",
                                msg     = "Cooldown for \"" .. bind.label .. "\" (ms).\nDefault: " .. tostring(codeDefault) .. "ms  |  0 = no cooldown:",
                                confirm = "Set",
                                cancel  = "Cancel",
                                default = tostring(current),
                            }, function(r)
                                if r.confirmed then
                                    local num = tonumber(r.value)
                                    if num and num >= 0 then
                                        ms.cooldowns[bind.id] = math.floor(num)
                                        ms.saveSettings()
                                        ms.bind.rebind()
                                        ms.playSlot("update")
                                        hs.timer.doAfter(0.2, function()
                                            ms.alert(bind.label .. " cooldown: " .. tostring(math.floor(num)) .. "ms", 2, true)
                                            ms.ui.refresh()
                                        end)
                                    else
                                        ms.alert("Invalid value. Enter a non-negative number.", 2)
                                    end
                                end
                            end)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Reset Bind: " .. bind.label,
                        fn = function()
                            ms.bindConfig[bind.id] = nil
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            ms.alert(bind.label .. " bind reset to default.", 2, true)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Reset Cooldown: " .. bind.label,
                        fn = function()
                            ms.cooldowns[bind.id] = nil
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            local def = ms.registry._defs[bind.id]
                            local defMs = (def and def.cooldown) or 1000
                            ms.alert(bind.label .. " cooldown reset to " .. tostring(defMs) .. "ms.", 2, true)
                        end
                    })
                end

                table.insert(section, { title = "-" })
                table.insert(section, {
                    title = "Rebind",
                    menu = rebindSub,
                })
                table.insert(section, { title = "-" })
                table.insert(section, {
                    title = "Reset All to Default...",
                    fn = function()
                    ms.playSlot("interact")
                    ms.ui.modal({
                        title   = "Reset All to Default",
                        msg     = "Reset all binds and cooldowns in this section to their default values?",
                        confirm = "Reset",
                        cancel  = "Cancel",
                    }, function(r)
                        if r.confirmed then
                            for _, bind in ipairs(defs) do
                                ms.bindConfig[bind.id] = nil
                                ms.cooldowns[bind.id]  = nil
                            end
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            hs.timer.doAfter(0.2, function()
                                ms.alert("All binds reset to default.", 3, true)
                                ms.ui.refresh()
                            end)
                        end
                    end)
                end })

                return section
            end
        -- END Section builder --


        -- System submenu --
            local function buildSystemSubmenu()
                local sub = {}
                for _, id in ipairs({
                    "enable",
                    "disable",
                    "toggle",
                }) do
                    local def = ms.systemBinds._defs[id]
                    if def then
                        local bindStr = ms.systemBinds.bindStr(id)
                        table.insert(sub, {
                            title = def.label .. "  " .. bindStr,
                            disabled = true,
                        })
                        table.insert(sub, {
                            title = "  Rebind: " .. def.label,
                            fn = function()
                                ms.alert("Rebinding: " .. def.label
                                    .. "\nCurrent: " .. bindStr
                                    .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                                local capture
                                local cancelTimer
                                capture = hs.eventtap.new({
                                    hs.eventtap.event.types.keyDown,
                                    hs.eventtap.event.types.leftMouseDown,
                                    hs.eventtap.event.types.rightMouseDown,
                                    hs.eventtap.event.types.otherMouseDown,
                                }, function(event)
                                    capture:stop()
                                    capture = nil
                                    cancelTimer:stop()
                                    local parsed, newBindStr
                                    local t = event:getType()
                                    if t == hs.eventtap.event.types.keyDown then
                                        local keyCode = event:getKeyCode()
                                        local flags = event:getFlags()
                                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                            ms.alert("Rebind cancelled.", 2)
                                            return true
                                        end
                                        local mods = {}
                                        if flags.cmd   then table.insert(mods, "cmd")   end
                                        if flags.alt   then table.insert(mods, "alt")   end
                                        if flags.ctrl  then table.insert(mods, "ctrl")  end
                                        if flags.shift then table.insert(mods, "shift") end
                                        local keyStr = hs.keycodes.map[keyCode]
                                        if keyStr then
                                            parsed = {
                                                type = "key",
                                                mods = mods,
                                                key  = keyStr,
                                            }
                                            local parts = {}
                                            for _, m in ipairs(mods) do table.insert(parts, m) end
                                            table.insert(parts, keyStr)
                                            newBindStr = table.concat(parts, "+")
                                        end
                                    else
                                        local btn
                                        if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                                        elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                                        else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                                        parsed = {
                                            type="mouse",
                                            button=btn,
                                        }
                                        newBindStr = "Mouse " .. btn
                                    end
                                    if parsed then
                                        ms.playSlot("interact")
                                        ms.ui.modal({
                                            title   = "Confirm Rebind",
                                            msg     = "Set \"" .. def.label .. "\" to:  " .. newBindStr,
                                            confirm = "Confirm",
                                            cancel  = "Cancel",
                                        }, function(r)
                                            if r.confirmed then
                                                ms.systemBinds._config[id] = parsed
                                                ms.saveSettings()
                                                ms.systemBinds.rebind()
                                                ms.playSlot("update")
                                                hs.timer.doAfter(0.2, function()
                                                    ms.alert(def.label .. " rebound to: " .. newBindStr, 3, true)
                                                end)
                                            else
                                                ms.alert("Rebind cancelled.", 2, true)
                                            end
                                        end)
                                    else
                                        ms.alert("Could not read input. Try again.", 2)
                                    end
                                    return true
                                end)
                                capture:start()
                                cancelTimer = hs.timer.doAfter(15, function()
                                    if capture then capture:stop()
                                    capture = nil
                                    ms.alert("Rebind timed out.", 2) end
                                end)
                            end
                        })
                        table.insert(sub, {
                            title = "  Reset: " .. def.label,
                            fn = function()
                                ms.systemBinds._config[id] = nil
                                ms.saveSettings()
                                ms.systemBinds.rebind()
                                ms.playSlot("reset")
                                ms.alert(def.label .. " reset to default.", 2, true)
                            end
                        })
                    end
                end
                table.insert(sub, { title = "-" })
                local displayBinds = {
                    {
                        label = "Panic Button / Stop All",
                        bind = "Alt+F10",
                    },
                    {
                        label = "Get Target Window Info",
                        bind = "Ctrl+Shift+R",
                    },
                    {
                        label = "Quick Reload",
                        bind = "Alt+[-> Reload Options",
                    },
                    {
                        label = "Full Reload",
                        bind = "Alt+]-> Reload Options",
                    },
                    {
                        label = "Open Menu",
                        bind = "Alt+P",
                    },
                }
                for _, bind in ipairs(displayBinds) do
                    table.insert(sub, {
                        title = bind.label .. "  " .. bind.bind,
                        disabled = true,
                    })
                end
                return sub
            end

            local function buildSoundSubmenu()
                ms._discoverSounds()
                local sub = {}
                table.insert(sub, {
                    title = (ms.soundEnabled and "✓" or "✗") .. " Sound Effects",
                    fn = function()
                        ms.soundEnabled = not ms.soundEnabled
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.alert("Sound Effects: " .. (ms.soundEnabled and "ON" or "OFF"), 2, true)
                    end
                })
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Volume: " .. tostring(ms.soundVolume or 100) .. "%",
                    disabled = true,
                })
                table.insert(sub, {
                    title = "Set Volume...",
                    fn = function()
                        ms.playSlot("interact")
                        ms.ui.prompt({
                            title   = "Sound Volume",
                            msg     = "Enter volume (0-100):",
                            confirm = "Set",
                            cancel  = "Cancel",
                            default = tostring(ms.soundVolume or 100),
                        }, function(r)
                            if r.confirmed then
                                local num = tonumber(r.value)
                                if num and num >= 0 and num <= 100 then
                                    ms.soundVolume = math.floor(num)
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Volume set to " .. tostring(ms.soundVolume) .. "%", 2, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Invalid value. Must be 0-100.", 2)
                                end
                            end
                        end)
                    end
                })
                table.insert(sub, {
                    title = "Reset Volume",
                    fn = function()
                        ms.soundVolume = 100
                        ms.saveSettings()
                        ms.playSlot("reset")
                        ms.alert("Volume reset to 100%", 2, true)
                    end
                })
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Import Sound Files...",
                    fn = function()
                        ms.playSlot("alert")
                        hs.focus()
                        local slibDir = SoundActiveDir:match("^(.-)[/\\]*$") or SoundActiveDir
                        local result = hs.dialog.chooseFileOrFolder(
                            "Select one or more sound files to add to your library",
                            hs.fs.attributes(slibDir) and SoundActiveDir or os.getenv("HOME"),
                            true, false, true
                        )
                        local paths = {}
                        for _, v in pairs(result or {}) do
                            if type(v) == "string" then table.insert(paths, v) end
                        end
                        if #paths == 0 then return end
                        result = paths

                        if not hs.fs.attributes(slibDir) then
                            hs.execute("mkdir -p '" .. SoundActiveDir .. "'")
                        end
                        if not hs.fs.attributes(slibDir) then
                            ms.alert("Could not create sounds folder at:\n" .. SoundLib, 4)
                            return
                        end

                        local function sq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

                        local added, failed = {}, {}
                        for _, srcPath in ipairs(result) do
                            local filename   = srcPath:match("([^/]+)$")
                            local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                            if not filename or not importName then
                                table.insert(failed, srcPath)
                                goto nextFile
                            end
                            local dst = SoundActiveDir .. filename
                            if srcPath ~= dst then
                                local copied = false
                                local f = io.open(srcPath, "rb")
                                if f then
                                    local content = f:read("*all")
                                    f:close()
                                    local g = io.open(dst, "wb")
                                    if g then
                                        g:write(content)
                                        g:close()
                                        copied = true
                                    else
                                        print("ms: import: io.open write failed for " .. tostring(srcPath))
                                    end
                                else
                                    print("ms: import: io.open read failed for " .. tostring(srcPath))
                                end
                                if not copied then
                                    local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                                    if not copied then
                                        print("ms: import: shell cp failed for " .. tostring(srcPath))
                                    end
                                end
                                if not copied then
                                    table.insert(failed, importName)
                                    goto nextFile
                                end
                            end
                            ms.importedSounds = ms.importedSounds or {}
                            ms.importedSounds[importName] = filename
                            table.insert(added, importName)
                            ::nextFile::
                        end

                        if #added > 0 then
                            ms.saveSettings()
                            ms._soundsDirty = true
                            ms._discoverSounds()
                            ms._pendingReopenToSound = true
                        end
                        hs.timer.doAfter(0.2, function()
                            if #added > 0 then
                                ms.playSlot("update")
                            end
                            if #added > 0 and #failed == 0 then
                                local label = #added == 1
                                    and ("Sound \"" .. added[1] .. "\" added.")
                                    or  (#added .. " sounds added.")
                                ms.alert(label, 3, true)
                            elseif #added > 0 then
                                ms.alert(
                                    #added .. " added, " .. #failed .. " failed.",
                                    3,
                                    true
                                )
                            else
                                ms.alert("Import failed. Grant Hammerspoon Full Disk Access\nfor importing from outside ~/.hammerspoon.", 5)
                            end
                        end)
                    end
                })
                table.insert(sub, { title = "-" })
                local slots = {
                    {
                        id = "load",
                        label = "Loading Screen End",
                    },
                    {
                        id = "launch",
                        label = "Launch Announcement",
                    },
                    {
                        id = "updateAvailable",
                        label = "Update Available",
                    },
                    {
                        id = "alert",
                        label = "Alert / Notice",
                    },
                    {
                        id = "error",
                        label = "Error",
                    },
                    {
                        id = "enabled",
                        label = "Macros Enabled",
                    },
                    {
                        id = "disabled",
                        label = "Macros Disabled",
                    },
                    {
                        id = "update",
                        label = "Setting Updated",
                    },
                    {
                        id = "reset",
                        label = "Setting Reset",
                    },
                    {
                        id = "interact",
                        label = "Menu Interact",
                    },
                    {
                        id = "hover",
                        label = "Menu Hover",
                    },
                    {
                        id = "back",
                        label = "Menu Back",
                    },
                    {
                        id = "settingsOpen",
                        label = "Settings Open",
                    },
                    {
                        id = "settingsClose",
                        label = "Settings Close",
                    },
                }
                local soundNames = {}
                for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
                table.sort(soundNames)
                for _, slot in ipairs(slots) do
                    local assigned = ms.soundAssign and ms.soundAssign[slot.id]
                    local display  = assigned or "off"
                    local picker   = {}
                    table.insert(picker, {
                        title = (not assigned and "✓ " or "  ") .. "None",
                        fn = function()
                            ms.soundAssign = ms.soundAssign or {}
                            ms.soundAssign[slot.id] = nil
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert(slot.label .. " sound: off", 2, true)
                        end
                    })
                    table.insert(picker, { title = "-" })
                    if #soundNames == 0 then
                        table.insert(picker, {
                            title = "(no sound files imported)",
                            disabled = true,
                        })
                    else
                        for _, name in ipairs(soundNames) do
                            table.insert(picker, {
                                title = (assigned == name and "✓ " or "  ") .. name,
                                fn = function()
                                    ms.soundAssign = ms.soundAssign or {}
                                    ms.soundAssign[slot.id] = name
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert(slot.label .. " sound: " .. name, 2, true)
                                end
                            })
                        end
                    end
                    table.insert(sub, {
                        title = slot.label .. "  ( " .. display .. " )",
                        menu  = picker
                    })
                end
                return sub
            end

            local function buildTrackpadHoldSubmenu()
            local sub = {}
            local keys = ms.trackpadHoldKeys or {
                left = "n",
                right = "j",
            }

            table.insert(sub, {
                title = "Left Click Hold  ( " .. (keys.left or "unset") .. " )",
                fn = function()
                    ms.alert("Rebinding: Left Click Hold\nCurrent: " .. (keys.left or "unset")
                        .. "\nPress a key. Backspace to reset to default ( n ). Escape to cancel.", 15)
                    local capture, cancelTimer
                    capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        local flags = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2)
                        return true end
                        local newKey = (keyCode == 51) and "n" or hs.keycodes.map[keyCode]
                        if newKey then
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set Left Click Hold to:  " .. newKey,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.trackpadHoldKeys.left = newKey
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Left Click Hold set to: " .. newKey, 3, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2)
                                end
                            end)
                        else
                            ms.alert("Could not read key. Try again.", 2)
                        end
                        return true
                    end)
                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then capture:stop()
                        capture = nil
                        ms.alert("Rebind timed out.", 2) end
                    end)
                end
            })

            table.insert(sub, {
                title = "Right Click Hold  ( " .. (keys.right or "unset") .. " )",
                fn = function()
                    ms.alert("Rebinding: Right Click Hold\nCurrent: " .. (keys.right or "unset")
                        .. "\nPress a key. Backspace to reset to default ( j ). Escape to cancel.", 15)
                    local capture, cancelTimer
                    capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        local flags = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2)
                        return true end
                        local newKey = (keyCode == 51) and "j" or hs.keycodes.map[keyCode]
                        if newKey then
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set Right Click Hold to:  " .. newKey,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.trackpadHoldKeys.right = newKey
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Right Click Hold set to: " .. newKey, 3, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2)
                                end
                            end)
                        else
                            ms.alert("Could not read key. Try again.", 2)
                        end
                        return true
                    end)
                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then capture:stop()
                        capture = nil
                        ms.alert("Rebind timed out.", 2) end
                    end)
                end
            })

            table.insert(sub, { title = "-" })
            table.insert(sub, {
                title = "Reset both to default  ( n / j )",
                fn = function()
                    ms.playSlot("interact")
                    ms.ui.modal({
                        title   = "Reset Hold Keys",
                        msg     = "Reset both hold keys to defaults?  ( n / j )",
                        confirm = "Reset",
                        cancel  = "Cancel",
                    }, function(r)
                        if r.confirmed then
                            ms.trackpadHoldKeys.left  = "n"
                            ms.trackpadHoldKeys.right = "j"
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            hs.timer.doAfter(0.2, function()
                                ms.alert("Hold keys reset to default  ( n / j )", 3, true)
                                ms.ui.refresh()
                            end)
                        end
                    end)
                end
            })

            return sub
            end

            local function buildProfilesSubmenu()
                local sub = {}
                local currentName = ms.macroMeta and ms.macroMeta.name
                local profiles = getProfiles()
                if currentName then
                    table.insert(sub, {
                        title = "Active:  " .. currentName,
                        disabled = true,
                    })
                    table.insert(sub, { title = "-" })
                end
                if #profiles == 0 then
                    table.insert(sub, {
                        title = "No saved profiles.",
                        disabled = true,
                    })
                else
                    for _, name in ipairs(profiles) do
                        local isCurrent = (name == (currentName and sanitizeName(currentName)))
                        table.insert(sub, {
                            title    = (isCurrent and "✓ " or "") .. name,
                            disabled = isCurrent,
                            fn       = not isCurrent and function()
                                ms.ui.modal({
                                    title   = "Switch Profile",
                                    msg     = "Switch to \"" .. name .. "\"?\n\nThe current profile will be archived and Hammerspoon will reload in 3 seconds.",
                                    confirm = "Switch",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then switchProfile(name) end
                                end)
                            end or nil,
                        })
                    end
                end
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Create New Profile...",
                    fn    = function() createNewProfile() end,
                })
                local activeFolder = currentName and sanitizeName(currentName) or ""
                local hasMatching = false
                for _, p in ipairs(profiles) do
                    if p == activeFolder then hasMatching = true
                    break end
                end
                table.insert(sub, {
                    title    = "Save Current Profile",
                    disabled = not hasMatching,
                    fn       = hasMatching and function() saveCurrentProfile() end or nil,
                })
                table.insert(sub, {
                    title = "Import Profile...",
                    fn    = function() importProfile() end,
                })
                return sub
            end

            local keybindSubmenu = {
                {
                    title = "Main",
                    menu = buildBindSection(mainBindDefs),
                },
                {
                    title = "Optional",
                    menu = buildBindSection(optionalBindDefs),
                },
                {
                    title = "System",
                    menu = buildSystemSubmenu(),
                },
                { title = "-" },

                { title = "-" },

            }
        -- END System submenu --

        -- Settings submenu --
            local function buildSettingsSubmenu()
                return {
                    {
                        title = (ms.trackpadMode and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Trackpad / Pen Mode",
                        fn = function()
                        ms.trackpadMode = not ms.trackpadMode
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot("update")
                        ms.alert("Trackpad / Pen Mode: " .. (ms.trackpadMode and "ON" or "OFF"), 2, true)
                    end },
                    {
                        title = "Trackpad Hold Keys",
                        menu = buildTrackpadHoldSubmenu(),
                    },
                    { title = "-" },
                    {
                        title = (ms._swallowHotkeys and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Swallow Hotkey Inputs",
                        fn = function()
                        ms._swallowHotkeys = not ms._swallowHotkeys
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.alert("Swallow Hotkeys: " .. (ms._swallowHotkeys and "ON" .. "\nHotkey keypresses will be blocked from reaching the target app." or "OFF" .. "\nHotkey keypresses will pass through to the target app."), 4, true)
                    end },
                    {
                        title = (ms.gamepadEnabled and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Controller / Gamepad Input",
                        fn = function()
                        ms.gamepadEnabled = not ms.gamepadEnabled
                        if ms.gamepadEnabled then
                            if ms.gamepadStart then ms.gamepadStart() end
                        else
                            if ms.gamepadStop then ms.gamepadStop() end
                        end
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot("update")
                        if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                        ms.alert("Controller Input: " .. (ms.gamepadEnabled and "ON" or "OFF"), 2, true)
                    end },
                    { title = "-" },
                    {
                        title = (ms.socdEnabled and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " SOCD Cleaning",
                        fn = function()
                        ms.socdEnabled = not ms.socdEnabled
                        ms.saveSettings()
                        ms.socdApply()
                        ms.playSlot("update")
                        ms.alert("SOCD Cleaning: " .. (ms.socdEnabled and "ON" or "OFF"), 2, true)
                    end },
                    { title = "SOCD Mode: " .. (ms.socdMode == "lastWins" and "Last Input Wins" or ms.socdMode == "neutral" and "Neutral" or "First Input Wins"), menu = {
                        {
                            title = (ms.socdMode == "lastWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Last Input Wins",
                            fn = function()
                            ms.socdMode = "lastWins"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: Last Input Wins", 2, true)
                        end },
                        {
                            title = (ms.socdMode == "neutral" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Neutral",
                            fn = function()
                            ms.socdMode = "neutral"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: Neutral", 2, true)
                        end },
                        {
                            title = (ms.socdMode == "firstWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " First Input Wins",
                            fn = function()
                            ms.socdMode = "firstWins"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: First Input Wins", 2, true)
                        end },
                    }},
                    { title = "-" },
                    {
                        title = "Sound",
                        menu = buildSoundSubmenu(),
                    },
                    { title = "-" },
                    {
                        title = "Keybinds",
                        menu = keybindSubmenu,
                    },
                    { title = "-" },
                    {
                        title = "Save as Default...",
                        fn = function()
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Save as Default",
                            msg     = "Save current settings as the new default?\nThe existing default will be archived.",
                            confirm = "Save",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                ms.saveDefault()
                                ms.playSlot("update")
                                ms.ui.refresh()
                            end
                        end)
                    end },
                    {
                        title = "Reset to Default...",
                        fn = function()
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Reset to Default",
                            msg     = "Reset all settings to the saved default?\nCurrent settings will be overwritten.",
                            confirm = "Reset",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                if ms.resetToDefault() then
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Settings reset to default.", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end
                        end)
                    end },
                }
            end
        -- END Settings submenu --

        -- Developer submenu --
            local function buildDeveloperSubmenu()
                local _trusted = (ms.integrity.check() == "trusted")
                return {
                    {
                        title = "Debug Target Window",
                        fn = function()
                        ms.playSlot("interact")
                        ms.debugTarget()
                    end },
                    {
                        title = "Edit Macros",
                        fn = function()
                        ms.playSlot("interact")
                        os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
                    end },
                    { title = "-" },
                    {
                        title    = _trusted and "\xe2\x9c\x93 Trust Current Version" or "Trust Current Version...",
                        disabled = _trusted or nil,
                        fn       = not _trusted and function()
                            ms.playSlot("interact")
                            local status, cur = ms.integrity.check()
                            local prompt
                            if status == "uninitialized" then
                                prompt = "Seal this ms_core.lua as the trusted baseline?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                            else
                                prompt = "Hash mismatch detected. Trust the CURRENT (possibly modified) version?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                            end
                            ms.ui.modal({
                                title   = "Trust Current Version",
                                msg     = prompt,
                                confirm = "Trust",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then ms.integrity.trustCurrent() end
                            end)
                        end or nil,
                    },
                    { title = "Update Channel: " .. (ms._updateChannel == "testing" and "Testing" or "Stable"), menu = {
                        {
                            title = (ms._updateChannel == "stable" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Stable (MANIFEST.json)",
                            fn = function()
                            ms._updateChannel = "stable"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Update channel: Stable", 2, true)
                        end },
                        {
                            title = (ms._updateChannel == "testing" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Testing (GitHub Actions)",
                            fn = function()
                            ms._updateChannel = "testing"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Update channel: Testing", 2, true)
                        end },
                    }},
                    { title = "Testing Source: " .. ((ms._testingSource or "release") == "artifact" and "Artifacts" or "Releases"), menu = {
                        {
                            title = ((ms._testingSource or "release") == "release" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Releases (signed manifests)",
                            fn = function()
                            ms._testingSource = "release"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Testing source: Releases", 2, true)
                        end },
                        {
                            title = ((ms._testingSource or "release") == "artifact" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Artifacts (rapid testing)",
                            fn = function()
                            ms._testingSource = "artifact"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Testing source: Artifacts", 2, true)
                        end },
                    }},
                }
            end
        -- END Developer submenu --

        -- Help submenu --
            local function buildHelpSubmenu()
                return {
                    {
                        title = "About",
                        fn = function()
                        ms.playSlot("interact")
                        ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn, https://mudbourn.info", 6)
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. ", " .. ms.macroMeta.website end
                            ms.alert(msg, 10)
                        end
                    end },
                    {
                        title = "Version",
                        fn = function()
                        ms.playSlot("interact")
                        local ver = "?"
                        local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                        if lf then
                            local raw = lf:read("*a")
                            lf:close()
                            local v = raw:match('"version"%s*:%s*"([^"]+)"')
                            if v then ver = v end
                        end
                        local chan = ms._updateChannel or "stable"
                        local label = (chan == "testing") and "Test Build" or "Release"
                        ms.alert("mudscript v" .. ver .. "\n" .. label .. " (" .. chan .. ")", 5, true)
                    end },
                    {
                        title = "GitHub",
                        fn = function()
                        ms.playSlot("interact")
                        hs.urlevent.openURL("https://github.com/mudbourn/mudscript")
                    end },
                    {
                        title = "Documentation",
                        fn = function()
                        ms.playSlot("interact")
                        hs.urlevent.openURL(ms._docsURL .. "?platform=mac")
                    end },
                    { title = "-" },
                    {
                        title = "Check System Integrity",
                        fn = function()
                        ms.playSlot("interact")
                        local status, cur, trusted = ms.integrity.check()
                        if status == "trusted" then
                            ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                        elseif status == "mismatch" then
                            ms.alert("\xe2\x9a\xa0 Hash mismatch!\nExpected: " .. (trusted and trusted:sub(1, 16) or "?") .. "\xe2\x80\xa6\nCurrent:  " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6\n\nVerify the change or use Trust Current Version.", 9)
                        else
                            ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                        end
                    end },
                    {
                        title = "Check for Update...",
                        fn = function()
                        if ms._updateChannel == "testing" then
                            if not ms._testingRepo or ms._testingRepo == "" then
                                ms.alert("No testing repo configured.\nSet ms._testingRepo in ms_core.lua.", 5)
                                return
                            end
                        else
                            if not ms._updateManifestURL or ms._updateManifestURL == "" then
                                ms.alert("No update URL configured.\nSet ms._updateManifestURL in ms_core.lua.", 5)
                                return
                            end
                        end
                        local _chan = (ms._updateChannel == "testing") and "testing" or "stable"
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Check for Update",
                            msg     = "Channel: " .. _chan .. "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                            confirm = "Update",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                if ms._updateChannel == "testing" then
                                    ms.integrity.updateBeta()
                                else
                                    ms.integrity.update()
                                end
                            end
                        end)
                    end },
                    {
                        title = (ms._updateAlertsDisabled and "\xe2\x9c\x97" or "\xe2\x9c\x93")
                            .. " Update Alerts on Launch",
                        fn = function()
                        ms._updateAlertsDisabled = not ms._updateAlertsDisabled
                        ms.saveSettings()
                        if ms._updateAlertsDisabled then
                            ms.playSlot("reset")
                            ms.alert("Launch update alerts: Off\nRe-enable here anytime.", 3, true)
                        else
                            ms.playSlot("update")
                            ms.alert("Launch update alerts: On", 2, true)
                        end
                    end },
                    { title = "-" },
                    {
                        title = "Macro Info",
                        fn = function()
                        ms.playSlot("interact")
                        local path = os.getenv("HOME") .. "/.hammerspoon/ms_macro_info.txt"
                        local f = io.open(path, "w")
                        if f then
                            f:write("Macro Modifiers & Usage\n")
                            f:write("=======================\n\n")
                            local function writeSection(defs)
                                for _, bind in ipairs(defs) do
                                    if bind.info then
                                        f:write(bind.label .. "\n")
                                        f:write(string.rep("-", #bind.label) .. "\n")
                                        f:write(bind.info .. "\n")
                                    end
                                end
                            end
                            writeSection(mainBindDefs)
                            writeSection(optionalBindDefs)
                            f:close()
                            os.execute("open " .. path)
                        end
                    end },
                }
            end
        -- END Help submenu --

        -- Main menu --
            local function _buildMenuItems()
                return {
                    {
                        title = "Macros: " .. (BindValidity == 1 and "ENABLED" or "DISABLED"),
                        disabled = true,
                    },
                    { title = "-" },
                    {
                        title = "Enable Macros ( Enter )",
                        fn = function() ms.setMacros(1) end,
                    },
                    {
                        title = "Disable Macros ( / )",
                        fn = function() ms.setMacros(0) end,
                    },
                    { title = "-" },
                    {
                        title = "Reload Options",
                        menu = {
                        {
                            title = "Quick Reload ( ⌥[ )",
                            fn = function() ms.quickReload() end,
                        },
                        {
                            title = "Full Reload ( ⌥] )",
                            fn = function()
                            if ms.restart then ms.restart() else hs.reload() end
                        end },
                    }},
                    { title = "-" },
                    {
                        title = "Profiles",
                        menu = buildProfilesSubmenu(),
                    },
                    {
                        title = "Settings",
                        menu = buildSettingsSubmenu(),
                    },
                    {
                        title = "Developer",
                        menu = buildDeveloperSubmenu(),
                    },
                    {
                        title = "Help",
                        menu = buildHelpSubmenu(),
                    },
                }
            end
            local function _wrapFns(items)
                for _, item in ipairs(items or {}) do
                    if item.fn then
                        local orig = item.fn
                        item.fn = function()
                            ms._menuFnFired = true
                            orig()
                            if ms._menuOpen then
                                hs.timer.doAfter(0, function()
                                    if ms._menuOpen then
                                        ms._menuFnFired = false
                                        ms.playSlot("settingsOpen")
                                        ms._menuHoverStart()
                                        ms._menuVisible = true
                                        ms._menubar:popupMenu(ms._biasedMenuPt(ms._lastMenuPoint))
                                        ms._menuVisible = false
                                        ms._menuHoverStop()
                                        if not ms._menuFnFired then
                                            ms.playSlot("settingsClose")
                                        end
                                    end
                                end)
                            end
                        end
                    end
                    if item.menu then _wrapFns(item.menu) end
                end
            end
            if ms._pendingReopenToSound then
                ms._pendingReopenToSound = false
                local soundItems = buildSoundSubmenu()
                if ms._menuOpen then _wrapFns(soundItems) end
                return soundItems
            end
            local freshItems = _buildMenuItems()
            if ms._menuOpen then _wrapFns(freshItems) end
            return freshItems
        -- END Main menu --

        end
    -- END Native Menu Builder --
-- END Settings Menu --

end

return MsSettings

end

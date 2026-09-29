return function(ms, ctx)
    -- User Settings & Menu API --
        local themePath = ctx.themePath
        local _SETTING_TYPES = ctx._SETTING_TYPES
        local _HIDEABLE_FEATURES = ctx._HIDEABLE_FEATURES
        local _validateUserValue = ctx._validateUserValue

        -- ms.settings.define(def) --
            ms.settings.define = function(def)
                assert(type(def) == "table",
                    "ms.settings.define: argument must be a table")
                -- Stamp where this def came from so the Tools panel can filter
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
                if v == nil then return def.default end
                return v
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
                local hx = type(data[k]) == "string" and data[k]:match("^#(%x+)$")
                if hx and (#hx == 3 or #hx == 6 or #hx == 8) then
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
end

return function(ms, ctx)
    -- Authored Settings --
        local authoredPath = ctx.authoredPath

        local authoredMenusPath = ctx.authoredMenusPath

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
            if type(raw.uid) == "string" and raw.uid ~= "" then
                def.uid = raw.uid
            end
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
            if ms._pendingUserSettings then ms._pendingUserSettings[key] = nil end
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

            local prevVal = ms._userSettingVals and ms._userSettingVals[oldKey]

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

            if def.key == oldKey and prevVal ~= nil then
                ms._pendingUserSettings = ms._pendingUserSettings or {}
                ms._pendingUserSettings[def.key] = prevVal
            end

            local prevDef = ms._authoredSettings[foundAt]
            def.uid = prevDef.uid or def.uid or _newUid()
            ms._authoredSettings[foundAt] = def
            local ok = pcall(ms.settings.define, def)
            if not ok then
                ms._authoredSettings[foundAt] = prevDef
                return false, "could not register the setting"
            end

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
    -- END Authored Settings --
end

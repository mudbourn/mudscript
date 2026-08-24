-- ms_plugins (Plugin Loading & Teardown) --
    return function(ms)

        local _home    = os.getenv("HOME")
        local _hsDir   = _home .. "/.hammerspoon"
        local _spoons  = _hsDir .. "/Spoons"

        ms.plugins = {
            loaded = {},
            failed = {},
            _undo  = {},
        }

        -- Helpers --
            local function shortName(dir) return (dir:gsub("%.spoon$", "")) end

            local function record(dir, fn)
                local list = ms.plugins._undo[dir]
                if list then list[#list + 1] = fn end
            end

            local function removeValue(list, value)
                if type(list) ~= "table" then return end
                for i, v in ipairs(list) do
                    if v == value then
                        table.remove(list, i)
                        return
                    end
                end
            end
        -- END Helpers --

        -- Recording Proxy --
            local function subProxy(real, overrides)
                return setmetatable({}, {
                    __index = function(_, k)
                        local o = overrides[k]
                        if o ~= nil then return o end
                        return real[k]
                    end,
                    __newindex = function(_, k, v) real[k] = v end,
                })
            end

            local function makeProxy(dir)
                local overrides = {}

                overrides.bind = subProxy(ms.bind, {
                    define = function(id, a, b)
                        local out = ms.bind.define(id, a, b)
                        record(dir, function()
                            ms.bind._wires[id] = nil
                            if ms.registry and ms.registry._defs then
                                ms.registry._defs[id] = nil
                                removeValue(ms.registry._defList, id)
                            end
                            if ms.binds then ms.binds[id] = nil end
                            if ms.bindConfig then ms.bindConfig[id] = nil end
                        end)
                        return out
                    end,
                })

                overrides.bus = subProxy(ms.bus, {
                    on = function(topic, fn)
                        local out = ms.bus.on(topic, fn)
                        record(dir, function() pcall(ms.bus.off, topic, fn) end)
                        return out
                    end,
                })

                overrides.key = function(...)
                    local handle = ms.key(...)
                    if type(handle) == "table" and type(handle.delete) == "function" then
                        record(dir, function() pcall(handle.delete) end)
                    end
                    return handle
                end

                overrides.mouse = function(button, ...)
                    local out = ms.mouse(button, ...)
                    local mine = ms._mouseCallbacks and ms._mouseCallbacks[button]
                    record(dir, function()
                        if mine and ms._mouseCallbacks
                            and ms._mouseCallbacks[button] == mine then
                            ms._mouseCallbacks[button] = nil
                        end
                    end)
                    return out
                end

                overrides.scrollBind = function(direction, fn)
                    local handle = ms.scrollBind(direction, fn)
                    record(dir, function()
                        if ms._scrollCallbacks
                            and ms._scrollCallbacks[direction] == fn then
                            ms._scrollCallbacks[direction] = nil
                        end
                    end)
                    return handle
                end

                overrides.settings = subProxy(ms.settings, {
                    define = function(def)
                        local out = ms.settings.define(def)
                        record(dir, function()
                            removeValue(ms._userSettingDefs, def)
                            local keys = {}
                            if type(def) == "table" then
                                if def.key then keys[#keys + 1] = def.key end
                                for _, sub in ipairs(def.items or {}) do
                                    if type(sub) == "table" and sub.key then
                                        keys[#keys + 1] = sub.key
                                    end
                                end
                            end
                            for _, k in ipairs(keys) do
                                if ms._userSettingIndex then ms._userSettingIndex[k] = nil end
                                if ms._userSettingVals  then ms._userSettingVals[k]  = nil end
                            end
                        end)
                        return out
                    end,
                })

                overrides.tools = subProxy(ms.tools, {
                    define = function(def)
                        local out = ms.tools.define(def)
                        record(dir, function()
                            if type(def) == "table" and def.id and ms._toolIndex then
                                ms._toolIndex[def.id] = nil
                            end
                            removeValue(ms._toolDefs, def)
                        end)
                        return out
                    end,
                })

                return setmetatable({}, {
                    __index = function(_, k)
                        local o = overrides[k]
                        if o ~= nil then return o end
                        return ms[k]
                    end,
                    __newindex = function(_, k, v) ms[k] = v end,
                })
            end
        -- END Recording Proxy --

        -- Load --
            ms.plugins.load = function(dir)
                if not (ms.package and ms.package.validSpoonName
                    and ms.package.validSpoonName(dir)) then
                    return false, "Invalid plugin name."
                end
                if ms.plugins.loaded[dir] then return true end

                local short = shortName(dir)
                local init  = _spoons .. "/" .. dir .. "/init.lua"
                if not hs.fs.attributes(init) then
                    return false, "No init.lua in " .. dir .. "."
                end

                ms.plugins._undo[dir] = {}

                local env = setmetatable(
                    { ms = makeProxy(dir) },
                    {
                        __index    = _G,
                        __newindex = _G,
                    }
                )

                local prevPreload = package.preload[short]
                package.preload[short] = function()
                    local chunk, err = loadfile(init, "t", env)
                    if not chunk then error(err, 0) end
                    return chunk(short, init)
                end

                -- Tag every setting/menu/var/tool the plugin defines as
                -- plugin-origin so the Tools panel can filter it out.
                local prevOrigin = ms._defineOrigin
                ms._defineOrigin = "plugin"
                local ok, err = pcall(function() return hs.loadSpoon(short) end)
                ms._defineOrigin = prevOrigin

                package.preload[short] = prevPreload

                if not ok then
                    ms.plugins.unload(dir, { quiet = true })
                    ms.plugins.failed[dir] = tostring(err)
                    return false, tostring(err)
                end

                ms.plugins.loaded[dir] = true
                ms.plugins.failed[dir] = nil
                return true
            end

            ms.plugins.loadAll = function()
                if not (ms.package and ms.package.listPlugins) then return end
                for _, p in ipairs(ms.package.listPlugins()) do
                    if p.enabled and p.status == "ok" then
                        local ok, err = ms.plugins.load(p.dir)
                        if not ok then
                            print("Plugin " .. p.dir .. " failed to load: " .. tostring(err))
                        end
                    end
                end
            end
        -- END Load --

        -- Unload --
            ms.plugins.unload = function(dir, opts)
                opts = opts or {}
                if not (ms.package and ms.package.validSpoonName
                    and ms.package.validSpoonName(dir)) then
                    return false, "Invalid plugin name."
                end

                local short = shortName(dir)
                local obj   = _G.spoon and _G.spoon[short]

                if type(obj) == "table" and type(obj.stop) == "function" then
                    local ok, err = pcall(function() obj:stop() end)
                    if not ok and not opts.quiet then
                        print("Plugin " .. dir .. " stop() error: " .. tostring(err))
                    end
                end

                local undo = ms.plugins._undo[dir] or {}
                for i = #undo, 1, -1 do
                    local ok, err = pcall(undo[i])
                    if not ok and not opts.quiet then
                        print("Plugin " .. dir .. " teardown error: " .. tostring(err))
                    end
                end
                ms.plugins._undo[dir] = nil

                package.loaded[short] = nil
                if _G.spoon then _G.spoon[short] = nil end
                ms.plugins.loaded[dir] = nil

                if ms.ui and ms.ui.markDirty then pcall(ms.ui.markDirty) end
                return true
            end
        -- END Unload --

        -- Apply --
            ms.plugins.apply = function()
                if not (ms.package and ms.package.listPlugins) then return end
                for _, p in ipairs(ms.package.listPlugins()) do
                    local running = ms.plugins.loaded[p.dir] == true
                    local want    = p.enabled and p.status == "ok"
                    if want and not running then
                        ms.plugins.load(p.dir)
                    elseif running and not want then
                        ms.plugins.unload(p.dir)
                    end
                end
                for dir in pairs(ms.plugins.loaded) do
                    if not hs.fs.attributes(_spoons .. "/" .. dir) then
                        ms.plugins.unload(dir, { quiet = true })
                    end
                end
            end
        -- END Apply --

    end
-- END ms_plugins --

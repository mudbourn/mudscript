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

        local _noted = {}
        local _cache = nil
        local _offerTimer = nil

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
                                if ms._userSettingVals and ms._userSettingVals[k] ~= nil then
                                    ms._pendingUserSettings = ms._pendingUserSettings or {}
                                    ms._pendingUserSettings[k] = ms._userSettingVals[k]
                                    ms._userSettingVals[k] = nil
                                end
                            end
                        end)
                        return out
                    end,
                })

                overrides.setTargetApp = function(name)
                    ms.offerTargetApp(name)
                    record(dir, function() ms.withdrawTargetApp(name) end)
                end

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

                overrides.builder = subProxy(ms.builder, {
                    define = function(def)
                        local out = ms.builder.define(def)
                        record(dir, function()
                            if type(def) == "table" and def.id and ms._builderIndex then
                                ms._builderIndex[def.id] = nil
                            end
                            removeValue(ms._builderBlocks, def)
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

        -- Dependencies --
            local CORE_NAMES = { macroMeta = true }

            local STATE_TEXT = {
                loaded        = "loaded",
                disabled      = "installed but disabled",
                unverified    = "installed but not verified",
                notLoaded     = "installed but not loaded",
                notInstalled  = "not installed",
                unknown       = "unknown",
            }

            local function readMeta(dir)
                local f = io.open(_spoons .. "/" .. dir .. "/meta.json", "r")
                if not f then return nil end
                local raw = f:read("*all")
                f:close()
                local ok, doc = pcall(hs.json.decode, raw)
                if ok and type(doc) == "table" then return doc end
                return nil
            end

            local function collect(useCache)
                if useCache and _cache then return _cache.byNs, _cache.byId end
                local byNs   = {}
                local byId   = {}
                local rows   = {}

                if ms.package and ms.package.listPlugins then
                    local ok, list = pcall(ms.package.listPlugins)
                    for _, p in ipairs(ok and type(list) == "table" and list or {}) do
                        local meta  = readMeta(p.dir)
                        local state = "notLoaded"
                        if ms.plugins.loaded[p.dir] then
                            state = "loaded"
                        elseif not p.enabled then
                            state = "disabled"
                        elseif p.status ~= "ok" then
                            state = "unverified"
                        end
                        local row = {
                            id    = (meta and meta.id) or p.id,
                            name  = (meta and meta.name) or p.name,
                            dir   = p.dir,
                            state = state,
                        }
                        rows[#rows + 1] = row
                        if row.id then byId[row.id] = row end
                        local provides = meta and meta.provides
                        for _, ns in ipairs(type(provides) == "table" and provides or {}) do
                            if type(ns) == "string" and not byNs[ns] then byNs[ns] = row end
                        end
                    end
                end

                if ms.registry and ms.registry.list then
                    local ok, entries = pcall(ms.registry.list, { type = "plugin" })
                    for _, e in ipairs(ok and type(entries) == "table" and entries or {}) do
                        local row = byId[e.id]
                        if not row then
                            row = {
                                id    = e.id,
                                name  = e.name,
                                state = "notInstalled",
                            }
                            byId[e.id] = row
                        end
                        for _, ns in ipairs(type(e.provides) == "table" and e.provides or {}) do
                            if type(ns) == "string" and not byNs[ns] then byNs[ns] = row end
                        end
                    end
                end

                _cache = {
                    byNs = byNs,
                    byId = byId,
                }
                return byNs, byId
            end

            local function stripComments(source)
                local src = source:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
                return src
            end

            ms.plugins.stateText = function(state)
                return STATE_TEXT[state] or STATE_TEXT.unknown
            end

            ms.plugins.scanDeps = function(source, opts)
                opts = opts or {}
                local out = {}
                if type(source) ~= "string" then return out end

                local byNs = collect()
                local seen = {}
                local src  = stripComments(source)

                for start, ns, pos in src:gmatch("()%f[%w_]ms%.([%a_][%w_]*)()") do
                    local prev = start > 1 and src:sub(start - 1, start - 1) or ""
                    if not seen[ns] and prev ~= "." and prev ~= ":" then
                        seen[ns] = true
                        local assigned = src:match("^%s*=[^=]", pos) ~= nil
                        local row = byNs[ns]
                        if assigned or CORE_NAMES[ns] then
                            row = nil
                        elseif row then
                            if row.state ~= "loaded" or opts.all then
                                out[#out + 1] = {
                                    namespace = ns,
                                    id        = row.id,
                                    name      = row.name,
                                    dir       = row.dir,
                                    state     = row.state,
                                }
                            end
                        elseif ms[ns] == nil then
                            out[#out + 1] = {
                                namespace = ns,
                                state     = "unknown",
                            }
                        end
                    end
                end

                table.sort(out, function(a, b) return a.namespace < b.namespace end)
                return out
            end

            ms.plugins.scanFiles = function(paths, opts)
                local out  = {}
                local seen = {}
                for _, path in ipairs(paths or {}) do
                    local f = io.open(path, "r")
                    if f then
                        local raw = f:read("*all")
                        f:close()
                        for _, dep in ipairs(ms.plugins.scanDeps(raw, opts)) do
                            if not seen[dep.namespace] then
                                seen[dep.namespace] = true
                                out[#out + 1] = dep
                            end
                        end
                    end
                end
                return out
            end

            ms.plugins.macroPaths = function(name)
                local out = {}
                local rels = {
                    "ms_macros.lua",
                    "data/ms_macros_visual.lua",
                }
                for _, rel in ipairs(rels) do
                    local path = ms.profile.path(rel, name)
                    if path then out[#out + 1] = path end
                end
                return out
            end

            ms.plugins.statusById = function(id)
                local _, byId = collect()
                local row = byId[id]
                if row then return row end
                return {
                    id    = id,
                    name  = id,
                    state = "unknown",
                }
            end

            ms.plugins.missingFromManifest = function(manifest)
                local out = {}
                local rq  = type(manifest) == "table" and manifest.requires
                local ids = type(rq) == "table" and rq.plugins
                for _, id in ipairs(type(ids) == "table" and ids or {}) do
                    if type(id) == "string" then
                        local row = ms.plugins.statusById(id)
                        if row.state ~= "loaded" then out[#out + 1] = row end
                    end
                end
                return out
            end

            ms.plugins.depLines = function(rows)
                local lines = {}
                for _, row in ipairs(rows or {}) do
                    lines[#lines + 1] = "Needs plugin: " .. tostring(row.name or row.id)
                        .. " (" .. ms.plugins.stateText(row.state) .. ")"
                end
                return lines
            end

            ms.plugins.otherWarnings = function(warnings)
                local out = {}
                for _, w in ipairs(type(warnings) == "table" and warnings or {}) do
                    if type(w) == "string" and not w:find("^Needs plugin:") then
                        out[#out + 1] = w
                    end
                end
                return out
            end

            ms.plugins.offer = function(rows, notes)
                rows  = rows or {}
                notes = notes or {}
                if #rows == 0 and #notes == 0 then return end
                if not (ms.ui and ms.ui.modal) then return end

                local installs, enables = {}, {}
                for _, r in ipairs(rows) do
                    if r.state == "notInstalled" then
                        installs[#installs + 1] = r
                    elseif r.state == "disabled" then
                        enables[#enables + 1] = r
                    end
                end

                local lines = {}
                for _, n in ipairs(notes) do lines[#lines + 1] = n end
                for _, l in ipairs(ms.plugins.depLines(rows)) do lines[#lines + 1] = l end

                local actionable = #installs + #enables > 0
                local confirm = "OK"
                if #installs > 0 and #enables > 0 then
                    confirm = "Install and enable"
                elseif #installs > 0 then
                    confirm = "Install"
                elseif #enables > 0 then
                    confirm = "Enable"
                end

                local function show(tries)
                    if ms.ui._modalCallback and tries < 20 then
                        hs.timer.doAfter(0.25, function() show(tries + 1) end)
                        return
                    end
                    ms.ui.modal({
                        title   = #rows > 0 and "Plugins needed" or "Import notes",
                        msg     = table.concat(lines, "\n"),
                        confirm = confirm,
                        cancel  = actionable and "Later" or "Close",
                    }, function(res)
                        if not (actionable and res and res.confirmed) then return end
                        local actions = ms.ui._actions or {}
                        local enabled, installed, failed = {}, {}, {}

                        if ms.package and ms.package.setPluginEnabled then
                            for _, r in ipairs(enables) do
                                ms.package.setPluginEnabled(r.dir, true)
                                enabled[#enabled + 1] = r.name or r.id
                            end
                        end

                        local function finish()
                            _cache = nil
                            if ms.plugins.apply then pcall(ms.plugins.apply) end
                            if ms.ui.markDirty then pcall(ms.ui.markDirty) end
                            if ms.ui.refresh then pcall(ms.ui.refresh) end

                            local parts = {}
                            if #installed > 0 then parts[#parts + 1] = "Installed: " .. table.concat(installed, ", ") end
                            if #enabled > 0 then parts[#parts + 1] = "Enabled: " .. table.concat(enabled, ", ") end
                            if #failed > 0 then parts[#parts + 1] = "Failed: " .. table.concat(failed, ", ") end
                            if #parts > 0 then ms.alert(table.concat(parts, "\n"), 5, true) end
                        end

                        local i = 0
                        local function nextInstall(ok)
                            local prev = installs[i]
                            if prev then
                                local name = prev.name or prev.id
                                if ok then
                                    installed[#installed + 1] = name
                                    local row = ms.plugins.statusById(prev.id)
                                    if row.dir and ms.package and ms.package.setPluginEnabled then
                                        ms.package.setPluginEnabled(row.dir, true)
                                        enabled[#enabled + 1] = name
                                    end
                                else
                                    failed[#failed + 1] = name
                                end
                            end
                            i = i + 1
                            local r = installs[i]
                            if not (r and actions.browseInstall) then
                                finish()
                                return
                            end
                            actions.browseInstall({
                                id     = r.id,
                                label  = r.name,
                                onDone = nextInstall,
                            })
                        end
                        nextInstall()
                    end)
                end
                show(0)
            end

            ms.plugins.reportImport = function(result)
                local manifest = type(result) == "table" and result.manifest or nil
                ms.plugins.offer(
                    ms.plugins.missingFromManifest(manifest),
                    ms.plugins.otherWarnings(type(result) == "table" and result.warnings or nil)
                )
            end

            ms.plugins.scheduleOffer = function()
                if _offerTimer then _offerTimer:stop() end
                _offerTimer = hs.timer.doAfter(0.5, function()
                    _offerTimer = nil
                    pcall(ms.plugins.offerForActive)
                end)
            end

            ms.plugins.offerForActive = function(name)
                local rows = {}
                local seen = {}
                for _, dep in ipairs(ms.plugins.scanFiles(ms.plugins.macroPaths(name))) do
                    if dep.id and dep.state ~= "unknown" and not seen[dep.id] then
                        seen[dep.id] = true
                        rows[#rows + 1] = dep
                    end
                end
                ms.plugins.offer(rows)
            end

            ms.plugins.offerForProfile = function(name)
                pcall(ms.plugins.offerForActive, name)
            end

            ms.plugins.noticeMissing = function()
                local lines = {}
                local seen  = {}
                for _, dep in ipairs(ms.plugins.scanFiles(ms.plugins.macroPaths())) do
                    if dep.state ~= "unknown" and dep.id and not seen[dep.id] then
                        seen[dep.id] = true
                        lines[#lines + 1] = tostring(dep.name or dep.id)
                            .. " (" .. ms.plugins.stateText(dep.state) .. ")"
                    end
                end
                if #lines == 0 then return end
                ms.alert(
                    "Macros need plugins:\n" .. table.concat(lines, "\n")
                        .. "\nOpen Settings > Plugins or Browse.",
                    8,
                    true,
                    { priority = "low" }
                )
            end

            ms.plugins.noteMissing = function(ns)
                if _noted[ns] then return end
                _noted[ns] = true

                local byNs = collect(true)
                local row  = byNs[ns]
                if not row or row.state == "loaded" then return end

                local tail = "which is " .. ms.plugins.stateText(row.state)
                if row.state == "disabled" then
                    tail = tail .. ", enable it in Settings > Plugins"
                end
                local msg = "ms." .. ns .. " comes from the " .. tostring(row.name or row.id)
                    .. " plugin, " .. tail
                print(msg)
            end
        -- END Dependencies --

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

                local prevOrigin = ms._defineOrigin
                local prevPlugin = ms._definePlugin
                ms._defineOrigin = "plugin"
                ms._definePlugin = dir
                local ok, err = pcall(function() return hs.loadSpoon(short) end)
                ms._defineOrigin = prevOrigin
                ms._definePlugin = prevPlugin

                package.preload[short] = prevPreload

                if not ok then
                    ms.plugins.unload(dir, { quiet = true })
                    ms.plugins.failed[dir] = tostring(err)
                    return false, tostring(err)
                end

                ms.plugins.loaded[dir] = true
                _noted = {}
                _cache = nil
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
                    local ok, err = pcall(function() obj:stop(opts) end)
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
                _noted = {}
                _cache = nil

                if ms.ui and ms.ui.markDirty then pcall(ms.ui.markDirty) end
                return true
            end
        -- END Unload --

        -- Apply --
            ms.plugins.apply = function()
            _cache = nil
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

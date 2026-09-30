-- core/safety_nets (Safety Nets) --
    return function(ms)
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
                    -- Seed a minimal stub instead of erroring out of boot when ms_macros.lua is missing
                    print("ms_macros.lua missing at boot; seeding an empty stub: " .. macrosPath)
                    rawSrc = "-- ms_macros.lua was missing at boot and has been reset.\n"
                        .. "-- Activate a macro pack from the Installed Library to restore your macros.\n"
                        .. "ms.macroMeta = { name = \"Recovered\", author = \"\" }\n"
                    local seed = io.open(macrosPath, "w")
                    if seed then
                        seed:write(rawSrc)
                        seed:close()
                    end
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
                -- A bindless file is a legitimately empty profile, so warn rather than fault
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
            -- One-time, non-destructive surfacing of live and saved-profile packs into the library
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
            -- Re-flag each kind's active marker by content fingerprint on every boot
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
    end
-- END core/safety_nets --

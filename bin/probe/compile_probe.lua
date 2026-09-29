-- Compile Probe --
    local root = arg[0]:match("^(.*)/bin/probe/") or "."
    local fixture = arg[1] or (root .. "/bin/probe/fixtures/macros.json")
    local runSteps = tonumber(arg[2]) or 40

    -- JSON Decode --
        local function decode(s)
            local pos = 1

            local function ws()
                pos = s:find("[^%s]", pos) or #s + 1
            end

            local value

            local function str()
                local out = {}
                pos = pos + 1
                while true do
                    local c = s:sub(pos, pos)
                    if c == "" then error("unterminated string") end
                    if c == '"' then
                        pos = pos + 1
                        return table.concat(out)
                    end
                    if c == "\\" then
                        local n = s:sub(pos + 1, pos + 1)
                        local map = {
                            n = "\n",
                            t = "\t",
                            r = "\r",
                            b = "\b",
                            f = "\f"
                        }
                        if n == "u" then
                            out[#out + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
                            pos = pos + 6
                        else
                            out[#out + 1] = map[n] or n
                            pos = pos + 2
                        end
                    else
                        out[#out + 1] = c
                        pos = pos + 1
                    end
                end
            end

            value = function()
                ws()
                local c = s:sub(pos, pos)
                if c == "{" then
                    local t = {}
                    pos = pos + 1
                    ws()
                    if s:sub(pos, pos) == "}" then
                        pos = pos + 1
                        return t
                    end
                    while true do
                        ws()
                        local k = str()
                        ws()
                        pos = pos + 1
                        t[k] = value()
                        ws()
                        local d = s:sub(pos, pos)
                        pos = pos + 1
                        if d == "}" then return t end
                    end
                elseif c == "[" then
                    local t = {}
                    pos = pos + 1
                    ws()
                    if s:sub(pos, pos) == "]" then
                        pos = pos + 1
                        return t
                    end
                    while true do
                        t[#t + 1] = value()
                        ws()
                        local d = s:sub(pos, pos)
                        pos = pos + 1
                        if d == "]" then return t end
                    end
                elseif c == '"' then
                    return str()
                elseif s:sub(pos, pos + 3) == "true" then
                    pos = pos + 4
                    return true
                elseif s:sub(pos, pos + 4) == "false" then
                    pos = pos + 5
                    return false
                elseif s:sub(pos, pos + 3) == "null" then
                    pos = pos + 4
                    return nil
                end
                local num = s:match("^-?[%d%.eE+-]+", pos)
                pos = pos + #num
                return tonumber(num)
            end

            return value()
        end
    -- END JSON Decode --

    -- Host Stubs --
        local calls = {}

        local function record(name)
            return function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    local v = select(i, ...)
                    parts[#parts + 1] = type(v) == "table" and "{...}" or tostring(v)
                end
                calls[#calls + 1] = name .. "(" .. table.concat(parts, ", ") .. ")"
                if #calls >= runSteps then error("probe: step budget reached", 0) end
            end
        end

        hs = {
            fs = {
                attributes = function()
                    return nil
                end
            },
            json = {
                decode = decode,
                encode = function()
                    return "{}"
                end
            },
            timer = {
                doAfter = function() end
            }
        }

        local defined = {}

        local ms = setmetatable({
            bind = {
                define = function(id, fn, opts)
                    defined[#defined + 1] = {
                        id = id,
                        fn = fn,
                        opts = opts
                    }
                end
            },
            settings = {
                get = function(key)
                    return 100
                end
            },
            vars = {},
            fn = setmetatable({
                define = function() end
            }, {
                __call = function(_, f)
                    return f
                end
            }),
            keystate = function()
                return true
            end,
            mousestate = function()
                return true
            end
        }, {
            __index = function(t, k)
                local f = record("ms." .. k)
                rawset(t, k, f)
                return f
            end
        })
    -- END Host Stubs --

    -- Run --
        local f = assert(io.open(fixture, "r"))
        local data = decode(f:read("*a"))
        f:close()

        local chunk = assert(loadfile(root .. "/mac/lib/ms_compiler.lua"))
        chunk()(ms)

        local ids = {}
        for id in pairs(data.macros or {}) do ids[#ids + 1] = id end
        table.sort(ids)

        local failures = 0
        for _, id in ipairs(ids) do
            local def = data.macros[id]
            def.id = id
            print("== " .. id)
            local ok, code = pcall(ms.compiler.compile, def)
            if not ok then
                failures = failures + 1
                print("COMPILE ERROR  " .. tostring(code))
            else
                local fn, err = loadstring(code, "=" .. id)
                if not fn then
                    failures = failures + 1
                    print("SYNTAX ERROR  " .. err)
                    print(code)
                else
                    defined = {}
                    setfenv(fn, setmetatable({ ms = ms }, { __index = _G }))
                    local okRun, runErr = pcall(fn)
                    local entry = defined[1]
                    if not okRun then
                        failures = failures + 1
                        print("LOAD ERROR  " .. tostring(runErr))
                    elseif not entry then
                        failures = failures + 1
                        print("NO BIND  compiled code never called ms.bind.define")
                    else
                        print("bind  label=" .. tostring(entry.opts.label) .. "  group=" .. tostring(entry.opts.group) .. "  key=" .. tostring(entry.opts.default and entry.opts.default.key))
                        calls = {}
                        local okFire, fireErr = pcall(entry.fn)
                        print("fire  " .. #calls .. " host call(s)" .. (okFire and "" or "  stopped: " .. tostring(fireErr)))
                        for i = 1, math.min(#calls, 12) do print("  " .. calls[i]) end
                    end
                end
            end
        end

        print(("probe: %d macro(s), %d failure(s)"):format(#ids, failures))
        os.exit(failures == 0 and 0 or 1)
    -- END Run --
-- END Compile Probe --

-- core/utilities (Utilities) --
    return function(ms)

        ms.log = function(kind, a, b)
            if not ms.dev then return end
            local msg
            if kind == "if" then
                msg = "if (" .. tostring(a) .. ") -> " .. tostring(b)
            elseif kind == "for" then
                msg = "for " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
            elseif kind == "while" then
                msg = "while " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
            elseif kind == "repeat" then
                msg = "repeat until " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
            else
                msg = tostring(kind) .. (a and (" " .. tostring(a)) or "")
            end
            if spoon and ms.devtools then
                ms.devtools:macroLog(msg)
            end
        end

        ms._fnAccum = {
            lastLabel = nil,
            count = 0,
            startTime = 0,
            timer = nil,
        }
        local _fnFlush = function()
            local a = ms._fnAccum
            if a.count > 0 and a.lastLabel then
                local dur = math.floor((hs.timer.absoluteTime() - a.startTime) / 1e6)
                local msg = a.lastLabel
                if a.count > 1 then msg = msg .. " \195\151" .. a.count end
                if dur > 0 then msg = msg .. " (" .. dur .. "ms)" end
                if ms.dev and ms.dev.log then
                    ms.dev.log({
                        type = "step",
                        category = "macro",
                        msg = "[" .. a.lastLabel .. "] " .. msg,
                    })
                end
            end
            a.count = 0
            a.lastLabel = nil
            a.timer = nil
        end

        local _msFnWrap = function(fn, labelOrAsync)
            assert(type(fn) == "function", "ms.fn: fn must be a function")
            if labelOrAsync == false then return fn end

            local fnLabel = type(labelOrAsync) == "string" and labelOrAsync or nil

            return function(...)
                local label = fnLabel or ms._pendingLabel or "macro"
                ms._pendingLabel = nil

                local a = ms._fnAccum
                if a.lastLabel == label then
                    a.count = a.count + 1
                else
                    _fnFlush()
                    a.lastLabel = label
                    a.count = 1
                    a.startTime = hs.timer.absoluteTime()
                end
                if a.timer then a.timer:stop() end
                a.timer = hs.timer.doAfter(0.05, _fnFlush)

                local ctx = {
                    cancelled  = false,
                    paused     = false,
                    callStack  = { label },
                }

                local coBody = function(...)
                    if ms.dev and ms.dev.log then
                        ms.dev.log({
                            type = "step",
                            category = "macro",
                            msg = "[" .. label .. "] ▶",
                        })
                    end
                    local xok, xerr = xpcall(fn, debug.traceback, ...)
                    if ms.dev and ms.dev.log then
                        ms.dev.log({
                            type = "step",
                            category = "macro",
                            msg = "[" .. label .. "] ■",
                        })
                    end
                    if not xok then
                        local tb = tostring(xerr)
                        print("=== ms.fn error [" .. label .. "] ===\n" .. tb)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({
                                type = "error",
                                event = "macro_error",
                                macro = label,
                                msg = tb,
                            })
                        end
                        ms.alert("Macro error [" .. label .. "], see console", 6)
                    end
                end
                local co = coroutine.create(coBody)
                ms._coroContext[co]    = ctx
                ms._activeContexts[ctx] = true

                if ms.dev and ms._branchTrace then ms.devtools:startTrace(co, label) end

                local ok, err = coroutine.resume(co, ...)
                if not ok then
                    print("=== ms.fn resume error [" .. label .. "] ===\n" .. tostring(err))
                end

                if coroutine.status(co) == "dead" then
                    if ms.dev then ms.devtools:stopTrace(co) end
                    ms._coroContext[co]    = nil
                    ms._activeContexts[ctx] = nil
                end
            end
        end

        ms.fn = setmetatable({
            registry = {
                _defs = {},
                _defList = {},
            },

            define = function(id, fn, opts)
                assert(type(id) == "string", "ms.fn.define: id must be a string")
                local fnType = type(fn)
                assert(fnType == "function" or (fnType == "table" and getmetatable(fn) and getmetatable(fn).__call),
                    "ms.fn.define: fn must be a function or callable table")
                assert(not ms.fn.registry._defs[id],
                    "ms.fn.define: '" .. id .. "' is already registered")
                opts = opts or {}
                ms.fn.registry._defs[id] = {
                    fn      = fn,
                    label   = opts.label or id,
                    group   = opts.group or "user",
                    info    = opts.info,
                    params  = opts.params,
                    icon    = opts.icon,
                    cleared = opts.cleared ~= false,
                }
                table.insert(ms.fn.registry._defList, id)
            end,

            lookup = function(id)
                return ms.fn.registry._defs[id]
            end,

            list = function()
                return ms.fn.registry._defList
            end,
        }, {
            __call = function(_, fn, labelOrAsync)
                return _msFnWrap(fn, labelOrAsync)
            end,
        })

        ms._capturedStack = nil

        ms._getLabel = function()
            local co = coroutine.running()
            if co then
                local ctx = ms._coroContext[co]
                if ctx and ctx.callStack and #ctx.callStack > 0 then
                    return ctx.callStack[#ctx.callStack]
                end
            end
            if ms._capturedStack and #ms._capturedStack > 0 then
                return ms._capturedStack[#ms._capturedStack]
            end
            return nil
        end

        -- ms.callFn(id) invokes a named function tool inline
        ms.callFn = function(id)
            if type(id) ~= "string" then return end
            local function callable(f)
                return type(f) == "function"
                    or (type(f) == "table" and getmetatable(f)
                        and getmetatable(f).__call)
            end
            -- First a registered function tool (builder-authored).
            local def = ms.fn and ms.fn.registry and ms.fn.registry._defs[id]
            if def and callable(def.fn) then return def.fn() end
            -- Then any bound macro from the pack, by its bind id
            local wired = ms.bind and ms.bind._wires and ms.bind._wires[id]
            if callable(wired) then return wired() end
            -- Then a tool registered via ms.tools.define
            local tool = ms._toolIndex and ms._toolIndex[id]
            if tool and callable(tool.run) then return tool.run() end
            print("ms.callFn: no function tool or macro named '" .. tostring(id) .. "'")
        end

        -- ms.vars, disk-persistent shared helper variables
        do
            local varsPath = os.getenv("HOME")
                .. "/.hammerspoon/data/ms_helpervars.json"
            local store = { defs = {}, vals = {} }
            local loaded = false

            local function coerce(def, v)
                if not def then return v end
                if def.type == "number" then
                    local n = tonumber(v)
                    return n or tonumber(def.default) or 0
                elseif def.type == "boolean" then
                    return v == true or v == "true"
                end
                return v
            end

            local function persist()
                local ok, enc = pcall(hs.json.encode, store, true)
                if not ok then return end
                local f = io.open(varsPath, "w")
                if f then
                    f:write(enc)
                    f:close()
                end
            end

            local function ensureLoaded()
                if loaded then return end
                loaded = true
                local f = io.open(varsPath, "r")
                if not f then return end
                local raw = f:read("*all")
                f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if ok and type(data) == "table" then
                    store.defs = type(data.defs) == "table" and data.defs or {}
                    store.vals = type(data.vals) == "table" and data.vals or {}
                end
            end

            ms.vars = {}

            ms.vars.reload = function()
                store.defs = {}
                store.vals = {}
                loaded = false
            end

            -- Read a helper var live
            ms.vars.get = function(name)
                ensureLoaded()
                if type(name) ~= "string" then return nil end
                local v = store.vals[name]
                if v == nil then
                    local def = store.defs[name]
                    return def and def.default or nil
                end
                return v
            end

            -- Write a helper var and persist
            ms.vars.set = function(name, value)
                ensureLoaded()
                if type(name) ~= "string"
                    or not name:match("^[%a_][%w_]*$") then return end
                store.vals[name] = coerce(store.defs[name], value)
                persist()
                return store.vals[name]
            end

            -- Declare (or update) a helper var from the Tools panel.
            ms.vars.define = function(def)
                ensureLoaded()
                if type(def) ~= "table" then return false, "definition must be a table" end
                local name = type(def.name) == "string" and def.name or ""
                if not name:match("^[%a_][%w_]*$") then
                    return false, "name must be a valid identifier"
                end
                local t = def.type
                if t ~= "number" and t ~= "string" and t ~= "boolean" then
                    t = "string"
                end
                store.defs[name] = {
                    type    = t,
                    default = def.default,
                    label   = type(def.label) == "string" and def.label or name,
                    hint    = type(def.hint) == "string" and def.hint or nil,
                    -- Where the declaration came from, for the Tools filter
                    origin  = def.origin or ms._defineOrigin or "user",
                }
                if store.vals[name] == nil then
                    store.vals[name] = coerce(store.defs[name], def.default)
                end
                persist()
                return true
            end

            ms.vars.remove = function(name)
                ensureLoaded()
                if store.defs[name] == nil and store.vals[name] == nil then
                    return false, "'" .. tostring(name) .. "' is not a helper var"
                end
                store.defs[name] = nil
                store.vals[name] = nil
                persist()
                return true
            end

            -- List declarations (with live values) for the builder.
            ms.vars.list = function()
                ensureLoaded()
                local out = {}
                for name, def in pairs(store.defs) do
                    out[#out + 1] = {
                        name    = name,
                        type    = def.type,
                        default = def.default,
                        label   = def.label,
                        hint    = def.hint,
                        value   = store.vals[name],
                        origin  = def.origin or "user",
                    }
                end
                table.sort(out, function(a, b) return a.name < b.name end)
                return out
            end
        end

        ms._getRootLabel = function()
            local co = coroutine.running()
            if co then
                local ctx = ms._coroContext[co]
                if ctx and ctx.callStack and #ctx.callStack > 0 then
                    return ctx.callStack[1]
                end
            end
            if ms._capturedStack and #ms._capturedStack > 0 then
                return ms._capturedStack[1]
            end
            return nil
        end

        ms._getCallChain = function()
            local co = coroutine.running()
            local stack = nil
            if co then
                local ctx = ms._coroContext[co]
                stack = ctx and ctx.callStack
            end
            if not stack and ms._capturedStack then
                stack = ms._capturedStack
            end
            if stack and #stack > 0 then
                if #stack == 1 then
                    return stack[1]
                else
                    return stack[1] .. " > " .. stack[#stack]
                end
            end
            return nil
        end

        ms.sub = function(label, fn)
            assert(type(fn) == "function", "ms.sub: fn must be a function")
            return function(...)
                local co = coroutine.running()
                local ctx = co and ms._coroContext[co]
                if ctx then
                    if not ctx.callStack then ctx.callStack = {} end
                    table.insert(ctx.callStack, label)
                    local results = { fn(...) }
                    table.remove(ctx.callStack)
                    return table.unpack(results)
                end
                if ms._capturedStack then
                    table.insert(ms._capturedStack, label)
                    local results = { fn(...) }
                    table.remove(ms._capturedStack)
                    return table.unpack(results)
                end
                return fn(...)
            end
        end

        ms.pause = function(id)
            if not id then
                for _, ctx in pairs(ms._activeContexts) do ctx.paused = true end
                return
            end
            for _, ctx in pairs(ms._activeContexts) do
                if ctx.callStack and ctx.callStack[1] == id then ctx.paused = true
                return end
            end
        end

        ms.resume = function(id)
            local function _resume(co)
                local ctx = ms._coroContext[co]
                if not ctx then return end
                ctx.paused = false
                if coroutine.status(co) ~= "suspended" then return end
                local ok, err = coroutine.resume(co)
                if not ok then
                    print("=== ms.resume error [" .. (ctx.callStack and ctx.callStack[1] or "?") .. "] ===\n" .. tostring(err))
                end
                if coroutine.status(co) == "dead" then
                    if ms.dev then ms.devtools:stopTrace(co) end
                    ms._coroContext[co] = nil
                    ms._activeContexts[ctx] = nil
                end
            end
            if not id then
                for co in pairs(ms._coroContext) do _resume(co) end
                return
            end
            for co, ctx in pairs(ms._coroContext) do
                if ctx.callStack and ctx.callStack[1] == id then _resume(co)
                return end
            end
        end

        ms.copy = function(text)
            if ms.dev._watcherPanel then
                ms.devtools:watcherStep("copy")
            end
            if ms.dev then
                ms.devtools:macroLog("copy")
            end
            hs.pasteboard.setContents(text)
        end

        ms.paste = function()
            if ms.dev._watcherPanel then
                ms.devtools:watcherStep("paste")
            end
            if ms.dev then
                ms.devtools:macroLog("paste")
            end
            ms.type("v", { ms.windowsMode and "ctrl" or "cmd" })
        end

        -- Expand {name} tokens in a string at runtime against helper vars
        ms.interp = function(s)
            if type(s) ~= "string" then return s end
            if not s:find("{", 1, true) then return s end
            local depth = 0
            while depth < 8 and s:find("{[%a_][%w_]*}") do
                local changed = false
                s = s:gsub("{([%a_][%w_]*)}", function(name)
                    changed = true
                    local v = ms.vars and ms.vars.get and ms.vars.get(name)
                    if v == nil then return "" end
                    return tostring(v)
                end)
                depth = depth + 1
                if not changed then break end
            end
            return s
        end

        ms.cancelMacros = function()
            for co, ctx in pairs(ms._coroContext) do
                ctx.cancelled = true
                if ms.dev then ms.devtools:stopTrace(co) end
            end

            ms._activeContexts = {}
            ms._coroContext     = {}

            for keyCode, entry in pairs(ms._macroHeldKeys) do
                local ev = hs.eventtap.event.newKeyEvent(entry.mods, keyCode, false)
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end
            ms._macroHeldKeys = {}

            for btn, entry in pairs(ms._macroHeldButtons) do
                local ev = hs.eventtap.event.newMouseEvent(entry.upT, entry.pos)
                if btn >= 2 then
                    ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                end
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end
            ms._macroHeldButtons = {}
        end

        ms._soundsDirty = true

        ms.soundExtensions = {
            "wav",
            "aiff",
            "aif",
            "mp3",
            "m4a",
            "caf",
            "aac",
        }

        ms.isSoundFile = function(file)
            local ext = file:match("%.([^%.]+)$")
            if not ext then return false end
            ext = ext:lower()
            for _, e in ipairs(ms.soundExtensions) do
                if e == ext then return true end
            end
            return false
        end

        ms._autoSortSounds = function()
            local SoundLib = hs.configdir .. "/sounds/"
            local dirs = {
                {
                    dir = SoundLib .. "defaults/",
                    prefix = "d_",
                },
                {
                    dir = SoundLib .. "active/",
                    prefix = "a_",
                },
                {
                    dir = SoundLib .. "macro/",
                    prefix = "m_",
                },
            }
            for _, info in ipairs(dirs) do
                if hs.fs.attributes(info.dir) then
                    for file in hs.fs.dir(info.dir) do
                        if file ~= "." and file ~= ".." and ms.isSoundFile(file) then
                            for _, dest in ipairs(dirs) do
                                if file:sub(1, #dest.prefix) == dest.prefix
                                    and dest.dir ~= info.dir then
                                    local src = info.dir .. file
                                    local dst = dest.dir .. file
                                    if not hs.fs.attributes(dst) then
                                        os.rename(src, dst)
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        ms._discoverSounds = function()
            if not ms._soundsDirty then return end
            ms._soundsDirty = false
            ms.sounds      = {}
            ms.macroSounds = {}

            pcall(ms._autoSortSounds)

            -- WAV Header Repair --
                local function _wavU16(s, o)
                    return s:byte(o + 1) + s:byte(o + 2) * 256
                end

                local function _wavU32(s, o)
                    return s:byte(o + 1)
                        + s:byte(o + 2) * 256
                        + s:byte(o + 3) * 65536
                        + s:byte(o + 4) * 16777216
                end

                local function _sanitizeWav(path)
                    local f = io.open(path, "rb")
                    if not f then return end
                    local head = f:read(4096) or ""
                    f:close()
                    if head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then return end
                    local i = 12
                    while i + 8 <= #head do
                        local cid = head:sub(i + 1, i + 4)
                        local sz  = _wavU32(head, i + 4)
                        if cid == "fmt " and i + 8 + 16 <= #head then
                            local base = i + 8
                            if _wavU16(head, base) ~= 1 then return end
                            local ch   = _wavU16(head, base + 2)
                            local rate = _wavU32(head, base + 4)
                            local bits = _wavU16(head, base + 14)
                            local expBA = ch * math.floor(bits / 8)
                            local expBR = rate * expBA
                            if expBA <= 0 then return end
                            if _wavU16(head, base + 12) == expBA
                                and _wavU32(head, base + 8) == expBR then return end
                            local w = io.open(path, "r+b")
                            if not w then return end
                            w:seek("set", base + 8)
                            w:write(string.char(
                                expBR % 256,
                                math.floor(expBR / 256) % 256,
                                math.floor(expBR / 65536) % 256,
                                math.floor(expBR / 16777216) % 256
                            ))
                            w:seek("set", base + 12)
                            w:write(string.char(expBA % 256, math.floor(expBA / 256) % 256))
                            w:close()
                            return
                        end
                        i = i + 8 + sz + (sz % 2)
                    end
                end
            -- END --

            local function scanDir(dir, target)
                target = target or ms.sounds
                if not hs.fs.attributes(dir) then return end
                for file in hs.fs.dir(dir) do
                    if file ~= "." and file ~= ".." and ms.isSoundFile(file) then
                        local name = file:match("^(.+)%.[^%.]+$")
                        if name then
                            if file:lower():match("%.wav$") then
                                pcall(_sanitizeWav, dir .. file)
                            end
                            target[name] = dir .. file
                        end
                    end
                end
            end

            scanDir(SoundDefaultsDir)

            if not ms._customThemeDisabled then
                scanDir(SoundActiveDir)
            end

            scanDir(SoundMacroDir, ms.macroSounds)

            for name, filename in pairs(ms.importedSounds or {}) do
                if not ms._customThemeDisabled and not ms.sounds[name] then
                    local path = SoundLib .. filename
                    if hs.fs.attributes(path) then
                        ms.sounds[name] = path
                    end
                end
            end

            -- Warn once when slot assignments no longer resolve
            local missing = 0
            for _, name in pairs(ms.soundAssign or {}) do
                if type(name) == "string" and name ~= ""
                    and not ms.sounds[name] and not ms.macroSounds[name] then
                    missing = missing + 1
                end
            end
            if missing > 0 then
                local sig = missing .. "@" .. SoundActiveDir
                if sig ~= ms._missingSoundsSig then
                    ms._missingSoundsSig = sig
                    local msg = missing .. " assigned sound"
                        .. (missing == 1 and "" or "s")
                        .. " could not be found. Active sound folder may be "
                        .. "empty or misplaced (" .. SoundActiveDir
                        .. "). Falling back to defaults."
                    print("ms.sound: " .. msg)
                    if ms.dev and ms.dev.log then
                        pcall(ms.dev.log, {
                            type  = "warning",
                            event = "active_sounds_missing",
                            msg   = msg,
                            count = missing,
                        })
                    end
                    if ms.alert and ms.shell and ms.shell.isReady
                        and ms.shell.isReady() then
                        pcall(ms.alert, "Missing sounds\n" .. msg, 6)
                    end
                end
            else
                ms._missingSoundsSig = nil
            end
        end

        ms.sound = function(path, async, device)
            if path and not path:match("[/\\]") then
                path = ms.sounds[path] or ms.macroSounds[path] or path
            end
            if path then
                local fname = tostring(path):match("([^/\\]+)$") or tostring(path)
                if fname ~= ms._lastSoundLog then
                    ms._lastSoundLog = fname
                    if ms.dev then
                        local displayLabel = ms._getCallChain()
                        if displayLabel then
                            ms.dev.log({
                                type = "sound",
                                msg = "[" .. displayLabel .. "] " .. fname,
                                category = "macro"
                            })
                        end
                    end
                end
            end
            if not ms.soundEnabled then return end
            if not path then return end
            local s = hs.sound.getByFile(path) or hs.sound.getByName(path)
            if not s then
                print("ms.sound: could not load sound: " .. tostring(path))
                return
            end
            if ms.soundVolume ~= nil then
                s:volume(ms.soundVolume / 100)
            end
            if device then
                local dev = hs.audiodevice.findOutputByName(device)
                if dev then s:device(dev:uid()) end
            end
            async = (async ~= false)
            if not async then
                local co  = coroutine.running()
                local ctx = co and ms._coroContext[co]
                if co then
                    s:setCallback(function(snd, state)
                        if state == "stop" then
                            snd:setCallback(nil)
                            if ctx and ctx.cancelled then return end
                            local ok, err = coroutine.resume(co)
                            if not ok then
                                print("ms.sound resume error: " .. tostring(err))
                            end
                            if coroutine.status(co) == "dead" then
                                if ms.dev then ms.devtools:stopTrace(co) end
                                ms._coroContext[co] = nil
                                if ctx then ms._activeContexts[ctx] = nil end
                            end
                        end
                    end)
                    s:play()
                    coroutine.yield()
                    return
                end
            end
            s:play()
            return s
        end

        -- Only accept a resolved path that still exists on disk
        local function _slotPathExists(p)
            return type(p) == "string" and hs.fs.attributes(p) ~= nil
        end

        local function _resolveSlot(id)
            local assigned = ms.soundAssign and ms.soundAssign[id]
            if assigned then
                local p = (ms.sounds and ms.sounds[assigned])
                    or (ms.macroSounds and ms.macroSounds[assigned])
                if not p and assigned:find("/", 1, true)
                    and hs.fs.attributes(assigned) then
                    p = assigned
                end
                if _slotPathExists(p) then return p end
            end

            local p = (ms.sounds and ms.sounds[id])
                or (ms.macroSounds and ms.macroSounds[id])
            if _slotPathExists(p) then return p end

            local def = ms.soundSlot(id)
            if def and def.d then
                local dp = ms.sounds and ms.sounds[def.d]
                if _slotPathExists(dp) then return dp end
            end
            return nil
        end

        ms.playSlot = function(slotId)
            if not ms.soundEnabled then return false end
            if ms._quickReloading then return false end
            if ms._octaneMode and ms._octaneMuteSounds then return false end
            if not ms._startupSoundDone and slotId ~= "load" and slotId ~= "themeLoaded" and slotId ~= "updateAvailable" and slotId ~= "settingsOpen" and slotId ~= "settingsClose" then return false end
            ms._slotHandles = ms._slotHandles or {}
            -- Do not stop the slot's previous play before starting the new one
            local path
            for _, id in ipairs(ms.soundSlotChain(slotId)) do
                path = _resolveSlot(id)
                if path then break end
            end
            if not path then return false end
            local handle = ms.sound(path) or false
            if handle then
                ms._slotHandles[slotId] = handle
                ms._slotStartedAt = ms._slotStartedAt or {}
                ms._slotStartedAt[slotId] = hs.timer.secondsSinceEpoch()
            end
            return handle
        end

        ms.fadeOutSounds = function(durationMs, done)
            done = done or function() end
            durationMs = tonumber(durationMs) or 300
            local handles, starts = {}, {}
            for _, h in pairs(ms._slotHandles or {}) do
                if type(h) == "userdata" then
                    local ok, playing = pcall(function() return h:isPlaying() end)
                    if ok and playing then
                        handles[#handles + 1] = h
                        local okv, v = pcall(function() return h:volume() end)
                        starts[#handles] = (okv and v) or 1
                    end
                end
            end
            if #handles == 0 then return done() end
            local steps = 12
            local step  = 0
            local t
            t = hs.timer.doEvery((durationMs / 1000) / steps, function()
                step = step + 1
                local f = 1 - (step / steps)
                if f < 0 then f = 0 end
                for i, h in ipairs(handles) do
                    pcall(function() h:volume(starts[i] * f) end)
                end
                if step >= steps then
                    t:stop()
                    for _, h in ipairs(handles) do
                        pcall(function() h:stop() end)
                    end
                    done()
                end
            end)
        end

        ms._biasedMenuPt = function(raw)
            local p  = raw or hs.mouse.absolutePosition()
            local sf = hs.screen.mainScreen():frame()
            return {
                x = p.x * 0.75 + (sf.x + sf.w * 0.2) * 0.12,
                y = p.y * 0.75 + (sf.y + sf.h * 0.2) * 0.12,
            }
        end

        ms._menuHoverStart = function()
            if ms._menuHoverWatcher then return end
            local lastKey = nil
            ms._menuHoverWatcher = hs.timer.doEvery(0.025, function()
                if not ms._menuVisible then return end
                local el = hs.uielement.focusedElement()
                if not el then return end
                local ok, frame = pcall(function() return el:frame() end)
                if not ok or not frame then return end
                local key = frame.x .. "," .. frame.y
                if key ~= lastKey then
                    lastKey = key
                    ms.playSlot("hover")
                end
            end)
        end

        ms._menuHoverStop = function()
            if ms._menuHoverWatcher then
                ms._menuHoverWatcher:stop()
                ms._menuHoverWatcher = nil
            end
        end

        ms.mousePos = function()
            local win = ms.getTargetWin() or hs.window.focusedWindow()
            local pos = hs.mouse.absolutePosition()
            if not win then return pos.x, pos.y end
            local f = win:frame()
            return pos.x - f.x, pos.y - f.y
        end

        ms.screen = ms.screen or {}
        ms.screen.sampleAt = function(ax, ay)
            if not ax or not ay then return nil end

            local scr = hs.screen.mainScreen()
            for _, s in ipairs(hs.screen.allScreens()) do
                local f = s:frame()
                if ax >= f.x and ax < f.x + f.w
                and ay >= f.y and ay < f.y + f.h then
                    scr = s
                    break
                end
            end
            if not scr then return nil end

            local snap = scr:snapshot(hs.geometry.rect(ax, ay, 1, 1))
            if not snap then return nil end
            local c = snap:colorAt({ x = 0, y = 0 })
            if not c or c.red == nil then return nil end

            local r = math.floor((c.red   or 0) * 255 + 0.5)
            local g = math.floor((c.green or 0) * 255 + 0.5)
            local b = math.floor((c.blue  or 0) * 255 + 0.5)
            local a = math.floor((c.alpha or 1) * 255 + 0.5)
            return {
                r = r, g = g, b = b, a = a,
                hex = string.format("#%02X%02X%02X", r, g, b),
            }
        end

        ms.parseHex = function(hex)
            if type(hex) ~= "string" then return nil end
            local h = hex:gsub("^%s*#", ""):gsub("^0[xX]", ""):gsub("%s+$", "")
            if #h == 3 then h = h:gsub("(%x)", "%1%1") end
            if #h ~= 6 or h:find("[^%x]") then return nil end
            return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
        end

        local function _colorArgs(a, b, c, ...)
            if type(a) == "number" and type(b) == "number" and type(c) == "number" then
                return a, b, c, ...
            end
            local r, g, bl = ms.parseHex(a)
            if not r then error("ms.pixel: color must be a hex string like \"#FF5000\"", 3) end
            return r, g, bl, b, c, ...
        end

        local function _pixelArgs(x, ...)
            if type(x) ~= "table" then return x, ... end
            local t = x
            local color = t.color
            if color == nil and t.r ~= nil then
                return tonumber(t.x), tonumber(t.y), t.reference or t.ref,
                    tonumber(t.r), tonumber(t.g), tonumber(t.b),
                    tonumber(t.tolerance or t.tol), tonumber(t.timeout)
            end
            return tonumber(t.x), tonumber(t.y), t.reference or t.ref, color,
                tonumber(t.tolerance or t.tol), tonumber(t.timeout)
        end

        local function _pixelColor(x, y, reference)
            reference = reference or "Absolute"
            local ax, ay = ms.resolvePoint(x, y, reference)
            if not ax or not ay then return nil end
            local c = ms.screen.sampleAt(ax, ay)
            if not c then return nil end
            return c.hex, c.r, c.g, c.b
        end

        ms.pixelColor = function(...)
            return _pixelColor(_pixelArgs(...))
        end

        local function _pixelMatch(x, y, reference, r, g, b, tolerance)
            tolerance = tolerance or 10
            local _, cr, cg, cb = _pixelColor(x, y, reference)
            if not cr then return false end
            return math.abs(cr - r) <= tolerance
               and math.abs(cg - g) <= tolerance
               and math.abs(cb - b) <= tolerance
        end

        local function _matchArgs(x, y, reference, ...)
            return x, y, reference, _colorArgs(...)
        end

        ms.pixelMatch = function(...)
            return _pixelMatch(_matchArgs(_pixelArgs(...)))
        end

        ms.randWait = function(min, max)
            ms.wait(math.random(min, max))
        end

        ms.jitter = function(base, jitterMs)
            ms.wait(base + math.random(-jitterMs, jitterMs))
        end

        local _savedCursor = nil
        ms.saveCursor = function()
            _savedCursor = hs.mouse.absolutePosition()
            return _savedCursor
        end
        ms.restoreCursor = function()
            if _savedCursor then
                hs.mouse.absolutePosition(_savedCursor)
            end
        end

        ms.appRunning = function(appName)
            return hs.application.get(appName) ~= nil
        end

        ms.appIsFront = function(appName)
            local front = hs.application.frontmostApplication()
            return front and front:name() == appName
        end

        ms.focus = function(appName)
            local app = hs.application.get(appName)
            if app then
                pcall(function() app:activate() end)
                return true
            end
            return false
        end

        ms.toggle = function(key, mods)
            if ms.keystate(key) then
                ms.release(key, mods)
            else
                ms.press(key, mods)
            end
        end

        local function _waitPixel(want, x, y, ref, r, g, b, tol, timeout)
            timeout = timeout or 5000
            local deadline = hs.timer.absoluteTime() + timeout * 1000000
            while hs.timer.absoluteTime() < deadline do
                if _pixelMatch(x, y, ref, r, g, b, tol or 10) == want then return true end
                ms.wait(50)
            end
            return false
        end

        ms.waitPixel = function(...)
            return _waitPixel(true, _matchArgs(_pixelArgs(...)))
        end

        ms.waitNotPixel = function(...)
            return _waitPixel(false, _matchArgs(_pixelArgs(...)))
        end

        ms.screen._ocrBin = os.getenv("HOME") .. "/.local/bin/ms_ocr_read"

        -- Normalise a region arg into an absolute {x,y,w,h} in screen points
        local function _resolveRegion(region)
            local f = hs.screen.mainScreen():frame()
            if type(region) ~= "table" then
                return { x = f.x, y = f.y, w = f.w, h = f.h }
            end
            local x, y = region.x or 0, region.y or 0
            if region.ref then
                x, y = ms.resolvePoint(x, y, region.ref)
            end
            return {
                x = x, y = y,
                w = region.w or f.w,
                h = region.h or f.h,
            }
        end

        -- Capture a region to a temp PNG
        ms.screen.capture = function(region)
            local rg = _resolveRegion(region)
            if not rg.w or not rg.h or rg.w < 1 or rg.h < 1 then return nil end
            -- Pick the screen the region originates on
            local scr = hs.screen.mainScreen()
            for _, s in ipairs(hs.screen.allScreens()) do
                local f = s:frame()
                if rg.x >= f.x and rg.x < f.x + f.w
                and rg.y >= f.y and rg.y < f.y + f.h then
                    scr = s
                    break
                end
            end
            local snap = scr:snapshot(hs.geometry.rect(rg.x, rg.y, rg.w, rg.h))
            if not snap then return nil end
            -- Drop the empty base file, keeping the .png sibling
            local base = os.tmpname()
            os.remove(base)
            local path = base .. ".png"
            if not snap:saveToFile(path) then return nil end
            return path, rg
        end

        -- OCR a region, returning text and blocks
        ms.screen.ocr = function(region, opts)
            opts = opts or {}
            local path, rg = ms.screen.capture(region)
            if not path then return nil end

            local cmd = "'" .. ms.screen._ocrBin .. "' '" .. path .. "'"
                .. (opts.fast and " fast" or "")
            local out = hs.execute(cmd)
            os.remove(path)
            if not out or out == "" then return nil end

            local ok, data = pcall(function() return hs.json.decode(out) end)
            if not ok or type(data) ~= "table"
            or type(data.blocks) ~= "table" then
                return nil
            end
            if data.error then
                print("ms.screen.ocr: " .. tostring(data.error))
                return nil
            end

            -- Pixels-per-point from the helper's reported pixel width
            local sx = (data.w or rg.w) / rg.w
            local sy = (data.h or rg.h) / rg.h
            if sx == 0 then sx = 1 end
            if sy == 0 then sy = 1 end

            local blocks, texts = {}, {}
            for _, b in ipairs(data.blocks) do
                local left = rg.x + (b.x or 0) / sx
                local top  = rg.y + (b.y or 0) / sy
                local w    = (b.w or 0) / sx
                local h    = (b.h or 0) / sy
                blocks[#blocks + 1] = {
                    text = b.text or "",
                    conf = b.conf or 0,
                    x    = left + w / 2,
                    y    = top + h / 2,
                    left = left, top = top, w = w, h = h,
                }
                texts[#texts + 1] = b.text or ""
            end
            return { text = table.concat(texts, "\n"), blocks = blocks }
        end

        -- OCR a region and pull the first number out of it
        ms.screen.readNumber = function(region, opts)
            local res = ms.screen.ocr(region, opts)
            if not res then return nil end
            local cleaned = res.text:gsub(",", "")
            local match = cleaned:match("%-?%d+%.?%d*")
            return match and tonumber(match) or nil
        end

        -- Find on-screen text and return its center
        ms.screen.findText = function(text, region, opts)
            if not text or text == "" then return nil end
            local res = ms.screen.ocr(region, opts)
            if not res then return nil end
            local needle = tostring(text):lower()
            for _, b in ipairs(res.blocks) do
                if b.text:lower():find(needle, 1, true) then
                    return { x = b.x, y = b.y }, b
                end
            end
            return nil
        end

        -- Poll until text appears in the region
        ms.screen.waitText = function(text, region, timeout, opts)
            opts = opts or {}
            timeout = timeout or 5000
            local deadline = hs.timer.absoluteTime() + timeout * 1000000
            while hs.timer.absoluteTime() < deadline do
                local hit = ms.screen.findText(text, region, opts)
                if opts.gone then
                    if not hit then return true end
                elseif hit then
                    return hit
                end
                ms.wait(200)
            end
            return false
        end

        -- Pixel scanning aliases under ms.screen.*
        ms.screen.pixelColor   = ms.pixelColor
        ms.screen.pixelMatch   = ms.pixelMatch
        ms.screen.waitPixel    = ms.waitPixel
        ms.screen.waitNotPixel = ms.waitNotPixel

        -- Flat positional wrappers for the visual builder
        local function _regionFromArgs(x, y, w, h)
            if not w or w <= 0 or not h or h <= 0 then return nil end
            return { x = x or 0, y = y or 0, w = w, h = h }
        end
        ms.ocr = function(x, y, w, h)
            local res = ms.screen.ocr(_regionFromArgs(x, y, w, h))
            return res and res.text or nil
        end
        ms.readNumber = function(x, y, w, h)
            return ms.screen.readNumber(_regionFromArgs(x, y, w, h))
        end
        ms.findText = function(text, x, y, w, h)
            return ms.screen.findText(text, _regionFromArgs(x, y, w, h))
        end
        ms.waitText = function(text, x, y, w, h, timeout)
            return ms.screen.waitText(text, _regionFromArgs(x, y, w, h), timeout)
        end

        ms.waitApp = function(appName, timeout)
            timeout = timeout or 10000
            local deadline = hs.timer.absoluteTime() + timeout * 1000000
            while hs.timer.absoluteTime() < deadline do
                if hs.application.get(appName) then return true end
                ms.wait(100)
            end
            return false
        end

        ms.waitNotApp = function(appName, timeout)
            timeout = timeout or 10000
            local deadline = hs.timer.absoluteTime() + timeout * 1000000
            while hs.timer.absoluteTime() < deadline do
                if not hs.application.get(appName) then return true end
                ms.wait(100)
            end
            return false
        end

        ms.windowPos = function(appName)
            local app = hs.application.get(appName)
            if not app then return nil end
            local win = app:mainWindow()
            if not win then return nil end
            local f = win:frame()
            return {
                x = f.x,
                y = f.y,
                w = f.w,
                h = f.h,
            }
        end

        ms.window = function(operation, a, b, c, d)
            local win = ms.getTargetWin() or hs.window.focusedWindow()
            if not win then return false end
            local op = tostring(operation or "Move"):lower()
            local ok = pcall(function()
                if op == "resize" then
                    win:setSize({
                        w = tonumber(a) or 0,
                        h = tonumber(b) or 0,
                    })
                elseif op == "frame" then
                    win:setFrame({
                        x = tonumber(a) or 0,
                        y = tonumber(b) or 0,
                        w = tonumber(c) or 0,
                        h = tonumber(d) or 0,
                    })
                else
                    win:setTopLeft({
                        x = tonumber(a) or 0,
                        y = tonumber(b) or 0,
                    })
                end
            end)
            return ok
        end

        ms.multiPress = function(keys, delayMs, mods)
            delayMs = delayMs or 15
            for i, key in ipairs(keys) do
                ms.type(key, mods)
                if i < #keys then ms.wait(delayMs) end
            end
        end

        ms.setVolume = function(level)
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev then dev:setVolume(level) end
        end

        ms.mute = function()
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev then dev:setMuted(true) end
        end

        ms.unmute = function()
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev then dev:setMuted(false) end
        end

        ms.screenshot = function(path)
            path = path or os.getenv("HOME") .. "/Desktop/screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
            local screen = hs.screen.mainScreen()
            if not screen then return nil end
            local img = screen:snapshot()
            if not img then return nil end
            img:saveToFile(path)
            return path
        end

        local _clipWatcher = nil
        ms.clipChanged = function(callback)
            if _clipWatcher then _clipWatcher:stop() end
            _clipWatcher = hs.pasteboard.watcher.new(callback)
            _clipWatcher:start()
            return _clipWatcher
        end

        ms.moveMouse = function(x, y, ref, durationMs)
            durationMs = tonumber(durationMs) or 200
            local targetX, targetY = ms.resolvePoint(x, y, ref or "Absolute")
            local startPos = hs.mouse.absolutePosition()
            local startX, startY = startPos.x, startPos.y
            local dx = targetX - startX
            local dy = targetY - startY
            -- Zero-distance or near-instant move: jump and return
            if durationMs <= 16 or (dx == 0 and dy == 0) then
                hs.mouse.absolutePosition({ x = targetX, y = targetY })
                return
            end
            -- Animate synchronously, frame by frame
            local frameMs = 16
            local steps = math.max(1, math.floor(durationMs / frameMs + 0.5))
            for step = 1, steps do
                local t = step / steps
                t = 1 - (1 - t) ^ 3
                hs.mouse.absolutePosition({
                    x = startX + dx * t,
                    y = startY + dy * t,
                })
                if step < steps then ms.wait(frameMs) end
            end
            hs.mouse.absolutePosition({ x = targetX, y = targetY })
        end

        ms.dragPath = function(points, button, ref, delayMs)
            if type(points) == "string" then
                local parsed = {}
                for pair in points:gmatch("[^;]+") do
                    local sx, sy = pair:match("^%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
                    local nx, ny = tonumber(sx), tonumber(sy)
                    if nx and ny then parsed[#parsed + 1] = {
                        nx,
                        ny,
                    } end
                end
                points = parsed
            end
            if type(points) ~= "table" or #points < 2 then return end
            button = button or "Left"
            delayMs = delayMs or 10
            local btnNum = button == "Right" and 1
                or ((button == "Middle" or button == "Center") and 2 or 0)
            local downType = btnNum == 1 and hs.eventtap.event.types.rightMouseDown
                or (btnNum == 2 and hs.eventtap.event.types.otherMouseDown
                or hs.eventtap.event.types.leftMouseDown)
            local upType = btnNum == 1 and hs.eventtap.event.types.rightMouseUp
                or (btnNum == 2 and hs.eventtap.event.types.otherMouseUp
                or hs.eventtap.event.types.leftMouseUp)
            local dragType = btnNum == 1 and hs.eventtap.event.types.rightMouseDragged
                or (btnNum == 2 and hs.eventtap.event.types.otherMouseDragged
                or hs.eventtap.event.types.leftMouseDragged)

            local x1, y1 = ms.resolvePoint(points[1][1], points[1][2], ref or "Absolute")
            hs.mouse.absolutePosition({
                x = x1,
                y = y1,
            })
            local downEv = hs.eventtap.event.newMouseEvent(downType, {
                x = x1,
                y = y1,
            })
            if btnNum > 0 then downEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
            downEv:post()
            ms.wait(delayMs)

            for i = 2, #points do
                local px, py = ms.resolvePoint(points[i][1], points[i][2], ref or "Absolute")
                hs.mouse.absolutePosition({
                    x = px,
                    y = py,
                })
                local dragEv = hs.eventtap.event.newMouseEvent(dragType, {
                    x = px,
                    y = py,
                })
                if btnNum > 0 then dragEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                dragEv:post()
                ms.wait(delayMs)
            end

            local finalPos = hs.mouse.absolutePosition()
            local upEv = hs.eventtap.event.newMouseEvent(upType, finalPos)
            if btnNum > 0 then upEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
            upEv:post()
        end

        ms.notify = function(title, subTitle, infoText)
            local note = hs.notify.new({
                title = title or "mudscript",
                subTitle = subTitle or "",
                informativeText = infoText or "",
            }):send()
            return note
        end

            ms._antiTimeout = {
                fn = nil,
                interval = 900,
                timer = nil,
                running = false,
            }

            ms.antiTimeout = function(config)
                assert(type(config) == "table", "ms.antiTimeout: config must be a table")
                assert(type(config.action) == "function", "ms.antiTimeout: config.action must be a function")

                ms._antiTimeout.fn       = config.action
                ms._antiTimeout.interval = tonumber(config.interval) or 900

                local enabled  = config.enabled
                if enabled == nil then enabled = true end
                if ms._antiTimeoutEnabled == true then
                    enabled = true
                elseif ms._antiTimeoutEnabled == false then
                    enabled = false
                end

                if ms._antiTimeout.timer then
                    ms._antiTimeout.timer:stop()
                    ms._antiTimeout.timer = nil
                end

                if enabled then
                    ms._antiTimeout.running = true
                    local wrappedFn = ms.fn(ms._antiTimeout.fn)
                    ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                        if not ms._antiTimeout.running then return end
                        if not ms._targetActive then return end
                        pcall(wrappedFn)
                    end)
                else
                    ms._antiTimeout.running = false
                end
            end

            ms.antiTimeoutStop = function()
                ms._antiTimeout.running = false
                if ms._antiTimeout.timer then
                    ms._antiTimeout.timer:stop()
                    ms._antiTimeout.timer = nil
                end
            end

            ms.antiTimeoutStart = function()
                if not ms._antiTimeout.fn then return end
                ms._antiTimeout.running = true
                if not ms._antiTimeout.timer then
                    local wrappedFn = ms.fn(ms._antiTimeout.fn)
                    ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                        if not ms._antiTimeout.running then return end
                        if not ms._targetActive then return end
                        pcall(wrappedFn)
                    end)
                end
            end

            ms.antiTimeoutToggle = function()
                if ms._antiTimeout.running then
                    ms.antiTimeoutStop()
                else
                    ms.antiTimeoutStart()
                end
                return ms._antiTimeout.running
            end
        -- END Anti-Timeout --

    end
-- END core/utilities --

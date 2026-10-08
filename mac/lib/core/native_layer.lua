-- core/native_layer (Native Input Layer) --
    return function(ms)
        local BIN = os.getenv("HOME") .. "/.local/bin/ms_layer"
        local DISABLED_KEY = "ms.nativeLayer.disabled"
        local SKIP_ONCE_KEY = "ms.nativeLayer.skipOnce"
        local MAX_RESTARTS = 3

        ms.layer = {
            active = false,
            enable = function()
                hs.settings.set(DISABLED_KEY, nil)
                hs.reload()
            end,
            disable = function()
                hs.settings.set(DISABLED_KEY, true)
                hs.reload()
            end,
        }

        if hs.settings.get(SKIP_ONCE_KEY) then
            hs.settings.set(SKIP_ONCE_KEY, nil)
            print("ms_layer: skipped after repeated failures; using Lua taps until next reload")
            return
        end

        if hs.settings.get(DISABLED_KEY) or not hs.fs.attributes(BIN) then return end

        local REPLACED = {
            "_keyListener",
            "_mouseListener",
            "_scrollListener",
            "_socdListener",
            "_trackpadLeftListener",
            "_trackpadRightListener",
            "_trackpadDragTap",
        }

        local STUB = {
            start = function(self) return self end,
            stop = function(self) return self end,
            isEnabled = function() return true end,
            delete = function() end,
        }

        local function neuter()
            local dead = {}

            for _, field in ipairs(REPLACED) do
                local tap = ms[field]

                if tap ~= STUB then
                    if tap then
                        pcall(function() tap:stop() end)
                        dead[tap] = true
                    end

                    ms[field] = STUB
                end
            end

            local panicTap = ms._hotkeyHandles and ms._hotkeyHandles.panic

            if panicTap and panicTap ~= STUB then
                pcall(function() panicTap:stop() end)
                dead[panicTap] = true
                ms._hotkeyHandles.panic = STUB
            end

            if next(dead) and ms._resilientTaps then
                local kept = {}

                for _, t in ipairs(ms._resilientTaps) do
                    if not dead[t] then kept[#kept + 1] = t end
                end

                ms._resilientTaps = kept
            end
        end

        local idOf = setmetatable({}, { __mode = "k" })
        local byId = setmetatable({}, { __mode = "v" })
        local nextId = 0

        local function idFor(ref)
            local id = idOf[ref]

            if not id then
                nextId = nextId + 1
                id = nextId
                idOf[ref] = id
            end

            byId[id] = ref
            return id
        end

        local function modList(set)
            local out = {}

            for _, m in ipairs({
                "cmd",
                "alt",
                "ctrl",
                "shift",
            }) do
                if set and set[m] then out[#out + 1] = m end
            end

            return #out > 0 and out or nil
        end

        local kind = setmetatable({}, { __mode = "k" })
        local scrollRefs = {}

        local function buildConfig()
            local binds = {}

            for _, b in ipairs(ms._keyBindings or {}) do
                local name = hs.keycodes.map[b.keyCode]

                if name then
                    local also = {}

                    for _, oc in ipairs(b.alsoHeld or {}) do
                        also[#also + 1] = hs.keycodes.map[oc]
                    end

                    kind[b] = "key"
                    binds[#binds + 1] = {
                        id = idFor(b),
                        t = "key",
                        key = name,
                        mods = modList(b.mods),
                        mode = b.modsAny and "any" or (b.subsetMods and "subset" or "exact"),
                        also = #also > 0 and also or nil,
                        swallow = b.swallow and true or false,
                        system = b.system and true or false,
                        release = b.releaseFn ~= nil,
                    }
                end
            end

            for _, mb in ipairs(ms._modBindings or {}) do
                local mods = modList(mb.modSet)

                if mods then
                    kind[mb] = "mods"
                    binds[#binds + 1] = {
                        id = idFor(mb),
                        t = "mods",
                        mods = mods,
                        system = mb.system and true or false,
                    }
                end
            end

            for button, cb in pairs(ms._mouseCallbacks or {}) do
                kind[cb] = "mouse"
                binds[#binds + 1] = {
                    id = idFor(cb),
                    t = "mouse",
                    button = button,
                    swallow = cb.swallow and true or false,
                    system = cb.system and true or false,
                }
            end

            for dir, fn in pairs(ms._scrollCallbacks or {}) do
                local ref = scrollRefs[dir]

                if not ref or ref.fn ~= fn then
                    ref = {
                        fn = fn,
                        dir = dir,
                    }

                    scrollRefs[dir] = ref
                end

                kind[ref] = "scroll"
                binds[#binds + 1] = {
                    id = idFor(ref),
                    t = "scroll",
                    dir = dir,
                }
            end

            local hk = ms._hotkeys and ms._hotkeys.panic
            local panic = nil

            if hk and hk.key then
                panic = {
                    key = hk.key,
                    any = hk.mods == "any",
                    mods = hk.mods ~= "any" and hk.mods and #hk.mods > 0 and hk.mods or nil,
                }
            end

            local tp = ms.trackpadHoldKeys or {}
            return {
                c = "config",
                binds = #binds > 0 and binds or nil,
                panic = panic,
                swallow_hotkeys = ms._swallowHotkeys and true or false,
                socd = {
                    on = ms.socdEnabled and true or false,
                    mode = ms.socdMode or "lastWins",
                },
                trackpad = {
                    on = ms.trackpadMode and true or false,
                    left = tp.left,
                    right = tp.right,
                },
            }
        end

        local task = nil
        local restarts = 0
        local stopping = false
        local fatal = false
        local lastConfig, lastState = nil, nil
        local pending = nil
        local buf = ""

        local function send(tbl)
            if not task then return end
            task:setInput(hs.json.encode(tbl) .. "\n")
        end

        local function pushState(force)
            local s = (BindValidity == 1 and "1" or "0") .. (ms._targetActive and "1" or "0")
            if s == lastState and not force then return end
            lastState = s
            send({
                c = "state",
                enabled = BindValidity == 1,
                target = ms._targetActive and true or false,
            })
        end

        local function sync(force)
            pending = nil
            if not task then return end
            if ms.layer.active then neuter() end
            local ok, cfg = pcall(buildConfig)

            if not ok then
                print("ms_layer: config build failed: " .. tostring(cfg))
                return
            end

            local encoded = hs.json.encode(cfg)

            if encoded ~= lastConfig or force then
                lastConfig = encoded
                task:setInput(encoded .. "\n")
            end

            pushState(force)
        end

        local function scheduleSync()
            if ms.layer.active then neuter() end
            if pending or not task then return end
            pending = hs.timer.doAfter(0, function() sync(false) end)
        end

        ms.layer.sync = scheduleSync

        local function runFn(fn, label)
            if type(fn) ~= "function" then return end
            local co = coroutine.create(fn)
            local ok, err = coroutine.resume(co)
            if not ok then print(label .. " error: " .. tostring(err)) end
        end

        local SHIFT_CODES = {
            56,
            62,
        }

        local ALT_CODES = { 58 }

        local CTRL_CODES = {
            59,
            61,
        }

        local CMD_CODES = {
            55,
            54,
        }

        local MOD_TRACK = {
            shift = SHIFT_CODES,
            rightshift = SHIFT_CODES,
            alt = ALT_CODES,
            rightalt = ALT_CODES,
            ctrl = CTRL_CODES,
            rightctrl = CTRL_CODES,
            cmd = CMD_CODES,
            rightcmd = CMD_CODES,
        }

        local MOUSE_TRACK = {
            [0] = 997,
            [1] = 999,
            [2] = 998,
            [3] = 996,
            [4] = 995,
        }

        local MOD_BITS = {
            cmd = 1,
            alt = 2,
            ctrl = 4,
            shift = 8,
        }

        local function flagsOf(m)
            local f = {}

            for name, mask in pairs(MOD_BITS) do
                if math.floor(m / mask) % 2 == 1 then f[name] = true end
            end

            return f
        end

        local function onEvent(ev)
            local e = ev.e

            if e == "fire" then
                local ref = byId[ev.id]
                if not ref then return end
                ms._currentFlags = flagsOf(ev.m or 0)
                local k = kind[ref]

                if k == "key" then
                    if ev.edge == "up" then
                        runFn(ref.releaseFn, "ms.key")
                    else
                        runFn(ref.pressFn, "ms.key")
                    end
                elseif k == "mods" then
                    runFn(ref.firedFn, "ms.modBind")
                elseif k == "mouse" then
                    runFn(ref.fn, "ms.mouse callback")
                elseif k == "scroll" then
                    if ms._scrollCallbacks and ms._scrollCallbacks[ref.dir] == ref.fn then
                        runFn(ref.fn, "ms.scrollBind callback")
                    end
                end
            elseif e == "k" then
                local codes = MOD_TRACK[ev.k]

                if codes then
                    local flags = flagsOf(ev.m or 0)
                    local mod = ev.k:gsub("^right", "")

                    for _, c in ipairs(codes) do ms.keytrack[c] = flags[mod] or false end
                else
                    local code = hs.keycodes.map[ev.k]
                    if code then ms.keytrack[code] = ev.d end
                end

                if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                    local code = hs.keycodes.map[ev.k]
                    if code then pcall(ms.dev._onKeyEvent, code, ev.k, ev.d) end
                end
            elseif e == "m" then
                local code = MOUSE_TRACK[ev.b]
                if code then ms.keytrack[code] = ev.d end

                if ms.dev and ms.dev._wantsMouseEvents and ms.dev._wantsMouseEvents() then
                    local p = hs.mouse.absolutePosition()
                    pcall(ms.dev._onMouseEvent, ev.b, ev.d, math.floor(p.x), math.floor(p.y))
                end
            elseif e == "panic" then
                if not ms._hotkeysReady then return end
                if not ms._targetActive and not ms._isSafeZone() then return end
                ms.setMacros(0)
            elseif e == "ready" then
                ms.layer.active = true
                neuter()
                ms.layer.version = ev.version
                restarts = 0
                sync(true)
                print("ms_layer " .. tostring(ev.version) .. " owns input (" .. tostring(ev.platform) .. ")")
            elseif e == "revived" then
                if ms.dev then print("ms_layer: OS disabled the input hook; re-armed") end
            elseif e == "warn" then
                print("ms_layer: " .. tostring(ev.msg))
            elseif e == "error" then
                print("ms_layer error (" .. tostring(ev.code) .. "): " .. tostring(ev.msg))
                fatal = ev.code == "permission"

                if fatal and ms.alert then
                    ms.alert("Native input layer needs permission\n"
                        .. "System Settings > Privacy & Security > Accessibility\nand Input Monitoring: allow ms_layer", 10)
                end
            end
        end

        local start

        local function onExit(_, code)
            local wasActive = ms.layer.active
            task = nil
            ms.layer.active = false
            lastConfig, lastState = nil, nil
            if stopping then return end
            restarts = restarts + 1

            if not wasActive and (fatal or restarts > MAX_RESTARTS) then
                print("ms_layer: never came up (exit " .. tostring(code) .. "); Lua taps stay in charge")
                return
            end

            if restarts > MAX_RESTARTS then
                print("ms_layer: exited " .. tostring(code) .. " repeatedly; falling back to Lua taps")
                if ms.alert then ms.alert("Native input layer failed; using Lua input until next reload", 6) end
                hs.settings.set(SKIP_ONCE_KEY, true)
                hs.timer.doAfter(0.5, hs.reload)
                return
            end

            hs.timer.doAfter(0.25 * restarts, start)
        end

        start = function()
            buf = ""
            task = hs.task.new(BIN, onExit, function(_, stdOut)
                if not stdOut or stdOut == "" then return true end
                buf = buf .. stdOut

                while true do
                    local nl = buf:find("\n", 1, true)
                    if not nl then break end
                    local line = buf:sub(1, nl - 1)
                    buf = buf:sub(nl + 1)
                    local ok, ev = pcall(hs.json.decode, line)

                    if ok and type(ev) == "table" then
                        local okEv, err = pcall(onEvent, ev)
                        if not okEv then print("ms_layer event error: " .. tostring(err)) end
                    end
                end

                return true
            end)

            if not task or not task:start() then
                task = nil
                print("ms_layer: failed to launch " .. BIN)
            end
        end

        local function passThrough(fn, ...)
            fn()
            return ...
        end

        local function after(name, fn)
            local orig = ms[name]
            if type(orig) ~= "function" then return end
            ms[name] = function(...)
                return passThrough(fn, orig(...))
            end
        end

        local function wrapHandle(h)
            if type(h) == "table" and type(h.delete) == "function" then
                local del = h.delete
                h.delete = function(...)
                    local r = del(...)
                    scheduleSync()
                    return r
                end
            end

            return h
        end

        for _, name in ipairs({
            "key",
            "keyCombo",
            "scrollBind",
        }) do
            local orig = ms[name]

            if type(orig) == "function" then
                ms[name] = function(...)
                    local h = orig(...)
                    scheduleSync()
                    return wrapHandle(h)
                end
            end
        end

        for _, name in ipairs({
            "mouse",
            "socdStart",
            "socdStop",
            "socdApply",
            "_bindHotkeys",
            "saveSettings",
            "_ownUiFocus",
            "_ensureMouseListener",
        }) do
            after(name, scheduleSync)
        end

        after("setMacros", function() pushState(false) end)

        if ms.bind then
            for _, name in ipairs({
                "rebind",
                "teardown",
                "rebindSystem",
            }) do
                local orig = ms.bind[name]

                if type(orig) == "function" then
                    ms.bind[name] = function(...)
                        return passThrough(scheduleSync, orig(...))
                    end
                end
            end
        end

        local releaseHolds = ms._releaseTrackpadHolds

        ms._releaseTrackpadHolds = function()
            if not ms.layer.active and releaseHolds then releaseHolds() end
        end

        ms._layerStateWatch = hs.timer.doEvery(0.5, function() pushState(false) end)

        ms.layer.stop = function()
            if ms._layerStateWatch then ms._layerStateWatch:stop() end
            stopping = true

            if task then
                send({ c = "quit" })
                local t = task
                hs.timer.doAfter(0.2, function()
                    if t:isRunning() then t:terminate() end
                end)
            end
        end

        start()
    end
-- END core/native_layer --

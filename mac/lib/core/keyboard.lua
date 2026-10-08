-- core/keyboard (Keyboard Actions) --
    return function(ms)
        local hskeymap = {
            left = 123, right = 124, down = 125, up = 126,
            shift = 56, lshift = 56, rshift = 62,
            ctrl = 59, lctrl = 59, rctrl = 61,
            alt = 58, lalt = 58, ralt = 61,
            cmd = 55, lcmd = 55, rcmd = 54,
            f1 = 122, f2 = 120, f3 = 99, f4 = 118,
            f5 = 96, f6 = 97, f7 = 98, f8 = 100,
            f9 = 101, f10 = 109, f11 = 103, f12 = 111,
            leftclick = 997, mouse1 = 997,
            rightclick = 999, mouse2 = 999,
            middleclick = 998, mouse3 = 998,
            mouse4 = 996, mouseback = 996,
            mouse5 = 995, mouseforward = 995,
        }

        local function getCode(key)
            if type(key) == "number" then return key end
            local k = tostring(key):lower()
            return hskeymap[k] or hs.keycodes.map[k]
        end

        local _KEY_NAME_EXTRA = { [179] = "fn" }
        local _keyNameCache   = {}
        local function keyName(code)
            if code == nil then return nil end
            local hit = _keyNameCache[code]
            if hit ~= nil then
                if hit == false then return nil end
                return hit
            end
            local name = _KEY_NAME_EXTRA[code]
            if name == nil then
                local ok, v = pcall(function() return hs.keycodes.map[code] end)
                name = ok and v or nil
            end
            _keyNameCache[code] = (name == nil) and false or name
            return name
        end
        ms._keyName = keyName

        ms.keystate = function(...)
            local args = { ... }
            if args[2] == true then
                local code = args[1]
                return code and ms.keytrack[code] == true or false
            end
            for _, key in ipairs(args) do
                local code = getCode(key)
                if code and ms.keytrack[code] then
                    return true
                end
            end
            return false
        end

        ms.held = function(id)
            local c = ms.effectiveBind and ms.effectiveBind(id)
            if not c or not c.mods or #c.mods == 0 then return false end
            for _, m in ipairs(c.mods) do
                if not ms.keystate(m) then return false end
            end
            return true
        end

        local _prevModFlags = {
            shift = false,
            alt = false,
            ctrl = false,
            cmd = false,
        }

        -- Keycodes that are themselves modifiers
        local _MOD_CODES = {
            [54] = true, [55] = true,             -- cmd
            [56] = true, [60] = true, [62] = true, -- shift
            [58] = true, [61] = true,             -- alt / right-ctrl slot
            [59] = true,                          -- ctrl
        }
        local function _anyRealKeyHeld()
            for kc, down in pairs(ms.keytrack) do
                if down and not _MOD_CODES[kc] then return true end
            end
            return false
        end

        ms._keyListener = hs.eventtap.new({
            hs.eventtap.event.types.keyDown,
            hs.eventtap.event.types.keyUp,
            hs.eventtap.event.types.flagsChanged
        }, function(event)
            local isSynthetic = ms.isSynthetic(event)
            if isSynthetic then return false end

            local type = event:getType()
            local keyCode = event:getKeyCode()
            local flags = event:getFlags()

            if type == hs.eventtap.event.types.flagsChanged then
                ms.keytrack[56] = flags.shift
                ms.keytrack[62] = flags.shift
                ms.keytrack[58] = flags.alt
                ms.keytrack[59] = flags.ctrl
                ms.keytrack[61] = flags.ctrl
                ms.keytrack[55] = flags.cmd
                ms.keytrack[54] = flags.cmd
                -- Modifier-only binds fire once per press on exact match, no real key held
                if ms._modBindings and #ms._modBindings > 0 and not _anyRealKeyHeld() then
                    for _, mb in ipairs(ms._modBindings) do
                        local exact =
                            ((not mb.modSet.cmd)   == (not flags.cmd)) and
                            ((not mb.modSet.alt)   == (not flags.alt)) and
                            ((not mb.modSet.ctrl)  == (not flags.ctrl)) and
                            ((not mb.modSet.shift) == (not flags.shift))
                        if exact and not mb.fired then
                            mb.fired = true
                            if BindValidity == 1 or mb.system then
                                local co = coroutine.create(mb.firedFn)
                                local ok, err = coroutine.resume(co)
                                if not ok then print("ms.modBind error: " .. tostring(err)) end
                            end
                        elseif not exact then
                            mb.fired = false
                        end
                    end
                end
                if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                    local now = {
                        shift = flags.shift and true or false,
                        alt   = flags.alt   and true or false,
                        ctrl  = flags.ctrl  and true or false,
                        cmd   = flags.cmd   and true or false,
                    }
                    local modNames = {
                        {
                            k="shift",
                            code=56,
                            name="shift",
                        },
                        {
                            k="alt",
                            code=58,
                            name="alt",
                        },
                        {
                            k="ctrl",
                            code=59,
                            name="ctrl",
                        },
                        {
                            k="cmd",
                            code=55,
                            name="cmd",
                        },
                    }
                    for _, m in ipairs(modNames) do
                        if now[m.k] ~= _prevModFlags[m.k] then
                            pcall(ms.dev._onKeyEvent, m.code, m.name, now[m.k])
                        end
                    end
                    _prevModFlags = now
                end
                return false
            end

            if type == hs.eventtap.event.types.keyDown then
                local isRepeat = (event:getProperty(
                    hs.eventtap.event.properties.keyboardEventAutorepeat) or 0) ~= 0
                ms.keytrack[keyCode] = true
                if not isRepeat and ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                    pcall(ms.dev._onKeyEvent, keyCode, keyName(keyCode), true)
                end
                if not isRepeat and ms._keyBindingsByCode then
                    ms._currentFlags = flags
                    local bucket = ms._keyBindingsByCode[keyCode]
                    if bucket then
                    for _, binding in ipairs(bucket) do
                        if binding then
                            local modsMatch = true
                            if binding.modsAny then
                                -- Fire on the keycode regardless of modifiers.
                            elseif binding.subsetMods then
                                -- Subset: declared modifiers must be held, extras tolerated
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
                            else
                                -- Exact: declared set must equal held set.
                                if (not binding.mods.cmd)   ~= (not flags.cmd)   then modsMatch = false end
                                if (not binding.mods.alt)   ~= (not flags.alt)   then modsMatch = false end
                                if (not binding.mods.ctrl)  ~= (not flags.ctrl)  then modsMatch = false end
                                if (not binding.mods.shift) ~= (not flags.shift) then modsMatch = false end
                            end
                            local heldMatch = true
                            if binding.alsoHeld then
                                for _, oc in ipairs(binding.alsoHeld) do
                                    if not ms.keytrack[oc] then heldMatch = false
                                    break end
                                end
                            end
                            if modsMatch and heldMatch then
                                if BindValidity == 1 or binding.system then
                                    if binding.pressFn then
                                        local co = coroutine.create(binding.pressFn)
                                        local ok, err = coroutine.resume(co)
                                        if not ok then print("ms.key error: " .. tostring(err)) end
                                    end
                                    return binding.swallow
                                else
                                    return false
                                end
                            end
                        end
                    end
                    end
                end
            elseif type == hs.eventtap.event.types.keyUp then
                ms.keytrack[keyCode] = false
                if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                    pcall(ms.dev._onKeyEvent, keyCode, keyName(keyCode), false)
                end
                local bucketUp = ms._keyBindingsByCode and ms._keyBindingsByCode[keyCode]
                if bucketUp then
                    for _, binding in ipairs(bucketUp) do
                        if binding then
                            local modsMatch = true
                            if not binding.modsAny then
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
                            end
                            if modsMatch then
                                if BindValidity == 1 or binding.system then
                                    if binding.releaseFn then
                                        local co = coroutine.create(binding.releaseFn)
                                        local ok, err = coroutine.resume(co)
                                        if not ok then print("ms.key error: " .. tostring(err)) end
                                    end
                                    return binding.swallow
                                else
                                    return false
                                end
                            end
                        end
                    end
                end
            end

            return false
        end):start()

        ms._resilientTaps = { ms._keyListener }


        local function _keyLog(msg)
            if ms.dev and ms.devtools then
                local label = ms._getCallChain()
                ms.devtools:macroLog(msg, label)
                if ms.dev._watcherPanel then
                    ms.devtools:watcherStep(msg, label)
                end
            end
        end
        -- END Key logging --

            ms.press = function(key, mods)
                local keyCode = getCode(key)
                if not keyCode then
                    print("Error: Could not find keyCode for " .. tostring(key))
                    return
                end
                ms._keyHoldStarts = ms._keyHoldStarts or {}
                local alreadyHeld = ms._macroHeldKeys[keyCode]
                if not alreadyHeld then
                    ms._keyHoldStarts[keyCode] = hs.timer.absoluteTime()
                    if ms.dev and not ms.devtools:getTraceSuppress() then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        local msg = "down " .. tostring(key) .. modsStr
                        _keyLog(msg)
                    end
                end
                ms._macroHeldKeys[keyCode] = {
                    mods = mods or {},
                    owner = coroutine.running(),
                }
                local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.release = function(key, mods)
                local keyCode = getCode(key)
                if not keyCode then return end
                local durationStr = ""
                ms._keyHoldStarts = ms._keyHoldStarts or {}
                local startTime = ms._keyHoldStarts[keyCode]
                if startTime then
                    local elapsedNs = hs.timer.absoluteTime() - startTime
                    local elapsedMs = math.floor(elapsedNs / 1000000)
                    if elapsedMs >= 1000 then
                        durationStr = string.format(" (%.1fs)", elapsedMs / 1000)
                    elseif elapsedMs > 0 then
                        durationStr = string.format(" (%dms)", elapsedMs)
                    end
                    ms._keyHoldStarts[keyCode] = nil
                end
                if ms.dev and not ms.devtools:getTraceSuppress() then
                    local msg = "up " .. tostring(key) .. durationStr
                    _keyLog(msg)
                end
                ms._macroHeldKeys[keyCode] = nil
                local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, false)
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.forgetHeld = function(key)
                local keyCode = getCode(key)
                if not keyCode then return false end
                if ms._macroHeldKeys[keyCode] == nil then return false end
                ms._macroHeldKeys[keyCode] = nil
                if ms._keyHoldStarts then ms._keyHoldStarts[keyCode] = nil end
                return true
            end

            ms.type = function(key, mods, holdMs)
                local _hold = holdMs or 15
                if ms.dev then
                    local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                    local msg = "type " .. tostring(key) .. modsStr .. " (" .. _hold .. "ms)"
                    _keyLog(msg)
                end
                local _saved = ms.devtools:getTraceSuppress()
                ms.devtools:setTraceSuppress(true)
                ms.press(key, mods)
                ms.wait(_hold)
                ms.release(key, mods)
                ms.devtools:setTraceSuppress(_saved)
            end

            local HOLD_INITIAL_MS = 250
            local HOLD_REPEAT_MS  = 33
            ms.hold = function(key, mods, durationMs)
                local keyCode = getCode(key)
                if not keyCode then
                    print("Error: Could not find keyCode for " .. tostring(key))
                    return
                end
                ms.press(key, mods)
                local dur = tonumber(durationMs)
                if not dur or dur <= 0 then return end

                if dur <= HOLD_INITIAL_MS then
                    ms.wait(dur)
                else
                    ms.wait(HOLD_INITIAL_MS)
                    local elapsed = HOLD_INITIAL_MS
                    while elapsed < dur do
                        local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                        ev:setProperty(hs.eventtap.event.properties.keyboardEventAutorepeat, 1)
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                        ms.wait(HOLD_REPEAT_MS)
                        elapsed = elapsed + HOLD_REPEAT_MS
                    end
                end
                ms.release(key, mods)
            end

            ms.key = function(mods, key, swallow, pressFn, releaseFn, isSystem, subsetMods)
                local keyCode = getCode(key)
                if not keyCode then
                    print("Error: Could not find keyCode for " .. tostring(key))
                    return
                end

                local modsAny = (mods == "any")
                local modSet = {}
                if not modsAny then
                    for _, m in ipairs(mods or {}) do modSet[m] = true end
                end

                local binding = {
                    keyCode = keyCode,
                    mods = modSet,
                    modsAny = modsAny,
                    subsetMods = subsetMods or false,
                    swallow = swallow,
                    pressFn = pressFn,
                    releaseFn = releaseFn,
                    system = isSystem or false,
                }

                table.insert(ms._keyBindings, binding)
                local bucket = ms._keyBindingsByCode[keyCode]
                if not bucket then bucket = {}
                ms._keyBindingsByCode[keyCode] = bucket end
                bucket[#bucket + 1] = binding

                return { delete = function()
                    for i, b in ipairs(ms._keyBindings) do
                        if b == binding then
                            table.remove(ms._keyBindings, i)
                            break
                        end
                    end
                    local bcBucket = ms._keyBindingsByCode[keyCode]
                    if bcBucket then
                        for i, b in ipairs(bcBucket) do
                            if b == binding then
                                table.remove(bcBucket, i)
                                break
                            end
                        end
                        if #bcBucket == 0 then ms._keyBindingsByCode[keyCode] = nil end
                    end
                end}
            end

            ms.keyCombo = function(mods, keys, swallow, pressFn, isSystem, subsetMods)
                local codes = {}
                for _, k in ipairs(keys or {}) do
                    local c = getCode(k)
                    if not c then
                        print("Error: keyCombo could not resolve " .. tostring(k))
                        return { delete = function() end }
                    end
                    codes[#codes + 1] = c
                end
                if #codes < 2 then
                    return ms.key(mods, keys and keys[1], swallow, pressFn, nil, isSystem, subsetMods)
                end

                local modSet = {}
                for _, m in ipairs(mods or {}) do modSet[m] = true end

                local handles = {}
                for i, code in ipairs(codes) do
                    local others = {}
                    for j, oc in ipairs(codes) do
                        if j ~= i then others[#others + 1] = oc end
                    end
                    local binding = {
                        keyCode  = code,
                        mods     = modSet,
                        modsAny  = false,
                        subsetMods = subsetMods or false,
                        swallow  = swallow,
                        pressFn  = pressFn,
                        alsoHeld = others,
                        system   = isSystem or false,
                    }
                    table.insert(ms._keyBindings, binding)
                    local bucket = ms._keyBindingsByCode[code]
                    if not bucket then bucket = {}
                    ms._keyBindingsByCode[code] = bucket end
                    bucket[#bucket + 1] = binding
                    handles[#handles + 1] = binding
                end

                return { delete = function()
                    for _, binding in ipairs(handles) do
                        for i, b in ipairs(ms._keyBindings) do
                            if b == binding then table.remove(ms._keyBindings, i)
                            break end
                        end
                        local bc = ms._keyBindingsByCode[binding.keyCode]
                        if bc then
                            for i, b in ipairs(bc) do
                                if b == binding then table.remove(bc, i)
                                break end
                            end
                            if #bc == 0 then ms._keyBindingsByCode[binding.keyCode] = nil end
                        end
                    end
                end }
            end
    end
-- END core/keyboard --

-- core/mouse (Mouse Actions) --
    return function(ms)
        ms.scroll = function(direction, clicks)
            if ms.dev._watcherPanel then
                ms.devtools:watcherStep("scroll " .. tostring(direction)
                    .. (clicks and clicks > 1 and " x" .. clicks or ""))
            end
            clicks = clicks or 1
            local dx, dy = 0, 0
            if direction == "up" then dy = clicks
            elseif direction == "down" then dy = -clicks
            elseif direction == "left" then dx = -clicks
            elseif direction == "right" then dx = clicks
            end
            local ev = hs.eventtap.event.newScrollEvent({
                dx,
                dy,
            }, {}, "pixel")
            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
            ev:post()
        end

        -- Mouse button number to keytrack code
        local _MOUSE_TRACK_CODE = {
            [0] = 997,  -- left
            [1] = 999,  -- right
            [2] = 998,  -- middle
            [3] = 996,  -- thumb back
            [4] = 995,  -- thumb forward
        }

        ms._ensureMouseListener = function()
            if ms._mouseListener then return end
            ms._mouseCallbacks = {}
            local types = {
                hs.eventtap.event.types.leftMouseDown,
                hs.eventtap.event.types.leftMouseUp,
                hs.eventtap.event.types.rightMouseDown,
                hs.eventtap.event.types.rightMouseUp,
                hs.eventtap.event.types.otherMouseDown,
                hs.eventtap.event.types.otherMouseUp,
            }
            ms._mouseListener = hs.eventtap.new(types, function(event)
                    local type = event:getType()
                    local b
                    local isDown

                    if type == hs.eventtap.event.types.leftMouseDown then
                        b = 0
                        isDown = true
                    elseif type == hs.eventtap.event.types.leftMouseUp then
                        b = 0
                        isDown = false
                    elseif type == hs.eventtap.event.types.rightMouseDown then
                        b = 1
                        isDown = true
                    elseif type == hs.eventtap.event.types.rightMouseUp then
                        b = 1
                        isDown = false
                    elseif type == hs.eventtap.event.types.otherMouseDown then
                        b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                        isDown = true
                    else
                        b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                        isDown = false
                    end

                    local trackCode = _MOUSE_TRACK_CODE[b]
                    if trackCode then ms.keytrack[trackCode] = isDown end

                    if ms.dev and ms.dev._wantsMouseEvents and ms.dev._wantsMouseEvents() then
                        local _mp = hs.mouse.absolutePosition()
                        pcall(ms.dev._onMouseEvent, b, isDown,
                            math.floor(_mp.x), math.floor(_mp.y))
                    end

                    local callbackData = ms._mouseCallbacks[b]
                    if BindValidity ~= 1 then
                        if not (callbackData and callbackData.system) then return false end
                    end

                    if not isDown then return false end

                    if callbackData then
                        local co = coroutine.create(callbackData.fn)
                        local ok, err = coroutine.resume(co)
                        if not ok then
                            print("ms.mouse callback error: " .. tostring(err))
                        end
                        return callbackData.swallow
                    end

                    return false
                end):start()
            ms._resilientTaps[#ms._resilientTaps+1] = ms._mouseListener
        end

        ms.mouse = function(button, swallow, clickFn, isSystem)
            ms._ensureMouseListener()
            ms._mouseCallbacks[button] = {
                fn = clickFn,
                swallow = swallow,
                system = isSystem or false,
            }
        end

        -- Live mouse button state
        local _MOUSE_NAME_CODE = {
            left    = 997,
            l       = 997,
            ["0"]   = 997,
            right   = 999,
            r       = 999,
            ["1"]   = 999,
            middle  = 998,
            center  = 998,
            m       = 998,
            ["2"]   = 998,
            back    = 996,
            thumb   = 996,
            thumb1  = 996,
            ["3"]   = 996,
            forward = 995,
            thumb2  = 995,
            ["4"]   = 995,
        }
        ms.mousestate = function(...)
            ms._ensureMouseListener()
            local args = { ... }
            if #args == 0 then args = { "left" } end
            for _, btn in ipairs(args) do
                local code
                if type(btn) == "number" then
                    code = _MOUSE_TRACK_CODE[btn]
                else
                    code = _MOUSE_NAME_CODE[tostring(btn):lower()]
                end
                if code and ms.keytrack[code] then return true end
            end
            return false
        end
        ms._ensureMouseListener()

        ms._scrollCallbacks = ms._scrollCallbacks or {}
        ms.scrollBind = function(direction, fn)
            if not ms._scrollListener then
                ms._scrollCallbacks = {}
                ms._scrollListener = hs.eventtap.new({
                    hs.eventtap.event.types.scrollWheel,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local dy = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                    local dir = dy > 0 and "up" or "down"
                    local cb = ms._scrollCallbacks[dir]
                    if cb then
                        local co = coroutine.create(cb)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("ms.scrollBind callback error: " .. tostring(err)) end
                    end
                    return false
                end):start()
                ms._resilientTaps[#ms._resilientTaps+1] = ms._scrollListener
            end
            ms._scrollCallbacks[direction] = fn
            return {
                delete = function()
                    ms._scrollCallbacks[direction] = nil
                end,
            }
        end

        ms._gamepadTask = nil
        ms._gamepadCallbacks = {}
        ms._gamepadConnected = false
        ms._gamepadControllers = {}
        ms._gamepadHeld = {}
        ms._gamepadBinds = {}
        ms._gamepadAxes = {}

        local _GP_RANK = {
            l3 = 1,
            r3 = 2,
            l2 = 3,
            r2 = 4,
            l1 = 5,
            r1 = 6,
            a = 7,
            b = 8,
            x = 9,
            y = 10,
            up = 11,
            down = 12,
            left = 13,
            right = 14,
            menu = 15,
            options = 16,
            home = 17,
        }


        local _PAD_ALIAS = {
            lb = "l1",
            rb = "r1",
            l = "l1",
            r = "r1",
            lt = "l2",
            rt = "r2",
            zl = "l2",
            zr = "r2",
            ls = "l3",
            rs = "r3",
            lsb = "l3",
            rsb = "r3",
            cross = "a",
            circle = "b",
            square = "x",
            triangle = "y",
            start = "menu",
            plus = "menu",
            select = "options",
            back = "options",
            view = "options",
            share = "options",
            create = "options",
            minus = "options",
            guide = "home",
            xbox = "home",
            ps = "home",
            dup = "up",
            ddown = "down",
            dleft = "left",
            dright = "right",
            dpadup = "up",
            dpaddown = "down",
            dpadleft = "left",
            dpadright = "right",
        }

        local _PAD_LABELS = {
            xbox = {
                a = "A",
                b = "B",
                x = "X",
                y = "Y",
                l1 = "LB",
                r1 = "RB",
                l2 = "LT",
                r2 = "RT",
                l3 = "LS",
                r3 = "RS",
                up = "Up",
                down = "Down",
                left = "Left",
                right = "Right",
                menu = "Menu",
                options = "View",
                home = "Xbox",
            },
            generic = {
                a = "A",
                b = "B",
                x = "X",
                y = "Y",
                l1 = "LB",
                r1 = "RB",
                l2 = "LT",
                r2 = "RT",
                l3 = "LS",
                r3 = "RS",
                up = "Up",
                down = "Down",
                left = "Left",
                right = "Right",
                menu = "Menu",
                options = "View",
                home = "Home",
            },
            ds4 = {
                a = "Cross",
                b = "Circle",
                x = "Square",
                y = "Triangle",
                l1 = "L1",
                r1 = "R1",
                l2 = "L2",
                r2 = "R2",
                l3 = "L3",
                r3 = "R3",
                up = "Up",
                down = "Down",
                left = "Left",
                right = "Right",
                menu = "Options",
                options = "Share",
                home = "PS",
            },
            ["switch"] = {
                a = "B",
                b = "A",
                x = "Y",
                y = "X",
                l1 = "L",
                r1 = "R",
                l2 = "ZL",
                r2 = "ZR",
                l3 = "LS",
                r3 = "RS",
                up = "Up",
                down = "Down",
                left = "Left",
                right = "Right",
                menu = "+",
                options = "-",
                home = "Home",
            },
        }

        ms.padName = function(name)
            local n = tostring(name or ""):lower():gsub("^pad", ""):gsub("[%s_%-]", "")
            return _PAD_ALIAS[n] or n
        end

        ms.padType = function(c)
            local t = type(c) == "table" and c.type
            if not t then
                local first = ms._gamepadControllers and ms._gamepadControllers[1]
                t = first and first.type
            end
            return _PAD_LABELS[t] and t or "xbox"
        end

        ms.padLabel = function(name, padType)
            local n = ms.padName(name)
            local set = _PAD_LABELS[padType or ms.padType()] or _PAD_LABELS.xbox
            return set[n] or tostring(name or ""):upper()
        end

        ms.gpButtons = function(c)
            if type(c) ~= "table" then return {} end
            if type(c.buttons) == "table" and #c.buttons > 0 then
                local l = {}
                for _, b in ipairs(c.buttons) do l[#l + 1] = b end
                table.sort(l, function(p, q)
                    local rp, rq = _GP_RANK[p] or 99, _GP_RANK[q] or 99
                    if rp ~= rq then return rp < rq end
                    return tostring(p) < tostring(q)
                end)
                return l
            end
            if c.button then return { c.button } end
            return {}
        end

        ms.gpLabel = function(c, sep)
            local l = ms.gpButtons(c)
            if #l == 0 then return "?" end
            local out = {}
            for _, b in ipairs(l) do out[#out + 1] = ms.padLabel(b) end
            return table.concat(out, sep or " + ")
        end

        ms.gpToken = function(c)
            local l = ms.gpButtons(c)
            table.sort(l)
            return table.concat(l, "+")
        end

        local function _gamepadStatusChanged()
            ms._gamepadConnected = (#ms._gamepadControllers > 0)
            if ms.shell and ms.shell.eval then
                pcall(ms.shell.eval, "window.__gpType='" .. ms.padType()
                    .. "';window.dispatchEvent(new Event('ms:padtype'))")
            end
            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
        end

        local function _gamepadAddController(ev)
            for _, c in ipairs(ms._gamepadControllers) do
                if c.type == ev.c and c.player == ev.p then return end
            end
            ms._gamepadControllers[#ms._gamepadControllers + 1] = { type = ev.c, player = ev.p }
        end

        local function _gamepadRemoveController(ev)
            for i, c in ipairs(ms._gamepadControllers) do
                if c.type == ev.c and c.player == ev.p then
                    table.remove(ms._gamepadControllers, i)
                    return
                end
            end
        end

        ms.gamepadFeed = function(ev)
            if type(ev) ~= "table" or not ev.e then return end
            ms._gamepadCallbacks = ms._gamepadCallbacks or {}
            if ev.e == "connect" then
                _gamepadAddController(ev)
                if ms.dev and ms.dev._watcherPanel then
                    ms.devtools:watcherStep("gamepad connected: " .. (ev.c or "?"))
                end
                _gamepadStatusChanged()
            elseif ev.e == "disconnect" then
                _gamepadRemoveController(ev)
                _gamepadStatusChanged()
            elseif ev.e == "press" then
                ms._gamepadHeld[ev.b] = true
                local rebindCb = ms._gamepadCallbacks._rebind
                if rebindCb then
                    rebindCb(ev.b, "press", ms._gamepadHeld)
                else
                    local navCb = ms._gamepadCallbacks._nav
                    local consumed = false
                    if navCb then
                        local okN, res = pcall(navCb, "press", ev.b, ms._gamepadHeld)
                        consumed = okN and res == true
                    end
                    if not consumed then
                        local best, bestN = nil, -1
                        for _, bnd in ipairs(ms._gamepadBinds) do
                            if bnd.set[ev.b] then
                                local all = true
                                for k in pairs(bnd.set) do
                                    if not ms._gamepadHeld[k] then all = false break end
                                end
                                if all and bnd.n > bestN then best, bestN = bnd, bnd.n end
                            end
                        end
                        if best then
                            local co = coroutine.create(best.fn)
                            local ok2, err = coroutine.resume(co)
                            if not ok2 then print("ms.gamepad callback error: " .. tostring(err)) end
                        end
                    end
                end
            elseif ev.e == "release" then
                ms._gamepadHeld[ev.b] = nil
                local rebindCb = ms._gamepadCallbacks._rebind
                if rebindCb then
                    rebindCb(ev.b, "release", ms._gamepadHeld)
                else
                    local navCb = ms._gamepadCallbacks._nav
                    if navCb then pcall(navCb, "release", ev.b, ms._gamepadHeld) end
                end
            elseif ev.e == "trigger" then
                ms._gamepadAxes[ev.b] = tonumber(ev.v) or 0
            elseif ev.e == "move" then
                ms._gamepadAxes[ev.b] = {
                    x = tonumber(ev.x) or 0,
                    y = tonumber(ev.y) or 0,
                }
                local navCb = ms._gamepadCallbacks._nav
                if navCb then pcall(navCb, "move", ev.b, ev.x, ev.y) end
            end
        end

        ms.gamepadSetExternal = function(on)
            on = on and true or false
            if ms._gamepadExternal == on then return end
            ms._gamepadExternal = on
            ms._gamepadControllers = {}
            ms._gamepadHeld = {}
            ms._gamepadAxes = {}
            _gamepadStatusChanged()
            if ms._gamepadTask then
                ms._gamepadTask:terminate()
                ms._gamepadTask = nil
            end
            if not on and ms.gamepadEnabled then
                local binds = ms._gamepadBinds
                local cbs = ms._gamepadCallbacks
                ms.gamepadStart()
                ms._gamepadBinds = binds
                ms._gamepadCallbacks = cbs
            end
        end

        ms.gamepadStart = function()
            if ms._gamepadTask or ms._gamepadExternal then return end
            local _isWin = package.config:sub(1, 1) == "\\"
            local bin = os.getenv("HOME") .. "/.local/bin/ms_gc_read" .. (_isWin and ".exe" or "")
            ms._gamepadCallbacks = {}
            ms._gamepadControllers = {}
            ms._gamepadHeld = {}
            ms._gamepadAxes = {}
            ms._gamepadTask = hs.task.new(bin, function() end, function(task, stdOut, stdErr)
                if not stdOut or stdOut == "" then return true end
                for line in stdOut:gmatch("[^\r\n]+") do
                    local ok, ev = pcall(function() return hs.json.decode(line) end)
                    if ok and ev and ev.e and not ms._gamepadExternal then
                        ms.gamepadFeed(ev)
                    end
                end
                return true
            end)
            ms._gamepadTask:start()
        end

        ms.gamepadStop = function()
            if ms._gamepadTask then
                ms._gamepadTask:terminate()
                ms._gamepadTask = nil
                ms._gamepadCallbacks = {}
                ms._gamepadConnected = false
                ms._gamepadControllers = {}
                ms._gamepadHeld = {}
                ms._gamepadBinds = {}
                ms._gamepadAxes = {}
            end
        end

        -- Reconcile the reader daemon with the persisted enable flag
        ms.gamepadSync = function()
            if ms.gamepadEnabled then
                if not ms._gamepadTask then ms.gamepadStart() end
                if ms.shell and ms.shell.gpEnsureOpenBind then ms.shell.gpEnsureOpenBind() end
            else
                if ms.shell and ms.shell.gpClearOpenBind then ms.shell.gpClearOpenBind() end
                if ms._gamepadTask then ms.gamepadStop() end
            end
        end

        -- Register a controller binding
        ms.gamepadBind = function(spec, fn)
            if not ms.gamepadEnabled then
                return { delete = function() end }
            end
            if not ms._gamepadTask then ms.gamepadStart() end
            local list = type(spec) == "table" and spec or { spec }
            local set, n = {}, 0
            for _, b in ipairs(list) do
                if not set[b] then set[b] = true
                n = n + 1 end
            end
            if n == 0 then return { delete = function() end } end
            local entry = { set = set, list = list, n = n, fn = fn }
            ms._gamepadBinds[#ms._gamepadBinds + 1] = entry
            return {
                delete = function()
                    for i, e in ipairs(ms._gamepadBinds) do
                        if e == entry then table.remove(ms._gamepadBinds, i)
                        break end
                    end
                end,
            }
        end

        -- Live controller state --
            local function _padEnsure()
                if ms.gamepadEnabled and not ms._gamepadTask then ms.gamepadStart() end
            end

            ms.padstate = function(...)
                _padEnsure()
                for _, b in ipairs({ ... }) do
                    if ms._gamepadHeld[ms.padName(b)] then return true end
                end
                return false
            end

            ms.padaxis = function(name)
                _padEnsure()
                local n = ms.padName(name or "left")
                if n == "l3" then n = "left" elseif n == "r3" then n = "right" end
                if n == "left" or n == "right" then
                    local a = ms._gamepadAxes[n]
                    if a then return a.x, a.y end
                    return 0, 0
                end
                local v = ms._gamepadAxes[n]
                if v then return v end
                return ms._gamepadHeld[n] and 1 or 0
            end
        -- END Live controller state --

        ms.Mouse = function(operation, button, reference, ...)
            local OPS  = {
                Move=true,
                Click=true,
                DoubleClick=true,
                TripleClick=true,
                Drag=true,
                Press=true,
                Release=true,
            }
            local BTNS = {
                Left=0,
                Right=1,
                Center=2,
                Button4=3,
                Button5=4,
            }
            local REFS = {
                Absolute=true,   Mouse=true,     Follow=true,
                WindowTL=true,   WindowTR=true,  WindowBL=true,
                WindowBR=true,   WindowCenter=true,
                ScreenTL=true,   ScreenTR=true,  ScreenBL=true,
                ScreenBR=true,   ScreenCenter=true,
            }
            assert(OPS[operation],     "ms.Mouse: unknown operation '"  .. tostring(operation)  .. "'")
            assert(BTNS[button] ~= nil, "ms.Mouse: unknown button '"      .. tostring(button)     .. "'")
            assert(REFS[reference],    "ms.Mouse: unknown reference '"   .. tostring(reference)  .. "'")

            local args = { ... }
            local o = type(args[1]) == "boolean" and 1 or 0
            local x1, y1, x2, y2 = args[o + 1], args[o + 2], args[o + 3], args[o + 4]
            local hold = tonumber(args[o + 5]) or 50

            do
                local parts = {
                    "Mouse ",
                    tostring(operation),
                    " ",
                    tostring(button),
                    " ",
                    tostring(reference),
                }
                if x1 then parts[#parts + 1] = " " .. tostring(x1) .. "," .. tostring(y1) end
                if x2 then parts[#parts + 1] = " -> " .. tostring(x2) .. "," .. tostring(y2) end
                local msg = table.concat(parts)
                if ms.dev and ms.dev._watcherPanel then
                    ms.devtools:watcherStep(msg)
                end
                if ms.dev then
                    ms.devtools:macroLog(msg)
                end
            end

            local btn  = BTNS[button]

            local ax1, ay1 = ms.resolvePoint(x1, y1, reference)
            local ax2, ay2 = ax1, ay1
            if x2 ~= nil and y2 ~= nil then ax2, ay2 = ms.resolvePoint(x2, y2, reference) end
            local pos1 = {
                x = ax1,
                y = ay1,
            }
            local pos2 = {
                x = ax2,
                y = ay2,
            }

            local downT, upT, dragT
            if btn == 0 then
                downT = hs.eventtap.event.types.leftMouseDown
                upT   = hs.eventtap.event.types.leftMouseUp
                dragT = hs.eventtap.event.types.leftMouseDragged
            elseif btn == 1 then
                downT = hs.eventtap.event.types.rightMouseDown
                upT   = hs.eventtap.event.types.rightMouseUp
                dragT = hs.eventtap.event.types.rightMouseDragged
            else
                downT = hs.eventtap.event.types.otherMouseDown
                upT   = hs.eventtap.event.types.otherMouseUp
                dragT = hs.eventtap.event.types.otherMouseDragged
            end

            local follow = operation ~= "Drag" and (reference == "Follow" or (reference == "Mouse" and (x1 or 0) == 0 and (y1 or 0) == 0 and (x2 or 0) == 0 and (y2 or 0) == 0))
            local function post(evType, pos)
                if follow then pos = hs.mouse.absolutePosition() end
                local ev = hs.eventtap.event.newMouseEvent(evType, pos)
                if btn >= 2 then
                    ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                end
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            local function moveTo(pos)
                if follow then return end
                local mv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos)
                mv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                mv:post()
                hs.mouse.absolutePosition(pos)
            end

            local function singleClick(pos)
                post(downT, pos)
                ms.wait(hold)
                post(upT, pos)
            end

            if     operation == "Move"        then moveTo(pos1)
            elseif operation == "Click"       then moveTo(pos1)
            if not follow then ms.wait(50) end
            singleClick(pos1)
            elseif operation == "DoubleClick" then
                moveTo(pos1)
                if not follow then ms.wait(50) end
                singleClick(pos1)
                ms.wait(50)
                singleClick(pos1)
            elseif operation == "TripleClick" then
                moveTo(pos1)
                if not follow then ms.wait(50) end
                for i = 1, 3 do singleClick(pos1)
                if i < 3 then ms.wait(50) end end
            elseif operation == "Drag"        then
                moveTo(pos1)
                ms.wait(50)
                post(downT, pos1)
                ms.wait(50)
                post(dragT, pos2)
                hs.mouse.absolutePosition(pos2)
                ms.wait(50)
                post(upT, pos2)
            elseif operation == "Press"       then
                moveTo(pos1)
                post(downT, pos1)
                ms._macroHeldButtons[btn] = {
                    upT = upT,
                    pos = pos1,
                    owner = coroutine.running(),
                }
            elseif operation == "Release"     then
                post(upT, pos1)
                ms._macroHeldButtons[btn] = nil
            end
        end

        -- ms.cam camera drag via CGEvent --

        local _camEvType  = hs.eventtap.event.types.otherMouseDragged
        local _camBtn     = hs.eventtap.event.properties.mouseEventButtonNumber
        local _camDx      = hs.eventtap.event.properties.mouseEventDeltaX
        local _camDy      = hs.eventtap.event.properties.mouseEventDeltaY
        local _camTotalX  = 0
        local _camTotalY  = 0
        local _camRebalancing = false
        local _camAnchor  = nil
        local _camActivated = false
        local _camTransforms = {}

        local function _updateCamAnchor()
            local win = ms.getTargetWin()
            if win then
                local f = win:frame()
                _camAnchor = {
                    x = f.x + (f.w / 2),
                    y = f.y + (f.h / 2),
                }
            end
        end

        local function _activateCam()
            if _camActivated then return end
            local pos = hs.mouse.absolutePosition()
            local downEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, pos)
            local upEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseUp, pos)
            downEv:setProperty(_camBtn, 5)
            upEv:setProperty(_camBtn, 5)
            downEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
            upEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
            _camActivated = true
            downEv:post()
            local co, isMain = coroutine.running()
            if co and not isMain then
                ms.wait(10)
                upEv:post()
            else
                hs.timer.doAfter(0.01, function() upEv:post() end)
            end
        end

        ms._updateCamAnchor = _updateCamAnchor
        ms._activateCam = _activateCam
        ms._resetCamActivated = function() _camActivated = false end

        ms.cam = setmetatable({}, {
            __call = function(_, dx, dy)
                if not _camActivated then _activateCam() end

                local transform = ms._targetApp and _camTransforms[ms._targetApp]
                if transform then
                    local ok, tx, ty = pcall(transform, dx, dy)
                    if ok and type(tx) == "number" and type(ty) == "number" then
                        dx = tx
                        dy = ty
                    end
                end

                dx = math.floor(dx + 0.5)
                dy = math.floor(dy + 0.5)

                local pos = hs.mouse.absolutePosition()
                local ev  = hs.eventtap.event.newMouseEvent(_camEvType, pos)
                ev:setProperty(_camBtn, 5)
                ev:setProperty(_camDx, dx)
                ev:setProperty(_camDy, dy)
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()


                if not _camRebalancing then
                    _camTotalX = _camTotalX + dx
                    _camTotalY = _camTotalY + dy
                end
            end,
        })

        ms.bus.on("ui:_shell:navigate", function(data)
            if data and data.panel then
                _updateCamAnchor()
            end
        end)
        local _origCamCall = getmetatable(ms.cam).__call
        getmetatable(ms.cam).__call = function(self, dx, dy)
            dx = math.floor(dx + 0.5)
            dy = math.floor(dy + 0.5)
            local saved = ms.dev and ms.devtools and ms.devtools:getTraceSuppress()
            if saved ~= nil then ms.devtools:setTraceSuppress(true) end
            _origCamCall(self, dx, dy)
            if saved ~= nil then ms.devtools:setTraceSuppress(saved) end
            if ms.dev and ms.devtools then
                ms.devtools:accCamMove(dx, dy, ms._getCallChain())
            end
        end

        ms.cam.rebalance = function(granularity)
            if granularity == nil then
                granularity = 4
            end
            if _camTotalX == 0 and _camTotalY == 0 then return end
            _camRebalancing = true
            local div1 = 1/granularity
            local div2 = div1/2
            for i = 1, granularity * 2 do
                ms.cam(-_camTotalX * div2, -_camTotalY * div2)
                ms.wait(2)
            end
            _camTotalX = 0
            _camTotalY = 0
            _camRebalancing = false
        end

        ms.cam.setTransform = function(app, fn)
            assert(type(app) == "string" and app ~= "",
                "ms.cam.setTransform: app must be a non-empty string")
            assert(fn == nil or type(fn) == "function",
                "ms.cam.setTransform: fn must be a function or nil")
            _camTransforms[app] = fn
        end

        ms.cam.reset = function()
            _camTotalX = 0
            _camTotalY = 0
        end

        ms.flick = function(dx, dy, opts)
            opts = opts or {}
            local count = opts.count or math.max(1, math.floor(math.abs(dx) / 100 + 0.5))
            local gapUs = opts.gapUs or ms._flickGapUs or 1000
            local perX, remX = math.floor(dx / count), dx % count
            local perY, remY = math.floor(dy / count), dy % count
            local accX, accY = 0, 0
            local i = 0
            local function step()
                i = i + 1
                local ex = perX
                accX = accX + remX
                if accX >= count then ex = ex + 1
                accX = accX - count end
                local ey = perY
                accY = accY + remY
                if accY >= count then ey = ey + 1
                accY = accY - count end
                ms.cam(ex, ey)
            end
            local co, isMain = coroutine.running()
            if co and not isMain then
                for n = 1, count do
                    step()
                    if n < count then ms.wait(gapUs / 1000) end
                end
                return
            end
            local function schedule()
                step()
                if i < count then hs.timer.doAfter(gapUs / 1000000, schedule) end
            end
            schedule()
        end

        local _sweepQueue = {}
        local _sweepTimer = nil
        local _SWEEP_HZ   = 120

        local function _sweepTick()
            if #_sweepQueue == 0 then
                if _sweepTimer then _sweepTimer:stop()
                _sweepTimer = nil end
                return
            end
            local job = _sweepQueue[1]
            if job.ticksLeft <= 0 then
                table.remove(_sweepQueue, 1)
                if #_sweepQueue == 0 then
                    if _sweepTimer then _sweepTimer:stop()
                    _sweepTimer = nil end
                end
                return
            end
            local perTickX = job.dx / job.totalTicks
            local perTickY = job.dy / job.totalTicks
            local ex = math.floor(perTickX * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickX * (job.totalTicks - job.ticksLeft))
            local ey = math.floor(perTickY * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickY * (job.totalTicks - job.ticksLeft))
            if ex == 0 and ey == 0 then ex = perTickX >= 0 and 1 or -1
            ey = 0 end
            ms.cam(ex, ey)
            job.ticksLeft = job.ticksLeft - 1
        end

        ms.cam.sweep = function(dx, dy, durationMs)
            local ticks = math.max(1, math.floor((durationMs / 1000) * _SWEEP_HZ + 0.5))
            _sweepQueue[#_sweepQueue + 1] = {
                dx = dx,
                dy = dy,
                ticksLeft = ticks,
                totalTicks = ticks,
            }
            if not _sweepTimer then
                _sweepTimer = hs.timer.doEvery(1 / _SWEEP_HZ, _sweepTick)
            end
        end

        ms.cam.sweepBlocking = function(dx, dy, durationMs)
            ms.cam.sweep(dx, dy, durationMs)
            ms.wait(durationMs)
        end

        ms.cam.sweepCancel = function()
            _sweepQueue = {}
            if _sweepTimer then _sweepTimer:stop()
            _sweepTimer = nil end
        end

        -- END ms.cam --

    end
-- END core/mouse --

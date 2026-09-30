-- core/compiler_bridge (Macro Lab Shell <-> Compiler bridge) --
    return function(ms)
        do
            local function _macroShellEval(js)
                if ms.shell and ms.shell.eval then
                    ms.shell.eval(js)
                end
            end

            if ms.bus then
                ms.bus.on("ui:macros:listMacros", function(body)
                    local ids = ms.compiler.list()
                    local json = hs.json.encode(ids)
                    _macroShellEval("if(window.macroLab)macroLab.setMacroList(" .. json .. ")")
                end)

                ms.bus.on("ui:macros:listBinds", function()
                    if ms.ui and ms.ui.pushBindList then
                        pcall(ms.ui.pushBindList)
                    end
                end)

                ms.bus.on("ui:macros:getMacro", function(_, body)
                    if not body or not body.id then return end
                    local def = ms.compiler.get(body.id)
                    if def then
                        local json = hs.json.encode(def)
                        _macroShellEval("if(window.macroLab)macroLab.setMacroDef(" .. json .. ")")
                    end
                end)

                local function _registerAndNotify()
                    pcall(ms.compiler.load)
                    if ms.bind and ms.bind.rebind then pcall(ms.bind.rebind) end
                    _macroShellEval("if(window.shellReceive)shellReceive('macros','macroSaved',{})")
                    if ms.ui and ms.ui.pushBindList then pcall(ms.ui.pushBindList) end
                end

                ms.bus.on("ui:macros:saveMacro", function(_, body)
                    if not body or not body.id or not body.def then
                        return
                    end
                    local ok, err = pcall(ms.compiler.write, body.id, body.def)
                    if ok then
                        -- Surface a compile error to the builder
                        local compileErr = ms.compiler._errors
                            and ms.compiler._errors[body.id]
                        _registerAndNotify()
                        if compileErr then
                            print("ms.compiler.saveMacro: '" .. tostring(body.id)
                                .. "' saved but failed to compile: " .. tostring(compileErr))
                            local payload = hs.json.encode({
                                id  = body.id,
                                err = tostring(compileErr),
                            })
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','saveError',"
                                .. payload .. ")")
                        else
                            print("ms.compiler.saveMacro: '" .. tostring(body.id) .. "' saved and registered")
                        end
                    else
                        print("ms.compiler.saveMacro error: " .. tostring(err))
                        local payload = hs.json.encode({
                            id  = body.id,
                            err = tostring(err),
                        })
                        _macroShellEval("if(window.shellReceive)shellReceive('macros','saveError',"
                            .. payload .. ")")
                    end
                end)

                ms.bus.on("ui:macros:deleteMacro", function(_, body)
                    if not body or not body.id then return end
                    local id = body.id

                    local isVisual = false
                    if ms.compiler and ms.compiler.list then
                        local okL, ids = pcall(ms.compiler.list)
                        if okL and type(ids) == "table" then
                            for _, vid in ipairs(ids) do
                                if vid == id then isVisual = true
                                break end
                            end
                        end
                    end

                    if isVisual then
                        local ok, err = pcall(ms.compiler.delete, id)
                        if ok then
                            print("ms.compiler.deleteMacro: '" .. tostring(id) .. "' removed")
                            _registerAndNotify()
                        else
                            print("ms.compiler.deleteMacro error: " .. tostring(err))
                        end
                    elseif ms.suppressMacro and ms.suppressMacro(id) then
                        print("deleteMacro: suppressed handwritten macro '" .. tostring(id) .. "'")
                        _macroShellEval("if(window.shellReceive)shellReceive('macros','macroSaved',{})")
                        if ms.ui and ms.ui.pushBindList then pcall(ms.ui.pushBindList) end
                    else
                        print("deleteMacro: '" .. tostring(id) .. "' is neither a visual macro nor a suppressible bind")
                    end
                end)

                ms.bus.on("ui:macros:getMeta", function()
                    local ok, meta = pcall(ms.compiler.getMeta)
                    local json = hs.json.encode(ok and meta or {})
                    _macroShellEval("if(window.macroLab)macroLab.setMeta(" .. json .. ")")
                end)

                ms.bus.on("ui:macros:setMeta", function(_, body)
                    if type(body) ~= "table" then return end
                    local ok, err = pcall(ms.compiler.setMeta, {
                        name    = body.name,
                        version = body.version,
                        author  = body.author,
                        website = body.website,
                    })
                    if ok then
                        print("ms.compiler.setMeta: pack meta updated")
                        _registerAndNotify()
                    else
                        print("ms.compiler.setMeta error: " .. tostring(err))
                    end
                end)

                ms.bus.on("ui:macros:testRun", function(_, body)
                    local reported = false
                    local hid = false
                    local function send(ok, err)
                        local res = hs.json.encode({
                            ok = ok and true or false,
                            err = err or "",
                        })
                        _macroShellEval("if(window.shellReceive)shellReceive('macros','testRunResult'," .. res .. ")")
                    end
                    local function report(ok, err)
                        if reported then return end
                        reported = true
                        if not hid then return send(ok, err) end
                        ms.shell.show()
                        hs.timer.doAfter(0.15, function() send(ok, err) end)
                    end
                    if not body then report(false, "no macro definition")
                    return end
                    local function cancelTestRuns()
                        for co, ctx in pairs(ms._coroContext or {}) do
                            local root = ctx.callStack and ctx.callStack[1]
                            if type(root) == "string" and root:sub(1, 5) == "test:" then
                                ctx.cancelled = true
                                ms._coroContext[co] = nil
                                if ms._activeContexts then ms._activeContexts[ctx] = nil end
                            end
                        end
                    end
                    local function run()
                        local callOk, cerr = pcall(ms.compiler.testRun, body, report)
                        if not callOk then report(false, tostring(cerr)) end
                        hs.timer.doAfter(30, function()
                            if reported then return end
                            cancelTestRuns()
                            report(false, "Test run timed out")
                        end)
                    end
                    if body.hideShell and ms.shell and ms._shellState and ms._shellState.visible then
                        hid = true
                        ms.shell.hide()
                        local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                        hs.timer.doAfter(fadeMs / 1000 + 0.2, run)
                    else
                        run()
                    end
                end)

                do
                    local rec = {
                        tap = nil, winFilter = nil, lastTs = nil,
                        threshold = 50, opts = {}, drag = nil, winFrames = {},
                        move = nil, _inFlush = false, _resample = nil,
                        _moveFlushTimer = nil, _startTimer = nil,
                        hidden = false, held = {},
                    }
                    ms._macroRecord = rec

                    local HOLD_S = 0.4

                    local function sendStep(json)
                        _macroShellEval("if(window.shellReceive)shellReceive('macros','recordStep'," .. json .. ")")
                    end

                    local function sendOldest()
                        local json = table.remove(rec.held, 1)
                        if json then sendStep(json) end
                    end

                    local function pushStep(action, params)
                        local json = hs.json.encode({
                            action = action,
                            params = params,
                        })
                        if not rec.hidden then return sendStep(json) end
                        rec.held[#rec.held + 1] = json
                        hs.timer.doAfter(HOLD_S, sendOldest)
                    end

                    local flushMoves

                    local function maybeWait()
                        if not rec._inFlush then flushMoves() end
                        local now = hs.timer.secondsSinceEpoch()
                        if rec.opts.recordDelays ~= false and rec.lastTs then
                            local dt = math.floor((now - rec.lastTs) * 1000 + 0.5)
                            if dt >= rec.threshold then
                                pushStep("ms.wait", { ms = dt })
                            end
                        end
                        rec.lastTs = now
                    end

                    local function inShell(pt)
                        if not pt then return false end
                        local ok, frame = pcall(function()
                            if ms.shell and ms.shell.webview and ms.shell.webview() then
                                return ms.shell.webview():frame()
                            end
                        end)
                        if ok and frame then
                            return pt.x >= frame.x and pt.x <= frame.x + frame.w
                                and pt.y >= frame.y and pt.y <= frame.y + frame.h
                        end
                        return false
                    end

                    local function modsOf(ev)
                        local f = ev:getFlags()
                        local mods = {}
                        if f.cmd   then mods[#mods + 1] = "cmd"   end
                        if f.alt   then mods[#mods + 1] = "alt"   end
                        if f.ctrl  then mods[#mods + 1] = "ctrl"  end
                        if f.shift then mods[#mods + 1] = "shift" end
                        return mods
                    end

                    local function buttonOf(t, et)
                        if t == et.rightMouseDown or t == et.rightMouseUp
                            or t == et.rightMouseDragged then return "Right" end
                        if t == et.otherMouseDown or t == et.otherMouseUp
                            or t == et.otherMouseDragged then return "Center" end
                        return "Left"
                    end

                    local function emitClick(button, pt)
                        pushStep("ms.Mouse", {
                            operation = "Click", button = button, reference = "Absolute",
                            x = math.floor((pt and pt.x or 0) + 0.5),
                            y = math.floor((pt and pt.y or 0) + 0.5),
                        })
                    end

                    -- Emit buffered free-cursor movement as moveMouse steps
                    flushMoves = function()
                        if rec._moveFlushTimer then
                            rec._moveFlushTimer:stop()
                            rec._moveFlushTimer = nil
                        end
                        local m = rec.move
                        rec.move = nil
                        if not m or not m.points or #m.points < 2 then return end
                        local resample = rec._resample
                        local path = resample
                            and resample(m.points, rec.opts.moveGranularity) or m.points
                        if not path or #path < 2 then return end
                        rec._inFlush = true
                        maybeWait()
                        for i = 2, #path do
                            pushStep("ms.moveMouse", {
                                x = math.floor(path[i][1] + 0.5),
                                y = math.floor(path[i][2] + 0.5),
                                ref = "Absolute",
                                durationMs = 8,
                            })
                        end
                        rec._inFlush = false
                    end

                    rec.start = function(threshold, opts)
                        if rec.tap then return end
                        rec.threshold = tonumber(threshold) or 50
                        rec.opts = opts or {}
                        rec.lastTs = nil
                        rec.drag = nil
                        rec.move = nil
                        rec._inFlush = false
                        if rec._moveFlushTimer then
                            rec._moveFlushTimer:stop()
                            rec._moveFlushTimer = nil
                        end
                        local et = hs.eventtap.event.types

                        local mode  = rec.opts.pressMode or "type"
                        local types = { et.keyDown }
                        if mode == "pressRelease" then
                            types[#types + 1] = et.keyUp
                        end
                        if rec.opts.recordMouseButtons ~= false or rec.opts.recordDrags then
                            types[#types + 1] = et.leftMouseDown
                            types[#types + 1] = et.rightMouseDown
                            types[#types + 1] = et.otherMouseDown
                        end
                        if rec.opts.recordDrags then
                            types[#types + 1] = et.leftMouseUp
                            types[#types + 1] = et.rightMouseUp
                            types[#types + 1] = et.otherMouseUp
                            types[#types + 1] = et.leftMouseDragged
                            types[#types + 1] = et.rightMouseDragged
                            types[#types + 1] = et.otherMouseDragged
                        end
                        if rec.opts.recordMouseMoves then
                            types[#types + 1] = et.mouseMoved
                        end

                        local function resampleDrag(pts, granularity)
                            local n = #pts
                            if n <= 2 then return pts end
                            local g = tonumber(granularity) or 5
                            if g < 1 then g = 1 elseif g > 10 then g = 10 end
                            local epsilon = 40 / g

                            local keep = {}
                            keep[1] = true
                            keep[n] = true
                            local stack = { {
                                1,
                                n,
                            } }
                            while #stack > 0 do
                                local seg = table.remove(stack)
                                local first, last = seg[1], seg[2]
                                local ax, ay = pts[first][1], pts[first][2]
                                local bx, by = pts[last][1], pts[last][2]
                                local dx, dy = bx - ax, by - ay
                                local len2 = dx * dx + dy * dy
                                local maxD, idx = -1, nil
                                for i = first + 1, last - 1 do
                                    local px, py = pts[i][1], pts[i][2]
                                    local dist
                                    if len2 == 0 then
                                        local ex, ey = px - ax, py - ay
                                        dist = math.sqrt(ex * ex + ey * ey)
                                    else
                                        local t = ((px - ax) * dx + (py - ay) * dy) / len2
                                        if t < 0 then t = 0 elseif t > 1 then t = 1 end
                                        local cx, cy = ax + t * dx, ay + t * dy
                                        local ex, ey = px - cx, py - cy
                                        dist = math.sqrt(ex * ex + ey * ey)
                                    end
                                    if dist > maxD then maxD, idx = dist, i end
                                end
                                if idx and maxD > epsilon then
                                    keep[idx] = true
                                    stack[#stack + 1] = {
                                        first,
                                        idx,
                                    }
                                    stack[#stack + 1] = {
                                        idx,
                                        last,
                                    }
                                end
                            end

                            local out = {}
                            for i = 1, n do if keep[i] then out[#out + 1] = pts[i] end end

                            local CAP = 200
                            if #out > CAP then
                                local trimmed, stepN, acc = {}, #out / CAP, 1
                                for i = 1, CAP do
                                    trimmed[i] = out[math.floor(acc + 0.5)] or out[#out]
                                    acc = acc + stepN
                                end
                                trimmed[1] = out[1]
                                trimmed[CAP] = out[#out]
                                out = trimmed
                            end
                            return out
                        end

                        rec._resample = resampleDrag

                        rec.tap = hs.eventtap.new(types, function(ev)
                            local ok = pcall(function()
                                local t = ev:getType()

                                if t == et.keyDown then
                                    local key = hs.keycodes.map[ev:getKeyCode()]
                                    if type(key) ~= "string" or key == "" then return end
                                    local mods = modsOf(ev)
                                    maybeWait()
                                    if mode == "press" or mode == "pressRelease" then
                                        pushStep("ms.press", {
                                            key = key,
                                            mods = mods,
                                        })
                                    else
                                        pushStep("ms.type", {
                                            key = key,
                                            mods = mods,
                                        })
                                    end
                                    return
                                end
                                if t == et.keyUp then
                                    local key = hs.keycodes.map[ev:getKeyCode()]
                                    if type(key) ~= "string" or key == "" then return end
                                    maybeWait()
                                    pushStep("ms.release", { key = key })
                                    return
                                end

                                if t == et.mouseMoved then
                                    if rec.drag then return end
                                    local pt = ev:location()
                                    if inShell(pt) then return end
                                    if not rec.move then rec.move = { points = {} } end
                                    local pts = rec.move.points
                                    if #pts < 4000 then
                                        pts[#pts + 1] = {
                                            pt.x,
                                            pt.y,
                                        }
                                    end
                                    -- Commit a movement run once the cursor goes idle
                                    if rec._moveFlushTimer then
                                        rec._moveFlushTimer:stop()
                                    end
                                    rec._moveFlushTimer = hs.timer.doAfter(0.15, function()
                                        rec._moveFlushTimer = nil
                                        pcall(flushMoves)
                                    end)
                                    return
                                end

                                if t == et.leftMouseDown or t == et.rightMouseDown
                                    or t == et.otherMouseDown then
                                    local pt = ev:location()
                                    if inShell(pt) then return end
                                    local button = buttonOf(t, et)
                                    if rec.opts.recordDrags then
                                        -- Commit free movement before the press
                                        flushMoves()
                                        rec.drag = {
                                            button = button, moved = false,
                                            x1 = pt.x, y1 = pt.y, x2 = pt.x, y2 = pt.y,
                                            points = { {
                                                pt.x,
                                                pt.y,
                                            } },
                                        }
                                    elseif rec.opts.recordMouseButtons ~= false then
                                        maybeWait()
                                        emitClick(button, pt)
                                    end
                                    return
                                end

                                if t == et.leftMouseDragged or t == et.rightMouseDragged
                                    or t == et.otherMouseDragged then
                                    if rec.drag then
                                        local pt = ev:location()
                                        rec.drag.moved = true
                                        rec.drag.x2, rec.drag.y2 = pt.x, pt.y
                                        local pts = rec.drag.points
                                        if pts and #pts < 4000 then
                                            pts[#pts + 1] = {
                                                pt.x,
                                                pt.y,
                                            }
                                        end
                                    end
                                    return
                                end
                                if t == et.leftMouseUp or t == et.rightMouseUp
                                    or t == et.otherMouseUp then
                                    local d = rec.drag
                                    rec.drag = nil
                                    if not d then return end
                                    local pt = ev:location()
                                    d.x2, d.y2 = pt.x, pt.y
                                    if d.moved then
                                        maybeWait()
                                        if d.points then d.points[#d.points + 1] = {
                                            d.x2,
                                            d.y2,
                                        } end
                                        local path = d.points
                                            and resampleDrag(d.points, rec.opts.dragGranularity)
                                            or nil
                                        if path and #path >= 3 then
                                            local parts = {}
                                            for _, p in ipairs(path) do
                                                parts[#parts + 1] = math.floor(p[1] + 0.5)
                                                    .. "," .. math.floor(p[2] + 0.5)
                                            end
                                            pushStep("ms.dragPath", {
                                                points  = table.concat(parts, ";"),
                                                button  = d.button,
                                                ref     = "Absolute",
                                                delayMs = 10,
                                            })
                                        else
                                            pushStep("ms.Mouse", {
                                                operation = "Drag", button = d.button,
                                                reference = "Absolute",
                                                x  = math.floor(d.x1 + 0.5), y  = math.floor(d.y1 + 0.5),
                                                x2 = math.floor(d.x2 + 0.5), y2 = math.floor(d.y2 + 0.5),
                                            })
                                        end
                                    elseif rec.opts.recordMouseButtons ~= false
                                        and not inShell({
                                            x = d.x1,
                                            y = d.y1,
                                        }) then
                                        maybeWait()
                                        emitClick(d.button, {
                                            x = d.x1,
                                            y = d.y1,
                                        })
                                    end
                                    return
                                end
                            end)
                            if not ok then print("ms.macroRecord: capture error") end
                            return false
                        end)

                        if rec.tap then rec.tap:start() end

                        if rec.opts.recordWindowMove or rec.opts.recordWindowResize then
                            rec.winFrames = {}
                            local wf = hs.window.filter.new(nil)
                            rec.winFilter = wf
                            local function onWinChange(win)
                                local okw = pcall(function()
                                    if not win then return end
                                    local app = win:application()
                                    if app and app:name() == "Hammerspoon" then return end
                                    local id = win:id()
                                    local f  = win:frame()
                                    local prev = rec.winFrames[id]
                                    rec.winFrames[id] = {
                                        x = f.x,
                                        y = f.y,
                                        w = f.w,
                                        h = f.h,
                                    }
                                    if not prev then return end
                                    local moved   = (f.x ~= prev.x) or (f.y ~= prev.y)
                                    local resized = (f.w ~= prev.w) or (f.h ~= prev.h)
                                    if resized and rec.opts.recordWindowResize then
                                        maybeWait()
                                        pushStep("ms.window", {
                                            operation = "Resize",
                                            x = math.floor(f.w + 0.5), y = math.floor(f.h + 0.5),
                                        })
                                    elseif moved and rec.opts.recordWindowMove then
                                        maybeWait()
                                        pushStep("ms.window", {
                                            operation = "Move",
                                            x = math.floor(f.x + 0.5), y = math.floor(f.y + 0.5),
                                        })
                                    end
                                end)
                                if not okw then print("ms.macroRecord: window capture error") end
                            end
                            pcall(function()
                                for _, w in ipairs(wf:getWindows()) do
                                    if w and w.id and w:id() then
                                        local f = w:frame()
                                        rec.winFrames[w:id()] = {
                                            x = f.x,
                                            y = f.y,
                                            w = f.w,
                                            h = f.h,
                                        }
                                    end
                                end
                            end)
                            local wEvents = { hs.window.filter.windowMoved }
                            if hs.window.filter.windowsChanged then
                                wEvents[#wEvents + 1] = hs.window.filter.windowsChanged
                            end
                            wf:subscribe(wEvents, onWinChange)
                        end

                        print("ms.macroRecord: started (threshold "
                            .. rec.threshold .. "ms, mode " .. mode .. ")")
                    end

                    rec.stop = function(discardHeld)
                        if rec._startTimer then
                            rec._startTimer:stop()
                            rec._startTimer = nil
                        end
                        if rec._moveFlushTimer then
                            rec._moveFlushTimer:stop()
                            rec._moveFlushTimer = nil
                        end
                        flushMoves()
                        if discardHeld then rec.held = {} end
                        while #rec.held > 0 do sendOldest() end
                        rec.hidden = false
                        if rec.tap then rec.tap:stop()
                        rec.tap = nil end
                        if rec.winFilter then
                            pcall(function() rec.winFilter:unsubscribeAll() end)
                            rec.winFilter = nil
                        end
                        rec.drag = nil
                        rec.move = nil
                        rec._inFlush = false
                        rec.lastTs = nil
                        rec.winFrames = {}
                        print("ms.macroRecord: stopped")
                    end

                    ms.bus.on("ui:macros:startRecording", function(_, body)
                        body = body or {}
                        if rec.tap or rec._startTimer then return end
                        if not (body.hideShell and ms.shell and ms._shellState and ms._shellState.visible) then
                            return rec.start(body.waitThreshold, body.options)
                        end
                        rec.hidden = true
                        ms.shell.hide()
                        local fadeMs = (ms._theme and ms._theme.fadeMs) or 250
                        rec._startTimer = hs.timer.doAfter(fadeMs / 1000 + 0.2, function()
                            rec._startTimer = nil
                            rec.start(body.waitThreshold, body.options)
                        end)
                    end)
                    ms.bus.on("ui:macros:stopRecording", function()
                        rec.stop()
                    end)
                    ms.bus.on("macroLab:toggled", function(_, body)
                        if not (body and body.visible and rec.hidden) then return end
                        rec.stop(true)
                        hs.timer.doAfter(0.15, function()
                            _macroShellEval("if(window.shellReceive)shellReceive('macros','recordStopped',{})")
                        end)
                    end)
                end

                local _TOOL_TYPES = {
                    toggle = true,
                    slider = true,
                    seg = true,
                }
                ms.bus.on("ui:macros:listTools", function()
                    local tools = {}
                    for _, def in ipairs(ms._userSettingDefs or {}) do
                        if type(def) == "table" and def.key
                            and _TOOL_TYPES[def.type] then
                            tools[#tools + 1] = {
                                key     = def.key,
                                label   = def.label or def.key,
                                type    = def.type,
                                hint    = def.hint,
                                min     = def.min,
                                max     = def.max,
                                step    = def.step,
                                unit    = def.unit,
                                options = def.options,
                                default = def.default,
                                value   = ms.settings.get(def.key),
                                section = def.section,
                                source  = def.authored and "builder" or "pack",
                            }
                        end
                    end
                    -- Helper vars are bindable too, carrying kind="var" so the editor emits {__varRef}
                    if ms.vars and ms.vars.list then
                        local okV, vlist = pcall(ms.vars.list)
                        if okV and type(vlist) == "table" then
                            for _, v in ipairs(vlist) do
                                tools[#tools + 1] = {
                                    key     = v.name,
                                    label   = v.label or v.name,
                                    type    = v.type or "string",
                                    default = v.default,
                                    value   = v.value,
                                    hint    = v.hint,
                                    kind    = "var",
                                    source  = "helpervar",
                                }
                            end
                        end
                    end
                    local json = hs.json.encode(tools)
                    _macroShellEval("if(window.macroLab)macroLab.setToolList(" .. json .. ")")

                    -- Function tools list: builder-authored functions plus the pack's bound macros
                    local fns = {}
                    local seenFn = {}
                    if ms.compiler and ms.compiler.listFunctions then
                        local okF, flist = pcall(ms.compiler.listFunctions)
                        if okF and type(flist) == "table" then
                            for _, f in ipairs(flist) do
                                f.source = "builder"
                                seenFn[f.id] = true
                                fns[#fns + 1] = f
                            end
                        end
                    end
                    if ms.registry and ms.registry._defList then
                        for _, id in ipairs(ms.registry._defList) do
                            local d = ms.registry._defs[id]
                            if d and not d.system and not seenFn[id]
                                and ms.bind and ms.bind._wires
                                and ms.bind._wires[id] then
                                fns[#fns + 1] = {
                                    id     = id,
                                    name   = d.label or id,
                                    group  = d.group,
                                    source = "pack",
                                }
                            end
                        end
                    end
                    -- Tools defined with a run fn are callable, so surface them in the Functions list
                    if ms._toolDefs then
                        for _, def in ipairs(ms._toolDefs) do
                            if type(def) == "table" and def.id
                                and type(def.run) == "function"
                                and not seenFn[def.id] then
                                seenFn[def.id] = true
                                fns[#fns + 1] = {
                                    id     = def.id,
                                    name   = def.name or def.id,
                                    source = def._origin or "plugin",
                                }
                            end
                        end
                    end
                    local fjson = hs.json.encode(fns)
                    _macroShellEval("if(window.macroLab&&window.macroLab.setFunctionList)macroLab.setFunctionList(" .. fjson .. ")")
                end)

                -- Function tool authoring (reuses the macro step canvas).
                ms.bus.on("ui:tools:saveFunction", function(_, body)
                    if type(body) ~= "table" or not body.id or not body.def then return end
                    local ok, err = pcall(ms.compiler.writeFunction, body.id, body.def)
                    if ok then
                        print("ms.compiler.saveFunction: '" .. tostring(body.id) .. "' saved")
                        if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{})")
                    else
                        print("ms.compiler.saveFunction error: " .. tostring(err))
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{error:" .. hs.json.encode(tostring(err)) .. "})")
                    end
                end)

                ms.bus.on("ui:tools:getFunction", function(_, body)
                    if type(body) ~= "table" or not body.id then return end
                    local def = ms.compiler.getFunction(body.id)
                    if def then
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','functionDef',"
                            .. hs.json.encode(def) .. ")")
                    end
                end)

                ms.bus.on("ui:tools:deleteFunction", function(_, body)
                    if type(body) ~= "table" or not body.id then return end
                    local ok, err = pcall(ms.compiler.deleteFunction, body.id)
                    if ok then
                        if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','functionSaved',{})")
                    else
                        print("ms.compiler.deleteFunction error: " .. tostring(err))
                    end
                end)

                -- Helper var declaration (disk-persistent shared variables).
                ms.bus.on("ui:tools:saveHelperVar", function(_, body)
                    if type(body) ~= "table" or not body.def then return end
                    local ok, err = ms.vars.define(body.def)
                    if ok then
                        print("ms.vars.define: '" .. tostring(body.def.name) .. "' saved")
                        if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                        -- Rebuild and push UI state so the Variable list includes the new var
                        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                        if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{})")
                    else
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{error:" .. hs.json.encode(tostring(err)) .. "})")
                    end
                end)

                ms.bus.on("ui:tools:deleteHelperVar", function(_, body)
                    if type(body) ~= "table" or not body.name then return end
                    local ok = ms.vars.remove(body.name)
                    if ok then
                        if ms.bus and ms.bus.emit then pcall(ms.bus.emit, "ui:macros:listTools") end
                        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                        if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                        _macroShellEval("if(window.shellReceive)shellReceive('tools','helperVarSaved',{})")
                    end
                end)
            end
        end
    end
-- END core/compiler_bridge --

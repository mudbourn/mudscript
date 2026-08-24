return function(ms)
-- MsAlert --
    local MsAlert = {}

    MsAlert.name    = "MsAlert"
    MsAlert.version = "1.0"

    MsAlert.maxAlerts    = 4
    MsAlert.bottomY      = 150
    MsAlert.getAnimDuration = function()
        return (ms._theme and ms._theme.alertAnimMs or 250) / 1000
    end
    MsAlert.getAnimSteps = function()
        return (ms._theme and ms._theme.alertAnimSteps or 30)
    end
-- END MsAlert --

-- State --
    local queue = {}
    -- The state tier: a reserved single slot that always sits at the bottom
    -- anchor (most prominent) with every normal alert stacked above it, and is
    -- never evicted by maxAlerts. Only one occupant at a time -- macro bind
    -- state and octane share it. A new state message morphs the live slot in
    -- place instead of tearing it down and rebuilding.
    local stateEntry = nil
-- END State --

-- Helpers --
    local function screenBounds()
        local f = hs.screen.mainScreen():frame()

        return f.x, f.y, f.w, f.y + f.h
    end

    local function hexToColor(hex, default)
        if type(hex) ~= "string" then return default end

        local h = hex:match("^#?([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")

        if not h then return default end

        return {
            red   = tonumber(h:sub(1, 2), 16) / 255,
            green = tonumber(h:sub(3, 4), 16) / 255,
            blue  = tonumber(h:sub(5, 6), 16) / 255,
            alpha = 1,
        }
    end

    -- Shared geometry so makeCanvas and the in-place morph agree on sizing.
    local PADDING = 16
    local LINE_H  = 20
    local CLOSE_W = 22

    local function measure(msg)
        local lines = {}

        for line in ((msg or "") .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end

        local longestLine = 0

        for _, line in ipairs(lines) do
            if #line > longestLine then longestLine = #line end
        end

        local charW = 8
        local cw    = math.max(200, math.min(600, longestLine * charW + PADDING * 2)) + CLOSE_W
        local textH = #lines * LINE_H
        local ch    = textH + PADDING * 2

        return cw, ch, textH
    end

    local function themeColors()
        local theme       = ms._theme or {}
        local bgColor     = hexToColor(theme.surface2, {
            red = 0.11, green = 0.063, blue = 0.047, alpha = 1,
        })
        local txtColor    = hexToColor(theme.text, {
            red = 0.94, green = 0.87, blue = 0.69, alpha = 1,
        })
        local accentColor = hexToColor(theme.accent, {
            red = 0.77, green = 0.10, blue = 0.10, alpha = 1,
        })

        bgColor.alpha = 0.88

        return bgColor, txtColor, accentColor
    end
-- END Helpers --

-- Canvas --
    local function makeCanvas(msg, x, y, w, alpha)
        local padding = PADDING
        local closeW  = CLOSE_W

        local cw, ch, textH = measure(msg)
        local cx            = x + (w - cw) / 2

        local theme                        = ms._theme or {}
        local bgColor, txtColor, accentColor = themeColors()
        local radius      = type(theme.radius) == "number" and math.max(0, theme.radius) or 3

        local font = "Helvetica"

        if type(theme.font) == "string" and #theme.font > 0
            and not theme.font:find("[/\\]") then
            font = theme.font
        end

        local c = hs.canvas.new({
            x = cx,
            y = y,
            w = cw,
            h = ch,
        })

        c:level((hs.canvas.windowLevels.screenSaver or 1000) + 1)
        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
        c:alpha(alpha or 0)

        c:appendElements(
            {
                type                = "rectangle",
                action              = "strokeAndFill",
                fillColor           = bgColor,
                strokeColor         = accentColor,
                strokeWidth         = 1,
                roundedRectRadii    = {
                    xRadius = radius,
                    yRadius = radius,
                },
                trackMouseEnterExit = true,
            },
            {
                type          = "text",
                text          = msg,
                textFont      = font,
                textSize      = 13,
                textColor     = txtColor,
                textAlignment = "center",
                frame         = {
                    x = 0,
                    y = padding + 4,
                    w = cw,
                    h = textH,
                },
            },
            {
                type          = "text",
                text          = "\xe2\x9c\x95",
                textFont      = "Helvetica",
                textSize      = 10,
                textColor     = {
                    red   = txtColor.red,
                    green = txtColor.green,
                    blue  = txtColor.blue,
                    alpha = 0,
                },
                textAlignment = "center",
                frame         = {
                    x = cw - closeW,
                    y = 5,
                    w = closeW - 4,
                    h = 14,
                },
                trackMouseDown = true,
            }
        )

        c:show()

        local xShowColor = {
            red   = txtColor.red,
            green = txtColor.green,
            blue  = txtColor.blue,
            alpha = 0.45,
        }

        local xHideColor = {
            red   = txtColor.red,
            green = txtColor.green,
            blue  = txtColor.blue,
            alpha = 0,
        }

        local function showX()
            pcall(function() c:elementAttribute(3, "textColor", xShowColor) end)
        end

        local function hideX()
            pcall(function() c:elementAttribute(3, "textColor", xHideColor) end)
        end

        return c, ch, showX, hideX
    end
-- END Canvas --

-- Animation --
    local function animateEntry(entry, fromY, toY, fromAlpha, toAlpha, onDone, force)
        if entry._animTimer then entry._animTimer:stop() end

        if ms and ms._octaneMode and not force then
            if entry.canvas then
                local f = entry.canvas:frame()
                entry.canvas:frame({
                    x = f.x,
                    y = toY,
                    w = f.w,
                    h = f.h,
                })
                entry.canvas:alpha(toAlpha)
            end
            if onDone then onDone() end
            return
        end

        local step = 0
        local animDuration = MsAlert.getAnimDuration()
        local animSteps = MsAlert.getAnimSteps()

        entry._animTimer = hs.timer.doEvery(animDuration / animSteps, function()
            step = step + 1

            local t    = step / animSteps
            local ease = 1 - (1 - t) ^ 3
            local y     = fromY     + (toY     - fromY)     * ease
            local alpha = fromAlpha + (toAlpha - fromAlpha) * ease

            if entry.canvas then
                local f = entry.canvas:frame()

                entry.canvas:frame({
                    x = f.x,
                    y = y,
                    w = f.w,
                    h = f.h,
                })
                entry.canvas:alpha(alpha)
            end

            if step >= animSteps then
                entry._animTimer:stop()
                entry._animTimer = nil

                if onDone then onDone() end
            end
        end)
    end

    local function fadeOut(entry, onDone, force)
        if not entry.canvas then
            if onDone then onDone() end

            return
        end

        local f = entry.canvas:frame()

        animateEntry(entry, f.y, f.y, 1, 0, onDone, force)
    end

    -- Morph the live state slot to a new message in place: cross-fade the text
    -- and tween the box width so a bind flip (enabled -> disabled, octane
    -- on -> off) reads as one alert changing its mind, never a teardown and
    -- rebuild. Always animates -- these confirmations should be seen even when
    -- octane mode has muted every other animation.
    local function morphStateEntry(entry, newMsg)
        local c = entry.canvas

        if not c then return end
        if entry._morphTimer then
            entry._morphTimer:stop()
            entry._morphTimer = nil
        end

        local _, txtColor = themeColors()
        local sx, _, sw   = screenBounds()

        -- Start from the canvas's live width, not the old message's, so a flip
        -- landing mid-morph tweens from wherever the box currently is.
        local oldW               = c:frame().w or ({ measure(entry.msg or "") })[1]
        local newW, newH, textH  = measure(newMsg)

        local steps  = MsAlert.getAnimSteps()
        local dur    = MsAlert.getAnimDuration()
        local half   = math.floor(steps / 2)
        local step   = 0
        local swapped = false

        local function apply(w, textAlpha)
            local f  = c:frame()
            local cx = sx + (sw - w) / 2

            c:frame({ x = cx, y = f.y, w = w, h = newH })

            pcall(function()
                c:elementAttribute(2, "textColor", {
                    red   = txtColor.red,
                    green = txtColor.green,
                    blue  = txtColor.blue,
                    alpha = textAlpha,
                })
            end)
            pcall(function()
                c:elementAttribute(2, "frame", { x = 0, y = PADDING + 4, w = w, h = textH })
            end)
            pcall(function()
                c:elementAttribute(3, "frame", { x = w - CLOSE_W, y = 5, w = CLOSE_W - 4, h = 14 })
            end)
        end

        entry._morphTimer = hs.timer.doEvery(dur / steps, function()
            step = step + 1

            local t     = step / steps
            local ease  = 1 - (1 - t) ^ 3
            local w     = oldW + (newW - oldW) * ease
            -- Triangular text fade: full -> 0 at the midpoint -> full.
            local alpha = (t <= 0.5) and (1 - t / 0.5) or ((t - 0.5) / 0.5)

            if step >= half and not swapped then
                swapped = true
                pcall(function() c:elementAttribute(2, "text", newMsg) end)
            end

            apply(w, alpha)

            if step >= steps then
                entry._morphTimer:stop()
                entry._morphTimer = nil

                apply(newW, 1)
                entry.h   = newH
                entry.msg = newMsg

                MsAlert:_redraw(nil)
            end
        end)
    end
-- END Animation --

-- Dismiss --
    local dismissEntry

    dismissEntry = function(entry)
        if entry.timer then
            entry.timer:stop()
            entry.timer = nil
        end

        for i, e in ipairs(queue) do
            if e == entry then
                table.remove(queue, i)

                fadeOut(e, function()
                    if e.canvas then e.canvas:delete() end
                end)

                MsAlert:_redraw(nil)

                break
            end
        end
    end

    function MsAlert:expireAll()
        for i = #queue, 1, -1 do
            local e = queue[i]
            if e then pcall(function() dismissEntry(e) end) end
        end

        if stateEntry then
            local e = stateEntry

            stateEntry = nil

            if e.timer then e.timer:stop() end
            if e._morphTimer then e._morphTimer:stop() end

            pcall(function()
                fadeOut(e, function()
                    if e.canvas then e.canvas:delete() end
                end, true)
            end)
        end

        MsAlert._sealed = true
    end

    function MsAlert:dismissAll()
        for i = #queue, 1, -1 do
            local e = queue[i]

            if e.timer then
                e.timer:stop()
                e.timer = nil
            end
            if e._animTimer then
                e._animTimer:stop()
                e._animTimer = nil
            end
            if e.canvas then
                pcall(function() e.canvas:delete() end)
                e.canvas = nil
            end
        end

        queue = {}

        if stateEntry then
            if stateEntry.timer then stateEntry.timer:stop() end
            if stateEntry._animTimer then stateEntry._animTimer:stop() end
            if stateEntry._morphTimer then stateEntry._morphTimer:stop() end
            if stateEntry.canvas then
                pcall(function() stateEntry.canvas:delete() end)
            end

            stateEntry = nil
        end
    end

    function MsAlert:recolor()
        local bgColor, txtColor, accentColor = themeColors()

        local function paint(e)
            if e and e.canvas then
                pcall(function() e.canvas:elementAttribute(1, "fillColor", bgColor) end)
                pcall(function() e.canvas:elementAttribute(1, "strokeColor", accentColor) end)
                pcall(function() e.canvas:elementAttribute(2, "textColor", txtColor) end)
            end
        end

        for _, e in ipairs(queue) do
            paint(e)
        end

        paint(stateEntry)
    end

    function MsAlert:dismissById(id)
        for i = #queue, 1, -1 do
            local e = queue[i]

            if e.id == id then
                if e.timer then
                    e.timer:stop()
                    e.timer = nil
                end
                if e._animTimer then
                    e._animTimer:stop()
                    e._animTimer = nil
                end
                if e.canvas then
                    pcall(function() e.canvas:delete() end)
                    e.canvas = nil
                end

                table.remove(queue, i)
            end
        end
    end

    local function dismissByIdAnimated(id)
        for _, e in ipairs(queue) do
            if e.id == id then
                dismissEntry(e)
                break
            end
        end
    end

    -- Retire the state slot: always fade it out first (forced, so octane mode
    -- can't skip straight to deletion while it's still on screen), then delete.
    local function dismissState()
        if not stateEntry then return end

        local e = stateEntry

        stateEntry = nil

        if e.timer then
            e.timer:stop()
            e.timer = nil
        end
        if e._morphTimer then
            e._morphTimer:stop()
            e._morphTimer = nil
        end

        fadeOut(e, function()
            if e.canvas then e.canvas:delete() end
        end, true)

        MsAlert:_redraw(nil)
    end

    local function createState(msg)
        local sx, _, sw, sBottom = screenBounds()
        local c, h, showX, hideX = makeCanvas(msg, sx, sBottom - MsAlert.bottomY, sw, 0)

        -- One level above the normal alerts so the reserved slot always wins
        -- any z-overlap, not just the vertical ordering.
        c:level((hs.canvas.windowLevels.screenSaver or 1000) + 2)

        local entry = {
            msg    = msg,
            canvas = c,
            h      = h,
            id     = "_state",
            source = "system",
            state  = true,
            _showX = showX,
            _hideX = hideX,
        }

        c:mouseCallback(function(_, m, elemId)
            if m == "mouseEnter" then
                entry._hovered = true

                if entry.timer then
                    entry.timer:stop()
                    entry.timer = nil
                end
                if entry._showX then entry._showX() end

            elseif m == "mouseExit" and elemId == 1 then
                entry._hovered = false

                if entry._hideX then entry._hideX() end

                if not entry.timer then
                    entry.timer = hs.timer.doAfter(2, function() dismissState() end)
                end

            elseif m == "mouseDown" and elemId == 3 then
                dismissState()
            end
        end)

        stateEntry = entry

        MsAlert:_redraw(entry)
    end
-- END Dismiss --

-- Redraw --
    function MsAlert:_redraw(newEntry)
        local sx, sy, sw, sBottom = screenBounds()

        for _, entry in ipairs(queue) do
            if not entry.h then
                local lines = {}

                for line in (entry.msg .. "\n"):gmatch("([^\n]*)\n") do
                    table.insert(lines, line)
                end

                entry.h = #lines * 20 + 32
            end
        end

        local currentY = sBottom - self.bottomY

        for i = #queue, 1, -1 do
            local entry   = queue[i]
            local targetY = currentY - entry.h

            currentY = targetY - 8

            if entry == newEntry then
                if not entry.canvas then
                    local c, h, showX, hideX = makeCanvas(entry.msg, sx, sBottom - self.bottomY, sw, 0)

                    entry.canvas = c
                    entry.h      = h
                    entry._showX = showX
                    entry._hideX = hideX

                    c:mouseCallback(function(cvs, msg, id, cx, cy)
                        if msg == "mouseEnter" then
                            entry._hovered = true

                            if entry.timer then
                                entry.timer:stop()
                                entry.timer = nil
                            end
                            if entry._showX then entry._showX() end

                        elseif msg == "mouseExit" and id == 1 then
                            entry._hovered = false

                            if entry._hideX then entry._hideX() end

                            if not entry.timer then
                                entry.timer = hs.timer.doAfter(2, function()
                                    dismissEntry(entry)
                                end)
                            end

                        elseif msg == "mouseDown" and id == 3 then
                            dismissEntry(entry)
                        end
                    end)
                end

                animateEntry(entry, sBottom - self.bottomY, targetY, 0, 1, nil)
            else
                if entry.canvas then
                    local f = entry.canvas:frame()

                    animateEntry(entry, f.y, targetY, 1, 1, nil)
                end
            end
        end

        -- The state slot sits above the entire normal stack -- highest on
        -- screen, on top of everything regardless of source. Forced fade only
        -- on first show; plain repositions respect octane mode like the rest.
        if stateEntry and stateEntry.canvas then
            local targetY = currentY - stateEntry.h

            if stateEntry == newEntry then
                animateEntry(stateEntry, sBottom - self.bottomY, targetY, 0, 1, nil, true)
            else
                local f = stateEntry.canvas:frame()

                animateEntry(stateEntry, f.y, targetY, 1, 1, nil)
            end
        end
    end
-- END Redraw --

-- State tier --
    -- The reserved 5th layer. Macro bind state and octane both route here.
    -- First call fades a fresh slot in; every later call morphs the live slot
    -- in place rather than obliterating and redrawing it.
    function MsAlert:_showState(msg, duration, noDefaultSound)
        if not ms._startupSoundDone then return end
        if MsAlert._sealed then return end

        duration = duration or 3

        if loadfinish == 1 and not noDefaultSound then
            ms.playSlot("alert")
        end

        if stateEntry and stateEntry.canvas then
            if stateEntry.timer then
                stateEntry.timer:stop()
                stateEntry.timer = nil
            end

            morphStateEntry(stateEntry, msg)
        else
            createState(msg)
        end

        if stateEntry and not stateEntry._hovered then
            stateEntry.timer = hs.timer.doAfter(duration, function()
                dismissState()
            end)
        end
    end
-- END State tier --

-- Call --
    function MsAlert:__call(msg, duration, noDefaultSound, opts)
        if not ms._startupSoundDone then return end

        if MsAlert._sealed then return end

        duration = duration or 5

        local src = opts and opts.source or "system"
        local id  = opts and opts.id or nil

        -- State-tier alerts (macro bind state, octane) bypass the normal queue
        -- entirely and live in the reserved slot.
        if opts and (opts.state or opts.priority == "state"
            or id == "_state" or id == "octane_state") then
            return self:_showState(msg, duration, noDefaultSound)
        end

        if id then
            dismissByIdAnimated(id)
        end

        if ms.dev and ms.dev.log and id ~= "_state" then
            local isError = msg and (
                msg:find("[Ff]ailed") or msg:find("[Ee]rror")
                or msg:find("[Cc]ould not") or msg:find("[Cc]annot")
                or msg:find("[Rr]ejected") or msg:find("[Dd]enied")
                or msg:find("[Aa]borted")
            )

            ms.dev.log({
                type   = isError and "error" or "system",
                event  = "alert",
                source = src,
                msg    = (msg or ""):sub(1, 200),
            })
        end

        if loadfinish == 1 and not noDefaultSound then
            ms.playSlot("alert")
        end

        if #queue >= self.maxAlerts then
            local oldest = queue[1]

            if oldest._animTimer then oldest._animTimer:stop() end
            if oldest.timer then oldest.timer:stop() end

            fadeOut(oldest, function()
                if oldest.canvas then oldest.canvas:delete() end
            end)

            table.remove(queue, 1)
        end

        local entry = {
            msg      = msg,
            canvas   = nil,
            timer    = nil,
            h        = nil,
            id       = opts and opts.id or nil,
            source   = src,
            priority = opts and opts.priority or "normal",
        }

        table.insert(queue, entry)
        self:_redraw(entry)

        entry.timer = hs.timer.doAfter(duration, function()
            dismissEntry(entry)
        end)
    end
-- END Call --

-- Make callable --
    setmetatable(MsAlert, {
        __call = function(self, ...)
            return self:__call(...)
        end,
    })
-- END Make callable --

return MsAlert
end

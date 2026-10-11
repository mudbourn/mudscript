return function(ms)
    -- Drag Guard --
        local CHECK_EVERY = 0.15
        local IDLE_LIMIT  = 2.0
        local FLOOD_RATE  = 400

        local _drags = {}
        local _timer = nil

        local function _log(msg)
            if ms.debug then ms.debug.log("drag", msg) end
        end

        local function _leftHeld()
            local ok, b = pcall(hs.mouse.getButtons)
            if not ok or type(b) ~= "table" then return nil end
            return b.left == true or b[1] == true
        end

        local function _stopTimer()
            if _timer then _timer:stop() end
            _timer = nil
        end

        local function _finish(name, reason)
            local d = _drags[name]
            if not d then return end
            _drags[name] = nil
            local secs = hs.timer.secondsSinceEpoch() - d.started
            _log(string.format("%s ended (%s) after %.2fs, %d moves", name, reason, secs, d.moves))
            if reason ~= "mouse up" and reason ~= "page" then
                print("[MsShell] " .. name .. " drag released: " .. reason)
            end
            pcall(d.stop)
            if next(_drags) == nil then _stopTimer() end
        end

        local function _tick()
            local now = hs.timer.secondsSinceEpoch()
            local held = _leftHeld()
            for name, d in pairs(_drags) do
                if held == false then
                    _finish(name, "button no longer held, mouse up was missed")
                elseif held == nil and now - d.lastMove > IDLE_LIMIT then
                    _finish(name, "no movement and button state unknown")
                else
                    local span = now - d.windowStart
                    if span >= 1 then
                        local rate = d.windowMoves / span
                        if rate > FLOOD_RATE then
                            _log(string.format("%s flood: %.0f moves/s", name, rate))
                        end
                        d.windowStart = now
                        d.windowMoves = 0
                    end
                end
            end
        end

        ms.shell.beginDrag = function(name, stopFn)
            local now = hs.timer.secondsSinceEpoch()
            _drags[name] = {
                stop        = stopFn,
                started     = now,
                lastMove    = now,
                moves       = 0,
                windowStart = now,
                windowMoves = 0,
            }
            _log(name .. " started")
            if not _timer then _timer = hs.timer.doEvery(CHECK_EVERY, _tick) end
        end

        ms.shell.dragMoved = function(name)
            local d = _drags[name]
            if not d then return end
            d.moves = d.moves + 1
            d.windowMoves = d.windowMoves + 1
            d.lastMove = hs.timer.secondsSinceEpoch()
        end

        ms.shell.endDrag = function(name, reason)
            _finish(name, reason or "mouse up")
        end

        ms.shell.releaseDrags = function(reason)
            local names = {}
            for name in pairs(_drags) do names[#names + 1] = name end
            for _, name in ipairs(names) do _finish(name, reason or "released") end
            ms._shellDragging = false
            return #names
        end
    -- END Drag Guard --
end

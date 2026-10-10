-- core/native_spy (Native Cursor Spy) --
    return function(ms)
        local _isWin = package.config:sub(1, 1) == "\\"

        if _G.__ms_spyStop then pcall(_G.__ms_spyStop) end

        local BIN = os.getenv("HOME") .. "/.local/bin/ms_spy" .. (_isWin and ".exe" or "")
        local MAX_RESTARTS = 3
        local INTERVAL_MS = 50

        local task = nil
        local handler = nil
        local ready = false
        local failed = false
        local stopping = true
        local restarts = 0
        local buf = ""
        local binChecked = false
        local binPresent = false

        ms.spy = {}

        local function hasBinary()
            if not binChecked then
                binChecked = true
                binPresent = hs.fs.attributes(BIN) ~= nil
            end

            return binPresent
        end

        local function send(tbl)
            if not task then return end
            task:setInput(hs.json.encode(tbl) .. "\n")
        end

        local function onEvent(ev)
            local t = ev.t

            if t == "spy" then
                if handler then
                    local ok, err = pcall(handler, ev)
                    if not ok then print("ms_spy handler error: " .. tostring(err)) end
                end
            elseif t == "ready" then
                ready = true
                restarts = 0
                send({
                    c = "config",
                    interval_ms = INTERVAL_MS,
                })
            elseif t == "error" then
                failed = true
                ready = false
                print("ms_spy: " .. tostring(ev.msg) .. "; using the Lua inspector")
            elseif t == "warn" then
                print("ms_spy: " .. tostring(ev.msg))
            end
        end

        local launch

        local function onExit(owner)
            if owner ~= task then return end

            task = nil
            ready = false

            if stopping or failed then return end

            restarts = restarts + 1

            if restarts > MAX_RESTARTS then
                failed = true
                print("ms_spy: exited repeatedly; using the Lua inspector")
                return
            end

            hs.timer.doAfter(0.25 * restarts, function()
                if not stopping and not task then launch() end
            end)
        end

        launch = function()
            buf = ""
            local mine

            mine = hs.task.new(BIN, function() onExit(mine) end, function(_, stdOut)
                if not stdOut or stdOut == "" then return true end
                buf = buf .. stdOut

                while true do
                    local nl = buf:find("\n", 1, true)
                    if not nl then break end
                    local line = buf:sub(1, nl - 1)
                    buf = buf:sub(nl + 1)
                    local ok, ev = pcall(hs.json.decode, line)

                    if ok and type(ev) == "table" then onEvent(ev) end
                end

                return true
            end)

            task = mine

            if not task or not task:start() then
                task = nil
                failed = true
                print("ms_spy: failed to launch " .. BIN)
            end
        end

        ms.spy.available = function()
            return not failed and hasBinary()
        end

        ms.spy.serving = function()
            return task ~= nil and ready and not failed
        end

        ms.spy.start = function(onSpy)
            handler = onSpy

            if failed or not hasBinary() then return false end

            stopping = false

            if not task then launch() end

            return task ~= nil
        end

        ms.spy.stop = function()
            stopping = true
            handler = nil
            ready = false

            if task then
                send({ c = "quit" })
                local t = task
                task = nil
                hs.timer.doAfter(0.2, function()
                    if t:isRunning() then t:terminate() end
                end)
            end
        end

        _G.__ms_spyStop = ms.spy.stop

        if hs.shutdownCallback ~= _G.__ms_spyShutdownWrapper then
            local priorShutdown = hs.shutdownCallback

            _G.__ms_spyShutdownWrapper = function()
                if _G.__ms_spyStop then pcall(_G.__ms_spyStop) end

                if priorShutdown then priorShutdown() end
            end

            hs.shutdownCallback = _G.__ms_spyShutdownWrapper
        end
    end
-- END core/native_spy --

local obj = {}
obj.__index = obj

obj.name    = "VirtualPad"
obj.version = "0.1.0"
obj.author  = "mudbourn"
obj.license = "MIT"

-- Constants --
    local IS_WIN = package.config:sub(1, 1) == "\\"

    local BIN_DIR = os.getenv("HOME") .. "/.local/bin"

    local BIN = BIN_DIR .. "/ms_vpad" .. (IS_WIN and ".exe" or "")

    local BUTTONS = {
        a = true,
        b = true,
        x = true,
        y = true,
        l1 = true,
        r1 = true,
        l2 = true,
        r2 = true,
        l3 = true,
        r3 = true,
        up = true,
        down = true,
        left = true,
        right = true,
        menu = true,
        options = true,
        home = true,
    }
-- END Constants --

-- Bundle Paths --
    local function bundleDir()
        local src = debug.getinfo(1, "S").source
        local dir = src and src:match("^@(.*)[/\\][^/\\]+$")
        if dir then return dir end
        return os.getenv("HOME") .. "/.hammerspoon/Spoons/VirtualPad.spoon"
    end

    local function amfiOff()
        local out = hs.execute("/usr/sbin/nvram boot-args 2>/dev/null") or ""
        return out:find("amfi_get_out_of_my_way=0x1", 1, true) ~= nil
            or out:find("amfi_get_out_of_my_way=1", 1, true) ~= nil
    end

    local function mtime(path)
        local a = hs.fs.attributes(path)
        return a and a.modification or nil
    end

    local function copyFile(from, to)
        local src = io.open(from, "rb")
        if not src then return false end
        local data = src:read("*a")
        src:close()
        local dst = io.open(to, "wb")
        if not dst then return false end
        dst:write(data)
        dst:close()
        return true
    end

    local function quitTask(task)
        if not task:isRunning() then return end
        if IS_WIN then
            task:closeInput()
        else
            task:terminate()
        end
    end
-- END Bundle Paths --

function obj:init()
    local state = {
        task      = nil,
        build     = nil,
        ready     = false,
        pad       = nil,
        lastError = nil,
        held      = {},
        axes      = {},
        stopped   = false,
    }

    -- Helpers --
        local function armed() return ms.settings.get("vpadArmed") ~= false end

        local function normButton(name)
            local n = tostring(name or ""):lower():gsub("^pad", "")
            if n == "lb" then n = "l1" elseif n == "rb" then n = "r1" end
            if n == "lt" then n = "l2" elseif n == "rt" then n = "r2" end
            if n == "ls" then n = "l3" elseif n == "rs" then n = "r3" end
            if n == "start" then n = "menu" elseif n == "select" or n == "back" then n = "options" end
            return BUTTONS[n] and n or nil
        end

        local function send(line)
            if state.task and state.task:isRunning() then
                state.task:setInput(line .. "\n")
            end
        end

        local function setExternal(on)
            if ms.gamepadSetExternal then ms.gamepadSetExternal(on) end
        end

        local function owner()
            local co = coroutine.running()
            return co or "main"
        end
    -- END Helpers --

    -- Helper Process --
        local start

        local function onOutput(_, out)
            for line in tostring(out or ""):gmatch("[^\n]+") do
                local ok, msg = pcall(hs.json.decode, line)
                if ok and type(msg) == "table" then
                    if msg.e == "pad" then
                        if ms.gamepadFeed then ms.gamepadFeed(msg.ev) end
                    elseif msg.e == "ready" then
                        setExternal(true)
                        state.ready = true
                        state.pad = msg.name
                        state.lastError = nil
                        ms.bus.emit("vpad:ready", msg)
                    elseif msg.e == "lost" then
                        state.ready = false
                        state.pad = nil
                        state.held = {}
                        state.axes = {}
                        setExternal(false)
                        ms.bus.emit("vpad:lost", msg)
                    elseif msg.e == "error" then
                        state.lastError = msg.m
                    end
                end
            end
            return true
        end

        local function launch()
            if state.stopped or (state.task and state.task:isRunning()) then return end
            state.task = hs.task.new(BIN, function(code)
                state.ready = false
                state.pad = nil
                state.task = nil
                setExternal(false)
                if code ~= 0 and IS_WIN then
                    hs.task.new(BIN, nil, {
                        "--unhide",
                    }):start()
                end
                if code ~= 0 and not state.stopped then
                    state.lastError = "helper exited with code " .. tostring(code)
                end
            end, onOutput)
            state.task:start()
        end

        local function compile(onDone)
            local src = bundleDir() .. "/bin/ms_vpad.swift"
            local ent = bundleDir() .. "/bin/ms_vpad.entitlements"
            local binTime = mtime(BIN)
            local srcTime = mtime(src)
            if binTime and (not srcTime or binTime >= srcTime) then return onDone(true) end
            hs.fs.mkdir(os.getenv("HOME") .. "/.local/bin")
            local cmd = string.format(
                "swiftc -O -o %q %q && codesign -f -s - --entitlements %q %q",
                BIN, src, ent, BIN
            )
            state.build = hs.task.new("/bin/zsh", function(code, _, err)
                state.build = nil
                if code ~= 0 then state.lastError = "build failed: " .. tostring(err) end
                onDone(code == 0)
            end, {
                "-lc",
                cmd,
            })
            state.build:start()
        end

        local function install(onDone)
            hs.fs.mkdir(BIN_DIR)
            for _, name in ipairs({
                "ms_vpad.exe",
                "SDL2.dll",
            }) do
                local src = bundleDir() .. "/bin/" .. name
                local dst = BIN_DIR .. "/" .. name
                local srcTime = mtime(src)
                local dstTime = mtime(dst)
                if srcTime and (not dstTime or dstTime < srcTime) and not copyFile(src, dst) then
                    state.lastError = "could not install " .. name .. " to " .. BIN_DIR
                    return onDone(false)
                end
            end
            onDone(mtime(BIN) ~= nil)
        end

        start = function()
            if state.stopped then return end
            if IS_WIN then
                install(function(ok) if ok then launch() end end)
                return
            end
            if not amfiOff() then
                state.lastError = "AMFI is on (needs SIP off and amfi_get_out_of_my_way=0x1)"
                return
            end
            compile(function(ok) if ok then launch() end end)
        end
    -- END Helper Process --

    -- Armed Toggle --
        ms.settings.define({
            type    = "toggle",
            key     = "vpadArmed",
            label   = "Virtual Pad Armed",
            hint    = "When off, ms.vpad.* calls are ignored and the controller is released back to the system",
            default = true,
            save    = true,
            section = "vpad",
            onChange = function(v)
                if v == false then
                    if state.task then quitTask(state.task) end
                else
                    start()
                end
            end,
        })
    -- END Armed Toggle --

    -- Simulation API (ms.vpad) --
        ms.vpad = {}

        ms.vpad.available = function()
            return armed() and state.ready
        end

        ms.vpad.controller = function()
            return state.pad
        end

        ms.vpad.press = function(name)
            local b = normButton(name)
            if not b or not ms.vpad.available() then return false end
            state.held[b] = owner()
            send("btn " .. b .. " 1")
            return true
        end

        ms.vpad.release = function(name)
            local b = normButton(name)
            if not b or not state.held[b] then return false end
            state.held[b] = nil
            send("btn " .. b .. " 0")
            return true
        end

        ms.vpad.tap = function(name, holdMs)
            if not ms.vpad.press(name) then return false end
            ms.wait(holdMs or 50)
            ms.vpad.release(name)
            return true
        end

        ms.vpad.stick = function(side, x, y)
            if not ms.vpad.available() then return false end
            local p = (side == "right" or side == "r") and "r" or "l"
            if x == nil then
                state.axes[p .. "x"] = nil
                state.axes[p .. "y"] = nil
                send("axis " .. p .. "x off")
                send("axis " .. p .. "y off")
                return true
            end
            state.axes[p .. "x"] = owner()
            state.axes[p .. "y"] = owner()
            send(string.format("axis %sx %.4f", p, x))
            send(string.format("axis %sy %.4f", p, -(y or 0)))
            return true
        end

        ms.vpad.trigger = function(name, value)
            local t = normButton(name)
            if t ~= "l2" and t ~= "r2" then return false end
            if not ms.vpad.available() then return false end
            if value == nil then
                state.axes[t] = nil
                send("axis " .. t .. " off")
                return true
            end
            state.axes[t] = owner()
            send(string.format("axis %s %.4f", t, value))
            return true
        end

        ms.vpad.releaseAll = function()
            state.held = {}
            state.axes = {}
            send("reset")
        end

        ms.vpad.status = function()
            return {
                armed = armed(),
                ready = state.ready,
                controller = state.pad,
                error = state.lastError,
            }
        end
    -- END Simulation API --

    -- Cancel Hook --
        local origCancel = ms.cancelMacros
        self._origCancel = origCancel
        ms.cancelMacros = function(...)
            local r = { origCancel(...) }
            local live = ms._coroContext or {}
            for b, co in pairs(state.held) do
                if co ~= "main" and not live[co] then
                    state.held[b] = nil
                    send("btn " .. b .. " 0")
                end
            end
            for a, co in pairs(state.axes) do
                if co ~= "main" and not live[co] then
                    state.axes[a] = nil
                    send("axis " .. a .. " off")
                end
            end
            return unpack(r)
        end
    -- END Cancel Hook --

    -- Status Action --
        ms.settings.define({
            type    = "action",
            key     = "vpadStatus",
            label   = "Virtual Pad Status",
            section = "vpad",
            onAction = function()
                local s = ms.vpad.status()
                local line = s.ready and ("Cloning: " .. tostring(s.controller))
                    or ("Not ready: " .. tostring(s.error or "no controller connected"))
                ms.alert(line, 4)
            end,
        })
    -- END Status Action --

    self._state = state
    if armed() then start() end
    return self
end

function obj:stop()
    local state = self._state
    if state then
        state.stopped = true
        if state.build then state.build:terminate() end
        if state.task then quitTask(state.task) end
    end
    if ms.gamepadSetExternal then ms.gamepadSetExternal(false) end
    if self._origCancel then ms.cancelMacros = self._origCancel end
    ms.vpad = nil
    return self
end

return obj

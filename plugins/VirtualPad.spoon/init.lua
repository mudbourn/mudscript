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

    local CACHE = os.getenv("HOME") .. "/.hammerspoon/data/ms_vpad_pad.json"

    local SOCK = os.getenv("HOME") .. "/.hammerspoon/data/ms_vpad.sock"

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

    local function sipOff()
        local out = hs.execute("/usr/bin/csrutil status 2>/dev/null") or ""
        return out:find("disabled", 1, true) ~= nil
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
        sock      = nil,
        poll      = nil,
        replacing = false,
        build     = nil,
        ready     = false,
        pad       = nil,
        lastError = nil,
        held      = {},
        axes      = {},
        stopped   = false,
        virtual   = false,
        blocked   = nil,
        warned    = false,
        noHidHide = false,
        hidHideNoticed = false,
        outBuf    = "",
    }

    -- Helpers --
        local function armed() return ms.settings.get("vpadArmed") ~= false end

        local function normButton(name)
            local n = ms.padName(name)
            return BUTTONS[n] and n or nil
        end

        local function send(line)
            if state.sock then
                state.sock:write(line .. "\n")
            elseif state.task and state.task:isRunning() then
                state.task:setInput(line .. "\n")
            end
        end

        local function setExternal(on)
            if ms.gamepadSetExternal then ms.gamepadSetExternal(on) end
        end

        local function warnBlocked()
            if not state.blocked or state.warned then return end
            state.warned = true
            ms.alert("Virtual Pad: " .. state.blocked, 6)
        end

        local function usable()
            if ms.vpad.available() then return true end
            warnBlocked()
            return false
        end

        local function owner()
            local co = coroutine.running()
            return co or "main"
        end
    -- END Helpers --

    -- Helper Process --
        local start
        local replace

        local function onOutput(_, out)
            local buf = state.outBuf .. tostring(out or "")
            local cut = buf:match(".*()\n")
            if not cut then
                state.outBuf = buf
                return true
            end
            state.outBuf = buf:sub(cut + 1)
            for line in buf:sub(1, cut - 1):gmatch("[^\n]+") do
                local ok, msg = pcall(hs.json.decode, line)
                if ok and type(msg) == "table" then
                    if msg.e == "pad" then
                        if ms.gamepadFeed then ms.gamepadFeed(msg.ev) end
                    elseif msg.e == "virtual" then
                        setExternal(true)
                        state.virtual = true
                    elseif msg.e == "ready" then
                        setExternal(true)
                        state.ready = true
                        state.virtual = true
                        state.pad = msg.name
                        state.lastError = nil
                        ms.bus.emit("vpad:ready", msg)
                    elseif msg.e == "lost" then
                        state.ready = false
                        state.pad = nil
                        state.held = {}
                        state.axes = {}
                        ms.bus.emit("vpad:lost", msg)
                    elseif msg.e == "hello" then
                        local built = mtime(BIN)
                        local running = tonumber(msg.build)
                        if built and running and built > running + 1 and not state.replacing then
                            state.replacing = true
                            replace()
                        end
                    elseif msg.e == "nohidhide" then
                        state.noHidHide = true
                        if not state.hidHideNoticed then
                            state.hidHideNoticed = true
                            ms.alert("Virtual Pad works, but games also see the real pad. Install HidHide from Settings > Virtual Pad to hide it", 6)
                        end
                    elseif msg.e == "error" then
                        state.lastError = msg.m
                    end
                end
            end
            return true
        end

        local function dropSocket()
            if state.poll then
                state.poll:stop()
                state.poll = nil
            end
            if state.sock then
                local sock = state.sock
                state.sock = nil
                pcall(function() sock:disconnect() end)
            end
            state.outBuf = ""
        end

        local function onHelperGone()
            dropSocket()
            state.ready = false
            state.virtual = false
            state.pad = nil
            setExternal(false)
        end

        local function attach(onDone)
            local done = false
            local function finish(ok)
                if done then return end
                done = true
                onDone(ok)
            end
            local sock = hs.socket.new()
            sock:setCallback(function(data)
                onOutput(nil, data)
                if state.sock == sock then sock:read("\n") end
            end)
            sock:connect(SOCK, function()
                if done or state.stopped then
                    pcall(function() sock:disconnect() end)
                    return
                end
                state.sock = sock
                state.outBuf = ""
                sock:read("\n")
                state.poll = hs.timer.doEvery(2, function()
                    if state.sock == sock and not sock:connected() then
                        onHelperGone()
                        if not state.stopped and armed() then start() end
                    end
                end)
                finish(true)
            end)
            hs.timer.doAfter(0.5, function()
                if state.sock ~= sock then
                    pcall(function() sock:disconnect() end)
                    finish(false)
                end
            end)
        end

        local function spawn()
            hs.task.new("/bin/sh", nil, {
                "-c",
                string.format("nohup %q --cache %q --socket %q >/dev/null 2>&1 &", BIN, CACHE, SOCK),
            }):start()
        end

        local function connectHelper(tries)
            if state.stopped or state.sock then return end
            attach(function(ok)
                if ok or state.stopped then return end
                if tries == 0 then spawn() end
                if tries < 10 then
                    hs.timer.doAfter(0.3, function() connectHelper(tries + 1) end)
                else
                    state.lastError = "helper did not start"
                end
            end)
        end

        local function quitHelper()
            if state.sock then
                send("quit")
                onHelperGone()
            elseif state.task then
                quitTask(state.task)
            end
        end

        replace = function()
            quitHelper()
            hs.timer.doAfter(0.5, function()
                state.replacing = false
                connectHelper(0)
            end)
        end

        local function launch()
            if state.stopped then return end
            if not IS_WIN then return connectHelper(0) end
            if state.task and state.task:isRunning() then return end
            state.outBuf = ""
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
            end, onOutput, {})
            state.task:start()
        end

        local function compile(onDone)
            local src = bundleDir() .. "/bin/ms_vpad.swift"
            local ent = bundleDir() .. "/bin/ms_vpad.entitlements"
            local binTime = mtime(BIN)
            local srcTime = mtime(src)
            if binTime and (not srcTime or binTime >= srcTime) then return onDone(true) end
            hs.fs.mkdir(os.getenv("HOME") .. "/.local/bin")
            local tmp = string.format("%s.build.%d.%d", BIN, os.time(), math.random(1, 1000000))
            local cmd = string.format(
                "swiftc -O -o %q %q && codesign -f -s - --entitlements %q %q && mv -f %q %q",
                tmp, src, ent, tmp, tmp, BIN
            )
            state.build = hs.task.new("/bin/zsh", function(code, _, err)
                state.build = nil
                if code ~= 0 then
                    os.remove(tmp)
                    state.lastError = "build failed: " .. tostring(err)
                end
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
            if not sipOff() then
                state.blocked = "SIP is on. Boot into Recovery and run csrutil disable to use the virtual pad"
            elseif not amfiOff() then
                state.blocked = "AMFI is on. Set boot-args amfi_get_out_of_my_way=0x1 to use the virtual pad"
            end
            if state.blocked then
                state.lastError = state.blocked
                warnBlocked()
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
                    quitHelper()
                else
                    start()
                end
            end,
        })
    -- END Armed Toggle --

    -- Simulation API (ms.vpad) --
        ms.vpad = {}

        ms.vpad.available = function()
            return armed() and (state.ready or state.virtual)
        end

        ms.vpad.controller = function()
            return state.pad
        end

        ms.vpad.press = function(name)
            local b = normButton(name)
            if not b or not usable() then return false end
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
            if not usable() then return false end
            local p = tostring(side or ""):lower():match("^r") and "r" or "l"
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
            if not usable() then return false end
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

    -- Builder Blocks --
        if ms.builder and ms.builder.define then
            local BUTTON_OPTS = {
                "a",
                "b",
                "x",
                "y",
                "l1",
                "r1",
                "l2",
                "r2",
                "l3",
                "r3",
                "up",
                "down",
                "left",
                "right",
                "menu",
                "options",
                "home",
            }

            local function buttonParam()
                return {
                    name     = "button",
                    type     = "enum",
                    options  = BUTTON_OPTS,
                    pad      = true,
                    label    = "Button",
                    required = true,
                }
            end

            ms.builder.define({
                id       = "ms.vpad.tap",
                name     = "Tap Button",
                desc     = "Press and release a virtual controller button.",
                category = "vpad",
                params   = {
                    buttonParam(),
                    {
                        name     = "holdMs",
                        type     = "number",
                        unit     = "ms",
                        default  = 50,
                        label    = "Hold (ms)",
                        required = false,
                    },
                },
            })

            ms.builder.define({
                id       = "ms.vpad.press",
                name     = "Hold Button",
                desc     = "Hold a virtual controller button down until released.",
                category = "vpad",
                params   = { buttonParam() },
            })

            ms.builder.define({
                id       = "ms.vpad.release",
                name     = "Release Button",
                desc     = "Release a held virtual controller button.",
                category = "vpad",
                params   = { buttonParam() },
            })

            ms.builder.define({
                id       = "ms.vpad.stick",
                name     = "Move Stick",
                desc     = "Hold a stick at a position from -1 to 1. Release All hands it back to the real controller.",
                category = "vpad",
                params   = {
                    {
                        name     = "side",
                        type     = "enum",
                        options  = {
                            "left",
                            "right",
                        },
                        label    = "Stick",
                        required = true,
                    },
                    {
                        name     = "x",
                        type     = "number",
                        label    = "X (-1 to 1)",
                        required = false,
                    },
                    {
                        name     = "y",
                        type     = "number",
                        label    = "Y (-1 to 1)",
                        required = false,
                    },
                },
            })

            ms.builder.define({
                id       = "ms.vpad.trigger",
                name     = "Set Trigger",
                desc     = "Hold a trigger at a value from 0 to 1. Release All hands it back to the real controller.",
                category = "vpad",
                params   = {
                    {
                        name     = "name",
                        type     = "enum",
                        options  = {
                            "l2",
                            "r2",
                        },
                        pad      = true,
                        label    = "Trigger",
                        required = true,
                    },
                    {
                        name     = "value",
                        type     = "number",
                        label    = "Value (0 to 1)",
                        required = false,
                    },
                },
            })

            ms.builder.define({
                id       = "ms.vpad.releaseAll",
                name     = "Release All",
                desc     = "Release every held button, stick and trigger.",
                category = "vpad",
                params   = {},
            })
        end
    -- END Builder Blocks --

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
            return (table.unpack or unpack)(r)
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

    -- HidHide Install Action --
        if IS_WIN then
            ms.settings.define({
                type    = "action",
                key     = "vpadInstallHidHide",
                label   = "Install HidHide",
                hint    = "Hides the real controller from games so they only see the virtual pad. Needs admin approval and a reboot",
                section = "vpad",
                onAction = function()
                    hs.task.new(os.getenv("ComSpec") or "C:\\Windows\\System32\\cmd.exe", nil, {
                        "/c",
                        "start",
                        "HidHide",
                        "winget",
                        "install",
                        "--id",
                        "Nefarius.HidHide",
                        "-e",
                        "--accept-package-agreements",
                        "--accept-source-agreements",
                    }):start()
                    ms.alert("Installing HidHide. Approve the admin prompt, then reboot when it finishes", 6)
                end,
            })
        end
    -- END HidHide Install Action --

    self._state = state
    self._quitHelper = quitHelper
    self._dropSocket = dropSocket
    if armed() then
        start()
    elseif not IS_WIN then
        attach(function(ok) if ok then quitHelper() end end)
    end
    return self
end

function obj:stop(opts)
    local state = self._state
    if state then
        if state.build then state.build:terminate() end
        if opts and opts.reload and not IS_WIN then
            self._dropSocket()
        else
            self._quitHelper()
        end
        state.stopped = true
    end
    if ms.gamepadSetExternal then ms.gamepadSetExternal(false) end
    if self._origCancel then ms.cancelMacros = self._origCancel end
    ms.vpad = nil
    return self
end

return obj

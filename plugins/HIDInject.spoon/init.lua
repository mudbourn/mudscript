--- === HIDInject ===
--- Opt-in HID injection: ms.hid.* posts input directly to the target app.

local obj = {}
obj.__index = obj

obj.name    = "HIDInject"
obj.version = "0.1.0"
obj.author  = "mudbourn"
obj.license = "MIT"

-- Keycode Resolver --
    local function keyCode(key)
        if type(key) == "number" then return key end
        return hs.keycodes.map[key]
    end
-- END Keycode Resolver --

function obj:init()
    local held = { keys = {}, buttons = {} }

    -- Helpers --
        local function targetApp()
            return ms._targetApp and hs.application.get(ms._targetApp) or nil
        end

        local function armed() return ms.settings.get("hidArmed") ~= false end
    -- END Helpers --

    -- Armed Toggle --
        ms.settings.define({
            type    = "toggle",
            key     = "hidArmed",
            label   = "HID Injection Armed",
            hint    = "When off, ms.hid.* calls are ignored (installed but inert)",
            default = true,
            save    = true,
            section = "hid",
        })
    -- END Armed Toggle --

    -- Injection API (ms.hid) --
        ms.hid = {}

        ms.hid.available = function()
            return armed() and targetApp() ~= nil
        end

        ms.hid.press = function(key, mods)
            if not armed() then return end
            local app = targetApp()
            if not app then return end
            local code = keyCode(key)
            if not code then return end
            local ev = hs.eventtap.event.newKeyEvent(mods or {}, code, true)
            ev:post(app)
            held.keys[code] = mods or {}
        end

        ms.hid.release = function(key, mods)
            if not armed() then return end
            local app = targetApp()
            if not app then return end
            local code = keyCode(key)
            if not code then return end
            local ev = hs.eventtap.event.newKeyEvent(mods or (held.keys[code]) or {}, code, false)
            ev:post(app)
            held.keys[code] = nil
        end

        ms.hid.type = function(key, mods, holdMs)
            ms.hid.press(key, mods)
            ms.wait(holdMs or 15)
            ms.hid.release(key, mods)
        end

        ms.hid.click = function(button)
            if not armed() then return end
            local app = targetApp()
            if not app then return end
            button = button or 0
            local pos = hs.mouse.absolutePosition()
            local downT, upT
            if button == 0 then
                downT, upT = hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.leftMouseUp
            elseif button == 1 then
                downT, upT = hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.rightMouseUp
            else
                downT, upT = hs.eventtap.event.types.otherMouseDown, hs.eventtap.event.types.otherMouseUp
            end
            local function send(t)
                local ev = hs.eventtap.event.newMouseEvent(t, pos)
                if button >= 2 then
                    ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, button)
                end
                ev:post(app)
            end
            send(downT)
            ms.wait(30)
            send(upT)
        end

        ms.hid.releaseAll = function()
            local app = targetApp()
            if app then
                for code, mods in pairs(held.keys) do
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, code, false)
                    ev:post(app)
                end
            end
            held.keys = {}
            held.buttons = {}
        end
    -- END Injection API --

    -- Status Action --
        ms.settings.define({
            type    = "action",
            key     = "hidStatus",
            label   = "HID Injection Status",
            section = "hid",
            onAction = function()
                local app = targetApp()
                ms.alert(string.format("Armed: %s   Target: %s",
                    tostring(armed()),
                    app and app:name() or (ms._targetApp or "none")), 4)
            end,
        })
    -- END Status Action --

    self._held = held
    return self
end

function obj:stop()
    if ms.hid and ms.hid.releaseAll then pcall(ms.hid.releaseAll) end
    ms.hid = nil
    return self
end

return obj

-- MsSettings --
return function(ms)
-- MsSettings --
    local MsSettings = {}

    MsSettings.name    = "MsSettings"
    MsSettings.version = "1.0"
-- END MsSettings --

-- Init --
    function MsSettings:init()
    end
-- END Init --

-- Start --
    function MsSettings:start()
        if not _G.ms then return end
        local ms = _G.ms
        if ms.checkGuardian and not ms.checkGuardian("MsSettings") then return end

        self:_initSettingsMenu(ms)
    end
-- END Start --

-- Settings Menu --
    -- Panel State & Builders --
        function MsSettings:_initSettingsMenu(ms)
        local settingsPath    = os.getenv("HOME") .. "/.hammerspoon/ms_settings.txt"
        local trustedHashPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_trusted_hash"

        ms.bindConfig = {}
        ms.bindHandles = {}
        ms.bindIgnoreMods = ms.bindIgnoreMods or {}

        ms.parseBind = function(str)
            local btn = str:match("^mouse:(%d+)$")
            if btn then return {
                type="mouse",
                button=tonumber(btn),
            } end
            local dir = str:match("^scroll:(%w+)$")
            if dir and (dir == "up" or dir == "down") then return {
                type="scroll",
                direction=dir,
            } end
            local gp = str:match("^gamepad:([%w+]+)$")
            if gp then
                local list = {}
                for b in gp:gmatch("[^+]+") do list[#list + 1] = b end
                if #list == 1 then
                    return {
                        type = "gamepad",
                        button = list[1],
                    }
                elseif #list > 1 then
                    return {
                        type = "gamepad",
                        buttons = list,
                    }
                end
            end
            local mods = {}
            local parts = {}
            for part in str:gmatch("[^+]+") do
                table.insert(parts, part:lower())
            end
            local modkeys = {
                cmd   = true,
                alt   = true,
                ctrl  = true,
                shift = true,
            }
            local key = nil
            for _, part in ipairs(parts) do
                if modkeys[part] then
                    table.insert(mods, part)
                else
                    key = part
                end
            end
            if key then return {
                type = "key",
                mods = mods,
                key  = key,
            }end
            return nil
        end
    -- END Panel State & Builders --

    -- Submodules --
        local ctx = {
            settingsPath = settingsPath,
            backupDir = function(sub) return ms.backups.dir(sub) end,
            trustedHashPath = trustedHashPath,
        }
        for _, name in ipairs({
            "validation",
            "authored",
            "lifecycle",
            "api",
            "profiles",
            "profile_io",
            "integrity",
        }) do
            package.loaded["lib.settings." .. name] = nil
            require("lib.settings." .. name)(ms, ctx)
        end
    -- END Submodules --

    -- SOCD Engine --
        ms._socdListener = nil
        ms._socdHeld = {
            a = false,
            d = false,
            w = false,
            s = false,
        }

        local socdKeyCodes = {
            a = hs.keycodes.map["a"],
            d = hs.keycodes.map["d"],
            w = hs.keycodes.map["w"],
            s = hs.keycodes.map["s"],
        }

        local socdCodeToKey = {}
        for name, code in pairs(socdKeyCodes) do
            socdCodeToKey[code] = name
        end

        local socdOpposite = {
            a = "d",
            d = "a",
            w = "s",
            s = "w",
        }

        local function socdPost(code, down)
            local ev = hs.eventtap.event.newKeyEvent({}, code, down)

            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, ms.SOCD_TAG)
            ev:post()
            ms.keytrack[code] = down
        end

        local function socdReset()
            ms._socdHeld = {
                a = false,
                d = false,
                w = false,
                s = false,
            }
            ms._socdSwallowed = {}
            ms._socdCut = {}
        end

        ms.socdStart = function()
            if ms._socdListener then return end
            if ms.layer and ms.layer.active then return end

            socdReset()

            local lastValidity = BindValidity

            ms._socdListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
            }, function(event)
                local props = hs.eventtap.event.properties
                if ms.isSynthetic(event) then return false end

                local keyCode = event:getKeyCode()
                local key = socdCodeToKey[keyCode]
                if not key then return false end

                if BindValidity ~= lastValidity then
                    lastValidity = BindValidity
                    socdReset()
                end

                local isDown = event:getType() == hs.eventtap.event.types.keyDown
                local isRepeat = isDown and event:getProperty(props.keyboardEventAutorepeat) ~= 0
                local mode = ms.socdMode or "lastWins"
                local opp = socdOpposite[key]
                local oppCode = socdKeyCodes[opp]
                local active = BindValidity == 1

                if isDown then
                    if isRepeat then
                        if not active then return false end
                        if mode == "neutral" and ms._socdHeld[opp] then return true end
                        return ms._socdSwallowed[key] == true
                    end

                    ms._socdHeld[key] = true

                    if not active or not ms._socdHeld[opp] then return false end

                    if mode == "lastWins" then
                        ms._socdCut[opp] = true
                        socdPost(oppCode, false)
                    elseif mode == "firstWins" then
                        ms._socdHeld[key] = false
                        ms._socdSwallowed[key] = true
                        return true
                    elseif mode == "neutral" then
                        ms._socdCut[opp] = true
                        ms._socdCut[key] = true
                        socdPost(oppCode, false)
                        socdPost(keyCode, false)
                        return true
                    end

                    return false
                end

                ms._socdHeld[key] = false

                if ms._socdSwallowed[key] then
                    ms._socdSwallowed[key] = false
                    return true
                end

                local oppCut = ms._socdCut[opp]
                ms._socdCut[opp] = nil

                if active and oppCut and ms._socdHeld[opp] and (mode == "lastWins" or mode == "neutral") then
                    socdPost(oppCode, true)
                end

                return false
            end):start()
        end

        ms.socdStop = function()
            if ms._socdListener then
                ms._socdListener:stop()
                ms._socdListener = nil
            end
            socdReset()
        end

        ms.socdApply = function()
            if ms.socdEnabled then
                ms.socdStart()
            else
                ms.socdStop()
            end
        end
    -- END SOCD Engine --

    -- Menu --
        for _, name in ipairs({
            "menu",
        }) do
            package.loaded["lib.settings." .. name] = nil
            require("lib.settings." .. name)(ms, ctx)
        end
    -- END Menu --
-- END Settings Menu --

end

return MsSettings

end

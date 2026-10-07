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

        local function socdAxis(neg, pos, axisKey)
            local negHeld = ms._socdHeld[neg]
            local posHeld = ms._socdHeld[pos]
            local mode = ms.socdMode or "lastWins"

            if not negHeld and not posHeld then return end
            if negHeld and not posHeld then return end
            if posHeld and not negHeld then return end

            if mode == "neutral" then
                local negCode = socdKeyCodes[neg]
                local posCode = socdKeyCodes[pos]
                local evNeg = hs.eventtap.event.newKeyEvent({}, negCode, false)
                local evPos = hs.eventtap.event.newKeyEvent({}, posCode, false)
                evNeg:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                evPos:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                evNeg:post()
                evPos:post()
            elseif mode == "lastWins" then
            elseif mode == "firstWins" then
            end
        end

        ms.socdStart = function()
            if ms._socdListener then return end
            ms._socdHeld  = {
                a = false,
                d = false,
                w = false,
                s = false,
            }

            ms._socdListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
            }, function(event)
                if BindValidity ~= 1 then return false end
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end

                local keyCode = event:getKeyCode()
                local key = socdCodeToKey[keyCode]
                if not key then return false end

                local isDown = event:getType() == hs.eventtap.event.types.keyDown
                local mode = ms.socdMode or "lastWins"

                if isDown then
                    ms._socdHeld[key] = true

                    if key == "a" or key == "d" then
                        local opp = (key == "a") and "d" or "a"
                        if ms._socdHeld[opp] then
                            if mode == "lastWins" then
                                local oppCode = socdKeyCodes[opp]
                                local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev:post()
                                ms.keytrack[oppCode] = false
                            elseif mode == "firstWins" then
                                ms._socdHeld[key] = false
                                return true
                            elseif mode == "neutral" then
                                local oppCode = socdKeyCodes[opp]
                                local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev1:post()
                                ev2:post()
                                ms.keytrack[oppCode] = false
                                ms.keytrack[keyCode] = false
                                return true
                            end
                        end

                    elseif key == "w" or key == "s" then
                        local opp = (key == "w") and "s" or "w"
                        if ms._socdHeld[opp] then
                            if mode == "lastWins" then
                                local oppCode = socdKeyCodes[opp]
                                local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev:post()
                                ms.keytrack[oppCode] = false
                            elseif mode == "firstWins" then
                                ms._socdHeld[key] = false
                                return true
                            elseif mode == "neutral" then
                                local oppCode = socdKeyCodes[opp]
                                local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                ev1:post()
                                ev2:post()
                                ms.keytrack[oppCode] = false
                                ms.keytrack[keyCode] = false
                                return true
                            end
                        end
                    end

                else
                    ms._socdHeld[key] = false

                    if mode == "lastWins" then
                        local opp
                        if key == "a" then opp = "d"
                        elseif key == "d" then opp = "a"
                        elseif key == "w" then opp = "s"
                        elseif key == "s" then opp = "w"
                        end
                        if opp and ms._socdHeld[opp] then
                            local oppCode = socdKeyCodes[opp]
                            local ev = hs.eventtap.event.newKeyEvent({}, oppCode, true)
                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            ev:post()
                            ms.keytrack[oppCode] = true
                        end
                    end
                end

                return false
            end):start()
        end

        ms.socdStop = function()
            if ms._socdListener then
                ms._socdListener:stop()
                ms._socdListener = nil
            end
            ms._socdHeld  = {
                a = false,
                d = false,
                w = false,
                s = false,
            }
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

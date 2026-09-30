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
        local jsonPath        = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings.json"
        local defaultPath     = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings_default.json"
        local authoredPath    = os.getenv("HOME") .. "/.hammerspoon/data/ms_authored.json"
        local authoredMenusPath = os.getenv("HOME") .. "/.hammerspoon/data/ms_authored_menus.json"
        local archivePath     = os.getenv("HOME") .. "/.hammerspoon/backups/"
        local macrosPath      = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
        local profilesPath    = os.getenv("HOME") .. "/.hammerspoon/profiles/"
        local corePath        = os.getenv("HOME") .. "/.hammerspoon/ms_core.lua"
        local trustedHashPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_trusted_hash"
        local themePath       = os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json"
        local visualJsonPath  = os.getenv("HOME") .. "/.hammerspoon/data/ms_macros_visual.json"
        local visualLuaPath   = os.getenv("HOME") .. "/.hammerspoon/data/ms_macros_visual.lua"
        local helperVarsPath  = os.getenv("HOME") .. "/.hammerspoon/data/ms_helpervars.json"

        -- Builder content that rides with a profile beyond ms_macros.lua
        local function profileContentFiles()
            return {
                { live = visualJsonPath, name = "ms_macros_visual.json" },
                { live = visualLuaPath,  name = "ms_macros_visual.lua" },
                { live = authoredPath,   name = "ms_authored.json" },
                { live = authoredMenusPath, name = "ms_authored_menus.json" },
                { live = helperVarsPath, name = "ms_helpervars.json" },
            }
        end

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
            -- Parse gamepad single button or a chord
            local gp = str:match("^gamepad:([%w+]+)$")
            if gp then
                local list = {}
                for b in gp:gmatch("[^+]+") do list[#list + 1] = b end
                if #list == 1 then
                    return { type = "gamepad", button = list[1] }
                elseif #list > 1 then
                    return { type = "gamepad", buttons = list }
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
            jsonPath = jsonPath,
            defaultPath = defaultPath,
            authoredPath = authoredPath,
            authoredMenusPath = authoredMenusPath,
            archivePath = archivePath,
            macrosPath = macrosPath,
            profilesPath = profilesPath,
            trustedHashPath = trustedHashPath,
            themePath = themePath,
            profileContentFiles = profileContentFiles,
        }
        for _, name in ipairs({
            "validation",
            "authored",
            "lifecycle",
            "api",
            "profiles",
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

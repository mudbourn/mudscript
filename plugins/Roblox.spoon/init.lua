--- === Roblox ===
--- Roblox target + live settings reader + anti-timeout + cache cleaner.
--- See README.md for behaviour and rationale.

local obj = {}
obj.__index = obj

obj.name    = "Roblox"
obj.version = "0.2.0"
obj.author  = "mudbourn"
obj.license = "MIT"

-- Platform --
    local IS_WINDOWS = package.config:sub(1, 1) == "\\"

    local function winPath(p) return (tostring(p):gsub("/", "\\")) end

    local function shellOpen(path)
        if IS_WINDOWS then
            os.execute('start "" "' .. winPath(path) .. '"')
        else
            os.execute("open '" .. path .. "'")
        end
    end

    local function revealDir(path)
        if IS_WINDOWS then
            os.execute('explorer "' .. winPath(path) .. '"')
        else
            os.execute("open '" .. path .. "'")
        end
    end
-- END Platform --

-- Paths --
    local CACHE_LABEL = "com.mudscript.cache-cleaner"

    local ROBLOX_DIR
    local SETTINGS_XML
    local TARGET_APP

    if IS_WINDOWS then
        local localApp = os.getenv("LOCALAPPDATA") or (os.getenv("HOME") .. "/AppData/Local")
        ROBLOX_DIR   = localApp .. "/Roblox"
        SETTINGS_XML = ROBLOX_DIR .. "/GlobalBasicSettings_13.xml"
        TARGET_APP   = "RobloxPlayerBeta"
    else
        ROBLOX_DIR   = os.getenv("HOME") .. "/Library/Roblox"
        SETTINGS_XML = ROBLOX_DIR .. "/GlobalBasicSettings_13.xml"
        TARGET_APP   = "Roblox"
    end

    local function robloxVersionDir()
        local base = ROBLOX_DIR .. "/Versions"
        local best, bestTime
        local ok, iter, dobj = pcall(hs.fs.dir, base)
        if not ok or not iter then return nil end

        for entry in iter, dobj do
            if entry:sub(1, 1) ~= "." then
                local exe  = base .. "/" .. entry .. "/RobloxPlayerBeta.exe"
                local attr = hs.fs.attributes(exe)
                if attr then
                    local mt = attr.modification or 0
                    if not bestTime or mt > bestTime then
                        best     = base .. "/" .. entry
                        bestTime = mt
                    end
                end
            end
        end

        if dobj then dobj:close() end

        return best
    end
-- END Paths --

local _sensWatcher = nil
local _sensTimer   = nil
local _cacheTimer  = nil

-- Settings Reader --
    local function readSetting(key)
        if type(key) ~= "string" then return nil end
        local f = io.open(SETTINGS_XML, "r")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        if not data then return nil end
        return data:match('name="' .. key .. '"[^>]*>([^<]*)<')
    end

    local function readNumber(key)
        return tonumber(readSetting(key))
    end

    local function readBool(key)
        local v = readSetting(key)
        if v == nil then return nil end
        return v == "true"
    end

    local function readVectorX(key)
        if type(key) ~= "string" then return nil end
        local f = io.open(SETTINGS_XML, "r")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        if not data then return nil end
        local block = data:match('name="' .. key .. '">(.-)</Vector2>')
        if not block then return nil end
        return tonumber(block:match('<X>%s*([%-%d%.eE]+)%s*</X>'))
    end

    local function effectiveSensitivity()
        return readNumber("MouseSensitivity")
            or readVectorX("MouseSensitivityThirdPerson")
            or readVectorX("MouseSensitivityFirstPerson")
    end
-- END Settings Reader --

-- Cache Cleaner --
    local function bundleDir()
        local src = debug.getinfo(1, "S").source
        local dir = src and src:match("^@(.*)/[^/]+$")
        if dir then return dir end
        return os.getenv("HOME") .. "/.hammerspoon/Spoons/Roblox.spoon"
    end

    local function litPattern(s) return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end
    local function litRepl(s) return (s:gsub("%%", "%%%%")) end

    local function runWinCleaner()
        local script = bundleDir() .. "/bin/clean_roblox_cache.cmd"
        if not hs.fs.attributes(script) then return end
        os.execute('start "" /min cmd /c "' .. winPath(script) .. '"')
    end

    local function syncCacheCleanerWin(enabled)
        if _cacheTimer then
            _cacheTimer:stop()
            _cacheTimer = nil
        end

        if enabled then
            runWinCleaner()
            _cacheTimer = hs.timer.doEvery(21600, runWinCleaner)
        end
    end

    local function syncCacheCleanerMac(enabled)
        local home      = os.getenv("HOME")
        local dir       = bundleDir()
        local scriptSrc = dir .. "/bin/clean_roblox_cache.sh"
        local plistSrc  = dir .. "/bin/" .. CACHE_LABEL .. ".plist"
        local plistDst  = home .. "/Library/LaunchAgents/" .. CACHE_LABEL .. ".plist"
        if enabled then
            if hs.fs.attributes(plistSrc) and hs.fs.attributes(scriptSrc) then
                local f = io.open(plistSrc, "r")
                if f then
                    local content = f:read("*all")
                    f:close()
                    content = content:gsub(litPattern("%%AGENT_PATH%%"), litRepl(scriptSrc))
                    local g = io.open(plistDst, "w")
                    if g then
                        g:write(content)
                        g:close()
                    end
                    os.execute("chmod 755 '" .. scriptSrc .. "'")
                    os.execute("launchctl unload '" .. plistDst
                        .. "' 2>/dev/null; launchctl load '" .. plistDst .. "'")
                end
            end
        else
            os.execute("launchctl unload '" .. plistDst .. "' 2>/dev/null")
            os.remove(plistDst)
        end
    end

    local function syncCacheCleaner(enabled)
        if IS_WINDOWS then
            syncCacheCleanerWin(enabled)
        else
            syncCacheCleanerMac(enabled)
        end
    end
-- END Cache Cleaner --

function obj:init()

    -- Target App --
        ms.setTargetApp(TARGET_APP)
    -- END Target App --

    -- Live Reader (ms.roblox) --
        ms.roblox = {
            setting         = readSetting,
            settingNumber   = readNumber,
            settingBool     = readBool,

            sensitivity     = function() return effectiveSensitivity() end,
            gamepadSens     = function() return readNumber("GamepadCameraSensitivity") end,
            framerateCap    = function() return readNumber("FramerateCap") end,
            graphicsQuality = function() return readNumber("GraphicsQualityLevel") end,
            savedQuality    = function() return readNumber("SavedQualityLevel") end,
            masterVolume    = function() return readNumber("MasterVolume") end,
            fullscreen      = function() return readBool("Fullscreen") end,
            cameraInverted  = function() return readBool("CameraYInverted") end,

            isFocused = function() return ms._targetActive == true end,
            activate  = function()
                if ms._targetHandle then
                    pcall(function() ms._targetHandle:activate() end)
                end
            end,
        }
    -- END Live Reader --

    -- Anti-Timeout --
        local function armAntiTimeout()
            local enabled = ms.settings.get("robloxAntiTimeout")
            local minutes = ms.settings.get("robloxAntiTimeoutMins") or 15
            ms.antiTimeout({
                enabled  = enabled == true,
                interval = math.max(1, minutes) * 60,
                action   = function() ms.press("f15") end,
            })
        end

        ms.settings.define({
            type    = "toggle",
            key     = "robloxAntiTimeout",
            label   = "Anti-Timeout",
            hint    = "Send a harmless keystroke on an interval to avoid Roblox's idle kick",
            default = false,
            save    = true,
            section = "roblox",
            onChange = function() armAntiTimeout() end,
        })

        ms.settings.define({
            type    = "slider",
            key     = "robloxAntiTimeoutMins",
            label   = "Anti-Timeout Interval (min)",
            min     = 1,
            max     = 19,
            step    = 1,
            default = 15,
            save    = true,
            section = "roblox",
            onChange = function() armAntiTimeout() end,
        })
    -- END Anti-Timeout --

    -- Camera Sensitivity --
        -- The manual camera-sensitivity slider. It used to live in the pack's
        -- ms_macros.lua; it belongs here because it only means anything for the
        -- Roblox camera, and the Sensitivity Tether below drives it. Defined
        -- before the tether so the tether's graft finds it. Persisted value is
        -- restored by ms.settings.define (pending user settings) as before.
        ms.settings.define({
            type    = "slider",
            key     = "cameraSensitivity",
            label   = "Camera Sensitivity",
            min     = 0.1,
            max     = 4,
            step    = 0.1,
            default = 1.5,
            save    = true,
            section = "roblox",
            onChange = function(val)
                ms._camSens = val
            end,
        })
    -- END Camera Sensitivity --

    -- Sensitivity Tether --
        local function syncSensitivity()
            if ms.settings.get("robloxSyncSensitivity") == false then return end
            local sens = effectiveSensitivity()
            if type(sens) ~= "number" or sens <= 0 then return end
            if ms._camSens ~= sens then
                ms._camSens = sens
                if ms.settings.get("cameraSensitivity") ~= nil then
                    pcall(ms.settings.set, "cameraSensitivity", sens)
                end
            end
        end

        ms.settings.define({
            type    = "toggle",
            key     = "robloxSyncSensitivity",
            label   = "Sync Sensitivity From Roblox",
            hint    = "Tie the macro camera sensitivity to Roblox's live in-game sensitivity so spins stay calibrated (turn off to set it manually)",
            default = true,
            save    = true,
            section = "roblox",
            onChange = function() pcall(syncSensitivity) end,
        })

        if _sensWatcher then _sensWatcher:stop() end
        _sensWatcher = hs.pathwatcher.new(SETTINGS_XML, function()
            pcall(syncSensitivity)
        end)
        if _sensWatcher then _sensWatcher:start() end

        if _sensTimer then _sensTimer:stop() end
        _sensTimer = hs.timer.doEvery(10, function() pcall(syncSensitivity) end)
        pcall(syncSensitivity)
    -- END Sensitivity Tether --

    -- Cache Cleaner Toggle --
        ms.settings.define({
            type    = "toggle",
            key     = "robloxCacheCleaner",
            label   = "Roblox Cache Cleaner",
            hint    = "Auto-purge micro-profiler dumps & stale caches every 6h (launchd agent)",
            default = false,
            save    = true,
            section = "roblox",
            onChange = function(on) pcall(syncCacheCleaner, on == true) end,
        })
    -- END Cache Cleaner Toggle --

    -- Builder Tools --
        if ms.tools and ms.tools.define then
            ms.tools.define({
                id   = "roblox.sensitivity",
                name = "Roblox: Mouse Sensitivity",
                run  = function() return ms.roblox.sensitivity() end,
            })

            ms.tools.define({
                id   = "roblox.framerateCap",
                name = "Roblox: Framerate Cap",
                run  = function() return ms.roblox.framerateCap() end,
            })

            ms.tools.define({
                id   = "roblox.isFocused",
                name = "Roblox: Is Focused",
                run  = function() return ms.roblox.isFocused() end,
            })

            -- Moved here from the roblox settings section: a function that
            -- pops the live Roblox settings as an alert.
            ms.tools.define({
                id   = "roblox.showSettings",
                name = "Roblox: Show Settings",
                run  = function()
                    local sens = ms.roblox.sensitivity()
                    local fps  = ms.roblox.framerateCap()
                    local q    = ms.roblox.graphicsQuality()
                    if sens or fps or q then
                        ms.alert(string.format(
                            "Sensitivity: %s   FPS cap: %s   Quality: %s",
                            tostring(sens or "?"), tostring(fps or "?"), tostring(q or "?")), 4)
                    else
                        ms.alert("Roblox settings not found.", 3)
                    end
                end,
            })

            ms.tools.define({
                id   = "roblox.openFastFlags",
                name = "Roblox: Open Fast Flags",
                run  = function()
                    local path
                    if IS_WINDOWS then
                        local vdir = robloxVersionDir()
                        if not vdir then
                            ms.alert("Roblox install folder not found.", 3)
                            return
                        end
                        path = vdir .. "/ClientSettings/ClientAppSettings.json"
                    else
                        path = "/Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json"
                    end

                    local dir = path:match("^(.*)/[^/]+$")
                    if dir and not hs.fs.attributes(dir) then
                        hs.execute("mkdir -p '" .. dir:gsub("\\", "/") .. "'")
                    end

                    if not hs.fs.attributes(path) then
                        local f = io.open(path, "w")
                        if f then
                            f:write("{\n}\n")
                            f:close()
                        else
                            ms.alert("Could not create ClientAppSettings.json (permission?).", 4)
                            return
                        end
                    end

                    shellOpen(path)
                end,
            })

            ms.tools.define({
                id   = "roblox.openAppFolder",
                name = "Roblox: Open Roblox Folder",
                run  = function()
                    if IS_WINDOWS then
                        revealDir(robloxVersionDir() or ROBLOX_DIR)
                    else
                        revealDir("/Applications/Roblox.app/Contents")
                    end
                end,
            })
        end
    -- END Builder Tools --

    armAntiTimeout()
    return self
end

function obj:stop()
    if _sensWatcher then
        _sensWatcher:stop()
        _sensWatcher = nil
    end
    if _sensTimer then
        _sensTimer:stop()
        _sensTimer = nil
    end
    if _cacheTimer then
        _cacheTimer:stop()
        _cacheTimer = nil
    end
    pcall(function() ms.antiTimeoutStop() end)
    if ms._targetApp == "Roblox" then
        pcall(function() ms.setTargetApp(nil) end)
    end
    ms.roblox = nil
    return self
end

return obj

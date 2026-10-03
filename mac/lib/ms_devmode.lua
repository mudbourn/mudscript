return function(ms)
    -- Developer Mode (ms.devmode) --
        local flagPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_devmode"

        ms.devmode = ms.devmode or {}

        -- IPC --
            local function _ipcStart()
                if package.loaded["hs.ipc"] and hs.ipc and hs.ipc.__default then return true end
                package.loaded["hs.ipc"] = nil
                local ok, mod = pcall(require, "hs.ipc")
                if not ok then
                    print("MsDevmode: hs.ipc failed to load: " .. tostring(mod))
                    return false
                end
                hs.ipc = mod
                return true
            end

            local function _ipcStop()
                local mod = package.loaded["hs.ipc"]
                if type(mod) == "table" and mod.__default then
                    pcall(function() mod.__default:delete() end)
                    mod.__default = nil
                end
                package.loaded["hs.ipc"] = nil
            end
        -- END IPC --

        -- State --
            ms.devmode.isOn = function()
                return hs.fs.attributes(flagPath) ~= nil
            end

            ms.devmode.ipcRunning = function()
                local mod = package.loaded["hs.ipc"]
                return type(mod) == "table" and mod.__default ~= nil
            end

            ms.devmode.bootedInDevMode = function()
                return _G._guardianDevMode == true
            end

            ms.devmode.enable = function()
                local f = io.open(flagPath, "w")
                if not f then return false end
                f:write(os.date("!%Y-%m-%dT%H:%M:%SZ"))
                f:close()
                _ipcStart()
                return true
            end

            ms.devmode.disable = function()
                os.remove(flagPath)
                _ipcStop()
                return true
            end
        -- END State --

        if ms.package then
            ms.package.protectionDisabled = ms.devmode.isOn
        end

        if ms.devmode.isOn() then _ipcStart() end
    -- END Developer Mode --
end

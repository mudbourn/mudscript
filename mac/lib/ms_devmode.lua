return function(ms)
    -- Developer Mode (ms.devmode) --
        local baseDir = "/Library/Application Support/mudscript"
        local flagDir = baseDir .. "/devmode"

        ms.devmode = ms.devmode or {}

        local _on = false

        -- Paths --
            local function _shq(p)
                return "'" .. tostring(p):gsub("'", "'\\''") .. "'"
            end

            local function _flagPath()
                local user = (os.getenv("USER") or ""):gsub("[^%w%._%-]", "")
                if user == "" then return nil end
                return flagDir .. "/" .. user
            end
        -- END Paths --

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

        -- Authorization --
            local function _authorized()
                local flag = _flagPath()
                if not flag then return false end
                local out = hs.execute("/usr/bin/stat -f '%u %Lp %HT' "
                    .. _shq(baseDir) .. " " .. _shq(flagDir) .. " " .. _shq(flag) .. " 2>/dev/null")
                if type(out) ~= "string" then return false end
                local want = {
                    "Directory",
                    "Directory",
                    "Regular File",
                }
                local i = 0
                for line in out:gmatch("[^\n]+") do
                    i = i + 1
                    local uid, perm, kind = line:match("^(%d+) (%d+) (.+)$")
                    if uid ~= "0" or kind ~= want[i] then return false end
                    local g = tonumber(perm:sub(-2, -2)) or 7
                    local o = tonumber(perm:sub(-1)) or 7
                    if g == 2 or g == 3 or g >= 6 or o == 2 or o == 3 or o >= 6 then return false end
                end
                return i == 3
            end

            local function _runAsAdmin(cmd, onDone)
                local script = "do shell script \"" .. cmd:gsub("\\", "\\\\"):gsub("\"", "\\\"")
                    .. "\" with administrator privileges"
                local task = hs.task.new("/usr/bin/osascript", function(code)
                    onDone(code == 0)
                end, {
                    "-e",
                    script,
                })
                if not task or not task:start() then onDone(false) end
            end
        -- END Authorization --

        -- State --
            ms.devmode.isOn = function()
                return _on
            end

            ms.devmode.ipcRunning = function()
                local mod = package.loaded["hs.ipc"]
                return type(mod) == "table" and mod.__default ~= nil
            end

            ms.devmode.bootedInDevMode = function()
                return _G._guardianDevMode == true
            end

            ms.devmode.enable = function(onDone)
                local flag = _flagPath()
                if not flag then
                    if onDone then onDone(false) end
                    return
                end
                local cmd = "/bin/mkdir -p " .. _shq(flagDir)
                    .. " && /usr/sbin/chown root:wheel " .. _shq(baseDir) .. " " .. _shq(flagDir)
                    .. " && /bin/chmod 755 " .. _shq(baseDir) .. " " .. _shq(flagDir)
                    .. " && /bin/rm -rf " .. _shq(flag)
                    .. " && /usr/bin/touch " .. _shq(flag)
                    .. " && /usr/sbin/chown root:wheel " .. _shq(flag)
                    .. " && /bin/chmod 644 " .. _shq(flag)
                _runAsAdmin(cmd, function(ok)
                    _on = _authorized()
                    ok = ok and _on
                    if ok then _ipcStart() end
                    if onDone then onDone(ok) end
                end)
            end

            ms.devmode.disable = function(onDone)
                local flag = _flagPath()
                if not flag then
                    if onDone then onDone(true) end
                    return
                end
                _runAsAdmin("/bin/rm -rf " .. _shq(flag), function()
                    _on = _authorized()
                    local off = not _on
                    if off then _ipcStop() end
                    if onDone then onDone(off) end
                end)
            end
        -- END State --

        if ms.package then
            ms.package.protectionDisabled = _authorized
        end

        _on = _authorized()
        if _on then
            _ipcStart()
            hs.timer.doAfter(3, function()
                ms.alert("Developer mode is on.\nIntegrity checks and the plugin gate are off.", 8)
            end)
        end
    -- END Developer Mode --
end

return function(ms)
    -- Developer Mode (ms.devmode) --
        local baseDir = "/Library/Application Support/mudscript"

        ms.devmode = ms.devmode or {}

        -- Root Flags --
            local function _shq(p)
                return "'" .. tostring(p):gsub("'", "'\\''") .. "'"
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

            ms.devmode.rootFlag = function(name)
                local flagDir = baseDir .. "/" .. name
                local rf = {}

                local function _path()
                    local user = (os.getenv("USER") or ""):gsub("[^%w%._%-]", "")
                    if user == "" then return nil end
                    return flagDir .. "/" .. user
                end

                rf.authorized = function()
                    local flag = _path()
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

                rf.set = function(onDone)
                    local flag = _path()
                    if not flag then
                        onDone(false)
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
                        onDone(ok and rf.authorized())
                    end)
                end

                rf.clear = function(onDone)
                    local flag = _path()
                    if not flag then
                        onDone(true)
                        return
                    end
                    _runAsAdmin("/bin/rm -rf " .. _shq(flag), function()
                        onDone(not rf.authorized())
                    end)
                end

                return rf
            end
        -- END Root Flags --

        local _flag = ms.devmode.rootFlag("devmode")
        local _on   = false

        -- State --
            ms.devmode.isOn = function()
                return _on
            end

            ms.devmode.bootedInDevMode = function()
                return _G._guardianDevMode == true
            end

            ms.devmode.enable = function(onDone)
                _flag.set(function(ok)
                    _on = _flag.authorized()
                    if onDone then onDone(ok and _on) end
                end)
            end

            ms.devmode.disable = function(onDone)
                _flag.clear(function(off)
                    _on = _flag.authorized()
                    if onDone then onDone(off) end
                end)
            end
        -- END State --

        if ms.package then
            ms.package.protectionDisabled = _flag.authorized
        end

        _on = _flag.authorized()
        if _on then
            hs.timer.doAfter(3, function()
                ms.alert("Developer mode is on.\nIntegrity checks and the plugin gate are off.", 8)
            end)
        end
    -- END Developer Mode --
end

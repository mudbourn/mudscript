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

            local _isWin = package.config:sub(1, 1) == "\\"

            -- Windows Flags --
                local PS = (os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
                local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                local WRITE_MASK = "0x500D0156"
                local TRUSTED = "'S-1-5-32-544','S-1-5-18'"

                local function _encode(script)
                    local bytes = {}
                    for i = 1, #script do
                        bytes[#bytes + 1] = script:byte(i)
                        bytes[#bytes + 1] = 0
                    end
                    local out = {}
                    for i = 1, #bytes, 3 do
                        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
                        local n = a * 65536 + (b or 0) * 256 + (c or 0)
                        local q = {
                            math.floor(n / 262144) % 64,
                            math.floor(n / 4096) % 64,
                            math.floor(n / 64) % 64,
                            n % 64,
                        }
                        out[#out + 1] = B64:sub(q[1] + 1, q[1] + 1) .. B64:sub(q[2] + 1, q[2] + 1)
                            .. (b and B64:sub(q[3] + 1, q[3] + 1) or "=")
                            .. (c and B64:sub(q[4] + 1, q[4] + 1) or "=")
                    end
                    return table.concat(out)
                end

                local function _psArgs(script)
                    return {
                        "-NoProfile",
                        "-NonInteractive",
                        "-WindowStyle",
                        "Hidden",
                        "-EncodedCommand",
                        _encode(script),
                    }
                end

                local function _winFlag(name)
                    local rf = {}
                    local user = (os.getenv("USERNAME") or ""):gsub("[^%w%._%-]", "")
                    local flagName = tostring(name):gsub("[^%w%._%-]", "")
                    local paths = "$ProgressPreference='SilentlyContinue';$b=Join-Path $env:ProgramData 'mudscript';$d=Join-Path $b '" .. flagName
                        .. "';$f=Join-Path $d '" .. user .. "';"
                    local checkScript = paths
                        .. "$ok=Test-Path -LiteralPath $f -PathType Leaf;"
                        .. "if($ok){foreach($p in @($b,$d,$f)){$a=Get-Acl -LiteralPath $p;"
                        .. "$s=[System.Security.Principal.SecurityIdentifier];"
                        .. "if($a.GetOwner($s).Value -notin @(" .. TRUSTED .. ")){$ok=$false};"
                        .. "foreach($r in $a.GetAccessRules($true,$true,$s)){"
                        .. "if($r.AccessControlType -eq 'Allow' -and $r.IdentityReference.Value -notin @(" .. TRUSTED .. ")"
                        .. " -and ([int64]$r.FileSystemRights -band " .. WRITE_MASK .. ")){$ok=$false}}}};"
                        .. "if($ok){'authorized'}"
                    local setScript = paths
                        .. "$ErrorActionPreference='Stop';"
                        .. "New-Item -ItemType Directory -Force -Path $d|Out-Null;"
                        .. "foreach($p in @($b,$d)){$acl=New-Object System.Security.AccessControl.DirectorySecurity;"
                        .. "$acl.SetAccessRuleProtection($true,$false);"
                        .. "$acl.SetOwner([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544');"
                        .. "foreach($e in @(@('S-1-5-32-544','FullControl'),@('S-1-5-18','FullControl'),@('S-1-5-32-545','ReadAndExecute'))){"
                        .. "$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("
                        .. "([System.Security.Principal.SecurityIdentifier]$e[0]),$e[1],'ContainerInherit,ObjectInherit','None','Allow')))};"
                        .. "Set-Acl -LiteralPath $p -AclObject $acl};"
                        .. "if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Recurse -Force};"
                        .. "New-Item -ItemType File -Path $f|Out-Null"
                    local clearScript = paths
                        .. "if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Recurse -Force}"

                    local function _elevate(script, onDone)
                        local outer = "$p=Start-Process -FilePath '" .. PS .. "' -Verb RunAs -Wait -PassThru -WindowStyle Hidden"
                            .. " -ArgumentList '" .. table.concat(_psArgs(script), " ") .. "';exit $p.ExitCode"
                        local task = hs.task.new(PS, function(code)
                            onDone(code == 0)
                        end, _psArgs(outer))
                        if not task or not task:start() then onDone(false) end
                    end

                    local cached = nil

                    local function _recheck(onDone)
                        local task = hs.task.new(PS, function(_, out)
                            cached = type(out) == "string" and out:find("authorized", 1, true) ~= nil
                            onDone(cached)
                        end, _psArgs(checkScript))
                        if not task or not task:start() then onDone(cached == true) end
                    end

                    rf.authorized = function()
                        if user == "" or flagName == "" then return false end
                        if cached == nil then
                            local out = hs.execute('"' .. PS .. '" ' .. table.concat(_psArgs(checkScript), " "), false)
                            cached = type(out) == "string" and out:find("authorized", 1, true) ~= nil
                        end
                        return cached
                    end

                    rf.set = function(onDone)
                        if user == "" or flagName == "" then
                            onDone(false)
                            return
                        end
                        _elevate(setScript, function(ok)
                            _recheck(function(on)
                                onDone(ok and on)
                            end)
                        end)
                    end

                    rf.clear = function(onDone)
                        if user == "" or flagName == "" or not rf.authorized() then
                            onDone(true)
                            return
                        end
                        _elevate(clearScript, function()
                            _recheck(function(on)
                                onDone(not on)
                            end)
                        end)
                    end

                    return rf
                end
            -- END Windows Flags --

            ms.devmode.rootFlag = function(name)
                if _isWin then return _winFlag(name) end
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

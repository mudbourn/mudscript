-- MsGuardian (pre-load integrity check) --
return function()

local _obj = {
    name    = "MsGuardian",
    version = "1.0",
}

-- Paths --
    local _home      = os.getenv("HOME")
    local _corePath  = _home .. "/.hammerspoon/ms_core.lua"
    local _trustPath = _home .. "/.hammerspoon/data/.ms_trusted_hash"
    local _dataPath  = _home .. "/.hammerspoon/data/"

    local _publicKey = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
]]
-- END Paths --

-- Helpers --
    local function _hashFile(path)
        local out = hs.execute("shasum -a 256 '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")

        return (out and #out >= 64) and out:sub(1, 64):lower() or nil
    end

    local function _hashFilesBatch(paths)
        local out = {}
        if not paths or #paths == 0 then return out end
        local quoted = {}
        for i = 1, #paths do
            quoted[i] = "'" .. paths[i]:gsub("'", "'\\''") .. "'"
        end
        local res = hs.execute("shasum -a 256 " .. table.concat(quoted, " ") .. " 2>/dev/null")
        if not res then return out end
        for line in res:gmatch("[^\n]+") do
            local hash, path = line:match("^(%x+)%s+%*?(.+)$")
            if hash and #hash >= 64 and path then
                out[path] = hash:sub(1, 64):lower()
            end
        end
        return out
    end

    local function _readTrustedManifest()
        local _paths = {
            _trustPath,
            _home .. "/.hammerspoon/.ms_trusted_hash",
        }

        for _, _p in ipairs(_paths) do
            local f = io.open(_p, "r")
            if f then
                local raw = f:read("*all")
                f:close()
                if raw and raw ~= "" then
                    local single = raw:match("^%s*([0-9a-fA-F]+)%s*$")
                    if single and #single == 64 then
                        return { ["ms_core.lua"] = single:lower() }
                    end
                    local ok, tbl = pcall(hs.json.decode, raw)
                    if ok and type(tbl) == "table" then
                        local norm = {}
                        for k, v in pairs(tbl) do
                            if type(v) == "string" and #v == 64 then
                                local rel = k:gsub(".*/%.hammerspoon/", "")
                                norm[rel] = v:lower()
                            end
                        end
                        if next(norm) then return norm end
                    end
                end
            end
        end

        return nil
    end

    local function _readTrusted()
        local m = _readTrustedManifest()
        return m and m["ms_core.lua"] or nil
    end

    local function _trackedFiles()
        local files = { _corePath }

        local spoonDir = _home .. "/.hammerspoon/Spoons/"
        local ok, iter, dir_obj = pcall(hs.fs.dir, spoonDir)
        if ok and iter then
            for entry in iter, dir_obj do
                if entry ~= "." and entry ~= ".." then
                    local init = spoonDir .. entry .. "/init.lua"
                    if hs.fs.attributes(init) then
                        files[#files + 1] = init
                    end
                end
            end
            dir_obj:close()
        end

        local uiDir = _home .. "/.hammerspoon/ui/"
        local ok2, iter2, dir2 = pcall(hs.fs.dir, uiDir)
        if ok2 and iter2 then
            for entry in iter2, dir2 do
                if entry:match("%.html$") and not entry:match("^_popout_") then
                    files[#files + 1] = uiDir .. entry
                end
            end
            dir2:close()
        end
        local function _walkUiJs(dir)
            local okd, iterd, dobj = pcall(hs.fs.dir, dir)
            if not okd or not iterd then return end
            for entry in iterd, dobj do
                if entry ~= "." and entry ~= ".." then
                    local path = dir .. entry
                    local attr = hs.fs.attributes(path)
                    if attr and attr.mode == "directory" then
                        _walkUiJs(path .. "/")
                    elseif entry:match("%.js$") then
                        files[#files + 1] = path
                    end
                end
            end
            dobj:close()
        end
        _walkUiJs(uiDir)

        local binDir = _home .. "/.hammerspoon/bin/"
        local ok3, iter3, dir3 = pcall(hs.fs.dir, binDir)
        if ok3 and iter3 then
            for entry in iter3, dir3 do
                if entry:match("%.sh$") then
                    files[#files + 1] = binDir .. entry
                end
            end
            dir3:close()
        end

        local function _walkLua(dir)
            local okd, iterd, dobj = pcall(hs.fs.dir, dir)
            if not okd or not iterd then return end
            for entry in iterd, dobj do
                if entry ~= "." and entry ~= ".." then
                    local path = dir .. entry
                    local attr = hs.fs.attributes(path)
                    if attr and attr.mode == "directory" then
                        _walkLua(path .. "/")
                    elseif entry:match("%.lua$") then
                        files[#files + 1] = path
                    end
                end
            end
            dobj:close()
        end
        _walkLua(_home .. "/.hammerspoon/lib/")

        table.sort(files)
        return files
    end

    local function _checkAll(manifest)
        if not manifest then return "uninitialized" end
        local files = _trackedFiles()
        local toHash = {}
        for _, absPath in ipairs(files) do
            local rel = absPath:gsub(".*/%.hammerspoon/", "")
            if manifest[rel] then toHash[#toHash + 1] = absPath end
        end
        local hashed = _hashFilesBatch(toHash)
        for _, absPath in ipairs(toHash) do
            local rel = absPath:gsub(".*/%.hammerspoon/", "")
            local cur = hashed[absPath]
            if not cur then return "error", rel end
            if cur ~= manifest[rel] then return "mismatch", rel end
        end
        return "ok"
    end

    local function _verifyManifestSignature(manifest)
        if not manifest.signature or manifest.signature == "" then
            return false
        end
        local signTarget = (manifest.bundle and manifest.bundle.sha256 ~= "")
            and manifest.bundle.sha256 or manifest.sha256
        if not signTarget or signTarget == "" then return false end

        local _keyPath = _dataPath .. "_guardian_pub.pem"
        local _sigPath = _dataPath .. "_guardian_sig.bin"
        local _msgPath = _dataPath .. "_guardian_msg.bin"

        os.execute("mkdir -p '" .. _dataPath .. "'")

        local _kf = io.open(_keyPath, "w")
        if _kf then
            _kf:write(_publicKey)
            _kf:close()
        end

        local _sf = io.open(_sigPath .. ".b64", "w")
        if _sf then
            _sf:write(manifest.signature)
            _sf:close()
        end
        hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
        os.remove(_sigPath .. ".b64")

        local _mf = io.open(_msgPath, "w")
        if _mf then
            _mf:write(signTarget:lower())
            _mf:close()
        end

        local _out, _ok = hs.execute(
            "openssl dgst -sha256 -verify '" .. _keyPath ..
            "' -signature '" .. _sigPath ..
            "' '" .. _msgPath .. "' 2>&1"
        )

        os.remove(_keyPath)
        os.remove(_sigPath)
        os.remove(_msgPath)

        return _ok and _out and _out:find("Verified OK") ~= nil
    end

    local function _readFileManifest()
        local _fmPath = _home .. "/.hammerspoon/data/.ms_file_manifest.json"
        local f = io.open(_fmPath, "r")
        if not f then return nil end
        local raw = f:read("*all")
        f:close()
        if not raw or raw == "" then return nil end
        local ok, tbl = pcall(hs.json.decode, raw)
        if ok and type(tbl) == "table" and type(tbl.files) == "table" then
            return tbl
        end
        return nil
    end

    local function _verifyFileManifestSignature(fm)
        if not fm.signature or fm.signature == "" then
            return false
        end

        local signPayload = {
            version   = fm.version,
            generated = fm.generated,
            files     = fm.files,
        }
        local okEncode, unsorted = pcall(hs.json.encode, signPayload)
        if not okEncode or not unsorted then return false end

        local _sortTmp = _dataPath .. "_guardian_sort_tmp.json"
        local _stf = io.open(_sortTmp, "w")
        if _stf then
            _stf:write(unsorted)
            _stf:close()
        end
        local sortedOut = hs.execute("jq -c -S '.' '" .. _sortTmp .. "' 2>/dev/null")
        os.remove(_sortTmp)
        local minified = sortedOut and sortedOut ~= "" and sortedOut:sub(-1) == "\n"
            and sortedOut:sub(1, -2) or sortedOut
        if not minified or minified == "" then return false end

        local _keyPath = _dataPath .. "_guardian_pub.pem"
        local _sigPath = _dataPath .. "_guardian_sig.bin"
        local _msgPath = _dataPath .. "_guardian_msg.bin"

        os.execute("mkdir -p '" .. _dataPath .. "'")

        local _kf = io.open(_keyPath, "w")
        if _kf then
            _kf:write(_publicKey)
            _kf:close()
        end

        local _sf = io.open(_sigPath .. ".b64", "w")
        if _sf then
            _sf:write(fm.signature)
            _sf:close()
        end
        hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
        os.remove(_sigPath .. ".b64")

        local _mf = io.open(_msgPath, "w")
        if _mf then
            _mf:write(minified)
            _mf:close()
        end

        local _out, _ok = hs.execute(
            "openssl dgst -sha256 -verify '" .. _keyPath ..
            "' -signature '" .. _sigPath ..
            "' '" .. _msgPath .. "' 2>&1"
        )

        os.remove(_keyPath)
        os.remove(_sigPath)
        os.remove(_msgPath)

        return _ok and _out and _out:find("Verified OK") ~= nil
    end

    local function _checkFileManifest()
        local fm = _readFileManifest()
        if not fm then return "legacy" end

        if not _verifyFileManifestSignature(fm) then
            return "tampered"
        end

        local toHash, expectedFor = {}, {}
        for relPath, expected in pairs(fm.files) do
            if type(expected) == "string" and #expected == 64 then
                local absPath = _home .. "/.hammerspoon/" .. relPath
                if hs.fs.attributes(absPath) then
                    toHash[#toHash + 1] = absPath
                    expectedFor[absPath] = {
                        rel = relPath,
                        hash = expected:lower(),
                    }
                end
            end
        end
        local hashed = _hashFilesBatch(toHash)
        for _, absPath in ipairs(toHash) do
            local want = expectedFor[absPath]
            local cur  = hashed[absPath]
            if not cur or cur ~= want.hash then return "mismatch", want.rel end
        end

        return "ok"
    end

    -- Added-file check, scoped to Spoons/ --
    local _ledgerPath = _dataPath .. ".ms_plugin_ledger.json"
    local _spoonsDir  = _home .. "/.hammerspoon/Spoons"

    local function _hashSpoonTree(absDir)
        local out, ok = hs.execute(
            "cd '" .. absDir .. "' && find . -type f ! -name '.DS_Store' " ..
            "! -name '._*' ! -path './__MACOSX/*' " ..
            "-exec shasum -a 256 {} + 2>/dev/null | LC_ALL=C sort -k2 | shasum -a 256"
        )
        if not ok or not out then return nil end
        return out:match("^(%x+)")
    end

    local function _installedSpoons()
        local found = {}
        if not hs.fs.attributes(_spoonsDir) then return found end
        for name in hs.fs.dir(_spoonsDir) do
            if name:sub(1, 1) ~= "." and name:match("%.spoon$") then
                local abs = _spoonsDir .. "/" .. name
                local attr = hs.fs.attributes(abs)
                if attr and attr.mode == "directory" then
                    found[name] = _hashSpoonTree(abs)
                end
            end
        end
        return found
    end

    local function _readLedger()
        local f = io.open(_ledgerPath, "r")
        if not f then return nil end
        local raw = f:read("*all")
        f:close()
        if not raw or raw == "" then return nil end
        local ok, tbl = pcall(hs.json.decode, raw)
        if ok and type(tbl) == "table" and type(tbl.plugins) == "table" then
            return tbl
        end
        return nil
    end

    local function _writeLedger(tbl)
        local ok, json = pcall(hs.json.encode, tbl)
        if not ok then return false end
        local f = io.open(_ledgerPath, "w")
        if not f then return false end
        f:write(json .. "\n")
        f:close()
        return true
    end

    local function _checkSpoons()
        local installed = _installedSpoons()
        local ledger    = _readLedger()

        if not ledger then
            local first = nil
            for name in pairs(installed) do
                if not first or name < first then first = name end
            end
            if first then return "noledger", first end

            _writeLedger({
                version   = 1,
                createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                plugins   = {},
            })
            return "ok"
        end

        for name, hash in pairs(installed) do
            local rec = ledger.plugins[name]
            if type(rec) ~= "table" or type(rec.hash) ~= "string" then
                return "unknown", name
            end
            if hash and hash:lower() ~= rec.hash:lower() then
                return "unknown", name
            end
        end

        return "ok"
    end

    local function _unknownSpoonSpec(name)
        return {
            titlebar = "mudscript: Unrecognized Plugin",
            height   = 430,
            title    = "Unrecognized plugin",
            lead     = "A plugin in Spoons/ was not installed through mudscript, "
                    .. "or has changed since it was. Because of this, mudscript did "
                    .. "not load, so no macros or key bindings are active.",
            rows     = {
                {
                    label = "Plugin",
                    value = "Spoons/" .. tostring(name),
                },
            },
            warning  = {
                "Plugins run as code, so an unrecognized one blocks startup "
                .. "instead of loading unchecked.",
                "If you added it yourself, re-import it through the plugin "
                .. "library. Otherwise remove it from ~/.hammerspoon/Spoons/ "
                .. "and reload.",
            },
            actions  = {
                {
                    label = "Reveal in Finder",
                    action = "revealSpoons",
                    style = "accent",
                },
                {
                    label = "Keep Blocked",
                    action = "keepBlocked",
                },
            },
        }
    end

    local function _noLedgerSpec(name)
        return {
            titlebar = "mudscript: Plugins Not Verified",
            height   = 430,
            title    = "No plugin record",
            lead     = "Plugins are installed, but mudscript has no record of "
                    .. "where they came from. Because of this, mudscript did not load, "
                    .. "so no macros or key bindings are active.",
            rows     = {
                {
                    label = "Found",
                    value = "Spoons/" .. tostring(name),
                },
            },
            warning  = {
                "Expected once, on an install that predates plugin verification. "
                .. "Re-import each plugin through the library to record it.",
                "The record is not rebuilt from disk on purpose: if it were, "
                .. "deleting one file would make any plugin look trusted.",
            },
            actions  = {
                {
                    label = "Reveal in Finder",
                    action = "revealSpoons",
                    style = "accent",
                },
                {
                    label = "Keep Blocked",
                    action = "keepBlocked",
                },
            },
        }
    end
    -- END Added-file check --

    local function _repairViaUpdate(onProgress, onDone)
        local _archivePath = _home .. "/.hammerspoon/data/updates/"
        os.execute("mkdir -p '" .. _archivePath .. "'")

        if onProgress then pcall(onProgress, "Fetching latest release info...") end

        hs.http.asyncGet("https://api.github.com/repos/mudbourn/mudscript/releases/latest", {
            ["Accept"] = "application/vnd.github+json",
        }, function(code, body, _)
            if code ~= 200 or not body then
                if onDone then pcall(onDone, false, "GitHub API returned HTTP " .. tostring(code)) end
                return
            end
            local ok, data = pcall(hs.json.decode, body)
            if not ok or not data then
                if onDone then pcall(onDone, false, "Could not parse release JSON") end
                return
            end
            local downloadUrl
            local assets = data.assets or {}
            for _, asset in ipairs(assets) do
                if asset.name and asset.name:match("^mudscript%-macos%-.*%.zip$") then
                    downloadUrl = asset.browser_download_url
                    break
                end
            end
            if not downloadUrl then
                if onDone then pcall(onDone, false, "No mudscript-macos bundle found in latest release") end
                return
            end

            if onProgress then pcall(onProgress, "Downloading signed bundle...") end

            -- Download the bundle with curl, NOT hs.http.asyncGet: asyncGet
            -- returns the body through a lossy NSData->string conversion that
            -- corrupts non-UTF8 bytes, so the .zip came out unextractable and
            -- the update silently failed at unzip. curl writes exact bytes; -L
            -- follows the release-asset redirect; args are an array (no shell).
            local tmpArchive = _archivePath .. "ms_bundle_update.zip"
            local _dlTask = hs.task.new("/usr/bin/curl", function(fCode)
                if fCode ~= 0 then
                    if onDone then pcall(onDone, false, "Bundle download failed (curl exit " .. tostring(fCode) .. ")") end
                    return
                end
                if not hs.fs.attributes(tmpArchive) then
                    if onDone then pcall(onDone, false, "Bundle download produced no file") end
                    return
                end

                if onProgress then pcall(onProgress, "Extracting bundle...") end

                local tmpExtract = _archivePath .. "ms_bundle_extract/"
                os.execute("rm -rf '" .. tmpExtract .. "'")
                os.execute("mkdir -p '" .. tmpExtract .. "'")
                local _, extractOk = hs.execute("unzip -o '" .. tmpArchive .. "' -d '" .. tmpExtract .. "' 2>&1")
                os.remove(tmpArchive)
                if not extractOk then
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if onDone then pcall(onDone, false, "Could not extract bundle zip") end
                    return
                end

                local topDir = nil
                local dh = io.popen("ls -d '" .. tmpExtract .. "'/mudscript-* 2>/dev/null | head -1")
                if dh then
                    topDir = dh:read("*l")
                    dh:close()
                end
                if not topDir or topDir == "" then topDir = tmpExtract end
                if not topDir:match("/$") then topDir = topDir .. "/" end

                if onProgress then pcall(onProgress, "Verifying bundle signature...") end

                local manifestPath = topDir .. "MANIFEST.json"
                local manifest = nil
                local mf = io.open(manifestPath, "r")
                if mf then
                    local mOk, m = pcall(hs.json.decode, mf:read("*all"))
                    mf:close()
                    if mOk then manifest = m end
                end
                if not manifest then
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if onDone then pcall(onDone, false, "Bundle missing MANIFEST.json") end
                    return
                end
                if not _verifyManifestSignature(manifest) then
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if onDone then pcall(onDone, false, "Signature verification failed, unsigned or tampered bundle") end
                    return
                end

                if onProgress then pcall(onProgress, "Applying update...") end

                local hsDir = _home .. "/.hammerspoon/"
                local timestamp = os.date("%Y-%m-%d_%H%M")
                local replaceList = {
                    "ms_core.lua",
                    "init.lua",
                    "ui",
                    "bin",
                    "lib",
                    "Spoons",
                }
                local templateList = {
                    "ms_macros.lua",
                    "profiles/Default",
                }

                os.execute("mkdir -p '" .. _archivePath .. "'")

                for _, name in ipairs(replaceList) do
                    local src = topDir .. name
                    local dst = hsDir .. name
                    if hs.fs.attributes(src) then
                        if hs.fs.attributes(dst) then
                            local safeName = name:gsub("/", "_")
                            local bak = _archivePath .. safeName .. "_" .. timestamp
                                .. (hs.fs.attributes(dst).mode == "directory" and ".d.bak" or ".bak")
                            os.execute("rm -rf '" .. bak .. "'")
                            os.execute("cp -R '" .. dst .. "' '" .. bak .. "'")
                        end
                        os.execute("rm -rf '" .. dst .. "'")
                        os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                    end
                end

                local fmSrc = topDir .. "data/.ms_file_manifest.json"
                local fmDst = hsDir .. "data/.ms_file_manifest.json"
                if hs.fs.attributes(fmSrc) then
                    os.execute("mkdir -p '" .. hsDir .. "data'")
                    os.execute("cp '" .. fmSrc .. "' '" .. fmDst .. "'")
                end

                local mfSrc = topDir .. "MANIFEST.json"
                local mfDst = hsDir .. "MANIFEST.json"
                if hs.fs.attributes(mfSrc) then
                    os.execute("cp '" .. mfSrc .. "' '" .. mfDst .. "'")
                end

                for _, name in ipairs(templateList) do
                    local src = topDir .. name
                    local dst = hsDir .. name
                    if hs.fs.attributes(src) and not hs.fs.attributes(dst) then
                        local parent = dst:match("(.+)/[^/]+$")
                        if parent then os.execute("mkdir -p '" .. parent .. "'") end
                        os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                    end
                end

                os.execute("rm -rf '" .. tmpExtract .. "'")

                if onProgress then pcall(onProgress, "Update applied, reloading...") end
                if onDone then pcall(onDone, true) end
            end, { "-sSL", "--fail", "--max-time", "300", "-o", tmpArchive, downloadUrl })

            if not _dlTask or not _dlTask:start() then
                if onDone then pcall(onDone, false, "Could not start the bundle download") end
            end
        end)
    end

    local function _safeShow(view)
        if not view then return false end
        local ok = pcall(function() view:show() end)
        if ok then return true end
        hs.timer.doAfter(0.05, function()
            pcall(function() view:show() end)
        end)
        return false
    end

    local function _showGuardianBlock(expectedHash, currentHash, spec)
        local _customThemeDisabled = true
        pcall(function()
            local _sf = io.open(_home .. "/.hammerspoon/data/ms_settings.json", "r")
            if _sf then
                local _raw = _sf:read("*all")
                _sf:close()
                local _ok, _sd = pcall(hs.json.decode, _raw)
                if _ok and type(_sd) == "table" then
                    _customThemeDisabled = (_sd.customThemeDisabled == true)
                end
            end
        end)

        pcall(function()
            local _soundPath = _customThemeDisabled
                and (_home .. "/.hammerspoon/sounds/defaults/d_Error.wav")
                or  (_home .. "/.hammerspoon/sounds/active/a_Error.wav")
            local _snd = hs.sound.getByFile(_soundPath)
            if _snd then _snd:play() end
        end)

        local _guardianView = nil
        local _guardianPos   = nil -- tracked in Lua, not read back from frame(), to survive drag

        local _ucGuardian = hs.webview.usercontent.new("guardian")

        _ucGuardian:setCallback(function(msg)
            local body = msg.body

            if body == "confirmDelete" then
                pcall(function() if _guardianView then _guardianView:delete() end end)
                os.remove(_trustPath)
                os.remove(_home .. "/.hammerspoon/data/.ms_file_manifest.json")
                hs.reload()

            elseif body == "keepBlocked" then
                pcall(function() if _guardianView then _guardianView:delete() end end)
                pcall(function()
                    local app = hs.application.get("Hammerspoon")
                    if app then app:kill() else os.exit(0) end
                end)

            elseif body == "revealSpoons" then
                hs.execute("/usr/bin/open '" .. _spoonsDir .. "'")

            else
                local ok, data = pcall(hs.json.decode, body) -- JSON move delta from the drag handler

                if ok and data and data.action == "repair" then
                    _repairViaUpdate(
                        function(progressMsg)
                            pcall(function()
                                _guardianView:evaluateJavaScript(
                                    "setRepairStatus(" .. hs.json.encode(progressMsg) .. ", false)"
                                )
                            end)
                        end,
                        function(repairOk, errMsg)
                            if repairOk then
                                hs.reload()
                            else
                                pcall(function()
                                    _guardianView:evaluateJavaScript(
                                        "setRepairStatus(" .. hs.json.encode("Repair failed: " .. (errMsg or "unknown error")) .. ", true)"
                                    )
                                end)
                            end
                        end
                    )

                elseif ok and data and data.action == "move" then
                    pcall(function()
                        if not _guardianPos then return end
                        _guardianPos.x = _guardianPos.x + (data.dx or 0)
                        _guardianPos.y = _guardianPos.y + (data.dy or 0)
                        _guardianView:frame(_guardianPos)
                    end)
                end
            end
        end)

        local _ok, _screen = pcall(function() return hs.screen.mainScreen():frame() end)

        if _ok and _screen then
            local _gw, _gh = 480, (spec and spec.height) or 360

            local _gx = _screen.x + math.floor((_screen.w - _gw) / 2)
            local _gy = _screen.y + math.floor((_screen.h - _gh) / 2)

            _guardianView = hs.webview.new({
                x = _gx,
                y = _gy,
                w = _gw,
                h = _gh,
            }, {}, _ucGuardian)

            _guardianPos = {
                x = _gx,
                y = _gy,
                w = _gw,
                h = _gh,
            }
        end

        if _guardianView then
            pcall(function() _guardianView:windowStyle(0) end)
            pcall(function() _guardianView:level(hs.canvas.windowLevels.popUpMenu or 101) end)
            pcall(function() _guardianView:shadow(true) end)
            pcall(function() _guardianView:allowTextEntry(false) end)

            local _htmlPath = _home .. "/.hammerspoon/ui/ms_guardian.html"
            local _baseURL  = "file://" .. _home .. "/.hammerspoon/ui/"

            local _guardianTheme = nil

            if not _customThemeDisabled then
                local _tf = io.open(_home .. "/.hammerspoon/data/ms_theme.json", "r")

                if _tf then
                    local _td = hs.json.decode(_tf:read("*all"))
                    _tf:close()

                    if type(_td) == "table" then
                        _guardianTheme = _td
                    end
                end
            end

            local _gf = io.open(_htmlPath, "r")

            if _gf then
                local _ghtml = _gf:read("*all")
                _gf:close()

                _guardianView:html(_ghtml, _baseURL)
                _guardianView:alpha(0)
                _safeShow(_guardianView)

                local _fadeStarted = false

                _guardianView:navigationCallback(function(action)
                    pcall(function()
                        if spec then
                            _guardianView:evaluateJavaScript(
                                "setFailure(" .. hs.json.encode(spec) .. ")"
                            )
                        else
                            local _t = (expectedHash or "unknown"):sub(1, 16) .. "..."
                            local _c = (currentHash or "unknown"):sub(1, 16)  .. "..."

                            _guardianView:evaluateJavaScript(
                                "setHashes('" .. _t .. "', '" .. _c .. "')"
                            )
                        end

                        if _guardianTheme then
                            local _tj = hs.json.encode(_guardianTheme)

                            if _tj then
                                _guardianView:evaluateJavaScript("applyTheme(" .. _tj .. ")")
                            end
                        end

                    end)

                    if not _fadeStarted then
                        _fadeStarted = true
                        local _fadeSteps = 8
                        local _fadeStep  = 0
                        local _fadeTimer
                        _fadeTimer = hs.timer.doEvery(0.019, function()
                            _fadeStep = _fadeStep + 1
                            local _a = math.min(_fadeStep / _fadeSteps, 1.0)
                            pcall(function() _guardianView:alpha(_a) end)
                            -- doEvery's callback receives no timer arg (Hammerspoon
                            -- parity), so stop via the captured handle, not a param.
                            if _a >= 1.0 and _fadeTimer then _fadeTimer:stop() end
                        end)
                    end
                end)

            else
                _guardianView:delete()
                hs.focus()

                local _choice = hs.dialog.blockAlert(
                    "\u{26a0} Integrity Error: mudscript Did Not Load",
                    "File hash mismatch detected. Delete trusted manifest and reload?",
                    "Keep Blocked",
                    "Delete Manifest & Reload"
                )

                if _choice == "Delete Manifest & Reload" then
                    os.remove(_trustPath)
                    os.remove(_home .. "/.hammerspoon/data/.ms_file_manifest.json")
                    hs.reload()
                end
            end
        else
            hs.focus()

            local _choice = hs.dialog.blockAlert(
                "\u{26a0} Integrity Error: mudscript Did Not Load",
                "File hash mismatch detected. Delete trusted manifest and reload?",
                "Keep Blocked",
                "Delete Manifest & Reload"
            )

            if _choice == "Delete Manifest & Reload" then
                os.remove(_trustPath)
                os.remove(_home .. "/.hammerspoon/data/.ms_file_manifest.json")
                hs.reload()
            end
        end
    end

    local function _seedTrustedFromDisk()
        local newManifest = {}
        for _, absPath in ipairs(_trackedFiles()) do
            local h = _hashFile(absPath)
            if h then
                newManifest[absPath:gsub(".*/%.hammerspoon/", "")] = h
            end
        end
        local ok, json = pcall(hs.json.encode, newManifest)
        if ok then
            local wf = io.open(_trustPath, "w")
            if wf then
                wf:write(json .. "\n")
                wf:close()
            end
        end
    end

    local function _signedManifestConfirms()
        local _cur = _hashFile(_corePath)
        if not _cur then return false end

        local _mf = io.open(_home .. "/.hammerspoon/MANIFEST.json", "r")
        if not _mf then return false end
        local _raw = _mf:read("*all")
        _mf:close()

        local _ok, _m = pcall(hs.json.decode, _raw)
        return _ok and type(_m) == "table"
            and type(_m.sha256) == "string"
            and #_m.sha256 == 64
            and _m.sha256:lower() == _cur:lower()
            and _verifyManifestSignature(_m)
    end
-- END Helpers --

-- Integrity Check --
    local _blocked = false
    local _manifest = _readTrustedManifest()
    local _fmResult, _fmFailedFile = _checkFileManifest()

    if _fmResult == "ok" then
        print("Guardian: per-file manifest verified, all files intact.")
        pcall(function()
            local fm = _readFileManifest()
            if fm and fm.files then
                local ok, json = pcall(hs.json.encode, fm.files)
                if ok then
                    local wf = io.open(_trustPath, "w")
                    if wf then
                        wf:write(json .. "\n")
                        wf:close()
                    end
                end
            end
        end)

    elseif _fmResult == "legacy" then
        local _checkResult, _failedFile = _checkAll(_manifest)

        if _checkResult == "uninitialized" then
            if _signedManifestConfirms() then
                _seedTrustedFromDisk()
                print("Guardian: no trusted manifest, seeded from signed MANIFEST.json.")
            else
                _blocked = true
                print("Guardian: no trusted manifest and no valid signed MANIFEST.json, blocking.")
                _showGuardianBlock(nil, _hashFile(_corePath))
            end

        elseif _checkResult == "error" then
            print("Guardian: could not hash " .. (_failedFile or "unknown") .. ", skipping check.")

        elseif _checkResult == "mismatch" then
            -- A tracked file differs from the (deploy-written) trusted manifest.
            -- We do NOT reseed on _signedManifestConfirms() here: that check
            -- covers ms_core.lua alone, but _seedTrustedFromDisk() would re-bless
            -- EVERY on-disk file -- so a non-core tamper (lib/ui/bin) would pass
            -- whenever core still matched the shipped signed hash. Legacy mode has
            -- no signed per-file coverage to fall back on, so the safe action is
            -- to block. A genuine signed core+files update arrives through the
            -- install/repair flow with .ms_file_manifest.json restored, landing on
            -- the per-file "ok" path above rather than as a legacy mismatch; a
            -- local edit is fixed by re-running deploy, which re-seeds the manifest.
            _blocked = true
            local _exp = _manifest and _manifest[_failedFile or "ms_core.lua"] or nil
            local _got = _hashFile(_home .. "/.hammerspoon/" .. (_failedFile or "ms_core.lua"))
            _showGuardianBlock(_exp, _got)
            print("Guardian: legacy hash mismatch for " .. (_failedFile or "unknown") .. ", blocking.")
        end -- if _checkResult
    elseif _fmResult == "tampered" then
        _blocked = true
        _showGuardianBlock(nil, nil)
        print("Guardian: per-file manifest signature verification failed, blocking.")

    elseif _fmResult == "mismatch" then
        -- Reached only after the per-file manifest's OWN signature already
        -- verified (_checkFileManifest returns "mismatch" past that gate), so a
        -- file differing from a validly-signed manifest is unambiguous tamper.
        -- A legitimate update ships a fresh matching signed manifest and lands
        -- as "ok", never "mismatch" -- so there is no update to confirm here.
        -- We must NOT fall back to _signedManifestConfirms()/_seedTrustedFromDisk():
        -- that escape validates ms_core.lua ALONE and would then re-bless every
        -- other on-disk file, letting a non-core tamper (lib/ui/bin) pass as long
        -- as core matched a signed hash. Block instead.
        _blocked = true
        local _exp, _got = nil, nil
        if _fmFailedFile then
            local fm = _readFileManifest()
            if fm and fm.files then _exp = fm.files[_fmFailedFile] end
            _got = _hashFile(_home .. "/.hammerspoon/" .. _fmFailedFile)
        end
        _showGuardianBlock(_exp, _got)
        print("Guardian: per-file hash mismatch for " .. (_fmFailedFile or "unknown") .. ", blocking.")
    end

    if not _blocked then
        local _spResult, _spName = _checkSpoons()
        if _spResult == "noledger" then
            _blocked = true
            _showGuardianBlock(nil, nil, _noLedgerSpec(_spName))
            print("Guardian: plugins installed but no plugin ledger, blocking. Re-import them to record.")
        elseif _spResult == "unknown" then
            _blocked = true
            _showGuardianBlock(nil, nil, _unknownSpoonSpec(_spName))
            print("Guardian: unrecognized plugin Spoons/" .. tostring(_spName) .. ", blocking.")
        end
    end
-- END Integrity Check --

    if not _blocked then
        _G._guardianPassed = true
    end

-- Load Core --
    if not _blocked then
        dofile(_corePath)
    end
-- END Load Core --

return _obj
end

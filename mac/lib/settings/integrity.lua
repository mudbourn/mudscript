return function(ms, ctx)
    -- System Integrity --
        local archivePath = ctx.archivePath
        local trustedHashPath = ctx.trustedHashPath

        ms.integrity = {}

        local _integrityFiles = nil
        ms.integrity.trackedFiles = function()
            if _integrityFiles then return _integrityFiles end
            local hsDir = os.getenv("HOME") .. "/.hammerspoon/"
            _integrityFiles = { hsDir .. "ms_core.lua" }
            local spoonDir = hsDir .. "Spoons/"
            local ok, iter, dir_obj = pcall(hs.fs.dir, spoonDir)
            if ok and iter then
                for entry in iter, dir_obj do
                    if entry ~= "." and entry ~= ".." then
                        local init = spoonDir .. entry .. "/init.lua"
                        if hs.fs.attributes(init) then
                            _integrityFiles[#_integrityFiles + 1] = init
                        end
                    end
                end
                dir_obj:close()
            end
            table.sort(_integrityFiles)
            return _integrityFiles
        end

        ms.integrity.hashFile = function(path)
            local escaped = "'" .. path:gsub("'", "'\\''") .. "'"
            local out = hs.execute("shasum -a 256 " .. escaped .. " 2>/dev/null")
            if out and #out >= 64 then return out:sub(1, 64):lower() end
            return nil
        end

        ms.integrity.readTrustedManifest = function()
            local f = io.open(trustedHashPath, "r")
            if not f then return nil end
            local raw = f:read("*all")
            f:close()
            if not raw or raw == "" then return nil end

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
                return next(norm) and norm or nil
            end

            return nil
        end

        ms.integrity.writeTrustedManifest = function(manifest)
            local ok, json = pcall(hs.json.encode, manifest)
            if not ok then
                ms.dev.log({
                    type = "error",
                    event = "hash_seed_failed",
                })
                return false
            end
            local f = io.open(trustedHashPath, "w")
            if f then
                f:write(json .. "\n")
                f:close()
                local n = 0
                for _ in pairs(manifest) do n = n + 1 end
                ms.dev.log({
                    type    = "system",
                    event   = "manifest_seeded",
                    files   = n,
                })
                return true
            end
            ms.dev.log({
                type = "error",
                event = "hash_seed_failed",
            })
            return false
        end

        ms.integrity.readTrustedHash = function()
            local m = ms.integrity.readTrustedManifest()
            return m and m["ms_core.lua"] or nil
        end

        ms.integrity.writeTrustedHash = function(hash)
            return ms.integrity.writeTrustedManifest({ ["ms_core.lua"] = hash })
        end

        ms.integrity.deleteTrustedHash = function()
            return os.remove(trustedHashPath) ~= nil
        end

        local _intCache         = {
            status  = nil,
            details = nil,
            t       = 0,
        }
        local _intHashInProgress = false

        ms.integrity.invalidateCache = function()
            _intCache.t = 0
            ms.dev.log({
                type = "system",
                event = "integrity_cache_invalidated",
            })
        end

        ms.integrity.check = function()
            local now = os.time()
            if _intCache.status ~= nil and (now - _intCache.t) < 60 then
                local d = _intCache.details and _intCache.details["ms_core.lua"]
                return _intCache.status, d and d.cur, d and d.trusted
            end
            if _intHashInProgress then
                local d = _intCache.details and _intCache.details["ms_core.lua"]
                return _intCache.status or "uninitialized", d and d.cur, d and d.trusted
            end

            _intHashInProgress = true
            local files = ms.integrity.trackedFiles()
            local trusted = ms.integrity.readTrustedManifest()
            local details = {}
            local allOk = true
            local anyMismatch = false
            local pending = #files
            local done = false

            if pending == 0 then
                _intHashInProgress = false
                _intCache = {
                    status = "uninitialized",
                    details = {},
                    t = now,
                }
                return "uninitialized"
            end

            for _, absPath in ipairs(files) do
                local rel = absPath:gsub(".*/%.hammerspoon/", "")
                local _t = hs.task.new("/usr/bin/shasum", function(_, out, _)
                    local cur = (out and #out >= 64) and out:sub(1, 64):lower() or nil
                    local tru = trusted and trusted[rel] or nil
                    local fileStatus
                    if not tru then
                        fileStatus = "unknown"
                    elseif cur == tru then
                        fileStatus = "ok"
                    else
                        fileStatus = "mismatch"
                        anyMismatch = true
                        allOk = false
                    end
                    details[rel] = {
                        cur = cur,
                        trusted = tru,
                        status = fileStatus,
                    }

                    pending = pending - 1
                    if pending == 0 and not done then
                        done = true
                        _intHashInProgress = false
                        local status
                        if not trusted then
                            status = "uninitialized"
                        elseif anyMismatch then
                            status = "mismatch"
                        else
                            status = "trusted"
                        end
                        _intCache = {
                            status  = status,
                            details = details,
                            t       = os.time(),
                        }
                        ms.dev.log({
                            type    = "system",
                            event   = "integrity_check",
                            status  = status,
                            files   = #files,
                            matched = not anyMismatch,
                        })
                        if status == "mismatch" then hs.reload() end
                    end
                end, {
                    "-a",
                    "256",
                    absPath,
                })
                if _t then
                    _t:start()
                else
                    details[rel] = {
                        cur = nil,
                        trusted = trusted and trusted[rel] or nil,
                        status = "error",
                    }
                    allOk = false
                    pending = pending - 1
                end
            end

            return _intCache.status or "uninitialized"
        end

        ms.integrity.trustCurrent = function()
            local files = ms.integrity.trackedFiles()
            local manifest = {}
            local failed = false
            for _, absPath in ipairs(files) do
                local hash = ms.integrity.hashFile(absPath)
                if not hash then
                    failed = true
                    break
                end
                local rel = absPath:gsub(".*/%.hammerspoon/", "")
                manifest[rel] = hash
            end
            if failed then
                ms.alert("System integrity: could not hash one or more files.", 4)
                return false
            end
            if ms.integrity.writeTrustedManifest(manifest) then
                ms.integrity.invalidateCache()
                local n = 0
                for _ in pairs(manifest) do n = n + 1 end
                ms.alert("Trusted manifest saved.\n" .. n .. " files sealed.", 4, true)
                return true
            end
            ms.alert("System integrity: could not write trusted manifest.", 4)
            return false
        end


        local function _applyBundleUpdate(bundleDir, timestamp)
            local hsDir = os.getenv("HOME") .. "/.hammerspoon/"

            local topDir = nil
            local dh = io.popen("ls -d '" .. bundleDir .. "'/mudscript-* 2>/dev/null | head -1")
            if dh then topDir = dh:read("*l")
            dh:close() end
            if not topDir or topDir == "" then
                topDir = bundleDir
            end
            if not topDir:match("/$") then topDir = topDir .. "/" end

            -- Wholesale-replaceable install artifacts, mirroring a fresh install
            local replaceList = {
                "ms_core.lua",
                "init.lua",
                "lib",
                "templates",
                "ui",
                "bin",
                "Spoons",
            }
            local templateList = {
                "ms_macros.lua",
                "profiles/Default",
            }

            os.execute("mkdir -p '" .. archivePath .. "'")

            for _, name in ipairs(replaceList) do
                local src = topDir .. name
                local dst = hsDir .. name
                if hs.fs.attributes(src) then
                    if hs.fs.attributes(dst) then
                        local safeName = name:gsub("/", "_")
                        local bak = archivePath .. safeName .. "_" .. timestamp
                            .. (hs.fs.attributes(dst).mode == "directory" and ".d.bak" or ".bak")
                        os.execute("rm -rf '" .. bak .. "'")
                        os.execute("cp -R '" .. dst .. "' '" .. bak .. "'")
                    end
                    os.execute("rm -rf '" .. dst .. "'")
                    os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                end
            end

            local _fmSrc = topDir .. "data/.ms_file_manifest.json"
            local _fmDst = hsDir .. "data/.ms_file_manifest.json"
            if hs.fs.attributes(_fmSrc) then
                os.execute("mkdir -p '" .. hsDir .. "data'")
                os.execute("cp '" .. _fmSrc .. "' '" .. _fmDst .. "'")
            end

            local _mfSrc = topDir .. "MANIFEST.json"
            local _mfDst = hsDir .. "MANIFEST.json"
            if hs.fs.attributes(_mfSrc) then
                os.execute("cp '" .. _mfSrc .. "' '" .. _mfDst .. "'")
            end

            for _, name in ipairs(templateList) do
                local src = topDir .. name
                local dst = hsDir .. name
                if hs.fs.attributes(src) and not hs.fs.attributes(dst) then
                    os.execute("mkdir -p '" .. dst:match("(.+)/[^/]+$") .. "'")
                    os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                end
            end

            return true
        end

        local function _verifySignature(manifest)
            if not manifest.signature or manifest.signature == ""
                or not ms._updatePublicKey
                or ms._updatePublicKey:find("PLACEHOLDER") then
                return true
            end
            local _tmpDir  = archivePath
            local _keyPath = _tmpDir .. "upd_pub.pem"
            local _sigPath = _tmpDir .. "upd_sig.bin"
            local _msgPath = _tmpDir .. "upd_msg.bin"
            os.execute("mkdir -p '" .. _tmpDir .. "'")
            local _keyContent = ms._updatePublicKey
                :gsub("^[%s\n]+", "")
                :gsub("\n[%s]+", "\n")
                :gsub("[%s]+$", "\n")
            local _kf = io.open(_keyPath, "w")
            if _kf then _kf:write(_keyContent)
            _kf:close() end
            local _sf = io.open(_sigPath .. ".b64", "w")
            if _sf then _sf:write(manifest.signature)
            _sf:close() end
            hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
            os.remove(_sigPath .. ".b64")
            local _signTarget = manifest.bundle and manifest.bundle.sha256 or manifest.sha256
            local _mf = io.open(_msgPath, "w")
            if _mf then _mf:write(_signTarget:lower())
            _mf:close() end
            local _out, _ok = hs.execute(
                "openssl dgst -sha256 -verify '" .. _keyPath ..
                "' -signature '" .. _sigPath ..
                "' '" .. _msgPath .. "' 2>&1"
            )
            os.remove(_keyPath)
            os.remove(_sigPath)
            os.remove(_msgPath)
            if not _ok then
                ms.dev.log({
                    type   = "error",
                    event  = "signature_failed",
                    output = tostring(_out),
                })
                ms.alert("Update aborted: signature verification failed.\n" .. tostring(_out), 12)
                return false
            end
            ms.dev.log({
                type = "system",
                event = "signature_verified",
            })
            return true
        end

        -- Version comparison helpers (used by _fetchReleaseInfo and check functions) --
        local function _parseVersion(v)
            local t = {}
            if type(v) == "string" then
                local base = v:match("^[%d%.]+")
                if base then
                    for n in base:gmatch("%d+") do t[#t + 1] = tonumber(n) or 0 end
                end
                t._pre = v:find("%-pre") ~= nil or v:find("%-beta") ~= nil
                    or v:find("%-rc") ~= nil
                local preNum = v:match("%-pre%.(%d+)")
                t._preNum = preNum and tonumber(preNum) or 0
            end
            return t
        end

        local function _remoteIsNewer(localV, remoteV)
            local a, b = _parseVersion(localV), _parseVersion(remoteV)
            local len = math.max(#a, #b)
            for i = 1, len do
                local la, ra = a[i] or 0, b[i] or 0
                if ra > la then return true  end
                if ra < la then return false end
            end
            if a._pre and not b._pre then return true  end
            if not a._pre and b._pre then return false end
            if a._pre and b._pre then
                return (b._preNum or 0) > (a._preNum or 0)
            end
            return false
        end
        -- END Version comparison helpers --

        -- _fetchReleaseInfo [GitHub Releases API helper] --
        local function _fetchReleaseInfo(channel, callback)
            local repo = ms._testingRepo or "mudbourn/mudscript"
            local apiURL
            if channel == "stable" then
                apiURL = "https://api.github.com/repos/" .. repo .. "/releases/latest"
            else
                apiURL = "https://api.github.com/repos/" .. repo .. "/releases?per_page=5"
            end
            hs.http.asyncGet(apiURL, {
                ["Accept"] = "application/vnd.github+json",
            }, function(code, body, _)
                if code ~= 200 or not body then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_fetch_failed",
                        channel = channel,
                        code    = code,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local ok, data = pcall(hs.json.decode, body)
                if not ok or not data then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local release
                if channel == "stable" then
                    release = data
                else
                    if type(data) ~= "table" or #data == 0 then
                        ms.dev.log({
                            type    = "error",
                            event   = "release_parse_failed",
                            channel = channel,
                            reason  = "empty_array",
                        })
                        if callback then pcall(callback, nil) end
                        return
                    end
                    release = data[1]
                    local bestIdx = 1
                    for i = 2, #data do
                        if _remoteIsNewer(
                            data[bestIdx].tag_name or "",
                            data[i].tag_name or ""
                        ) then
                            bestIdx = i
                        end
                    end
                    release = data[bestIdx]
                end
                if not release or not release.tag_name then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                        reason  = "no_tag",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local downloadUrl
                local assets = release.assets or {}
                for _, asset in ipairs(assets) do
                    if asset.name and asset.name:match("^mudscript%-macos%-.*%.zip$") then
                        downloadUrl = asset.browser_download_url
                        break
                    end
                end
                if not downloadUrl then
                    ms.dev.log({
                        type    = "error",
                        event   = "release_parse_failed",
                        channel = channel,
                        reason  = "no_asset",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local tagName = release.tag_name
                local version = tagName:gsub("^v", "")
                if callback then pcall(callback, {
                    version     = version,
                    downloadUrl = downloadUrl,
                    tagName     = tagName,
                }) end
            end)
        end
        -- END _fetchReleaseInfo --

        -- _fetchArtifactInfo [GitHub Actions artifact helper] --
        local function _fetchArtifactInfo(callback)
            local repo = ms._testingRepo or "mudbourn/mudscript"
            local workflow = ms._testingWorkflow or "testing"
            local token = ms._githubToken
            if not token or token == "" then
                local tokenPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token"
                local f = io.open(tokenPath, "r")
                if f then token = f:read("*l")
                f:close() end
                if token and token ~= "" then ms._githubToken = token end
            end
            if not token or token == "" then
                ms.dev.log({
                    type = "error",
                    event = "artifact_fetch_failed",
                    reason = "no_token",
                })
                if callback then pcall(callback, nil) end
                return
            end

            local baseVersion = "0.0.0"
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then
                        baseVersion = lm.version:gsub("%-pre[%.%-]%d+$", "")
                    end
                end
            end

            local runsURL = "https://api.github.com/repos/" .. repo
                .. "/actions/workflows/" .. workflow .. ".yml/runs?per_page=1&status=completed"
            local headers = {
                ["Accept"] = "application/vnd.github+json",
                ["Authorization"] = "Bearer " .. token,
            }
            hs.http.asyncGet(runsURL, headers, function(code, body, _)
                if code ~= 200 or not body then
                    ms.dev.log({
                        type = "error",
                        event = "artifact_fetch_failed",
                        reason = "runs_http",
                        code = code,
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local ok, data = pcall(hs.json.decode, body)
                if not ok or not data or not data.workflow_runs or #data.workflow_runs == 0 then
                    if callback then pcall(callback, nil) end
                    return
                end
                local run = data.workflow_runs[1]
                local runId = run.id
                local runNumber = run.run_number

                local artURL = "https://api.github.com/repos/" .. repo
                    .. "/actions/runs/" .. runId .. "/artifacts"
                hs.http.asyncGet(artURL, headers, function(code2, body2, _)
                    if code2 ~= 200 or not body2 then
                        ms.dev.log({
                            type = "error",
                            event = "artifact_fetch_failed",
                            reason = "artifacts_http",
                            code = code2,
                        })
                        if callback then pcall(callback, nil) end
                        return
                    end
                    local ok2, artData = pcall(hs.json.decode, body2)
                    if not ok2 or not artData or not artData.artifacts then
                        if callback then pcall(callback, nil) end
                        return
                    end
                    for _, art in ipairs(artData.artifacts) do
                        if art.name and art.name:match("macos") then
                            local downloadURL = "https://api.github.com/repos/" .. repo
                                .. "/actions/artifacts/" .. art.id .. "/zip"
                            ms.dev.log({
                                type = "system",
                                event = "artifact_found",
                                name = art.name,
                                run = runNumber,
                            })
                            if callback then
                                pcall(callback, {
                                    version = baseVersion .. "-pre." .. runNumber,
                                    downloadUrl = downloadURL,
                                    headers = headers,
                                    format = "zip",
                                })
                            end
                            return
                        end
                    end
                    for _, art in ipairs(artData.artifacts) do
                        if art.name then
                            local downloadURL = "https://api.github.com/repos/" .. repo
                                .. "/actions/artifacts/" .. art.id .. "/zip"
                            if callback then
                                pcall(callback, {
                                    version = baseVersion .. "-pre." .. runNumber,
                                    downloadUrl = downloadURL,
                                    headers = headers,
                                    format = "zip",
                                })
                            end
                            return
                        end
                    end
                    ms.dev.log({
                        type = "error",
                        event = "artifact_fetch_failed",
                        reason = "no_artifact",
                    })
                    if callback then pcall(callback, nil) end
                end)
            end)
        end
        -- END _fetchArtifactInfo --

        -- Update [stable channel] --
        ms.integrity.update = function()
            ms.dev.log({
                type    = "system",
                event   = "update_start",
                channel = "stable",
            })
            ms.alert("Checking for stable update\xe2\x80\xa6", 4, true)
            _fetchReleaseInfo("stable", function(info)
                if not info then
                    ms.dev.log({
                        type   = "error",
                        event  = "update_failed",
                        reason = "release_fetch",
                    })
                    ms.alert("Update failed: could not fetch release info.", 5)
                    return
                end
                local newVersion = info.version
                local bundleURL  = info.downloadUrl
                ms.alert("Downloading v" .. newVersion .. " bundle\xe2\x80\xa6", 4, true)
                ms.dev.log({
                    type    = "system",
                    event   = "update_download_start",
                    version = newVersion,
                    format  = "bundle",
                })
                hs.http.asyncGet(bundleURL, nil, function(fCode, fBody, _)
                    if fCode ~= 200 or not fBody then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "download_http",
                            code    = fCode,
                            version = newVersion,
                        })
                        ms.alert("Update failed: bundle download returned " .. tostring(fCode) .. ".", 5)
                        return
                    end
                    os.execute("mkdir -p '" .. archivePath .. "'")
                    local isZip = bundleURL:match("%.zip$")
                    local tmpArchive = archivePath .. (isZip and "ms_bundle_update.zip" or "ms_bundle_update.tar.gz")
                    local tmpF = io.open(tmpArchive, "wb")
                    if not tmpF then
                        ms.alert("Update failed: could not write temp file.", 4)
                        return
                    end
                    tmpF:write(fBody)
                    tmpF:close()
                    local tmpExtract = archivePath .. "ms_bundle_extract/"
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    os.execute("mkdir -p '" .. tmpExtract .. "'")
                    local _, extractOk
                    if isZip then
                        _, extractOk = hs.execute("unzip -o '" .. tmpArchive .. "' -d '" .. tmpExtract .. "' 2>&1")
                    else
                        _, extractOk = hs.execute("tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1")
                    end
                    os.remove(tmpArchive)
                    if not extractOk then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "extract_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not extract bundle.", 5)
                        return
                    end
                    local manifestPath = tmpExtract .. "MANIFEST.json"
                    local topDir = nil
                    local dh = io.popen("ls -d '" .. tmpExtract .. "'/mudscript-* 2>/dev/null | head -1")
                    if dh then topDir = dh:read("*l")
                    dh:close() end
                    if topDir and topDir ~= "" then
                        if not topDir:match("/$") then topDir = topDir .. "/" end
                        local altManifest = topDir .. "MANIFEST.json"
                        if hs.fs.attributes(altManifest) then manifestPath = altManifest end
                    end
                    local manifest = nil
                    local mf = io.open(manifestPath, "r")
                    if mf then
                        local ok, m = pcall(hs.json.decode, mf:read("*all"))
                        mf:close()
                        if ok then manifest = m end
                    end
                    if manifest and not _verifySignature(manifest) then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        return
                    end
                    local timestamp = os.date("%Y-%m-%d_%H%M")
                    ms._updateInProgress = true
                    os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                    local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                    if _sp then _sp:close() end
                    local ok = _applyBundleUpdate(tmpExtract, timestamp)
                    ms._updateInProgress = false
                    os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if not ok then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "apply_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not apply bundle.", 5)
                        return
                    end
                    ms.dev.log({
                        type    = "system",
                        event   = "update_applied",
                        version = newVersion,
                        format  = "bundle",
                    })
                    ms.integrity.trustCurrent()
                    ms.integrity.invalidateCache()
                    ms.alert("Updated to v" .. newVersion .. ".\\nReloading in 3 seconds\\xe2\\x80\\xa6", 5, true)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end)
            end)
        end
        -- END Update --

        -- Update Beta [testing channel] --
        ms.integrity.updateBeta = function()
            ms.dev.log({
                type    = "system",
                event   = "update_start",
                channel = "testing",
                source  = ms._testingSource or "release",
            })
            ms.alert("Checking for testing update\\xe2\\x80\\xa6", 4, true)

            local fetchFn = (ms._testingSource == "artifact") and _fetchArtifactInfo
                or function(cb) _fetchReleaseInfo("testing", cb) end

            fetchFn(function(info)
                if not info then
                    ms.dev.log({
                        type   = "error",
                        event  = "update_failed",
                        reason = (ms._testingSource == "artifact") and "artifact_fetch" or "release_fetch",
                    })
                    if ms._testingSource == "artifact" then
                        if not ms._githubToken or ms._githubToken == "" then
                            ms.alert("Update failed: no GitHub token configured.\\nSet one in Settings \\xe2\\x86\\x92 Developer.", 6)
                        else
                            ms.alert("Update failed: could not fetch artifact.\\nCheck your GitHub token has actions:read permission.", 6)
                        end
                    else
                        ms.alert("Update failed: could not fetch testing release info.", 5)
                    end
                    return
                end
                local newVersion = info.version

                local _localVer
                do
                    local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                    if lf then
                        local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                        lf:close()
                        if ok and lm and lm.version then _localVer = lm.version end
                    end
                end
                if _localVer and not _remoteIsNewer(_localVer, newVersion) then
                    ms.alert("Already on the latest testing version (v" .. _localVer .. ").", 4, true)
                    return
                end

                local bundleURL  = info.downloadUrl
                ms.alert("Downloading v" .. newVersion .. " bundle\xe2\x80\xa6", 4, true)
                ms.dev.log({
                    type    = "system",
                    event   = "update_download_start",
                    version = newVersion,
                    format  = "bundle",
                })
                hs.http.asyncGet(bundleURL, info.headers or nil, function(fCode, fBody, _)
                    if fCode ~= 200 or not fBody then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "download_http",
                            code    = fCode,
                            version = newVersion,
                        })
                        ms.alert("Update failed: bundle download returned " .. tostring(fCode) .. ".", 5)
                        return
                    end
                    os.execute("mkdir -p '" .. archivePath .. "'")
                    local isZip = bundleURL:match("%.zip$")
                    local tmpArchive = archivePath .. (isZip and "ms_bundle_update.zip" or "ms_bundle_update.tar.gz")
                    local tmpF = io.open(tmpArchive, "wb")
                    if not tmpF then
                        ms.alert("Update failed: could not write temp file.", 4)
                        return
                    end
                    tmpF:write(fBody)
                    tmpF:close()
                    local tmpExtract = archivePath .. "ms_bundle_extract/"
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    os.execute("mkdir -p '" .. tmpExtract .. "'")
                    local _, extractOk
                    if isZip then
                        _, extractOk = hs.execute("unzip -o '" .. tmpArchive .. "' -d '" .. tmpExtract .. "' 2>&1")
                    else
                        _, extractOk = hs.execute("tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1")
                    end
                    os.remove(tmpArchive)
                    if not extractOk then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "extract_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not extract bundle.", 5)
                        return
                    end
                    local manifestPath = tmpExtract .. "MANIFEST.json"
                    local topDir = nil
                    local dh = io.popen("ls -d '" .. tmpExtract .. "'/mudscript-* 2>/dev/null | head -1")
                    if dh then topDir = dh:read("*l")
                    dh:close() end
                    if topDir and topDir ~= "" then
                        if not topDir:match("/$") then topDir = topDir .. "/" end
                        local altManifest = topDir .. "MANIFEST.json"
                        if hs.fs.attributes(altManifest) then manifestPath = altManifest end
                    end
                    local manifest = nil
                    local mf = io.open(manifestPath, "r")
                    if mf then
                        local ok, m = pcall(hs.json.decode, mf:read("*all"))
                        mf:close()
                        if ok then manifest = m end
                    end
                    if manifest and not _verifySignature(manifest) then
                        os.execute("rm -rf '" .. tmpExtract .. "'")
                        return
                    end
                    local timestamp = os.date("%Y-%m-%d_%H%M")
                    ms._updateInProgress = true
                    os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                    local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                    if _sp then _sp:close() end
                    local ok = _applyBundleUpdate(tmpExtract, timestamp)
                    ms._updateInProgress = false
                    os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                    os.execute("rm -rf '" .. tmpExtract .. "'")
                    if not ok then
                        ms.dev.log({
                            type    = "error",
                            event   = "update_failed",
                            reason  = "apply_failed",
                            version = newVersion,
                        })
                        ms.alert("Update failed: could not apply bundle.", 5)
                        return
                    end
                    ms.dev.log({
                        type    = "system",
                        event   = "update_applied",
                        version = newVersion,
                        format  = "bundle",
                    })
                    ms.integrity.trustCurrent()
                    ms.integrity.invalidateCache()
                    ms.alert("Updated to v" .. newVersion .. ".\\nReloading in 3 seconds\\xe2\\x80\\xa6", 5, true)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end)
            end)
        end
        -- END Update Beta --

        -- Check For Update [stable channel] --
        ms.integrity.checkForUpdate = function(callback)
            local localVersion
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then localVersion = lm.version end
                end
            end
            _fetchReleaseInfo("stable", function(info)
                if not info then
                    ms.dev.log({
                        type    = "error",
                        event   = "update_check_failed",
                        channel = "stable",
                    })
                    if callback then pcall(callback, nil) end
                    return
                end
                local remoteVersion = info.version
                if _remoteIsNewer(localVersion, remoteVersion) then
                    ms.dev.log({
                        type     = "system",
                        event    = "update_available",
                        local_v  = localVersion,
                        remote_v = remoteVersion,
                        channel  = "stable",
                    })
                    if callback then
                        pcall(callback, {
                            version = remoteVersion or "?",
                            sha256  = info.sha256,
                        })
                    end
                    return
                end
                if callback then pcall(callback, nil) end
            end)
        end
        -- END Check For Update --

        -- Check For Update Beta [testing channel] --
        ms.integrity.checkForUpdateBeta = function(callback)
            local localVersion
            do
                local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                if lf then
                    local ok, lm = pcall(hs.json.decode, lf:read("*all"))
                    lf:close()
                    if ok and lm and lm.version then localVersion = lm.version end
                end
            end
            _fetchReleaseInfo("testing", function(info)
                if not info then
                    if callback then pcall(callback, nil) end
                    return
                end
                local remoteVersion = info.version
                if _remoteIsNewer(localVersion, remoteVersion) then
                    ms.dev.log({
                        type     = "system",
                        event    = "update_available",
                        local_v  = localVersion,
                        remote_v = remoteVersion,
                        channel  = "testing",
                    })
                    if callback then
                        pcall(callback, {
                            version = remoteVersion or "?",
                            sha256  = info.sha256,
                        })
                    end
                else
                    if callback then pcall(callback, nil) end
                end
            end)
        end
        -- END Check For Update Beta --

        -- Check For Content Updates [installed packages & plugins] --
        ms.integrity.checkContentUpdates = function(callback)
            local function scan()
                local installed = {}
                if ms.package and ms.package.listPlugins then
                    local okP, plugins = pcall(ms.package.listPlugins)
                    if okP and type(plugins) == "table" then
                        for _, p in ipairs(plugins) do
                            if p.id and type(p.version) == "string" then
                                installed[p.id] = {
                                    version = p.version,
                                    type    = "plugin",
                                    name    = p.name or p.id,
                                }
                            end
                        end
                    end
                end
                if ms.package and ms.package.listContent then
                    local okC, content = pcall(ms.package.listContent)
                    if okC and type(content) == "table" then
                        for id, rec in pairs(content) do
                            if installed[id] == nil and type(rec) == "table"
                                and type(rec.version) == "string" then
                                installed[id] = {
                                    version = rec.version,
                                    type    = rec.type or "content",
                                    name    = rec.name or id,
                                }
                            end
                        end
                    end
                end
                local entries = (ms.registry and ms.registry.list)
                    and ms.registry.list({}) or {}
                local out = {}
                for _, e in ipairs(entries) do
                    local inst = e.id and installed[e.id]
                    if inst and type(e.version) == "string"
                        and _remoteIsNewer(inst.version, e.version) then
                        out[#out + 1] = {
                            id   = e.id,
                            name = e.name or inst.name or e.id,
                            type = e.type or inst.type,
                            from = inst.version,
                            to   = e.version,
                        }
                    end
                end
                return out
            end
            if ms.registry and ms.registry.refresh then
                ms.registry.refresh({ force = true }, function()
                    if callback then pcall(callback, scan()) end
                end)
            else
                if callback then pcall(callback, scan()) end
            end
        end
        -- END Check For Content Updates --
    -- END System Integrity --

    -- ms.showGuardian --
        ms.showGuardian = function(trusted, current, spec)
            trusted = trusted or ("a3f8" .. string.rep("0", 12))
            current = current or ("9c1e" .. string.rep("f", 12))
            local _home = os.getenv("HOME")
            local _htmlPath = _home .. "/.hammerspoon/ui/ms_guardian.html"
            local _baseURL  = "file://" .. _home .. "/.hammerspoon/ui/"
            local _uc = hs.webview.usercontent.new("guardianPreview")
            local _panel = nil
            local _pos   = nil
            _uc:setCallback(function(msg)
                local body = msg.body
                if body == "keepBlocked" or body == "confirmDelete" then
                    pcall(function() if _panel then _panel:delete() end end)
                else
                    local ok, data = pcall(hs.json.decode, body)
                    if ok and data and data.action == "move" and _pos then
                        _pos.x = _pos.x + (data.dx or 0)
                        _pos.y = _pos.y + (data.dy or 0)
                        pcall(function() _panel:frame(_pos) end)
                    end
                end
            end)
            local sf = hs.screen.mainScreen():frame()
            local w, h = 480, (spec and spec.height) or 360
            local x = sf.x + math.floor((sf.w - w) / 2)
            local y = sf.y + math.floor((sf.h - h) / 2)
            _pos   = {
                x = x,
                y = y,
                w = w,
                h = h,
            }
            _panel = hs.webview.new(_pos, {}, _uc)
            if not _panel then return end
            pcall(function() _panel:windowStyle(0) end)
            pcall(function() _panel:level((hs.canvas.windowLevels.screenSaver or 1000) + 1) end)
            pcall(function() _panel:shadow(true) end)
            if ms and ms.theme and ms.theme.applyWindowRadius then ms.theme.applyWindowRadius(_panel) end
            if ms and ms.theme and ms.theme.onChanged then
                ms.theme.onChanged(function()
                    if ms and ms.theme and ms.theme._pushWindowRadius then ms.theme._pushWindowRadius(_panel) end
                end)
            end
            local f = io.open(_htmlPath, "r")
            if not f then return end
            _panel:html(f:read("*all"), _baseURL)
            f:close()
            ms.safeShow(_panel)
            pcall(function() _panel:bringToFront(true) end)
            local _errSound = (not ms._customThemeDisabled and ms.sounds and ms.sounds["a_Error"])
                or (ms.sounds and ms.sounds["d_Error"])
            if _errSound then pcall(function() ms.sound(_errSound) end) end
            _panel:navigationCallback(function()
                pcall(function()
                    local t = trusted:sub(1, 16) .. "\xe2\x80\xa6"
                    local c = current:sub(1, 16)  .. "\xe2\x80\xa6"
                    _panel:evaluateJavaScript(
                        "setHashes('" .. t .. "', '" .. c .. "')"
                    )
                    if spec then
                        local sj = hs.json.encode(spec)
                        if sj then
                            _panel:evaluateJavaScript("setFailure(" .. sj .. ")")
                        end
                    end
                    _panel:evaluateJavaScript("setPreviewMode()")
                    if not ms._customThemeDisabled then
                        local tj = hs.json.encode(ms._theme or {})
                        if tj then
                            _panel:evaluateJavaScript("applyTheme(" .. tj .. ")")
                        end
                    end
                end)
            end)
        end

        -- Swap a Mouse 3+ trigger for its declared fallback key in trackpad mode
        local TRACKPAD_MAX_BUTTON = 2
        local function trackpadFallback(bind, rootId)
            if not ms.trackpadMode or type(bind) ~= "table" then return bind end
            if bind.type ~= "mouse" then return bind end
            local n = tonumber(bind.button)
            if not (n and n > TRACKPAD_MAX_BUTTON) then return bind end
            local rootDef = ms.registry._defs and ms.registry._defs[rootId]
            local fb = rootDef and rootDef.trackpad
            if type(fb) ~= "table" or not fb.key then return bind end
            -- Keep the resolved bind's own modifiers unless the fallback overrides them
            return { type = "key", key = fb.key, mods = fb.mods or bind.mods or {} }
        end

        ms.effectiveBind = function(id)
            local def = ms.registry._defs and ms.registry._defs[id]
            local raw = ms.bindConfig[id] or (def and def.default)
            local resolved, rootId = raw, id
            if raw and type(raw) == "table" and raw.type and ms.registry._defs[raw.type] then
                local visited = {}
                local accum = {}
                local function addMods(mods)
                    for _, m in ipairs(mods or {}) do
                        local dup = false
                        for _, e in ipairs(accum) do
                            if e == m then dup = true
                            break end
                        end
                        if not dup then accum[#accum+1] = m end
                    end
                end
                addMods(raw.mods)
                local current = raw
                while current and type(current) == "table" and current.type
                    and ms.registry._defs[current.type] and not visited[current.type] do
                    visited[current.type] = true
                    rootId = current.type
                    local parentDef = ms.registry._defs[current.type]
                    local parentBind = ms.bindConfig[current.type] or (parentDef and parentDef.default)
                    if parentBind and type(parentBind) == "table" and parentBind.type
                        and not ms.registry._defs[parentBind.type] then
                        addMods(parentBind.mods)
                        resolved = {
                            type = parentBind.type,
                            key = parentBind.key,
                                 button = parentBind.button,
                                 direction = parentBind.direction,
                                 mods = accum }
                        break
                    end
                    addMods(parentBind and parentBind.mods)
                    current = parentBind
                end
            end
            return trackpadFallback(resolved, rootId)
        end
    -- END ms.showGuardian --
end

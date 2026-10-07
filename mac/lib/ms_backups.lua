return function(ms)
    local B = {}

    -- State --
        local _root = ms._backupRoot
        local _timer = nil
        local _busy = false
        local _tasks = {}
        local _bootTimer = nil
        local _pending = {}
        local _made = {}
        local _subs = {
            auto = true,
            updates = true,
            settings = true,
            logs = true,
            tmp = true,
        }
    -- END State --

    -- Helpers --
        local function sq(s)
            return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
        end

        local function dir(sub)
            local path = _root
            if sub and _subs[sub] then path = _root .. sub .. "/" end
            if not _made[path] then
                if not hs.fs.attributes(path) then os.execute("mkdir -p " .. sq(path)) end
                _made[path] = true
            end
            return path
        end

        local function indexPath()
            return dir("auto") .. "index.json"
        end

        local function canon(v)
            if type(v) ~= "table" then return hs.json.encode({ v }) end
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            local parts = {}
            for _, k in ipairs(keys) do
                local val = v[k]
                local enc
                if type(val) == "table" then enc = canon(val) else enc = hs.json.encode({ val }) end
                parts[#parts + 1] = tostring(k) .. "=" .. enc
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end

        local function settingsDigest(path)
            local f = io.open(path, "rb")
            if not f then return "" end
            local raw = f:read("*all")
            f:close()
            local ok, data = pcall(hs.json.decode, raw)
            if not ok or type(data) ~= "table" then return hs.hash.SHA256(raw) end
            data.shell = nil
            return hs.hash.SHA256(canon(data))
        end

        local function readIndex()
            local f = io.open(indexPath(), "r")
            if not f then return {} end
            local raw = f:read("*all")
            f:close()
            local ok, data = pcall(hs.json.decode, raw)
            if not ok or type(data) ~= "table" then return {} end
            return data
        end

        local function writeIndex(list)
            local f = io.open(indexPath(), "w")
            if not f then return false end
            f:write(hs.json.encode(list, true))
            f:close()
            return true
        end

        local function newestFirst(list)
            table.sort(list, function(a, b)
                if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
                return tostring(a.id) > tostring(b.id)
            end)
            return list
        end

        local function intervalSeconds()
            local hours = tonumber(ms._backupIntervalHours) or 12
            return hours * 3600
        end

        local function runTask(args, onDone)
            local task
            task = hs.task.new("/bin/sh", function(code, out, err)
                _tasks[task] = nil
                onDone(code, out or "", err or "")
            end, args)
            _tasks[task] = true
            if not task:start() then
                _tasks[task] = nil
                onDone(-1, "", "start failed")
            end
        end

        local function validId(id)
            return type(id) == "string" and id:match("^%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d[_%d]*$") ~= nil
        end

        local function push()
            if not (ms.shell and ms.shell.eval) then return end
            local ok, json = pcall(hs.json.encode, {
                items = B.list(),
                dir = _root,
                busy = _busy,
            })
            if not ok then return end
            pcall(ms.shell.eval, "if(window.shellReceive)shellReceive('backups','list'," .. json .. ")")
        end
    -- END Helpers --

    -- Index --
        function B.dir(sub)
            return dir(sub)
        end

        function B.list()
            local auto = dir("auto")
            local stored = readIndex()
            local out = {}
            local known = {}
            for _, e in ipairs(stored) do
                if type(e) == "table" and validId(e.id) and hs.fs.attributes(auto .. e.id .. ".mspkg") then
                    e.file = e.id .. ".mspkg"
                    e.size = hs.fs.attributes(auto .. e.file, "size") or e.size or 0
                    out[#out + 1] = e
                    known[e.id] = true
                end
            end
            for name in hs.fs.dir(auto) do
                local id = name:match("^(.+)%.mspkg$")
                if id and validId(id) and not known[id] then
                    local mod = hs.fs.attributes(auto .. name, "modification") or os.time()
                    out[#out + 1] = {
                        id = id,
                        file = name,
                        time = mod,
                        lastChecked = mod,
                        profile = "",
                        reason = "unknown",
                        size = hs.fs.attributes(auto .. name, "size") or 0,
                    }
                end
            end
            return newestFirst(out)
        end

        function B.prune(protectId, protectId2)
            local auto = dir("auto")
            local keep = tonumber(ms._backupKeep) or 10
            local list = B.list()
            local kept = {}
            for i, e in ipairs(list) do
                if i <= keep or e.id == protectId or e.id == protectId2 then
                    kept[#kept + 1] = e
                else
                    os.remove(auto .. e.file)
                end
            end
            writeIndex(kept)
            return #list - #kept
        end

        function B.delete(id)
            if not validId(id) then return false end
            os.remove(dir("auto") .. id .. ".mspkg")
            local kept = {}
            for _, e in ipairs(B.list()) do
                if e.id ~= id then kept[#kept + 1] = e end
            end
            writeIndex(kept)
            push()
            return true
        end

        function B.openFolder()
            hs.open(dir())
        end
    -- END Index --

    -- Snapshot --
        function B.snapshot(reason, onDone, protectId)
            onDone = onDone or function() end
            reason = reason or "auto"
            if _busy then
                _pending[#_pending + 1] = {
                    reason = reason,
                    onDone = onDone,
                    protectId = protectId,
                }
                return
            end
            if not ms.stageProfilePkg then
                onDone(false, "unavailable")
                return
            end
            _busy = true
            local function finish(ok, info)
                _busy = false
                push()
                onDone(ok, info)
                local nextJob = table.remove(_pending, 1)
                if nextJob then B.snapshot(nextJob.reason, nextJob.onDone, nextJob.protectId) end
            end
            pcall(ms.saveSettings)
            local stage = dir("tmp") .. "snap_stage/"
            local staged, counts = ms.stageProfilePkg(stage)
            if not staged then
                finish(false, counts)
                return
            end
            local hashCmd = 'cd "$1" && find . -type f ! -path ./ms_settings.json -print0 | LC_ALL=C sort -z | xargs -0 /usr/bin/shasum -a 256 | /usr/bin/shasum -a 256'
            runTask({
                "-c",
                hashCmd,
                "sh",
                stage,
            }, function(code, out)
                local hash = out:match("^(%x+)")
                if hash then hash = hs.hash.SHA256(hash .. settingsDigest(stage .. "ms_settings.json")) end
                if code ~= 0 or not hash then
                    os.execute("rm -rf " .. sq(stage))
                    finish(false, "hash failed")
                    return
                end
                local list = B.list()
                local auto = dir("auto")
                local newest = list[1]
                if newest and newest.hash == hash then
                    newest.lastChecked = os.time()
                    writeIndex(list)
                    os.execute("rm -rf " .. sq(stage))
                    if reason == "manual" and ms.alert then
                        ms.alert("No changes since " .. os.date("%Y-%m-%d %H:%M", newest.time or os.time()), 4, true)
                    end
                    finish(true, {
                        skipped = true,
                        entry = newest,
                    })
                    return
                end
                local now = os.time()
                local id = os.date("%Y-%m-%d_%H%M%S", now)
                local n = 1
                local base = id
                while hs.fs.attributes(auto .. id .. ".mspkg") do
                    n = n + 1
                    id = base .. "_" .. n
                end
                local outPath = auto .. id .. ".mspkg"
                runTask({
                    "-c",
                    'cd "$1" && /usr/bin/zip -qr "$2" .',
                    "sh",
                    stage,
                    outPath,
                }, function(zcode)
                    os.execute("rm -rf " .. sq(stage))
                    if zcode ~= 0 or not hs.fs.attributes(outPath) then
                        os.remove(outPath)
                        finish(false, "zip failed")
                        return
                    end
                    local entry = {
                        id = id,
                        file = id .. ".mspkg",
                        time = now,
                        lastChecked = now,
                        profile = ms.activeProfile and ms.activeProfile() or "",
                        reason = reason,
                        size = hs.fs.attributes(outPath, "size") or 0,
                        hash = hash,
                    }
                    local all = B.list()
                    local found = false
                    for _, e in ipairs(all) do
                        if e.id == id then
                            found = true
                            break
                        end
                    end
                    if not found then all[#all + 1] = entry end
                    writeIndex(all)
                    B.prune(id, protectId)
                    finish(true, {
                        skipped = false,
                        entry = entry,
                    })
                end)
            end)
        end
    -- END Snapshot --

    -- Restore --
        local function placeNewOnly(srcDir, dstDir)
            if not hs.fs.attributes(srcDir) then return end
            if not hs.fs.attributes(dstDir) then os.execute("mkdir -p " .. sq(dstDir)) end
            for file in hs.fs.dir(srcDir) do
                if file ~= "." and file ~= ".." and not hs.fs.attributes(dstDir .. file) then
                    hs.execute("/bin/cp " .. sq(srcDir .. file) .. " " .. sq(dstDir .. file))
                end
            end
        end

        local function applyRestore(entry, base)
            for _, cf in ipairs(ms.profilePkgFiles()) do
                local src = base .. cf.name
                if hs.fs.attributes(src) then
                    local _, cpOk = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(cf.live))
                    if not cpOk then
                        ms.alert("Restore: could not write " .. cf.name .. ".", 5)
                    end
                end
            end
            placeNewOnly(base .. "sounds/active/", SoundActiveDir)
            placeNewOnly(base .. "sounds/defaults/", SoundDefaultsDir)
            placeNewOnly(base .. "sounds/macro/", SoundMacroDir)
            placeNewOnly(base .. "fonts/", hs.configdir .. "/ui/fonts/")
            if ms.loadSettings then pcall(ms.loadSettings) end
            if ms.hotswapLive then ms.hotswapLive() end
            if ms.package and ms.package.reconcileActive then
                for _, k in ipairs({
                    "theme",
                    "sound",
                    "macro",
                }) do
                    pcall(ms.package.reconcileActive, k)
                end
            end
            local name = entry.profile or ""
            if name ~= "" and name ~= "unnamed" and ms.package and ms.package.setActiveProfile then
                pcall(ms.package.setActiveProfile, name)
            end
            ms._profilesDirty = true
            B.schedule()
            if ms.playSlot then ms.playSlot("update") end
            ms.alert("Restored backup from " .. os.date("%Y-%m-%d %H:%M", entry.time or os.time()) .. ".", 4, true)
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
            end
            if ms.shell and ms.shell.eval then
                pcall(ms.shell.eval, "if(window.shellReceive)shellReceive('macros','profileSwitched',{})")
            end
        end

        local function runRestore(entry)
            local pkg = dir("auto") .. entry.file
            local work = dir("tmp") .. "restore/"
            os.execute("rm -rf " .. sq(work))
            os.execute("mkdir -p " .. sq(work))
            local _, unzipOk = hs.execute("/usr/bin/unzip -o " .. sq(pkg) .. " -d " .. sq(work) .. " 2>/dev/null")
            local macroSrc = work .. "ms_macros.lua"
            local f = unzipOk and hs.fs.attributes(work .. "ms_settings.json") and io.open(macroSrc, "rb")
            if not f then
                os.execute("rm -rf " .. sq(work))
                ms.alert("Restore failed: backup is unreadable or incomplete.", 5)
                return
            end
            local content = f:read("*all")
            f:close()
            local errs = ms.auditMacros(content)
            if #errs > 0 then
                os.execute("rm -rf " .. sq(work))
                ms.alert("Restore rejected, security scan failed:\n  - " .. table.concat(errs, "\n  - "), 8)
                return
            end
            B.snapshot("pre-restore", function(ok, info)
                if not ok then
                    os.execute("rm -rf " .. sq(work))
                    ms.alert("Restore cancelled: could not back up the current setup (" .. tostring(info) .. ").", 6)
                    return
                end
                applyRestore(entry, work)
                os.execute("rm -rf " .. sq(work))
                push()
            end, entry.id)
        end

        function B.restore(id)
            if not validId(id) then return end
            local entry
            for _, e in ipairs(B.list()) do
                if e.id == id then
                    entry = e
                    break
                end
            end
            if not entry then
                ms.alert("Backup not found.", 4)
                return
            end
            if not (ms.ui and ms.ui.modal) then return end
            ms.ui.modal({
                title = "Restore Backup",
                msg = "Restore the setup from " .. os.date("%Y-%m-%d %H:%M", entry.time or os.time())
                    .. "?\n\nYour current setup is backed up first, then replaced.",
                confirm = "Restore",
                cancel = "Cancel",
            }, function(r)
                if r and r.confirmed then runRestore(entry) end
            end)
        end
    -- END Restore --

    -- Schedule --
        function B.schedule()
            if _timer then
                _timer:stop()
                _timer = nil
            end
            local secs = intervalSeconds()
            if secs <= 0 then return end
            _timer = hs.timer.doEvery(secs, function()
                B.snapshot("auto")
            end)
        end

        function B.bootCheck()
            if _bootTimer then _bootTimer:stop() end
            _bootTimer = hs.timer.doAfter(45, function()
                _bootTimer = nil
                local secs = intervalSeconds()
                if secs <= 0 then return end
                local newest = B.list()[1]
                if not newest or os.time() - (newest.lastChecked or newest.time or 0) >= secs then
                    B.snapshot("auto")
                end
            end)
        end
    -- END Schedule --

    ms.backups = B
    return B
end

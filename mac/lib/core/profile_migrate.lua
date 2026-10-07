return function(ms)
    -- Paths --
        local hsDir = os.getenv("HOME") .. "/.hammerspoon"
        local rootDir = hsDir .. "/profiles"
        local stageDir = hsDir .. "/profiles.migrating"
        local backupRoot = hsDir .. "/backups"
        local libraryDir = hsDir .. "/data/library"

        local ROOT_FILES = {
            "ms_macros.lua",
            "data/ms_settings.json",
            "data/ms_settings_default.json",
            "data/ms_theme.json",
            "data/ms_macros_visual.json",
            "data/ms_macros_visual.lua",
            "data/ms_authored.json",
            "data/ms_authored_menus.json",
            "data/ms_helpervars.json",
        }

        local ROOT_DIRS = {
            "sounds/active",
            "sounds/macro",
        }

        local KINDS = {
            "theme",
            "sound",
            "macro",
        }

        local STUB_MACROS = "-- New profile. Add your macros below.\n"
    -- END Paths --

    -- Helpers --
        local function sq(s)
            return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
        end

        local function isDir(p)
            local a = hs.fs.attributes(p)
            return a ~= nil and a.mode == "directory"
        end

        local function isFile(p)
            local a = hs.fs.attributes(p)
            return a ~= nil and a.mode == "file"
        end

        local function exists(p)
            return hs.fs.attributes(p) ~= nil
        end

        local function readBin(p)
            local f = io.open(p, "rb")
            if not f then return nil end
            local body = f:read("*all")
            f:close()
            return body
        end

        local function writeBin(p, body)
            local f = io.open(p, "wb")
            if not f then return false end
            f:write(body)
            f:close()
            return true
        end

        local function trimmed(s)
            if type(s) ~= "string" then return "" end
            return (s:gsub("^%s+", ""):gsub("%s+$", ""))
        end

        local function run(cmd)
            local _, ok = hs.execute(cmd)
            return ok == true
        end

        local function mkdirp(p)
            run("mkdir -p " .. sq(p))
            return isDir(p)
        end

        local function parentOf(p)
            return p:match("^(.*)/[^/]+$")
        end

        local function decode(raw)
            if type(raw) ~= "string" then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then return tbl end
            return nil
        end

        local function nowIso()
            return os.date("!%Y-%m-%dT%H:%M:%SZ")
        end

        local function safeName(name)
            if type(name) ~= "string" then return nil end
            local clean = name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
            if clean == "" or clean == "." or clean == ".." or clean:sub(1, 1) == "." then
                return nil
            end
            return clean
        end

        local function relFor(flat)
            if flat == "ms_macros.lua" then return flat end
            if flat:find("^ms_") and (flat:find("%.json$") or flat == "ms_macros_visual.lua") then
                return "data/" .. flat
            end
            return flat
        end

        local function walk(dir, rel, out)
            for entry in hs.fs.dir(dir) do
                if entry ~= "." and entry ~= ".." and entry ~= ".DS_Store" then
                    local abs = dir .. "/" .. entry
                    local r = (rel == "") and entry or (rel .. "/" .. entry)
                    local a = hs.fs.attributes(abs)
                    if a and a.mode == "directory" then
                        walk(abs, r, out)
                    elseif a and a.mode == "file" then
                        out[#out + 1] = r
                    end
                end
            end
            return out
        end

        local skipped = {}

        local function note(msg)
            print("[profile_migrate] " .. tostring(msg))
        end

        local function skip(msg)
            skipped[#skipped + 1] = msg
            note("skipped: " .. msg)
        end
    -- END Helpers --

    -- Copy Plan --
        local function copyOne(src, dst, pairsOut)
            local body = readBin(src)
            if not body then return false, "cannot read " .. src end
            local parent = parentOf(dst)
            if parent and not mkdirp(parent) then return false, "cannot create " .. parent end
            if not writeBin(dst, body) then return false, "cannot write " .. dst end
            pairsOut[#pairsOut + 1] = {
                src = src,
                dst = dst,
            }
            return true
        end

        local function copyTree(srcDir, dstDir, pairsOut, mapRel)
            if not isDir(srcDir) then return true end
            for _, rel in ipairs(walk(srcDir, "", {})) do
                local target = mapRel and mapRel(rel) or rel
                local ok, err = copyOne(srcDir .. "/" .. rel, dstDir .. "/" .. target, pairsOut)
                if not ok then return false, err end
            end
            return true
        end

        local function verify(pairsOut)
            for _, pr in ipairs(pairsOut) do
                local a = readBin(pr.src)
                local b = readBin(pr.dst)
                if a == nil or b == nil or a ~= b then
                    return false, "mismatch: " .. pr.src
                end
            end
            return true
        end
    -- END Copy Plan --

    -- Metadata --
        local function macroFacts(body)
            local facts = {}
            if type(body) ~= "string" then return facts end
            local block = body:match("macroMeta%s*=%s*(%b{})")
            if block then
                facts.name = block:match('name%s*=%s*"([^"]*)"')
                facts.author = block:match('author%s*=%s*"([^"]*)"')
            end
            return facts
        end

        local function packInfo(kind, slug)
            local meta = decode(readBin(libraryDir .. "/" .. kind .. "/" .. slug .. "/meta.json"))
            return {
                slug = slug,
                version = meta and meta.version or nil,
                owner = meta and meta.owner or nil,
            }
        end

        local function activeMarkerPacks()
            local packs = {}
            for _, kind in ipairs(KINDS) do
                local slug = trimmed(readBin(libraryDir .. "/" .. kind .. "/.active"))
                if slug ~= "" then packs[kind] = packInfo(kind, slug) end
            end
            return packs
        end

        local function foldedPacks(packsJson)
            local packs = {}
            local src = decode(packsJson)
            if not src then return packs end
            for _, kind in ipairs(KINDS) do
                if type(src[kind]) == "string" and src[kind] ~= "" then
                    packs[kind] = packInfo(kind, src[kind])
                end
            end
            return packs
        end

        local function writeProfileJson(dir, name, macroBody, packs)
            local facts = macroFacts(macroBody)
            local now = nowIso()
            local meta = {
                formatVersion = 2,
                name = name,
                version = "1.0.0",
                author = facts.author or "",
                created = now,
                updated = now,
                origin = "local",
            }
            if packs and next(packs) then meta.packs = packs end
            local ok, enc = pcall(hs.json.encode, meta, true)
            if not ok then return false, "cannot encode profile.json" end
            if not writeBin(dir .. "/profile.json", enc .. "\n") then
                return false, "cannot write profile.json"
            end
            return true
        end
    -- END Metadata --

    -- Detect --
        local function rootHasLive()
            if isFile(hsDir .. "/ms_macros.lua") then return true end
            for _, rel in ipairs(ROOT_FILES) do
                if isFile(hsDir .. "/" .. rel) then return true end
            end
            for _, rel in ipairs(ROOT_DIRS) do
                if isDir(hsDir .. "/" .. rel) and #walk(hsDir .. "/" .. rel, "", {}) > 0 then
                    return true
                end
            end
            return false
        end

        local function archivedNames()
            local out = {}
            if not isDir(rootDir) then return out end
            for entry in hs.fs.dir(rootDir) do
                if entry:sub(1, 1) ~= "." and not entry:find("%.migrating$") and isDir(rootDir .. "/" .. entry) then
                    out[#out + 1] = entry
                end
            end
            table.sort(out)
            return out
        end

        local function activeName()
            local marked = safeName(trimmed(readBin(libraryDir .. "/.active_profile")))
            if marked then return marked end
            local facts = macroFacts(readBin(hsDir .. "/ms_macros.lua"))
            local fromMeta = safeName(facts.name)
            if fromMeta then return fromMeta end
            return "Default"
        end

        local function hasAnythingToMigrate(archived)
            if #archived > 0 then return true end
            if exists(libraryDir .. "/.active_profile") then return true end
            return rootHasLive()
        end
    -- END Detect --

    -- Safety Copy --
        local function safetyCopy(bk, archived)
            local safety = bk .. "/safety"
            if not mkdirp(safety) then return false, "cannot create backup folder" end
            for _, rel in ipairs(ROOT_FILES) do
                local src = hsDir .. "/" .. rel
                if isFile(src) then
                    local dst = safety .. "/root/" .. rel
                    if not mkdirp(parentOf(dst)) then return false, "cannot create " .. parentOf(dst) end
                    if not run("/bin/cp -p " .. sq(src) .. " " .. sq(dst)) or not isFile(dst) then
                        return false, "backup copy failed: " .. rel
                    end
                end
            end
            for _, rel in ipairs(ROOT_DIRS) do
                local src = hsDir .. "/" .. rel
                if isDir(src) then
                    local dst = safety .. "/root/" .. rel
                    if not mkdirp(parentOf(dst)) then return false, "cannot create " .. parentOf(dst) end
                    if not run("/bin/cp -Rp " .. sq(src) .. " " .. sq(dst)) or not isDir(dst) then
                        return false, "backup copy failed: " .. rel
                    end
                end
            end
            if isDir(rootDir) then
                if not run("/bin/cp -Rp " .. sq(rootDir) .. " " .. sq(safety .. "/profiles")) then
                    return false, "backup copy failed: profiles"
                end
            end
            if isDir(libraryDir) then
                local markers = { ".active_profile" }
                for _, kind in ipairs(KINDS) do
                    markers[#markers + 1] = kind .. "/.active"
                end
                for _, rel in ipairs(markers) do
                    local src = libraryDir .. "/" .. rel
                    if isFile(src) then
                        local dst = safety .. "/library/" .. rel
                        if not mkdirp(parentOf(dst)) then return false, "cannot create " .. parentOf(dst) end
                        if not run("/bin/cp -p " .. sq(src) .. " " .. sq(dst)) then
                            return false, "backup copy failed: " .. rel
                        end
                    end
                end
            end
            return true
        end
    -- END Safety Copy --

    -- Stage --
        local function stageFromRoot(name, pairsOut)
            local dst = stageDir .. "/" .. name
            if not mkdirp(dst .. "/data") then return false, "cannot create " .. dst end
            local macroBody = readBin(hsDir .. "/ms_macros.lua")
            for _, rel in ipairs(ROOT_FILES) do
                local src = hsDir .. "/" .. rel
                if isFile(src) then
                    local ok, err = copyOne(src, dst .. "/" .. rel, pairsOut)
                    if not ok then return false, err end
                end
            end
            for _, rel in ipairs(ROOT_DIRS) do
                local ok, err = copyTree(hsDir .. "/" .. rel, dst .. "/" .. rel, pairsOut)
                if not ok then return false, err end
                mkdirp(dst .. "/" .. rel)
            end
            if not macroBody then
                if not writeBin(dst .. "/ms_macros.lua", STUB_MACROS) then
                    return false, "cannot write stub macros"
                end
            end
            return writeProfileJson(dst, name, macroBody, activeMarkerPacks())
        end

        local function stageFromArchive(name, srcName, pairsOut)
            local src = rootDir .. "/" .. srcName
            local dst = stageDir .. "/" .. name
            if not mkdirp(dst .. "/data") then return false, "cannot create " .. dst end
            local packsJson = nil
            local shaped = isFile(src .. "/profile.json") or isDir(src .. "/data")
            if shaped then
                local ok, err = copyTree(src, dst, pairsOut)
                if not ok then return false, err end
            else
                for _, rel in ipairs(walk(src, "", {})) do
                    if rel == "packs.json" then
                        packsJson = readBin(src .. "/" .. rel)
                    else
                        local target = rel:find("/") and rel or relFor(rel)
                        local ok, err = copyOne(src .. "/" .. rel, dst .. "/" .. target, pairsOut)
                        if not ok then return false, err end
                    end
                end
            end
            mkdirp(dst .. "/sounds/active")
            mkdirp(dst .. "/sounds/macro")
            local macroBody = readBin(dst .. "/ms_macros.lua")
            if not macroBody then
                if not writeBin(dst .. "/ms_macros.lua", STUB_MACROS) then
                    return false, "cannot write stub macros"
                end
            end
            if shaped and isFile(dst .. "/profile.json") then return true end
            return writeProfileJson(dst, name, macroBody, foldedPacks(packsJson))
        end

        local function buildStage(active, archived, hasLive)
            run("/bin/rm -rf " .. sq(stageDir))
            if not mkdirp(stageDir) then return nil, "cannot create staging folder" end
            local pairsOut = {}
            local used = {}
            local activeFromArchive = (not hasLive) and isDir(rootDir .. "/" .. active)
            local ok, err
            if activeFromArchive then
                ok, err = stageFromArchive(active, active, pairsOut)
            else
                ok, err = stageFromRoot(active, pairsOut)
            end
            if not ok then return nil, err end
            used[active] = true
            for _, entry in ipairs(archived) do
                if entry == active then
                    if hasLive then skip("stale archive folder for the active profile \"" .. entry .. "\"") end
                else
                    local target = safeName(entry)
                    if not target then
                        skip("archived folder \"" .. entry .. "\" has an unusable name")
                    elseif used[target] then
                        skip("archived folder \"" .. entry .. "\" duplicates \"" .. target .. "\"")
                    else
                        ok, err = stageFromArchive(target, entry, pairsOut)
                        if not ok then return nil, err end
                        used[target] = true
                    end
                end
            end
            return pairsOut
        end
    -- END Stage --

    -- Commit --
        local function moveToBackup(bk)
            local moved = 0
            local failed = 0
            local function mv(src, rel)
                local dst = bk .. "/root/" .. rel
                if mkdirp(parentOf(dst)) and run("/bin/mv " .. sq(src) .. " " .. sq(dst)) then
                    moved = moved + 1
                else
                    failed = failed + 1
                end
            end
            for _, rel in ipairs(ROOT_FILES) do
                local src = hsDir .. "/" .. rel
                if isFile(src) then mv(src, rel) end
            end
            for _, rel in ipairs(ROOT_DIRS) do
                local src = hsDir .. "/" .. rel
                if isDir(src) then mv(src, rel) end
            end
            local markers = { ".active_profile" }
            for _, kind in ipairs(KINDS) do
                markers[#markers + 1] = kind .. "/.active"
            end
            for _, rel in ipairs(markers) do
                local src = libraryDir .. "/" .. rel
                if isFile(src) then mv(src, "data/library/" .. rel) end
            end
            return moved, failed
        end

        local function swapIn(bk)
            local oldTarget = nil
            if isDir(rootDir) then
                if not mkdirp(bk) then return false, "cannot create backup folder" end
                oldTarget = bk .. "/profiles-old"
                if exists(oldTarget) then oldTarget = oldTarget .. "-" .. tostring(os.time()) end
                if not os.rename(rootDir, oldTarget) then return false, "cannot move old profiles" end
            end
            if not os.rename(stageDir, rootDir) then
                if oldTarget then os.rename(oldTarget, rootDir) end
                return false, "cannot move staged profiles into place"
            end
            return true
        end

        local function finishStage(active, bk)
            local ok = writeBin(stageDir .. "/.active", active .. "\n")
            if not ok then return false, "cannot write .active" end
            if bk then
                writeBin(stageDir .. "/.backup", bk .. "\n")
                writeBin(stageDir .. "/.pending-root-move", bk .. "\n")
            end
            if not writeBin(stageDir .. "/.layout", "2\n") then return false, "cannot write .layout" end
            return true
        end
    -- END Commit --

    -- Run --
        local function layoutNow()
            local n = tonumber(trimmed(readBin(rootDir .. "/.layout")))
            return n or 0
        end

        local function resume()
            local bk = trimmed(readBin(stageDir .. "/.backup"))
            if bk == "" then
                bk = backupRoot .. "/migration-resumed-" .. os.date("%Y-%m-%d_%H%M%S")
                mkdirp(bk)
            end
            local ok, err = swapIn(bk)
            if not ok then return nil, err end
            os.remove(rootDir .. "/.backup")
            moveToBackup(bk)
            os.remove(rootDir .. "/.pending-root-move")
            return bk
        end

        local function migrate()
            local archived = archivedNames()
            local hasLive = rootHasLive()
            local active = activeName()
            local legacy = hasAnythingToMigrate(archived)

            local bk = nil
            local function dropBackup()
                if bk and not exists(bk .. "/profiles-old") then
                    run("/bin/rm -rf " .. sq(bk))
                end
            end
            if legacy then
                bk = backupRoot .. "/migration-" .. os.date("%Y-%m-%d_%H%M%S")
                local n = 1
                local base = bk
                while exists(bk) do
                    n = n + 1
                    bk = base .. "_" .. n
                end
                local ok, err = safetyCopy(bk, archived)
                if not ok then
                    dropBackup()
                    return nil, err
                end
            end

            local pairsOut, berr = buildStage(active, archived, hasLive)
            if not pairsOut then
                run("/bin/rm -rf " .. sq(stageDir))
                dropBackup()
                return nil, berr
            end

            local vok, verr = verify(pairsOut)
            if not vok then
                run("/bin/rm -rf " .. sq(stageDir))
                dropBackup()
                return nil, verr
            end

            local fok, ferr = finishStage(active, bk)
            if not fok then
                run("/bin/rm -rf " .. sq(stageDir))
                dropBackup()
                return nil, ferr
            end

            local swapBk = bk or (backupRoot .. "/migration-empty-" .. os.date("%Y-%m-%d_%H%M%S"))
            local sok, serr = swapIn(swapBk)
            if not sok then
                run("/bin/rm -rf " .. sq(stageDir))
                if not exists(swapBk .. "/profiles-old") then
                    run("/bin/rm -rf " .. sq(swapBk))
                end
                return nil, serr
            end
            os.remove(rootDir .. "/.backup")

            if bk then
                local _, failed = moveToBackup(bk)
                if failed > 0 then
                    note("warning: " .. failed .. " root item(s) could not be moved into " .. bk)
                else
                    os.remove(rootDir .. "/.pending-root-move")
                end
            end
            return bk
        end

        local function leftovers()
            if isFile(hsDir .. "/ms_macros.lua") then return true end
            for _, rel in ipairs(ROOT_FILES) do
                if isFile(hsDir .. "/" .. rel) then return true end
            end
            return false
        end

        local function execute()
            if layoutNow() >= 2 then
                local pending = trimmed(readBin(rootDir .. "/.pending-root-move"))
                if pending ~= "" then
                    moveToBackup(pending)
                    os.remove(rootDir .. "/.pending-root-move")
                    os.remove(rootDir .. "/.backup")
                    note("finished an interrupted root move into " .. pending)
                end
                if leftovers() then
                    note("warning: root profile files found on a v2 layout, leaving them alone")
                    return {
                        status = "current",
                        warning = "Root profile files found on the new layout. They were left in place.",
                    }
                end
                return { status = "current" }
            end

            if isFile(stageDir .. "/.layout") then
                local bk, err = resume()
                if bk then
                    return {
                        status = "migrated",
                        backup = bk,
                    }
                end
                run("/bin/rm -rf " .. sq(stageDir))
                note("resume failed: " .. tostring(err))
            elseif isDir(stageDir) then
                run("/bin/rm -rf " .. sq(stageDir))
            end

            local ok, bk, err = pcall(migrate)
            if not ok then
                run("/bin/rm -rf " .. sq(stageDir))
                note("failed: " .. tostring(bk))
                return {
                    status = "failed",
                    error = tostring(bk),
                }
            end
            if err or (bk == nil and layoutNow() < 2) then
                note("failed: " .. tostring(err))
                return {
                    status = "failed",
                    error = tostring(err),
                }
            end
            return {
                status = bk and "migrated" or "fresh",
                backup = bk,
            }
        end
    -- END Run --

    local result = execute()
    if ms.profile and ms.profile.refresh then ms.profile.refresh() end
    ms._profileMigration = result
    if result.status == "migrated" then
        local label = result.backup and result.backup:match("([^/]+)$") or "backups"
        ms._profileMigrationNotice = "Profiles moved to the new folder layout. Backup in backups/" .. label .. "."
        if #skipped > 0 then
            ms._profileMigrationNotice = ms._profileMigrationNotice
                .. "\nSkipped: " .. table.concat(skipped, ", ") .. "."
        end
    end
    return result
end

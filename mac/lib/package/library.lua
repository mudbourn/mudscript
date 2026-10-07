return function(ms, ctx)
    -- Context --
        local _hsDir = ctx.hsDir

        local _dataDir = ctx.dataDir

        local sq = ctx.sq

        local fileExists = ctx.fileExists

        local readFile = ctx.readFile

        local writeFile = ctx.writeFile

        local safeRelPath = ctx.safeRelPath

        local destFor = ctx.destFor

        local pathAllowed = ctx.pathAllowed

        local applyDropped = ctx.applyDropped
    -- END Context --

    -- Installed Library --
        local LIBRARY_ROOT = _dataDir .. "/library"

        local LIBRARY_KINDS = {
            theme = true,
            sound = true,
            macro = true,
        }

        ms.package.isLibraryKind = function(kind) return LIBRARY_KINDS[kind] == true end

        local function librarySlug(name)
            local slug = tostring(name or "")
                :gsub("%.mspkg$", "")
                :gsub("[^%w%-_ ]", "")
                :gsub("%s+", "-")
                :gsub("%-+", "-")
                :gsub("^%-", "")
                :gsub("%-$", "")
            if slug == "" then slug = "slice" end
            return slug:sub(1, 64)
        end

        local function libraryDir(kind, slug)
            return LIBRARY_ROOT .. "/" .. kind .. "/" .. slug
        end

        ms.package.librarySlug = librarySlug
        ms.package.libraryHasEntry = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return false end
            return hs.fs.attributes(libraryDir(kind, librarySlug(slug)) .. "/meta.json") ~= nil
        end

        ms.package.blankMacroSrc = function()
            return "-- New profile - add your macros below.\n"
        end

        local function readJSON(path)
            local raw = readFile(path)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then return tbl end
            return nil
        end

        local function activeMarkerPath(kind) return LIBRARY_ROOT .. "/" .. kind .. "/.active" end

        ms.package.libraryGetActive = function(kind)
            if not LIBRARY_KINDS[kind] then return nil end
            local s = readFile(activeMarkerPath(kind))
            if not s then return nil end
            s = s:gsub("%s+$", "")
            return s ~= "" and s or nil
        end

        ms.package.librarySetActive = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return end
            if slug and slug ~= "" then
                local dir = LIBRARY_ROOT .. "/" .. kind
                hs.execute("mkdir -p " .. sq(dir))
                writeFile(activeMarkerPath(kind), librarySlug(slug) .. "\n")
            else
                os.remove(activeMarkerPath(kind))
            end
        end

        local activeProfilePath = LIBRARY_ROOT .. "/.active_profile"
        ms.package.getActiveProfile = function()
            local s = readFile(activeProfilePath)
            if not s then return nil end
            s = s:gsub("%s+$", "")
            return s ~= "" and s or nil
        end
        ms.package.setActiveProfile = function(name)
            if name and name ~= "" then
                hs.execute("mkdir -p " .. sq(LIBRARY_ROOT))
                writeFile(activeProfilePath, tostring(name) .. "\n")
            else
                os.remove(activeProfilePath)
            end
        end

        local function profilePacksPath(name)
            return _hsDir .. "/profiles/" .. tostring(name) .. "/packs.json"
        end
        ms.package.getProfilePacks = function(name)
            if not name or name == "" then return nil end
            local t = readJSON(profilePacksPath(name))
            if type(t) ~= "table" then return nil end
            local out = {}
            for _, k in ipairs({
                "theme",
                "sound",
                "macro",
            }) do
                if type(t[k]) == "string" and t[k] ~= "" then out[k] = t[k] end
            end
            return out
        end
        ms.package.setProfilePacks = function(name, tbl)
            if not name or name == "" or type(tbl) ~= "table" then return false end
            local rec = {}
            for _, k in ipairs({
                "theme",
                "sound",
                "macro",
            }) do
                if type(tbl[k]) == "string" and tbl[k] ~= "" then rec[k] = tbl[k] end
            end
            local dir = _hsDir .. "/profiles/" .. tostring(name)
            hs.execute("mkdir -p " .. sq(dir))
            return writeFile(profilePacksPath(name), hs.json.encode(rec) .. "\n")
        end

        ms.package.librarySave = function(kind, files, meta)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind: " .. tostring(kind) end
            if type(files) ~= "table" or next(files) == nil then
                return nil, "Nothing to store."
            end
            meta = type(meta) == "table" and meta or {}

            local name = meta.name or "Untitled"
            local slug = librarySlug(meta.slug or name)
            local dir  = libraryDir(kind, slug)
            local filesDir = dir .. "/files"

            hs.execute("/bin/rm -rf " .. sq(dir))
            hs.execute("mkdir -p " .. sq(filesDir))

            local stored = {}
            for rel, src in pairs(files) do
                local clean = safeRelPath(rel)
                if clean and pathAllowed(kind, clean) and fileExists(src) then
                    local destDir = (filesDir .. "/" .. clean):match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(filesDir .. "/" .. clean))
                    if ok then stored[#stored + 1] = clean end
                end
            end

            if #stored == 0 then
                hs.execute("/bin/rm -rf " .. sq(dir))
                return nil, "No readable files to store."
            end

            local record = {
                slug        = slug,
                kind        = kind,
                name        = name,
                origin      = meta.origin,
                owner       = meta.owner,
                version     = meta.version,
                fileCount   = #stored,
                installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }

            writeFile(dir .. "/meta.json", hs.json.encode(record) .. "\n")
            return record
        end

        ms.package.libraryList = function(kind)
            local out = {}
            if not LIBRARY_KINDS[kind] then return out end

            local base = LIBRARY_ROOT .. "/" .. kind
            if not hs.fs.attributes(base) then return out end

            local activeSlug = ms.package.libraryGetActive(kind)
            for entry in hs.fs.dir(base) do
                if entry ~= "." and entry ~= ".." and not entry:find("^%.") then
                    local rec = readJSON(base .. "/" .. entry .. "/meta.json")
                    if rec then
                        rec.slug = rec.slug or entry
                        rec.active = (activeSlug ~= nil and rec.slug == activeSlug)
                        out[#out + 1] = rec
                    end
                end
            end

            table.sort(out, function(a, b)
                return tostring(a.installedAt) > tostring(b.installedAt)
            end)
            return out
        end

        ms.package.libraryActivate = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            slug = librarySlug(slug)

            local filesDir = libraryDir(kind, slug) .. "/files"
            if not hs.fs.attributes(filesDir) then return nil, "No such library entry." end

            if kind == "macro" and ms.auditMacros then
                local src = readFile(filesDir .. "/ms_macros.lua")
                if type(src) == "string" and src ~= "" then
                    local errs = ms.auditMacros(src)
                    if type(errs) == "table" and #errs > 0 then
                        return nil, "Macro security scan failed:\n  - " ..
                            table.concat(errs, "\n  - ")
                    end
                end
            end

            local rels = hs.execute(
                "cd " .. sq(filesDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
            ) or ""

            local incoming = {}
            for line in rels:gmatch("[^\r\n]+") do
                local clean = safeRelPath(line:gsub("^%./", ""))
                if clean and pathAllowed(kind, clean) then incoming[clean] = true end
            end

            local prev = ms.package.libraryGetActive(kind)
            if prev and prev ~= slug then
                local prevDir = libraryDir(kind, prev) .. "/files"
                if hs.fs.attributes(prevDir) then
                    local prevRels = hs.execute(
                        "cd " .. sq(prevDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
                    ) or ""
                    for line in prevRels:gmatch("[^\r\n]+") do
                        local clean = safeRelPath(line:gsub("^%./", ""))
                        if clean and pathAllowed(kind, clean) and not incoming[clean] then
                            local dest = destFor(clean)
                            if fileExists(dest) then
                                hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                                os.remove(dest)
                            end
                        end
                    end
                end
            end

            local installed, failed = {}, {}
            for line in rels:gmatch("[^\r\n]+") do
                local clean = safeRelPath(line:gsub("^%./", ""))
                if clean and pathAllowed(kind, clean) then
                    local src  = filesDir .. "/" .. clean
                    local dest = destFor(clean)

                    if fileExists(dest) then
                        hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                    end

                    local destDir = dest:match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end

                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(dest))
                    if ok then installed[#installed + 1] = clean
                    else failed[#failed + 1] = clean end
                end
            end

            local hadFiles = next(incoming) ~= nil
            if hadFiles and #installed == 0 then
                return nil, "Nothing could be activated."
            end
            if not hadFiles then
                if kind == "theme" then
                    os.remove(_dataDir .. "/ms_theme.json")
                elseif kind == "sound" then
                    os.remove(_hsDir .. "/sound_assign.json")
                    ms._soundsDirty = true
                elseif kind == "macro" then
                    if not fileExists(_hsDir .. "/ms_macros.lua") then
                        writeFile(_hsDir .. "/ms_macros.lua",
                            "-- Blank macro pack - add your macros below.\n"
                            .. "ms.macroMeta = { name = \"" .. tostring(slug)
                            .. "\", author = \"\" }\n")
                    end
                end
            end

            applyDropped(installed)
            ms.package.librarySetActive(kind, slug)
            if kind == "macro" and ms.plugins and ms.plugins.scheduleOffer then
                pcall(ms.plugins.scheduleOffer)
            end

            return {
                kind      = kind,
                slug      = slug,
                installed = installed,
                failed    = failed,
            }
        end

        ms.switchPack = function(slug, kind)
            return ms.package.libraryActivate(kind or "macro", slug)
        end

        ms.package.libraryRemove = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return false, "Not a library kind." end
            slug = librarySlug(slug)

            local dir = libraryDir(kind, slug)
            if not hs.fs.attributes(dir) then return false, "No such library entry." end

            hs.execute("/bin/rm -rf " .. sq(dir))
            if hs.fs.attributes(dir) then return false, "Could not remove entry." end
            if ms.package.libraryGetActive(kind) == slug then
                ms.package.librarySetActive(kind, nil)
            end
            return true
        end

        ms.package.libraryRename = function(kind, slug, newName)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            slug = librarySlug(slug)
            local dir = libraryDir(kind, slug)
            local rec = readJSON(dir .. "/meta.json")
            if not rec then return nil, "No such library entry." end
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if newName == "" then return nil, "Name cannot be empty." end
            rec.name = newName
            writeFile(dir .. "/meta.json", hs.json.encode(rec) .. "\n")
            return rec
        end

        ms.package.libraryRenameEntry = function(kind, oldSlug, newName)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            oldSlug = librarySlug(oldSlug)
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if newName == "" then return nil, "Name cannot be empty." end
            local oldDir = libraryDir(kind, oldSlug)
            if not hs.fs.attributes(oldDir) then return nil end
            local newSlug = librarySlug(newName)
            if newSlug ~= oldSlug then
                local newDir = libraryDir(kind, newSlug)
                if hs.fs.attributes(newDir) then
                    return nil, "A pack with that name already exists."
                end
                local _, ok = hs.execute("/bin/mv " .. sq(oldDir) .. " " .. sq(newDir))
                if not ok or not hs.fs.attributes(newDir) then
                    return nil, "Could not rename entry."
                end
                if ms.package.libraryGetActive(kind) == oldSlug then
                    ms.package.librarySetActive(kind, newSlug)
                end
            end
            local dir = libraryDir(kind, newSlug)
            local rec = readJSON(dir .. "/meta.json") or {}
            rec.name = newName
            rec.slug = newSlug
            writeFile(dir .. "/meta.json", hs.json.encode(rec) .. "\n")
            return rec
        end

        local function foldLiveMacroBinds()
            if type(ms.bindConfig) ~= "table" then return end
            local jsonPath = _dataDir .. "/ms_macros_visual.json"
            local data = readJSON(jsonPath)
            if type(data) ~= "table" or type(data.macros) ~= "table" then return end

            local changed = false
            for id, macro in pairs(data.macros) do
                local cfg = ms.bindConfig[id]
                if type(macro) == "table" and type(cfg) == "table"
                    and (cfg.type == nil or cfg.type == "key") and cfg.key ~= nil then
                    local mods = {}
                    for _, m in ipairs(cfg.mods or {}) do mods[#mods + 1] = m end
                    macro.bind = {
                        type = "key",
                        key = cfg.key,
                        mods = mods,
                    }
                    changed = true
                end
            end
            if changed then writeFile(jsonPath, hs.json.encode(data) .. "\n") end
        end

        ms.package.libraryCreateEmpty = function(kind, name)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            name = (type(name) == "string" and name ~= "") and name or ("New " .. kind)
            local slug = librarySlug(name)
            local dir  = libraryDir(kind, slug)
            if hs.fs.attributes(dir) then return nil, "A pack with that name already exists." end
            hs.execute("mkdir -p " .. sq(dir .. "/files"))

            local fileCount = 0
            if kind == "sound" and ms.soundSlotDefaults then
                local assigns = ms.soundSlotDefaults()
                if next(assigns) then
                    writeFile(dir .. "/files/sound_assign.json",
                        hs.json.encode(assigns) .. "\n")
                    fileCount = 1
                end
            elseif kind == "macro" then
                writeFile(dir .. "/files/ms_macros.lua",
                    ms.package.blankMacroSrc())
                fileCount = 1
            end

            local record = {
                slug        = slug,
                kind        = kind,
                name        = name,
                origin      = "new",
                fileCount   = fileCount,
                installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
            writeFile(dir .. "/meta.json", hs.json.encode(record) .. "\n")
            return record
        end

        ms.package.libraryCreateSeeded = function(kind, name)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            name = (type(name) == "string" and name ~= "") and name or ("New " .. kind)
            local slug = librarySlug(name)
            if hs.fs.attributes(libraryDir(kind, slug)) then
                return nil, "A pack with that name already exists."
            end

            if kind == "macro" then foldLiveMacroBinds() end
            local files = ms.package.collect(kind)
            if next(files) == nil then
                return ms.package.libraryCreateEmpty(kind, name)
            end
            return ms.package.librarySave(kind, files, {
                slug   = slug,
                name   = name,
                origin = "seeded",
            })
        end

        ms.package.libraryClear = function(kind)
            if not LIBRARY_KINDS[kind] then return 0, "Not a library kind." end
            local active = ms.package.libraryGetActive(kind)
            local removed = 0
            for _, rec in ipairs(ms.package.libraryList(kind)) do
                if rec.slug ~= active then
                    hs.execute("/bin/rm -rf " .. sq(libraryDir(kind, rec.slug)))
                    removed = removed + 1
                end
            end
            return removed
        end

        ms.package.libraryFilesDir = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return nil end
            return libraryDir(kind, librarySlug(slug)) .. "/files"
        end

        ms.package.libraryCapture = function(kind, name, intoSlug)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end

            if kind == "macro" then foldLiveMacroBinds() end
            local files = ms.package.collect(kind)
            if next(files) == nil then
                return nil, "Nothing live to capture as a " .. kind .. "."
            end

            local prior = intoSlug and readJSON(libraryDir(kind, librarySlug(intoSlug)) .. "/meta.json")
            if type(prior) == "table" and type(prior.name) == "string" and prior.name ~= "" then
                name = prior.name
            else
                prior, intoSlug = nil, nil
            end

            local rec, err = ms.package.librarySave(kind, files, {
                name    = (type(name) == "string" and name ~= "" and name) or "Current " .. kind,
                slug    = intoSlug,
                origin  = prior and prior.origin or "captured",
                owner   = prior and prior.owner or nil,
                version = prior and prior.version or nil,
            })
            if rec then ms.package.librarySetActive(kind, rec.slug) end
            return rec, err
        end

        ms.package.libraryImportDir = function(kind, baseDir, meta)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            if not hs.fs.attributes(baseDir) then return nil, "No such folder." end
            local files = ms.package.collect(kind, { baseDir = baseDir })
            if next(files) == nil then return nil, "Nothing to import." end
            return ms.package.librarySave(kind, files, meta or {})
        end

        ms.package.migrateMacroPacks = function()
            local macroRoot  = LIBRARY_ROOT .. "/macro"
            local doneMarker = macroRoot .. "/.migrated"
            if hs.fs.attributes(doneMarker) then return end

            local function slugExists(name)
                return hs.fs.attributes(libraryDir("macro", librarySlug(name))) ~= nil
            end

            local liveName = (ms.macroMeta and type(ms.macroMeta.name) == "string"
                and ms.macroMeta.name ~= "" and ms.macroMeta.name) or "Current Macros"
            local liveFiles = ms.package.collect("macro")
            if next(liveFiles) ~= nil and not slugExists(liveName) then
                local rec = ms.package.librarySave("macro", liveFiles, {
                    name    = liveName,
                    origin  = "current",
                    version = ms.macroMeta and ms.macroMeta.version or nil,
                })
                if rec and not ms.package.libraryGetActive("macro") then
                    ms.package.librarySetActive("macro", rec.slug)
                end
            end

            local profilesDir = _hsDir .. "/profiles/"
            if hs.fs.attributes(profilesDir) then
                for entry in hs.fs.dir(profilesDir) do
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.") then
                        local pdir = profilesDir .. entry
                        if hs.fs.attributes(pdir .. "/ms_macros.lua") and not slugExists(entry) then
                            ms.package.libraryImportDir("macro", pdir, {
                                name = entry, origin = "profile",
                            })
                        end
                    end
                end
            end

            hs.execute("mkdir -p " .. sq(macroRoot))
            writeFile(doneMarker, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
        end

        ms.package.migrateProfilePacks = function()
            local profilesDir = _hsDir .. "/profiles/"
            if not hs.fs.attributes(profilesDir) then return end
            for entry in hs.fs.dir(profilesDir) do
                if entry ~= "." and entry ~= ".." and not entry:find("^%.")
                    and not hs.fs.attributes(profilePacksPath(entry)) then
                    local slug = librarySlug(entry)
                    local refs = {}
                    for _, k in ipairs({
                        "theme",
                        "sound",
                        "macro",
                    }) do
                        if ms.package.libraryHasEntry(k, slug) then refs[k] = slug end
                    end
                    if next(refs) then ms.package.setProfilePacks(entry, refs) end
                end
            end
        end

        local RECONCILE_SKIP = {
            ["sound_assign.json"]     = true,
            ["ms_macros_visual.lua"]  = true,
        }

        local function canonicalJSON(v)
            local t = type(v)
            if t == "table" then
                local n, isSeq = 0, true
                for k in pairs(v) do
                    n = n + 1
                    if type(k) ~= "number" then isSeq = false end
                end
                if isSeq and n > 0 and #v == n then
                    local parts = {}
                    for i = 1, n do parts[i] = canonicalJSON(v[i]) end
                    return "[" .. table.concat(parts, ",") .. "]"
                end
                local keys = {}
                for k in pairs(v) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                local parts = {}
                for _, k in ipairs(keys) do
                    parts[#parts + 1] = string.format("%q", k) .. ":" .. canonicalJSON(v[k])
                end
                return "{" .. table.concat(parts, ",") .. "}"
            elseif t == "string" then
                return string.format("%q", v)
            elseif t == "number" or t == "boolean" then
                return tostring(v)
            end
            return "null"
        end

        local function stripVisualBinds(tbl)
            if type(tbl) == "table" and type(tbl.macros) == "table" then
                for _, m in pairs(tbl.macros) do
                    if type(m) == "table" then m.bind = nil end
                end
            end
            return tbl
        end

        local function sliceFingerprint(files)
            local rels = {}
            for rel in pairs(files) do
                if not RECONCILE_SKIP[rel] then rels[#rels + 1] = rel end
            end
            table.sort(rels)
            if #rels == 0 then return nil end

            local parts = {}
            for _, rel in ipairs(rels) do
                local token
                if rel:match("%.json$") then
                    local tbl = readJSON(files[rel])
                    if tbl then
                        if rel == "ms_macros_visual.json" then stripVisualBinds(tbl) end
                        token = "json:" .. canonicalJSON(tbl)
                    end
                end
                if not token then
                    local h = hs.execute("/sbin/md5 -q " .. sq(files[rel]) .. " 2>/dev/null") or ""
                    h = h:gsub("%s+", "")
                    if h == "" then return nil end
                    token = h
                end
                parts[#parts + 1] = rel .. ":" .. token
            end
            return table.concat(parts, "|")
        end

        local function entryFiles(kind, slug)
            local out = {}
            local filesDir = libraryDir(kind, slug) .. "/files"
            if not hs.fs.attributes(filesDir) then return out end
            local rels = hs.execute(
                "cd " .. sq(filesDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
            ) or ""
            for line in rels:gmatch("[^\r\n]+") do
                local rel = line:gsub("^%./", "")
                out[rel] = filesDir .. "/" .. rel
            end
            return out
        end

        ms.package.reconcileActive = function(kind)
            if not LIBRARY_KINDS[kind] then return end
            local liveFp = sliceFingerprint(ms.package.collect(kind))
            if not liveFp then return end

            for _, rec in ipairs(ms.package.libraryList(kind)) do
                if sliceFingerprint(entryFiles(kind, rec.slug)) == liveFp then
                    ms.package.librarySetActive(kind, rec.slug)
                    return
                end
            end
            ms.package.librarySetActive(kind, nil)
        end
    -- END Installed Library --
end

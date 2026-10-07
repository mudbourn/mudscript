return function(ms, ctx)
    -- Profile Management --
        local backupDir = ctx.backupDir

        ms._buildDefaultSettings = function()
            local data = {
                sensitivity      = 1.5,
                trackpadMode     = false,
                gamepadEnabled   = false,
                socdEnabled      = false,
                socdMode         = "lastWins",

                trackpadHoldKeys = {
                    left = "n",
                    right = "j",
                },
                soundEnabled     = true,
                soundVolume      = 100,
                soundAssign      = {},
                bundleSoundsWithTheme = true,
                backupIntervalHours = 12,
                backupKeep       = 10,
                macros           = {},
                macroLabEnabled  = true,
                shell            = {
                    x = nil,
                    y = nil,
                    w = 900,
                    h = 600,
                    lastPanel = "macros",
                    visible = false,
                },
            }
            if ms.macroDefaults then
                for k, v in pairs(ms.macroDefaults) do
                    if k ~= "macros" then data[k] = v end
                end
                if ms.macroDefaults.macros then
                    for id, entry in pairs(ms.macroDefaults.macros) do
                        data.macros[id] = data.macros[id] or {}
                        for k, v in pairs(entry) do data.macros[id][k] = v end
                    end
                end
            end
            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not (def.default and def.default.type) then
                    data.macros[id] = data.macros[id] or {}
                    if data.macros[id].enabled == nil then
                        data.macros[id].enabled = def.enabled
                    end
                end
            end
            local f = io.open(ms.profile.file("defaults"), "w")
            if f then
                f:write(hs.json.encode(data, true))
                f:close()
            end
        end

        local function sq(s)
            return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
        end

        local function sanitizeName(name)
            return (name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", ""))
        end

        local function copyDirContents(src, dst)
            if not hs.fs.attributes(src) then return 0 end
            os.execute("mkdir -p " .. sq(dst))
            local copied = 0
            for file in hs.fs.dir(src) do
                if file ~= "." and file ~= ".." and not file:find("%.bak$") then
                    local _, ok = hs.execute("/bin/cp -R " .. sq(src .. "/" .. file) .. " " .. sq(dst .. "/" .. file))
                    if ok then copied = copied + 1 end
                end
            end
            return copied
        end

        local function copyProfileContent(srcDir, dstDir)
            for _, rel in ipairs(ms.profile.CONTENT_FILES) do
                local src = srcDir .. "/" .. rel
                if hs.fs.attributes(src) then
                    local parent = (dstDir .. "/" .. rel):match("^(.*)/[^/]+$")
                    os.execute("mkdir -p " .. sq(parent))
                    hs.execute("/bin/cp " .. sq(src) .. " " .. sq(dstDir .. "/" .. rel))
                end
            end
            for _, rel in ipairs(ms.profile.SOUND_DIRS) do
                local src = srcDir .. "/" .. rel:gsub("/$", "")
                copyDirContents(src, dstDir .. "/" .. rel:gsub("/$", ""))
            end
        end

        local function readMacroMeta(filePath)
            local captured = {}
            local dummyFn  = function() end
            local dummyTbl = setmetatable({}, {
                __index    = function() return dummyFn end,
                __newindex = function() end,
                __call     = function() end,
            })
            local proxy = setmetatable({}, {
                __index    = function(t, k)
                    if k == "macroMeta" then return captured.macroMeta end
                    return dummyTbl
                end,
                __newindex = function(t, k, v)
                    if k == "macroMeta" then captured.macroMeta = v end
                end,
            })
            local env = setmetatable({ ms = proxy }, {
                __index    = function() return nil end,
                __newindex = function() end,
            })
            local chunk, err
            if setfenv then
                chunk, err = loadfile(filePath)
                if chunk then setfenv(chunk, env) end
            else
                chunk, err = loadfile(filePath, "bt", env)
            end
            if not chunk then
                print("readMacroMeta: parse error in " .. filePath .. ": " .. tostring(err))
                return nil
            end
            if jit then pcall(jit.off, chunk, true) end

            local _co = coroutine.create(chunk)
            local _hookFires = 0

            debug.sethook(
                _co,
                function()
                    _hookFires = _hookFires + 1
                    if _hookFires > 2000 then
                        error("readMacroMeta: instruction limit exceeded (possible infinite loop in " .. filePath .. ")")
                    end
                end,
                "",
                1000
            )

            coroutine.resume(_co)
            return captured.macroMeta
        end


        local function activeProfile()
            return sanitizeName(ms.profile.active() or "")
        end

        local function v2Guard()
            if ms.profile.isV2() then return true end
            ms.alert("Profiles are still on the old layout.\nRestart mudscript to finish the move.", 6)
            return false
        end

        ms._profilesDirty = true
        local _profilesCache = nil
        local function getProfiles()
            if not ms._profilesDirty and _profilesCache then return _profilesCache end
            ms._profilesDirty = false
            local list = ms.profile.list()
            local activeName = activeProfile()
            if activeName ~= "" and hs.fs.attributes(ms.profile.root() .. "/" .. activeName) then
                local found = false
                for _, p in ipairs(list) do
                    if p == activeName then
                        found = true
                        break
                    end
                end
                if not found then table.insert(list, activeName) end
            end
            table.sort(list)
            _profilesCache = list
            return list
        end

        local function newMeta(folderName, extra)
            local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
            local meta = {
                formatVersion = 2,
                name = folderName,
                version = "1.0.0",
                author = "You",
                created = now,
                updated = now,
                origin = "local",
            }
            for k, v in pairs(extra or {}) do meta[k] = v end
            return meta
        end

        local function computeRequires(name)
            local ids = {}
            local seen = {}
            if ms.plugins and ms.plugins.scanFiles then
                local paths = {}
                for _, rel in ipairs({ "ms_macros.lua", "data/ms_macros_visual.lua" }) do
                    local path = ms.profile.path(rel, name)
                    if path then paths[#paths + 1] = path end
                end
                local deps = ms.plugins.scanFiles(paths, { all = true })
                for _, dep in ipairs(deps) do
                    if dep.id and not seen[dep.id] then
                        seen[dep.id] = true
                        ids[#ids + 1] = dep.id
                    end
                end
            end
            table.sort(ids)
            local requires = {}
            if ms.version then requires.mudscript = ms.version end
            if #ids > 0 then requires.plugins = ids end
            if next(requires) == nil then return nil end
            return requires
        end
        ms.profileRequires = computeRequires

        local function stampRequires(name)
            local requires = computeRequires(name)
            ms.profile.updateMeta(name, function(meta)
                meta.requires = requires
            end)
        end
        ms.stampProfileRequires = stampRequires


        local auditMacros
        ms.auditMacros = function(src) return auditMacros(src) end

        local function hotswapLive()
            local wasQuick = ms._quickReloading
            ms._quickReloading = true
            if ms.ui and ms.ui._actions and ms.ui._actions.reloadMacros then
                pcall(ms.ui._actions.reloadMacros)
            end
            if ms.loadTheme then pcall(ms.loadTheme) end
            pcall(function() ms.alert:recolor() end)
            pcall(function() ms.dev:recolor() end)
            ms._soundsDirty = true
            if ms._discoverSounds then pcall(ms._discoverSounds) end
            if ms._loadAuthoredSettings then pcall(ms._loadAuthoredSettings) end
            if ms._defineAuthoredSettings then pcall(ms._defineAuthoredSettings) end
            if ms._loadAuthoredMenus then pcall(ms._loadAuthoredMenus) end
            ms._quickReloading = wasQuick
        end
        ms.hotswapLive = hotswapLive

        local function pushPackLists()
            if ms.ui._actions and ms.ui._actions.libraryList then
                for _, k in ipairs({
                    "theme",
                    "sound",
                    "macro",
                }) do
                    pcall(ms.ui._actions.libraryList, { kind = k })
                end
            end
        end

        local function switchProfile(targetName)
            ms.dev.log({
                type   = "system",
                event  = "profile_switch_start",
                target = targetName,
            })
            if not v2Guard() then return end
            local target = sanitizeName(tostring(targetName or ""))
            if target == "" or not ms.profile.exists(target) then
                ms.dev.log({
                    type   = "error",
                    event  = "profile_switch_failed",
                    reason = "not_found",
                    target = targetName,
                })
                ms.alert("Profile switch failed: \"" .. tostring(targetName) .. "\" was not found.", 5)
                return
            end
            if target == activeProfile() then return end

            local targetMacros = ms.profile.path("ms_macros.lua", target)
            local tf = targetMacros and io.open(targetMacros, "r")
            if tf then
                local targetSrc = tf:read("*all")
                tf:close()
                local switchErrs = auditMacros(targetSrc)
                if #switchErrs > 0 then
                    ms.alert("Profile switch rejected, security scan failed:\n  - "
                        .. table.concat(switchErrs, "\n  - "), 8)
                    return
                end
            end

            pcall(ms.saveSettings)
            if not ms.profile.setActive(target) then
                ms.alert("Profile switch failed: could not activate \"" .. target .. "\".", 5)
                return
            end
            ms.profile.repoint()
            ms.profile.ensure(target)
            if not hs.fs.attributes(ms.profile.file("macros")) then
                local stub = io.open(ms.profile.file("macros"), "w")
                if stub then
                    stub:write("-- New profile. Add your macros below.\n")
                    stub:close()
                end
            end

            ms.dev.log({
                type   = "system",
                event  = "profile_switch_complete",
                target = target,
            })

            ms._profilesDirty = true
            hotswapLive()

            ms.playSlot("update")
            ms.alert("Switched to \"" .. target .. "\".", 3, true)
            if ms.plugins and ms.plugins.scheduleOffer then
                pcall(ms.plugins.scheduleOffer)
            end
            ms.ui.markDirty()
            ms.ui.refresh()
            pushPackLists()
            if ms.shell and ms.shell.eval then
                pcall(ms.shell.eval, "if(window.shellReceive)shellReceive('macros','profileSwitched',{})")
            end
        end

        auditMacros = function(src)
                local function blank(s) return s:gsub("[^\n]", " ") end
                local out = {}
                local i, n = 1, #src

                while i <= n do
                    local c = src:sub(i, i)

                    if c == '"' or c == "'" then
                        -- Short quoted string --
                            local j = i + 1
                            while j <= n do
                                local ch = src:sub(j, j)
                                if ch == "\\" then
                                    j = j + 2
                                elseif ch == c then
                                    break
                                elseif ch == "\n" then
                                    break
                                else
                                    j = j + 1
                                end
                            end
                            out[#out + 1] = blank(src:sub(i, j))
                            i = j + 1
                        -- END Short quoted string --

                    elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
                        -- Comment --
                            local j      = i + 2
                            local isLong = false
                            if src:sub(j, j) == "[" then
                                local eq = 0
                                while src:sub(j + 1 + eq, j + 1 + eq) == "=" do eq = eq + 1 end
                                if src:sub(j + 1 + eq, j + 1 + eq) == "[" then
                                    local closer = "]" .. string.rep("=", eq) .. "]"
                                    local _, ce  = src:find(closer, j + 2 + eq, true)
                                    out[#out + 1] = blank(src:sub(i, ce or n))
                                    i = ce and ce + 1 or n + 1
                                    isLong = true
                                end
                            end
                            if not isLong then
                                local nl = src:find("\n", j)
                                if nl then
                                    out[#out + 1] = blank(src:sub(i, nl - 1)) .. "\n"
                                    i = nl + 1
                                else
                                    out[#out + 1] = blank(src:sub(i))
                                    i = n + 1
                                end
                            end
                        -- END Comment --

                    elseif c == "[" then
                        -- Long string [=*[...]=*] --
                            local eq = 0
                            while src:sub(i + 1 + eq, i + 1 + eq) == "=" do eq = eq + 1 end
                            if src:sub(i + 1 + eq, i + 1 + eq) == "[" then
                                local closer = "]" .. string.rep("=", eq) .. "]"
                                local _, ce  = src:find(closer, i + 2 + eq, true)
                                out[#out + 1] = blank(src:sub(i, ce or n))
                                i = ce and ce + 1 or n + 1
                            else
                                out[#out + 1] = c
                                i = i + 1
                            end
                        -- END Long string [=*[...]=*] --

                    else
                        out[#out + 1] = c
                        i = i + 1
                    end
                end

                local clean = " " .. table.concat(out)
                local errs  = {}
                local function deny(pat, label)
                    if clean:find(pat) then table.insert(errs, label) end
                end

                deny("[^%w%.]hs%.[%a_]",      "direct hs.* API access")

                deny("[^%w%.]load%s*%(",       "load()")
                deny("loadfile%s*%(",           "loadfile()")
                deny("loadstring%s*%(",         "loadstring()")
                deny("[^%w%.]dofile%s*%(",      "dofile()")
                deny("[^%w%.]require%s*%(",     "require()")

                deny("[^%w%.]os%.[%a_]",        "os.* access")
                deny("[^%w%.]io%.[%a_]",        "io.* access")
                deny("[^%w%.]popen%s*%(",       "popen()")

                deny("[^%w%.]debug%.[%a_]",     "debug.* access")
                deny("[^%w%.]package%.[%a_]",   "package.* access")
                deny("collectgarbage%s*%(",     "collectgarbage()")

                deny("setmetatable%s*%(",       "setmetatable()")
                deny("getmetatable%s*%(",       "getmetatable()")
                deny("[^%w_]rawget%s*%(",       "rawget()")
                deny("[^%w_]rawset%s*%(",       "rawset()")
                deny("setfenv%s*%(",            "setfenv()")
                deny("getfenv%s*%(",            "getfenv()")
                deny("%f[%w_]_G%f[^%w_]",      "_G global-environment access")

                deny(":launch%s*%(",            ":launch()")
                deny(":activate%s*%(",          ":activate()")
                deny("openURL%s*%(",            "openURL()")

                local mediaExts = {
                    "%.mp3","%.wav","%.aiff","%.m4a","%.ogg","%.flac",
                    "%.caf","%.aac","%.mp4","%.mov","%.avi",
                    "%.jpg","%.jpeg","%.png","%.gif","%.webp","%.bmp","%.tiff",
                }
                local function nearMedia(pos)
                    local ctx = clean:sub(math.max(1, pos-10), math.min(#clean, pos+120))
                    for _, ext in ipairs(mediaExts) do
                        if ctx:find(ext) then return true end
                    end
                    return false
                end
                for _, sysPath in ipairs({
                    "/Users/","/home/","/Applications/",
                    "/usr/","/var/","/etc/","/bin/","/sbin/",
                    "/opt/","/tmp/","/System/","/Library/",
                    "~/","%.hammerspoon",
                }) do
                    local pos = 1
                    while true do
                        local found = clean:find(sysPath, pos)
                        if not found then break end
                        if not nearMedia(found) then
                            local snip = clean:sub(found, math.min(#clean, found+35))
                                            :gsub("%s+", " ")
                            table.insert(errs, "disallowed path: " .. snip)
                            break
                        end
                        pos = found + 1
                    end
                end

                for line in clean:gmatch("[^\n]+") do
                    local name = line:match("^%s*function%s+([%a_][%w_]*)%s*%(")
                    if name then
                        table.insert(errs, "non-local global function definition: " .. name .. "()")
                    end
                end

            return errs
        end


        local function createNewProfile(seed)
            if not v2Guard() then return end
            local base, n, folderName = "New Profile", 0, nil
            repeat
                n = n + 1
                folderName = base .. " " .. n
            until not ms.profile.exists(folderName)

            if seed then pcall(ms.saveSettings) end
            local sourceDir = ms.profile.dir()
            local dir = ms.profile.ensure(folderName)
            if not hs.fs.attributes(dir) then
                ms.alert("Could not create profile folder.", 3)
                return
            end

            local extra = nil
            if seed then
                copyProfileContent(sourceDir, dir)
                local packs = ms.profile.packs()
                if next(packs) then extra = { packs = packs } end
            end

            if not hs.fs.attributes(dir .. "/ms_macros.lua") then
                local blankSrc = (ms.package and ms.package.blankMacroSrc
                    and ms.package.blankMacroSrc())
                    or "-- New profile. Add your macros below.\n"
                local mf = io.open(dir .. "/ms_macros.lua", "w")
                if not mf then
                    ms.alert("Could not write the new profile.", 3)
                    return
                end
                mf:write(blankSrc)
                mf:close()
            end

            local meta = newMeta(folderName, extra)
            if not seed then
                local packMeta = {
                    name    = folderName,
                    version = "1.0.0",
                    author  = "You",
                    website = "",
                }
                local vf = io.open(dir .. "/data/ms_macros_visual.json", "w")
                if vf then
                    vf:write(hs.json.encode({
                        macros = {},
                        meta   = packMeta,
                    }, true))
                    vf:close()
                end
                if ms.compiler and ms.compiler._writeFile then
                    pcall(ms.compiler._writeFile, {}, packMeta, dir .. "/data/ms_macros_visual.lua")
                end
            end
            ms.profile.writeMeta(folderName, meta)

            ms._profilesDirty = true

            if not seed then
                ms.playSlot("update")
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                switchProfile(folderName)
                return
            end

            ms.playSlot("update")
            ms.alert("Created \"" .. folderName .. "\".", 3)
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
            end
        end

        local function saveCurrentProfile()
            if not v2Guard() then return end
            local name = activeProfile()
            if name == "" or not ms.profile.exists(name) then
                ms.alert("Cannot save: no profile is active.\nUse Save as New Profile instead.", 5)
                return
            end
            pcall(ms.saveSettings)
            stampRequires(name)
            ms.playSlot("update")
            ms._profilesDirty = true
            ms.ui.markDirty()
            ms.ui.refresh()
            hs.timer.doAfter(0.2, function()
                ms.alert("Profile \"" .. name .. "\" saved.", 3, true)
            end)
        end

        local function renameProfile(oldName, newName)
            if not v2Guard() then return end
            local oldFolder = sanitizeName(oldName or "")
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            local newFolder = sanitizeName(newName)
            if oldFolder == "" or newFolder == "" or not ms.profile.safeName(newFolder)
                or not ms.profile.exists(oldFolder) then
                ms.alert("Rename failed: invalid name.", 4)
                return
            end
            if newFolder ~= oldFolder and ms.profile.exists(newFolder) then
                ms.alert("A profile named \"" .. newFolder .. "\" already exists.", 4)
                return
            end

            local isActive = (oldFolder == activeProfile())

            if newFolder ~= oldFolder then
                if not os.rename(ms.profile.root() .. "/" .. oldFolder, ms.profile.root() .. "/" .. newFolder) then
                    ms.alert("Rename failed: could not move the profile folder.", 4)
                    return
                end
                ms.profile.updateMeta(newFolder, function(meta)
                    meta.name = newFolder
                end)
            end

            if isActive and newFolder ~= oldFolder then
                ms.profile.setActive(newFolder)
                ms.profile.repoint()
                ms._soundsDirty = true
                if ms._discoverSounds then pcall(ms._discoverSounds) end
            end

            ms._profilesDirty = true
            ms.playSlot("update")
            ms.alert("Renamed to \"" .. newFolder .. "\".", 3, true)
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
                pushPackLists()
            end
        end
        ms.renameProfile = renameProfile

        local function deleteProfile(name)
            if not ms.profile.isV2() then return false, "old layout" end
            local target = sanitizeName(tostring(name or ""))
            if target == "" or not ms.profile.exists(target) then return false, "not found" end
            if target == activeProfile() then return false, "active" end
            local targetDir = ms.profile.dir(target)
            if not targetDir or targetDir == ms.profile.root() then return false, "not found" end
            hs.execute("/bin/rm -rf " .. sq(targetDir))
            ms._profilesDirty = true
            return not hs.fs.attributes(ms.profile.root() .. "/" .. target)
        end
        ms.deleteProfile = deleteProfile

        ms.clearProfiles = function()
            local deleted = 0
            for _, entry in ipairs(ms.profile.list()) do
                if deleteProfile(entry) then deleted = deleted + 1 end
            end
            return deleted
        end

        local function alignedProfile()
            local active = activeProfile()
            if active == "" then return "" end
            for _, p in ipairs(getProfiles()) do
                if p == active then return p end
            end
            return ""
        end

        ms.sanitizeName       = sanitizeName
        ms.getProfiles        = getProfiles
        ms.alignedProfile     = alignedProfile
        ms.activeProfile      = activeProfile
        ms.switchProfile      = switchProfile
        ms.createNewProfile   = createNewProfile
        ms.saveCurrentProfile = saveCurrentProfile

        ctx.sanitizeName = sanitizeName
        ctx.getProfiles = getProfiles
        ctx.switchProfile = switchProfile
        ctx.createNewProfile = createNewProfile
        ctx.saveCurrentProfile = saveCurrentProfile
        ctx.readMacroMeta = readMacroMeta
        ctx.copyDirContents = copyDirContents
        ctx.newMeta = newMeta
        ctx.v2Guard = v2Guard
        ctx.sq = sq
    -- END Profile Management --
end

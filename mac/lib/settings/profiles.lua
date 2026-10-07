return function(ms, ctx)
    -- Profile Management --
        local jsonPath = ctx.jsonPath
        local defaultPath = ctx.defaultPath
        local backupDir = ctx.backupDir
        local macrosPath = ctx.macrosPath
        local profilesPath = ctx.profilesPath
        local themePath = ctx.themePath
        local profileContentFiles = ctx.profileContentFiles

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
            local f = io.open(defaultPath, "w")
            if f then
                f:write(hs.json.encode(data, true))
                f:close()
            end
        end

        local function sanitizeName(name)
            return (name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", ""))
        end

        local function moveFile(src, dst)
            local f = io.open(src, "r")
            if not f then return false, "cannot read " .. src end
            local content = f:read("*all")
            f:close()
            local g = io.open(dst, "w")
            if not g then return false, "cannot write " .. dst end
            g:write(content)
            g:close()
            os.remove(src)
            return true
        end

        local function moveDirContents(src, dst)
            if not hs.fs.attributes(src) then return 0 end
            os.execute("mkdir -p '" .. dst:gsub("'", "'\\''") .. "'")
            local moved = 0
            for file in hs.fs.dir(src) do
                if file ~= "." and file ~= ".." then
                    if os.rename(src .. file, dst .. file) then
                        moved = moved + 1
                    end
                end
            end
            return moved
        end

        -- Copy a dir's contents into dst, skipping .bak scratch files
        local function copyDirContents(src, dst)
            if not hs.fs.attributes(src) then return 0 end
            local q = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            os.execute("mkdir -p " .. q(dst))
            local copied = 0
            for file in hs.fs.dir(src) do
                if file ~= "." and file ~= ".." and not file:find("%.bak$") then
                    local _, ok = hs.execute("/bin/cp -R " .. q(src .. file) .. " " .. q(dst .. file))
                    if ok then copied = copied + 1 end
                end
            end
            return copied
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
            local marked = ms.package and ms.package.getActiveProfile and ms.package.getActiveProfile()
            if marked then return sanitizeName(marked) end
            return ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
        end

        ms._profilesDirty = true
        local _profilesCache = nil
        local function getProfiles()
            if not ms._profilesDirty and _profilesCache then return _profilesCache end
            ms._profilesDirty = false
            local list = {}
            if not hs.fs.attributes(profilesPath) then _profilesCache = list
            return list end
            for entry in hs.fs.dir(profilesPath) do
                if entry ~= "." and entry ~= ".." then
                    local attr = hs.fs.attributes(profilesPath .. entry)
                    if attr and attr.mode == "directory" then
                        if hs.fs.attributes(profilesPath .. entry .. "/ms_macros.lua")
                            or hs.fs.attributes(profilesPath .. entry .. "/ms_settings.json") then
                            table.insert(list, entry)
                        end
                    end
                end
            end
            local activeName = activeProfile()
            if activeName ~= "" and hs.fs.attributes(profilesPath .. activeName) then
                local found = false
                for _, p in ipairs(list) do
                    if p == activeName then found = true
                    break end
                end
                if not found then
                    table.insert(list, activeName)
                end
            end
            table.sort(list)
            _profilesCache = list
            return list
        end

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

        local function switchProfile(targetName)
            ms.dev.log({
                type   = "system",
                event  = "profile_switch_start",
                target = targetName,
            })
            local targetFile = profilesPath .. targetName .. "/ms_macros.lua"
            local hasMacros = hs.fs.attributes(targetFile) ~= nil
            local targetSrc, switchErrs
            if hasMacros then
                local tf = io.open(targetFile, "r")
                if not tf then
                    ms.dev.log({
                        type   = "error",
                        event  = "profile_switch_failed",
                        reason = "cannot_read",
                        target = targetName,
                    })
                    ms.alert("Profile switch failed: cannot read target profile.", 5)
                    return
                end
                targetSrc = tf:read("*all")
                tf:close()
                switchErrs = auditMacros(targetSrc)
                if #switchErrs > 0 then
                    ms.alert("Profile switch rejected, security scan failed:\n  - "
                        .. table.concat(switchErrs, "\n  - "), 8)
                    return
                end
            end
            local currentName = activeProfile()
            if currentName == "" then currentName = "unnamed" end
            pcall(ms.saveSettings)
            if ms.package and ms.package.libraryCapture
                and ms.package.libraryGetActive and ms.package.libraryHasEntry then
                local kinds = {
                    "theme",
                    "sound",
                    "macro",
                }
                for _, k in ipairs(kinds) do
                    local into = ms.package.libraryGetActive(k)
                    if into and ms.package.libraryHasEntry(k, into) then
                        pcall(ms.package.libraryCapture, k, nil, into)
                    end
                end
            end
            hs.fs.mkdir(profilesPath)
            hs.fs.mkdir(profilesPath .. currentName)

            local currentHasMacros = hs.fs.attributes(macrosPath) ~= nil
            if currentHasMacros then
                local ok, err = moveFile(macrosPath, profilesPath .. currentName .. "/ms_macros.lua")
                if not ok then
                    ms.alert("Profile switch failed: could not archive current profile.\n" .. tostring(err), 5)
                    return
                end
            end
            local hadSettings = hs.fs.attributes(jsonPath)   and moveFile(jsonPath,    profilesPath .. currentName .. "/ms_settings.json")
            local hadDefaults = hs.fs.attributes(defaultPath) and moveFile(defaultPath, profilesPath .. currentName .. "/ms_settings_default.json")
            local hadTheme    = hs.fs.attributes(themePath)   and moveFile(themePath,   profilesPath .. currentName .. "/ms_theme.json")
            local curSoundsDir = profilesPath .. currentName .. "/sounds/"
            moveDirContents(SoundActiveDir, curSoundsDir .. "active/")
            moveDirContents(SoundMacroDir,  curSoundsDir .. "macro/")
            for _, cf in ipairs(profileContentFiles()) do
                if hs.fs.attributes(cf.live) then
                    moveFile(cf.live, profilesPath .. currentName .. "/" .. cf.name)
                end
            end

            if hasMacros then
                local ok, err = moveFile(profilesPath .. targetName .. "/ms_macros.lua", macrosPath)
                if not ok then
                    if currentHasMacros then moveFile(profilesPath .. currentName .. "/ms_macros.lua", macrosPath) end
                    if hadSettings then moveFile(profilesPath .. currentName .. "/ms_settings.json",         jsonPath)    end
                    if hadDefaults then moveFile(profilesPath .. currentName .. "/ms_settings_default.json", defaultPath) end
                    if hadTheme    then moveFile(profilesPath .. currentName .. "/ms_theme.json",            themePath)   end
                    moveDirContents(profilesPath .. currentName .. "/sounds/active/", SoundActiveDir)
                    moveDirContents(profilesPath .. currentName .. "/sounds/macro/",  SoundMacroDir)
                    for _, cf in ipairs(profileContentFiles()) do
                        local arch = profilesPath .. currentName .. "/" .. cf.name
                        if hs.fs.attributes(arch) then moveFile(arch, cf.live) end
                    end
                    ms.alert("Profile switch failed: could to activate \"" .. targetName .. "\".\n" .. tostring(err), 5)
                    return
                end
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings.json") then
                moveFile(profilesPath .. targetName .. "/ms_settings.json",         jsonPath)
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings_default.json") then
                moveFile(profilesPath .. targetName .. "/ms_settings_default.json", defaultPath)
            end
            if hs.fs.attributes(profilesPath .. targetName .. "/ms_theme.json") then
                moveFile(profilesPath .. targetName .. "/ms_theme.json", themePath)
            end
            local tgtSoundsDir = profilesPath .. targetName .. "/sounds/"
            moveDirContents(tgtSoundsDir .. "active/", SoundActiveDir)
            moveDirContents(tgtSoundsDir .. "macro/",  SoundMacroDir)
            for _, cf in ipairs(profileContentFiles()) do
                local arch = profilesPath .. targetName .. "/" .. cf.name
                if hs.fs.attributes(arch) then moveFile(arch, cf.live) end
            end

            if not hs.fs.attributes(macrosPath) then
                local stub = io.open(macrosPath, "w")
                if stub then
                    stub:write("-- New profile. Add your macros below.\n")
                    stub:close()
                end
            end

            local alignedKinds = {}
            if ms.package and ms.package.librarySlug
                and ms.package.libraryActivate and ms.package.libraryHasEntry then
                local links = ms.package.getProfilePacks
                    and ms.package.getProfilePacks(targetName) or nil
                local pslug = ms.package.librarySlug(targetName)
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    local slug = (links and links[k]) or pslug
                    if slug and ms.package.libraryHasEntry(k, slug) then
                        local ok, res = pcall(ms.package.libraryActivate, k, slug)
                        if ok and res then alignedKinds[k] = true end
                    end
                end
            end

            ms.dev.log({
                type   = "system",
                event  = "profile_switch_complete",
                target = targetName,
            })

            hotswapLive()

            if ms.package and ms.package.reconcileActive then
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    if not alignedKinds[k] then
                        pcall(ms.package.reconcileActive, k)
                    end
                end
            end

            if ms.package and ms.package.setActiveProfile then
                pcall(ms.package.setActiveProfile, targetName)
            end

            ms.playSlot("update")
            ms.alert("Switched to \"" .. targetName .. "\".", 3, true)
            if ms.plugins and ms.plugins.scheduleOffer then
                pcall(ms.plugins.scheduleOffer)
            end
            ms.ui.markDirty()
            ms.ui.refresh()
            if ms.ui._actions and ms.ui._actions.libraryList then
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    pcall(ms.ui._actions.libraryList, { kind = k })
                end
            end
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
            -- END Lexer pass --

                if name then
                    table.insert(errs, "non-local global function definition: " .. name .. "()")
                end
            end

            return errs
        end

        local function importProfile()
            ms.playSlot("alert")
            hs.focus()
            local result = hs.dialog.chooseFileOrFolder(
                "Select an ms_macros.lua file to import",
                os.getenv("HOME") .. "/Downloads/",
                true, false, false
            )
            local target = hs.application.get(ms._targetApp)
            local selectedPath
            for _, v in pairs(result or {}) do
                if type(v) == "string" then selectedPath = v
                break end
            end
            if not selectedPath then
                if target then pcall(function() target:activate() end) end
                return
            end
            local meta = readMacroMeta(selectedPath)
            if not meta or not meta.name or meta.name == "" then
                if target then pcall(function() target:activate() end) end
                ms.alert("Could not read profile name.\nMake sure the file has ms.macroMeta = { name = \"...\" }.", 6)
                return
            end
            local folderName = sanitizeName(meta.name)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end

            local function _commit()
                hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                if not hs.fs.attributes(profilesPath .. folderName) then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not create profile folder.", 3)
                    return
                end
                local f = io.open(selectedPath, "rb")
                if not f then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not read the selected file.", 3)
                    return
                end
                local content = f:read("*all")
                f:close()
                local auditErrs = auditMacros(content)
                if #auditErrs > 0 then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 "
                        .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                    return
                end
                local dst    = profilesPath .. folderName .. "/ms_macros.lua"
                local copied = false
                local g = io.open(dst, "wb")
                if g then
                    g:write(content)
                    g:close()
                    copied = true
                end
                if not copied then
                    local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                end
                if not copied then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                    return
                end
                ms.playSlot("update")
                ms._profilesDirty = true
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                ms.ui.refresh()
                if target then pcall(function() target:activate() end) end
                hs.timer.doAfter(0.2, function()
                    ms.alert("Profile \"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles.", 5, true)
                end)
            end

            if hs.fs.attributes(profilesPath .. folderName) then
                ms.ui.modal({
                    title   = "Overwrite Profile?",
                    msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this file?",
                    confirm = "Replace",
                    cancel  = "Cancel",
                }, function(r)
                    if r.confirmed then
                        _commit()
                    else
                        if target then pcall(function() target:activate() end) end
                    end
                end)
            else
                _commit()
            end
        end

        -- Create a fresh profile entry without touching the active profile
        local function createNewProfile(seed)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            hs.fs.mkdir(profilesPath)

            local base, n, folderName = "New Profile", 0, nil
            repeat
                n = n + 1
                folderName = base .. " " .. n
            until not hs.fs.attributes(profilesPath .. folderName)

            local dir = profilesPath .. folderName
            hs.execute("mkdir -p " .. sq(dir))
            if not hs.fs.attributes(dir) then
                ms.alert("Could not create profile folder.", 3)
                return
            end

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

            -- Seed from the current setup, capturing live macros too
            if seed then
                if hs.fs.attributes(jsonPath) then
                    hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(dir .. "/ms_settings.json"))
                end
                if hs.fs.attributes(defaultPath) then
                    hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(dir .. "/ms_settings_default.json"))
                end
                if hs.fs.attributes(themePath) then
                    hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(dir .. "/ms_theme.json"))
                end
                copyDirContents(SoundActiveDir, dir .. "/sounds/active/")
                copyDirContents(SoundMacroDir,  dir .. "/sounds/macro/")
                -- Live handwritten macros overwrite the blank stub written above
                if hs.fs.attributes(macrosPath) then
                    hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(dir .. "/ms_macros.lua"))
                end
                -- Visual macros, authored tools, and helper vars travel too
                for _, cf in ipairs(profileContentFiles()) do
                    if hs.fs.attributes(cf.live) then
                        hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(dir .. "/" .. cf.name))
                    end
                end
                -- Bank the seeded slices as profile-named component packs (copy-only)
                if ms.package and ms.package.libraryImportDir then
                    for _, k in ipairs({ "macro", "theme", "sound" }) do
                        pcall(ms.package.libraryImportDir, k, dir,
                            { name = folderName, origin = "profile" })
                    end
                end
            end

            if not seed then
                local meta = {
                    name    = folderName,
                    version = "1.0.0",
                    author  = "You",
                    website = "",
                }
                local vf = io.open(dir .. "/ms_macros_visual.json", "w")
                if vf then
                    vf:write(hs.json.encode({
                        macros = {},
                        meta   = meta,
                    }, true))
                    vf:close()
                end
                if ms.compiler and ms.compiler._writeFile then
                    pcall(ms.compiler._writeFile, {}, meta, dir .. "/ms_macros_visual.lua")
                end
            end

            -- A blank profile spawns matching blank theme + sound packs
            if not seed and ms.package and ms.package.libraryCreateEmpty then
                for _, k in ipairs({ "macro", "theme", "sound" }) do
                    local ok, rec, err = pcall(ms.package.libraryCreateEmpty, k, folderName)
                    -- Log a failed pack creation instead of swallowing it
                    if not ok or not rec then
                        local why = (not ok) and tostring(rec) or tostring(err)
                        print("createNewProfile: libraryCreateEmpty(" .. k
                            .. ") did not create a pack: " .. why)
                        if ms.dev and ms.dev.log then
                            pcall(ms.dev.log, {
                                type  = "warning",
                                event = "profile_pack_create_failed",
                                kind  = k,
                                msg   = why,
                            })
                        end
                    end
                end
            end

            -- Record the profile's explicit component-pack links in packs.json
            if ms.package and ms.package.setProfilePacks
                and ms.package.libraryHasEntry and ms.package.librarySlug then
                local slug = ms.package.librarySlug(folderName)
                local refs = {}
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    if ms.package.libraryHasEntry(k, slug) then refs[k] = slug end
                end
                pcall(ms.package.setProfilePacks, folderName, refs)
            end

            ms._profilesDirty = true

            -- A blank profile switches to itself so it reads as aligned
            if not seed then
                ms.playSlot("update")
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                switchProfile(folderName)
                return
            end

            ms.playSlot("update")
            ms.alert("Created \"" .. folderName .. "\".", 3)
            -- markDirty forces refresh to rebuild the pushed state
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
            end
        end

        local function saveCurrentProfile()
            local name = activeProfile()
            if name == "" then
                ms.alert("Cannot save: no profile is active.\nUse Save as New Profile instead.", 5)
                return
            end
            local folderName = sanitizeName(name)
            local existing = getProfiles()
            local found = false
            for _, p in ipairs(existing) do
                if p == folderName then found = true
                break end
            end
            if not found then
                ms.alert("No saved profile named \"" .. name .. "\" found.\nUse Save as New Profile instead.", 4)
                return
            end
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            local dst = profilesPath .. folderName .. "/ms_macros.lua"
            local _, st = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(dst))
            if st ~= true then
                ms.alert("Could not update profile.", 3)
                return
            end
            if hs.fs.attributes(jsonPath) then
                hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
            end
            if hs.fs.attributes(defaultPath) then
                hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
            end
            if hs.fs.attributes(themePath) then
                hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
            end
            -- Sounds travel with the profile too
            local sndDst = profilesPath .. folderName .. "/sounds/"
            copyDirContents(SoundActiveDir, sndDst .. "active/")
            copyDirContents(SoundMacroDir,  sndDst .. "macro/")
            -- Visual macros, authored tools, and helper vars travel too.
            for _, cf in ipairs(profileContentFiles()) do
                if hs.fs.attributes(cf.live) then
                    hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(profilesPath .. folderName .. "/" .. cf.name))
                end
            end
            if ms.package and ms.package.libraryCapture and ms.package.setProfilePacks then
                local refs = {}
                local linked = (ms.package.getProfilePacks
                    and ms.package.getProfilePacks(folderName)) or {}
                for _, k in ipairs({ "theme", "sound", "macro" }) do
                    local into = (ms.package.libraryGetActive and ms.package.libraryGetActive(k))
                        or linked[k]
                    local rec = ms.package.libraryCapture(k, name, into)
                    if rec and rec.slug then refs[k] = rec.slug end
                end
                pcall(ms.package.setProfilePacks, folderName, refs)
                if ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end
            ms.playSlot("update")
            ms._profilesDirty = true
            ms.ui.markDirty()
            ms.ui.refresh()
            hs.timer.doAfter(0.2, function()
                ms.alert("Profile \"" .. name .. "\" updated.", 3, true)
            end)
        end

        -- Rename a profile: its folder, active marker and same-named packs
        local function renameProfile(oldName, newName)
            local oldFolder = sanitizeName(oldName or "")
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            local newFolder = sanitizeName(newName)
            if oldFolder == "" or newFolder == "" then
                ms.alert("Rename failed: invalid name.", 4)
                return
            end
            if newFolder ~= oldFolder then
                for _, p in ipairs(getProfiles()) do
                    if p == newFolder then
                        ms.alert("A profile named \"" .. newFolder .. "\" already exists.", 4)
                        return
                    end
                end
            end

            local isActive = (oldFolder == activeProfile())

            if newFolder ~= oldFolder and hs.fs.attributes(profilesPath .. oldFolder) then
                os.rename(profilesPath .. oldFolder, profilesPath .. newFolder)
            end

            -- Keep the profile's same-named packs aligned as the slug follows
            if ms.package and ms.package.libraryRenameEntry and ms.package.librarySlug then
                for _, k in ipairs({ "macro", "theme", "sound" }) do
                    pcall(ms.package.libraryRenameEntry, k,
                        ms.package.librarySlug(oldFolder), newFolder)
                end
            end

            if isActive and ms.package and ms.package.setActiveProfile then
                pcall(ms.package.setActiveProfile, newFolder)
            end

            ms._profilesDirty = true
            ms.playSlot("update")
            ms.alert("Renamed to \"" .. newFolder .. "\".", 3, true)
            if ms.ui then
                if ms.ui.markDirty then ms.ui.markDirty() end
                if ms.ui.refresh then ms.ui.refresh() end
                if ms.ui._actions and ms.ui._actions.libraryList then
                    for _, k in ipairs({ "macro", "theme", "sound" }) do
                        pcall(ms.ui._actions.libraryList, { kind = k })
                    end
                end
            end
        end
        ms.renameProfile = renameProfile

        local function profilePkgFiles()
            local list = {
                {
                    live = macrosPath,
                    name = "ms_macros.lua",
                },
                {
                    live = jsonPath,
                    name = "ms_settings.json",
                },
                {
                    live = defaultPath,
                    name = "ms_settings_default.json",
                },
                {
                    live = themePath,
                    name = "ms_theme.json",
                },
            }
            for _, cf in ipairs(profileContentFiles()) do
                list[#list + 1] = cf
            end
            return list
        end
        ms.profilePkgFiles = profilePkgFiles

        local function stageProfilePkg(tmpDir)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            os.execute("rm -rf " .. sq(tmpDir))
            os.execute("mkdir -p " .. sq(tmpDir))
            if not hs.fs.attributes(macrosPath) then
                os.execute("rm -rf " .. sq(tmpDir))
                return false, "could not read ms_macros.lua"
            end
            for _, cf in ipairs(profilePkgFiles()) do
                if hs.fs.attributes(cf.live) then
                    hs.execute("/bin/cp " .. sq(cf.live) .. " " .. sq(tmpDir .. cf.name))
                end
            end
            local soundsDir = tmpDir .. "sounds/"
            local counts = {
                sounds = 0,
                macroSounds = 0,
                fonts = 0,
            }
            local bundledPaths = {}
            for _, soundName in pairs(ms.soundAssign or {}) do
                if type(soundName) == "string" and ms.sounds then
                    local soundPath = ms.sounds[soundName]
                    if soundPath and hs.fs.attributes(soundPath) then
                        local filename = soundPath:match("([^/\\]+)$")
                        local subdir = ""
                        pcall(function()
                            if soundPath:sub(1, #SoundActiveDir) == SoundActiveDir then
                                subdir = "active/"
                            elseif soundPath:sub(1, #SoundDefaultsDir) == SoundDefaultsDir then
                                subdir = "defaults/"
                            end
                        end)
                        local relPath = subdir .. filename
                        if filename and not bundledPaths[relPath] then
                            local destDir = soundsDir .. subdir
                            os.execute("mkdir -p " .. sq(destDir))
                            hs.execute("/bin/cp " .. sq(soundPath) .. " " .. sq(destDir .. filename))
                            bundledPaths[relPath] = true
                            counts.sounds = counts.sounds + 1
                        end
                    end
                end
            end
            local usedMacroSounds = {}
            for _, soundName in pairs(ms.soundAssign or {}) do
                if type(soundName) == "string" and ms.macroSounds and ms.macroSounds[soundName] then
                    usedMacroSounds[soundName] = ms.macroSounds[soundName]
                end
            end
            for _, soundPath in pairs(usedMacroSounds) do
                if hs.fs.attributes(soundPath) then
                    local filename = soundPath:match("([^/\\]+)$")
                    local relPath = "macro/" .. filename
                    if filename and not bundledPaths[relPath] then
                        local destDir = soundsDir .. "macro/"
                        os.execute("mkdir -p " .. sq(destDir))
                        hs.execute("/bin/cp " .. sq(soundPath) .. " " .. sq(destDir .. filename))
                        bundledPaths[relPath] = true
                        counts.macroSounds = counts.macroSounds + 1
                    end
                end
            end
            local fontName = (ms._theme and ms._theme.font) or nil
            if type(fontName) == "string" and #fontName > 0 and not fontName:find("[/\\]") then
                local fontsSrc = hs.configdir .. "/ui/fonts/"
                if hs.fs.attributes(fontsSrc) then
                    local fontsDir = tmpDir .. "fonts/"
                    local pattern = fontName:lower():gsub("%-", "%%-")
                    for file in hs.fs.dir(fontsSrc) do
                        if file ~= "." and file ~= ".." then
                            local lower = file:lower()
                            if lower:match("^" .. pattern) and (lower:match("%.ttf$") or lower:match("%.otf$")) then
                                os.execute("mkdir -p " .. sq(fontsDir))
                                hs.execute("/bin/cp " .. sq(fontsSrc .. file) .. " " .. sq(fontsDir .. file))
                                counts.fonts = counts.fonts + 1
                            end
                        end
                    end
                end
            end
            return true, counts
        end
        ms.stageProfilePkg = stageProfilePkg

        local function buildProfilePkg(outPath)
            local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
            local tmpDir = backupDir("tmp") .. "mspkg_export/"
            local staged, counts = stageProfilePkg(tmpDir)
            if not staged then return false, counts end
            hs.execute("cd " .. sq(tmpDir) .. " && zip -r " .. sq(outPath) .. " . 2>/dev/null")
            os.execute("rm -rf " .. sq(tmpDir))
            return hs.fs.attributes(outPath) ~= nil, counts
        end
        ms.buildProfilePkg = buildProfilePkg

        local function exportProfilePkg()
            local name = activeProfile()
            if name == "" then name = "unnamed" end
            local outName = name .. ".mspkg"
            local outPath = os.getenv("HOME") .. "/Downloads/" .. outName
            local ok, counts = buildProfilePkg(outPath)
            if ok then
                ms.playSlot("alert")
                local msg = "Exported " .. outName .. " to ~/Downloads/"
                if counts.sounds > 0 then
                    msg = msg .. "\n" .. counts.sounds .. " sound" .. (counts.sounds > 1 and "s" or "") .. " bundled."
                end
                if counts.macroSounds > 0 then
                    msg = msg .. "\n" .. counts.macroSounds .. " macro sound" .. (counts.macroSounds > 1 and "s" or "") .. " bundled."
                end
                if counts.fonts > 0 then
                    msg = msg .. "\n" .. counts.fonts .. " font" .. (counts.fonts > 1 and "s" or "") .. " bundled."
                end
                ms.alert(msg, 5, true)
            elseif counts then
                ms.alert("Export failed: " .. tostring(counts) .. ".", 4)
            else
                ms.alert("Export failed: could not create " .. outName .. ".", 4)
            end
        end

        local function importProfilePkg()
            hs.focus()
            local result = hs.dialog.chooseFileOrFolder(
                "Select a .mspkg profile package to import",
                os.getenv("HOME") .. "/Downloads/",
                true, false, false, {
                    "mspkg",
                    "zip",
                }
            )
            local target = hs.application.get(ms._targetApp)
            local selectedPath
            for _, v in pairs(result or {}) do
                if type(v) == "string" then selectedPath = v
                break end
            end
            if not selectedPath then
                if target then pcall(function() target:activate() end) end
                return
            end
            local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
            local tmpDir = backupDir("tmp") .. "mspkg_import/"
            os.execute("rm -rf " .. sq(tmpDir))
            os.execute("mkdir -p " .. sq(tmpDir))
            hs.execute("unzip -o " .. sq(selectedPath) .. " -d " .. sq(tmpDir) .. " 2>/dev/null")
            local baseDir = tmpDir
            local macroSrc = tmpDir .. "ms_macros.lua"
            if not hs.fs.attributes(macroSrc) then
                local found = false
                for entry in hs.fs.dir(tmpDir) do
                    if entry ~= "." and entry ~= ".." then
                        local sub = tmpDir .. entry .. "/"
                        if hs.fs.attributes(sub) and hs.fs.attributes(sub .. "ms_macros.lua") then
                            baseDir = sub
                            macroSrc = sub .. "ms_macros.lua"
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    for entry in hs.fs.dir(tmpDir) do
                        if entry ~= "." and entry ~= ".." then
                            local sub = tmpDir .. entry .. "/"
                            if hs.fs.attributes(sub) and hs.fs.attributes(sub .. "ms_settings.json") then
                                baseDir = sub
                                found = true
                                break
                            end
                        end
                    end
                    if not found and hs.fs.attributes(tmpDir .. "ms_settings.json") then
                        baseDir = tmpDir
                        found = true
                    end
                    if found then
                        local zipName = selectedPath:match("([^/]+)%.mspkg$") or selectedPath:match("([^/]+)%.zip$") or "imported"
                        local folderName = sanitizeName(zipName)
                        hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                        local settingsSrc = baseDir .. "ms_settings.json"
                        if hs.fs.attributes(settingsSrc) then
                            hs.execute("/bin/cp " .. sq(settingsSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                        end
                        local defSrc = baseDir .. "ms_settings_default.json"
                        if hs.fs.attributes(defSrc) then
                            hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                        end
                        local themeSrc = baseDir .. "ms_theme.json"
                        if hs.fs.attributes(themeSrc) then
                            hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                        end
                        if target then pcall(function() target:activate() end) end
                        ms.alert("Imported settings as \"" .. zipName .. "\".\n(no macros in package)", 4)
                        os.execute("rm -rf " .. sq(tmpDir))
                        return
                    end
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import failed: package does not contain ms_macros.lua or ms_settings.json.", 5)
                    os.execute("rm -rf " .. sq(tmpDir))
                    return
                end
            end
            local mf = io.open(macroSrc, "rb")
            if not mf then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import failed: could not read ms_macros.lua from package.", 4)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local content = mf:read("*all")
            mf:close()
            local auditErrs = auditMacros(content)
            if #auditErrs > 0 then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 " .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local meta = readMacroMeta(macroSrc)
            if not meta or not meta.name or meta.name == "" then
                if target then pcall(function() target:activate() end) end
                ms.alert("Import failed: could not read profile name from ms_macros.lua.", 5)
                os.execute("rm -rf " .. sq(tmpDir))
                return
            end
            local folderName = sanitizeName(meta.name)

            local function _commit()
                hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                local dst = profilesPath .. folderName .. "/ms_macros.lua"
                local copied = false
                local gf = io.open(dst, "wb")
                if gf then gf:write(content)
                gf:close()
                copied = true end
                if not copied then
                    local _, st = hs.execute("/bin/cp " .. sq(macroSrc) .. " " .. sq(dst))
                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                end
                if not copied then
                    if target then pcall(function() target:activate() end) end
                    ms.alert("Import failed: could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                    os.execute("rm -rf " .. sq(tmpDir))
                    return
                end
                local settingsSrc = baseDir .. "ms_settings.json"
                if hs.fs.attributes(settingsSrc) then
                    hs.execute("/bin/cp " .. sq(settingsSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                end
                local defSrc = baseDir .. "ms_settings_default.json"
                if hs.fs.attributes(defSrc) then
                    hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                end
                local themeSrc = baseDir .. "ms_theme.json"
                if hs.fs.attributes(themeSrc) then
                    hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                end
                local soundsAdded = {}
                local macroAdded = {}
                local _sndDirPrefix = {
                    [SoundDefaultsDir] = "d_",
                    [SoundActiveDir]   = "a_",
                    [SoundMacroDir]    = "m_",
                }
                local _sndVariantSlots = 3
                local _sndConflicts = {}

                local function _readFile(path)
                    local f = io.open(path, "rb")
                    if not f then return nil end
                    local d = f:read("*all")
                    f:close()
                    return d
                end
                local function _writeFile(path, data)
                    local f = io.open(path, "wb")
                    if not f then return false end
                    f:write(data)
                    f:close()
                    return true
                end

                local function _placeSnd(srcSnd, dstDir, file, added)
                    if hs.fs.attributes(srcSnd, "mode") ~= "file" then return end
                    if not hs.fs.attributes(dstDir) then
                        hs.execute("mkdir -p " .. sq(dstDir))
                    end
                    local pfx  = _sndDirPrefix[dstDir]
                    local stem = file:match("^(.+)%.[^%.]+$") or file
                    local ext  = file:match("%.([^%.]+)$")
                    ext = ext and ("." .. ext) or ""
                    if pfx and stem:sub(1, #pfx) ~= pfx then stem = pfx .. stem end
                    local base = stem:match("^(.-)%d+$") or stem

                    local function slotName(i)
                        return base .. (i > 1 and tostring(i) or "") .. ext
                    end

                    local data = _readFile(srcSnd)
                    if not data then return end

                    local free
                    for i = 1, _sndVariantSlots do
                        local p = dstDir .. slotName(i)
                        if not hs.fs.attributes(p) then
                            free = free or i
                        elseif _readFile(p) == data then
                            return
                        end
                    end
                    if free then
                        local name = slotName(free)
                        if _writeFile(dstDir .. name, data) then
                            table.insert(added, name:match("^(.+)%.[^%.]+$") or name)
                        end
                    else
                        table.insert(_sndConflicts, {
                            data = data,
                            dir = dstDir,
                            base = base,
                            ext = ext,
                            added = added,
                        })
                    end
                end

                local function _importSndDir(srcDir, dstDir, added)
                    if not hs.fs.attributes(srcDir) then return end
                    for file in hs.fs.dir(srcDir) do
                        if file ~= "." and file ~= ".." then
                            _placeSnd(srcDir .. file, dstDir, file, added)
                        end
                    end
                end
                local soundsDir = baseDir .. "sounds/"
                if hs.fs.attributes(soundsDir) then
                    local hasSubdirs = hs.fs.attributes(soundsDir .. "active/")
                        or hs.fs.attributes(soundsDir .. "defaults/")
                        or hs.fs.attributes(soundsDir .. "macro/")
                    if hasSubdirs then
                        _importSndDir(soundsDir .. "active/",   SoundActiveDir,   soundsAdded)
                        pcall(function() _importSndDir(soundsDir .. "defaults/", SoundDefaultsDir, soundsAdded) end)
                        _importSndDir(soundsDir .. "macro/",    SoundMacroDir,    macroAdded)
                    else
                        local hasSounds = false
                        local legacyFiles = {}
                        for file in hs.fs.dir(soundsDir) do
                            if file ~= "." and file ~= ".." then
                                if hs.fs.attributes(soundsDir .. file, "mode") == "file" then
                                    hasSounds = true
                                    table.insert(legacyFiles, file)
                                end
                            end
                        end
                        if hasSounds then
                            for _, f in ipairs(legacyFiles) do
                                local name = f:match("^(.+)%.[^%.]+$") or f
                                local dest = SoundActiveDir
                                if name:sub(1, 2) == "d_" then
                                    dest = SoundDefaultsDir
                                elseif name:sub(1, 2) == "m_" then
                                    dest = SoundMacroDir
                                elseif name:sub(1, 2) == "a_" then
                                    dest = SoundActiveDir
                                end
                                local added = (dest == SoundMacroDir) and macroAdded or soundsAdded
                                _placeSnd(soundsDir .. f, dest, f, added)
                            end
                        end
                    end
                end
                local macroSrc = baseDir .. "macro/"
                if hs.fs.attributes(macroSrc) then
                    _importSndDir(macroSrc, SoundMacroDir, macroAdded)
                end
                if #soundsAdded > 0 or #macroAdded > 0 then
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                end

                local function _resolveSndConflicts(idx)
                    local c = _sndConflicts[idx]
                    if not c then
                        if idx > 1 then
                            ms.saveSettings()
                            ms._soundsDirty = true
                            ms._discoverSounds()
                            ms.ui.refresh()
                        end
                        return
                    end
                    local slots = {}
                    for i = 1, _sndVariantSlots do
                        slots[#slots + 1] = "  " .. i .. ". "
                            .. c.base .. (i > 1 and tostring(i) or "")
                    end
                    ms.ui.prompt({
                        title   = "Replace a Sound Variant?",
                        msg     = "\"" .. c.base .. "\" already has "
                            .. _sndVariantSlots .. " variants:\n"
                            .. table.concat(slots, "\n")
                            .. "\n\nEnter 1-" .. _sndVariantSlots
                            .. " to replace one, or cancel to skip this sound:",
                        confirm = "Replace",
                        cancel  = "Skip",
                        default = "",
                    }, function(r)
                        local n = r.confirmed and tonumber(r.value)
                        if n and n >= 1 and n <= _sndVariantSlots then
                            local name = c.base .. (n > 1 and tostring(n) or "") .. c.ext
                            if _writeFile(c.dir .. name, c.data) then
                                table.insert(c.added, name:match("^(.+)%.[^%.]+$") or name)
                            end
                        elseif r.confirmed then
                            ms.alert("Invalid slot, skipped \"" .. c.base .. "\".", 2)
                        end
                        _resolveSndConflicts(idx + 1)
                    end)
                end
                if #_sndConflicts > 0 then _resolveSndConflicts(1) end
                local fontsAdded = 0
                do
                    local fontsDir = baseDir .. "fonts/"
                    if hs.fs.attributes(fontsDir) then
                        local dstDir = os.getenv("HOME") .. "/Library/Fonts/"
                        hs.fs.mkdir(dstDir)
                        for file in hs.fs.dir(fontsDir) do
                            if file ~= "." and file ~= ".." then
                                local ext = file:match("%.([^%.]+)$")
                                if ext == "ttf" or ext == "otf" or ext == "woff" or ext == "woff2" then
                                    local srcFont = fontsDir .. file
                                    local dstFont = dstDir .. file
                                    if not hs.fs.attributes(dstFont) then
                                        local ff = io.open(srcFont, "rb")
                                        if ff then
                                            local fdata = ff:read("*all")
                                            ff:close()
                                            local of = io.open(dstFont, "wb")
                                            if of then of:write(fdata)
                                            of:close()
                                            fontsAdded = fontsAdded + 1 end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                os.execute("rm -rf " .. sq(tmpDir))
                if target then pcall(function() target:activate() end) end
                ms.playSlot("update")
                hs.timer.doAfter(0.2, function()
                    local msg = "\"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles."
                    if #soundsAdded > 0 then
                        msg = msg .. "\n" .. #soundsAdded .. " sound" .. (#soundsAdded > 1 and "s" or "") .. " added to library."
                    end
                    if #macroAdded > 0 then
                        msg = msg .. "\n" .. #macroAdded .. " macro sound" .. (#macroAdded > 1 and "s" or "") .. " added."
                    end
                    if fontsAdded > 0 then
                        msg = msg .. "\n" .. fontsAdded .. " font" .. (fontsAdded > 1 and "s" or "") .. " installed."
                    end
                    ms.alert(msg, 6, true)
                    ms._profilesDirty = true
                    ms.ui.markDirty()
                    ms.ui.refresh()
                end)
            end

            if hs.fs.attributes(profilesPath .. folderName) then
                ms.ui.modal({
                    title   = "Overwrite Profile?",
                    msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this package?",
                    confirm = "Replace",
                    cancel  = "Cancel",
                }, function(r)
                    if r.confirmed then
                        _commit()
                    else
                        os.execute("rm -rf " .. sq(tmpDir))
                        if target then pcall(function() target:activate() end) end
                    end
                end)
            else
                _commit()
            end
        end

        -- The profile the live setup is "on", from the explicit active marker
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
        ms.importProfile      = importProfile
        ms.importProfilePkg   = importProfilePkg
        ms.exportProfilePkg   = exportProfilePkg
        ms.createNewProfile   = createNewProfile
        ms.saveCurrentProfile = saveCurrentProfile

        ctx.sanitizeName = sanitizeName
        ctx.getProfiles = getProfiles
        ctx.switchProfile = switchProfile
        ctx.importProfile = importProfile
        ctx.createNewProfile = createNewProfile
        ctx.saveCurrentProfile = saveCurrentProfile
    -- END Profile Management --
end

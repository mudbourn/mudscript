return function(ms, ctx)
    -- Profile Import & Export --
        local sanitizeName = ctx.sanitizeName
        local readMacroMeta = ctx.readMacroMeta
        local copyDirContents = ctx.copyDirContents
        local newMeta = ctx.newMeta
        local v2Guard = ctx.v2Guard
        local sq = ctx.sq

        local function refocusTarget()
            local target = hs.application.get(ms._targetApp)
            if target then pcall(function() target:activate() end) end
        end

        local function importProfile()
            if not v2Guard() then return end
            ms.playSlot("alert")
            hs.focus()
            local result = hs.dialog.chooseFileOrFolder(
                "Select an ms_macros.lua file to import",
                os.getenv("HOME") .. "/Downloads/",
                true, false, false
            )
            local selectedPath
            for _, v in pairs(result or {}) do
                if type(v) == "string" then
                    selectedPath = v
                    break
                end
            end
            if not selectedPath then
                refocusTarget()
                return
            end
            local meta = readMacroMeta(selectedPath)
            if not meta or not meta.name or meta.name == "" then
                refocusTarget()
                ms.alert("Could not read profile name.\nMake sure the file has ms.macroMeta = { name = \"...\" }.", 6)
                return
            end
            local folderName = sanitizeName(meta.name)
            if not ms.profile.safeName(folderName) then
                refocusTarget()
                ms.alert("Import failed: the profile name is not usable.", 4)
                return
            end
            if folderName == ms.activeProfile() then
                refocusTarget()
                ms.alert("\"" .. folderName .. "\" is the active profile.\nSwitch to another profile before replacing it.", 6)
                return
            end

            local function commit()
                local f = io.open(selectedPath, "rb")
                if not f then
                    refocusTarget()
                    ms.alert("Could not read the selected file.", 3)
                    return
                end
                local content = f:read("*all")
                f:close()
                local auditErrs = ms.auditMacros(content)
                if #auditErrs > 0 then
                    refocusTarget()
                    ms.alert("Import rejected, security scan failed:\n  - "
                        .. table.concat(auditErrs, "\n  - "), 8)
                    return
                end
                local dir = ms.profile.ensure(folderName)
                local g = io.open(dir .. "/ms_macros.lua", "wb")
                if not g then
                    refocusTarget()
                    ms.alert("Could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                    return
                end
                g:write(content)
                g:close()
                if not ms.profile.readMeta(folderName) then
                    ms.profile.writeMeta(folderName, newMeta(folderName, {
                        origin = "import",
                        author = type(meta.author) == "string" and meta.author or "",
                    }))
                end
                pcall(ms.stampProfileRequires, folderName)
                ms.playSlot("update")
                ms._profilesDirty = true
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                ms.ui.refresh()
                refocusTarget()
                hs.timer.doAfter(0.2, function()
                    ms.alert("Profile \"" .. meta.name .. "\" imported.\nSwitch to it from Settings > Profiles.", 5, true)
                    if ms.plugins and ms.plugins.offerForProfile then
                        ms.plugins.offerForProfile(folderName)
                    end
                end)
            end

            if ms.profile.exists(folderName) then
                ms.ui.modal({
                    title   = "Overwrite Profile?",
                    msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace its macros with this file?",
                    confirm = "Replace",
                    cancel  = "Cancel",
                }, function(r)
                    if r.confirmed then
                        commit()
                    else
                        refocusTarget()
                    end
                end)
            else
                commit()
            end
        end

        local function importProfilePkg()
            if ms.ui and ms.ui._actions and ms.ui._actions.importPackage then
                ms.ui._actions.importPackage()
            end
        end

        local function exportProfilePkg()
            if not v2Guard() then return end
            local name = ms.activeProfile()
            if name == "" then name = "unnamed" end
            pcall(ms.saveSettings)
            pcall(ms.stampProfileRequires, name)
            local meta = ms.profile.readMeta(name) or {}
            local outName = name .. ".mspkg"
            local outPath = os.getenv("HOME") .. "/Downloads/" .. outName
            local files = ms.package.collect("profile", { name = name })
            local manifest, err = ms.package.pack({
                type     = "profile",
                name     = name,
                version  = meta.version,
                author   = meta.author,
                requires = ms.version and { mudscript = ms.version } or nil,
                files    = files,
                out      = outPath,
            })
            if manifest then
                ms.playSlot("alert")
                ms.alert("Exported " .. outName .. " to ~/Downloads/", 5, true)
            else
                ms.alert("Export failed: " .. tostring(err) .. ".", 4)
            end
        end
    -- END Profile Import & Export --

    -- Profile Staging --
        local function stageThemeFont(tmpDir)
            local fontName = (ms._theme and ms._theme.font) or nil
            if type(fontName) ~= "string" or #fontName == 0 or fontName:find("[/\\]") then return 0 end
            local fontsSrc = hs.configdir .. "/ui/fonts/"
            if not hs.fs.attributes(fontsSrc) then return 0 end
            local copied = 0
            local pattern = fontName:lower():gsub("%-", "%%-")
            for file in hs.fs.dir(fontsSrc) do
                if file ~= "." and file ~= ".." then
                    local lower = file:lower()
                    if lower:match("^" .. pattern) and (lower:match("%.ttf$") or lower:match("%.otf$")) then
                        os.execute("mkdir -p " .. sq(tmpDir .. "ui/fonts/"))
                        hs.execute("/bin/cp " .. sq(fontsSrc .. file) .. " " .. sq(tmpDir .. "ui/fonts/" .. file))
                        copied = copied + 1
                    end
                end
            end
            return copied
        end

        local function stageProfilePkg(tmpDir, name)
            local target = (name and name ~= "") and name or ms.profile.active()
            if ms.profile.isV2() and not ms.profile.exists(target) then
                return false, "profile not found"
            end
            local srcDir = ms.profile.dir(target)
            os.execute("rm -rf " .. sq(tmpDir))
            os.execute("mkdir -p " .. sq(tmpDir))
            if not hs.fs.attributes(srcDir .. "/ms_macros.lua") then
                os.execute("rm -rf " .. sq(tmpDir))
                return false, "could not read ms_macros.lua"
            end
            for _, rel in ipairs(ms.profile.CONTENT_FILES) do
                local src = srcDir .. "/" .. rel
                if hs.fs.attributes(src) then
                    local parent = (tmpDir .. rel):match("^(.*)/[^/]+$")
                    os.execute("mkdir -p " .. sq(parent))
                    hs.execute("/bin/cp " .. sq(src) .. " " .. sq(tmpDir .. rel))
                end
            end
            if hs.fs.attributes(srcDir .. "/profile.json") then
                hs.execute("/bin/cp " .. sq(srcDir .. "/profile.json") .. " " .. sq(tmpDir .. "profile.json"))
            end
            local counts = {
                sounds = 0,
                macroSounds = 0,
                fonts = 0,
            }
            counts.sounds = copyDirContents(srcDir .. "/sounds/active", tmpDir .. "sounds/active")
            counts.macroSounds = copyDirContents(srcDir .. "/sounds/macro", tmpDir .. "sounds/macro")
            if target == ms.profile.active() then counts.fonts = stageThemeFont(tmpDir) end
            return true, counts
        end
        ms.stageProfilePkg = stageProfilePkg
    -- END Profile Staging --

    ms.importProfile = importProfile
    ms.importProfilePkg = importProfilePkg
    ms.exportProfilePkg = exportProfilePkg
    ctx.importProfile = importProfile
end

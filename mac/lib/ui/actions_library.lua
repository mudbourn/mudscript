return function(ms, ctx)
    local MsUI = ctx.MsUI
    local sq = ctx.sq
    local profilesPath = ctx.profilesPath
    local _savedEditor = ctx._savedEditor
    local _editorName = ctx._editorName
    local _pickEditor = ctx._pickEditor

    return {
            -- Profiles --
                switchProfile = function(data) if data.name then ms.switchProfile(data.name) end end,

                renameProfile = function(data)
                    if data.name and data.newName and ms.renameProfile then
                        ms.renameProfile(data.name, data.newName)
                    end
                end,

                deleteProfile = function(data)
                    if not data.name then return end
                    local targetName = ms.sanitizeName(data.name)
                    local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                    if targetName == "" or targetName == activeName then return end
                    local dir = profilesPath .. targetName
                    if not hs.fs.attributes(dir) then return end
                    os.execute("rm -rf " .. sq(dir))
                    if ms.package and ms.package.libraryRemove then
                        for _, k in ipairs({ "macro", "theme", "sound" }) do
                            pcall(ms.package.libraryRemove, k, targetName)
                        end
                    end
                    ms._profilesDirty = true
                    ms.ui.markDirty()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.05, function()
                        ms.alert("Profile \"" .. data.name .. "\" deleted.", 2, true)
                        ms.ui.refresh()
                        if ms.ui._actions and ms.ui._actions.libraryList then
                            for _, k in ipairs({ "macro", "theme", "sound" }) do
                                pcall(ms.ui._actions.libraryList, { kind = k })
                            end
                        end
                    end)
                end,

                clearProfiles = function()
                    local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                    if activeName == "" then return end
                    if not hs.fs.attributes(profilesPath) then return end
                    local deleted = 0
                    for entry in hs.fs.dir(profilesPath) do
                        if entry ~= "." and entry ~= ".." then
                            local safe = ms.sanitizeName(entry)
                            if safe ~= "" and safe ~= activeName then
                                local dir = profilesPath .. entry
                                local attr = hs.fs.attributes(dir)
                                if attr and attr.mode == "directory" then
                                    os.execute("rm -rf " .. sq(dir))
                                    if ms.package and ms.package.libraryRemove then
                                        for _, k in ipairs({ "macro", "theme", "sound" }) do
                                            pcall(ms.package.libraryRemove, k, safe)
                                        end
                                    end
                                    deleted = deleted + 1
                                end
                            end
                        end
                    end
                    ms._profilesDirty = true
                    ms.ui.markDirty()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.05, function()
                        ms.alert(deleted .. " profile" .. (deleted == 1 and "" or "s") .. " deleted.", 3, true)
                        ms.ui.refresh()
                        if ms.ui._actions and ms.ui._actions.libraryList then
                            for _, k in ipairs({ "macro", "theme", "sound" }) do
                                pcall(ms.ui._actions.libraryList, { kind = k })
                            end
                        end
                    end)
                end,

                importProfile     = function() ms.importProfile() end,
                createNewProfile  = function(data) ms.createNewProfile(data and data.seed == true) end,
                saveCurrentProfile = function() ms.saveCurrentProfile() end,
            -- END --

            -- Editors & Windows --
                editMacros = function(data)
                    local path = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"

                    local function openIn(app)
                        if app then
                            os.execute("open -a '" .. app .. "' '" .. path .. "'")
                        else
                            os.execute("open -t '" .. path .. "'")
                        end
                    end

                    if not (data and data.ack) and not ms._editMacrosAck then
                        ms.playSlot("alert")
                        ms.shell.eval("window.msEditMacrosNotice && msEditMacrosNotice.show()")
                        return
                    end
                    if not ms._editMacrosAck then
                        ms._editMacrosAck = true
                        if ms.saveSettings then ms.saveSettings() end
                    end

                    local editor = _savedEditor()
                    if editor then
                        openIn(editor)
                    else
                        _pickEditor(function(app) openIn(app) end)
                    end
                end,

                chooseMacroEditor = function()
                    ms.playSlot("interact")
                    local current = _editorName(_savedEditor())
                    ms.ui.modal({
                        title   = "Change macro editor",
                        msg     = "Pick the app mudscript opens ms_macros.lua in."
                            .. (current and ("\n\nCurrent: " .. current) or "\n\nNo editor set yet."),
                        confirm = "Choose editor...",
                        cancel  = "Cancel",
                    }, function(res)
                        if not (res and res.confirmed) then return end
                        _pickEditor(function(app)
                            ms.playSlot("update")
                            ms.alert("Macro editor set to " .. (_editorName(app) or "your pick") .. ".", 4, true)
                        end)
                    end)
                end,

                editThemeJson = function()
                    local path = os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json"

                    if not hs.fs.attributes(path) then
                        local f = io.open(path, "w")
                        if f then
                            f:write(hs.json.encode(ms._theme or {}, true))
                            f:close()
                        end
                    end

                    local function openIn(app)
                        if app then
                            os.execute("open -a '" .. app .. "' '" .. path .. "'")
                        else
                            os.execute("open -t '" .. path .. "'")
                        end
                    end

                    local editor     = _savedEditor()
                    local editorName = _editorName(editor)

                    ms.playSlot("alert")
                    ms.ui.modal({
                        title   = "Edit theme JSON",
                        msg     = "Opens ms_theme.json, the raw theme file. Colours take "
                            .. "#rgb, #rrggbb, or #rrggbbaa where the last pair is opacity. "
                            .. "Reload the theme to apply your edits."
                            .. (editorName and ("\n\nEditor: " .. editorName) or ""),
                        confirm = editorName and ("Open in " .. editorName) or "Choose editor...",
                        cancel  = "Cancel",
                    }, function(res)
                        if not (res and res.confirmed) then return end
                        if editor then
                            openIn(editor)
                        else
                            _pickEditor(function(app) openIn(app) end)
                        end
                    end)
                end,

                setThemeKey = function(data)
                    if not data.key or not ms.saveTheme then return end
                    local value = data.value
                    if type(value) ~= "string" and type(value) ~= "number" then return end
                    ms.saveTheme({ [data.key] = value })
                    if data.key == "radius" or data.key == "windowRadius" then
                        pcall(function() ms.shell.applyWindowRadius() end)
                    end
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                resetTheme = function()
                    if not ms.resetTheme then return end
                    ms.resetTheme()
                    pcall(function() ms.shell.applyWindowRadius() end)
                    ms.playSlot("reset")
                    ms.alert("Theme reset to defaults.\nYour old file was kept as ms_theme.json.bak", 4, true)
                    ms.ui.refresh()
                end,
            -- END --

            -- Packages --
                exportPackage = function(data)
                    local kind = data and data.type
                    if not (ms.package and ms.package.collect and kind) then return end

                    local collectOpts, namedProfile = nil, nil
                    if kind == "profile" and data.profileName then
                        local safe = ms.sanitizeName(data.profileName)
                        local pdir = profilesPath .. safe
                        if safe == "" or not hs.fs.attributes(pdir) then
                            ms.alert("Profile \"" .. tostring(data.profileName) .. "\" not found.", 4)
                            return
                        end
                        collectOpts = { configDir = pdir .. "/" }
                        namedProfile = safe
                    end

                    local isSlice = false
                    if data.slug and ms.package.libraryFilesDir then
                        local fdir = ms.package.libraryFilesDir(kind, data.slug)
                        if not (fdir and hs.fs.attributes(fdir)) then
                            ms.alert("Pack not found in library.", 4)
                            return
                        end
                        collectOpts = { baseDir = fdir }
                        namedProfile = ms.sanitizeName(data.name or "")
                        isSlice = true
                    end

                    local files = ms.package.collect(kind, collectOpts)
                    if kind == "sound" and not isSlice then
                        local assignPath = ms.package.exportSoundAssign()
                        if assignPath then files["sound_assign.json"] = assignPath end
                    end
                    if next(files) == nil then
                        ms.alert("Nothing to export as a " .. kind .. " package.", 4)
                        return
                    end

                    ms.playSlot("alert")
                    hs.focus()
                    local chosen = hs.dialog.chooseFileOrFolder(
                        "Choose where to save the " .. kind .. " package",
                        os.getenv("HOME") .. "/Documents", false, true, false
                    )
                    local dir
                    for _, v in pairs(chosen or {}) do
                        if type(v) == "string" then dir = v
                        break end
                    end
                    ms.ui.show()
                    if not dir then return end

                    local meta = namedProfile and {} or (ms.macroMeta or {})
                    local base = namedProfile or ms.sanitizeName(meta.name or "mudscript")
                    if base == "" then base = "mudscript" end
                    local out = dir:gsub("/$", "") .. "/" .. base .. "-" .. kind .. ".mspkg"

                    local manifest, err = ms.package.pack({
                        type    = kind,
                        name    = base .. " " .. kind,
                        version = (type(meta.version) == "string" and meta.version ~= "") and meta.version or nil,
                        author  = meta.author,
                        website = meta.website,
                        files   = files,
                        out     = out,
                    })
                    hs.timer.doAfter(0.15, function()
                        if manifest then
                            ms.playSlot("update")
                            ms.alert("Exported " .. out:match("([^/]+)$") ..
                                "\nBuilt on " .. ms.package.osLabel(manifest) .. ".", 3, true)
                        else
                            ms.alert("Export failed:\n" .. tostring(err), 5)
                        end
                    end)
                end,

                importPackage = function()
                    if not (ms.package and ms.package.install) then return end
                    ms.playSlot("alert")
                    hs.focus()
                    local chosen = hs.dialog.chooseFileOrFolder(
                        "Select a .mspkg package to import",
                        os.getenv("HOME") .. "/Documents", true, false, false
                    )
                    local path
                    for _, v in pairs(chosen or {}) do
                        if type(v) == "string" then path = v
                        break end
                    end
                    ms.ui.show()
                    if not path then return end

                    local function finish(result, err)
                        hs.timer.doAfter(0.15, function()
                            if not result then
                                ms.alert("Import failed:\n" .. tostring(err), 5)
                                return
                            end
                            if ms._soundsDirty then ms._discoverSounds() end
                            if ms.loadTheme then ms.loadTheme() end
                            ms.playSlot("update")
                            if result.manifest.type == "profile" then
                                ms._profilesDirty = true
                                ms.alert(
                                    "\"" .. (result.profile or result.manifest.name
                                        or "Profile") .. "\" imported.\n" ..
                                    "Switch to it from Settings \xe2\x86\x92 Profiles.",
                                    5, true
                                )
                                if ms.ui.markDirty then ms.ui.markDirty() end
                            else
                                ms.alert(
                                    (result.manifest.name or "Package") .. " imported (" ..
                                    #result.installed .. " files).", 4, true
                                )
                            end
                            ms.ui.refresh()
                        end)
                    end

                    local result, err = ms.package.install(path)
                    local _peek = ms.package.inspect(path)
                    local _isPlugin = type(_peek) == "table" and _peek.type == "plugin"
                    if not result and not _isPlugin and tostring(err):find("validated library") then
                        ms.ui.modal({
                            title   = "This package is not in the validated library.",
                            msg     = "Import " .. path:match("([^/]+)$") .. " anyway?",
                            confirm = "Import",
                            cancel  = "Cancel",
                        }, function(res)
                            if not (res and res.confirmed) then return end
                            local r2, e2 = ms.package.install(path, { force = true })
                            finish(r2, e2)
                        end)
                        return
                    end

                    finish(result, err)
                end,
            -- END --

            -- Browse --
                browseList = function(data)
                    if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then return end

                    local function push()
                        local entries = (ms.registry and ms.registry.list)
                            and ms.registry.list({}) or {}
                        local installedById = {}
                        if ms.package and ms.package.listPlugins then
                            local okP, plugins = pcall(ms.package.listPlugins)
                            if okP and type(plugins) == "table" then
                                for _, p in ipairs(plugins) do
                                    if p.id then installedById[p.id] = p.version or true end
                                end
                            end
                        end
                        if ms.package and ms.package.listContent then
                            local okC, content = pcall(ms.package.listContent)
                            if okC and type(content) == "table" then
                                for id, rec in pairs(content) do
                                    if installedById[id] == nil then
                                        installedById[id] = (type(rec) == "table"
                                            and rec.version) or true
                                    end
                                end
                            end
                        end
                        local out = {}
                        for _, e in ipairs(entries) do
                            local instV = installedById[e.id]
                            out[#out + 1] = {
                                id          = e.id,
                                type        = e.type,
                                name        = e.name,
                                version     = e.version,
                                author      = e.author,
                                description = e.description,
                                website     = e.website,
                                trust       = e.trust,
                                components  = e.components,
                                installed        = instV ~= nil or nil,
                                installedVersion = (type(instV) == "string") and instV or nil,
                                url         = e.url,
                                sha256      = e.sha256,
                            }
                        end
                        local ok, json = pcall(hs.json.encode, { entries = out })
                        if ok and json then
                            pcall(function()
                                ms.shell.eval("shellReceive('browse', 'catalog', " .. json .. ")")
                            end)
                        end
                    end

                    push()
                    if ms.registry and ms.registry.refresh then
                        ms.registry.refresh({ force = true }, function(ok)
                            if ok then push() end
                        end)
                    end
                end,

                browseInstall = function(data)
                    if not (data and data.id and ms.registry and ms.registry.download
                            and ms.package and ms.package.install) then return end
                    local label = data.label or data.id

                    ms.registry.download(data.id, function(path, derr)
                        if not path then
                            ms.alert("Download failed:\n" .. tostring(derr), 5)
                            return
                        end
                        local result, err = ms.package.install(path, {
                            trustLookup   = ms.registry.trustLookup,
                            component     = (data.component ~= "" and data.component) or nil,
                            includeSounds = data.includeSounds == true,
                            id            = data.id,
                        })
                        hs.timer.doAfter(0.15, function()
                            if not result then
                                ms.alert("Install failed:\n" .. tostring(err), 5)
                                return
                            end
                            if ms._soundsDirty then ms._discoverSounds() end
                            if ms.loadTheme then ms.loadTheme() end
                            ms.playSlot("update")
                            ms.alert(
                                (result.manifest.name or label) .. " installed (" ..
                                #result.installed .. " files).", 4, true
                            )
                            ms._profilesDirty = true
                            ms.ui.markDirty()
                            ms.ui.refresh()
                        end)
                    end)
                end,
            -- END --

            -- Installed Library --
                libraryList = function(data)
                    if not (ms.package and ms.package.libraryList and ms.shell) then return end
                    local kind = data and data.kind
                    if not (ms.package.isLibraryKind and ms.package.isLibraryKind(kind)) then return end

                    local entries = ms.package.libraryList(kind)
                    local ok, json = pcall(hs.json.encode, {
                        kind    = kind,
                        entries = entries,
                    })
                    if ok and json then
                        ms.shell.eval("shellReceive('library', '" .. kind ..
                            "', " .. json .. ")")
                    end
                end,

                profilesList = function()
                    if not (ms.getProfiles and ms.shell) then return end
                    local ok, names = pcall(ms.getProfiles)
                    if not ok or type(names) ~= "table" then names = {} end
                    local active = (ms.alignedProfile and ms.alignedProfile())
                        or (ms.macroMeta and ms.macroMeta.name and ms.sanitizeName
                            and ms.sanitizeName(ms.macroMeta.name)) or ""
                    local entries = {}
                    for _, n in ipairs(names) do
                        entries[#entries + 1] = { name = n, active = (n == active) }
                    end
                    local ok2, json = pcall(hs.json.encode, { entries = entries })
                    if ok2 and json then
                        ms.shell.eval("shellReceive('profileList', 'list', " .. json .. ")")
                    end
                end,

                libraryActivate = function(data)
                    if not (data and data.kind and data.slug and ms.package
                            and ms.package.libraryActivate) then return end

                    local res, err = ms.package.libraryActivate(data.kind, data.slug)
                    if not res then
                        ms.alert("Could not activate:\n" .. tostring(err), 4)
                        return
                    end

                    local wasQuick = ms._quickReloading
                    ms._quickReloading = true
                    if data.kind == "macro" then
                        if ms.ui._actions.reloadMacros then pcall(ms.ui._actions.reloadMacros) end
                        if ms._loadAuthoredSettings then pcall(ms._loadAuthoredSettings) end
                        if ms._defineAuthoredSettings then pcall(ms._defineAuthoredSettings) end
                        if ms._loadAuthoredMenus then pcall(ms._loadAuthoredMenus) end
                    elseif data.kind == "theme" then
                        if ms.loadTheme then pcall(ms.loadTheme) end
                        pcall(function() ms.alert:recolor() end)
                        pcall(function() ms.dev:recolor() end)
                    end
                    if ms._soundsDirty and ms._discoverSounds then pcall(ms._discoverSounds) end
                    if data.kind == "sound" then
                        pcall(function()
                            local sa       = ms.soundAssign or {}
                            local defaults = ms.soundSlotDefaults and ms.soundSlotDefaults() or {}
                            local preset   = "custom"
                            local isDefault = next(defaults) ~= nil
                            for sid, d in pairs(defaults) do
                                if (sa[sid] or "") ~= (d or "") then isDefault = false break end
                            end
                            if isDefault then
                                preset = "default"
                            elseif ms.buildSoundPresets then
                                for _, p in ipairs(ms.buildSoundPresets()) do
                                    local match = next(p.assigns or {}) ~= nil
                                    for sid, name in pairs(p.assigns or {}) do
                                        if (sa[sid] or "") ~= (name or "") then match = false break end
                                    end
                                    if match then preset = tostring(p.num) break end
                                end
                            end
                            ms._soundPreset = preset
                            if ms.saveSettings then ms.saveSettings() end
                        end)
                    end
                    ms._quickReloading = wasQuick

                    ms.playSlot("update")
                    ms.alert((data.name or "Slice") .. " activated.", 3, true)
                    ms.ui.markDirty()
                    ms.ui.refresh()
                    if ms.ui._actions.libraryList then
                        pcall(ms.ui._actions.libraryList, { kind = data.kind })
                    end
                end,

                libraryRemove = function(data)
                    if not (data and data.kind and data.slug and ms.package
                            and ms.package.libraryRemove) then return end

                    local ok, err = ms.package.libraryRemove(data.kind, data.slug)
                    if not ok then
                        ms.alert("Could not remove:\n" .. tostring(err), 4)
                        return
                    end
                    ms.playSlot("back")
                    ms.ui._actions.libraryList({ kind = data.kind })
                end,

                libraryCapture = function(data)
                    if not (data and data.kind and ms.package and ms.package.libraryCapture) then return end

                    local rec, err = ms.package.libraryCapture(data.kind, data.name)
                    if not rec then
                        ms.alert("Could not capture:\n" .. tostring(err), 4)
                        return
                    end
                    ms.playSlot("update")
                    ms.alert("Saved \"" .. rec.name .. "\" to the library.", 3, true)
                    ms.ui._actions.libraryList({ kind = data.kind })
                end,

                libraryRename = function(data)
                    if not (data and data.kind and data.slug and ms.package
                            and ms.package.libraryRename) then return end
                    local rec, err = ms.package.libraryRename(data.kind, data.slug, data.name)
                    if not rec then
                        ms.alert("Could not rename:\n" .. tostring(err), 4)
                        return
                    end
                    ms.playSlot("update")
                    ms.ui._actions.libraryList({ kind = data.kind })
                end,

                libraryCreateEmpty = function(data)
                    if not (data and data.kind and ms.package
                            and ms.package.libraryCreateEmpty) then return end
                    local rec, err
                    if data.seed == true and ms.package.libraryCreateSeeded then
                        rec, err = ms.package.libraryCreateSeeded(data.kind, data.name)
                    else
                        rec, err = ms.package.libraryCreateEmpty(data.kind, data.name)
                    end
                    if not rec then
                        ms.alert("Could not create:\n" .. tostring(err), 4)
                        return
                    end
                    ms.playSlot("update")
                    ms.alert("Created \"" .. rec.name .. "\".", 3, true)
                    ms.ui._actions.libraryList({ kind = data.kind })
                end,

                libraryClear = function(data)
                    if not (data and data.kind and ms.package
                            and ms.package.libraryClear) then return end
                    local removed = ms.package.libraryClear(data.kind)
                    ms.playSlot("reset")
                    ms.alert(removed .. " " .. tostring(data.kind) .. " pack" ..
                        (removed == 1 and "" or "s") .. " removed.", 3, true)
                    ms.ui._actions.libraryList({ kind = data.kind })
                end,
            -- END --

            -- Plugins --
                setPluginEnabled = function(data)
                    if not (data and data.dir and ms.package and ms.package.setPluginEnabled) then return end
                    ms.package.setPluginEnabled(data.dir, data.value == true)
                    if ms.plugins and ms.plugins.apply then
                        local ok, err = pcall(ms.plugins.apply)
                        if not ok then print("[MsUI] plugin apply failed: " .. tostring(err)) end
                    end
                    ms.ui.markDirty()
                    ms.ui.refresh()
                end,

                removePlugin = function(data)
                    if not (data and data.dir and ms.package and ms.package.removePlugin) then return end
                    local dir = data.dir

                    ms.playSlot("alert")
                    ms.ui.modal({
                        title   = "Remove " .. (data.label or dir) .. "?",
                        msg     = "The plugin's files are deleted from Spoons/. This cannot be undone.",
                        confirm = "Remove",
                        cancel  = "Cancel",
                    }, function(res)
                        if not (res and res.confirmed) then return end

                        if ms.plugins and ms.plugins.unload then
                            pcall(ms.plugins.unload, dir)
                        end

                        local ok, err = ms.package.removePlugin(dir)
                        if not ok then
                            ms.alert("Could not remove plugin:\n" .. tostring(err), 5)
                            return
                        end

                        ms.ui.markDirty()
                        ms.ui.refresh()
                        ms.alert((data.label or dir) .. " removed.", 4, true)
                    end)
                end,

                openPluginsFolder = function()
                    local dir = os.getenv("HOME") .. "/.hammerspoon/Spoons"
                    hs.fs.mkdir(dir)
                    os.execute("open '" .. dir .. "'")
                end,
            -- END --

            -- Integrity & Updates --
                openDevLogs = function()
                    local logDir = os.getenv("HOME") .. "/Documents/ms_dev_logs/"
                    hs.fs.mkdir(logDir)
                    os.execute("open " .. logDir)
                end,

                trustCurrentVersion = function()
                    ms.integrity.trustCurrent()
                    ms.ui.refresh()
                end,

                deleteTrustedHash = function()
                    ms.integrity.deleteTrustedHash()
                    ms.alert("Trusted manifest deleted.\nIntegrity protection is now OFF until you re-trust.", 5)
                    ms.ui.refresh()
                end,

                checkIntegrity = function()
                    local status, cur, trusted = ms.integrity.check()
                    if status == "trusted" then
                        ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                        ms.ui.refresh()
                    elseif status == "mismatch" then
                        hs.reload()
                    else
                        ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                        ms.ui.refresh()
                    end
                end,

                showFakeError = function(data)
                    local which = (data and data.value) or "integrity"
                    local spec = nil
                    if which == "unknownPlugin" then
                        spec = {
                            titlebar = "mudscript :// Unrecognized Plugin",
                            height   = 430,
                            title    = "Unrecognized plugin",
                            lead     = "A plugin in Spoons/ was not installed through mudscript, "
                                    .. "or has changed since it was. Because of this, mudscript did "
                                    .. "not load, so no macros or key bindings are active.",
                            rows     = { { label = "Plugin", value = "Spoons/Example.spoon" } },
                            warning  = {
                                "Plugins run as code, so an unrecognized one blocks startup "
                                .. "instead of loading unchecked.",
                                "mudscript only runs plugins installed from its verified library. "
                                .. "Remove this one from ~/.hammerspoon/Spoons/ and reload.",
                            },
                            actions  = {
                                { label = "Reveal in Finder", action = "revealSpoons", style = "accent" },
                                { label = "Keep Blocked", action = "keepBlocked" },
                            },
                        }
                    elseif which == "noLedger" then
                        spec = {
                            titlebar = "mudscript :// Plugins Not Verified",
                            height   = 430,
                            title    = "No plugin record",
                            lead     = "Plugins are installed, but mudscript has no record of "
                                    .. "where they came from. Because of this, mudscript did not load, "
                                    .. "so no macros or key bindings are active.",
                            rows     = { { label = "Found", value = "Spoons/Example.spoon" } },
                            warning  = {
                                "Expected once, on an install that predates plugin verification. "
                                .. "Reinstall each plugin from the library so it is recorded again.",
                                "The record is not rebuilt from disk on purpose: if it were, "
                                .. "deleting one file would make any plugin look trusted.",
                            },
                            actions  = {
                                { label = "Reveal in Finder", action = "revealSpoons", style = "accent" },
                                { label = "Keep Blocked", action = "keepBlocked" },
                            },
                        }
                    elseif which == "sandbox" then
                        spec = {
                            titlebar = "mudscript :// Sandbox Violation",
                            height   = 430,
                            title    = "Blocked an unsafe call",
                            lead     = "A macro script reached outside the macro sandbox, with a call "
                                    .. "like hs.*, os.*, io.* or the shell. mudscript blocked it, so the "
                                    .. "script was quarantined and its macro did not run.",
                            rows     = {
                                { label = "Script", value = "ms_macros.lua" },
                                { label = "Call", value = "hs.execute(...)" },
                            },
                            warning  = {
                                "Macros run in a restricted sandbox with no access to the system, "
                                .. "the filesystem, or the shell. A script reaching for those is "
                                .. "either a mistake or something that should never run unchecked.",
                                "Edit the macro to stay within the ms.* API and reload. Your other "
                                .. "macros are unaffected.",
                            },
                            actions  = {
                                { label = "Quit mudscript", action = "keepBlocked", style = "accent" },
                            },
                        }
                    end
                    ms.showGuardian(nil, nil, spec)
                end,

                openURL = function(data) if data.url then hs.urlevent.openURL(data.url) end end,

                checkForUpdate = function()
                    if ms._updateChannel == "testing" then
                        ms.integrity.updateBeta()
                    else
                        ms.integrity.update()
                    end
                end,
            -- END --
    }
end

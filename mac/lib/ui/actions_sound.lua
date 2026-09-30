return function(ms, ctx)
    local sq = ctx.sq
    local _emptyToNil = ctx._emptyToNil

    return {
            -- Sound Output --
                setSoundEnabled = function(data)
                    ms.soundEnabled = (data.value == true)
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setSoundVolume = function(data)
                    local num = tonumber(data.value)
                    if num and num >= 0 and num <= 100 then
                        ms.soundVolume = math.floor(num)
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setSoundAssign = function(data)
                    if not data.slot then return end
                    ms.soundAssign = ms.soundAssign or {}
                    ms.soundAssign[data.slot] = _emptyToNil(data.name)
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,
            -- END --

            -- Sound Files --
                importSounds = function()
                    ms.playSlot("alert")
                    local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select one or more sound files to add to your library",
                        hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                        true, false, true
                    )
                    local paths = {}
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then table.insert(paths, v) end
                    end
                    if #paths == 0 then ms.ui.show()
                    return end
                    if not hs.fs.attributes(slibDir) then
                        hs.execute("mkdir -p '" .. SoundLib .. "'")
                    end
                    hs.execute("mkdir -p " .. sq(SoundActiveDir))
                    hs.execute("mkdir -p " .. sq(SoundMacroDir))
                    if not hs.fs.attributes(slibDir) then
                        ms.ui.show()
                        ms.alert("Could not create sounds folder:\n" .. SoundLib, 4)
                        return
                    end
                    local added, failed = {}, {}
                    for _, srcPath in ipairs(paths) do
                        local filename   = srcPath:match("([^/]+)$")
                        local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                        if not filename or not importName then
                            table.insert(failed, srcPath)
                        else
                            local dst    = SoundActiveDir .. filename
                            local copied = false
                            if srcPath ~= dst then
                                local f = io.open(srcPath, "rb")
                                if f then
                                    local content = f:read("*all")
                                    f:close()
                                    local g = io.open(dst, "wb")
                                    if g then g:write(content)
                                    g:close()
                                    copied = true end
                                end
                                if not copied then
                                    local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                                end
                                if not copied then table.insert(failed, importName) end
                            else
                                copied = true
                            end
                            if copied then
                                ms.importedSounds = ms.importedSounds or {}
                                ms.importedSounds[importName] = filename
                                table.insert(added, importName)
                            end
                        end
                    end
                    if #added > 0 then
                        ms.saveSettings()
                        ms._soundsDirty = true
                        ms._discoverSounds()
                    end
                    ms.ui.show()
                    hs.timer.doAfter(0.15, function()
                        if #added > 0 then ms.playSlot("update") end
                        if #added > 0 and #failed == 0 then
                            local label = #added == 1
                                and ("Sound \"" .. added[1] .. "\" added.")
                                or  (#added .. " sounds added.")
                            ms.alert(label, 3, true)
                        elseif #added > 0 then
                            ms.alert(
                                #added .. " added, " .. #failed .. " failed.",
                                3,
                                true
                            )
                        else
                            ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                        end
                        ms.ui.refresh()
                    end)
                end,

                importSoundForSlot = function(data)
                    if not data.slot then return end
                    local slot = data.slot
                    ms.playSlot("alert")
                    local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select a sound file for \"" .. (data.label or slot) .. "\"",
                        hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                        true, false, false,
                        ms.soundExtensions
                    )
                    local selectedPath
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then selectedPath = v
                        break end
                    end
                    if not selectedPath then ms.ui.show()
                    return end
                    if not hs.fs.attributes(slibDir) then
                        hs.execute("mkdir -p '" .. SoundLib .. "'")
                    end
                    local filename = selectedPath:match("([^/]+)$")
                    if not filename then
                        ms.ui.show()
                        ms.alert("Could not read filename.", 3)
                        return
                    end

                    if not ms.isSoundFile(filename) then
                        ms.ui.show()
                        ms.alert("Not a sound file.\nSupported: "
                            .. table.concat(ms.soundExtensions, ", ") .. ".", 4)
                        return
                    end

                    local ext        = filename:match("(%.[^%.]+)$") or ""
                    local stem       = filename:match("^(.+)%.[^%.]+$") or filename
                    local importName = ms.safeSoundName(stem, "a_")
                    filename         = importName .. ext

                    local dst    = SoundActiveDir .. filename
                    local copied = false
                    if selectedPath ~= dst then
                        local f = io.open(selectedPath, "rb")
                        if f then
                            local content = f:read("*all")
                            f:close()
                            local g = io.open(dst, "wb")
                            if g then g:write(content)
                            g:close()
                            copied = true end
                        end
                        if not copied then
                            local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                            copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                        end
                    else
                        copied = true
                    end
                    ms.ui.show()
                    if not copied then
                        hs.timer.doAfter(0.15, function()
                            ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                        end)
                        return
                    end
                    ms.importedSounds = ms.importedSounds or {}
                    ms.importedSounds[importName] = filename
                    ms.soundAssign = ms.soundAssign or {}
                    ms.soundAssign[slot] = importName
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                    ms.playSlot("update")
                    hs.timer.doAfter(0.15, function()
                        ms.alert("\"" .. importName .. "\" imported and assigned.", 3, true)
                        ms.ui.refresh()
                    end)
                end,

                removeSound = function(data)
                    local name = data and data.name
                    if type(name) ~= "string" or name == "" then return end

                    ms._discoverSounds()
                    local path = (ms.sounds or {})[name] or (ms.macroSounds or {})[name]
                    if not path then
                        ms.alert("No such sound: " .. name, 3)
                        return
                    end
                    if path:find("/sounds/defaults/") or name:sub(1, 2) == "d_" then
                        ms.alert("Default sounds cannot be removed.", 3)
                        return
                    end

                    local ok = os.remove(path)
                    if not ok then
                        local _, st = hs.execute("/bin/rm -f " .. sq(path))
                        ok = (st == true) or (hs.fs.attributes(path) == nil)
                    end
                    if not ok then
                        ms.alert("Could not remove \"" .. name .. "\".", 4)
                        return
                    end

                    ms.soundAssign = ms.soundAssign or {}
                    for slot, assigned in pairs(ms.soundAssign) do
                        if assigned == name then ms.soundAssign[slot] = nil end
                    end
                    if ms.importedSounds then ms.importedSounds[name] = nil end

                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.15, function()
                        ms.alert("\"" .. name .. "\" removed.", 3, true)
                        ms.ui.refresh()
                    end)
                end,

                setSoundKind = function(data)
                    local name = data and data.name
                    local kind = data and data.kind
                    if type(name) ~= "string" or name == "" then return end
                    if kind ~= "active" and kind ~= "macro" then return end

                    ms._discoverSounds()
                    local path = (ms.sounds or {})[name] or (ms.macroSounds or {})[name]
                    if not path then
                        ms.alert("No such sound: " .. name, 3)
                        return
                    end
                    if path:find("/sounds/defaults/") or name:sub(1, 2) == "d_" then
                        ms.alert("Default sounds cannot be re-typed.", 3)
                        return
                    end

                    local dstDir = (kind == "macro") and SoundMacroDir or SoundActiveDir
                    local prefix = (kind == "macro") and "m_" or "a_"
                    local file   = path:match("([^/]+)$") or ""
                    local stem   = file:match("^(.+)%.[^%.]+$") or file
                    local ext    = file:match("(%.[^%.]+)$") or ""
                    stem = stem:gsub("^[dam]_", "")

                    local newName = prefix .. stem
                    local dst     = dstDir .. newName .. ext

                    if dst == path then
                        if ms.importedSounds then ms.importedSounds[name] = nil end
                        ms.saveSettings()
                        ms._soundsDirty = true
                        ms._discoverSounds()
                        ms.playSlot("update")
                        hs.timer.doAfter(0.15, function() ms.ui.refresh() end)
                        return
                    end
                    if hs.fs.attributes(dst) then
                        ms.alert("A sound named \"" .. newName .. "\" already exists.", 4)
                        return
                    end
                    if not hs.fs.attributes(dstDir) then
                        hs.execute("mkdir -p " .. sq(dstDir))
                    end

                    local ok = os.rename(path, dst)
                    if not ok then
                        local _, st = hs.execute("/bin/mv " .. sq(path) .. " " .. sq(dst))
                        ok = (st == true) or (hs.fs.attributes(dst) ~= nil)
                    end
                    if not ok then
                        ms.alert("Could not move \"" .. name .. "\".", 4)
                        return
                    end

                    ms.soundAssign = ms.soundAssign or {}
                    for slot, assigned in pairs(ms.soundAssign) do
                        if assigned == name then ms.soundAssign[slot] = newName end
                    end

                    if ms.importedSounds then ms.importedSounds[name] = nil end

                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                    ms.playSlot("update")
                    hs.timer.doAfter(0.15, function()
                        ms.alert("\"" .. newName .. "\" is now a "
                            .. kind .. " sound.", 3, true)
                        ms.ui.refresh()
                    end)
                end,

                setBundleSoundsWithTheme = function(data)
                    ms.bundleSoundsWithTheme = (data and data.value) == true
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,
            -- END --

            -- Sound Presets --
                setSoundPreset = function(data)
                    if not data.assigns or type(data.assigns) ~= "table" then return end
                    ms.soundAssign = ms.soundAssign or {}
                    for slotId, soundName in pairs(data.assigns) do
                        ms.soundAssign[slotId] = soundName
                    end
                    ms._soundPreset = data.preset or "default"
                    ms.saveSettings()
                    ms.playSlot("interact")
                    ms.ui.refresh()
                end,

                clearSoundPreset = function(data)
                    if not data.slots or type(data.slots) ~= "table" then return end
                    ms.soundAssign = ms.soundAssign or {}
                    for _, slotId in ipairs(data.slots) do
                        ms.soundAssign[slotId] = nil
                    end
                    ms._soundPreset = "custom"
                    ms.saveSettings()
                    ms.playSlot("interact")
                    ms.ui.refresh()
                end,
            -- END --
    }
end

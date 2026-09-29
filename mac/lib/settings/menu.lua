return function(ms, ctx)
    -- Native Menu Builder --
        local sanitizeName = ctx.sanitizeName
        local getProfiles = ctx.getProfiles
        local switchProfile = ctx.switchProfile
        local importProfile = ctx.importProfile
        local createNewProfile = ctx.createNewProfile
        local saveCurrentProfile = ctx.saveCurrentProfile

        -- Menubar & Bind Collection --
            if ms._menubar then pcall(function() ms._menubar:delete() end) end
            ms._menubar = hs.menubar.new()
            ms._menubar:setIcon(os.getenv("HOME") .. "/.hammerspoon/ui/icons/ms_icon_gen.tiff", true)
            local _legacyNativeMenuBuilder = function()
                local mainBindDefs, optionalBindDefs = {}, {}
                for _, id in ipairs(ms.registry._defList or {}) do
                    local def = ms.registry._defs[id]
                    if def and not (def.default and def.default.type) then
                        local entry = {
                            id    = id,
                            label = def.label,
                            info  = def.info,
                        }
                        if def.group == "main" then
                            table.insert(mainBindDefs, entry)
                        elseif def.group == "optional" then
                            table.insert(optionalBindDefs, entry)
                        end
                    end
                end
        -- END Menubar & Bind Collection --

        -- Shared helpers --
            local function bindStr(c)
                if not c then return "( unset )" end
                if c.type == "mouse" then return "( Mouse " .. c.button .. " )" end
                if c.type == "scroll" then
                    local d = c.direction or "?"
                    return "( Scroll " .. d:sub(1,1):upper() .. d:sub(2) .. " )"
                end
                if c.type == "gamepad" then return "( Pad " .. ms.gpLabel(c) .. " )" end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                table.insert(parts, c.key)
                return "( " .. table.concat(parts, "+") .. " )"
            end

            local function currentBindStr(id)
                return bindStr(ms.effectiveBind(id))
            end
        -- END Shared helpers --

        -- Rebind capture --
            local function makeRebindFn(bind)
                return function()
                    ms.alert("Rebinding: " .. bind.label .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                    local capture
                    local cancelTimer

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.otherMouseDown,
                    }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()

                        local parsed = nil
                        local bindStr2 = ""
                        local t = event:getType()

                        if t == hs.eventtap.event.types.keyDown then
                            local keyCode = event:getKeyCode()
                            local flags = event:getFlags()
                            if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                ms.alert("Rebind cancelled.", 2)
                                return true
                            end
                            local mods = {}
                            if flags.cmd   then table.insert(mods, "cmd")   end
                            if flags.alt   then table.insert(mods, "alt")   end
                            if flags.ctrl  then table.insert(mods, "ctrl")  end
                            if flags.shift then table.insert(mods, "shift") end
                            local keyStr = hs.keycodes.map[keyCode]
                            if keyStr then
                                parsed = {
                                    type = "key",
                                    mods = mods,
                                    key  = keyStr,
                                }
                                local parts = {}
                                for _, m in ipairs(mods) do table.insert(parts, m) end
                                table.insert(parts, keyStr)
                                bindStr2 = table.concat(parts, "+")
                            end
                        else
                            local btn
                            if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                            elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                            else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                            parsed = {
                                type="mouse",
                                button=btn,
                            }
                            bindStr2 = "Mouse " .. btn
                        end

                        if parsed then
                            local conflictId = ms.bind.siblingConflict(bind.id, parsed)
                            if conflictId then
                                ms.playSlot("alert")
                                local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                                ms.alert("Bind Conflict: \"" .. bindStr2 .. "\" is already used by \"" .. cLabel .. "\". Try a different input.", 4)
                                return true
                            end
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set \"" .. bind.label .. "\" to:  " .. bindStr2,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.bindConfig[bind.id] = parsed
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.bind.rebind()
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert(bind.label .. " rebound to: " .. bindStr2, 3, true)
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2, true)
                                end
                            end)
                        else
                            ms.alert("Could not read input. Try again.", 2)
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop()
                            capture = nil
                            ms.alert("Rebind timed out.", 2)
                        end
                    end)
                end
            end

        -- END Rebind capture --

        -- Section builder --
            local function buildBindSection(defs)
                local section = {}
                local rebindSub = {}

                for _, bind in ipairs(defs) do
                    local enabled = ms.binds[bind.id]
                    table.insert(section, {
                        title = bind.label .. "  " .. currentBindStr(bind.id),
                        checked = enabled and true or false,
                        fn = function()
                            ms.binds[bind.id] = not ms.binds[bind.id]
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("update")
                            ms.alert(bind.label .. ": " .. (ms.binds[bind.id] and "ON" or "OFF"), 2, true)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Rebind: " .. bind.label,
                        fn = makeRebindFn(bind),
                    })
                    table.insert(rebindSub, {
                        title = "Set Cooldown: " .. bind.label,
                        fn = function()
                            ms.playSlot("interact")
                            local codeDef = ms.registry._defs[bind.id]
                            local codeDefault = (codeDef and codeDef.cooldown) or 1000
                            local current = ms.cooldowns[bind.id] or codeDefault
                            ms.ui.prompt({
                                title   = "Set Cooldown",
                                msg     = "Cooldown for \"" .. bind.label .. "\" (ms).\nDefault: " .. tostring(codeDefault) .. "ms  |  0 = no cooldown:",
                                confirm = "Set",
                                cancel  = "Cancel",
                                default = tostring(current),
                            }, function(r)
                                if r.confirmed then
                                    local num = tonumber(r.value)
                                    if num and num >= 0 then
                                        ms.cooldowns[bind.id] = math.floor(num)
                                        ms.saveSettings()
                                        ms.bind.rebind()
                                        ms.playSlot("update")
                                        hs.timer.doAfter(0.2, function()
                                            ms.alert(bind.label .. " cooldown: " .. tostring(math.floor(num)) .. "ms", 2, true)
                                            ms.ui.refresh()
                                        end)
                                    else
                                        ms.alert("Invalid value. Enter a non-negative number.", 2)
                                    end
                                end
                            end)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Reset Bind: " .. bind.label,
                        fn = function()
                            ms.bindConfig[bind.id] = nil
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            ms.alert(bind.label .. " bind reset to default.", 2, true)
                        end
                    })
                    table.insert(rebindSub, {
                        title = "Reset Cooldown: " .. bind.label,
                        fn = function()
                            ms.cooldowns[bind.id] = nil
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            local def = ms.registry._defs[bind.id]
                            local defMs = (def and def.cooldown) or 1000
                            ms.alert(bind.label .. " cooldown reset to " .. tostring(defMs) .. "ms.", 2, true)
                        end
                    })
                end

                table.insert(section, { title = "-" })
                table.insert(section, {
                    title = "Rebind",
                    menu = rebindSub,
                })
                table.insert(section, { title = "-" })
                table.insert(section, {
                    title = "Reset All to Default...",
                    fn = function()
                    ms.playSlot("interact")
                    ms.ui.modal({
                        title   = "Reset All to Default",
                        msg     = "Reset all binds and cooldowns in this section to their default values?",
                        confirm = "Reset",
                        cancel  = "Cancel",
                    }, function(r)
                        if r.confirmed then
                            for _, bind in ipairs(defs) do
                                ms.bindConfig[bind.id] = nil
                                ms.cooldowns[bind.id]  = nil
                            end
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            hs.timer.doAfter(0.2, function()
                                ms.alert("All binds reset to default.", 3, true)
                                ms.ui.refresh()
                            end)
                        end
                    end)
                end })

                return section
            end
        -- END Section builder --


        -- System submenu --
            local function buildSystemSubmenu()
                local sub = {}
                for _, id in ipairs({
                    "enable",
                    "disable",
                    "toggle",
                }) do
                    local def = ms.systemBinds._defs[id]
                    if def then
                        local bindStr = ms.systemBinds.bindStr(id)
                        table.insert(sub, {
                            title = def.label .. "  " .. bindStr,
                            disabled = true,
                        })
                        table.insert(sub, {
                            title = "  Rebind: " .. def.label,
                            fn = function()
                                ms.alert("Rebinding: " .. def.label
                                    .. "\nCurrent: " .. bindStr
                                    .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                                local capture
                                local cancelTimer
                                capture = hs.eventtap.new({
                                    hs.eventtap.event.types.keyDown,
                                    hs.eventtap.event.types.leftMouseDown,
                                    hs.eventtap.event.types.rightMouseDown,
                                    hs.eventtap.event.types.otherMouseDown,
                                }, function(event)
                                    capture:stop()
                                    capture = nil
                                    cancelTimer:stop()
                                    local parsed, newBindStr
                                    local t = event:getType()
                                    if t == hs.eventtap.event.types.keyDown then
                                        local keyCode = event:getKeyCode()
                                        local flags = event:getFlags()
                                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                            ms.alert("Rebind cancelled.", 2)
                                            return true
                                        end
                                        local mods = {}
                                        if flags.cmd   then table.insert(mods, "cmd")   end
                                        if flags.alt   then table.insert(mods, "alt")   end
                                        if flags.ctrl  then table.insert(mods, "ctrl")  end
                                        if flags.shift then table.insert(mods, "shift") end
                                        local keyStr = hs.keycodes.map[keyCode]
                                        if keyStr then
                                            parsed = {
                                                type = "key",
                                                mods = mods,
                                                key  = keyStr,
                                            }
                                            local parts = {}
                                            for _, m in ipairs(mods) do table.insert(parts, m) end
                                            table.insert(parts, keyStr)
                                            newBindStr = table.concat(parts, "+")
                                        end
                                    else
                                        local btn
                                        if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                                        elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                                        else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                                        parsed = {
                                            type="mouse",
                                            button=btn,
                                        }
                                        newBindStr = "Mouse " .. btn
                                    end
                                    if parsed then
                                        ms.playSlot("interact")
                                        ms.ui.modal({
                                            title   = "Confirm Rebind",
                                            msg     = "Set \"" .. def.label .. "\" to:  " .. newBindStr,
                                            confirm = "Confirm",
                                            cancel  = "Cancel",
                                        }, function(r)
                                            if r.confirmed then
                                                ms.systemBinds._config[id] = parsed
                                                ms.saveSettings()
                                                ms.systemBinds.rebind()
                                                ms.playSlot("update")
                                                hs.timer.doAfter(0.2, function()
                                                    ms.alert(def.label .. " rebound to: " .. newBindStr, 3, true)
                                                end)
                                            else
                                                ms.alert("Rebind cancelled.", 2, true)
                                            end
                                        end)
                                    else
                                        ms.alert("Could not read input. Try again.", 2)
                                    end
                                    return true
                                end)
                                capture:start()
                                cancelTimer = hs.timer.doAfter(15, function()
                                    if capture then capture:stop()
                                    capture = nil
                                    ms.alert("Rebind timed out.", 2) end
                                end)
                            end
                        })
                        table.insert(sub, {
                            title = "  Reset: " .. def.label,
                            fn = function()
                                ms.systemBinds._config[id] = nil
                                ms.saveSettings()
                                ms.systemBinds.rebind()
                                ms.playSlot("reset")
                                ms.alert(def.label .. " reset to default.", 2, true)
                            end
                        })
                    end
                end
                table.insert(sub, { title = "-" })
                local displayBinds = {
                    {
                        label = "Panic Button / Stop All",
                        bind = "Alt+F10",
                    },
                    {
                        label = "Get Target Window Info",
                        bind = "Ctrl+Shift+R",
                    },
                    {
                        label = "Quick Reload",
                        bind = "Alt+[-> Reload Options",
                    },
                    {
                        label = "Full Reload",
                        bind = "Alt+]-> Reload Options",
                    },
                    {
                        label = "Open Menu",
                        bind = "Alt+P",
                    },
                }
                for _, bind in ipairs(displayBinds) do
                    table.insert(sub, {
                        title = bind.label .. "  " .. bind.bind,
                        disabled = true,
                    })
                end
                return sub
            end

            local function buildSoundSubmenu()
                ms._discoverSounds()
                local sub = {}
                table.insert(sub, {
                    title = "Sound Effects",
                    checked = ms.soundEnabled and true or false,
                    fn = function()
                        ms.soundEnabled = not ms.soundEnabled
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.alert("Sound Effects: " .. (ms.soundEnabled and "ON" or "OFF"), 2, true)
                    end
                })
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Volume: " .. tostring(ms.soundVolume or 100) .. "%",
                    disabled = true,
                })
                table.insert(sub, {
                    title = "Set Volume...",
                    fn = function()
                        ms.playSlot("interact")
                        ms.ui.prompt({
                            title   = "Sound Volume",
                            msg     = "Enter volume (0-100):",
                            confirm = "Set",
                            cancel  = "Cancel",
                            default = tostring(ms.soundVolume or 100),
                        }, function(r)
                            if r.confirmed then
                                local num = tonumber(r.value)
                                if num and num >= 0 and num <= 100 then
                                    ms.soundVolume = math.floor(num)
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Volume set to " .. tostring(ms.soundVolume) .. "%", 2, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Invalid value. Must be 0-100.", 2)
                                end
                            end
                        end)
                    end
                })
                table.insert(sub, {
                    title = "Reset Volume",
                    fn = function()
                        ms.soundVolume = 100
                        ms.saveSettings()
                        ms.playSlot("reset")
                        ms.alert("Volume reset to 100%", 2, true)
                    end
                })
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Import Sound Files...",
                    fn = function()
                        ms.playSlot("alert")
                        hs.focus()
                        local slibDir = SoundActiveDir:match("^(.-)[/\\]*$") or SoundActiveDir
                        local result = hs.dialog.chooseFileOrFolder(
                            "Select one or more sound files to add to your library",
                            hs.fs.attributes(slibDir) and SoundActiveDir or os.getenv("HOME"),
                            true, false, true
                        )
                        local paths = {}
                        for _, v in pairs(result or {}) do
                            if type(v) == "string" then table.insert(paths, v) end
                        end
                        if #paths == 0 then return end
                        result = paths

                        if not hs.fs.attributes(slibDir) then
                            hs.execute("mkdir -p '" .. SoundActiveDir .. "'")
                        end
                        if not hs.fs.attributes(slibDir) then
                            ms.alert("Could not create sounds folder at:\n" .. SoundLib, 4)
                            return
                        end

                        local function sq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

                        local added, failed = {}, {}
                        for _, srcPath in ipairs(result) do
                            local filename   = srcPath:match("([^/]+)$")
                            local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                            if not filename or not importName then
                                table.insert(failed, srcPath)
                                goto nextFile
                            end
                            local dst = SoundActiveDir .. filename
                            if srcPath ~= dst then
                                local copied = false
                                local f = io.open(srcPath, "rb")
                                if f then
                                    local content = f:read("*all")
                                    f:close()
                                    local g = io.open(dst, "wb")
                                    if g then
                                        g:write(content)
                                        g:close()
                                        copied = true
                                    else
                                        print("ms: import: io.open write failed for " .. tostring(srcPath))
                                    end
                                else
                                    print("ms: import: io.open read failed for " .. tostring(srcPath))
                                end
                                if not copied then
                                    local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                                    if not copied then
                                        print("ms: import: shell cp failed for " .. tostring(srcPath))
                                    end
                                end
                                if not copied then
                                    table.insert(failed, importName)
                                    goto nextFile
                                end
                            end
                            ms.importedSounds = ms.importedSounds or {}
                            ms.importedSounds[importName] = filename
                            table.insert(added, importName)
                            ::nextFile::
                        end

                        if #added > 0 then
                            ms.saveSettings()
                            ms._soundsDirty = true
                            ms._discoverSounds()
                            ms._pendingReopenToSound = true
                        end
                        hs.timer.doAfter(0.2, function()
                            if #added > 0 then
                                ms.playSlot("update")
                            end
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
                                ms.alert("Import failed. Grant Hammerspoon Full Disk Access\nfor importing from outside ~/.hammerspoon.", 5)
                            end
                        end)
                    end
                })
                table.insert(sub, { title = "-" })
                local slots = {
                    {
                        id = "load",
                        label = "Loading Screen End",
                    },
                    {
                        id = "launch",
                        label = "Launch Announcement",
                    },
                    {
                        id = "updateAvailable",
                        label = "Update Available",
                    },
                    {
                        id = "alert",
                        label = "Alert / Notice",
                    },
                    {
                        id = "error",
                        label = "Error",
                    },
                    {
                        id = "enabled",
                        label = "Macros Enabled",
                    },
                    {
                        id = "disabled",
                        label = "Macros Disabled",
                    },
                    {
                        id = "update",
                        label = "Setting Updated",
                    },
                    {
                        id = "reset",
                        label = "Setting Reset",
                    },
                    {
                        id = "interact",
                        label = "Menu Interact",
                    },
                    {
                        id = "hover",
                        label = "Menu Hover",
                    },
                    {
                        id = "back",
                        label = "Menu Back",
                    },
                    {
                        id = "settingsOpen",
                        label = "Settings Open",
                    },
                    {
                        id = "settingsClose",
                        label = "Settings Close",
                    },
                }
                local soundNames = {}
                for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
                table.sort(soundNames)
                for _, slot in ipairs(slots) do
                    local assigned = ms.soundAssign and ms.soundAssign[slot.id]
                    local display  = assigned or "off"
                    local picker   = {}
                    table.insert(picker, {
                        title = "None",
                        checked = not assigned,
                        fn = function()
                            ms.soundAssign = ms.soundAssign or {}
                            ms.soundAssign[slot.id] = nil
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert(slot.label .. " sound: off", 2, true)
                        end
                    })
                    table.insert(picker, { title = "-" })
                    if #soundNames == 0 then
                        table.insert(picker, {
                            title = "(no sound files imported)",
                            disabled = true,
                        })
                    else
                        for _, name in ipairs(soundNames) do
                            table.insert(picker, {
                                title = name,
                                checked = assigned == name,
                                fn = function()
                                    ms.soundAssign = ms.soundAssign or {}
                                    ms.soundAssign[slot.id] = name
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert(slot.label .. " sound: " .. name, 2, true)
                                end
                            })
                        end
                    end
                    table.insert(sub, {
                        title = slot.label .. "  ( " .. display .. " )",
                        menu  = picker
                    })
                end
                return sub
            end

            local function buildTrackpadHoldSubmenu()
            local sub = {}
            local keys = ms.trackpadHoldKeys or {
                left = "n",
                right = "j",
            }

            table.insert(sub, {
                title = "Left Click Hold  ( " .. (keys.left or "unset") .. " )",
                fn = function()
                    ms.alert("Rebinding: Left Click Hold\nCurrent: " .. (keys.left or "unset")
                        .. "\nPress a key. Backspace to reset to default ( n ). Escape to cancel.", 15)
                    local capture, cancelTimer
                    capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        local flags = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2)
                        return true end
                        local newKey = (keyCode == 51) and "n" or hs.keycodes.map[keyCode]
                        if newKey then
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set Left Click Hold to:  " .. newKey,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.trackpadHoldKeys.left = newKey
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Left Click Hold set to: " .. newKey, 3, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2)
                                end
                            end)
                        else
                            ms.alert("Could not read key. Try again.", 2)
                        end
                        return true
                    end)
                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then capture:stop()
                        capture = nil
                        ms.alert("Rebind timed out.", 2) end
                    end)
                end
            })

            table.insert(sub, {
                title = "Right Click Hold  ( " .. (keys.right or "unset") .. " )",
                fn = function()
                    ms.alert("Rebinding: Right Click Hold\nCurrent: " .. (keys.right or "unset")
                        .. "\nPress a key. Backspace to reset to default ( j ). Escape to cancel.", 15)
                    local capture, cancelTimer
                    capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                        capture:stop()
                        capture = nil
                        cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        local flags = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2)
                        return true end
                        local newKey = (keyCode == 51) and "j" or hs.keycodes.map[keyCode]
                        if newKey then
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set Right Click Hold to:  " .. newKey,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.trackpadHoldKeys.right = newKey
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("update")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Right Click Hold set to: " .. newKey, 3, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2)
                                end
                            end)
                        else
                            ms.alert("Could not read key. Try again.", 2)
                        end
                        return true
                    end)
                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then capture:stop()
                        capture = nil
                        ms.alert("Rebind timed out.", 2) end
                    end)
                end
            })

            table.insert(sub, { title = "-" })
            table.insert(sub, {
                title = "Reset both to default  ( n / j )",
                fn = function()
                    ms.playSlot("interact")
                    ms.ui.modal({
                        title   = "Reset Hold Keys",
                        msg     = "Reset both hold keys to defaults?  ( n / j )",
                        confirm = "Reset",
                        cancel  = "Cancel",
                    }, function(r)
                        if r.confirmed then
                            ms.trackpadHoldKeys.left  = "n"
                            ms.trackpadHoldKeys.right = "j"
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("reset")
                            hs.timer.doAfter(0.2, function()
                                ms.alert("Hold keys reset to default  ( n / j )", 3, true)
                                ms.ui.refresh()
                            end)
                        end
                    end)
                end
            })

            return sub
            end

            local function buildProfilesSubmenu()
                local sub = {}
                local currentName = ms.macroMeta and ms.macroMeta.name
                local profiles = getProfiles()
                if currentName then
                    table.insert(sub, {
                        title = "Active:  " .. currentName,
                        disabled = true,
                    })
                    table.insert(sub, { title = "-" })
                end
                if #profiles == 0 then
                    table.insert(sub, {
                        title = "No saved profiles.",
                        disabled = true,
                    })
                else
                    for _, name in ipairs(profiles) do
                        local isCurrent = (name == (currentName and sanitizeName(currentName)))
                        table.insert(sub, {
                            title    = name,
                            checked  = isCurrent,
                            disabled = isCurrent,
                            fn       = not isCurrent and function()
                                ms.ui.modal({
                                    title   = "Switch Profile",
                                    msg     = "Switch to \"" .. name .. "\"?\n\nThe current profile will be archived and Hammerspoon will reload in 3 seconds.",
                                    confirm = "Switch",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then switchProfile(name) end
                                end)
                            end or nil,
                        })
                    end
                end
                table.insert(sub, { title = "-" })
                table.insert(sub, {
                    title = "Create New Profile...",
                    fn    = function() createNewProfile() end,
                })
                local activeFolder = currentName and sanitizeName(currentName) or ""
                local hasMatching = false
                for _, p in ipairs(profiles) do
                    if p == activeFolder then hasMatching = true
                    break end
                end
                table.insert(sub, {
                    title    = "Save Current Profile",
                    disabled = not hasMatching,
                    fn       = hasMatching and function() saveCurrentProfile() end or nil,
                })
                table.insert(sub, {
                    title = "Import Profile...",
                    fn    = function() importProfile() end,
                })
                return sub
            end

            local keybindSubmenu = {
                {
                    title = "Main",
                    menu = buildBindSection(mainBindDefs),
                },
                {
                    title = "Optional",
                    menu = buildBindSection(optionalBindDefs),
                },
                {
                    title = "System",
                    menu = buildSystemSubmenu(),
                },
                { title = "-" },

                { title = "-" },

            }
        -- END System submenu --

        -- Settings submenu --
            local function buildSettingsSubmenu()
                return {
                    {
                        title = (ms.trackpadMode and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Trackpad / Pen Mode",
                        fn = function()
                        ms.trackpadMode = not ms.trackpadMode
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot("update")
                        ms.alert("Trackpad / Pen Mode: " .. (ms.trackpadMode and "ON" or "OFF"), 2, true)
                    end },
                    {
                        title = "Trackpad Hold Keys",
                        menu = buildTrackpadHoldSubmenu(),
                    },
                    { title = "-" },
                    {
                        title = (ms._swallowHotkeys and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Swallow Hotkey Inputs",
                        fn = function()
                        ms._swallowHotkeys = not ms._swallowHotkeys
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.alert("Swallow Hotkeys: " .. (ms._swallowHotkeys and "ON" .. "\nHotkey keypresses will be blocked from reaching the target app." or "OFF" .. "\nHotkey keypresses will pass through to the target app."), 4, true)
                    end },
                    {
                        title = (ms.gamepadEnabled and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Controller / Gamepad Input",
                        fn = function()
                        ms.gamepadEnabled = not ms.gamepadEnabled
                        if ms.gamepadEnabled then
                            if ms.gamepadStart then ms.gamepadStart() end
                            if ms.shell and ms.shell.gpEnsureOpenBind then ms.shell.gpEnsureOpenBind() end
                        else
                            if ms.shell and ms.shell.gpClearOpenBind then ms.shell.gpClearOpenBind() end
                            if ms.gamepadStop then ms.gamepadStop() end
                        end
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot("update")
                        if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                        ms.alert("Controller Input: " .. (ms.gamepadEnabled and "ON" or "OFF"), 2, true)
                    end },
                    { title = "-" },
                    {
                        title = (ms.socdEnabled and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " SOCD Cleaning",
                        fn = function()
                        ms.socdEnabled = not ms.socdEnabled
                        ms.saveSettings()
                        ms.socdApply()
                        ms.playSlot("update")
                        ms.alert("SOCD Cleaning: " .. (ms.socdEnabled and "ON" or "OFF"), 2, true)
                    end },
                    { title = "SOCD Mode: " .. (ms.socdMode == "lastWins" and "Last Input Wins" or ms.socdMode == "neutral" and "Neutral" or "First Input Wins"), menu = {
                        {
                            title = (ms.socdMode == "lastWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Last Input Wins",
                            fn = function()
                            ms.socdMode = "lastWins"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: Last Input Wins", 2, true)
                        end },
                        {
                            title = (ms.socdMode == "neutral" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Neutral",
                            fn = function()
                            ms.socdMode = "neutral"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: Neutral", 2, true)
                        end },
                        {
                            title = (ms.socdMode == "firstWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " First Input Wins",
                            fn = function()
                            ms.socdMode = "firstWins"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("SOCD Mode: First Input Wins", 2, true)
                        end },
                    }},
                    { title = "-" },
                    {
                        title = "Sound",
                        menu = buildSoundSubmenu(),
                    },
                    { title = "-" },
                    {
                        title = "Keybinds",
                        menu = keybindSubmenu,
                    },
                    { title = "-" },
                    {
                        title = "Save as Default...",
                        fn = function()
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Save as Default",
                            msg     = "Save current settings as the new default?\nThe existing default will be archived.",
                            confirm = "Save",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                ms.saveDefault()
                                ms.playSlot("update")
                                ms.ui.refresh()
                            end
                        end)
                    end },
                    {
                        title = "Reset to Default...",
                        fn = function()
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Reset to Default",
                            msg     = "Reset all settings to the saved default?\nCurrent settings will be overwritten.",
                            confirm = "Reset",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                if ms.resetToDefault() then
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Settings reset to default.", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end
                        end)
                    end },
                }
            end
        -- END Settings submenu --

        -- Developer submenu --
            local function buildDeveloperSubmenu()
                local _trusted = (ms.integrity.check() == "trusted")
                return {
                    {
                        title = "Debug Target Window",
                        fn = function()
                        ms.playSlot("interact")
                        ms.debugTarget()
                    end },
                    {
                        title = "Edit Macros",
                        fn = function()
                        ms.playSlot("interact")
                        os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
                    end },
                    { title = "-" },
                    {
                        title    = _trusted and "\xe2\x9c\x93 Trust Current Version" or "Trust Current Version...",
                        disabled = _trusted or nil,
                        fn       = not _trusted and function()
                            ms.playSlot("interact")
                            local status, cur = ms.integrity.check()
                            local prompt
                            if status == "uninitialized" then
                                prompt = "Seal this ms_core.lua as the trusted baseline?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                            else
                                prompt = "Hash mismatch detected. Trust the CURRENT (possibly modified) version?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                            end
                            ms.ui.modal({
                                title   = "Trust Current Version",
                                msg     = prompt,
                                confirm = "Trust",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then ms.integrity.trustCurrent() end
                            end)
                        end or nil,
                    },
                    { title = "Update Channel: " .. (ms._updateChannel == "testing" and "Testing" or "Stable"), menu = {
                        {
                            title = (ms._updateChannel == "stable" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Stable (MANIFEST.json)",
                            fn = function()
                            ms._updateChannel = "stable"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Update channel: Stable", 2, true)
                        end },
                        {
                            title = (ms._updateChannel == "testing" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Testing (GitHub Actions)",
                            fn = function()
                            ms._updateChannel = "testing"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Update channel: Testing", 2, true)
                        end },
                    }},
                    { title = "Testing Source: " .. ((ms._testingSource or "release") == "artifact" and "Artifacts" or "Releases"), menu = {
                        {
                            title = ((ms._testingSource or "release") == "release" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Releases (signed manifests)",
                            fn = function()
                            ms._testingSource = "release"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Testing source: Releases", 2, true)
                        end },
                        {
                            title = ((ms._testingSource or "release") == "artifact" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Artifacts (rapid testing)",
                            fn = function()
                            ms._testingSource = "artifact"
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.alert("Testing source: Artifacts", 2, true)
                        end },
                    }},
                }
            end
        -- END Developer submenu --

        -- Help submenu --
            local function buildHelpSubmenu()
                return {
                    {
                        title = "About",
                        fn = function()
                        ms.playSlot("interact")
                        ms.alert("mudscript HS utilities\nBy: mudbourn, https://mudbourn.info", 6)
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. ", " .. ms.macroMeta.website end
                            ms.alert(msg, 10)
                        end
                    end },
                    {
                        title = "Version",
                        fn = function()
                        ms.playSlot("interact")
                        local ver = "?"
                        local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                        if lf then
                            local raw = lf:read("*a")
                            lf:close()
                            local v = raw:match('"version"%s*:%s*"([^"]+)"')
                            if v then ver = v end
                        end
                        local chan = ms._updateChannel or "stable"
                        local label = (chan == "testing") and "Test Build" or "Release"
                        ms.alert("mudscript v" .. ver .. "\n" .. label .. " (" .. chan .. ")", 5, true)
                    end },
                    {
                        title = "GitHub",
                        fn = function()
                        ms.playSlot("interact")
                        hs.urlevent.openURL("https://github.com/mudbourn/mudscript")
                    end },
                    {
                        title = "Documentation",
                        fn = function()
                        ms.playSlot("interact")
                        hs.urlevent.openURL(ms._docsURL .. "?platform=mac")
                    end },
                    { title = "-" },
                    {
                        title = "Check System Integrity",
                        fn = function()
                        ms.playSlot("interact")
                        local status, cur, trusted = ms.integrity.check()
                        if status == "trusted" then
                            ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                        elseif status == "mismatch" then
                            ms.alert("\xe2\x9a\xa0 Hash mismatch!\nExpected: " .. (trusted and trusted:sub(1, 16) or "?") .. "\xe2\x80\xa6\nCurrent:  " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6\n\nVerify the change or use Trust Current Version.", 9)
                        else
                            ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                        end
                    end },
                    {
                        title = "Check for Update...",
                        fn = function()
                        if ms._updateChannel == "testing" then
                            if not ms._testingRepo or ms._testingRepo == "" then
                                ms.alert("No testing repo configured.\nSet ms._testingRepo in ms_core.lua.", 5)
                                return
                            end
                        else
                            if not ms._updateManifestURL or ms._updateManifestURL == "" then
                                ms.alert("No update URL configured.\nSet ms._updateManifestURL in ms_core.lua.", 5)
                                return
                            end
                        end
                        local _chan = (ms._updateChannel == "testing") and "testing" or "stable"
                        ms.playSlot("interact")
                        ms.ui.modal({
                            title   = "Check for Update",
                            msg     = "Channel: " .. _chan .. "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                            confirm = "Update",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                if ms._updateChannel == "testing" then
                                    ms.integrity.updateBeta()
                                else
                                    ms.integrity.update()
                                end
                            end
                        end)
                    end },
                    {
                        title = (ms._updateAlertsDisabled and "\xe2\x9c\x97" or "\xe2\x9c\x93")
                            .. " Update Alerts on Launch",
                        fn = function()
                        ms._updateAlertsDisabled = not ms._updateAlertsDisabled
                        ms.saveSettings()
                        if ms._updateAlertsDisabled then
                            ms.playSlot("reset")
                            ms.alert("Launch update alerts: Off\nRe-enable here anytime.", 3, true)
                        else
                            ms.playSlot("update")
                            ms.alert("Launch update alerts: On", 2, true)
                        end
                    end },
                    { title = "-" },
                    {
                        title = "Macro Info",
                        fn = function()
                        ms.playSlot("interact")
                        local path = os.getenv("HOME") .. "/.hammerspoon/ms_macro_info.txt"
                        local f = io.open(path, "w")
                        if f then
                            f:write("Macro Modifiers & Usage\n")
                            f:write("=======================\n\n")
                            local function writeSection(defs)
                                for _, bind in ipairs(defs) do
                                    if bind.info then
                                        f:write(bind.label .. "\n")
                                        f:write(string.rep("-", #bind.label) .. "\n")
                                        f:write(bind.info .. "\n")
                                    end
                                end
                            end
                            writeSection(mainBindDefs)
                            writeSection(optionalBindDefs)
                            f:close()
                            os.execute("open " .. path)
                        end
                    end },
                }
            end
        -- END Help submenu --

        -- Main menu --
            local function _buildMenuItems()
                return {
                    {
                        title = "Macros: " .. (BindValidity == 1 and "ENABLED" or "DISABLED"),
                        disabled = true,
                    },
                    { title = "-" },
                    {
                        title = "Enable Macros ( Enter )",
                        fn = function() ms.setMacros(1) end,
                    },
                    {
                        title = "Disable Macros ( / )",
                        fn = function() ms.setMacros(0) end,
                    },
                    { title = "-" },
                    {
                        title = "Reload Options",
                        menu = {
                        {
                            title = "Quick Reload ( " .. (ms.windowsMode and "Alt+[" or "Opt+[") .. " )",
                            fn = function() ms.quickReload() end,
                        },
                        {
                            title = "Full Reload ( " .. (ms.windowsMode and "Alt+]" or "Opt+]") .. " )",
                            fn = function()
                            if ms.restart then ms.restart() else hs.reload() end
                        end },
                    }},
                    { title = "-" },
                    {
                        title = "Profiles",
                        menu = buildProfilesSubmenu(),
                    },
                    {
                        title = "Settings",
                        menu = buildSettingsSubmenu(),
                    },
                    {
                        title = "Developer",
                        menu = buildDeveloperSubmenu(),
                    },
                    {
                        title = "Help",
                        menu = buildHelpSubmenu(),
                    },
                }
            end
            local function _wrapFns(items)
                for _, item in ipairs(items or {}) do
                    if item.fn then
                        local orig = item.fn
                        item.fn = function()
                            ms._menuFnFired = true
                            orig()
                            if ms._menuOpen then
                                hs.timer.doAfter(0, function()
                                    if ms._menuOpen then
                                        ms._menuFnFired = false
                                        ms.playSlot("settingsOpen")
                                        ms._menuHoverStart()
                                        ms._menuVisible = true
                                        ms._menubar:popupMenu(ms._biasedMenuPt(ms._lastMenuPoint))
                                        ms._menuVisible = false
                                        ms._menuHoverStop()
                                        if not ms._menuFnFired then
                                            ms.playSlot("settingsClose")
                                        end
                                    end
                                end)
                            end
                        end
                    end
                    if item.menu then _wrapFns(item.menu) end
                end
            end
            if ms._pendingReopenToSound then
                ms._pendingReopenToSound = false
                local soundItems = buildSoundSubmenu()
                if ms._menuOpen then _wrapFns(soundItems) end
                return soundItems
            end
            local freshItems = _buildMenuItems()
            if ms._menuOpen then _wrapFns(freshItems) end
            return freshItems
        -- END Main menu --

        end
    -- END Native Menu Builder --
end

return function(ms, ctx)
    local _bindDisplay = ctx._bindDisplay
    local _restoreAfterCapture = ctx._restoreAfterCapture
    local _rebindModal = ctx._rebindModal

    return {
            -- Shell Lifecycle --
                ready = function() ms.ui.refresh() end,

                setMacros = function(data)
                    ms.setMacros(tonumber(data.value) == 1 and 1 or 0)
                    ms.ui.refresh()
                end,

                playSlot = function(data) if data.slot then ms.playSlot(data.slot) end end,

                previewSound = function(data)
                    if data and type(data.name) == "string" and data.name ~= "" then
                        ms.sound(data.name)
                    end
                end,

                alert = function(data)
                    if data.msg then
                        ms.alert(tostring(data.msg), tonumber(data.duration) or 3, data.noSound == true)
                    end
                end,

                close = function() ms.ui.hide() end,
            -- END --

            -- Reload & Shutdown --
                reloadMacros = function()
                    local af = io.open(ms.profile.file("macros"), "r")
                    if not af then
                        ms.alert("Reload failed:\nCannot open ms_macros.lua.", 6)
                        return false
                    end
                    local rawSrc = af:read("*all")
                    af:close()
                    local auditErrs = ms.auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        ms.alert("Reload blocked, audit failed.", 6)
                        return false
                    end
                    local chunk, loadErr = load(
                        rawSrc,
                        "@ms_macros.lua",
                        "bt",
                        ms._macroSandbox
                    )
                    if not chunk then
                        ms.alert("Reload failed:\n" .. tostring(loadErr), 6)
                        return false
                    end

                    if ms.plugins and ms.plugins.loaded then
                        for dir in pairs(ms.plugins.loaded) do
                            pcall(ms.plugins.unload, dir, {
                                quiet = true,
                                reload = true,
                            })
                        end
                    end
                    ms.bind.teardown()
                    ms.registry._defs    = {}
                    ms.registry._defList = {}
                    ms.bind._wires    = {}
                    ms.bind._autoCount = 0
                    ms.macroMeta       = nil
                    ms._userSettingDefs  = {}
                    ms._userSettingIndex = {}
                    ms._stashUserSettings()

                    ms._defineOrigin = "pack"
                    local ok, runErr = xpcall(chunk, debug.traceback)
                    ms._defineOrigin = nil
                    if not ok then
                        local tb = tostring(runErr)
                        print("=== ms_macros.lua reload error ===\n" .. tb)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({
                                type = "error",
                                event = "reload_error",
                                msg = tb,
                            })
                        end
                        ms.alert("Reload failed, see console", 6)
                        pcall(function()
                            ms.bind._registerSystemBinds()
                            ms.bind.rebindSystem()
                        end)
                        return false
                    end
                    if ms._captureHandMeta then ms._captureHandMeta() end
                    if ms.vars and ms.vars.reload then ms.vars.reload() end
                    if ms.compiler and ms.compiler.paths then
                        if hs.fs.attributes(ms.compiler.paths.json) then
                            local rebOk, rebErr = pcall(ms.compiler.rebuild)
                            if not rebOk then
                                print("ms.compiler.rebuild (reload): " .. tostring(rebErr))
                            end
                        end
                        local ldOk, ldErr = pcall(ms.compiler.load)
                        if not ldOk then
                            print("ms.compiler.load (reload): " .. tostring(ldErr))
                        end
                    end
                    for _, id in ipairs(ms.registry._defList) do
                        local def = ms.registry._defs[id]
                        if def and not (def.default and def.default.type) and ms.binds[id] == nil then
                            ms.binds[id] = def.enabled
                        end
                    end
                    ms._systemActions = {}
                    if ms._userSettingIndex["showTamperWarning"] then
                        ms._systemActions["showTamperWarning"] = function()
                            ms.showGuardian()
                        end
                        ms._systemActions["showIntegrityError"] = function()
                            ms.showGuardian()
                        end
                    end
                    if ms.plugins and ms.plugins.loadAll then
                        pcall(ms.plugins.loadAll)
                    end
                    ms.loadSettings()
                    if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
                    ms.bind.rebind()
                    ms.socdApply()
                    if ms.gamepadSync then ms.gamepadSync() end
                    if not ms._quickReloading then
                        ms.playSlot("update")
                        ms.alert("Macros reloaded.", 4, true)
                    end
                    if not ms._quickReloading then
                        hs.timer.doAfter(0.15, function()
                            pcall(function()
                                local app = ms._targetApp and hs.application.get(ms._targetApp)
                                if app then
                                    app:hide()
                                    hs.timer.doAfter(0.15, function()
                                        pcall(function() app:activate() end)
                                    end)
                                end
                            end)
                        end)
                    end
                    return true
                end,

                reloadSettings = function()
                    ms.loadSettings()
                    ms.bind.rebind()
                    ms.socdApply()
                    if ms.gamepadSync then ms.gamepadSync() end
                    ms.playSlot("update")
                    ms.alert("Settings reloaded.", 4, true)
                    ms.ui.refresh()
                end,

                reloadTheme = function()
                    ms.loadTheme()
                    pcall(function() ms.alert:recolor() end)
                    pcall(function() ms.dev:recolor() end)
                    pcall(function() ms.shell.recolorPopouts() end)
                    pcall(function() ms.shell.applyWindowRadius() end)
                    ms.playSlot("update")
                    ms.alert("Theme reloaded.", 4, true, { priority = "low" })
                    ms.ui.hide()
                    hs.timer.doAfter(0.15, function() ms.ui.show() end)
                end,

                reloadUI = function()
                    ms.reloadUI()
                end,

                reloadAll = function() hs.reload() end,

                shutdown = function() ms.shutdown() end,

                quickReload = function()
                    ms.reload()
                end,

                setQROption = function(data)
                    if data.key and ms._qrOptions then
                        ms._qrOptions[data.key] = (data.value == true)
                        ms.saveSettings()
                        ms.playSlot("interact")
                    end
                end,
            -- END --

            -- Settings & Toggles --
                setCustomTheme = function(data)
                    ms._customThemeDisabled = not (data.value and true or false)
                    if ms._customThemeDisabled then
                        for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                        for sid, def in pairs(ms.soundSlotDefaults()) do
                            ms.soundAssign[sid] = def
                        end
                        ms.saveSettings()
                        ms._soundsDirty = true
                        ms._discoverSounds()
                    else
                        ms.loadTheme()
                        ms._soundsDirty = true
                        ms._discoverSounds()
                        local savedPreset = ms._soundPreset
                        if savedPreset and savedPreset ~= "custom" then
                            local assigns
                            if savedPreset == "default" then
                                assigns = ms.soundSlotDefaults()
                            else
                                local num = tonumber(savedPreset)
                                for _, p in ipairs(ms.buildSoundPresets()) do
                                    if p.num == num then assigns = p.assigns
                                    break end
                                end
                            end
                            for sid, name in pairs(assigns or {}) do
                                ms.soundAssign[sid] = name
                            end
                        end
                        ms.saveSettings()
                    end
                    pcall(function() ms.alert:recolor() end)
                    pcall(function() ms.dev:recolor() end)
                    pcall(function() ms.shell.recolorPopouts() end)
                    if ms.playSlot then
                        pcall(ms.playSlot, data.value and "toggleOn" or "toggleOff")
                    end
                    ms.ui.refresh()
                    hs.timer.doAfter(0.2, function() ms.ui.refresh() end)
                end,

                setDevArchiveLimit = function(data)
                    local n = tonumber(data.value)
                    if n and n >= 0 and n <= 50 then
                        ms._devArchiveLimit = math.floor(n)
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setUpdateChannel = function(data)
                    local ch = data.value
                    if ch == "testing" or ch == "stable" then
                        ms._updateChannel = ch
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setTestingSource = function(data)
                    local src = data.value
                    if src == "release" or src == "artifact" then
                        ms._testingSource = src
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setUiZoom = function(data)
                    local cur = ms._uiZoom or 1.0
                    local target
                    if data.reset then
                        target = 1.0
                    elseif data.delta then
                        target = cur + (tonumber(data.delta) or 0)
                    else
                        target = tonumber(data.value) or cur
                    end
                    if ms.shell and ms.shell.applyZoom then
                        ms.shell.applyZoom(target)
                    else
                        ms._uiZoom = math.max(0.5, math.min(2.0, target))
                    end
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setOctaneMode = function(data)
                    local enabled = data.value and true or false
                    ms._octaneMode = enabled
                    ms.saveSettings()
                    if ms.octane then
                        if enabled then ms.octane._apply() else ms.octane._remove() end
                    end
                    ms.ui.refresh()
                end,

                setOctaneMuteSounds = function(data)
                    ms._octaneMuteSounds = data.value and true or false
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setUiTransparency = function(data)
                    ms._uiTransparencyOff = not (data.value and true or false)
                    ms.saveSettings()
                    if ms.theme and ms.theme.repaint then pcall(ms.theme.repaint) end
                    ms.ui.refresh()
                end,

                setMacroLabEnabled = function(data)
                    local enabled = data.value and true or false
                    ms._macroLabEnabled = enabled
                    if ms._userSettingVals then ms._userSettingVals["macroLabEnabled"] = enabled end
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setGithubToken = function(data)
                    ms._githubToken = data.value or ""
                    local tokenPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token"
                    if ms._githubToken ~= "" then
                        local f = io.open(tokenPath, "w")
                        if f then f:write(ms._githubToken)
                        f:close() end
                        os.execute("chmod 600 '" .. tokenPath .. "'")
                    else
                        os.remove(tokenPath)
                    end
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                setMacroEnabled = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if def and def.system then return end
                    local want = (data.value == true)
                    if want and ms.effectiveBind(data.id) == nil then
                        ms.binds[data.id] = false
                        ms.saveSettings()
                        ms.bind.rebind()
                        hs.timer.doAfter(0.1, function()
                            ms.alert((def and def.label or data.id)
                                .. " has no bind, set one before enabling.", 2, true)
                            ms.ui.refresh()
                        end)
                        return
                    end
                    ms.binds[data.id] = want
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.ui.refresh()
                end,

                setBindIgnoreMods = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if def and def.system then return end
                    ms.bindIgnoreMods = ms.bindIgnoreMods or {}
                    ms.bindIgnoreMods[data.id] = (data.value == true) or nil
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.ui.refresh()
                end,

                setTrackpadMode = function(data)
                    ms.trackpadMode = (data.value == true)
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.ui.refresh()
                end,

                setSocdEnabled = function(data)
                    ms.socdEnabled = (data.value == true)
                    ms.saveSettings()
                    ms.socdApply()
                    ms.ui.refresh()
                end,

                setWindowsMode = function(data)
                    ms.windowsMode = ms.windowsHost or (data.value == true)
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setGamepadEnabled = function(data)
                    ms.gamepadEnabled = (data.value == true)
                    if ms.gamepadEnabled then
                        if ms.gamepadStart then ms.gamepadStart() end
                        if ms.shell and ms.shell.gpEnsureOpenBind then ms.shell.gpEnsureOpenBind() end
                    else
                        if ms.shell and ms.shell.gpClearOpenBind then ms.shell.gpClearOpenBind() end
                        if ms.gamepadStop then ms.gamepadStop() end
                    end
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.ui.refresh()
                end,

                setUpdateAlerts = function(data)
                    ms._updateAlertsDisabled = not (data.value == true)
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setSocdMode = function(data)
                    if data.value == "lastWins" or data.value == "neutral" or data.value == "firstWins" then
                        ms.socdMode = data.value
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                saveDefault = function()
                    ms.saveDefault()
                    ms.ui.refresh()
                end,

                resetToDefault = function()
                    if ms.resetToDefault() then ms.playSlot("reset") end
                    ms.ui.refresh()
                end,
            -- END --

            -- Dev Panels --
                openConsole       = function() ms.dev.console.toggle()  end,
                openWatcher       = function() ms.dev.watcher.toggle()  end,
                openKeys          = function() ms.dev.keys.toggle()     end,
                openWindowMonitor = function() ms.dev.window.toggle()   end,
            -- END --

            -- Binds --
                startRebind = function(data)
                    if not data.id then return end

                    if data.systemBind then
                        local sysDef = ms.systemBinds._defs[data.id]
                        if not sysDef then return end
                        local label = sysDef.label
                        _rebindModal({
                            label    = label,
                            current  = _bindDisplay(ms.systemBinds.effective(data.id)),
                            gamepad  = true,
                            onCancel = function() _restoreAfterCapture()
                            ms.ui.refresh() end,
                            apply    = function(parsed)
                                ms.systemBinds._config[data.id] = parsed
                                ms.saveSettings()
                                ms.playSlot("update")
                                ms.systemBinds.rebind()
                            end,
                        })
                        return
                    end

                    local def = ms.registry._defs[data.id]
                    if not def then return end
                    local label = def.label or data.id
                    _rebindModal({
                        label    = label,
                        current  = _bindDisplay(ms.effectiveBind(data.id)),
                        gamepad  = true,
                        onCancel = function() _restoreAfterCapture()
                        ms.ui.refresh() end,
                        validate = function(parsed, bindStr)
                            local conflictId = ms.bind.siblingConflict(data.id, parsed)
                            if not conflictId then return nil end
                            local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                            return "\"" .. bindStr .. "\" is already used by \"" .. cLabel .. "\"."
                        end,
                        apply    = function(parsed)
                            ms.bindConfig[data.id] = parsed
                            if not def.system then ms.binds[data.id] = true end
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.bind.rebind()
                        end,
                    })
                end,

                bindToMacro = function(data)
                    if not data.id or type(data.targetId) ~= "string" then return end
                    local def        = ms.registry._defs and ms.registry._defs[data.id]
                    local targetDef  = ms.registry._defs and ms.registry._defs[data.targetId]
                    if not def or not targetDef then return end
                    if data.id == data.targetId then
                        ms.playSlot("alert")
                        ms.alert("A macro can't be bound to itself.", 4)
                        return
                    end
                    local visited = {}
                    local cur = data.targetId
                    while cur and not visited[cur] do
                        if cur == data.id then
                            ms.playSlot("alert")
                            ms.alert("That would create a bind loop.", 4)
                            return
                        end
                        visited[cur] = true
                        local c = ms.bindConfig[cur]
                            or (ms.registry._defs[cur] and ms.registry._defs[cur].default)
                        cur = (type(c) == "table" and c.type and ms.registry._defs[c.type])
                            and c.type or nil
                    end
                    local existing = ms.bindConfig[data.id]
                    local mods = (type(data.mods) == "table") and data.mods
                        or (type(existing) == "table" and type(existing.mods) == "table" and existing.mods)
                        or {}
                    ms.bindConfig[data.id] = { type = data.targetId, mods = mods }
                    if not def.system then ms.binds[data.id] = true end
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.bind.rebind()
                    if #mods == 0 then
                        hs.timer.doAfter(0.15, function()
                            ms.ui._actions.startModRebind({ id = data.id })
                        end)
                        return
                    end
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def.label or data.id) .. " now follows "
                            .. (targetDef.label or data.targetId) .. ".", 2, true)
                        ms.ui.refresh()
                    end)
                end,
            -- END --

            -- Authored Settings --
                resetSetting = function(data)
                    local key = data.key
                    local def = ms.macroDefaults or {}
                    if key == "trackpadMode" then
                        ms.trackpadMode = (def.trackpadMode == true)
                        ms.saveSettings()
                        ms.bind.rebind()
                    elseif key == "socdEnabled" then
                        ms.socdEnabled = (def.socdEnabled == true)
                        ms.saveSettings()
                        ms.socdApply()
                    elseif key == "windowsMode" then
                        ms.windowsMode = ms.windowsHost or (def.windowsMode == true)
                        ms.saveSettings()
                    elseif key == "socdMode" then
                        ms.socdMode = def.socdMode or "lastWins"
                        ms.saveSettings()
                    elseif key == "gamepadEnabled" then
                        ms.gamepadEnabled = (def.gamepadEnabled == true)
                        if ms.gamepadEnabled then
                            if ms.shell and ms.shell.gpEnsureOpenBind then ms.shell.gpEnsureOpenBind() end
                        else
                            if ms.shell and ms.shell.gpClearOpenBind then ms.shell.gpClearOpenBind() end
                            if ms.gamepadStop then ms.gamepadStop() end
                        end
                        ms.saveSettings()
                        ms.bind.rebind()
                    elseif key == "soundEnabled" then
                        ms.soundEnabled = true
                        ms.saveSettings()
                    elseif key == "soundVolume" then
                        ms.soundVolume = 100
                        ms.saveSettings()
                    end
                    ms.playSlot("reset")
                    ms.ui.refresh()
                end,

                userSettingChange = function(data)
                    if not data.key then return end
                    ms.settings.set(data.key, data.value)
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                userSettingAction = function(data)
                    if not data.key then return end
                    local def = ms._userSettingIndex[data.key]
                    if def and def.type == "action" and type(def.onAction) == "function" then
                        pcall(def.onAction)
                    end
                    local sysAction = ms._systemActions and ms._systemActions[data.key]
                    if type(sysAction) == "function" then pcall(sysAction) end
                    ms.ui.refresh()
                end,

                resetUserSetting = function(data)
                    if not data.key then return end
                    local def = ms._userSettingIndex[data.key]
                    if not def or def.default == nil then return end
                    ms.settings.set(data.key, def.default)
                    ms.playSlot("reset")
                    ms.ui.refresh()
                end,

                runFunction = function(data)
                    if not data or type(data.id) ~= "string" then return end
                    if ms.callFn then
                        local co = coroutine.create(function() ms.callFn(data.id) end)
                        local ok, err = coroutine.resume(co)
                        if not ok then print("runFunction: " .. tostring(err)) end
                    end
                    ms.playSlot("interact")
                end,

                setHelperVarValue = function(data)
                    if not data or type(data.name) ~= "string" then return end
                    if ms.vars and ms.vars.set then ms.vars.set(data.name, data.value) end
                    ms.playSlot("update")
                    if ms.ui.markDirty then ms.ui.markDirty() end
                    ms.ui.refresh()
                end,

                addUserSetting = function(data)
                    local ok, err = ms.addAuthoredSetting(data and data.def)
                    if ok then
                        ms.playSlot("update")
                        ms.ui.refresh()
                        ms.alert("Setting added to your pack.", 3)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't add setting: " .. (err or "invalid"), 4)
                    end
                end,

                removeUserSetting = function(data)
                    local ok, err = ms.removeAuthoredSetting(data and data.key)
                    if ok then
                        ms.playSlot("reset")
                        ms.ui.refresh()
                        ms.alert("Tool removed from your pack.", 3)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't remove tool: " .. (err or "invalid"), 4)
                    end
                end,

                updateUserSetting = function(data)
                    local ok, err = ms.updateAuthoredSetting(
                        data and data.key, data and data.def)
                    if ok then
                        ms.playSlot("update")
                        ms.ui.refresh()
                        ms.alert("Setting updated.", 3)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't update setting: " .. (err or "invalid"), 4)
                    end
                end,

                removeUserSettingByUid = function(data)
                    local ok, err = ms.removeAuthoredSettingByUid(data and data.uid)
                    if ok then
                        ms.playSlot("reset")
                        ms.ui.refresh()
                        ms.alert("Item removed from your pack.", 2)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't remove item: " .. (err or "invalid"), 4)
                    end
                end,

                reorderUserSettings = function(data)
                    local ok, err = ms.reorderAuthoredSettings(data and data.order)
                    if ok then
                        ms.playSlot("interact")
                        ms.ui.refresh()
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't reorder: " .. (err or "invalid"), 4)
                    end
                end,

                addUserMenu = function(data)
                    local ok, err = ms.addAuthoredMenu(data or {})
                    if ok then
                        ms.playSlot("update")
                        ms.ui.refresh()
                        ms.alert("Section added.", 2)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't add section: " .. (err or "invalid"), 4)
                    end
                end,

                updateUserMenu = function(data)
                    local ok, err = ms.updateAuthoredMenu(data and data.id, data or {})
                    if ok then
                        ms.playSlot("update")
                        ms.ui.refresh()
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't rename section: " .. (err or "invalid"), 4)
                    end
                end,

                removeUserMenu = function(data)
                    local ok, err = ms.removeAuthoredMenu(data and data.id)
                    if ok then
                        ms.playSlot("reset")
                        ms.ui.refresh()
                        ms.alert("Section removed.", 2)
                    else
                        ms.playSlot("alert")
                        ms.alert("Couldn't remove section: " .. (err or "invalid"), 4)
                    end
                end,
            -- END --

            -- Modal & Bind Config --
                modalResult = function(data)
                    if ms.ui._modalCallback then
                        local cb = ms.ui._modalCallback
                        ms.ui._modalCallback = nil
                        pcall(cb, {
                            confirmed = data.confirmed == true,
                            value     = type(data.value) == "string" and data.value or "",
                        })
                    end
                end,

                resetBind = function(data)
                    if not data.id then return end

                    if data.systemBind then
                        ms.systemBinds._config[data.id] = nil
                        ms.saveSettings()
                        ms.systemBinds.rebind()
                        ms.playSlot("reset")
                        local def = ms.systemBinds._defs[data.id]
                        hs.timer.doAfter(0.1, function()
                            ms.alert((def and def.label or data.id) .. " reset to default.", 2, true)
                            ms.ui.refresh()
                        end)
                        return
                    end

                    local def = ms.registry._defs[data.id]
                    if not def then return end
                    ms.bindConfig[data.id] = nil
                    local restored = ms.effectiveBind(data.id) ~= nil
                    if not restored then ms.binds[data.id] = false end
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def.label or data.id) .. (restored
                            and " reset to default."
                            or " has no default bind, disabled."), 2, true)
                        ms.ui.refresh()
                    end)
                end,

                setModifier = function(data)
                end,

                clearModifier = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs and ms.registry._defs[data.id]
                    if not def or not def.default then return end
                    ms.bindConfig[data.id] = nil
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def.label or data.id) .. " reset to default.", 2, true)
                        ms.ui.refresh()
                    end)
                end,

                startModRebind = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if not def then return end
                    local curCfg  = ms.bindConfig[data.id] or def.default
                    if not curCfg then return end
                    local label = def.label or data.id
                    local curMods = curCfg and curCfg.mods or {}
                    local cur     = curMods[1]
                    local curType = curCfg.type or (def.default and def.default.type)

                    ms.alert("Modifier for \"" .. label .. "\""
                        .. "\nCurrent: " .. (cur or "unset")
                        .. "\nPress a key, Backspace to clear, Escape to cancel.", 15, false, { id = "_rebind" })

                    ms._inputOpen = true
                    ms.ui._open   = false

                    local capture, cancelTimer
                    local prevFlags = {}

                    local function finish(newKey, cancelled)
                        ms._inputOpen = false
                        if not cancelled then
                            if newKey then
                                ms.bindConfig[data.id] = {
                                    type = curType,
                                    mods = { newKey },
                                }
                            else
                                ms.bindConfig[data.id] = {
                                    type = curType,
                                    mods = {},
                                }
                            end
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot(newKey and "update" or "reset")
                        end
                        ms.ui.ensureVisible()
                        hs.timer.doAfter(0.1, function()
                            if not cancelled then
                                if newKey then
                                    ms.alert("Modifier set to: " .. newKey, 3, true, { id = "_rebind" })
                                else
                                    ms.alert("Modifier cleared.", 3, true, { id = "_rebind" })
                                end
                            else
                                ms.alert("Modifier rebind cancelled.", 2, false, { id = "_rebind" })
                            end
                            ms.ui.refresh()
                        end)
                    end

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.flagsChanged,
                    }, function(event)
                        local t     = event:getType()
                        local flags = event:getFlags()

                        if t == hs.eventtap.event.types.flagsChanged then
                            local newMod = nil
                            if flags.shift and not prevFlags.shift then newMod = "shift"
                            elseif flags.alt   and not prevFlags.alt   then newMod = "alt"
                            elseif flags.ctrl  and not prevFlags.ctrl  then newMod = "ctrl"
                            elseif flags.cmd   and not prevFlags.cmd   then newMod = "cmd" end
                            prevFlags = flags
                            if not newMod then return false end
                            capture:stop()
                            capture = nil
                            cancelTimer:stop()
                            finish(newMod, false)
                            return false
                        end

                        capture:stop()
                        capture = nil
                        cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                            finish(nil, true)
                        elseif keyCode == 51 then
                            finish(nil, false)
                        else
                            local keyName = hs.keycodes.map[keyCode]
                            finish(keyName or nil, keyName == nil)
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop()
                            capture = nil
                            finish(nil, true)
                        end
                    end)
                end,
            -- END --
    }
end

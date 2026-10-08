-- core/bind_controller (Macro Bind Controller) --
    return function(ms)
        local _debounceTimer = nil
        local _stateSound    = nil

        local function _doNotify(state)
            if loadfinish ~= 1 then return end
            if _debounceTimer then _debounceTimer:stop()
            _debounceTimer = nil end
            _debounceTimer = hs.timer.doAfter(0.05, function()
                _debounceTimer = nil
                if _stateSound then pcall(function() _stateSound:stop() end)
                _stateSound = nil end
                if state == 1 then
                    _stateSound = ms.playSlot("enabled")
                    ms.alert("Macros enabled!",  3, true, {
                        id = "_state",
                        source = "system",
                    })
                else
                    _stateSound = ms.playSlot("disabled")
                    ms.alert("Macros disabled.", 3, true, {
                        id = "_state",
                        source = "system",
                    })
                end
            end)
        end

        local function _refreshUIState()
            if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
            local shellVisible = ms._shellState and ms._shellState.visible
            if shellVisible or (ms.ui and ms.ui._open) then
                if ms.shell and ms.shell.eval then
                    pcall(ms.shell.eval, "window.updateMacrosToggleBtn&&updateMacrosToggleBtn("
                        .. tostring(BindValidity == 1) .. ")")
                end
            end
        end

        ms.setMacros = function(state, silent)
            if state == 1 and BindValidity ~= 1 then
                BindValidity = 1
                hs.timer.doAfter(0, function()
                    if BindValidity ~= 1 then return end
                    if ms._updateCamAnchor then ms._updateCamAnchor() end
                    ms.dev.log({
                        type = "system",
                        event = "macros_enabled",
                    })
                    if not silent then _doNotify(1) end
                    _refreshUIState()
                end)
            elseif state == 0 and BindValidity ~= 0 then
                BindValidity = 0
                if ms._releaseTrackpadHolds then ms._releaseTrackpadHolds() end
                hs.timer.doAfter(0, function()
                    if BindValidity ~= 0 then return end
                    for _, timer in pairs(ms.running) do
                        if timer and timer.stop then timer:stop() end
                    end
                    ms.running = {}
                    ms.dev.log({
                        type = "system",
                        event = "macros_disabled",
                    })
                    if not silent then _doNotify(0) end
                    _refreshUIState()
                    ms.cancelMacros()
                end)
            end
        end

        ms._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
            if eventType == hs.application.watcher.activated then
                if appName == (ms._targetApp) then
                    local fromDialog = ms._inputOpen
                    ms._inputOpen = false
                    ms._targetActive = true
                    ms.dev.log({
                        type = "system",
                        event = "target_focus",
                        fromDialog = fromDialog or false,
                    })
                    if ms._updateCamAnchor then ms._updateCamAnchor() end
                    if ms._resetCamActivated then ms._resetCamActivated() end
                    if not ms._loadComplete then return end
                    if fromDialog then
                        BindValidity = 1
                    else
                        ms.setMacros(1, true)
                    end
                else
                    if appName == "Hammerspoon" and ms._ownUiHeld then return end
                    ms._inputOpen    = (appName == "Hammerspoon") and (ms._targetActive or ms._inputOpen)
                    ms._targetActive = false
                    ms.dev.log({
                        type = "system",
                        event = "target_blur",
                        to = appName,
                    })
                    if ms._camActivated ~= nil then ms._camActivated = false end
                    if BindValidity == 1 then
                        ms.setMacros(0, true)
                    end
                end
            end
        end):start()
        _G.__ms_appWatcher = ms._appWatcher

        ms._ownUiFocus = function(hasFocus)
            if hasFocus then
                if ms._ownUiHeld then return end
                ms._ownUiHeld = true
                ms._inputOpen = ms._targetActive or ms._inputOpen
                ms._targetActive = false
                if BindValidity == 1 then ms.setMacros(0, true) end
                return
            end
            if not ms._ownUiHeld then return end
            ms._ownUiHeld = false
            local front = hs.application.frontmostApplication()
            if front and front:name() == ms._targetApp then
                ms._inputOpen = false
                ms._targetActive = true
                if ms._loadComplete then ms.setMacros(1, true) end
            end
        end

        _G._initTimer = hs.timer.doAfter(0.3, function()
            local frontApp = hs.application.frontmostApplication()
            if ms._targetApp and frontApp and frontApp:name() == ms._targetApp then
                ms._targetActive = true
            end
        end)

        ms.octane = ms.octane or {}
        -- Visible pulse whenever octane flips
        ms.octane._notify = function(on)
            if ms.playSlot then pcall(ms.playSlot, on and "toggleOn" or "toggleOff") end
            if not ms.alert then return end
            pcall(ms.alert,
                on and "Octane enabled!" or "Octane disabled.",
                3, true, { id = "octane_state", source = "system" })
        end
        ms.octane.on = function()
            if ms._octaneMode then return end
            ms._octaneMode = true
            if ms.saveSettings then pcall(ms.saveSettings) end
            ms.octane._apply()
            ms.octane._notify(true)
            if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
        end
        ms.octane.off = function()
            if not ms._octaneMode then return end
            ms._octaneMode = false
            if ms.saveSettings then pcall(ms.saveSettings) end
            ms.octane._remove()
            ms.octane._notify(false)
            if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
        end
        ms.octane.toggle = function()
            if ms._octaneMode then ms.octane.off() else ms.octane.on() end
        end
        ms.octane._apply = function()
            if ms.dev and ms.dev.log and ms.dev.log.pauseAll then
                pcall(ms.dev.log.pauseAll)
            end
            if ms.devtools and ms.devtools.stopAllPollers then
                pcall(function() ms.devtools:stopAllPollers() end)
            end
            if ms._menuHoverWatcher then
                ms._menuHoverWatcher:stop()
                ms._menuHoverWatcher = nil
            end
            if ms.devtools and ms.devtools.setWinElementInspect then
                pcall(function() ms.devtools:setWinElementInspect(false) end)
            end
            if ms.theme and ms.theme.repaint then pcall(ms.theme.repaint) end
        end
        ms.octane._remove = function()
            if ms.dev and ms.dev.log and ms.dev.log.resumeAll then
                pcall(ms.dev.log.resumeAll)
            end
            if ms.devtools and ms.devtools.restartPollersIfActive then
                pcall(function() ms.devtools:restartPollersIfActive() end)
            end
            if ms._menuVisible and ms._menuHoverStart then
                pcall(ms._menuHoverStart)
            end
            if ms.theme and ms.theme.repaint then pcall(ms.theme.repaint) end
        end

        ms._hotkeys = {
            panic       = {
                mods = {"alt"},
                key = "F10",
            },
            quickReload = {
                mods = {"alt"},
                key = "[",
            },
            fullReload  = {
                mods = {"alt"},
                key = "]",
            },
            openMenu    = {
                mods = {"alt"},
                key = "p",
            },
        }
        ms._hotkeyHandles = {}

        local _hotkeyCooldowns = {}
        local _hotkeyDown = {}
        local _hotkeyDownAt = {}
        local _hotkeyTapSet = {}
        local _HOTKEY_LATCH_MAX = 10

        local function _clearStaleLatch(id, isRepeat)
            if not _hotkeyDown[id] then return end

            local since = _hotkeyDownAt[id]
            local aged  = (not since) or (hs.timer.secondsSinceEpoch() - since) > _HOTKEY_LATCH_MAX

            if (not isRepeat) or aged then
                _hotkeyDown[id]      = false
                _hotkeyCooldowns[id] = false
                _hotkeyDownAt[id]    = nil
            end
        end

        local function _resetHotkeyLatches()
            _hotkeyDown      = {}
            _hotkeyCooldowns = {}
            _hotkeyDownAt    = {}
        end

        ms._makeKeyWatcher = function(mods, key, onDown)
            local keyCode = hs.keycodes.map[key]
            if not keyCode then return nil end

            local modsAny = (mods == "any")
            local modSet = {}
            if not modsAny then
                for _, m in ipairs(mods or {}) do modSet[m] = true end
            end

            local function modsMatch(flags)
                if modsAny then return true end
                for m, _ in pairs(modSet) do
                    if not flags[m] then return false end
                end
                return true
            end
            local function modsExact(flags)
                if modsAny then return true end
                if not modsMatch(flags) then return false end
                if flags.cmd   and not modSet.cmd   then return false end
                if flags.alt   and not modSet.alt   then return false end
                if flags.ctrl  and not modSet.ctrl  then return false end
                if flags.shift and not modSet.shift then return false end
                return true
            end
            local id = (modsAny and "any" or table.concat(mods or {}, ",")) .. ":" .. key
            local tap = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
                hs.eventtap.event.types.flagsChanged,
            }, function(e)
                local type = e:getType()
                local flags = e:getFlags()
                local kc = e:getKeyCode()
                if type == hs.eventtap.event.types.flagsChanged then
                    if not modsAny and not modsMatch(flags) then
                        _hotkeyDown[id] = false
                        _hotkeyCooldowns[id] = false
                        _hotkeyDownAt[id] = nil
                    end
                    return false
                end
                if type == hs.eventtap.event.types.keyDown then
                    if kc == keyCode then
                        local isRepeat = (e:getProperty(
                            hs.eventtap.event.properties.keyboardEventAutorepeat) or 0) ~= 0
                        _clearStaleLatch(id, isRepeat)
                        if modsExact(flags) and not _hotkeyDown[id] and not _hotkeyCooldowns[id] then
                            _hotkeyDown[id]   = true
                            _hotkeyDownAt[id] = hs.timer.secondsSinceEpoch()
                            hs.timer.doAfter(0, onDown)
                        end
                        return ms._swallowHotkeys and true or false
                    end
                    return false
                end
                if type == hs.eventtap.event.types.keyUp then
                    if kc == keyCode then
                        _hotkeyDown[id]   = false
                        _hotkeyDownAt[id] = nil
                        _hotkeyCooldowns[id] = true
                        hs.timer.doAfter(0.15, function()
                            _hotkeyCooldowns[id] = false
                        end)
                        return ms._swallowHotkeys and true or false
                    end
                    return false
                end
                return false
            end)
            return tap
        end

        ms._bindHotkeys = function()
            for _, h in pairs(ms._hotkeyHandles) do
                if h and h.stop then h:stop() end
            end
            ms._hotkeyHandles = {}
            _resetHotkeyLatches()

            local kept = {}
            for _, t in ipairs(ms._resilientTaps) do
                if not _hotkeyTapSet[t] then kept[#kept+1] = t end
            end
            ms._resilientTaps = kept
            _hotkeyTapSet = {}

            local function _register(name, t)
                ms._hotkeyHandles[name] = t
                _hotkeyTapSet[t] = true
                ms._resilientTaps[#ms._resilientTaps+1] = t
                t:start()
            end

            local hk = ms._hotkeys.panic
            local tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                if not ms._hotkeysReady then return end
                if not ms._targetActive and not ms._isSafeZone() then return end
                ms.setMacros(0)
            end)
            if tap then _register("panic", tap) end

            if ms._quickReloadHotkey then
                pcall(function() ms._quickReloadHotkey:delete() end)
                ms._quickReloadHotkey = nil
            end
            hk = ms._hotkeys.quickReload
            do
                local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                    if not ms._hotkeysReady then return end
                    if ms._qrCooldown then return end
                    ms._qrCooldown = true
                    if ms._qrCooldownTimer then ms._qrCooldownTimer:stop() end
                    ms._qrCooldownTimer = hs.timer.doAfter(1.0, function() ms._qrCooldown = false end)
                    pcall(ms.reload)
                end)
                if ok and hotkey then ms._quickReloadHotkey = hotkey end
            end

            if ms._fullReloadHotkey then
                pcall(function() ms._fullReloadHotkey:delete() end)
                ms._fullReloadHotkey = nil
            end
            hk = ms._hotkeys.fullReload
            do
                local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                    if not ms._hotkeysReady then return end
                    if ms.restart then ms.restart() else hs.reload() end
                end)
                if ok and hotkey then ms._fullReloadHotkey = hotkey end
            end

            if ms._openMenuHotkey then
                pcall(function() ms._openMenuHotkey:delete() end)
                ms._openMenuHotkey = nil
            end
            hk = ms._hotkeys.openMenu
            do
                local ok, hotkey = pcall(hs.hotkey.bind, hk.mods, hk.key, function()
                    if not ms._hotkeysReady then return end
                    if ms._macroLabEnabled and ms.shell and ms.shell.toggle then
                        ms.shell.toggle()
                    elseif ms.ui and ms.ui.toggle then
                        ms.ui.toggle()
                    end
                end)
                if ok and hotkey then ms._openMenuHotkey = hotkey end
            end

        end

        ms._tapWatchdog = hs.timer.doEvery(2, function()
            local revivedHotkey = false

            for _, tap in ipairs(ms._resilientTaps) do
                if tap and not tap:isEnabled() then
                    tap:start()
                    if _hotkeyTapSet[tap] then revivedHotkey = true end
                    if ms.dev then print("ms: revived a disabled eventtap") end
                end
            end

            if revivedHotkey then _resetHotkeyLatches() end
        end)

        ms._bindHotkeys()

    end
-- END core/bind_controller --

return function(ms)
-- MsUI --
    local MsUI = {}

    MsUI.name    = "MsUI"
    MsUI.version = "1.0"

    local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
-- END MsUI --

-- Init --
    function MsUI:init()
    end
-- END Init --

-- Start --
    function MsUI:start()
        if not _G.ms then return end
        local ms = _G.ms
        if ms.checkGuardian and not ms.checkGuardian("MsUI") then return end

        self:_initPanel(ms)
    end
-- END Start --

-- Webview Panel --
    function MsUI:_initPanel(ms)
    require("hs.webview")
    require("hs.webview.usercontent")
    -- Panel State & Builders --
        ms.ui = {
            _panel         = nil,
            _open          = false,
            _modalCallback = nil,
            _panelPos      = nil,
            _uiFadeTimer   = nil,
        }

        local function _modParts(mods)
            local out = {}
            if type(mods) == "table" then
                for _, m in ipairs(mods) do
                    out[#out + 1] = m:sub(1, 1):upper() .. m:sub(2)
                end
            elseif mods == "any" then
                out[#out + 1] = "Any"
            end
            return out
        end

        local function _bindDisplay(c, anyMods)
            if not c then return nil end
            local parts = _modParts(c.mods)
            if anyMods and (c.type == "key" or c.type == "combo") and parts[1] ~= "Any" then
                table.insert(parts, 1, "Any")
            end
            if c.type == "mods" then
                if #parts == 0 then return "unset" end
                return table.concat(parts, "+")
            end
            local trigger
            if c.type == "mouse" then
                trigger = "Mouse " .. tostring(c.button)
            elseif c.type == "scroll" then
                local d = c.direction or "?"
                trigger = "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
            elseif c.type == "gamepad" then
                trigger = "Pad " .. ms.gpLabel(c)
            elseif c.type == "combo" then
                local ks = {}
                for _, k in ipairs(c.keys or {}) do ks[#ks+1] = (k or ""):upper() end
                trigger = table.concat(ks, "+")
            else
                trigger = (c.key or ""):upper()
            end
            table.insert(parts, trigger)
            return table.concat(parts, "+")
        end

        local function _bindTokens(c)
            if not c then return {} end
            local out = _modParts(c.mods)
            if c.type == "mods" then
                return out
            elseif c.type == "mouse" then
                out[#out + 1] = "Mouse " .. tostring(c.button)
            elseif c.type == "scroll" then
                local d = c.direction or "?"
                out[#out + 1] = "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
            elseif c.type == "gamepad" then
                out[#out + 1] = "Pad " .. ms.gpLabel(c)
            elseif c.type == "combo" then
                for _, k in ipairs(c.keys or {}) do out[#out + 1] = (k or ""):upper() end
            else
                out[#out + 1] = (c.key or ""):upper()
            end
            return out
        end

        local function _effectiveParent(id)
            local def = ms.registry._defs and ms.registry._defs[id]
            if not def then return nil end
            local cfg = ms.bindConfig and ms.bindConfig[id]
            local src = (type(cfg) == "table" and cfg.type) and cfg or def.default
            if type(src) ~= "table" or not src.type then return nil end
            if ms.registry._defs[src.type] then return src.type end
            return nil
        end

        local function _buildMacroList()
            local macros  = {}
            local byId    = {}

            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not def.system and not (ms._suppressedMacros and ms._suppressedMacros[id])
                    and not _effectiveParent(id) then
                    local eff = ms.effectiveBind(id)
                    local bindable = eff ~= nil
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    local entry = {
                        id        = id,
                        label     = def.label,
                        group     = def.group,
                        bind      = _bindDisplay(eff, ms.bindIgnoreMods and ms.bindIgnoreMods[id]),
                        enabled   = (enabled and bindable) and true or false,
                        bindable  = bindable,
                        bindType  = eff and eff.type or nil,
                        ignoreMods = (ms.bindIgnoreMods and ms.bindIgnoreMods[id]) and true or false,
                        subs      = {},
                    }
                    byId[id] = entry
                    table.insert(macros, entry)
                end
            end

            for _, id in ipairs(ms.registry._defList or {}) do
                local def          = ms.registry._defs[id]
                local directParent = _effectiveParent(id)
                if def and not def.system and not (ms._suppressedMacros and ms._suppressedMacros[id])
                    and directParent then
                    local parent = directParent
                    local seen = { [id] = true }
                    while parent and not byId[parent] and not seen[parent] do
                        seen[parent] = true
                        parent = _effectiveParent(parent)
                    end
                    local host = parent and byId[parent]
                    if host then
                        local eff = ms.effectiveBind(id)
                        local subEnabled = ms.binds[id]
                        if subEnabled == nil then subEnabled = def.enabled end
                        local subBindable = eff ~= nil
                        table.insert(host.subs, {
                            id       = id,
                            label    = def.label,
                            group    = def.group,
                            bind     = _bindDisplay(eff, ms.bindIgnoreMods and ms.bindIgnoreMods[id]),
                            parent   = directParent,
                            enabled  = (subEnabled and subBindable) and true or false,
                            bindable = subBindable,
                            bindType = eff and eff.type or nil,
                            ignoreMods = (ms.bindIgnoreMods and ms.bindIgnoreMods[id]) and true or false,
                        })
                    end
                end
            end

            for _, id in ipairs({
                "enable",
                "disable",
                "toggle",
                "octane",
                "zoomIn",
                "zoomOut",
                "zoomReset",
            }) do
                local def = ms.systemBinds._defs[id]
                if def then
                    table.insert(macros, {
                        id         = id,
                        label      = def.label,
                        group      = "system",
                        bind       = _bindDisplay(ms.systemBinds.effective(id)),
                        systemBind = true,
                        subs       = {},
                    })
                end
            end

            return macros
        end
        ms.ui._buildMacroList = _buildMacroList

        local function _buildGamepadBinds()
            local out = {}
            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not def.system
                    and not (ms._suppressedMacros and ms._suppressedMacros[id]) then
                    local eff = ms.effectiveBind(id)
                    if eff and eff.type == "gamepad" then
                        out[#out + 1] = {
                            id     = id,
                            label  = def.label or id,
                            pad    = ms.gpLabel(eff),
                            bind   = _bindDisplay(eff),
                        }
                    end
                end
            end
            for _, id in ipairs({ "enable", "disable", "toggle", "octane", "zoomIn", "zoomOut", "zoomReset" }) do
                local def = ms.systemBinds._defs[id]
                if def then
                    local eff = ms.systemBinds.effective(id)
                    if eff and eff.type == "gamepad" then
                        out[#out + 1] = {
                            id         = id,
                            label      = def.label or id,
                            pad        = ms.gpLabel(eff),
                            bind       = _bindDisplay(eff),
                            systemBind = true,
                        }
                    end
                end
            end
            return out
        end
        ms.ui._buildGamepadBinds = _buildGamepadBinds

        local function _buildUIState()
            local macros = _buildMacroList()

            ms._discoverSounds()
            local soundNames = {}
            for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
            table.sort(soundNames)

            local macroSoundNames = {}
            for name in pairs(ms.macroSounds or {}) do table.insert(macroSoundNames, name) end
            table.sort(macroSoundNames)

            local soundEntries = {}
            local function _entry(name, path, role)
                local imported = (ms.importedSounds or {})[name] ~= nil
                soundEntries[#soundEntries + 1] = {
                    name      = name,
                    kind      = imported and "imported" or role,
                    role      = role,
                    imported  = imported,
                    removable = (role ~= "default"),
                }
            end
            for _, name in ipairs(soundNames) do
                local path = (ms.sounds or {})[name] or ""
                _entry(name, path,
                    path:find("/sounds/defaults/") and "default" or "active")
            end
            for _, name in ipairs(macroSoundNames) do
                _entry(name, (ms.macroSounds or {})[name] or "", "macro")
            end

            local soundPresets = ms.buildSoundPresets()

            local status, curHash = ms.integrity.check()
            local meta = ms.macroMeta or {}

            local userSoundSlots = {}
            for _, def in ipairs(ms._userSettingDefs) do
                if def.type == "soundSlot" then
                    table.insert(userSoundSlots, {
                        key = def.key,
                        label = def.label or def.key,
                    })
                end
            end
            for _, menuDef in ipairs(ms._userMenuDefs) do
                for _, item in ipairs(menuDef.items or {}) do
                    if item.type == "soundSlot" then
                        table.insert(userSoundSlots, {
                            key = item.key,
                            label = item.label or item.key,
                        })
                    end
                end
            end

            local _authoredKeys = {}
            for _, ad in ipairs(ms._authoredSettings or {}) do
                if ad.key then _authoredKeys[ad.key] = true end
            end

            local function _serItem(d)
                local it = {
                    type     = d.type,
                    key      = d.key,
                    label    = d.label,
                    hint     = d.hint,
                    authored = (d.uid ~= nil) or (d.key and _authoredKeys[d.key]) or nil,
                    uid      = d.uid,
                    section  = d.section,
                    origin   = d._origin or "pack",
                    plugin   = d._plugin,
                }
                if d.type == "slider" then
                    it.min  = d.min
                    it.max  = d.max
                    it.step = d.step
                    it.unit = d.unit
                elseif d.type == "seg" then
                    it.options = d.options
                elseif d.type == "action" then
                    it.btnLabel = d.btnLabel
                    it.danger = d.danger
                elseif d.type == "group" then
                    local subs = {}
                    for _, sd in ipairs(d.items or {}) do
                        local si = {
                            type    = sd.type,
                            key     = sd.key,
                            label   = sd.label,
                            hint    = sd.hint,
                        }
                        if sd.type == "slider" then
                            si.min  = sd.min
                            si.max  = sd.max
                            si.step = sd.step
                            si.unit = sd.unit
                        elseif sd.type == "seg"    then si.options  = sd.options
                        elseif sd.type == "action" then
                            si.btnLabel = sd.btnLabel
                            si.danger = sd.danger
                        end
                        if sd.key and sd.type ~= "action"
                            and sd.type ~= "divider" and sd.type ~= "groupLabel" then
                            si.value   = ms.settings.get(sd.key)
                            si.default = sd.default
                        end
                        table.insert(subs, si)
                    end
                    it.items = subs
                end
                if d.key and d.type ~= "action"
                    and d.type ~= "divider" and d.type ~= "groupLabel"
                    and d.type ~= "group" then
                    it.value   = ms.settings.get(d.key)
                    it.default = d.default
                end
                return it
            end

            local userSettings = {}
            for _, def in ipairs(ms._userSettingDefs) do
                local okV, shown = true, true
                if type(def.visible) == "function" then
                    okV, shown = pcall(def.visible)
                end
                if not okV or shown ~= false then
                    table.insert(userSettings, _serItem(def))
                end
            end

            local userSections = {}
            for _, m in ipairs(ms._authoredMenus or {}) do
                table.insert(userSections, {
                    id    = m.id,
                    title = m.title,
                    icon  = m.icon,
                    hint  = m.hint,
                    origin = "user",
                })
            end
            local userFunctions = {}
            if ms.compiler and ms.compiler.listFunctions then
                local okF, flist = pcall(ms.compiler.listFunctions)
                if okF and type(flist) == "table" then
                    for _, f in ipairs(flist) do
                        userFunctions[#userFunctions + 1] = {
                            id     = f.id,
                            label  = f.name or f.id,
                            origin = "user",
                        }
                    end
                end
            end
            local userVariables = {}
            if ms.vars and ms.vars.list then
                local okV, listV = pcall(ms.vars.list)
                if okV and type(listV) == "table" then userVariables = listV end
            end

            local userMenus = {}
            for _, menuDef in ipairs(ms._userMenuDefs) do
                local items = {}
                for _, item in ipairs(menuDef.items) do
                    local entry = {
                        type  = item.type,
                        key   = item.key,
                        label = item.label,
                        hint  = item.hint,
                    }
                    if item.type == "slider" then
                        entry.min  = item.min
                        entry.max  = item.max
                        entry.step = item.step
                        entry.unit = item.unit
                    elseif item.type == "seg" then
                        entry.options = item.options
                    elseif item.type == "action" then
                        entry.btnLabel = item.btnLabel
                        entry.danger = item.danger
                    end
                    if item.key then
                        entry.value   = ms.settings.get(item.key)
                        entry.default = item.default
                    end
                    table.insert(items, entry)
                end
                table.insert(userMenus, {
                    id     = menuDef.id,
                    title  = menuDef.title,
                    icon   = menuDef.icon,
                    items  = items,
                    origin = menuDef._origin or "pack",
                    plugin = menuDef._plugin,
                })
            end

            local themeFonts = {}
            for _, fam in ipairs({
                "Palatino",
                "Georgia",
                "Helvetica",
                "Menlo",
            }) do
                table.insert(themeFonts, {
                    label = fam,
                    value = fam,
                })
            end
            local _fontDir = os.getenv("HOME") .. "/.hammerspoon/ui/fonts/"
            if hs.fs.attributes(_fontDir) then
                local files = {}
                for entry in hs.fs.dir(_fontDir) do
                    if entry:match("%.[ot]tf$") or entry:match("%.woff2?$") then
                        table.insert(files, entry)
                    end
                end
                table.sort(files)
                for _, entry in ipairs(files) do
                    table.insert(themeFonts, {
                        label = entry:match("^(.+)%.[^%.]+$") or entry,
                        value = "ui/fonts/" .. entry,
                    })
                end
            end

            local themeFile = ms.readThemeFile and ms.readThemeFile() or {}
            local themeSet  = {}
            for k in pairs(themeFile) do themeSet[k] = true end

            local themeOut = {}
            for k, v in pairs(ms._theme) do themeOut[k] = v end
            if themeOut.font and themeOut.font:match("%.[ot]tf$")
                or (themeOut.font and themeOut.font:match("%.woff2?$"))
            then
                local fp = os.getenv("HOME") .. "/.hammerspoon/" .. themeOut.font
                if hs.fs.attributes(fp) then
                    themeOut.fontURL  = "file://" .. fp
                    themeOut.font = themeOut.font:match("([^/\\]+)%.[^%.]+$") or themeOut.font
                end
            end

            return {
                macrosEnabled           = (BindValidity == 1),
                macros                  = macros,
                trackpadMode            = ms.trackpadMode or false,
                socdEnabled             = ms.socdEnabled or false,
                socdMode                = ms.socdMode or "lastWins",
                windowsMode             = ms.windowsMode or false,
                windowsHost             = ms.windowsHost or false,
                gamepadEnabled          = ms.gamepadEnabled or false,
                gamepadConnected        = ms._gamepadConnected or false,
                gamepadControllers      = ms._gamepadControllers or {},
                gamepadBinds            = _buildGamepadBinds(),

                soundEnabled            = ms.soundEnabled,
                soundVolume             = ms.soundVolume or 100,
                soundAssign             = ms.soundAssign or {},
                soundSlots              = ms.soundSlots or {},
                soundNames              = soundNames,
                macroSoundNames         = macroSoundNames,
                soundEntries            = soundEntries,
                bundleSoundsWithTheme   = ms.bundleSoundsWithTheme ~= false,
                soundPresets            = soundPresets,
                currentProfile          = (ms.alignedProfile and ms.alignedProfile())
                    or (ms.activeProfile and ms.activeProfile()) or "",
                profiles                = ms.getProfiles(),
                integrityStatus         = status,
                integrityHash           = curHash,
                devMode                 = ms.devmode ~= nil and ms.devmode.isOn() or false,
                devIpcRunning           = ms.devmode ~= nil and ms.devmode.ipcRunning() or false,
                devBooted               = ms.devmode ~= nil and ms.devmode.bootedInDevMode() or false,
                plugins                 = (function()
                    if not (ms.package and ms.package.listPlugins) then return {} end
                    local ok, list = pcall(ms.package.listPlugins)
                    if not ok or type(list) ~= "table" then return {} end
                    local failed = (ms.plugins and ms.plugins.failed) or {}
                    local loaded = (ms.plugins and ms.plugins.loaded) or {}
                    for _, p in ipairs(list) do
                        p.loadError = failed[p.dir]
                        p.running   = loaded[p.dir] == true
                    end
                    return list
                end)(),
                macroMeta               = {
                    name    = meta.name,
                    author  = meta.author,
                    website = meta.website,
                },
                docsURL                 = ms._docsURL,
                updateManifestURL       = ms._updateManifestURL,
                userSettings            = userSettings,
                userFunctions           = userFunctions,
                userVariables           = userVariables,
                userSections            = userSections,
                userSoundSlots          = userSoundSlots,
                userMenus               = userMenus,
                hiddenFeatures          = ms._hiddenFeatures,
                customThemeEnabled      = not (ms._customThemeDisabled or false),
                devArchiveLimit         = ms._devArchiveLimit or 15,
                backupIntervalHours     = ms._backupIntervalHours or 12,
                backupKeep              = ms._backupKeep or 10,
                updateChannel           = ms._updateChannel or "stable",
                updateAlertsDisabled    = ms._updateAlertsDisabled or false,
                testingSource           = ms._testingSource or "release",
                uiZoom                  = ms._uiZoom or 1.0,
                octaneMode              = ms._octaneMode or false,
                octaneMuteSounds        = ms._octaneMuteSounds or false,
                uiTransparencyOff       = ms._uiTransparencyOff or false,
                macroLabEnabled         = ms._macroLabEnabled ~= false,
                githubToken             = (function()
                    if ms._githubToken then return ms._githubToken end
                    local f = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token", "r")
                    if f then local t = f:read("*l")
                    f:close()
                    if t then ms._githubToken = t
                    return t end end
                    return ""
                end)(),
                qrOptions               = ms._qrOptions or {
                    macros   = true,
                    theme    = true,
                    settings = true,
                    ui       = true,
                },
                consoleOpen             = ms.dev._consoleOpen or false,
                watcherOpen             = ms.dev._watcherOpen or false,
                keysOpen                = ms.dev._keysOpen or false,
                windowOpen              = ms.dev._windowOpen or false,
                theme                   = themeOut,
                themeFonts              = themeFonts,
                themeSet                = themeSet,
                themeFontValue          = themeFile.font or ms._theme.font or "",
                msVersion               = (function()
                    local p = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                    local f = io.open(p, "r")
                    if not f then return nil end
                    local ok, m = pcall(hs.json.decode, f:read("*all"))
                    f:close()
                    local base = (ok and m and m.version) or nil
                    if not base then return nil end

                    if ms._updateChannel == "testing" then
                        local maj, min, pat = base:match("^(%d+)%.(%d+)%.(%d+)$")
                        if maj and min and pat then
                            local nextVer = maj .. "." .. min .. "." .. tostring(tonumber(pat) + 1)
                            local buildPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_build_num"
                            local bf = io.open(buildPath, "r")
                            local buildNum = 0
                            if bf then buildNum = tonumber(bf:read("*all")) or 0
                            bf:close() end
                            return nextVer .. "-pre." .. tostring(buildNum)
                        end
                    end
                    return base
                end)(),
            }
        end
    -- END Panel State & Builders --

    -- UI State Cache --
        local _uiStateDirty = true
        local _uiStateJSON  = nil
        local _shellStale   = true

        local function _rebuildUICache()
            local ok, json = pcall(hs.json.encode, _buildUIState())
            if ok and type(json) == "string" then
                _uiStateJSON  = "receiveState(" .. json .. ");"
                _uiStateDirty = false
            else
                print("[MsUI] _buildUIState JSON encode FAILED (Settings/Tools/Appearance/"
                    .. "Profiles will not hydrate): " .. tostring(json))
            end
        end

        ms.ui.markDirty = function()
            _uiStateDirty = true
            _shellStale   = true
        end

        ms.ui.needsRefresh = function() return _shellStale end

        ms.ui.refresh = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
            local stateArg = _uiStateJSON and _uiStateJSON:match("^receiveState%((.*)%);$")
            if stateArg and stateArg ~= "null"
                and ms.shell and ms.shell.isReady and ms.shell.isReady() then
                pcall(function()
                    ms.shell.eval("shellReceive('settings', 'state', " .. stateArg .. ")")
                end)
                _shellStale = false
            end
            pcall(function() ms.ui.pushBindList() end)
        end

        ms.ui.pushBindList = function()
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then return end
            local ok, json = pcall(hs.json.encode, _buildMacroList())
            if not ok or not json then return end
            pcall(function()
                ms.shell.eval("shellReceive('macros', 'bindList', " .. json .. ")")
            end)
        end

        ms.ui.prebuild = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
        end

        ms.ui._precacheHTML = function()
        end

        local function _emptyToNil(s) if s == nil or s == "" then return nil end
        return s end

        local function _restoreAfterCapture()
            ms.ui._open = true
            local target = hs.application.get(ms._targetApp)
            if target then
                hs.timer.doAfter(0.05, function()
                    local ok, win = pcall(function() return target:mainWindow() end)
                    if ok and win then pcall(function() win:focus() end) end
                    pcall(function() target:activate() end)
                end)
            end
        end

        local function _rebindModal(opts)
            local label   = opts.label or "bind"
            local current = opts.current or "unset"

            ms.ui.ensureVisible()

            local phase = "capture"
            local capturedParsed, capturedStr
            local capture, cancelTimer
            local settled   = false
            local heldCodes = {}
            local heldCount = 0
            local comboKeys = {}
            local comboSeen = {}
            local comboMods = {}
            local started   = false
            local modOnly   = false

            local INSTRUCTIONS =
                "Press a key, or hold a combo. Modifiers on their own\n"
                .. "(Option, Option+Shift), mouse buttons, scroll, and\n"
                .. "controller buttons work too, hold several pad\n"
                .. "buttons at once for a controller combo.\n"
                .. "Release to set  -  Escape to cancel."

            local function captureMsg()
                return "Current:  " .. current .. "\n\n" .. INSTRUCTIONS
            end

            local function stopCapture()
                if capture then capture:stop()
                capture = nil end
                if cancelTimer then cancelTimer:stop()
                cancelTimer = nil end
                if ms._gamepadCallbacks then ms._gamepadCallbacks._rebind = nil end
            end

            local function modList()
                local mods = {}
                for _, m in ipairs({
                    "cmd",
                    "alt",
                    "ctrl",
                    "shift",
                }) do
                    if comboMods[m] then mods[#mods + 1] = m end
                end
                return mods
            end

            local startCapture

            local function onClosed(r)
                local confirmed = r and r.confirmed
                if phase == "conflict" and confirmed then
                    startCapture()
                    return
                end
                ms._inputOpen = false
                if phase == "confirm" and confirmed then
                    opts.apply(capturedParsed, capturedStr)
                    _restoreAfterCapture()
                    ms.ui.refresh()
                else
                    if opts.onCancel then opts.onCancel() end
                end
            end

            local function toConfirm(parsed)
                if settled then return end
                settled = true
                stopCapture()
                local bindStr = _bindDisplay(parsed)
                capturedParsed, capturedStr = parsed, bindStr

                local err = opts.validate and opts.validate(parsed, bindStr) or nil
                if err then
                    phase = "conflict"
                    ms.playSlot("alert")
                    ms.ui.modalUpdate({
                        title       = "Bind Conflict",
                        msg         = err .. "\n\nTry a different input?",
                        keys        = _bindTokens(parsed),
                        confirm     = "Try Again",
                        cancel      = "Cancel",
                        showConfirm = true,
                        showCancel  = true,
                    })
                    return
                end

                phase = "confirm"
                ms.playSlot("interact")
                ms.ui.modalUpdate({
                    title       = "Confirm Rebind",
                    msg         = "Set \"" .. label .. "\" to:",
                    keys        = _bindTokens(parsed),
                    confirm     = "Confirm",
                    cancel      = "Cancel",
                    showConfirm = true,
                    showCancel  = true,
                })
            end

            startCapture = function()
                phase     = "capture"
                settled   = false
                started   = false
                heldCodes = {}
                heldCount = 0
                comboKeys = {}
                comboSeen = {}
                comboMods = {}
                modOnly   = false
                ms._inputOpen = true

                ms.ui.modal({
                    title   = "Rebind, " .. label,
                    msg     = captureMsg(),
                    confirm = "Set",
                    cancel  = "Cancel",
                }, onClosed)
                ms.ui.modalUpdate({
                    showConfirm = false,
                    showCancel = false,
                    keys = {},
                })

                local function livePreview()
                    if #comboKeys == 0 then return end
                    local preview
                    if #comboKeys > 1 then
                        preview = {
                            type = "combo",
                            mods = modList(),
                            keys = comboKeys,
                        }
                    else
                        preview = {
                            type = "key",
                            mods = modList(),
                            key  = comboKeys[1],
                        }
                    end
                    ms.ui.modalUpdate({ keys = _bindTokens(preview) })
                end

                local function finalizeKeys()
                    if settled or #comboKeys == 0 then return end
                    local mods = modList()
                    if #comboKeys == 1 then
                        toConfirm({
                            type = "key",
                            mods = mods,
                            key  = comboKeys[1],
                        })
                    else
                        toConfirm({
                            type = "combo",
                            mods = mods,
                            keys = comboKeys,
                        })
                    end
                end

                capture = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                    hs.eventtap.event.types.flagsChanged,
                    hs.eventtap.event.types.leftMouseDown,
                    hs.eventtap.event.types.rightMouseDown,
                    hs.eventtap.event.types.otherMouseDown,
                    hs.eventtap.event.types.scrollWheel,
                }, function(event)
                    local t = event:getType()

                    if t == hs.eventtap.event.types.flagsChanged then
                        if settled then return true end
                        if heldCount > 0 or #comboKeys > 0 then return true end
                        local f = event:getFlags()
                        local any = false
                        if f.cmd   then comboMods.cmd   = true; any = true end
                        if f.alt   then comboMods.alt   = true; any = true end
                        if f.ctrl  then comboMods.ctrl  = true; any = true end
                        if f.shift then comboMods.shift = true; any = true end
                        if any then
                            modOnly = true
                            started = true
                            ms.ui.modalUpdate({ keys = _bindTokens({ type = "mods", mods = modList() }) })
                        elseif modOnly then
                            local mods = modList()
                            if #mods > 0 then toConfirm({ type = "mods", mods = mods }) end
                        end
                        return true
                    end

                    if t == hs.eventtap.event.types.keyDown then
                        local keyCode = event:getKeyCode()
                        local flags   = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                            settled = true
                            stopCapture()
                            ms.ui.modalClose(false)
                            return true
                        end
                        local keyStr = hs.keycodes.map[keyCode]
                        if not keyStr then return true end
                        if not heldCodes[keyCode] then
                            heldCodes[keyCode] = true
                            heldCount = heldCount + 1
                            if not comboSeen[keyStr] then
                                comboSeen[keyStr] = true
                                comboKeys[#comboKeys + 1] = keyStr
                            end
                        end
                        if flags.cmd   then comboMods.cmd   = true end
                        if flags.alt   then comboMods.alt   = true end
                        if flags.ctrl  then comboMods.ctrl  = true end
                        if flags.shift then comboMods.shift = true end
                        started = true
                        livePreview()
                        return true

                    elseif t == hs.eventtap.event.types.keyUp then
                        local keyCode = event:getKeyCode()
                        if heldCodes[keyCode] then
                            heldCodes[keyCode] = nil
                            heldCount = heldCount - 1
                            if heldCount <= 0 and started then finalizeKeys() end
                        end
                        return true

                    elseif t == hs.eventtap.event.types.scrollWheel then
                        if settled or started then return true end
                        local dy  = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                        local dir = dy > 0 and "up" or "down"
                        toConfirm({
                            type = "scroll",
                            direction = dir,
                        })
                        return true

                    else
                        if settled or started then return true end
                        local btn
                        if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                        elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                        else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                        toConfirm({
                            type = "mouse",
                            button = btn,
                        })
                        return true
                    end
                end)

                if opts.gamepad and ms.gamepadEnabled then
                    if not ms._gamepadTask then ms.gamepadStart() end
                    local gpHeldCount = 0
                    local gpOrder, gpSeen = {}, {}
                    ms._gamepadCallbacks._rebind = function(btn, phase)
                        if settled or started then return end
                        if phase == "press" then
                            gpHeldCount = gpHeldCount + 1
                            if not gpSeen[btn] then
                                gpSeen[btn] = true
                                gpOrder[#gpOrder + 1] = btn
                            end
                            local disp = (#gpOrder > 1)
                                and { type = "gamepad", buttons = gpOrder }
                                or  { type = "gamepad", button  = gpOrder[1] }
                            ms.ui.modalUpdate({ keys = _bindTokens(disp) })
                        elseif phase == "release" then
                            gpHeldCount = gpHeldCount - 1
                            if gpHeldCount <= 0 and #gpOrder > 0 then
                                if #gpOrder > 1 then
                                    toConfirm({
                                        type = "gamepad",
                                        buttons = ms.gpButtons({ buttons = gpOrder }),
                                    })
                                else
                                    toConfirm({ type = "gamepad", button = gpOrder[1] })
                                end
                            end
                        end
                    end
                end

                capture:start()
                cancelTimer = hs.timer.doAfter(15, function()
                    if settled then return end
                    settled = true
                    stopCapture()
                    ms.ui.modalClose(false)
                end)
            end

            startCapture()
        end

        local _editorPrefFile = os.getenv("HOME") .. "/.hammerspoon/data/.ms_editor"
        local function _savedEditor()
            local f = io.open(_editorPrefFile, "r")
            if not f then return nil end
            local p = f:read("*l")
            f:close()
            if p and p ~= "" and hs.fs.attributes(p) then return p end
            return nil
        end
        local function _editorName(app)
            return app and app:match("([^/]+)%.app$") or nil
        end
        local function _pickEditor(after)
            ms.ui.hide()
            hs.focus()
            local chosen = hs.dialog.chooseFileOrFolder(
                "Choose your text editor", "/Applications",
                true, false, false, { "app" }
            )
            ms.ui.show()
            local app
            for _, v in pairs(chosen or {}) do
                if type(v) == "string" then app = v
                break end
            end
            if not app then return end
            local f = io.open(_editorPrefFile, "w")
            if f then f:write(app)
            f:close() end
            if after then after(app) end
        end

        local ctx = {
            MsUI = MsUI,
            sq = sq,
            _bindDisplay = _bindDisplay,
            _emptyToNil = _emptyToNil,
            _restoreAfterCapture = _restoreAfterCapture,
            _rebindModal = _rebindModal,
            _savedEditor = _savedEditor,
            _editorName = _editorName,
            _pickEditor = _pickEditor,
        }

        ms.ui._actions = {}

        for _, name in ipairs({
            "actions_library",
            "actions_sound",
            "actions_shell",
            "actions_backups",
        }) do
            package.loaded["lib.ui." .. name] = nil

            for key, handler in pairs(require("lib.ui." .. name)(ms, ctx)) do
                ms.ui._actions[key] = handler
            end
        end

        do
            local _backing = ms.ui._actions
            ms.ui._actions = setmetatable({}, {
                __index    = _backing,
                __newindex = function(_, k)
                    error("ms.ui._actions is read-only (attempted write to '" .. tostring(k) .. "')", 2)
                end,
                __len      = function() return #_backing end,
            })
        end
        if ms.bus then
            local function _routeAction(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if not action then return end
                local handler = ms.ui._actions[action]
                if handler then
                    local ok, err = pcall(handler, body)
                    if not ok then print("[MsUI] handler error: " .. tostring(err)) end
                end
            end

            ms.bus.on("ui:settings:*", _routeAction)
            ms.bus.on("ui:macros:*", _routeAction)
            ms.bus.on("ui:tools:*",  _routeAction)
            ms.bus.on("ui:plugins:*", _routeAction)
            ms.bus.on("ui:browse:*", _routeAction)
            ms.bus.on("ui:library:*", _routeAction)
        end

        ms.ui.show = function()
            if ms.shell and ms.shell.show then ms.shell.show() end
        end

        ms.ui.ensureVisible = function()
            local visible = ms._shellState and ms._shellState.visible
            local ready   = ms.shell and ms.shell.isReady and ms.shell.isReady()
            if visible and ready then
                ms.ui._open = true
                return
            end
            ms.ui.show()
        end

        ms.ui.hide = function()
            ms.ui._open = false
            if ms.shell and ms.shell.hide then ms.shell.hide() end
        end

        ms.ui.toggle = function()
            if ms.shell and ms.shell.toggle then ms.shell.toggle() end
        end

        ms.ui.prewarm = function()
            if not (ms.shell and ms.shell.init) then return end

            pcall(function()
                if ms.shell.webview and ms.shell.webview() then return end
                ms.shell.init()
            end)
        end
    -- END UI State Cache --

    -- ms.ui.modal --
        ms.ui.modal = function(data, callback)
            if not callback then return end
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                pcall(callback, { confirmed = false })
                return
            end
            local ok, json = pcall(hs.json.encode, {
                title   = data.title   or "",
                msg     = data.msg     or "",
                confirm = data.confirm or "OK",
                cancel  = data.cancel  or "Cancel",
            })
            if not ok then pcall(callback, { confirmed = false })
            return end
            ms.ui._modalCallback = callback
            pcall(function()
                ms.shell.eval("openLuaModal(" .. json .. ")")
            end)
        end

        ms.ui.modalUpdate = function(data)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                return
            end
            local ok, json = pcall(hs.json.encode, data or {})
            if not ok then return end
            pcall(function()
                ms.shell.eval("updateLuaModal(" .. json .. ")")
            end)
        end

        ms.ui.modalClose = function(confirmed)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                return
            end
            pcall(function()
                ms.shell.eval("closeModal(" .. (confirmed and "true" or "false") .. ")")
            end)
        end
    -- END ms.ui.modal --

    -- ms.ui.prompt --
        ms.ui.prompt = function(data, callback)
            if not callback then return end
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                pcall(callback, {
                    confirmed = false,
                    value = "",
                })
                return
            end
            local ok, json = pcall(hs.json.encode, {
                title        = data.title   or "",
                msg          = data.msg     or "",
                confirm      = data.confirm or "OK",
                cancel       = data.cancel  or "Cancel",
                hasInput     = true,
                inputDefault = data.default or "",
            })
            if not ok then pcall(callback, {
                confirmed = false,
                value = "",
            })
            return end
            ms.ui._modalCallback = callback
            pcall(function()
                ms.shell.eval("openLuaModal(" .. json .. ")")
            end)
        end
    -- END ms.ui.prompt --

    end
-- END Webview Panel --

return MsUI

end

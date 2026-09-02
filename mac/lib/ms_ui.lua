return function(ms)
-- MsUI --
    local MsUI = {}

    MsUI.name    = "MsUI"
    MsUI.version = "1.0"

    local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

    local profilesPath = os.getenv("HOME") .. "/.hammerspoon/profiles/"
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

        local function _bindDisplay(c)
            if not c then return nil end
            local parts = _modParts(c.mods)
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
                        bind      = _bindDisplay(eff),
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
                            bind     = _bindDisplay(eff),
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
                table.insert(userSettings, _serItem(def))
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
                })
            end

            local themeFonts = {}
            for _, fam in ipairs({
                "Almendra",
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
                    or (meta.name and ms.sanitizeName(meta.name)) or "",
                profiles                = ms.getProfiles(),
                integrityStatus         = status,
                integrityHash           = curHash,
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
                updateChannel           = ms._updateChannel or "stable",
                updateAlertsDisabled    = ms._updateAlertsDisabled or false,
                testingSource           = ms._testingSource or "release",
                uiZoom                  = ms._uiZoom or 1.0,
                octaneMode              = ms._octaneMode or false,
                octaneMuteSounds        = ms._octaneMuteSounds or false,
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

        ms.ui.markDirty = function() _uiStateDirty = true end

        ms.ui.refresh = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
            local stateArg = _uiStateJSON and _uiStateJSON:match("^receiveState%((.*)%);$")
            if stateArg and stateArg ~= "null"
                and ms.shell and ms.shell.isReady and ms.shell.isReady() then
                pcall(function()
                    ms.shell.eval("shellReceive('settings', 'state', " .. stateArg .. ")")
                end)
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
                .. "controller buttons work too — hold several pad\n"
                .. "buttons at once for a controller combo.\n"
                .. "Release to set  ·  Escape to cancel."

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
                                    toConfirm({ type = "gamepad", buttons = gpOrder })
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

        ms.ui._actions = {
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
                    local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                    local af = io.open(macrosPath, "r")
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
                            pcall(ms.plugins.unload, dir, { quiet = true })
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
                    ms._userSettingVals  = {}

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
                    ms._macroMetaFromHand = ms.macroMeta ~= nil
                    if ms.compiler and ms.compiler.paths
                        and hs.fs.attributes(ms.compiler.paths.json) then
                        local rebOk, rebErr = pcall(ms.compiler.rebuild)
                        if not rebOk then
                            print("ms.compiler.rebuild (reload): " .. tostring(rebErr))
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
                    ms.windowsMode = (data.value == true)
                    ms.saveSettings()
                    ms.ui.refresh()
                end,

                setGamepadEnabled = function(data)
                    ms.gamepadEnabled = (data.value == true)
                    if ms.gamepadEnabled then
                        if ms.gamepadStart then ms.gamepadStart() end
                    else
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

                setSoundPreset = function(data)
                    if not data.assigns then return end
                    ms.soundAssign = ms.soundAssign or {}
                    local loadSlots = {
                        "themeLoaded",
                        "load",
                        "launch",
                    }
                    for _, sid in ipairs(loadSlots) do
                        ms.soundAssign[sid] = nil
                    end
                    for slotId, soundName in pairs(data.assigns) do
                        ms.soundAssign[slotId] = soundName
                    end
                    ms._soundPreset = data.preset or "default"
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                clearSoundPreset = function(data)
                    if not data.slots then return end
                    ms.soundAssign = ms.soundAssign or {}
                    for _, slotId in ipairs(data.slots) do
                        ms.soundAssign[slotId] = nil
                    end
                    ms._soundPreset = "custom"
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,
            -- END --

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

            -- Editors & Windows --
                openWindowMonitor = function() if ms.dev and ms.dev.window then ms.dev.window.toggle() end end,

                openConsole = function() hs.openConsole() end,

                editMacros = function()
                    local path = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"

                    local function openIn(app)
                        if app then
                            os.execute("open -a '" .. app .. "' '" .. path .. "'")
                        else
                            os.execute("open -t '" .. path .. "'")
                        end
                    end

                    local editor     = _savedEditor()
                    local editorName  = _editorName(editor)

                    ms.playSlot("alert")
                    ms.ui.modal({
                        title   = "Edit handwritten macros",
                        msg     = "Opens ms_macros.lua, the handwritten macro suite. "
                            .. "Visual builder macros are stored separately and are "
                            .. "not edited here."
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

                editTheme = function()
                    os.execute("open '" .. os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json'")
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
                        ms.windowsMode = (def.windowsMode == true)
                        ms.saveSettings()
                    elseif key == "socdMode" then
                        ms.socdMode = def.socdMode or "lastWins"
                        ms.saveSettings()
                    elseif key == "gamepadEnabled" then
                        ms.gamepadEnabled = (def.gamepadEnabled == true)
                        if not ms.gamepadEnabled and ms.gamepadStop then ms.gamepadStop() end
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

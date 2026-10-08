-- Startup loading screen
return function(ms)

    local _lWebView, _lFadingOut
    local _lMsgBuffer = {}
    local _lContentShown = false
    local _lContentQueue = {}
    local _lHoldUntil = 0
    local _lFadePending = false
    local CONTENT_HOLD = 1.5

    ms.loading = {}

    -- Update --
        ms.loading.update = function(pct, msg)
            if not _lWebView then
                _lMsgBuffer[#_lMsgBuffer + 1] = {
                    pct = pct,
                    msg = msg,
                }
                return
            end
            local encoded = msg and ('"' .. msg:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"') or "null"
            _lWebView:evaluateJavaScript(string.format("setProgress(%d, %s)", pct, encoded))
        end
    -- END Update --

    -- State --
        ms.loading.isFadingOut = function() return _lFadingOut == true end

        ms.loading.isVisible = function() return _lWebView ~= nil end

        ms.loading.holdFor = function(seconds)
            local untilAt = hs.timer.secondsSinceEpoch() + (tonumber(seconds) or 0)
            if untilAt > _lHoldUntil then _lHoldUntil = untilAt end
        end

        ms.loading.holdForSound = function(snd)
            if type(snd) ~= "userdata" then return end
            local ok, dur = pcall(function() return snd:duration() end)
            if ok and type(dur) == "number" then ms.loading.holdFor(dur) end
        end

        ms.loading.onContent = function(cb)
            if _lContentShown or not _lWebView then
                pcall(cb)
                return
            end
            _lContentQueue[#_lContentQueue + 1] = cb
        end
    -- END State --

    -- Eval --
        ms.loading.eval = function(code)
            if _lWebView then pcall(function() _lWebView:evaluateJavaScript(code) end) end
        end
    -- END Eval --

    -- Meta Push --
        ms.loading.pushMeta = function()
            if _lWebView and ms.macroMeta then
                if ms.macroMeta.name then
                    pcall(function() _lWebView:evaluateJavaScript("setProfileName('" .. ms.macroMeta.name:gsub("'", "\\'") .. "')") end)
                end
                if ms.macroMeta.author and ms.macroMeta.author ~= "" then
                    pcall(function() _lWebView:evaluateJavaScript("setCreator('" .. ms.macroMeta.author:gsub("'", "\\'") .. "')") end)
                end
            end
        end
    -- END Meta Push --

    -- Theme --
        ms.loading.applyTheme = function()
            if _lWebView then
                local themeJson = hs.json.encode(ms._theme or {})
                _lWebView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
            end
        end
    -- END Theme --

    -- Create --
        ms.loading.create = function()
            local _startBootChoreography

            _G._bootChoreographyStarted = false

            local sf  = hs.screen.mainScreen():frame()
            local lw, lh = 360, 140
            local lx  = sf.x + math.floor((sf.w - lw) / 2)
            local ly  = sf.y + math.floor((sf.h - lh) / 2)

            local _ucLoad = hs.webview.usercontent.new("loading")
            _ucLoad:setCallback(function(message)
                local ok, data = pcall(hs.json.decode, message.body)
                if not ok or type(data) ~= "table" then return end
                if data.action == "ready" then
                    if _G._bootChoreographyStarted then
                        if _lWebView then
                            pcall(function() _lWebView:evaluateJavaScript("showBrand()") end)
                        end
                        ms.loading.pushMeta()
                    else
                        _startBootChoreography()
                    end
                end
            end)

            local htmlPath = hs.configdir .. "/ui/ms_loading.html"
            local baseURL  = "file://" .. hs.configdir .. "/ui/"

            _lWebView = hs.webview.new({
                x = lx,
                y = ly,
                w = lw,
                h = lh,
            }, {}, _ucLoad)
            pcall(function() _lWebView:windowStyle(0) end)
            pcall(function() _lWebView:transparent(true) end)
            pcall(function() _lWebView:level(hs.canvas.windowLevels.popUpMenu or 25) end)
            pcall(function() _lWebView:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
            pcall(function() _lWebView:allowTextEntry(false) end)
            pcall(function() _lWebView:shadow(false) end)
            _lWebView:alpha(0)

            local f = io.open(htmlPath, "r")
            if f then
                local html = f:read("*all")
                f:close()
                _lWebView:html(html, baseURL)
            end

            local function js(code)
                if _lWebView then pcall(function() _lWebView:evaluateJavaScript(code) end) end
            end

            _startBootChoreography = function()
                if _G._bootChoreographyStarted then return end
                _G._bootChoreographyStarted = true

                _G._loadTimers = {}

                pcall(function() ms.loadTheme() end)

                if ms.macroMeta and ms.macroMeta.name then
                    js("setProfileName('" .. ms.macroMeta.name:gsub("'", "\\'") .. "')")
                end
                if ms.macroMeta and ms.macroMeta.author and ms.macroMeta.author ~= "" then
                    js("setCreator('" .. ms.macroMeta.author:gsub("'", "\\'") .. "')")
                end

                for _, entry in ipairs(_lMsgBuffer) do
                    local encoded = entry.msg and ('"' .. entry.msg:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"') or "null"
                    js(string.format("setProgress(%d, %s)", entry.pct, encoded))
                end
                _lMsgBuffer = {}

                ms.safeShow(_lWebView)
                local step, steps = 0, 25
                _G._loadTimers.fadeIn = hs.timer.doEvery(0.15 / steps, function()
                    step = step + 1
                    if _lWebView then _lWebView:alpha(step / steps) end
                    if step >= steps then
                        if _G._loadTimers.fadeIn then
                            _G._loadTimers.fadeIn:stop()
                            _G._loadTimers.fadeIn = nil
                        end
                    end
                end)

                local okBoot, bootSnd = pcall(function() return ms.sound(SoundDefaultsDir .. "d_Boot.wav") end)
                if okBoot then ms.loading.holdForSound(bootSnd) end

                js("showBrand()")
                _G._loadTimers.shift = hs.timer.doAfter(2.0, function() js("shiftBrand()") end)
                _G._loadTimers.content = hs.timer.doAfter(2.9, function()
                    js("showDivider()")
                    js("showContent()")
                    _lContentShown = true
                    ms.loading.holdFor(CONTENT_HOLD)
                    local queue = _lContentQueue
                    _lContentQueue = {}
                    for _, cb in ipairs(queue) do pcall(cb) end
                end)

                if type(ms._onBootAnchor) == "function" then
                    pcall(ms._onBootAnchor)
                end
            end

            hs.timer.doAfter(0.9, function()
                if not _G._bootChoreographyStarted then
                    _startBootChoreography()
                end
            end)
        end
    -- END Create --

    -- Fade Out --
        ms.loading.fadeOut = function(onDone)
            if not _lWebView or _lFadingOut or _lFadePending then return end
            if not _lContentShown then
                _lFadePending = true
                _lContentQueue[#_lContentQueue + 1] = function()
                    _lFadePending = false
                    ms.loading.fadeOut(onDone)
                end
                return
            end
            local wait = _lHoldUntil - hs.timer.secondsSinceEpoch()
            if wait > 0 then
                _lFadePending = true
                _G._loadTimers.hold = hs.timer.doAfter(wait, function()
                    _lFadePending = false
                    ms.loading.fadeOut(onDone)
                end)
                return
            end
            _lFadingOut = true
            local fadeIn = _G._loadTimers and _G._loadTimers.fadeIn
            if fadeIn then
                fadeIn:stop()
                _G._loadTimers.fadeIn = nil
            end
            local startAlpha = 1
            local okAlpha, curAlpha = pcall(function() return _lWebView:alpha() end)
            if okAlpha and type(curAlpha) == "number" then startAlpha = curAlpha end
            _G._loadTimers = _G._loadTimers or {}
            local step, steps = 0, 25
            _G._loadTimers.fadeOut = hs.timer.doEvery((ms._theme.fadeMs or 250) / 1000 / steps, function()
                step = step + 1
                if _lWebView then _lWebView:alpha(startAlpha * (1 - (step / steps))) end
                if step >= steps then
                    if _G._loadTimers.fadeOut then
                        _G._loadTimers.fadeOut:stop()
                        _G._loadTimers.fadeOut = nil
                    end
                    if _lWebView then
                        _lWebView:delete()
                        _lWebView = nil
                    end
                    _G._loadTimers.announce = hs.timer.doAfter(0.1, onDone)
                end
            end)
        end
    -- END Fade Out --

end

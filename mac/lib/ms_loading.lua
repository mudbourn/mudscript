-- ms_loading (Startup Loading Screen) --
return function(ms)

    local _lWebView, _lFadingOut
    local _lMsgBuffer = {}

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

            -- Reset the ready-handshake guard so THIS create() owns a fresh boot
            -- choreography. The flag lives on _G and survives a config re-entry
            -- (see the __ms_core_running guard in ms_core), so without this reset
            -- a stale `true` from a prior boot makes the fallback below skip the
            -- fade-in and the loading screen never appears. This reset lived in
            -- ms_core pre-extraction and was dropped when the module was split
            -- out — restoring it here, where create() owns the choreography.
            _G._bootChoreographyStarted = false

            local sf  = hs.screen.mainScreen():frame()
            local lw, lh = 360, 140
            local lx  = sf.x + math.floor((sf.w - lw) / 2)
            local ly  = sf.y + math.floor((sf.h - lh) / 2)

            -- Handler name MUST match the one the page posts to
            -- (window.webkit.messageHandlers.loading in ms_loading.html); a
            -- mismatch silently drops the ready handshake, leaving the reveal to
            -- depend entirely on the 0.5s fallback timer below.
            local _ucLoad = hs.webview.usercontent.new("loading")
            _ucLoad:setCallback(function(message)
                local ok, data = pcall(hs.json.decode, message.body)
                if not ok or type(data) ~= "table" then return end
                if data.action == "ready" then
                    if _G._bootChoreographyStarted then
                        -- Re-assert the brand now that the page has handshaked.
                        if _lWebView then
                            pcall(function() _lWebView:evaluateJavaScript("showBrand()") end)
                        end
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
                -- Deliberately do NOT push the theme here: the screen comes up in
                -- the neutral default look and snaps to the user's theme at the
                -- animGate "Applying theme…" step, in sync with the themeLoaded
                -- sound (ms_core ~6556). The compat label themes with everything
                -- else at that moment via CSS vars (its font is var(--font)).

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

                pcall(function() ms.sound(SoundDefaultsDir .. "d_Boot.wav") end)

                js("showBrand()")
                _G._loadTimers[2] = hs.timer.doAfter(0.2, function() js("showBrand()") end)

                _G._loadTimers[3] = hs.timer.doAfter(1.7, function() js("shiftBrand()") end)

                _G._loadTimers[4] = hs.timer.doAfter(2.5, function()
                    js("showDivider()")
                    js("showContent()")
                end)
            end

            hs.timer.doAfter(0.5, function()
                if not _G._bootChoreographyStarted then
                    _startBootChoreography()
                end
            end)
        end
    -- END Create --

    -- Fade Out --
        ms.loading.fadeOut = function(onDone)
            if not _lWebView or _lFadingOut then return end
            _lFadingOut = true
            local step, steps = 0, 25
            _G._loadTimers.fadeOut = hs.timer.doEvery((ms._theme.fadeMs or 250) / 1000 / steps, function()
                step = step + 1
                if _lWebView then _lWebView:alpha(1 - (step / steps)) end
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
-- END ms_loading --

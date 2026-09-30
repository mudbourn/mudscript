return function(ms, ctx)
    -- On-screen keyboard window --
        local _oskView = nil

        local function _oskTheme()
            if _oskView and ms._theme then
                pcall(function()
                    _oskView:evaluateJavaScript(
                        "if(window.OSK)OSK.applyTheme(" .. hs.json.encode(ms.theme.effective()) .. ")")
                end)
            end
        end

        ms.shell._buildOsk = function()
            if _oskView then return end
            require("hs.webview")

            local sf = hs.screen.mainScreen():frame()
            local w, h = 620, 320
            _oskView = hs.webview.new({
                x = sf.x + math.floor((sf.w - w) / 2),
                y = sf.y + sf.h - h - 40,
                w = w,
                h = h,
            })
            pcall(function()
                local M = hs.webview.windowMasks or {}
                _oskView:windowStyle((M.borderless or 0) + (M.nonactivating or 128))
            end)
            pcall(function() _oskView:transparent(true) end)
            pcall(function() _oskView:shadow(false) end)
            pcall(function() _oskView:level((hs.canvas.windowLevels.popUpMenu or 101) + 3) end)
            _oskView:alpha(0)

            local htmlPath = hs.configdir .. "/ui/ms_osk.html"
            local baseURL  = "file://" .. hs.configdir .. "/ui/"
            local f = io.open(htmlPath, "r")
            if f then
                local html = f:read("*all")
                f:close()
                local tf = io.open(hs.configdir .. "/ui/modules/ui-tokens.js", "r")
                if tf then
                    local tokens = tf:read("*all")
                    tf:close()
                    html = html:gsub('<script src="%./modules/ui%-tokens%.js"></script>', function()
                        return "<script>" .. tokens .. "</script>"
                    end, 1)
                end
                _oskView:html(html, baseURL)
            end

            hs.timer.doAfter(0.1, _oskTheme)
        end

        ms.shell.osk = {}

        ms.shell.osk.render = function(payload)
            if not _oskView then return end
            pcall(function()
                _oskView:evaluateJavaScript(
                    "if(window.OSK)OSK.render(" .. hs.json.encode(payload) .. ")")
            end)
        end

        ms.shell.osk.show = function(senderView, payload)
            ms.shell._buildOsk()
            if not _oskView then return end

            local f = _oskView:frame()
            local w, h = f.w, f.h
            local sf = hs.screen.mainScreen():frame()
            local x = sf.x + math.floor((sf.w - w) / 2)
            local y = sf.y + sf.h - h - 40
            local ok, tf = pcall(function() return senderView and senderView:frame() end)
            if ok and tf then
                x = tf.x + math.floor((tf.w - w) / 2)
                y = tf.y + tf.h - h + 20
            end
            x = math.max(sf.x, math.min(sf.x + sf.w - w, x))
            y = math.max(sf.y, math.min(sf.y + sf.h - h, y))
            pcall(function()
                _oskView:frame({
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                })
            end)

            _oskTheme()
            pcall(function()
                _oskView:evaluateJavaScript(
                    "if(window.OSK)OSK.show(" .. hs.json.encode(payload) .. ")")
            end)
            if ms.safeShow then ms.safeShow(_oskView) else pcall(function() _oskView:show() end) end
            _oskView:alpha(1)
            pcall(function() _oskView:bringToFront(true) end)
        end

        ms.shell.osk.hide = function()
            if not _oskView then return end
            pcall(function() _oskView:evaluateJavaScript("if(window.OSK)OSK.hide()") end)
            _oskView:alpha(0)
            pcall(function() _oskView:hide() end)
        end

        ms.shell.osk.move = function(dx, dy)
            if not _oskView then return end
            pcall(function()
                local f = _oskView:frame()
                local sf = hs.screen.mainScreen():frame()
                local nx = math.max(sf.x, math.min(sf.x + sf.w - f.w, f.x + (dx or 0)))
                local ny = math.max(sf.y, math.min(sf.y + sf.h - f.h, f.y + (dy or 0)))
                _oskView:frame({
                    x = nx,
                    y = ny,
                    w = f.w,
                    h = f.h,
                })
            end)
        end

        ms.shell.osk._recv = function(body, senderView)
            if type(body) ~= "table" or not body.op then return end
            local op = body.op
            if op == "open" then ms.shell.osk.show(senderView, body)
            elseif op == "render" then ms.shell.osk.render(body)
            elseif op == "close" then ms.shell.osk.hide()
            elseif op == "move" then ms.shell.osk.move(body.dx, body.dy) end
        end

        ms.shell.osk._retheme = _oskTheme

        ms.shell.osk._destroy = function()
            if _oskView then
                pcall(function() _oskView:delete() end)
                _oskView = nil
            end
        end
    -- END --
end

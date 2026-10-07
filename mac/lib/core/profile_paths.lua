return function(ms)
    -- Profile Paths --
        local hsDir = os.getenv("HOME") .. "/.hammerspoon"
        local rootDir = hsDir .. "/profiles"
        local layoutPath = rootDir .. "/.layout"
        local activePath = rootDir .. "/.active"
        local legacyActivePath = hsDir .. "/data/library/.active_profile"

        local P = {}

        local _layout = nil
        local _active = nil
    -- END Profile Paths --

    -- File Map --
        P.FILES = {
            macros = "ms_macros.lua",
            settings = "data/ms_settings.json",
            defaults = "data/ms_settings_default.json",
            theme = "data/ms_theme.json",
            visualJson = "data/ms_macros_visual.json",
            visualLua = "data/ms_macros_visual.lua",
            authored = "data/ms_authored.json",
            authoredMenus = "data/ms_authored_menus.json",
            helperVars = "data/ms_helpervars.json",
            meta = "profile.json",
        }

        P.CONTENT_FILES = {
            "ms_macros.lua",
            "data/ms_settings.json",
            "data/ms_settings_default.json",
            "data/ms_theme.json",
            "data/ms_macros_visual.json",
            "data/ms_macros_visual.lua",
            "data/ms_authored.json",
            "data/ms_authored_menus.json",
            "data/ms_helpervars.json",
        }

        P.SOUND_DIRS = {
            "sounds/active/",
            "sounds/macro/",
        }

        P.relFor = function(flat)
            if type(flat) ~= "string" then return nil end
            if flat == "ms_macros.lua" then return flat end
            if flat:find("^ms_") and (flat:find("%.json$") or flat == "ms_macros_visual.lua") then
                return "data/" .. flat
            end
            return flat
        end

        P.flatFor = function(rel)
            if type(rel) ~= "string" then return nil end
            return (rel:gsub("^data/", ""))
        end
    -- END File Map --

    -- Helpers --
        local function readText(path)
            local f = io.open(path, "rb")
            if not f then return nil end
            local body = f:read("*all")
            f:close()
            return body
        end

        local function writeText(path, body)
            local f = io.open(path, "wb")
            if not f then return false end
            f:write(body)
            f:close()
            return true
        end

        local function trimmed(s)
            if type(s) ~= "string" then return "" end
            return (s:gsub("^%s+", ""):gsub("%s+$", ""))
        end

        local function sq(s)
            return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
        end

        local function safeName(name)
            if type(name) ~= "string" then return nil end
            local clean = name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
            if clean == "" or clean == "." or clean == ".." or clean:sub(1, 1) == "." then
                return nil
            end
            return clean
        end

        local function isDir(path)
            local a = hs.fs.attributes(path)
            return a ~= nil and a.mode == "directory"
        end

        P.safeName = safeName
    -- END Helpers --

    -- Layout --
        P.refresh = function()
            _layout = nil
            _active = nil
        end

        P.layout = function()
            if _layout then return _layout end
            local n = tonumber(trimmed(readText(layoutPath)))
            _layout = (n and n >= 2) and 2 or 1
            return _layout
        end

        P.isV2 = function()
            return P.layout() >= 2
        end

        P.root = function()
            return rootDir
        end
    -- END Layout --

    -- Active Profile --
        P.list = function()
            local out = {}
            if not isDir(rootDir) then return out end
            for entry in hs.fs.dir(rootDir) do
                if entry:sub(1, 1) ~= "." and not entry:find("%.migrating$") then
                    local dir = rootDir .. "/" .. entry
                    if isDir(dir) then
                        local has = hs.fs.attributes(dir .. "/profile.json")
                            or hs.fs.attributes(dir .. "/ms_macros.lua")
                            or hs.fs.attributes(dir .. "/ms_settings.json")
                        if has then out[#out + 1] = entry end
                    end
                end
            end
            table.sort(out)
            return out
        end

        P.active = function()
            if _active then return _active end
            local name
            if P.isV2() then
                name = safeName(trimmed(readText(activePath)))
                if not name or not isDir(rootDir .. "/" .. name) then
                    name = P.list()[1] or "Default"
                end
            else
                name = trimmed(readText(legacyActivePath))
            end
            _active = name
            return name
        end

        P.dir = function(name)
            if not P.isV2() then
                if name == nil or name == "" or name == P.active() then return hsDir end
                local legacy = safeName(name)
                return legacy and (rootDir .. "/" .. legacy) or hsDir
            end
            local n = (name == nil or name == "") and P.active() or safeName(name)
            if not n then n = P.active() end
            return rootDir .. "/" .. n
        end

        P.path = function(rel, name)
            return P.dir(name) .. "/" .. tostring(rel or "")
        end

        P.file = function(key, name)
            local rel = P.FILES[key]
            if not rel then return nil end
            return P.path(rel, name)
        end

        P.exists = function(name)
            local n = safeName(name)
            return n ~= nil and isDir(rootDir .. "/" .. n)
        end

        P.ensure = function(name)
            local dir = P.dir(name)
            hs.execute("mkdir -p " .. sq(dir .. "/data") .. " " .. sq(dir .. "/sounds/active")
                .. " " .. sq(dir .. "/sounds/macro"))
            return dir
        end

        P.setActive = function(name)
            if not P.isV2() then
                if name and name ~= "" then
                    hs.execute("mkdir -p " .. sq(hsDir .. "/data/library"))
                    writeText(legacyActivePath, tostring(name) .. "\n")
                else
                    os.remove(legacyActivePath)
                end
                _active = nil
                return true
            end
            local n = safeName(name)
            if not n or not isDir(rootDir .. "/" .. n) then return false end
            local tmp = activePath .. ".tmp"
            if not writeText(tmp, n .. "\n") then return false end
            if not os.rename(tmp, activePath) then
                os.remove(tmp)
                return false
            end
            _active = n
            return true
        end
    -- END Active Profile --

    -- Metadata --
        P.readMeta = function(name)
            if not P.isV2() then return nil end
            local raw = readText(P.path("profile.json", name))
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then return tbl end
            return nil
        end

        P.writeMeta = function(name, tbl)
            if not P.isV2() or type(tbl) ~= "table" then return false end
            local dir = P.dir(name)
            if not isDir(dir) then return false end
            local ok, enc = pcall(hs.json.encode, tbl, true)
            if not ok or type(enc) ~= "string" then return false end
            local target = dir .. "/profile.json"
            local tmp = target .. ".tmp"
            if not writeText(tmp, enc .. "\n") then return false end
            if not os.rename(tmp, target) then
                os.remove(tmp)
                return false
            end
            return true
        end

        P.updateMeta = function(name, mutate)
            local resolved = (name == nil or name == "") and P.active() or name
            local meta = P.readMeta(resolved) or {
                formatVersion = 2,
                name = resolved,
                version = "1.0.0",
                origin = "local",
                created = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
            mutate(meta)
            meta.formatVersion = 2
            meta.updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
            return P.writeMeta(resolved, meta)
        end

        P.packs = function(name)
            local meta = P.readMeta(name)
            if meta and type(meta.packs) == "table" then return meta.packs end
            return {}
        end
    -- END Metadata --

    -- Repoint --
        P.repoint = function()
            P.refresh()
            SoundActiveDir = P.path("sounds/active/")
            SoundMacroDir = P.path("sounds/macro/")
            if ms.compiler and ms.compiler.repoint then
                pcall(ms.compiler.repoint)
            end
            if ms.vars and ms.vars.repoint then
                pcall(ms.vars.repoint)
            end
        end
    -- END Repoint --

    ms.profile = P
    return P
end

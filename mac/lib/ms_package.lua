-- ms_package (Typed Package Format: .mspkg) --
return function(ms)

    local _home     = os.getenv("HOME")
    local _hsDir    = _home .. "/.hammerspoon"
    local _dataDir  = _hsDir .. "/data"

    local MANIFEST_NAME  = "mspkg.json"
    local FORMAT_VERSION = 1

    ms.package = {}

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

        local function hashFile(path)
            local out = hs.execute("shasum -a 256 " .. sq(path) .. " 2>/dev/null")
            return (out and #out >= 64) and out:sub(1, 64):lower() or nil
        end

        local function fileExists(path)
            local a = hs.fs.attributes(path)
            return a ~= nil and a.mode == "file"
        end

        local function readFile(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local body = f:read("*all")
            f:close()
            return body
        end

        local function writeFile(path, body)
            local f = io.open(path, "w")
            if not f then return false end
            f:write(body)
            f:close()
            return true
        end

        local function safeRelPath(p)
            if type(p) ~= "string" or p == "" then return nil end
            if p:find("^/") or p:find("^~") then return nil end
            if p:find("%.%.") then return nil end
            if p:find("^%.") then return nil end
            return p
        end

        local function tempDir(tag)
            local base = os.getenv("TMPDIR") or "/tmp/"
            if not base:find("/$") then base = base .. "/" end
            local dir = base .. "mspkg-" .. tag .. "-" .. tostring(math.random(100000, 999999))
            hs.execute("mkdir -p " .. sq(dir))
            return dir
        end

        local function versionLess(a, b)
            local am = { tostring(a):match("^(%d+)%.(%d+)%.(%d+)$") }
            local bm = { tostring(b):match("^(%d+)%.(%d+)%.(%d+)$") }
            if #am < 3 or #bm < 3 then return false end
            for i = 1, 3 do
                local x, y = tonumber(am[i]), tonumber(bm[i])
                if x ~= y then return x < y end
            end
            return false
        end

        local function rmrf(dir)
            if dir and dir:find("mspkg%-") then hs.execute("/bin/rm -rf " .. sq(dir)) end
        end

        -- Where a packaged relative path lands in the live install. Shared by
        -- install and the library so an activated slice reaches the same dirs.
        local function destFor(clean)
            if clean == "ms_macros.lua" then
                return _hsDir .. "/ms_macros.lua"
            elseif clean == "ms_macros_visual.lua" then
                -- The compiled visual macros live in data/, not the top level.
                return _dataDir .. "/ms_macros_visual.lua"
            elseif clean:find("^ms_") and clean:find("%.json$") then
                return _dataDir .. "/" .. clean
            else
                return _hsDir .. "/" .. clean
            end
        end
    -- END Helpers --

    -- Type Specs --
        local TYPE_SPECS = {
            macro = {
                label    = "Macro Pack",
                paths    = {
                    "ms_macros.lua",
                    "ms_macros_visual.json",
                    "ms_macros_visual.lua",
                    "ms_authored.json",
                    "ms_helpervars.json",
                    "sounds/macro/",
                },
                required = {
                    "ms_macros.lua",
                    "ms_macros_visual.json",
                },
            },
            theme = {
                label    = "Theme",
                paths    = {
                    "ms_theme.json",
                    "ui/fonts/",
                    "sounds/active/",
                    "sounds/macro/",
                    "sound_assign.json",
                },
                required = { "ms_theme.json" },
            },
            sound = {
                label    = "Sound Pack",
                paths    = {
                    "sounds/active/",
                    "sounds/macro/",
                    "sound_assign.json",
                },
                required = { "sounds/active/" },
            },
            plugin = {
                label    = "Plugin",
                paths    = { "Spoons/" },
                required = { "Spoons/" },
            },
            profile = {
                label    = "Profile",
                paths    = {
                    "ms_macros.lua",
                    "ms_macros_visual.json",
                    "ms_macros_visual.lua",
                    "ms_authored.json",
                    "ms_helpervars.json",
                    "ms_settings.json",
                    "ms_settings_default.json",
                    "ms_theme.json",
                    "sounds/active/",
                    "sounds/macro/",
                    "ui/fonts/",
                    "sound_assign.json",
                },
                required = {},
            },
        }

        ms.package.TYPES = {
            "macro",
            "theme",
            "sound",
            "plugin",
            "profile",
        }

        ms.package.spec = function(kind) return TYPE_SPECS[kind] end

        local function manifestType(report)
            local m = type(report) == "table" and report.manifest
            if type(m) ~= "table" or m.legacy then return nil end
            return m.type
        end

        ms.package.protectionDisabled = function() return false end

        local _ledgerPath = _dataDir .. "/.ms_plugin_ledger.json"

        local function spoonTreeHash(absDir)
            local out, ok = hs.execute(
                "cd " .. sq(absDir) .. " && find . -type f ! -name '.DS_Store' " ..
                "! -name '._*' ! -path './__MACOSX/*' " ..
                "-exec shasum -a 256 {} + 2>/dev/null | LC_ALL=C sort -k2 | shasum -a 256"
            )
            if not ok or not out then return nil end
            return out:match("^(%x+)")
        end

        local function readLedger()
            local raw = readFile(_ledgerPath)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" and type(tbl.plugins) == "table" then
                return tbl
            end
            return nil
        end

        local function writeLedger(ledger)
            local ok, json = pcall(hs.json.encode, ledger)
            if not ok then return false end
            return writeFile(_ledgerPath, json .. "\n")
        end

        ms.package.recordPlugins = function(names, manifest, id)
            -- `id` is the registry entry id (see recordContent).
            id = (type(id) == "string" and id ~= "" and id)
                or (manifest and manifest.id) or nil
            local ledger = readLedger() or {
                version = 1,
                plugins = {},
            }

            for name in pairs(names) do
                local hash = spoonTreeHash(_hsDir .. "/Spoons/" .. name)
                if hash then
                    ledger.plugins[name] = {
                        hash        = hash,
                        id          = id,
                        name        = manifest and manifest.name or nil,
                        version     = manifest and manifest.version or nil,
                        author      = manifest and manifest.author or nil,
                        website     = manifest and manifest.website or nil,
                        description = manifest and manifest.description or nil,
                        installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }
                end
            end

            return writeLedger(ledger)
        end

        -- Installed-version record for non-plugin content, keyed by registry id.
        local _contentLedgerPath = _dataDir .. "/.ms_content_ledger.json"

        local function readContentLedger()
            local raw = readFile(_contentLedgerPath)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" and type(tbl.content) == "table" then
                return tbl
            end
            return nil
        end

        -- `id` is the registry entry id, which the manifest does not carry, so
        -- the caller passes it.
        ms.package.recordContent = function(manifest, id)
            id = (type(id) == "string" and id ~= "" and id)
                or (type(manifest) == "table" and manifest.id) or nil
            if type(manifest) ~= "table" or type(id) ~= "string" or id == "" then
                return false
            end
            local ledger = readContentLedger() or { version = 1, content = {} }
            ledger.content[id] = {
                id          = id,
                type        = manifest.type,
                name        = manifest.name,
                version     = manifest.version,
                author      = manifest.author,
                website     = manifest.website,
                description = manifest.description,
                installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
            local ok, json = pcall(hs.json.encode, ledger)
            if not ok then return false end
            return writeFile(_contentLedgerPath, json .. "\n")
        end

        -- Returns { [id] = { version = ..., ... }, ... } for installed content,
        -- or an empty table. Used by Browse to flag already-installed entries.
        ms.package.listContent = function()
            local ledger = readContentLedger()
            return (ledger and ledger.content) or {}
        end

        local function pathAllowed(kind, rel)
            local spec = TYPE_SPECS[kind]
            if not spec then return false end
            for _, prefix in ipairs(spec.paths) do
                if prefix:find("/$") then
                    if rel:sub(1, #prefix) == prefix then return true end
                elseif rel == prefix then
                    return true
                end
            end
            return false
        end

        local function requiredSatisfied(kind, rels)
            local spec = TYPE_SPECS[kind]
            if not spec then return false end
            if #spec.required == 0 then return true end
            for _, req in ipairs(spec.required) do
                for _, rel in ipairs(rels) do
                    if rel == req or (req:find("/$") and rel:sub(1, #req) == req) then
                        return true
                    end
                end
            end
            return false
        end

        ms.package.pathAllowed = pathAllowed
        ms.package.requiredSatisfied = requiredSatisfied
    -- END Type Specs --

    -- Fingerprint --
        ms.package.fingerprint = function()
            local arch = hs.execute("/usr/bin/uname -m 2>/dev/null") or ""
            return {
                os        = "macos",
                arch      = arch:gsub("%s+", ""),
                mudscript = ms.version or "unknown",
            }
        end

        local OS_LABELS = {
            macos = "macOS",
            windows = "Windows",
        }

        ms.package.osLabel = function(manifest)
            local os_ = type(manifest) == "table" and (manifest.platform or {}).os
            if type(os_) ~= "string" or os_ == "" then return "an unknown platform" end
            return OS_LABELS[os_] or os_
        end

        ms.package.compatWarnings = function(manifest)
            local warnings = {}
            if type(manifest) ~= "table" then return warnings end

            local fp   = manifest.platform or {}
            local here = ms.package.fingerprint()

            if fp.os and fp.os ~= "" and fp.os ~= here.os then
                warnings[#warnings + 1] =
                    "Built on " .. ms.package.osLabel(manifest) .. ", importing on " ..
                    (OS_LABELS[here.os] or here.os) ..
                    ". Key names, modifiers and camera behaviour differ between platforms."
                if manifest.type == "macro" and manifest.macroFormat == "lua" then
                    warnings[#warnings + 1] =
                        "This pack ships hand-written Lua only. Cross-platform packs travel " ..
                        "best as ms_macros_visual.json, which is compiled on import."
                end
            end

            if fp.arch and fp.arch ~= "" and here.arch ~= "" and fp.arch ~= here.arch then
                warnings[#warnings + 1] =
                    "Built for " .. tostring(fp.arch) .. ", this machine is " .. here.arch ..
                    ". Only matters for plugins shipping native code."
            end

            local rq  = manifest.requires
            local req = (type(rq) == "table" and rq.mudscript)
                     or (type(rq) == "string" and rq)
                     or nil
            if type(req) == "string" and req ~= "" then
                local want = req:match("(%d+%.%d+%.%d+)")
                local have = tostring(ms.version or ""):match("(%d+%.%d+%.%d+)")
                if want and have and versionLess(have, want) then
                    warnings[#warnings + 1] =
                        "Needs mudscript " .. req .. ", this install is " .. tostring(ms.version) .. "."
                end
            end

            return warnings
        end
    -- END Fingerprint --

    -- Inspect --
        ms.package.inspect = function(path)
            if not fileExists(path) then return nil, "Package not found." end

            local raw = hs.execute("/usr/bin/unzip -p " .. sq(path) .. " " .. MANIFEST_NAME .. " 2>/dev/null")

            if raw and raw ~= "" then
                local ok, decoded = pcall(hs.json.decode, raw)
                if ok and type(decoded) == "table" and decoded.type then
                    if not TYPE_SPECS[decoded.type] then
                        return nil, "Unknown package type: " .. tostring(decoded.type)
                    end
                    return decoded
                end
            end

            local listing = hs.execute("/usr/bin/unzip -Z1 " .. sq(path) .. " 2>/dev/null") or ""
            if listing:find("ms_macros%.lua") or listing:find("ms_settings%.json") then
                return {
                    formatVersion = 0,
                    type          = "profile",
                    name          = path:match("([^/]+)%.mspkg$") or "Untitled Profile",
                    legacy        = true,
                }
            end

            return nil, "Not a recognisable mudscript package."
        end

        ms.package.contents = function(path)
            local listing = hs.execute("/usr/bin/unzip -Z1 " .. sq(path) .. " 2>/dev/null") or ""
            local out = {}
            for line in listing:gmatch("[^\r\n]+") do
                if not line:find("/$") and line ~= MANIFEST_NAME and not line:find("^__MACOSX/") then
                    out[#out + 1] = line
                end
            end
            return out
        end
    -- END Inspect --

    -- Verify --
        ms.package.verify = function(path, trustLookup)
            local result = {
                ok = false,
                trust = "unsigned",
                issues = {},
                warnings = {},
            }

            local manifest, err = ms.package.inspect(path)
            if not manifest then
                result.issues[#result.issues + 1] = err or "Unreadable package."
                return result
            end
            result.manifest = manifest

            result.hash = hashFile(path)
            if not result.hash then
                result.issues[#result.issues + 1] = "Could not hash package."
                return result
            end

            local members = ms.package.contents(path)
            for _, rel in ipairs(members) do
                if not safeRelPath(rel) then
                    result.issues[#result.issues + 1] = "Unsafe path in package: " .. rel
                elseif not manifest.legacy and not pathAllowed(manifest.type, rel) then
                    result.issues[#result.issues + 1] =
                        "File not permitted in a " .. manifest.type .. " package: " .. rel
                end
            end

            if not manifest.legacy and not requiredSatisfied(manifest.type, members) then
                local spec = TYPE_SPECS[manifest.type]
                result.issues[#result.issues + 1] =
                    "A " .. tostring(manifest.type) .. " package needs " ..
                    table.concat(spec and spec.required or {}, " or ") .. "."
            end

            if type(manifest.contents) == "table" then
                local dir = tempDir("verify")
                hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(dir) .. " 2>/dev/null")
                for rel, want in pairs(manifest.contents) do
                    local got = hashFile(dir .. "/" .. rel)
                    if not got then
                        result.issues[#result.issues + 1] = "Listed but missing: " .. rel
                    elseif got ~= tostring(want):lower() then
                        result.issues[#result.issues + 1] = "Modified since packing: " .. rel
                    end
                end
                rmrf(dir)
            end

            if #result.issues > 0 then
                result.trust = "tampered"
                return result
            end

            if type(trustLookup) == "function" then
                local ok, level = pcall(trustLookup, result.hash, manifest)
                if ok and type(level) == "string" then result.trust = level end
            end

            result.warnings = ms.package.compatWarnings(manifest)
            result.ok = true
            return result
        end
    -- END Verify --

    -- Profile components --
        local PROFILE_COMPONENT_KINDS = {
            "theme",
            "sound",
            "macro",
        }

        local function isAudioRel(rel)
            return rel:sub(1, 14) == "sounds/active/"
                or rel:sub(1, 13) == "sounds/macro/"
                or rel == "sound_assign.json"
        end

        local function profileComponents(relPaths, includeSoundsInTheme)
            local comp = {
                theme    = { files = {}, includesSounds = includeSoundsInTheme and true or false },
                sound    = { files = {} },
                macro    = { files = {} },
                settings = { files = {} },
            }
            local function add(t, r) t[#t + 1] = r end
            for _, r in ipairs(relPaths) do
                if r == "ms_theme.json" or r:sub(1, 9) == "ui/fonts/" then add(comp.theme.files, r) end
                if includeSoundsInTheme and isAudioRel(r) then add(comp.theme.files, r) end
                if isAudioRel(r) then add(comp.sound.files, r) end
                if r == "ms_macros.lua" or r == "ms_macros_visual.json"
                    or r == "ms_macros_visual.lua" or r == "ms_authored.json"
                    or r == "ms_helpervars.json"
                    or r:sub(1, 13) == "sounds/macro/" then add(comp.macro.files, r) end
                if r == "ms_settings.json" or r == "ms_settings_default.json" then
                    add(comp.settings.files, r)
                end
            end
            return comp
        end
    -- END Profile components --

    -- Pack --
        ms.package.pack = function(opts)
            opts = opts or {}
            local kind = opts.type
            local spec = TYPE_SPECS[kind]
            if not spec then return nil, "Unknown package type." end
            if type(opts.files) ~= "table" or next(opts.files) == nil then
                return nil, "Nothing to pack."
            end
            if not opts.out or opts.out == "" then return nil, "No output path." end

            local staging = tempDir("pack")
            local manifest = {
                formatVersion = FORMAT_VERSION,
                type          = kind,
                name          = opts.name or "Untitled",
                version       = opts.version or "1.0.0",
                author        = opts.author,
                website       = opts.website,
                description   = opts.description,
                created       = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                platform      = ms.package.fingerprint(),
                requires      = opts.requires,
                contents      = {},
            }

            local staged = 0
            for rel, src in pairs(opts.files) do
                local clean = safeRelPath(rel)
                if not clean then
                    rmrf(staging)
                    return nil, "Unsafe path: " .. tostring(rel)
                end
                if not pathAllowed(kind, clean) then
                    rmrf(staging)
                    return nil, "A " .. kind .. " package cannot carry " .. clean .. "."
                end
                if fileExists(src) then
                    local destDir = (staging .. "/" .. clean):match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(staging .. "/" .. clean))
                    if ok then
                        manifest.contents[clean] = hashFile(staging .. "/" .. clean)
                        staged = staged + 1
                    end
                end
            end

            if staged == 0 then
                rmrf(staging)
                return nil, "No readable source files."
            end

            local packed = {}
            for rel in pairs(manifest.contents) do packed[#packed + 1] = rel end
            if not requiredSatisfied(kind, packed) then
                rmrf(staging)
                return nil, "A " .. kind .. " package needs " ..
                    table.concat(spec.required, " or ") .. "."
            end

            if kind == "macro" then
                local hasLua  = manifest.contents["ms_macros.lua"] ~= nil
                local hasJSON = manifest.contents["ms_macros_visual.json"] ~= nil
                manifest.macroFormat = (hasLua and hasJSON) and "both"
                    or (hasJSON and "json" or "lua")
            end

            if kind == "profile" then
                local rels = {}
                for rel in pairs(manifest.contents) do rels[#rels + 1] = rel end
                local includeSounds = opts.includeSoundsInTheme
                if includeSounds == nil then includeSounds = false end
                local comp = profileComponents(rels, includeSounds)
                manifest.components = {}
                for _, k in ipairs(PROFILE_COMPONENT_KINDS) do
                    if #comp[k].files > 0 then manifest.components[k] = comp[k] end
                end
                if #comp.settings.files > 0 then manifest.components.settings = comp.settings end
            end

            if not writeFile(staging .. "/" .. MANIFEST_NAME, hs.json.encode(manifest)) then
                rmrf(staging)
                return nil, "Could not write manifest."
            end

            hs.execute("/bin/rm -f " .. sq(opts.out))
            local outDir = opts.out:match("(.*)/")
            if outDir then hs.execute("mkdir -p " .. sq(outDir)) end

            local _, zipped = hs.execute(
                "cd " .. sq(staging) .. " && /usr/bin/zip -qq -r -X " .. sq(opts.out) .. " . 2>/dev/null"
            )
            rmrf(staging)

            if not zipped or not fileExists(opts.out) then return nil, "Could not write package." end

            manifest.hash = hashFile(opts.out)
            return manifest
        end
    -- END Pack --

    -- Split --
        ms.package.split = function(path, outDir, opts)
            opts = opts or {}
            local manifest, err = ms.package.inspect(path)
            if not manifest then return nil, err or "Unreadable package." end
            if manifest.type ~= "profile" then
                return nil, "Only a profile can be split (this is a " ..
                    tostring(manifest.type) .. " package)."
            end
            if not outDir or outDir == "" then return nil, "No output folder." end
            outDir = outDir:gsub("/$", "")

            local includeSounds = opts.includeSoundsInTheme
            if includeSounds == nil then
                local tc = type(manifest.components) == "table" and manifest.components.theme
                includeSounds = (type(tc) == "table" and tc.includesSounds) and true or false
            end

            local rels = ms.package.contents(path)
            local comp = profileComponents(rels, includeSounds)

            local staging = tempDir("split")
            hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(staging) .. " 2>/dev/null")

            local base = manifest.name
                or (path:match("([^/]+)%.mspkg$")) or "Profile"
            base = base:gsub("%s+[Pp]rofile$", "")
            local fileBase = base:gsub("[/\\%c]", ""):gsub("%s+$", "")
            if fileBase == "" then fileBase = "Profile" end

            local made, skipped = {}, {}
            for _, kind in ipairs(PROFILE_COMPONENT_KINDS) do
                local files, present = {}, {}
                for _, rel in ipairs(comp[kind].files) do
                    local abs = staging .. "/" .. rel
                    if fileExists(abs) then
                        files[rel] = abs
                        present[#present + 1] = rel
                    end
                end
                if #present == 0 then
                elseif not requiredSatisfied(kind, present) then
                    skipped[#skipped + 1] = {
                        type = kind,
                        why = "missing " .. table.concat((TYPE_SPECS[kind] or {}).required or {}, " or "),
                    }
                else
                    local label = (TYPE_SPECS[kind] or {}).label or kind
                    local out = outDir .. "/" .. fileBase .. "-" .. kind .. ".mspkg"
                    local m, perr = ms.package.pack({
                        type    = kind,
                        name    = base .. " " .. label,
                        version = manifest.version,
                        author  = manifest.author,
                        website = manifest.website,
                        files   = files,
                        out     = out,
                    })
                    if m then
                        made[#made + 1] = {
                            type = kind,
                            path = out,
                            name = base .. " " .. label,
                        }
                    else
                        skipped[#skipped + 1] = {
                            type = kind,
                            why = perr or "pack failed",
                        }
                    end
                end
            end
            rmrf(staging)
            return {
                made = made,
                skipped = skipped,
            }
        end
    -- END Split --

    -- Apply dropped files --
        -- Post-copy side effects shared by install and library activation:
        -- recompile visual macros, rehydrate the slot map, and flag sounds
        -- dirty so the panel rediscovers them. `installed` is the list of
        -- relative paths that actually landed on disk.
        local function applyDropped(installed)
            local sawAudio = false

            for _, rel in ipairs(installed) do
                if isAudioRel(rel) then sawAudio = true end
            end

            -- A dropped visual-macros source must be recompiled to its .lua.
            -- rebuild() is the compile-all entry point (compile(macroDef) is a
            -- single-macro helper and needs an argument), and load() brings the
            -- result into the live sandbox so the macros actually register.
            if ms.compiler and ms.compiler.rebuild then
                for _, rel in ipairs(installed) do
                    if rel == "ms_macros_visual.json" then
                        pcall(function() ms.compiler.rebuild() end)
                        if ms.compiler.load then pcall(function() ms.compiler.load() end) end
                        break
                    end
                end
            end

            for _, rel in ipairs(installed) do
                if rel == "sound_assign.json" then
                    local dropped = _hsDir .. "/sound_assign.json"
                    local f = io.open(dropped, "r")
                    if f then
                        local raw = f:read("*all")
                        f:close()
                        local ok, tbl = pcall(hs.json.decode, raw)
                        if ok and type(tbl) == "table" then
                            ms.soundAssign = ms.soundAssign or {}
                            for slot, name in pairs(tbl) do
                                if type(slot) == "string" and type(name) == "string" then
                                    ms.soundAssign[slot] = name
                                end
                            end
                            if ms.saveSettings then pcall(ms.saveSettings) end
                        end
                    end
                    os.remove(dropped)
                    break
                end
            end

            if sawAudio then ms._soundsDirty = true end
        end
    -- END Apply dropped files --

    -- Install --
        -- Install a full profile package into profiles/<name>/, seed its
        -- component packs into the library, and link packs.json — the
        -- reciprocal of a profile export. Unlike the generic install path it
        -- does NOT splatter files over the live setup: importing a profile
        -- adds it to the Profiles menu, and switching to it (switchProfile) is
        -- what goes live. Routing a profile through the plain install had three
        -- faults this fixes: no library packs were seeded (libKind "profile"
        -- is not a library kind, so the seed gate was never true), no
        -- profiles/<name>/ entry was created (so it never showed in the menu,
        -- even after a reload), and the live splatter only took effect after a
        -- full hs.reload().
        local function installProfile(staging, manifest, opts)
            -- Profile identity: the macroMeta.name inside ms_macros.lua (what
            -- the Profiles menu and the pack-slug convention key on), falling
            -- back to the manifest name. Sanitised to a filesystem-safe folder
            -- name the same way ms_settings.sanitizeName does.
            local folderName
            local body = readFile(staging .. "/ms_macros.lua")
            if body then
                folderName = body:match('macroMeta%s*=%s*{.-name%s*=%s*"([^"]*)"')
            end
            if not folderName or folderName == "" then
                folderName = manifest.name or "Imported Profile"
            end
            folderName = folderName:gsub('[/\\:*?"<>|%c]', "_")
                :gsub("^%s+", ""):gsub("%s+$", "")
            if folderName == "" then folderName = "Imported Profile" end

            local profileDir = _hsDir .. "/profiles/" .. folderName
            hs.execute("mkdir -p " .. sq(profileDir))
            if not hs.fs.attributes(profileDir) then
                return nil, "Could not create profile folder."
            end

            -- Copy every profile-eligible file from staging into the profile
            -- dir, preserving relative structure.
            local installed = {}
            for rel in pairs(manifest.contents or {}) do
                local clean = safeRelPath(rel)
                if clean and pathAllowed("profile", clean) then
                    local src = staging .. "/" .. clean
                    if fileExists(src) then
                        local dest = profileDir .. "/" .. clean
                        local destDir = dest:match("(.*)/")
                        if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                        local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(dest))
                        if ok then installed[#installed + 1] = clean end
                    end
                end
            end

            if #installed == 0 then return nil, "Nothing could be installed." end

            -- Seed each component pack into the installed library from the
            -- STAGED files (not the live setup — the live slice is unrelated to
            -- the profile being imported), so the profile's look, sounds, and
            -- macros can be hotswapped and switchProfile can activate them.
            local pslug = ms.package.librarySlug(folderName)
            local refs  = {}
            for _, kind in ipairs({ "macro", "theme", "sound" }) do
                local files = {}
                for rel in pairs(manifest.contents or {}) do
                    local clean = safeRelPath(rel)
                    if clean and pathAllowed(kind, clean)
                        and fileExists(staging .. "/" .. clean) then
                        files[clean] = staging .. "/" .. clean
                    end
                end
                if next(files) then
                    local ok, rec = pcall(ms.package.librarySave, kind, files, {
                        name    = folderName,
                        origin  = "profile",
                        version = manifest.version,
                    })
                    if ok and rec then refs[kind] = pslug end
                end
            end

            -- Link the profile to the component packs just seeded (packs.json),
            -- the authoritative map switchProfile and boot read.
            if next(refs) and ms.package.setProfilePacks then
                pcall(ms.package.setProfilePacks, folderName, refs)
            end

            if not opts.component then
                pcall(function() ms.package.recordContent(manifest, opts.id) end)
            end
            ms._profilesDirty = true

            return {
                manifest  = manifest,
                installed = installed,
                failed    = {},
                profile   = folderName,
            }
        end

        ms.package.install = function(path, opts)
            opts = opts or {}

            local report = ms.package.verify(path, opts.trustLookup)
            if not report.ok then
                return nil, table.concat(report.issues, "\n")
            end

            if manifestType(report) == "plugin" and report.trust ~= "trusted" then
                if not ms.package.protectionDisabled() then
                    return nil,
                        "This plugin is not in the validated library.\n" ..
                        "Plugins run as code, so they cannot be imported one-off. " ..
                        "Disable security protections entirely to run unvalidated plugins."
                end
            elseif report.trust == "unsigned" and not opts.force then
                return nil, "Package is not in the validated library. Import anyway to continue."
            end

            if ms.auditMacros then
                for _, rel in ipairs(ms.package.contents(path)) do
                    if rel == "ms_macros.lua" then
                        local src = hs.execute("/usr/bin/unzip -p " .. sq(path) .. " ms_macros.lua 2>/dev/null")
                        if type(src) == "string" and src ~= "" then
                            local errs = ms.auditMacros(src)
                            if type(errs) == "table" and #errs > 0 then
                                return nil, "Macro security scan failed:\n  - " ..
                                    table.concat(errs, "\n  - ")
                            end
                        end
                        break
                    end
                end
            end

            local manifest = report.manifest
            local staging  = tempDir("install")
            hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(staging) .. " 2>/dev/null")

            -- A full profile import is installed as a first-class profile (its
            -- own dir + seeded component packs + packs.json), not splattered
            -- over the live setup. A component slice pulled FROM a profile
            -- (opts.component) still takes the generic single-kind path below.
            if manifest.type == "profile" and not opts.component then
                local res, perr = installProfile(staging, manifest, opts)
                rmrf(staging)
                if not res then return nil, perr end
                return res
            end

            local sliceSet = nil
            if opts.component and type(manifest.components) == "table" then
                sliceSet = {}
                local c = manifest.components[opts.component]
                if type(c) == "table" and type(c.files) == "table" then
                    for _, rel in ipairs(c.files) do sliceSet[rel] = true end
                end
                if opts.component == "theme" and opts.includeSounds
                   and type(manifest.components.sound) == "table"
                   and type(manifest.components.sound.files) == "table" then
                    for _, rel in ipairs(manifest.components.sound.files) do sliceSet[rel] = true end
                end
                if next(sliceSet) == nil then
                    rmrf(staging)
                    return nil, "This profile has no \"" .. tostring(opts.component) .. "\" component."
                end
            end

            local installed, failed = {}, {}

            for _, rel in ipairs(ms.package.contents(path)) do
                local clean = safeRelPath(rel)
                if clean and (not sliceSet or sliceSet[clean])
                   and (manifest.legacy or pathAllowed(manifest.type, clean)) then
                    local dest = destFor(clean)

                    if opts.backup ~= false and fileExists(dest) then
                        hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                    end

                    local destDir = dest:match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end

                    local _, ok = hs.execute("/bin/cp " .. sq(staging .. "/" .. clean) .. " " .. sq(dest))
                    if ok then installed[#installed + 1] = clean
                    else failed[#failed + 1] = clean end
                end
            end

            -- Mirror the slice into the installed library so the panels can
            -- hotswap it later. The kind is the component for a slice install,
            -- else the package's own type. Named after the manifest, so a slice
            -- pulled from a profile inherits that profile's name.
            local libKind = opts.component or manifest.type
            if #installed > 0 and ms.package.isLibraryKind(libKind) and not opts.noLibrary then
                local libFiles = {}
                for _, clean in ipairs(installed) do
                    if pathAllowed(libKind, clean) then
                        libFiles[clean] = staging .. "/" .. clean
                    end
                end
                if next(libFiles) then
                    pcall(function()
                        ms.package.librarySave(libKind, libFiles, {
                            name    = manifest.name,
                            origin  = opts.component and "profile-slice" or "installed",
                            version = manifest.version,
                        })
                    end)
                end
            end

            rmrf(staging)

            if #installed == 0 then return nil, "Nothing could be installed." end

            applyDropped(installed)

            if manifest.type == "plugin" then
                local names = {}
                for _, rel in ipairs(installed) do
                    local spoon = rel:match("^Spoons/([^/]+%.spoon)")
                    if spoon then names[spoon] = true end
                end
                if next(names) then
                    pcall(function() ms.package.recordPlugins(names, manifest, opts.id) end)
                end
            else
                -- Record the installed version for Update detection. A component
                -- slice is a partial install, so it is not recorded.
                if not opts.component then
                    pcall(function() ms.package.recordContent(manifest, opts.id) end)
                end
            end

            if manifest.type == "profile" then
                ms._profilesDirty = true
            end

            return {
                manifest  = manifest,
                installed = installed,
                failed    = failed,
                trust     = report.trust,
                warnings  = report.warnings,
            }
        end
    -- END Install --

    -- Plugin Inventory --

        local function validSpoonName(name)
            if type(name) ~= "string" then return nil end
            if not name:match("^[%w%-%._ ]+%.spoon$") then return nil end
            if name:find("%.%.") or name:find("^%.") then return nil end
            return name
        end

        ms.package.validSpoonName = validSpoonName

        ms.package.pluginEnabled = function(name)
            local off = ms._pluginsDisabled
            return not (type(off) == "table" and off[name] == true)
        end

        ms.package.listPlugins = function()
            local out = {}
            local spoonsDir = _hsDir .. "/Spoons"
            if not hs.fs.attributes(spoonsDir) then return out end

            local ledger = readLedger()
            local rows   = (ledger and ledger.plugins) or {}

            for entry in hs.fs.dir(spoonsDir) do
                local name = validSpoonName(entry)
                local abs  = spoonsDir .. "/" .. tostring(entry)
                local attr = name and hs.fs.attributes(abs)
                if name and attr and attr.mode == "directory" then
                    local rec    = rows[name]
                    local status = "unrecorded"
                    if type(rec) == "table" and type(rec.hash) == "string" then
                        local live = spoonTreeHash(abs)
                        status = (live and live:lower() == rec.hash:lower())
                            and "ok" or "modified"
                    end
                    rec = type(rec) == "table" and rec or {}

                    out[#out + 1] = {
                        dir         = name,
                        name        = rec.name or name:gsub("%.spoon$", ""),
                        id          = rec.id,
                        version     = rec.version,
                        author      = rec.author,
                        website     = rec.website,
                        description = rec.description,
                        installedAt = rec.installedAt,
                        status      = status,
                        enabled     = ms.package.pluginEnabled(name),
                    }
                end
            end

            table.sort(out, function(a, b)
                return a.name:lower() < b.name:lower()
            end)
            return out
        end

        ms.package.setPluginEnabled = function(name, on)
            if not validSpoonName(name) then return false end
            ms._pluginsDisabled = ms._pluginsDisabled or {}
            ms._pluginsDisabled[name] = (on == false) or nil
            if ms.saveSettings then pcall(ms.saveSettings) end
            return true
        end

        ms.package.removePlugin = function(name)
            if not validSpoonName(name) then return false, "Invalid plugin name." end

            local abs  = _hsDir .. "/Spoons/" .. name
            local attr = hs.fs.attributes(abs)
            if not attr or attr.mode ~= "directory" then
                return false, "No such plugin."
            end

            hs.execute("/bin/rm -rf " .. sq(abs))
            if hs.fs.attributes(abs) then
                return false, "Could not remove " .. name .. "."
            end

            local ledger = readLedger()
            if ledger and ledger.plugins[name] then
                ledger.plugins[name] = nil
                writeLedger(ledger)
            end

            if ms._pluginsDisabled then ms._pluginsDisabled[name] = nil end
            if ms.saveSettings then pcall(ms.saveSettings) end

            return true
        end
    -- END Plugin Inventory --

    -- Export Helpers --
        ms.package.collect = function(kind, opts)
            local files = {}

            local function addIf(rel, abs)
                if fileExists(abs) then files[rel] = abs end
            end

            local function addDir(relDir, absDir)
                if not hs.fs.attributes(absDir) then return end
                for entry in hs.fs.dir(absDir) do
                    -- Skip dotfiles and .bak backups. Activation writes a
                    -- <file>.bak next to each overwritten asset, and those
                    -- siblings live right inside sounds/macro/; collecting them
                    -- pollutes the slice and breaks the reconcile fingerprint.
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.")
                        and not entry:find("%.bak") then
                        local abs = absDir .. entry
                        if fileExists(abs) then files[relDir .. entry] = abs end
                    end
                end
            end

            if kind == "macro" then
                -- baseDir lets us collect a pack from an arbitrary folder (a
                -- profile dir) rather than the live locations, for migration.
                local base = opts and opts.baseDir
                local dataSrc = function(f) return base and (base .. "/" .. f) or (_dataDir .. "/" .. f) end
                addIf("ms_macros.lua",         base and (base .. "/ms_macros.lua") or (_hsDir .. "/ms_macros.lua"))
                addIf("ms_macros_visual.json", dataSrc("ms_macros_visual.json"))
                addIf("ms_macros_visual.lua",  dataSrc("ms_macros_visual.lua"))
                addIf("ms_authored.json",      dataSrc("ms_authored.json"))
                addIf("ms_helpervars.json",    dataSrc("ms_helpervars.json"))
                addDir("sounds/macro/",        base and (base .. "/sounds/macro/") or (_hsDir .. "/sounds/macro/"))

            elseif kind == "theme" then
                addIf("ms_theme.json", _dataDir .. "/ms_theme.json")
                addDir("ui/fonts/",    _hsDir .. "/ui/fonts/")
                if ms.bundleSoundsWithTheme ~= false then
                    addDir("sounds/active/", _hsDir .. "/sounds/active/")
                    addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                    local assign = ms.package.exportSoundAssign()
                    if assign then files["sound_assign.json"] = assign end
                end

            elseif kind == "sound" then
                addDir("sounds/active/", _hsDir .. "/sounds/active/")
                addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                local assign = ms.package.exportSoundAssign()
                if assign then files["sound_assign.json"] = assign end

            elseif kind == "profile" then
                local cfg = opts and opts.configDir
                local macrosSrc = cfg and (cfg .. "ms_macros.lua")            or (_hsDir   .. "/ms_macros.lua")
                local dataSrc   = function(f) return cfg and (cfg .. f)       or (_dataDir .. "/" .. f) end
                addIf("ms_macros.lua",            macrosSrc)
                addIf("ms_macros_visual.json",    dataSrc("ms_macros_visual.json"))
                addIf("ms_macros_visual.lua",     dataSrc("ms_macros_visual.lua"))
                addIf("ms_authored.json",         dataSrc("ms_authored.json"))
                addIf("ms_helpervars.json",       dataSrc("ms_helpervars.json"))
                addIf("ms_settings.json",         dataSrc("ms_settings.json"))
                addIf("ms_settings_default.json", dataSrc("ms_settings_default.json"))
                addIf("ms_theme.json",            dataSrc("ms_theme.json"))
                addDir("sounds/active/", _hsDir .. "/sounds/active/")
                addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                addDir("ui/fonts/",      _hsDir .. "/ui/fonts/")
                local assign = ms.package.exportSoundAssign()
                if assign then files["sound_assign.json"] = assign end
            end

            return files
        end

        ms.package.exportSoundAssign = function()
            local path = tempDir("assign") .. "/sound_assign.json"
            if writeFile(path, hs.json.encode(ms.soundAssign or {})) then return path end
            return nil
        end
    -- END Export Helpers --

    -- Installed Library --
        -- A shelf of installed, hotswappable slices — a theme, a sound pack, or
        -- a macro pack — that Browse fills on install and the panels manage.
        -- Each entry is a folder under data/library/<kind>/<slug>/ holding the
        -- slice's files verbatim (by their live relative paths) plus meta.json.
        -- Activating an entry copies those files into the live dirs, reusing the
        -- same destinations install writes to. See [[partial-install-single-asset-slices]].
        local LIBRARY_ROOT = _dataDir .. "/library"

        local LIBRARY_KINDS = {
            theme = true,
            sound = true,
            macro = true,
        }

        ms.package.isLibraryKind = function(kind) return LIBRARY_KINDS[kind] == true end

        local function librarySlug(name)
            local slug = tostring(name or "")
                :gsub("%.mspkg$", "")
                :gsub("[^%w%-_ ]", "")
                :gsub("%s+", "-")
                :gsub("%-+", "-")
                :gsub("^%-", "")
                :gsub("%-$", "")
            if slug == "" then slug = "slice" end
            return slug:sub(1, 64)
        end

        local function libraryDir(kind, slug)
            return LIBRARY_ROOT .. "/" .. kind .. "/" .. slug
        end

        -- Exposed so profile code can map a profile name to its pack slug and
        -- test whether the profile's same-named pack exists in a kind.
        ms.package.librarySlug = librarySlug
        ms.package.libraryHasEntry = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return false end
            return hs.fs.attributes(libraryDir(kind, librarySlug(slug)) .. "/meta.json") ~= nil
        end

        -- The canonical blank macro source. Shared by createNewProfile and
        -- libraryCreateEmpty so a blank profile's live ms_macros.lua and its
        -- blank macro pack are byte-identical — which lets the reconcile
        -- fingerprint match them and keeps the pack marked active across boots.
        ms.package.blankMacroSrc = function(name)
            return table.concat({
                "-- New profile — add your macros below.",
                "ms.macroMeta = {",
                "    name   = \"" .. tostring(name or "") .. "\",",
                "    author = \"\",",
                "}",
                "",
            }, "\n")
        end

        local function readJSON(path)
            local raw = readFile(path)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then return tbl end
            return nil
        end

        -- Which stored slice of a kind is currently live. Persisted as a plain
        -- slug in data/library/<kind>/.active so the panels can flag the active
        -- entry and boot can tell whether a pack still needs importing.
        local function activeMarkerPath(kind) return LIBRARY_ROOT .. "/" .. kind .. "/.active" end

        ms.package.libraryGetActive = function(kind)
            if not LIBRARY_KINDS[kind] then return nil end
            local s = readFile(activeMarkerPath(kind))
            if not s then return nil end
            s = s:gsub("%s+$", "")
            return s ~= "" and s or nil
        end

        ms.package.librarySetActive = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return end
            if slug and slug ~= "" then
                local dir = LIBRARY_ROOT .. "/" .. kind
                hs.execute("mkdir -p " .. sq(dir))
                writeFile(activeMarkerPath(kind), librarySlug(slug) .. "\n")
            else
                os.remove(activeMarkerPath(kind))
            end
        end

        -- The profile the live setup is "on", tracked explicitly rather than
        -- inferred from the three pack markers. A profile switch records the
        -- profile name here. A single-pack hotswap NO LONGER clears it: a profile
        -- is a collection of component packs, so swapping one component just swaps
        -- that slot's live pack while the profile stays active (its packs.json
        -- still names the saved pack until the user saves). This decouples "which
        -- profile is active" from pack naming — same-named packs are not required
        -- to exist, and packs named off-convention (e.g. a shared sound pack) no
        -- longer make the profile read as unaligned. The value is a raw profile
        -- folder name (what getProfiles returns), or nil when nothing is claimed.
        local activeProfilePath = LIBRARY_ROOT .. "/.active_profile"
        ms.package.getActiveProfile = function()
            local s = readFile(activeProfilePath)
            if not s then return nil end
            s = s:gsub("%s+$", "")
            return s ~= "" and s or nil
        end
        ms.package.setActiveProfile = function(name)
            if name and name ~= "" then
                hs.execute("mkdir -p " .. sq(LIBRARY_ROOT))
                writeFile(activeProfilePath, tostring(name) .. "\n")
            else
                os.remove(activeProfilePath)
            end
        end

        -- A profile is an explicit collection of component packs, one per kind.
        -- profiles/<name>/packs.json records the library slug the profile uses for
        -- each kind, so a profile can point at off-convention or shared packs (a
        -- profile named "Combat Warriors Macros" can own a macro pack named
        -- anything). A missing key = that slot is a custom/unsaved mix with no
        -- linked pack. This is the authoritative link; the old same-name slug
        -- convention is only a fallback for legacy profiles that predate this file.
        local function profilePacksPath(name)
            return _hsDir .. "/profiles/" .. tostring(name) .. "/packs.json"
        end
        ms.package.getProfilePacks = function(name)
            if not name or name == "" then return nil end
            local t = readJSON(profilePacksPath(name))
            if type(t) ~= "table" then return nil end
            local out = {}
            for _, k in ipairs({ "theme", "sound", "macro" }) do
                if type(t[k]) == "string" and t[k] ~= "" then out[k] = t[k] end
            end
            return out
        end
        ms.package.setProfilePacks = function(name, tbl)
            if not name or name == "" or type(tbl) ~= "table" then return false end
            local rec = {}
            for _, k in ipairs({ "theme", "sound", "macro" }) do
                if type(tbl[k]) == "string" and tbl[k] ~= "" then rec[k] = tbl[k] end
            end
            local dir = _hsDir .. "/profiles/" .. tostring(name)
            hs.execute("mkdir -p " .. sq(dir))
            return writeFile(profilePacksPath(name), hs.json.encode(rec) .. "\n")
        end

        -- Copy a slice into the library. `files` is { relpath = absSource },
        -- exactly the shape collect() returns. `meta` carries the display name
        -- (which inherits its origin profile's name), origin, and version.
        ms.package.librarySave = function(kind, files, meta)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind: " .. tostring(kind) end
            if type(files) ~= "table" or next(files) == nil then
                return nil, "Nothing to store."
            end
            meta = type(meta) == "table" and meta or {}

            local name = meta.name or "Untitled"
            local slug = librarySlug(meta.slug or name)
            local dir  = libraryDir(kind, slug)
            local filesDir = dir .. "/files"

            hs.execute("/bin/rm -rf " .. sq(dir))
            hs.execute("mkdir -p " .. sq(filesDir))

            local stored = {}
            for rel, src in pairs(files) do
                local clean = safeRelPath(rel)
                if clean and pathAllowed(kind, clean) and fileExists(src) then
                    local destDir = (filesDir .. "/" .. clean):match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(filesDir .. "/" .. clean))
                    if ok then stored[#stored + 1] = clean end
                end
            end

            if #stored == 0 then
                hs.execute("/bin/rm -rf " .. sq(dir))
                return nil, "No readable files to store."
            end

            local record = {
                slug        = slug,
                kind        = kind,
                name        = name,
                origin      = meta.origin,
                version     = meta.version,
                fileCount   = #stored,
                installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }

            writeFile(dir .. "/meta.json", hs.json.encode(record) .. "\n")
            return record
        end

        -- Every stored slice of a kind, newest first.
        ms.package.libraryList = function(kind)
            local out = {}
            if not LIBRARY_KINDS[kind] then return out end

            local base = LIBRARY_ROOT .. "/" .. kind
            if not hs.fs.attributes(base) then return out end

            local activeSlug = ms.package.libraryGetActive(kind)
            for entry in hs.fs.dir(base) do
                if entry ~= "." and entry ~= ".." and not entry:find("^%.") then
                    local rec = readJSON(base .. "/" .. entry .. "/meta.json")
                    if rec then
                        rec.slug = rec.slug or entry
                        rec.active = (activeSlug ~= nil and rec.slug == activeSlug)
                        out[#out + 1] = rec
                    end
                end
            end

            table.sort(out, function(a, b)
                return tostring(a.installedAt) > tostring(b.installedAt)
            end)
            return out
        end

        -- Copy a stored slice's files into the live install and run the same
        -- post-copy steps install does. Backs up whatever it overwrites.
        ms.package.libraryActivate = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            slug = librarySlug(slug)

            local filesDir = libraryDir(kind, slug) .. "/files"
            if not hs.fs.attributes(filesDir) then return nil, "No such library entry." end

            -- A macro pack's ms_macros.lua is executed on the next reload, so it
            -- must pass the same security scan install runs before it goes live.
            if kind == "macro" and ms.auditMacros then
                local src = readFile(filesDir .. "/ms_macros.lua")
                if type(src) == "string" and src ~= "" then
                    local errs = ms.auditMacros(src)
                    if type(errs) == "table" and #errs > 0 then
                        return nil, "Macro security scan failed:\n  - " ..
                            table.concat(errs, "\n  - ")
                    end
                end
            end

            local rels = hs.execute(
                "cd " .. sq(filesDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
            ) or ""

            -- The set of relpaths the incoming slice provides, so the replace
            -- step below can spare live files this slice is about to overwrite.
            local incoming = {}
            for line in rels:gmatch("[^\r\n]+") do
                local clean = safeRelPath(line:gsub("^%./", ""))
                if clean and pathAllowed(kind, clean) then incoming[clean] = true end
            end

            -- Clean replace: activation must swap the slice, not layer onto it.
            -- Remove exactly the files the previously-active entry owned that
            -- this one does not carry (e.g. a blank macro pack must clear the
            -- prior pack's ms_macros_visual.*). Scoped to the prior entry's own
            -- file list, so shared assets (sounds/macro/) another pack placed
            -- are never collateral. Skipped when there is no prior marker — the
            -- live state is custom and we cannot know what it owns.
            local prev = ms.package.libraryGetActive(kind)
            if prev and prev ~= slug then
                local prevDir = libraryDir(kind, prev) .. "/files"
                if hs.fs.attributes(prevDir) then
                    local prevRels = hs.execute(
                        "cd " .. sq(prevDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
                    ) or ""
                    for line in prevRels:gmatch("[^\r\n]+") do
                        local clean = safeRelPath(line:gsub("^%./", ""))
                        if clean and pathAllowed(kind, clean) and not incoming[clean] then
                            local dest = destFor(clean)
                            if fileExists(dest) then
                                hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                                os.remove(dest)
                            end
                        end
                    end
                end
            end

            local installed, failed = {}, {}
            for line in rels:gmatch("[^\r\n]+") do
                local clean = safeRelPath(line:gsub("^%./", ""))
                if clean and pathAllowed(kind, clean) then
                    local src  = filesDir .. "/" .. clean
                    local dest = destFor(clean)

                    if fileExists(dest) then
                        hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                    end

                    local destDir = dest:match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end

                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(dest))
                    if ok then installed[#installed + 1] = clean
                    else failed[#failed + 1] = clean end
                end
            end

            -- A blank pack carries no files. That is a valid "reset to
            -- default" activation (the same way a blank macro pack or profile
            -- is), NOT a failure — only error if the slice HAD files and every
            -- copy failed. The clean-replace above already removed the prior
            -- entry's files; also clear this kind's live default targets so it
            -- resets even when there was no prior marker (custom/unmanaged live
            -- state). Non-destructive: only the config file that pins a
            -- non-default look/preset is removed, never the user's audio.
            local hadFiles = next(incoming) ~= nil
            if hadFiles and #installed == 0 then
                return nil, "Nothing could be activated."
            end
            if not hadFiles then
                if kind == "theme" then
                    os.remove(_dataDir .. "/ms_theme.json")
                elseif kind == "sound" then
                    os.remove(_hsDir .. "/sound_assign.json")
                    ms._soundsDirty = true
                elseif kind == "macro" then
                    -- Clean-replace just removed the prior pack's ms_macros.lua
                    -- and a blank pack carries none — leaving the live macros
                    -- file absent, which breaks reloadMacros and would crash the
                    -- next cold boot's audit. Seed the same minimal stub boot
                    -- and switchProfile use so there is always a valid file.
                    if not fileExists(_hsDir .. "/ms_macros.lua") then
                        writeFile(_hsDir .. "/ms_macros.lua",
                            "-- Blank macro pack — add your macros below.\n"
                            .. "ms.macroMeta = { name = \"" .. tostring(slug)
                            .. "\", author = \"\" }\n")
                    end
                end
            end

            applyDropped(installed)
            ms.package.librarySetActive(kind, slug)

            return {
                kind      = kind,
                slug      = slug,
                installed = installed,
                failed    = failed,
            }
        end

        -- Public, macro-callable alias for activating an installed pack by slug.
        -- Top-level so a handwritten macro can call it exactly as the visual
        -- builder emits it (ms.switchPack), and so the builder module can be
        -- labelled by a real function name. kind defaults to a macro pack.
        ms.switchPack = function(slug, kind)
            return ms.package.libraryActivate(kind or "macro", slug)
        end

        ms.package.libraryRemove = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return false, "Not a library kind." end
            slug = librarySlug(slug)

            local dir = libraryDir(kind, slug)
            if not hs.fs.attributes(dir) then return false, "No such library entry." end

            hs.execute("/bin/rm -rf " .. sq(dir))
            if hs.fs.attributes(dir) then return false, "Could not remove entry." end
            if ms.package.libraryGetActive(kind) == slug then
                ms.package.librarySetActive(kind, nil)
            end
            return true
        end

        -- Rename a stored slice in place. The slug (folder name + .active
        -- marker) stays put so nothing has to move on disk; only the display
        -- name in meta.json changes. Mirrors the profiles panel's rename.
        ms.package.libraryRename = function(kind, slug, newName)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            slug = librarySlug(slug)
            local dir = libraryDir(kind, slug)
            local rec = readJSON(dir .. "/meta.json")
            if not rec then return nil, "No such library entry." end
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if newName == "" then return nil, "Name cannot be empty." end
            rec.name = newName
            writeFile(dir .. "/meta.json", hs.json.encode(rec) .. "\n")
            return rec
        end

        -- Rename a stored slice's SLUG (folder) as well as its display name, so
        -- a profile rename can keep its same-named packs aligned (alignment
        -- matches by slug). Moves the entry folder, updates meta, and carries
        -- the .active marker across if this entry was active. No-op if the entry
        -- does not exist; refuses to clobber an existing target slug.
        ms.package.libraryRenameEntry = function(kind, oldSlug, newName)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            oldSlug = librarySlug(oldSlug)
            newName = type(newName) == "string" and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if newName == "" then return nil, "Name cannot be empty." end
            local oldDir = libraryDir(kind, oldSlug)
            if not hs.fs.attributes(oldDir) then return nil end   -- nothing to rename
            local newSlug = librarySlug(newName)
            if newSlug ~= oldSlug then
                local newDir = libraryDir(kind, newSlug)
                if hs.fs.attributes(newDir) then
                    return nil, "A pack with that name already exists."
                end
                local _, ok = hs.execute("/bin/mv " .. sq(oldDir) .. " " .. sq(newDir))
                if not ok or not hs.fs.attributes(newDir) then
                    return nil, "Could not rename entry."
                end
                if ms.package.libraryGetActive(kind) == oldSlug then
                    ms.package.librarySetActive(kind, newSlug)
                end
            end
            local dir = libraryDir(kind, newSlug)
            local rec = readJSON(dir .. "/meta.json") or {}
            rec.name = newName
            rec.slug = newSlug
            writeFile(dir .. "/meta.json", hs.json.encode(rec) .. "\n")
            return rec
        end

        -- Record each visual macro's current key bind into the LIVE
        -- ms_macros_visual.json, so a subsequent capture banks it and the bind
        -- travels with the pack. Visual macros register with no built-in bind —
        -- the key lives only in ms_settings.json (profile-owned) — so swapping a
        -- pack onto another profile's settings loses the bind. The compiler
        -- already emits a `default` bind from a macro's `bind` field
        -- (ms_compiler.lua), so recording it here makes the activated pack
        -- self-bind. Folding the LIVE file (not just the stored copy) keeps live
        -- and stored byte-identical, so the reconcile fingerprint still matches.
        -- Only key binds are folded (the shape the compiler fully restores);
        -- other bind types stay settings-only.
        local function foldLiveMacroBinds()
            if type(ms.bindConfig) ~= "table" then return end
            local jsonPath = _dataDir .. "/ms_macros_visual.json"
            local data = readJSON(jsonPath)
            if type(data) ~= "table" or type(data.macros) ~= "table" then return end

            local changed = false
            for id, macro in pairs(data.macros) do
                local cfg = ms.bindConfig[id]
                if type(macro) == "table" and type(cfg) == "table"
                    and (cfg.type == nil or cfg.type == "key") and cfg.key ~= nil then
                    local mods = {}
                    for _, m in ipairs(cfg.mods or {}) do mods[#mods + 1] = m end
                    macro.bind = { type = "key", key = cfg.key, mods = mods }
                    changed = true
                end
            end
            if changed then writeFile(jsonPath, hs.json.encode(data) .. "\n") end
        end

        -- Create a bare-bones, empty library slot the user can populate later —
        -- the pack analogue of Create New Profile ([[create-new-profile-makes-empty-entry]]).
        -- Meta only, no files; activating it copies nothing (the live slice
        -- stays put) until the user saves their current setup into it.
        ms.package.libraryCreateEmpty = function(kind, name)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            name = (type(name) == "string" and name ~= "") and name or ("New " .. kind)
            local slug = librarySlug(name)
            local dir  = libraryDir(kind, slug)
            if hs.fs.attributes(dir) then return nil, "A pack with that name already exists." end
            hs.execute("mkdir -p " .. sq(dir .. "/files"))

            -- A blank SOUND pack is not silent-empty: like a blank profile
            -- (seeded default rather than silent), it represents the DEFAULT
            -- preset. Seed a full default sound_assign.json (every slot mapped
            -- to its built-in default sample) so activating the pack resets the
            -- live assignments — and therefore the Presets indicator — to
            -- Default. Without it, activation kept the previous pack's slot map
            -- (applyDropped only merges the assigns a slice carries), so the
            -- preset never showed Default.
            local fileCount = 0
            if kind == "sound" and ms.soundSlotDefaults then
                local assigns = ms.soundSlotDefaults()
                if next(assigns) then
                    writeFile(dir .. "/files/sound_assign.json",
                        hs.json.encode(assigns) .. "\n")
                    fileCount = 1
                end
            elseif kind == "macro" then
                -- A blank macro pack carries the same stub ms_macros.lua a blank
                -- profile goes live with, so the two are byte-identical and the
                -- pack's active marker survives the reconcile fingerprint.
                writeFile(dir .. "/files/ms_macros.lua",
                    ms.package.blankMacroSrc(name))
                fileCount = 1
            end

            local record = {
                slug        = slug,
                kind        = kind,
                name        = name,
                origin      = "new",
                fileCount   = fileCount,
                installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
            writeFile(dir .. "/meta.json", hs.json.encode(record) .. "\n")
            return record
        end

        -- Create a new named entry seeded from the current live slice — the
        -- pack analogue of Create New Profile ▸ "Seed from current". Unlike
        -- libraryCapture it does NOT flip the active marker (creating a profile
        -- doesn't switch to it), and it refuses to clobber an existing name.
        -- If nothing is live to seed, it falls back to an empty slot.
        ms.package.libraryCreateSeeded = function(kind, name)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            name = (type(name) == "string" and name ~= "") and name or ("New " .. kind)
            local slug = librarySlug(name)
            if hs.fs.attributes(libraryDir(kind, slug)) then
                return nil, "A pack with that name already exists."
            end

            if kind == "macro" then foldLiveMacroBinds() end
            local files = ms.package.collect(kind)
            if next(files) == nil then
                return ms.package.libraryCreateEmpty(kind, name)
            end
            return ms.package.librarySave(kind, files, {
                slug   = slug,
                name   = name,
                origin = "seeded",
            })
        end

        -- Remove every stored entry of a kind except the active one — the pack
        -- analogue of Clear Saved Profiles. Returns the count removed.
        ms.package.libraryClear = function(kind)
            if not LIBRARY_KINDS[kind] then return 0, "Not a library kind." end
            local active = ms.package.libraryGetActive(kind)
            local removed = 0
            for _, rec in ipairs(ms.package.libraryList(kind)) do
                if rec.slug ~= active then
                    hs.execute("/bin/rm -rf " .. sq(libraryDir(kind, rec.slug)))
                    removed = removed + 1
                end
            end
            return removed
        end

        -- Absolute path to a stored slice's files, so export can pack a
        -- specific library entry rather than only the live one.
        ms.package.libraryFilesDir = function(kind, slug)
            if not LIBRARY_KINDS[kind] then return nil end
            return libraryDir(kind, librarySlug(slug)) .. "/files"
        end

        -- Snapshot the current live slice of a kind into the library, so the
        -- user can bank the setup they are running and hotswap back to it.
        ms.package.libraryCapture = function(kind, name)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end

            if kind == "macro" then foldLiveMacroBinds() end
            local files = ms.package.collect(kind)
            if next(files) == nil then
                return nil, "Nothing live to capture as a " .. kind .. "."
            end

            local rec, err = ms.package.librarySave(kind, files, {
                name   = (type(name) == "string" and name ~= "" and name) or "Current " .. kind,
                origin = "captured",
            })
            -- Capturing banks the live slice, so that entry is what is live now.
            if rec then ms.package.librarySetActive(kind, rec.slug) end
            return rec, err
        end

        -- Import a slice sitting in an arbitrary folder (e.g. a profile dir)
        -- into the library. Copy only; the source folder is left untouched.
        ms.package.libraryImportDir = function(kind, baseDir, meta)
            if not LIBRARY_KINDS[kind] then return nil, "Not a library kind." end
            if not hs.fs.attributes(baseDir) then return nil, "No such folder." end
            local files = ms.package.collect(kind, { baseDir = baseDir })
            if next(files) == nil then return nil, "Nothing to import." end
            return ms.package.librarySave(kind, files, meta or {})
        end

        -- One-time, non-destructive migration: surface every macro pack the user
        -- already has — the live pack plus each saved profile's pack — as library
        -- entries so they appear in Installed Macro Packs and can be hotswapped.
        -- Copies only; never deletes profile files. Idempotent by slug + marker.
        ms.package.migrateMacroPacks = function()
            local macroRoot  = LIBRARY_ROOT .. "/macro"
            local doneMarker = macroRoot .. "/.migrated"
            if hs.fs.attributes(doneMarker) then return end

            local function slugExists(name)
                return hs.fs.attributes(libraryDir("macro", librarySlug(name))) ~= nil
            end

            -- 1. The live pack, named from its own credits when present.
            local liveName = (ms.macroMeta and type(ms.macroMeta.name) == "string"
                and ms.macroMeta.name ~= "" and ms.macroMeta.name) or "Current Macros"
            local liveFiles = ms.package.collect("macro")
            if next(liveFiles) ~= nil and not slugExists(liveName) then
                local rec = ms.package.librarySave("macro", liveFiles, {
                    name    = liveName,
                    origin  = "current",
                    version = ms.macroMeta and ms.macroMeta.version or nil,
                })
                -- The live pack is, by definition, what is active right now.
                if rec and not ms.package.libraryGetActive("macro") then
                    ms.package.librarySetActive("macro", rec.slug)
                end
            end

            -- 2. Each saved profile's pack, named after its profile folder.
            local profilesDir = _hsDir .. "/profiles/"
            if hs.fs.attributes(profilesDir) then
                for entry in hs.fs.dir(profilesDir) do
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.") then
                        local pdir = profilesDir .. entry
                        if hs.fs.attributes(pdir .. "/ms_macros.lua") and not slugExists(entry) then
                            ms.package.libraryImportDir("macro", pdir, {
                                name = entry, origin = "profile",
                            })
                        end
                    end
                end
            end

            hs.execute("mkdir -p " .. sq(macroRoot))
            writeFile(doneMarker, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
        end

        -- Backfill profiles/<name>/packs.json for legacy profiles that predate it,
        -- by linking to any already-existing same-named component pack. Runs every
        -- boot but no-ops per profile that already has packs.json, and never
        -- CREATES packs (that would be an implicit save) — a profile with no
        -- same-named pack in a kind is left unlinked for that slot until the user
        -- explicitly saves. Idempotent and cheap (a few fs stats per profile).
        ms.package.migrateProfilePacks = function()
            local profilesDir = _hsDir .. "/profiles/"
            if not hs.fs.attributes(profilesDir) then return end
            for entry in hs.fs.dir(profilesDir) do
                if entry ~= "." and entry ~= ".." and not entry:find("^%.")
                    and not hs.fs.attributes(profilePacksPath(entry)) then
                    local slug = librarySlug(entry)
                    local refs = {}
                    for _, k in ipairs({ "theme", "sound", "macro" }) do
                        if ms.package.libraryHasEntry(k, slug) then refs[k] = slug end
                    end
                    if next(refs) then ms.package.setProfilePacks(entry, refs) end
                end
            end
        end

        -- Files whose bytes are regenerated on the fly (so they never compare
        -- equal even when the slice is otherwise identical) — excluded from the
        -- reconcile fingerprint. sound_assign.json is re-encoded by collect();
        -- ms_macros_visual.lua is recompiled from its .json on every rebuild()
        -- (the .json source stays in the fingerprint), so its bytes drift.
        local RECONCILE_SKIP = {
            ["sound_assign.json"]     = true,
            ["ms_macros_visual.lua"]  = true,
        }

        -- Deterministic JSON serialization (sorted object keys) so a slice's
        -- *.json files fingerprint by CONTENT, not by hs.json.encode's unstable
        -- key order. Without this, a plain re-encode of an identical table (e.g.
        -- a bind serialized {type,key,mods} vs {key,type,mods}) produced different
        -- bytes and flipped the reconcile badge. Array vs object is inferred:
        -- a non-empty pure-sequence table is an array, everything else an object.
        local function canonicalJSON(v)
            local t = type(v)
            if t == "table" then
                local n, isSeq = 0, true
                for k in pairs(v) do
                    n = n + 1
                    if type(k) ~= "number" then isSeq = false end
                end
                if isSeq and n > 0 and #v == n then
                    local parts = {}
                    for i = 1, n do parts[i] = canonicalJSON(v[i]) end
                    return "[" .. table.concat(parts, ",") .. "]"
                end
                local keys = {}
                for k in pairs(v) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                local parts = {}
                for _, k in ipairs(keys) do
                    parts[#parts + 1] = string.format("%q", k) .. ":" .. canonicalJSON(v[k])
                end
                return "{" .. table.concat(parts, ",") .. "}"
            elseif t == "string" then
                return string.format("%q", v)
            elseif t == "number" or t == "boolean" then
                return tostring(v)
            end
            return "null"
        end

        -- Per-macro key binds are profile-owned (they live in ms_settings.json and
        -- are folded into the pack only so they travel on activation). Two macro
        -- slices with identical macro CONTENT but different binds are the same pack
        -- for reconcile purposes, so strip binds before fingerprinting.
        local function stripVisualBinds(tbl)
            if type(tbl) == "table" and type(tbl.macros) == "table" then
                for _, m in pairs(tbl.macros) do
                    if type(m) == "table" then m.bind = nil end
                end
            end
            return tbl
        end

        -- A stable content fingerprint of a { rel = abs } slice: sorted rel paths,
        -- each reduced to a content token. JSON files are canonicalized (and macro
        -- binds stripped) so key-order and bind drift never cause a false mismatch;
        -- other files are md5'd. Returns nil if the slice is empty or a hash is
        -- unavailable, so a failed hash never masquerades as a match.
        local function sliceFingerprint(files)
            local rels = {}
            for rel in pairs(files) do
                if not RECONCILE_SKIP[rel] then rels[#rels + 1] = rel end
            end
            table.sort(rels)
            if #rels == 0 then return nil end

            local parts = {}
            for _, rel in ipairs(rels) do
                local token
                if rel:match("%.json$") then
                    local tbl = readJSON(files[rel])
                    if tbl then
                        if rel == "ms_macros_visual.json" then stripVisualBinds(tbl) end
                        token = "json:" .. canonicalJSON(tbl)
                    end
                end
                if not token then
                    local h = hs.execute("/sbin/md5 -q " .. sq(files[rel]) .. " 2>/dev/null") or ""
                    h = h:gsub("%s+", "")
                    if h == "" then return nil end
                    token = h
                end
                parts[#parts + 1] = rel .. ":" .. token
            end
            return table.concat(parts, "|")
        end

        -- The { rel = abs } map of a stored entry's files.
        local function entryFiles(kind, slug)
            local out = {}
            local filesDir = libraryDir(kind, slug) .. "/files"
            if not hs.fs.attributes(filesDir) then return out end
            local rels = hs.execute(
                "cd " .. sq(filesDir) .. " && find . -type f ! -name '.DS_Store' ! -name '*.bak' 2>/dev/null"
            ) or ""
            for line in rels:gmatch("[^\r\n]+") do
                local rel = line:gsub("^%./", "")
                out[rel] = filesDir .. "/" .. rel
            end
            return out
        end

        -- Point the active marker at whichever stored entry matches the live
        -- slice by content, so themes/sounds flag correctly even when the live
        -- state was set outside the library (theme editor, wholesale profile
        -- switch). If nothing matches, the live state is custom/unsaved and no
        -- entry is claimed. Runs every boot; a handful of md5s over small slices.
        ms.package.reconcileActive = function(kind)
            if not LIBRARY_KINDS[kind] then return end
            local liveFp = sliceFingerprint(ms.package.collect(kind))
            if not liveFp then return end   -- can't fingerprint — leave marker be

            for _, rec in ipairs(ms.package.libraryList(kind)) do
                if sliceFingerprint(entryFiles(kind, rec.slug)) == liveFp then
                    ms.package.librarySetActive(kind, rec.slug)
                    return
                end
            end
            ms.package.librarySetActive(kind, nil)
        end
    -- END Installed Library --

    -- Smoke Test --
        ms.package.selfTest = function()
            local steps = {}
            local function step(name, ok, detail)
                steps[#steps + 1] = {
                    step = name,
                    ok = ok and true or false,
                    detail = detail,
                }
                return ok
            end

            local out = tempDir("selftest") .. "/selftest-theme.mspkg"

            local files, count = ms.package.collect("theme"), 0
            for _ in pairs(files) do count = count + 1 end
            if not step("collect", files["ms_theme.json"] ~= nil,
                        files["ms_theme.json"] and (count .. " files")
                            or "no live ms_theme.json to pack") then
                return {
                    ok = false,
                    steps = steps,
                }
            end

            local manifest, err = ms.package.pack({
                type    = "theme",
                name    = "Self-test Theme",
                version = "0.0.0",
                files   = files,
                out     = out,
            })
            if not step("pack", manifest ~= nil, err or (manifest and manifest.hash)) then
                return {
                    ok = false,
                    steps = steps,
                }
            end

            local report = ms.package.verify(out)
            if not step("verify", report.ok, table.concat(report.issues, "; ")) then
                rmrf(out:match("(.*)/"))
                return {
                    ok = false,
                    steps = steps,
                }
            end

            step("trust", report.trust == "unsigned", "trust = " .. tostring(report.trust))

            local res, ierr = ms.package.install(out, {
                force = true,
                backup = false,
            })
            step("install", res ~= nil, ierr or (res and table.concat(res.installed, ", ")))

            rmrf(out:match("(.*)/"))

            local allOk = true
            for _, s in ipairs(steps) do if not s.ok then allOk = false end end
            return {
                ok = allOk,
                steps = steps,
            }
        end
    -- END Smoke Test --

end

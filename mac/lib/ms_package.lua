-- ms_package (Typed Package Format: .mspkg) --
return function(ms)

    local _home     = os.getenv("HOME")
    local _hsDir    = _home .. "/.hammerspoon"
    local _dataDir  = _hsDir .. "/data"

    local MANIFEST_NAME  = "mspkg.json"
    local FORMAT_VERSION = 1
    local PROFILE_FORMAT = 2

    ms.package = {}

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("\\", "/"):gsub("'", "'\\''") .. "'" end

        local _hashCmd = nil
        local function hashTool()
            if _hashCmd ~= nil then return _hashCmd end
            local out = hs.execute(
                "command -v shasum >/dev/null 2>&1 && printf '%s' 'shasum -a 256' || "
                .. "(command -v sha256sum >/dev/null 2>&1 && printf sha256sum || printf '')"
            )
            out = out and out:gsub("%s+$", "") or ""
            _hashCmd = (out ~= "") and out or false
            return _hashCmd
        end

        local function hashFile(path)
            local tool = hashTool()
            if not tool then return nil end
            local out = hs.execute(tool .. " " .. sq(path) .. " 2>/dev/null")
            if type(out) ~= "string" then return nil end
            local h = out:gsub("^\\", ""):match("^(%x+)")
            return (h and #h >= 64) and h:sub(1, 64):lower() or nil
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

        local function versionParts(v)
            local t = {}
            local base = tostring(v or ""):match("%d+[%d%.]*")
            if base then
                for n in base:gmatch("%d+") do t[#t + 1] = tonumber(n) end
            end
            return t
        end

        local function versionLess(a, b)
            local am, bm = versionParts(a), versionParts(b)
            if #am == 0 or #bm == 0 then return false end
            for i = 1, math.max(#am, #bm) do
                local x, y = am[i] or 0, bm[i] or 0
                if x ~= y then return x < y end
            end
            return false
        end

        local function rmrf(dir)
            if dir and dir:find("mspkg%-") then hs.execute("/bin/rm -rf " .. sq(dir)) end
        end

        local function destFor(clean, profileName)
            if clean:find("^ui/fonts/") or clean:find("^Spoons/") then
                return _hsDir .. "/" .. clean
            end
            return ms.profile.path(ms.profile.relFor(clean), profileName)
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
                    "profile.json",
                    "ms_macros.lua",
                    "data/ms_macros_visual.json",
                    "data/ms_macros_visual.lua",
                    "data/ms_authored.json",
                    "data/ms_authored_menus.json",
                    "data/ms_helpervars.json",
                    "data/ms_settings.json",
                    "data/ms_settings_default.json",
                    "data/ms_theme.json",
                    "sounds/active/",
                    "sounds/macro/",
                    "ui/fonts/",
                    "sound_assign.json",
                },
                legacyPaths = {
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
                    "fonts/",
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
            local tool = hashTool()
            if not tool then return nil end
            local out, ok = hs.execute(
                "cd " .. sq(absDir) .. " && find . -type f ! -name '.DS_Store' " ..
                "! -name '._*' ! -path './__MACOSX/*' " ..
                "-exec " .. tool .. " {} + 2>/dev/null | LC_ALL=C sort -k2 | " .. tool
            )
            if not ok or not out then return nil end
            return out:gsub("^\\", ""):match("^(%x+)")
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

        ms.package.recordContent = function(manifest, id)
            id = (type(id) == "string" and id ~= "" and id)
                or (type(manifest) == "table" and manifest.id) or nil
            if type(manifest) ~= "table" or type(id) ~= "string" or id == "" then
                return false
            end
            local ledger = readContentLedger() or {
                version = 1,
                content = {},
            }
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

        ms.package.listContent = function()
            local ledger = readContentLedger()
            return (ledger and ledger.content) or {}
        end

        local function pathAllowed(kind, rel, formatVersion)
            local spec = TYPE_SPECS[kind]
            if not spec then return false end
            local paths = spec.paths
            if kind == "profile" and (tonumber(formatVersion) or 0) < PROFILE_FORMAT then
                paths = spec.legacyPaths
            end
            for _, prefix in ipairs(paths) do
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

            local rq  = manifest.requires
            local req = (type(rq) == "table" and rq.mudscript)
                     or (type(rq) == "string" and rq)
                     or nil
            if type(req) == "string" and req ~= "" then
                if versionLess(ms.version, req) then
                    warnings[#warnings + 1] =
                        "Needs mudscript " .. req .. ", this install is " .. tostring(ms.version) .. "."
                end
            end

            if ms.plugins and ms.plugins.missingFromManifest then
                local rows = ms.plugins.missingFromManifest(manifest)
                for _, line in ipairs(ms.plugins.depLines(rows)) do
                    warnings[#warnings + 1] = line
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
                elseif not manifest.legacy and not pathAllowed(manifest.type, rel, manifest.formatVersion) then
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
                theme = {
                    files = {},
                    includesSounds = includeSoundsInTheme and true or false,
                },
                sound    = { files = {} },
                macro    = { files = {} },
                settings = { files = {} },
            }
            local function add(t, r) t[#t + 1] = r end
            for _, r in ipairs(relPaths) do
                local f = ms.profile.flatFor(r)
                if f == "ms_theme.json" or r:sub(1, 9) == "ui/fonts/" then add(comp.theme.files, r) end
                if includeSoundsInTheme and isAudioRel(r) then add(comp.theme.files, r) end
                if isAudioRel(r) then add(comp.sound.files, r) end
                if f == "ms_macros.lua" or f == "ms_macros_visual.json"
                    or f == "ms_macros_visual.lua" or f == "ms_authored.json"
                    or f == "ms_helpervars.json"
                    or r:sub(1, 13) == "sounds/macro/" then add(comp.macro.files, r) end
                if f == "ms_settings.json" or f == "ms_settings_default.json" then
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

            local requires = opts.requires
            if kind ~= "plugin" and ms.plugins and ms.plugins.scanFiles then
                local srcs = {}
                for rel, src in pairs(opts.files) do
                    if tostring(rel):match("%.lua$") then srcs[#srcs + 1] = src end
                end
                local ids, seen = {}, {}
                for _, dep in ipairs(ms.plugins.scanFiles(srcs, { all = true })) do
                    if dep.id and dep.id ~= opts.id and not seen[dep.id] then
                        seen[dep.id] = true
                        ids[#ids + 1] = dep.id
                    end
                end
                if #ids > 0 then
                    local base = {}
                    if type(requires) == "table" then
                        for k, v in pairs(requires) do base[k] = v end
                    elseif type(requires) == "string" then
                        base.mudscript = requires
                    end
                    base.plugins = base.plugins or ids
                    requires = base
                end
            end

            local staging = tempDir("pack")
            local manifest = {
                formatVersion = (kind == "profile") and PROFILE_FORMAT or FORMAT_VERSION,
                type          = kind,
                name          = opts.name or "Untitled",
                version       = opts.version or "1.0.0",
                author        = opts.author,
                website       = opts.website,
                description   = opts.description,
                created       = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                platform      = ms.package.fingerprint(),
                requires      = requires,
                contents      = {},
            }

            local staged = 0
            for rel, src in pairs(opts.files) do
                local clean = safeRelPath(rel)
                if not clean then
                    rmrf(staging)
                    return nil, "Unsafe path: " .. tostring(rel)
                end
                if not pathAllowed(kind, clean, (kind == "profile") and PROFILE_FORMAT or FORMAT_VERSION) then
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
                if type(opts.componentNames) == "table" then
                    for k, c in pairs(manifest.components) do
                        local n = opts.componentNames[k]
                        if type(n) == "string" and n ~= "" then c.name = n end
                    end
                end
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
                        local flat = ms.profile.flatFor(rel)
                        files[flat] = abs
                        present[#present + 1] = flat
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
                    local mc = type(manifest.components) == "table" and manifest.components[kind] or nil
                    local cname = (type(mc) == "table" and type(mc.name) == "string" and mc.name ~= "")
                        and mc.name or (base .. " " .. label)
                    local out = outDir .. "/" .. fileBase .. "-" .. kind .. ".mspkg"
                    local m, perr = ms.package.pack({
                        type    = kind,
                        name    = cname,
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
                            name = cname,
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
        local function applyDropped(installed)
            local sawAudio = false

            for _, rel in ipairs(installed) do
                if isAudioRel(rel) then sawAudio = true end
            end

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
                    local dropped = destFor("sound_assign.json")
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
        local function claimSlug(kind, name, owner)
            local base = ms.package.librarySlug(name)
            local taken = {}
            for _, rec in ipairs(ms.package.libraryList(kind)) do
                taken[rec.slug] = rec.owner or false
            end
            local slug, n = base, 1
            while taken[slug] ~= nil and taken[slug] ~= owner do
                n = n + 1
                slug = base .. "-" .. n
            end
            return slug
        end

        local function readJSONFile(path)
            if not path then return nil end
            local raw = readFile(path)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" then return tbl end
            return nil
        end

        local function walkFiles(dir, rel, out)
            for entry in hs.fs.dir(dir) do
                if entry ~= "." and entry ~= ".." and entry ~= ".DS_Store" and entry ~= MANIFEST_NAME
                    and not entry:find("^%._") and entry ~= "__MACOSX" then
                    local abs = dir .. "/" .. entry
                    local r = (rel == "") and entry or (rel .. "/" .. entry)
                    local a = hs.fs.attributes(abs)
                    if a and a.mode == "directory" then
                        walkFiles(abs, r, out)
                    elseif a and a.mode == "file" then
                        out[#out + 1] = r
                    end
                end
            end
            return out
        end

        local function uniqueProfileName(base)
            if not ms.profile.exists(base) then return base end
            local n = 1
            local name
            repeat
                n = n + 1
                name = base .. " " .. n
            until not ms.profile.exists(name)
            return name
        end

        local function packageProfileName(staging, manifest, v2)
            local name
            if v2 then
                local meta = readJSONFile(staging .. "/profile.json")
                name = meta and meta.name
            end
            if type(name) ~= "string" or name == "" then
                local body = readFile(staging .. "/ms_macros.lua")
                if body then name = body:match('macroMeta%s*=%s*{.-name%s*=%s*"([^"]*)"') end
            end
            if type(name) ~= "string" or name == "" then name = manifest.name end
            name = tostring(name or "Imported Profile")
            name = name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
            name = name:gsub("^%.+", "")
            if name == "" then name = "Imported Profile" end
            return name
        end

        local function mergeSoundAssign(dir)
            local assignPath = dir .. "/sound_assign.json"
            local assign = readJSONFile(assignPath)
            if assign then
                local settingsPath = dir .. "/data/ms_settings.json"
                local settings = readJSONFile(settingsPath) or {}
                settings.soundAssign = type(settings.soundAssign) == "table" and settings.soundAssign or {}
                for slot, name in pairs(assign) do
                    if type(slot) == "string" and type(name) == "string" then
                        settings.soundAssign[slot] = name
                    end
                end
                writeFile(settingsPath, hs.json.encode(settings, true))
            end
            os.remove(assignPath)
        end

        local function installFonts(folder)
            local fontsDir = _hsDir .. "/ui/fonts"
            for _, rel in ipairs({
                "ui/fonts",
                "fonts",
            }) do
                local src = folder .. "/" .. rel
                if hs.fs.attributes(src) then
                    hs.execute("mkdir -p " .. sq(fontsDir))
                    for file in hs.fs.dir(src) do
                        if file ~= "." and file ~= ".." and not file:find("^%.") and not hs.fs.attributes(fontsDir .. "/" .. file) then
                            hs.execute("/bin/cp " .. sq(src .. "/" .. file) .. " " .. sq(fontsDir .. "/" .. file))
                        end
                    end
                    hs.execute("/bin/rm -rf " .. sq(src))
                end
            end
        end

        local function profileRoot(staging)
            local function holdsProfile(dir)
                return fileExists(dir .. "/ms_macros.lua")
                    or fileExists(dir .. "/ms_settings.json")
                    or fileExists(dir .. "/data/ms_settings.json")
                    or fileExists(dir .. "/profile.json")
            end
            if holdsProfile(staging) then return staging end
            for entry in hs.fs.dir(staging) do
                if entry ~= "." and entry ~= ".." and entry ~= "__MACOSX" then
                    local sub = staging .. "/" .. entry
                    local a = hs.fs.attributes(sub)
                    if a and a.mode == "directory" and holdsProfile(sub) then return sub end
                end
            end
            return staging
        end

        local function installProfile(stagingRoot, manifest, opts)
            local staging = profileRoot(stagingRoot)
            local v2 = (tonumber(manifest.formatVersion) or 0) >= PROFILE_FORMAT
            local folderName = packageProfileName(staging, manifest, v2)

            local existingMeta = nil
            if type(opts.id) == "string" and opts.id ~= "" then
                for _, candidate in ipairs(ms.profile.list()) do
                    local cm = ms.profile.readMeta(candidate)
                    if cm and cm.origin == "registry" and cm.owner == opts.id then
                        folderName = candidate
                        existingMeta = cm
                        break
                    end
                end
            end
            local updating = existingMeta ~= nil
            if not updating then folderName = uniqueProfileName(folderName) end

            local root = ms.profile.root()
            local building = root .. "/.install-" .. tostring(math.random(100000, 999999))
            hs.execute("/bin/rm -rf " .. sq(building))
            hs.execute("mkdir -p " .. sq(building .. "/data") .. " " .. sq(building .. "/sounds/active")
                .. " " .. sq(building .. "/sounds/macro"))
            if not hs.fs.attributes(building) then
                return nil, "Could not create profile folder."
            end

            local installed = {}
            for _, rel in ipairs(walkFiles(staging, "", {})) do
                local clean = safeRelPath(rel)
                if clean and pathAllowed("profile", clean, v2 and PROFILE_FORMAT or 0) and clean ~= "profile.json" then
                    local target = v2 and clean or ms.profile.relFor(clean)
                    local dest = building .. "/" .. target
                    local destDir = dest:match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                    local _, ok = hs.execute("/bin/cp " .. sq(staging .. "/" .. clean) .. " " .. sq(dest))
                    if ok then installed[#installed + 1] = target end
                end
            end

            if #installed == 0 then
                hs.execute("/bin/rm -rf " .. sq(building))
                return nil, "Nothing could be installed."
            end

            local macroBody = readFile(building .. "/ms_macros.lua")
            if macroBody and ms.auditMacros then
                local errs = ms.auditMacros(macroBody)
                if type(errs) == "table" and #errs > 0 then
                    hs.execute("/bin/rm -rf " .. sq(building))
                    return nil, "Macro security scan failed:\n  - " .. table.concat(errs, "\n  - ")
                end
            end

            mergeSoundAssign(building)
            installFonts(building)

            local packageMeta = v2 and readJSONFile(staging .. "/profile.json") or {}
            local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
            local meta = {
                formatVersion = PROFILE_FORMAT,
                name          = folderName,
                version       = manifest.version or packageMeta.version or "1.0.0",
                author        = manifest.author or packageMeta.author or "",
                created       = (updating and existingMeta.created) or now,
                updated       = now,
                origin        = (type(opts.id) == "string" and opts.id ~= "") and "registry" or "import",
                owner         = (type(opts.id) == "string" and opts.id ~= "") and opts.id or nil,
                requires      = manifest.requires or packageMeta.requires,
            }
            writeFile(building .. "/profile.json", hs.json.encode(meta, true) .. "\n")

            local replacedActive = false
            if updating then
                if ms.backups and ms.backups.snapshot then
                    pcall(ms.backups.snapshot, "pre-update", nil, nil, folderName)
                end
                local oldSettings = ms.profile.path("data/ms_settings.json", folderName)
                if oldSettings and hs.fs.attributes(oldSettings) then
                    hs.execute("/bin/cp " .. sq(oldSettings) .. " " .. sq(building .. "/data/ms_settings.json"))
                end
                local keepDir = (ms.backups and ms.backups.dir and ms.backups.dir("updates") or (_hsDir .. "/backups/updates/"))
                    .. "profile_" .. folderName .. "_" .. os.date("%Y-%m-%d_%H%M%S")
                local final = root .. "/" .. folderName
                if not os.rename(final, keepDir) then
                    hs.execute("/bin/rm -rf " .. sq(building))
                    return nil, "Could not replace the existing profile."
                end
                if not os.rename(building, final) then
                    os.rename(keepDir, final)
                    hs.execute("/bin/rm -rf " .. sq(building))
                    return nil, "Could not replace the existing profile."
                end
                replacedActive = (folderName == ms.profile.active())
            else
                if not os.rename(building, root .. "/" .. folderName) then
                    hs.execute("/bin/rm -rf " .. sq(building))
                    return nil, "Could not create profile folder."
                end
            end

            pcall(function() ms.stampProfileRequires(folderName) end)
            local stamped = ms.profile.readMeta(folderName)
            if stamped and stamped.requires then manifest.requires = stamped.requires end

            if not opts.component then
                pcall(function() ms.package.recordContent(manifest, opts.id) end)
            end
            ms._profilesDirty = true

            return {
                manifest      = manifest,
                installed     = installed,
                failed        = {},
                profile       = folderName,
                updated       = updating,
                updatedActive = replacedActive,
            }
        end

        local function packageFileList(path, manifest)
            local list = {}
            for _, rel in ipairs(ms.package.contents(path)) do
                local clean = safeRelPath(rel)
                if clean and (manifest.legacy or pathAllowed(manifest.type, clean, manifest.formatVersion)) then
                    list[#list + 1] = clean
                end
            end
            return list
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

            if manifest.type == "profile" and not opts.component then
                if not ms.profile.isV2() then
                    rmrf(staging)
                    return nil, "Profiles are still on the old layout. Restart mudscript and try again."
                end
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

            local libKind = opts.component or manifest.type
            local useLibrary = ms.package.isLibraryKind(libKind) and not opts.noLibrary
            local installed, failed = {}, {}
            local libFiles = {}

            for _, clean in ipairs(packageFileList(path, manifest)) do
                if not sliceSet or sliceSet[clean] then
                    if useLibrary then
                        local flat = ms.profile.flatFor(clean)
                        if pathAllowed(libKind, flat) and fileExists(staging .. "/" .. clean) then
                            libFiles[flat] = staging .. "/" .. clean
                        end
                    else
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
            end

            if useLibrary and next(libFiles) then
                local owner = opts.id or ("slice:" .. tostring(manifest.name))
                local okSave, rec = pcall(ms.package.librarySave, libKind, libFiles, {
                    name    = manifest.name,
                    slug    = claimSlug(libKind, manifest.name, owner),
                    owner   = owner,
                    origin  = (opts.component or opts.noRecord) and "profile-slice" or "installed",
                    version = manifest.version,
                })
                if okSave and type(rec) == "table" then
                    if opts.activate ~= false then
                        local act, aerr = ms.package.libraryActivate(libKind, rec.slug)
                        if not act then
                            rmrf(staging)
                            return nil, aerr or "Nothing could be installed."
                        end
                        installed = act.installed
                        failed = act.failed
                    else
                        for flat in pairs(libFiles) do installed[#installed + 1] = flat end
                    end
                end
            end

            rmrf(staging)

            if #installed == 0 then return nil, "Nothing could be installed." end

            if not useLibrary then applyDropped(installed) end

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
                if not opts.component and not opts.noRecord then
                    pcall(function() ms.package.recordContent(manifest, opts.id) end)
                end
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

        ms.package.installSpoonZip = function(path, opts)
            opts = opts or {}
            local entry = type(opts.entry) == "table" and opts.entry or {}

            local hash = hashFile(path)
            if not hash then return nil, "Could not hash the plugin archive." end

            local trust = "unsigned"
            if type(opts.trustLookup) == "function" then
                local ok, level = pcall(opts.trustLookup, hash, { type = "plugin" })
                if ok and type(level) == "string" then trust = level end
            end
            if trust ~= "trusted" and not ms.package.protectionDisabled() then
                return nil,
                    "This plugin is not in the validated library.\n" ..
                    "Plugins run as code, so they cannot be imported one-off."
            end

            local modes = hs.execute("/usr/bin/unzip -Z " .. sq(path) .. " 2>/dev/null") or ""
            for line in modes:gmatch("[^\r\n]+") do
                if line:find("^l") then
                    return nil, "The plugin archive contains links, which are not allowed."
                end
            end

            local listing = hs.execute("/usr/bin/unzip -Z1 " .. sq(path) .. " 2>/dev/null") or ""
            local top = nil
            for line in listing:gmatch("[^\r\n]+") do
                if line:find("^/") or line:find("%.%.") then
                    return nil, "Unsafe path in plugin archive: " .. line
                end
                local base = line:match("([^/]*)/*$")
                if not line:find("^__MACOSX/") and base ~= ".DS_Store" and not base:find("^%._") then
                    local first = line:match("^([^/]+)")
                    if not first then return nil, "Unsafe path in plugin archive: " .. line end
                    if top and top ~= first then
                        return nil, "A plugin archive must hold exactly one .spoon folder."
                    end
                    top = first
                end
            end
            local name = validSpoonName(top)
            if not name then return nil, "The archive does not hold a valid .spoon folder." end

            local staging = tempDir("spoon")
            hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(staging) .. " 2>/dev/null")
            hs.execute("/usr/bin/find " .. sq(staging) .. " \\( -name '.DS_Store' -o -name '._*' \\) -delete 2>/dev/null")
            hs.execute("/bin/rm -rf " .. sq(staging .. "/__MACOSX"))

            local src = staging .. "/" .. name
            local attr = hs.fs.attributes(src)
            if not (attr and attr.mode == "directory") or not fileExists(src .. "/init.lua") then
                rmrf(staging)
                return nil, "The plugin archive has no init.lua."
            end
            local links = hs.execute("/usr/bin/find " .. sq(staging) .. " -type l 2>/dev/null") or ""
            if links:match("%S") then
                rmrf(staging)
                return nil, "The plugin archive contains links, which are not allowed."
            end

            local files = {}
            local found = hs.execute("cd " .. sq(staging) .. " && /usr/bin/find " .. sq(name) .. " -type f 2>/dev/null") or ""
            for rel in found:gmatch("[^\r\n]+") do files[#files + 1] = "Spoons/" .. rel end

            local spoonsDir = _hsDir .. "/Spoons"
            local dest = spoonsDir .. "/" .. name
            hs.execute("mkdir -p " .. sq(spoonsDir))
            local fresh = dest .. ".new"
            hs.execute("/bin/rm -rf " .. sq(fresh))
            local _, copied = hs.execute("/bin/cp -R " .. sq(src) .. " " .. sq(fresh))
            rmrf(staging)
            if not copied or not hs.fs.attributes(fresh) then
                hs.execute("/bin/rm -rf " .. sq(fresh))
                return nil, "Could not copy the plugin into Spoons."
            end
            hs.execute("/bin/rm -rf " .. sq(dest))
            local _, moved = hs.execute("/bin/mv " .. sq(fresh) .. " " .. sq(dest))
            if not moved or not hs.fs.attributes(dest) then
                hs.execute("/bin/rm -rf " .. sq(fresh))
                return nil, "Could not copy the plugin into Spoons."
            end

            local manifest = {
                type        = "plugin",
                name        = entry.name or name:gsub("%.spoon$", ""),
                version     = entry.version,
                author      = entry.author,
                website     = entry.website,
                description = entry.description,
                id          = opts.id or entry.id,
                requires    = entry.requiresPlugins and { plugins = entry.requiresPlugins } or nil,
            }
            pcall(function() ms.package.recordPlugins({ [name] = true }, manifest, manifest.id) end)

            return {
                manifest  = manifest,
                installed = files,
                failed    = {},
                trust     = trust,
                warnings  = {},
            }
        end

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
                if abs and fileExists(abs) then files[rel] = abs end
            end

            local function addDir(relDir, absDir)
                if not absDir or not hs.fs.attributes(absDir) then return end
                for entry in hs.fs.dir(absDir) do
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.")
                        and not entry:find("%.bak") then
                        local abs = absDir .. entry
                        if fileExists(abs) then files[relDir .. entry] = abs end
                    end
                end
            end

            local base = opts and opts.baseDir
            local function flatSrc(rel)
                if base then return base .. "/" .. rel end
                return ms.profile.path(ms.profile.relFor(rel), opts and opts.name)
            end
            local function soundSrc(sub)
                if base then return base .. "/sounds/" .. sub .. "/" end
                return ms.profile.path("sounds/" .. sub .. "/", opts and opts.name)
            end

            if kind == "macro" then
                addIf("ms_macros.lua",         flatSrc("ms_macros.lua"))
                addIf("ms_macros_visual.json", flatSrc("ms_macros_visual.json"))
                addIf("ms_macros_visual.lua",  flatSrc("ms_macros_visual.lua"))
                addIf("ms_authored.json",      flatSrc("ms_authored.json"))
                addIf("ms_helpervars.json",    flatSrc("ms_helpervars.json"))
                addDir("sounds/macro/",        soundSrc("macro"))

            elseif kind == "theme" then
                addIf("ms_theme.json", flatSrc("ms_theme.json"))
                addDir("ui/fonts/",    _hsDir .. "/ui/fonts/")
                if ms.bundleSoundsWithTheme ~= false then
                    addDir("sounds/active/", soundSrc("active"))
                    addDir("sounds/macro/",  soundSrc("macro"))
                    local assign = ms.package.exportSoundAssign()
                    if assign then files["sound_assign.json"] = assign end
                end

            elseif kind == "sound" then
                addDir("sounds/active/", soundSrc("active"))
                addDir("sounds/macro/",  soundSrc("macro"))
                local assign = ms.package.exportSoundAssign()
                if assign then files["sound_assign.json"] = assign end

            elseif kind == "profile" then
                local name = opts and opts.name
                for _, rel in ipairs(ms.profile.CONTENT_FILES) do
                    addIf(rel, ms.profile.path(rel, name))
                end
                addDir("sounds/active/", ms.profile.path("sounds/active/", name))
                addDir("sounds/macro/",  ms.profile.path("sounds/macro/", name))
                addDir("ui/fonts/",      _hsDir .. "/ui/fonts/")
                local assign = nil
                if name == nil or name == "" or name == ms.profile.active() then
                    assign = ms.package.exportSoundAssign()
                else
                    local settings = readJSONFile(ms.profile.path("data/ms_settings.json", name))
                    local named = settings and settings.soundAssign
                    if type(named) == "table" then
                        local tmp = tempDir("assign") .. "/sound_assign.json"
                        if writeFile(tmp, hs.json.encode(named)) then assign = tmp end
                    end
                end
                if assign then files["sound_assign.json"] = assign end
                local meta = ms.profile.readMeta(name)
                if meta then
                    meta.packs = nil
                    meta.owner = nil
                    meta.origin = nil
                    local metaPath = tempDir("meta") .. "/profile.json"
                    if writeFile(metaPath, hs.json.encode(meta, true) .. "\n") then
                        files["profile.json"] = metaPath
                    end
                end
            end

            return files
        end

        ms.package.exportSoundAssign = function()
            local path = tempDir("assign") .. "/sound_assign.json"
            if writeFile(path, hs.json.encode(ms.soundAssign or {})) then return path end
            return nil
        end
    -- END Export Helpers --

    -- Submodules --
        local ctx = {
            dataDir = _dataDir,
            sq = sq,
            fileExists = fileExists,
            readFile = readFile,
            writeFile = writeFile,
            safeRelPath = safeRelPath,
            destFor = destFor,
            pathAllowed = pathAllowed,
            applyDropped = applyDropped,
        }

        package.loaded["lib.package.library"] = nil

        require("lib.package.library")(ms, ctx)
    -- END Submodules --

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

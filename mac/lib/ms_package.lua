-- ms_package (Typed Package Format: .mspkg) --
return function(ms)

    local _home     = os.getenv("HOME")
    local _hsDir    = _home .. "/.hammerspoon"
    local _dataDir  = _hsDir .. "/data"

    local MANIFEST_NAME  = "mspkg.json"
    local FORMAT_VERSION = 1

    ms.package = {}

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("\\", "/"):gsub("'", "'\\''") .. "'" end

        -- Cross-platform sha256 tool: shasum on mac, sha256sum on git-for-Windows
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

        -- Where a packaged relative path lands in the live install
        local function destFor(clean)
            if clean == "ms_macros.lua" then
                return _hsDir .. "/ms_macros.lua"
            elseif clean == "ms_macros_visual.lua" then
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

        -- Record installed non-plugin content, keyed by registry id
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

        -- Installed content records keyed by id, for Browse to flag entries
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
                formatVersion = FORMAT_VERSION,
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
        -- Post-copy side effects shared by install and library activation
        local function applyDropped(installed)
            local sawAudio = false

            for _, rel in ipairs(installed) do
                if isAudioRel(rel) then sawAudio = true end
            end

            -- Recompile a dropped visual-macros source and load it into the sandbox
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
        -- Install a full profile into profiles/<name>/, seed its component packs, and link packs.json
        local function installProfile(staging, manifest, opts)
            -- Profile folder name from macroMeta.name, sanitised filesystem-safe
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

            -- Copy every profile-eligible file from staging into the profile dir
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

            -- Seed each component pack into the library from the staged files
            local pslug = ms.package.librarySlug(folderName)
            local refs  = {}
            for _, kind in ipairs({
                "macro",
                "theme",
                "sound",
            }) do
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

            -- Link the profile to the component packs just seeded (packs.json)
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

            -- A full profile import installs as a first-class profile, not over the live setup
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

            -- Mirror the slice into the installed library so the panels can hotswap it
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
                -- Record the installed version for Update detection
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
                    -- Skip dotfiles and .bak backups
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.")
                        and not entry:find("%.bak") then
                        local abs = absDir .. entry
                        if fileExists(abs) then files[relDir .. entry] = abs end
                    end
                end
            end

            if kind == "macro" then
                -- baseDir collects a pack from an arbitrary folder, for migration
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

    -- Submodules --
        local ctx = {
            hsDir = _hsDir,
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

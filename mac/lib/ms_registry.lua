-- ms_registry (Package Registry Client) --
return function(ms)

    local _home    = os.getenv("HOME")
    local _dataDir = _home .. "/.hammerspoon/data"

    local INDEX_URL     = "https://raw.githubusercontent.com/mudbourn/mudscript/main/registry/index.json"
    local CACHE_PATH    = _dataDir .. "/ms_registry_cache.json"
    local BUNDLED_PATH  = _dataDir .. "/registry_index.json"
    local FORMAT_VERSION = 1
    local CACHE_TTL      = 6 * 60 * 60

    local PUBLIC_KEY = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
]]

    ms.registry = ms.registry or {}

    local function emptyIndex()
        return {
            formatVersion = FORMAT_VERSION,
            generated = nil,
            entries = {},
        }
    end

    local _index     = emptyIndex()
    local _byId      = {}
    local _byHash    = {}
    local _signed    = false
    local _fetchedAt = nil
    local _source    = "none"
    local _error     = nil
    local _loading   = false

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

        local function readFile(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local body = f:read("*all")
            f:close()
            return body
        end

        -- _dataDir is created once, lazily, by the only writer that targets it
        -- (persist -> CACHE_PATH). writeFile itself must NOT shell out: it is also
        -- used for the verify temp files under TMPDIR (which always exists), and on
        -- Windows every hs.execute is a ~140ms cmd->sh spawn -- 3 of those per verify
        -- purely to mkdir a dir that already exists was a large chunk of the Browse
        -- stall. Mac's popen made it free, so this was Windows-only.
        local _dataDirEnsured = false
        local function ensureDataDir()
            if _dataDirEnsured then return end
            hs.execute("mkdir -p " .. sq(_dataDir))
            _dataDirEnsured = true
        end

        local function writeFile(path, body)
            -- Binary mode: on Windows LuaJIT's text-mode "w" rewrites every \n to
            -- \r\n. The signature message is `canon .. "\n"`, so a text-mode write
            -- makes openssl hash `canon\r\n` while the signer (jq) hashed `canon\n`
            -- -- every verify then fails and the whole library shows empty. mac's
            -- "w" never translates, which is why this was Windows-only. "wb" keeps
            -- bare \n on both platforms (same reason hs/execute.lua writes "wb").
            local f = io.open(path, "wb")
            if not f then return false end
            f:write(body)
            f:close()
            return true
        end

        local function tmpPath(tag)
            local base = os.getenv("TMPDIR") or "/tmp/"
            if not base:find("/$") then base = base .. "/" end
            return base .. "msreg-" .. tag .. "-" .. tostring(math.random(100000, 999999))
        end

        local function isHash(s)
            return type(s) == "string" and #s == 64 and s:match("^%x+$") ~= nil
        end

        local ALLOWED_HOSTS = {
            ["github.com"]                    = true,
            ["objects.githubusercontent.com"] = true,
            ["raw.githubusercontent.com"]     = true,
            ["api.github.com"]                = true,
        }

        local function urlAllowed(url)
            if type(url) ~= "string" then return false end
            local host = url:match("^https://([^/]+)/")
            if not host then return false end
            host = host:gsub(":%d+$", ""):lower()
            return ALLOWED_HOSTS[host] == true
        end
    -- END Helpers --

    -- Signature --
        -- Rebuild the exact bytes the registry signer hashed and verify the RSA
        -- signature with openssl. The signer runs `jq -c -S '{formatVersion,
        -- generated, entries}'` (see bin/registry_sign.sh); that canonical form
        -- -- compact, recursively key-sorted, raw UTF-8, forward slashes NOT
        -- escaped, integers with no fractional part, plus jq's trailing newline.
        -- hs.json.encode CANNOT reproduce it: NSJSONSerialization (which backs it)
        -- neither sorts keys nor leaves slashes unescaped (it emits `https:\/\/`),
        -- so every byte comparison failed and served an EMPTY registry (no browse,
        -- no installs). canonicalJSON() below rebuilds the jq -c -S bytes in pure
        -- Lua, which also keeps the `jq` dependency out of the client (it is absent
        -- on Windows and off Hammerspoon's PATH on macOS).
        -- openssl (on PATH here and on macOS) does the base64 decode
        -- and the verify, so no platform-specific base64 flags (-D vs -d, the
        -- macOS-only -i/-o) are needed either.
        -- openssl drives signature verification; the Windows POSIX-shell path cannot
        -- reach it (the same gap that makes the Guardian inert -- shasum/openssl are not
        -- on that shell's PATH). Probe once so we can (a) skip a pointless verify that
        -- would just fail, and (b) let loadLocal trust the shipped bundled index when the
        -- tool is missing rather than reject it and leave the whole library empty.
        local _opensslChecked, _opensslOK = false, false
        local function opensslAvailable()
            if not _opensslChecked then
                _opensslChecked = true
                -- macOS ships LibreSSL as /usr/bin/openssl (what hs.execute
                -- resolves), whose `openssl version` prints "LibreSSL x.y.z" --
                -- NOT "OpenSSL". Matching only "OpenSSL" made the probe report
                -- unavailable, so verifySignature bailed and every strict adopt
                -- failed with "Index signature did not verify" -> empty library.
                -- LibreSSL provides the same `base64`/`dgst -verify` CLI we use
                -- (confirmed verifying the live signature), so accept both.
                local out, ok = hs.execute("openssl version 2>/dev/null")
                _opensslOK = (ok and type(out) == "string"
                    and (out:find("OpenSSL") ~= nil
                        or out:find("LibreSSL") ~= nil)) or false
            end
            return _opensslOK
        end

        -- Canonical JSON identical to `jq -c -S`, byte-for-byte: object keys sorted
        -- by codepoint (Lua's default string compare is a byte compare, which equals
        -- codepoint order for UTF-8), no insignificant whitespace, forward slashes
        -- left unescaped, integers printed without a decimal point, and UTF-8 passed
        -- through verbatim (jq -c is not --ascii-output). This is the byte sequence
        -- the signer hashed; hs.json.encode is not a substitute (see the note above).
        local function canonEscape(s)
            return (s:gsub('[%z\1-\31\\"]', function(c)
                local b = string.byte(c)
                if     c == '"'  then return '\\"'
                elseif c == '\\' then return '\\\\'
                elseif b == 8    then return '\\b'
                elseif b == 9    then return '\\t'
                elseif b == 10   then return '\\n'
                elseif b == 12   then return '\\f'
                elseif b == 13   then return '\\r'
                else                  return string.format('\\u%04x', b) end
            end))
        end

        local function canonNumber(n)
            if n ~= n or n == math.huge or n == -math.huge then return "null" end
            if n == math.floor(n) and math.abs(n) < 1e15 then
                return string.format("%.0f", n)   -- integer, no fractional part
            end
            return string.format("%.17g", n)
        end

        local function canonicalJSON(v)
            local t = type(v)
            if t == "string" then
                return '"' .. canonEscape(v) .. '"'
            elseif t == "number" then
                return canonNumber(v)
            elseif t == "boolean" then
                return v and "true" or "false"
            elseif t == "table" then
                local n = #v
                -- Positive array length => JSON array. Empty tables serialise as
                -- an object ({}); the signed index carries no empty arrays, so the
                -- object/array ambiguity of an empty Lua table never bites.
                if n > 0 then
                    local parts = {}
                    for i = 1, n do parts[i] = canonicalJSON(v[i]) end
                    return "[" .. table.concat(parts, ",") .. "]"
                end
                local keys = {}
                for k in pairs(v) do keys[#keys + 1] = k end
                table.sort(keys)
                local parts = {}
                for _, k in ipairs(keys) do
                    parts[#parts + 1] = '"' .. canonEscape(k) .. '":' .. canonicalJSON(v[k])
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
            return "null"   -- nil / hs.json null sentinel / unsupported
        end

        local function verifySignature(doc)
            if type(doc) ~= "table" then return false end
            if type(doc.signature) ~= "string" or doc.signature == "" then
                return false
            end
            -- Cannot verify without openssl; report unverified (loadLocal decides whether
            -- a given source is trusted enough to adopt anyway).
            if not opensslAvailable() then return false end

            local payload = {
                formatVersion = doc.formatVersion,
                generated     = doc.generated,
                entries       = doc.entries,
            }
            local okEncode, canon = pcall(canonicalJSON, payload)
            if not okEncode or type(canon) ~= "string" or canon == "" then
                return false
            end
            local minified = canon .. "\n"   -- jq's CLI trailing newline is part of the signed bytes

            local keyPath = tmpPath("pub")
            local sigB64  = tmpPath("sig") .. ".b64"
            local sigPath = tmpPath("sig")
            local msgPath = tmpPath("msg")

            writeFile(keyPath, PUBLIC_KEY)
            writeFile(sigB64, doc.signature)
            writeFile(msgPath, minified)

            -- Decode the base64 signature with openssl (identical on every
            -- platform) rather than base64(1), whose decode flag differs by OS.
            -- -A reads the blob as a single line.
            hs.execute("openssl base64 -d -A -in " .. sq(sigB64) ..
                " -out " .. sq(sigPath) .. " 2>/dev/null")
            os.remove(sigB64)

            local out, ok = hs.execute(
                "openssl dgst -sha256 -verify " .. sq(keyPath) ..
                " -signature " .. sq(sigPath) ..
                " " .. sq(msgPath) .. " 2>&1"
            )

            os.remove(keyPath)
            os.remove(sigPath)
            os.remove(msgPath)

            return (ok and out and out:find("Verified OK") ~= nil) or false
        end
    -- END Signature --

    -- Parse --
        local function normalise(raw, i)
            local function bad(why)
                return nil, "entry #" .. tostring(i) .. " (" ..
                    (type(raw) == "table" and tostring(raw.id) or "?") .. "): " .. why
            end
            if type(raw) ~= "table" then return bad("not an object") end
            if type(raw.id) ~= "string" or raw.id == "" then return bad("missing id") end
            if not isHash(raw.sha256) then return bad("sha256 is not 64 hex characters") end
            if not ms.package.spec(raw.type) then return bad("unknown type " .. tostring(raw.type)) end
            if raw.url ~= nil and not urlAllowed(raw.url) then return bad("download URL not permitted") end

            return {
                id          = raw.id,
                type        = raw.type,
                name        = type(raw.name) == "string" and raw.name or raw.id,
                version     = type(raw.version) == "string" and raw.version or "",
                author      = type(raw.author) == "string" and raw.author or "",
                description = type(raw.description) == "string" and raw.description or "",
                website     = type(raw.website) == "string" and raw.website or "",
                sha256      = raw.sha256:lower(),
                url         = raw.url,
                size        = tonumber(raw.size) or nil,
                requires    = type(raw.requires) == "string" and raw.requires or nil,
                components  = type(raw.components) == "table" and raw.components or nil,
                trust       = raw.trust == "trusted" and "trusted" or "community",
            }
        end

        local function adopt(doc, source, requireSignature)
            if type(doc) ~= "table" or type(doc.entries) ~= "table" then
                return false, "Malformed index."
            end
            if doc.formatVersion and tonumber(doc.formatVersion) ~= FORMAT_VERSION then
                return false, "Unsupported index format: " .. tostring(doc.formatVersion)
            end

            local signed, sigReason = verifySignature(doc)
            if requireSignature and not signed then
                return false, sigReason or "Index signature did not verify."
            end

            local entries, byId, byHash = {}, {}, {}
            for i, raw in ipairs(doc.entries) do
                local e, why = normalise(raw, i)
                if not e then return false, why end
                if byId[e.id] then
                    return false, "entry #" .. i .. ": duplicate id " .. e.id
                end
                if byHash[e.sha256] then
                    return false, "entry #" .. i .. ": duplicate sha256 for " .. e.id
                end
                entries[#entries + 1] = e
                byId[e.id]            = e
                byHash[e.sha256]      = e
            end

            _index = {
                formatVersion = FORMAT_VERSION,
                generated     = doc.generated,
                entries       = entries,
            }
            _byId      = byId
            _byHash    = byHash
            _signed    = signed
            _source    = source
            _fetchedAt = tonumber(doc._fetchedAt) or os.time()
            return true
        end

        local function decode(body)
            if type(body) ~= "string" or body == "" then return nil end
            local ok, doc = pcall(hs.json.decode, body)
            if not ok or type(doc) ~= "table" then return nil end
            return doc
        end
    -- END Parse --

    -- Load --
        local function loadLocal()
            local cached = decode(readFile(CACHE_PATH))
            if cached and adopt(cached, "cache", true) then return true end

            -- The bundled index ships INSIDE the deployed app tree, so it inherits the
            -- same trust as the Lua code that reads it; its signature is a defence-in-
            -- depth check against on-disk tampering. That check needs openssl, which the
            -- Windows shell path cannot reach -- and requiring it there rejected the
            -- shipped index and left Browse showing "no packages". So require the
            -- signature only when we can actually verify it; otherwise trust the local
            -- shipped file. Network indexes (adopt below in refresh) stay strict, since
            -- those are untrusted regardless of tooling.
            local bundled = decode(readFile(BUNDLED_PATH))
            if bundled then
                local ok, why = adopt(bundled, "bundled", opensslAvailable())
                if ok then return true end
                -- Surfaced so a still-empty library after this fix names its cause
                -- (e.g. a signature that verifies-and-fails while openssl IS present,
                -- which would point at a canonical-JSON byte mismatch, not tooling).
                print("[ms.registry] bundled index rejected (openssl="
                    .. tostring(opensslAvailable()) .. "): " .. tostring(why))
            elseif not bundled then
                print("[ms.registry] bundled index unreadable at " .. tostring(BUNDLED_PATH))
            end

            return false
        end

        local function persist(doc)
            doc._fetchedAt = os.time()
            local ok, body = pcall(hs.json.encode, doc)
            if ok and body then ensureDataDir(); writeFile(CACHE_PATH, body) end
        end
    -- END Load --

    -- Public: refresh --
        ms.registry.refresh = function(opts, cb)
            if type(opts) == "function" then opts, cb = {}, opts end
            opts = opts or {}
            local done = function(ok, err)
                _loading = false
                if type(cb) == "function" then pcall(cb, ok, err) end
            end

            if _loading then
                if type(cb) == "function" then pcall(cb, false, "Refresh already in progress.") end
                return
            end

            if not opts.force and _fetchedAt and (os.time() - _fetchedAt) < CACHE_TTL then
                if type(cb) == "function" then pcall(cb, true, nil) end
                return
            end

            _loading = true
            hs.http.asyncGet(INDEX_URL, nil, function(code, body, _)
                if code ~= 200 then
                    _error = "Could not reach the registry (HTTP " .. tostring(code) .. ")."
                    if #_index.entries == 0 then loadLocal() end
                    return done(false, _error)
                end

                local doc = decode(body)
                if not doc then
                    _error = "Registry index was not readable JSON."
                    return done(false, _error)
                end

                local ok, err = adopt(doc, "network", true)
                if not ok then
                    _error = err
                    return done(false, err)
                end

                _error = nil
                persist(doc)
                done(true, nil)
            end)
        end
    -- END refresh --

    -- Public: read --
        ms.registry.list = function(opts)
            opts = opts or {}
            local q = type(opts.query) == "string" and opts.query:lower() or nil
            local out = {}
            for _, e in ipairs(_index.entries) do
                local keep = true
                if opts.type and e.type ~= opts.type then keep = false end
                if keep and q and q ~= "" then
                    keep = (e.name:lower():find(q, 1, true) ~= nil)
                        or (e.author:lower():find(q, 1, true) ~= nil)
                        or (e.description:lower():find(q, 1, true) ~= nil)
                end
                if keep then out[#out + 1] = e end
            end
            return out
        end

        ms.registry.get = function(id) return type(id) == "string" and _byId[id] or nil end

        ms.registry.find = function(hash)
            if not isHash(hash) then return nil end
            return _byHash[hash:lower()]
        end

        ms.registry.trustLookup = function(hash, manifest)
            if not _signed then return "unsigned" end
            local entry = ms.registry.find(hash)
            if not entry then return "unsigned" end

            if type(manifest) == "table" and manifest.type and manifest.type ~= entry.type then
                return "unsigned"
            end

            return entry.trust
        end

        ms.registry.status = function()
            return {
                state     = _loading and "loading" or (#_index.entries > 0 and "ready" or "empty"),
                count     = #_index.entries,
                signed    = _signed,
                source    = _source,
                generated = _index.generated,
                fetchedAt = _fetchedAt,
                error     = _error,
            }
        end
    -- END read --

    -- Public: download --
        ms.registry.download = function(idOrEntry, cb)
            local done = function(path, err)
                if type(cb) == "function" then pcall(cb, path, err) end
            end

            local entry = type(idOrEntry) == "table" and idOrEntry or ms.registry.get(idOrEntry)
            if not entry then return done(nil, "No such package in the registry.") end
            if not urlAllowed(entry.url) then
                return done(nil, "Package download location is not permitted.")
            end

            -- Download with curl via hs.task, NOT hs.http.asyncGet. asyncGet
            -- returns the body as a Lua string through a lossy NSData->string
            -- conversion that corrupts non-UTF8 bytes, so a .mspkg (a zip) comes
            -- out with a different hash than the registry's — every binary
            -- download "fails the hash" and updates never take. curl writes the
            -- exact bytes; -L follows GitHub's release-asset redirect, and args
            -- are passed as an array (no shell), so the URL needs no escaping.
            local path = tmpPath("dl") .. ".mspkg"
            local args = {
                "-sSL", "--fail", "--max-time", "120", "-o", path, entry.url,
            }
            local task = hs.task.new("/usr/bin/curl", function(code, _, stderr)
                if code ~= 0 then
                    os.remove(path)
                    return done(nil, "Download failed (curl exit "
                        .. tostring(code) .. ").")
                end

                local out = hs.execute("shasum -a 256 " .. sq(path) .. " 2>/dev/null")
                local got = (out and #out >= 64) and out:sub(1, 64):lower() or nil
                if got ~= entry.sha256 then
                    os.remove(path)
                    return done(nil, "Downloaded package did not match the registry hash.")
                end

                done(path, nil)
            end, args)

            if not task or not task:start() then
                os.remove(path)
                return done(nil, "Could not start the download.")
            end
        end
    -- END download --

    -- Boot --
        loadLocal()
    -- END Boot --

end

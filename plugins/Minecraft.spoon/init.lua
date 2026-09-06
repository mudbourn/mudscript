--- === Minecraft ===
--- Minecraft target + live client data via the ms-mc-bridge mod (loopback
--- WebSocket).

local obj = {}
obj.__index = obj

obj.name    = "Minecraft"
obj.version = "0.1.0"
obj.author  = "mudbourn"
obj.license = "MIT"

-- Config --
    local WS_URL    = "ws://127.0.0.1:47600"
    local SUBSCRIBE = {
        "health",
        "hunger",
        "armor",
        "heldItem",
        "context",
    }
-- END Config --

function obj:init()

    -- Target App --
        ms.setTargetApp("Minecraft")
    -- END Target App --

    local state = {
        ws        = nil,
        cache     = {},
        pending   = {},
        nextId    = 0,
        connected = false,
    }

    -- Connection --
        local function onMessage(event, message)
            if event == "open" then
                state.connected = true
                pcall(function()
                    state.ws:send(hs.json.encode({
                        q      = "subscribe",
                        topics = SUBSCRIBE,
                    }))
                end)
            elseif event == "closed" or event == "fail" then
                state.connected = false
            elseif event == "received" and type(message) == "string" then
                local ok, decoded = pcall(hs.json.decode, message)
                if not ok or type(decoded) ~= "table" then return end
                if decoded.push then
                    state.cache[decoded.push] = decoded.data
                elseif decoded.id ~= nil then
                    state.pending[decoded.id] = decoded.data or {}
                elseif decoded.q and decoded.data then
                    state.cache[decoded.q] = decoded.data
                end
            end
        end

        local function connect()
            if state.ws then return end
            local ok, ws = pcall(function() return hs.websocket.new(WS_URL, onMessage) end)
            if ok then state.ws = ws end
        end

        connect()
    -- END Connection --

    -- Query API (ms.mc) --
        ms.mc = {}

        ms.mc.cached = function(topic) return state.cache[topic] end

        ms.mc.isConnected = function() return state.connected == true end

        ms.mc.query = function(q, timeoutMs)
            if not state.connected or not state.ws then
                return state.cache[q]
            end
            local _co, isMain = coroutine.running()
            if isMain then return state.cache[q] end
            timeoutMs = timeoutMs or 300
            state.nextId = state.nextId + 1
            local id = state.nextId
            pcall(function()
                state.ws:send(hs.json.encode({
                    q  = q,
                    id = id,
                }))
            end)

            local waited = 0
            while state.pending[id] == nil and waited < timeoutMs do
                ms.wait(5)
                waited = waited + 5
            end
            local data = state.pending[id]
            state.pending[id] = nil
            if data ~= nil then state.cache[q] = data end
            return data
        end

        local function read(q)
            local _co, isMain = coroutine.running()
            if not isMain then
                local ok, v = pcall(ms.mc.query, q)
                if ok and v ~= nil then return v end
            end
            return state.cache[q]
        end

        ms.mc.health = function()
            local d = read("health")
            return d and d.health
        end

        ms.mc.maxHealth = function()
            local d = read("health")
            return d and d.maxHealth
        end

        ms.mc.hunger = function()
            local d = read("hunger")
            return d and d.food
        end

        ms.mc.heldItem  = function() return read("heldItem") end
        ms.mc.armor     = function() return read("armor") end
        ms.mc.position  = function() return read("position") end
        ms.mc.target    = function() return read("target") end
        ms.mc.options   = function() return read("options") end

        ms.mc.durabilityPct = function(slot)
            slot = slot or "main"
            local d
            if slot == "main" then d = read("heldItem")
            elseif slot == "off" then d = ms.mc.query("offhand")
            else
                local a = read("armor")
                d = a and a[slot]
            end
            return d and d.durabilityPct
        end

        ms.mc.hasItem = function(id)
            local inv = ms.mc.query("inventory")
            if not (inv and inv.items) then return false end
            for _, it in ipairs(inv.items) do
                if it.id == id then return true end
            end
            return false
        end

        ms.mc.countItem = function(id)
            local inv = ms.mc.query("inventory")
            if not (inv and inv.items) then return 0 end
            local n = 0
            for _, it in ipairs(inv.items) do
                if it.id == id then n = n + (it.count or 0) end
            end
            return n
        end
    -- END Query API --

    -- Status Action --
        ms.settings.define({
            type    = "action",
            key     = "mcStatus",
            label   = "Minecraft Bridge Status",
            section = "minecraft",
            onAction = function()
                if ms.mc.isConnected() then
                    local h = state.cache.health
                    ms.alert(string.format("Bridge connected. Health: %s",
                        h and tostring(h.health) or "?"), 4)
                else
                    ms.alert("Bridge not connected. Is the ms-mc-bridge mod running?", 4)
                end
            end,
        })
    -- END Status Action --

    -- Builder Tools --
        if ms.tools and ms.tools.define then
            ms.tools.define({
                id   = "mc.health",
                name = "MC: Health",
                run  = function() return ms.mc.health() end,
            })

            ms.tools.define({
                id   = "mc.hunger",
                name = "MC: Hunger",
                run  = function() return ms.mc.hunger() end,
            })

            ms.tools.define({
                id   = "mc.mainDurability",
                name = "MC: Main-hand Durability %",
                run  = function() return ms.mc.durabilityPct("main") end,
            })
        end
    -- END Builder Tools --

    self._state = state
    return self
end

function obj:stop()
    if self._state and self._state.ws then
        pcall(function() self._state.ws:close() end)
        self._state.ws = nil
    end
    if ms._targetApp == "Minecraft" then
        pcall(function() ms.setTargetApp(nil) end)
    end
    ms.mc = nil
    return self
end

return obj

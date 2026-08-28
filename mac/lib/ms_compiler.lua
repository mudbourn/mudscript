-- ms_compiler (Visual Macro Compiler) --
    return function(ms)

        local home       = os.getenv("HOME")
        local dataDir    = home .. "/.hammerspoon/data"
        local jsonPath   = dataDir .. "/ms_macros_visual.json"
        local luaPath    = dataDir .. "/ms_macros_visual.lua"

        ms.compiler = {}

        -- Broken-macro quarantine --
            -- A macro whose emitted body fails to compile is not dropped from
            -- the generated file (which would take the WHOLE chunk down on load,
            -- unregistering every visual macro at once and blanking their
            -- binds). Instead rebuild emits a call to this helper, which
            -- registers the macro normally — so it keeps its list slot and key
            -- bind — with a body that surfaces the compile error when run. The
            -- failure stays isolated to the one broken macro and is visible
            -- instead of silent.
            ms._brokenMacro = function(spec)
                spec = type(spec) == "table" and spec or {}
                local id = spec.id
                if type(id) ~= "string" then return end
                local label  = spec.name or id
                local errMsg = spec.err or "unknown compile error"
                local fn = ms.fn(function()
                    ms.alert("Macro '" .. label .. "' has a build error and "
                        .. "can't run. Open the builder to fix it.", 4)
                    error("[ms.compiler] macro '" .. id
                        .. "' failed to compile: " .. errMsg, 0)
                end, label)
                local opts = { group = spec.group or "visual", label = label }
                if spec.cooldown then opts.cooldown = spec.cooldown end
                local b = spec.bind
                if type(b) == "table" and (b.type or b.key) then
                    opts.default = {
                        type = b.type or "key",
                        mods = b.mods or {},
                        key  = b.key,
                    }
                end
                ms.bind.define(id, fn, opts)
            end
        -- END Broken-macro quarantine --

        -- Helpers --
            local function toolRef(val)
                if type(val) ~= "table" then return nil end
                -- A setting binding: Value->Tool wired to an authored setting.
                if type(val.__toolRef) == "string"
                    and val.__toolRef:match("^[%a_][%w_]*$") then
                    return 'ms.settings.get("' .. val.__toolRef .. '")'
                end
                -- A helper-var binding: Value->Tool wired to a declared, disk-
                -- persistent shared variable. Read live so several macros see
                -- the same value; distinct tag from settings so the two pools
                -- never collide.
                if type(val.__varRef) == "string"
                    and val.__varRef:match("^[%a_][%w_]*$") then
                    return 'ms.vars.get("' .. val.__varRef .. '")'
                end
                return nil
            end

            -- Expand {name} tokens in a string literal into live helper-var
            -- reads, emitting a Lua concatenation. A string with no valid token
            -- returns a plain quoted literal unchanged, so existing macros (and
            -- text that merely contains braces, e.g. NBT like {Health:20}) are
            -- untouched. `{{` / `}}` escape literal braces inside an interpolated
            -- string. Reads are coerced with tostring(x or "") so numeric or
            -- unset vars concatenate cleanly instead of erroring.
            local function interpString(s)
                if not s:match("{[%a_][%w_]*}") then
                    return string.format("%q", s)
                end
                local parts, lit = {}, {}
                local function flushLit()
                    if #lit > 0 then
                        parts[#parts + 1] = string.format("%q", table.concat(lit))
                        lit = {}
                    end
                end
                local i, n = 1, #s
                while i <= n do
                    local c = s:sub(i, i)
                    if c == "{" and s:sub(i + 1, i + 1) == "{" then
                        lit[#lit + 1] = "{"; i = i + 2
                    elseif c == "}" and s:sub(i + 1, i + 1) == "}" then
                        lit[#lit + 1] = "}"; i = i + 2
                    elseif c == "{" then
                        local close = s:find("}", i + 1, true)
                        local name = close and s:sub(i + 1, close - 1) or nil
                        if name and name:match("^[%a_][%w_]*$") then
                            flushLit()
                            parts[#parts + 1] = 'tostring(ms.vars.get("' .. name .. '") or "")'
                            i = close + 1
                        else
                            lit[#lit + 1] = "{"; i = i + 1
                        end
                    else
                        lit[#lit + 1] = c; i = i + 1
                    end
                end
                flushLit()
                if #parts == 0 then return '""' end
                if #parts == 1 then return parts[1] end
                return "(" .. table.concat(parts, " .. ") .. ")"
            end

            local function serialize(val)
                local ref = toolRef(val)
                -- A wired var/setting value used as string text may itself embed
                -- {name} tokens; expand them at runtime. (Numeric contexts go
                -- through numArg, which stays bare, and conditions resolve the
                -- ref directly — so this only affects value/text fields.)
                if ref then return "ms.interp(" .. ref .. ")" end
                local t = type(val)
                if t == "string"  then return interpString(val) end
                if t == "number"  then return tostring(val) end
                if t == "boolean" then return tostring(val) end
                if t == "nil"     then return "nil" end
                if t == "table" then
                    local parts = {}
                    local isList = (#val > 0)
                    if isList then
                        for _, v in ipairs(val) do
                            parts[#parts + 1] = serialize(v)
                        end
                    else
                        for k, v in pairs(val) do
                            local key
                            if type(k) == "string" and k:match("^%a[%w_]*$") then
                                key = k
                            else
                                key = "[" .. serialize(k) .. "]"
                            end
                            parts[#parts + 1] = key .. " = " .. serialize(v)
                        end
                    end
                    return "{" .. table.concat(parts, ", ") .. "}"
                end
                return tostring(val)
            end

            local function ident(v, default)
                if v == nil or v == "" then return default end
                return v
            end

            local function numArg(v, default)
                local ref = toolRef(v)
                if ref then return ref end
                if type(v) == "number" then return tostring(v) end
                if type(v) == "string" and v ~= "" and tonumber(v) then return v end
                return tostring(default)
            end

            local function buildArgs(params, argOrder)
                if not params or not argOrder then return "" end
                local parts = {}
                for _, key in ipairs(argOrder) do
                    local v = params[key]
                    if v ~= nil then
                        parts[#parts + 1] = serialize(v)
                    end
                end
                return table.concat(parts, ", ")
            end
        -- END Helpers --

        -- Emitters --
            local INDENT = "    "

            local function indent(n)
                local s = ""
                for _ = 1, n do s = s .. INDENT end
                return s
            end

            local emitStep

            local emitters = {}

            emitters["ms.type"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.type(" .. args .. ")"
            end

            emitters["ms.wait"] = function(step, lvl)
                local p = step.params or {}
                return indent(lvl) .. "ms.wait(" .. numArg(p.ms, 100) .. ")"
            end

            emitters["ms.copy"] = function(step, lvl)
                local text = (step.params and step.params.text) or ""
                return indent(lvl) .. "ms.copy(" .. serialize(text) .. ")"
            end

            emitters["ms.paste"] = function(step, lvl)
                return indent(lvl) .. "ms.paste()"
            end

            emitters["ms.press"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.press(" .. args .. ")"
            end

            emitters["ms.hold"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.hold(" .. args .. ")"
            end

            emitters["ms.release"] = function(step, lvl)
                local key = (step.params and step.params.key) or ""
                return indent(lvl) .. "ms.release(" .. serialize(key) .. ")"
            end

            emitters["ms.cam"] = function(step, lvl)
                local p = step.params or {}
                return indent(lvl) .. "ms.cam(" .. numArg(p.dx, 0) .. ", " .. numArg(p.dy, 0) .. ")"
            end

            emitters["ms.cam.rebalance"] = function(step, lvl)
                return indent(lvl) .. "ms.cam.rebalance()"
            end

            emitters["ms.cam.reset"] = function(step, lvl)
                return indent(lvl) .. "ms.cam.reset()"
            end

            emitters["ms.scroll"] = function(step, lvl)
                local p = step.params or {}
                local dir = serialize(p.direction or "up")
                if toolRef(p.clicks) then
                    return indent(lvl) .. "ms.scroll(" .. dir .. ", " .. numArg(p.clicks, 1) .. ")"
                end
                if p.clicks and p.clicks > 1 then
                    return indent(lvl) .. "ms.scroll(" .. dir .. ", " .. tostring(p.clicks) .. ")"
                end
                return indent(lvl) .. "ms.scroll(" .. dir .. ")"
            end

            emitters["ms.alert"] = function(step, lvl)
                local p = step.params or {}
                local args = serialize(p.message or p.msg or "")
                if p.duration then args = args .. ", " .. tostring(p.duration) end
                return indent(lvl) .. "ms.alert(" .. args .. ")"
            end

            emitters["ms.Mouse"] = function(step, lvl)
                local p = step.params or {}
                local parts = {}
                parts[#parts + 1] = serialize(p.operation or "Click")
                parts[#parts + 1] = serialize(p.button or "Left")
                parts[#parts + 1] = serialize(p.reference or "Mouse")
                if p.unscaled == true then
                    parts[#parts + 1] = "true"
                end
                local x1 = p.x1 ~= nil and p.x1 or p.x
                local y1 = p.y1 ~= nil and p.y1 or p.y
                parts[#parts + 1] = numArg(x1, 0)
                parts[#parts + 1] = numArg(y1, 0)
                local op = tostring(p.operation or ""):lower()
                if op == "drag" or p.x2 ~= nil or p.y2 ~= nil then
                    parts[#parts + 1] = numArg(p.x2, 0)
                    parts[#parts + 1] = numArg(p.y2, 0)
                end
                return indent(lvl) .. "ms.Mouse(" .. table.concat(parts, ", ") .. ")"
            end

            emitters["ms.moveMouse"] = function(step, lvl)
                local p = step.params or {}
                local x   = numArg(p.x, 0)
                local y   = numArg(p.y, 0)
                local ref = serialize(p.ref or p.reference or "Absolute")
                local dur = numArg(p.durationMs, 200)
                return indent(lvl) .. "ms.moveMouse("
                    .. x .. ", " .. y .. ", " .. ref .. ", " .. dur .. ")"
            end

            emitters["ms.dragPath"] = function(step, lvl)
                local p = step.params or {}
                local pts   = serialize(p.points or "")
                local btn   = serialize(p.button or "Left")
                local ref   = serialize(p.ref or p.reference or "Absolute")
                local delay = numArg(p.delayMs, 10)
                return indent(lvl) .. "ms.dragPath("
                    .. pts .. ", " .. btn .. ", " .. ref .. ", " .. delay .. ")"
            end

            emitters["var_set"] = function(step, lvl)
                local p = step.params or {}
                local value = serialize(p.value)
                -- A valid identifier is hoisted (see tempVarDecl), so assign to
                -- it — declaring `local` here would shadow the hoisted var and
                -- strand its value in this block. Fall back to a local only for
                -- names that couldn't be hoisted.
                if type(p.name) == "string" and p.name:match("^[%a_][%w_]*$") then
                    return indent(lvl) .. p.name .. " = " .. value
                end
                return indent(lvl) .. "local " .. ident(p.name, "v") .. " = " .. value
            end

            -- Call a function tool (an authored, reusable ms.fn) by name. The
            -- name is identifier-validated so nothing can break out of the
            -- string literal; an empty/invalid name emits an inert comment.
            emitters["call_fn"] = function(step, lvl)
                local p = step.params or {}
                local name = type(p.name) == "string"
                    and p.name:match("^[%a_][%w_]*$") or nil
                if not name then
                    return indent(lvl) .. "-- call function (unresolved reference)"
                end
                return indent(lvl) .. 'ms.callFn("' .. name .. '")'
            end

            -- Write a declared helper var (disk-persistent, shared across
            -- macros). Reads are done by binding a Value field to the var
            -- (see toolRef); this is the explicit write side.
            emitters["hvar_set"] = function(step, lvl)
                local p = step.params or {}
                local name = type(p.name) == "string"
                    and p.name:match("^[%a_][%w_]*$") or nil
                if not name then
                    return indent(lvl) .. "-- set helper var (unresolved reference)"
                end
                return indent(lvl) .. 'ms.vars.set("' .. name .. '", '
                    .. serialize(p.value) .. ")"
            end

            -- Switch to another profile by name. The name is an arbitrary
            -- folder string (may contain spaces), so it's a quoted literal via
            -- serialize, not an identifier.
            emitters["ms.switchProfile"] = function(step, lvl)
                local p = step.params or {}
                return indent(lvl) .. "ms.switchProfile(" .. serialize(p.name or "") .. ")"
            end

            -- Activate an installed library pack (macro / theme / sound slice)
            -- by slug. kind is constrained to the known slices; slug is a
            -- quoted literal.
            emitters["switch_pack"] = function(step, lvl)
                local p = step.params or {}
                local kind = tostring(p.kind or "macro")
                if kind ~= "macro" and kind ~= "theme" and kind ~= "sound" then
                    kind = "macro"
                end
                return indent(lvl) .. 'ms.package.libraryActivate("' .. kind
                    .. '", ' .. serialize(p.slug or "") .. ")"
            end

            emitters["var_add"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " + " .. numArg(p.amount, 1)
            end

            emitters["var_sub"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " - " .. numArg(p.amount, 1)
            end

            emitters["var_mul"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " * " .. numArg(p.amount, 2)
            end

            local _flowCounter = 0

            -- Ongoing inter-step delay set by an action_delay step. See
            local _actionDelay = 0
            local _CONTAINER = {
                ["if"]     = true,
                ["for"]    = true,
                ["while"]  = true,
                ["repeat"] = true,
            }

            -- In an expression context (if/while conditions) a {name} token is
            -- the variable's live value, so it expands to a bare `ms.vars.get`
            -- call — no quoting/tostring like the string-literal case. Keeps the
            -- {name} UI convention uniform across every field the user types in.
            local function interpExpr(s)
                return (s:gsub("{([%a_][%w_]*)}", 'ms.vars.get("%1")'))
            end

            local function stepCond(step)
                local c = step.condition
                if c == nil then c = step.params and step.params.condition end
                -- A condition wired to a tool/var arrives as a {__toolRef} /
                -- {__varRef} table. Resolve it to the live read expression
                -- (ms.settings.get / ms.vars.get) instead of interpolating a
                -- string — otherwise the branch silently compiles to `true`.
                local ref = toolRef(c)
                if ref then return ref end
                if type(c) == "table" then c = nil end
                if c == nil or c == "" then c = "true" end
                return interpExpr(c)
            end

            local function thenSteps(step) return step["then"] or step.then_steps end
            local function elseSteps(step) return step["else"] or step.else_steps end

            -- Local ("temp") variables are declared per-step by var_set, which
            -- would scope them to the block they sit in — so a var_add in a
            -- sibling/outer block, or a read before the first set, would hit a
            -- global nil and blow up (nil arithmetic). Collect every temp-var
            -- name up front (recursing into if/for/while/repeat bodies) so the
            -- compiler can hoist a single function-scoped declaration; var_set
            -- then assigns instead of re-declaring. Only valid Lua identifiers
            -- are hoisted; anything else falls back to a local at its use site.
            local VAR_ACTIONS = {
                var_set = true, var_add = true, var_sub = true, var_mul = true,
            }
            local function collectTempVars(steps, seen, order)
                if type(steps) ~= "table" then return end
                for _, step in ipairs(steps) do
                    if VAR_ACTIONS[step.action] then
                        local nm = step.params and step.params.name
                        if type(nm) == "string" and nm:match("^[%a_][%w_]*$")
                            and not seen[nm] then
                            seen[nm] = true
                            order[#order + 1] = nm
                        end
                    end
                    collectTempVars(thenSteps(step), seen, order)
                    collectTempVars(elseSteps(step), seen, order)
                    collectTempVars(step.body, seen, order)
                end
            end

            -- The hoisted declaration line, or nil when the macro uses no temp
            -- vars. Every var starts at 0 so a var_add before any var_set still
            -- does arithmetic instead of erroring; a var_set overwrites it.
            local function tempVarDecl(steps)
                local seen, order = {}, {}
                collectTempVars(steps, seen, order)
                if #order == 0 then return nil end
                local zeros = {}
                for i = 1, #order do zeros[i] = "0" end
                return indent(1) .. "local " .. table.concat(order, ", ")
                    .. " = " .. table.concat(zeros, ", ")
            end

            emitters["if"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                lines[#lines + 1] = indent(lvl) .. "if " .. cond .. " then"
                lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', true)"
                local ts = thenSteps(step)
                if ts then
                    for _, s in ipairs(ts) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                local es = elseSteps(step)
                if es and #es > 0 then
                    lines[#lines + 1] = indent(lvl) .. "else"
                    lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', false)"
                    for _, s in ipairs(es) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                return table.concat(lines, "\n")
            end

            emitters["for"] = function(step, lvl)
                local p = step.params or {}
                local varName = ident(p.var, "i")
                local from    = p.from or 1
                local to      = p.to or 1
                local stepVal = p.step
                local lines = {}
                local forArgs = tostring(from) .. ", " .. tostring(to)
                if stepVal then forArgs = forArgs .. ", " .. tostring(stepVal) end
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "for " .. varName .. " = " .. forArgs .. " do"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                lines[#lines + 1] = indent(lvl) .. "ms.log('for', '" .. varName .. "=" .. forArgs .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["while"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "while " .. cond .. " do"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                lines[#lines + 1] = indent(lvl) .. "ms.log('while', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["repeat"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "repeat"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "until " .. cond
                lines[#lines + 1] = indent(lvl) .. "ms.log('repeat', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["comment"] = function(step, lvl)
                local text = (step.params and step.params.text) or ""
                return indent(lvl) .. "-- " .. text
            end

            emitters["code"] = function(step, lvl)
                local src = (step.params and step.params.source) or ""
                local lines = {}
                for line in src:gmatch("([^\n]*)\n?") do
                    if line ~= "" then
                        lines[#lines + 1] = indent(lvl) .. line
                    end
                end
                return table.concat(lines, "\n")
            end

            emitters["setting"] = function(step, lvl)
                local p = step.params or {}
                local key = type(p.key) == "string"
                    and p.key:match("^[%a_][%w_]*$") or nil
                if not key then
                    return indent(lvl) .. "-- setting (unresolved reference)"
                end
                local label = type(p.label) == "string"
                    and p.label:gsub("[\r\n]", " ") or key
                return indent(lvl) .. '-- setting "' .. label
                    .. '" (shared, read via ms.settings.get("' .. key .. '"))'
            end

            local function genericEmitter(step, lvl)
                local action = step.action
                local p = step.params or {}
                if p.args then
                    local parts = {}
                    for _, v in ipairs(p.args) do
                        parts[#parts + 1] = serialize(v)
                    end
                    return indent(lvl) .. action .. "(" .. table.concat(parts, ", ") .. ")"
                end
                local parts = {}
                for k, v in pairs(p) do
                    parts[#parts + 1] = k .. "=" .. serialize(v)
                end
                if #parts == 0 then
                    return indent(lvl) .. action .. "()"
                end
                return indent(lvl) .. action .. "(" .. serialize(p) .. ")"
            end

            -- Sets _actionDelay and emits only a marker comment.
            emitters["action_delay"] = function(step, lvl)
                local p = step.params or {}
                local n = tonumber(p.delayMs) or 0
                if n < 0 then n = 0 end
                _actionDelay = math.floor(n)
                return indent(lvl) .. "-- action delay: " .. _actionDelay
                    .. "ms between steps"
            end

            emitStep = function(step, lvl)
                lvl = lvl or 1
                local action = step.action
                if not action then return indent(lvl) .. "-- [empty step]" end
                local emitter = emitters[action]
                local line = emitter and emitter(step, lvl) or genericEmitter(step, lvl)
                -- Append the ongoing action delay after leaf steps.
                if _actionDelay > 0 and action ~= "action_delay"
                    and not _CONTAINER[action] then
                    line = line .. "\n" .. indent(lvl)
                        .. "ms.wait(" .. _actionDelay .. ")"
                end
                return line
            end
        -- END Emitters --

        -- Compile --
            ms.compiler.compile = function(macroDef)
                assert(type(macroDef) == "table", "ms.compiler.compile: macroDef must be a table")
                assert(type(macroDef.id) == "string", "ms.compiler.compile: macroDef.id must be a string")

                local id     = macroDef.id
                local name   = macroDef.name or id
                local author = macroDef.author or "Visual"
                local group  = macroDef.group or "visual"
                local steps  = macroDef.steps or {}
                local bind   = macroDef.bind or {}
                local cooldown = macroDef.cooldown

                assert(id:match("^[%a_][%w_]*$"),
                    "ms.compiler.compile: invalid macro id '" .. id .. "' (must be a valid Lua identifier)")

                local fnName = id .. "Function"
                local lines = {}

                lines[#lines + 1] = "local " .. fnName .. " = ms.fn(function()"
                lines[#lines + 1] = indent(1) .. "local t = 100"
                local tvDecl = tempVarDecl(steps)
                if tvDecl then lines[#lines + 1] = tvDecl end
                _actionDelay = 0   -- never leak a delay between macros
                for _, step in ipairs(steps) do
                    lines[#lines + 1] = emitStep(step, 1)
                end
                lines[#lines + 1] = 'end, "' .. name .. '")'
                lines[#lines + 1] = ""

                lines[#lines + 1] = 'ms.bind.define("' .. id .. '", ' .. fnName .. ", {"
                lines[#lines + 1] = indent(1) .. 'group   = "' .. group .. '",'
                lines[#lines + 1] = indent(1) .. 'label   = "' .. name .. '",'
                if cooldown then
                    lines[#lines + 1] = indent(1) .. "cooldown = " .. tostring(cooldown) .. ","
                end
                if bind.type or bind.key then
                    lines[#lines + 1] = indent(1) .. "default = {"
                    lines[#lines + 1] = indent(2) .. 'type = "' .. (bind.type or "key") .. '",'
                    if bind.mods and #bind.mods > 0 then
                        local modParts = {}
                        for _, m in ipairs(bind.mods) do modParts[#modParts + 1] = '"' .. m .. '"' end
                        lines[#lines + 1] = indent(2) .. "mods = {" .. table.concat(modParts, ", ") .. "},"
                    else
                        lines[#lines + 1] = indent(2) .. "mods = {},"
                    end
                    if bind.key then
                        lines[#lines + 1] = indent(2) .. 'key  = "' .. bind.key .. '",'
                    end
                    lines[#lines + 1] = indent(1) .. "},"
                end
                lines[#lines + 1] = "})"

                return table.concat(lines, "\n")
            end

            -- Compile a function tool: a named, reusable ms.fn registered so
            -- any macro can invoke it with ms.callFn("id"). Reuses the exact
            -- step emitters the macro compiler uses, so a function tool is
            -- authored on the same canvas and behaves identically at runtime.
            ms.compiler.compileFunction = function(fnDef)
                assert(type(fnDef) == "table", "ms.compiler.compileFunction: fnDef must be a table")
                assert(type(fnDef.id) == "string", "ms.compiler.compileFunction: fnDef.id must be a string")
                assert(fnDef.id:match("^[%a_][%w_]*$"),
                    "ms.compiler.compileFunction: invalid id '" .. fnDef.id .. "'")

                local id    = fnDef.id
                local label = fnDef.name or id
                local steps = fnDef.steps or {}
                local fnName = id .. "Tool"
                local lines = {}

                -- coroutine=false makes ms.fn return the raw function, so the
                -- tool runs inline in its caller's coroutine; otherwise it is
                -- wrapped to run in its own (async). Legacy defs (nil) stay
                -- wrapped, preserving how they already behave.
                local asCoroutine = fnDef.coroutine ~= false
                local secondArg = asCoroutine
                    and ('"' .. label:gsub('[\r\n"]', " ") .. '"')
                    or "false"

                lines[#lines + 1] = "local " .. fnName .. " = ms.fn(function()"
                lines[#lines + 1] = indent(1) .. "local t = 100"
                local tvDecl = tempVarDecl(steps)
                if tvDecl then lines[#lines + 1] = tvDecl end
                _actionDelay = 0
                for _, step in ipairs(steps) do
                    lines[#lines + 1] = emitStep(step, 1)
                end
                lines[#lines + 1] = "end, " .. secondArg .. ")"
                lines[#lines + 1] = ""
                lines[#lines + 1] = 'ms.fn.define("' .. id .. '", ' .. fnName .. ", {"
                lines[#lines + 1] = indent(1) .. 'group = "tool",'
                lines[#lines + 1] = indent(1) .. 'label = "' .. label:gsub('[\r\n"]', " ") .. '",'
                lines[#lines + 1] = "})"

                return table.concat(lines, "\n")
            end
        -- END Compile --

        -- Write File --
            local function luaStr(v)
                if type(v) ~= "string" then return '""' end
                return string.format("%q", v)
            end

            -- Does this emitted source parse as valid Lua? compile() can happily
            -- return syntactically broken text (a raw `code` step or a hand-typed
            -- condition passes straight through), and the whole generated file is
            -- loaded as ONE chunk — so a single bad macro would fail the load and
            -- unregister every visual macro. Parse each macro on its own first so
            -- the damage can be contained. Returns nil on success, else the error.
            local function syntaxError(src)
                if type(src) ~= "string" then return "compiler returned non-string" end
                -- Mirror the load() path used elsewhere here: LuaJIT reports
                -- _VERSION "Lua 5.1" and keeps loadstring, so prefer it and only
                -- fall back to 5.2+ load(). Parsing alone — undefined globals in
                -- the source don't matter since we never execute the chunk.
                local chunk, err
                if loadstring then
                    chunk, err = loadstring(src, "ms_macro_check")
                else
                    chunk, err = load(src, "@ms_macro_check", "t")
                end
                if chunk then return nil end
                return tostring(err)
            end

            -- Source for a quarantined macro: registers it via ms._brokenMacro so
            -- it keeps its list slot and bind but reports the compile error when
            -- run. All interpolated values go through luaStr, so an error string
            -- full of quotes/newlines can't itself produce broken source.
            local function brokenMacroSource(macroDef, errMsg)
                local b = macroDef.bind
                local bindLit = "nil"
                if type(b) == "table" and (b.type or b.key) then
                    local mods = {}
                    for _, m in ipairs(b.mods or {}) do mods[#mods + 1] = luaStr(m) end
                    bindLit = "{ type = " .. luaStr(b.type or "key")
                        .. ", key = " .. (b.key and luaStr(b.key) or "nil")
                        .. ", mods = { " .. table.concat(mods, ", ") .. " } }"
                end
                return "ms._brokenMacro({\n"
                    .. "    id    = " .. luaStr(macroDef.id) .. ",\n"
                    .. "    name  = " .. luaStr(macroDef.name or macroDef.id) .. ",\n"
                    .. "    group = " .. luaStr(macroDef.group or "visual") .. ",\n"
                    .. "    err   = " .. luaStr(errMsg) .. ",\n"
                    .. "    bind  = " .. bindLit .. ",\n"
                    .. "})"
            end

            ms.compiler._writeFile = function(sources, meta)
                meta = type(meta) == "table" and meta or {}
                local lines = {}
                lines[#lines + 1] = "-- AUTO-GENERATED by ms.compiler (DO NOT EDIT BY HAND) --"
                lines[#lines + 1] = "-- Source: data/ms_macros_visual.json"
                lines[#lines + 1] = "-- Rebuild: ms.compiler.rebuild()"
                lines[#lines + 1] = "-- END AUTO-GENERATED --"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "-- Creator Credits --"
                lines[#lines + 1] = "    ms.macroMeta = {"
                lines[#lines + 1] = "        name    = " .. luaStr(meta.name    or "Visual Macros") .. ","
                lines[#lines + 1] = "        version = " .. luaStr(meta.version or "1.0.0") .. ","
                lines[#lines + 1] = "        author  = " .. luaStr(meta.author  or "ms.compiler") .. ","
                lines[#lines + 1] = "        website = " .. luaStr(meta.website or "") .. ","
                lines[#lines + 1] = "    }"
                lines[#lines + 1] = "-- END Creator Credits --"
                lines[#lines + 1] = ""

                -- Indent the body one level inside its fold markers, matching
                -- the Creator Credits block, so each section collapses cleanly
                -- in Zed. Blank lines stay bare (no trailing whitespace).
                local function indentBlock(src)
                    local out = {}
                    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                        out[#out + 1] = line == "" and "" or (INDENT .. line)
                    end
                    return table.concat(out, "\n")
                end

                for _, entry in ipairs(sources) do
                    lines[#lines + 1] = "-- " .. entry.id .. " --"
                    lines[#lines + 1] = indentBlock(entry.source)
                    lines[#lines + 1] = "-- END " .. entry.id .. " --"
                    lines[#lines + 1] = ""
                end

                local out = table.concat(lines, "\n") .. "\n"

                os.execute("mkdir -p '" .. dataDir .. "'")

                local f = io.open(luaPath, "w")
                if not f then
                    error("ms.compiler: cannot open " .. luaPath .. " for writing")
                end
                f:write(out)
                f:close()

                return true
            end
        -- END Write File --

        -- Rebuild --
            ms.compiler.rebuild = function()
                local f = io.open(jsonPath, "r")
                if not f then
                    error("ms.compiler.rebuild: cannot open " .. jsonPath)
                end
                local raw = f:read("*all")
                f:close()

                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" then
                    error("ms.compiler.rebuild: invalid JSON in " .. jsonPath .. ": " .. tostring(data))
                end

                -- Compile errors from this pass, keyed by macro id. saveMacro
                -- reads this right after rebuild() to tell the builder a save
                -- produced a broken macro instead of silently succeeding.
                ms.compiler._errors = {}

                local macros = data.macros or {}
                local sources = {}
                local count = 0

                for id, macroDef in pairs(macros) do
                    macroDef.id = id
                    local srcOk, src = pcall(ms.compiler.compile, macroDef)
                    -- Two failure modes: the emitter itself throws (srcOk false),
                    -- or it returns text that does not parse (syntaxError). Either
                    -- way, quarantine the macro so its bad Lua can't sink the
                    -- whole file's load.
                    local errMsg
                    if not srcOk then
                        errMsg = tostring(src)
                    else
                        errMsg = syntaxError(src)
                    end
                    if errMsg then
                        print("ms.compiler: compile error for '" .. id .. "': " .. errMsg)
                        ms.compiler._errors[id] = errMsg
                        src = brokenMacroSource(macroDef, errMsg)
                    end
                    sources[#sources + 1] = {
                        id     = id,
                        source = src,
                    }
                    count = count + 1
                end

                -- Function tools compile ahead of the macros so a macro that
                -- calls one finds it already defined in the same chunk.
                local functions = data.functions or {}
                local fnSources = {}
                local fnCount = 0
                for id, fnDef in pairs(functions) do
                    fnDef.id = id
                    local okF, srcF = pcall(ms.compiler.compileFunction, fnDef)
                    local fnErr
                    if not okF then
                        fnErr = tostring(srcF)
                    else
                        fnErr = syntaxError(srcF)
                    end
                    if fnErr then
                        print("ms.compiler: function compile error for '" .. id .. "': " .. fnErr)
                        ms.compiler._errors["fn:" .. id] = fnErr
                        -- A comment is valid Lua, so it keeps the file loadable.
                        -- Any macro that calls this tool hits a nil at runtime
                        -- (isolated) instead of failing the whole load.
                        srcF = "-- [FUNCTION COMPILE ERROR for " .. id .. "]\n"
                            .. "-- " .. fnErr:gsub("\n", "\n-- ") .. "\n"
                    end
                    fnSources[#fnSources + 1] = { id = "fn:" .. id, source = srcF }
                    fnCount = fnCount + 1
                end
                table.sort(fnSources, function(a, b) return a.id < b.id end)

                table.sort(sources, function(a, b) return a.id < b.id end)

                local allSources = {}
                for _, s in ipairs(fnSources) do allSources[#allSources + 1] = s end
                for _, s in ipairs(sources)   do allSources[#allSources + 1] = s end
                ms.compiler._writeFile(allSources, data.meta)

                print("ms.compiler.rebuild: compiled " .. count .. " macro(s), "
                    .. fnCount .. " function tool(s) -> " .. luaPath)
                return count
            end
        -- END Rebuild --

        -- Load --
            ms.compiler.load = function()
                local prev = ms.compiler._registeredIds
                if prev then
                    for id in pairs(prev) do
                        if ms.registry then
                            ms.registry._defs[id] = nil
                            for i = #ms.registry._defList, 1, -1 do
                                if ms.registry._defList[i] == id then
                                    table.remove(ms.registry._defList, i)
                                end
                            end
                        end
                        if ms.bind and ms.bind._wires then ms.bind._wires[id] = nil end
                    end
                    ms.compiler._registeredIds = nil
                end

                -- Function tools register into ms.fn.registry, not ms.registry,
                -- so clear the previous batch there too or the second load
                -- trips ms.fn.define's "already registered" assert.
                local prevFn = ms.compiler._registeredFnIds
                if prevFn and ms.fn and ms.fn.registry then
                    for id in pairs(prevFn) do
                        ms.fn.registry._defs[id] = nil
                        for i = #ms.fn.registry._defList, 1, -1 do
                            if ms.fn.registry._defList[i] == id then
                                table.remove(ms.fn.registry._defList, i)
                            end
                        end
                    end
                    ms.compiler._registeredFnIds = nil
                end
                local _fnBefore = {}
                if ms.fn and ms.fn.registry then
                    for _, id in ipairs(ms.fn.registry._defList) do _fnBefore[id] = true end
                end

                if not hs.fs.attributes(luaPath) then
                    print("ms.compiler.load: no compiled file at " .. luaPath .. " (skipping)")
                    return false
                end

                local f = io.open(luaPath, "r")
                if not f then
                    print("ms.compiler.load: cannot open " .. luaPath)
                    return false
                end
                local rawSrc = f:read("*all")
                f:close()

                if ms.auditMacros then
                    local auditErrs = ms.auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        local msg = "ms_macros_visual.lua failed security audit ("
                            .. #auditErrs .. " violation"
                            .. (#auditErrs > 1 and "s" or "") .. "):\n"
                        for _, e in ipairs(auditErrs) do
                            msg = msg .. "  - " .. e .. "\n"
                        end
                        print(msg)
                        ms.alert("Visual macros audit failed. See console.", 6)
                        return false
                    end
                end

                local sandbox = ms._macroSandbox
                if not sandbox then
                    error("ms.compiler.load: macro sandbox not initialized")
                end

                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    chunk, loadErr = load(rawSrc, "@ms_macros_visual.lua", "bt", sandbox)
                else
                    chunk, loadErr = loadstring(rawSrc, "@ms_macros_visual.lua")
                    if chunk then setfenv(chunk, sandbox) end
                end
                if not chunk then
                    print("ms.compiler.load: failed to load: " .. tostring(loadErr))
                    ms.alert("Visual macros load error. See console.", 6)
                    return false
                end

                ms._macroMetaLocked = ms._macroMetaFromHand == true
                local ok, runErr = pcall(chunk)
                ms._macroMetaLocked = false
                if not ok then
                    print("ms.compiler.load: execution error: " .. tostring(runErr))
                    ms.alert("Visual macros runtime error. See console.", 6)
                    return false
                end

                local reg = {}
                for _, id in ipairs(ms.compiler.list()) do reg[id] = true end
                ms.compiler._registeredIds = reg

                -- Any ms.fn ids that appeared during this load are function
                -- tools we own; remember them so the next load can clear them.
                local fnReg = {}
                if ms.fn and ms.fn.registry then
                    for _, id in ipairs(ms.fn.registry._defList) do
                        if not _fnBefore[id] then fnReg[id] = true end
                    end
                end
                ms.compiler._registeredFnIds = fnReg

                print("ms.compiler.load: visual macros loaded into sandbox")
                return true
            end
        -- END Load --

        -- Test Run --
            ms.compiler.testRun = function(macroDef, onDone)
                local reported = false
                local function done(ok, err)
                    if reported then return end
                    reported = true
                    if onDone then pcall(onDone, ok and true or false, err) end
                    return ok, err
                end

                if type(macroDef) ~= "table" then return done(false, "no macro definition") end
                local steps = macroDef.steps or {}
                local lines = { "return function()", indent(1) .. "local t = 100" }
                for _, step in ipairs(steps) do
                    local okc, line = pcall(emitStep, step, 1)
                    if not okc then return done(false, "compile error: " .. tostring(line)) end
                    lines[#lines + 1] = line
                end
                lines[#lines + 1] = "end"
                local src = table.concat(lines, "\n")

                if ms.auditMacros then
                    local errs = ms.auditMacros(src)
                    if errs and #errs > 0 then
                        return done(false, "audit failed: " .. tostring(errs[1]))
                    end
                end

                local sandbox = ms._macroSandbox
                if not sandbox then return done(false, "macro sandbox not initialized") end

                local chunk, loadErr = load(src, "@ms_test_run", "bt", sandbox)
                if not chunk then return done(false, "load: " .. tostring(loadErr)) end
                local ok, fnOrErr = pcall(chunk)
                if not ok then return done(false, tostring(fnOrErr)) end
                local fn = fnOrErr
                if type(fn) ~= "function" then return done(false, "compiled body is not a function") end

                local ctx = {
                    cancelled = false,
                    paused = false,
                    callStack = { "test:" .. (macroDef.id or "macro") },
                }
                local co = coroutine.create(function()
                    local rok, rerr = xpcall(fn, debug.traceback)
                    done(rok, rok and nil or rerr)
                end)
                if ms._coroContext then ms._coroContext[co] = ctx end
                if ms._activeContexts then ms._activeContexts[ctx] = true end

                local resok, reserr = coroutine.resume(co)
                if not resok then
                    return done(false, tostring(reserr))
                end
            end
        -- END Test Run --

        -- Write --
            ms.compiler.write = function(macroId, macroDef)
                assert(type(macroId) == "string", "ms.compiler.write: macroId must be a string")
                assert(type(macroDef) == "table",  "ms.compiler.write: macroDef must be a table")

                macroDef.id = macroId

                local data = { macros = {} }
                local f = io.open(jsonPath, "r")
                if f then
                    local raw = f:read("*all")
                    f:close()
                    local ok, parsed = pcall(hs.json.decode, raw)
                    if ok and type(parsed) == "table" then
                        data = parsed
                        data.macros = data.macros or {}
                    end
                end

                -- Preserve the macro's key bind across a builder save. The
                -- builder canvas has no bind editor, so macroDef.bind arrives
                -- nil; writing it blindly would strip a bind the user set via the
                -- rebind UI (which lives in ms.bindConfig / ms_settings.json, not
                -- in this JSON) or one previously baked here. Fall back to the
                -- live bindConfig entry — folded to the stored { type,key,mods }
                -- shape the compiler emits as a `default` bind — then to the
                -- existing JSON entry. This both prevents the clobber AND bakes
                -- the current bind in, so it travels with the pack and survives
                -- profile switches instead of being settings-only.
                local bind = macroDef.bind
                if bind == nil then
                    local cfg = ms.bindConfig and ms.bindConfig[macroId]
                    if type(cfg) == "table"
                        and (cfg.type == nil or cfg.type == "key") and cfg.key ~= nil then
                        local mods = {}
                        for _, m in ipairs(cfg.mods or {}) do mods[#mods + 1] = m end
                        bind = { type = "key", key = cfg.key, mods = mods }
                    elseif type(data.macros[macroId]) == "table" then
                        bind = data.macros[macroId].bind
                    end
                end

                data.macros[macroId] = {
                    name     = macroDef.name,
                    author   = macroDef.author,
                    group    = macroDef.group,
                    bind     = bind,
                    steps    = macroDef.steps,
                    cooldown = macroDef.cooldown,
                }

                os.execute("mkdir -p '" .. dataDir .. "'")
                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler.write: cannot open " .. jsonPath .. " for writing")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()

                ms.compiler.rebuild()

                print("ms.compiler.write: saved '" .. macroId .. "' to JSON and recompiled")
                return true
            end
        -- END Write --

        -- Delete --
            ms.compiler.delete = function(macroId)
                assert(type(macroId) == "string", "ms.compiler.delete: macroId must be a string")

                local f = io.open(jsonPath, "r")
                if not f then
                    print("ms.compiler.delete: no JSON file found")
                    return false
                end
                local raw = f:read("*all")
                f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" then
                    error("ms.compiler.delete: invalid JSON")
                end

                data.macros = data.macros or {}
                if not data.macros[macroId] then
                    print("ms.compiler.delete: macro '" .. macroId .. "' not found")
                    return false
                end

                local deleted = data.macros[macroId]
                data.macros[macroId] = nil

                local pb = deleted and deleted.bind
                local pbType = (type(pb) == "table") and pb.type or nil
                local isConcrete = pbType == "key" or pbType == "mouse"
                    or pbType == "scroll" or pbType == "gamepad" or pbType == "combo"
                if isConcrete then
                    for _, def in pairs(data.macros) do
                        local b = def.bind
                        if type(b) == "table" and b.type == macroId then
                            local mods, seen = {}, {}
                            for _, mm in ipairs(pb.mods or {}) do
                                if not seen[mm] then
                                    seen[mm] = true
                                    mods[#mods + 1] = mm
                                end
                            end
                            for _, mm in ipairs(b.mods or {}) do
                                if not seen[mm] then
                                    seen[mm] = true
                                    mods[#mods + 1] = mm
                                end
                            end
                            def.bind = {
                                type      = pb.type,
                                key       = pb.key,
                                button    = pb.button,
                                direction = pb.direction,
                                keys      = pb.keys,
                                mods      = mods,
                            }
                        end
                    end
                end

                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler.delete: cannot write JSON")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()

                ms.compiler.rebuild()
                print("ms.compiler.delete: removed '" .. macroId .. "' and recompiled")
                return true
            end
        -- END Delete --

        -- List --
            ms.compiler.list = function()
                local f = io.open(jsonPath, "r")
                if not f then return {} end
                local raw = f:read("*all")
                f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                    return {}
                end
                local ids = {}
                for id in pairs(data.macros) do ids[#ids + 1] = id end
                table.sort(ids)
                return ids
            end
        -- END List --

        -- Get --
            ms.compiler.get = function(macroId)
                local f = io.open(jsonPath, "r")
                if not f then return nil end
                local raw = f:read("*all")
                f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                    return nil
                end
                local def = data.macros[macroId]
                if def then def.id = macroId end
                return def
            end
        -- END Get --

        -- Function tools (data.functions) --
            local function readData()
                local data = {}
                local f = io.open(jsonPath, "r")
                if f then
                    local raw = f:read("*all")
                    f:close()
                    local ok, parsed = pcall(hs.json.decode, raw)
                    if ok and type(parsed) == "table" then data = parsed end
                end
                data.macros    = data.macros    or {}
                data.functions = data.functions or {}
                return data
            end

            local function writeData(data)
                os.execute("mkdir -p '" .. dataDir .. "'")
                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler: cannot open " .. jsonPath .. " for writing")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()
            end

            ms.compiler.writeFunction = function(fnId, fnDef)
                assert(type(fnId) == "string" and fnId:match("^[%a_][%w_]*$"),
                    "ms.compiler.writeFunction: fnId must be a valid identifier")
                assert(type(fnDef) == "table", "ms.compiler.writeFunction: fnDef must be a table")
                if ms.compiler.get(fnId) then
                    error("ms.compiler.writeFunction: '" .. fnId
                        .. "' collides with a macro of the same id")
                end
                local data = readData()
                data.functions[fnId] = {
                    name      = fnDef.name,
                    steps     = fnDef.steps,
                    coroutine = fnDef.coroutine == true,
                }
                writeData(data)
                ms.compiler.rebuild()
                pcall(ms.compiler.load)
                print("ms.compiler.writeFunction: saved '" .. fnId .. "' and recompiled")
                return true
            end

            ms.compiler.deleteFunction = function(fnId)
                assert(type(fnId) == "string", "ms.compiler.deleteFunction: fnId must be a string")
                local data = readData()
                if not data.functions[fnId] then
                    print("ms.compiler.deleteFunction: '" .. fnId .. "' not found")
                    return false
                end
                data.functions[fnId] = nil
                writeData(data)
                ms.compiler.rebuild()
                pcall(ms.compiler.load)
                print("ms.compiler.deleteFunction: removed '" .. fnId .. "'")
                return true
            end

            ms.compiler.listFunctions = function()
                local data = readData()
                local out = {}
                for id, def in pairs(data.functions) do
                    out[#out + 1] = { id = id, name = def.name or id }
                end
                table.sort(out, function(a, b) return a.id < b.id end)
                return out
            end

            ms.compiler.getFunction = function(fnId)
                local data = readData()
                local def = data.functions[fnId]
                if def then def.id = fnId end
                return def
            end
        -- END Function tools --

        -- Meta (pack credits: name / author / website) --
            ms.compiler.getMeta = function()
                if ms._macroMetaFromHand and type(ms.macroMeta) == "table" then
                    return {
                        name    = ms.macroMeta.name    or "",
                        version = ms.macroMeta.version or "",
                        author  = ms.macroMeta.author  or "",
                        website = ms.macroMeta.website or "",
                        owned   = true,
                    }
                end
                local f = io.open(jsonPath, "r")
                if not f then return {} end
                local raw = f:read("*all")
                f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" or type(data.meta) ~= "table" then
                    return {}
                end
                return {
                    name    = data.meta.name    or "",
                    version = data.meta.version or "",
                    author  = data.meta.author  or "",
                    website = data.meta.website or "",
                    owned   = false,
                }
            end

            ms.compiler.setMeta = function(meta)
                assert(type(meta) == "table", "ms.compiler.setMeta: meta must be a table")

                if ms._macroMetaFromHand then
                    print("ms.compiler.setMeta: ignored, handwritten ms_macros.lua owns the pack credits")
                    return false, "handwritten"
                end

                local data = { macros = {} }
                local f = io.open(jsonPath, "r")
                if f then
                    local raw = f:read("*all")
                f:close()
                    local ok, parsed = pcall(hs.json.decode, raw)
                    if ok and type(parsed) == "table" then
                        data = parsed
                        data.macros = data.macros or {}
                    end
                end

                data.meta = {
                    name    = type(meta.name)    == "string" and meta.name    or "",
                    version = type(meta.version) == "string" and meta.version or "",
                    author  = type(meta.author)  == "string" and meta.author  or "",
                    website = type(meta.website) == "string" and meta.website or "",
                }

                os.execute("mkdir -p '" .. dataDir .. "'")
                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler.setMeta: cannot open " .. jsonPath .. " for writing")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()

                ms.compiler.rebuild()
                print("ms.compiler.setMeta: updated pack meta and recompiled")
                return true
            end
        -- END Meta --

        -- Paths --
            ms.compiler.paths = {
                json = jsonPath,
                lua  = luaPath,
                data = dataDir,
            }
        -- END Paths --
    end
-- END ms_compiler --

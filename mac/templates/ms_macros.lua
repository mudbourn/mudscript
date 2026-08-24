-- Creator Credits (CREDIT YOURSELF!) --
    ms.macroMeta = {
        name    = "Default",
        author  = "User"
    }
-- END Creator Credits --

-- Target App (optional) --
    -- ms.setTargetApp("Roblox")
-- END Target App --


local NewMacro1Function = ms.fn(function()
    local t = 100
        ms.type("/")
        ms.wait(t)
        ms.copy("Hello world!")
        ms.wait(t)
        ms.type("v", { "cmd" })
        ms.wait(t)
        ms.type("return")
end)

ms.bind.define("NewMacro1", NewMacro1Function, {
    group   = "optional",
    label   = "New Macro 1",
    default = {
        type = "key",
        mods = {"ctrl"},
        key  = "G",
    },
})

-- Camera Sensitivity lives in the Roblox plugin (Roblox.spoon) now. --

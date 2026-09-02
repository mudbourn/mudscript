-- mudscript bootstrap. See DOCS_MAC.md section 20 for the integrity model.

if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

-- Disarm the exit hard-kill backstops before any heavy boot work.
pcall(function() os.remove(hs.configdir .. "/data/.ms_restart_pending") end)
pcall(function() os.remove(hs.configdir .. "/data/.ms_shutdown_pending") end)

require("lib.ms_guardian")()

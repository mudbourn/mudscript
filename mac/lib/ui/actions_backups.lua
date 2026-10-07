return function(ms, ctx)
    return {
        -- Backups --
            backupsList = function()
                if ms.backups and ms.backups.list then
                    local ok, json = pcall(hs.json.encode, {
                        items = ms.backups.list(),
                        dir = ms._backupRoot,
                    })
                    if ok and ms.shell and ms.shell.eval then
                        pcall(ms.shell.eval, "if(window.shellReceive)shellReceive('backups','list'," .. json .. ")")
                    end
                end
            end,

            backupNow = function()
                ms.backups.snapshot("manual", function(ok, info)
                    if ok and info and not info.skipped then
                        ms.playSlot("update")
                        ms.alert("Backup saved.", 3, true)
                    elseif not ok then
                        ms.alert("Backup failed: " .. tostring(info) .. ".", 5)
                    end
                end)
            end,

            backupRestore = function(data)
                ms.backups.restore(data and data.id)
            end,

            backupDelete = function(data)
                local id = data and data.id
                if not (ms.ui and ms.ui.modal) then return end
                ms.ui.modal({
                    title = "Delete Backup",
                    msg = "Delete this backup permanently?",
                    confirm = "Delete",
                    cancel = "Cancel",
                }, function(r)
                    if r and r.confirmed then ms.backups.delete(id) end
                end)
            end,

            backupsOpenFolder = function()
                ms.backups.openFolder()
            end,

            setBackupInterval = function(data)
                local n = tonumber(data.value)
                if n and ms._backupIntervalChoices[math.floor(n)] then
                    ms._backupIntervalHours = math.floor(n)
                    ms.saveSettings()
                    ms.backups.schedule()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setBackupKeep = function(data)
                local n = tonumber(data.value)
                if n and n >= 1 and n <= 50 then
                    ms._backupKeep = math.floor(n)
                    ms.saveSettings()
                    ms.backups.prune()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,
        -- END Backups --
    }
end

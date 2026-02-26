local Device = require("device")
local PluginShare = require("pluginshare")

local SystemUtils = {}

function SystemUtils.setAutoSuspend(seconds)
    local autosuspend = PluginShare.live_autosuspend
    if autosuspend then
        autosuspend.auto_suspend_timeout_seconds = seconds
        G_reader_settings:saveSetting("auto_suspend_timeout_seconds", seconds)
        
        if type(autosuspend._unschedule) == "function" then
            autosuspend:_unschedule()
        end
        if seconds > 0 and type(autosuspend._start) == "function" then
            autosuspend:_start()
        end
        
        if Device:isKindle() then
            if type(autosuspend._unschedule_kindle) == "function" then
                autosuspend:_unschedule_kindle()
            end
            if type(autosuspend._start_kindle) == "function" then
                autosuspend:_start_kindle()
            end
        end
    end
end

return SystemUtils
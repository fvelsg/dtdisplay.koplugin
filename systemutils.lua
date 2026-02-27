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

function SystemUtils.hasFrontlight()
    if not Device:hasFrontlight() then return false end
    local powerd = Device:getPowerDevice()
    return powerd ~= nil and type(powerd.setIntensity) == "function"
end

function SystemUtils.getBrightness()
    if not SystemUtils.hasFrontlight() then return nil end
    local powerd = Device:getPowerDevice()
    if type(powerd.isFrontlightOn) == "function" and not powerd:isFrontlightOn() then
        return 0
    end
    return powerd.fl_intensity
end

function SystemUtils.setBrightness(level)
    if not SystemUtils.hasFrontlight() or not level then return end
    local powerd = Device:getPowerDevice()
    if level <= 0 then
        if type(powerd.turnOffFrontlight) == "function" then
            powerd:turnOffFrontlight()
        end
        return
    end
    local max_intensity = powerd.fl_max or 24
    if level > max_intensity then level = max_intensity end
    powerd:setIntensity(level)
end

return SystemUtils
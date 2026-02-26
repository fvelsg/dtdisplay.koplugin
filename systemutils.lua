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
    -- powerd is the correct cross-device frontlight API.
    -- Device.flc (kobolight) only exists on Kobo and is nil on Kindle.
    return powerd ~= nil and type(powerd.setIntensity) == "function"
end

function SystemUtils.getBrightness()
    if not SystemUtils.hasFrontlight() then return nil end
    return Device:getPowerDevice().fl_intensity
end

function SystemUtils.setBrightness(level)
    if not SystemUtils.hasFrontlight() or not level then return end
    local powerd = Device:getPowerDevice()
    local max_intensity = powerd.fl_max or 24
    local min_intensity = powerd.fl_min or 0
    if level > max_intensity then level = max_intensity end
    if level < min_intensity then level = min_intensity end
    powerd:setIntensity(level)
end

return SystemUtils
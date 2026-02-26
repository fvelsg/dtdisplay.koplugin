-- statusutils.lua
local Device = require("device")
local _ = require("gettext")
local T = require("ffi/util").template
local NetworkMgr = require("ui/network/manager")

local StatusUtils = {}

function StatusUtils.getBatteryText()
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local battery_level = powerd:getCapacity()
        local prefix = powerd:getBatterySymbol(
            powerd:isCharged(),
            powerd:isCharging(),
            battery_level
        )
        return T(_("%1 %2 %"), prefix, battery_level)
    end
    
    return "" -- Always safe to return an empty string if there's no battery
end

function StatusUtils.getWifiStatusText()
    if NetworkMgr:isWifiOn() then
        return _("")
    else
        return _("")
    end
end

function StatusUtils.getMemoryStatusText()
    -- Based on the implemenation in readerfooter.lua
    local statm = io.open("/proc/self/statm", "r")
    if statm then
        local dummy, rss = statm:read("*number", "*number")
        statm:close()
        -- we got the nb of 4Kb-pages used, that we convert to MiB
        rss = math.floor(rss * (4096 / 1024 / 1024))
        return T(_(" %1 MiB"), rss)
    end
end

return StatusUtils
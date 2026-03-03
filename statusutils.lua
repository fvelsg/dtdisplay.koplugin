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

        -- getBatterySymbol was added in a later KOReader build; guard for older installs
        local prefix = ""
        if type(powerd.getBatterySymbol) == "function" then
            prefix = powerd:getBatterySymbol(
                powerd:isCharged(),
                powerd:isCharging(),
                battery_level
            )
        end

        return T(_("%1 %2 %"), prefix, battery_level)
    end

    return ""
end

function StatusUtils.getWifiStatusText()
    if NetworkMgr:isWifiOn() then
        return _("")
    else
        return _("")
    end
end

function StatusUtils.getMemoryStatusText()
    -- Based on the implementation in readerfooter.lua
    local statm = io.open("/proc/self/statm", "r")
    if statm then
        local dummy, rss = statm:read("*number", "*number")
        statm:close()
        -- Guard: read can return nil if the file is momentarily unreadable
        if rss == nil then return nil end
        -- Convert 4KB pages to MiB
        rss = math.floor(rss * (4096 / 1024 / 1024))
        return T(_(" %1 MiB"), rss)
    end
    -- Returns nil when /proc/self/statm is unavailable
end

function StatusUtils.getStatusText()
    local wifi_string    = StatusUtils.getWifiStatusText()
    local memory_string  = StatusUtils.getMemoryStatusText()
    local battery_string = StatusUtils.getBatteryText()

    -- table.concat errors on nil elements in LuaJIT — filter them out first
    local parts = {}
    for _, s in ipairs({ wifi_string, memory_string, battery_string }) do
        if s ~= nil and s ~= "" then
            parts[#parts + 1] = s
        end
    end
    return table.concat(parts, " | ")
end

return StatusUtils
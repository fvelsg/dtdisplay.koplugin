local Datetime = require("frontend/datetime")

local TimeUtils = {}

function TimeUtils.getDateText(now, use_locale)
    return Datetime.secondsToDate(now, use_locale)
end

function TimeUtils.getTimeText(now)
    return Datetime.secondsToHour(now, true, false)
end

return TimeUtils
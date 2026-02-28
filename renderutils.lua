local Device = require("device")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Font = require("ui/font")
local Screen = Device.screen

local TimeUtils = require("timeutils")
local StatusUtils = require("statusutils")

local RenderUtils = {}

-- clock_format: "follow" | "24" | "12"  (forwarded to TimeUtils)
function RenderUtils.renderTimeWidget(now, width, font_face, clock_format)
    return TextBoxWidget:new {
        text = TimeUtils.getTimeText(now, clock_format),
        face = font_face or Font:getFace("tfont", 119),
        width = width or Screen:getWidth(),
        alignment = "center",
        bold = true,
    }
end

function RenderUtils.renderDateWidget(now, width, font_face, use_locale)
    return TextBoxWidget:new {
        text = TimeUtils.getDateText(now, use_locale),
        face = font_face or Font:getFace("infofont", 32),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

function RenderUtils.renderStatusWidget(width, font_face)
    return TextBoxWidget:new {
        text = StatusUtils.getStatusText(),
        face = font_face or Font:getFace("infofont"),
        width = width or Screen:getWidth(),
        alignment = "center",
    }
end

return RenderUtils
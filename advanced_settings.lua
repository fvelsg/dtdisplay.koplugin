-- advanced_settings.lua
-- Place this file in the DtDisplay plugin folder.
-- When "Advanced settings" is enabled in the menu, values set here take
-- priority over the UI. Set any field to nil (or omit it) to keep the UI value.

return {
    time_widget = {
        font_size = nil,   -- e.g. 150  (overrides the UI font size slider)
        font_name = nil,   -- e.g. "./fonts/noto/NotoSans-Bold.ttf"
    },
    date_widget = {
        font_size = nil,
        font_name = nil,
    },
    status_widget = {
        font_size = nil,
        font_name = nil,
    },
    clock_format  = "follow",  -- "24", "12", or "follow"
    night_mode    = "follow",  -- "night", "normal"(that is light mode), or "follow"
}
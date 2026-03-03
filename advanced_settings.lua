-- advanced_settings.lua
-- Place this file in the DtDisplay plugin folder.
-- When "Advanced settings" is enabled in the menu, values set here take
-- priority over the UI. Set any field to nil (or omit it) to keep the UI value.

return {
    -- WIDGETS --
    time_widget = {
        font_size = nil,  -- e.g. 150 (overrides the UI font size slider)
        font_name = nil,  -- e.g. "./fonts/noto/NotoSans-Bold.ttf"
    },
    date_widget = {
        font_size = nil,
        font_name = nil,
    },
    status_widget = {
        font_size = nil,
        font_name = nil,
    },

    -- CLOCK ORIENTATION --
    -- To use a custom rotation, set follow_koreader = false AND set custom_rotation.
    -- custom_rotation values: 0 = portrait, 1 = landscape CW, 2 = portrait inverted, 3 = landscape CCW
    rotation = {
        follow_koreader = true,   -- true or false
        custom_rotation = 3,   -- 0, 1, 2, or 3
    },

    -- SUSPEND BEHAVIOUR --
    -- The same rules as rotation apply: set all three together for predictable results.
    suspend = {
        never_suspend          = nil,  -- true = never suspend while clock runs
        custom_timeout_enabled = nil,  -- true = use the timeout below instead of KOReader default
        custom_timeout_minutes = nil,  -- e.g. 30
    },

    png_overlay = {
        enabled                  = true,  -- true or false
        mode                     = nil,  -- "single" or "cycle"
        
        -- Single mode paths (portrait and landscape)
        single_file_path_portrait  = nil,  -- e.g. "/mnt/us/covers/my_cover.png"
        single_file_path_landscape = nil,
        single_file_path           = nil,  -- legacy fallback used if portrait/landscape are empty

        -- Cycle mode folder paths
        portrait_folder_path   = nil,  -- folder containing PNGs for portrait
        landscape_folder_path  = nil,
        folder_path            = nil,  -- legacy fallback

        cycle_minutes          = nil,  -- how often to cycle to the next image
        full_refresh_on_cycle  = nil,  -- true = full e-ink refresh on each cycle
        invert_with_night_mode = nil,  -- false = keep PNG uninverted when night mode is on
    },
    -- INDIVIDUAL STATUS WIDGETS --
    -- Leave values as nil to inherit from status_widget
    
    battery_widget = {
        font_size = 50,             -- e.g., slightly larger than the rest
        font_name = nil,            -- e.g., "./fonts/noto/NotoSans-Bold.ttf"
        format    = "icon",      -- Options: "percent", "icon", or "both"
    },
    
    wifi_widget = {
        font_size = 20,             -- e.g., smaller
        font_name = nil,
    },
    
    memory_widget = {
        font_size = 20,
        font_name = nil,
    },

    -- WIDGET BRIGHTNESS --
    -- Set to -1 to disable (use device default), or 0–24 (device max may vary)
    widget_brightness = -1,

    -- FULL REFRESH INTERVAL --
    -- Number of minutes between full e-ink refreshes. Set to 0 to disable.
    full_refresh_minutes = nil,

    -- CLOCK & DISPLAY --
    clock_format = nil,  -- "24", "12", or "follow"
    night_mode   = "night",  -- "night", "normal", or "follow"


}

-- =========================================================================
-- PER-IMAGE CONFIGURATION TEMPLATE
-- Name this file exactly the same as your image (e.g., background1.lua)
-- and place it in the exact same folder as the image.
--
-- INSTRUCTIONS:
-- 1. If you leave a value as 'nil' or delete the line entirely, the plugin 
--    will automatically use your standard KOReader UI settings.
-- 2. You only need to keep the sections you actively want to change!
-- =========================================================================

return {
    -- ==========================================
    -- 1. TEXT & FONT SETTINGS
    -- ==========================================
    
    -- The brand new Custom Text Widget!
    custom_text_widget = {
        text      = "Your custom quote or label goes here!", 
        font_size = 32,             -- Number: Size of the font
        font_name = nil,            -- String: Path to font (e.g., "./fonts/noto/NotoSans-Bold.ttf")
        width     = 400,            -- Number: Width in pixels. Text wraps automatically. 'nil' = full screen.
        alignment = "center",       -- String: "left", "center", or "right"
    },

    time_widget = {
        font_size = nil,            
        font_name = nil,            
    },
    
    date_widget = {
        font_size = nil,
        font_name = nil,
    },
    
    status_widget = {
        font_size = nil,
        font_name = nil,
    },
    
    battery_widget = {
        font_size = nil,
        font_name = nil,
        format    = "both",         -- String: "percent" (100%), "icon" (🔋), or "both" (🔋 100%)
    },
    
    wifi_widget = {
        font_size = nil,
        font_name = nil,
    },
    
    memory_widget = {
        font_size = nil,
        font_name = nil,
    },

    -- ==========================================
    -- 2. LAYOUT & POSITIONING (The 'elements' block)
    -- ==========================================
    -- This controls where things appear on the screen.
    --   visible: true (show) or false (hide)
    --   z:       Layering. 1 is background, 2 is middle, 3 is top.
    --   unit:    "px" (pixels from center) or "%" (percentage from center)
    --   x:       Horizontal movement (negative = left, positive = right)
    --   y:       Vertical movement (negative = up, positive = down)
    
    elements = {
        png = {
            visible = true, z = 1, unit = "px", x = 0, y = 0,
        },
        time = {
            visible = true, z = 2, unit = "px", x = 0, y = 0,
        },
        date = {
            visible = true, z = 2, unit = "%", x = 0, y = -20,
        },
        status = {
            visible = true, z = 2, unit = "%", x = 0, y = 20,
        },
        custom_text = {
            visible = false, z = 2, unit = "%", x = 0, y = 45,
        },
        wifi = {
            visible = false, z = 2, unit = "%", x = 0, y = 30,
        },
        battery = {
            visible = false, z = 2, unit = "%", x = 0, y = 35,
        },
        memory = {
            visible = false, z = 2, unit = "%", x = 0, y = 40,
        },
    },

    -- ==========================================
    -- 3. DISPLAY & THEME OVERRIDES
    -- ==========================================
    
    -- Force a specific clock format for this image
    clock_format = "follow",        -- String: "24", "12", or "follow" (follows KOReader system setting)

    -- Force a specific background theme for this image
    night_mode   = "follow",        -- String: "night" (dark), "normal" (light), or "follow"

    png_overlay = {
        -- Do you want the PNG colors to flip when the screen goes dark?
        invert_with_night_mode = false, -- Boolean: true or false
    },

    -- ==========================================
    -- 4. HARDWARE BEHAVIOR OVERRIDES
    -- ==========================================
    
    -- Force a specific screen brightness for this image
    widget_brightness = -1,         -- Number: 0 to 24 (depends on device). -1 disables this feature.

    -- Force the screen to rotate when this image appears
    rotation = {
        follow_koreader = true,     -- Boolean: true or false
        custom_rotation = 0,        -- Number: 0 (Portrait), 1 (Landscape CW), 2 (Portrait Inverted), 3 (Landscape CCW)
    },

    -- Prevent the e-reader from sleeping while this image is shown
    suspend = {
        never_suspend          = false, -- Boolean: true (never sleep) or false (allow sleep)
        custom_timeout_enabled = false, -- Boolean: true (use custom timer below) or false
        custom_timeout_minutes = 60,    -- Number: minutes before sleeping
    },

    -- Force a full e-ink screen flash to clear ghosting
    full_refresh_minutes = 0,       -- Number: minutes between full flashes. 0 disables this feature.
}

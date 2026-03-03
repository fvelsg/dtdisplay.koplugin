-- -- Template for Per-Image Configuration
-- -- Delete any line or section you don't need to override.

-- return {
--     -- ==========================================
--     -- 1. FONT & FORMAT SETTINGS
--     -- ==========================================
--     time_widget = {
--         font_size = 150,
--         font_name = "./fonts/noto/NotoSans-Bold.ttf", -- Leave as nil to use UI default
--     },
--     date_widget = {
--         font_size = 32,
--         font_name = nil,
--     },
--     status_widget = {
--         font_size = 24,
--         font_name = nil,
--     },
--     battery_widget = {
--         font_size = 28,
--         font_name = nil,
--         format    = "percent", -- Options: "percent", "icon", or "both"
--     },
--     wifi_widget = {
--         font_size = 20,
--         font_name = nil,
--     },
--     memory_widget = {
--         font_size = 20,
--         font_name = nil,
--     },

--     -- ==========================================
--     -- 2. LAYOUT & POSITIONING (elements)
--     -- ==========================================
--     -- x: Horizontal offset from center (negative = left, positive = right)
--     -- y: Vertical offset from center (negative = up, positive = down)
--     -- z: Layer stack (1 is background, 2 is middle, 3 is top)
--     -- unit: "px" for pixels, "%" for screen percentage
--     -- visible: true or false
    
--     elements = {
--         png = {
--             visible = true,
--             z = 1,
--             -- PNG usually stays centered at x=0, y=0
--         },
--         time = {
--             x = 0, y = -10, unit = "%", z = 2, visible = true,
--         },
--         date = {
--             x = 0, y = 10, unit = "%", z = 2, visible = true,
--         },
--         status = {
--             visible = false, -- e.g., Hide the combined status bar for this image
--         },
--         battery = {
--             x = -20, y = 30, unit = "%", z = 2, visible = true,
--         },
--         wifi = {
--             x = 0, y = 30, unit = "%", z = 2, visible = true,
--         },
--         memory = {
--             x = 20, y = 30, unit = "%", z = 2, visible = true,
--         },
--     },

--     -- ==========================================
--     -- 3. DISPLAY & THEME OVERRIDES
--     -- ==========================================
--     -- Force this specific image to always use 24h or 12h clock
--     clock_format = "follow", -- "24", "12", or "follow"

--     -- Force the screen theme when this image is shown
--     night_mode = "follow", -- "night", "normal", or "follow"

--     png_overlay = {
--         -- Set to false if you want THIS specific image's colors 
--         -- to invert when night mode is active.
--         invert_with_night_mode = true, 
--     },

--     -- ==========================================
--     -- 4. HARDWARE BEHAVIOR OVERRIDES
--     -- ==========================================
--     -- Custom brightness for this image (-1 to disable/follow device)
--     widget_brightness = -1,

--     -- Clock Orientation
--     rotation = {
--         follow_koreader = true,
--         custom_rotation = 0, -- 0 (Portrait), 1 (Land CW), 2 (Port Invert), 3 (Land CCW)
--     },

--     -- Custom suspend rules for this image
--     suspend = {
--         never_suspend = false,
--         custom_timeout_enabled = false,
--         custom_timeout_minutes = 60,
--     },

--     -- Full screen e-ink refresh interval (minutes, 0 to disable)
--     full_refresh_minutes = 0,
-- }

-- Template for Per-Image Configuration
-- All values here are set to 'nil' or default coordinates so they change NOTHING.
-- Edit only the values you specifically want to override for this image.

return {
    -- ==========================================
    -- 1. FONT & FORMAT SETTINGS
    -- ==========================================
    -- Leaving these as 'nil' makes them follow your main UI settings.
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
        format    = nil, -- e.g., "percent", "icon", or "both"
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
    -- 2. LAYOUT & POSITIONING (elements)
    -- ==========================================
    -- These are the exact default coordinates. 
    -- Change them to move things around just for this image.
    elements = {
        png = {
            x = 0, y = 0, unit = "px", z = 1, visible = true 
        },
        time = {
            x = 0, y = 0, unit = "px", z = 2, visible = true,
        },
        date = {
            x = 0, y = -20, unit = "%", z = 2, visible = true,
        },
        status = {
            x = 0, y = 20, unit = "%", z = 2, visible = true,
        },
        -- The individual widgets are hidden by default
        wifi = {
            x = 0, y = 30, unit = "%", z = 2, visible = false,
        },
        battery = {
            x = 0, y = 35, unit = "%", z = 2, visible = false,
        },
        memory = {
            x = 0, y = 40, unit = "%", z = 2, visible = false,
        },
    },

    -- ==========================================
    -- 3. DISPLAY & THEME OVERRIDES
    -- ==========================================
    clock_format = nil, -- e.g., "24", "12", or "follow"
    night_mode   = nil, -- e.g., "night", "normal", or "follow"

    png_overlay = {
        invert_with_night_mode = nil, -- e.g., true or false
    },

    -- ==========================================
    -- 4. HARDWARE BEHAVIOR OVERRIDES
    -- ==========================================
    widget_brightness = -1,

    rotation = {
        follow_koreader = nil,
        custom_rotation = nil, 
    },

    suspend = {
        never_suspend          = nil,
        custom_timeout_enabled = nil,
        custom_timeout_minutes = nil,
    },

    full_refresh_minutes = nil,
}

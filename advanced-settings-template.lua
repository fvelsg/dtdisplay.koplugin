-- =========================================================================
-- ADVANCED SETTINGS (GLOBAL OVERRIDE)
-- =========================================================================
-- This file overrides the standard KOReader UI settings when the 
-- "Advanced Settings" toggle is checked in the plugin menu.
-- 
-- Leave a value as 'nil' to keep using the setting from the UI menu.
-- =========================================================================

return {
    -- ==========================================
    -- 1. FONT & TEXT SETTINGS
    -- ==========================================
    
    -- The Custom Text Widget (Global)
    custom_text_widget = {
        text      = nil,            -- e.g., "My E-Reader Dashboard"
        font_size = nil,            -- e.g., 28
        font_name = nil,            -- e.g., "./fonts/noto/NotoSans-Bold.ttf"
        width     = nil,            -- Width in pixels. 'nil' = full screen width.
        alignment = nil,            -- "left", "center", or "right"
    },

    time_widget = {
        font_size = nil,  
        font_name = nil,  
    },
    
    date_widget = {
        font_size = nil,
        font_name = nil,
    },
    
    -- The combined status bar (if you are still using it)
    status_widget = {
        font_size = nil,
        font_name = nil,
    },
    
    -- Individual Status Widgets
    battery_widget = {
        font_size = nil,
        font_name = nil,
        format    = nil,            -- "percent", "icon", or "both"
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
    -- 2. DISPLAY & THEME SETTINGS
    -- ==========================================
    
    clock_format = nil,             -- "24", "12", or "follow"
    night_mode   = nil,             -- "night", "normal", or "follow"

    png_overlay = {
        enabled                    = nil, -- true or false
        mode                       = nil, -- "single" or "cycle"
        
        -- Default Folders / Files (Usually better to set these in the UI)
        single_file_path_portrait  = nil, 
        single_file_path_landscape = nil,
        portrait_folder_path       = nil, 
        landscape_folder_path      = nil,
        
        cycle_minutes              = nil, -- e.g., 5
        full_refresh_on_cycle      = nil, -- true or false
        
        -- Should the PNG colors flip in night mode globally?
        invert_with_night_mode     = nil, -- true or false
        
        -- Allow per-image .lua files to override these settings?
        use_image_config           = nil, -- true or false
    },


    -- ==========================================
    -- 3. HARDWARE BEHAVIOR
    -- ==========================================
    
    widget_brightness = nil,        -- 0 to max device brightness. -1 to disable.

    rotation = {
        follow_koreader = nil,      -- true or false
        custom_rotation = nil,      -- 0 (Portrait), 1 (Land CW), 2 (Port Invert), 3 (Land CCW)
    },

    suspend = {
        never_suspend          = nil, -- true or false
        custom_timeout_enabled = nil, -- true or false
        custom_timeout_minutes = nil, -- e.g., 60
    },

    full_refresh_minutes = nil,     -- Minutes between e-ink flashes. 0 to disable.
}

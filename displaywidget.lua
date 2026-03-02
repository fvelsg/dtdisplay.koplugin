local Blitbuffer = require("ffi/blitbuffer")
local Date = os.date
local Datetime = require("frontend/datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local PluginShare = require("pluginshare")
local Screen = Device.screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget") -- Added TextWidget to tightly wrap strings
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

-- Importing from the other files --
local StatusUtils = require("statusutils")
local PngUtils = require("pngutils")
local TimeUtils = require("timeutils")
local RenderUtils = require("renderutils")
local SystemUtils = require("systemutils")

------------------

local T = require("ffi/util").template
local _ = require("gettext")

--- Helper to deep-merge tables. Overrides base values with override values.
local function deepMerge(base, override)
    if type(base) ~= "table" then return override or base end
    if type(override) ~= "table" then return base end
    
    local res = {}
    for k, v in pairs(base) do
        if type(v) == "table" then
            res[k] = deepMerge(v, {}) -- deep copy the table
        else
            res[k] = v
        end
    end
    
    for k, v in pairs(override) do
        if type(v) == "table" then
            if type(res[k]) == "table" then
                res[k] = deepMerge(res[k], v)
            else
                res[k] = deepMerge({}, v)
            end
        else
            res[k] = v
        end
    end
    return res
end

local DisplayWidget = InputContainer:extend {
    props = {},
}

function DisplayWidget:init()
    -- Store incoming settings (UI + advanced_settings.lua) as the base foundation
    self.base_props = self.props
    
    -- Evaluate the current PNG and merge its .lua settings before initial render
    self:updateActiveProps()

    self.now = os.time()
    self.time_widget = nil
    self.date_widget = nil
    self.status_widget = nil
    self.battery_widget = nil
    self.wifi_widget = nil
    self.memory_widget = nil
    self.datetime_vertical_group = nil

    -- PNG overlay state
    self.png_overlay_widget = nil
    self.png_cycle_index = 1
    self.png_cycle_counter = 0
    self.full_refresh_counter = 0 
    self.png_file_list = nil

    self.is_closing = false

    -- Rotation handling
    self.original_rotation = Screen:getRotationMode()
    self:applyClockRotation()

    self.autoRefresh = function()
        self:refresh()
        return UIManager:scheduleIn(60 - tonumber(Date("%S")), self.autoRefresh)
    end

    -- Events
    self.ges_events.TapClose = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new {
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
        }
    }

    -- Hints
    self.covers_fullscreen = true

    -- Render
    UIManager:setDirty("all", "full") -- return to flashpartial if crashes
    self[1] = self:render()
    
    -- Store original autosuspend timeout and apply new logic based on menu settings
    local autosuspend = PluginShare.live_autosuspend
    if autosuspend then
        self.original_autosuspend_timeout = autosuspend.auto_suspend_timeout_seconds
    end

    if self.props and self.props.suspend then
        if self.props.suspend.never_suspend then
            SystemUtils.setAutoSuspend(-1)
        elseif self.props.suspend.custom_timeout_enabled and self.props.suspend.custom_timeout_minutes then
            SystemUtils.setAutoSuspend(self.props.suspend.custom_timeout_minutes * 60)
        end
    end

    self.original_brightness = nil

    if self.props.widget_brightness and self.props.widget_brightness >= 0 then
        if SystemUtils.hasFrontlight() then
            self.original_brightness = SystemUtils.getBrightness()
            SystemUtils.setBrightness(self.props.widget_brightness)
        end
    end    
end

--- Generates the active self.props by merging image.lua (if any) onto base_props.
function DisplayWidget:updateActiveProps()
    self.props = deepMerge({}, self.base_props)

    local png_path, _ = self:getCurrentPngPathAndType()
    if png_path then
        local lua_path = png_path:gsub("%.png$", ".lua")
        local f = io.open(lua_path, "r")
        if f then
            f:close()
            local ok, img_props = pcall(dofile, lua_path)
            if ok and type(img_props) == "table" then
                self.props = deepMerge(self.props, img_props)
            end
        end
    end
end

function DisplayWidget:applyClockRotation()
    local rotation_settings = self.props and self.props.rotation
    if rotation_settings and not rotation_settings.follow_koreader then
        local custom = rotation_settings.custom_rotation or 0
        Screen:setRotationMode(custom)
    end
end

function DisplayWidget:restoreRotation()
    if self.original_rotation then
        Screen:setRotationMode(self.original_rotation)
        self.original_rotation = nil
    end
end

function DisplayWidget:refresh()
    self.now = os.time()
    self:update()
    
    if type(self.cyclePngOverlay) == "function" then
        self:cyclePngOverlay()
    end

    local full_refresh_minutes = self.props.full_refresh_minutes
    if full_refresh_minutes and full_refresh_minutes > 0 then
        self.full_refresh_counter = self.full_refresh_counter + 1
        if self.full_refresh_counter >= full_refresh_minutes then 
            self.full_refresh_counter = 0
            UIManager:setDirty("all", "full")
            return
        end
    end

    if self.using_custom_positions then
        UIManager:setDirty("all", "ui")
    else
        UIManager:setDirty("all", "ui", self.datetime_vertical_group.dimen)
    end
end

function DisplayWidget:onShow()
    return self:autoRefresh()
end

function DisplayWidget:onResume()
    self.now = os.time()
    self:update()
    UIManager:setDirty("all", "full") 
    UIManager:unschedule(self.autoRefresh)
    self:autoRefresh()
end

function DisplayWidget:onSuspend()
    UIManager:unschedule(self.autoRefresh)
end

function DisplayWidget:onTapClose()
    if self.is_closing then
        return
    end
    self.is_closing = true

    UIManager:unschedule(self.autoRefresh)
    self:restoreRotation()
    
    if self.original_brightness then
        SystemUtils.setBrightness(self.original_brightness)
    end

    if self.original_autosuspend_timeout then
        SystemUtils.setAutoSuspend(self.original_autosuspend_timeout)
    end
    UIManager:close(self)
end

DisplayWidget.onAnyKeyPressed = DisplayWidget.onTapClose

function DisplayWidget:onCloseWidget()
    self:restoreRotation()
    if self.original_autosuspend_timeout then
        SystemUtils.setAutoSuspend(self.original_autosuspend_timeout)
    end
    if self.original_brightness then
        SystemUtils.setBrightness(self.original_brightness)
    end
end

function DisplayWidget:update()
    local time_text = TimeUtils.getTimeText(self.now, self.props.clock_format)
    local date_text = TimeUtils.getDateText(self.now, true)

    if self.time_widget.text ~= time_text then
        self.time_widget:setText(time_text)
    end
    if self.date_widget.text ~= date_text then
        self.date_widget:setText(date_text)
    end

    if self.status_widget then
        local status_text = StatusUtils.getStatusText()
        if self.status_widget.text ~= status_text then
            self.status_widget:setText(status_text)
        end
    end

    if self.battery_widget then
        local bat_text = StatusUtils.getBatteryText()
        if self.battery_widget.text ~= bat_text then
            self.battery_widget:setText(bat_text)
        end
    end

    if self.wifi_widget then
        local wifi_text = StatusUtils.getWifiStatusText()
        if self.wifi_widget.text ~= wifi_text then
            self.wifi_widget:setText(wifi_text)
        end
    end

    if self.memory_widget then
        local mem_text = StatusUtils.getMemoryStatusText()
        if self.memory_widget.text ~= mem_text then
            self.memory_widget:setText(mem_text)
        end
    end
end

--- Get the active folder path based on current orientation.
function DisplayWidget:getActiveFolderPath()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if not overlay_settings then return nil end

    if PngUtils.isPortraitOrientation() then
        local folder = overlay_settings.portrait_folder_path
        if folder and folder ~= "" then return folder end
        local legacy = overlay_settings.folder_path
        if legacy and legacy ~= "" then return legacy end
    else
        local folder = overlay_settings.landscape_folder_path
        if folder and folder ~= "" then return folder end
        local legacy = overlay_settings.folder_path
        if legacy and legacy ~= "" then return legacy end
    end
    return nil
end

--- Get the active single file path based on current orientation.
function DisplayWidget:getActiveSingleFilePath()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if not overlay_settings then return nil end

    if PngUtils.isPortraitOrientation() then
        local fpath = overlay_settings.single_file_path_portrait
        if fpath and fpath ~= "" then return fpath end
        local legacy = overlay_settings.single_file_path
        if legacy and legacy ~= "" then return legacy end
    else
        local fpath = overlay_settings.single_file_path_landscape
        if fpath and fpath ~= "" then return fpath end
        local legacy = overlay_settings.single_file_path
        if legacy and legacy ~= "" then return legacy end
    end
    return nil
end

--- Get sorted list of valid PNG files from the active folder.
function DisplayWidget:getPngFileList()
    if self.png_file_list then return self.png_file_list end

    local overlay_settings = self.base_props and self.base_props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then return nil end

    local folder = self:getActiveFolderPath()
    if not folder then return nil end

    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then return nil end

    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local lower = entry:lower()
            if lower:match("%.png$") then
                table.insert(files, entry)
            end
        end
    end
    table.sort(files)

    local valid_files = {}
    for _, fname in ipairs(files) do
        local fpath = folder .. "/" .. fname
        local res_type = PngUtils.checkPngResolution(fpath)
        if res_type then
            table.insert(valid_files, { filename = fname, resolution_type = res_type })
        end
    end

    if #valid_files == 0 then return nil end
    self.png_file_list = valid_files
    return self.png_file_list
end

--- Get the current PNG file path and its resolution type.
function DisplayWidget:getCurrentPngPathAndType()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then return nil, nil end

    local mode = overlay_settings.mode or "single"

    if mode == "single" then
        local single_path = self:getActiveSingleFilePath()
        if single_path then
            local res_type = PngUtils.checkPngResolution(single_path)
            if res_type then return single_path, res_type end
        end
        return nil, nil
    elseif mode == "cycle" then
        local files = self:getPngFileList()
        if not files or #files == 0 then return nil, nil end
        local folder = self:getActiveFolderPath()
        if not folder then return nil, nil end
        if self.png_cycle_index > #files then self.png_cycle_index = 1 end
        local entry = files[self.png_cycle_index]
        return folder .. "/" .. entry.filename, entry.resolution_type
    end
    return nil, nil
end

--- Get the configured cycle interval in minutes
function DisplayWidget:getCycleMinutes()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if overlay_settings and overlay_settings.cycle_minutes then
        return overlay_settings.cycle_minutes
    end
    return 1
end

--- Check if full refresh on cycle is enabled
function DisplayWidget:isFullRefreshOnCycle()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if overlay_settings then
        return overlay_settings.full_refresh_on_cycle == true
    end
    return false
end

--- Cycle to the next PNG image, update active props, and rebuild layout
function DisplayWidget:cyclePngOverlay()
    local overlay_settings = self.base_props and self.base_props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then return end
    if overlay_settings.mode ~= "cycle" then return end

    local files = self:getPngFileList()
    if not files or #files == 0 then return end

    self.png_cycle_counter = self.png_cycle_counter + 1
    local cycle_minutes = self:getCycleMinutes()

    if self.png_cycle_counter >= cycle_minutes then
        self.png_cycle_counter = 0
        self.png_cycle_index = self.png_cycle_index + 1
        if self.png_cycle_index > #files then
            self.png_cycle_index = 1
        end

        -- Image has changed: Evaluate specific settings and rebuild layout
        self:updateActiveProps()
        
        if self[1] and self[1].free then
            self[1]:free()
        end
        
        self[1] = self:render()
        self:update() -- Ensure text inside new widgets is correct instantly

        local refresh_mode = "ui"
        if self:isFullRefreshOnCycle() then
            refresh_mode = "full"
        end
        UIManager:setDirty("all", refresh_mode)
    end
end

--- Create the PNG overlay ImageWidget with proper rotation handling.
function DisplayWidget:createPngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then return nil end

    local ImageWidget = require("ui/widget/imagewidget")
    local screen_size = Screen:getSize()
    local rotation_angle = PngUtils.getImageRotationAngle(res_type)

    return ImageWidget:new {
        file = png_path,
        width = screen_size.w,
        height = screen_size.h,
        scale_factor = 0,
        alpha = true,
        rotation_angle = rotation_angle,
    }
end

--- Returns true if any position value is explicitly set in props.positions
--- or if any standalone status widgets are shown (which require custom positioning)
local function hasCustomPositions(props)
    if not props then return false end
    
    local pos = props.positions
    if type(pos) == "table" then
        if pos.date_x ~= nil or pos.date_y ~= nil
            or pos.time_x ~= nil or pos.time_y ~= nil
            or pos.status_x ~= nil or pos.status_y ~= nil then
            return true
        end
    end

    if props.battery_widget and props.battery_widget.show then return true end
    if props.wifi_widget and props.wifi_widget.show then return true end
    if props.memory_widget and props.memory_widget.show then return true end

    return false
end

--- Build the clock frame using the original centered VerticalGroup layout.
function DisplayWidget:renderDefaultLayout(screen_size)
    local total_height = self.time_widget:getSize().h + self.date_widget:getSize().h
    local items = { self.date_widget, self.time_widget }

    if self.status_widget then
        total_height = total_height + self.status_widget:getSize().h
        table.insert(items, self.status_widget)
    end
    if self.battery_widget then
        total_height = total_height + self.battery_widget:getSize().h
        table.insert(items, self.battery_widget)
    end
    if self.wifi_widget then
        total_height = total_height + self.wifi_widget:getSize().h
        table.insert(items, self.wifi_widget)
    end
    if self.memory_widget then
        total_height = total_height + self.memory_widget:getSize().h
        table.insert(items, self.memory_widget)
    end

    local spacer_height = (screen_size.h - total_height) / 2

    local spacer_widget = TextBoxWidget:new {
        text   = nil,
        face   = Font:getFace("cfont"),
        width  = screen_size.w,
        height = spacer_height,
    }

    self.datetime_vertical_group = VerticalGroup:new(items)
    
    local vertical_group = VerticalGroup:new {
        spacer_widget,
        self.datetime_vertical_group,
        spacer_widget,
    }

    return FrameContainer:new {
        geom       = Geom:new { w = screen_size.w, h = screen_size.h },
        radius     = 0,
        bordersize = 0,
        padding    = 0,
        margin     = 0,
        background = Blitbuffer.COLOUR_WHITE,
        color      = Blitbuffer.COLOUR_WHITE,
        width      = screen_size.w,
        height     = screen_size.h,
        vertical_group,
    }
end

--- Build the clock frame using exact x/y positions from props.positions and individual widgets.
function DisplayWidget:renderCustomLayout(screen_size)
    local total_height = self.time_widget:getSize().h + self.date_widget:getSize().h
                       
    if self.status_widget then
        total_height = total_height + self.status_widget:getSize().h
    end

    local center_y         = (screen_size.h - total_height) / 2
    local default_date_y   = center_y
    local default_time_y   = center_y + self.date_widget:getSize().h
    local default_status_y = center_y + self.date_widget:getSize().h + self.time_widget:getSize().h

    local pos      = self.props.positions or {}
    local date_x   = pos.date_x   or 0
    local date_y   = pos.date_y   or default_date_y
    local time_x   = pos.time_x   or 0
    local time_y   = pos.time_y   or default_time_y

    self.date_widget.overlap_offset   = { date_x,   date_y   }
    self.time_widget.overlap_offset   = { time_x,   time_y   }

    local bg_spacer = TextBoxWidget:new {
        text   = nil,
        face   = Font:getFace("cfont"),
        width  = screen_size.w,
        height = screen_size.h,
    }

    local background_frame = FrameContainer:new {
        geom       = Geom:new { w = screen_size.w, h = screen_size.h },
        radius     = 0,
        bordersize = 0,
        padding    = 0,
        margin     = 0,
        background = Blitbuffer.COLOUR_WHITE,
        color      = Blitbuffer.COLOUR_WHITE,
        width      = screen_size.w,
        height     = screen_size.h,
        bg_spacer,
    }

    local overlap_items = {
        dimen = Geom:new { w = screen_size.w, h = screen_size.h },
        background_frame,
        self.date_widget,
        self.time_widget,
    }

    if self.status_widget then
        local status_x = pos.status_x or 0
        local status_y = pos.status_y or default_status_y
        self.status_widget.overlap_offset = { status_x, status_y }
        table.insert(overlap_items, self.status_widget)
    end

    if self.battery_widget then
        local bw = self.props.battery_widget
        self.battery_widget.overlap_offset = { bw.x or 0, bw.y or 0 }
        table.insert(overlap_items, self.battery_widget)
    end
    if self.wifi_widget then
        local ww = self.props.wifi_widget
        self.wifi_widget.overlap_offset = { ww.x or 0, ww.y or 0 }
        table.insert(overlap_items, self.wifi_widget)
    end
    if self.memory_widget then
        local mw = self.props.memory_widget
        self.memory_widget.overlap_offset = { mw.x or 0, mw.y or 0 }
        table.insert(overlap_items, self.memory_widget)
    end

    return OverlapGroup:new(overlap_items)
end

function DisplayWidget:render()
    local screen_size = Screen:getSize()

    -- Instantiate widgets
    self.time_widget = RenderUtils.renderTimeWidget(
        self.now,
        screen_size.w,
        Font:getFace(self.props.time_widget.font_name, self.props.time_widget.font_size),
        self.props.clock_format
    )
    self.date_widget = RenderUtils.renderDateWidget(
        self.now,
        screen_size.w,
        Font:getFace(self.props.date_widget.font_name, self.props.date_widget.font_size),
        true
    )
    
    if not self.props.status_widget or self.props.status_widget.show ~= false then
        self.status_widget = RenderUtils.renderStatusWidget(
            screen_size.w,
            Font:getFace(self.props.status_widget and self.props.status_widget.font_name, self.props.status_widget and self.props.status_widget.font_size)
        )
    else
        self.status_widget = nil
    end

    -- CHANGED: Use TextWidget instead of TextBoxWidget to wrap the text tightly
    -- without drawing an invisible background box that defaults to screen width.
    if self.props.battery_widget and self.props.battery_widget.show then
        self.battery_widget = TextWidget:new {
            text = StatusUtils.getBatteryText(),
            face = Font:getFace(self.props.battery_widget.font_name, self.props.battery_widget.font_size)
        }
    else
        self.battery_widget = nil
    end

    if self.props.wifi_widget and self.props.wifi_widget.show then
        self.wifi_widget = TextWidget:new {
            text = StatusUtils.getWifiStatusText(),
            face = Font:getFace(self.props.wifi_widget.font_name, self.props.wifi_widget.font_size)
        }
    else
        self.wifi_widget = nil
    end

    if self.props.memory_widget and self.props.memory_widget.show then
        self.memory_widget = TextWidget:new {
            text = StatusUtils.getMemoryStatusText(),
            face = Font:getFace(self.props.memory_widget.font_name, self.props.memory_widget.font_size)
        }
    else
        self.memory_widget = nil
    end

    local clock_frame
    if hasCustomPositions(self.props) then
        self.using_custom_positions = true
        clock_frame = self:renderCustomLayout(screen_size)
    else
        self.using_custom_positions = false
        clock_frame = self:renderDefaultLayout(screen_size)
    end

    self.png_file_list = nil

    self.png_overlay_widget = self:createPngOverlayWidget()

    if self.png_overlay_widget then
        self.overlap_group = OverlapGroup:new {
            dimen = Geom:new { w = screen_size.w, h = screen_size.h },
            clock_frame,
            self.png_overlay_widget,
        }
        return self.overlap_group
    else
        self.overlap_group = nil
        return clock_frame
    end
end

function DisplayWidget:paintTo(bb, x, y)
    -- Determine global KOReader state
    local global_night = G_reader_settings:isTrue("night_mode")
    
    -- Determine what state we want based on our settings
    local setting = self.props and self.props.night_mode or "follow"
    local want_night = global_night
    if setting == "night" then 
        want_night = true
    elseif setting == "normal" then 
        want_night = false 
    end

    -- Determine if the PNG should be inverted IN night mode
    local want_png_inverted = false
    if want_night then
        -- Default is false unless explicitly set to true
        local inv_setting = self.props and self.props.png_overlay and self.props.png_overlay.invert_with_night_mode
        if inv_setting == true then
            want_png_inverted = true
        end
    end

    -- Since we set `self.covers_fullscreen = true`, KOReader culls the 
    -- global NightModeWidget. We are 100% responsible for inverting the screen 
    -- if we want a dark mode appearance. No external inversion will happen.

    if self.overlap_group then
        if want_night and not want_png_inverted then
            -- 1. Base is dark, PNG is normal
            self.overlap_group[1]:paintTo(bb, x, y)
            bb:invertRect(x, y, Screen:getWidth(), Screen:getHeight())
            self.overlap_group[2]:paintTo(bb, x, y)
        elseif want_night and want_png_inverted then
            -- 2. Base is dark, PNG is inverted
            self.overlap_group[1]:paintTo(bb, x, y)
            self.overlap_group[2]:paintTo(bb, x, y)
            bb:invertRect(x, y, Screen:getWidth(), Screen:getHeight())
        else
            -- 3. Day mode (nothing inverted)
            self.overlap_group[1]:paintTo(bb, x, y)
            self.overlap_group[2]:paintTo(bb, x, y)
        end
    else
        -- No PNG overlay
        InputContainer.paintTo(self, bb, x, y)
        if want_night then
            bb:invertRect(x, y, Screen:getWidth(), Screen:getHeight())
        end
    end
end

return DisplayWidget
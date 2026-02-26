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

local DisplayWidget = InputContainer:extend {
    props = {},
}

function DisplayWidget:init()
    -- Properties
    self.now = os.time()
    self.time_widget = nil
    self.date_widget = nil
    self.status_widget = nil
    self.datetime_vertical_group = nil

    -- PNG overlay state
    self.png_overlay_widget = nil
    self.png_cycle_index = 1
    self.png_cycle_counter = 0
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
    UIManager:setDirty("all", "flashpartial")
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
    -- Cycle PNG overlay if in cycle mode
    if type(self.cyclePngOverlay) == "function" then
        self:cyclePngOverlay()
    end
    UIManager:setDirty("all", "ui", self.datetime_vertical_group.dimen)
end

function DisplayWidget:onShow()
    return self:autoRefresh()
end

function DisplayWidget:onResume()
    -- Device woke up from suspend — restart the clock refresh timer
    self.now = os.time()
    self:update()
    UIManager:setDirty("all", "flashpartial")

    -- Restart the auto-refresh timer
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
    
    -- RESTORE ORIGINAL AUTOSUSPEND
    if self.original_autosuspend_timeout then
        SystemUtils.setAutoSuspend(self.original_autosuspend_timeout)
    end
    
    UIManager:close(self)
end

DisplayWidget.onAnyKeyPressed = DisplayWidget.onTapClose

function DisplayWidget:onCloseWidget()
    -- Safety net: ensure rotation and suspend are always restored even if closed externally
    self:restoreRotation()
    if self.original_autosuspend_timeout then
        SystemUtils.setAutoSuspend(self.original_autosuspend_timeout)
    end
end


function DisplayWidget:update()
    local time_text = TimeUtils.getTimeText(self.now)
    local date_text = TimeUtils.getDateText(self.now, true)
    local status_text = StatusUtils.getStatusText()

    -- Avoid spamming repeated calls to setText
    if self.time_widget.text ~= time_text then
        self.time_widget:setText(time_text)
    end
    if self.date_widget.text ~= date_text then
        self.date_widget:setText(date_text)
    end
    if self.status_widget.text ~= status_text then
        self.status_widget:setText(status_text)
    end
end

--- Get the active folder path based on current orientation.
function DisplayWidget:getActiveFolderPath()
    local overlay_settings = self.props and self.props.png_overlay
    if not overlay_settings then
        return nil
    end

    if PngUtils.isPortraitOrientation() then
        local folder = overlay_settings.portrait_folder_path
        if folder and folder ~= "" then
            return folder
        end
        local legacy = overlay_settings.folder_path
        if legacy and legacy ~= "" then
            return legacy
        end
    else
        local folder = overlay_settings.landscape_folder_path
        if folder and folder ~= "" then
            return folder
        end
        local legacy = overlay_settings.folder_path
        if legacy and legacy ~= "" then
            return legacy
        end
    end

    return nil
end

--- Get the active single file path based on current orientation.
function DisplayWidget:getActiveSingleFilePath()
    local overlay_settings = self.props and self.props.png_overlay
    if not overlay_settings then
        return nil
    end

    if PngUtils.isPortraitOrientation() then
        local fpath = overlay_settings.single_file_path_portrait
        if fpath and fpath ~= "" then
            return fpath
        end
        local legacy = overlay_settings.single_file_path
        if legacy and legacy ~= "" then
            return legacy
        end
    else
        local fpath = overlay_settings.single_file_path_landscape
        if fpath and fpath ~= "" then
            return fpath
        end
        local legacy = overlay_settings.single_file_path
        if legacy and legacy ~= "" then
            return legacy
        end
    end

    return nil
end

--- Get sorted list of valid PNG files from the active folder.
function DisplayWidget:getPngFileList()
    if self.png_file_list then
        return self.png_file_list
    end

    local overlay_settings = self.props and self.props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then
        return nil
    end

    local folder = self:getActiveFolderPath()
    if not folder then
        return nil
    end

    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then
        return nil
    end

    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local lower = entry:lower()
            if lower:match("%.png$") then
                table.insert(files, entry)
            end
        end
    end

    table.sort(files)

    -- Filter by resolution
    local valid_files = {}
    for _, fname in ipairs(files) do
        local fpath = folder .. "/" .. fname
        local res_type = PngUtils.checkPngResolution(fpath)
        if res_type then
            table.insert(valid_files, { filename = fname, resolution_type = res_type })
        end
    end

    if #valid_files == 0 then
        return nil
    end

    self.png_file_list = valid_files
    return self.png_file_list
end

--- Get the current PNG file path and its resolution type.
function DisplayWidget:getCurrentPngPathAndType()
    local overlay_settings = self.props and self.props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then
        return nil, nil
    end

    local mode = overlay_settings.mode or "single"

    if mode == "single" then
        local single_path = self:getActiveSingleFilePath()
        if single_path then
            local res_type = PngUtils.checkPngResolution(single_path)
            if res_type then
                return single_path, res_type
            end
        end
        return nil, nil
    elseif mode == "cycle" then
        local files = self:getPngFileList()
        if not files or #files == 0 then
            return nil, nil
        end
        local folder = self:getActiveFolderPath()
        if not folder then
            return nil, nil
        end
        if self.png_cycle_index > #files then
            self.png_cycle_index = 1
        end
        local entry = files[self.png_cycle_index]
        return folder .. "/" .. entry.filename, entry.resolution_type
    end

    return nil, nil
end

--- Get the configured cycle interval in minutes
function DisplayWidget:getCycleMinutes()
    local overlay_settings = self.props and self.props.png_overlay
    if overlay_settings and overlay_settings.cycle_minutes then
        return overlay_settings.cycle_minutes
    end
    return 1
end

--- Check if full refresh on cycle is enabled
function DisplayWidget:isFullRefreshOnCycle()
    local overlay_settings = self.props and self.props.png_overlay
    if overlay_settings then
        return overlay_settings.full_refresh_on_cycle == true
    end
    return false
end

--- Cycle to the next PNG image based on configured interval.
function DisplayWidget:cyclePngOverlay()
    local overlay_settings = self.props and self.props.png_overlay
    if not overlay_settings or not overlay_settings.enabled then
        return
    end
    if overlay_settings.mode ~= "cycle" then
        return
    end

    local files = self:getPngFileList()
    if not files or #files == 0 then
        return
    end

    self.png_cycle_counter = self.png_cycle_counter + 1
    local cycle_minutes = self:getCycleMinutes()

    if self.png_cycle_counter >= cycle_minutes then
        self.png_cycle_counter = 0
        self.png_cycle_index = self.png_cycle_index + 1
        if self.png_cycle_index > #files then
            self.png_cycle_index = 1
        end

        -- Update the overlay widget with the new image
        self:updatePngOverlayWidget()

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
    if not png_path then
        return nil
    end

    local ImageWidget = require("ui/widget/imagewidget")
    local screen_size = Screen:getSize()
    local rotation_angle = PngUtils.getImageRotationAngle(res_type)

    local widget = ImageWidget:new {
        file = png_path,
        width = screen_size.w,
        height = screen_size.h,
        scale_factor = 0,
        alpha = true,
        rotation_angle = rotation_angle,
    }

    return widget
end

--- Update the overlay widget in-place for cycling.
function DisplayWidget:updatePngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then
        return
    end

    if self.png_overlay_widget and self.overlap_group then
        local ImageWidget = require("ui/widget/imagewidget")
        local screen_size = Screen:getSize()
        local rotation_angle = PngUtils.getImageRotationAngle(res_type)

        -- Free old image resources
        if self.png_overlay_widget.free then
            self.png_overlay_widget:free()
        end

        local new_widget = ImageWidget:new {
            file = png_path,
            width = screen_size.w,
            height = screen_size.h,
            scale_factor = 0,
            alpha = true,
            rotation_angle = rotation_angle,
        }

        self.png_overlay_widget = new_widget
        if self.overlap_group and #self.overlap_group >= 2 then
            self.overlap_group[2] = new_widget
        end
    end
end

function DisplayWidget:render()
    local screen_size = Screen:getSize()

    -- Insntiate widgets
    self.time_widget = RenderUtils.renderTimeWidget(
        self.now,
        screen_size.w,
        Font:getFace(
            self.props.time_widget.font_name,
            self.props.time_widget.font_size
        )
    )
    self.date_widget = RenderUtils.renderDateWidget(
        self.now,
        screen_size.w,
        Font:getFace(
            self.props.date_widget.font_name,
            self.props.date_widget.font_size
        ),
        true
    )
    self.status_widget = RenderUtils.renderStatusWidget(
        screen_size.w,
        Font:getFace(
            self.props.status_widget.font_name,
            self.props.status_widget.font_size
        )
    )

    -- Compute the widget heights and the amount of spacing we need
    local total_height = self.time_widget:getSize().h + self.date_widget:getSize().h + self.status_widget:getSize().h
    local spacer_height = (screen_size.h - total_height) / 2

    -- HELP: is there a better way of drawing blank space?
    local spacer_widget = TextBoxWidget:new {
        text = nil,
        face = Font:getFace("cfont"),
        width = screen_size.w,
        height = spacer_height
    }

    -- Lay out and assemble
    self.datetime_vertical_group = VerticalGroup:new {
        self.date_widget,
        self.time_widget,
        self.status_widget,
    }
    local vertical_group = VerticalGroup:new {
        spacer_widget,
        self.datetime_vertical_group,
        spacer_widget,
    }

    local clock_frame = FrameContainer:new {
        geom = Geom:new { w = screen_size.w, screen_size.h },
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOUR_WHITE,
        color = Blitbuffer.COLOUR_WHITE,
        width = screen_size.w,
        height = screen_size.h,
        vertical_group
    }

    -- Reset file list cache when rendering (orientation may have changed)
    self.png_file_list = nil

    -- Build PNG overlay if enabled
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

return DisplayWidget
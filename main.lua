local Dispatcher = require("dispatcher")
local DisplayWidget = require("displaywidget")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local LuaSettings = require("frontend/luasettings")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local cre -- delayed loading
local _ = require("gettext")
local T = require("ffi/util").template

local DtDisplay = WidgetContainer:extend {
    name = "dtdisplay",
    config_file = "dtdisplay_config.lua",
    local_storage = nil,
    is_doc_only = false,
}

function DtDisplay:init()
    self:initLuaSettings()

    self.settings = self.local_storage.data
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function DtDisplay:initLuaSettings()
    self.local_storage = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.config_file))
    if next(self.local_storage.data) == nil then
        self.local_storage:reset({
            date_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 25,
            },
            time_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 119,
            },
            status_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 24,
            },
            rotation = {
                follow_koreader = true,
                custom_rotation = 0,
            },
            png_overlay = {
                enabled = false,
                folder_path = "",
                portrait_folder_path = "",
                landscape_folder_path = "",
                mode = "single",
                single_file_path = "",
                single_file_path_portrait = "",
                single_file_path_landscape = "",
                cycle_minutes = 1,
                full_refresh_on_cycle = false,
            },
            suspend = {
                never_suspend = false,
                custom_timeout_enabled = false,
                custom_timeout_minutes = 60,
            },
        })
        self.local_storage:flush()
    end

    -- Migration: ensure rotation settings exist for users upgrading from older config
    if self.local_storage.data.rotation == nil then
        self.local_storage.data.rotation = {
            follow_koreader = true,
            custom_rotation = 0,
        }
        self.local_storage:flush()
    end

    -- Migration: ensure png_overlay settings exist
    if self.local_storage.data.png_overlay == nil then
        self.local_storage.data.png_overlay = {
            enabled = false,
            folder_path = "",
            portrait_folder_path = "",
            landscape_folder_path = "",
            mode = "single",
            single_file_path = "",
            single_file_path_portrait = "",
            single_file_path_landscape = "",
            cycle_minutes = 1,
            full_refresh_on_cycle = false,
        }
        self.local_storage:flush()
    end

    -- Migration: ensure cycle_minutes exists
    if self.local_storage.data.png_overlay.cycle_minutes == nil then
        self.local_storage.data.png_overlay.cycle_minutes = 1
        self.local_storage:flush()
    end

    -- Migration: ensure separate folder paths exist
    if self.local_storage.data.png_overlay.portrait_folder_path == nil then
        self.local_storage.data.png_overlay.portrait_folder_path = self.local_storage.data.png_overlay.folder_path or ""
        self.local_storage:flush()
    end
    if self.local_storage.data.png_overlay.landscape_folder_path == nil then
        self.local_storage.data.png_overlay.landscape_folder_path = self.local_storage.data.png_overlay.folder_path or ""
        self.local_storage:flush()
    end

    -- Migration: ensure separate single file paths exist
    if self.local_storage.data.png_overlay.single_file_path_portrait == nil then
        self.local_storage.data.png_overlay.single_file_path_portrait = self.local_storage.data.png_overlay.single_file_path or ""
        self.local_storage:flush()
    end
    if self.local_storage.data.png_overlay.single_file_path_landscape == nil then
        self.local_storage.data.png_overlay.single_file_path_landscape = self.local_storage.data.png_overlay.single_file_path or ""
        self.local_storage:flush()
    end

    -- Migration: ensure full_refresh_on_cycle exists
    if self.local_storage.data.png_overlay.full_refresh_on_cycle == nil then
        self.local_storage.data.png_overlay.full_refresh_on_cycle = false
        self.local_storage:flush()
    end

    -- Migration: ensure suspend settings exist
    if self.local_storage.data.suspend == nil then
        self.local_storage.data.suspend = {
            never_suspend = false,
            custom_timeout_enabled = false,
            custom_timeout_minutes = 60,
        }
        self.local_storage:flush()
    end

    if self.local_storage.data.widget_brightness == nil then
        self.local_storage.data.widget_brightness = -1
    end

    if self.local_storage.data.full_refresh_minutes == nil then
        self.local_storage.data.full_refresh_minutes = 0 -- 0 = disabled
    end

    if self.local_storage.data.clock_format == nil then
        self.local_storage.data.clock_format = "follow"
        self.local_storage:flush()
    end
end
----

function DtDisplay:addToMainMenu(menu_items)
    menu_items.dtdisplay = {
        text = _("Time & Day"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Launch"),
                separator = true,
                callback = function()
                    UIManager:show(DisplayWidget:new { props = self.settings })
                end,
            },
            {
                text = _("Date widget font"),
                sub_item_table = self:getFontMenuList(
                    {
                        font_callback = function(font_name)
                            self:setDateFont(font_name)
                        end,
                        font_size_callback = function(font_size)
                            self:setDateFontSize(font_size)
                        end,
                        font_size_func = function()
                            return self.settings.date_widget.font_size
                        end,
                        checked_func = function(font)
                            return font == self.settings.date_widget.font_name
                        end
                    }
                ),
            },
            {
                text = _("Time widget font"),
                sub_item_table = self:getFontMenuList(
                    {
                        font_callback = function(font_name)
                            self:setTimeFont(font_name)
                        end,
                        font_size_callback = function(font_size)
                            self:setTimeFontSize(font_size)
                        end,
                        font_size_func = function()
                            return self.settings.time_widget.font_size
                        end,
                        checked_func = function(font)
                            return font == self.settings.time_widget.font_name
                        end
                    }
                ),
            },
            {
                text = _("Status line font"),
                sub_item_table = self:getFontMenuList(
                    {
                        font_callback = function(font_name)
                            self:setStatuslineFont(font_name)
                        end,
                        font_size_callback = function(font_size)
                            self:setStatuslineFontSize(font_size)
                        end,
                        font_size_func = function()
                            return self.settings.status_widget.font_size
                        end,
                        checked_func = function(font)
                            return font == self.settings.status_widget.font_name
                        end
                    }
                ),
            },
            {
                text = _("Clock orientation"),
                separator = false,
                sub_item_table = self:getRotationMenuList(),
            },
            {
                text = _("Clock format"),
                separator = false,
                sub_item_table = self:getClockFormatMenuList(),
            },
            {
                text = _("Suspend settings"),
                separator = false,
                sub_item_table = self:getSuspendMenuList(),
            },
            {
                text = _("PNG overlay"),
                separator = false,
                sub_item_table = self:getPngOverlayMenuList(),
            },
            {
                text = _("Widget Brightness"),
                separator = false,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:showBrightnessSpinWidget(touchmenu_instance, self.settings.widget_brightness, function(new_val)
                        self.settings.widget_brightness = new_val
                        -- Save the setting immediately when changed
                        self.local_storage:reset(self.settings)
                        self.local_storage:flush()
                    end)
                end,
            },
            {
                text_func = function()
                    local total = self.settings.full_refresh_minutes or 0
                    if total == 0 then
                        return _("Full refresh: disabled")
                    end

                    local h = math.floor(total / 60)
                    local m = total % 60
                    if h == 0 then 
                        return T(_("Full refresh: every %1 min"), m)
                    elseif m == 0 then
                        return T(_("Full refresh: every %1 h"), h)
                    else
                        return T(_("Full refresh: every %1 h %2 min"), h, m)
                    end
                end,
                
                keep_menu_open = true,
            
                callback = function(touchmenu_instance)
                    self:showFullRefreshSpinWidget(touchmenu_instance)
                end,
            },
        },
    }
end

function DtDisplay:getRotationMenuList()
    local rotation_labels = {
        [0] = _("0° (Portrait)"),
        [1] = _("90° (Landscape clockwise)"),
        [2] = _("180° (Portrait inverted)"),
        [3] = _("270° (Landscape counter-clockwise)"),
    }

    local menu_list = {
        {
            text = _("Follow KOReader orientation"),
            checked_func = function()
                return self.settings.rotation.follow_koreader
            end,
            callback = function()
                self:setRotationFollowKOReader(true)
            end,
            separator = true,
        },
    }

    for rotation = 0, 3 do
        table.insert(menu_list, {
            text = rotation_labels[rotation],
            checked_func = function()
                return not self.settings.rotation.follow_koreader
                    and self.settings.rotation.custom_rotation == rotation
            end,
            callback = function()
                self:setCustomRotation(rotation)
            end,
        })
    end

    return menu_list
end

function DtDisplay:getClockFormatMenuList()
    return {
        {
            text = _("Follow KOReader setting"),
            checked_func = function()
                return self.settings.clock_format == "follow"
            end,
            callback = function()
                self:setClockFormat("follow")
            end,
            separator = true,
        },
        {
            text = _("24-hour"),
            checked_func = function()
                return self.settings.clock_format == "24"
            end,
            callback = function()
                self:setClockFormat("24")
            end,
        },
        {
            text = _("12-hour (AM/PM)"),
            checked_func = function()
                return self.settings.clock_format == "12"
            end,
            callback = function()
                self:setClockFormat("12")
            end,
        },
    }
end

function DtDisplay:setClockFormat(fmt)
    self.settings.clock_format = fmt
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end


function DtDisplay:setRotationFollowKOReader(follow)
    self.settings.rotation.follow_koreader = follow
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setCustomRotation(rotation)
    self.settings.rotation.follow_koreader = false
    self.settings.rotation.custom_rotation = rotation
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Build the suspend settings submenu
function DtDisplay:getSuspendMenuList()
    local menu_list = {}

    -- Never suspend
    table.insert(menu_list, {
        text = _("Never suspend while clock is running"),
        checked_func = function()
            return self.settings.suspend.never_suspend
        end,
        callback = function()
            self.settings.suspend.never_suspend = not self.settings.suspend.never_suspend
            if self.settings.suspend.never_suspend then
                self.settings.suspend.custom_timeout_enabled = false
            end
            self:saveSuspendSettings()
        end,
        separator = true,
    })

    -- Custom timeout toggle
    table.insert(menu_list, {
        text = _("Use custom suspend timeout"),
        checked_func = function()
            return self.settings.suspend.custom_timeout_enabled
        end,
        enabled_func = function()
            return not self.settings.suspend.never_suspend
        end,
        callback = function()
            self.settings.suspend.custom_timeout_enabled = not self.settings.suspend.custom_timeout_enabled
            self:saveSuspendSettings()
        end,
    })

    -- Custom timeout value
    table.insert(menu_list, {
        text_func = function()
            local mins = self.settings.suspend.custom_timeout_minutes or 60
            if mins == 1 then
                return T(_("Suspend timeout: %1 minute"), mins)
            else
                return T(_("Suspend timeout: %1 minutes"), mins)
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            return self.settings.suspend.custom_timeout_enabled and not self.settings.suspend.never_suspend
        end,
        callback = function(touchmenu_instance)
            self:showSuspendTimeoutSpinWidget(touchmenu_instance)
        end,
        separator = true,
    })

    -- Info: current behavior
    table.insert(menu_list, {
        text_func = function()
            if self.settings.suspend.never_suspend then
                return _("Status: Auto-suspend disabled while clock runs")
            elseif self.settings.suspend.custom_timeout_enabled then
                return T(_("Status: Custom timeout of %1 min"), self.settings.suspend.custom_timeout_minutes or 60)
            else
                return _("Status: Using KOReader default suspend")
            end
        end,
        keep_menu_open = true,
        callback = function() end,
    })

    return menu_list
end

--- Save suspend settings
function DtDisplay:saveSuspendSettings()
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Show spin widget for suspend timeout
function DtDisplay:showSuspendTimeoutSpinWidget(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    local current_value = self.settings.suspend.custom_timeout_minutes or 60
    UIManager:show(
        SpinWidget:new {
            value = current_value,
            value_min = 1,
            value_max = 480,
            value_step = 1,
            value_hold_step = 10,
            ok_text = _("Set timeout"),
            title_text = _("Suspend timeout (minutes)"),
            callback = function(spin)
                self.settings.suspend.custom_timeout_minutes = spin.value
                self:saveSuspendSettings()
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        }
    )
end

--- Get the recommended resolution string based on current screen size
function DtDisplay:getRecommendedResolutionText()
    local screen_size = Screen:getSize()
    local sw, sh = screen_size.w, screen_size.h
    local pw, ph
    if sw > sh then
        pw, ph = sh, sw
    else
        pw, ph = sw, sh
    end
    return T(_("Recommended: %1x%2 (portrait) / %3x%4 (landscape)"), pw, ph, ph, pw)
end

--- Build the PNG overlay submenu
function DtDisplay:getPngOverlayMenuList()
    local menu_list = {}

    -- Info: recommended resolution
    table.insert(menu_list, {
        text_func = function()
            return self:getRecommendedResolutionText()
        end,
        keep_menu_open = true,
        callback = function() end,
        separator = true,
    })

    -- Toggle: enable/disable overlay
    table.insert(menu_list, {
        text = _("Enable PNG overlay"),
        checked_func = function()
            return self.settings.png_overlay.enabled
        end,
        callback = function()
            self.settings.png_overlay.enabled = not self.settings.png_overlay.enabled
            self:savePngOverlaySettings()
        end,
        separator = true,
    })

    -- Portrait folder selection
    table.insert(menu_list, {
        text_func = function()
            local folder = self.settings.png_overlay.portrait_folder_path
            if folder and folder ~= "" then
                local short = folder:match("([^/]+)$") or folder
                return T(_("Portrait PNG folder: %1"), short)
            else
                return _("Select portrait PNG folder")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showPngFolderChooser(touchmenu_instance, "portrait")
        end,
    })

    -- Landscape folder selection
    table.insert(menu_list, {
        text_func = function()
            local folder = self.settings.png_overlay.landscape_folder_path
            if folder and folder ~= "" then
                local short = folder:match("([^/]+)$") or folder
                return T(_("Landscape PNG folder: %1"), short)
            else
                return _("Select landscape PNG folder")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showPngFolderChooser(touchmenu_instance, "landscape")
        end,
        separator = true,
    })

    -- Select single PNG file for portrait
    table.insert(menu_list, {
        text_func = function()
            local fpath = self.settings.png_overlay.single_file_path_portrait
            if fpath and fpath ~= "" then
                local fname = fpath:match("([^/]+)$") or fpath
                return T(_("Portrait file: %1"), fname)
            else
                return _("Select a portrait PNG file")
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            local folder = self.settings.png_overlay.portrait_folder_path
            return folder and folder ~= ""
        end,
        callback = function(touchmenu_instance)
            self:showPngFileSelector(touchmenu_instance, "portrait")
        end,
    })

    -- Select single PNG file for landscape
    table.insert(menu_list, {
        text_func = function()
            local fpath = self.settings.png_overlay.single_file_path_landscape
            if fpath and fpath ~= "" then
                local fname = fpath:match("([^/]+)$") or fpath
                return T(_("Landscape file: %1"), fname)
            else
                return _("Select a landscape PNG file")
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            local folder = self.settings.png_overlay.landscape_folder_path
            return folder and folder ~= ""
        end,
        callback = function(touchmenu_instance)
            self:showPngFileSelector(touchmenu_instance, "landscape")
        end,
        separator = true,
    })

    -- Image selection mode: single
    table.insert(menu_list, {
        text = _("Use single image"),
        checked_func = function()
            return self.settings.png_overlay.mode == "single"
        end,
        callback = function()
            self.settings.png_overlay.mode = "single"
            self:savePngOverlaySettings()
        end,
    })

    -- Image selection mode: cycle
    table.insert(menu_list, {
        text = _("Cycle through all images in folder"),
        checked_func = function()
            return self.settings.png_overlay.mode == "cycle"
        end,
        callback = function()
            self.settings.png_overlay.mode = "cycle"
            self:savePngOverlaySettings()
        end,
        separator = true,
    })

    -- Cycle interval setting
    table.insert(menu_list, {
        text_func = function()
            local mins = self.settings.png_overlay.cycle_minutes or 1
            if mins == 1 then
                return T(_("Cycle interval: %1 minute"), mins)
            else
                return T(_("Cycle interval: %1 minutes"), mins)
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            return self.settings.png_overlay.mode == "cycle"
        end,
        callback = function(touchmenu_instance)
            self:showCycleIntervalSpinWidget(touchmenu_instance)
        end,
        separator = true,
    })

    -- Full refresh on cycle toggle
    table.insert(menu_list, {
        text = _("Full screen refresh on image change"),
        checked_func = function()
            return self.settings.png_overlay.full_refresh_on_cycle
        end,
        callback = function()
            self.settings.png_overlay.full_refresh_on_cycle = not self.settings.png_overlay.full_refresh_on_cycle
            self:savePngOverlaySettings()
        end,
    })

    return menu_list
end

--- Save PNG overlay settings to persistent storage
function DtDisplay:savePngOverlaySettings()
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Show folder chooser dialog for PNG folder selection
function DtDisplay:showPngFolderChooser(touchmenu_instance, orientation_type)
    local PathChooser = require("ui/widget/pathchooser")
    local setting_key
    if orientation_type == "portrait" then
        setting_key = "portrait_folder_path"
    else
        setting_key = "landscape_folder_path"
    end

    local start_path = self.settings.png_overlay[setting_key]
    if not start_path or start_path == "" then
        start_path = DataStorage:getDataDir()
    end

    local path_chooser = PathChooser:new {
        select_directory = true,
        select_file = false,
        path = start_path,
        onConfirm = function(chosen_path)
            self.settings.png_overlay[setting_key] = chosen_path
            self.settings.png_overlay.folder_path = chosen_path
            if orientation_type == "portrait" then
                self.settings.png_overlay.single_file_path_portrait = ""
            else
                self.settings.png_overlay.single_file_path_landscape = ""
            end
            self:savePngOverlaySettings()
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }
    UIManager:show(path_chooser)
end

--- Show file selector dialog to pick a single PNG.
function DtDisplay:showPngFileSelector(touchmenu_instance, orientation_type)
    local folder_key, file_key
    if orientation_type == "portrait" then
        folder_key = "portrait_folder_path"
        file_key = "single_file_path_portrait"
    else
        folder_key = "landscape_folder_path"
        file_key = "single_file_path_landscape"
    end

    local folder = self.settings.png_overlay[folder_key]
    if not folder or folder == "" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = _("Please select a PNG folder first."),
        })
        return
    end

    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = _("Cannot open the selected folder."),
        })
        return
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

    local valid_files = {}
    local screen_size = Screen:getSize()
    local sw, sh = screen_size.w, screen_size.h
    local native_w, native_h
    if sw > sh then
        native_w, native_h = sh, sw
    else
        native_w, native_h = sw, sh
    end

    for _, fname in ipairs(files) do
        local fpath = folder .. "/" .. fname
        local img_w, img_h = self:readPngDimensions(fpath)
        if img_w and img_h then
            if (img_w == native_w and img_h == native_h) or (img_w == native_h and img_h == native_w) then
                table.insert(valid_files, fname)
            end
        end
    end

    if #valid_files == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = T(_("No PNG files with valid resolution found.\nExpected: %1x%2 or %3x%4"), native_w, native_h, native_h, native_w),
        })
        return
    end

    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local buttons = {}
    for _, fname in ipairs(valid_files) do
        table.insert(buttons, {
            {
                text = fname,
                callback = function()
                    self.settings.png_overlay[file_key] = folder .. "/" .. fname
                    self.settings.png_overlay.single_file_path = folder .. "/" .. fname
                    self:savePngOverlaySettings()
                    UIManager:close(self._png_file_dialog)
                    self._png_file_dialog = nil
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        })
    end

    self._png_file_dialog = ButtonDialogTitle:new {
        title = T(_("Select a %1 PNG file"), orientation_type),
        buttons = buttons,
    }
    UIManager:show(self._png_file_dialog)
end

--- Read PNG dimensions from file header.
function DtDisplay:readPngDimensions(filepath)
    local f = io.open(filepath, "rb")
    if not f then
        return nil, nil
    end
    local header = f:read(24)
    f:close()
    if not header or #header < 24 then
        return nil, nil
    end
    local png_sig = "\137PNG\r\n\026\n"
    if header:sub(1, 8) ~= png_sig then
        return nil, nil
    end
    local function read_be_uint32(s, offset)
        local b1, b2, b3, b4 = s:byte(offset, offset + 3)
        return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end
    local w = read_be_uint32(header, 17)
    local h = read_be_uint32(header, 21)
    return w, h
end

--- Show spin widget for cycle interval setting
function DtDisplay:showCycleIntervalSpinWidget(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    local current_value = self.settings.png_overlay.cycle_minutes or 1
    UIManager:show(
        SpinWidget:new {
            value = current_value,
            value_min = 1,
            value_max = 120,
            value_step = 1,
            value_hold_step = 5,
            ok_text = _("Set interval"),
            title_text = _("Image cycle interval (minutes)"),
            callback = function(spin)
                self.settings.png_overlay.cycle_minutes = spin.value
                self:savePngOverlaySettings()
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        }
    )
end

function DtDisplay:getFontMenuList(args)
    -- Unpack arguments
    local font_callback = args.font_callback
    local font_size_callback = args.font_size_callback
    local font_size_func = args.font_size_func
    local checked_func = args.checked_func

    -- Based on readerfont.lua
    cre = require("document/credocument"):engineInit()
    local face_list = cre.getFontFaces()
    local menu_list = {}

    -- Font size
    table.insert(menu_list, {
        text_func = function()
            return T(_("Font size: %1"), font_size_func())
        end,
        callback = function(touchmenu_instance)
            self:showFontSizeSpinWidget(touchmenu_instance, font_size_func(), font_size_callback)
        end,
        keep_menu_open = true,
        separator = true
    })

    -- Font list
    for k, v in ipairs(face_list) do
        local font_filename, font_faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(v)
        table.insert(menu_list, {
            text_func = function()
                local default_font = G_reader_settings:readSetting("cre_font")
                local fallback_font = G_reader_settings:readSetting("fallback_font")
                local monospace_font = G_reader_settings:readSetting("monospace_font")
                local text = v
                if font_filename and font_faceindex then
                    text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                end

                if v == monospace_font then
                    text = text .. " \u{1F13C}"
                elseif is_monospace then
                    text = text .. " \u{1D39}"
                end
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   "
                end
                return text
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if font_filename and font_faceindex then
                        return Font:getFace(font_filename, size, font_faceindex)
                    end
                end
            end,
            callback = function()
                return font_callback(font_filename)
            end,
            hold_callback = function(touchmenu_instance)
            end,
            checked_func = function()
                return checked_func(font_filename)
            end,
            menu_item_id = v,
        })
    end

    return menu_list
end

function DtDisplay:setDateFont(font)
    self.settings["date_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setTimeFont(font)
    self.settings["time_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setStatuslineFont(font)
    self.settings["status_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setDateFontSize(font_size)
    self.settings["date_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setTimeFontSize(font_size)
    self.settings["time_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setStatuslineFontSize(font_size)
    self.settings["status_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:showDateTimeWidget()
    UIManager:show(DisplayWidget:new {})
end

function DtDisplay:onDTDisplayLaunch()
    UIManager:show(DisplayWidget:new { props = self.settings })
end

function DtDisplay:showFontSizeSpinWidget(touchmenu_instance, font_size, callback)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(
        SpinWidget:new {
            value = font_size,
            value_min = 8,
            value_max = 256,
            value_step = 1,
            value_hold_step = 10,
            ok_text = _("Set font size"),
            title_text = _("Set font size"),
            callback = function(spin)
                callback(spin.value)
                touchmenu_instance:updateItems()
            end
        }
    )
end

function DtDisplay:onDispatcherRegisterActions()
    Dispatcher:registerAction("dtdisplay_launch", { category="none", event="DTDisplayLaunch", title=_("Launch Time & Day"), general=true})
end

function DtDisplay:showBrightnessSpinWidget(touchmenu_instance, current_brightness, callback)
    local SpinWidget = require("ui/widget/spinwidget")
    local max_intensity = 24
    if Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        if powerd and powerd.fl_max then
            max_intensity = powerd.fl_max
        end
    end
    UIManager:show(
        SpinWidget:new {
            value = current_brightness,
            value_min = -1, -- Allow -1 to disable the feature
            value_max = max_intensity,
            value_step = 1,
            value_hold_step = 5,
            ok_text = _("Set brightness"),
            title_text = _("Widget Brightness (-1 to disable)"),
            callback = function(spin)
                callback(spin.value)
                touchmenu_instance:updateItems()
            end
        }
    )
end

function DtDisplay:showFullRefreshSpinWidget(touchmenu_instance)
    local total_minutes = self.settings.full_refresh_minutes or 0
    local current_hours = math.floor(total_minutes / 60)
    local current_minutes = total_minutes % 60

    local DateTimeWidget = require("ui/widget/datetimewidget")

    UIManager:show(DateTimeWidget:new {
        hour = current_hours,
        min = current_minutes,
        ok_text = _("Set interval"),
        title_text = _("Full refresh interval (0h 0min = disabled)"),
        callback = function(time)
            local total = time.hour * 60 + time.min
            self.settings.full_refresh_minutes = total
            self.local_storage:reset(self.settings)
            self.local_storage:flush()
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    })
end

return DtDisplay
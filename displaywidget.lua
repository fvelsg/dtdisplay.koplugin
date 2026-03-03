-- displaywidget.lua

local Blitbuffer     = require("ffi/blitbuffer")
local Date           = os.date
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare    = require("pluginshare")
local Screen         = Device.screen
local UIManager      = require("ui/uimanager")

local StatusUtils = require("statusutils")
local PngUtils    = require("pngutils")
local TimeUtils   = require("timeutils")
local RenderUtils = require("renderutils")
local SystemUtils = require("systemutils")

local T = require("ffi/util").template
local _ = require("gettext")


-- Helper to safely clone base settings so image configs don't permanently overwrite them
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deep_copy(v) end
    return res
end



local function makeTransparent(widget)
    widget.paintTo = function(self, bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        -- self._bb has white background (255) and black glyphs (0).
        -- colorblitFrom treats src=255 as "paint" and src=0 as "skip" — 
        -- exactly backwards. Invert _bb so glyphs=255 (paint) and
        -- background=0 (skip), blit black glyphs onto bb leaving the PNG
        -- underneath untouched, then restore _bb to its original state.
        local w = self.width
        local h = self._bb:getHeight()
        self._bb:invertRect(0, 0, w, h)
        bb:colorblitFrom(self._bb, x, y, 0, 0, w, h, Blitbuffer.COLOR_BLACK)
        self._bb:invertRect(0, 0, w, h)
    end
    return widget
end

-- ---------------------------------------------------------------------------
-- Load a PNG as a true BBRGB32 buffer with the alpha channel fully intact,
-- so that bb:blitFrom() can alpha-composite it correctly onto the display.
--
-- ROOT CAUSE OF THE ORIGINAL BUG
-- --------------------------------
-- KOReader's MuPDF renderer defaults to Mupdf.color = false on e-ink devices.
-- In this mode MuPDF renders every image to grayscale (BB8) internally,
-- compositing the alpha channel against white during that step.  By the time
-- renderImageFile() returns, the buffer is already BB8 with no alpha — the
-- transparent pixels have been baked to white.  This happened with every
-- approach tried so far:
--   • ImageWidget(alpha=true)   → still routed through MuPDF grayscale path
--   • RenderImage:renderImageFile → same grayscale path
--   • Mupdf.renderImageFile without color=true → still grayscale, and the
--     returned dimensions differed from ImageWidget's, breaking light mode
--
-- THE FIX
-- --------
-- Temporarily set Mupdf.color = true before calling renderImageFile.  This
-- forces MuPDF to render in RGBA (BBRGB32), preserving per-pixel alpha.
-- KOReader's C blitbuffer then correctly alpha-composites BBRGB32 → BB8:
--   alpha = 0   → destination pixel left untouched  (transparent)
--   alpha = 255 → destination pixel fully overwritten (opaque)
--   0 < alpha < 255 → proportional blend            (antialiased edge)
-- Because blitFrom composites against whatever is already in the destination
-- buffer, this also fixes night-mode path A automatically: the PNG is painted
-- after the screen inversion, so the background is already black, and
-- transparent pixels stay black rather than showing as white.
-- ---------------------------------------------------------------------------
local function loadPngWidget(png_path, width, height, rotation_angle)
    local img_bb

    local ok_m, Mupdf = pcall(require, "ffi/mupdf")
    if ok_m and Mupdf then
        -- Save and override the color flag so MuPDF returns BBRGB32 + alpha.
        -- Always restore it, even if renderImageFile throws.
        local saved_color = Mupdf.color
        Mupdf.color = true
        local ok_r, result = pcall(function()
            return Mupdf.renderImageFile(png_path, width, height)
        end)
        Mupdf.color = saved_color
        if ok_r and result then
            img_bb = result
        end
    end

    -- Fallback: ImageWidget-style load.  Alpha is pre-composited to white by
    -- MuPDF, so transparent areas will show as white — same as the original
    -- behaviour.  Better than showing nothing if Mupdf is unavailable.
    if not img_bb then
        local ok_ri, RenderImage = pcall(require, "ui/renderimage")
        if ok_ri and RenderImage then
            local ok_r2, result2 = pcall(function()
                return RenderImage:renderImageFile(png_path, false, width, height)
            end)
            if ok_r2 and result2 then
                img_bb = result2
            end
        end
    end

    if not img_bb then return nil end

    -- Rotate when needed (e.g. landscape-format PNG displayed in portrait).
    -- rotatedCopy() accepts degrees: 0, 90, 180, 270.
    if rotation_angle and rotation_angle ~= 0 then
        local rotated = img_bb:rotatedCopy(rotation_angle)
        img_bb:free()
        img_bb = rotated
        if not img_bb then return nil end
    end

    local iw = img_bb:getWidth()
    local ih = img_bb:getHeight()

    return {
        _img_bb = img_bb,
        dimen   = Geom:new{ x = 0, y = 0, w = iw, h = ih },

        getSize = function(self)
            return Geom:new{ w = self._img_bb:getWidth(), h = self._img_bb:getHeight() }
        end,

        -- alphablitFrom reads per-pixel alpha from the BBRGB32 source:
        --   alpha = 0   → pixel skipped, destination unchanged (transparent)
        --   alpha = 255 → pixel fully overwrites destination (opaque)
        --   0 < alpha < 255 → proportional blend (antialiased edges)
        --
        -- blitFrom must NOT be used here: it ignores alpha entirely, converting
        -- premultiplied RGBA pixels with A=0 straight to gray=0 (black), making
        -- transparent areas render as black instead of showing the background.
        paintTo = function(self, bb, x, y)
            self.dimen.x = x
            self.dimen.y = y
            bb:alphablitFrom(self._img_bb, x, y, 0, 0,
                             self._img_bb:getWidth(), self._img_bb:getHeight(), 0xFF)
        end,

        free = function(self)
            if self._img_bb then
                self._img_bb:free()
                self._img_bb = nil
            end
        end,
    }
end


local function toAbsolute(coord, screen_dim, widget_dim, unit)
    local offset
    if unit == "%" then
        offset = (coord / 100) * screen_dim
    else
        offset = coord
    end
    return math.floor(screen_dim / 2 - widget_dim / 2 + offset)
end




-- local DEFAULT_ELEMENTS = {
--     png    = { x = 0, y =   0, unit = "px", z = 1, visible = true },
--     date   = { x = 0, y = -20, unit = "%",  z = 2, visible = true },
--     time   = { x = 0, y =   0, unit = "px", z = 2, visible = true },
--     status = { x = 0, y =  20, unit = "%",  z = 2, visible = true },
-- }

local DEFAULT_ELEMENTS = {
    png     = { x = 0, y =   0, unit = "px", z = 1, visible = true },
    date    = { x = 0, y = -20, unit = "%",  z = 2, visible = true },
    time    = { x = 0, y =   0, unit = "px", z = 2, visible = true },
    status  = { x = 0, y =  20, unit = "%",  z = 2, visible = true },
    wifi    = { x = 0, y =  30, unit = "%",  z = 2, visible = false },
    battery = { x = 0, y =  35, unit = "%",  z = 2, visible = false },
    memory  = { x = 0, y =  40, unit = "%",  z = 2, visible = false },
}

local DisplayWidget = InputContainer:extend {
    props      = {},
    plugin_dir = "",
}

local function isDisplayInverted(props)
    local setting = props and props.night_mode or "follow"
    local koreader_night = G_reader_settings:isTrue("night_mode")
    
    if setting == "night" then return true end
    if setting == "normal" then return false end
    return koreader_night -- "follow" case
end


function DisplayWidget:init()
    self.now              = os.time()
    self.is_closing       = false
    self.render_list      = {}
    
    -- Store original props as the baseline
    self.base_props = deep_copy(self.props)
    self._using_custom_config = false

    self.png_cycle_index      = 1
    self.png_cycle_counter    = 0
    self.full_refresh_counter = 0
    self.png_file_list        = nil

    self.dimen = Geom:new {
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    self.original_rotation = Screen:getRotationMode()
    self:applyClockRotation()

    self.autoRefresh = function()
        self:refresh()
        return UIManager:scheduleIn(60 - tonumber(Date("%S")), self.autoRefresh)
    end

    self.ges_events.TapClose = {
        GestureRange:new {
            ges   = "tap",
            range = Geom:new {
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
        }
    }
    self.covers_fullscreen = true

    -- Load the baseline elements.lua
    local elements_path = self.plugin_dir .. "elements.lua"
    local ok, file_elements = pcall(dofile, elements_path)
    if not ok or type(file_elements) ~= "table" then
        file_elements = {}
    end

    self.base_elements = {}
    for name, defaults in pairs(DEFAULT_ELEMENTS) do
        local user = file_elements[name] or {}
        self.base_elements[name] = {
            x       = user.x ~= nil and user.x or defaults.x,
            y       = user.y ~= nil and user.y or defaults.y,
            unit    = user.unit or defaults.unit,
            z       = user.z   ~= nil and user.z or defaults.z,
            visible = user.visible ~= false,
        }
    end

    -- Dynamically load image config (if any) and sync night mode
    self._using_custom_config = self:applyImageProps()
    self:syncStateFlags()

    self:render()
    UIManager:setDirty("all", "full")

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

function DisplayWidget:render()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    -- Robust helper: Checks advanced_settings first, then falls back to status default
    local function getFont(widget_name)
        local w_props = self.props[widget_name] or {}
        local name = w_props.font_name or self.props.status_widget.font_name
        local size = w_props.font_size or self.props.status_widget.font_size
        return Font:getFace(name, size)
    end

    self.time_widget = makeTransparent(RenderUtils.renderTimeWidget(
        self.now, sw,
        Font:getFace(self.props.time_widget.font_name, self.props.time_widget.font_size),
        self.props.clock_format
    ))
    self.date_widget = makeTransparent(RenderUtils.renderDateWidget(
        self.now, sw,
        Font:getFace(self.props.date_widget.font_name, self.props.date_widget.font_size),
        true
    ))
    self.status_widget = makeTransparent(RenderUtils.renderStatusWidget(
        sw,
        Font:getFace(self.props.status_widget.font_name, self.props.status_widget.font_size)
    ))

    -- Initialize new individual widgets with separate font control
    self.wifi_widget    = makeTransparent(RenderUtils.renderWifiWidget(sw, getFont("wifi_widget")))
    self.memory_widget  = makeTransparent(RenderUtils.renderMemoryWidget(sw, getFont("memory_widget")))
    
    local batt_props  = self.props.battery_widget or {}
    local batt_format = batt_props.format or "both"
    self.battery_widget = makeTransparent(RenderUtils.renderBatteryWidget(sw, getFont("battery_widget"), batt_format))

    self.png_file_list      = nil
    self.png_overlay_widget = self:createPngOverlayWidget()

    self.render_list = {}

    local function addWidget(name, widget)
        local elem = self.elements[name]
        if not elem or not elem.visible then return end
        local size = widget:getSize()
        table.insert(self.render_list, {
            widget = widget,
            px     = toAbsolute(elem.x, sw, size.w, elem.unit),
            py     = toAbsolute(elem.y, sh, size.h, elem.unit),
            z      = elem.z,
            is_png = false,
        })
    end

    addWidget("time",    self.time_widget)
    addWidget("date",    self.date_widget)
    addWidget("status",  self.status_widget)
    addWidget("wifi",    self.wifi_widget)
    addWidget("battery", self.battery_widget)
    addWidget("memory",  self.memory_widget)

    local png_elem = self.elements["png"]
    if self.png_overlay_widget and png_elem and png_elem.visible then
        table.insert(self.render_list, {
            widget = self.png_overlay_widget,
            px     = toAbsolute(png_elem.x, sw, sw, png_elem.unit),
            py     = toAbsolute(png_elem.y, sh, sh, png_elem.unit),
            z      = png_elem.z,
            is_png = true,
        })
    end

    table.sort(self.render_list, function(a, b) return a.z < b.z end)
end

function DisplayWidget:render()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    -- Robust helper: Checks advanced_settings first, then falls back to status default
    local function getFont(widget_name)
        local w_props = self.props[widget_name] or {}
        local name = w_props.font_name or self.props.status_widget.font_name
        local size = w_props.font_size or self.props.status_widget.font_size
        return Font:getFace(name, size)
    end

    self.time_widget = makeTransparent(RenderUtils.renderTimeWidget(
        self.now, sw,
        Font:getFace(self.props.time_widget.font_name, self.props.time_widget.font_size),
        self.props.clock_format
    ))
    self.date_widget = makeTransparent(RenderUtils.renderDateWidget(
        self.now, sw,
        Font:getFace(self.props.date_widget.font_name, self.props.date_widget.font_size),
        true
    ))
    self.status_widget = makeTransparent(RenderUtils.renderStatusWidget(
        sw,
        Font:getFace(self.props.status_widget.font_name, self.props.status_widget.font_size)
    ))

    -- Initialize new individual widgets with separate font control
    self.wifi_widget    = makeTransparent(RenderUtils.renderWifiWidget(sw, getFont("wifi_widget")))
    self.memory_widget  = makeTransparent(RenderUtils.renderMemoryWidget(sw, getFont("memory_widget")))
    
    local batt_props  = self.props.battery_widget or {}
    local batt_format = batt_props.format or "both"
    self.battery_widget = makeTransparent(RenderUtils.renderBatteryWidget(sw, getFont("battery_widget"), batt_format))

    self.png_file_list      = nil
    self.png_overlay_widget = self:createPngOverlayWidget()

    self.render_list = {}

    local function addWidget(name, widget)
        local elem = self.elements[name]
        if not elem or not elem.visible then return end
        local size = widget:getSize()
        table.insert(self.render_list, {
            widget = widget,
            px     = toAbsolute(elem.x, sw, size.w, elem.unit),
            py     = toAbsolute(elem.y, sh, size.h, elem.unit),
            z      = elem.z,
            is_png = false,
        })
    end

    addWidget("time",    self.time_widget)
    addWidget("date",    self.date_widget)
    addWidget("status",  self.status_widget)
    addWidget("wifi",    self.wifi_widget)
    addWidget("battery", self.battery_widget)
    addWidget("memory",  self.memory_widget)

    local png_elem = self.elements["png"]
    if self.png_overlay_widget and png_elem and png_elem.visible then
        table.insert(self.render_list, {
            widget = self.png_overlay_widget,
            px     = toAbsolute(png_elem.x, sw, sw, png_elem.unit),
            py     = toAbsolute(png_elem.y, sh, sh, png_elem.unit),
            z      = png_elem.z,
            is_png = true,
        })
    end

    table.sort(self.render_list, function(a, b) return a.z < b.z end)
end

function DisplayWidget:syncStateFlags()
    local is_dark = isDisplayInverted(self.props)
    local system_night = G_reader_settings:isTrue("night_mode")
    
    self.apply_manual_inversion = (is_dark == true and system_night == false)
    
    self.invert_png_overlay = true
    if self.props.png_overlay and self.props.png_overlay.invert_with_night_mode == false then
        self.invert_png_overlay = false
    end
end

function DisplayWidget:applyImageProps()
    -- Always reset to the baseline UI/Advanced settings first
    self.props = deep_copy(self.base_props)
    self.elements = deep_copy(self.base_elements)

    -- Abort if the feature is turned off in the UI
    if not self.props.png_overlay or not self.props.png_overlay.use_image_config then
        return false 
    end

    local png_path = self:getCurrentPngPathAndType()
    if not png_path then return false end

    -- Convert /path/to/image.png -> /path/to/image.lua (handles .PNG or .png)
    local config_path = png_path:gsub("%.[pP][nN][gG]$", ".lua")
    
    local ok, img_cfg = pcall(dofile, config_path)
    if not ok or type(img_cfg) ~= "table" then
        return false -- File doesn't exist or has syntax errors
    end

    -- Merge custom standard properties
    for k, v in pairs(img_cfg) do
        if k ~= "elements" then 
            if type(v) == "table" and type(self.props[k]) == "table" then
                for k2, v2 in pairs(v) do
                    if v2 ~= nil then self.props[k][k2] = v2 end
                end
            elseif v ~= nil then
                self.props[k] = v
            end
        end
    end

    -- Merge custom positioning/layout elements
    if img_cfg.elements then
        for name, user in pairs(img_cfg.elements) do
            if self.elements[name] then
                if user.x ~= nil then self.elements[name].x = user.x end
                if user.y ~= nil then self.elements[name].y = user.y end
                if user.unit ~= nil then self.elements[name].unit = user.unit end
                if user.z ~= nil then self.elements[name].z = user.z end
                if user.visible ~= nil then self.elements[name].visible = user.visible end
            end
        end
    end

    return true -- Successfully loaded and applied a custom image config
end

function DisplayWidget:update()
    local time_text   = TimeUtils.getTimeText(self.now, self.props.clock_format)
    local date_text   = TimeUtils.getDateText(self.now, true)
    local status_text = StatusUtils.getStatusText()
    
    local wifi_text   = StatusUtils.getWifiStatusText()
    local memory_text = StatusUtils.getMemoryStatusText() or ""
    
    local batt_props  = self.props.battery_widget or {}
    local batt_format = batt_props.format or "both"
    local batt_text   = StatusUtils.getBatteryText(batt_format)

    if self.time_widget.text   ~= time_text   then self.time_widget:setText(time_text)     end
    if self.date_widget.text   ~= date_text   then self.date_widget:setText(date_text)     end
    if self.status_widget.text ~= status_text then self.status_widget:setText(status_text) end
    
    if self.wifi_widget.text    ~= wifi_text   then self.wifi_widget:setText(wifi_text)    end
    if self.memory_widget.text  ~= memory_text then self.memory_widget:setText(memory_text) end
    if self.battery_widget.text ~= batt_text   then self.battery_widget:setText(batt_text)  end
end


-- function DisplayWidget:paintTo(bb, x, y)
--     local sw = Screen:getWidth()
--     local sh = Screen:getHeight()
    
--     -- Are we supposed to be in a dark UI?
--     local is_dark = isDisplayInverted(self.props)
--     -- Is the hardware going to flip the screen at the very end?
--     local system_night = G_reader_settings:isTrue("night_mode")

--     -- 1. Start with a clean white background
--     bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)

--     -- 2. Separate PNG from text widgets
--     local png_item = nil
--     for _, item in ipairs(self.render_list) do
--         if item.is_png then png_item = item; break end
--     end

--     -- 3. Paint all text widgets first
--     for _, item in ipairs(self.render_list) do
--         if not item.is_png then
--             item.widget:paintTo(bb, x + item.px, y + item.py)
--         end
--     end

--     -- 4. Paint the PNG with proper night mode logic
--     if is_dark then
--         if system_night then
--             -- SCENARIO A: HARDWARE NIGHT MODE
--             -- The system will invert everything on the screen automatically.
--             if png_item then
--                 if not self.invert_png_overlay then
--                     -- User wants Original Image with Dark Transparent Background.
--                     -- TRICK: Invert the target area, paint image, then invert back.
--                     -- When the hardware does the final flip, the image returns to normal, and the transparent background goes dark.
--                     local pw, ph = png_item.widget:getSize().w, png_item.widget:getSize().h
--                     local px, py = x + png_item.px, y + png_item.py
                    
--                     bb:invertRect(px, py, pw, ph)
--                     png_item.widget:paintTo(bb, px, py)
--                     bb:invertRect(px, py, pw, ph)
--                 else
--                     -- User wants Inverted Image with Dark Background.
--                     -- Paint normally. The hardware will invert it for us.
--                     png_item.widget:paintTo(bb, x + png_item.px, y + png_item.py)
--                 end
--             end
--         else
--             -- SCENARIO B: SOFTWARE NIGHT MODE (Plugin only)
--             -- We must flip the colors manually.
--             if png_item then
--                 if not self.invert_png_overlay then
--                     -- User wants Original Image with Dark Transparent Background.
--                     -- Invert the screen to black FIRST, then paint the image on top.
--                     bb:invertRect(x, y, sw, sh)
--                     png_item.widget:paintTo(bb, x + png_item.px, y + png_item.py)
--                 else
--                     -- User wants Inverted Image with Dark Background.
--                     -- Paint the image first, THEN invert the entire screen.
--                     png_item.widget:paintTo(bb, x + png_item.px, y + png_item.py)
--                     bb:invertRect(x, y, sw, sh)
--                 end
--             else
--                 -- No image, just invert the text/background
--                 bb:invertRect(x, y, sw, sh)
--             end
--         end
--     else
--         -- SCENARIO C: LIGHT MODE
--         -- Everything is normal. Just paint the image.
--         if png_item then
--             png_item.widget:paintTo(bb, x + png_item.px, y + png_item.py)
--         end
--     end
-- end

function DisplayWidget:paintTo(bb, x, y)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    
    local is_dark = isDisplayInverted(self.props)
    local system_night = G_reader_settings:isTrue("night_mode")
    
    -- Are we manually forcing dark mode while the hardware is in light mode?
    local software_dark = (is_dark and not system_night)
    
    -- Do we need to "pre-invert" the PNG so the final flip restores its true colors?
    local needs_png_pre_inversion = (is_dark and not self.invert_png_overlay)

    -- 1. Start with a clean white background
    bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)

    -- 2. Paint ALL items in their correct Z-index order
    for _, item in ipairs(self.render_list) do
        if item.is_png then
            if needs_png_pre_inversion then
                -- TRICK: Invert the target area, paint image, then invert back.
                -- This guarantees transparent parts go dark while colors stay normal 
                -- after the final screen flip.
                local pw, ph = item.widget:getSize().w, item.widget:getSize().h
                local px, py = x + item.px, y + item.py
                
                bb:invertRect(px, py, pw, ph)
                item.widget:paintTo(bb, px, py)
                bb:invertRect(px, py, pw, ph)
            else
                -- Just paint it normally
                item.widget:paintTo(bb, x + item.px, y + item.py)
            end
        else
            -- Paint text widgets (Time, Date, Status) normally
            item.widget:paintTo(bb, x + item.px, y + item.py)
        end
    end

    -- 3. Final Software Inversion (Only if the plugin is doing the dark mode manually)
    -- If system_night is true, KOReader's hardware driver does this step automatically.
    if software_dark then
        bb:invertRect(x, y, sw, sh)
    end
end


-- function DisplayWidget:refresh()
--     -- Sync flags with current props/settings
--     local is_dark = isDisplayInverted(self.props)
--     local system_night = G_reader_settings:isTrue("night_mode")
--     self.apply_manual_inversion = (is_dark == true and system_night == false)
    
--     self.invert_png_overlay = true
--     if self.props.png_overlay and self.props.png_overlay.invert_with_night_mode == false then
--         self.invert_png_overlay = false
--     end

--     self.now = os.time()
--     self:update()

--     if type(self.cyclePngOverlay) == "function" then
--         self:cyclePngOverlay()
--     end

--     local frm = self.props.full_refresh_minutes
--     if frm and frm > 0 then
--         self.full_refresh_counter = self.full_refresh_counter + 1
--         if self.full_refresh_counter >= frm then
--             self.full_refresh_counter = 0
--             UIManager:setDirty("all", "full")
--             return
--         end
--     end

--     UIManager:setDirty("all", "ui")
-- end

function DisplayWidget:refresh()
    -- Ensure flags stay synced if user changes night mode via gestures
    self:syncStateFlags()

    self.now = os.time()
    self:update()

    if type(self.cyclePngOverlay) == "function" then
        self:cyclePngOverlay()
    end

    local frm = self.props.full_refresh_minutes
    if frm and frm > 0 then
        self.full_refresh_counter = self.full_refresh_counter + 1
        if self.full_refresh_counter >= frm then
            self.full_refresh_counter = 0
            UIManager:setDirty("all", "full")
            return
        end
    end

    UIManager:setDirty("all", "ui")
end

function DisplayWidget:cyclePngOverlay()
    local o = self.base_props and self.base_props.png_overlay
    if not o or not o.enabled or o.mode ~= "cycle" then return end
    
    local files = self:getPngFileList()
    if not files or #files == 0 then return end
    
    self.png_cycle_counter = self.png_cycle_counter + 1
    if self.png_cycle_counter >= self:getCycleMinutes() then
        self.png_cycle_counter = 0
        self.png_cycle_index   = self.png_cycle_index + 1
        if self.png_cycle_index > #files then self.png_cycle_index = 1 end
        
        -- The image changed. Store previous state, then check for new configs
        local had_custom = self._using_custom_config
        self._using_custom_config = self:applyImageProps()
        self:syncStateFlags()
        
        self:updatePngOverlayWidget()

        -- If we loaded a custom config, OR if we just dropped one (transitioning back to normal)
        -- We must force the UI to re-render the layout and font sizes dynamically.
        if self._using_custom_config or had_custom then
            self:render()
        end
        
        UIManager:setDirty("all", self:isFullRefreshOnCycle() and "full" or "ui")
    end
end

function DisplayWidget:onShow()        return self:autoRefresh() end

function DisplayWidget:onResume()
    self.now = os.time()
    self:update()
    UIManager:setDirty("all", "full")
    UIManager:unschedule(self.autoRefresh)
    self:autoRefresh()
end

function DisplayWidget:onSuspend()     UIManager:unschedule(self.autoRefresh) end

function DisplayWidget:onTapClose()
    if self.is_closing then return end
    self.is_closing = true
    UIManager:unschedule(self.autoRefresh)
    self:restoreRotation()
    if self.original_brightness          then SystemUtils.setBrightness(self.original_brightness) end
    if self.original_autosuspend_timeout then SystemUtils.setAutoSuspend(self.original_autosuspend_timeout) end
    UIManager:close(self)
end

DisplayWidget.onAnyKeyPressed = DisplayWidget.onTapClose

function DisplayWidget:onCloseWidget()
    self:restoreRotation()
    if self.original_autosuspend_timeout then SystemUtils.setAutoSuspend(self.original_autosuspend_timeout) end
    if self.original_brightness          then SystemUtils.setBrightness(self.original_brightness) end
end

function DisplayWidget:applyClockRotation()
    local r = self.props and self.props.rotation
    if r and not r.follow_koreader then
        Screen:setRotationMode(r.custom_rotation or 0)
    end
end

function DisplayWidget:restoreRotation()
    if self.original_rotation then
        Screen:setRotationMode(self.original_rotation)
        self.original_rotation = nil
    end
end

function DisplayWidget:getActiveFolderPath()
    local o = self.props and self.props.png_overlay
    if not o then return nil end
    if PngUtils.isPortraitOrientation() then
        if o.portrait_folder_path  and o.portrait_folder_path  ~= "" then return o.portrait_folder_path  end
        if o.folder_path           and o.folder_path           ~= "" then return o.folder_path           end
    else
        if o.landscape_folder_path and o.landscape_folder_path ~= "" then return o.landscape_folder_path end
        if o.folder_path           and o.folder_path           ~= "" then return o.folder_path           end
    end
end

function DisplayWidget:getActiveSingleFilePath()
    local o = self.props and self.props.png_overlay
    if not o then return nil end
    if PngUtils.isPortraitOrientation() then
        if o.single_file_path_portrait  and o.single_file_path_portrait  ~= "" then return o.single_file_path_portrait  end
        if o.single_file_path           and o.single_file_path           ~= "" then return o.single_file_path           end
    else
        if o.single_file_path_landscape and o.single_file_path_landscape ~= "" then return o.single_file_path_landscape end
        if o.single_file_path           and o.single_file_path           ~= "" then return o.single_file_path           end
    end
end

function DisplayWidget:getPngFileList()
    if self.png_file_list then return self.png_file_list end
    local o = self.props and self.props.png_overlay
    if not o or not o.enabled then return nil end
    local folder = self:getActiveFolderPath()
    if not folder then return nil end
    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then return nil end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." and entry:lower():match("%.png$") then
            table.insert(files, entry)
        end
    end
    table.sort(files)
    local valid = {}
    for _, fname in ipairs(files) do
        local res = PngUtils.checkPngResolution(folder .. "/" .. fname)
        if res then table.insert(valid, { filename = fname, resolution_type = res }) end
    end
    if #valid == 0 then return nil end
    self.png_file_list = valid
    return self.png_file_list
end

function DisplayWidget:getCurrentPngPathAndType()
    local o = self.props and self.props.png_overlay
    if not o or not o.enabled then return nil, nil end
    local mode = o.mode or "single"
    if mode == "single" then
        local p = self:getActiveSingleFilePath()
        if p then
            local res = PngUtils.checkPngResolution(p)
            if res then return p, res end
        end
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

function DisplayWidget:getCycleMinutes()
    local o = self.props and self.props.png_overlay
    return (o and o.cycle_minutes) or 1
end

function DisplayWidget:isFullRefreshOnCycle()
    local o = self.props and self.props.png_overlay
    return o and o.full_refresh_on_cycle == true
end

-- function DisplayWidget:cyclePngOverlay()
--     local o = self.props and self.props.png_overlay
--     if not o or not o.enabled or o.mode ~= "cycle" then return end
--     local files = self:getPngFileList()
--     if not files or #files == 0 then return end
--     self.png_cycle_counter = self.png_cycle_counter + 1
--     if self.png_cycle_counter >= self:getCycleMinutes() then
--         self.png_cycle_counter = 0
--         self.png_cycle_index   = self.png_cycle_index + 1
--         if self.png_cycle_index > #files then self.png_cycle_index = 1 end
--         self:updatePngOverlayWidget()
--         UIManager:setDirty("all", self:isFullRefreshOnCycle() and "full" or "ui")
--     end
-- end

function DisplayWidget:createPngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then return nil end
    local ss = Screen:getSize()
    return loadPngWidget(
        png_path, ss.w, ss.h,
        PngUtils.getImageRotationAngle(res_type)
    )
end

function DisplayWidget:updatePngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then return end
    local ss = Screen:getSize()

    -- FIX: Call free() on the internal buffer, not just the widget table
    if self.png_overlay_widget and self.png_overlay_widget._img_bb then
        self.png_overlay_widget._img_bb:free() 
    end

    local new_widget = loadPngWidget(
        png_path, ss.w, ss.h,
        PngUtils.getImageRotationAngle(res_type)
    )
    self.png_overlay_widget = new_widget
    for _, item in ipairs(self.render_list) do
        if item.is_png then item.widget = new_widget; break end
    end
end

return DisplayWidget
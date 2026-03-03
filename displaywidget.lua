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




local DEFAULT_ELEMENTS = {
    png    = { x = 0, y =   0, unit = "px", z = 1, visible = true },
    date   = { x = 0, y = -20, unit = "%",  z = 2, visible = true },
    time   = { x = 0, y =   0, unit = "px", z = 2, visible = true },
    status = { x = 0, y =  20, unit = "%",  z = 2, visible = true },
}


local DisplayWidget = InputContainer:extend {
    props      = {},
    plugin_dir = "",
}

local function getEffectiveNightMode(props)
    local setting        = props and props.night_mode or "follow"
    local koreader_night = G_reader_settings:isTrue("night_mode")
    local desired_night
    if     setting == "night"  then desired_night = true
    elseif setting == "normal" then desired_night = false
    else                            desired_night = koreader_night
    end
    return desired_night ~= koreader_night
end


function DisplayWidget:init()
    self.now              = os.time()
    self.is_closing       = false
    self.render_list      = {}
    self.time_widget      = nil
    self.date_widget      = nil
    self.status_widget    = nil
    self.png_overlay_widget = nil

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

    self.apply_night_inversion = getEffectiveNightMode(self.props)
    self.invert_png_overlay = true
    if self.props.png_overlay and self.props.png_overlay.invert_with_night_mode == false then
        self.invert_png_overlay = false
    end

    local elements_path = self.plugin_dir .. "elements.lua"
    local ok, file_elements = pcall(dofile, elements_path)
    if not ok or type(file_elements) ~= "table" then
        require("logger").warn("DtDisplay: could not load elements.lua:", file_elements)
        file_elements = {}
    end

    self.elements = {}
    for name, defaults in pairs(DEFAULT_ELEMENTS) do
        local user = file_elements[name] or {}
        self.elements[name] = {
            x       = user.x ~= nil and user.x or defaults.x,
            y       = user.y ~= nil and user.y or defaults.y,
            unit    = user.unit or defaults.unit,
            z       = user.z   ~= nil and user.z or defaults.z,
            visible = user.visible ~= false,
        }
    end

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

    addWidget("time",   self.time_widget)
    addWidget("date",   self.date_widget)
    addWidget("status", self.status_widget)

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


function DisplayWidget:paintTo(bb, x, y)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    -- 1. Start with a clean slate
    bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)

    -- Identify the PNG item if it exists
    local png_item = nil
    for _, item in ipairs(self.render_list) do
        if item.is_png then png_item = item; break end
    end

    -- 2. CASE: Night mode is ON, but we must NOT invert the PNG
    if self.apply_night_inversion and png_item and not self.invert_png_overlay then
        -- Paint only text/UI elements first
        for _, item in ipairs(self.render_list) do
            if not item.is_png then
                item.widget:paintTo(bb, x + item.px, y + item.py)
            end
        end
        -- Invert the background and text ONLY (PNG is not there yet)
        bb:invertRect(x, y, sw, sh)
        -- Now paint the PNG on top of the inverted background (it stays original)
        png_item.widget:paintTo(bb, x + png_item.px, y + png_item.py)

    -- 3. CASE: Night mode is ON and we SHOULD invert the PNG (or no PNG exists)
    elseif self.apply_night_inversion then
        for _, item in ipairs(self.render_list) do
            item.widget:paintTo(bb, x + item.px, y + item.py)
        end
        -- Invert EVERYTHING including the PNG
        bb:invertRect(x, y, sw, sh)

    -- 4. CASE: Normal mode (Night mode OFF)
    else
        for _, item in ipairs(self.render_list) do
            item.widget:paintTo(bb, x + item.px, y + item.py)
        end
    end
end

function DisplayWidget:update()
    local time_text   = TimeUtils.getTimeText(self.now, self.props.clock_format)
    local date_text   = TimeUtils.getDateText(self.now, true)
    local status_text = StatusUtils.getStatusText()

    if self.time_widget.text   ~= time_text   then self.time_widget:setText(time_text)     end
    if self.date_widget.text   ~= date_text   then self.date_widget:setText(date_text)     end
    if self.status_widget.text ~= status_text then self.status_widget:setText(status_text) end
end


function DisplayWidget:refresh()
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

function DisplayWidget:cyclePngOverlay()
    local o = self.props and self.props.png_overlay
    if not o or not o.enabled or o.mode ~= "cycle" then return end
    local files = self:getPngFileList()
    if not files or #files == 0 then return end
    self.png_cycle_counter = self.png_cycle_counter + 1
    if self.png_cycle_counter >= self:getCycleMinutes() then
        self.png_cycle_counter = 0
        self.png_cycle_index   = self.png_cycle_index + 1
        if self.png_cycle_index > #files then self.png_cycle_index = 1 end
        self:updatePngOverlayWidget()
        UIManager:setDirty("all", self:isFullRefreshOnCycle() and "full" or "ui")
    end
end

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
local Element = require('elements/Element')

-- DinaPlayer: resting width of the volume slider as a fraction of its full width,
-- when the volume element isn't hovered. Shared by the slider (bar geometry) and
-- the mute icon (which slides to track the bar's centre as it collapses).
local COLLAPSED_WIDTH = 0.25

-- DinaPlayer: the slider's dark (unfilled) backing — the same grey as the
-- timeline's watched trail (Timeline.lua WATCHED_BG), so the two read as one
-- family. The over-dark number is drawn in this same colour so it blends in.
local SLIDER_BG = '3a3a3a'

--[[ VolumeSlider ]]

---@class VolumeSlider : Element
local VolumeSlider = class(Element)
---@param props? ElementProps
function VolumeSlider:new(props) return Class.new(self, props) --[[@as VolumeSlider]] end
function VolumeSlider:init(props)
	Element.init(self, 'volume_slider', props)
	self.pressed = false
	self.nudge_y = 0 -- vertical position where volume overflows 100
	self.nudge_size = 0
	self.draw_nudge = false
	self.spacing = 0
	self.border_size = 0
	self:update_dimensions()
end

function VolumeSlider:update_dimensions()
	self.border_size = math.max(0, round(options.volume_border * state.scale))
end

function VolumeSlider:get_visibility() return Elements.volume:get_visibility(self) end

function VolumeSlider:set_volume(volume)
	volume = round(volume / options.volume_step) * options.volume_step
	if state.volume == volume then return end
	mp.commandv('set', 'volume', clamp(0, volume, state.volume_max))
end

function VolumeSlider:set_from_cursor()
	local volume_fraction = (self.by - cursor.y - self.border_size) / (self.by - self.ay - self.border_size)
	self:set_volume(volume_fraction * state.volume_max)
end

function VolumeSlider:on_display() self:update_dimensions() end
function VolumeSlider:on_options() self:update_dimensions() end
function VolumeSlider:on_coordinates()
	if type(state.volume_max) ~= 'number' or state.volume_max <= 0 then return end
	local width = self.bx - self.ax
	self.nudge_y = self.by - round((self.by - self.ay) * (100 / state.volume_max))
	self.nudge_size = round(width * 0.18)
	self.draw_nudge = self.ay < self.nudge_y
	self.spacing = round(width * 0.2)
end
function VolumeSlider:on_global_mouse_move()
	if self.pressed then self:set_from_cursor() end
end
function VolumeSlider:handle_wheel_up() self:set_volume(state.volume + options.volume_step) end
function VolumeSlider:handle_wheel_down() self:set_volume(state.volume - options.volume_step) end

function VolumeSlider:render()
	local visibility = self:get_visibility()
	local ax, ay, bx, by = self.ax, self.ay, self.bx, self.by

	-- DinaPlayer: collapse the bar toward its docked edge when the volume element
	-- isn't hovered (see Volume.expand). Interaction is unaffected — this is a
	-- vertical slider, volume tracks cursor.y only, so narrowing the width is purely
	-- visual. Done before create_nudged_path is defined so the path picks it up.
	local expand = Elements.volume and Elements.volume.expand or 1
	local factor = COLLAPSED_WIDTH + (1 - COLLAPSED_WIDTH) * expand
	local full_width = bx - ax
	if options.volume == 'left' then bx = ax + full_width * factor else ax = bx - full_width * factor end

	local width, height = bx - ax, by - ay

	if width <= 0 or height <= 0 or visibility <= 0 then return end

	cursor:zone('primary_down', self, function()
		self.pressed = true
		self:set_from_cursor()
		cursor:once('primary_up', function() self.pressed = false end)
	end)
	cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
	cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)

	local ass = assdraw.ass_new()
	local nudge_y, nudge_size = self.draw_nudge and self.nudge_y or -math.huge, self.nudge_size
	local volume_y = self.ay + self.border_size +
		((height - (self.border_size * 2)) * (1 - math.min(state.volume / state.volume_max, 1)))

	-- Draws a rectangle with nudge at requested position
	---@param p number Padding from slider edges.
	---@param r number Border radius.
	---@param cy? number A y coordinate where to clip the path from the bottom.
	function create_nudged_path(p, r, cy)
		cy = cy or ay + p
		local ax, bx, by = ax + p, bx - p, by - p
		local d, rh = r * 2, r / 2
		local nudge_size = ((QUARTER_PI_SIN * (nudge_size - p)) + p) / QUARTER_PI_SIN
		local path = assdraw.ass_new()
		path:move_to(bx - r, by)
		path:line_to(ax + r, by)
		if cy > by - d then
			local subtracted_radius = (d - (cy - (by - d))) / 2
			local xbd = (r - subtracted_radius * 1.35) -- x bezier delta
			path:bezier_curve(ax + xbd, by, ax + xbd, cy, ax + r, cy)
			path:line_to(bx - r, cy)
			path:bezier_curve(bx - xbd, cy, bx - xbd, by, bx - r, by)
		else
			path:bezier_curve(ax + rh, by, ax, by - rh, ax, by - r)
			local nudge_bottom_y = nudge_y + nudge_size

			if cy + rh <= nudge_bottom_y then
				path:line_to(ax, nudge_bottom_y)
				if cy <= nudge_y then
					path:line_to((ax + nudge_size), nudge_y)
					local nudge_top_y = nudge_y - nudge_size
					if cy <= nudge_top_y then
						local r, rh = r, rh
						if cy > nudge_top_y - r then
							r = nudge_top_y - cy
							rh = r / 2
						end
						path:line_to(ax, nudge_top_y)
						path:line_to(ax, cy + r)
						path:bezier_curve(ax, cy + rh, ax + rh, cy, ax + r, cy)
						path:line_to(bx - r, cy)
						path:bezier_curve(bx - rh, cy, bx, cy + rh, bx, cy + r)
						path:line_to(bx, nudge_top_y)
					else
						local triangle_side = cy - nudge_top_y
						path:line_to((ax + triangle_side), cy)
						path:line_to((bx - triangle_side), cy)
					end
					path:line_to((bx - nudge_size), nudge_y)
				else
					local triangle_side = nudge_bottom_y - cy
					path:line_to((ax + triangle_side), cy)
					path:line_to((bx - triangle_side), cy)
				end
				path:line_to(bx, nudge_bottom_y)
			else
				path:line_to(ax, cy + r)
				path:bezier_curve(ax, cy + rh, ax + rh, cy, ax + r, cy)
				path:line_to(bx - r, cy)
				path:bezier_curve(bx - rh, cy, bx, cy + rh, bx, cy + r)
			end
			path:line_to(bx, by - r)
			path:bezier_curve(bx, by - rh, bx - rh, by, bx - r, by)
		end
		return path
	end

	-- BG & FG paths
	-- DinaPlayer: clamp the corner radius so it never exceeds half the (possibly
	-- collapsed) width, which would distort the rounded path on the narrow bar.
	local radius = math.max(0, math.min(state.radius, math.floor(width / 2) - self.border_size))
	local bg_path = create_nudged_path(0, radius + self.border_size)
	local fg_path = create_nudged_path(self.border_size, radius, volume_y)

	-- Background
	-- DinaPlayer: dark backing coloured like the timeline's watched trail
	-- (SLIDER_BG), at menu opacity — gated by the slider's own visibility so it
	-- still hides with the UI.
	ass:new_event()
	ass:append('{\\rDefault\\an7\\blur0\\bord0\\1c&H' .. SLIDER_BG ..
		'\\iclip(' .. fg_path.scale .. ', ' .. fg_path.text .. ')}')
	ass:opacity(config.opacity.menu, visibility)
	ass:pos(0, 0)
	ass:draw_start()
	ass:append(bg_path.text)
	ass:draw_stop()

	-- Foreground
	ass:new_event()
	ass:append('{\\rDefault\\an7\\blur0\\bord0\\1c&H' .. fg .. '}')
	ass:opacity(config.opacity.slider_gauge, visibility)
	ass:pos(0, 0)
	ass:draw_start()
	ass:append(fg_path.text)
	ass:draw_stop()

	-- Current volume value. DinaPlayer: hidden at rest, fades in with the
	-- hover-expand, and centred on the (animating) drawn bar.
	if expand > 0.02 then
		local volume_string = tostring(round(state.volume * 10) / 10)
		local font_size = round(((width * 0.6) - (#volume_string * (width / 20))) * options.font_scale * 1.2) -- DinaPlayer: slightly larger
		local text_opacity = visibility * expand
		if volume_y < self.by - self.spacing then
			ass:txt(ax + (width / 2), self.by - self.spacing, 2, volume_string, {
				size = font_size,
				color = fgt,
				opacity = text_opacity,
				clip = '\\clip(' .. fg_path.scale .. ', ' .. fg_path.text .. ')',
			})
		end
		if volume_y > self.by - self.spacing - font_size then
			ass:txt(ax + (width / 2), self.by - self.spacing, 2, volume_string, {
				size = font_size,
				-- DinaPlayer: over the dark (unfilled) backing the number is drawn in
				-- the backing colour (SLIDER_BG) so it blends in — the digits only
				-- read over the filled part of the gauge.
				color = SLIDER_BG,
				opacity = text_opacity,
				clip = '\\iclip(' .. fg_path.scale .. ', ' .. fg_path.text .. ')',
			})
		end
	end

	-- Disabled stripes for no audio
	if not state.has_audio then
		local fg_100_path = create_nudged_path(self.border_size, state.radius)
		local texture_opts = {
			size = 200,
			color = 'ffffff',
			opacity = visibility * 0.1,
			anchor_x = ax,
			clip = '\\clip(' .. fg_100_path.scale .. ',' .. fg_100_path.text .. ')',
		}
		ass:texture(ax, ay, bx, by, 'a', texture_opts)
		texture_opts.color = '000000'
		texture_opts.anchor_x = ax + texture_opts.size / 28
		ass:texture(ax, ay, bx, by, 'a', texture_opts)
	end

	return ass
end

--[[ Volume ]]

---@class Volume : Element
local Volume = class(Element)

function Volume:new() return Class.new(self) --[[@as Volume]] end
function Volume:init()
	Element.init(self, 'volume', {render_order = 7})
	self.size = 0
	self.mute_ay = 0
	-- DinaPlayer: hover-expand. At rest the bar is a quarter of its full width with
	-- no mute icon and no number; hovering expands it to full width and fades the
	-- icon and number in. Leaving collapses it again immediately.
	self.expand = 0 -- 0 = collapsed (narrow), 1 = expanded (full)
	self.hovered = false
	self.slider = VolumeSlider:new({anchor_id = 'volume', render_order = self.render_order})
	self:update_dimensions()
end

function Volume:destroy()
	self.slider:destroy()
	Element.destroy(self)
end

-- DinaPlayer: animate the hover-expand factor. Snappy to open, smoother to close.
function Volume:animate_expand(to)
	self:tween_property('expand', self.expand, to, to > 0 and 150 or 250)
end

-- DinaPlayer: react to the cursor entering/leaving the volume column. Entering
-- expands, leaving collapses — both immediately.
function Volume:set_hovered(hovered)
	if hovered == self.hovered then return end
	self.hovered = hovered
	self:animate_expand(hovered and 1 or 0)
end

-- DinaPlayer: base show/hide value — visible together with the controls bar.
function Volume:get_base_visibility()
	if not state.is_idle and not state.has_audio then return 0 end
	if Elements:maybe('timeline', 'get_is_hovered') then return -1 end
	return math.max(Elements:maybe('controls', 'get_visibility') or 0, Element.get_visibility(self))
end

-- DinaPlayer: the slider shows at full opacity together with the controls bar —
-- no hover-based fade. (It used to sit faint at rest and brighten on hover.)
function Volume:get_visibility()
	return self:get_base_visibility()
end

-- DinaPlayer: extend the proximity hit rect all the way to the screen edge on the
-- docked side, so moving the cursor past the bar into the margin keeps it hovered
-- (expanded and visible) instead of collapsing it. Drives both visibility and the
-- hover-expand, which both key off proximity.
function Volume:update_proximity()
	if cursor.hidden then
		self:reset_proximity()
	else
		local rect = {
			ax = options.volume == 'left' and 0 or self.ax,
			ay = self.ay,
			bx = options.volume == 'left' and self.bx or display.width,
			by = self.by,
		}
		local range = options.proximity_out - options.proximity_in
		self.proximity_raw = get_point_to_rectangle_proximity(cursor, rect)
		self.proximity = 1 - (clamp(0, self.proximity_raw - options.proximity_in, range) / range)
	end
end

function Volume:update_dimensions()
	self.size = round(options.volume_size * state.scale)
	local min_y = Elements:v('top_bar', 'by') or Elements:v('window_border', 'size', 0)
	local max_y = Elements:v('controls', 'ay') or Elements:v('timeline', 'ay')
		or display.height - Elements:v('window_border', 'size', 0)
	local available_height = max_y - min_y
	local max_height = available_height * 0.8
	local height = round(math.min(self.size * 8, max_height) * 0.75) -- DinaPlayer: 75% height
	self.enabled = height > self.size * 2 -- don't render if too small
	local margin = (self.size / 2) + Elements:v('window_border', 'size', 0)
	self.ax = round(options.volume == 'left' and margin or display.width - margin - self.size)
	self.ay = min_y + round((available_height - height) / 2)
	self.bx = round(self.ax + self.size)
	self.by = round(self.ay + height)
	self.mute_ay = self.by - self.size
	self.slider.enabled = self.enabled
	self.slider:set_coordinates(self.ax, self.ay, self.bx, self.mute_ay)
end

function Volume:on_display() self:update_dimensions() end
function Volume:on_prop_border() self:update_dimensions() end
function Volume:on_prop_title_bar() self:update_dimensions() end
function Volume:on_prop_volume_max() self:update_dimensions() end
function Volume:on_controls_reflow() self:update_dimensions() end
function Volume:on_options() self:update_dimensions() end

function Volume:render()
	local visibility = self:get_visibility()
	if visibility <= 0 then return end

	-- DinaPlayer: drive the hover-expand. The cursor being anywhere in the volume
	-- column (or a drag in progress) counts as hovered — a generous target, since
	-- the resting bar is narrow.
	self:set_hovered(self.slider.pressed or (not cursor.hidden and self.proximity_raw <= 0))

	-- Reset volume on secondary click
	cursor:zone('secondary_click', self, function()
		mp.set_property_native('mute', false)
		mp.set_property_native('volume', 100)
	end)

	-- Mute button. DinaPlayer: only clickable once expanded, so the invisible
	-- resting bar doesn't toggle mute from clicks in the empty column.
	local mute_rect = {ax = self.ax, ay = self.mute_ay, bx = self.bx, by = self.by}
	if self.expand > 0.5 then
		cursor:zone('primary_down', mute_rect, function() mp.commandv('cycle', 'mute') end)
	end
	local ass = assdraw.ass_new()
	local width_half = (mute_rect.bx - mute_rect.ax) / 2
	local height_half = (mute_rect.by - mute_rect.ay) / 2
	local icon_size = math.min(width_half, height_half) * 1.5
	local icon_name, horizontal_shift = 'volume_up', 0
	if state.mute then
		icon_name = 'volume_off'
	elseif state.volume <= 0 then
		icon_name, horizontal_shift = 'volume_mute', height_half * 0.25
	elseif state.volume <= 60 then
		icon_name, horizontal_shift = 'volume_down', height_half * 0.125
	end
	-- DinaPlayer: the mute icon fades in with the hover-expand (hidden at rest), and
	-- slides to track the bar's centre — toward the docked edge as it collapses, back
	-- to the full-width centre as it expands.
	local icon_visibility = math.max(0, self:get_base_visibility()) * self.expand
	local underlay_opacity = {main = icon_visibility * 0.3, border = icon_visibility}
	local bar_w = (self.bx - self.ax) * (COLLAPSED_WIDTH + (1 - COLLAPSED_WIDTH) * self.expand)
	local icon_cx = options.volume == 'left' and (self.ax + bar_w / 2) or (self.bx - bar_w / 2)
	ass:icon(icon_cx, mute_rect.ay + height_half, icon_size, 'volume_up',
		{border = options.text_border * state.scale, opacity = underlay_opacity, align = 5}
	)
	ass:icon(icon_cx - horizontal_shift, mute_rect.ay + height_half, icon_size, icon_name,
		{opacity = icon_visibility, align = 5}
	)
	return ass
end

return Volume

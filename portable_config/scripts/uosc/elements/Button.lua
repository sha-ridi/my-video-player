local Element = require('elements/Element')

---@alias ButtonProps {icon: string; on_click?: function; is_clickable?: boolean; anchor_id?: string; active?: boolean; badge?: string|number; foreground?: string; background?: string; tooltip?: string}

---@class Button : Element
local Button = class(Element)

---@param id string
---@param props ButtonProps
function Button:new(id, props) return Class.new(self, id, props) --[[@as Button]] end
---@param id string
---@param props ButtonProps
function Button:init(id, props)
	self.icon = props.icon
	-- DinaPlayer: per-button glyph scale. The button (hit area + chip) keeps its
	-- size; only the icon inside is multiplied by this. Defaults to 1.
	self.icon_scale = props.icon_scale or 1
	self.active = props.active
	self.tooltip = props.tooltip
	-- DinaPlayer: which control-bar cluster this button belongs to ('right' or
	-- 'left'), used to hide its hover tooltip while a popup sits above it.
	self.tooltip_group = props.tooltip_group
	self.badge = props.badge
	self.menu_type = props.menu_type
	self.foreground = props.foreground or fg
	self.background = props.background or bg
	self.is_clickable = true
	---@type fun()|nil
	self.on_click = props.on_click
	Element.init(self, id, props)
end

function Button:on_coordinates() self.font_size = round((self.by - self.ay) * 0.7) end
function Button:handle_cursor_click()
	if not self.on_click or not self.is_clickable then return end
	-- We delay the callback to next tick, otherwise we are risking race
	-- conditions as we are in the middle of event dispatching.
	-- For example, handler might add a menu to the end of the element stack, and that
	-- than picks up this click event we are in right now, and instantly closes itself.
	mp.add_timeout(0.01, self.on_click)
end

function Button:render()
	local visibility = self:get_visibility()
	if visibility <= 0 then return end
	cursor:zone('primary_down', self, function() self:handle_cursor_click() end)

	local ass = assdraw.ass_new()
	local is_clickable = self.is_clickable and self.on_click ~= nil
	local is_hover = self.proximity_raw <= 0
	-- DinaPlayer: YouTube-like chip container. The icon color never inverts; the
	-- container is an icon-colored rounded rect: subtle on hover, stronger when
	-- active (this button's popup is open, or its feature is enabled).
	local is_active = self.active
		or (self.menu_type ~= nil and Elements.menu ~= nil and Elements.menu.type == self.menu_type)
		or self.observed_active
	local foreground = self.foreground
	local background = self.background
	local background_opacity = 0
	if is_active then
		background_opacity = 0.25
	elseif is_hover and is_clickable then
		background_opacity = 0.12
	end

	-- Background (chip container)
	if background_opacity > 0 then
		ass:rect(self.ax, self.ay, self.bx, self.by, {
			color = foreground,
			radius = state.radius,
			opacity = visibility * background_opacity,
		})
	end

	-- Tooltip on hover. DinaPlayer: suppress it while a popup is open above this
	-- button's cluster — the right cluster (subtitles/audio/settings/fullscreen)
	-- when the sub/audio/settings popup is open, the left cluster (prev/playlist/
	-- next) when the playlist popup is open — so the label doesn't clutter the popup.
	local tooltip_hidden = false
	if self.tooltip_group and Elements.menu and Elements.menu.type then
		local t = Elements.menu.type
		if self.tooltip_group == 'right' then
			tooltip_hidden = t == 'sub' or t == 'audio' or t == 'settings'
		elseif self.tooltip_group == 'left' then
			tooltip_hidden = t == 'playlist'
		end
	end
	-- DinaPlayer: lift the tooltip off the button by half the gap a bottom-anchored
	-- popup leaves above the controls (that gap = menu anchor margin − menu padding,
	-- where the margin is half a menu item's height). Stock was a flat 2px.
	if is_hover and self.tooltip and not tooltip_hidden then
		local menu_margin = round(round(fullscreen_size('menu_item_height') * state.scale) / 2)
		local menu_pad = round(fullscreen_size('menu_padding') * state.scale)
		ass:tooltip(self, self.tooltip, {offset = round((menu_margin - menu_pad) / 2)})
	end

	-- Badge
	local icon_clip
	if self.badge then
		local badge_font_size = self.font_size * 0.6
		local badge_opts = {size = badge_font_size, color = background, opacity = visibility}
		local badge_width = text_width(self.badge, badge_opts)
		local width, height = math.ceil(badge_width + (badge_font_size / 7) * 2), math.ceil(badge_font_size * 0.93)
		local bx, by = self.bx - 1, self.by - 1
		ass:rect(bx - width, by - height, bx, by, {
			color = foreground,
			radius = state.radius,
			opacity = visibility,
			border = self.active and 0 or 1,
			border_color = background,
		})
		ass:txt(bx - width / 2, by - height / 2, 5, self.badge, badge_opts)

		local clip_border = math.max(self.font_size / 20, 1)
		local clip_path = assdraw.ass_new()
		clip_path:round_rect_cw(
			math.floor((bx - width) - clip_border), math.floor((by - height) - clip_border), bx, by, 3
		)
		icon_clip = '\\iclip(' .. clip_path.scale .. ', ' .. clip_path.text .. ')'
	end

	-- Icon
	local x, y = round(self.ax + (self.bx - self.ax) / 2), round(self.ay + (self.by - self.ay) / 2)
	ass:icon(x, y, self.font_size * self.icon_scale, self.icon, {
		color = foreground,
		border = options.text_border * state.scale,
		border_color = background,
		opacity = visibility,
		clip = icon_clip,
	})

	return ass
end

return Button

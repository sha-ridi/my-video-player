local Element = require('elements/Element')

-- DinaPlayer: the "next episode in N…" plate that appears over the closing
-- credits, bottom right. scripts/skip-ending.lua owns the logic and publishes
-- the remaining seconds; this only draws it and reports the click.
--
-- It lives inside uosc so the click goes through uosc's cursor zones — that way
-- pressing it doesn't also pause the video the way a raw MBTN_LEFT would.

---@class SkipEnding : Element
local SkipEnding = class(Element)

-- Netflix-style hand-off: two buttons side by side, bottom right. A white
-- "Watch credits" (stay on this episode) on the left, and a grey
-- "Next episode in {n}" (jump now) on the right. Doing nothing still lets the
-- countdown auto-advance (scripts/skip-ending.lua owns that).
local NEXT_PREFIX = 'Next episode in'
local CREDITS_LABEL = 'Watch credits'
-- Last episode of a series: a static white badge, no countdown, does nothing.
local LAST_LABEL = 'Last episode'

function SkipEnding:new() return Class.new(self) --[[@as SkipEnding]] end
function SkipEnding:init()
	Element.init(self, 'skip_ending', {render_order = 6})
	self.enabled = false
	self.seconds = nil
	self.progress = 0 -- 0..1 fill of the "Next episode" button (0 start -> 1 hand-off)
	self.ignores_curtain = true
	-- Highest value seen in the current countdown. The plate is right-anchored, so
	-- sizing it to the live number would make it jump left when 10 becomes 9 — it
	-- is measured against the widest number this countdown will show instead.
	self.max_seconds = nil
	-- Last episode of a series: show only the "Watch credits" button, no countdown.
	self.credits_only = false
	self:observe_mp_property('user-data/dinaplayer/ending-countdown', 'native', function(_, value)
		local seconds = tonumber(value)
		self.seconds = (seconds and seconds > 0) and seconds or nil
		self.max_seconds = self.seconds and math.max(self.max_seconds or 0, self.seconds) or nil
		self.enabled = self.seconds ~= nil or self.credits_only
		self:update_dimensions()
		request_render()
	end)
	-- Smooth 0..1 fill fraction, published ~20x/s by scripts/skip-ending.lua.
	self:observe_mp_property('user-data/dinaplayer/ending-progress', 'native', function(_, value)
		self.progress = tonumber(value) or 0
		request_render()
	end)
	self:observe_mp_property('user-data/dinaplayer/ending-credits-only', 'native', function(_, value)
		self.credits_only = value == true
		self.enabled = self.seconds ~= nil or self.credits_only
		self:update_dimensions()
		request_render()
	end)
	self:update_dimensions()
end

function SkipEnding:update_dimensions()
	local scale = state.scale
	-- Everything is a ratio of the title size, so one option resizes the whole
	-- plate (and `skip_ending_size_fullscreen` can enlarge it in fullscreen only).
	local base = fullscreen_size('skip_ending_size')
	self.font_size = round(base * scale * options.font_scale)
	self.padding = round(base * (13 / 15) * scale)
	self.gap = round(base * (4 / 15) * scale)
	local vpad = round(self.font_size * 0.5)
	local opts = {size = self.font_size, bold = true}

	-- Two single-line buttons. The "Next episode in N" label keeps the countdown
	-- number in a fixed-width slot (sized to the widest number this countdown will
	-- show), so the text doesn't jiggle when e.g. 10 becomes 9.
	self.button_h = self.font_size + vpad * 2
	self.next_prefix_w = round(text_width(NEXT_PREFIX, opts))
	self.next_num_gap = round(self.font_size * 0.28)
	self.next_num_w = round(text_width(tostring(self.max_seconds or self.seconds or 0), opts))
	self.next_content_w = self.next_prefix_w + self.next_num_gap + self.next_num_w
	-- Smaller padding on the right of the number than on the left, so the button
	-- doesn't look empty after a 1-digit countdown.
	self.next_right_pad = round(self.padding * 0.5)
	self.next_w = self.padding + self.next_content_w + self.next_right_pad
	self.credits_w = round(text_width(CREDITS_LABEL, opts) + self.padding * 2)
	self.last_w = round(text_width(LAST_LABEL, opts) + self.padding * 2)
	-- Last episode: "Watch credits" + a static "Last episode" badge (instead of the
	-- counting-down "Next episode" button).
	local total_w = (self.credits_only and not self.seconds) and (self.credits_w + self.gap + self.last_w)
		or (self.credits_w + self.gap + self.next_w)

	-- Sit above the control bar, hugging the right edge like the controls do.
	local margin = round(options.controls_margin * scale)
	local bx = display.width - margin
	local by = (Elements:v('controls', 'ay') or (display.height - margin)) - margin
	self:set_coordinates(round(bx - total_w), round(by - self.button_h), round(bx), round(by))
end

function SkipEnding:on_display() self:update_dimensions() end
function SkipEnding:on_prop_border() self:update_dimensions() end
function SkipEnding:on_prop_fullormaxed() self:update_dimensions() end

-- Always fully visible while it's counting: it's a prompt, not part of the
-- controls that fade out with the cursor.
function SkipEnding:get_visibility() return self.enabled and 1 or 0 end

function SkipEnding:render()
	if not self.enabled then return end
	local ass = assdraw.ass_new()
	local cy = self.ay + self.button_h / 2

	-- Last episode of a series: "Watch credits" on the left (dismisses the plate) and
	-- a static white "Last episode" badge on the right instead of the counting-down
	-- "Next episode" button — nothing to hand off to, so no fill and no click on it.
	if self.credits_only and not self.seconds then
		local last_rect = {ax = self.bx - self.last_w, ay = self.ay, bx = self.bx, by = self.by}
		ass:rect(last_rect.ax, last_rect.ay, last_rect.bx, last_rect.by, {color = fg, opacity = 1, radius = state.radius})
		ass:txt((last_rect.ax + last_rect.bx) / 2, cy, 5, LAST_LABEL, {
			size = self.font_size, bold = true, color = fgt, opacity = 1, wrap = 2,
		})
		local cr_rect = {ax = last_rect.ax - self.gap - self.credits_w, ay = self.ay, bx = last_rect.ax - self.gap, by = self.by}
		local cr_hover = get_point_to_rectangle_proximity(cursor, cr_rect) <= 0
		cursor:zone('primary_down', cr_rect, function()
			mp.commandv('script-message', 'dina-ending-cancel')
		end)
		ass:rect(cr_rect.ax, cr_rect.ay, cr_rect.bx, cr_rect.by, {color = bg, opacity = 0.92, radius = state.radius})
		if cr_hover then
			ass:rect(cr_rect.ax, cr_rect.ay, cr_rect.bx, cr_rect.by, {color = fg, opacity = 0.18, radius = state.radius})
		end
		ass:txt(cr_rect.ax + self.credits_w / 2, cy, 5, CREDITS_LABEL, {
			size = self.font_size, bold = true, color = bgt, opacity = 1, wrap = 2,
		})
		return ass
	end

	if not self.seconds then return end

	-- Right button: "Next episode in N" — jump to the next episode now. White base
	-- with a Netflix-style dark fill that sweeps left->right as the countdown runs
	-- out; the fill reaching the far edge coincides with the hand-off.
	local next_rect = {ax = self.bx - self.next_w, ay = self.ay, bx = self.bx, by = self.by}
	local next_hover = get_point_to_rectangle_proximity(cursor, next_rect) <= 0
	cursor:zone('primary_down', next_rect, function()
		mp.commandv('script-message', 'dina-ending-next')
	end)
	ass:rect(next_rect.ax, next_rect.ay, next_rect.bx, next_rect.by, {
		color = fg, opacity = 1, radius = state.radius,
	})
	-- Progress fill: a dark bar growing from the left, clipped to the button's
	-- rounded shape so its left/top/bottom follow the corners while the right edge
	-- stays flush.
	local progress = clamp(0, self.progress or 0, 1)
	local fill_bx = round(next_rect.ax + (next_rect.bx - next_rect.ax) * progress)
	if fill_bx > next_rect.ax then
		local btn = assdraw.ass_new()
		btn:round_rect_cw(next_rect.ax, next_rect.ay, next_rect.bx, next_rect.by, state.radius)
		ass:rect(next_rect.ax, next_rect.ay, fill_bx, next_rect.by, {
			color = 'a3a3a3', opacity = 1, clip = '\\clip(' .. btn.scale .. ',' .. btn.text .. ')',
		})
	end
	-- Hover: darken the white button a touch so it reads as pressable.
	if next_hover then
		ass:rect(next_rect.ax, next_rect.ay, next_rect.bx, next_rect.by,
			{color = bg, opacity = 0.14, radius = state.radius})
	end
	-- Left-anchor the content (prefix + number in a fixed-width slot). The slot
	-- keeps a 2->1 digit change from shifting the text; the button's right padding
	-- is trimmed above so a 1-digit countdown doesn't leave a big empty gap.
	-- The label is always dark: it reads on both the white unfilled part and the
	-- light-grey fill. (Still drawn twice, once per clip region, for simplicity.)
	local content_ax = next_rect.ax + self.padding
	local num_ax = content_ax + self.next_prefix_w + self.next_num_gap
	local dark_clip = '\\clip(' .. fill_bx .. ',' .. next_rect.ay .. ',' .. next_rect.bx .. ',' .. next_rect.by .. ')'
	local light_clip = '\\clip(' .. next_rect.ax .. ',' .. next_rect.ay .. ',' .. fill_bx .. ',' .. next_rect.by .. ')'
	local function draw_label(x, s)
		ass:txt(x, cy, 4, s, {size = self.font_size, bold = true, color = fgt, opacity = 1, wrap = 2, clip = dark_clip})
		ass:txt(x, cy, 4, s, {size = self.font_size, bold = true, color = fgt, opacity = 1, wrap = 2, clip = light_clip})
	end
	draw_label(content_ax, NEXT_PREFIX)
	draw_label(num_ax, tostring(self.seconds))

	-- Left button: grey "Watch credits" — stay on this episode (as before).
	local cr_rect = {ax = next_rect.ax - self.gap - self.credits_w, ay = self.ay, bx = next_rect.ax - self.gap, by = self.by}
	local cr_hover = get_point_to_rectangle_proximity(cursor, cr_rect) <= 0
	cursor:zone('primary_down', cr_rect, function()
		mp.commandv('script-message', 'dina-ending-cancel')
	end)
	ass:rect(cr_rect.ax, cr_rect.ay, cr_rect.bx, cr_rect.by, {
		color = bg, opacity = 0.92, radius = state.radius,
	})
	-- Hover: lighten the grey button so it reads as pressable.
	if cr_hover then
		ass:rect(cr_rect.ax, cr_rect.ay, cr_rect.bx, cr_rect.by,
			{color = fg, opacity = 0.18, radius = state.radius})
	end
	ass:txt(cr_rect.ax + self.credits_w / 2, cy, 5, CREDITS_LABEL, {
		size = self.font_size, bold = true, color = bgt, opacity = 1, wrap = 2,
	})

	return ass
end

return SkipEnding

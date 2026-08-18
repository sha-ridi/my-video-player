local Element = require('elements/Element')

---@class Timeline : Element
local Timeline = class(Element)

function Timeline:new() return Class.new(self) --[[@as Timeline]] end
function Timeline:init()
	Element.init(self, 'timeline', {render_order = 5})
	---@type false|{pause: boolean, distance: number, last: {x: number, y: number}}
	self.pressed = false
	self.obstructed = false
	self.size = 0
	self.progress_size = 0
	self.min_progress_size = 0 -- used for `flash-progress`
	self.font_size = 0
	self.top_border = 0
	self.line_width = 0
	self.progress_line_width = 0
	self.is_hovered = false
	self.has_thumbnail = false
	self.heatmap = nil
	-- DinaPlayer (Netflix layout): the slider track is inset between the two corner
	-- timestamps. These hold the current inset so cursor→time mapping (get_time_at_x)
	-- stays in sync with what's drawn. Default to the full band until first render.
	self.track_ax = nil
	self.track_bx = nil
	self.track_cy = nil

	self:decide_progress_size()
	self:update_dimensions()

	-- Load Youtube heatmap data if available
	self:register_mp_event('file-loaded', function()
		self.heatmap = load_youtube_heatmap()
	end)
	-- Release any dragging and clear heatmap when file gets unloaded
	self:register_mp_event('end-file', function()
		self.pressed = false
		self.heatmap = nil
	end)
end

function Timeline:get_visibility()
	return math.max(Elements:maybe('controls', 'get_visibility') or 0, Element.get_visibility(self))
end

function Timeline:decide_enabled()
	local previous = self.enabled
	local renderable = not self.obstructed and state.duration ~= nil and state.duration > 0 and state.time ~= nil
	if renderable then
		-- Renderable again: cancel any pending disable and show.
		if self._disable_grace then self._disable_grace:kill(); self._disable_grace = nil end
		self.enabled = true
	elseif previous and not self.obstructed then
		-- DinaPlayer: on prev/next the next episode's `duration`/`time` blink to nil
		-- for a frame while it loads, which used to flash the timeline out and back
		-- in. Defer the disable briefly; if it's genuinely not renderable after the
		-- grace (real idle/end), disable for real then.
		if not self._disable_grace then
			self._disable_grace = mp.add_timeout(0.5, function()
				self._disable_grace = nil
				local ok = not self.obstructed and state.duration ~= nil and state.duration > 0 and state.time ~= nil
				if not ok and self.enabled then
					self.enabled = false
					Elements:trigger('timeline_enabled', false)
				end
			end)
		end
		-- keep self.enabled unchanged (still true) during the grace
	else
		self.enabled = false
	end
	if self.enabled ~= previous then Elements:trigger('timeline_enabled', self.enabled) end
end

function Timeline:get_effective_size()
	if Elements:v('speed', 'dragging') then return self.size end
	local progress_size = math.max(self.min_progress_size, self.progress_size)
	return progress_size + math.ceil((self.size - self.progress_size) * self:get_visibility())
end

function Timeline:get_is_hovered() return self.enabled and self.is_hovered end

function Timeline:update_dimensions()
	self.size = round(fullscreen_size('timeline_size') * state.scale)
	self.top_border = round(options.timeline_border * state.scale)
	self.line_width = round(options.timeline_line_width * state.scale)
	self.progress_line_width = round(options.progress_line_width * state.scale)
	self.font_size = math.floor(math.min((self.size + 60 * state.scale) * 0.2, self.size * 0.96) * options.font_scale)
	local window_border_size = Elements:v('window_border', 'size', 0)
	self.ax = window_border_size
	-- DinaPlayer: lift the whole timeline up by `controls_margin` so the gap below it
	-- (to the screen edge) matches the gap above it (up to the control-bar icons) —
	-- Controls places the icons exactly `controls_margin` above the timeline's top.
	local bottom_margin = round(options.controls_margin * state.scale)
	self.bx = display.width - window_border_size
	self.by = display.height - window_border_size - bottom_margin
	self.ay = self.by - self.size - self.top_border
	self.width = self.bx - self.ax
	self.chapter_size = math.max((self.by - self.ay) / 10, 3)
	self.chapter_size_hover = self.chapter_size * 2

	-- Disable if not enough space
	local available_space = display.height - window_border_size * 2 - Elements:v('top_bar', 'size', 0)
	self.obstructed = available_space < self.size + 10
	self:decide_enabled()
end

function Timeline:decide_progress_size()
	local show = options.progress == 'always'
		or (options.progress == 'fullscreen' and state.fullormaxed)
		or (options.progress == 'windowed' and not state.fullormaxed)
	self.progress_size = show and options.progress_size or 0
end

function Timeline:toggle_progress()
	local current = self.progress_size
	self:tween_property('progress_size', current, current > 0 and 0 or options.progress_size)
	request_render()
end

function Timeline:flash_progress()
	if self.enabled and options.flash_duration > 0 then
		if not self._flash_progress_timer then
			self._flash_progress_timer = mp.add_timeout(options.flash_duration / 1000, function()
				self:tween_property('min_progress_size', options.progress_size, 0)
			end)
			self._flash_progress_timer:kill()
		end

		self:tween_stop()
		self.min_progress_size = options.progress_size
		request_render()
		self._flash_progress_timer.timeout = options.flash_duration / 1000
		self._flash_progress_timer:kill()
		self._flash_progress_timer:resume()
	end
end

function Timeline:get_time_at_x(x)
	-- DinaPlayer (Netflix layout): the slider track is inset between the two corner
	-- timestamps, so map the cursor onto that track — clicking anywhere between the
	-- timecodes seeks proportionally. Falls back to the full band before first render.
	local ax = self.track_ax or self.ax
	local bx = self.track_bx or self.bx
	local progress = clamp(0, (x - ax) / math.max(1, bx - ax), 1)
	return state.duration * progress
end

---@param fast? boolean
function Timeline:set_from_cursor(fast)
	if state.time and state.duration then
		mp.commandv('seek', self:get_time_at_x(cursor.x), fast and 'absolute+keyframes' or 'absolute+exact')
	end
end

function Timeline:clear_thumbnail()
	if self.has_thumbnail then
		mp.commandv('script-message-to', 'thumbfast', 'clear')
		self.has_thumbnail = false
	end
end

function Timeline:handle_cursor_down()
	self.pressed = {pause = state.pause, distance = 0, last = {x = cursor.x, y = cursor.y}}
	mp.set_property_native('pause', true)
	self:set_from_cursor()
end
function Timeline:on_prop_duration() self:decide_enabled() end
function Timeline:on_prop_time() self:decide_enabled() end
function Timeline:on_prop_border() self:update_dimensions() end
function Timeline:on_prop_title_bar() self:update_dimensions() end
function Timeline:on_prop_fullormaxed()
	self:decide_progress_size()
	self:update_dimensions()
end
function Timeline:on_display() self:update_dimensions() end
function Timeline:on_options()
	self:decide_progress_size()
	self:update_dimensions()
end
function Timeline:handle_cursor_up()
	if self.pressed then
		mp.set_property_native('pause', self.pressed.pause)
		self.pressed = false
	end
end
function Timeline:on_global_mouse_leave()
	self.pressed = false
end

function Timeline:on_global_mouse_move()
	if self.pressed then
		self.pressed.distance = self.pressed.distance + get_point_to_point_proximity(self.pressed.last, cursor)
		self.pressed.last.x, self.pressed.last.y = cursor.x, cursor.y
		if state.is_video and math.abs(cursor:get_velocity().x) / self.width * state.duration > 30 then
			self:set_from_cursor(true)
		else
			self:set_from_cursor()
		end
	end
end

function Timeline:render()
	if self.size == 0 then
		self:clear_thumbnail()
		return
	end

	local size = self:get_effective_size()
	local visibility = self:get_visibility()
	self.is_hovered = false

	if size < 1 then
		self:clear_thumbnail()
		return
	end

	-- DinaPlayer: during a prev/next switch, state.time/duration blink to nil for a
	-- frame. decide_enabled keeps the timeline enabled through it (so it doesn't
	-- flash out), but the math below needs real values — so redraw the last good
	-- frame until they come back.
	if state.time == nil or state.duration == nil or state.duration <= 0 then
		return self._last_ass
	end

	if self.proximity_raw <= 0 then
		self.is_hovered = true
	end

	-- Seek on click/drag, step on wheel
	if visibility > 0 then
		cursor:zone('primary_down', self, function()
			self:handle_cursor_down()
			cursor:once('primary_up', function() self:handle_cursor_up() end)
		end)
		if config.timeline_step ~= 0 then
			cursor:zone('wheel_down', self, function()
				mp.commandv('seek', -config.timeline_step, config.timeline_step_flag)
			end)
			cursor:zone('wheel_up', self, function()
				mp.commandv('seek', config.timeline_step, config.timeline_step_flag)
			end)
		end
	end

	local ass = assdraw.ass_new()
	local progress = state.time / state.duration
	local progress_size = math.max(self.min_progress_size, self.progress_size)

	-- Band the timeline lives in (full width strip along the bottom)
	local bax, bay, bbx, bby = self.ax, self.by - size - self.top_border, self.bx, self.by
	local fay, fby = bay + self.top_border, bby
	local fcy = fay + (size / 2)

	-- Corner-timestamp opacity fades to 0 as the strip minimizes
	local hide_text_below = math.max(self.font_size * 0.8, progress_size * 2)
	local hide_text_ramp = hide_text_below / 2
	local text_opacity = clamp(0, size - hide_text_below, hide_text_ramp) / hide_text_ramp

	-- When the strip is too short for the full slider (it's retracting, or an always-on
	-- progress bar is configured), fall back to a slim ambient line. DinaPlayer runs
	-- progress=never, so `progress_size` is 0 and nothing is drawn here — this is what
	-- stops the thin minimized-timeline line from flashing as the timeline hides. The
	-- line is still drawn if an always-on progress bar or a flash is ever enabled.
	if text_opacity <= 0 then
		self.track_ax, self.track_bx, self.track_cy = bax, bbx, fcy
		self:clear_thumbnail()
		if progress_size > 0 then
			local ph = math.max(round(2 * state.scale), size)
			local top = bby - ph
			ass:rect(bax, top, bbx, bby, {color = 'ffffff', opacity = 0.25 * config.opacity.timeline})
			ass:rect(bax, top, bax + self.width * progress, bby, {color = 'ffffff', opacity = config.opacity.position})
		end
		self._last_ass = ass
		return ass
	end

	-- Corner timestamps sit OUTSIDE the slider, hugging the strip's left/right edges;
	-- the slider narrows to the space between them (Netflix layout). `reserve` is the
	-- wider of the two timecodes, applied to both sides so the track can't jitter as
	-- the digits change width.
	local time_size = round(self.font_size * options.timeline_timestamp_scale)
	local time_border = options.timeline_timestamp_border * state.scale
	local edge_inset = round(10 * state.scale)
	local edge_gap = round(12 * state.scale)
	local left_ts = state.time_human or format_time(state.time, state.duration)
	local right_ts = state.destination_time_human or format_time(state.time - state.duration, state.duration)
	local reserve = math.max(timestamp_width(left_ts, {size = time_size, border = time_border}),
		timestamp_width(right_ts, {size = time_size, border = time_border}))

	-- Slider track geometry: thin, vertically centered, rounded (pill) ends
	local track_ax = round(bax + edge_inset + reserve + edge_gap)
	local track_bx = round(bbx - edge_inset - reserve - edge_gap)
	if track_bx - track_ax < 40 then track_ax, track_bx = bax + edge_inset, bbx - edge_inset end -- tiny window safety
	local track_h = math.max(round(4 * state.scale), round(size * 0.16))
	local knob_r = math.max(track_h, round(7 * state.scale))
	local track_ay = round(fcy - track_h / 2)
	local track_by = track_ay + track_h
	local track_r = track_h / 2
	self.track_ax, self.track_bx, self.track_cy = track_ax, track_bx, fcy

	local function t2x(time)
		return track_ax + (track_bx - track_ax) * clamp(0, time / state.duration, 1)
	end
	local fill_bx = t2x(state.time)

	-- Hover state, resolved before the track is drawn so it can render the YouTube-
	-- style lighter "seek preview" segment (playhead → cursor).
	local is_dragging = Elements:v('speed', 'dragging')
	local hover_threshold = round(8 * state.scale)
	local hovered_chapter = nil

	-- Nearest chapter within reach is the hovered one (detected up front so snapping
	-- and is_hovered are known before anything is painted).
	if config.opacity.chapters > 0 and #state.chapters > 0 and self.proximity_raw <= 0 then
		local closest = math.huge
		for _, chapter in ipairs(state.chapters) do
			local dx = math.abs(cursor.x - t2x(chapter.time))
			if dx <= hover_threshold and dx < closest then
				hovered_chapter, closest = chapter, dx
				self.is_hovered = true
			end
		end
	end

	local hovering = (self.proximity_raw <= 0 or self.pressed or hovered_chapter) and not is_dragging
	local cursor_x = round(clamp(track_ax, hovered_chapter and t2x(hovered_chapter.time) or cursor.x, track_bx))

	-- DinaPlayer: chapters are drawn as GAPS cut out of the track (transparent slots,
	-- like YouTube's dividers) instead of dark marks. Build one \iclip that removes a
	-- thin vertical slot at each chapter; it's applied to every track layer below, so
	-- the video shows through there. Interaction (snap/hover/click) is unchanged.
	local mark_w = math.max(round(3 * state.scale), 3)
	local gap_w = round(mark_w * 1.8) -- chapter gaps are a bit wider than an A-B mark
	local gap_clip = nil
	if config.opacity.chapters > 0 and #state.chapters > 0 then
		local parts = {}
		for _, chapter in ipairs(state.chapters) do
			if chapter.time > 0.1 then
				local gx = round(t2x(chapter.time) - gap_w / 2)
				parts[#parts + 1] = string.format('m %d %d l %d %d l %d %d l %d %d',
					gx, track_ay, gx + gap_w, track_ay, gx + gap_w, track_by, gx, track_by)
			end
		end
		if #parts > 0 then gap_clip = '\\iclip(' .. table.concat(parts, ' ') .. ')' end
	end

	-- Unplayed track. Base is a darker translucent grey; while hovering, the stretch
	-- from the playhead up to the cursor lightens (YouTube-style seek preview). The
	-- already-watched white part is left clean — no line or tick painted back over it.
	ass:rect(track_ax, track_ay, track_bx, track_by,
		{color = 'ffffff', opacity = 0.25 * config.opacity.timeline, radius = track_r, clip = gap_clip})
	if hovering and cursor_x > fill_bx then
		ass:rect(math.max(track_ax, fill_bx), track_ay, cursor_x, track_by,
			{color = 'ffffff', opacity = 0.55 * config.opacity.timeline, clip = gap_clip})
	end

	-- Played fill: solid white
	ass:rect(track_ax, track_ay, math.max(track_ax, fill_bx), track_by,
		{color = 'ffffff', opacity = config.opacity.position, radius = track_r, clip = gap_clip})

	-- Uncached (buffering) ranges — subtle darkening confined to the track
	if state.uncached_ranges and options.timeline_cache then
		for _, range in ipairs(state.uncached_ranges) do
			local ax = range[1] < 0.5 and track_ax or math.floor(t2x(range[1]))
			local bx = range[2] > state.duration - 0.5 and track_bx or math.ceil(t2x(range[2]))
			ass:rect(ax, track_ay, bx, track_by, {color = '000000', opacity = 0.3 * config.opacity.timeline, clip = gap_clip})
		end
	end

	-- Custom (chapter) ranges — colored segments on the track
	for _, chapter_range in ipairs(state.chapter_ranges) do
		local rax = chapter_range.start < 0.1 and track_ax or t2x(chapter_range.start)
		local rbx = chapter_range['end'] > state.duration - 0.1 and track_bx
			or t2x(math.min(chapter_range['end'], state.duration))
		ass:rect(rax, track_ay, rbx, track_by, {color = chapter_range.color, opacity = chapter_range.opacity, clip = gap_clip})
	end

	-- Chapters are cut out of the track as transparent gaps (gap_clip, above), not
	-- painted marks. draw_mark stays only for the A-B loop indicators. Here we keep
	-- each chapter's click/hover zone (snapping is resolved at the top of render).
	local MARK_COLOR = '151515'
	local function draw_mark(x, opacity)
		local mx = round(x - mark_w / 2)
		ass:rect(mx, track_ay, mx + mark_w, track_by, {color = MARK_COLOR, opacity = opacity})
	end

	if config.opacity.chapters > 0 and #state.chapters > 0 then
		for _, chapter in ipairs(state.chapters) do
			if visibility > 0 and chapter == hovered_chapter then
				local cx = t2x(chapter.time)
				cursor:zone('primary_down',
					{ax = cx - hover_threshold, ay = track_ay - knob_r, bx = cx + hover_threshold, by = track_by + knob_r},
					function() mp.commandv('seek', chapter.time, 'absolute+exact') end)
			end
		end
	end

	-- A-B loop markers (same dark rectangle, full opacity)
	if config.opacity.chapters > 0 then
		if state.ab_loop_a and state.ab_loop_a >= 0 then draw_mark(t2x(state.ab_loop_a), 1) end
		if state.ab_loop_b and state.ab_loop_b > 0 then draw_mark(t2x(state.ab_loop_b), 1) end
	end

	-- Round white knob at the playhead (Netflix)
	local knob_cx = round(clamp(track_ax, fill_bx, track_bx))
	ass:circle(knob_cx, round(fcy), knob_r, {color = 'ffffff', opacity = config.opacity.position})

	-- Hover extras: time tooltip, thumbnail, chapter title. No vertical cursor line —
	-- the lighter preview segment is the seek indicator, keeping the watched part clean.
	local rendered_thumbnail = false
	if hovering then
		local hovered_seconds = hovered_chapter and hovered_chapter.time or self:get_time_at_x(cursor.x)
		local tooltip_gap = round(2 * state.scale)
		local tooltip_anchor = {ax = cursor_x, ay = round(fcy - knob_r), bx = cursor_x, by = round(fcy + knob_r)}

		-- Time at cursor
		local opts = {size = self.font_size, offset = tooltip_gap, margin = tooltip_gap, timestamp = options.time_precision > 0}
		local hovered_time_human = format_time(hovered_seconds, state.duration)
		opts.width_overwrite = timestamp_width(hovered_time_human, opts)
		tooltip_anchor = ass:tooltip(tooltip_anchor, hovered_time_human, opts)

		-- Thumbnail
		if not thumbnail.disabled
			and (not self.pressed or self.pressed.distance < 5)
			and thumbnail.width ~= 0
			and thumbnail.height ~= 0
		then
			local border = math.max(1, round(state.scale))
			local thumb_x_margin, thumb_y_margin = border + tooltip_gap + bax, border + tooltip_gap
			local thumb_width, thumb_height = thumbnail.width, thumbnail.height
			local thumb_x = round(clamp(
				thumb_x_margin,
				cursor_x - thumb_width / 2,
				display.width - thumb_width - thumb_x_margin
			))
			local thumb_y = round(tooltip_anchor.ay - thumb_y_margin - thumb_height)
			local tax, tay = (thumb_x - border), (thumb_y - border)
			local tbx, tby = (thumb_x + thumb_width + border), (thumb_y + thumb_height + border)
			-- Dark backing matte, sharp corners, no outline
			ass:rect(tax, tay, tbx, tby, {color = bg, opacity = config.opacity.thumbnail, radius = 0})
			local thumb_seconds = (state.rebase_start_time == false and state.start_time) and
				(hovered_seconds - state.start_time) or hovered_seconds
			mp.commandv('script-message-to', 'thumbfast', 'thumb', thumb_seconds, thumb_x, thumb_y)
			self.has_thumbnail, rendered_thumbnail = true, true
			tooltip_anchor.ay = tay
		end

		-- Chapter title
		if config.opacity.chapters > 0 and #state.chapters > 0 then
			local _, chapter = itable_find(state.chapters, function(c) return hovered_seconds >= c.time end,
				#state.chapters, 1)
			if chapter and not chapter.is_end_only then
				ass:tooltip(tooltip_anchor, chapter.title_wrapped, {
					size = self.font_size,
					offset = tooltip_gap,
					responsive = false,
					bold = true,
					width_overwrite = chapter.title_wrapped_width * self.font_size,
					lines = chapter.title_lines,
					margin = tooltip_gap,
				})
			end
		end
	end

	if not rendered_thumbnail then self:clear_thumbnail() end

	-- Corner timestamps: plain white digits over the video, vertically centered,
	-- hugging the strip edges. No outline (`timeline_timestamp_border`), like Netflix.
	if text_opacity > 0 then
		local func = options.time_precision > 0 and ass.timestamp or ass.txt
		local edge_opts = {
			size = time_size,
			opacity = text_opacity,
			border = time_border,
			color = 'ffffff',
		}
		-- Anchor each timecode to the track edge (not the window edge) so the gap to
		-- the slider is identical on both sides, whatever each number's width. `reserve`
		-- already guaranteed the room, so they can't overflow toward the window edge.
		func(ass, track_ax - edge_gap, fcy, 6, left_ts, edge_opts) -- elapsed, right-aligned
		func(ass, track_bx + edge_gap, fcy, 4, right_ts, edge_opts) -- remaining/total, left-aligned
	end

	-- DinaPlayer: cache the last good frame so a nil-blink during a file switch can
	-- redraw it instead of flashing the timeline out (see the guard above).
	self._last_ass = ass
	return ass
end

return Timeline

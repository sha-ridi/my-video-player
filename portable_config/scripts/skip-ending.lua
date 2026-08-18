-- DinaPlayer: "Skip Ending" — Netflix-style hand-off to the next episode.
--
-- When playback reaches the closing credits (found by chapter-sense.lua, which
-- only reports them for something that looks like an episode), a plate appears
-- in the bottom-right corner counting down from COUNTDOWN. Do nothing and the
-- next episode starts; click the plate to stay and watch the credits.
--
-- On by default; the choice persists next to the config like the other toggles.
-- The plate itself is drawn by uosc (elements/SkipEnding.lua), which reads the
-- countdown from `user-data/dinaplayer/ending-countdown`.
local state_path = mp.command_native({'expand-path', '~~/skip-ending.state'})
local enabled = true -- on by default (state file overrides if the user changed it)

local COUNTDOWN = 10

local ending_at = nil   -- when the credits start in this file
local dismissed = false -- user chose to watch the credits
local left = nil        -- seconds still on the clock
local timer = nil
-- Last episode of a multi-file playlist: there's nothing to hand off to, so the
-- plate shows a single "Watch credits" button (no countdown, no auto-advance).
local credits_only = false

local function publish_enabled()
	mp.set_property_native('user-data/dinaplayer/skip-ending', enabled)
end

-- How often the countdown updates. Sub-second so the plate's progress fill
-- sweeps smoothly instead of stepping once per second.
local COUNTDOWN_TICK = 0.05

-- Publish the current countdown state for the plate (elements/SkipEnding.lua):
-- the integer seconds for the label (10..1) and a 0..1 fill fraction for the
-- progress bar (0 at the start, 1 at the hand-off).
local function publish_countdown()
	if not left then return end
	mp.set_property_native('user-data/dinaplayer/ending-countdown', math.max(1, math.ceil(left)))
	mp.set_property_native('user-data/dinaplayer/ending-progress', (COUNTDOWN - left) / COUNTDOWN)
end

local function hide()
	left = nil
	if timer then timer:kill() end
	timer = nil
	credits_only = false
	mp.set_property_native('user-data/dinaplayer/ending-credits-only', false)
	-- 0 rather than nil: user-data keeps the key, and the plate treats it as off.
	mp.set_property_native('user-data/dinaplayer/ending-countdown', 0)
	mp.set_property_native('user-data/dinaplayer/ending-progress', 0)
end

--[[ Fade to black + silence at the hand-off, then back in on the next episode.
     The black is an ASS overlay so it reaches true black over any frame; the
     audio fade ramps the `volume` property, which is restored on the next file. ]]
local FADE_OUT, FADE_IN, STEP = 0.8, 0.6, 0.05
local orig_volume = nil    -- volume before the fade, restored after
local advancing = false    -- a countdown hand-off is in flight
local fade_timer = nil
local black = nil          -- the black overlay

-- o: 0 = clear, 1 = fully black
local function draw_black(o)
	if o <= 0 then
		if black then black:remove() end
		return
	end
	black = black or mp.create_osd_overlay('ass-events')
	local w = mp.get_property_number('osd-width') or 1920
	local h = mp.get_property_number('osd-height') or 1080
	black.res_x, black.res_y = w, h
	local a = string.format('%02X', math.floor((1 - o) * 255 + 0.5))
	black.data = string.format([[{\an7\pos(0,0)\bord0\shad0\1c&H000000&\1a&H%s&\p1}m 0 0 l %d 0 %d %d 0 %d{\p0}]], a, w, w, h, h)
	black:update()
end

local function stop_fade()
	if fade_timer then fade_timer:kill(); fade_timer = nil end
end

local function fade_out(done)
	stop_fade()
	orig_volume = mp.get_property_number('volume') or 100
	local n, i = math.max(1, math.floor(FADE_OUT / STEP)), 0
	fade_timer = mp.add_periodic_timer(FADE_OUT / n, function()
		i = i + 1
		local o = i / n
		draw_black(o)
		mp.set_property_number('volume', orig_volume * (1 - o))
		if i >= n then stop_fade(); if done then done() end end
	end)
end

local function fade_in()
	stop_fade()
	local target = orig_volume or mp.get_property_number('volume') or 100
	draw_black(1)
	mp.set_property_number('volume', 0)
	local n, i = math.max(1, math.floor(FADE_IN / STEP)), 0
	fade_timer = mp.add_periodic_timer(FADE_IN / n, function()
		i = i + 1
		local k = i / n
		draw_black(1 - k)
		mp.set_property_number('volume', target * k)
		if i >= n then
			stop_fade(); draw_black(0)
			mp.set_property_number('volume', target); orig_volume = nil
		end
	end)
end

-- Undo an in-flight fade (user cancelled, or the next file never loaded).
local function abort_fade()
	stop_fade()
	draw_black(0)
	if orig_volume ~= nil then mp.set_property_number('volume', orig_volume); orig_volume = nil end
	advancing = false
end

local function has_next_episode()
	local pos = mp.get_property_number('playlist-pos')
	local count = mp.get_property_number('playlist-count') or 0
	return pos ~= nil and pos + 1 < count
end

-- The last entry of a playlist that holds more than one video (i.e. the final
-- episode of a series). A single lone file is left alone.
local function is_last_of_multi()
	local pos = mp.get_property_number('playlist-pos')
	local count = mp.get_property_number('playlist-count') or 0
	return pos ~= nil and count > 1 and pos + 1 >= count
end

-- Show just the "Watch credits" button (no countdown / hand-off).
local function show_credits_only()
	credits_only = true
	mp.set_property_native('user-data/dinaplayer/ending-credits-only', true)
end

-- Fade the picture to black and the sound down, THEN switch. The next episode
-- fades back in (see file-loaded). Start it from the top, ignoring its saved
-- position: the hand-off means "play the next one", and landing mid-episode is
-- never what it meant. mpv applies `resume-playback` while loading, so turning it
-- off here covers exactly this one file; file-loaded puts it back, leaving the
-- next/prev buttons resuming as before. Skip Opening still runs (seeks from 0).
local function advance_now()
	hide()
	advancing = true
	fade_out(function()
		mp.set_property_bool('resume-playback', false)
		mp.commandv('playlist-next')
		-- Safety: never leave the screen black if the next file fails to load.
		mp.add_timeout(5, function() if advancing then abort_fade() end end)
	end)
end

local function tick()
	-- Paused mid-credits: hold the countdown rather than jumping on its own.
	if mp.get_property_bool('pause') then return end
	if not left then return end
	left = left - COUNTDOWN_TICK
	if left <= 0 then
		advance_now()
	else
		publish_countdown()
	end
end

local function start()
	if timer then timer:kill() end
	left = COUNTDOWN
	publish_countdown()
	timer = mp.add_periodic_timer(COUNTDOWN_TICK, tick)
end

local function read_state()
	local f = io.open(state_path, 'r')
	if f then
		local s = f:read('*a') or ''
		f:close()
		enabled = s:find('yes') ~= nil
	end
end

local function write_state()
	local f = io.open(state_path, 'w')
	if f then
		f:write(enabled and 'yes' or 'no')
		f:close()
	end
end

read_state()
publish_enabled()

mp.register_event('file-loaded', function()
	hide()
	dismissed = false
	ending_at = nil
	-- The auto-advance above turns this off for one file; anything opened after
	-- that resumes normally again.
	mp.set_property_bool('resume-playback', true)
	-- If we arrived here by the countdown, fade the picture and sound back in;
	-- any other open (manual next/prev, launch) clears a stray fade harmlessly.
	if advancing then advancing = false; fade_in() else abort_fade() end
end)

-- chapter-sense.lua answers a moment after load (it needs the duration), so take
-- the credits position from the property as it changes.
mp.observe_property('user-data/dinaplayer/marks', 'native', function(_, marks)
	ending_at = type(marks) == 'table' and marks.ending_start or nil
end)

mp.observe_property('time-pos', 'number', function(_, pos)
	if not enabled or dismissed or advancing or not ending_at or not pos then return end
	if left or credits_only then
		-- Seeked back out of the credits: put the plate away.
		if pos < ending_at - 1 then hide() end
		return
	end
	if pos >= ending_at then
		if has_next_episode() then start()
		elseif is_last_of_multi() then show_credits_only() end
	end
end)

-- Clicking the plate: stay on this episode, and don't offer again for this file.
mp.register_script_message('dina-ending-cancel', function()
	if not left and not credits_only then return end
	hide()
	dismissed = true
end)

-- Clicking "Next episode": jump immediately instead of waiting out the countdown.
mp.register_script_message('dina-ending-next', function()
	if not left then return end
	advance_now()
end)

mp.register_script_message('skip-ending-toggle', function()
	enabled = not enabled
	write_state()
	publish_enabled()
	if not enabled then hide() end
end)

-- DinaPlayer: works out which chapters are the opening and the closing credits.
--
-- Chapter lists are wildly inconsistent, so the rules are deliberately
-- conservative — when a file doesn't look like a series episode we simply
-- report nothing and the player behaves as if the feature was off. Named
-- chapters ("OP", "Ending", "Титры"…) are trusted more than shape alone.
--
-- Publishes what it found for the current file as `user-data/dinaplayer/marks`:
--   {opening_end = <seconds>|nil, ending_start = <seconds>|nil}
-- so skip-opening.lua and skip-ending.lua just read the answer.

local OPENING_WORDS = {'opening', 'op', 'intro', 'заставка', 'опенинг', 'вступление', 'титры'}
local ENDING_WORDS = {'ending', 'ed', 'credits', 'outro', 'эндинг', 'титры', 'концовка'}

-- An episode. Films get left alone: their long title sequences and end credits
-- are part of the thing you sat down to watch.
local MIN_EPISODE = 5 * 60
local MAX_EPISODE = 90 * 60

local OPENING_MIN, OPENING_MAX = 40, 150 -- a themed opening, in seconds
local OPENING_SEARCH = 6 * 60            -- openings live near the start
local ENDING_MIN, ENDING_MAX = 20, 240   -- closing credits
local ENDING_FROM = 0.7                  -- and in the last portion of the file

local function has_word(title, words)
	if not title then return false end
	local low = title:lower()
	for _, w in ipairs(words) do
		-- Whole word only, so "Operation" isn't read as "OP".
		if low:find('%f[%w]' .. w .. '%f[%W]') then return true end
	end
	return false
end

-- Segments of the file: the gap before the first chapter counts as one too,
-- because plenty of releases mark the opening by putting a chapter after it.
local function segments(chapters, duration)
	local out = {}
	if #chapters == 0 then return out end
	if chapters[1].time > 1 then
		out[#out + 1] = {start = 0, stop = chapters[1].time, title = nil}
	end
	for i, ch in ipairs(chapters) do
		out[#out + 1] = {start = ch.time, stop = chapters[i + 1] and chapters[i + 1].time or duration, title = ch.title}
	end
	return out
end

---@return number|nil time to skip the opening to
local function find_opening(chapters, duration)
	local segs = segments(chapters, duration)
	if #segs < 2 then return nil end

	-- 1. A chapter that says what it is. Never the last one — skipping into it
	--    would skip the episode.
	for i, seg in ipairs(segs) do
		if seg.start > OPENING_SEARCH then break end
		local length = seg.stop - seg.start
		if i < #segs and has_word(seg.title, OPENING_WORDS) and length >= 10 and length <= 300 then
			return seg.stop
		end
	end

	-- 2. Nothing named: look for an opening-sized piece near the start that is
	--    followed by a far longer one — that longer piece is the episode. Takes
	--    the last such piece, so a short cold open before the opening (a common
	--    layout) doesn't get mistaken for the opening itself.
	if duration < MIN_EPISODE or duration > MAX_EPISODE then return nil end
	local target
	for i, seg in ipairs(segs) do
		if seg.start > OPENING_SEARCH then break end
		local length, next_seg = seg.stop - seg.start, segs[i + 1]
		if next_seg and length >= OPENING_MIN and length <= OPENING_MAX
			and (next_seg.stop - next_seg.start) >= length * 3 then
			target = seg.stop
		end
	end
	return target
end

---@return number|nil time the closing credits start at
local function find_ending(chapters, duration)
	if #chapters < 2 then return nil end
	local last = chapters[#chapters]
	local length = duration - last.time
	if has_word(last.title, ENDING_WORDS) and length >= 10 and length <= 400 then
		return last.time
	end
	local episode_like = duration >= MIN_EPISODE and duration <= MAX_EPISODE
	if episode_like and length >= ENDING_MIN and length <= ENDING_MAX
		and last.time >= duration * ENDING_FROM then
		return last.time
	end
	return nil
end

local function publish()
	local duration = mp.get_property_number('duration')
	local chapters = mp.get_property_native('chapter-list', {})
	if not duration or duration <= 0 then
		mp.set_property_native('user-data/dinaplayer/marks', {})
		return
	end
	mp.set_property_native('user-data/dinaplayer/marks', {
		opening_end = find_opening(chapters, duration),
		ending_start = find_ending(chapters, duration),
	})
end

mp.register_event('file-loaded', publish)
mp.observe_property('chapter-list', 'native', publish)
-- `duration` is often still unknown when the file loads, which would publish an
-- empty result; republish once it (and the chapters) are actually known.
mp.observe_property('duration', 'native', publish)

-- Debug helper for checking the rules against made-up files:
--   script-message dina-marks-test '{"duration":1440,"chapters":[{"time":0,"title":"OP"}]}'
mp.register_script_message('dina-marks-test', function(json)
	local data = require('mp.utils').parse_json(json)
	if not data then return end
	local o = find_opening(data.chapters or {}, data.duration)
	local e = find_ending(data.chapters or {}, data.duration)
	mp.msg.info(string.format('MARKS %s -> opening_end=%s ending_start=%s',
		tostring(data.name or '?'), tostring(o), tostring(e)))
end)

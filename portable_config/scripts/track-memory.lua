-- DinaPlayer: remembers the LANGUAGE you pick for audio / subtitles / secondary
-- subtitles and applies it to files opened later, like Netflix does for a series.
--
-- Without this, a track choice only survived inside one session (mpv keeps the
-- properties) or for that exact file (saved in its watch-later). Opening a fresh
-- episode after restarting the player fell back to the alang/slang defaults.
--
-- Only manual choices are remembered: changes within GUARD seconds of loading a
-- file are mpv's own automatic track selection (and our own applying below), so
-- they're ignored. A file being resumed keeps whatever was saved for it — the
-- remembered language is only applied when a file starts from the beginning.
local state_path = mp.command_native({'expand-path', '~~/track-prefs.state'})
local GUARD = 1.0

local KEYS = {'aid', 'sid', 'ssid'}
-- aid / sid / ssid -> {lang = code or 'no' (turned off), title, forced, n}.
-- Language alone isn't enough: a series often has several tracks in one
-- language (forced + full subtitles, two dubs), so the title, the forced flag
-- and the position among same-language tracks pick the right one of them.
local prefs = {}
local last_load = 0

local function read_state()
	local f = io.open(state_path, 'r')
	if not f then return end
	for line in f:lines() do
		local k, field, v = line:match('^(%w+)%.?(%w*)=(.*)$')
		if k and v then
			prefs[k] = prefs[k] or {}
			prefs[k][field == '' and 'lang' or field] = v
		end
	end
	f:close()
end

local function write_state()
	local f = io.open(state_path, 'w')
	if not f then return end
	for _, k in ipairs(KEYS) do
		local p = prefs[k]
		if p and p.lang then
			f:write(k, '=', p.lang, '\n')
			for _, field in ipairs({'title', 'forced', 'n'}) do
				if p[field] then f:write(k, '.', field, '=', p[field], '\n') end
			end
		end
	end
	f:close()
end

---@return table|nil {lang, title, forced, n} describing the given track id
local function describe(track_type, id)
	local n = tonumber(id)
	if not n then return nil end
	local tracks = mp.get_property_native('track-list', {})
	local lang
	for _, t in ipairs(tracks) do
		if t.type == track_type and t.id == n and t.lang and #t.lang > 0 then lang = t.lang:lower() end
	end
	if not lang then return nil end
	local index = 0
	for _, t in ipairs(tracks) do
		if t.type == track_type and t.lang and t.lang:lower() == lang then
			index = index + 1
			if t.id == n then
				return {
					lang = lang,
					title = ((t.title or ''):gsub('[\r\n]', ' ')),
					forced = t.forced and 'yes' or 'no',
					n = tostring(index),
				}
			end
		end
	end
end

local function same(a, b)
	return a and b and a.lang == b.lang and a.title == b.title and a.forced == b.forced and a.n == b.n
end

local function store(key, track_type, value)
	local pref = (value == 'no' or value == nil) and {lang = 'no'} or describe(track_type, value)
	if pref and not same(pref, prefs[key]) then
		prefs[key] = pref
		write_state()
	end
end

local function remember(key, track_type, value)
	if mp.get_time() - last_load < GUARD then return end -- automatic selection, not a choice
	store(key, track_type, value)
end

mp.observe_property('sid', 'string', function(_, v) remember('sid', 'sub', v) end)
mp.observe_property('secondary-sid', 'string', function(_, v) remember('ssid', 'sub', v) end)
mp.observe_property('aid', 'string', function(_, v) remember('aid', 'audio', v) end)

---@return number|nil id of the track of that type that best matches the pref
local function find_track(track_type, pref, exclude_id)
	local best_id, best_score, index = nil, -1, 0
	for _, t in ipairs(mp.get_property_native('track-list', {})) do
		if t.type == track_type and t.lang and t.lang:lower() == pref.lang then
			index = index + 1
			if t.id ~= exclude_id then
				local score = 0
				if pref.title and pref.title ~= '' and (t.title or '') == pref.title then score = score + 4 end
				if pref.forced and (t.forced and 'yes' or 'no') == pref.forced then score = score + 2 end
				if pref.n and tostring(index) == pref.n then score = score + 1 end
				if score > best_score then best_id, best_score = t.id, score end
			end
		end
	end
	return best_id
end

-- An explicit pick from a menu: trusted, so it skips the post-load guard that
-- exists only to ignore mpv's automatic track selection.
mp.register_script_message('dina-track-chosen', function(key, value)
	if not key then return end
	store(key, key == 'aid' and 'audio' or 'sub', value)
end)

mp.register_event('file-loaded', function()
	last_load = mp.get_time()
	-- Resuming a file: keep the tracks saved for it, don't override.
	if (mp.get_property_number('time-pos', 0) or 0) > 1 then return end

	local function apply(key, prop, track_type, exclude_id)
		local pref = prefs[key]
		if not pref or not pref.lang then return nil end
		if pref.lang == 'no' then
			mp.set_property(prop, 'no')
			return nil
		end
		local id = find_track(track_type, pref, exclude_id)
		if id then mp.set_property(prop, tostring(id)) end
		return id
	end

	apply('aid', 'aid', 'audio')
	local sid = apply('sid', 'sid', 'sub')
	-- Never put the same track in both slots (mirrors the subtitles menu rule).
	apply('ssid', 'secondary-sid', 'sub', sid)
end)

read_state()

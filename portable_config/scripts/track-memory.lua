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

local prefs = {} -- aid / sid / ssid -> language code, or 'no' (turned off)
local last_load = 0

local function read_state()
	local f = io.open(state_path, 'r')
	if not f then return end
	for line in f:lines() do
		local k, v = line:match('^(%w+)=(.+)$')
		if k and v then prefs[k] = v end
	end
	f:close()
end

local function write_state()
	local f = io.open(state_path, 'w')
	if not f then return end
	for _, k in ipairs({'aid', 'sid', 'ssid'}) do
		if prefs[k] then f:write(k, '=', prefs[k], '\n') end
	end
	f:close()
end

---@return string|nil language of the given track id, lowercased
local function lang_of(track_type, id)
	local n = tonumber(id)
	if not n then return nil end
	for _, t in ipairs(mp.get_property_native('track-list', {})) do
		if t.type == track_type and t.id == n and t.lang and #t.lang > 0 then
			return t.lang:lower()
		end
	end
	return nil
end

local function remember(key, track_type, value)
	if mp.get_time() - last_load < GUARD then return end -- automatic selection, not a choice
	local pref = value == 'no' and 'no' or lang_of(track_type, value)
	if pref and pref ~= prefs[key] then
		prefs[key] = pref
		write_state()
	end
end

mp.observe_property('sid', 'string', function(_, v) remember('sid', 'sub', v) end)
mp.observe_property('secondary-sid', 'string', function(_, v) remember('ssid', 'sub', v) end)
mp.observe_property('aid', 'string', function(_, v) remember('aid', 'audio', v) end)

---@return number|nil id of the first track of that type in the given language
local function find_track(track_type, lang, exclude_id)
	for _, t in ipairs(mp.get_property_native('track-list', {})) do
		if t.type == track_type and t.lang and t.lang:lower() == lang and t.id ~= exclude_id then
			return t.id
		end
	end
	return nil
end

-- An explicit pick from a menu: trusted, so it skips the post-load guard that
-- exists only to ignore mpv's automatic track selection.
mp.register_script_message('dina-track-chosen', function(key, value)
	if not key then return end
	local track_type = key == 'aid' and 'audio' or 'sub'
	local pref = (value == 'no' or value == nil) and 'no' or lang_of(track_type, value)
	if pref and pref ~= prefs[key] then
		prefs[key] = pref
		write_state()
	end
end)

mp.register_event('file-loaded', function()
	last_load = mp.get_time()
	-- Resuming a file: keep the tracks saved for it, don't override.
	if (mp.get_property_number('time-pos', 0) or 0) > 1 then return end

	local function apply(key, prop, track_type, exclude_id)
		local pref = prefs[key]
		if not pref then return nil end
		if pref == 'no' then
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

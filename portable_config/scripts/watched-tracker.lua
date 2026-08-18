-- DinaPlayer: remembers which playlist entries have been watched or are still in
-- progress, and exposes both sets via `user-data/dina-watched` and
-- `user-data/dina-inprogress` so the uosc playlist can mark them (see the playlist
-- serializer in scripts/uosc/main.lua).
--
--   * watched     - playback passed WATCH_THRESHOLD percent (or hit EOF).
--   * in progress - playback got past START_THRESHOLD but not to WATCH_THRESHOLD.
--
-- The key is the playlist entry's `filename` — the exact same string uosc's
-- playlist sees — so matching is a plain table lookup.
--
-- Persisted to cache/watched.txt and cache/inprogress.txt. cache/ is auto-created
-- by mpv (shader cache) and is excluded from player updates, so the history
-- survives across updates.
local utils = require 'mp.utils'

local watched_path = mp.command_native({'expand-path', '~~/cache/watched.txt'})
local inprogress_path = mp.command_native({'expand-path', '~~/cache/inprogress.txt'})
local WATCH_THRESHOLD = 90 -- percent that counts a file as fully watched
local START_THRESHOLD = 5 -- percent past which a file counts as "in progress"
local watched = {} -- set: filename -> true
local in_progress = {} -- set: filename -> true

local function publish()
	mp.set_property_native('user-data/dina-watched', watched)
	mp.set_property_native('user-data/dina-inprogress', in_progress)
end

local function read_set(path, set)
	local f = io.open(path, 'r')
	if not f then return end
	for line in f:lines() do
		if line and #line > 0 then set[line] = true end
	end
	f:close()
end

local function write_set(path, set)
	local f = io.open(path, 'w')
	if not f then return end -- cache/ not there yet; will retry on the next change
	for key in pairs(set) do f:write(key, '\n') end
	f:close()
end

local function current_key()
	local pos = mp.get_property_number('playlist-pos')
	if not pos or pos < 0 then return nil end
	return mp.get_property('playlist/' .. pos .. '/filename')
end

local function mark_watched()
	local key = current_key()
	if not key or watched[key] then return end
	watched[key] = true
	write_set(watched_path, watched)
	if in_progress[key] then -- promote: it's fully watched now, no longer "in progress"
		in_progress[key] = nil
		write_set(inprogress_path, in_progress)
	end
	publish()
end

local function mark_in_progress()
	local key = current_key()
	if not key or watched[key] or in_progress[key] then return end
	in_progress[key] = true
	write_set(inprogress_path, in_progress)
	publish()
end

mp.observe_property('percent-pos', 'number', function(_, pct)
	if not pct then return end
	if pct >= WATCH_THRESHOLD then
		mark_watched()
	elseif pct >= START_THRESHOLD then
		mark_in_progress()
	end
end)

mp.register_event('end-file', function(event)
	if event.reason == 'eof' then mark_watched() end
end)

-- Manual toggle from the playlist: flip a file's "seen" state.
--   seen (checkmark)  -> unseen: remove from both sets (no icon)
--   unseen / clock    -> seen:  add to watched, clear in_progress (checkmark)
-- The resume position (watch_later) is never touched, so playback still resumes.
mp.register_script_message('dina-toggle-seen', function(key)
	if not key or key == '' then return end
	if watched[key] then
		watched[key] = nil
		in_progress[key] = nil
	else
		watched[key] = true
		in_progress[key] = nil
	end
	write_set(watched_path, watched)
	write_set(inprogress_path, in_progress)
	publish()
end)

read_set(watched_path, watched)
read_set(inprogress_path, in_progress)
publish()

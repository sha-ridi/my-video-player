-- DinaPlayer: remember the player volume across sessions. One global value for
-- everything (not per file) — the volume slider sets it, and it comes back at the
-- next launch. Persisted to volume.state next to the config (excluded from the
-- release ZIP and .gitignore'd, like the other *.state files). Mute is NOT
-- remembered — it always starts off.
local state_path = mp.command_native({'expand-path', '~~/volume.state'})

local function read_saved()
	local f = io.open(state_path, 'r')
	if not f then return nil end
	local s = f:read('*a') or ''
	f:close()
	return tonumber((s:gsub('%s+', '')))
end

local last_written = nil
local function save(v)
	v = math.max(0, math.min(100, math.floor(v + 0.5)))
	if v == last_written then return end
	local f = io.open(state_path, 'w')
	if not f then return end
	f:write(tostring(v))
	f:close()
	last_written = v
end

-- Restore the saved volume once at startup.
local saved = read_saved()
if saved then
	last_written = math.max(0, math.min(100, math.floor(saved + 0.5)))
	mp.set_property_number('volume', last_written)
end

-- Persist on every change (writes are tiny and de-duplicated above).
mp.observe_property('volume', 'number', function(_, v)
	if v then save(v) end
end)

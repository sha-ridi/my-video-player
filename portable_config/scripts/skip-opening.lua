-- DinaPlayer: "Skip Opening" — when on, playback starts past the opening.
-- On by default; the choice persists in a state file next to the config and the
-- Settings popup renders it as a one-click toggle.
--
-- Which part counts as the opening is decided by scripts/chapter-sense.lua (it
-- only reports one when the file really looks like a series episode), so films
-- and oddly chaptered files are left alone.
local state_path = mp.command_native({'expand-path', '~~/skip-opening.state'})
local enabled = true -- on by default (state file overrides if the user changed it)

local function publish()
	mp.set_property_native('user-data/dinaplayer/skip-opening', enabled)
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
publish()

-- chapter-sense.lua can only work the opening out once the duration is known,
-- which is usually a moment after the file loads — so react to its answer
-- arriving rather than reading it once and giving up.
local handled_path = nil

mp.register_event('file-loaded', function() handled_path = nil end)

mp.observe_property('user-data/dinaplayer/marks', 'native', function(_, marks)
	if not enabled or type(marks) ~= 'table' then return end
	local target = marks.opening_end
	local path = mp.get_property('path')
	if not target or target <= 0.5 or handled_path == path then return end
	-- Only at the start: a file resumed past the opening keeps its position.
	if (mp.get_property_number('time-pos', 0) or 0) < target then
		handled_path = path
		mp.commandv('seek', tostring(target), 'absolute+exact')
	end
end)

mp.register_script_message('skip-opening-toggle', function()
	enabled = not enabled
	write_state()
	publish()
end)

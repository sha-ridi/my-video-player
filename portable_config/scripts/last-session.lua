-- DinaPlayer: remembers the last thing you watched and reopens it when the
-- player is launched on its own (double-clicking DinaPlayer.exe or its shortcut,
-- with no file). autoload then rebuilds the playlist from that folder, and the
-- usual resume/Skip Opening rules apply, so it lands you right back where you
-- were — instead of an empty player.
--
-- Only restores at startup: if any file has been opened this session, becoming
-- idle later never pulls the old one back.
local utils = require 'mp.utils'

local state_path = mp.command_native({'expand-path', '~~/last-file.state'})
local had_file = false
local restored = false

local function is_url(p) return p:find('^%a[%w+.%-]*://') ~= nil end

---@return string|nil absolute path (or URL) of what's playing
local function current_path()
	local p = mp.get_property('path')
	if not p or p == '' then return nil end
	if is_url(p) then return p end
	-- Make it absolute: a relative path would break once the working directory differs.
	if not (p:match('^%a:[/\\]') or p:match('^[/\\][/\\]') or p:match('^[/\\]')) then
		local cwd = mp.get_property('working-directory')
		if cwd then p = utils.join_path(cwd, p) end
	end
	return p
end

mp.register_event('file-loaded', function()
	had_file = true
	local p = current_path()
	if not p then return end
	local f = io.open(state_path, 'w')
	if f then
		f:write(p)
		f:close()
	end
end)

mp.observe_property('idle-active', 'bool', function(_, idle)
	if restored or had_file or not idle then return end
	restored = true
	local f = io.open(state_path, 'r')
	if not f then return end
	local p = (f:read('*a') or ''):gsub('%s+$', '')
	f:close()
	if p == '' then return end
	-- Skip a file that no longer exists (deleted, or an unplugged drive).
	if not is_url(p) and not utils.file_info(p) then return end
	mp.commandv('loadfile', p)
end)

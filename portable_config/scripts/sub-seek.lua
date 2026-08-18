-- DinaPlayer: jump to the previous / next subtitle line (bound to , and . in
-- input.conf). Playback moves to that line's start, so the subtitle text on
-- screen updates with it — handy for re-reading a phrase or skipping ahead by
-- dialogue instead of by seconds.
--
-- It always follows the primary subtitle track.
--
-- mpv's own `sub-seek` only knows about subtitle events that were already shown
-- or sit inside the demuxer's read-ahead window, so it does nothing before the
-- first line of an episode or across a long silence. When that happens we scan:
-- hop the position forward/backward in read-ahead-sized steps (so no line can
-- slip between two probes), retrying at each stop, and give up back where we
-- started if there really is nothing.
local HOP = 45        -- seconds per probe; must stay below demuxer-readahead-secs
local MAX_HOPS = 40   -- ≈30 minutes of silence before giving up
local SETTLE = 0.25   -- let the demuxer fill after a seek
local CHECK = 0.15    -- let a sub-seek apply before reading time-pos
local scanning = false

local function seek_to(t) mp.commandv('no-osd', 'seek', tostring(t), 'absolute+keyframes') end
local function raw_sub_seek(n) mp.command_native({'sub-seek', n, 'primary'}) end
local function pos() return mp.get_property_number('time-pos') or 0 end

local function scan(n, origin, hop)
	if hop > MAX_HOPS then
		scanning = false
		seek_to(origin) -- nothing found: leave the viewer where they were
		return
	end
	local duration = mp.get_property_number('duration')
	local probe = n > 0 and (origin + HOP * hop) or (origin - HOP * hop)
	if (n > 0 and duration and probe >= duration - 0.5) or (n < 0 and probe <= 0) then
		scanning = false
		seek_to(origin)
		return
	end

	seek_to(probe)
	mp.add_timeout(SETTLE, function()
		-- Going back: the probe pulled the surrounding lines into the cache, so
		-- retry from where we started; going forward we can just look ahead.
		if n < 0 then seek_to(origin) end
		mp.add_timeout(n < 0 and SETTLE or 0, function()
			local from = pos()
			raw_sub_seek(n)
			mp.add_timeout(CHECK, function()
				if math.abs(pos() - from) > 0.15 then
					scanning = false -- landed on a subtitle
				else
					scan(n, origin, hop + 1)
				end
			end)
		end)
	end)
end

mp.register_script_message('dina-sub-seek', function(amount)
	local n = tonumber(amount)
	if not n or scanning then return end
	-- Nothing to seek by if no subtitle track is selected.
	if not mp.get_property_number('sid') then return end

	local origin = pos()
	raw_sub_seek(n)
	mp.add_timeout(CHECK, function()
		if math.abs(pos() - origin) > 0.15 then return end -- worked outright
		scanning = true
		scan(n, origin, 1)
	end)
end)

-- DinaPlayer: turns release-style file names into readable titles.
--
--   The.Sopranos.S06E20.576p.BluRay.Goblin.Eng.HBO  ->  The Sopranos  ·  S06E20
--   Шрэк (2001) {BDRip-AVC} [Живов] [Дольский]      ->  Шрэк (2001)
--   [SubsPlease] Frieren - 05 (1080p) [A1B2C3D4]    ->  Frieren  ·  05
--
-- The cleaned name is pushed into `force-media-title` (so uosc's top bar shows
-- it) and, for every playlist entry, published as `user-data/dina-pretty` for
-- the playlist menu. Names we can't confidently parse (a phone clip, a screen
-- recording) are left exactly as they are — better untouched than mangled.

-- Tokens that mark where the actual title ends and release details begin.
local TECH = {
	'2160p', '1080p', '720p', '576p', '480p', '4k', 'uhd',
	'bluray', 'blu%-ray', 'bdremux', 'bdrip', 'brrip', 'remux', 'webrip', 'web%-dl', 'webdl', 'web',
	'hdtv', 'dvdrip', 'hdrip', 'dvd', 'ts', 'camrip',
	'x264', 'x265', 'h264', 'h265', 'h%.264', 'h%.265', 'hevc', 'avc', 'xvid', 'divx',
	'10bit', '8bit', 'hdr10', 'hdr', 'dolby', 'atmos', 'dts', 'eac3', 'ac3', 'ddp', 'dd5', 'aac', 'mp3', 'flac', 'opus',
	'repack', 'proper', 'extended', 'uncut', 'limited', 'internal', 'complete',
	'hbo', 'amzn', 'dsnp', 'hulu', 'netflix', 'nf',
	'goblin', 'mvo', 'dvo', 'avo', 'dub', 'dubbed', 'subs', 'sub',
	'rus', 'eng', 'jpn', 'ukr', 'multi',
	'lostfilm', 'newstudio', 'kubik', 'jaskier', 'hdrezka', 'kurazh', 'kerob',
}

local function trim(s) return (s:gsub('^[%s%-_%.]+', ''):gsub('[%s%-_%.]+$', '')) end

-- Strip the directory and the extension.
local function stem(path)
	local base = path:match('([^/\\]+)$') or path
	return (base:gsub('%.[^%.]+$', ''))
end

---@return string|nil title, string|nil episode, string|nil year
local function parse(name)
	-- Leading [ReleaseGroup] and trailing [hash] / {tech} blocks.
	name = name:gsub('^%s*%[[^%]]-%]%s*', '')
	local removed
	repeat
		name, removed = name:gsub('%s*[%[{][^%]}]-[%]}]%s*$', '')
	until removed == 0

	-- Dot/underscore separated releases become spaces; names that already use
	-- spaces keep their dots (they may belong to the title).
	local _, dots = name:gsub('%.', '')
	local _, spaces = name:gsub(' ', '')
	if dots >= 2 and spaces <= 1 then name = name:gsub('%.', ' ') end
	name = name:gsub('_', ' ')

	local lower = name:lower()
	local episode, cut_at

	-- S06E20 / s6e20, with a non-letter (or nothing) in front so it can't match inside a word.
	local s, _, season, ep = lower:find('s(%d%d?%d?)e(%d%d?%d?)')
	if s then
		local before = s > 1 and lower:sub(s - 1, s - 1) or ' '
		if before:match('[%s%-%.%[%(]') then
			episode = string.format('S%02dE%02d', tonumber(season), tonumber(ep))
			cut_at = s
		end
	end
	if not episode then -- 1x02
		local s2, _, a, b = lower:find('(%d%d?)x(%d%d?%d?)')
		if s2 then
			episode, cut_at = a .. 'x' .. b, s2
		end
	end
	if not episode then -- anime style: "Title - 05"
		local title_part, num = name:match('^(.-)%s+%-%s+(%d%d?%d?)%s*')
		if title_part and #title_part > 0 then
			episode = num
			cut_at = #title_part + 1
		end
	end

	local year = lower:match('[%(%[%s](19%d%d)[%)%]%s]') or lower:match('[%(%[%s](20%d%d)[%)%]%s]')

	local title = cut_at and name:sub(1, cut_at - 1) or name

	-- Everything from the first release token onwards is noise.
	local first
	for _, token in ipairs(TECH) do
		local lowered = title:lower()
		local at = lowered:find('[%s%.%-%[%({]' .. token .. '[%s%.%-%]%)}]') or
			lowered:find('[%s%.%-%[%({]' .. token .. '$')
		if at and (not first or at < first) then first = at end
	end
	if first then title = title:sub(1, first - 1) end

	-- Leftover bracket blocks, the year, and doubled spaces.
	title = title:gsub('[%[{%(][^%]}%)]-[%]}%)]', ' ')
	if year then title = title:gsub(year, ' ') end
	title = trim(title:gsub('%s%s+', ' '))

	if #title == 0 then return nil end
	return title, episode, year
end

---@return string|nil a display name, or nil to keep the original
local function pretty(path)
	if not path or path:find('^%a[%w+.%-]*://') then return nil end -- leave URLs alone
	local name = stem(path)
	if not name or #name == 0 then return nil end
	local title, episode, year = parse(name)
	if not title then return nil end
	if episode then return title .. '  ·  ' .. episode end
	if year then return title .. ' (' .. year .. ')' end
	-- No episode and no year: only worth showing if we actually tidied something.
	if title ~= name then return title end
	return nil
end

local function apply_current()
	local path = mp.get_property('path')
	if not path then return end
	-- Always assign an explicit title. Clearing the override doesn't make mpv
	-- recompute `media-title`, so an unparsable file would otherwise keep showing
	-- the previous one. Fall back to the file's own title tag, then to its name.
	local nice = pretty(path)
	if not nice then
		local tagged = mp.get_property('metadata/by-key/Title')
		nice = (tagged and #tagged > 0) and tagged or stem(path)
	end
	mp.set_property('force-media-title', nice)
end

local function publish_playlist()
	local map = {}
	for _, entry in ipairs(mp.get_property_native('playlist', {})) do
		if entry.filename then
			local nice = pretty(entry.filename)
			if nice then map[entry.filename] = nice end
		end
	end
	mp.set_property_native('user-data/dina-pretty', map)
end

-- `force-media-title` is a sticky global override: mpv keeps showing our value
-- until we change it. The catch is that mpv also snapshots the *current*
-- `media-title` into `playlist/N/title` when it switches entries — and that
-- happens before `file-loaded` fires for the new file, so the still-forced title
-- of the *previous* episode would leak into the new entry (every played row ends
-- up labelled with its neighbour's title). Dropping the override the moment a new
-- file starts lets mpv record each entry's own real title; `apply_current` then
-- re-forces our pretty title for the top bar once the file is loaded.
local function clear_override() mp.set_property('force-media-title', '') end

mp.register_event('start-file', clear_override)
mp.register_event('file-loaded', apply_current)
mp.observe_property('playlist', 'native', publish_playlist)

-- Debug helper: `script-message dina-pretty-of "<name>"` logs how it'd be shown.
mp.register_script_message('dina-pretty-of', function(name)
	mp.msg.info('PRETTY [' .. tostring(name) .. '] -> [' .. tostring(pretty(name)) .. ']')
end)

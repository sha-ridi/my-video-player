-- DinaPlayer: picks up dub tracks and subtitles that sit next to the video as
-- separate files — the usual layout of Russian releases, e.g.
--
--   Шрэк (2001) {BDRip-AVC} [Живов] [Дольский].mkv
--   Шрэк (2001) {BDRip-AVC} [Живов] [Дольский] - 1. Сергей Визгунов (VHS).ac3
--   Шрэк (2001) {BDRip-AVC} [Живов] [Дольский] - 2. Андрей Гаврилов (VHS).ac3
--   Shrek dvd rip Xvid.Rets.srt
--
-- mpv's own auto-loading is left off (mpv.conf) and everything happens here so
-- the tracks get readable names: the shared file name is stripped, leaving
-- "1. Сергей Визгунов (VHS)" instead of the whole path in the audio menu.
--
-- Loose subtitles whose name doesn't match the video are only taken when the
-- folder holds a single video — that's a film with its subtitle file. In a
-- season folder it would otherwise attach every episode's subtitles at once.
local utils = require 'mp.utils'

local AUDIO = {ac3 = true, eac3 = true, dts = true, thd = true, mka = true, mp3 = true, m4a = true,
	aac = true, flac = true, opus = true, ogg = true, wav = true, wv = true, mp2 = true}
local SUBS = {srt = true, ass = true, ssa = true, sub = true, idx = true, vtt = true, sup = true, smi = true}
local VIDEO = {mkv = true, mp4 = true, avi = true, mov = true, m4v = true, webm = true, wmv = true,
	ts = true, m2ts = true, mpg = true, mpeg = true, flv = true, ogv = true, rmvb = true}

local function ext_of(name)
	local e = name:match('%.([%a%d]+)$')
	return e and e:lower() or nil
end

local function stem_of(name) return (name:gsub('%.[^%.]+$', '')) end

-- "<video name> - 1. Сергей Визгунов (VHS).ac3" -> "1. Сергей Визгунов (VHS)"
local function track_title(file_name, video_stem)
	local title = stem_of(file_name)
	if title:sub(1, #video_stem) == video_stem then
		title = title:sub(#video_stem + 1)
	end
	title = title:gsub('^[%s%-_%.]+', ''):gsub('[%s%-_%.]+$', '')
	return #title > 0 and title or stem_of(file_name)
end

mp.register_event('file-loaded', function()
	local path = mp.get_property('path')
	if not path or path:find('^%a[%w+.%-]*://') then return end
	local dir, file = utils.split_path(mp.command_native({'expand-path', path}))
	if not dir or dir == '' then return end
	local files = utils.readdir(dir, 'files')
	if not files then return end

	local video_stem = stem_of(file)
	local videos = 0
	for _, name in ipairs(files) do
		local e = ext_of(name)
		if e and VIDEO[e] then videos = videos + 1 end
	end

	for _, name in ipairs(files) do
		if name ~= file then
			local e = ext_of(name)
			local full = utils.join_path(dir, name)
			local matches_video = name:sub(1, #video_stem) == video_stem
			if e and AUDIO[e] and matches_video then
				-- 'auto' keeps the current track selected; this only adds a choice.
				mp.commandv('audio-add', full, 'auto', track_title(name, video_stem))
			elseif e and SUBS[e] and (matches_video or videos == 1) then
				mp.commandv('sub-add', full, 'auto', track_title(name, video_stem))
			end
		end
	end
end)

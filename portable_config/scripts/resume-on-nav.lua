-- DinaPlayer: owns the resume position ("watch later") for every file.
--
-- Why this exists instead of mpv's save-position-on-quit (which is off in
-- mpv.conf):
--   * mpv only auto-saves on quit, NOT when you switch files inside the
--     playlist — so going to another episode and back restarted it.
--   * `keep-open=yes` pauses on the last frame instead of unloading the file,
--     so quitting there made mpv save a resume point AT the end, and reopening
--     that episode showed its last frame instead of starting over.
--   * mpv NEVER saves mid-playback — so if the machine loses power, crashes,
--     or is force-killed, the unload hook never runs and the whole episode is
--     lost (it reopens from the start, or from a stale old position). That is
--     the most painful failure, so on top of the unload hook we also save
--     periodically and on pause/seek (see below).

-- Decide-and-save used at UNLOAD (playlist navigation or quit). This is the one
-- place allowed to DELETE the resume point: a file watched to the end gets none
-- (so it doesn't reopen on its last frame), and one closed right after opening
-- (pos <= 1) is treated as "not really started".
local function save_on_unload()
    local pos = mp.get_property_number('time-pos')
    local dur = mp.get_property_number('duration')
    local finished = dur and dur > 0 and pos and pos >= dur - 1
    if finished or not pos or pos <= 1 then
        mp.command('delete-watch-later-config')
    else
        mp.command('write-watch-later-config')
    end
end

mp.add_hook('on_unload', 50, save_on_unload)

-- Mid-playback save used by the timer and by pause/seek. Unlike the unload path
-- this NEVER deletes on an early position: at load time pause-on-start.lua pauses
-- (and skip-opening.lua seeks) while the position is still ~0, and deleting there
-- would wipe a perfectly good resume point before playback even starts. So we
-- only ever WRITE a real position here; the only delete is stale-end cleanup, so
-- a crash on the last frame doesn't leave the episode reopening at its end.
local function save_now()
    if mp.get_property_bool('idle-active') then return end
    local pos = mp.get_property_number('time-pos')
    if not pos then return end
    local dur = mp.get_property_number('duration')
    if dur and dur > 0 and pos >= dur - 1 then
        mp.command('delete-watch-later-config')
    elseif pos > 1 then
        mp.command('write-watch-later-config')
    end
    -- pos <= 1: leave any existing resume point untouched.
end

-- Heartbeat: while a file is actually playing, persist the position every 30s so
-- an abrupt power-off/crash costs at most the last half-minute, not the episode.
-- Paused playback isn't advancing, so there's nothing new to write — pausing
-- itself already saved (below), and we skip the timer's write while paused to
-- avoid pointlessly rewriting the same value for hours.
mp.add_periodic_timer(30, function()
    if mp.get_property_bool('pause') then return end
    save_now()
end)

-- Save the moment playback is paused: catches "paused it and walked away, then
-- closed the laptop / lost power" — the position is captured right at the pause,
-- not up to 30s stale.
mp.observe_property('pause', 'bool', function(_, paused)
    if paused then save_now() end
end)

-- Save right after a manual seek, so jumping somewhere and immediately closing
-- (or crashing) keeps the new spot.
mp.register_event('seek', save_now)

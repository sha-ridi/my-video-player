-- DinaPlayer: owns the resume position ("watch later") for every file.
--
-- Why this exists instead of mpv's save-position-on-quit (which is off in
-- mpv.conf):
--   * mpv only auto-saves on quit, NOT when you switch files inside the
--     playlist — so going to another episode and back restarted it.
--   * `keep-open=yes` pauses on the last frame instead of unloading the file,
--     so quitting there made mpv save a resume point AT the end, and reopening
--     that episode showed its last frame instead of starting over.
--
-- The on_unload hook runs both on playlist navigation and on quit, so handling
-- it in one place covers everything and leaves no race with skip-opening.lua
-- (nothing seeks at load time).
mp.add_hook('on_unload', 50, function()
    local pos = mp.get_property_number('time-pos')
    local dur = mp.get_property_number('duration')
    local finished = dur and dur > 0 and pos and pos >= dur - 1
    if finished or not pos or pos <= 1 then
        -- Watched to the end (or barely started): no resume point, so the file
        -- starts from the beginning next time.
        mp.command('delete-watch-later-config')
    else
        mp.command('write-watch-later-config')
    end
end)

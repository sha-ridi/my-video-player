-- DinaPlayer: expose the real mpv executable path to other scripts.
--
-- thumbfast spawns a second mpv process to render seekbar thumbnails and finds
-- the binary via `user-data/frontend/process-path`. Plain/portable mpv never
-- sets that property, so thumbfast falls back to "mpv" — which isn't on PATH
-- here (our binary is DinaPlayer.exe, or mpv.exe in the dev sandbox), producing
-- "thumbfast: ERROR! cannot create mpv subprocess".
--
-- The executable lives one level above the config dir (portable_config), both
-- in the release layout (<dir>/DinaPlayer.exe + <dir>/portable_config) and in
-- the dev sandbox (build/vendor/mpv/mpv.exe + .../portable_config junction).
-- This file sorts before thumbfast.lua, so the property is set before thumbfast
-- reads it at load time.
local utils = require 'mp.utils'

local cfg = mp.command_native({'expand-path', '~~/'})
if type(cfg) == 'string' and #cfg > 0 then
    cfg = cfg:gsub('/+$', '')
    local parent = utils.split_path(cfg)
    for _, name in ipairs({'DinaPlayer.exe', 'mpv.exe', 'mpv'}) do
        local full = utils.join_path(parent, name)
        local info = utils.file_info(full)
        if info and info.is_file then
            mp.set_property_native('user-data/frontend/process-path', full)
            break
        end
    end
end

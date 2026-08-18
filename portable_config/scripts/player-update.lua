-- DinaPlayer: "Update DinaPlayer" — closes the player and launches the
-- updater (DinaPlayer-Setup.exe), which downloads the latest release and
-- reinstalls over the current folder (keeping watch progress and settings).
--
-- Why a separate process: the player can't overwrite its own running files, so
-- the updater must run after mpv exits. We launch it DETACHED, then quit.
--
-- Setup.exe normally sits next to DinaPlayer.exe (the installer and the release
-- ZIP both place it there). If it's somehow missing (e.g. an old install that
-- predates that), we download it first via PowerShell, then launch it — so the
-- button always works.
local utils = require 'mp.utils'

local SETUP_URL = 'https://github.com/sha-ridi/my-video-player/releases/latest/download/DinaPlayer-Setup.exe'

local function install_root()
    local cfg = mp.command_native({'expand-path', '~~/'})
    if type(cfg) ~= 'string' or #cfg == 0 then return nil end
    cfg = cfg:gsub('[/\\]+$', '')
    return (utils.split_path(cfg)) -- parent of the config dir = install dir
end

mp.register_script_message('player-update', function()
    local root = install_root()
    if not root then
        mp.osd_message('Could not locate the player folder', 4)
        return
    end
    local setup = utils.join_path(root, 'DinaPlayer-Setup.exe')
    local info = utils.file_info(setup)

    if info and info.is_file then
        -- Launch the updater independently, then quit so it can replace our files.
        -- /autoupdate: it starts the update itself (no manual click) and reopens the
        -- player when done — so the button is "close, update, reopen" in one press.
        mp.command_native({name = 'subprocess', args = {setup, '/autoupdate'}, playback_only = false, detach = true})
        mp.commandv('quit')
    else
        -- Missing: download it, then launch it — all in one detached PowerShell,
        -- so it runs after the player closes.
        mp.osd_message('Downloading the updater…', 30)
        local ps = "$ErrorActionPreference='Stop';"
            .. "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;"
            .. "Invoke-WebRequest '" .. SETUP_URL .. "' -OutFile '" .. setup .. "';"
            .. "Start-Process '" .. setup .. "' -ArgumentList '/autoupdate'"
        mp.command_native({
            name = 'subprocess',
            args = {'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps},
            playback_only = false,
            detach = true,
        })
        mp.commandv('quit')
    end
end)

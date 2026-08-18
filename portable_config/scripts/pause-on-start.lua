-- DinaPlayer: "Pause on start" — when enabled, the first video opened after the
-- player launches starts PAUSED (you press play when ready). On by default.
--
-- The setting persists across sessions in a small state file next to the config.
-- Only the FIRST file of a session is paused — auto-advancing to the next episode
-- keeps playing as normal.
--
-- The Settings popup (scripts/settings-menu.lua) renders this as a one-click
-- toggle: it reads the current value from the `user-data` property published
-- below, and flips it with the `pause-on-start-toggle` message.
local state_path = mp.command_native({'expand-path', '~~/pause-on-start.state'})
local enabled = true  -- on by default (state file overrides if the user changed it)
local first_file = true

local function publish()
    mp.set_property_native('user-data/dinaplayer/pause-on-start', enabled)
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

mp.register_event('file-loaded', function()
    if first_file then
        first_file = false
        if enabled then mp.set_property_bool('pause', true) end
    end
end)

mp.register_script_message('pause-on-start-toggle', function()
    enabled = not enabled
    write_state()
    publish()
end)

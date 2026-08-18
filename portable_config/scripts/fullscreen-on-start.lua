-- DinaPlayer: "Fullscreen on start" — open the player in fullscreen. On by
-- default. The choice persists across sessions in a small state file next to
-- the config.
--
-- The Settings popup (scripts/settings-menu.lua) renders this as a one-click
-- toggle: it reads the current value from the `user-data` property published
-- below, and flips it with the `fullscreen-on-start-toggle` message.
local state_path = mp.command_native({'expand-path', '~~/fullscreen-on-start.state'})
local enabled = true  -- on by default (state file overrides if the user changed it)

local function publish()
    mp.set_property_native('user-data/dinaplayer/fullscreen-on-start', enabled)
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

-- Apply at load so the window opens fullscreen without a windowed flash.
if enabled then mp.set_property_bool('fullscreen', true) end

mp.register_script_message('fullscreen-on-start-toggle', function()
    enabled = not enabled
    write_state()
    publish()
end)

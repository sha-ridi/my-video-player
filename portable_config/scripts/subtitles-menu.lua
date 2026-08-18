-- DinaPlayer: custom subtitles popup (opened by the CC button).
--
-- Two columns, Netflix-style: the same list of tracks rendered twice, under
-- "Primary" and "Secondary" headers. A cell is filled when that slot holds that
-- track, so both slots are readable at a glance and settable in one click —
-- where the earlier segmented control hid half the state behind a tab.
-- Each column has its own "Off", which clears only that slot.
--
-- Picking a track that the other slot already holds MOVES it (frees the other
-- slot), so the same track is never primary and secondary at once.
--
-- The two-column rendering itself is a DinaPlayer patch in uosc's
-- elements/Menu.lua, driven by `columns` on the menu and `slots` on each item.
--
-- Replaces uosc's built-in subtitles menu (and its per-item "secondary" arrow):
-- the CC button runs `script-message dina-subtitles-open`.
local utils = require 'mp.utils'

local MENU_TYPE = 'sub' -- keep 'sub' so the CC button chip still highlights
local SELF = mp.get_script_name()
local CALLBACK = {SELF, 'subs-event'}

local function sub_tracks()
    local out = {}
    for _, t in ipairs(mp.get_property_native('track-list', {})) do
        if t.type == 'sub' then out[#out + 1] = t end
    end
    return out
end

local function build()
    local sid = mp.get_property_number('sid')
    local ssid = mp.get_property_number('secondary-sid')

    local items = {
        {title = 'Off', slots = {sid == nil, ssid == nil}, value = {'set', 'no'}},
    }
    for _, t in ipairs(sub_tracks()) do
        local title = t.title or (t.lang and t.lang:upper()) or ('Subtitle ' .. tostring(t.id))
        items[#items + 1] = {
            title = title,
            hint = t.title and t.lang and t.lang:upper() or nil,
            slots = {sid == t.id, ssid == t.id},
            value = {'set', t.id},
        }
    end

    return {
        type = MENU_TYPE,
        callback = CALLBACK,
        columns = {'Primary', 'Secondary'},
        max_visible = 8,
        items = items,
    }
end

local is_open = false
mp.observe_property('user-data/uosc/menu/type', 'native', function(_, v) is_open = v == MENU_TYPE end)

local function refresh()
    if is_open then
        mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(build()))
    end
end

-- Assign `target` (a track id or 'no') to the slot of `column` (1 = primary,
-- 2 = secondary), freeing it from the other slot first.
local function assign(column, target)
    local sid = mp.get_property_number('sid')
    local ssid = mp.get_property_number('secondary-sid')
    if column == 2 then
        if target ~= 'no' and sid == target then mp.set_property('sid', 'no') end
        mp.set_property('secondary-sid', tostring(target))
    else
        if target ~= 'no' and ssid == target then mp.set_property('secondary-sid', 'no') end
        mp.set_property('sid', tostring(target))
    end
    -- Tell track-memory.lua this was a deliberate pick, so it's remembered even
    -- when it happens right after opening a file (it ignores automatic changes).
    mp.commandv('script-message', 'dina-track-chosen', column == 2 and 'ssid' or 'sid', tostring(target))
end

mp.register_script_message('subs-event', function(json)
    local e = utils.parse_json(json)
    if type(e) ~= 'table' then return end
    if e.type == 'activate' and type(e.value) == 'table' then
        assign(tonumber(e.column) == 2 and 2 or 1, e.value[2])
    end
end)

mp.register_script_message('dina-subtitles-open', function()
    if is_open then
        mp.commandv('script-message-to', 'uosc', 'close-menu', MENU_TYPE)
    else
        mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(build()))
    end
end)

mp.observe_property('sid', 'native', refresh)
mp.observe_property('secondary-sid', 'native', refresh)
mp.observe_property('track-list', 'native', refresh)

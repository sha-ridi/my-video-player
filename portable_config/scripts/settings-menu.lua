-- DinaPlayer: the gear (Settings) popup, built here in Lua.
--
-- YouTube-style navigation: submenus (Playback speed / Chapters / Keyboard
-- shortcuts) REPLACE the current view in place with a "‹ Back" header, instead
-- of uosc's default translucent, sliding nested panels. We get this by keeping
-- every view as the SAME external menu (type 'settings') and swapping its
-- contents via `update-menu` — no nested panels, so no parent-behind and no
-- slide. All events are routed to us through the menu `callback`, so we fully
-- control navigation and can go back via the header, Backspace or mouse-back.
--
-- Rows also show their current value on the right and toggle in place; the
-- observers at the bottom re-render the open view when anything changes.
local utils = require 'mp.utils'

local MENU_TYPE = 'settings'
local SELF = mp.get_script_name()
local CALLBACK = {SELF, 'menu-event'}

local SPEEDS = {0.5, 0.75, 1, 1.25, 1.5, 1.75, 2}
local SPEED_STEP = 0.25

local function round2(n) return tonumber(string.format('%.2f', n)) end

local function speed_title(s)
    return s == 1 and 'Normal' or (string.format('%g', s) .. '×')
end

local function current_speed() return round2(mp.get_property_number('speed') or 1) end

-- State of the on-start toggles, published by pause-on-start.lua and
-- fullscreen-on-start.lua so this menu doesn't need to know how they persist it.
local function toggle_enabled(name)
    return mp.get_property_native('user-data/dinaplayer/' .. name) == true
end


-- ---- item builders (values are {kind, ...}; the callback interprets them) ----

local function speed_items()
    local speed, items = current_speed(), {}
    for _, s in ipairs(SPEEDS) do
        items[#items + 1] = {
            title = speed_title(s),
            active = math.abs(speed - s) < 0.001,
            value = {'cmd', 'set', 'speed', tostring(s)},
        }
    end
    return items
end

local function format_time(t)
    t = math.floor(t or 0)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = t % 60
    if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
    return string.format('%d:%02d', m, s)
end

local function chapter_items()
    local chapters = mp.get_property_native('chapter-list', {})
    local current = mp.get_property_number('chapter') -- 0-based, or nil
    local items = {}
    for i, ch in ipairs(chapters) do
        items[#items + 1] = {
            title = (ch.title and #ch.title > 0) and ch.title or ('Chapter ' .. i),
            hint = format_time(ch.time),
            active = current ~= nil and (i - 1) == current,
            value = {'cmd', 'set', 'chapter', tostring(i - 1)},
        }
    end
    if #items == 0 then
        items[1] = {title = 'No chapters', selectable = false, italic = true, muted = true}
    end
    return items
end

-- A readable, NON-clickable hotkey cheat sheet grouped by section. `{h=...}` rows
-- are section headers; the rest are `action, key`. All rows are selectable=false.
local SHORTCUTS = {
    {h = 'Playback'},
    {'Play / pause', 'Space  ·  K  ·  Click'},
    {h = 'Seeking'},
    {'Seek  −5s / +5s', '←  ·  →'},
    {'Seek  −10s / +10s', 'J  ·  L  ·  Wheel ← / →'},
    {'Seek  −30s / +30s', 'Shift+←  ·  Shift+→'},
    {'Chapter  prev / next', '[  ·  ]'},
    {'Subtitle  prev / next', ',  ·  .'},
    {h = 'Screen'},
    {'Fullscreen', 'F  ·  Double-click'},
    {'Exit fullscreen', 'Esc'},
    -- Only the mouse actions that have no keyboard equivalent above: click,
    -- double-click and wheel-seek are already listed with their keys.
    {h = 'Mouse'},
    {'Zoom to cursor', 'Ctrl + Wheel'},
    {'Previous / next video', 'Back / Forward buttons'},
}

local function shortcut_items()
    local items = {}
    for _, s in ipairs(SHORTCUTS) do
        if s.h then
            items[#items + 1] = {title = s.h, selectable = false, bold = true, muted = true}
        else
            items[#items + 1] = {title = s[1], hint = s[2], selectable = false}
        end
    end
    return items
end

-- `chevron = true` marks rows that open a submenu; uosc's elements/Menu.lua draws
-- an enlarged "›" on the right (YouTube-style). Toggles and the update action
-- don't get one.
local function main_items()
    return {
        -- DinaPlayer: no group-break separator lines in Settings — groups read from
        -- order alone (the header underline in submenus stays).
        {title = 'Playback speed', hint = speed_title(current_speed()), chevron = true, value = {'nav', 'speed'}},
        {title = 'Chapters', chevron = true, value = {'nav', 'chapters'}},
        -- `toggle` (a DinaPlayer field read by uosc's elements/Menu.lua) draws an
        -- iOS-style switch on the right of the row in place of the hint text.
        {title = 'Pause on start', toggle = toggle_enabled('pause-on-start'), value = {'msg', 'pause-on-start-toggle'}},
        {title = 'Fullscreen on start', toggle = toggle_enabled('fullscreen-on-start'), value = {'msg', 'fullscreen-on-start-toggle'}},
        {title = 'Skip Opening', toggle = toggle_enabled('skip-opening'), value = {'msg', 'skip-opening-toggle'}},
        {title = 'Skip Ending', toggle = toggle_enabled('skip-ending'), value = {'msg', 'skip-ending-toggle'}},
        {title = 'Keyboard shortcuts', chevron = true, value = {'nav', 'shortcuts'}},
        {title = 'Update DinaPlayer', value = {'msg', 'player-update'}},
    }
end

-- Submenus use uosc's fixed title as a clickable "‹ Back" header (title_back),
-- so it stays put while the list scrolls, and cap the list at 8 visible rows.
local function submenu(title, items)
    return {type = MENU_TYPE, callback = CALLBACK, title = title, title_back = true, max_visible = 8, items = items}
end

local function data_for(view)
    if view == 'speed' then return submenu('Playback speed', speed_items())
    elseif view == 'chapters' then return submenu('Chapters', chapter_items())
    elseif view == 'shortcuts' then return submenu('Keyboard shortcuts', shortcut_items())
    end
    return {type = MENU_TYPE, callback = CALLBACK, max_visible = 8, items = main_items()}
end

-- Tracks whether *our* menu is on screen (so refreshes stay no-ops otherwise)
-- and which view is showing (so refresh re-renders the right one).
local is_open = false
local current_view = 'main'

-- Observed as `native`, not `string`: mpv serializes user-data to JSON for the
-- string format, which would hand us `"settings"` (quotes) and never match.
mp.observe_property('user-data/uosc/menu/type', 'native', function(_, value)
    is_open = value == MENU_TYPE
    if not is_open then current_view = 'main' end
end)

local function show(view, force_open)
    current_view = view
    local action = (force_open or not is_open) and 'open-menu' or 'update-menu'
    mp.commandv('script-message-to', 'uosc', action, utils.format_json(data_for(view)))
end

local function refresh()
    if is_open then
        mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(data_for(current_view)))
    end
end

mp.register_script_message('settings-menu-open', function()
    if is_open then
        mp.commandv('script-message-to', 'uosc', 'close-menu', MENU_TYPE)
    else
        show('main', true)
    end
end)

mp.register_script_message('menu-event', function(json)
    local e = utils.parse_json(json)
    if type(e) ~= 'table' then return end

    -- Back: header/Backspace/mouse-back from a submenu -> main; from main -> close.
    if e.type == 'back' or (e.type == 'key' and e.id == 'left') then
        if current_view == 'main' then
            mp.commandv('script-message-to', 'uosc', 'close-menu', MENU_TYPE)
        else
            show('main')
        end
        return
    end

    if e.type ~= 'activate' or type(e.value) ~= 'table' then return end
    local v = e.value
    if v[1] == 'nav' then
        show(v[2])
    elseif v[1] == 'cmd' then
        local a = {} ; for i = 2, #v do a[#a + 1] = v[i] end
        mp.commandv(unpack(a))
    elseif v[1] == 'msg' then
        local a = {'script-message'} ; for i = 2, #v do a[#a + 1] = v[i] end
        mp.commandv(unpack(a))
    end
end)

-- Keep the open view in sync with changes from any source (menu clicks, the
-- [/]/Backspace hotkeys, the on-start scripts).
mp.observe_property('speed', 'number', refresh)
mp.observe_property('chapter', 'number', refresh)
mp.observe_property('chapter-list', 'native', refresh)
mp.observe_property('user-data/dinaplayer/pause-on-start', 'native', refresh)
mp.observe_property('user-data/dinaplayer/fullscreen-on-start', 'native', refresh)
mp.observe_property('user-data/dinaplayer/skip-opening', 'native', refresh)
mp.observe_property('user-data/dinaplayer/skip-ending', 'native', refresh)

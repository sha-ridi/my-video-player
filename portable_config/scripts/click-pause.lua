-- click-pause.lua — YouTube-style: single left-click toggles pause,
-- double-click is reserved for fullscreen (input.conf MBTN_LEFT_DBL).
--
-- Why this exists: uosc >=5.x removed its old click_threshold/click_command
-- debounce, so a naive `MBTN_LEFT cycle pause` binding in input.conf toggles
-- pause on *every* click, including both clicks of a double-click used for
-- `MBTN_LEFT_DBL cycle fullscreen` — causing a pause flicker. mpv upstream
-- rejected shipping this debounce as a builtin binding (PR #15405), so it's
-- implemented here as a small script instead.
--
-- MBTN_LEFT and MBTN_LEFT_DBL are distinct mpv key names — mpv fires the
-- plain MBTN_LEFT down/up pair for *each* click (including both clicks of a
-- double-click) and *additionally* fires MBTN_LEFT_DBL once double-click
-- detection completes. Binding MBTN_LEFT here does not shadow or consume
-- MBTN_LEFT_DBL, so input.conf's `MBTN_LEFT_DBL cycle fullscreen` still
-- fires independently and unconditionally.
local threshold = 0.30  -- s; window to wait for a potential second click
local pending = nil
-- Was the button released during the current click? A click that stays held the
-- whole `threshold` window is a hold/drag (e.g. moving the window), not a click —
-- so we don't toggle pause for it.
local released = false

-- While a uosc menu/popup is open, a click either interacts with it or closes
-- it — it must never also toggle pause. uosc publishes the open menu type at
-- this property (nil when no menu is open).
-- NOTE: when a menu closes, uosc sets this property to nil, but reading it back
-- as a 'string' yields the literal "null" (not Lua nil) — so we must treat
-- "null" as closed too, otherwise menu_open sticks at true after the first menu
-- is opened and closed, permanently disabling click-to-pause.
local menu_open = false
mp.observe_property('user-data/uosc/menu/type', 'string', function(_, value)
    menu_open = value ~= nil and value ~= '' and value ~= 'null'
end)

local function toggle()
    pending = nil
    if menu_open then return end  -- a menu opened during the debounce window
    if not released then return end  -- still held the whole window -> hold/drag, not a click
    mp.command("cycle pause")
end

mp.add_forced_key_binding("MBTN_LEFT", "click_pause", function(e)
    -- Track the release regardless of anything else, so `toggle` can tell a real
    -- click (pressed and let go) from a button held down the whole window.
    if e.event == "up" then released = true return end
    if e.event ~= "down" then return end
    if menu_open then return end
    if pending then          -- second click within window -> double-click
        pending:kill()       -- cancel pause; MBTN_LEFT_DBL handles fullscreen
        pending = nil
    else
        released = false     -- new click; assume held until we see the matching up
        pending = mp.add_timeout(threshold, toggle)
    end
end, {complex = true})

-- Known residual limitation: this binding only fires for clicks mpv routes
-- to plain MBTN_LEFT. uosc claims mouse input over its own UI zones (e.g.
-- hovering the control bar/timeline) and normally lets clicks on bare video
-- fall through to this binding, but a click that lands exactly on a uosc
-- element is not guaranteed to reach here — that residual case is left to
-- the user's manual acceptance pass rather than solved by this script.

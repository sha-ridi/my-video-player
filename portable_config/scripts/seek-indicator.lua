-- DinaPlayer — YouTube-style stacking seek indicator.
-- Bound from input.conf via `script-message dina-seek <n>`: performs the seek
-- AND shows a translucent pill on the right (forward, "+N sec »") or left
-- (back, "« −N sec"). Pressing again before it fades (~0.8s) stacks the amount
-- (+5, +10, +15…). Switching direction resets the counter. Works for RIGHT/LEFT,
-- j/l, Shift+arrows and the Russian-layout duplicates — any key routed here.

local mp = require 'mp'

local HIDE_AFTER = 0.8   -- seconds of no press before the pill disappears
local overlay = mp.create_osd_overlay('ass-events')
local total = 0          -- accumulated (signed) seconds currently displayed
local timer = nil

-- Stadium-shaped (fully rounded ends) rectangle as an ASS drawing, origin 0,0.
local function rrect(W, H, r)
    return string.format(
        'm %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d '
        .. 'l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d',
        r, 0,
        W - r, 0,
        W, 0, W, 0, W, r,
        W, H - r,
        W, H, W, H, W - r, H,
        r, H,
        0, H, 0, H, 0, H - r,
        0, r,
        0, 0, 0, 0, r, 0)
end

local function hide()
    if timer then timer:kill(); timer = nil end
    total = 0
    overlay:remove()
end

local function render()
    local osd = mp.get_property_native('osd-dimensions')
    if not osd or not osd.w or osd.w == 0 then return end
    local W, H = osd.w, osd.h

    local forward = total >= 0
    local secs = math.abs(total)
    local label = forward
        and ('+' .. secs .. ' sec »')
        or ('« −' .. secs .. ' sec')

    local fs = math.max(20, math.min(math.floor(H * 0.033), 40))
    local digits = #tostring(secs)
    local pw = math.floor(fs * (5.2 + digits * 0.62))
    local ph = math.floor(fs * 1.9)

    local margin = math.floor(W * 0.04)   -- small gap from the screen edge
    local cy = math.floor(H * 0.5)
    local cx = forward
        and (W - margin - math.floor(pw / 2))
        or (margin + math.floor(pw / 2))
    local x0 = math.floor(cx - pw / 2)
    local y0 = math.floor(cy - ph / 2)

    local pill = string.format(
        '{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c&H000000&\\1a&H55&\\p1}%s{\\p0}',
        x0, y0, rrect(pw, ph, math.floor(ph / 2)))
    local text = string.format(
        '{\\an5\\pos(%d,%d)\\bord0\\shad1\\4a&H80&\\1c&HFFFFFF&\\fs%d\\fnInter\\b1}%s',
        cx, cy, fs, label)

    overlay.res_x = W
    overlay.res_y = H
    overlay.data = pill .. '\n' .. text
    overlay:update()
end

local function seek(n)
    n = tonumber(n)
    if not n or n == 0 then return end

    mp.commandv('seek', tostring(n))   -- same relative seek as before

    -- Direction change starts a fresh count.
    if (total > 0 and n < 0) or (total < 0 and n > 0) then total = 0 end
    total = total + n

    render()
    if timer then timer:kill() end
    timer = mp.add_timeout(HIDE_AFTER, hide)
end

mp.register_script_message('dina-seek', seek)

-- Don't leave a stale pill hanging across file changes.
mp.register_event('start-file', hide)

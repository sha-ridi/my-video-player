# DinaPlayer — YouTube-style UI overhaul (icons, popups, autohide)

**Date:** 2026-07-16
**Status:** Approved by Dima (design), pending implementation plan
**Prereq:** builds on top of the earlier change that removed shuffle/loop buttons and
moved speed into the menu (uncommitted working-tree change as of writing).

## Goal

Make the uosc-based UI behave and read like YouTube's player:

1. Replace all uosc glyph icons with **Font Awesome Solid** (chosen over Material
   Symbols Rounded and Phosphor Fill).
2. Bottom-bar layout: episode navigation on the left; **subtitles · audio track ·
   gear (settings) · fullscreen** on the right. The audio-track selector becomes a
   first-class button next to subtitles. The generic "menu" button is replaced by a
   gear.
3. Menus open as **anchored popups** (YouTube-style) instead of a centered modal
   with a dimming curtain.
4. Bottom bar visibility becomes **binary and time-based**: any mouse movement shows
   it at full opacity; ~2.5–3 s of no movement hides it together with the cursor.
   The current proximity-gradient behavior is removed.
5. Buttons get a **hover container**: a rounded background highlight on hover, and a
   slightly different variant of the same container when the button is "active"
   (its popup is open, or its feature is enabled — e.g. subtitles on). No red
   underline indicators.

Approach for popups (decided): **reuse and restyle the existing uosc Menu engine**
(reposition + de-modalize), not a from-scratch popup element. Pixel-perfect YouTube
rows (right-aligned values, toggles) are explicitly a possible later iteration.

## 1. Icon replacement (Font Awesome Solid)

- uosc renders icons as ligatures from `portable_config/fonts/uosc_icons.otf`
  (Material Design names like `play_arrow`, `pause`, `settings`, ~60 glyphs used
  across the skin — grep uosc source for `icon(` / `icon =` usages to build the
  definitive list).
- Build a replacement OTF where each **uosc ligature name maps to the visually
  corresponding Font Awesome Solid glyph** (FA 7.x free set, already vetted:
  play, pause, forward-step/backward-step, closed-captioning, language, gear,
  expand, list, gauge-high, crop-simple, camera, headphones, keyboard, power-off,
  chevron-right, check, volume-high, …).
- Gaps in FA coverage are filled with the visually closest **Material Symbols
  Rounded (filled)** glyph so no uosc icon ever renders as tofu.
- Source SVGs live in `assets/icons/<name>.svg` (committed); a build script
  (Node + fantasticon, or fontforge — implementer's choice, must run on macOS)
  regenerates `portable_config/fonts/uosc_icons.otf`. The generated font is
  committed (same vendoring policy as uosc itself).
- Icon meaning decisions already made:
  - **Audio track button: FA `language`** (hieroglyph + A) — tracks are dub
    languages. (Dima was offered `headphones` and chose to keep `language`.)
  - **Settings button: FA `gear`.**
  - `headphones` is used for the "Audio device" menu row instead.
- License: FA Free icons are CC BY 4.0 — add attribution to a `NOTICE` /
  `THIRD-PARTY.md` file and mention it in README's build section.

## 2. Bottom bar layout

New `controls=` line (in the `# --- DinaPlayer overrides ---` block of
`portable_config/script-opts/uosc.conf`), left → right:

```
prev, next, items, space, subtitles, audio, gear-button, fullscreen
```

- `prev` / `next` = episode navigation, `items` = playlist (episode list).
- `subtitles` and `audio` sit adjacent; both always visible during video playback
  (keep the existing `<video,audio>`-style visibility guards where they make
  sense; do not hide `audio` behind `has_many_audio` — a single-track file should
  still show the button and open a one-item popup).
- Gear = a button that opens the settings popup (either the stock `menu` control
  whose glyph now renders as a gear via the font swap, or a custom
  `command:<icon>:script-binding uosc/menu-blurred` button — implementer picks
  whichever is cleaner, tooltip "Settings").
- Volume stays as uosc's vertical right-edge slider + mouse wheel (NOT a
  YouTube-style horizontal slider — out of scope).
- Time readouts stay on the timeline (uosc default), not in the controls row.

## 3. Popups instead of modal menus

All three popup sources use the same patched Menu engine:

| Button | Content |
| --- | --- |
| Subtitles (CC) | subtitle track list (existing `uosc/subtitles`) |
| Audio | audio track list (existing `uosc/audio`) |
| Gear | settings menu (see below) |

Menu engine changes (`portable_config/scripts/uosc/elements/Menu.lua` + related):

- **No curtain / dimming** when opened from a control-bar button.
- **Anchored placement**: popup opens above the bottom bar, horizontally aligned
  to the source button (right-aligned near the right edge like YouTube), instead
  of centered. Falls back to a sane position in tiny windows.
- Rounded corners, constrained max height (scrolls inside), width ~280–320 px at
  scale 1.
- **Click outside the popup closes it** — and must NOT toggle pause (coordinate
  with `scripts/click-pause.lua`; the close-click is swallowed). Esc also closes.
- Submenus keep the existing uosc behavior (drill-in with a back arrow) — this
  matches YouTube's Sleep-timer-style nested popup.
- Keyboard navigation and type-to-search keep working.

Gear popup content (labels in **English** — Dima's decision; defined via `#!`
items in `portable_config/input.conf`, evolving the menu introduced earlier
today):

- Playback speed → submenu: 0.5x / 0.75x / Normal (1x) / 1.25x / 1.5x / 1.75x /
  2x / Faster +0.25 (`]`) / Slower −0.25 (`[`) / Reset to 1x (`Backspace`)
- Aspect ratio → Default / 16:9 / 4:3 / 2.35:1
- Chapters (chapter list)
- Screenshot
- Audio device
- Key bindings (list)
- Quit

(Subtitles / audio / playlist rows are NOT duplicated in the gear popup — they
have dedicated buttons. Dima wants the fuller utils list kept for now; pruning is
a later decision.)

## 4. Show/hide behavior (autohide)

- Remove the proximity gradient: while the UI is shown, all bar elements render at
  full opacity regardless of cursor distance. (Either via
  `proximity_in`/`proximity_out` config values large enough to cover the window,
  or a small patch to `Element:get_visibility()` — config-first, patch only if
  config proves insufficient.)
- `autohide=yes` in uosc.conf; `cursor-autohide=2500` (ms) in mpv.conf — mouse
  movement shows bar + cursor, 2.5 s idle hides both together.
- While **paused**, the bar stays visible (`timeline_persistency=paused`,
  `controls_persistency=paused`; volume/top_bar left as-is).
- While a popup is open, the bar stays visible.
- Existing fade animation is kept for the show/hide transition.

## 5. Button hover/active container

In `Button.lua` / `CycleButton.lua` rendering:

- **Hover**: rounded-rect background container behind the icon (subtle, ~10%
  white), YouTube-chip-like.
- **Active** (popup currently open from this button, or stateful feature enabled —
  subtitles visible): the same container, slightly stronger/different (e.g. ~20%
  white), so hover and active read as two intensities of one affordance.
- No underline indicators anywhere.

## Non-goals (this iteration)

- Horizontal volume slider in the bar.
- Pixel-perfect YouTube popup rows (right-aligned current values, toggle
  switches) — possible follow-up on top of approach A.
- Quality selector, sleep timer, "stable volume" — features DinaPlayer doesn't
  have.
- Top bar redesign, pause/seek animations.

## Acceptance (macOS preview: `mpv --config-dir="$PWD/portable_config" <video>`)

1. All bar icons render as FA Solid glyphs; no tofu anywhere (buttons, menus,
   pause indicator, volume slider).
2. Bar layout matches §2; audio button opens track popup next to CC popup.
3. Popups: anchored above their button, no screen dimming, click-outside closes
   without pausing, submenu back-navigation works, wheel scrolls long lists.
4. Bar shows on any mouse move at full opacity, hides after ~2.5 s idle together
   with cursor; never hides while paused or while a popup is open.
5. Hover shows the container highlight; open-popup/subtitles-on shows the active
   variant.
6. `--msg-level=all=warn` run prints no uosc/config warnings.
7. Existing behaviors unaffected: click-pause, double-click fullscreen, wheel
   volume, position/track memory, episode autoload.

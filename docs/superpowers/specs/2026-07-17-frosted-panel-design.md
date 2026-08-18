# DinaPlayer — frosted floating panels behind the bars

**Date:** 2026-07-17
**Status:** Approved by Dima (design), pending implementation plan
**Prereq:** builds on the YouTube-style UI overhaul (`2026-07-16-youtube-ui-design.md`),
specifically the chip hover/active containers (`dcc11f5`) and the popup/autohide
behavior (`ea38dce`, `3e6eb13`, `93b16be`).

## Goal

Give the top bar and the bottom bar a **floating, frosted, rounded panel** to sit on,
in the spirit of the TIDAL player: a translucent dark surface with soft edges, inset
from the window edges, with the controls and timeline living inside it.

Reference behavior wanted: the bar reads as a distinct surface hovering over the
video, not as controls painted directly onto the frame.

## The blur constraint (decided)

uosc draws through mpv's ASS/OSD layer, which composites **on top** of the video.
ASS has no backdrop-filter: `\blur` only feathers the edges of a shape being drawn,
it cannot blur the pixels behind it. A true frosted-glass panel is therefore
**impossible from uosc's Lua/ASS**.

Two routes were considered:

1. **Fake it in ASS** — translucent panel + soft halo + rim highlight. Cheap,
   animatable, no perf or GPU-compatibility risk.
2. **Real GLSL blur** — hook mpv's render output and blur a rounded band. Genuine
   frost, but mpv shaders take no runtime uniforms, so bar geometry (which changes
   with window size and `state.scale`) would have to be baked into regenerated
   shader source and reloaded from Lua on every resize; show/hide could not fade
   smoothly.

**Decision: route 1.** The panel is a convincing fake. Nothing behind it is actually
blurred. If it reads flat against real footage we revisit — but not in this change.

## Architecture

**Decided approach: `Panel` paints, existing elements own their layout.**

The rejected alternative was making `Panel` own the pill geometry and having
`Timeline`/`Controls` query it for their content rect. That inverts the existing
dependency (today `Controls.by` reads `timeline.ay`) and makes `on_display` update
order load-bearing, for no visible gain.

### New element: `elements/Panel.lua`

- `render_order = 3.5` — after `PauseIndicator` (3), before `TopBar` (4), `Timeline`
  (5), `Controls` (6). `Elements:add` sorts by `render_order` and paints in order, so
  3.5 puts the panel above the video and beneath everything it backs. Non-integer
  orders sort fine (plain Lua number comparison).
- **Claims no cursor area.** It never calls `set_coordinates`, so it takes no
  proximity and no hit-testing. `elements/Curtain.lua` is the precedent: a pure
  render element with no coordinates.
- **Owns zero layout.** At render time it reads the live boxes of the elements it
  backs (`Elements.timeline.ax/ay/bx/by`, `Elements.controls.*`, `Elements.top_bar.*`)
  and derives its rects from them, so it cannot drift out of sync with the content.
- Draws **two pills** — one for the bottom bar (union of `timeline` and `controls`),
  one for the top bar — with identical fill, radius, and inset so they read as one
  system.
- If a backed element is disabled or missing, its pill is not drawn. The bottom pill
  falls back to whichever of `timeline`/`controls` is enabled.

### Geometry

Two new quantities, both scaled by `state.scale`:

- **`panel_inset`** — gap from the window edge to the pill's **outer** edge.
- **`panel_padding`** — gap from the pill's edge to the **content** inside it.

Therefore:

- Timeline and controls inset from the window edge by `panel_inset + panel_padding`.
- Pill rect = union of the backed elements' boxes, expanded by `panel_padding`.
- The pill's outer edge lands exactly `panel_inset` from the window edge.

### Layout changes to existing elements

- **`Timeline:update_dimensions()`** currently hardcodes full-window span:
  `self.ax = window_border_size`, `self.bx = display.width - window_border_size`,
  `self.by = display.height - window_border_size`. All three gain the inset, so the
  timeline stops spanning the full width and lifts off the bottom edge.
- **`Controls:update_dimensions()`** already insets itself by `controls_margin` and
  derives `self.by` from `timeline.ay`. Because the timeline lifts, controls follow
  for free. The existing margin and the new padding must not double up — reconcile so
  the visible gap matches `panel_padding`.
- **`TopBar`** gets the same inset treatment for its own pill.
- The `available_space` / `obstructed` guards in both `Timeline` and `Controls` must
  account for the added inset, so the bars still disable themselves gracefully in a
  very short window.

### Paint recipe

Three stacked passes per pill, painted in order:

1. **Glass body** — rounded rect, `panel_color` at `panel_opacity` (~0.65 default),
   `radius = panel_radius`.
2. **Halo** — a soft bloom just outside the body, which is what distinguishes "glass"
   from "flat card". `lib/ass.lua` hardcodes `\blur0` into its rect tags
   (`ass.lua:200`), so this needs either the existing `opacity.shadow` path that
   `ass_mt:rect` already supports, or a small custom draw that emits `\blur N`.
   Expected to need live fiddling.
3. **Rim** — a 1px lighter line along the top edge at low opacity, the highlight glass
   picks up.

`ass_mt:rect` already supports `radius` (`ass.lua:216`) and is already used for the
rounded chips in `Button.lua`, so the body and rim need no new primitives.

### Visibility

`Panel` takes its opacity from `Elements.controls:get_visibility()` for the bottom
pill and `Elements.top_bar:get_visibility()` for the top one, rather than
reimplementing any visibility logic. It therefore inherits the binary autohide and
`timeline_persistency` / `controls_persistency` behavior tuned in `ea38dce` and
`3e6eb13` for free, and fades in and out with the bars.

The curtain guard added in `Elements:update_proximities()` and `Element:get_visibility()`
(`config.opacity.curtain = 0` means a curtain that draws nothing must not disable
elements underneath it) applies unchanged — `Panel` at order 3.5 sits below the
curtain's 999 and must not be suppressed while a popup is open.

## Configuration

New keys in the `# --- DinaPlayer overrides ---` block of
`portable_config/script-opts/uosc.conf`, read via `options` like every other uosc
option:

| Key | Default (unscaled) | Meaning |
| --- | --- | --- |
| `panel_inset` | 12 | gap from window edge to pill outer edge |
| `panel_padding` | 8 | gap from pill edge to content |
| `panel_radius` | 12 | corner radius of the pill |
| `panel_opacity` | 0.65 | opacity of the glass body |
| `panel_color` | matches `color.background` | fill color of the glass body |

`panel_opacity = 0` skips the panel paint entirely but does **not** change layout —
the bars stay inset. Restoring the current flush-to-edge look means
`panel_opacity = 0` **and** `panel_inset = 0`, `panel_padding = 0`. Defaults are
starting points to be tuned by eye during implementation, not fixed requirements.

## Testing and verification

There is **no automated test harness in this repo**, and this change is purely
visual. Verification is manual, by running:

```bash
mpv --config-dir="$PWD/portable_config" <video>
```

and checking, at minimum:

- **Dark footage** — the panel must still be distinguishable from the frame.
- **Bright footage** — the panel must not wash out; text must stay legible.
- **Windowed and fullscreen** — inset and radius scale correctly with `state.scale`.
- **Resize** — geometry follows without lag or drift, including very short windows
  where the bars disable themselves.
- **Popup open** — panels stay visible and correctly ordered under the menu
  (regression risk against `93b16be` and `3e6eb13`).
- **Paused** — panels persist with the bars per `*_persistency`.
- **Hover** — chip containers from `dcc11f5` still read against the new surface.

## Out of scope

- Real GLSL backdrop blur (see the constraint section above).
- Restyling the chips, popups, or timeline internals. This change adds a surface
  underneath them and insets them; it does not redesign them.
- Moving the timeline onto the same row as the buttons (TIDAL's exact arrangement).
  The timeline stays above the controls, both inside the pill.

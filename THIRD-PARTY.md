# Licensing & third-party notices

## DinaPlayer's own code

The DinaPlayer-authored parts — the Lua scripts in `portable_config/scripts/`
(everything except the vendored `uosc/`, `thumbfast.lua` and `autoload.lua`,
which are noted below) and the configuration files in `portable_config/` — are:

**Copyright © 2026 Dina. Licensed under the GNU General Public License, version 3
or (at your option) any later version (GPL-3.0-or-later).** Full text:
[`licenses/GPL-3.0.txt`](licenses/GPL-3.0.txt).

## The player as distributed

The released package (`DinaPlayer-Portable.zip`) bundles the **mpv** binary,
which is GPL-licensed. The distribution **as a whole is therefore covered by the
GNU GPL**. You may use, study, modify and redistribute it, including for free;
any distributed derivative must remain open under the GPL.

**Corresponding source.** The DinaPlayer scripts and configs ship as source
(plain `.lua` / `.conf` files under `portable_config/`) inside the package. The
source for mpv and the other components is at the upstream links below. The
license texts are bundled in the [`licenses/`](licenses/) folder.

## The installer is separate and closed-source

`DinaPlayer-Setup.exe` is an independent installer/updater — **Copyright © 2026
Dina, all rights reserved.** It is not built from any GPL code (it only downloads
and installs the player), is not part of the player's GPL source, and is **not**
distributed under the GPL. It is provided as a convenience only.

## Components

| Component | Files | License | Source |
| --- | --- | --- | --- |
| **mpv** (player engine) | `mpv.exe`, libs (branded `DinaPlayer.exe`) | **GPL-2.0-or-later** | source: <https://github.com/mpv-player/mpv> · Windows build: <https://github.com/zhongfly/mpv-winbuild> |
| **uosc** (skin) | `portable_config/scripts/uosc/` | **LGPL-2.1** | <https://github.com/tomasklaen/uosc> |
| uosc icon font | `portable_config/fonts/uosc_icons.otf` | icon glyphs from Google **Material Icons, Apache-2.0**, shipped within uosc | <https://github.com/tomasklaen/uosc> |
| uosc texture font | `portable_config/fonts/uosc_textures.ttf` | part of uosc, **LGPL-2.1** | <https://github.com/tomasklaen/uosc> |
| **thumbfast** (seek previews) | `portable_config/scripts/thumbfast.lua` | **MPL-2.0** | <https://github.com/po5/thumbfast> |
| **autoload** (playlist) | `portable_config/scripts/autoload.lua` | from the mpv project, **GPL** | <https://github.com/mpv-player/mpv> (`TOOLS/lua/autoload.lua`) |
| **Inter** (UI font) | `portable_config/fonts/Inter.ttf` | **SIL OFL 1.1** | <https://github.com/rsms/inter> |

Notes:

- **mpv** is used unmodified (the zhongfly Windows build; that repository's own
  MIT license covers its build scripts, while the resulting `mpv.exe` binary is
  GPL because it statically links a GPL-enabled FFmpeg).
- **uosc** and **thumbfast** carry small DinaPlayer patches, all marked
  `DinaPlayer:` in comments; the modified source travels in the package.
- **autoload** is based on mpv's script with a natural-sort patch (also marked
  `DinaPlayer:`).
- **Inter** and the **Material Icons** glyphs are used unmodified.

License texts for GPL-3.0, GPL-2.0, LGPL-2.1, MPL-2.0, OFL-1.1 and Apache-2.0
are in [`licenses/`](licenses/).

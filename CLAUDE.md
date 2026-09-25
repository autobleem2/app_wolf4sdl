# app_wolf4sdl - developer context

**Wolf4SDL** packaged as **two AutoBleem Apps**, one zip per App per platform (`dist/<app>-<key>-<version>.zip`), in
the multi-platform App format (the launcher's `docs/app-format-plan.md`). Wolf4SDL picks its game at compile
time, so each App is its own build of the same source:

| App | folder | Store id | program | defines | data |
|---|---|---|---|---|---|
| Wolfenstein 3D (Shareware) | `Apps/wolf4sdl/` | `app/wolf4sdl` | `wolf3d` | `CARMACIZED UPLOAD` | v1.4 shareware, `*.wl1` |
| Spear of Destiny (Demo) | `Apps/sodemo/` | `app/sodemo` | `spear` | `CARMACIZED SPEAR SPEARDEMO` | v1.0 demo, `*.sdm` |

Started 2026-09-25, the fourth third-party App port (autobleem-main `docs/decisions.md`, "Third-party App
ports" - the rules; `app_opentyrian`'s CLAUDE.md is the template). `app/wolf4sdl` keeps the RetroBoot App's
folder and id, so the Store updates it in place on psc. The SoD demo was the owner's addition.

## The owner's decisions for this port (2026-09-25)

- **Upstream**: `fabiangreffrath/wolf4sdl` (the maintained SDL2 port), pinned at `a51c229e` (2026-05-04 - tag
  `20251124` plus a HUD fix); the package version is that date, `20260504-1` (`VERSION`).
- **The 2020 layout, filled out**: Cross fire, Circle run, Square open, Triangle/Select next/previous weapon,
  L1/R1 strafe, L2 pause, R2/Start menu (`patches/wolf4sdl/0001-psc-button-layout.patch`, the `buttonjoy[]`
  defaults - the config file is binary, so defaults cannot ship as a file).
- **Both games**: the Wolfenstein shareware and the Spear of Destiny demo.
- **The picture** (the owner saw it wrong on the PC): `--res 960 600`, not the 2020 port's `--resf 1280 720`.
  Wolf4SDL draws at a whole scale factor (`min(w/320, h/200)`), so 1280x720 got a 3x picture in the corner of
  its buffer, and `--resf` also turns the 4:3 correction off; with a 320x200 multiple the buffer is full and
  `SDL_RenderSetLogicalSize` scales it to any display at 4:3 (960x720 - exactly the console's height).

## Layout

| path | what |
|---|---|
| `upstream/wolf4sdl` | the pinned upstream source (submodule) |
| `patches/wolf4sdl/0001-psc-button-layout.patch` | `buttonjoy[]`: on Linux in the numbering of the virtual pad's **PlayStation Classic layout** (Triangle 0, Circle 1, Cross 2, Square 3, L2 4, R2 5, L1 6, R1 7, Select 8, Start 9, the D-pad on axes 0/1); on Windows (`_WIN32`) in an XInput pad's raw numbering (A B X Y LB RB Back Start) - its triggers are axes, so pause is in the menu there |
| `resources/pad.ini` | `virtual = psc`: Wolf4SDL reads raw buttons and axes 0/1, and an X360 pad's triggers are axes; shown the console's own layout, every pad plays like the console's, L2/R2 included |
| `resources/<app>/` | `app.ini` (`Exec=bin/{key}/<program>`, `Args=--fullscreen --res 960 600 --configdir . --joystick 0`, `Args.win=` the same plus `--joystickhat 0` - the XInput D-pad is hat 0; no `Lib` - SDL2 and SDL2_mixer are the launcher's or the system's), `readme.txt`, `icon.png` |
| `ci/build.sh` | `native|psc|rpi|rpi64|pcusb|win|all`: the data from our mirror (sha256-pinned), then for each App a copy of the source, the patch, and upstream's Makefile with a generated `CONFIG` file carrying `-DVERSIONALREADYCHOSEN` and the version defines. psc links SDL2_mixer by name (its `.pc` names a `vorbisfile.pc` the image does not have). Windows links libgcc, libstdc++ **and winpthread** statically. |
| `tools/make_icons.py` | draws each icon from the game's own title screen, decoding VGAGRAPH as Wolf4SDL does (VGAHEAD offsets, VGADICT Huffman, the four-plane pictures); the chunk numbers (Wolfenstein 99 in `wolfpal.inc`'s palette; Spear 74+75 in its own palette, chunk 131) are the gfxv_*.h enums under each build's defines |
| `tools/store_item.py`, `tools/check_psc_binary.sh`, `tools/check_needed.sh` | as in app_crispydoom |

## Things to know

- **The data** is on our mirror, zipped by us (data files only, lower case, fixed timestamps):
  `mirror/wolf3d/wolf3d-shareware-1.4.zip` - the eight `.wl1` of the v1.4 shareware, byte for byte the same as
  archive.org's `wolf3dsw` copy (the original `1WOLF14.ZIP` holds them packed in a DOS installer, `DEICE`) - and
  `mirror/wolf3d/sod-demo-1.0.zip` - the eight `.sdm` of the v1.0 demo from archive.org's `spear-of-destiny-g192`
  (identical to `spear-box`'s; the player's `CONFIG.SDM` left out) plus `sod.doc`.
- **Settings and saves** are in the App folder (`--configdir .`): `config.wl1`/`config.sdm` and the save games.
  A Store update does not touch them (they are not in the package).
- **Windows**: `--joystickhat 0` makes Wolf4SDL quit if the pad has no hat; every XInput pad has one. Both
  programs ran on the dev PC on 2026-09-25 with only the Windows product's official SDL DLLs on PATH.
- **Build on the server**: sync with MSYS2's rsync (excluding `/build_*`, `/dist`), then
  `docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -w /src ghcr.io/autobleem2/autobleem-build:develop ci/build.sh all`.
- **Not yet run**: on a console, a Pi or the PC stick (the tester checklist).

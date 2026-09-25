# app_wolf4sdl

[Wolf4SDL](https://github.com/fabiangreffrath/wolf4sdl) packaged as two [AutoBleem](https://github.com/autobleem2/autobleem)
Apps for the PlayStation Classic, the Raspberry Pi, the AutoBleem PC stick and Windows:

- **Wolfenstein 3D (Shareware)** - "Escape from Wolfenstein", the v1.4 shareware episode;
- **Spear of Destiny (Demo)** - the v1.0 playable demo.

Install them from the AutoBleem Store. The upstream source is a pinned submodule; this repository holds only
the build (`ci/build.sh`, run in the [autobleem-build](https://github.com/autobleem2/autobleem-build) image),
one patch (the PlayStation Classic button layout) and each App's files.

```
git clone --recurse-submodules https://github.com/autobleem2/app_wolf4sdl
ci/build.sh all    # inside ghcr.io/autobleem2/autobleem-build
```

Controls (PlayStation Classic pad): D-pad move and turn, Cross fire, Circle run, Square open, Triangle/Select
next/previous weapon, L1/R1 strafe, L2 pause, R2 or Start the menu. Press Reset on the console or hold
Start + Select to leave.

Licence: the build, patch and tools GPL-3.0-or-later; Wolf4SDL id Software's licence or the GPL; the game data
is id Software's shareware and demo, freely distributable (see `LICENSE`).

#!/usr/bin/env bash
# Builds Wolf4SDL in the autobleem-build image (ghcr.io/autobleem2/autobleem-build) and packages it as two AutoBleem
# Apps. Wolf4SDL picks its game at compile time, so each is its own build of the same source:
#
#   Apps/wolf4sdl/  Wolfenstein 3D (Shareware) - episode 1, the v1.4 shareware data (*.wl1); program wolf3d
#   Apps/sodemo/    Spear of Destiny (Demo)    - the v1.0 demo data (*.sdm); program spear
#
#   ci/build.sh native                    a host build (build_native/)
#   ci/build.sh psc|rpi|rpi64|pcusb|win   a target -> dist/<app>-<key>-<version>.zip for each of the two
#   ci/build.sh all                       every one of them
#
# upstream/wolf4sdl is a pinned submodule, never edited: each build copies it and applies patches/wolf4sdl/*.patch
# (CLAUDE.md). SDL2 and SDL2_mixer are the launcher's (the console, Windows) or the system's (the Pis, the PC
# stick) - nothing is bundled. The game data comes from our mirror, pinned by sha256.
#
# On the build server: docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -w /src \
#                          ghcr.io/autobleem2/autobleem-build:develop ci/build.sh all
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

VERSION="${AB_VERSION:-$(tr -d '\r' < VERSION)}"
JOBS="${JOBS:-$(nproc)}"
PSC=${AB_PSC_TOOLCHAIN:-/opt/psc}
MINGW_SDL2=${AB_MINGW_SDL2:-/opt/mingw-sdl2}
MIRROR="${AB_MIRROR_URL:-https://autobleem.retromenele.pl/mirror}"

# app -> program name, the version defines (version.h's table), the data archive and its sha256
APPS=(wolf4sdl sodemo)
declare -A PROGRAM=([wolf4sdl]=wolf3d [sodemo]=spear)
declare -A DEFINES=([wolf4sdl]="-DCARMACIZED -DUPLOAD" [sodemo]="-DCARMACIZED -DSPEAR -DSPEARDEMO")
declare -A DATA=([wolf4sdl]=wolf3d-shareware-1.4.zip [sodemo]=sod-demo-1.0.zip)
declare -A DATA_SHA=(
    [wolf4sdl]=8fef32878a443488dd1c26c3bd9cc36e93c3152f099876c597ffb07ed2bbc784
    [sodemo]=d3af299c1d455e3fea7a64951d794faff713050e9c9ed356ff6c42446d0fe20a
)

banner() { printf '\n==== %s ====\n' "$*"; }

fetch_data() {
    mkdir -p build_data
    for app in "${APPS[@]}"; do
        local zip="build_data/${DATA[$app]}"
        if ! { [ -f "$zip" ] && echo "${DATA_SHA[$app]}  $zip" | sha256sum -c --quiet - 2>/dev/null; }; then
            banner "data: ${DATA[$app]} (our mirror)"
            curl -fsSL -o "$zip" "$MIRROR/wolf3d/${DATA[$app]}"
            echo "${DATA_SHA[$app]}  $zip" | sha256sum -c -
        fi
    done
}

# ---------------------------------------------------------------------------------------------------------
# One target. Each target_* sets CC, CXX, STRIP, CFLAGS_T (CPU flags), SDL_CFLAGS, SDL_LIBS, EXTRA_LDFLAGS, EXE
# ---------------------------------------------------------------------------------------------------------
pc_sdl() { # pc_sdl <pkg-config>: SDL2 + SDL2_mixer through the target's pkg-config
    SDL_CFLAGS=$("$1" --cflags sdl2 SDL2_mixer)
    SDL_LIBS=$("$1" --libs sdl2 SDL2_mixer)
}
target_native() {
    CC=gcc; CXX=g++; STRIP=strip; CFLAGS_T=""; EXTRA_LDFLAGS=""; EXE=""
    pc_sdl pkg-config
}
target_psc() {
    # the console's gcc-6 against a Debian Stretch sysroot, and the launcher's SDL2 family (/opt/psc/sdl2)
    CC="$PSC/bin/armv8-sony-linux-gnueabihf-gcc"; CXX="$PSC/bin/armv8-sony-linux-gnueabihf-g++"
    STRIP="$PSC/bin/armv8-sony-linux-gnueabihf-strip"
    CFLAGS_T="-mfloat-abi=hard -march=armv8-a -mfpu=neon-vfpv4"; EXTRA_LDFLAGS=""; EXE=""
    # SDL2_mixer's .pc names vorbisfile, which has no .pc of its own there: the mixer is linked by name
    SDL_CFLAGS=$(PKG_CONFIG_LIBDIR="$PSC/sdl2/lib/pkgconfig" pkg-config --cflags sdl2)
    SDL_LIBS="$(PKG_CONFIG_LIBDIR="$PSC/sdl2/lib/pkgconfig" pkg-config --libs sdl2) -lSDL2_mixer"
}
target_rpi() {
    CC=arm-linux-gnueabihf-gcc; CXX=arm-linux-gnueabihf-g++; STRIP=arm-linux-gnueabihf-strip
    CFLAGS_T="-mfloat-abi=hard -mfpu=neon-vfpv4 -march=armv7-a"; EXTRA_LDFLAGS=""; EXE=""
    pc_sdl arm-linux-gnueabihf-pkg-config
}
target_rpi64() {
    CC=aarch64-linux-gnu-gcc; CXX=aarch64-linux-gnu-g++; STRIP=aarch64-linux-gnu-strip
    CFLAGS_T="-march=armv8-a"; EXTRA_LDFLAGS=""; EXE=""
    pc_sdl aarch64-linux-gnu-pkg-config
}
target_pcusb() {
    CC=i686-linux-gnu-gcc; CXX=i686-linux-gnu-g++; STRIP=i686-linux-gnu-strip
    CFLAGS_T="-march=i686 -mtune=generic -D_FILE_OFFSET_BITS=64"; EXTRA_LDFLAGS=""; EXE=""
    pc_sdl i386-linux-gnu-pkg-config
}
target_win() {
    # the official SDL2 mingw development packages: the DLLs the Windows product ships next to the launcher,
    # which puts its folder on an App's PATH. The C++ runtime goes in statically - nothing else ships it.
    CC=x86_64-w64-mingw32-gcc; CXX=x86_64-w64-mingw32-g++; STRIP=x86_64-w64-mingw32-strip
    CFLAGS_T=""; EXE=.exe
    SDL_CFLAGS="-I$MINGW_SDL2/include -I$MINGW_SDL2/include/SDL2 -Dmain=SDL_main"
    SDL_LIBS="-L$MINGW_SDL2/lib -lmingw32 -lSDL2main -lSDL2 -lSDL2_mixer -mwindows"
    # (and winpthread, which the static libstdc++ of a posix-thread MinGW calls into)
    EXTRA_LDFLAGS="-static-libgcc -static-libstdc++ -Wl,-Bstatic,--whole-archive -lwinpthread -Wl,--no-whole-archive,-Bdynamic"
}

build_app() { # build_app <key> <app>
    local key="$1" app="$2" dir="build_$1/$2"
    local program="${PROGRAM[$app]}$EXE"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -r upstream/wolf4sdl "$dir/src"
    rm -rf "$dir/src/.git"
    for p in patches/wolf4sdl/*.patch; do
        [ -f "$p" ] || continue
        patch -d "$dir/src" -p1 --no-backup-if-mismatch < "$p" >/dev/null
    done
    # upstream's Makefile reads its flags from a config file (CONFIG); ours says which game and which CPU
    cat > "$dir/src/config.autobleem" <<EOF
CFLAGS += -O2 $CFLAGS_T -DVERSIONALREADYCHOSEN ${DEFINES[$app]}
LDFLAGS += $EXTRA_LDFLAGS
EOF
    make -C "$dir/src" -j "$JOBS" CONFIG=config.autobleem CC="$CC" CXX="$CXX" BINARY="${PROGRAM[$app]}" \
        CFLAGS_SDL="$SDL_CFLAGS" LDFLAGS_SDL="$SDL_LIBS" Q= >/dev/null
    # a MinGW link names its output with .exe on its own
    local built="$dir/src/${PROGRAM[$app]}"
    [ -f "$built" ] || built="$built.exe"

    local stage="build_$key/Apps/$app"
    rm -rf "$stage"
    mkdir -p "$stage/bin/$key"
    cp "$built" "$stage/bin/$key/$program"
    "$STRIP" "$stage/bin/$key/$program"
    cp "resources/$app/app.ini" "resources/$app/readme.txt" "resources/$app/icon.png" resources/pad.ini "$stage/"
    cp "$dir/src/license-gpl.txt" "$stage/LICENSE-gpl.txt"
    cp "$dir/src/license-id.txt" "$stage/LICENSE-id.txt"
    python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        "build_data/${DATA[$app]}" "$stage"
    sed -i "s/^Version=.*/Version=$VERSION/" "$stage/app.ini"
}

build_target() { # build_target <key>
    banner "$1 (build_$1)"
    "target_$1"
    for app in "${APPS[@]}"; do
        build_app "$1" "$app"
    done
}

package() { # package <key>
    local key="$1" dir="build_$1"
    mkdir -p dist
    for app in "${APPS[@]}"; do
        local zip="dist/$app-$key-$VERSION.zip"
        rm -f "$zip"
        (cd "$dir" && python3 - "$ROOT/$zip" "$app" <<'EOF'
import os, sys, zipfile
# every file under Apps/<app>, with its mode (the program stays executable where the filesystem keeps it)
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(os.path.join("Apps", sys.argv[2])):
        dirs.sort()
        for name in sorted(files):
            z.write(os.path.join(root, name))
EOF
        )
        ls -l "$zip"
    done
}

check() { # check <key>: each program is the platform's and needs nothing we do not ship
    local key="$1"
    for app in "${APPS[@]}"; do
        local stage="build_$key/Apps/$app" program="${PROGRAM[$app]}"
        case "$key" in
            psc)
                file "$stage/bin/psc/$program" | grep -q 'ELF 32-bit LSB.*ARM'
                bash tools/check_psc_binary.sh "$stage/bin/psc/$program" "$PSC" ;;
            rpi) file "$stage/bin/rpi/$program" | grep -q 'ELF 32-bit LSB.*ARM' ;;
            rpi64) file "$stage/bin/rpi64/$program" | grep -q 'ELF 64-bit LSB.*aarch64' ;;
            pcusb) file "$stage/bin/pcusb/$program" | grep -q 'ELF 32-bit LSB.*Intel 80386' ;;
            win) file "$stage/bin/win/$program.exe" | grep -q 'PE32+ executable.*x86-64' ;;
        esac
        bash tools/check_needed.sh "$key" "$stage"
    done
}

build_native() {
    fetch_data
    build_target native
    ls -l build_native/Apps/*/bin/native/
}

build_one() { # build_one <key>
    fetch_data
    build_target "$1"
    check "$1"
    package "$1"
}

[ $# -gt 0 ] || { echo "usage: $0 native|psc|rpi|rpi64|pcusb|win|all" >&2; exit 2; }
for target in "$@"; do
    case "$target" in
        native) build_native ;;
        psc | rpi | rpi64 | pcusb | win) build_one "$target" ;;
        all) build_native; for k in psc rpi rpi64 pcusb win; do build_one "$k"; done ;;
        *) echo "unknown target: $target" >&2; exit 2 ;;
    esac
done

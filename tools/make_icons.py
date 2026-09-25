#!/usr/bin/env python3
"""Draw each App's icon.png (256x219, what the launcher's Apps set shows) from its own game's title screen:

    tools/make_icons.py build_data     -> resources/wolf4sdl/icon.png, resources/sodemo/icon.png

Nothing of unknown origin: the picture is the one the game itself opens with, read out of its VGAGRAPH the way
Wolf4SDL reads it (id_ca.cpp) - VGAHEAD's 3-byte chunk offsets, VGADICT's Huffman tree (head node 254), each
chunk's expanded length first, chunk 0 the table of picture sizes, a picture stored as four planes. Wolfenstein's
title (chunk 99 in the v1.4 shareware) is drawn in the game palette (wolfpal.inc); Spear's is two halves
(chunks 74 and 75, at y 0 and 80) in a palette of its own (chunk 131). The chunk numbers are what the gfxv_*.h
enums come to with each build's version defines. Needs Pillow; run after ci/build.sh has fetched the data.
"""
import os
import re
import struct
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
W, H = 256, 219
STARTPICS = 3

GAMES = {
    # app: (data zip, extension, [(chunk, y)], palette chunk or None for wolfpal.inc)
    "wolf4sdl": ("wolf3d-shareware-1.4.zip", "wl1", [(99, 0)], None),
    "sodemo": ("sod-demo-1.0.zip", "sdm", [(74, 0), (75, 80)], 131),
}


class Graphics:
    def __init__(self, files, ext):
        head = files["vgahead." + ext]
        self.starts = []
        for i in range(0, len(head) - 2, 3):
            value = head[i] | head[i + 1] << 8 | head[i + 2] << 16
            self.starts.append(-1 if value == 0xFFFFFF else value)
        d = files["vgadict." + ext]
        self.nodes = [struct.unpack_from("<HH", d, 4 * i) for i in range(255)]
        self.data = files["vgagraph." + ext]
        table = self.chunk(0)
        self.sizes = [struct.unpack_from("<hh", table, i) for i in range(0, len(table), 4)]

    def chunk(self, number):
        start = self.starts[number]
        (length,) = struct.unpack_from("<i", self.data, start)
        return self.expand(self.data[start + 4:], length)

    def expand(self, source, length):
        out = bytearray()
        node = self.nodes[254]
        for byte in source:
            for bit in range(8):
                value = node[1] if byte & (1 << bit) else node[0]
                if value < 256:
                    out.append(value)
                    if len(out) >= length:
                        return bytes(out)
                    node = self.nodes[254]
                else:
                    node = self.nodes[value - 256]
        return bytes(out)

    def picture(self, number):
        width, height = self.sizes[number - STARTPICS]
        planes = self.chunk(number)
        quarter = width >> 2
        pixels = bytearray(width * height)
        for y in range(height):
            for x in range(width):
                pixels[y * width + x] = planes[(y * quarter + (x >> 2)) + (x & 3) * quarter * height]
        return width, height, bytes(pixels)


def wolf_palette():
    text = open(os.path.join(ROOT, "upstream", "wolf4sdl", "wolfpal.inc"), encoding="ascii").read()
    values = [tuple(int(v) for v in m) for m in re.findall(r"RGB\(\s*(\d+),\s*(\d+),\s*(\d+)\)", text)]
    return [(r * 255 // 63, g * 255 // 63, b * 255 // 63) for r, g, b in values[:256]]


def main(argv):
    data_dir = argv[1] if len(argv) > 1 else os.path.join(ROOT, "build_data")
    for app, (archive, ext, parts, palette_chunk) in GAMES.items():
        with zipfile.ZipFile(os.path.join(data_dir, archive)) as z:
            files = {os.path.basename(n).lower(): z.read(n) for n in z.namelist()}
        gfx = Graphics(files, ext)
        if palette_chunk is None:
            palette = wolf_palette()
        else:
            raw = gfx.chunk(palette_chunk)
            palette = [(raw[i] * 255 // 63, raw[i + 1] * 255 // 63, raw[i + 2] * 255 // 63) for i in range(0, 768, 3)]
        screen = Image.new("RGB", (320, 200))
        for number, top in parts:
            width, height, pixels = gfx.picture(number)
            part = Image.new("RGB", (width, height))
            part.putdata([palette[p] for p in pixels])
            screen.paste(part, (0, top))
        # 320x200 on a 4:3 screen: stretch to its displayed shape, then cover the icon
        screen = screen.resize((320, 240), Image.LANCZOS)
        scale = max(W / screen.width, H / screen.height)
        screen = screen.resize((round(screen.width * scale), round(screen.height * scale)), Image.LANCZOS)
        left, top = (screen.width - W) // 2, (screen.height - H) // 2
        icon = screen.crop((left, top, left + W, top + H)).convert("RGBA")
        out = os.path.join(ROOT, "resources", app, "icon.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        icon.save(out)
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

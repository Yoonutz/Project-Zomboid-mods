"""Generate TwoManCrew UI icons.

Palette sampled from the mod's existing TwoManCrew_Journal.png so the new
action icons read as the same set rather than borrowed clip art:

    outline  #1A140F   brass  #DAA238 / #F0C874 / #BA8E3E
    steel    #5C6878 / #3E4856

Each icon is authored as a 16x16 character grid, one char per pixel, then
upscaled 3x by nearest neighbour to a 48x48 variant. Nearest neighbour
matters: the icons are pixel art, and a smoothing resample would turn the
one-pixel outline into mush.

Output is RGBA (PNG colour type 6) to match the existing icons, which
getTexture loads fine.
"""

import struct
import zlib
import os

# Relative to this script, which sits at the mod root beside deploy.mjs -
# outside Contents/, so the generator itself is never packaged. Run it as
# `python make-icons.py` from anywhere; the output path does not depend on
# the working directory.
OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "Contents", "mods", "TwoManCrew", "42", "media", "ui",
)

PALETTE = {
    ".": None,                    # transparent
    "K": (0x1A, 0x14, 0x0F),      # outline
    "B": (0xDA, 0xA2, 0x38),      # brass mid
    "L": (0xF0, 0xC8, 0x74),      # brass light
    "D": (0xBA, 0x8E, 0x3E),      # brass dark
    "S": (0x5C, 0x68, 0x78),      # steel mid
    "T": (0x3E, 0x48, 0x56),      # steel dark
    "G": (0x6E, 0xB0, 0x5E),      # green (partner nearby)
    "R": (0xC4, 0x5A, 0x3E),      # red-brown (alone)
}

# A circular arrow. Reads as "ask the server again".
REFRESH = [
    "................",
    ".....KKKKKK.....",
    "...KKLLLLLLKK...",
    "..KLLKKKKKKLLK..",
    "..KLKK....KKLK..",
    ".KLLK......KLLK.",
    ".KLK........KLK.",
    ".KLK........KLK.",
    ".KLK........KLK.",
    ".KLLK......KBBBK",
    "..KLKK....KBLLBK",
    "..KLLKKKKKBLLLLK",
    "...KKLLLLLLLLLK.",
    ".....KKKKKKKKK..",
    ".......KKKKK....",
    "................",
]

# A surveyor's flag planted in ground. Reads as "claim this block".
CLAIM = [
    "................",
    "...KKKKKKKK.....",
    "...KLLLLLLKK....",
    "...KLBBBBBBLK...",
    "...KLBLLLLBBLK..",
    "...KLBBBBBBBLK..",
    "...KLBLLLLBBLK..",
    "...KLBBBBBBLK...",
    "...KLLLLLLKK....",
    "...KKKKKKK......",
    "...KSSK.........",
    "...KSSK.........",
    "..KKSSKK........",
    ".KTTSSTTK.......",
    "KTTTTTTTTK......",
    ".KKKKKKKK.......",
]

# An open book. Reads as "switch the view / read the log".
#
# The ruled lines are drawn in outline black, not brass: an earlier pass used
# brass-on-brass and the lines were invisible at 16px, leaving two blank
# rectangles. Contrast has to come from the darkest colour in the palette,
# because a 16px icon has no room for a subtle one.
VIEW = [
    "................",
    "..KKKK....KKKK..",
    ".KLLLLK..KLLLLK.",
    "KLLLLLLKKLLLLLLK",
    "KLKKKKLKKLKKKKLK",
    "KLLLLLLKKLLLLLLK",
    "KLKKKKLKKLKKKKLK",
    "KLLLLLLKKLLLLLLK",
    "KLKKKKLKKLKKKKLK",
    "KLLLLLLKKLLLLLLK",
    "KLKKKKLKKLKKKKLK",
    "KLLLLLLKKLLLLLLK",
    "KDDDDDDKKDDDDDDK",
    ".KDDDDDKKDDDDDK.",
    "..KKKKK..KKKKK..",
    "................",
]

# Two hard hats side by side - the crew badge. This is the widget's only
# element once collapsed, so it has to read as two people at a glance.
#
# The brims are kept separate all the way down. A previous pass ran the two
# hats into one continuous brass band across rows 5-7, which rendered as a
# single blob rather than a pair - at this size the gap between the two
# shapes is what carries the meaning, so it is never filled.
CREW = [
    "................",
    "...KKK.....KKK..",
    "..KBBBK...KBBBK.",
    ".KBLLLBK.KBLLLBK",
    ".KBLLLBK.KBLLLBK",
    "KBBLLLBBKBBLLLBB",
    "KBBBBBBBKBBBBBBB",
    "KKKKKKKK.KKKKKKK",
    "................",
    "...KKK.....KKK..",
    "..KSSSK...KSSSK.",
    "..KSTSK...KSTSK.",
    "..KSSSK...KSSSK.",
    "...KSK.....KSK..",
    "..KKSKK...KKSKK.",
    "................",
]


def grid_to_rgba(grid):
    """Turn a character grid into a flat RGBA byte list plus its size."""
    h = len(grid)
    w = len(grid[0])
    rows = []
    for line in grid:
        assert len(line) == w, "ragged icon grid"
        row = bytearray()
        for ch in line:
            colour = PALETTE[ch]
            if colour is None:
                row += bytes((0, 0, 0, 0))
            else:
                row += bytes(colour) + b"\xff"
        rows.append(bytes(row))
    return w, h, rows


def upscale(rows, w, h, factor):
    """Nearest-neighbour upscale. Keeps pixel-art edges hard."""
    out = []
    for row in rows:
        big = bytearray()
        for x in range(w):
            px = row[x * 4:(x + 1) * 4]
            big += px * factor
        for _ in range(factor):
            out.append(bytes(big))
    return w * factor, h * factor, out


def write_png(path, w, h, rows):
    """Minimal RGBA PNG writer - no filtering, one IDAT."""
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


ICONS = {
    "TwoManCrew_Refresh": REFRESH,
    "TwoManCrew_Claim": CLAIM,
    "TwoManCrew_View": VIEW,
    "TwoManCrew_Crew": CREW,
}

for name, grid in ICONS.items():
    w, h, rows = grid_to_rgba(grid)
    write_png(os.path.join(OUT, name + "_16.png"), w, h, rows)
    bw, bh, brows = upscale(rows, w, h, 3)
    write_png(os.path.join(OUT, name + ".png"), bw, bh, brows)
    print("wrote", name, "16x16 and %dx%d" % (bw, bh))

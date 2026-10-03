"""Redraw graphic text labels (uncompressed 2bpp tiles) in English.

Config: gfx/labels.json, a list of
  {"name", "offset": file offset of tile 0, "layout": [[tile idx...], ...],
   "text": English, "ink": 3, "align": "center"|"left", "y": top row,
   "narrow": "chars to draw with condensed glyphs"}
The original ink is erased (refilled from the nearest non-ink pixel in the
row, which keeps highlight blobs), then the English is drawn in the ink
colour with the VWF font.
"""
import json, os
from fontlib import ROOT, load

NARROW = {   # condensed variants for tight labels (rows 0-7, as font.txt)
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "m": [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    "w": [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
}

def tile_px(d):
    return [[((d[2*r] >> (7-x)) & 1) | (((d[2*r+1] >> (7-x)) & 1) << 1) for x in range(8)] for r in range(8)]

def px_tile(px):
    out = bytearray()
    for r in range(8):
        lo = hi = 0
        for x in range(8):
            c = px[r][x]; lo |= (c & 1) << (7-x); hi |= ((c >> 1) & 1) << (7-x)
        out += bytes([lo, hi])
    return bytes(out)

def glyph_rows(ch, font, narrow):
    if ch in narrow and ch in NARROW:
        rows = NARROW[ch]; return rows, len(rows[0])
    data, adv = font[ord(ch)]
    w = adv - 1
    rows = ["".join("#" if data[3 + r] & (0x80 >> x) else "." for x in range(max(w, 1))) for r in range(10)]
    return rows, w

def apply(rom, cfg, font):
    off = cfg["offset"]; layout = cfg["layout"]; ink = cfg.get("ink", 3)
    H = len(layout) * 8; W = len(layout[0]) * 8
    img = [[0] * W for _ in range(H)]
    for ty, row in enumerate(layout):
        for tx, t in enumerate(row):
            px = tile_px(rom[off + t * 16: off + t * 16 + 16])
            for y in range(8):
                for x in range(8): img[ty*8+y][tx*8+x] = px[y][x]
    if cfg.get("style") == "outline":        # outlined sprite text: start blank
        img = [[0] * W for _ in range(H)]
        ink = cfg.get("fill", 1)
    for c in cfg.get("clear", []):           # wipe decoration colours
        for y in range(H):
            for x in range(W):
                if img[y][x] == c: img[y][x] = cfg.get("bg", 0)
    bg = cfg.get("bg")
    for y in range(H):                       # erase ink
        for x in range(W):
            if img[y][x] == ink:
                if bg is not None: img[y][x] = bg; continue
                c = 0
                for d in range(1, W):
                    for xx in (x - d, x + d):
                        if 0 <= xx < W and img[y][xx] != ink: c = img[y][xx]; break
                    else: continue
                    break
                img[y][x] = c
    narrow = cfg.get("narrow", "")
    lines = cfg["text"].split("|")
    lh = cfg.get("line_h", 10)
    area_w = cfg.get("w", W)
    for li, line in enumerate(lines):
        glyphs = [glyph_rows(ch, font, narrow) for ch in line]
        total = sum(w for _, w in glyphs) + max(0, len(glyphs) - 1)
        if total > area_w: raise SystemExit(f"label {cfg['name']!r}: {line!r} {total}px > {area_w}px")
        x = (area_w - total) // 2 if cfg.get("align", "center") == "center" else cfg.get("x", 0)
        y0 = cfg.get("y", (H - 8) // 2 if H >= 10 else 0) + li * lh
        for rows, w in glyphs:
            for r, row in enumerate(rows):
                for i, p in enumerate(row):
                    if p == "#" and 0 <= y0 + r < H and x + i < W: img[y0 + r][x + i] = ink
            x += w + 1
    if cfg.get("style") == "outline":
        oc = cfg.get("outline", 3)
        src = [r[:] for r in img]
        for y in range(H):
            for x in range(W):
                if src[y][x] == 0 and any(0 <= y + dy < H and 0 <= x + dx < W and src[y + dy][x + dx] == ink
                                          for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                    img[y][x] = oc
    for ty, row in enumerate(layout):
        for tx, t in enumerate(row):
            px = [[img[ty*8+y][tx*8+xx] for xx in range(8)] for y in range(8)]
            rom[off + t * 16: off + t * 16 + 16] = px_tile(px)

def apply_all(rom):
    path = os.path.join(ROOT, "gfx", "labels.json")
    if not os.path.exists(path): return 0
    font = load(); cfgs = json.load(open(path, encoding="utf8"))
    for c in cfgs: apply(rom, c, font)
    return len(cfgs)

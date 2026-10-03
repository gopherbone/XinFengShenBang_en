"""Parser for the original Chinese dialogue format.

Bytes $F0-$FF select a 224-glyph font page (sticky), $E0-$EF are control
codes, everything else is a glyph index in the current page.
"""
import json, os
from collections import defaultdict
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.path.join(ROOT, "orig", "xfsb.gbc")   # original ROM (not in git)
T = json.load(open(os.path.join(ROOT, "tools", "glyph_table.json"), encoding="utf8"))
SCRIPT_BANKS = [0x08, 0x11, 0x1B, 0x1D, 0x4C, 0x4D, 0x4E, 0x4F, 0x51, 0x56,
                0x57, 0x5A, 0x5B, 0x5C, 0x5D, 0x64, 0x65, 0x66]
ARGS = {0xE0: 2, 0xE5: 2}
END = {0xE2, 0xE4, 0xE5, 0xE6, 0xE8, 0xEF}
OPENERS = {0xE0, 0xE1, 0xE9}

def parse(rom, off, limit):
    """Tokens: ('P',page) ('C',code,args) ('G',page,byte,char). None if invalid."""
    page = 0; toks = []; i = off
    while i < limit:
        b = rom[i]; i += 1
        if b >= 0xF0:
            page = b & 0xF; toks.append(('P', page)); continue
        if b >= 0xE0:
            a = bytes(rom[i:i + ARGS.get(b, 0)]); i += len(a)
            toks.append(('C', b, a))
            if b in END: return toks, i
            continue
        k = f"{page:x}:{b:02x}"
        if k not in T: return None
        toks.append(('G', page, b, T[k]))
    return None

SIGN_BANK, SIGN_TABLE = 0x0C, (0x401F, 0x40C0)   # signposts: pointer lists

def collect(rom):
    """All dialogue messages: {"bb:aaaa": tokens} (box-opening messages only)."""
    msgs = {}
    base = SIGN_BANK * 0x4000
    for a in range(SIGN_TABLE[0], SIGN_TABLE[1], 2):
        p = rom[base + a - 0x4000] | rom[base + a - 0x3FFF] << 8
        if SIGN_TABLE[1] <= p < 0x8000:
            r = parse(rom, base + p - 0x4000, base + 0x4000)
            if r and r[0][0][:2] == ('C', 0xE1):
                msgs[f"{SIGN_BANK:02x}:{p:04x}"] = r[0]
    for b in SCRIPT_BANKS:
        base = b * 0x4000; d = rom[base:base + 0x4000]
        starts = set()
        for i in range(len(d) - 2):
            if d[i] in (0x14, 0x16):
                p = d[i + 1] | d[i + 2] << 8
                if 0x4000 <= p < 0x8000 and d[p - 0x4000] in OPENERS:
                    starts.add(p - 0x4000)
        for i in range(len(d) - 1):
            if d[i] in END and d[i + 1] == 0xE0:
                starts.add(i + 1)
        for s in sorted(starts):
            r = parse(rom, base + s, base + 0x4000)
            if r and r[0][0][0] == 'C' and r[0][0][1] in OPENERS and any(t[0] == 'G' for t in r[0]):
                msgs[f"{b:02x}:{0x4000 + s:04x}"] = r[0]
    return msgs

def structure(toks):
    """-> (boxes, tail). boxes: [(opener_bytes, chinese_text)], tail: end info."""
    boxes = []; tail = None
    for t in toks:
        if t[0] == 'C' and t[1] in OPENERS:
            boxes.append([bytes([t[1]]) + t[2], ""])
        elif t[0] == 'G':
            boxes[-1][1] += t[3]
        elif t[0] == 'C' and t[1] in (0xEC, 0xEE):
            boxes[-1][1] += "¶"
        elif t[0] == 'C' and t[1] == 0xE7:
            tail = ('E7',)
        elif t[0] == 'C' and t[1] in END:
            if t[1] == 0xE5: tail = ('E5', t[2])
            elif tail is None: tail = ('END', t[1])
            else: tail = tail + (t[1],)
    return boxes, tail

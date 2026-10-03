"""Dump/encode strings of the menu & battle interpreter (bank 0 $08CA).

Same glyph encoding as dialogue; no inline control arguments. Strings end
with $E4/$ED (return) or $E2 (wait+end).
"""
import json, os
import textdump
from textdump import T
MENU_BANKS = [0x0D, 0x1E, 0x25, 0x2D]   # (bank $0C signposts are dialogue)
TERM = (0xE2, 0xE4, 0xED)
EXTRA = [(0x0A, 0x4FA9), (0x0A, 0x4FAF),   # title menu (own glyph set)
         (0x2D, 0x7E18)]
TABLES = [(0x1E, 0x4953), (0x1E, 0x607F), (0x1E, 0x62CD), (0x1E, 0x64A7), (0x1E, 0x6951),
          (0x1E, 0x4986), (0x0D, 0x4E34), (0x0D, 0x53F1), (0x2D, 0x7E00)]

def parse(rom, bank, addr):
    """-> (tokens, end_addr) or None. tokens: glyph chars / ('C',code)."""
    o = bank * 0x4000 + addr - 0x4000; page = None; toks = []; i = 0
    while i < 160:
        b = rom[o + i]; i += 1
        if b >= 0xF0:
            page = b & 0xF
            if page > 9: return None
            continue
        if b >= 0xE0:
            toks.append(('C', b))
            if b in TERM: return toks, addr + i
            continue
        if page is None: return None
        k = f"{page:x}:{b:02x}"
        if k not in T: return None
        toks.append(('G', T[k]))
    return None

def table_targets(rom, bank, addr):
    o = bank * 0x4000 + addr - 0x4000; out = []
    for i in range(400):
        p = rom[o + 2 * i] | rom[o + 2 * i + 1] << 8
        if not 0x4000 <= p < 0x8000: break
        out.append(p)
    return out

def collect(rom):
    starts = set()
    for b in MENU_BANKS:
        base = b * 0x4000
        for i in range(0x3FFF):
            if rom[base + i] in TERM:
                starts.add((b, 0x4000 + i + 1))
    for b, a in TABLES:
        for p in table_targets(rom, b, a): starts.add((b, p))
    starts |= set(EXTRA)
    out = {}
    for b, a in sorted(starts):
        r = parse(rom, b, a)
        if not r: continue
        toks, end = r
        if not any(t[0] == 'G' for t in toks) and (b, a) not in {(tb, p) for tb, ta in TABLES for p in table_targets(rom, tb, ta)}:
            continue
        zh = "".join(t[1] if t[0] == 'G' else f"[{t[1]:02X}]" for t in toks)
        cells = sum(1 for t in toks if t[0] == 'G')
        out[f"{b:02x}:{a:04x}"] = dict(zh=zh, cells=cells, end=end)
    return out

def encode(en, term):
    """English with [XX] control tokens -> bytes; term = original terminator."""
    out = bytearray(); i = 0
    while i < len(en):
        if en[i] == "[" and i + 3 < len(en) and en[i + 3] == "]":
            out.append(int(en[i + 1:i + 3], 16)); i += 4; continue
        out.append(ord(en[i])); i += 1
    return out

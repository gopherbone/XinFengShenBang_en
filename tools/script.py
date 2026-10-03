"""English script encoding and insertion."""
import json, os, glob, re
import textdump
from fontlib import ROOT, text_width

LINE_PX = 112
SCRIPT_DIR = os.path.join(ROOT, "script")

def load_names():
    names = []
    for l in open(os.path.join(SCRIPT_DIR, "names_en.txt"), encoding="utf8"):
        k, _, v = l.rstrip("\n").partition(" ")
        assert int(k, 16) == len(names)
        names.append(v)
    return names

def load_translations():
    en = {}
    for p in sorted(glob.glob(os.path.join(SCRIPT_DIR, "dialogue", "*.json"))):
        for e in json.load(open(p, encoding="utf8")):
            en[e["id"]] = e["en"]
    return en

def wrap(text, font):
    """Greedy pixel word-wrap -> list of pages, each a list of <=2 lines."""
    pages = []
    for chunk in text.split("|"):
        words = chunk.split()
        lines = []; cur = ""
        for w in words:
            cand = (cur + " " + w) if cur else w
            if text_width(cand, font) <= LINE_PX:
                cur = cand; continue
            if cur: lines.append(cur)
            cur = w
            while text_width(cur, font) > LINE_PX:      # hard-split long words
                n = len(cur)
                while text_width(cur[:n], font) > LINE_PX: n -= 1
                lines.append(cur[:n]); cur = cur[n:]
        if cur: lines.append(cur)
        if not lines: lines = [""]
        for i in range(0, len(lines), 2):
            pages.append(lines[i:i + 2])
    return pages

def sanitize(s):
    s = s.replace("…", "...").replace("—", "-").replace("–", "-")
    s = s.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    return "".join(c if 0x20 <= ord(c) < 0x7F else "?" for c in s)

def encode_box(text, font, need_free_line=False):
    pages = wrap(sanitize(text), font)
    if need_free_line and len(pages[-1]) == 2:
        last = pages[-1].pop()
        pages.append([last])
    out = bytearray()
    for pi, pg in enumerate(pages):
        if pi: out.append(0xEC)
        for li, line in enumerate(pg):
            if li: out.append(0xED)
            out += line.encode("ascii")
    return out

def encode_message(boxes, tail, en, font, syms):
    out = bytearray()
    for bi, (opener, _zh) in enumerate(boxes):
        last = bi == len(boxes) - 1
        choice = last and tail and tail[0] in ('E5', 'E7')
        out += opener
        out += encode_box(en[bi], font, need_free_line=choice)
    if tail is None:
        out.append(0xE2)
    elif tail[0] == 'E5':
        out.append(0xED); out.append(0xE5)
        a = syms["EnStrYesNo"][1]; out += bytes([a & 0xFF, a >> 8])
    elif tail[0] == 'E7':
        out.append(0xED); out.append(0xE7); out.append(0xE2)
    else:
        out.append(tail[1])
    return out

def insert(rom, font, syms, first_bank, lookup_bank):
    msgs = textdump.collect(rom)
    en = load_translations()
    bank = first_bank; pos = 0x4000; placed = {}; missing = 0
    for mid in sorted(msgs):
        if mid not in en: missing += 1; continue
        boxes, tail = textdump.structure(msgs[mid])
        if len(boxes) != len(en[mid]):
            print("box count mismatch", mid); missing += 1; continue
        data = encode_message(boxes, tail, en[mid], font, syms)
        if pos + len(data) > 0x7FFF:
            bank += 1; pos = 0x4000
        o = bank * 0x4000 + pos - 0x4000
        rom[o:o + len(data)] = data
        placed[mid] = (bank, pos); pos += len(data)
    # lookup tables: index in lookup_bank, subtables packed after it
    by_bank = {}
    for mid, (nb, na) in placed.items():
        ob, oa = (int(x, 16) for x in mid.split(":"))
        by_bank.setdefault(ob, []).append((oa, nb, na))
    tb, tp = lookup_bank, 0x4000 + 256 * 3
    idx = lookup_bank * 0x4000
    for ob, ents in sorted(by_bank.items()):
        blob = bytearray([len(ents) & 0xFF, len(ents) >> 8])
        for oa, nb, na in sorted(ents):
            blob += bytes([oa & 0xFF, oa >> 8, nb, na & 0xFF, na >> 8])
        if tp + len(blob) > 0x7FFF:
            tb += 1; tp = 0x4000
        assert tb < first_bank
        o = tb * 0x4000 + tp - 0x4000
        rom[o:o + len(blob)] = blob
        rom[idx + ob * 3: idx + ob * 3 + 3] = bytes([tb, tp & 0xFF, tp >> 8])
        tp += len(blob)
    return dict(messages=len(msgs), inserted=len(placed), missing=missing,
                last_bank=hex(bank), table_end=(hex(tb), hex(tp)))

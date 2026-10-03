"""English script encoding and insertion."""
import json, os, glob, re
import textdump, menutext
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

def wrap_line(para, font):
    """Greedy pixel word-wrap of one paragraph -> list of lines."""
    lines = []; cur = ""
    for w in para.split():
        cand = (cur + " " + w) if cur else w
        if text_width(cand, font) <= LINE_PX:
            cur = cand; continue
        if cur: lines.append(cur)
        cur = w
        while text_width(cur, font) > LINE_PX:          # hard-split long words
            n = len(cur)
            while text_width(cur[:n], font) > LINE_PX: n -= 1
            lines.append(cur[:n]); cur = cur[n:]
    if cur: lines.append(cur)
    return lines

def wrap(text, font):
    """-> list of pages (<=2 lines each). "|" forces a page, "\n" a line."""
    pages = []
    for chunk in text.split("|"):
        lines = [l for para in chunk.split("\n") for l in wrap_line(para, font)] or [""]
        for i in range(0, len(lines), 2):
            pages.append(lines[i:i + 2])
    return pages

ARROWS = {"\u2191": 0x80, "\u2193": 0x81, "\u2190": 0x82, "\u2192": 0x83,
          "\u2196": 0x84, "\u2197": 0x85, "\u2198": 0x86, "\u2199": 0x87}

def sanitize(s):
    s = s.replace("…", "...").replace("—", "-").replace("–", "-")
    s = s.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    s = "".join(chr(ARROWS[c]) if c in ARROWS else c for c in s)
    return "".join(c if 0x20 <= ord(c) < 0x7F or 0x80 <= ord(c) <= 0x87 or c == "\n" else "?" for c in s)

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
            out += line.encode("latin-1")
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

DESC_LINE_PX = 144   # item/treasure description box: 2 lines x 9 cells

def pad_slot(en, cells, font):
    """Spaces that blank the rest of the original slot after a shorter
    English string (space = 4px)."""
    used = (text_width(sanitize(en), font) + 15) // 16
    return bytes([0x17 + cells]) if used < cells <= 8 else b""

PROLOGUE = (0x26, 0x5FA2)

def encode_prologue(en, font, cells_per_line=8, lines_per_page=5, ee_per_page=40):
    """Typewriter prologue. Lines start at cell n*8 (pen code); every page
    but the last carries exactly 40 EE delays so the game's page clear
    (after 40 EEs) lines up with the English layout."""
    lines = []
    for chunk in sanitize(en).split("|"):          # "|" = force new page
        cur = ""
        for w in chunk.split():
            c = (cur + " " + w).strip()
            if text_width(c, font) <= cells_per_line * 16: cur = c
            else: lines.append(cur); cur = w
        if cur: lines.append(cur)
        while len(lines) % lines_per_page: lines.append("")
    while lines and not lines[-1]: lines.pop()
    pages = [lines[i:i + lines_per_page] for i in range(0, len(lines), lines_per_page)]
    out = bytearray()
    for pi, pg in enumerate(pages):
        last = pi == len(pages) - 1
        chars = [(li, ch) for li, l in enumerate(pg) for ch in l]
        n = len(chars)
        ee = {}
        if not last:
            for k in range(ee_per_page):
                i = max(0, (k + 1) * n // ee_per_page - 1); ee[i] = ee.get(i, 0) + 1
        else:
            ee = {i: 1 for i in range(2, n, 3)}
        cur = 0
        for i, (li, ch) in enumerate(chars):
            if li != cur:
                out.append(0x10); cur = li       # next line
            out.append(ord(ch))
            out += bytes([0xEE] * ee.get(i, 0))
    return out

def load_menu():
    en = {}
    for p in sorted(glob.glob(os.path.join(SCRIPT_DIR, "menu", "*.json"))):
        for e in json.load(open(p, encoding="utf8")):
            if e.get("en"): en[e["id"]] = e["en"]
    return en

def encode_menu(en, zh, font):
    """Menu string -> bytes (without terminator). Descriptions get wrapped
    onto the second line of their box with a pen move."""
    en = sanitize(en)
    if zh.startswith(("法寶：", "道具：")) and "[" not in en:
        words = en.split(); l1 = ""
        while words and text_width((l1 + " " + words[0]).strip(), font) <= DESC_LINE_PX:
            l1 = (l1 + " " + words.pop(0)).strip()
        out = bytearray(l1.encode())
        if words:
            out.append(DESC_LINE_PX // 16)
            out += " ".join(words).encode()
        return out
    return menutext.encode(en, None)

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
    # menu / battle strings
    mstr = menutext.collect(rom)
    men = load_menu()
    names = load_names()
    for i, n in enumerate(names):          # speaker-name table, used by menus too
        o = 0xD * 0x4000 + 0xE34 + 2 * i
        mid = f"0d:{rom[o] | rom[o + 1] << 8:04x}"
        if n and mid not in men: men[mid] = n
    menu_placed = 0
    pid = f"{PROLOGUE[0]:02x}:{PROLOGUE[1]:04x}"
    if pid in men:
        mstr[pid] = dict(zh="", cells=0, end=None, prologue=True)
    for mid in sorted(men):
        if mid not in mstr: continue
        info = mstr[mid]
        ob, oa = (int(x, 16) for x in mid.split(":"))
        if info.get("prologue"):
            data = encode_prologue(men[mid], font) + bytes([0xEF])
            if pos + len(data) > 0x7FFF: bank += 1; pos = 0x4000
            o = bank * 0x4000 + pos - 0x4000
            rom[o:o + len(data)] = data
            placed[mid] = (bank, pos); pos += len(data); menu_placed += 1
            continue
        term = rom[ob * 0x4000 + info["end"] - 1 - 0x4000]
        data = encode_menu(men[mid], info["zh"], font)
        if ob == 0x2D:                      # battle box: indent away from portrait
            data = bytearray([0x11]) + data
        if 0 < info["cells"] <= 15 and "[" not in men[mid] and not info["zh"].startswith(("法寶：", "道具：")):
            data += pad_slot(men[mid], info["cells"], font)
        data += bytes([term])
        if pos + len(data) > 0x7FFF:
            bank += 1; pos = 0x4000
        o = bank * 0x4000 + pos - 0x4000
        rom[o:o + len(data)] = data
        placed[mid] = (bank, pos); pos += len(data); menu_placed += 1
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
    return dict(menu=menu_placed, messages=len(msgs), inserted=len(placed), missing=missing,
                last_bank=hex(bank), table_end=(hex(tb), hex(tp)))

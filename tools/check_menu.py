#!/usr/bin/env python3
"""Check menu translations against pixel budgets.
usage: check_menu.py <zh.json> <en.json>   (lists entries that are too wide)"""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fontlib import load, text_width
font = load()
zh = {e["id"]: e for e in json.load(open(sys.argv[1], encoding="utf8"))}
en = json.load(open(sys.argv[2], encoding="utf8"))
bad = 0
for e in en:
    z = zh.get(e["id"]); s = e.get("en", "")
    if z is None: print("unknown id", e["id"]); bad += 1; continue
    if any(not (0x20 <= ord(c) < 0x7F) for c in s): print("non-ascii", e["id"], s); bad += 1; continue
    import re
    vis = re.sub(r"\[[0-9A-F]{2}\]", "", s)
    if z["kind"] == "description":
        words = vis.split(); lines = [""]
        for w in words:
            c = (lines[-1] + " " + w).strip()
            if text_width(c, font) <= 144: lines[-1] = c
            else: lines.append(w)
        if len(lines) > 2: print(f"too long (needs {len(lines)} lines of 144px)", e["id"], s); bad += 1
    else:
        w = text_width(vis, font)
        if w > z["budget_px"]: print(f"too wide {w}>{z['budget_px']}px", e["id"], repr(s)); bad += 1
print("problems:", bad)

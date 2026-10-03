#!/usr/bin/env python3
"""Build the English ROM: expand, assemble hacks, insert script, fix checksums."""
import json, os, subprocess, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fontlib, script, labels, mkips

ROOT = fontlib.ROOT
BUILD = os.path.join(ROOT, "build")
ORIG = os.path.join(ROOT, "Xin Feng Shen Bang (Unlicensed, Chinese) (Multicart Rip) [Header Fix].gbc")
OUT = os.path.join(BUILD, "XinFengShenBang_en.gbc")
BANK_VWF, BANK_LOOKUP, FIRST_TEXT_BANK = 0x80, 0x81, 0x83
NBANKS = 256

def run(*cmd):
    print("+", " ".join(cmd)); subprocess.run(cmd, check=True, cwd=ROOT)

def write_font(font):
    widths = bytes(font[c][1] for c in range(0x20, 0x88))
    data = b"".join(bytes(font[c][0]) for c in range(0x20, 0x88))
    open(os.path.join(BUILD, "font_widths.bin"), "wb").write(widths)
    open(os.path.join(BUILD, "font_data.bin"), "wb").write(data)

def write_names(names, rom):
    # Name2Table: same names, $E4-terminated, for the menu/battle interpreter
    # (EA substitution); NameSrcTable: the original Chinese pointers (0D:4E34).
    src = [rom[0xD * 0x4000 + 0xE34 + 2 * i] | rom[0xD * 0x4000 + 0xE35 + 2 * i] << 8
           for i in range(len(names))]
    lines = [f"DEF NAME_COUNT EQU {len(names)}", "NameSrcTable::"]
    lines += [f"    dw ${p:04X}" for p in src]
    lines.append("Name2Table::")
    lines += [f"    dw Name2_{i:02X}" for i in range(len(names))]
    for i, n in enumerate(names):
        lines.append(f"Name2_{i:02X}: db \"{n}\", $E4" if n else f"Name2_{i:02X}: db $E4")
    lines.append("NameTable::")
    for i in range(len(names)):
        lines.append(f"    dw Name_{i:02X}")
    for i, n in enumerate(names):
        lines.append(f"Name_{i:02X}: db \"{n}\", 0" if n else f"Name_{i:02X}: db 0")
    open(os.path.join(BUILD, "names.asm"), "w").write("\n".join(lines) + "\n")

def read_sym(path):
    syms = {}
    for l in open(path):
        l = l.split(";")[0].strip()
        if not l: continue
        a, name = l.split()
        b, addr = a.split(":")
        syms[name] = (int(b, 16), int(addr, 16))
    return syms

def hashes(b):
    import hashlib, zlib
    return {"size": len(b), "crc32": f"{zlib.crc32(b) & 0xFFFFFFFF:08X}",
            "md5": hashlib.md5(b).hexdigest(), "sha1": hashlib.sha1(b).hexdigest()}

def write_release(orig, out):
    """docs/ is the GitHub Pages site: IPS patch + hashes for the web patcher."""
    ips = mkips.make_ips(orig, out)
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    open(os.path.join(docs, "xin-feng-shen-bang-en.ips"), "wb").write(ips)
    meta = {"source": hashes(orig), "patched": hashes(out), "patch": hashes(ips)}
    json.dump(meta, open(os.path.join(docs, "xin-feng-shen-bang-en.json"), "w"), indent=1)
    print("patched ROM", meta["patched"]["crc32"], "patch", meta["patch"]["size"], "bytes")

def main():
    os.makedirs(BUILD, exist_ok=True)
    rom = bytearray(open(ORIG, "rb").read())
    rom += b"\x00" * (NBANKS * 0x4000 - len(rom))
    for b in range(0x80, NBANKS):          # bank self-ID byte read by the game
        rom[b * 0x4000 + 0x3FFF] = b
    rom[0x148] = 0x07                       # 4 MB
    font = fontlib.load()
    write_font(font)
    names = script.load_names()
    write_names(names, rom)
    base = os.path.join(BUILD, "base.gbc")
    open(base, "wb").write(rom)
    run("rgbasm", "-o", "build/main.o", "src/main.asm")
    run("rgblink", "-O", "build/base.gbc", "-o", "build/linked.gbc", "-n", "build/linked.sym", "build/main.o")
    rom = bytearray(open(os.path.join(BUILD, "linked.gbc"), "rb").read())
    syms = read_sym(os.path.join(BUILD, "linked.sym"))
    stats = script.insert(rom, font, syms, FIRST_TEXT_BANK, BANK_LOOKUP)
    stats["labels"] = labels.apply_all(rom)
    open(OUT, "wb").write(rom)
    run("rgbfix", "-v", "build/XinFengShenBang_en.gbc")
    write_release(open(ORIG, "rb").read(), open(OUT, "rb").read())
    print(stats)

if __name__ == "__main__":
    main()

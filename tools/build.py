#!/usr/bin/env python3
"""Build the English ROM: expand, assemble hacks, insert script, fix checksums."""
import json, os, subprocess, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fontlib, script

ROOT = fontlib.ROOT
BUILD = os.path.join(ROOT, "build")
ORIG = os.path.join(ROOT, "Xin Feng Shen Bang (Unlicensed, Chinese) (Multicart Rip) [Header Fix].gbc")
OUT = os.path.join(BUILD, "XinFengShenBang_en.gbc")
BANK_VWF, BANK_LOOKUP, FIRST_TEXT_BANK = 0x80, 0x81, 0x83
NBANKS = 256

def run(*cmd):
    print("+", " ".join(cmd)); subprocess.run(cmd, check=True, cwd=ROOT)

def write_font(font):
    widths = bytes(font[c][1] for c in range(0x20, 0x7F))
    data = b"".join(bytes(font[c][0]) for c in range(0x20, 0x7F))
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

def main():
    os.makedirs(BUILD, exist_ok=True)
    rom = bytearray(open(ORIG, "rb").read())
    rom += b"\xFF" * (NBANKS * 0x4000 - len(rom))
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
    open(OUT, "wb").write(rom)
    run("rgbfix", "-v", "build/XinFengShenBang_en.gbc")
    print(stats)

if __name__ == "__main__":
    main()

"""Compile font/font.txt into 1bpp glyph data (16 rows x 8px) plus widths."""
import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP=3   # vertical offset of glyph row 0 within the 16px cell
SPACING=1
def load(path=os.path.join(ROOT,"font","font.txt")):
    glyphs={}; cur=None
    for line in open(path):
        line=line.rstrip("\n")
        if line.startswith("char "):
            cur=int(line.split()[1],16); glyphs[cur]=[]
        elif cur is not None and line:
            glyphs[cur].append(line)
    out={}
    for c,rows in glyphs.items():
        w=len(rows[0]); data=[0]*16
        for r,row in enumerate(rows):
            v=0
            for x,p in enumerate(row):
                if p=="#": v|=0x80>>x
            data[TOP+r]=v
        adv = w+SPACING
        out[c]=(data,adv)
    return out
def text_width(s, font):
    return sum(font[ord(ch)][1] for ch in s)

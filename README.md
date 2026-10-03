# Xin Feng Shen Bang (新封神榜) — English translation

English translation patch for the Chinese GBC RPG *Xin Feng Shen Bang*, with a
variable-width, mixed-case font.

## Building

Requirements: Python 3, [RGBDS](https://rgbds.gbdev.io/) (`rgbasm`, `rgblink`, `rgbfix`) on `PATH`.

```sh
python3 tools/build.py      # -> build/XinFengShenBang_en.gbc
```

The original ROM (`Xin Feng Shen Bang (Unlicensed, Chinese) (Multicart Rip) [Header Fix].gbc`)
must be in the repository root.

## How it works

* The ROM is expanded from 2 MB to 4 MB (MBC5). New banks carry the game's
  bank self-ID byte at `$7FFF`.
* `src/main.asm` hooks the dialogue engine in bank 0:
  * the message-start dispatcher (`$1C83`) looks each message up in a redirect
    table (banks `$81-$82`) and, if translated, maps the English copy instead;
  * the glyph output path (`$1CC9`) is diverted to a VWF renderer (bank `$80`)
    while an English message is showing; untranslated text still uses the
    original 16x16 Chinese renderer;
  * speaker names (`$1E4B`) are rendered with the VWF from an English table;
  * the shared Yes/No and Items/Treasures choice strings have English copies.
* The VWF draws 1bpp glyphs into a 2-cell WRAM buffer and uploads cells with
  the game's own HBlank-safe copier, reusing the original 16x16 cell/tile layout
  of the text box (7 cells x 2 lines for dialogue, 4 cells for names).
* `tools/build.py` compiles `font/font.txt`, assembles the hacks, word-wraps
  and paginates the English script by pixel width (`tools/script.py`), packs it
  into banks `$83+`, writes the lookup tables and fixes the checksums.

## Files

| Path | Contents |
|---|---|
| `font/font.txt` | VWF font (original design), one ASCII-art glyph per character |
| `script/dialogue/*.json` | English dialogue, keyed by original `bank:address` |
| `script/names_en.txt` | Speaker names (index = original name-table index) |
| `script/glossary.md` | Translation glossary |
| `tools/glyph_table.json` | Transcription of the original 2,189-glyph Chinese font |
| `tools/textdump.py` | Parser for the original script format |

## Status

* Dialogue (3,985 messages): translated and inserted.
* Menus, item/treasure names and descriptions, battle text: not yet translated.

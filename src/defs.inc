; Shared constants for the translation hacks.

DEF BANK_VWF     EQU $80     ; VWF renderer, font, speaker names
DEF BANK_LOOKUP  EQU $81     ; message redirect table
DEF FIRST_TEXT_BANK EQU $83  ; English script banks start here ($81-$82: lookup)
DEF LOOKUP_INDEX EQU $4000

DEF BODY_CELLS   EQU 7       ; 16px cells per dialogue line (112px)
DEF NAME_CELLS   EQU 4       ; 16px cells in the speaker name field (64px)
DEF BATTLE_INDENT EQU 4     ; left margin of battle message lines (px)

; WRAM (verified unused by the original game)
DEF wEnglish     EQU $D780   ; 1 while an English message is being shown
DEF wOrigBank    EQU $D781
DEF wOrigPtr     EQU $D782   ; 2 bytes
DEF wVwfX        EQU $D784   ; pen x within the current line
DEF wCurCell     EQU $D785   ; cell held in wCellBuf[0..31]
DEF wTileBase    EQU $D786   ; first tile of cell 0
DEF wPlaceMap    EQU $D787   ; nonzero: place tilemap entries for new cells
DEF wMaxCells    EQU $D788
DEF wAdv         EQU $D789
DEF wDidPlace    EQU $D78A   ; a frame wait already happened this glyph
DEF wPlaced      EQU $D78B   ; bitmask of cells placed on this line
DEF wSndToggle   EQU $D78C
DEF wEnglish2    EQU $D78D   ; 1 while an English menu/battle string is shown
DEF wD055Exp     EQU $D78E   ; [$D055] value left by the last VWF glyph
DEF wTargetCell  EQU $D78F
DEF wLineCell    EQU $D7D0   ; system 2: cell offset of the current line
DEF wEnglish3    EQU $D7D1   ; system 3 (location banner) English flag
DEF wStrTop      EQU $D7D2   ; system 2: string began its own slot
DEF wStrDepth    EQU $D7D3   ; system 2 nesting depth
DEF wIndent      EQU $D7D4   ; system 2: pen indent for fresh slots (battle box)
DEF wStr3Buf     EQU $D7D5   ; 43 bytes: English location string copy
DEF wCellBuf     EQU $D790   ; 64 bytes: current cell + next cell

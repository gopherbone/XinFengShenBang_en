; Xin Feng Shen Bang - English translation hacks
; Assembled with RGBDS and linked as an overlay onto the expanded ROM.

INCLUDE "src/defs.inc"

; =====================================================================
; Bank 0 patches
; =====================================================================

; --- Message start dispatcher (orig $1C83-$1C95) -----------------------
; Same four bank sources as the original, but all funnel into
; Hook_MsgStart, which redirects translated messages to the English banks.
SECTION "MsgDispatch", ROM0[$1C83]
MsgDispatch:
    ldh a, [$FFB6]
    jr .go
    ldh a, [$FFBF]
    jr .go
    ldh a, [$FFC2]
    jr .go
    ld a, [$DB25]
.go
    call Hook_MsgStart      ; $1C92 (replaces rst $20)
    push hl                 ; $1C95 ($1C96 stays "pop hl", the loop head)

; --- Glyph output (orig $1CC9: ld [$d052], a) --------------------------
SECTION "CharPatch", ROM0[$1CC9]
    jp Hook_Char

; --- Speaker name renderer (orig $1E4B: ld a, $0d / rst $20) -----------
SECTION "NamePatch", ROM0[$1E4B]
    jp Hook_Name

; --- Message end (orig $1F0A: ld a, [$7fff]) ---------------------------
SECTION "EndPatch", ROM0[$1F0A]
    call Hook_End

; --- E7 substring pointer (orig $1FF5: ld hl, $2004) -------------------
SECTION "E7Patch", ROM0[$1FF5]
    call Hook_E7Ptr

; --- E3/EA/EB inserts (orig: call $471E / $47C9 / $4772, bank $1E code) ---
SECTION "E3Patch", ROM0[$1F33]
    call Hook_E3
SECTION "EAPatch2", ROM0[$2101]
    call Hook_EA2
SECTION "EBPatch", ROM0[$2111]
    call Hook_EB

; --- EF: end without closing box (orig $22DF: xor a / ldh [$bc],a / pop hl / ret)
SECTION "EFPatch", ROM0[$22DF]
    jp Hook_EF

; --- Menu/battle text interpreter (system 2) ---------------------------
; $08CA: string entry (orig: call $0299 / push hl / [loop at $08CE])
SECTION "Str2Patch", ROM0[$08CA]
    jp Hook_Str2
; $08DB: glyph output (orig: jp $0B02)
SECTION "Char2Patch", ROM0[$08DB]
    jp Hook_Char2
; $090B: control-code table entry for E1 (number), orig dw $09C1
SECTION "E1Patch", ROM0[$090B]
    dw Hook_E1
; Battle reward box template (bank $2D): the original leaves a 4-column
; hole after cell 1 for a fixed-position digit field. Make the 8 cells
; contiguous so English text and VWF digits flow in one line.
SECTION "RewardBoxRow1", ROMX[$7D5D], BANK[$2D]
    FOR I, 8
        db $31 + I * 4, $33 + I * 4
    ENDR
    db $71, $71
SECTION "RewardBoxRow2", ROMX[$7D71], BANK[$2D]
    FOR I, 8
        db $32 + I * 4, $34 + I * 4
    ENDR
    db $71, $71
; $0AE8: EA inline name substitution (orig: ld a, $0d / rst $20)
SECTION "EAPatch", ROM0[$0AE8]
    call Hook_EA

; --- Location-name banner (system 3, bank $0D) ----------------------------
; $0D:437C: load string pointer (orig: ld a,[hli] / ld h,[hl] / ld l,a)
SECTION "Str3Patch", ROMX[$437C], BANK[$0D]
    call Hook_Str3
; $0D:438D: glyph output (orig: call $05BB)
SECTION "Char3Patch", ROMX[$438D], BANK[$0D]
    call Hook_Char3

; =====================================================================
; Bank 0 hook code (free space at the end of bank 0)
; =====================================================================
SECTION "Bank0Hooks", ROM0[$3800]

; In: a = original text bank, hl = original message pointer.
; Out: bank mapped and hl set to the message to interpret.
Hook_MsgStart::
    ld [wOrigBank], a
    ld a, l
    ld [wOrigPtr], a
    ld a, h
    ld [wOrigPtr + 1], a
    call LookupMsg
    jr nc, .notFound
    ld b, a
    ld a, 1
    ld [wEnglish], a
    ld a, b
    rst $20
    ret
.notFound
    xor a
    ld [wEnglish], a
    ld a, [wOrigPtr]
    ld l, a
    ld a, [wOrigPtr + 1]
    ld h, a
    ld a, [wOrigBank]
    rst $20
    ret

; In: a = character byte (stack holds the text pointer).
Hook_Char::
    ld [$D052], a
    ld b, a
    ld a, [wEnglish]
    and a
    ld a, b
    jp z, $1CCC             ; original 16x16 glyph path
    ld a, [$7FFF]
    push af
    ld a, BANK_VWF
    rst $20
    call VWF_Char
    pop af
    rst $20
    jp $1C96

; Called from the name routine with bank $0A mapped; must return with $0A.
Hook_Name::
    ld a, [wEnglish]
    and a
    jr z, .orig
    ld a, BANK_VWF
    rst $20
    call VWF_Name
    ld a, $0A
    rst $20
    ret
.orig
    ld a, $0D
    rst $20
    jp $1E4E

; --- System 2 hooks -----------------------------------------------------
; Entry of the menu/battle interpreter. Strings can nest (names inserted by
; control codes call back in here), so the caller's bank and the English
; flag are saved and restored around each string.
Hook_Str2::
    call $0299
    ld a, [$7FFF]
    push af
    ld a, [wEnglish2]
    push af
    ld a, [wStrTop]
    push af
    ld a, [wStrDepth]       ; only outermost strings pad their slot
    inc a
    ld [wStrDepth], a
    dec a
    ld a, 0
    jr nz, .nested
    ld [wIndent], a         ; outermost string: no indent until it asks
    inc a
.nested
    ld [wStrTop], a
    ld a, [$7FFF]
    ld [wOrigBank], a
    ld a, l
    ld [wOrigPtr], a
    ld a, h
    ld [wOrigPtr + 1], a
    call LookupMsg
    jr nc, .notFound
    ld b, a
    ld a, 1
    ld [wEnglish2], a
    ld a, b
    rst $20
    jr .run
.notFound
    xor a
    ld [wEnglish2], a
    ld a, [wOrigPtr]
    ld l, a
    ld a, [wOrigPtr + 1]
    ld h, a
    ld a, [wOrigBank]
    rst $20
.run
    call .interp
    ld a, [wStrDepth]
    dec a
    ld [wStrDepth], a
    pop af
    ld [wStrTop], a
    pop af
    ld [wEnglish2], a
    pop af
    rst $20
    ret
.interp
    push hl
    jp $08CE

Hook_Char2::
    ld b, a
    ld a, [wEnglish2]
    and a
    ld a, b
    jp z, $0B02
    ld [$D052], a
    cp " "
    jr nz, .go
    ld hl, sp + 0           ; space: copy the next word (text ptr on stack)
    ld a, [hli]             ; for the battle-line word-wrap lookahead
    ld h, [hl]
    ld l, a
    ld de, wLook
    ld c, LOOK_LEN
.look
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .look
.go
    ld a, [$7FFF]
    push af
    ld a, BANK_VWF
    rst $20
    call VWF_Char2
    pop af
    rst $20
    jp $08CE

; EA: insert the name at [$D037] (bank $0D). In English mode use the
; English copy from the VWF bank instead.
Hook_EA::
    ld a, [wEnglish2]
    and a
    jr nz, .en
    ld a, $0D
    rst $20
    ret
.en
    ld a, BANK_VWF
    rst $20
    jp VWF_MapName

; --- System 3 hooks (code runs from bank $0D, so English strings are ----
; copied into WRAM instead of switching banks under it) -----------------
Hook_Str3::
    ld a, [hli]
    ld h, [hl]
    ld l, a
    xor a
    ld [wEnglish3], a
    ld a, $0D
    ld [wOrigBank], a
    ld a, l
    ld [wOrigPtr], a
    ld a, h
    ld [wOrigPtr + 1], a
    call LookupMsg
    jr nc, .orig
    rst $20
    ld de, wStr3Buf
.copy
    ld a, [hli]
    ld [de], a
    inc de
    cp $ED
    jr nz, .copy
    push de
    ld a, $0D
    rst $20
    ld a, [wOrigPtr]        ; the byte after the original's $ED is a parameter
    ld l, a
    ld a, [wOrigPtr + 1]
    ld h, a
.find
    ld a, [hli]
    cp $ED
    jr nz, .find
    ld a, [hl]
    pop de
    ld [de], a
    ld a, 1
    ld [wEnglish3], a
    ld hl, wStr3Buf
    ret
.orig
    ld a, $0D
    rst $20
    ld a, [wOrigPtr]
    ld l, a
    ld a, [wOrigPtr + 1]
    ld h, a
    ret

Hook_Char3::
    ld b, a
    ld a, [wEnglish3]
    and a
    ld a, b
    jp z, $05BB
    ld [$D052], a
    ld a, [$7FFF]
    push af
    ld a, BANK_VWF
    rst $20
    call VWF_Char3
    pop af
    rst $20
    ret

; E1: print the 16-bit big-endian number at [$D031]. In English mode it
; is drawn inline with the VWF instead of the original fixed digit field.
Hook_E1::
    ld a, [wEnglish2]
    and a
    jp z, $09C1
    ld a, [$D031]
    ld h, a
    ld a, [$D032]
    ld l, a
    ld e, 0                 ; nonzero once a digit has been printed
    ld bc, -10000
    call .digit
    ld bc, -1000
    call .digit
    ld bc, -100
    call .digit
    ld bc, -10
    call .digit
    ld e, 1                 ; always print the ones digit
    ld bc, -1
    call .digit
    jp $08CE
.digit
    ld a, "0" - 1
.sub
    inc a
    add hl, bc
    jr c, .sub
    ld d, a                 ; undo the last subtraction
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ld a, d
    cp "0"
    jr nz, .emit
    ld a, e
    and a
    ret z                   ; skip leading zero
    ld a, d
.emit
    ld e, 1
    ld [$D052], a
    push hl
    push de
    ld a, [$7FFF]
    push af
    ld a, BANK_VWF
    rst $20
    call VWF_Char2
    pop af
    rst $20
    pop de
    pop hl
    ret

; E3/EA/EB call code in the message's own (original) bank that points
; [$CBFE] at an item name or digit string there, then the engine reads it
; and returns via E4. In English mode: run that code with the original bank
; mapped, then copy the English version of the insert into WRAM.
Hook_E3::
    ld de, $471E
    jr Hook_Insert
Hook_EA2::
    ld de, $47C9
    jr Hook_Insert
Hook_EB::
    ld de, $4772
Hook_Insert:
    ld a, [wEnglish]
    and a
    jr nz, .en
    push de                 ; original: just call it in the mapped bank
    ret
.en
    ld a, [$7FFF]
    ld [wSubBank], a
    ld a, [wOrigBank]
    rst $20
    call .callDE
    ld a, [$CBFE]
    ld [wOrigPtr], a
    ld a, [$CBFF]
    ld [wOrigPtr + 1], a
    call LookupMsg          ; English copy of the inserted string?
    jr nc, .done
    rst $20
    ld de, wStr3Buf
    ld c, 24
.copy
    ld a, [hli]
    cp $11                  ; drop slot-padding / pen codes
    jr c, .keep
    cp $20
    jr c, .skip
.keep
    ld [de], a
    inc de
    cp $E4
    jr z, .copied
.skip
    dec c
    jr nz, .copy
    ld a, $E4
    ld [de], a
.copied
    ld a, LOW(wStr3Buf)
    ld [$CBFE], a
    ld a, HIGH(wStr3Buf)
    ld [$CBFF], a
.done
    ld a, [wSubBank]
    rst $20
    ret
.callDE
    push de
    ret

Hook_End::
    xor a
    ld [wEnglish], a
    ld a, [$7FFF]
    ret

Hook_EF::
    xor a
    ld [wEnglish], a
    ldh [$FFBC], a
    pop hl
    ret

Hook_E7Ptr::
    ld hl, $2004
    ld a, [wEnglish]
    and a
    ret z
    ld hl, EnStrServe
    ret

; Message lookup. Index at BANK_LOOKUP:$4000, 256 x (db bank, dw ptr) per
; original bank (bank 0 = none). Subtable: dw count, then count x
; (dw orig_addr, db new_bank, dw new_addr). Tables are written by build.py.
; Out: carry set + a = new bank, hl = new pointer if found.
LookupMsg:
    ld a, BANK_LOOKUP
    rst $20
    ld a, [wOrigBank]
    ld l, a
    ld h, 0
    ld e, l
    ld d, h
    add hl, hl
    add hl, de
    ld de, LOOKUP_INDEX
    add hl, de
    ld a, [hli]
    and a
    ret z                   ; no table (carry clear)
    ld b, a
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld a, b
    rst $20
    ld a, [hli]
    ld c, a
    ld a, [hli]
    ld b, a
    ld a, [wOrigPtr]
    ld e, a
    ld a, [wOrigPtr + 1]
    ld d, a
.loop
    ld a, b
    or c
    ret z                   ; not found (carry clear)
    ld a, [hli]
    cp e
    jr nz, .skip
    ld a, [hl]
    cp d
    jr nz, .skip
    inc hl
    ld a, [hli]             ; new bank
    ld b, a
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld a, b
    scf
    ret
.skip
    inc hl
    inc hl
    inc hl
    inc hl
    dec bc
    jr .loop

; English substrings referenced by the script (bank 0, always mapped).
; Bytes $01-$0E move the pen to x = n*8 within the line.
EnStrYesNo::
    db 4, "Yes", 10, "No", $E6
EnStrServe::
    db 2, "Items", 8, "Treasure", $E8

; =====================================================================
; VWF renderer (bank BANK_VWF)
; =====================================================================
SECTION "VWF", ROMX[$4000], BANK[BANK_VWF]

; Body text character. [$D052] = byte, [$CBF0]=0 marks a fresh line,
; [$CBF1] = line (0/1).
VWF_Char::
    xor a
    ld [wDidPlace], a
    ld a, [$CBF0]
    and a
    jr nz, .cont
    ; start of a new line
    xor a
    ld [wVwfX], a
    ld [wCurCell], a
    ld [wPlaced], a
    call ClearCellBuf
    ld a, [$CBF1]
    and a
    ld a, $A8
    jr z, .tb
    ld a, $C4
.tb
    ld [wTileBase], a
    ld a, 1
    ld [wPlaceMap], a
    ld a, BODY_CELLS
    ld [wMaxCells], a
.cont
    ld a, [$D052]
    cp $20
    jr nc, .glyph
    ; $01-$1F: move pen to x = n*8
    add a
    add a
    add a
    call VWF_SetX
    jr .marker
.glyph
    call RenderGlyph
    ld a, [$D052]
    cp " "
    jr z, .marker
    ld a, [wSndToggle]
    xor 1
    ld [wSndToggle], a
    jr z, .marker
    ld a, $1D               ; text blip (every other glyph)
    call $2F19
.marker
    ld a, [wCurCell]
    inc a
    ld [$CBF0], a
    ldh a, [$FF95]
    bit 0, a                ; A held: no delay
    ret nz
    ld a, [wDidPlace]
    and a
    ret nz
    jp $0299                ; wait one frame

; a = new pen x. Moving forward to a later cell finishes the current cell
; and uploads blank tiles for every cell passed over, so shorter English
; strings also erase the rest of their original slot.
VWF_SetX:
    ld [wVwfX], a
    swap a
    and $0F
    ld [wTargetCell], a
.next
    ld a, [wTargetCell]
    ld b, a
    ld a, [wCurCell]
    cp b
    ret nc                  ; same cell (or backwards): keep the buffer
    inc a
    ld [wCurCell], a
    call ClearCellBuf
    ld a, [wCurCell]
    ld b, a
    ld a, [wTargetCell]
    cp b
    ret z                   ; arrived: new cell stays empty, not uploaded yet
    ld a, [wCurCell]
    ld hl, wCellBuf
    call UploadCell         ; blank intermediate cell
    jr .next

; Renders the name for speaker [$CBF7] into tiles $E0-$EF.
VWF_Name::
    xor a
    ld [wVwfX], a
    ld [wCurCell], a
    ld [wPlaceMap], a
    call ClearCellBuf
    ld a, $E0
    ld [wTileBase], a
    ld a, NAME_CELLS
    ld [wMaxCells], a
    ld a, [$CBF7]
    ld l, a
    ld h, 0
    add hl, hl
    ld de, NameTable
    add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a
.loop
    ld a, [hli]
    and a
    jr z, .done
    ld [$D052], a
    push hl
    call RenderGlyph
    pop hl
    jr .loop
.done
    ld a, BODY_CELLS
    ld [wMaxCells], a
    ret

; System 2 glyph. Slot tiles are [$D08B] + [$D055]; [$D055] counts tiles.
; Control bytes $01-$1F move to the start of cell n of the slot (used to
; start new lines in multi-line boxes); wLineCell is that cell offset.
VWF_Char2::
    ld a, [$D055]
    and a
    jr z, .fresh
    ld b, a
    ld a, [wD055Exp]
    cp b
    jr z, .cont
    ld a, b                 ; someone else advanced the slot: resume there
    srl a
    srl a
    jr .start
.fresh
    xor a
    ld [wLineCell], a
    ld [wCurCell], a
    ld a, [wIndent]         ; inserted names in an indented line keep it
    ld [wVwfX], a
    call ClearCellBuf
    jr .cont
.start
    ld [wLineCell], a
    xor a
    ld [wCurCell], a
    ld [wVwfX], a
    call ClearCellBuf
.cont
    xor a
    ld [wPlaceMap], a
    ld a, 16
    ld [wMaxCells], a
    ld a, [$D052]
    cp $20
    jr nc, .glyph
    cp $18
    jr nc, .pad
    cp $11
    jr z, .nudge
    cp $10
    jr nz, .jump
    ld a, [wLineCell]       ; $10: next line of an 8-cell-wide box
    add 8
.jump
    ld [wLineCell], a       ; $01-$0F: restart at cell n
    xor a
    ld [wCurCell], a
    ld [wVwfX], a
    call ClearCellBuf
    jr .done
.pad
    call VWF_Pad2
    jr .done
.nudge
    ld a, BATTLE_INDENT     ; $11: indent this line (and fresh slots in it)
    ld [wIndent], a
    ld a, [wVwfX]
    add BATTLE_INDENT
    ld [wVwfX], a
    jr .done
.glyph
    cp " "
    call z, WrapBattleLine  ; may start line 2 instead of drawing the space
    jr c, .done
    call SetTileBase2
    call RenderGlyph
.done
    ld a, [wVwfX]
    and $0F
    ld b, 0
    jr z, .exact
    inc b
.exact
    ld a, [wCurCell]
    add b
    ld b, a
    ld a, [wLineCell]
    add b
    add a
    add a
    ld [$D055], a
    ld [wD055Exp], a
    ret

; $18-$1F: blank the slot up to cell (n - $17), but only for a string that
; started its own slot (names inserted mid-sentence are left unpadded).
VWF_Pad2:
    ld a, [wStrTop]
    and a
    ret z
    ld a, [$D052]
    sub $17
    ld [wTargetCell], a
    call SetTileBase2
    ld a, [wVwfX]
    and $0F
    jr z, .loop             ; current cell holds no pixels yet: blank it too
    ld a, [wCurCell]
    inc a
    ld [wCurCell], a
.loop
    ld a, [wTargetCell]
    ld b, a
    ld a, [wCurCell]
    cp b
    jr nc, .end
    call ClearCellBuf
    ld a, [wCurCell]
    ld hl, wCellBuf
    call UploadCell
    ld a, [wCurCell]
    inc a
    ld [wCurCell], a
    jr .loop
.end
    ld a, [wCurCell]        ; continue from the target cell as a new "line"
    ld b, a
    ld a, [wLineCell]
    add b
    ld [wLineCell], a
    xor a
    ld [wCurCell], a
    ld [wVwfX], a
    jp ClearCellBuf

; At a space in an indented battle line (2 lines x BATTLE_LINE_CELLS cells),
; measure the next word from wLook; if it won't fit on line 1, move to the
; start of line 2 instead. Carry set = space consumed.
WrapBattleLine:
    ld a, [wIndent]
    and a
    ret z                   ; (carry clear) only battle message lines
    ld a, [wLineCell]
    cp BATTLE_LINE_CELLS
    ret nc                  ; already on line 2 (carry clear)
    ld hl, wLook
    ld b, 0                 ; word width
    ld c, LOOK_LEN
.measure
    ld a, [hli]
    cp $E0
    jr nc, .ctrl
    cp $21
    jr c, .measured         ; space or pen code ends the word
    sub $20
    ld e, a
    ld d, 0
    push hl
    ld hl, FontWidths
    add hl, de
    ld a, [hl]
    pop hl
    add b
    ld b, a
    dec c
    jr nz, .measure
    jr .measured
.ctrl
    cp $E4                  ; name/item inserts: assume a typical width
    jr z, .measured
    cp $ED
    jr z, .measured
    cp $E2
    jr z, .measured
    ld a, b
    add 48
    ld b, a
.measured
    ld a, [wLineCell]       ; pen position in the line
    swap a
    ld c, a
    ld a, [wVwfX]
    add c
    add 4                   ; the space itself
    add b
    jr c, .wrap
    cp BATTLE_LINE_CELLS * 16 + 1
    ccf
    ret nc                  ; fits: draw the space normally
.wrap
    ld a, BATTLE_LINE_CELLS
    ld [wLineCell], a
    xor a
    ld [wCurCell], a
    ld a, [wIndent]
    ld [wVwfX], a
    call ClearCellBuf
    scf
    ret

SetTileBase2:
    ld a, [wLineCell]
    add a
    add a
    ld b, a
    ld a, [$D08B]
    add b
    ld [wTileBase], a
    ret

; System 3 glyph: same slot logic as system 2, tiles start at $A8.
VWF_Char3::
    ld a, [$D08B]
    push af
    ld a, $A8
    ld [$D08B], a
    call VWF_Char2
    pop af
    ld [$D08B], a
    ret

; [$D037] = Chinese name pointer (bank $0D) -> English copy, if known.
VWF_MapName::
    ld a, [$D037]
    ld e, a
    ld a, [$D038]
    ld d, a
    ld hl, NameSrcTable
    ld bc, 0
.loop
    ld a, [hli]
    cp e
    jr nz, .next
    ld a, [hl]
    cp d
    jr z, .found
.next
    inc hl
    inc c
    ld a, c
    cp NAME_COUNT
    jr nz, .loop
    ld a, $0D               ; unknown: keep the original
    rst $20
    ret
.found
    ld hl, Name2Table
    add hl, bc
    add hl, bc
    ld a, [hli]
    ld [$D037], a
    ld a, [hl]
    ld [$D038], a
    ret

ClearCellBuf:
    ld hl, wCellBuf
    ld b, 64
    xor a
.l
    ld [hli], a
    dec b
    jr nz, .l
    ret

; Draws glyph [$D052] at wVwfX into the cell buffer, uploads the touched
; cells and advances the pen.
RenderGlyph:
    ld a, [$D052]
    sub $20
    ld e, a
    ld d, 0
    ld hl, FontWidths
    add hl, de
    ld a, [hl]
    ld [wAdv], a
    ld l, e
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, FontData
    add hl, de              ; hl = 16 glyph rows
    ld a, [wVwfX]
    and $0F
    ld c, a
    ld de, wCellBuf
    bit 3, c
    jr z, .d0
    ld de, wCellBuf + 16
.d0
    ld a, c
    and 7
    ld c, a                 ; bit shift
    ld b, 16
.row
    ld a, [hli]
    push hl
    push bc
    ld h, a
    ld l, 0
    ld a, c
    and a
    jr z, .noshift
.sh
    srl h
    rr l
    dec a
    jr nz, .sh
.noshift
    ld a, [de]
    or h
    ld [de], a
    push de
    ld a, e
    add 16
    ld e, a
    jr nc, .nc
    inc d
.nc
    ld a, [de]
    or l
    ld [de], a
    pop de
    inc de
    pop bc
    pop hl
    dec b
    jr nz, .row

    ld a, [wCurCell]
    ld hl, wCellBuf
    call UploadCell
    ld a, [wAdv]
    ld b, a
    ld a, [wVwfX]
    add b
    ld [wVwfX], a
    swap a
    and $0F
    ld b, a
    ld a, [wCurCell]
    cp b
    ret z
    ; crossed into the next cell
    ld a, [wVwfX]
    and $0F
    jr z, .noSpill
    ld a, [wCurCell]
    inc a
    ld hl, wCellBuf + 32
    call UploadCell
.noSpill
    ld hl, wCellBuf + 32
    ld de, wCellBuf
    ld b, 32
.cp
    ld a, [hl]
    ld [de], a
    xor a
    ld [hli], a
    inc de
    dec b
    jr nz, .cp
    ld a, [wCurCell]
    inc a
    ld [wCurCell], a
    ret

; a = cell index, hl = 32-byte 1bpp cell (TL,BL,TR,BR column order)
UploadCell:
    ld b, a
    ld a, [wMaxCells]
    dec a
    cp b
    ret c                   ; past the end of the text area
    ld a, b
    add a
    add a
    ld c, a
    ld a, [wTileBase]
    add c
    ld c, a                 ; c = first tile of the cell
    ld a, l
    ld [$D02B], a
    ld a, h
    ld [$D02C], a
    ld a, c
    swap a
    ld d, a
    and $0F
    cp $08
    jr nc, .hi
    or $90                  ; tiles $00-$7F live at $9000 (signed mode)
    jr .addr
.hi
    or $80
.addr
    ld [$D0E5], a
    ld a, d
    and $F0
    ld [$D0E4], a
    ld a, 4
    ld [$CBF2], a
    push bc
    call $2C38
    pop bc
    ld a, [wPlaceMap]
    and a
    ret z
    ; place the cell's tilemap entries once per line
    ld a, b
    ld hl, BitTable
    add l
    ld l, a
    jr nc, .nc
    inc h
.nc
    ld a, [wPlaced]
    ld e, a
    and [hl]
    ret nz
    ld a, e
    or [hl]
    ld [wPlaced], a
    ; fall through

; b = cell index, c = first tile. Mirrors the original $1D47/$1D02 path.
PlaceCell:
    ld a, [$D0CD]
    ld l, a
    ld a, [$D0CE]
    ld h, a
    ld de, $0041
    add hl, de
    ld a, b
    add a
    ld e, a
    ld a, [$CBF1]
    and a
    jr z, .l0
    ld a, $28
    add e
    ld e, a
.l0
    ld d, 0
    add hl, de
    ld de, $0014
    ld a, c
    push hl
    ld [hl], a
    inc a
    add hl, de
    ld [hl], a
    inc a
    pop hl
    inc hl
    ld [hl], a
    inc a
    add hl, de
    ld [hl], a
    ld a, b
    ld [$CBF0], a
    ld a, c
    ld [$CBF3], a
    call $1D02
    ld a, 1
    ld [$CBF4], a
    call $0299
    ld a, 1
    ld [wDidPlace], a
    ret

BitTable:
    db $01, $02, $04, $08, $10, $20, $40, $80

FontWidths::
    INCBIN "build/font_widths.bin"
FontData::
    INCBIN "build/font_data.bin"

INCLUDE "build/names.asm"

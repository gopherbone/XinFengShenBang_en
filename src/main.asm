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

; --- EF: end without closing box (orig $22DF: xor a / ldh [$bc],a / pop hl / ret)
SECTION "EFPatch", ROM0[$22DF]
    jp Hook_EF

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
    db 3, "Yes", 9, "No", $E6
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

; a = new pen x
VWF_SetX:
    ld [wVwfX], a
    swap a
    and $0F
    ld b, a
    ld a, [wCurCell]
    cp b
    ret z
    ld a, b
    ld [wCurCell], a
    jp ClearCellBuf

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
    or $80
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

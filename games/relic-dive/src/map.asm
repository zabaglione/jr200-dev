; SPDX-License-Identifier: MIT
; Packed terrain (even X in low nibble), independent explored and visible masks.
; A=x B=y. CELL returns logical terrain|explored in A; X=packed address.
; Terrain-only lookup for line of sight; no explored-mask lookup.
TERRAIN_CELL:
    STAA [CELL_X]
    STAB [CELL_Y]
    TBA
    LSRA
    LSRA
    LSRA
    ADDA FLOORS >> 8
    STAA [CELL_PACKED]
    LDAA [CELL_Y]
    ASLA
    ASLA
    ASLA
    ASLA
    ASLA
    STAA [CELL_PACKED + 1]
    LDAA [CELL_X]
    LSRA
    ORAA [CELL_PACKED + 1]
    STAA [CELL_PACKED + 1]
    LDX [CELL_PACKED]
    LDAA [X]
    LDAB [CELL_X]
    BITB 1
    BEQ CELL_LOW
    LSRA
    LSRA
    LSRA
    LSRA
CELL_LOW:
    ANDA 15
    RTS
CELL:
    JSR TERRAIN_CELL
    STAA [CELL_VALUE]
    LDAA [CELL_X]
    LDAB [CELL_Y]
    JSR BIT_ADDRESS
    LDAA [X]
    BITA [CELL_MASK]
    BEQ CELL_UNSEEN
    LDAA [CELL_VALUE]
    ORAA 128
    BRA CELL_RETURN
CELL_UNSEEN:
    LDAA [CELL_VALUE]
CELL_RETURN:
    LDX [CELL_PACKED]
    TSTA
    RTS
WRITE_CELL:
    LDAB 1
    STAB [VIS_DIRTY]
    ANDA 15
    STAA [CELL_VALUE]
    LDX [CELL_PACKED]
    LDAB [CELL_X]
    BITB 1
    BEQ WRITE_CELL_LOW
    ASLA
    ASLA
    ASLA
    ASLA
    STAA [CELL_VALUE]
    LDAA [X]
    ANDA 15
    BRA WRITE_CELL_MERGE
WRITE_CELL_LOW:
    LDAA [X]
    ANDA 0xF0
WRITE_CELL_MERGE:
    ORAA [CELL_VALUE]
    STAA [X]
    RTS
; A=x B=y -> X=explored byte, CELL_MASK=bit, CELL_BIT_PTR=X.
BIT_ADDRESS:
    STAA [CELL_INDEX + 1]
    ASLB
    ASLB
    ASLB
    LSRA
    LSRA
    LSRA
    ABA
    STAA [CELL_BIT_PTR + 1]
    LDAA SEEN >> 8
    STAA [CELL_BIT_PTR]
    LDAA [CELL_INDEX + 1]
    ANDA 7
    STAA [INDEX_OFFSET + 1]
    LDX BIT_MASKS
    ADDX16 INDEX_OFFSET
    LDAA [X]
    STAA [CELL_MASK]
    LDX [CELL_BIT_PTR]
    RTS
MARK_SEEN:
    LDX [CELL_BIT_PTR]
    LDAA [X]
    ORAA [CELL_MASK]
    STAA [X]
    RTS
VISIBLE_CELL:
    JSR BIT_ADDRESS
    INC [CELL_BIT_PTR]
    LDX [CELL_BIT_PTR]
    LDAA [X]
    ANDA [CELL_MASK]
    STAA [VISIBLE_VALUE]
    LDX VISIBLE_VALUE
    RTS
MARK_VISIBLE:
    JSR BIT_ADDRESS
    INC [CELL_BIT_PTR]
    LDX [CELL_BIT_PTR]
    LDAA [X]
    ORAA [CELL_MASK]
    STAA [X]
    RTS
BIT_MASKS: .db 1,2,4,8,16,32,64,128

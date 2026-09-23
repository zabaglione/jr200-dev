; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc.
; All routines preserve S. They do not change interrupt vectors or masks.
;
; jr_screen_clear
;   Fills all 32 x 24 cells with standard spaces, white on black.
;   Clobbers A and X. Preserves B.
;
; jr_screen_put
;   Input: X = address in JR200_SCREEN_CODES, A = character, B = attribute.
;   Clobbers A and X. Preserves B. Not reentrant.
;
; jr_pcg_define
;   Input: X = address of eight source bytes, A = code 0x00-0x1f or 0x80-0x9f.
;   Output: carry clear on success, carry set for an unsupported code.
;   Clobbers A, B, and X. Not reentrant.

jr_screen_clear:
        LDX     JR200_SCREEN_CODES
        LDAA    JR200_CHAR_SPACE
jr_screen_clear_codes:
        STAA    [X]
        INX
        CPX     JR200_SCREEN_CODES_END
        BNE     jr_screen_clear_codes
        LDX     JR200_SCREEN_ATTRIBUTES
        LDAA    JR200_ATTR_STANDARD_WHITE
jr_screen_clear_attributes:
        STAA    [X]
        INX
        CPX     JR200_SCREEN_ATTRIBUTES_END
        BNE     jr_screen_clear_attributes
        RTS

jr_screen_put:
        STX     [jr_screen_pointer]
        STAA    [X]
        LDAA    [jr_screen_pointer]
        ADDA    0x04
        STAA    [jr_screen_pointer]
        LDX     [jr_screen_pointer]
        STAB    [X]
        RTS

jr_pcg_define:
        STX     [jr_pcg_source]
        TAB
        ANDA    0x60
        BNE     jr_pcg_invalid
        TBA
        ANDA    0x1f
        ASLA
        ASLA
        ASLA
        STAA    [jr_pcg_destination + 1]
        LDAA    0xc0
        BITB    0x80
        BEQ     jr_pcg_bank_selected
        LDAA    0xc4
jr_pcg_bank_selected:
        STAA    [jr_pcg_destination]
        LDAB    8
jr_pcg_copy_loop:
        LDX     [jr_pcg_source]
        LDAA    [X]
        INX
        STX     [jr_pcg_source]
        LDX     [jr_pcg_destination]
        STAA    [X]
        INX
        STX     [jr_pcg_destination]
        DECB
        BNE     jr_pcg_copy_loop
        CLC
        RTS
jr_pcg_invalid:
        SEC
        RTS

jr_screen_pointer:
        .dw     0
jr_pcg_source:
        .dw     0
jr_pcg_destination:
        .dw     0

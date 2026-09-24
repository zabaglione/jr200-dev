; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc, session.inc and a page-aligned JR_SHADOW from the game:
;   JR_SHADOW          768 screen codes, followed by 768 attributes
; Drawing goes to the RAM shadow; jr_gfx_present copies it to VRAM in one
; pass so a frame never shows a half-drawn screen. Not re-entrant.
;
; jr_gfx_at
;   Input: A = column 0-31, B = row 0-23.
;   Output: X = JR_RT_CURSOR = shadow code address. Clobbers A and B.
; jr_gfx_putc
;   Input: A = code. Writes A and JR_RT_COLOR at the cursor, then advances.
;   Preserves A and B. Clobbers X.
; jr_gfx_text
;   Input: X = zero-terminated string. Writes at the cursor with JR_RT_COLOR.
;   Clobbers A and X. Preserves B.
; jr_gfx_dec2 / jr_gfx_dec3
;   Input: A = value (dec2 expects 0-99). Writes 2 or 3 digits at the cursor.
;   Clobbers A, B and X.
; jr_gfx_tile
;   Input: A = first of four consecutive codes (top-left, top-right,
;   bottom-left, bottom-right). Draws a 2x2 tile at the cursor with
;   JR_RT_COLOR and advances the cursor by two columns. Clobbers A, B and X.
; jr_gfx_fill
;   Input: A = code, B = attribute for all 768 cells. Clobbers X.
; jr_gfx_present
;   Copies the shadow to $C100-$C3FF and $C500-$C7FF. IRQs must be masked
;   (jr_session_enter does this) because S walks the shadow. Clobbers A and X.

JR_RT_CURSOR:       .equ    JR_RT + 15
JR_RT_COLOR:        .equ    JR_RT + 17
JR_RT_TMP:          .equ    JR_RT + 18
JR_RT_NUM:          .equ    JR_RT + 20
JR_RT_DIGIT:        .equ    JR_RT + 21
JR_RT_TEXT:         .equ    JR_RT + 22
JR_RT_PRESENT_SP:   .equ    JR_RT + 24

JR_SHADOW_ATTRS:    .equ    JR_SHADOW + 0x300

jr_gfx_at:
        STAA    [JR_RT_TMP + 1]
        TBA
        LSRA
        LSRA
        LSRA
        ANDB    7
        ASLB
        ASLB
        ASLB
        ASLB
        ASLB
        ADDB    [JR_RT_TMP + 1]
        ADDA    JR_SHADOW >> 8
        STAA    [JR_RT_CURSOR]
        STAB    [JR_RT_CURSOR + 1]
        LDX     [JR_RT_CURSOR]
        RTS

jr_gfx_putc:
        LDX     [JR_RT_CURSOR]
        STAA    [X]
        PSHA
        LDAA    [JR_RT_CURSOR]
        ADDA    3
        STAA    [JR_RT_TMP]
        LDAA    [JR_RT_CURSOR + 1]
        STAA    [JR_RT_TMP + 1]
        LDX     [JR_RT_TMP]
        LDAA    [JR_RT_COLOR]
        STAA    [X]
        LDX     [JR_RT_CURSOR]
        INX
        STX     [JR_RT_CURSOR]
        PULA
        RTS

jr_gfx_text:
        STX     [JR_RT_TEXT]
jr_gfx_text_loop:
        LDX     [JR_RT_TEXT]
        LDAA    [X]
        BEQ     jr_gfx_text_done
        INX
        STX     [JR_RT_TEXT]
        JSR     jr_gfx_putc
        BRA     jr_gfx_text_loop
jr_gfx_text_done:
        RTS

jr_gfx_dec3:
        CLRB
jr_gfx_dec3_hundreds:
        CMPA    100
        BCS     jr_gfx_dec3_put
        SUBA    100
        INCB
        BRA     jr_gfx_dec3_hundreds
jr_gfx_dec3_put:
        STAA    [JR_RT_NUM]
        TBA
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    [JR_RT_NUM]
jr_gfx_dec2:
        CLRB
jr_gfx_dec2_tens:
        CMPA    10
        BCS     jr_gfx_dec2_put
        SUBA    10
        INCB
        BRA     jr_gfx_dec2_tens
jr_gfx_dec2_put:
        STAA    [JR_RT_NUM]
        TBA
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    [JR_RT_NUM]
        ADDA    0x30
        JMP     jr_gfx_putc

jr_gfx_tile:
        STAA    [JR_RT_DIGIT]
        JSR     jr_gfx_putc
        INCA
        JSR     jr_gfx_putc
        LDX     [JR_RT_CURSOR]
        STX     [JR_RT_TEXT]
        LDAB    [JR_RT_CURSOR + 1]
        ADDB    30
        STAB    [JR_RT_CURSOR + 1]
        BCC     jr_gfx_tile_lower
        INC     [JR_RT_CURSOR]
jr_gfx_tile_lower:
        INCA
        JSR     jr_gfx_putc
        INCA
        JSR     jr_gfx_putc
        LDX     [JR_RT_TEXT]
        STX     [JR_RT_CURSOR]
        RTS

jr_gfx_fill:
        LDX     JR_SHADOW
jr_gfx_fill_codes:
        STAA    [X]
        INX
        CPX     JR_SHADOW_ATTRS
        BNE     jr_gfx_fill_codes
jr_gfx_fill_attrs:
        STAB    [X]
        INX
        CPX     JR_SHADOW_ATTRS + 0x300
        BNE     jr_gfx_fill_attrs
        RTS

jr_gfx_present:
        STS     [JR_RT_PRESENT_SP]
        LDS     JR_SHADOW - 1
        LDX     JR200_SCREEN_CODES
jr_gfx_present_codes:
        PULA
        STAA    [X]
        PULA
        STAA    [X + 1]
        PULA
        STAA    [X + 2]
        PULA
        STAA    [X + 3]
        PULA
        STAA    [X + 4]
        PULA
        STAA    [X + 5]
        PULA
        STAA    [X + 6]
        PULA
        STAA    [X + 7]
        INX
        INX
        INX
        INX
        INX
        INX
        INX
        INX
        CPX     JR200_SCREEN_CODES_END
        BNE     jr_gfx_present_codes
        LDX     JR200_SCREEN_ATTRIBUTES
jr_gfx_present_attrs:
        PULA
        STAA    [X]
        PULA
        STAA    [X + 1]
        PULA
        STAA    [X + 2]
        PULA
        STAA    [X + 3]
        PULA
        STAA    [X + 4]
        PULA
        STAA    [X + 5]
        PULA
        STAA    [X + 6]
        PULA
        STAA    [X + 7]
        INX
        INX
        INX
        INX
        INX
        INX
        INX
        INX
        CPX     JR200_SCREEN_ATTRIBUTES_END
        BNE     jr_gfx_present_attrs
        LDS     [JR_RT_PRESENT_SP]
        RTS

; jr_gfx_lines
;   Input: X = table of entries: .db column, row, attribute / .dw text,
;   ending with a column byte of 0xFF. Clobbers A, B and X.

JR_RT_LINES:        .equ    JR_RT + 40

jr_gfx_lines:
        STX     [JR_RT_LINES]
jr_gfx_lines_loop:
        LDX     [JR_RT_LINES]
        LDAA    [X]
        CMPA    0xff
        BEQ     jr_gfx_lines_done
        LDAB    [X + 2]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDX     [JR_RT_LINES]
        LDX     [X + 3]
        JSR     jr_gfx_text
        LDX     [JR_RT_LINES]
        INX
        INX
        INX
        INX
        INX
        STX     [JR_RT_LINES]
        BRA     jr_gfx_lines_loop
jr_gfx_lines_done:
        RTS

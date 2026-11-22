; SPDX-License-Identifier: BSD-3-Clause
; Requires gfx.inc or gfx_buffered.inc. Draw a diagram into the existing shadow.
; X points to runs of x, y, screen attribute, glyph count (1 or more), glyphs.
; Set bit 7 of y for 2x2 tiles. These advance two columns per glyph.
; Set x to 0xff to end the diagram. Attributes are passed through unchanged,
; including the hardware's PCG and multicolor semigraphics modes.
; Clobbers A, B, X, JR_RT_TABLE and JR_RT_LINES.
jr_guide_draw:
        LDAA    [X]
        CMPA    0xff
        BEQ     jr_guide_done
        STX     [JR_RT_TABLE]
        LDAB    [X + 2]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 1]
        STAB    [JR_RT_LINES]
        ANDB    0x7f
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        LDAB    [X + 3]
        INX
        INX
        INX
        INX
jr_guide_glyph:
        LDAA    [X]
        INX
        STX     [JR_RT_TABLE]
        TST     [JR_RT_LINES]
        BMI     jr_guide_tile
        JSR     jr_gfx_putc
        BRA     jr_guide_next
jr_guide_tile:
        JSR     jr_gfx_tile
jr_guide_next:
        LDX     [JR_RT_TABLE]
        DECB
        BNE     jr_guide_glyph
        BRA     jr_guide_draw
jr_guide_done:
        RTS

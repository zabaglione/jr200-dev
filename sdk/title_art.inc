; SPDX-License-Identifier: BSD-3-Clause
; Draw a packed 32 x 24 title to the target's code and attribute planes.
; X = asset. The first byte is the CRTC border colour. In the cell stream,
; 1..127 repeats one pair, 0x81..0xff is a literal run, and 0 ends.
; The generator supplies exactly 768 cells. Clobbers A, B, X and copy scratch.

JR_TITLE_RUN:       .equ    JR_RT_COUNT
JR_TITLE_CODE:      .equ    JR_RT_COUNT + 1
JR_TITLE_ATTR:      .equ    JR_RT_TABLE

jr_title_draw:
        LDAA    [X]
        STAA    [JR200_BORDER]
        STAA    [JR_RT_BORDER_ACTIVE]
        INX
        STX     [JR_RT_SRC]
        LDX     JR_TITLE_SCREEN
        STX     [JR_RT_DST]
        LDX     JR_TITLE_ATTRIBUTES
        STX     [JR_TITLE_ATTR]
jr_title_next:
        LDX     [JR_RT_SRC]
        LDAA    [X]
        BEQ     jr_title_done
        STAA    [JR_TITLE_RUN]
        INX
        STX     [JR_RT_SRC]
        TST     [JR_TITLE_RUN]
        BMI     jr_title_literal
        JSR     jr_title_pair
jr_title_repeat:
        JSR     jr_title_cell
        DEC     [JR_TITLE_RUN]
        BNE     jr_title_repeat
        BRA     jr_title_next
jr_title_literal:
        LDAA    [JR_TITLE_RUN]
        ANDA    0x7f
        STAA    [JR_TITLE_RUN]
jr_title_literal_next:
        JSR     jr_title_pair
        JSR     jr_title_cell
        DEC     [JR_TITLE_RUN]
        BNE     jr_title_literal_next
        BRA     jr_title_next
jr_title_done:
        RTS

jr_title_pair:
        LDX     [JR_RT_SRC]
        LDAA    [X]
        STAA    [JR_TITLE_CODE]
        LDAB    [X + 1]
        INX
        INX
        STX     [JR_RT_SRC]
        RTS

jr_title_cell:
        LDX     [JR_RT_DST]
        LDAA    [JR_TITLE_CODE]
        STAA    [X]
        INX
        STX     [JR_RT_DST]
        LDX     [JR_TITLE_ATTR]
        STAB    [X]
        INX
        STX     [JR_TITLE_ATTR]
        RTS

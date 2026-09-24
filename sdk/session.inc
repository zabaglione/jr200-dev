; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and these symbols from the game:
;   JR_SAVE          4096-byte buffer for the caller's PCG, screen and font RAM
;   JR_RT            64-byte runtime work area shared by the port modules
;   JR_STACK_TOP     highest byte of the game's own stack
;
; jr_session_enter
;   Call with JSR as the first action of the BASIC USR entry. Saves CC, the
;   caller S, key IRQ mask, key control port, PCG banks 0/1, screen codes/attributes and
;   character RAM $D000-$D7FF, masks IRQs, enables the Key-On status bit and
;   returns on the game's own stack. Clobbers A, B and X.
;
;   The border register is not readable, so sessions never change it.
;
; jr_session_leave
;   Jump (do not JSR) here to stop sound, restore everything saved by
;   jr_session_enter and RTS to the BASIC caller with its original S and CC.
;
; jr_copy
;   Input: JR_RT_SRC, JR_RT_DST, JR_RT_COUNT (non-zero 16-bit count).
;   Copies bytes upward. IRQs must be masked because S walks the source.
;   Output: JR_RT_COUNT = end of the destination (DST + count); JR_RT_SRC
;   and JR_RT_DST are unchanged. Clobbers A, B and X. Restores S.

JR_RT_SAVE_CC:      .equ    JR_RT + 0
JR_RT_SAVE_SP:      .equ    JR_RT + 1
JR_RT_SAVE_MASK:    .equ    JR_RT + 3
JR_RT_SAVE_KEYCTL:  .equ    JR_RT + 4
JR_RT_RETURN:       .equ    JR_RT + 5
JR_RT_SRC:          .equ    JR_RT + 7
JR_RT_DST:          .equ    JR_RT + 9
JR_RT_COUNT:        .equ    JR_RT + 11
JR_RT_TABLE:        .equ    JR_RT + 13
JR_RT_COPY_SP:      .equ    JR_RT + 44

JR_SAVE_PCG0:       .equ    JR_SAVE
JR_SAVE_CODES:      .equ    JR_SAVE + 0x100
JR_SAVE_PCG1:       .equ    JR_SAVE + 0x400
JR_SAVE_ATTRS:      .equ    JR_SAVE + 0x500
JR_SAVE_FONT:       .equ    JR_SAVE + 0x800

JR_CHARACTER_RAM:   .equ    0xd000

jr_session_enter:
        PULA
        PULB
        STAA    [JR_RT_RETURN]
        STAB    [JR_RT_RETURN + 1]
        TPA
        STAA    [JR_RT_SAVE_CC]
        SEI
        STS     [JR_RT_SAVE_SP]
        LDS     JR_STACK_TOP
        ; $C000-$C7FF is saved as one block: PCG0, codes, PCG1, attributes.
        LDX     JR200_PCG_BANK0
        STX     [JR_RT_SRC]
        LDX     JR_SAVE
        STX     [JR_RT_DST]
        LDX     0x0800
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDX     JR_CHARACTER_RAM
        STX     [JR_RT_SRC]
        LDX     JR_SAVE_FONT
        STX     [JR_RT_DST]
        LDX     0x0800
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDAA    [JR200_KEY_CONTROL]
        ANDA    0xef
        STAA    [JR_RT_SAVE_KEYCTL]
        LDAA    [JR200_KEY_IRQ_MASK]
        STAA    [JR_RT_SAVE_MASK]
        ORAA    1
        STAA    [JR200_KEY_IRQ_MASK]
        LDAA    [JR200_KEY_IRQ_STATUS]
        LDAA    [JR_RT_RETURN + 1]
        PSHA
        LDAA    [JR_RT_RETURN]
        PSHA
        RTS

jr_session_leave:
        SEI
        JSR     jr_sound_all_stop
        LDX     JR_SAVE
        STX     [JR_RT_SRC]
        LDX     JR200_PCG_BANK0
        STX     [JR_RT_DST]
        LDX     0x0800
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDX     JR_SAVE_FONT
        STX     [JR_RT_SRC]
        LDX     JR_CHARACTER_RAM
        STX     [JR_RT_DST]
        LDX     0x0800
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        ; Put the key control port back (twice, so the MCU sees no edge) and
        ; discard a Key-On event left by the exit key before BASIC resumes.
        LDAA    [JR_RT_SAVE_KEYCTL]
        STAA    [JR200_KEY_CONTROL]
        STAA    [JR200_KEY_CONTROL]
        LDAA    [JR200_KEY_IRQ_STATUS]
        LDAA    [JR_RT_SAVE_MASK]
        STAA    [JR200_KEY_IRQ_MASK]
        LDS     [JR_RT_SAVE_SP]
        LDAA    [JR_RT_SAVE_CC]
        TAP
        RTS

jr_copy:
        ; S walks the source (IRQs are masked by jr_session_enter).
        STS     [JR_RT_COPY_SP]
        LDAA    [JR_RT_DST]
        LDAB    [JR_RT_DST + 1]
        ADDB    [JR_RT_COUNT + 1]
        ADCA    [JR_RT_COUNT]
        STAA    [JR_RT_COUNT]
        STAB    [JR_RT_COUNT + 1]
        LDS     [JR_RT_SRC]
        DES
        LDX     [JR_RT_DST]
jr_copy_loop:
        PULA
        STAA    [X]
        INX
        CPX     [JR_RT_COUNT]
        BNE     jr_copy_loop
        LDS     [JR_RT_COPY_SP]
        RTS

; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc, session.inc and keyscan.inc. One-key held input with
; press, repeat and release events from the keyboard MCU, not its data latch.
; Call jr_keyscan_init, then jr_keyrepeat_init before the first poll. Poll at a
; regular game tick; the delay and period below are poll counts, not seconds.
;
; jr_keyrepeat_init: clears the previous key and countdown. Clobbers no regs.
; jr_keyrepeat_poll: A = raw current key (previous key on release), B = event:
;   0 none, 1 press, 2 repeat, 3 release. A key-to-key change reports only
;   the new press. A stale MCU response returns A = B = 0 without changing
;   repeat state. Clobbers A, B, X.
; Uses JR_RT + 47..49; no caller data may occupy those bytes.

JR_RT_REPEAT_PREV:    .equ    JR_RT + 47
JR_RT_REPEAT_COUNT:   .equ    JR_RT + 48
JR_RT_REPEAT_CURRENT: .equ    JR_RT + 49
JR_REPEAT_DELAY:      .equ    4
JR_REPEAT_PERIOD:     .equ    2
JR_REPEAT_PRESS:      .equ    1
JR_REPEAT_AGAIN:      .equ    2
JR_REPEAT_RELEASE:    .equ    3

jr_keyrepeat_init:
        CLR     [JR_RT_REPEAT_PREV]
        CLR     [JR_RT_REPEAT_COUNT]
        CLR     [JR_RT_REPEAT_CURRENT]
        RTS

jr_keyrepeat_poll:
        JSR     jr_keyscan
        BCC     jr_keyrepeat_fresh
        CLRA
        CLRB
        RTS
jr_keyrepeat_fresh:
        STAA    [JR_RT_REPEAT_CURRENT]
        CMPA    [JR_RT_REPEAT_PREV]
        BEQ     jr_keyrepeat_same
        LDAB    [JR_RT_REPEAT_PREV]
        STAA    [JR_RT_REPEAT_PREV]
        TSTA
        BNE     jr_keyrepeat_press
        CLR     [JR_RT_REPEAT_COUNT]
        TBA
        LDAB    JR_REPEAT_RELEASE
        RTS
jr_keyrepeat_press:
        LDAA    JR_REPEAT_DELAY
        STAA    [JR_RT_REPEAT_COUNT]
        LDAA    [JR_RT_REPEAT_CURRENT]
        LDAB    JR_REPEAT_PRESS
        RTS
jr_keyrepeat_same:
        TSTA
        BEQ     jr_keyrepeat_none
        DEC     [JR_RT_REPEAT_COUNT]
        BNE     jr_keyrepeat_none
        LDAA    JR_REPEAT_PERIOD
        STAA    [JR_RT_REPEAT_COUNT]
        LDAA    [JR_RT_REPEAT_CURRENT]
        LDAB    JR_REPEAT_AGAIN
        RTS
jr_keyrepeat_none:
        CLRB
        LDAA    [JR_RT_REPEAT_CURRENT]
        RTS

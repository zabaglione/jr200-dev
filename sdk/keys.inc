; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc. Key-On event input.
; The data latch keeps the last code after release, so these routines use
; only the Key-On status bit: one press produces one action. Reading the
; status acknowledges the event. They never report whether a key is held.
;
; jr_keys_poll
;   Output: A = action, B = raw key code of the event (0 when none).
;     0 none/other, 1 W (up), 2 S (down), 3 A (left), 4 D (right),
;     5 RETURN, 6 SPACE, JR_KEY_EXIT for ESC or CTRL+C.
;   Letters are case-insensitive. Preserves X and S.

JR_KEY_NONE:        .equ    0
JR_KEY_UP:          .equ    1
JR_KEY_DOWN:        .equ    2
JR_KEY_LEFT:        .equ    3
JR_KEY_RIGHT:       .equ    4
JR_KEY_CONFIRM:     .equ    5
JR_KEY_BACK:        .equ    6
JR_KEY_EXIT:        .equ    0x80

jr_keys_poll:
        CLRB
        LDAA    [JR200_KEY_IRQ_STATUS]
        BITA    1
        BEQ     jr_keys_poll_none
        LDAB    [JR200_KEY_DATA]
        TBA
        CMPA    0x1b
        BEQ     jr_keys_poll_exit
        CMPA    0x03
        BEQ     jr_keys_poll_exit
        CMPA    0x0d
        BEQ     jr_keys_poll_confirm
        CMPA    0x20
        BEQ     jr_keys_poll_back
        ORAA    0x20
        CMPA    0x77
        BEQ     jr_keys_poll_up
        CMPA    0x73
        BEQ     jr_keys_poll_down
        CMPA    0x61
        BEQ     jr_keys_poll_left
        CMPA    0x64
        BEQ     jr_keys_poll_right
jr_keys_poll_none:
        CLRA
        RTS
jr_keys_poll_up:
        LDAA    JR_KEY_UP
        RTS
jr_keys_poll_down:
        LDAA    JR_KEY_DOWN
        RTS
jr_keys_poll_left:
        LDAA    JR_KEY_LEFT
        RTS
jr_keys_poll_right:
        LDAA    JR_KEY_RIGHT
        RTS
jr_keys_poll_confirm:
        LDAA    JR_KEY_CONFIRM
        RTS
jr_keys_poll_back:
        LDAA    JR_KEY_BACK
        RTS
jr_keys_poll_exit:
        LDAA    JR_KEY_EXIT
        RTS

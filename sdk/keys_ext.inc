; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc. Key-On event input with game-defined extra actions.
; Drop-in replacement for keys.inc (do not include both): the same actions
; 1-6 and JR_KEY_EXIT, plus the game's game_key_table, a list of
; (lower-case key, action) byte pairs ending with 0, looked up for any other
; key. Actions 7-12 follow JR100dev: 7 X (alternate), 8 F, 9 Q, 10 E, 11 Z,
; 12 C; a game may map a key to any action above 6. sdk/port.inc passes such
; actions to game_act during play and treats them as "other" elsewhere.
;
; jr_keys_poll
;   Output: A = action, B = raw key code of the event (0 when none).
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
        STX     [JR_RT_KEY_X]
        LDX     game_key_table
jr_keys_poll_table:
        TST     [X]
        BEQ     jr_keys_poll_unmapped
        CMPA    [X]
        BEQ     jr_keys_poll_mapped
        INX
        INX
        BRA     jr_keys_poll_table
jr_keys_poll_mapped:
        LDAA    [X + 1]
        LDX     [JR_RT_KEY_X]
        RTS
jr_keys_poll_unmapped:
        LDX     [JR_RT_KEY_X]
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

JR_RT_KEY_X:        .equ    JR_RT + 54

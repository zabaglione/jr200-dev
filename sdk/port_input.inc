; SPDX-License-Identifier: BSD-3-Clause
; Navigation input for the buffered port and ranked runtimes. Each project
; reserves 23 bytes at JR_INPUT and supplies GAME_INPUT_POLICY (A -> queued
; action or zero). Menus use the raw keys and discard pending game actions.
; The FIFO keeps 15 events in order. New events are dropped if it is full.
; Captures are allowed with the normal CPU stack and never dispatch rules.

JR_INPUT_HEAD:      .equ    JR_INPUT
JR_INPUT_TAIL:      .equ    JR_INPUT + 1
JR_INPUT_EFFECT:    .equ    JR_INPUT + 2
JR_INPUT_QUEUE:     .equ    JR_INPUT + 3
JR_INPUT_SAVED_X:   .equ    JR_INPUT_QUEUE + 16
JR_INPUT_MODAL:     .equ    JR_INPUT_SAVED_X + 2
JR_INPUT_TURN:      .equ    JR_INPUT_MODAL + 1
JR_INPUT_MASK:      .equ    15

JR_INPUT_CHECKPOINT: .macro
        JSR     jr_input_capture
        .end
JR_INPUT_RESET_HOOK:     .macro
        JSR     jr_input_reset
        .end
JR_INPUT_BEGIN:     .macro
        INC     [JR_INPUT_EFFECT]
        .end
JR_INPUT_END:       .macro
        DEC     [JR_INPUT_EFFECT]
        .end

JR_INPUT_MODAL_BEGIN: .macro
        JSR     jr_input_reset
        INC     [JR_INPUT_MODAL]
        .end
JR_INPUT_MODAL_END:   .macro
        CLR     [JR_INPUT_MODAL]
        .end

JR_INPUT_ACTION_BEGIN: .macro
        JSR     jr_input_begin_turn
        .end
JR_INPUT_ACTION_END:   .macro
        CLR     [JR_INPUT_TURN]
        .end

jr_input_begin_turn:
        CMPA    JR_KEY_RIGHT
        BLS     jr_input_turn_ready
        INC     [JR_INPUT_TURN]
jr_input_turn_ready:
        RTS

jr_input_reset:
        CLR     [JR_INPUT_HEAD]
        CLR     [JR_INPUT_TAIL]
        CLR     [JR_INPUT_EFFECT]
        CLR     [JR_INPUT_MODAL]
        CLR     [JR_INPUT_TURN]
        RTS

jr_input_read:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_input_menu_read
        JSR     jr_input_capture
        CLRB
        LDAA    [JR_INPUT_HEAD]
        CMPA    [JR_INPUT_TAIL]
        BEQ     jr_input_empty
        LDX     JR_INPUT_QUEUE
        JSR     jr_add_x_a
        LDAA    [JR_INPUT_HEAD]
        INCA
        ANDA    JR_INPUT_MASK
        STAA    [JR_INPUT_HEAD]
        LDAA    [X]
        RTS
jr_input_empty:
        CLRA
        RTS
jr_input_menu_read:
        JSR     jr_input_reset
        JMP     jr_keys_poll

jr_input_wait:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_input_wait_raw
        JSR     jr_input_capture
        CLRA
        RTS
jr_input_wait_raw:
        JMP     jr_keys_poll

; Take the Key-On latch before a subsequent key can overwrite it.
; Preserve A, B, X and CC at every graphics checkpoint.
jr_input_capture:
        PSHA
        TPA
        PSHA
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_input_capture_done
        TST     [JR_INPUT_MODAL]
        BNE     jr_input_capture_done
        LDAA    [JR200_KEY_IRQ_STATUS]
        BITA    1
        BEQ     jr_input_capture_done
        PSHB
        JSR     jr_keys_decode
        TSTA
        BEQ     jr_input_restore_b
        CMPA    JR_KEY_EXIT
        BNE     jr_input_capture_action
        JMP     jr_session_leave
jr_input_capture_action:
        STX     [JR_INPUT_SAVED_X]
        JSR     GAME_INPUT_POLICY
        TSTA
        BEQ     jr_input_restore_x
        TAB
        LDAA    [JR_INPUT_TAIL]
        INCA
        ANDA    JR_INPUT_MASK
        CMPA    [JR_INPUT_HEAD]
        BEQ     jr_input_restore_x
        PSHA
        LDX     JR_INPUT_QUEUE
        LDAA    [JR_INPUT_TAIL]
        JSR     jr_add_x_a
        STAB    [X]
        PULA
        STAA    [JR_INPUT_TAIL]
jr_input_restore_x:
        LDX     [JR_INPUT_SAVED_X]
jr_input_restore_b:
        PULB
jr_input_capture_done:
        PULA
        TAP
        PULA
        RTS

; Directions can wait through an effect. Confirm, restart and other commands
; are only collected during ordinary play, so they cannot confirm the result
; of a turn or a dialog that has not yet appeared.
jr_input_default_policy:
        CMPA    JR_KEY_RIGHT
        BLS     jr_input_allowed
        TST     [JR_INPUT_EFFECT]
        BNE     jr_input_reject
        TST     [JR_INPUT_TURN]
        BEQ     jr_input_allowed
jr_input_reject:
        CLRA
jr_input_allowed:
        RTS

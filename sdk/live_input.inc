; SPDX-License-Identifier: BSD-3-Clause
; Opt-in input buffering for port.inc games with long draws and effects.
; The game supplies game_init_state, a nonzero GAME_RATE, GAME_SPACE_RESET
; set to 1, and reserves 21 bytes at JR_LIVE.
; Call jr_live_capture from long draws while the normal stack is active.
; Replace jr_test_animate with jr_live_animate to defer input during effects.
; The queue holds up to 15 actions, in order. If full, keep the oldest.
; Exit is immediate. Restart confirmation only accepts SPACE outside effects.

JR_LIVE_READ:       .equ    JR_LIVE
JR_LIVE_WRITE:      .equ    JR_LIVE + 1
JR_LIVE_EFFECT:     .equ    JR_LIVE + 2
JR_LIVE_QUEUE:      .equ    JR_LIVE + 3
JR_LIVE_MASK:       .equ    15
JR_LIVE_SAVED_X:    .equ    JR_LIVE_QUEUE + 16

; port.inc calls us after stage setup. Its menu loop resumes on stage exit.
game_init:
        JSR     jr_live_reset_queue
        JSR     game_init_state
        TST     [JR_TEST_QUIET]
        BNE     jr_live_done
jr_live_redraw:
        JSR     jr_live_render
jr_live_frame:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_live_capture
        LDAA    [JR_LIVE_READ]
        CMPA    [JR_LIVE_WRITE]
        BEQ     jr_live_tick
        LDX     JR_LIVE_QUEUE
        JSR     jr_add_x_a
        LDAA    [JR_LIVE_READ]
        INCA
        ANDA    JR_LIVE_MASK
        STAA    [JR_LIVE_READ]
        LDAA    [X]
        CMPA    JR_KEY_BACK
        BEQ     jr_live_restart
        JSR     game_act
        BRA     jr_live_after_step
jr_live_tick:
        INC     [JR_PORT_TICKS]
        LDAA    [JR_PORT_TICKS]
        CMPA    GAME_RATE
        BCS     jr_live_frame
        CLR     [JR_PORT_TICKS]
        JSR     game_tick
jr_live_after_step:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     jr_live_redraw
jr_live_reset_queue:
        CLR     [JR_LIVE_READ]
        CLR     [JR_LIVE_WRITE]
        CLR     [JR_LIVE_EFFECT]
jr_live_done:
        RTS

; Reset the current stage in place so repeated restarts do not grow the stack.
jr_live_restart:
        JSR     jr_live_reset_queue
        JSR     jr_port_confirm
        TSTA
        BEQ     jr_live_redraw
        JSR     jr_sfx_stop
        CLR     [JR_PORT_TICKS]
        CLR     [JR_PORT_LOSS]
        CLR     [JR_PORT_LOSS + 1]
        LDX     GAME_STATE
        CLRA
jr_live_clear_state:
        STAA    [X]
        INX
        CPX     GAME_STATE_END
        BNE     jr_live_clear_state
        JSR     game_init_state
        BRA     jr_live_redraw

jr_live_render:
        JSR     jr_live_capture
        JSR     game_draw
        JSR     jr_live_capture
        JSR     jr_gfx_present
        JMP     jr_live_capture

; Poll the hardware's single Key-On latch before another key can replace it.
; Preserve A, B, X and CC so a draw can call this with live registers.
jr_live_capture:
        PSHA
        PSHB
        TPA
        PSHA
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_live_capture_done
        TST     [JR_TEST_QUIET]
        BNE     jr_live_capture_done
        JSR     jr_keys_poll
        BEQ     jr_live_capture_done
        CMPA    JR_KEY_EXIT
        BNE     jr_live_capture_action
        JMP     jr_session_leave
jr_live_capture_action:
        CMPA    JR_KEY_BACK
        BNE     jr_live_enqueue
        TST     [JR_LIVE_EFFECT]
        BNE     jr_live_capture_done
jr_live_enqueue:
        TAB
        LDAA    [JR_LIVE_WRITE]
        INCA
        ANDA    JR_LIVE_MASK
        CMPA    [JR_LIVE_READ]
        BEQ     jr_live_capture_done
        PSHA
        STX     [JR_LIVE_SAVED_X]
        LDX     JR_LIVE_QUEUE
        LDAA    [JR_LIVE_WRITE]
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [JR_LIVE_SAVED_X]
        PULA
        STAA    [JR_LIVE_WRITE]
jr_live_capture_done:
        PULA
        TAP
        PULB
        PULA
        RTS

; A = total effect frames, including the draw. Rules resume after the hold.
jr_live_animate:
        TST     [JR_TEST_QUIET]
        BNE     jr_live_animate_return
        LDAB    [JR_PORT_MODE]
        CMPB    JR_MODE_PLAY
        BEQ     jr_live_animate_play
        JMP     jr_port_animate
jr_live_animate_play:
        SUBA    GAME_RENDER_FRAMES
        BCC     jr_live_animate_duration
        CLRA
jr_live_animate_duration:
        STAA    [JR_PORT_FRAMES]
        INC     [JR_LIVE_EFFECT]
        JSR     jr_live_render
jr_live_animate_wait:
        TST     [JR_PORT_FRAMES]
        BEQ     jr_live_animate_done
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_live_capture
        DEC     [JR_PORT_FRAMES]
        BRA     jr_live_animate_wait
jr_live_animate_done:
        CLR     [JR_LIVE_EFFECT]
jr_live_animate_return:
        RTS

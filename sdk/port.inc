; SPDX-License-Identifier: BSD-3-Clause
; Stage-based game loop shared by the JR100dev ports. Requires jr200.inc,
; session.inc, keys.inc, gfx.inc, frame.inc, math.inc, sound.inc and sfx.inc.
;
; Modes: 0 title, 1 play, 2 stage clear, 3 lost, 4 all clear, 5 help.
; Title: RETURN starts, any other key shows help; help returns on any key.
; Play: W/S/A/D/RETURN (and SPACE when GAME_SPACE_RESET is 0) go to
; game_act. SPACE with GAME_SPACE_RESET 1 opens the restart confirmation.
; Clear/lost/all-clear wait for RETURN (next stage / confirm retry / title).
; ESC or CTRL+C leaves through jr_session_leave from every wait loop.
; Key-On events that arrive during jr_port_animate/jr_port_hold are
; discarded (except exit) so an effect never confirms the next move.
;
; The game supplies:
;   GAME_LEVELS, GAME_RATE (frames per game_tick, 0 = none), GAME_SPACE_RESET,
;   GAME_STATE / GAME_STATE_END (cleared before each stage),
;   GAME_STATUS_ROW / GAME_STATUS_ATTR, GAME_RENDER_FRAMES (frames one
;   jr_port_render is counted as; jr_port_animate waits the rest), game_sfx_table (.dw 4 phrases:
;   move, use, win, lose), and routines game_draw_title, game_draw_help,
;   game_init, game_act (A = action), game_tick, game_draw (full screen).
; Game routines may clobber A, B and X; state lives in memory.
;
; jr_port_run      jump here after jr_session_enter and the game's setup
; jr_port_win      stage cleared (mode 2) with the win phrase
; jr_port_lose     X = message or 0 for the default; mode 3, lose phrase
; jr_port_sound    A = phrase index 0-3
; jr_port_render   game_draw, status line, present
; jr_port_animate  A = frames: render, then wait A - GAME_RENDER_FRAMES frames
; jr_port_hold     A = frames: wait without rendering

JR_PORT_MODE:       .equ    JR_RT + 32
JR_PORT_LEVEL:      .equ    JR_RT + 33
JR_PORT_ACTION:     .equ    JR_RT + 34
JR_PORT_TICKS:      .equ    JR_RT + 35
JR_PORT_CHOICE:     .equ    JR_RT + 36
JR_PORT_LOSS:       .equ    JR_RT + 37
JR_PORT_FRAMES:       .equ    JR_RT + 39
JR_PORT_RAW:        .equ    JR_RT + 42

JR_MODE_TITLE:      .equ    0
JR_MODE_PLAY:       .equ    1
JR_MODE_CLEAR:      .equ    2
JR_MODE_LOST:       .equ    3
JR_MODE_END:        .equ    4
JR_MODE_HELP:       .equ    5

JR_PORT_DIALOG_ATTR: .equ   0x0f

jr_port_run:
jr_port_title:
        CLR     [JR_PORT_MODE]
        JSR     jr_sfx_stop
        JSR     game_draw_title
        JSR     jr_gfx_present
jr_port_idle:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_keys_poll
        STAB    [JR_PORT_RAW]
        TSTA
        BNE     jr_port_dispatch
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_port_idle
        LDAA    GAME_RATE
        BEQ     jr_port_idle
        INC     [JR_PORT_TICKS]
        LDAA    [JR_PORT_TICKS]
        CMPA    GAME_RATE
        BCS     jr_port_idle
        CLR     [JR_PORT_TICKS]
        JSR     game_tick
        JSR     jr_port_render
        BRA     jr_port_idle

jr_port_dispatch:
        CMPA    JR_KEY_EXIT
        BNE     jr_port_dispatch_mode
        JMP     jr_session_leave
jr_port_dispatch_mode:
        STAA    [JR_PORT_ACTION]
        LDAB    [JR_PORT_MODE]
        BEQ     jr_port_title_input
        CMPB    JR_MODE_PLAY
        BEQ     jr_port_game_input
        CMPB    JR_MODE_HELP
        BEQ     jr_port_title
        CMPA    JR_KEY_CONFIRM
        BNE     jr_port_idle
        CMPB    JR_MODE_CLEAR
        BEQ     jr_port_advance
        CMPB    JR_MODE_LOST
        BEQ     jr_port_retry
        BRA     jr_port_title

jr_port_title_input:
        CMPA    JR_KEY_CONFIRM
        BEQ     jr_port_start
        LDAA    JR_MODE_HELP
        STAA    [JR_PORT_MODE]
        JSR     game_draw_help
        JSR     jr_gfx_present
        BRA     jr_port_idle

jr_port_start:
        CLR     [JR_PORT_LEVEL]
jr_port_new_level:
        LDX     GAME_STATE
        CLRA
jr_port_clear_state:
        STAA    [X]
        INX
        CPX     GAME_STATE_END
        BNE     jr_port_clear_state
        LDAA    JR_MODE_PLAY
        STAA    [JR_PORT_MODE]
        CLR     [JR_PORT_TICKS]
        CLR     [JR_PORT_LOSS]
        CLR     [JR_PORT_LOSS + 1]
        JSR     jr_sfx_stop
        JSR     game_init
        JSR     jr_port_render
        JMP     jr_port_idle

jr_port_advance:
        INC     [JR_PORT_LEVEL]
        LDAA    [JR_PORT_LEVEL]
        CMPA    GAME_LEVELS
        BCS     jr_port_new_level
        DEC     [JR_PORT_LEVEL]
        LDAA    JR_MODE_END
        STAA    [JR_PORT_MODE]
        JSR     jr_port_render
        JMP     jr_port_idle

jr_port_game_input:
        CMPA    JR_KEY_BACK
        BNE     jr_port_game_act
        LDAB    GAME_SPACE_RESET
        BNE     jr_port_retry
jr_port_game_act:
        LDAA    [JR_PORT_ACTION]
        JSR     game_act
        JSR     jr_port_render
        JMP     jr_port_idle

jr_port_retry:
        JSR     jr_port_confirm
        TSTA
        BNE     jr_port_new_level
        JSR     jr_port_render
        JMP     jr_port_idle

jr_port_render:
        JSR     game_draw
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     jr_port_render_present
        LDX     jr_port_status_clear
        CMPA    JR_MODE_CLEAR
        BEQ     jr_port_render_status
        LDX     jr_port_status_end
        CMPA    JR_MODE_LOST
        BNE     jr_port_render_status
        LDX     [JR_PORT_LOSS]
jr_port_render_status:
        STX     [JR_RT_TABLE]
        LDAA    GAME_STATUS_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    GAME_STATUS_ROW
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
jr_port_render_present:
        JMP     jr_gfx_present

jr_port_win:
        LDAA    JR_MODE_CLEAR
        STAA    [JR_PORT_MODE]
        LDAA    2
        BRA     jr_port_sound

jr_port_lose:
        CPX     0
        BNE     jr_port_lose_message
        LDX     jr_port_status_lose
jr_port_lose_message:
        STX     [JR_PORT_LOSS]
        LDAA    JR_MODE_LOST
        STAA    [JR_PORT_MODE]
        LDAA    3

jr_port_sound:
        ANDA    3
        ASLA
        LDX     game_sfx_table
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_sfx_play

jr_port_animate:
        SUBA    GAME_RENDER_FRAMES
        BCC     jr_port_animate_wait
        CLRA
jr_port_animate_wait:
        STAA    [JR_PORT_FRAMES]
        JSR     jr_port_render
        BRA     jr_port_wait
jr_port_hold:
        STAA    [JR_PORT_FRAMES]
jr_port_wait:
        TST     [JR_PORT_FRAMES]
        BEQ     jr_port_wait_done
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_keys_poll
        CMPA    JR_KEY_EXIT
        BNE     jr_port_wait_next
        JMP     jr_session_leave
jr_port_wait_next:
        DEC     [JR_PORT_FRAMES]
        BRA     jr_port_wait
jr_port_wait_done:
        RTS

; Output: A = 0 (NO, default and SPACE) or 1 (YES). Redraw after return.
jr_port_confirm:
        CLR     [JR_PORT_CHOICE]
jr_port_confirm_draw:
        LDAA    JR_PORT_DIALOG_ATTR
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    9
        JSR     jr_gfx_at
        LDAB    160
jr_port_confirm_blank:
        LDAA    0x20
        JSR     jr_gfx_putc
        DECB
        BNE     jr_port_confirm_blank
        LDX     jr_port_confirm_lines
        JSR     jr_gfx_lines
        LDAA    9
        TST     [JR_PORT_CHOICE]
        BEQ     jr_port_confirm_cursor
        LDAA    17
jr_port_confirm_cursor:
        LDAB    11
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        JSR     jr_gfx_present
jr_port_confirm_idle:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_keys_poll
        TSTA
        BEQ     jr_port_confirm_idle
        CMPA    JR_KEY_EXIT
        BNE     jr_port_confirm_key
        JMP     jr_session_leave
jr_port_confirm_key:
        CMPA    JR_KEY_BACK
        BEQ     jr_port_confirm_no
        CMPA    JR_KEY_CONFIRM
        BEQ     jr_port_confirm_done
        DECA
        ANDA    1
        STAA    [JR_PORT_CHOICE]
        BRA     jr_port_confirm_draw
jr_port_confirm_no:
        CLR     [JR_PORT_CHOICE]
jr_port_confirm_done:
        LDAA    [JR_PORT_CHOICE]
        RTS

jr_port_confirm_lines:
        .db     9, 10, JR_PORT_DIALOG_ATTR
        .dw     jr_port_confirm_question
        .db     10, 11, JR_PORT_DIALOG_ATTR
        .dw     jr_port_confirm_choices
        .db     2, 13, JR_PORT_DIALOG_ATTR
        .dw     jr_port_confirm_hint
        .db     0xff
jr_port_confirm_question:
        .db     "REALLY RESET?", 0
jr_port_confirm_choices:
        .db     "NO      YES", 0
jr_port_confirm_hint:
        .db     "A/D SELECT  RETURN CHOOSE", 0
jr_port_status_clear:
        .db     "CLEAR - RETURN FOR NEXT STAGE", 0
jr_port_status_lose:
        .db     "TRY AGAIN - RETURN TO RESTART", 0
jr_port_status_end:
        .db     "ALL STAGES CLEAR - THANK YOU", 0

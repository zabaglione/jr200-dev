; SPDX-License-Identifier: BSD-3-Clause
; Ranked forty-stage campaign loop for the JR100dev ports: a drop-in
; alternative to sdk/port.inc (do not include both) with the same jr_port_*
; routines, following upstream games/native/campaign_runtime.asm and
; password.asm (zabaglione/jr100dev). Requires jr200.inc, session.inc,
; keys_ext.inc (with x -> 7 and f -> 8 in game_key_table), gfx.inc,
; frame.inc, math.inc and sound.inc with sfx.inc or audio.inc.
;
; Modes: 0 title, 1 play, 2 stage clear, 4 all clear, 5 help, 6 stage map,
; 7 password. Title: RETURN plays the selected stage, F opens the map, X the
; password screen, any other key the help. Play: SPACE retry (confirmed),
; F map (confirmed), other actions go to game_act. Clear: RETURN next stage,
; SPACE retry, F map. Map: WASD select (wrapping), RETURN play, SPACE title,
; X password. Password: letters type, '-' or BACKSPACE erase, RETURN loads,
; X cancels; the code carries the stage and every stage's best rating.
; BEST survives retries, the title and the map; jr_port_run clears it.
; Forty stages (GAME_LEVELS 40) as upstream: the code holds twenty pairs.
;
; The game supplies, besides port.inc's GAME_* values and game_* routines:
;   JR_RANK (JR_RANK_SIZE bytes outside GAME_STATE), GAME_PASSWORD_TAG,
;   GAME_STAR_CODE (PCG code of a filled star, +1 an empty one; load
;   jr_rank_star_patterns there), GAME_STAR_ATTR, game_title_text (the
;   title, 0-terminated), game_level_par (A = stage -> A = par), and the
;   addresses RANK_MOVES, RANK_OVERFLOW, RANK_RUNES, RANK_STARS (in
;   GAME_STATE) and RANK_RUNE_A, RANK_RUNE_B, RANK_PAR (the stage's d[67],
;   d[68] and d[69]).
;
; jr_rank_spend    count one move (upstream spend_move)
; jr_rank_take     A = position: collect a rune there (upstream take_rune)
; jr_rank_clear    rate the stage, record BEST and win (upstream ranked_clear)
; jr_rank_hud      draw "MOV 000  PAR 000  RUNES 0/2" on row 20

JR_PORT_MODE:       .equ    JR_RT + 32
JR_PORT_LEVEL:      .equ    JR_RT + 33
JR_PORT_ACTION:     .equ    JR_RT + 34
JR_PORT_TICKS:      .equ    JR_RT + 35
JR_PORT_CHOICE:     .equ    JR_RT + 36
JR_PORT_LOSS:       .equ    JR_RT + 37
JR_PORT_FRAMES:     .equ    JR_RT + 39
JR_PORT_RAW:        .equ    JR_RT + 42

JR_MODE_TITLE:      .equ    0
JR_MODE_PLAY:       .equ    1
JR_MODE_CLEAR:      .equ    2
JR_MODE_LOST:       .equ    3
JR_MODE_END:        .equ    4
JR_MODE_HELP:       .equ    5
JR_MODE_MAP:        .equ    6
JR_MODE_PASSWORD:   .equ    7

JR_KEY_PASSWORD:    .equ    7
JR_KEY_MAP:         .equ    8

JR_PORT_DIALOG_ATTR: .equ   0x0f
JR_RANK_TEXT_ATTR:  .equ    0x07
JR_RANK_HEAD_ATTR:  .equ    0x06
JR_RANK_HINT_ATTR:  .equ    0x05
JR_RANK_CODE_ATTR:  .equ    0x04
JR_RANK_ERROR_ATTR: .equ    0x02

JR_RANK_BEST:       .equ    JR_RANK             ; 40 ratings
JR_RANK_REC:        .equ    JR_RANK + 40        ; 40 bytes of code work
JR_RANK_BUF:        .equ    JR_RANK + 80        ; up to 24 code values
JR_RANK_LEN:        .equ    JR_RANK + 104
JR_RANK_PREFIX:     .equ    JR_RANK + 105
JR_RANK_HEADER:     .equ    JR_RANK + 106
JR_RANK_LIMIT:      .equ    JR_RANK + 107
JR_RANK_INDEX:      .equ    JR_RANK + 108
JR_RANK_CRC:        .equ    JR_RANK + 109
JR_RANK_POS:        .equ    JR_RANK + 110
JR_RANK_VALUE:      .equ    JR_RANK + 111
JR_RANK_ERROR:      .equ    JR_RANK + 112
JR_RANK_BACK:       .equ    JR_RANK + 113
JR_RANK_COL:        .equ    JR_RANK + 114
JR_RANK_ROW:        .equ    JR_RANK + 115
JR_RANK_CELL:       .equ    JR_RANK + 116
JR_RANK_TOTAL:      .equ    JR_RANK + 117
JR_RANK_STARS_LEFT: .equ    JR_RANK + 118
JR_RANK_SIZE:       .equ    120

jr_port_run:
        LDX     JR_RANK_BEST
jr_port_run_clear:
        CLR     [X]
        INX
        CPX     JR_RANK_BEST + 40
        BNE     jr_port_run_clear
        CLR     [JR_PORT_LEVEL]
jr_port_title:
        CLR     [JR_PORT_MODE]
        JSR     jr_sfx_stop
        JSR     game_draw_title
        LDX     jr_rank_title_lines
        JSR     jr_gfx_lines
        LDAA    22
        JSR     jr_rank_show_code
        JSR     jr_gfx_present
jr_port_idle:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_keys_poll
        STAB    [JR_PORT_RAW]
        CMPA    JR_KEY_EXIT
        BNE     jr_port_idle_mode
        JMP     jr_session_leave
jr_port_idle_mode:
        PSHA
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PASSWORD
        PULA
        BNE     jr_port_idle_action
        TSTB
        BEQ     jr_port_idle
        JMP     jr_rank_password_key
jr_port_idle_action:
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
        STAA    [JR_PORT_ACTION]
        LDAB    [JR_PORT_MODE]
        CMPB    JR_MODE_HELP
        BEQ     jr_port_title
        CMPB    JR_MODE_MAP
        BNE     jr_port_dispatch_map
        JMP     jr_rank_map_input
jr_port_dispatch_map:
        CMPA    JR_KEY_MAP
        BNE     jr_port_dispatch_title
        CMPB    JR_MODE_PLAY
        BNE     jr_port_open_map
        JSR     jr_port_confirm
        TSTA
        BNE     jr_port_open_map
        JSR     jr_port_render
        JMP     jr_port_idle
jr_port_open_map:
        JMP     jr_rank_map
jr_port_dispatch_title:
        TSTB
        BNE     jr_port_dispatch_retry
        CMPA    JR_KEY_PASSWORD
        BNE     jr_port_title_start
        JMP     jr_rank_password_open
jr_port_title_start:
        CMPA    JR_KEY_CONFIRM
        BEQ     jr_port_new_level
        LDAA    JR_MODE_HELP
        STAA    [JR_PORT_MODE]
        JSR     game_draw_help
        JSR     jr_gfx_present
        JMP     jr_port_idle
jr_port_dispatch_retry:
        CMPA    JR_KEY_BACK
        BEQ     jr_port_retry
        CMPB    JR_MODE_PLAY
        BEQ     jr_port_game_act
        CMPA    JR_KEY_CONFIRM
        BEQ     jr_port_dispatch_confirm
        JMP     jr_port_idle
jr_port_dispatch_confirm:
        CMPB    JR_MODE_CLEAR
        BEQ     jr_port_advance
        JMP     jr_port_title

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

jr_port_game_act:
        JSR     game_act
        JSR     jr_port_render
        JMP     jr_port_idle

jr_port_retry:
        JSR     jr_port_confirm
        TSTA
        BNE     jr_port_new_level
        JSR     jr_port_render
        JMP     jr_port_idle

; game_draw, then the stage number, BEST (and NOW after a clear) and status.
jr_port_render:
        JSR     game_draw
        LDAA    JR_RANK_TEXT_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    25
        CLRB
        JSR     jr_gfx_at
        LDX     jr_rank_txt_stage
        JSR     jr_gfx_text
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     jr_rank_txt_best
        JSR     jr_gfx_text
        LDAA    [JR_PORT_LEVEL]
        LDX     JR_RANK_BEST
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    6
        JSR     jr_rank_stars
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     jr_port_render_present
        LDAA    JR_RANK_TEXT_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    19
        LDAB    21
        JSR     jr_gfx_at
        LDX     jr_rank_txt_now
        JSR     jr_gfx_text
        LDAB    [RANK_STARS]
        LDAA    23
        JSR     jr_rank_stars
        LDX     jr_rank_txt_clear
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BEQ     jr_port_render_status
        LDX     jr_port_status_end
jr_port_render_status:
        STX     [JR_RT_TABLE]
        LDAA    GAME_STATUS_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
jr_port_render_present:
        JMP     jr_gfx_present

; A = x, B = rating: three stars on row 21 (filled, then empty).
jr_rank_stars:
        STAB    [JR_RANK_STARS_LEFT]
        LDAB    21
; A = x, B = y, JR_RANK_STARS_LEFT = filled count.
jr_rank_stars_at:
        JSR     jr_gfx_at
        LDAA    GAME_STAR_ATTR
        STAA    [JR_RT_COLOR]
        LDAB    3
jr_rank_stars_next:
        LDAA    GAME_STAR_CODE + 1
        TST     [JR_RANK_STARS_LEFT]
        BEQ     jr_rank_stars_put
        DEC     [JR_RANK_STARS_LEFT]
        LDAA    GAME_STAR_CODE
jr_rank_stars_put:
        PSHB
        JSR     jr_gfx_putc
        PULB
        DECB
        BNE     jr_rank_stars_next
        RTS

; A = value -> three digits at the cursor.
jr_rank_dec3:
        LDAB    100
        JSR     jr_divmod8
        PSHB
        ADDA    0x30
        JSR     jr_gfx_putc
        PULA
        JMP     jr_gfx_dec2

jr_port_win:
        LDAA    JR_MODE_CLEAR
        STAA    [JR_PORT_MODE]
        LDAA    2
        BRA     jr_port_sound

jr_port_lose:
        LDAA    JR_MODE_TITLE
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

; ---------------------------------------------------------------- rating

jr_rank_spend:
        LDAA    [RANK_MOVES]
        CMPA    255
        BEQ     jr_rank_spend_over
        INC     [RANK_MOVES]
        RTS
jr_rank_spend_over:
        LDAA    1
        STAA    [RANK_OVERFLOW]
        RTS

jr_rank_take:
        LDAB    [RANK_RUNES]
        PSHB
        CMPA    [RANK_RUNE_A]
        BNE     jr_rank_take_b
        LDAB    [RANK_RUNES]
        ORAB    1
        STAB    [RANK_RUNES]
jr_rank_take_b:
        CMPA    [RANK_RUNE_B]
        BNE     jr_rank_take_done
        LDAB    [RANK_RUNES]
        ORAB    2
        STAB    [RANK_RUNES]
jr_rank_take_done:
        PULB
        CMPB    [RANK_RUNES]
        BEQ     jr_rank_take_same
        LDAA    1
        JMP     jr_port_sound
jr_rank_take_same:
        RTS

jr_rank_clear:
        LDAA    1
        STAA    [RANK_STARS]
        TST     [RANK_OVERFLOW]
        BNE     jr_rank_clear_record
        LDAA    [RANK_MOVES]
        CMPA    [RANK_PAR]
        BHI     jr_rank_clear_record
        LDAA    2
        LDAB    [RANK_RUNES]
        CMPB    3
        BNE     jr_rank_clear_stars
        LDAA    3
jr_rank_clear_stars:
        STAA    [RANK_STARS]
jr_rank_clear_record:
        LDAA    [JR_PORT_LEVEL]
        LDX     JR_RANK_BEST
        JSR     jr_add_x_a
        LDAA    [RANK_STARS]
        CMPA    [X]
        BLS     jr_rank_clear_win
        STAA    [X]
jr_rank_clear_win:
        JMP     jr_port_win

jr_rank_hud:
        LDAA    JR_RANK_TEXT_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDX     jr_rank_txt_hud
        JSR     jr_gfx_text
        LDAA    5
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [RANK_MOVES]
        JSR     jr_rank_dec3
        TST     [RANK_OVERFLOW]
        BEQ     jr_rank_hud_par
        LDAA    0x2b
        JSR     jr_gfx_putc
jr_rank_hud_par:
        LDAA    14
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [RANK_PAR]
        JSR     jr_rank_dec3
        LDAA    25
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [RANK_RUNES]
        TAB
        ANDA    1
        LSRB
        ABA
        ADDA    0x30
        JMP     jr_gfx_putc

; ---------------------------------------------------------------- stage map

jr_rank_map:
        LDAA    JR_MODE_MAP
        STAA    [JR_PORT_MODE]
        LDAA    0x20
        LDAB    JR_RANK_TEXT_ATTR
        JSR     jr_gfx_fill
        LDAA    JR_RANK_HEAD_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    2
        CLRB
        JSR     jr_gfx_at
        LDX     jr_rank_txt_header
        JSR     jr_gfx_text
        CLR     [JR_RANK_CELL]
        CLR     [JR_RANK_COL]
        CLR     [JR_RANK_TOTAL]
        LDAA    3
        STAA    [JR_RANK_ROW]
jr_rank_map_cell:
        LDAA    JR_RANK_TEXT_ATTR
        LDAB    [JR_RANK_CELL]
        CMPB    [JR_PORT_LEVEL]
        BNE     jr_rank_map_colour
        LDAA    JR_RANK_HEAD_ATTR
jr_rank_map_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [JR_RANK_COL]
        LDAB    [JR_RANK_ROW]
        JSR     jr_gfx_at
        LDAA    0x20
        LDAB    [JR_RANK_CELL]
        CMPB    [JR_PORT_LEVEL]
        BNE     jr_rank_map_mark
        LDAA    0x3e
jr_rank_map_mark:
        JSR     jr_gfx_putc
        LDAA    [JR_RANK_CELL]
        INCA
        JSR     jr_gfx_dec2
        LDAA    [JR_RANK_CELL]
        LDX     JR_RANK_BEST
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RANK_STARS_LEFT]
        ADDA    [JR_RANK_TOTAL]
        STAA    [JR_RANK_TOTAL]
        LDAA    [JR_RANK_COL]
        ADDA    3
        LDAB    [JR_RANK_ROW]
        JSR     jr_rank_stars_at
        INC     [JR_RANK_CELL]
        LDAA    [JR_RANK_COL]
        ADDA    6
        STAA    [JR_RANK_COL]
        CMPA    30
        BCS     jr_rank_map_next
        CLR     [JR_RANK_COL]
        INC     [JR_RANK_ROW]
        INC     [JR_RANK_ROW]
jr_rank_map_next:
        LDAA    [JR_RANK_CELL]
        CMPA    GAME_LEVELS
        BCS     jr_rank_map_cell
        LDX     jr_rank_map_lines
        JSR     jr_gfx_lines
        LDAA    JR_RANK_TEXT_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    13
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [JR_RANK_TOTAL]
        JSR     jr_rank_dec3
        LDAA    7
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_rank_dec3
        LDAA    17
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        JSR     game_level_par
        JSR     jr_rank_dec3
        LDAA    22
        JSR     jr_rank_show_code
        JSR     jr_gfx_present
        JMP     jr_port_idle

jr_rank_map_input:
        CMPA    JR_KEY_PASSWORD
        BNE     jr_rank_map_play
        JMP     jr_rank_password_open
jr_rank_map_play:
        CMPA    JR_KEY_CONFIRM
        BNE     jr_rank_map_title
        JMP     jr_port_new_level
jr_rank_map_title:
        CMPA    JR_KEY_BACK
        BNE     jr_rank_map_move
        JMP     jr_port_title
jr_rank_map_move:
        LDAB    [JR_PORT_LEVEL]
        CMPA    JR_KEY_UP
        BNE     jr_rank_map_down
        SUBB    5
        BCC     jr_rank_map_set
        ADDB    GAME_LEVELS
        BRA     jr_rank_map_set
jr_rank_map_down:
        CMPA    JR_KEY_DOWN
        BNE     jr_rank_map_left
        ADDB    5
        BRA     jr_rank_map_wrap
jr_rank_map_left:
        CMPA    JR_KEY_LEFT
        BNE     jr_rank_map_right
        TSTB
        BNE     jr_rank_map_prev
        LDAB    GAME_LEVELS
jr_rank_map_prev:
        DECB
        BRA     jr_rank_map_set
jr_rank_map_right:
        CMPA    JR_KEY_RIGHT
        BEQ     jr_rank_map_next_stage
        JMP     jr_port_idle
jr_rank_map_next_stage:
        INCB
jr_rank_map_wrap:
        CMPB    GAME_LEVELS
        BCS     jr_rank_map_set
        SUBB    GAME_LEVELS
jr_rank_map_set:
        STAB    [JR_PORT_LEVEL]
        JMP     jr_rank_map

; ---------------------------------------------------------------- password

; A = row: "PW " and the current code at column 0.
jr_rank_show_code:
        PSHA
        JSR     jr_rank_encode
        LDAA    JR_RANK_CODE_ATTR
        STAA    [JR_RT_COLOR]
        PULB
        CLRA
        JSR     jr_gfx_at
        LDX     jr_rank_txt_pw
        JSR     jr_gfx_text
        JMP     jr_rank_code_text

; the stage and BEST as values 0-15 in JR_RANK_BUF (upstream password.py).
jr_rank_encode:
        CLR     [JR_RANK_INDEX]
jr_rank_encode_pack:
        LDAA    [JR_RANK_INDEX]
        ASLA
        LDX     JR_RANK_BEST
        JSR     jr_add_x_a
        LDAA    [X]
        ASLA
        ASLA
        ORAA    [X + 1]
        PSHA
        LDAA    [JR_RANK_INDEX]
        LDX     JR_RANK_REC
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [JR_RANK_INDEX]
        LDAA    [JR_RANK_INDEX]
        CMPA    20
        BNE     jr_rank_encode_pack
        ; leading pairs of three stars, trailing uncleared pairs
        CLR     [JR_RANK_PREFIX]
        LDX     JR_RANK_REC
jr_rank_encode_prefix:
        LDAA    [X]
        CMPA    15
        BNE     jr_rank_encode_trim
        INX
        INC     [JR_RANK_PREFIX]
        LDAA    [JR_RANK_PREFIX]
        CMPA    20
        BCS     jr_rank_encode_prefix
jr_rank_encode_trim:
        LDAA    20
        STAA    [JR_RANK_LIMIT]
jr_rank_encode_trim_next:
        LDAA    [JR_RANK_LIMIT]
        CMPA    [JR_RANK_PREFIX]
        BEQ     jr_rank_encode_header
        DECA
        LDX     JR_RANK_REC
        JSR     jr_add_x_a
        TST     [X]
        BNE     jr_rank_encode_header
        DEC     [JR_RANK_LIMIT]
        BRA     jr_rank_encode_trim_next
jr_rank_encode_header:
        LDAA    [JR_PORT_LEVEL]
        TST     [JR_RANK_PREFIX]
        BEQ     jr_rank_encode_head_ready
        ORAA    128
        LDAB    [JR_RANK_PREFIX]
        CMPB    16
        BCS     jr_rank_encode_head_ready
        ORAA    64
jr_rank_encode_head_ready:
        STAA    [JR_RANK_HEADER]
        CLR     [JR_RANK_LEN]
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     jr_rank_push
        LDAA    [JR_RANK_HEADER]
        ANDA    15
        JSR     jr_rank_push
        TST     [JR_RANK_PREFIX]
        BEQ     jr_rank_encode_body
        LDAA    [JR_RANK_PREFIX]
        ANDA    15
        JSR     jr_rank_push
jr_rank_encode_body:
        LDAA    [JR_RANK_PREFIX]
        STAA    [JR_RANK_INDEX]
jr_rank_encode_body_next:
        LDAA    [JR_RANK_INDEX]
        CMPA    [JR_RANK_LIMIT]
        BEQ     jr_rank_encode_check
        LDX     JR_RANK_REC
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_rank_push
        INC     [JR_RANK_INDEX]
        BRA     jr_rank_encode_body_next
jr_rank_encode_check:
        JSR     jr_rank_checksum
        LDAA    [JR_RANK_CRC]
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     jr_rank_push
        LDAA    [JR_RANK_CRC]
        ANDA    15
; A = value -> appended to JR_RANK_BUF.
jr_rank_push:
        PSHA
        LDAA    [JR_RANK_LEN]
        LDX     JR_RANK_BUF
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [JR_RANK_LEN]
        RTS

; JR_RANK_CRC = the game-tagged CRC of JR_RANK_BUF (0 for a whole code).
jr_rank_checksum:
        LDAA    GAME_PASSWORD_TAG
        STAA    [JR_RANK_CRC]
        CLR     [JR_RANK_POS]
jr_rank_checksum_next:
        LDAA    [JR_RANK_POS]
        CMPA    [JR_RANK_LEN]
        BEQ     jr_rank_crc_done
        LDX     JR_RANK_BUF
        JSR     jr_add_x_a
        LDAA    [X]
        ASLA
        ASLA
        ASLA
        ASLA
        EORA    [JR_RANK_CRC]
        LDAB    4
jr_rank_crc_bit:
        ASLA
        BCC     jr_rank_crc_keep
        EORA    7
jr_rank_crc_keep:
        DECB
        BNE     jr_rank_crc_bit
        STAA    [JR_RANK_CRC]
        INC     [JR_RANK_POS]
        BRA     jr_rank_checksum_next
jr_rank_crc_done:
        RTS

; JR_RANK_BUF as letters at the cursor, a space after every four.
jr_rank_code_text:
        CLR     [JR_RANK_POS]
jr_rank_code_text_next:
        LDAA    [JR_RANK_POS]
        CMPA    [JR_RANK_LEN]
        BEQ     jr_rank_code_text_done
        LDX     JR_RANK_BUF
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     jr_rank_alphabet
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_putc
        INC     [JR_RANK_POS]
        LDAA    [JR_RANK_POS]
        ANDA    3
        BNE     jr_rank_code_text_next
        LDAA    [JR_RANK_POS]
        CMPA    [JR_RANK_LEN]
        BEQ     jr_rank_code_text_done
        LDAA    0x20
        JSR     jr_gfx_putc
        BRA     jr_rank_code_text_next
jr_rank_code_text_done:
        RTS

jr_rank_password_open:
        LDAA    [JR_PORT_MODE]
        STAA    [JR_RANK_BACK]
        LDAA    JR_MODE_PASSWORD
        STAA    [JR_PORT_MODE]
        CLR     [JR_RANK_LEN]
        CLR     [JR_RANK_ERROR]
jr_rank_password_draw:
        LDAA    0x20
        LDAB    JR_RANK_TEXT_ATTR
        JSR     jr_gfx_fill
        LDX     jr_rank_password_lines
        JSR     jr_gfx_lines
        LDAA    JR_RANK_HEAD_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    3
        JSR     jr_gfx_at
        LDX     game_title_text
        JSR     jr_gfx_text
        LDAA    JR_RANK_TEXT_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    17
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [JR_RANK_LEN]
        JSR     jr_rank_dec3
        LDAA    JR_RANK_CODE_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    6
        JSR     jr_gfx_at
        JSR     jr_rank_code_text
        TST     [JR_RANK_ERROR]
        BEQ     jr_rank_password_shown
        LDAA    JR_RANK_ERROR_ATTR
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    4
        JSR     jr_gfx_at
        LDX     jr_rank_txt_error
        JSR     jr_gfx_text
jr_rank_password_shown:
        JSR     jr_gfx_present
        JMP     jr_port_idle

; B = raw key: letters type, '-' or BACKSPACE erase, RETURN loads, X cancels.
jr_rank_password_key:
        CMPB    0x0d
        BEQ     jr_rank_restore
        CMPB    0x08
        BEQ     jr_rank_password_erase
        CMPB    0x2d
        BEQ     jr_rank_password_erase
        TBA
        CMPA    0x61
        BCS     jr_rank_password_upper
        CMPA    0x7b
        BCC     jr_rank_password_upper
        ANDA    0xdf
jr_rank_password_upper:
        CMPA    0x58
        BNE     jr_rank_password_letter
        LDAA    [JR_RANK_BACK]
        CMPA    JR_MODE_MAP
        BNE     jr_rank_password_title
        JMP     jr_rank_map
jr_rank_password_title:
        JMP     jr_port_title
jr_rank_password_letter:
        LDX     jr_rank_alphabet
        CLRB
jr_rank_password_find:
        CMPA    [X]
        BEQ     jr_rank_password_found
        INX
        INCB
        CMPB    16
        BNE     jr_rank_password_find
        JMP     jr_port_idle
jr_rank_password_found:
        LDAA    [JR_RANK_LEN]
        CMPA    24
        BCC     jr_rank_password_bad
        TBA
        JSR     jr_rank_push
        CLR     [JR_RANK_ERROR]
        JMP     jr_rank_password_draw
jr_rank_password_erase:
        TST     [JR_RANK_LEN]
        BEQ     jr_rank_password_erased
        DEC     [JR_RANK_LEN]
jr_rank_password_erased:
        CLR     [JR_RANK_ERROR]
        JMP     jr_rank_password_draw
jr_rank_password_bad:
        LDAA    1
        STAA    [JR_RANK_ERROR]
        JMP     jr_rank_password_draw

; Validate everything first, then write BEST and the stage (upstream P_RESTORE).
jr_rank_restore:
        LDAA    [JR_RANK_LEN]
        CMPA    4
        BCS     jr_rank_password_bad
        JSR     jr_rank_checksum
        TST     [JR_RANK_CRC]
        BNE     jr_rank_password_bad
        LDAA    [JR_RANK_BUF]
        ASLA
        ASLA
        ASLA
        ASLA
        ORAA    [JR_RANK_BUF + 1]
        STAA    [JR_RANK_HEADER]
        ANDA    63
        CMPA    GAME_LEVELS
        BCC     jr_rank_password_bad
        LDAA    2
        STAA    [JR_RANK_POS]
        CLR     [JR_RANK_PREFIX]
        LDAA    [JR_RANK_HEADER]
        BITA    128
        BNE     jr_rank_restore_prefix
        BITA    64
        BNE     jr_rank_password_bad
        BRA     jr_rank_restore_count
jr_rank_restore_prefix:
        LDAA    [JR_RANK_LEN]
        CMPA    5
        BCS     jr_rank_password_bad
        LDAA    [JR_RANK_BUF + 2]
        LDAB    [JR_RANK_HEADER]
        BITB    64
        BEQ     jr_rank_restore_prefix_value
        ORAA    16
jr_rank_restore_prefix_value:
        TSTA
        BEQ     jr_rank_password_bad
        CMPA    21
        BCC     jr_rank_password_bad
        STAA    [JR_RANK_PREFIX]
        INC     [JR_RANK_POS]
jr_rank_restore_count:
        LDAA    [JR_RANK_LEN]
        SUBA    2
        STAA    [JR_RANK_LIMIT]
        SUBA    [JR_RANK_POS]
        ADDA    [JR_RANK_PREFIX]
        CMPA    21
        BCC     jr_rank_password_bad
        ; ratings: prefix pairs of three, the body, then zeros
        LDX     JR_RANK_REC
        LDAB    [JR_RANK_PREFIX]
jr_rank_restore_fill:
        TSTB
        BEQ     jr_rank_restore_body
        LDAA    3
        STAA    [X]
        STAA    [X + 1]
        INX
        INX
        DECB
        BRA     jr_rank_restore_fill
jr_rank_restore_body:
        LDAA    [JR_RANK_POS]
        CMPA    [JR_RANK_LIMIT]
        BEQ     jr_rank_restore_zero
        STX     [JR_RT_TABLE]
        LDX     JR_RANK_BUF
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     [JR_RT_TABLE]
        TAB
        LSRA
        LSRA
        STAA    [X]
        ANDB    3
        STAB    [X + 1]
        INX
        INX
        INC     [JR_RANK_POS]
        BRA     jr_rank_restore_body
jr_rank_restore_zero:
        CPX     JR_RANK_REC + 40
        BEQ     jr_rank_restore_commit
        CLR     [X]
        INX
        BRA     jr_rank_restore_zero
jr_rank_restore_commit:
        CLRB
jr_rank_restore_copy:
        TBA
        LDX     JR_RANK_REC
        JSR     jr_add_x_a
        LDAA    [X]
        PSHA
        TBA
        LDX     JR_RANK_BEST
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INCB
        CMPB    40
        BNE     jr_rank_restore_copy
        LDAA    [JR_RANK_HEADER]
        ANDA    63
        STAA    [JR_PORT_LEVEL]
        JMP     jr_rank_map

; ---------------------------------------------------------------- data

; 8x8 filled and empty stars (upstream's rating glyphs)
jr_rank_star_patterns:
        .db     0x10, 0x38, 0xfe, 0x7c, 0x38, 0x6c, 0xc6, 0x00
        .db     0x10, 0x28, 0xc6, 0x44, 0x28, 0x54, 0x82, 0x00
jr_rank_alphabet:
        .db     "ACDEFGHJKMNPQRTW"

jr_rank_title_lines:
        .db     0, 21, JR_RANK_HINT_ATTR
        .dw     jr_rank_txt_title_keys
        .db     4, 23, JR_RANK_HINT_ATTR
        .dw     jr_rank_txt_title_rooms
        .db     0xff
jr_rank_map_lines:
        .db     1, 19, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_total
        .db     1, 20, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_par
        .db     1, 21, JR_RANK_HINT_ATTR
        .dw     jr_rank_txt_map_keys
        .db     1, 23, JR_RANK_HINT_ATTR
        .dw     jr_rank_txt_map_exit
        .db     0xff
jr_rank_password_lines:
        .db     8, 0, JR_RANK_HEAD_ATTR
        .dw     jr_rank_txt_restore
        .db     1, 2, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_type
        .db     3, 6, JR_RANK_HINT_ATTR
        .dw     jr_rank_txt_field
        .db     10, 7, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_length
        .db     3, 10, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_letters
        .db     5, 12, JR_RANK_CODE_ATTR
        .dw     jr_rank_alphabet_text
        .db     3, 19, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_erase
        .db     2, 23, JR_RANK_TEXT_ATTR
        .dw     jr_rank_txt_cancel
        .db     0xff

jr_rank_txt_stage:
        .db     "STG ", 0
jr_rank_txt_best:
        .db     "BEST", 0
jr_rank_txt_now:
        .db     "NOW", 0
jr_rank_txt_hud:
        .db     "MOV 000  PAR 000  RUNES 0/2", 0
jr_rank_txt_clear:
        .db     "RETURN NEXT  SPACE RETRY  F MAP", 0
jr_rank_txt_title_keys:
        .db     " RET PLAY F MAP X LOAD SPACE ?", 0
jr_rank_txt_title_rooms:
        .db     "40 ROOMS / CTRL+C EXIT", 0
jr_rank_txt_header:
        .db     "FORTY CHAMBERS / STAR RECORDS", 0
jr_rank_txt_total:
        .db     "TOTAL STARS 000 / 120", 0
jr_rank_txt_par:
        .db     "STAGE 000 / PAR 000", 0
jr_rank_txt_map_keys:
        .db     "WASD SELECT / RETURN PLAY", 0
jr_rank_txt_map_exit:
        .db     "SPACE TITLE / X PASSWORD LOAD", 0
jr_rank_txt_pw:
        .db     "PW ", 0
jr_rank_txt_restore:
        .db     "PASSWORD RESTORE", 0
jr_rank_txt_type:
        .db     "TYPE LETTERS / RETURN TO LOAD", 0
jr_rank_txt_field:
        .db     "____ ____ ____ ____ ____ ____", 0
jr_rank_txt_length:
        .db     "LENGTH 000 / 24", 0
jr_rank_txt_letters:
        .db     "LETTERS IN A CODE:", 0
jr_rank_alphabet_text:
        .db     "A C D E F G H J K M N P Q R T W", 0
jr_rank_txt_erase:
        .db     "- / BACKSPACE : ERASE", 0
jr_rank_txt_cancel:
        .db     "X : CANCEL / SPACES IGNORED", 0
jr_rank_txt_error:
        .db     "CHECK CODE AND GAME TITLE", 0

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
jr_port_status_end:
        .db     "ALL STAGES CLEAR - THANK YOU", 0

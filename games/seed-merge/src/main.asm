; SPDX-License-Identifier: MIT
; SEED MERGE for JR-200. Rules: jr100dev games/seed_merge/rules.py 1.5.1.
; Board cells hold exponents (1=2, 6=64). The JR-100 machine code is not used.
        .filename.jr "SEED-MERGE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

SM_BOARD:           .equ    GAME_STATE
SM_SEED:            .equ    GAME_STATE + 16
SM_BEST:            .equ    GAME_STATE + 17
SM_MOVES:           .equ    GAME_STATE + 18
SM_CHANGED:         .equ    GAME_STATE + 19
SM_MOVED:           .equ    GAME_STATE + 20
SM_MERGED:          .equ    GAME_STATE + 21
SM_STEP:            .equ    GAME_STATE + 22
SM_LINE:            .equ    GAME_STATE + 23
SM_I:               .equ    GAME_STATE + 24
SM_P:               .equ    GAME_STATE + 25
SM_N:               .equ    GAME_STATE + 26
SM_VALUE:           .equ    GAME_STATE + 27
SM_SEARCH:          .equ    GAME_STATE + 28
SM_TABLE:           .equ    GAME_STATE + 30
SM_DI:              .equ    GAME_STATE + 32
SM_DX:              .equ    GAME_STATE + 33
SM_DY:              .equ    GAME_STATE + 34
SM_DVAL:            .equ    GAME_STATE + 35
SM_NUMBER:          .equ    GAME_STATE + 36

SM_TEXT:            .equ    0x07
SM_TITLE:           .equ    0x06
SM_LABEL:           .equ    0x04

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        LDAA    7
        STAA    [SM_SEED]
        JSR     sm_spawn
        JSR     sm_spawn
        LDAA    1
        STAA    [SM_BEST]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BCC     sm_act_done
        ; Direction 1..4 selects a 16-byte array of ordered board indices.
        DECA
        ASLA
        LDX     sm_direction_tables
        JSR     jr_add_x_a
        LDX     [X]
        STX     [SM_TABLE]
        CLR     [SM_CHANGED]
        JSR     sm_settle
        JSR     sm_merge
        TST     [SM_MERGED]
        BEQ     sm_act_after_merge
        LDAA    1
        JSR     jr_port_sound
        LDAA    8
        JSR     jr_port_animate
sm_act_after_merge:
        JSR     sm_settle
        TST     [SM_CHANGED]
        BEQ     sm_act_check
        JSR     sm_spawn
        INC     [SM_MOVES]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
sm_act_check:
        LDAA    [SM_BEST]
        CMPA    6
        BCS     sm_act_possible
        JMP     jr_port_win
sm_act_possible:
        JSR     sm_possible
        TSTA
        BNE     sm_act_done
        LDX     sm_txt_lose
        JMP     jr_port_lose
sm_act_done:
        RTS

; Seed = (seed * 5 + 1) & 255. Pick the first free cell at seed+i mod 16.
sm_spawn:
        LDAA    [SM_SEED]
        STAA    [SM_VALUE]
        ASLA
        ASLA
        ADDA    [SM_VALUE]
        INCA
        STAA    [SM_SEED]
        ANDA    15
        STAA    [SM_SEARCH]
        CLR     [SM_I]
sm_spawn_loop:
        LDX     SM_BOARD
        LDAA    [SM_SEARCH]
        JSR     jr_add_x_a
        TST     [X]
        BNE     sm_spawn_next
        LDAA    1
        STAA    [X]
        RTS
sm_spawn_next:
        INC     [SM_SEARCH]
        LDAA    [SM_SEARCH]
        ANDA    15
        STAA    [SM_SEARCH]
        INC     [SM_I]
        LDAA    [SM_I]
        CMPA    16
        BCS     sm_spawn_loop
        RTS

; Settle each line up to three cells towards its leading edge.
sm_settle:
        CLR     [SM_STEP]
sm_settle_step:
        CLR     [SM_MOVED]
        CLR     [SM_LINE]
sm_settle_line:
        CLR     [SM_I]
sm_settle_pair:
        JSR     sm_pair
        LDX     SM_BOARD
        LDAA    [SM_P]
        JSR     jr_add_x_a
        TST     [X]
        BNE     sm_settle_next
        LDX     SM_BOARD
        LDAA    [SM_N]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     sm_settle_next
        STAA    [SM_VALUE]
        CLR     [X]
        LDX     SM_BOARD
        LDAA    [SM_P]
        JSR     jr_add_x_a
        LDAA    [SM_VALUE]
        STAA    [X]
        LDAA    1
        STAA    [SM_MOVED]
        STAA    [SM_CHANGED]
sm_settle_next:
        INC     [SM_I]
        LDAA    [SM_I]
        CMPA    3
        BCS     sm_settle_pair
        INC     [SM_LINE]
        LDAA    [SM_LINE]
        CMPA    4
        BCS     sm_settle_line
        TST     [SM_MOVED]
        BEQ     sm_settle_no_anim
        LDAA    3
        JSR     jr_port_animate
sm_settle_no_anim:
        INC     [SM_STEP]
        LDAA    [SM_STEP]
        CMPA    3
        BCS     sm_settle_step
        RTS

; Exactly one merge pass. A newly doubled cell cannot merge again this turn.
sm_merge:
        CLR     [SM_MERGED]
        CLR     [SM_LINE]
sm_merge_line:
        CLR     [SM_I]
sm_merge_pair:
        JSR     sm_pair
        LDX     SM_BOARD
        LDAA    [SM_P]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     sm_merge_next
        STAA    [SM_VALUE]
        LDX     SM_BOARD
        LDAA    [SM_N]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [SM_VALUE]
        BNE     sm_merge_next
        CLR     [X]
        LDAA    [SM_VALUE]
        INCA
        STAA    [SM_VALUE]
        LDX     SM_BOARD
        LDAB    [SM_P]
        TBA
        JSR     jr_add_x_a
        LDAA    [SM_VALUE]
        STAA    [X]
        CMPA    [SM_BEST]
        BLS     sm_merge_mark
        STAA    [SM_BEST]
sm_merge_mark:
        LDAA    1
        STAA    [SM_MERGED]
        STAA    [SM_CHANGED]
sm_merge_next:
        INC     [SM_I]
        LDAA    [SM_I]
        CMPA    3
        BCS     sm_merge_pair
        INC     [SM_LINE]
        LDAA    [SM_LINE]
        CMPA    4
        BCS     sm_merge_line
        RTS

; Position pair for the current line and offset in SM_TABLE.
sm_pair:
        LDAA    [SM_LINE]
        ASLA
        ASLA
        ADDA    [SM_I]
        LDX     [SM_TABLE]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SM_P]
        INX
        LDAA    [X]
        STAA    [SM_N]
        RTS

; Return A=1 if an empty cell or an orthogonally equal pair exists.
sm_possible:
        CLR     [SM_SEARCH]
sm_possible_loop:
        LDX     SM_BOARD
        LDAA    [SM_SEARCH]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     sm_possible_yes
        STAA    [SM_VALUE]
        LDAA    [SM_SEARCH]
        ANDA    3
        CMPA    3
        BEQ     sm_possible_down
        LDX     SM_BOARD
        LDAA    [SM_SEARCH]
        INCA
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [SM_VALUE]
        BEQ     sm_possible_yes
sm_possible_down:
        LDAA    [SM_SEARCH]
        CMPA    12
        BCC     sm_possible_next
        ADDA    4
        LDX     SM_BOARD
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [SM_VALUE]
        BEQ     sm_possible_yes
sm_possible_next:
        INC     [SM_SEARCH]
        LDAA    [SM_SEARCH]
        CMPA    16
        BCS     sm_possible_loop
        CLRA
        RTS
sm_possible_yes:
        LDAA    1
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    SM_TEXT
        JSR     jr_gfx_fill
        LDX     sm_hud
        JSR     jr_gfx_lines
        CLR     [SM_DI]
        LDAA    2
        STAA    [SM_DX]
        LDAA    4
        STAA    [SM_DY]
sm_draw_loop:
        LDX     SM_BOARD
        LDAA    [SM_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SM_DVAL]
        LDX     sm_colors
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [SM_DX]
        LDAB    [SM_DY]
        JSR     jr_gfx_at
        LDX     sm_border
        JSR     jr_gfx_text
        LDAA    [SM_DX]
        LDAB    [SM_DY]
        INCB
        JSR     jr_gfx_at
        LDX     sm_inside
        JSR     jr_gfx_text
        LDAA    [SM_DX]
        LDAB    [SM_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDX     sm_border
        JSR     jr_gfx_text
        TST     [SM_DVAL]
        BEQ     sm_draw_next
        LDAA    1
        STAA    [SM_NUMBER]
        LDAB    [SM_DVAL]
sm_draw_power:
        ASL     [SM_NUMBER]
        DECB
        BNE     sm_draw_power
        LDAA    [SM_DX]
        ADDA    2
        LDAB    [SM_DY]
        INCB
        JSR     jr_gfx_at
        LDAA    [SM_NUMBER]
        JSR     jr_gfx_dec3
sm_draw_next:
        INC     [SM_DI]
        LDAA    [SM_DI]
        ANDA    3
        BEQ     sm_draw_new_row
        LDAA    [SM_DX]
        ADDA    7
        STAA    [SM_DX]
        BRA     sm_draw_check
sm_draw_new_row:
        LDAA    2
        STAA    [SM_DX]
        LDAA    [SM_DY]
        ADDA    4
        STAA    [SM_DY]
sm_draw_check:
        LDAA    [SM_DI]
        CMPA    16
        BCC     sm_draw_finish
        JMP     sm_draw_loop
sm_draw_finish:
        LDAA    SM_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    20
        JSR     jr_gfx_at
        LDAA    1
        LDAB    [SM_BEST]
sm_draw_best_power:
        ASLA
        DECB
        BNE     sm_draw_best_power
        JSR     jr_gfx_dec3
        LDAA    21
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SM_MOVES]
        JMP     jr_gfx_dec3

game_draw_title:
        LDAA    0x20
        LDAB    SM_TEXT
        JSR     jr_gfx_fill
        LDX     sm_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SM_TEXT
        JSR     jr_gfx_fill
        LDX     sm_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

sm_direction_tables:
        .dw     sm_up, sm_down, sm_left, sm_right
sm_up:
        .db     0,4,8,12, 1,5,9,13, 2,6,10,14, 3,7,11,15
sm_down:
        .db     12,8,4,0, 13,9,5,1, 14,10,6,2, 15,11,7,3
sm_left:
        .db     0,1,2,3, 4,5,6,7, 8,9,10,11, 12,13,14,15
sm_right:
        .db     3,2,1,0, 7,6,5,4, 11,10,9,8, 15,14,13,12
sm_colors:
        .db     0x04, 0x02, 0x03, 0x06, 0x05, 0x01, 0x0e, 0x0f
sm_border:
        .db     "+-----+", 0
sm_inside:
        .db     "|     |", 0

sm_hud:
        .db     10,0,SM_TITLE
        .dw     sm_txt_name
        .db     4,2,SM_LABEL
        .dw     sm_txt_goal
        .db     2,20,SM_LABEL
        .dw     sm_txt_best
        .db     15,20,SM_LABEL
        .dw     sm_txt_moves
        .db     1,22,SM_TEXT
        .dw     sm_txt_bottom
        .db     0xff
sm_title_lines:
        .db     10,3,SM_TITLE
        .dw     sm_txt_name
        .db     5,7,0x02
        .dw     sm_txt_grow
        .db     4,12,SM_LABEL
        .dw     sm_txt_goal
        .db     8,16,SM_TEXT
        .dw     sm_txt_start
        .db     4,19,SM_TEXT
        .dw     sm_txt_howto
        .db     3,22,SM_LABEL
        .dw     sm_txt_credit
        .db     0xff
sm_help_lines:
        .db     10,2,SM_TITLE
        .dw     sm_txt_name
        .db     3,6,SM_TEXT
        .dw     sm_help_1
        .db     3,9,SM_TEXT
        .dw     sm_help_2
        .db     3,12,SM_TEXT
        .dw     sm_help_3
        .db     3,15,SM_TEXT
        .dw     sm_help_4
        .db     3,18,SM_TEXT
        .dw     sm_help_5
        .db     6,21,SM_LABEL
        .dw     sm_help_back
        .db     0xff
sm_txt_name:
        .db     "SEED MERGE", 0
sm_txt_grow:
        .db     "2  +  2  >  4  >  8  > 64", 0
sm_txt_goal:
        .db     "MERGE TWO SEEDS TO GROW 64", 0
sm_txt_start:
        .db     "RETURN : START", 0
sm_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
sm_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sm_txt_best:
        .db     "BEST", 0
sm_txt_moves:
        .db     "MOVES", 0
sm_txt_bottom:
        .db     "SPACE:RESTART  CTRL+C:BASIC", 0
sm_txt_lose:
        .db     "NO MORE MOVES", 0
sm_help_1:
        .db     "WASD : SLIDE ALL SEEDS", 0
sm_help_2:
        .db     "EQUAL NUMBERS MERGE ONCE", 0
sm_help_3:
        .db     "A NEW TWO AFTER A MOVE", 0
sm_help_4:
        .db     "GROW A SIXTY FOUR TO WIN", 0
sm_help_5:
        .db     "SPACE:RESTART  CTRL+C:BASIC", 0
sm_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     sm_sfx_slide, sm_sfx_merge, sm_sfx_win, sm_sfx_lose
sm_sfx_slide:
        .db     112,2, 0,0
sm_sfx_merge:
        .db     92,4, 76,4, 0,0
sm_sfx_win:
        .db     104,5, 88,5, 72,5, 52,12, 0,0
sm_sfx_lose:
        .db     120,7, 170,7, 215,16, 0,0

        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"

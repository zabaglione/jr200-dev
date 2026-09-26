; SPDX-License-Identifier: MIT
; RIBBON SNAKE for JR-200: a port of jr100dev games/ribbon_snake/rules.py 2.0.0.
; Six gardens, the growing ribbon, rocks, food placement, brakes, the goal and
; the three ways to lose follow the upstream source, one upstream tick per
; game_tick. Real-time rules are checked by the in-program self test
; (sdk/selftest.inc, title key T); P plays the garden-1 demo.
        .filename.jr "RIBBON-SNAKE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46c0
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream moves every 14 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    9
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    92
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    RS_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
RS_LENGTH:          .equ    GAME_STATE
RS_DIR:             .equ    GAME_STATE + 1
RS_BRAKES:          .equ    GAME_STATE + 2
RS_GOAL:            .equ    GAME_STATE + 3
RS_SLOW:            .equ    GAME_STATE + 4
RS_FOOD:            .equ    GAME_STATE + 5
RS_EATEN:           .equ    GAME_STATE + 6
RS_SLIDING:         .equ    GAME_STATE + 7
RS_B:               .equ    GAME_STATE + 8      ; body, head first (20)
RS_D:               .equ    GAME_STATE + 28     ; rocks (64)
RS_C:               .equ    GAME_STATE + 92     ; body before the last step (20)
RS_HIT:             .equ    GAME_STATE + 112    ; cell + 1 of a collision
RS_SPARK:           .equ    GAME_STATE + 113    ; cell + 1 of eaten food
RS_HELD:            .equ    GAME_STATE + 114    ; unused (no held keys)
RS_I:               .equ    GAME_STATE + 115
RS_T:               .equ    GAME_STATE + 116
RS_P:               .equ    GAME_STATE + 117
RS_N:               .equ    GAME_STATE + 118
RS_EATING:          .equ    GAME_STATE + 119
RS_DI:              .equ    GAME_STATE + 120
RS_DX:              .equ    GAME_STATE + 121
RS_DT:              .equ    GAME_STATE + 122
RS_DY:              .equ    GAME_STATE + 123
RS_DCODE:           .equ    GAME_STATE + 124
RS_MSG:             .equ    GAME_STATE + 125    ; loss message (2)

RS_TILE_FLOOR:      .equ    0x80
RS_TILE_ROCK:       .equ    0x84
RS_TILE_FOOD:       .equ    0x88
RS_TILE_BODY:       .equ    0x8c
RS_TILE_HEAD:       .equ    0x90        ; + 4 * (dir - 1)
RS_ATTR_FLOOR:      .equ    0x44
RS_ATTR_ROCK:       .equ    0x45
RS_ATTR_FOOD:       .equ    0x42
RS_ATTR_BODY:       .equ    0x43
RS_ATTR_HEAD:       .equ    0x47
RS_ATTR_HIT:        .equ    0x72        ; red on yellow
RS_ATTR_TEXT:       .equ    0x07
RS_ATTR_LABEL:      .equ    0x04
RS_ATTR_TITLE:      .equ    0x06
RS_ATTR_DIM:        .equ    0x05
RS_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     rs_patterns
        LDAA    RS_TILE_FLOOR
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    3
        STAA    [RS_LENGTH]
        STAA    [RS_BRAKES]
        LDAA    8
        STAA    [RS_B]
        CLR     [RS_B + 1]
        LDAA    1
        STAA    [RS_B + 2]
        LDAA    2
        STAA    [RS_DIR]
        LDAA    [JR_PORT_LEVEL]
        ADDA    8
        STAA    [RS_GOAL]
        ; rocks: d[18 + (i * 11 + level * 3) % 30] for i < 2 + level
        LDAA    [JR_PORT_LEVEL]
        STAA    [RS_T]
        ASLA
        ADDA    [RS_T]
        STAA    [RS_T]              ; i * 11 + level * 3, from i = 0
        LDAA    [JR_PORT_LEVEL]
        ADDA    2
        STAA    [RS_N]
rs_init_rock:
        LDAA    [RS_T]
rs_init_mod:
        CMPA    30
        BCS     rs_init_put
        SUBA    30
        BRA     rs_init_mod
rs_init_put:
        ADDA    18
        LDX     RS_D
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        LDAA    [RS_T]
        ADDA    11
        STAA    [RS_T]
        DEC     [RS_N]
        BNE     rs_init_rock

; food: the first p = (eaten * 13 + k * 7 + 26 + level * 9) % 64 that is not a
; rock or the body.
rs_place_food:
        LDAA    [JR_PORT_LEVEL]
        STAA    [RS_T]
        ASLA
        ASLA
        ASLA
        ADDA    [RS_T]
        ADDA    26
        LDAB    [RS_EATEN]
rs_place_food_eaten:
        TSTB
        BEQ     rs_place_food_start
        ADDA    13
        DECB
        BRA     rs_place_food_eaten
rs_place_food_start:
        STAA    [RS_P]
        LDAA    64
        STAA    [RS_I]
rs_place_food_try:
        LDAA    [RS_P]
        ANDA    63
        STAA    [RS_P]
        LDX     RS_D
        JSR     jr_add_x_a
        TST     [X]
        BNE     rs_place_food_next
        LDX     RS_B
        LDAB    [RS_LENGTH]
rs_place_food_body:
        LDAA    [X]
        CMPA    [RS_P]
        BEQ     rs_place_food_next
        INX
        DECB
        BNE     rs_place_food_body
        LDAA    [RS_P]
        STAA    [RS_FOOD]
        RTS
rs_place_food_next:
        LDAA    [RS_P]
        ADDA    7
        STAA    [RS_P]
        DEC     [RS_I]
        BNE     rs_place_food_try
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_CONFIRM
        BNE     rs_act_turn
        ; RETURN: a brake (eight ticks at half speed), three per garden
        TST     [RS_BRAKES]
        BEQ     rs_act_done
        TST     [RS_SLOW]
        BNE     rs_act_done
        DEC     [RS_BRAKES]
        LDAA    8
        STAA    [RS_SLOW]
        CLRA
        JMP     jr_port_sound
rs_act_turn:
        TSTA
        BEQ     rs_act_done
        CMPA    5
        BCC     rs_act_done
        TAB
        LDX     rs_opposite - 1
        LDAA    [RS_DIR]
        JSR     jr_add_x_a
        CMPB    [X]
        BEQ     rs_act_done
        STAB    [RS_DIR]
rs_act_done:
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     rs_act_done
        TST     [RS_SLOW]
        BEQ     rs_tick_move
        DEC     [RS_SLOW]
        LDAA    [RS_SLOW]
        ANDA    1
        BEQ     rs_act_done
rs_tick_move:
        LDAA    [RS_B]
        LDAB    [RS_DIR]
        JSR     rs_move
        STAA    [RS_P]
        CMPA    [RS_B]
        BNE     rs_tick_rock
        LDX     rs_txt_edge
        JMP     rs_tick_lose
rs_tick_rock:
        LDX     RS_D
        JSR     jr_add_x_a
        TST     [X]
        BEQ     rs_tick_body
        LDX     rs_txt_rock
        JMP     rs_tick_lose
rs_tick_body:
        CLR     [RS_EATING]
        LDAB    [RS_LENGTH]
        DECB
        LDAA    [RS_P]
        CMPA    [RS_FOOD]
        BNE     rs_tick_body_count
        INC     [RS_EATING]
        INCB
rs_tick_body_count:
        LDX     RS_B
rs_tick_body_next:
        LDAA    [X]
        CMPA    [RS_P]
        BNE     rs_tick_body_step
        LDX     rs_txt_body
        BRA     rs_tick_lose
rs_tick_body_step:
        INX
        DECB
        BNE     rs_tick_body_next
        ; c = the body before the step (plus the tail again), then shift
        LDX     RS_B
        LDAB    [RS_LENGTH]
rs_tick_copy:
        LDAA    [X]
        STAA    [X + 84]
        INX
        DECB
        BNE     rs_tick_copy
        LDAA    [X + 83]
        STAA    [X + 84]
        LDX     RS_B
        LDAA    [RS_LENGTH]
        JSR     jr_add_x_a
        LDAB    [RS_LENGTH]
rs_tick_shift:
        DEX
        LDAA    [X]
        STAA    [X + 1]
        DECB
        BNE     rs_tick_shift
        LDAA    [RS_P]
        STAA    [RS_B]
        LDAA    1
        STAA    [RS_SLIDING]
        LDAA    3
        JSR     jr_test_animate
        CLR     [RS_SLIDING]
        TST     [RS_EATING]
        BNE     rs_act_done_near289
        JMP     rs_act_done
rs_act_done_near289:
        INC     [RS_LENGTH]
        LDAA    [RS_P]
        INCA
        STAA    [RS_SPARK]
        LDAA    6
        JSR     jr_test_animate
        CLR     [RS_SPARK]
        INC     [RS_EATEN]
        JSR     rs_place_food
        LDAA    1
        JSR     jr_port_sound
        LDAA    [RS_EATEN]
        CMPA    [RS_GOAL]
        BEQ     rs_act_done_near305
        JMP     rs_act_done
rs_act_done_near305:
        JMP     jr_port_win
rs_tick_lose:
        ; X = the message; the collision cell flashes
        STX     [RS_MSG]
        LDAA    [RS_P]
        INCA
        STAA    [RS_HIT]
        LDAA    8
        JSR     jr_test_animate
        LDX     [RS_MSG]
        JMP     jr_port_lose

; A = position, B = direction 1-4 -> A = moved position (8x8, stops at edges).
rs_move:
        STAA    [RS_T]
        CMPB    JR_KEY_UP
        BNE     rs_move_down
        CMPA    8
        BCS     rs_move_done
        SUBA    8
        RTS
rs_move_down:
        CMPB    JR_KEY_DOWN
        BNE     rs_move_side
        CMPA    56
        BCC     rs_move_done
        ADDA    8
        RTS
rs_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     rs_move_right
        TSTA
        BEQ     rs_move_stay
        LDAA    [RS_T]
        DECA
        RTS
rs_move_right:
        CMPA    7
        BCC     rs_move_stay
        LDAA    [RS_T]
        INCA
        RTS
rs_move_stay:
        LDAA    [RS_T]
rs_move_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = cell, B = the cell it slides from -> A = x, B = y half-way between them.
rs_between:
        STAB    [RS_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [RS_DT]
        STAB    [RS_DY]
        LDAA    [RS_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [RS_DT]
        INCA
        ADDB    [RS_DY]
        ADDB    3
        RTS

; A = cell, [JR_RT_COLOR] set, [RS_DCODE] = tile: draw it on its own cell.
rs_put_cell:
        TAB
        JSR     rs_between
        JSR     jr_gfx_at
        LDAA    [RS_DCODE]
        JMP     jr_gfx_tile

game_draw:
        LDAA    0x20
        LDAB    RS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     rs_hud
        JSR     jr_gfx_lines
        CLR     [RS_DI]
rs_draw_cell:
        LDAA    RS_TILE_FLOOR
        LDAB    RS_ATTR_FLOOR
        LDX     RS_D
        STAA    [RS_DCODE]
        LDAA    [RS_DI]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     rs_draw_cell_put
        LDAA    RS_TILE_ROCK
        STAA    [RS_DCODE]
        LDAB    RS_ATTR_ROCK
rs_draw_cell_put:
        STAB    [JR_RT_COLOR]
        LDAA    [RS_DI]
        JSR     rs_put_cell
        INC     [RS_DI]
        LDAA    [RS_DI]
        CMPA    64
        BNE     rs_draw_cell
        ; food, then the ribbon from the tail to the head
        LDAA    RS_ATTR_FOOD
        TST     [RS_SPARK]
        BEQ     rs_draw_food
        LDAA    RS_ATTR_HIT
rs_draw_food:
        STAA    [JR_RT_COLOR]
        LDAA    RS_TILE_FOOD
        STAA    [RS_DCODE]
        LDAA    [RS_FOOD]
        TST     [RS_SPARK]
        BEQ     rs_draw_food_at
        LDAA    [RS_SPARK]
        DECA
rs_draw_food_at:
        JSR     rs_put_cell
        LDAA    [RS_LENGTH]
        STAA    [RS_DI]
rs_draw_body:
        DEC     [RS_DI]
        LDX     RS_B
        LDAA    [RS_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X]
        TST     [RS_SLIDING]
        BEQ     rs_draw_body_at
        LDAB    [X + 84]
rs_draw_body_at:
        JSR     rs_between
        JSR     jr_gfx_at
        LDAA    RS_ATTR_BODY
        LDAB    RS_TILE_BODY
        TST     [RS_DI]
        BNE     rs_draw_body_tile
        LDAA    [RS_DIR]
        DECA
        ASLA
        ASLA
        ADDA    RS_TILE_HEAD
        TAB
        LDAA    RS_ATTR_HEAD
rs_draw_body_tile:
        STAA    [JR_RT_COLOR]
        TBA
        JSR     jr_gfx_tile
        TST     [RS_DI]
        BNE     rs_draw_body
        ; a collision flashes on its cell
        LDAA    [RS_HIT]
        BEQ     rs_draw_panel
        DECA
        LDAB    RS_ATTR_HIT
        STAB    [JR_RT_COLOR]
        LDAB    RS_TILE_ROCK
        STAB    [RS_DCODE]
        JSR     rs_put_cell
rs_draw_panel:
        LDAA    RS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [RS_LENGTH]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [RS_EATEN]
        JSR     jr_gfx_dec2
        LDAA    8
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [RS_GOAL]
        JSR     jr_gfx_dec2
        LDAA    28
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [RS_BRAKES]
        ADDA    0x30
        JSR     jr_gfx_putc
        TST     [RS_SLOW]
        BEQ     rs_draw_demo
        LDAA    RS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    18
        JSR     jr_gfx_at
        LDX     rs_txt_slow
        JSR     jr_gfx_text
rs_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     rs_draw_done
        LDAA    RS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     rs_txt_demo
        JSR     jr_gfx_text
rs_draw_done:
        RTS

game_draw_title:
        LDX     rs_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    RS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     rs_title_tiles
        STX     [JR_RT_TABLE]
rs_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     rs_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [RS_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [RS_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     rs_title_tile
rs_title_text:
        LDX     rs_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    RS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     rs_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

rs_opposite:
        .db     2, 1, 4, 3

; x, attribute, code, y: a ribbon winding under the name
rs_title_tiles:
        .db     6, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     8, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     10, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     12, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     14, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     16, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     18, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     20, RS_ATTR_BODY, RS_TILE_BODY, 3
        .db     22, RS_ATTR_HEAD, RS_TILE_HEAD + 12, 3
        .db     25, RS_ATTR_FOOD, RS_TILE_FOOD, 3
        .db     6, RS_ATTR_BODY, RS_TILE_BODY, 5
        .db     2, RS_ATTR_ROCK, RS_TILE_ROCK, 5
        .db     27, RS_ATTR_ROCK, RS_TILE_ROCK, 5
        .db     0xff

rs_hud:
        .db     1, 0, RS_ATTR_TITLE
        .dw     rs_txt_name
        .db     20, 3, RS_ATTR_TITLE
        .dw     rs_txt_ribbon
        .db     20, 6, RS_ATTR_LABEL
        .dw     rs_txt_length
        .db     20, 13, RS_ATTR_LABEL
        .dw     rs_txt_eaten
        .db     20, 17, RS_ATTR_LABEL
        .dw     rs_txt_brakes
        .db     2, 20, RS_ATTR_LABEL
        .dw     rs_txt_goal
        .db     0xff
rs_title_lines:
        .db     10, 8, RS_ATTR_TITLE
        .dw     rs_txt_name
        .db     4, 10, RS_ATTR_LABEL
        .dw     rs_txt_tagline
        .db     4, 13, RS_ATTR_TEXT
        .dw     rs_txt_start
        .db     4, 15, RS_ATTR_TEXT
        .dw     rs_txt_howto
        .db     4, 17, RS_ATTR_DIM
        .dw     rs_txt_demo_hint
        .db     4, 19, RS_ATTR_DIM
        .dw     rs_txt_credit
        .db     0xff
rs_help_lines:
        .db     10, 1, RS_ATTR_TITLE
        .dw     rs_txt_name
        .db     1, 3, RS_ATTR_TEXT
        .dw     rs_help_1
        .db     1, 5, RS_ATTR_TEXT
        .dw     rs_help_2
        .db     1, 7, RS_ATTR_TEXT
        .dw     rs_help_3
        .db     1, 9, RS_ATTR_TEXT
        .dw     rs_help_4
        .db     1, 11, RS_ATTR_TEXT
        .dw     rs_help_5
        .db     1, 13, RS_ATTR_TEXT
        .dw     rs_help_6
        .db     1, 15, RS_ATTR_TEXT
        .dw     rs_help_7
        .db     1, 17, RS_ATTR_TEXT
        .dw     rs_help_8
        .db     1, 21, RS_ATTR_LABEL
        .dw     rs_help_back
        .db     0xff

rs_txt_name:
        .db     "RIBBON SNAKE", 0
rs_txt_ribbon:
        .db     "RIBBON", 0
rs_txt_length:
        .db     "LENGTH", 0
rs_txt_eaten:
        .db     "EATEN", 0
rs_txt_brakes:
        .db     "BRAKES", 0
rs_txt_slow:
        .db     "SLOW", 0
rs_txt_goal:
        .db     "GOAL", 0
rs_txt_demo:
        .db     "DEMO", 0
rs_txt_edge:
        .db     "THE HEAD HIT THE EDGE", 0
rs_txt_rock:
        .db     "THE HEAD HIT A ROCK", 0
rs_txt_body:
        .db     "THE HEAD HIT ITS OWN BODY", 0
rs_txt_tagline:
        .db     "EAT, GROW, NEVER BITE BACK", 0
rs_txt_start:
        .db     "RETURN : START", 0
rs_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
rs_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
rs_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
rs_help_1:
        .db     "WASD : STEER THE HEAD", 0
rs_help_2:
        .db     "RETURN : BRAKE FOR FOUR MOVES", 0
rs_help_3:
        .db     "THREE BRAKES FOR EACH GARDEN.", 0
rs_help_4:
        .db     "AVOID ROCKS, EDGES AND BODY.", 0
rs_help_5:
        .db     "FOOD GROWS THE RIBBON.", 0
rs_help_6:
        .db     "SIX GARDENS ADD NARROW ROUTES.", 0
rs_help_7:
        .db     "REVERSING DIRECTION IS IGNORED.", 0
rs_help_8:
        .db     "SPACE : RETRY THE GARDEN", 0
rs_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     rs_sfx_brake, rs_sfx_eat, rs_jingle_win, rs_jingle_lose
rs_sfx_brake:
        .db     120, 2, 150, 2, 180, 4, 0, 0
rs_sfx_eat:
        .db     45, 2, 36, 2, 30, 4, 0, 0

; Title: a winding waltz in C major, eighth note = 8 frames, looping.
rs_title_song:
        .db     1
        .dw     rs_title_melody, rs_title_harmony, rs_title_bass
rs_title_melody:
        .db     AU_E5, 8, AU_G5, 8, AU_E5, 8, AU_D5, 8, AU_C5, 16
        .db     AU_D5, 8, AU_F5, 8, AU_D5, 8, AU_B4, 8, AU_G4, 16
        .db     AU_A4, 8, AU_C5, 8, AU_E5, 8, AU_A5, 8, AU_G5, 16
        .db     AU_F5, 8, AU_D5, 8, AU_B4, 8, AU_D5, 8, AU_C5, 16, 0, 0
rs_title_harmony:
        .db     AU_C5, 48, AU_B4, 48, AU_C5, 48, AU_B4, 24, AU_G4, 24, 0, 0
rs_title_bass:
        .db     AU_C3, 16, AU_G3, 16, AU_G3, 16, AU_G2, 16, AU_D3, 16, AU_D3, 16
        .db     AU_A2, 16, AU_E3, 16, AU_E3, 16, AU_G2, 16, AU_G3, 16, AU_C3, 16, 0, 0

; Garden cleared: C major run.
rs_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     rs_win_melody, rs_win_harmony, rs_win_bass
rs_win_melody:
        .db     AU_C5, 6, AU_E5, 6, AU_G5, 6, AU_C6, 6, AU_E6, 30, 0, 0
rs_win_harmony:
        .db     AU_G4, 12, AU_C5, 12, AU_G5, 30, 0, 0
rs_win_bass:
        .db     AU_C3, 12, AU_G2, 12, AU_C2, 30, 0, 0
rs_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     rs_lose_melody, rs_lose_harmony, rs_lose_bass
rs_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
rs_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
rs_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


        .include "selftest.inc"
        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/audio.inc"
        .include "../../../sdk/audio_notes.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/selftest.inc"
        .include "../../../sdk/font_data.inc"

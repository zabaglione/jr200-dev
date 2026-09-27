; SPDX-License-Identifier: MIT
; POTION PATH for JR-200: a port of jr100dev games/potion_path/rules.py 3.0.0.
; The orders, poison cells, pars, the four ingredient moves and stocks and
; the twelve-dose limit follow the upstream source; display, colour and
; three-voice sound use the JR-200 port SDK.
        .filename.jr "POTION-PATH"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    20
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[64] and c[4].
PP_X:               .equ    GAME_STATE
PP_Y:               .equ    GAME_STATE + 1
PP_TX:              .equ    GAME_STATE + 2
PP_TY:              .equ    GAME_STATE + 3
PP_ING:             .equ    GAME_STATE + 4
PP_NOTICE:          .equ    GAME_STATE + 5
PP_POURING:         .equ    GAME_STATE + 6
PP_DOSES:           .equ    GAME_STATE + 7
PP_B:               .equ    GAME_STATE + 8
PP_C:               .equ    GAME_STATE + 72
; Effect and rule work bytes.
PP_NX:              .equ    GAME_STATE + 80
PP_NY:              .equ    GAME_STATE + 81
PP_EFFECT:          .equ    GAME_STATE + 82
PP_ECODE:           .equ    GAME_STATE + 83
PP_EATTR:           .equ    GAME_STATE + 84
PP_EX:              .equ    GAME_STATE + 85
PP_EY:              .equ    GAME_STATE + 86
PP_FX:              .equ    GAME_STATE + 87
PP_FY:              .equ    GAME_STATE + 88
PP_GX:              .equ    GAME_STATE + 89
PP_GY:              .equ    GAME_STATE + 90
PP_FRAME:           .equ    GAME_STATE + 91
PP_IA:              .equ    GAME_STATE + 92
PP_I:               .equ    GAME_STATE + 93
; Drawing work bytes.
PP_DI:              .equ    GAME_STATE + 100

PP_TILE_FLOOR:      .equ    0x80
PP_TILE_POISON:     .equ    0x84
PP_TILE_TARGET:     .equ    0x88
PP_TILE_FLASK:      .equ    0x8c
PP_TILE_SPARK:      .equ    0x00
PP_ATTR_FLOOR:      .equ    0x41
PP_ATTR_POISON:     .equ    0x42
PP_ATTR_TARGET:     .equ    0x46
PP_ATTR_FLASK:      .equ    0x43        ; a magenta potion
PP_ATTR_SPARK:      .equ    0x46
PP_ATTR_TEXT:       .equ    0x07
PP_ATTR_LABEL:      .equ    0x04
PP_ATTR_TITLE:      .equ    0x06
PP_ATTR_DIM:        .equ    0x05
PP_ATTR_PICK:       .equ    0x06
PP_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     pp_patterns
        LDAA    PP_TILE_FLOOR
        LDAB    16
        JSR     jr_pcg_load
        LDX     pp_spark_patterns
        CLRA
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    3
        STAA    [PP_X]
        STAA    [PP_Y]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        LDX     pp_orders
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [PP_TX]
        LDAA    [X + 1]
        STAA    [PP_TY]
        ; seven poison cells per recipe (255 = none)
        LDAA    [JR_PORT_LEVEL]
        LDAB    7
        JSR     jr_mul8
        STAA    [PP_I]
        LDAB    7
pp_init_poison:
        PSHB
        LDAA    [PP_I]
        LDX     pp_hazards
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    0xff
        BEQ     pp_init_next
        LDX     PP_B
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
pp_init_next:
        INC     [PP_I]
        PULB
        DECB
        BNE     pp_init_poison
        LDAA    4
        STAA    [PP_C]
        STAA    [PP_C + 1]
        STAA    [PP_C + 2]
        STAA    [PP_C + 3]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        LDAB    3
        CMPA    JR_KEY_UP
        BEQ     pp_act_pick
        CMPA    JR_KEY_LEFT
        BEQ     pp_act_pick
        LDAB    1
        CMPA    JR_KEY_DOWN
        BEQ     pp_act_pick
        CMPA    JR_KEY_RIGHT
        BEQ     pp_act_pick
        CMPA    JR_KEY_CONFIRM
        BEQ     pp_pour
        RTS
pp_act_pick:
        ADDB    [PP_ING]
        ANDB    3
        STAB    [PP_ING]
        RTS

pp_pour:
        LDAA    [PP_ING]
        LDX     PP_C
        JSR     jr_add_x_a
        TST     [X]
        BNE     pp_pour_move
        LDAA    1
        STAA    [PP_NOTICE]
        JMP     pp_buzz
pp_pour_move:
        CLR     [PP_NOTICE]
        ; ASH left 2, MOSS right 1 down 2, SALT up 1, ROOT right 3 down 1
        LDAA    [PP_X]
        LDAB    [PP_Y]
        TST     [PP_ING]
        BNE     pp_pour_moss
        CMPA    2
        BCS     pp_pour_none
        SUBA    2
        BRA     pp_pour_land
pp_pour_moss:
        PSHA
        LDAA    [PP_ING]
        CMPA    1
        PULA
        BNE     pp_pour_salt
        CMPA    7
        BCC     pp_pour_none
        CMPB    6
        BCC     pp_pour_none
        INCA
        ADDB    2
        BRA     pp_pour_land
pp_pour_salt:
        PSHA
        LDAA    [PP_ING]
        CMPA    2
        PULA
        BNE     pp_pour_root
        TSTB
        BEQ     pp_pour_none
        DECB
        BRA     pp_pour_land
pp_pour_root:
        CMPA    5
        BCC     pp_pour_none
        CMPB    7
        BCC     pp_pour_none
        ADDA    3
        INCB
pp_pour_land:
        STAA    [PP_NX]
        STAB    [PP_NY]
        ASLB
        ASLB
        ASLB
        ABA
        LDX     PP_B
        JSR     jr_add_x_a
        TST     [X]
        BEQ     pp_pour_go
        LDAA    2
        STAA    [PP_NOTICE]
        JMP     pp_buzz
pp_pour_none:
        RTS
pp_pour_go:
        LDAA    [PP_ING]
        LDX     PP_C
        JSR     jr_add_x_a
        DEC     [X]
        LDAA    1
        STAA    [PP_POURING]
        CLRA
        JSR     jr_port_sound
        ; the ingredient flies into the flask, then the potion moves
        LDAA    21
        STAA    [PP_FX]
        LDAA    [PP_ING]
        LDAB    3
        JSR     jr_mul8
        ADDA    5
        STAA    [PP_FY]
        LDAA    [PP_X]
        ASLA
        STAA    [PP_GX]
        LDAA    [PP_Y]
        ASLA
        ADDA    3
        STAA    [PP_GY]
        LDAA    [PP_ING]
        LDX     pp_ingredient_tile
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    PP_TILE_FLASK
        JSR     pp_flight
        LDAA    [PP_GX]
        STAA    [PP_FX]
        LDAA    [PP_GY]
        STAA    [PP_FY]
        LDAA    [PP_NX]
        ASLA
        STAA    [PP_GX]
        LDAA    [PP_NY]
        ASLA
        ADDA    3
        STAA    [PP_GY]
        LDAA    PP_TILE_FLASK
        LDAB    PP_ATTR_FLASK
        JSR     pp_flight
        CLR     [PP_POURING]
        LDAA    [PP_NX]
        STAA    [PP_X]
        LDAA    [PP_NY]
        STAA    [PP_Y]
        INC     [PP_DOSES]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [PP_X]
        CMPA    [PP_TX]
        BNE     pp_pour_limit
        LDAA    [PP_Y]
        CMPA    [PP_TY]
        BNE     pp_pour_limit
        ; the order is ready: a sparkle over it
        LDAA    [PP_TX]
        ASLA
        STAA    [PP_EX]
        LDAA    [PP_TY]
        ASLA
        ADDA    3
        STAA    [PP_EY]
        LDAA    2
        STAA    [PP_EFFECT]
        CLR     [PP_FRAME]
pp_sparkle:
        LDAA    4
        JSR     jr_port_animate
        INC     [PP_FRAME]
        LDAA    [PP_FRAME]
        CMPA    3
        BNE     pp_sparkle
        CLR     [PP_EFFECT]
        JMP     jr_port_win
pp_pour_limit:
        LDAA    [PP_DOSES]
        CMPA    12
        BCS     pp_pour_done
        LDX     pp_txt_lose
        JMP     jr_port_lose
pp_pour_done:
        RTS

pp_buzz:
        LDX     pp_sfx_buzz
        JMP     jr_sfx_play

; A = code, B = attribute: five frames of animate(3) from (FX, FY) to (GX, GY).
pp_flight:
        STAA    [PP_ECODE]
        STAB    [PP_EATTR]
        LDAA    1
        STAA    [PP_EFFECT]
        CLR     [PP_FRAME]
pp_flight_frame:
        LDAA    [PP_FX]
        LDAB    [PP_GX]
        JSR     pp_interp
        STAA    [PP_EX]
        LDAA    [PP_FY]
        LDAB    [PP_GY]
        JSR     pp_interp
        STAA    [PP_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [PP_FRAME]
        LDAA    [PP_FRAME]
        CMPA    5
        BNE     pp_flight_frame
        CLR     [PP_EFFECT]
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
pp_interp:
        STAA    [PP_IA]
        CBA
        BHI     pp_interp_back
        SUBB    [PP_IA]
        TBA
        LDAB    [PP_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [PP_IA]
        RTS
pp_interp_back:
        SBA
        LDAB    [PP_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [PP_IA]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_hud
        JSR     jr_gfx_lines
        LDAA    PP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the board: floor or poison
        CLR     [PP_DI]
pp_draw_cell:
        LDAA    [PP_DI]
        LDX     PP_B
        JSR     jr_add_x_a
        LDAB    PP_ATTR_FLOOR
        LDAA    PP_TILE_FLOOR
        TST     [X]
        BEQ     pp_draw_tile
        LDAB    PP_ATTR_POISON
        LDAA    PP_TILE_POISON
pp_draw_tile:
        STAB    [JR_RT_COLOR]
        PSHA
        LDAA    [PP_DI]
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        ANDA    7
        ASLA
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_tile
        INC     [PP_DI]
        LDAA    [PP_DI]
        CMPA    64
        BNE     pp_draw_cell
        LDAA    PP_ATTR_TARGET
        STAA    [JR_RT_COLOR]
        LDAA    [PP_TX]
        ASLA
        LDAB    [PP_TY]
        ASLB
        ADDB    3
        JSR     jr_gfx_at
        LDAA    PP_TILE_TARGET
        JSR     jr_gfx_tile
        TST     [PP_POURING]
        BNE     pp_draw_shelf
        LDAA    PP_ATTR_FLASK
        STAA    [JR_RT_COLOR]
        LDAA    [PP_X]
        ASLA
        LDAB    [PP_Y]
        ASLB
        ADDB    3
        JSR     jr_gfx_at
        LDAA    PP_TILE_FLASK
        JSR     jr_gfx_tile
pp_draw_shelf:
        ; the four ingredients in their colours, with the stock left
        CLR     [PP_DI]
pp_draw_ingredient:
        LDAA    [PP_DI]
        LDX     pp_ingredient_text
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [PP_DI]
        LDAB    3
        JSR     jr_mul8
        ADDA    5
        TAB
        LDAA    20
        JSR     jr_gfx_at
        LDAA    [PP_DI]
        ASLA
        LDX     pp_ingredient_names
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [PP_DI]
        LDX     PP_C
        JSR     jr_add_x_a
        LDAB    PP_ATTR_TEXT
        TST     [X]
        BNE     pp_draw_stock
        LDAB    PP_ATTR_BAD
pp_draw_stock:
        STAB    [JR_RT_COLOR]
        LDAA    [PP_DI]
        LDAB    3
        JSR     jr_mul8
        ADDA    6
        TAB
        LDAA    29
        JSR     jr_gfx_at
        LDAA    [PP_DI]
        LDX     PP_C
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [PP_DI]
        LDAA    [PP_DI]
        CMPA    4
        BNE     pp_draw_ingredient
        LDAA    PP_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [PP_ING]
        LDAB    3
        JSR     jr_mul8
        ADDA    5
        TAB
        LDAA    18
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; doses, par and the notice
        LDAA    PP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [PP_DOSES]
        JSR     jr_gfx_dec2
        LDAA    5
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        LDX     pp_pars
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_dec2
        LDAA    [PP_NOTICE]
        BEQ     pp_draw_effect
        LDAB    PP_ATTR_BAD
        STAB    [JR_RT_COLOR]
        DECA
        ASLA
        LDX     pp_notice_text
        JSR     jr_add_x_a
        LDX     [X]
        STX     [JR_RT_TABLE]
        LDAA    9
        LDAB    20
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
pp_draw_effect:
        LDAA    [PP_EFFECT]
        BEQ     pp_draw_done
        CMPA    1
        BNE     pp_draw_spark
        LDAA    [PP_EATTR]
        STAA    [JR_RT_COLOR]
        LDAA    [PP_EX]
        LDAB    [PP_EY]
        JSR     jr_gfx_at
        LDAA    [PP_ECODE]
        JMP     jr_gfx_tile
pp_draw_spark:
        LDAA    PP_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    [PP_EX]
        LDAB    [PP_EY]
        JSR     jr_gfx_at
        LDAA    [PP_FRAME]
        ASLA
        ASLA
        ADDA    PP_TILE_SPARK
        JMP     jr_gfx_tile
pp_draw_done:
        RTS

game_draw_title:
        LDX     pp_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_title_tiles
        STX     [JR_RT_TABLE]
pp_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     pp_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [PP_DI]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [PP_DI]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     pp_title_tile
pp_title_text:
        LDX     pp_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

pp_orders:
        .db     1, 2, 3, 1, 5, 7, 7, 6, 1, 1, 3, 0, 4, 3
        .db     6, 2, 0, 4, 1, 7, 3, 6, 5, 5, 7, 4, 1, 6
        .db     3, 5, 5, 4, 6, 7, 0, 2, 2, 1, 4, 0
pp_hazards:
        .db     0, 22, 40, 4, 255, 255, 255, 3, 37, 31, 2, 255, 255, 255
        .db     15, 37, 36, 58, 255, 255, 255, 47, 7, 53, 37, 255, 255, 255
        .db     37, 10, 35, 36, 255, 255, 255, 56, 12, 18, 32, 49, 255, 255
        .db     50, 56, 38, 32, 31, 255, 255, 14, 1, 12, 63, 50, 255, 255
        .db     21, 15, 19, 51, 29, 255, 255, 1, 35, 49, 60, 38, 255, 255
        .db     49, 19, 13, 17, 48, 41, 255, 25, 36, 2, 5, 39, 62, 255
        .db     3, 40, 6, 38, 62, 10, 255, 39, 28, 5, 43, 20, 46, 255
        .db     36, 62, 46, 5, 33, 7, 255, 53, 5, 24, 34, 2, 7, 3
        .db     49, 58, 0, 30, 15, 8, 47, 45, 33, 50, 47, 2, 52, 17
        .db     44, 42, 4, 17, 23, 31, 55, 1, 43, 17, 34, 40, 21, 19
pp_pars:
        .db     2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5
        .db     5, 5, 5, 6, 6, 6

; ASH white, MOSS green, SALT cyan, ROOT red
pp_ingredient_text:
        .db     0x07, 0x04, 0x05, 0x02
pp_ingredient_tile:
        .db     0x47, 0x44, 0x45, 0x42
pp_ingredient_names:
        .dw     pp_txt_ash, pp_txt_moss, pp_txt_salt, pp_txt_root
pp_notice_text:
        .dw     pp_txt_empty, pp_txt_poison

; x, attribute, code, y
pp_title_tiles:
        .db     9, PP_ATTR_FLASK, PP_TILE_FLASK, 3
        .db     13, PP_ATTR_FLOOR, PP_TILE_FLOOR, 3
        .db     17, PP_ATTR_POISON, PP_TILE_POISON, 3
        .db     21, PP_ATTR_TARGET, PP_TILE_TARGET, 3
        .db     0xff

pp_hud:
        .db     1, 0, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     22, 0, PP_ATTR_LABEL
        .dw     pp_txt_order
        .db     18, 2, PP_ATTR_LABEL
        .dw     pp_txt_recipe
        .db     18, 19, PP_ATTR_LABEL
        .dw     pp_txt_doses
        .db     1, 20, PP_ATTR_LABEL
        .dw     pp_txt_par
        .db     0xff
pp_title_lines:
        .db     10, 8, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     3, 10, PP_ATTR_LABEL
        .dw     pp_txt_tagline
        .db     8, 15, PP_ATTR_TEXT
        .dw     pp_txt_start
        .db     5, 17, PP_ATTR_TEXT
        .dw     pp_txt_howto
        .db     4, 22, PP_ATTR_DIM
        .dw     pp_txt_credit
        .db     0xff
pp_help_lines:
        .db     10, 1, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     1, 3, PP_ATTR_TEXT
        .dw     pp_help_1
        .db     1, 5, PP_ATTR_TEXT
        .dw     pp_help_2
        .db     1, 7, PP_ATTR_TEXT
        .dw     pp_help_3
        .db     1, 9, PP_ATTR_TEXT
        .dw     pp_help_4
        .db     1, 11, PP_ATTR_TEXT
        .dw     pp_help_5
        .db     1, 13, PP_ATTR_TEXT
        .dw     pp_help_6
        .db     1, 15, PP_ATTR_TEXT
        .dw     pp_help_7
        .db     1, 17, PP_ATTR_TEXT
        .dw     pp_help_8
        .db     1, 19, PP_ATTR_TEXT
        .dw     pp_help_9
        .db     1, 21, PP_ATTR_LABEL
        .dw     pp_help_back
        .db     0xff

pp_txt_name:
        .db     "POTION PATH", 0
pp_txt_order:
        .db     "ORDER", 0
pp_txt_recipe:
        .db     "RECIPE", 0
pp_txt_ash:
        .db     "ASH  L2", 0
pp_txt_moss:
        .db     "MOSS R1 D2", 0
pp_txt_salt:
        .db     "SALT U1", 0
pp_txt_root:
        .db     "ROOT R3 D1", 0
pp_txt_doses:
        .db     "DOSES", 0
pp_txt_par:
        .db     "PAR", 0
pp_txt_empty:
        .db     "INGREDIENT EMPTY", 0
pp_txt_poison:
        .db     "POISON LANDING", 0
pp_txt_lose:
        .db     "TWELVE DOSES MISSED THE RECIPE", 0
pp_txt_tagline:
        .db     "FOUR INGREDIENTS, ONE ORDER", 0
pp_txt_start:
        .db     "RETURN : START", 0
pp_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
pp_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
pp_help_1:
        .db     "WASD : SELECT INGREDIENT", 0
pp_help_2:
        .db     "RETURN : ADD TO THE FLASK", 0
pp_help_3:
        .db     "FOUR DOSES OF EACH INGREDIENT.", 0
pp_help_4:
        .db     "RED CELLS REJECT A LANDING.", 0
pp_help_5:
        .db     "ASH L2 / MOSS R1 D2", 0
pp_help_6:
        .db     "SALT U1 / ROOT R3 D1", 0
pp_help_7:
        .db     "REACH THE ORDER IN 12 DOSES.", 0
pp_help_8:
        .db     "TRY TO MATCH THE PAR SCORE.", 0
pp_help_9:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
pp_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     pp_sfx_pour, pp_sfx_brew, pp_jingle_win, pp_jingle_lose
pp_sfx_pour:
        .db     40, 2, 50, 2, 60, 2, 0, 0
pp_sfx_brew:
        .db     90, 3, 70, 3, 0, 0
pp_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a bubbling witch's waltz in A minor, quarter note = 12 frames, looping.
pp_title_song:
        .db     1
        .dw     pp_title_melody, pp_title_harmony, pp_title_bass
pp_title_melody:
        .db     AU_E5, 12, AU_A5, 12, AU_C6, 12, AU_B5, 24, AU_GS5, 12
        .db     AU_A5, 12, AU_E5, 12, AU_C5, 12, AU_D5, 24, AU_B4, 12
        .db     AU_C5, 12, AU_E5, 12, AU_A5, 12, AU_GS5, 24, AU_B5, 12
        .db     AU_A5, 36, 0, 36, 0, 0
pp_title_harmony:
        .db     AU_C5, 36, AU_E5, 36, AU_C5, 36, AU_GS4, 36
        .db     AU_A4, 36, AU_B4, 36, AU_C5, 36, 0, 36, 0, 0
pp_title_bass:
        .db     AU_A2, 12, AU_E3, 12, AU_E3, 12, AU_E2, 12, AU_E3, 12, AU_E3, 12
        .db     AU_A2, 12, AU_E3, 12, AU_E3, 12, AU_E2, 12, AU_GS2, 12, AU_B2, 12
        .db     AU_A2, 12, AU_C3, 12, AU_E3, 12, AU_E2, 12, AU_E3, 12, AU_E3, 12
        .db     AU_A2, 36, 0, 36, 0, 0

; Brewed: A major arpeggio over the tonic (54 frames).
pp_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     pp_win_melody, pp_win_harmony, pp_win_bass
pp_win_melody:
        .db     AU_A5, 8, AU_CS6, 8, AU_E6, 8, AU_A6, 30, 0, 0
pp_win_harmony:
        .db     AU_E5, 8, AU_A5, 8, AU_CS6, 8, AU_E6, 30, 0, 0
pp_win_bass:
        .db     AU_A3, 24, AU_A2, 30, 0, 0
pp_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     pp_lose_melody, pp_lose_harmony, pp_lose_bass
pp_lose_melody:
        .db     AU_E5, 12, AU_DS5, 12, AU_D5, 12, AU_CS5, 30, 0, 0
pp_lose_harmony:
        .db     AU_C5, 12, AU_B4, 12, AU_AS4, 12, AU_A4, 30, 0, 0
pp_lose_bass:
        .db     AU_A3, 36, AU_E3, 30, 0, 0

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
        .include "../../../sdk/font_data.inc"

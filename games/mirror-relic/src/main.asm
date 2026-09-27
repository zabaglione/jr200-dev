; SPDX-License-Identifier: MIT
; MIRROR RELIC for JR-200: a port of jr100dev games/mirror_relic/rules.py 3.0.0.
; The quartered hall, the clockwise/counterclockwise mirror turns, the phase
; letters A-D and the twenty-turn limit follow the upstream source; display,
; colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "MIRROR-RELIC"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[64] and c[64].
MR_FACING:          .equ    GAME_STATE
MR_POS:             .equ    GAME_STATE + 1
MR_ORIGIN:          .equ    GAME_STATE + 2
MR_LEFT:            .equ    GAME_STATE + 3
MR_TURNS:           .equ    GAME_STATE + 4
MR_PHASE:           .equ    GAME_STATE + 5
MR_ROTATING:        .equ    GAME_STATE + 6
MR_B:               .equ    GAME_STATE + 7
MR_C:               .equ    GAME_STATE + 71
; Effect state and rule work bytes.
MR_EFFECT:          .equ    GAME_STATE + 135
MR_EX:              .equ    GAME_STATE + 136
MR_EY:              .equ    GAME_STATE + 137
MR_EPHASE:          .equ    GAME_STATE + 138
MR_FRAME:           .equ    GAME_STATE + 139
MR_N:               .equ    GAME_STATE + 140
MR_ACTION:          .equ    GAME_STATE + 141
MR_MP:              .equ    GAME_STATE + 142
MR_MA:              .equ    GAME_STATE + 143
MR_MC:              .equ    GAME_STATE + 144
MR_IA:              .equ    GAME_STATE + 145
MR_FX:              .equ    GAME_STATE + 146
MR_FY:              .equ    GAME_STATE + 147
MR_TX:              .equ    GAME_STATE + 148
MR_TY:              .equ    GAME_STATE + 149
MR_K:               .equ    GAME_STATE + 150
; Drawing work bytes.
MR_DI:              .equ    GAME_STATE + 160
MR_DK:              .equ    GAME_STATE + 161
MR_DCODE:           .equ    GAME_STATE + 162
MR_DN:              .equ    GAME_STATE + 163

MR_EXIT:            .equ    53
MR_START:           .equ    54
MR_LIMIT:           .equ    20
MR_TILE_FLOOR:      .equ    0x80
MR_TILE_WALL:       .equ    0x84
MR_TILE_EXIT:       .equ    0x88
MR_TILE_RELIC:      .equ    0x8c
MR_TILE_HERO:       .equ    0x90        ; + 4 * (facing - 1)
MR_TILE_SPARK:      .equ    0x00
MR_ATTR_FLOOR:      .equ    0x41
MR_ATTR_WALL:       .equ    0x4f        ; white relief on blue
MR_ATTR_EXIT:       .equ    0x44
MR_ATTR_OPEN:       .equ    0x46
MR_ATTR_HERO:       .equ    0x47
MR_ATTR_SPARK:      .equ    0x46
MR_ATTR_ARROW:      .equ    0x05
MR_ATTR_TEXT:       .equ    0x07
MR_ATTR_LABEL:      .equ    0x04
MR_ATTR_TITLE:      .equ    0x06
MR_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     mr_patterns
        LDAA    0x80
        LDAB    32
        JSR     jr_pcg_load
        LDX     mr_spark_patterns
        CLRA
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    2
        STAA    [MR_FACING]
        ; walls on column 3 and row 3, four passages, the exit at 53
        LDX     MR_B
        CLRA
mr_init_cell:
        PSHA
        CLRB
        PSHA
        ANDA    7
        CMPA    3
        PULA
        BEQ     mr_init_wall
        LSRA
        LSRA
        LSRA
        CMPA    3
        BNE     mr_init_store
mr_init_wall:
        LDAB    1
mr_init_store:
        STAB    [X]
        INX
        PULA
        INCA
        CMPA    64
        BNE     mr_init_cell
        CLR     [MR_B + 19]
        CLR     [MR_B + 43]
        CLR     [MR_B + 26]
        CLR     [MR_B + 29]
        LDAA    6
        STAA    [MR_B + MR_EXIT]
        LDAA    MR_START
        STAA    [MR_POS]
        STAA    [MR_ORIGIN]
        ; c[relics[level * 3 + k]] = 1 + (level + 1 + k) % 4
        CLR     [MR_K]
mr_init_relic:
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_mul8
        ADDA    [MR_K]
        LDX     mr_relics
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     MR_C
        JSR     jr_add_x_a
        LDAA    [JR_PORT_LEVEL]
        INCA
        ADDA    [MR_K]
        ANDA    3
        INCA
        STAA    [X]
        INC     [MR_K]
        LDAA    [MR_K]
        CMPA    3
        BNE     mr_init_relic
        LDAA    3
        STAA    [MR_LEFT]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        STAA    [MR_ACTION]
        CMPA    JR_KEY_CONFIRM
        BCC     mr_act_turn
        STAA    [MR_FACING]
        TAB
        LDAA    [MR_POS]
        JSR     mr_move
        STAA    [MR_N]
        JSR     mr_cell_b
        CMPA    1
        BEQ     mr_act_collect
        LDAA    [MR_POS]
        STAA    [MR_ORIGIN]
        LDAA    [MR_N]
        STAA    [MR_POS]
        CMPA    [MR_ORIGIN]
        BEQ     mr_act_collect
        CLRA
        JSR     jr_port_sound
        LDAA    2
        JSR     jr_port_animate
        LDAA    [MR_POS]
        STAA    [MR_ORIGIN]
        BRA     mr_act_collect
mr_act_turn:
        CMPA    JR_KEY_CONFIRM
        BEQ     mr_act_turn_go
        CMPA    7
        BNE     mr_act_collect
mr_act_turn_go:
        JSR     mr_turn_target
        STAA    [MR_N]
        JSR     mr_cell_b
        CMPA    1
        BEQ     mr_act_collect
        LDAA    1
        STAA    [MR_ROTATING]
        LDX     mr_sfx_turn
        JSR     jr_sfx_play
        LDAA    [MR_POS]
        LDAB    [MR_N]
        JSR     mr_flight
        CLR     [MR_ROTATING]
        LDAA    [MR_N]
        STAA    [MR_POS]
        STAA    [MR_ORIGIN]
        INC     [MR_TURNS]
        LDAB    1
        LDAA    [MR_ACTION]
        CMPA    JR_KEY_CONFIRM
        BEQ     mr_act_phase
        LDAB    3
mr_act_phase:
        ADDB    [MR_PHASE]
        ANDB    3
        STAB    [MR_PHASE]
        LDAA    1
        JSR     jr_port_sound
mr_act_collect:
        ; if c[pos] == phase + 1: take the relic
        LDAA    [MR_POS]
        LDX     MR_C
        JSR     jr_add_x_a
        LDAA    [MR_PHASE]
        INCA
        CMPA    [X]
        BNE     mr_act_end
        CLR     [X]
        DEC     [MR_LEFT]
        LDAA    1
        JSR     jr_port_sound
        JSR     mr_sparkle
mr_act_end:
        LDAA    [MR_POS]
        CMPA    MR_EXIT
        BNE     mr_act_limit
        TST     [MR_LEFT]
        BNE     mr_act_limit
        JMP     jr_port_win
mr_act_limit:
        LDAA    [MR_TURNS]
        CMPA    MR_LIMIT
        BCS     mr_act_done
        LDX     mr_txt_lose
        JMP     jr_port_lose
mr_act_done:
        RTS

; A = cell -> A = b[cell]. Clobbers X.
mr_cell_b:
        LDX     MR_B
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; A = target of the turn for MR_ACTION (5 clockwise, 7 counterclockwise).
mr_turn_target:
        LDAA    [MR_POS]
        ANDA    7
        STAA    [MR_MC]
        LDAB    [MR_POS]
        LSRB
        LSRB
        LSRB
        LDAA    [MR_ACTION]
        CMPA    JR_KEY_CONFIRM
        BNE     mr_turn_ccw
        ; (pos % 8) * 8 + 7 - pos // 8
        LDAA    [MR_MC]
        ASLA
        ASLA
        ASLA
        ADDA    7
        SBA
        RTS
mr_turn_ccw:
        ; (7 - pos % 8) * 8 + pos // 8
        LDAA    7
        SUBA    [MR_MC]
        ASLA
        ASLA
        ASLA
        ABA
        RTS

; A = from cell, B = to cell: the explorer flies there in five animate(3).
mr_flight:
        PSHB
        JSR     mr_cell_xy
        STAA    [MR_FX]
        STAB    [MR_FY]
        PULA
        JSR     mr_cell_xy
        STAA    [MR_TX]
        STAB    [MR_TY]
        LDAA    1
        STAA    [MR_EFFECT]
        CLR     [MR_FRAME]
mr_flight_frame:
        LDAA    [MR_FX]
        LDAB    [MR_TX]
        JSR     mr_interp
        STAA    [MR_EX]
        LDAA    [MR_FY]
        LDAB    [MR_TY]
        JSR     mr_interp
        STAA    [MR_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [MR_FRAME]
        LDAA    [MR_FRAME]
        CMPA    5
        BNE     mr_flight_frame
        CLR     [MR_EFFECT]
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
mr_interp:
        STAA    [MR_IA]
        CBA
        BHI     mr_interp_back
        SUBB    [MR_IA]
        TBA
        LDAB    [MR_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [MR_IA]
        RTS
mr_interp_back:
        SBA
        LDAB    [MR_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [MR_IA]
        RTS

; sparkle at the explorer: three phases of animate(4).
mr_sparkle:
        LDAA    [MR_POS]
        JSR     mr_cell_xy
        STAA    [MR_EX]
        STAB    [MR_EY]
        LDAA    2
        STAA    [MR_EFFECT]
        CLR     [MR_FRAME]
mr_sparkle_phase:
        LDAA    [MR_FRAME]
        STAA    [MR_EPHASE]
        LDAA    4
        JSR     jr_port_animate
        INC     [MR_FRAME]
        LDAA    [MR_FRAME]
        CMPA    3
        BNE     mr_sparkle_phase
        CLR     [MR_EFFECT]
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
mr_move:
        STAA    [MR_MP]
        STAB    [MR_MA]
        ANDA    7
        STAA    [MR_MC]
        LDAA    [MR_MP]
        CMPB    JR_KEY_UP
        BNE     mr_move_down
        CMPA    8
        BCS     mr_move_done
        SUBA    8
        RTS
mr_move_down:
        CMPB    JR_KEY_DOWN
        BNE     mr_move_left
        CMPA    56
        BCC     mr_move_done
        ADDA    8
        RTS
mr_move_left:
        CMPB    JR_KEY_LEFT
        BNE     mr_move_right
        TST     [MR_MC]
        BEQ     mr_move_done
        DECA
        RTS
mr_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     mr_move_done
        LDAB    [MR_MC]
        CMPB    7
        BCC     mr_move_done
        INCA
mr_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    MR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mr_hud
        JSR     jr_gfx_lines
        LDAA    MR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        CLR     [MR_DI]
mr_draw_cell:
        LDAA    [MR_DI]
        LDX     MR_B
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     mr_cell_codes
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 7]
        CMPA    MR_TILE_EXIT
        BNE     mr_draw_relic
        TST     [MR_LEFT]
        BNE     mr_draw_relic
        LDAB    MR_ATTR_OPEN
mr_draw_relic:
        STAA    [MR_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [MR_DI]
        LDX     MR_C
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     mr_draw_tile
        STAA    [MR_DK]
        LDX     mr_phase_attr - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    MR_TILE_RELIC
        STAA    [MR_DCODE]
mr_draw_tile:
        LDAA    [MR_DI]
        JSR     mr_cell_xy
        JSR     jr_gfx_at
        LDAA    [MR_DCODE]
        JSR     jr_gfx_tile
        ; the relic's phase letter over its top-left cell
        LDAA    [MR_DI]
        LDX     MR_C
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     mr_draw_next
        LDX     mr_phase_attr - 1
        JSR     jr_add_x_a
        LDAA    [X]
        ANDA    0x07
        STAA    [JR_RT_COLOR]
        LDAA    [MR_DI]
        JSR     mr_cell_xy
        JSR     jr_gfx_at
        LDAA    [MR_DK]
        ADDA    0x40
        JSR     jr_gfx_putc
mr_draw_next:
        INC     [MR_DI]
        LDAA    [MR_DI]
        CMPA    64
        BEQ     mr_draw_arrow
        JMP     mr_draw_cell
mr_draw_arrow:
        ; the clockwise arrow: n = (pos % 8) * 8 + 7 - pos // 8
        LDAA    [MR_POS]
        ANDA    7
        ASLA
        ASLA
        ASLA
        ADDA    7
        LDAB    [MR_POS]
        LSRB
        LSRB
        LSRB
        SBA
        STAA    [MR_DN]
        LDX     MR_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    1
        BEQ     mr_draw_hero
        LDAA    [X + 64]
        BNE     mr_draw_hero
        LDAA    [MR_DN]
        CMPA    [MR_POS]
        BEQ     mr_draw_hero
        LDAA    MR_ATTR_ARROW
        STAA    [JR_RT_COLOR]
        LDAA    [MR_DN]
        JSR     mr_cell_xy
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
mr_draw_hero:
        TST     [MR_ROTATING]
        BNE     mr_draw_effect
        LDAA    MR_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [MR_POS]
        JSR     mr_cell_xy
        JSR     jr_gfx_at
        JSR     mr_hero_code
        JSR     jr_gfx_tile
mr_draw_effect:
        LDAA    [MR_EFFECT]
        BEQ     mr_draw_hud
        LDAA    [MR_EX]
        LDAB    [MR_EY]
        JSR     jr_gfx_at
        LDAA    [MR_EFFECT]
        CMPA    1
        BNE     mr_draw_spark
        LDAA    MR_ATTR_HERO
        STAA    [JR_RT_COLOR]
        JSR     mr_hero_code
        JSR     jr_gfx_tile
        BRA     mr_draw_hud
mr_draw_spark:
        LDAA    MR_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    [MR_EPHASE]
        ASLA
        ASLA
        JSR     jr_gfx_tile
mr_draw_hud:
        LDAA    MR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [MR_LEFT]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [MR_TURNS]
        JSR     jr_gfx_dec2
        LDX     mr_txt_of_limit
        JSR     jr_gfx_text
        LDAA    [MR_PHASE]
        LDX     mr_phase_attr
        JSR     jr_add_x_a
        LDAA    [X]
        ANDA    0x07
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [MR_PHASE]
        ADDA    0x41
        JSR     jr_gfx_putc
        LDAA    MR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDX     mr_txt_turning
        TST     [MR_ROTATING]
        BNE     mr_draw_status
        LDX     mr_txt_open
        TST     [MR_LEFT]
        BEQ     mr_draw_status
        RTS
mr_draw_status:
        JMP     jr_gfx_text

; A = tile code of the explorer for the current facing.
mr_hero_code:
        LDAA    [MR_FACING]
        DECA
        ASLA
        ASLA
        ADDA    MR_TILE_HERO
        RTS

; A = cell -> A = cell % 8 * 2, B = 3 + cell // 8 * 2.
mr_cell_xy:
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        ANDA    7
        ASLA
        RTS

game_draw_title:
        LDX     mr_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    MR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mr_title_tiles
        STX     [JR_RT_TABLE]
mr_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     mr_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [MR_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [MR_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     mr_title_tile
mr_title_text:
        LDX     mr_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    MR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mr_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0

mr_relics:
        .db     10, 21, 42, 0, 14, 49, 17, 6, 61, 8, 23, 40, 2, 13, 57, 16, 7, 48

; Tile code, then its attribute 7 bytes later, by b[i] (0 floor, 1 wall, 6 exit).
mr_cell_codes:
        .db     MR_TILE_FLOOR, MR_TILE_WALL, MR_TILE_FLOOR, MR_TILE_FLOOR
        .db     MR_TILE_FLOOR, MR_TILE_FLOOR, MR_TILE_EXIT
        .db     MR_ATTR_FLOOR, MR_ATTR_WALL, MR_ATTR_FLOOR, MR_ATTR_FLOOR
        .db     MR_ATTR_FLOOR, MR_ATTR_FLOOR, MR_ATTR_EXIT

; Relic colour for phase letters A-D: red, magenta, green, cyan.
mr_phase_attr:
        .db     0x42, 0x43, 0x44, 0x45

mr_hud:
        .db     1, 0, MR_ATTR_TITLE
        .dw     mr_txt_name
        .db     23, 0, MR_ATTR_LABEL
        .dw     mr_txt_hall
        .db     19, 3, MR_ATTR_LABEL
        .dw     mr_txt_views
        .db     20, 6, MR_ATTR_LABEL
        .dw     mr_txt_relics
        .db     20, 13, MR_ATTR_LABEL
        .dw     mr_txt_rotations
        .db     19, 17, MR_ATTR_LABEL
        .dw     mr_txt_phase
        .db     0xff

; x, attribute, tile, y
mr_title_tiles:
        .db     8, MR_ATTR_WALL, MR_TILE_WALL, 3
        .db     10, 0x42, MR_TILE_RELIC, 3
        .db     12, MR_ATTR_HERO, 0x9c, 3
        .db     14, MR_ATTR_WALL, MR_TILE_WALL, 3
        .db     16, MR_ATTR_WALL, MR_TILE_WALL, 3
        .db     18, 0x45, MR_TILE_RELIC, 3
        .db     20, MR_ATTR_OPEN, MR_TILE_EXIT, 3
        .db     22, MR_ATTR_WALL, MR_TILE_WALL, 3
        .db     0xff
mr_title_lines:
        .db     10, 8, MR_ATTR_TITLE
        .dw     mr_txt_name
        .db     2, 10, MR_ATTR_LABEL
        .dw     mr_txt_tagline
        .db     8, 15, MR_ATTR_TEXT
        .dw     mr_txt_start
        .db     5, 17, MR_ATTR_TEXT
        .dw     mr_txt_howto
        .db     4, 22, MR_ATTR_DIM
        .dw     mr_txt_credit
        .db     0xff
mr_help_lines:
        .db     10, 1, MR_ATTR_TITLE
        .dw     mr_txt_name
        .db     1, 4, MR_ATTR_TEXT
        .dw     mr_help_1
        .db     1, 6, MR_ATTR_TEXT
        .dw     mr_help_2
        .db     1, 8, MR_ATTR_TEXT
        .dw     mr_help_3
        .db     1, 10, MR_ATTR_TEXT
        .dw     mr_help_4
        .db     1, 12, MR_ATTR_TEXT
        .dw     mr_help_5
        .db     1, 14, MR_ATTR_TEXT
        .dw     mr_help_6
        .db     1, 16, MR_ATTR_TEXT
        .dw     mr_help_7
        .db     1, 18, MR_ATTR_TEXT
        .dw     mr_help_8
        .db     1, 20, MR_ATTR_TEXT
        .dw     mr_help_9
        .db     1, 22, MR_ATTR_LABEL
        .dw     mr_help_back
        .db     0xff

mr_txt_name:
        .db     "MIRROR RELIC", 0
mr_txt_hall:
        .db     "HALL", 0
mr_txt_views:
        .db     "FOUR VIEWS", 0
mr_txt_relics:
        .db     "RELICS", 0
mr_txt_rotations:
        .db     "ROTATIONS", 0
mr_txt_phase:
        .db     "PHASE", 0
mr_txt_of_limit:
        .db     "/20", 0
mr_txt_turning:
        .db     "MIRROR TURN", 0
mr_txt_open:
        .db     "EXIT OPEN", 0
mr_txt_lose:
        .db     "TWENTY ROTATIONS BEFORE EXIT", 0
mr_txt_tagline:
        .db     "TURN THE HALL TO REACH RELICS", 0
mr_txt_start:
        .db     "RETURN : START", 0
mr_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
mr_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
mr_help_1:
        .db     "WASD : WALK", 0
mr_help_2:
        .db     "RETURN : TURN CLOCKWISE", 0
mr_help_3:
        .db     "X : TURN COUNTERCLOCKWISE", 0
mr_help_4:
        .db     "A TURN MOVES PHASE A-D.", 0
mr_help_5:
        .db     "A RELIC NEEDS ITS PHASE.", 0
mr_help_6:
        .db     "> SHOWS THE CLOCKWISE SPOT.", 0
mr_help_7:
        .db     "GET THREE RELICS, THEN EXIT.", 0
mr_help_8:
        .db     "TWENTY TURNS / SIX HALLS.", 0
mr_help_9:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
mr_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     mr_sfx_step, mr_sfx_take, mr_jingle_win, mr_jingle_lose
mr_sfx_step:
        .db     90, 1, 0, 0
mr_sfx_take:
        .db     60, 3, 50, 3, 40, 6, 0, 0
mr_sfx_turn:
        .db     150, 2, 120, 2, 100, 2, 80, 2, 0, 0

; Title: four bars in D minor, quarter note = 24 frames, looping.
mr_title_song:
        .db     1
        .dw     mr_title_melody, mr_title_harmony, mr_title_bass
mr_title_melody:
        .db     AU_D5, 24, AU_F5, 24, AU_A5, 36, AU_G5, 12
        .db     AU_F5, 24, AU_E5, 24, AU_D5, 24, AU_E5, 24
        .db     AU_F5, 24, AU_A5, 24, AU_D6, 36, AU_C6, 12
        .db     AU_A5, 72, 0, 24, 0, 0
mr_title_harmony:
        .db     AU_A4, 48, AU_A4, 48, AU_AS4, 48, AU_G4, 48
        .db     AU_A4, 48, AU_F4, 48, AU_E4, 72, 0, 24, 0, 0
mr_title_bass:
        .db     AU_D3, 48, AU_D3, 48, AU_AS2, 48, AU_C3, 48
        .db     AU_D3, 48, AU_F3, 48, AU_A2, 72, 0, 24, 0, 0

; Clear: rising D major arpeggio over a held tonic (54 frames).
mr_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     mr_win_melody, mr_win_harmony, mr_win_bass
mr_win_melody:
        .db     AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_D6, 30, 0, 0
mr_win_harmony:
        .db     AU_A4, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 30, 0, 0
mr_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
; Out of turns: a falling D minor line (66 frames).
mr_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     mr_lose_melody, mr_lose_harmony, mr_lose_bass
mr_lose_melody:
        .db     AU_A4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
mr_lose_harmony:
        .db     AU_F4, 12, AU_E4, 12, AU_D4, 12, AU_CS4, 30, 0, 0
mr_lose_bass:
        .db     AU_D3, 36, AU_A2, 30, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys_ext.inc"
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

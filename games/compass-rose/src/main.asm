; SPDX-License-Identifier: MIT
; COMPASS ROSE for JR-200: a port of jr100dev games/compass_rose/rules.py 3.0.0.
; The rock rows, goals, bearing and distance bands, supplies, surveys and digs
; follow the upstream source; display, colour and three-voice sound use the
; JR-200 port SDK.
        .filename.jr "COMPASS-ROSE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    10
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then one byte per cell:
; bit 0 visited (b), bit 1 rock (c), bit 2 dug (d).
CR_FACING:          .equ    GAME_STATE
CR_POS:             .equ    GAME_STATE + 1
CR_ORIGIN:          .equ    GAME_STATE + 2
CR_TARGET:          .equ    GAME_STATE + 3
CR_FUEL:            .equ    GAME_STATE + 4
CR_DIGS:            .equ    GAME_STATE + 5
CR_SURVEYS:         .equ    GAME_STATE + 6
CR_SURVEY_POS:      .equ    GAME_STATE + 7
CR_NORTH:           .equ    GAME_STATE + 8
CR_EAST:            .equ    GAME_STATE + 9
CR_BAND:            .equ    GAME_STATE + 10
CR_SCANNING:        .equ    GAME_STATE + 11
CR_DIGGING:         .equ    GAME_STATE + 12
CR_DIG_FRAME:       .equ    GAME_STATE + 13
CR_CELLS:           .equ    GAME_STATE + 14
; Effect state and rule work bytes.
CR_EFFECT:          .equ    GAME_STATE + 80
CR_EX:              .equ    GAME_STATE + 81
CR_EY:              .equ    GAME_STATE + 82
CR_FRAME:           .equ    GAME_STATE + 83
CR_N:               .equ    GAME_STATE + 84
CR_MP:              .equ    GAME_STATE + 85
CR_MC:              .equ    GAME_STATE + 86
CR_T:               .equ    GAME_STATE + 87
CR_I:               .equ    GAME_STATE + 88
; Drawing work bytes.
CR_DI:              .equ    GAME_STATE + 96
CR_DCODE:           .equ    GAME_STATE + 97

CR_START:           .equ    27
CR_VISITED:         .equ    1
CR_ROCK:            .equ    2
CR_DUG:             .equ    4
CR_TILE_SAND:       .equ    0x80
CR_TILE_TRAIL:      .equ    0x84
CR_TILE_ROCK:       .equ    0x88
CR_TILE_HERO:       .equ    0x8c        ; + 4 * (facing - 1)
CR_ATTR_SAND:       .equ    0x46        ; yellow sand
CR_ATTR_TRAIL:      .equ    0x44        ; green footprints
CR_ATTR_ROCK:       .equ    0x57        ; white rock on red
CR_ATTR_HERO:       .equ    0x47
CR_ATTR_SPARK:      .equ    0x46
CR_ATTR_HOLE:       .equ    0x02
CR_ATTR_SCAN:       .equ    0x05
CR_ATTR_MARK:       .equ    0x05
CR_ATTR_BEARING:    .equ    0x06
CR_ATTR_TEXT:       .equ    0x07
CR_ATTR_LABEL:      .equ    0x04
CR_ATTR_TITLE:      .equ    0x06
CR_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     cr_patterns
        LDAA    0x80
        LDAB    28
        JSR     jr_pcg_load
        LDX     cr_spark_patterns
        CLRA
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    2
        STAA    [CR_FACING]
        LDAA    CR_START
        STAA    [CR_POS]
        STAA    [CR_ORIGIN]
        LDX     cr_goals
        LDAA    [JR_PORT_LEVEL]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [CR_TARGET]
        LDAA    32
        STAA    [CR_FUEL]
        LDAA    3
        STAA    [CR_DIGS]
        LDAA    4
        STAA    [CR_SURVEYS]
        ; rocks on 17-22 and 41-46, one gap in each row
        LDAA    [JR_PORT_LEVEL]
        LDAB    6
        JSR     jr_divmod8
        STAB    [CR_T]
        LDAA    [JR_PORT_LEVEL]
        ADDA    3
        LDAB    6
        JSR     jr_divmod8
        STAB    [CR_N]
        CLR     [CR_I]
cr_init_rock:
        LDAA    [CR_I]
        CMPA    [CR_T]
        BEQ     cr_init_lower
        LDX     CR_CELLS + 17
        JSR     jr_add_x_a
        LDAA    CR_ROCK
        STAA    [X]
cr_init_lower:
        LDAA    [CR_I]
        CMPA    [CR_N]
        BEQ     cr_init_next
        LDX     CR_CELLS + 41
        JSR     jr_add_x_a
        LDAA    CR_ROCK
        STAA    [X]
cr_init_next:
        INC     [CR_I]
        LDAA    [CR_I]
        CMPA    6
        BNE     cr_init_rock
        LDAA    [CR_TARGET]
        LDX     CR_CELLS
        JSR     jr_add_x_a
        CLR     [X]
        LDAA    CR_VISITED
        STAA    [CR_CELLS + CR_START]
        JMP     cr_survey

; north/east bearing and distance band of the target from here.
cr_survey:
        LDAA    [CR_POS]
        STAA    [CR_SURVEY_POS]
        LDAA    [CR_TARGET]
        LSRA
        LSRA
        LSRA
        LDAB    [CR_POS]
        LSRB
        LSRB
        LSRB
        JSR     cr_compare
        STAA    [CR_NORTH]
        LDAA    [CR_TARGET]
        ANDA    7
        LDAB    [CR_POS]
        ANDB    7
        JSR     cr_compare
        STAA    [CR_EAST]
        LDAA    [CR_POS]
        LDAB    [CR_TARGET]
        JSR     cr_distance
        CLRB
        CMPA    2
        BLS     cr_survey_band
        INCB
        CMPA    5
        BLS     cr_survey_band
        INCB
cr_survey_band:
        STAB    [CR_BAND]
        RTS

; A = target coordinate, B = own coordinate -> A = 1 if less, 2 if greater, else 0.
cr_compare:
        CBA
        BEQ     cr_compare_same
        BCS     cr_compare_less
        LDAA    2
        RTS
cr_compare_less:
        LDAA    1
        RTS
cr_compare_same:
        CLRA
        RTS

; A, B = cells -> A = |row difference| + |column difference|.
cr_distance:
        STAA    [CR_MP]
        STAB    [CR_MC]
        ANDA    7
        ANDB    7
        SBA
        BCC     cr_distance_cols
        NEGA
cr_distance_cols:
        STAA    [CR_I]
        LDAA    [CR_MP]
        LSRA
        LSRA
        LSRA
        LDAB    [CR_MC]
        LSRB
        LSRB
        LSRB
        SBA
        BCC     cr_distance_rows
        NEGA
cr_distance_rows:
        ADDA    [CR_I]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    7
        BNE     cr_act_other
        ; X: survey again for two supplies
        TST     [CR_SURVEYS]
        BNE     cr_act_done_near235
        JMP     cr_act_done
cr_act_done_near235:
        LDAA    [CR_FUEL]
        CMPA    3
        BCC     cr_act_done_near240
        JMP     cr_act_done
cr_act_done_near240:
        DEC     [CR_SURVEYS]
        DEC     [CR_FUEL]
        DEC     [CR_FUEL]
        LDX     cr_sfx_scan
        JSR     jr_sfx_play
        LDAA    1
        STAA    [CR_SCANNING]
cr_scan_frame:
        LDAA    5
        JSR     jr_port_animate
        INC     [CR_SCANNING]
        LDAA    [CR_SCANNING]
        CMPA    4
        BNE     cr_scan_frame
        CLR     [CR_SCANNING]
        JMP     cr_survey
cr_act_other:
        TSTA
        BEQ     cr_act_done
        CMPA    JR_KEY_CONFIRM
        BEQ     cr_dig
        BCC     cr_act_done
        ; walk: rocks and the edge block without cost
        STAA    [CR_FACING]
        TAB
        LDAA    [CR_POS]
        JSR     cr_move
        STAA    [CR_N]
        CMPA    [CR_POS]
        BEQ     cr_bump
        LDX     CR_CELLS
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    CR_ROCK
        BNE     cr_bump
        ORAA    CR_VISITED
        STAA    [X]
        LDAA    [CR_POS]
        STAA    [CR_ORIGIN]
        LDAA    [CR_N]
        STAA    [CR_POS]
        CLRA
        JSR     jr_port_sound
        LDAA    2
        JSR     jr_port_animate
        LDAA    [CR_POS]
        STAA    [CR_ORIGIN]
        DEC     [CR_FUEL]
        BNE     cr_act_done
        LDX     cr_txt_supplies
        JMP     jr_port_lose
cr_bump:
        LDX     cr_sfx_buzz
        JMP     jr_sfx_play
cr_act_done:
        RTS

cr_dig:
        LDAA    1
        STAA    [CR_DIGGING]
        CLR     [CR_DIG_FRAME]
cr_dig_step:
        CLRA
        JSR     jr_port_sound
        LDAA    6
        JSR     jr_port_animate
        LDAA    [CR_DIG_FRAME]
        CMPA    2
        BEQ     cr_dig_done
        INC     [CR_DIG_FRAME]
        BRA     cr_dig_step
cr_dig_done:
        CLR     [CR_DIGGING]
        LDAA    [CR_POS]
        LDX     CR_CELLS
        JSR     jr_add_x_a
        LDAA    [X]
        ORAA    CR_DUG
        STAA    [X]
        LDAA    [CR_POS]
        CMPA    [CR_TARGET]
        BNE     cr_dig_miss
        JSR     cr_sparkle
        LDAA    1
        JSR     jr_port_sound
        JMP     jr_port_win
cr_dig_miss:
        DEC     [CR_DIGS]
        LDX     cr_sfx_buzz
        JSR     jr_sfx_play
        TST     [CR_DIGS]
        BNE     cr_act_done
        LDX     cr_txt_digs
        JMP     jr_port_lose

; sparkle over the relic: three phases of animate(4).
cr_sparkle:
        LDAA    [CR_POS]
        JSR     cr_cell_xy
        STAA    [CR_EX]
        STAB    [CR_EY]
        LDAA    1
        STAA    [CR_EFFECT]
        CLR     [CR_FRAME]
cr_sparkle_phase:
        LDAA    4
        JSR     jr_port_animate
        INC     [CR_FRAME]
        LDAA    [CR_FRAME]
        CMPA    3
        BNE     cr_sparkle_phase
        CLR     [CR_EFFECT]
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
cr_move:
        STAA    [CR_MP]
        ANDA    7
        STAA    [CR_MC]
        LDAA    [CR_MP]
        CMPB    JR_KEY_UP
        BNE     cr_move_down
        CMPA    8
        BCS     cr_move_done
        SUBA    8
        RTS
cr_move_down:
        CMPB    JR_KEY_DOWN
        BNE     cr_move_left
        CMPA    56
        BCC     cr_move_done
        ADDA    8
        RTS
cr_move_left:
        CMPB    JR_KEY_LEFT
        BNE     cr_move_right
        TST     [CR_MC]
        BEQ     cr_move_done
        DECA
        RTS
cr_move_right:
        LDAB    [CR_MC]
        CMPB    7
        BCC     cr_move_done
        INCA
cr_move_done:
        RTS

; A = cell -> A = cell % 8 * 2, B = 3 + cell // 8 * 2.
cr_cell_xy:
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        ANDA    7
        ASLA
        RTS

; A = cell, JR_RT_COLOR set -> character A at the cell's top-left.
cr_cell_char:
        PSHB
        JSR     cr_cell_xy
        JSR     jr_gfx_at
        PULA
        JMP     jr_gfx_putc

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    CR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cr_hud
        JSR     jr_gfx_lines
        LDAA    CR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the map: rock, trail or sand
        CLR     [CR_DI]
cr_draw_cell:
        LDAA    [CR_DI]
        LDX     CR_CELLS
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     cr_look_rock
        BITA    CR_ROCK
        BNE     cr_draw_tile
        LDX     cr_look_trail
        BITA    CR_VISITED
        BNE     cr_draw_tile
        LDX     cr_look_sand
cr_draw_tile:
        LDAA    [X]
        STAA    [CR_DCODE]
        LDAA    [X + 1]
        STAA    [JR_RT_COLOR]
        LDAA    [CR_DI]
        JSR     cr_cell_xy
        JSR     jr_gfx_at
        LDAA    [CR_DCODE]
        JSR     jr_gfx_tile
        INC     [CR_DI]
        LDAA    [CR_DI]
        CMPA    64
        BNE     cr_draw_cell
        ; the explorer, facing its last move
        LDAA    CR_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [CR_POS]
        JSR     cr_cell_xy
        JSR     jr_gfx_at
        LDAA    [CR_FACING]
        DECA
        ASLA
        ASLA
        ADDA    CR_TILE_HERO
        JSR     jr_gfx_tile
        ; where the bearing was last taken
        LDAA    [CR_SURVEY_POS]
        CMPA    [CR_POS]
        BEQ     cr_draw_scan
        LDAB    CR_ATTR_MARK
        STAB    [JR_RT_COLOR]
        LDAB    0x2b
        JSR     cr_cell_char
cr_draw_scan:
        ; the survey ring: '*' on cells at distance `scanning`
        TST     [CR_SCANNING]
        BEQ     cr_draw_holes
        LDAA    CR_ATTR_SCAN
        STAA    [JR_RT_COLOR]
        CLR     [CR_DI]
cr_draw_ring:
        LDAA    [CR_DI]
        LDAB    [CR_POS]
        JSR     cr_distance
        CMPA    [CR_SCANNING]
        BNE     cr_draw_ring_next
        LDAA    [CR_DI]
        LDAB    0x2a
        JSR     cr_cell_char
cr_draw_ring_next:
        INC     [CR_DI]
        LDAA    [CR_DI]
        CMPA    64
        BNE     cr_draw_ring
cr_draw_holes:
        LDAA    CR_ATTR_HOLE
        STAA    [JR_RT_COLOR]
        CLR     [CR_DI]
cr_draw_hole:
        LDAA    [CR_DI]
        LDX     CR_CELLS
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    CR_DUG
        BEQ     cr_draw_hole_next
        LDAA    [CR_DI]
        LDAB    0x4f
        JSR     cr_cell_char
cr_draw_hole_next:
        INC     [CR_DI]
        LDAA    [CR_DI]
        CMPA    64
        BNE     cr_draw_hole
        ; the spade: '-' '/' '-'
        TST     [CR_DIGGING]
        BEQ     cr_draw_effect
        LDAA    CR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAB    0x2d
        LDAA    [CR_DIG_FRAME]
        CMPA    1
        BNE     cr_draw_spade
        LDAB    0x2f
cr_draw_spade:
        LDAA    [CR_POS]
        JSR     cr_cell_char
cr_draw_effect:
        TST     [CR_EFFECT]
        BEQ     cr_draw_hud
        LDAA    CR_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    [CR_EX]
        LDAB    [CR_EY]
        JSR     jr_gfx_at
        LDAA    [CR_FRAME]
        ASLA
        ASLA
        JSR     jr_gfx_tile
cr_draw_hud:
        ; bearing letters, or HERE
        LDAA    CR_ATTR_BEARING
        STAA    [JR_RT_COLOR]
        LDAA    [CR_NORTH]
        BEQ     cr_draw_east
        LDAA    23
        LDAB    8
        JSR     jr_gfx_at
        LDAA    0x4e
        LDAB    [CR_NORTH]
        CMPB    1
        BEQ     cr_draw_north
        LDAA    0x53
cr_draw_north:
        JSR     jr_gfx_putc
cr_draw_east:
        LDAA    [CR_EAST]
        BEQ     cr_draw_here
        LDAA    25
        LDAB    8
        JSR     jr_gfx_at
        LDAA    0x57
        LDAB    [CR_EAST]
        CMPB    1
        BEQ     cr_draw_east_put
        LDAA    0x45
cr_draw_east_put:
        JSR     jr_gfx_putc
cr_draw_here:
        LDAA    [CR_NORTH]
        ORAA    [CR_EAST]
        BNE     cr_draw_band
        LDAA    21
        LDAB    8
        JSR     jr_gfx_at
        LDX     cr_txt_here
        JSR     jr_gfx_text
cr_draw_band:
        LDAA    [CR_BAND]
        LDX     cr_band_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [CR_BAND]
        ASLA
        LDX     cr_band_text
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    CR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [CR_FUEL]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [CR_DIGS]
        JSR     jr_gfx_dec2
        LDAA    10
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [CR_SURVEYS]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    21
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [CR_SURVEY_POS]
        ANDA    7
        ADDA    0x31
        JSR     jr_gfx_putc
        LDAA    23
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [CR_SURVEY_POS]
        LSRA
        LSRA
        LSRA
        ADDA    0x31
        JMP     jr_gfx_putc

game_draw_title:
        LDX     cr_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    CR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cr_title_tiles
        STX     [JR_RT_TABLE]
cr_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     cr_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [CR_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [CR_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     cr_title_tile
cr_title_text:
        LDX     cr_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cr_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0

cr_goals:
        .db     13, 63, 60, 59, 61, 3, 57, 50, 58, 52
cr_look_rock:
        .db     CR_TILE_ROCK, CR_ATTR_ROCK
cr_look_trail:
        .db     CR_TILE_TRAIL, CR_ATTR_TRAIL
cr_look_sand:
        .db     CR_TILE_SAND, CR_ATTR_SAND
cr_band_attr:
        .db     0x04, 0x06, 0x02
cr_band_text:
        .dw     cr_txt_near, cr_txt_mid, cr_txt_far

; x, attribute, code, y
cr_title_tiles:
        .db     8, CR_ATTR_SAND, CR_TILE_SAND, 3
        .db     11, CR_ATTR_TRAIL, CR_TILE_TRAIL, 3
        .db     14, CR_ATTR_HERO, CR_TILE_HERO + 12, 3
        .db     17, CR_ATTR_ROCK, CR_TILE_ROCK, 3
        .db     20, CR_ATTR_SPARK, 0x04, 3
        .db     0xff

cr_hud:
        .db     1, 0, CR_ATTR_TITLE
        .dw     cr_txt_name
        .db     18, 3, CR_ATTR_LABEL
        .dw     cr_txt_expedition
        .db     20, 6, CR_ATTR_LABEL
        .dw     cr_txt_bearing
        .db     20, 12, CR_ATTR_LABEL
        .dw     cr_txt_steps
        .db     20, 16, CR_ATTR_LABEL
        .dw     cr_txt_digs_label
        .db     1, 20, CR_ATTR_LABEL
        .dw     cr_txt_surveys
        .db     15, 20, CR_ATTR_LABEL
        .dw     cr_txt_from
        .db     0xff
cr_title_lines:
        .db     10, 8, CR_ATTR_TITLE
        .dw     cr_txt_name
        .db     4, 10, CR_ATTR_LABEL
        .dw     cr_txt_tagline
        .db     8, 15, CR_ATTR_TEXT
        .dw     cr_txt_start
        .db     5, 17, CR_ATTR_TEXT
        .dw     cr_txt_howto
        .db     4, 22, CR_ATTR_DIM
        .dw     cr_txt_credit
        .db     0xff
cr_help_lines:
        .db     10, 2, CR_ATTR_TITLE
        .dw     cr_txt_name
        .db     1, 5, CR_ATTR_TEXT
        .dw     cr_help_1
        .db     1, 7, CR_ATTR_TEXT
        .dw     cr_help_2
        .db     1, 9, CR_ATTR_TEXT
        .dw     cr_help_3
        .db     1, 11, CR_ATTR_TEXT
        .dw     cr_help_4
        .db     1, 13, CR_ATTR_TEXT
        .dw     cr_help_5
        .db     1, 15, CR_ATTR_TEXT
        .dw     cr_help_6
        .db     1, 17, CR_ATTR_TEXT
        .dw     cr_help_7
        .db     1, 19, CR_ATTR_TEXT
        .dw     cr_help_8
        .db     1, 21, CR_ATTR_LABEL
        .dw     cr_help_back
        .db     0xff

cr_txt_name:
        .db     "COMPASS ROSE", 0
cr_txt_expedition:
        .db     "EXPEDITION", 0
cr_txt_bearing:
        .db     "BEARING", 0
cr_txt_steps:
        .db     "STEPS", 0
cr_txt_digs_label:
        .db     "DIGS", 0
cr_txt_surveys:
        .db     "SURVEYS", 0
cr_txt_from:
        .db     "FROM", 0
cr_txt_here:
        .db     "HERE", 0
cr_txt_near:
        .db     "NEAR", 0
cr_txt_mid:
        .db     "MID", 0
cr_txt_far:
        .db     "FAR", 0
cr_txt_supplies:
        .db     "OUT OF TRAVEL SUPPLIES", 0
cr_txt_digs:
        .db     "NO DIGS REMAIN", 0
cr_txt_tagline:
        .db     "READ THE BEARING, DIG GOLD", 0
cr_txt_start:
        .db     "RETURN : START", 0
cr_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
cr_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cr_help_1:
        .db     "WASD : MOVE  RETURN : DIG", 0
cr_help_2:
        .db     "X : SURVEY AGAIN, COSTS 2 FOOD", 0
cr_help_3:
        .db     "BEARING STAYS AT LAST SURVEY.", 0
cr_help_4:
        .db     "NEAR 0-2 / MID 3-5 / FAR 6+", 0
cr_help_5:
        .db     "COMPARE READINGS TO FIND GOLD.", 0
cr_help_6:
        .db     "FOUR SURVEYS AND THREE DIGS.", 0
cr_help_7:
        .db     "ROCKS BLOCK TRAVEL.", 0
cr_help_8:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
cr_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     cr_sfx_step, cr_sfx_found, cr_jingle_win, cr_jingle_lose
cr_sfx_step:
        .db     160, 2, 0, 0
cr_sfx_found:
        .db     60, 4, 50, 4, 40, 8, 0, 0
cr_sfx_scan:
        .db     120, 4, 0, 1, 100, 4, 0, 1, 80, 4, 0, 0
cr_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: an expedition march in E minor, quarter note = 16 frames, looping.
cr_title_song:
        .db     1
        .dw     cr_title_melody, cr_title_harmony, cr_title_bass
cr_title_melody:
        .db     AU_E5, 16, AU_G5, 16, AU_B5, 24, AU_A5, 8
        .db     AU_G5, 16, AU_FS5, 16, AU_E5, 32
        .db     AU_D5, 16, AU_FS5, 16, AU_A5, 24, AU_G5, 8
        .db     AU_FS5, 16, AU_DS5, 16, AU_E5, 32, 0, 0
cr_title_harmony:
        .db     AU_B4, 32, AU_E5, 32, AU_B4, 32, AU_G4, 32
        .db     AU_A4, 32, AU_D5, 32, AU_B4, 32, AU_G4, 32, 0, 0
cr_title_bass:
        .db     AU_E3, 16, AU_B2, 16, AU_E3, 16, AU_B2, 16
        .db     AU_C3, 16, AU_B2, 16, AU_E3, 32
        .db     AU_D3, 16, AU_A2, 16, AU_D3, 16, AU_A2, 16
        .db     AU_B2, 16, AU_B2, 16, AU_E3, 32, 0, 0

; Gold: E major arpeggio over the tonic (54 frames).
cr_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     cr_win_melody, cr_win_harmony, cr_win_bass
cr_win_melody:
        .db     AU_E5, 8, AU_GS5, 8, AU_B5, 8, AU_E6, 30, 0, 0
cr_win_harmony:
        .db     AU_B4, 8, AU_E5, 8, AU_GS5, 8, AU_B5, 30, 0, 0
cr_win_bass:
        .db     AU_E3, 24, AU_E2, 30, 0, 0
cr_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     cr_lose_melody, cr_lose_harmony, cr_lose_bass
cr_lose_melody:
        .db     AU_B4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
cr_lose_harmony:
        .db     AU_G4, 12, AU_FS4, 12, AU_E4, 12, AU_DS4, 30, 0, 0
cr_lose_bass:
        .db     AU_E3, 36, AU_B2, 30, 0, 0

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

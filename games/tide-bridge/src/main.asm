; SPDX-License-Identifier: MIT
; TIDE BRIDGE for JR-200: a port of jr100dev games/tide_bridge/rules.py 1.6.1.
; The tide planks, row/column toggles, the shore-to-gate search, the walk and
; the thirty-change limit follow the upstream source; display, colour and
; three-voice sound use the JR-200 port SDK.
        .filename.jr "TIDE-BRIDGE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[36].
TB_POS:             .equ    GAME_STATE
TB_ORIGIN:          .equ    GAME_STATE + 1
TB_FACING:          .equ    GAME_STATE + 2
TB_CURSOR:          .equ    GAME_STATE + 3
TB_MOVES:           .equ    GAME_STATE + 4
TB_AXIS:            .equ    GAME_STATE + 5
TB_WALKING:         .equ    GAME_STATE + 6
TB_HALF:            .equ    GAME_STATE + 7
TB_ARRIVED:         .equ    GAME_STATE + 8
TB_HOP:             .equ    GAME_STATE + 9
TB_B:               .equ    GAME_STATE + 10
; Search and rule work bytes.
TB_SEEN:            .equ    GAME_STATE + 48
TB_PARENT:          .equ    GAME_STATE + 84
TB_QUEUE:           .equ    GAME_STATE + 120
TB_HEAD:            .equ    GAME_STATE + 156
TB_TAIL:            .equ    GAME_STATE + 157
TB_P:               .equ    GAME_STATE + 158
TB_A:               .equ    GAME_STATE + 159
TB_N:               .equ    GAME_STATE + 160
TB_LEN:             .equ    GAME_STATE + 161
TB_T:               .equ    GAME_STATE + 162
TB_K:               .equ    GAME_STATE + 163
TB_MC:              .equ    GAME_STATE + 164
; Drawing work bytes.
TB_DI:              .equ    GAME_STATE + 170
TB_DX:              .equ    GAME_STATE + 171
TB_DY:              .equ    GAME_STATE + 172
TB_DT:              .equ    GAME_STATE + 173

TB_START:           .equ    30
TB_GATE:            .equ    5
TB_LIMIT:           .equ    30
TB_TILE_WATER:      .equ    0x80
TB_TILE_PLANK:      .equ    0x84
TB_TILE_GATE:       .equ    0x88
TB_TILE_HERO:       .equ    0x00        ; + 4 * (facing - 1)
TB_ATTR_WATER:      .equ    0x4d        ; cyan waves on blue
TB_ATTR_PLANK:      .equ    0x4e        ; yellow planks on blue
TB_ATTR_WATER_HI:   .equ    0x5d        ; the selected line: magenta ground
TB_ATTR_PLANK_HI:   .equ    0x5e
TB_ATTR_GATE:       .equ    0x4c        ; green gate
TB_ATTR_HERO:       .equ    0x4f
TB_ATTR_TEXT:       .equ    0x07
TB_ATTR_LABEL:      .equ    0x04
TB_ATTR_TITLE:      .equ    0x06
TB_ATTR_DIM:        .equ    0x05
TB_ATTR_ARROW:      .equ    0x03
TB_ATTR_GOOD:       .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     tb_patterns
        LDAA    TB_TILE_WATER
        LDAB    12
        JSR     jr_pcg_load
        LDX     tb_hero_patterns
        CLRA
        LDAB    24
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; b[i] = 3 when (i // 6 + i % 6 + level) % 3 == 0.
game_init:
        JSR     jr_music_stop
        CLR     [TB_K]
tb_init_cell:
        LDAA    [TB_K]
        LDAB    6
        JSR     jr_divmod8
        STAB    [TB_T]
        ADDA    [TB_T]
        ADDA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_divmod8
        LDAA    0
        TSTB
        BNE     tb_init_store
        LDAA    3
tb_init_store:
        PSHA
        LDAA    [TB_K]
        LDX     TB_B
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [TB_K]
        LDAA    [TB_K]
        CMPA    36
        BNE     tb_init_cell
        LDAA    TB_START
        STAA    [TB_POS]
        STAA    [TB_ORIGIN]
        LDAA    2
        STAA    [TB_FACING]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_UP
        BNE     tb_act_down
        LDAA    [TB_CURSOR]
        ADDA    5
        BRA     tb_act_cursor
tb_act_down:
        CMPA    JR_KEY_DOWN
        BNE     tb_act_axis
        LDAA    [TB_CURSOR]
        INCA
tb_act_cursor:
        CMPA    6
        BCS     tb_act_store
        SUBA    6
tb_act_store:
        STAA    [TB_CURSOR]
        RTS
tb_act_axis:
        CMPA    JR_KEY_LEFT
        BEQ     tb_act_flip
        CMPA    JR_KEY_RIGHT
        BNE     tb_act_confirm
tb_act_flip:
        LDAA    [TB_AXIS]
        EORA    1
        STAA    [TB_AXIS]
        RTS
tb_act_confirm:
        CMPA    JR_KEY_CONFIRM
        BNE     tb_act_done
        ; raise or lower the whole row or column
        CLR     [TB_K]
tb_toggle:
        LDAA    [TB_CURSOR]
        LDAB    [TB_K]
        TST     [TB_AXIS]
        BEQ     tb_toggle_row
        TBA
        LDAB    [TB_CURSOR]
tb_toggle_row:
        ; n = A * 6 + B
        STAB    [TB_T]
        LDAB    6
        JSR     jr_mul8
        ADDA    [TB_T]
        LDX     TB_B
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     tb_toggle_raise
        CLR     [X]
        BRA     tb_toggle_next
tb_toggle_raise:
        LDAA    3
        STAA    [X]
tb_toggle_next:
        INC     [TB_K]
        LDAA    [TB_K]
        CMPA    6
        BNE     tb_toggle
        INC     [TB_MOVES]
        LDAA    1
        JSR     jr_port_sound
        JSR     tb_connected
        LDAA    [TB_MOVES]
        CMPA    TB_LIMIT
        BCS     tb_act_done
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     tb_act_done
        LDX     0
        JMP     jr_port_lose
tb_act_done:
        RTS

; Breadth-first search from the shore over planks; when the gate is reached
; the hero walks the found path, cheers twice and the stage is won.
tb_connected:
        LDX     TB_SEEN
tb_search_clear:
        CLR     [X]
        INX
        CPX     TB_SEEN + 36
        BNE     tb_search_clear
        LDAA    1
        STAA    [TB_SEEN + TB_START]
        LDAA    TB_START
        STAA    [TB_QUEUE]
        LDAA    1
        STAA    [TB_TAIL]
        CLR     [TB_HEAD]
tb_search_head:
        LDAA    [TB_HEAD]
        CMPA    [TB_TAIL]
        BCC     tb_search_done
        LDX     TB_QUEUE
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TB_P]
        LDAA    1
        STAA    [TB_A]
tb_search_side:
        LDAA    [TB_P]
        LDAB    [TB_A]
        JSR     tb_move
        STAA    [TB_N]
        LDX     TB_SEEN
        JSR     jr_add_x_a
        TST     [X]
        BNE     tb_search_next
        LDAA    [TB_N]
        CMPA    TB_GATE
        BEQ     tb_search_take
        LDX     TB_B
        JSR     jr_add_x_a
        TST     [X]
        BEQ     tb_search_next
tb_search_take:
        LDAA    [TB_N]
        LDX     TB_SEEN
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        LDAA    [TB_N]
        LDX     TB_PARENT
        JSR     jr_add_x_a
        LDAA    [TB_P]
        STAA    [X]
        LDAA    [TB_TAIL]
        LDX     TB_QUEUE
        JSR     jr_add_x_a
        LDAA    [TB_N]
        STAA    [X]
        INC     [TB_TAIL]
tb_search_next:
        INC     [TB_A]
        LDAA    [TB_A]
        CMPA    5
        BNE     tb_search_side
        INC     [TB_HEAD]
        BRA     tb_search_head
tb_search_done:
        TST     [TB_SEEN + TB_GATE]
        BNE     tb_walk
        RTS
tb_walk:
        ; the path back from the gate, kept in the queue
        CLR     [TB_LEN]
        LDAA    TB_GATE
        STAA    [TB_T]
tb_walk_back:
        LDAA    [TB_T]
        CMPA    TB_START
        BEQ     tb_walk_go
        LDAA    [TB_LEN]
        LDX     TB_QUEUE
        JSR     jr_add_x_a
        LDAA    [TB_T]
        STAA    [X]
        INC     [TB_LEN]
        LDX     TB_PARENT
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TB_T]
        BRA     tb_walk_back
tb_walk_go:
        LDAA    1
        STAA    [TB_WALKING]
        LDAA    8
        JSR     jr_port_animate
tb_walk_step:
        TST     [TB_LEN]
        BEQ     tb_arrive
        DEC     [TB_LEN]
        LDAA    [TB_LEN]
        LDX     TB_QUEUE
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TB_T]
        ; facing: up/down by default, left/right within the row
        LDAB    1
        CMPA    [TB_POS]
        BCS     tb_walk_vertical
        LDAB    2
tb_walk_vertical:
        STAB    [TB_FACING]
        LDAB    6
        JSR     jr_divmod8
        STAA    [TB_K]
        LDAA    [TB_POS]
        LDAB    6
        JSR     jr_divmod8
        CMPA    [TB_K]
        BNE     tb_walk_move
        LDAB    3
        LDAA    [TB_T]
        CMPA    [TB_POS]
        BCS     tb_walk_side
        LDAB    4
tb_walk_side:
        STAB    [TB_FACING]
tb_walk_move:
        LDAA    [TB_POS]
        STAA    [TB_ORIGIN]
        LDAA    [TB_T]
        STAA    [TB_POS]
        LDAA    1
        STAA    [TB_HALF]
        CLRA
        JSR     jr_port_sound
        LDAA    3
        JSR     jr_port_animate
        CLR     [TB_HALF]
        LDAA    3
        JSR     jr_port_animate
        BRA     tb_walk_step
tb_arrive:
        LDAA    1
        STAA    [TB_ARRIVED]
        LDAA    2
        STAA    [TB_K]
tb_cheer:
        LDAA    5
        STAA    [TB_FACING]
        LDAA    1
        STAA    [TB_HOP]
        LDAA    1
        JSR     jr_port_sound
        LDAA    8
        JSR     jr_port_animate
        LDAA    6
        STAA    [TB_FACING]
        CLR     [TB_HOP]
        LDAA    8
        JSR     jr_port_animate
        DEC     [TB_K]
        BNE     tb_cheer
        LDAA    5
        STAA    [TB_FACING]
        LDAA    6
        JSR     jr_port_animate
        JMP     jr_port_win

; A = position, B = action 1-4 -> A = moved position (6x6, stops at edges).
tb_move:
        STAA    [TB_MC]
        CMPB    JR_KEY_UP
        BNE     tb_move_down
        CMPA    6
        BCS     tb_move_done
        SUBA    6
        RTS
tb_move_down:
        CMPB    JR_KEY_DOWN
        BNE     tb_move_side
        CMPA    30
        BCC     tb_move_done
        ADDA    6
        RTS
tb_move_side:
        PSHB
        LDAB    6
        JSR     jr_divmod8
        PULA
        ; A = action, B = column
        CMPA    JR_KEY_LEFT
        BNE     tb_move_right
        LDAA    [TB_MC]
        TSTB
        BEQ     tb_move_done
        DECA
        RTS
tb_move_right:
        LDAA    [TB_MC]
        CMPB    5
        BCC     tb_move_done
        INCA
tb_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_hud
        JSR     jr_gfx_lines
        LDAA    TB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the 6x6 tide: planks and water, the selected line on magenta
        CLR     [TB_DI]
tb_draw_cell:
        LDAA    [TB_DI]
        LDAB    6
        JSR     jr_divmod8
        STAA    [TB_DY]
        STAB    [TB_DX]
        CLR     [TB_DT]
        TST     [TB_WALKING]
        BNE     tb_draw_kind
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     tb_draw_kind
        LDAA    [TB_DY]
        TST     [TB_AXIS]
        BEQ     tb_draw_line
        LDAA    [TB_DX]
tb_draw_line:
        CMPA    [TB_CURSOR]
        BNE     tb_draw_kind
        INC     [TB_DT]
tb_draw_kind:
        LDAA    [TB_DI]
        LDX     TB_B
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     tb_look_water
        TSTA
        BEQ     tb_draw_look
        LDX     tb_look_plank
tb_draw_look:
        LDAA    [TB_DT]
        JSR     jr_add_x_a
        LDAA    [X + 2]
        STAA    [JR_RT_COLOR]
        LDAA    [X]
        STAA    [TB_DT]
        LDAA    [TB_DX]
        ASLA
        ADDA    2
        LDAB    [TB_DY]
        ASLB
        ADDB    5
        JSR     jr_gfx_at
        LDAA    [TB_DT]
        JSR     jr_gfx_tile
        INC     [TB_DI]
        LDAA    [TB_DI]
        CMPA    36
        BNE     tb_draw_cell
        LDAA    TB_ATTR_GATE
        STAA    [JR_RT_COLOR]
        LDAA    12
        LDAB    5
        JSR     jr_gfx_at
        LDAA    TB_TILE_GATE
        JSR     jr_gfx_tile
        ; the hero: between two cells while stepping, lifted while hopping
        LDAA    TB_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [TB_POS]
        LDAB    6
        JSR     jr_divmod8
        STAA    [TB_DY]
        STAB    [TB_DX]
        TST     [TB_HALF]
        BEQ     tb_draw_whole
        LDAA    [TB_ORIGIN]
        LDAB    6
        JSR     jr_divmod8
        ADDB    [TB_DX]
        ADDB    2
        ADDA    [TB_DY]
        ADDA    5
        BRA     tb_draw_hero
tb_draw_whole:
        LDAB    [TB_DX]
        ASLB
        ADDB    2
        LDAA    [TB_DY]
        ASLA
        ADDA    5
        SUBA    [TB_HOP]
tb_draw_hero:
        ; A = y, B = x
        PSHA
        TBA
        PULB
        JSR     jr_gfx_at
        LDAA    [TB_FACING]
        DECA
        ASLA
        ASLA
        ADDA    TB_TILE_HERO
        JSR     jr_gfx_tile
        TST     [TB_WALKING]
        BEQ     tb_draw_select
        LDX     tb_txt_crossing
        LDAB    TB_ATTR_TEXT
        TST     [TB_ARRIVED]
        BEQ     tb_draw_walk
        LDX     tb_txt_arrived
        LDAB    TB_ATTR_GOOD
tb_draw_walk:
        STAB    [JR_RT_COLOR]
        STX     [JR_RT_TABLE]
        LDAA    20
        LDAB    5
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        LDAA    20
        LDAB    10
        JSR     jr_gfx_at
        LDX     tb_txt_gate
        TST     [TB_ARRIVED]
        BEQ     tb_draw_walk_2
        LDX     tb_txt_hooray
tb_draw_walk_2:
        JSR     jr_gfx_text
        JMP     tb_draw_moves
tb_draw_select:
        LDAA    TB_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    5
        JSR     jr_gfx_at
        LDX     tb_txt_select
        JSR     jr_gfx_text
        LDAA    TB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    6
        JSR     jr_gfx_at
        LDX     tb_txt_row
        TST     [TB_AXIS]
        BEQ     tb_draw_axis
        LDX     tb_txt_col
tb_draw_axis:
        JSR     jr_gfx_text
        LDAA    24
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [TB_CURSOR]
        ADDA    0x31
        JSR     jr_gfx_putc
        ; arrows at both ends of the selected line
        LDAA    TB_ATTR_ARROW
        STAA    [JR_RT_COLOR]
        LDAA    [TB_CURSOR]
        ASLA
        STAA    [TB_DT]
        TST     [TB_AXIS]
        BNE     tb_draw_col_arrows
        LDAA    1
        LDAB    [TB_DT]
        ADDB    5
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    14
        LDAB    [TB_DT]
        ADDB    5
        JSR     jr_gfx_at
        LDAA    0x3c
        JSR     jr_gfx_putc
        BRA     tb_draw_moves
tb_draw_col_arrows:
        LDAA    [TB_DT]
        ADDA    2
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        LDAA    [TB_DT]
        ADDA    2
        LDAB    17
        JSR     jr_gfx_at
        LDAA    0x5e
        JSR     jr_gfx_putc
tb_draw_moves:
        LDAA    TB_ATTR_TEXT
        LDAB    [TB_MOVES]
        CMPB    25
        BCS     tb_draw_moves_colour
        LDAA    0x02
tb_draw_moves_colour:
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [TB_MOVES]
        JMP     jr_gfx_dec2

game_draw_title:
        LDX     tb_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_title_tiles
        STX     [JR_RT_TABLE]
tb_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     tb_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [TB_DT]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [TB_DT]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     tb_title_tile
tb_title_text:
        LDX     tb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; code, highlighted code, attribute, highlighted attribute
tb_look_water:
        .db     TB_TILE_WATER, TB_TILE_WATER, TB_ATTR_WATER, TB_ATTR_WATER_HI
tb_look_plank:
        .db     TB_TILE_PLANK, TB_TILE_PLANK, TB_ATTR_PLANK, TB_ATTR_PLANK_HI

; x, attribute, code, y
tb_title_tiles:
        .db     8, TB_ATTR_WATER, TB_TILE_WATER, 3
        .db     10, TB_ATTR_PLANK, TB_TILE_PLANK, 3
        .db     12, TB_ATTR_PLANK, TB_TILE_PLANK, 3
        .db     14, TB_ATTR_HERO, TB_TILE_HERO + 12, 3
        .db     16, TB_ATTR_PLANK, TB_TILE_PLANK, 3
        .db     18, TB_ATTR_WATER, TB_TILE_WATER, 3
        .db     20, TB_ATTR_GATE, TB_TILE_GATE, 3
        .db     0xff

tb_hud:
        .db     1, 0, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     24, 0, TB_ATTR_LABEL
        .dw     tb_txt_tide
        .db     19, 3, TB_ATTR_LABEL
        .dw     tb_txt_engine
        .db     20, 15, TB_ATTR_LABEL
        .dw     tb_txt_changes
        .db     26, 16, TB_ATTR_DIM
        .dw     tb_txt_limit
        .db     1, 19, TB_ATTR_DIM
        .dw     tb_txt_shore
        .db     0xff
tb_title_lines:
        .db     10, 8, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     3, 10, TB_ATTR_LABEL
        .dw     tb_txt_tagline
        .db     8, 15, TB_ATTR_TEXT
        .dw     tb_txt_start
        .db     5, 17, TB_ATTR_TEXT
        .dw     tb_txt_howto
        .db     4, 22, TB_ATTR_DIM
        .dw     tb_txt_credit
        .db     0xff
tb_help_lines:
        .db     10, 2, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     1, 5, TB_ATTR_TEXT
        .dw     tb_help_1
        .db     1, 7, TB_ATTR_TEXT
        .dw     tb_help_2
        .db     1, 9, TB_ATTR_TEXT
        .dw     tb_help_3
        .db     1, 11, TB_ATTR_TEXT
        .dw     tb_help_4
        .db     1, 13, TB_ATTR_TEXT
        .dw     tb_help_5
        .db     1, 15, TB_ATTR_TEXT
        .dw     tb_help_6
        .db     1, 21, TB_ATTR_LABEL
        .dw     tb_help_back
        .db     0xff

tb_txt_name:
        .db     "TIDE BRIDGE", 0
tb_txt_tide:
        .db     "TIDE", 0
tb_txt_engine:
        .db     "TIDE ENGINE", 0
tb_txt_changes:
        .db     "CHANGES", 0
tb_txt_limit:
        .db     "/30", 0
tb_txt_shore:
        .db     "SHORE", 0
tb_txt_select:
        .db     "SELECT", 0
tb_txt_row:
        .db     "ROW", 0
tb_txt_col:
        .db     "COL", 0
tb_txt_crossing:
        .db     "CROSSING", 0
tb_txt_gate:
        .db     "TO THE GATE", 0
tb_txt_arrived:
        .db     "ARRIVED!", 0
tb_txt_hooray:
        .db     "HOORAY!", 0
tb_txt_tagline:
        .db     "LINK THE SHORE TO THE GATE", 0
tb_txt_start:
        .db     "RETURN : START", 0
tb_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
tb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
tb_help_1:
        .db     "W/S : SELECT BRIDGE", 0
tb_help_2:
        .db     "A/D : ROW OR COLUMN", 0
tb_help_3:
        .db     "RETURN : RAISE / LOWER LINE", 0
tb_help_4:
        .db     "LINK THE SHORE TO THE GATE.", 0
tb_help_5:
        .db     "THIRTY CHANGES PER TIDE.", 0
tb_help_6:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
tb_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     tb_sfx_step, tb_sfx_raise, tb_jingle_win, tb_jingle_lose
tb_sfx_step:
        .db     180, 2, 0, 0
tb_sfx_raise:
        .db     200, 3, 150, 3, 100, 4, 0, 0

; Title: a sea song in D major, quarter note = 16 frames, looping.
tb_title_song:
        .db     1
        .dw     tb_title_melody, tb_title_harmony, tb_title_bass
tb_title_melody:
        .db     AU_A4, 16, AU_D5, 24, AU_E5, 8, AU_FS5, 16, AU_A5, 16
        .db     AU_G5, 16, AU_E5, 16, AU_FS5, 32
        .db     AU_D5, 16, AU_E5, 16, AU_FS5, 16, AU_G5, 16
        .db     AU_A5, 16, AU_CS5, 16, AU_D5, 32, 0, 0
tb_title_harmony:
        .db     AU_FS4, 32, AU_A4, 32, AU_B4, 32, AU_A4, 32
        .db     AU_A4, 32, AU_B4, 32, AU_G4, 32, AU_FS4, 32, 0, 0
tb_title_bass:
        .db     AU_D3, 16, AU_A2, 16, AU_D3, 16, AU_A2, 16
        .db     AU_G2, 16, AU_A2, 16, AU_D3, 32
        .db     AU_B2, 16, AU_A2, 16, AU_G2, 16, AU_E2, 16
        .db     AU_A2, 16, AU_A2, 16, AU_D3, 32, 0, 0

; Across: D major arpeggio over the tonic (54 frames).
tb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     tb_win_melody, tb_win_harmony, tb_win_bass
tb_win_melody:
        .db     AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_D6, 30, 0, 0
tb_win_harmony:
        .db     AU_A4, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 30, 0, 0
tb_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
tb_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     tb_lose_melody, tb_lose_harmony, tb_lose_bass
tb_lose_melody:
        .db     AU_A4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
tb_lose_harmony:
        .db     AU_F4, 12, AU_E4, 12, AU_D4, 12, AU_CS4, 30, 0, 0
tb_lose_bass:
        .db     AU_D3, 36, AU_A2, 30, 0, 0

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

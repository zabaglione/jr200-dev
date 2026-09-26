; SPDX-License-Identifier: MIT
; PEG GARDEN for JR-200: a port of jr100dev games/peg_garden/rules.py 1.5.1.
; The garden, the jump rule and the five-peg goal follow the upstream source;
; display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "PEG-GARDEN"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: b[25], s.cursor, s.selected, s.left, s.jumping, s.jump.
PG_BOARD:           .equ    GAME_STATE
PG_CURSOR:          .equ    GAME_STATE + 25
PG_SELECTED:        .equ    GAME_STATE + 26
PG_LEFT:            .equ    GAME_STATE + 27
PG_JUMPING:         .equ    GAME_STATE + 28
PG_JUMP:            .equ    GAME_STATE + 29
; Rule work bytes.
PG_DIR:             .equ    GAME_STATE + 32
PG_MID:             .equ    GAME_STATE + 33
PG_END:             .equ    GAME_STATE + 34
PG_MP:              .equ    GAME_STATE + 35
PG_MA:              .equ    GAME_STATE + 36
PG_MC:              .equ    GAME_STATE + 37
; Drawing work bytes.
PG_DI:              .equ    GAME_STATE + 48
PG_DX:              .equ    GAME_STATE + 49
PG_DY:              .equ    GAME_STATE + 50
PG_DCODE:           .equ    GAME_STATE + 51
PG_DK:              .equ    GAME_STATE + 52

PG_NONE:            .equ    255
PG_PEG:             .equ    4
PG_ROCK:            .equ    1
PG_GOAL:            .equ    5
PG_TILE_HOLE:       .equ    0x80
PG_TILE_ROCK:       .equ    0x84
PG_TILE_PEG:        .equ    0x88
PG_TILE_PICK:       .equ    0x8c
; Attribute bytes: 0x40 selects PCG, bits 3-5 background, bits 0-2 foreground.
PG_ATTR_HOLE:       .equ    0x60        ; black hole on green
PG_ATTR_ROCK:       .equ    0x61        ; blue rock on green
PG_ATTR_PEG:        .equ    0x66        ; yellow peg on green
PG_ATTR_PICK:       .equ    0x63        ; magenta framed peg on green
PG_ATTR_HOP:        .equ    0x46        ; yellow peg in the air, black background
PG_ATTR_LAWN:       .equ    0x20        ; plain character cell, green background
PG_ATTR_CURSOR:     .equ    0x27        ; white '>' on green
PG_ATTR_TEXT:       .equ    0x07
PG_ATTR_LABEL:      .equ    0x04
PG_ATTR_TITLE:      .equ    0x06
PG_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     pg_patterns
        LDAA    PG_TILE_HOLE
        LDAB    16
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; b[i] = 1 on the four corners, else 4; b[12] = 0.
game_init:
        JSR     jr_music_stop
        LDX     PG_BOARD
        CLRA
pg_init_cell:
        PSHA
        LDAB    PG_PEG
        CMPA    0
        BEQ     pg_init_rock
        CMPA    4
        BEQ     pg_init_rock
        CMPA    20
        BEQ     pg_init_rock
        CMPA    24
        BNE     pg_init_store
pg_init_rock:
        LDAB    PG_ROCK
pg_init_store:
        STAB    [X]
        INX
        PULA
        INCA
        CMPA    25
        BNE     pg_init_cell
        CLR     [PG_BOARD + 12]
        LDAA    12
        STAA    [PG_CURSOR]
        LDAA    PG_NONE
        STAA    [PG_SELECTED]
        LDAA    20
        STAA    [PG_LEFT]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     pg_confirm
        BCC     pg_act_done
        TAB
        LDAA    [PG_CURSOR]
        JSR     pg_move
        STAA    [PG_CURSOR]
pg_act_done:
        RTS

pg_confirm:
        LDAA    [PG_SELECTED]
        CMPA    PG_NONE
        BNE     pg_try
        LDAA    [PG_CURSOR]
        JSR     pg_cell_x
        LDAA    [X]
        CMPA    PG_PEG
        BNE     pg_act_done
        LDAA    [PG_CURSOR]
        STAA    [PG_SELECTED]
        CLRA
        JMP     jr_port_sound

; for a in range(4): mid = move(sel, a + 1); end = move(mid, a + 1); jump when
; mid != sel, end != mid, end == cursor, b[mid] == 4 and b[end] == 0.
pg_try:
        CLR     [PG_DIR]
pg_try_dir:
        LDAA    [PG_SELECTED]
        LDAB    [PG_DIR]
        INCB
        JSR     pg_move
        STAA    [PG_MID]
        LDAB    [PG_DIR]
        INCB
        JSR     pg_move
        STAA    [PG_END]
        LDAA    [PG_MID]
        CMPA    [PG_SELECTED]
        BEQ     pg_try_next
        LDAA    [PG_END]
        CMPA    [PG_MID]
        BEQ     pg_try_next
        CMPA    [PG_CURSOR]
        BNE     pg_try_next
        LDAA    [PG_MID]
        JSR     pg_cell_x
        LDAA    [X]
        CMPA    PG_PEG
        BNE     pg_try_next
        LDAA    [PG_END]
        JSR     pg_cell_x
        TST     [X]
        BNE     pg_try_next
        JSR     pg_do_jump
pg_try_next:
        INC     [PG_DIR]
        LDAA    [PG_DIR]
        CMPA    4
        BNE     pg_try_dir
        LDAA    PG_NONE
        STAA    [PG_SELECTED]
        LDAA    [PG_LEFT]
        CMPA    PG_GOAL + 1
        BCC     pg_act_done
        JMP     jr_port_win

pg_do_jump:
        LDAA    [PG_MID]
        JSR     pg_cell_x
        CLR     [X]
        LDAA    [PG_SELECTED]
        JSR     pg_cell_x
        CLR     [X]
        LDAA    1
        STAA    [PG_JUMPING]
        LDAA    [PG_SELECTED]
        STAA    [PG_JUMP]
        LDAA    3
        JSR     jr_port_animate
        LDAA    [PG_MID]
        STAA    [PG_JUMP]
        LDAA    6
        JSR     jr_port_animate
        LDAA    [PG_END]
        STAA    [PG_JUMP]
        LDAA    3
        JSR     jr_port_animate
        LDAA    [PG_END]
        JSR     pg_cell_x
        LDAA    PG_PEG
        STAA    [X]
        CLR     [PG_JUMPING]
        DEC     [PG_LEFT]
        LDAA    1
        JMP     jr_port_sound

; A = cell -> X = &b[cell]. Preserves B.
pg_cell_x:
        LDX     PG_BOARD
        JMP     jr_add_x_a

; A = position, B = action 1-4 -> A = moved position (5x5, stops at edges).
pg_move:
        STAA    [PG_MP]
        STAB    [PG_MA]
        LDAB    5
        JSR     jr_divmod8
        STAB    [PG_MC]
        LDAA    [PG_MP]
        LDAB    [PG_MA]
        CMPB    JR_KEY_UP
        BNE     pg_move_down
        CMPA    5
        BCS     pg_move_done
        SUBA    5
        RTS
pg_move_down:
        CMPB    JR_KEY_DOWN
        BNE     pg_move_left
        CMPA    20
        BCC     pg_move_done
        ADDA    5
        RTS
pg_move_left:
        CMPB    JR_KEY_LEFT
        BNE     pg_move_right
        TST     [PG_MC]
        BEQ     pg_move_done
        DECA
        RTS
pg_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     pg_move_done
        LDAB    [PG_MC]
        CMPB    4
        BCC     pg_move_done
        INCA
pg_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    PG_ATTR_TEXT
        JSR     jr_gfx_fill
        JSR     pg_draw_lawn
        LDX     pg_hud
        JSR     jr_gfx_lines
        ; tiles at (2 + i % 5 * 3, 4 + i // 5 * 3)
        CLR     [PG_DI]
pg_draw_cell:
        LDAA    [PG_DI]
        JSR     pg_cell_x
        LDAA    [X]
        LDX     pg_tile_codes
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 5]
        STAA    [PG_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [PG_DI]
        CMPA    [PG_SELECTED]
        BNE     pg_draw_tile
        LDAA    PG_TILE_PICK
        STAA    [PG_DCODE]
        LDAA    PG_ATTR_PICK
        STAA    [JR_RT_COLOR]
pg_draw_tile:
        LDAA    [PG_DI]
        JSR     pg_cell_xy
        JSR     jr_gfx_at
        LDAA    [PG_DCODE]
        JSR     jr_gfx_tile
        INC     [PG_DI]
        LDAA    [PG_DI]
        CMPA    25
        BNE     pg_draw_cell
        ; cursor '>' at (1 + i % 5 * 3, 4 + i // 5 * 3)
        LDAA    PG_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    [PG_CURSOR]
        JSR     pg_cell_xy
        DECA
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; the jumping peg one row higher
        TST     [PG_JUMPING]
        BEQ     pg_draw_counts
        LDAA    PG_ATTR_HOP
        STAA    [JR_RT_COLOR]
        LDAA    [PG_JUMP]
        JSR     pg_cell_xy
        DECB
        JSR     jr_gfx_at
        LDAA    PG_TILE_PEG
        JSR     jr_gfx_tile
pg_draw_counts:
        LDAA    PG_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [PG_LEFT]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    13
        JSR     jr_gfx_at
        LDAA    PG_GOAL
        JMP     jr_gfx_dec2

; Green lawn behind the board: columns 1-16, rows 3-18.
pg_draw_lawn:
        LDAA    PG_ATTR_LAWN
        STAA    [JR_RT_COLOR]
        LDAA    3
        STAA    [PG_DY]
pg_lawn_row:
        LDAA    1
        LDAB    [PG_DY]
        JSR     jr_gfx_at
        LDAB    16
pg_lawn_cell:
        LDAA    0x20
        JSR     jr_gfx_putc
        DECB
        BNE     pg_lawn_cell
        INC     [PG_DY]
        LDAA    [PG_DY]
        CMPA    19
        BNE     pg_lawn_row
        RTS

; A = cell -> A = 2 + cell % 5 * 3, B = 4 + cell // 5 * 3.
pg_cell_xy:
        LDAB    5
        JSR     jr_divmod8
        STAB    [PG_DK]
        TAB
        ASLA
        ABA
        ADDA    4
        TAB
        LDAA    [PG_DK]
        STAB    [PG_DK]
        TAB
        ASLA
        ABA
        ADDA    2
        LDAB    [PG_DK]
        RTS

game_draw_title:
        LDX     pg_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    PG_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pg_title_tiles
        STX     [JR_RT_TABLE]
pg_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     pg_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [PG_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [PG_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     pg_title_tile
pg_title_text:
        LDX     pg_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    PG_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pg_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; Tile code by b[i] (0 hole, 1 rock, 4 peg), then the attribute 5 bytes later.
pg_tile_codes:
        .db     PG_TILE_HOLE, PG_TILE_ROCK, PG_TILE_HOLE, PG_TILE_HOLE, PG_TILE_PEG
        .db     PG_ATTR_HOLE, PG_ATTR_ROCK, PG_ATTR_HOLE, PG_ATTR_HOLE, PG_ATTR_PEG

pg_hud:
        .db     1, 0, PG_ATTR_TITLE
        .dw     pg_txt_name
        .db     20, 3, PG_ATTR_LABEL
        .dw     pg_txt_garden
        .db     21, 6, PG_ATTR_LABEL
        .dw     pg_txt_remain
        .db     21, 12, PG_ATTR_LABEL
        .dw     pg_txt_target
        .db     20, 16, 0x06
        .dw     pg_txt_hint_peg
        .db     20, 17, 0x05
        .dw     pg_txt_hint_rock
        .db     20, 18, 0x03
        .dw     pg_txt_hint_pick
        .db     0xff

; x, attribute, tile, y: a peg hopping over a peg into a hole, with rocks.
pg_title_tiles:
        .db     6, PG_ATTR_ROCK, PG_TILE_ROCK, 4
        .db     9, PG_ATTR_PICK, PG_TILE_PICK, 4
        .db     12, PG_ATTR_PEG, PG_TILE_PEG, 4
        .db     15, PG_ATTR_HOLE, PG_TILE_HOLE, 4
        .db     18, PG_ATTR_PEG, PG_TILE_PEG, 4
        .db     21, PG_ATTR_ROCK, PG_TILE_ROCK, 4
        .db     12, PG_ATTR_HOP, PG_TILE_PEG, 1
        .db     0xff
pg_title_lines:
        .db     11, 9, PG_ATTR_TITLE
        .dw     pg_txt_name
        .db     5, 11, PG_ATTR_LABEL
        .dw     pg_txt_tagline
        .db     8, 15, PG_ATTR_TEXT
        .dw     pg_txt_start
        .db     5, 17, PG_ATTR_TEXT
        .dw     pg_txt_howto
        .db     4, 22, PG_ATTR_DIM
        .dw     pg_txt_credit
        .db     0xff
pg_help_lines:
        .db     10, 2, PG_ATTR_TITLE
        .dw     pg_txt_name
        .db     2, 5, PG_ATTR_TEXT
        .dw     pg_help_1
        .db     2, 7, PG_ATTR_TEXT
        .dw     pg_help_2
        .db     2, 9, PG_ATTR_TEXT
        .dw     pg_help_3
        .db     2, 11, PG_ATTR_TEXT
        .dw     pg_help_4
        .db     2, 13, PG_ATTR_TEXT
        .dw     pg_help_5
        .db     2, 15, PG_ATTR_TEXT
        .dw     pg_help_6
        .db     2, 17, PG_ATTR_TEXT
        .dw     pg_help_7
        .db     2, 20, PG_ATTR_LABEL
        .dw     pg_help_back
        .db     0xff

pg_txt_name:
        .db     "PEG GARDEN", 0
pg_txt_garden:
        .db     "STONE GARDEN", 0
pg_txt_remain:
        .db     "REMAIN", 0
pg_txt_target:
        .db     "TARGET", 0
pg_txt_hint_peg:
        .db     "PEG  YELLOW", 0
pg_txt_hint_rock:
        .db     "ROCK BLUE", 0
pg_txt_hint_pick:
        .db     "PICK FRAMED", 0
pg_txt_tagline:
        .db     "LEAVE FIVE PEGS OR FEWER", 0
pg_txt_start:
        .db     "RETURN : START", 0
pg_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
pg_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
pg_help_1:
        .db     "WASD : SELECT A CELL", 0
pg_help_2:
        .db     "RETURN : PEG, THEN HOLE", 0
pg_help_3:
        .db     "JUMP OVER ONE ADJACENT PEG.", 0
pg_help_4:
        .db     "THE JUMPED PEG IS REMOVED.", 0
pg_help_5:
        .db     "LEAVE FIVE PEGS OR FEWER.", 0
pg_help_6:
        .db     "SPACE : RESTORE THE GARDEN", 0
pg_help_7:
        .db     "CTRL+C : BACK TO BASIC", 0
pg_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     pg_sfx_pick, pg_sfx_land, pg_jingle_win, pg_jingle_lose
pg_sfx_pick:
        .db     60, 2, 0, 0
pg_sfx_land:
        .db     95, 3, 0, 1, 70, 4, 0, 0

; Title: four bars in G major, quarter note = 24 frames, looping.
pg_title_song:
        .db     1
        .dw     pg_title_melody, pg_title_harmony, pg_title_bass
pg_title_melody:
        .db     AU_G5, 24, AU_B5, 24, AU_D6, 24, AU_B5, 24
        .db     AU_C6, 24, AU_B5, 24, AU_A5, 24, AU_G5, 24
        .db     AU_A5, 24, AU_B5, 24, AU_C6, 24, AU_A5, 24
        .db     AU_G5, 72, 0, 24, 0, 0
pg_title_harmony:
        .db     AU_B4, 48, AU_D5, 48, AU_C5, 48, AU_E5, 48
        .db     AU_C5, 48, AU_D5, 48, AU_B4, 72, 0, 24, 0, 0
pg_title_bass:
        .db     AU_G3, 96, AU_C3, 96, AU_D3, 96, AU_G2, 72, 0, 24, 0, 0

; Clear: rising G major arpeggio over a held tonic (54 frames).
pg_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     pg_win_melody, pg_win_harmony, pg_win_bass
pg_win_melody:
        .db     AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_G6, 30, 0, 0
pg_win_harmony:
        .db     AU_B4, 8, AU_D5, 8, AU_G5, 8, AU_B5, 30, 0, 0
pg_win_bass:
        .db     AU_G3, 24, AU_G2, 30, 0, 0
; Retry prompt: falling minor line (66 frames). The garden has no loss rule.
pg_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     pg_lose_melody, pg_lose_harmony, pg_lose_bass
pg_lose_melody:
        .db     AU_D5, 12, AU_C5, 12, AU_B4, 12, AU_A4, 30, 0, 0
pg_lose_harmony:
        .db     AU_F4, 12, AU_E4, 12, AU_D4, 12, AU_C4, 30, 0, 0
pg_lose_bass:
        .db     AU_D3, 36, AU_D2, 30, 0, 0

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

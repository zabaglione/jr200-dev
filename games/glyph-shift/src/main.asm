; SPDX-License-Identifier: MIT
; GLYPH SHIFT for JR-200: a port of jr100dev games/glyph_shift/rules.py 1.6.1.
; The forty chambers (upstream levels.json), the rule swap between box and
; foe walls, the gate, optional runes, moves against par and the star rating
; follow the upstream source. The ranked campaign (stage map, best ratings
; and passwords) is sdk/ranked.inc; display, colour and three-voice sound use
; the JR-200 port SDK.
        .filename.jr "GLYPH-SHIFT"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_RANK:            .equ    0x4760
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    40
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_PASSWORD_TAG:  .equ    0x83
GAME_STAR_CODE:     .equ    0x10
GAME_STAR_ATTR:     .equ    0x46

; Upstream state (same order as tests/model.py), then b[64]; the stage's
; start, runes and par follow.
GS_FACING:          .equ    GAME_STATE
GS_POS:             .equ    GAME_STATE + 1
GS_ORIGIN:          .equ    GAME_STATE + 2
GS_PHASE:           .equ    GAME_STATE + 3
GS_CHANGES:         .equ    GAME_STATE + 4
GS_PAR:             .equ    GAME_STATE + 5
RANK_MOVES:         .equ    GAME_STATE + 6
RANK_OVERFLOW:      .equ    GAME_STATE + 7
RANK_RUNES:         .equ    GAME_STATE + 8
RANK_STARS:         .equ    GAME_STATE + 9
GS_B:               .equ    GAME_STATE + 10
GS_TAIL:            .equ    GAME_STATE + 74     ; d[64-69]
RANK_RUNE_A:        .equ    GS_TAIL + 3
RANK_RUNE_B:        .equ    GS_TAIL + 4
RANK_PAR:           .equ    GS_TAIL + 5
; Rule and drawing work bytes.
GS_I:               .equ    GAME_STATE + 96
GS_T:               .equ    GAME_STATE + 97
GS_N:               .equ    GAME_STATE + 98
GS_DI:              .equ    GAME_STATE + 104
GS_DCODE:           .equ    GAME_STATE + 105

GS_TILE_FLOOR:      .equ    0x80
GS_TILE_WALL:       .equ    0x84
GS_TILE_GATE:       .equ    0x88
GS_TILE_BOX:        .equ    0x8c
GS_TILE_FOE:        .equ    0x90
GS_TILE_RUNE:       .equ    0x94
GS_TILE_HERO:       .equ    0x00        ; + 4 * (facing - 1)
GS_ATTR_FLOOR:      .equ    0x41
GS_ATTR_WALL:       .equ    0x47
GS_ATTR_GATE:       .equ    0x44
GS_ATTR_BOX_WALL:   .equ    0x56        ; yellow box standing as a wall (red ground)
GS_ATTR_FOE_WALL:   .equ    0x53        ; magenta foe standing as a wall
GS_ATTR_OPEN:       .equ    0x41        ; a glyph you can walk through: dim blue
GS_ATTR_RUNE:       .equ    0x46
GS_ATTR_HERO:       .equ    0x47
GS_ATTR_TEXT:       .equ    0x07
GS_ATTR_LABEL:      .equ    0x04
GS_ATTR_TITLE:      .equ    0x06
GS_ATTR_DIM:        .equ    0x05
GS_ATTR_PICK:       .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     gs_patterns
        LDAA    GS_TILE_FLOOR
        LDAB    24
        JSR     jr_pcg_load
        LDX     gs_hero_patterns
        CLRA
        LDAB    16
        JSR     jr_pcg_load
        LDX     jr_rank_star_patterns
        LDAA    GAME_STAR_CODE
        LDAB    2
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; A = stage -> X = its packed data (38 bytes).
gs_stage:
        STAA    [GS_T]
        LDX     gs_levels
gs_stage_next:
        TST     [GS_T]
        BEQ     gs_stage_done
        LDAA    38
        JSR     jr_add_x_a
        DEC     [GS_T]
        BRA     gs_stage_next
gs_stage_done:
        RTS

game_level_par:
        JSR     gs_stage
        LDAA    [X + 37]
        RTS

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        JSR     gs_stage
        CLR     [GS_I]
gs_init_unpack:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        LDAA    [GS_I]
        ASLA
        LDX     GS_B
        JSR     jr_add_x_a
        PULA
        TAB
        LSRA
        LSRA
        LSRA
        LSRA
        STAA    [X]
        ANDB    15
        STAB    [X + 1]
        LDX     [JR_RT_TABLE]
        INX
        INC     [GS_I]
        LDAA    [GS_I]
        CMPA    32
        BNE     gs_init_unpack
        CLRB
gs_init_tail:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        TBA
        LDX     GS_TAIL
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        LDX     [JR_RT_TABLE]
        INX
        INCB
        CMPB    6
        BNE     gs_init_tail
        LDAA    2
        STAA    [GS_FACING]
        LDAA    [GS_TAIL]
        STAA    [GS_POS]
        STAA    [GS_ORIGIN]
        LDAA    [RANK_PAR]
        STAA    [GS_PAR]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        TSTA
        BNE     gs_act_done_near173
        JMP     gs_act_done
gs_act_done_near173:
        CMPA    JR_KEY_CONFIRM
        BCS     gs_act_walk
        BNE     gs_act_gate
        ; RETURN rewrites the rule: boxes or foes become the walls
        LDAA    [GS_PHASE]
        EORA    1
        STAA    [GS_PHASE]
        LDAA    [GS_CHANGES]
        CMPA    255
        BEQ     gs_act_spend
        INC     [GS_CHANGES]
gs_act_spend:
        JSR     jr_rank_spend
        LDAA    1
        JSR     jr_port_sound
        BRA     gs_act_gate
gs_act_walk:
        STAA    [GS_FACING]
        TAB
        LDAA    [GS_POS]
        JSR     gs_move
        CMPA    [GS_POS]
        BEQ     gs_act_gate
        STAA    [GS_N]
        LDX     GS_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    1
        BEQ     gs_act_gate
        LDAB    [GS_PHASE]
        CMPA    4
        BNE     gs_act_foe
        TSTB
        BEQ     gs_act_gate
gs_act_foe:
        CMPA    5
        BNE     gs_act_step
        TSTB
        BNE     gs_act_gate
gs_act_step:
        LDAA    [GS_POS]
        STAA    [GS_ORIGIN]
        LDAA    [GS_N]
        STAA    [GS_POS]
        CLRA
        JSR     jr_port_sound
        LDAA    2
        JSR     jr_port_animate
        LDAA    [GS_POS]
        STAA    [GS_ORIGIN]
        JSR     jr_rank_spend
        LDAA    [GS_POS]
        JSR     jr_rank_take
gs_act_gate:
        LDAA    [GS_POS]
        LDX     GS_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    3
        BNE     gs_act_done
        JMP     jr_rank_clear
gs_act_done:
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
gs_move:
        STAA    [GS_I]
        CMPB    JR_KEY_UP
        BNE     gs_move_down
        CMPA    8
        BCS     gs_move_done
        SUBA    8
        RTS
gs_move_down:
        CMPB    JR_KEY_DOWN
        BNE     gs_move_side
        CMPA    56
        BCC     gs_move_done
        ADDA    8
        RTS
gs_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     gs_move_right
        TSTA
        BEQ     gs_move_stay
        LDAA    [GS_I]
        DECA
        RTS
gs_move_right:
        CMPA    7
        BCC     gs_move_stay
        LDAA    [GS_I]
        INCA
        RTS
gs_move_stay:
        LDAA    [GS_I]
gs_move_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = cell kind -> A = tile code, B = attribute (boxes and foes by the rule).
gs_look:
        LDX     gs_looks
        ASLA
        JSR     jr_add_x_a
        LDAB    [X + 1]
        LDAA    [X]
        CMPA    GS_TILE_BOX
        BNE     gs_look_foe
        TST     [GS_PHASE]
        BEQ     gs_look_done
        LDAB    GS_ATTR_OPEN
gs_look_foe:
        CMPA    GS_TILE_FOE
        BNE     gs_look_done
        TST     [GS_PHASE]
        BNE     gs_look_done
        LDAB    GS_ATTR_OPEN
gs_look_done:
        RTS

game_draw:
        LDAA    0x20
        LDAB    GS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gs_hud
        JSR     jr_gfx_lines
        CLR     [GS_DI]
gs_draw_cell:
        LDAA    [GS_DI]
        LDX     GS_B
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     gs_look
        STAA    [GS_DCODE]
        LDAA    [GS_DI]
        CMPA    [RANK_RUNE_A]
        BNE     gs_draw_rune_b
        LDAA    [RANK_RUNES]
        ANDA    1
        BNE     gs_draw_put
        BRA     gs_draw_rune
gs_draw_rune_b:
        CMPA    [RANK_RUNE_B]
        BNE     gs_draw_put
        LDAA    [RANK_RUNES]
        ANDA    2
        BNE     gs_draw_put
gs_draw_rune:
        LDAA    GS_TILE_RUNE
        STAA    [GS_DCODE]
        LDAB    GS_ATTR_RUNE
gs_draw_put:
        STAB    [JR_RT_COLOR]
        LDAA    [GS_DI]
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        ANDA    7
        ASLA
        JSR     jr_gfx_at
        LDAA    [GS_DCODE]
        JSR     jr_gfx_tile
        INC     [GS_DI]
        LDAA    [GS_DI]
        CMPA    64
        BNE     gs_draw_cell
        ; the walker, half-way between cells while stepping
        LDAA    GS_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [GS_POS]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [GS_DI]
        STAB    [GS_DCODE]
        LDAA    [GS_ORIGIN]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [GS_DI]
        ADDB    [GS_DCODE]
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [GS_FACING]
        DECA
        ASLA
        ASLA
        ADDA    GS_TILE_HERO
        JSR     jr_gfx_tile
        ; the rule table: which glyph is a wall now
        LDAA    4
        JSR     gs_look
        STAB    [JR_RT_COLOR]
        PSHA
        LDAA    30
        LDAB    4
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_tile
        LDAA    5
        JSR     gs_look
        STAB    [JR_RT_COLOR]
        PSHA
        LDAA    30
        LDAB    8
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_tile
        LDAA    GS_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAB    5
        TST     [GS_PHASE]
        BEQ     gs_draw_rule
        LDAB    9
gs_draw_rule:
        LDAA    18
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    GS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    15
        JSR     jr_gfx_at
        LDAA    [GS_CHANGES]
        JSR     jr_rank_dec3
        JMP     jr_rank_hud

game_draw_title:
        LDX     gs_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    GS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gs_title_tiles
        STX     [JR_RT_TABLE]
gs_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     gs_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [GS_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [GS_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     gs_title_tile
gs_title_text:
        LDX     gs_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    GS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gs_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0x66, 8, 0
game_title_text:
        .db     "GLYPH SHIFT", 0

; by cell kind 0-5: code, attribute (4 and 5 by the rule)
gs_looks:
        .db     GS_TILE_FLOOR, GS_ATTR_FLOOR, GS_TILE_WALL, GS_ATTR_WALL
        .db     GS_TILE_FLOOR, GS_ATTR_FLOOR, GS_TILE_GATE, GS_ATTR_GATE
        .db     GS_TILE_BOX, GS_ATTR_BOX_WALL, GS_TILE_FOE, GS_ATTR_FOE_WALL

; x, attribute, code, y
gs_title_tiles:
        .db     8, GS_ATTR_WALL, GS_TILE_WALL, 3
        .db     10, GS_ATTR_HERO, GS_TILE_HERO + 12, 3
        .db     12, GS_ATTR_BOX_WALL, GS_TILE_BOX, 3
        .db     14, GS_ATTR_OPEN, GS_TILE_FOE, 3
        .db     16, GS_ATTR_RUNE, GS_TILE_RUNE, 3
        .db     18, GS_ATTR_FLOOR, GS_TILE_FLOOR, 3
        .db     20, GS_ATTR_GATE, GS_TILE_GATE, 3
        .db     0xff

gs_hud:
        .db     1, 0, GS_ATTR_TITLE
        .dw     game_title_text
        .db     18, 2, GS_ATTR_LABEL
        .dw     gs_txt_table
        .db     19, 5, GS_ATTR_TEXT
        .dw     gs_txt_box
        .db     19, 9, GS_ATTR_TEXT
        .dw     gs_txt_foe
        .db     19, 14, GS_ATTR_LABEL
        .dw     gs_txt_rewrites
        .db     0xff
gs_title_lines:
        .db     10, 8, GS_ATTR_TITLE
        .dw     game_title_text
        .db     2, 10, GS_ATTR_LABEL
        .dw     gs_txt_tagline
        .db     4, 15, GS_ATTR_TEXT
        .dw     gs_txt_start
        .db     4, 17, GS_ATTR_DIM
        .dw     gs_txt_credit
        .db     0xff
gs_help_lines:
        .db     10, 1, GS_ATTR_TITLE
        .dw     game_title_text
        .db     1, 3, GS_ATTR_TEXT
        .dw     gs_help_1
        .db     1, 5, GS_ATTR_TEXT
        .dw     gs_help_2
        .db     1, 7, GS_ATTR_TEXT
        .dw     gs_help_3
        .db     1, 9, GS_ATTR_TEXT
        .dw     gs_help_4
        .db     1, 11, GS_ATTR_TEXT
        .dw     gs_help_5
        .db     1, 13, GS_ATTR_TEXT
        .dw     gs_help_6
        .db     1, 15, GS_ATTR_TEXT
        .dw     gs_help_7
        .db     1, 17, GS_ATTR_TEXT
        .dw     gs_help_8
        .db     1, 19, GS_ATTR_TEXT
        .dw     gs_help_9
        .db     1, 21, GS_ATTR_LABEL
        .dw     gs_help_back
        .db     0xff

gs_txt_table:
        .db     "RULE TABLE", 0
gs_txt_box:
        .db     "BOX IS WALL", 0
gs_txt_foe:
        .db     "FOE IS WALL", 0
gs_txt_rewrites:
        .db     "REWRITES", 0
gs_txt_tagline:
        .db     "REWRITE THE RULE, FIND THE GATE", 0
gs_txt_start:
        .db     "RETURN : PLAY THE STAGE", 0
gs_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
gs_help_1:
        .db     "WASD : MOVE", 0
gs_help_2:
        .db     "RETURN : SWAP THE WALL RULE", 0
gs_help_3:
        .db     "REACH THE DIAMOND GATE.", 0
gs_help_4:
        .db     "WALK OVER OPTIONAL RUNES.", 0
gs_help_5:
        .db     "PAR OR LESS = TWO STARS.", 0
gs_help_6:
        .db     "PLUS BOTH RUNES = THREE STARS.", 0
gs_help_7:
        .db     "OVER PAR = CLEAR / ONE STAR.", 0
gs_help_8:
        .db     "SPACE RETRY / F STAGE SELECT", 0
gs_help_9:
        .db     "X : PASSWORD (TITLE / MAP)", 0
gs_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     gs_sfx_slide, gs_sfx_crystal, gs_jingle_win, gs_jingle_lose
gs_sfx_slide:
        .db     60, 1, 0, 0
gs_sfx_crystal:
        .db     40, 3, 32, 3, 27, 6, 0, 0

; Title: a runic march in D minor, eighth note = 8 frames, looping.
gs_title_song:
        .db     1
        .dw     gs_title_melody, gs_title_harmony, gs_title_bass
gs_title_melody:
        .db     AU_D5, 8, AU_A4, 8, AU_D5, 8, AU_F5, 8, AU_E5, 16, AU_C5, 16
        .db     AU_D5, 8, AU_F5, 8, AU_A5, 8, AU_G5, 8, AU_F5, 16, AU_E5, 16
        .db     AU_F5, 8, AU_E5, 8, AU_D5, 8, AU_C5, 8, AU_AS4, 16, AU_A4, 16
        .db     AU_G4, 8, AU_AS4, 8, AU_A4, 8, AU_CS5, 8, AU_D5, 32, 0, 0
gs_title_harmony:
        .db     AU_A4, 32, AU_G4, 32, AU_A4, 32, AU_C5, 32
        .db     AU_A4, 32, AU_F4, 32, AU_E4, 32, AU_F4, 32, 0, 0
gs_title_bass:
        .db     AU_D3, 16, AU_A2, 16, AU_C3, 16, AU_C3, 16
        .db     AU_D3, 16, AU_F2, 16, AU_A2, 16, AU_A2, 16
        .db     AU_D3, 16, AU_A2, 16, AU_G2, 16, AU_F2, 16
        .db     AU_E2, 16, AU_A2, 16, AU_D2, 32, 0, 0

; Gate reached: D major arpeggio over the tonic (54 frames).
gs_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     gs_win_melody, gs_win_harmony, gs_win_bass
gs_win_melody:
        .db     AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_D6, 30, 0, 0
gs_win_harmony:
        .db     AU_A4, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 30, 0, 0
gs_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
gs_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     gs_lose_melody, gs_lose_harmony, gs_lose_bass
gs_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
gs_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
gs_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0

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
        .include "../../../sdk/ranked.inc"
        .include "../../../sdk/font_data.inc"

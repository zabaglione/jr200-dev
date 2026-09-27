; SPDX-License-Identifier: MIT
; MAGNET VAULT for JR-200: a port of jr100dev games/magnet_vault/rules.py 1.6.1.
; The forty vaults (upstream levels.json), walking and facing, pulling the box
; in front, the two sockets, optional runes, moves against par and the star
; rating follow the upstream source. The ranked campaign (stage map, best
; ratings and passwords) is sdk/ranked.inc; display, colour and three-voice
; sound use the JR-200 port SDK.
        .filename.jr "MAGNET-VAULT"
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
GAME_PASSWORD_TAG:  .equ    0x62
GAME_STAR_CODE:     .equ    0x10
GAME_STAR_ATTR:     .equ    0x46

; Upstream state (same order as tests/model.py), then b[64] and c[64]; the
; stage's start, boxes, runes and par follow.
MV_POS:             .equ    GAME_STATE
MV_ORIGIN:          .equ    GAME_STATE + 1
MV_FACING:          .equ    GAME_STATE + 2
MV_PULLING:         .equ    GAME_STATE + 3
MV_BLOCK:           .equ    GAME_STATE + 4
MV_PULLS:           .equ    GAME_STATE + 5
MV_PAR:             .equ    GAME_STATE + 6
RANK_MOVES:         .equ    GAME_STATE + 7
RANK_OVERFLOW:      .equ    GAME_STATE + 8
RANK_RUNES:         .equ    GAME_STATE + 9
RANK_STARS:         .equ    GAME_STATE + 10
MV_B:               .equ    GAME_STATE + 11
MV_C:               .equ    GAME_STATE + 75
MV_TAIL:            .equ    GAME_STATE + 139    ; d[64-69]
RANK_RUNE_A:        .equ    MV_TAIL + 3
RANK_RUNE_B:        .equ    MV_TAIL + 4
RANK_PAR:           .equ    MV_TAIL + 5
; Rule and drawing work bytes.
MV_I:               .equ    GAME_STATE + 160
MV_T:               .equ    GAME_STATE + 161
MV_BEFORE:          .equ    GAME_STATE + 162
MV_WAS:             .equ    GAME_STATE + 163
MV_FRONT:           .equ    GAME_STATE + 164
MV_BEHIND:          .equ    GAME_STATE + 165
MV_COUNT:           .equ    GAME_STATE + 166
MV_DI:              .equ    GAME_STATE + 170
MV_DCODE:           .equ    GAME_STATE + 171
MV_DX:              .equ    GAME_STATE + 172

MV_TILE_FLOOR:      .equ    0x80
MV_TILE_WALL:       .equ    0x84
MV_TILE_SOCKET:     .equ    0x88
MV_TILE_BOX:        .equ    0x8c
MV_TILE_RUNE:       .equ    0x90
MV_TILE_HERO:       .equ    0x00        ; + 4 * (facing - 1)
MV_ATTR_FLOOR:      .equ    0x41
MV_ATTR_WALL:       .equ    0x47
MV_ATTR_SOCKET:     .equ    0x43
MV_ATTR_BOX:        .equ    0x45        ; a cyan steel box
MV_ATTR_BOX_IN:     .equ    0x67        ; a box in its socket: white on green
MV_ATTR_RUNE:       .equ    0x46
MV_ATTR_HERO:       .equ    0x47
MV_ATTR_TEXT:       .equ    0x07
MV_ATTR_LABEL:      .equ    0x04
MV_ATTR_TITLE:      .equ    0x06
MV_ATTR_DIM:        .equ    0x05
MV_ATTR_PICK:       .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     mv_patterns
        LDAA    MV_TILE_FLOOR
        LDAB    20
        JSR     jr_pcg_load
        LDX     mv_hero_patterns
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
mv_stage:
        STAA    [MV_T]
        LDX     mv_levels
mv_stage_next:
        TST     [MV_T]
        BEQ     mv_stage_done
        LDAA    38
        JSR     jr_add_x_a
        DEC     [MV_T]
        BRA     mv_stage_next
mv_stage_done:
        RTS

game_level_par:
        JSR     mv_stage
        LDAA    [X + 37]
        RTS

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        JSR     mv_stage
        CLR     [MV_I]
mv_init_unpack:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        LDAA    [MV_I]
        ASLA
        LDX     MV_B
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
        INC     [MV_I]
        LDAA    [MV_I]
        CMPA    32
        BNE     mv_init_unpack
        CLRB
mv_init_tail:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        TBA
        LDX     MV_TAIL
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        LDX     [JR_RT_TABLE]
        INX
        INCB
        CMPB    6
        BNE     mv_init_tail
        LDAA    [MV_TAIL]
        STAA    [MV_POS]
        STAA    [MV_ORIGIN]
        LDAA    4
        STAA    [MV_FACING]
        LDAA    [MV_TAIL + 1]
        JSR     mv_box
        LDAA    1
        STAA    [X]
        LDAA    [MV_TAIL + 2]
        JSR     mv_box
        LDAA    1
        STAA    [X]
        LDAA    [RANK_PAR]
        STAA    [MV_PAR]
        RTS

; A = cell -> X = c[cell] (the box there, if any).
mv_box:
        LDX     MV_C
        JMP     jr_add_x_a

; A = cell -> X = b[cell]; c[cell] is [X + 64].
mv_cell:
        LDX     MV_B
        JMP     jr_add_x_a

game_raw_key:
game_tick:
        RTS

game_act:
        TAB
        LDAA    [MV_POS]
        STAA    [MV_BEFORE]
        LDAA    [MV_FACING]
        STAA    [MV_WAS]
        TBA
        BNE     mv_act_after_near201
        JMP     mv_act_after
mv_act_after_near201:
        CMPA    JR_KEY_CONFIRM
        BEQ     mv_pull
        BCS     mv_act_after_near206
        JMP     mv_act_after
mv_act_after_near206:
        ; walk (or just turn): walls and boxes block
        STAA    [MV_FACING]
        LDAA    [MV_POS]
        JSR     mv_move
        STAA    [MV_T]
        LDX     MV_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    1
        BEQ     mv_act_after
        TST     [X + 64]
        BNE     mv_act_after
        LDAA    [MV_T]
        STAA    [MV_POS]
        BRA     mv_act_after
mv_pull:
        ; RETURN pulls the box in front one step, stepping back
        LDAA    [MV_POS]
        LDAB    [MV_FACING]
        JSR     mv_move
        STAA    [MV_FRONT]
        LDX     mv_opposite - 1
        LDAA    [MV_FACING]
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    [MV_POS]
        JSR     mv_move
        STAA    [MV_BEHIND]
        LDAA    [MV_FRONT]
        JSR     mv_box
        TST     [X]
        BEQ     mv_act_after
        LDAA    [MV_BEHIND]
        JSR     mv_cell
        TST     [X + 64]
        BNE     mv_act_after
        LDAA    [X]
        CMPA    1
        BEQ     mv_act_after
        LDAA    [MV_FRONT]
        JSR     mv_box
        CLR     [X]
        LDAA    [MV_POS]
        JSR     mv_box
        LDAA    1
        STAA    [X]
        STAA    [MV_PULLING]
        LDAA    [MV_FRONT]
        STAA    [MV_BLOCK]
        LDAA    [MV_BEHIND]
        STAA    [MV_POS]
        LDAA    [MV_PULLS]
        CMPA    255
        BEQ     mv_pull_sound
        INC     [MV_PULLS]
mv_pull_sound:
        LDAA    1
        JSR     jr_port_sound
mv_act_after:
        LDAA    [MV_POS]
        CMPA    [MV_BEFORE]
        BEQ     mv_act_turned
        LDAA    [MV_BEFORE]
        STAA    [MV_ORIGIN]
        TST     [MV_PULLING]
        BNE     mv_act_show
        CLRA
        JSR     jr_port_sound
mv_act_show:
        LDAA    2
        JSR     jr_port_animate
        LDAA    [MV_POS]
        STAA    [MV_ORIGIN]
        CLR     [MV_PULLING]
        BRA     mv_act_count
mv_act_turned:
        LDAA    [MV_FACING]
        CMPA    [MV_WAS]
        BEQ     mv_act_sockets
mv_act_count:
        JSR     jr_rank_spend
        LDAA    [MV_POS]
        JSR     jr_rank_take
mv_act_sockets:
        ; both sockets hold a box: the vault opens
        CLR     [MV_COUNT]
        LDX     MV_B
mv_act_socket:
        LDAA    [X]
        CMPA    3
        BNE     mv_act_socket_next
        TST     [X + 64]
        BEQ     mv_act_socket_next
        INC     [MV_COUNT]
mv_act_socket_next:
        INX
        CPX     MV_B + 64
        BNE     mv_act_socket
        LDAA    [MV_COUNT]
        CMPA    2
        BNE     mv_act_done
        JMP     jr_rank_clear
mv_act_done:
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
mv_move:
        STAA    [MV_I]
        CMPB    JR_KEY_UP
        BNE     mv_move_down
        CMPA    8
        BCS     mv_move_done
        SUBA    8
        RTS
mv_move_down:
        CMPB    JR_KEY_DOWN
        BNE     mv_move_side
        CMPA    56
        BCC     mv_move_done
        ADDA    8
        RTS
mv_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     mv_move_right
        TSTA
        BEQ     mv_move_stay
        LDAA    [MV_I]
        DECA
        RTS
mv_move_right:
        CMPA    7
        BCC     mv_move_stay
        LDAA    [MV_I]
        INCA
        RTS
mv_move_stay:
        LDAA    [MV_I]
mv_move_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = cell, B = the cell it slides from -> A = x, B = y half-way between them
; (the board starts at column 1).
mv_between:
        STAB    [MV_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [MV_T]
        STAB    [MV_I]
        LDAA    [MV_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [MV_T]
        INCA
        ADDB    [MV_I]
        ADDB    3
        RTS

game_draw:
        LDAA    0x20
        LDAB    MV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mv_hud
        JSR     jr_gfx_lines
        CLR     [MV_DI]
mv_draw_cell:
        LDAA    [MV_DI]
        LDX     MV_B
        JSR     jr_add_x_a
        LDAA    [X]
        ASLA
        LDX     mv_looks
        JSR     jr_add_x_a
        LDAB    [X + 1]
        LDAA    [X]
        STAA    [MV_DCODE]
        LDAA    [MV_DI]
        CMPA    [RANK_RUNE_A]
        BNE     mv_draw_rune_b
        LDAA    [RANK_RUNES]
        ANDA    1
        BNE     mv_draw_put
        BRA     mv_draw_rune
mv_draw_rune_b:
        CMPA    [RANK_RUNE_B]
        BNE     mv_draw_put
        LDAA    [RANK_RUNES]
        ANDA    2
        BNE     mv_draw_put
mv_draw_rune:
        LDAA    MV_TILE_RUNE
        STAA    [MV_DCODE]
        LDAB    MV_ATTR_RUNE
mv_draw_put:
        STAB    [JR_RT_COLOR]
        LDAA    [MV_DI]
        TAB
        JSR     mv_between
        JSR     jr_gfx_at
        LDAA    [MV_DCODE]
        JSR     jr_gfx_tile
        INC     [MV_DI]
        LDAA    [MV_DI]
        CMPA    64
        BNE     mv_draw_cell
        ; the boxes (one slides after the keeper while pulled)
        CLR     [MV_DI]
mv_draw_box:
        LDAA    [MV_DI]
        JSR     mv_cell
        TST     [X + 64]
        BEQ     mv_draw_box_next
        LDAB    MV_ATTR_BOX
        LDAA    [X]
        CMPA    3
        BNE     mv_draw_box_colour
        LDAB    MV_ATTR_BOX_IN
mv_draw_box_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [MV_DI]
        TAB
        TST     [MV_PULLING]
        BEQ     mv_draw_box_at
        CMPA    [MV_ORIGIN]
        BNE     mv_draw_box_at
        LDAB    [MV_BLOCK]
mv_draw_box_at:
        JSR     mv_between
        JSR     jr_gfx_at
        LDAA    MV_TILE_BOX
        JSR     jr_gfx_tile
mv_draw_box_next:
        INC     [MV_DI]
        LDAA    [MV_DI]
        CMPA    64
        BNE     mv_draw_box
        LDAA    MV_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [MV_POS]
        LDAB    [MV_ORIGIN]
        JSR     mv_between
        JSR     jr_gfx_at
        LDAA    [MV_FACING]
        DECA
        ASLA
        ASLA
        ADDA    MV_TILE_HERO
        JSR     jr_gfx_tile
        ; the panel: pulls, facing letter and the rune
        LDAA    MV_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [MV_PULLS]
        JSR     jr_rank_dec3
        LDAA    MV_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    10
        JSR     jr_gfx_at
        LDX     mv_facing_letters - 1
        LDAA    [MV_FACING]
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_putc
        LDAA    MV_ATTR_RUNE
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    13
        JSR     jr_gfx_at
        LDAA    MV_TILE_RUNE
        JSR     jr_gfx_tile
        JMP     jr_rank_hud

game_draw_title:
        LDX     mv_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    MV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mv_title_tiles
        STX     [JR_RT_TABLE]
mv_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     mv_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [MV_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [MV_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     mv_title_tile
mv_title_text:
        LDX     mv_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    MV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mv_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0x66, 8, 0
game_title_text:
        .db     "MAGNET VAULT", 0
mv_opposite:
        .db     2, 1, 4, 3
mv_facing_letters:
        .db     "NSWE"
; by cell kind 0-3: code, attribute
mv_looks:
        .db     MV_TILE_FLOOR, MV_ATTR_FLOOR, MV_TILE_WALL, MV_ATTR_WALL
        .db     MV_TILE_FLOOR, MV_ATTR_FLOOR, MV_TILE_SOCKET, MV_ATTR_SOCKET

; x, attribute, code, y
mv_title_tiles:
        .db     8, MV_ATTR_WALL, MV_TILE_WALL, 3
        .db     10, MV_ATTR_HERO, MV_TILE_HERO + 12, 3
        .db     12, MV_ATTR_BOX, MV_TILE_BOX, 3
        .db     14, MV_ATTR_FLOOR, MV_TILE_FLOOR, 3
        .db     16, MV_ATTR_SOCKET, MV_TILE_SOCKET, 3
        .db     18, MV_ATTR_BOX_IN, MV_TILE_BOX, 3
        .db     20, MV_ATTR_RUNE, MV_TILE_RUNE, 3
        .db     0xff

mv_hud:
        .db     1, 0, MV_ATTR_TITLE
        .dw     game_title_text
        .db     20, 3, MV_ATTR_LABEL
        .dw     mv_txt_magnet
        .db     20, 4, MV_ATTR_LABEL
        .dw     mv_txt_pulls
        .db     20, 9, MV_ATTR_LABEL
        .dw     mv_txt_facing
        .db     20, 16, MV_ATTR_DIM
        .dw     mv_txt_runes
        .db     0xff
mv_title_lines:
        .db     10, 8, MV_ATTR_TITLE
        .dw     game_title_text
        .db     3, 10, MV_ATTR_LABEL
        .dw     mv_txt_tagline
        .db     4, 15, MV_ATTR_TEXT
        .dw     mv_txt_start
        .db     4, 17, MV_ATTR_DIM
        .dw     mv_txt_credit
        .db     0xff
mv_help_lines:
        .db     10, 1, MV_ATTR_TITLE
        .dw     game_title_text
        .db     1, 3, MV_ATTR_TEXT
        .dw     mv_help_1
        .db     1, 5, MV_ATTR_TEXT
        .dw     mv_help_2
        .db     1, 7, MV_ATTR_TEXT
        .dw     mv_help_3
        .db     1, 9, MV_ATTR_TEXT
        .dw     mv_help_4
        .db     1, 11, MV_ATTR_TEXT
        .dw     mv_help_5
        .db     1, 13, MV_ATTR_TEXT
        .dw     mv_help_6
        .db     1, 15, MV_ATTR_TEXT
        .dw     mv_help_7
        .db     1, 17, MV_ATTR_TEXT
        .dw     mv_help_8
        .db     1, 19, MV_ATTR_TEXT
        .dw     mv_help_9
        .db     1, 21, MV_ATTR_LABEL
        .dw     mv_help_back
        .db     0xff

mv_txt_magnet:
        .db     "MAGNET", 0
mv_txt_pulls:
        .db     "PULLS", 0
mv_txt_facing:
        .db     "FACING", 0
mv_txt_runes:
        .db     "RUNES", 0
mv_txt_tagline:
        .db     "PULL THE BOXES INTO PLACE", 0
mv_txt_start:
        .db     "RETURN : PLAY THE STAGE", 0
mv_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
mv_help_1:
        .db     "WASD : WALK AND FACE", 0
mv_help_2:
        .db     "RETURN : PULL THE FRONT BOX", 0
mv_help_3:
        .db     "FILL BOTH DIAMOND SOCKETS.", 0
mv_help_4:
        .db     "WALK OVER OPTIONAL RUNES.", 0
mv_help_5:
        .db     "PAR OR LESS = TWO STARS.", 0
mv_help_6:
        .db     "PLUS BOTH RUNES = THREE STARS.", 0
mv_help_7:
        .db     "OVER PAR = CLEAR / ONE STAR.", 0
mv_help_8:
        .db     "SPACE RETRY / F STAGE SELECT", 0
mv_help_9:
        .db     "X : PASSWORD (TITLE / MAP)", 0
mv_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     mv_sfx_slide, mv_sfx_crystal, mv_jingle_win, mv_jingle_lose
mv_sfx_slide:
        .db     60, 1, 0, 0
mv_sfx_crystal:
        .db     40, 3, 32, 3, 27, 6, 0, 0

; Title: a clanking machine-room tune in G minor, eighth note = 8 frames, looping.
mv_title_song:
        .db     1
        .dw     mv_title_melody, mv_title_harmony, mv_title_bass
mv_title_melody:
        .db     AU_G4, 8, AU_G4, 8, AU_AS4, 8, AU_D5, 8, AU_C5, 16, AU_A4, 16
        .db     AU_AS4, 8, AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_DS5, 16, AU_D5, 16
        .db     AU_G5, 8, AU_F5, 8, AU_DS5, 8, AU_D5, 8, AU_C5, 16, AU_A4, 16
        .db     AU_AS4, 8, AU_A4, 8, AU_FS4, 8, AU_A4, 8, AU_G4, 32, 0, 0
mv_title_harmony:
        .db     AU_D4, 32, AU_DS4, 32, AU_F4, 32, AU_G4, 32
        .db     AU_DS4, 32, AU_DS4, 32, AU_D4, 32, AU_D4, 32, 0, 0
mv_title_bass:
        .db     AU_G2, 8, AU_G2, 8, AU_D3, 8, AU_G2, 8, AU_F2, 16, AU_F2, 16
        .db     AU_DS2, 8, AU_DS2, 8, AU_AS2, 8, AU_DS2, 8, AU_F2, 16, AU_AS2, 16
        .db     AU_C3, 8, AU_C3, 8, AU_G2, 8, AU_C3, 8, AU_F2, 16, AU_F2, 16
        .db     AU_D3, 8, AU_D3, 8, AU_D2, 8, AU_D3, 8, AU_G2, 32, 0, 0

; Vault sealed: G major arpeggio over the tonic (54 frames).
mv_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     mv_win_melody, mv_win_harmony, mv_win_bass
mv_win_melody:
        .db     AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_G6, 30, 0, 0
mv_win_harmony:
        .db     AU_D5, 8, AU_G5, 8, AU_B5, 8, AU_D6, 30, 0, 0
mv_win_bass:
        .db     AU_G3, 24, AU_G2, 30, 0, 0
mv_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     mv_lose_melody, mv_lose_harmony, mv_lose_bass
mv_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
mv_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
mv_lose_bass:
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

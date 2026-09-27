; SPDX-License-Identifier: MIT
; STONE BALANCE for JR-200: a port of jr100dev games/stone_balance/rules.py 2.0.0.
; Heaps, the take-one-to-three rule, the rival's table search and the switch
; to "last stone loses" from stage 6 follow the upstream source; display,
; colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "STONE-BALANCE"
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
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
SB_B:               .equ    GAME_STATE          ; b[3]
SB_PILE:            .equ    GAME_STATE + 3
SB_TAKE:            .equ    GAME_STATE + 4
SB_TURN:            .equ    GAME_STATE + 5
SB_EPILE:           .equ    GAME_STATE + 6
SB_ETAKE:           .equ    GAME_STATE + 7
SB_MISERE:          .equ    GAME_STATE + 8
; Effect and rule work bytes.
SB_EFFECT:          .equ    GAME_STATE + 16
SB_EX:              .equ    GAME_STATE + 17
SB_EY:              .equ    GAME_STATE + 18
SB_FRAME:           .equ    GAME_STATE + 19
SB_FX:              .equ    GAME_STATE + 20
SB_FY:              .equ    GAME_STATE + 21
SB_IA:              .equ    GAME_STATE + 22
SB_RPILE:           .equ    GAME_STATE + 23
SB_RCOUNT:          .equ    GAME_STATE + 24
SB_N:               .equ    GAME_STATE + 25
SB_I:               .equ    GAME_STATE + 26
SB_J:               .equ    GAME_STATE + 27
SB_FOUND:           .equ    GAME_STATE + 28
SB_VALUE:           .equ    GAME_STATE + 29
; Drawing work bytes.
SB_DI:              .equ    GAME_STATE + 48
SB_DJ:              .equ    GAME_STATE + 49
SB_DY:              .equ    GAME_STATE + 50

SB_TILE_STONE:      .equ    0x80
SB_TILE_SHELF:      .equ    0x84
SB_ATTR_STONE:      .equ    0x47        ; white stone
SB_ATTR_MARK:       .equ    0x46        ; yellow: the stones you will take
SB_ATTR_MINE:       .equ    0x46        ; your stone in flight
SB_ATTR_RIVAL:      .equ    0x42        ; the rival's stone in flight
SB_ATTR_SHELF:      .equ    0x41
SB_ATTR_SHELF_ON:   .equ    0x46
SB_ATTR_WINS:       .equ    0x04
SB_ATTR_LOSES:      .equ    0x02
SB_ATTR_TEXT:       .equ    0x07
SB_ATTR_LABEL:      .equ    0x04
SB_ATTR_TITLE:      .equ    0x06
SB_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     sb_patterns
        LDAA    SB_TILE_STONE
        LDAB    8
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        CMPA    5
        BCS     sb_init_heaps
        LDAB    1
        STAB    [SB_MISERE]
sb_init_heaps:
        LDAB    3
        JSR     jr_mul8
        LDX     sb_heaps
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SB_B]
        LDAA    [X + 1]
        STAA    [SB_B + 1]
        LDAA    [X + 2]
        STAA    [SB_B + 2]
        LDAA    1
        STAA    [SB_TAKE]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_UP
        BNE     sb_act_down
        LDAA    [SB_PILE]
        ADDA    2
        BRA     sb_act_pile
sb_act_down:
        CMPA    JR_KEY_DOWN
        BNE     sb_act_more
        LDAA    [SB_PILE]
        INCA
sb_act_pile:
        CMPA    3
        BCS     sb_act_pile_store
        SUBA    3
sb_act_pile_store:
        STAA    [SB_PILE]
        RTS
sb_act_more:
        CMPA    JR_KEY_LEFT
        BNE     sb_act_less
        LDAA    [SB_TAKE]
        INCA
        CMPA    4
        BNE     sb_act_take
        LDAA    1
        BRA     sb_act_take
sb_act_less:
        CMPA    JR_KEY_RIGHT
        BNE     sb_act_confirm
        LDAA    [SB_TAKE]
        DECA
        BNE     sb_act_take
        LDAA    3
sb_act_take:
        STAA    [SB_TAKE]
        RTS
sb_act_confirm:
        CMPA    JR_KEY_CONFIRM
        BNE     sb_act_done
        JSR     sb_pile_x
        LDAA    [X]
        CMPA    [SB_TAKE]
        BCS     sb_act_done
        LDAA    1
        STAA    [SB_TURN]
        LDAA    [SB_PILE]
        LDAB    [SB_TAKE]
        JSR     sb_remove
        JSR     sb_total
        BNE     sb_rival
        TST     [SB_MISERE]
        BEQ     sb_win
        LDX     sb_txt_lose_self
        JMP     jr_port_lose
sb_win:
        JMP     jr_port_win
sb_act_done:
        RTS

; The rival takes the first (pile, 1-3) that leaves no winning reply.
sb_rival:
        CLR     [SB_FOUND]
        CLR     [SB_I]
sb_rival_pile:
        CLR     [SB_J]
sb_rival_take:
        TST     [SB_FOUND]
        BNE     sb_rival_next
        LDAA    [SB_I]
        LDX     SB_B
        JSR     jr_add_x_a
        LDAA    [SB_J]
        INCA
        CMPA    [X]
        BHI     sb_rival_next
        LDAB    [X]
        STAB    [SB_VALUE]
        NEGA
        ADDA    [X]
        STAA    [X]
        JSR     sb_has_win
        PSHA
        LDAA    [SB_I]
        LDX     SB_B
        JSR     jr_add_x_a
        LDAA    [SB_VALUE]
        STAA    [X]
        PULA
        TSTA
        BNE     sb_rival_next
        LDAA    [SB_I]
        STAA    [SB_EPILE]
        LDAA    [SB_J]
        INCA
        STAA    [SB_ETAKE]
        LDAA    1
        STAA    [SB_FOUND]
sb_rival_next:
        INC     [SB_J]
        LDAA    [SB_J]
        CMPA    3
        BNE     sb_rival_take
        INC     [SB_I]
        LDAA    [SB_I]
        CMPA    3
        BNE     sb_rival_pile
        TST     [SB_FOUND]
        BNE     sb_rival_move
        ; no winning move: one stone from the last non-empty pile
        CLR     [SB_I]
sb_rival_any:
        LDAA    [SB_I]
        LDX     SB_B
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sb_rival_any_next
        LDAA    [SB_I]
        STAA    [SB_EPILE]
sb_rival_any_next:
        INC     [SB_I]
        LDAA    [SB_I]
        CMPA    3
        BNE     sb_rival_any
        LDAA    1
        STAA    [SB_ETAKE]
sb_rival_move:
        LDAA    2
        STAA    [SB_TURN]
        LDAA    [SB_EPILE]
        LDAB    [SB_ETAKE]
        JSR     sb_remove
        LDAA    1
        JSR     jr_port_sound
        JSR     sb_total
        BNE     sb_rival_done
        TST     [SB_MISERE]
        BEQ     sb_rival_lost
        JMP     jr_port_win
sb_rival_lost:
        LDX     sb_txt_lose_rival
        JMP     jr_port_lose
sb_rival_done:
        RTS

; A = has_win(): (table[b0 * 8 + b1] >> b2) & 1, non-zero when winning.
sb_has_win:
        LDX     sb_normal
        TST     [SB_MISERE]
        BEQ     sb_has_win_table
        LDX     sb_reverse
sb_has_win_table:
        LDAA    [SB_B]
        ASLA
        ASLA
        ASLA
        ADDA    [SB_B + 1]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [SB_B + 2]
        BEQ     sb_has_win_bit
sb_has_win_shift:
        LSRA
        DECB
        BNE     sb_has_win_shift
sb_has_win_bit:
        ANDA    1
        RTS

; A = pile, B = count: stones fly off one by one, then a pause of 12.
sb_remove:
        STAA    [SB_RPILE]
        STAB    [SB_RCOUNT]
sb_remove_stone:
        JSR     sb_pile_x_of
        DEC     [X]
        CLRA
        JSR     jr_port_sound
        ; flight(2 + b[pile] * 3, 4 + pile * 5, 27, 18)
        JSR     sb_pile_x_of
        LDAA    [X]
        LDAB    3
        JSR     jr_mul8
        ADDA    2
        STAA    [SB_FX]
        LDAA    [SB_RPILE]
        LDAB    5
        JSR     jr_mul8
        ADDA    4
        STAA    [SB_FY]
        LDAA    1
        STAA    [SB_EFFECT]
        CLR     [SB_FRAME]
sb_flight_frame:
        LDAA    [SB_FX]
        LDAB    27
        JSR     sb_interp
        STAA    [SB_EX]
        LDAA    [SB_FY]
        LDAB    18
        JSR     sb_interp
        STAA    [SB_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [SB_FRAME]
        LDAA    [SB_FRAME]
        CMPA    5
        BNE     sb_flight_frame
        CLR     [SB_EFFECT]
        DEC     [SB_RCOUNT]
        BNE     sb_remove_stone
        LDAA    12
        JMP     jr_port_animate

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
sb_interp:
        STAA    [SB_IA]
        CBA
        BHI     sb_interp_back
        SUBB    [SB_IA]
        TBA
        LDAB    [SB_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [SB_IA]
        RTS
sb_interp_back:
        SBA
        LDAB    [SB_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [SB_IA]
        RTS

; X = &b[pile] for SB_PILE / SB_RPILE. Clobbers A.
sb_pile_x:
        LDAA    [SB_PILE]
        BRA     sb_pile_x_a
sb_pile_x_of:
        LDAA    [SB_RPILE]
sb_pile_x_a:
        LDX     SB_B
        JMP     jr_add_x_a

; Z set when every pile is empty.
sb_total:
        LDAA    [SB_B]
        ADDA    [SB_B + 1]
        ADDA    [SB_B + 2]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    SB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sb_hud
        JSR     jr_gfx_lines
        LDAA    SB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the rule of this stage
        LDAA    8
        LDAB    2
        JSR     jr_gfx_at
        LDAA    SB_ATTR_WINS
        LDX     sb_txt_wins
        TST     [SB_MISERE]
        BEQ     sb_draw_rule
        LDAA    SB_ATTR_LOSES
        LDX     sb_txt_loses
sb_draw_rule:
        STAA    [JR_RT_COLOR]
        JSR     jr_gfx_text
        CLR     [SB_DI]
sb_draw_pile:
        LDAA    [SB_DI]
        LDAB    5
        JSR     jr_mul8
        ADDA    4
        STAA    [SB_DY]
        ; the shelf under the pile, yellow for the selected pile
        LDAA    SB_ATTR_SHELF
        LDAB    [SB_DI]
        CMPB    [SB_PILE]
        BNE     sb_draw_shelf
        LDAA    SB_ATTR_SHELF_ON
sb_draw_shelf:
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    [SB_DY]
        ADDB    3
        JSR     jr_gfx_at
        LDAB    11
sb_draw_shelf_tile:
        LDAA    SB_TILE_SHELF
        JSR     jr_gfx_tile
        DECB
        BNE     sb_draw_shelf_tile
        ; stones at (2 + j * 3, 4 + i * 5)
        CLR     [SB_DJ]
sb_draw_stone:
        LDAA    [SB_DI]
        LDX     SB_B
        JSR     jr_add_x_a
        LDAA    [SB_DJ]
        CMPA    [X]
        BCC     sb_draw_cursor
        ; marked when this is the selected pile and j + take >= b[i]
        LDAB    SB_ATTR_STONE
        LDAA    [SB_DI]
        CMPA    [SB_PILE]
        BNE     sb_draw_stone_tile
        LDAA    [SB_DJ]
        ADDA    [SB_TAKE]
        CMPA    [X]
        BCS     sb_draw_stone_tile
        LDAB    SB_ATTR_MARK
        STAB    [JR_RT_COLOR]
        LDAA    [SB_DJ]
        LDAB    3
        JSR     jr_mul8
        ADDA    2
        LDAB    [SB_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    0x5e
        JSR     jr_gfx_putc
        LDAB    SB_ATTR_MARK
sb_draw_stone_tile:
        STAB    [JR_RT_COLOR]
        LDAA    [SB_DJ]
        LDAB    3
        JSR     jr_mul8
        ADDA    2
        LDAB    [SB_DY]
        JSR     jr_gfx_at
        LDAA    SB_TILE_STONE
        JSR     jr_gfx_tile
        INC     [SB_DJ]
        BRA     sb_draw_stone
sb_draw_cursor:
        LDAA    [SB_DI]
        CMPA    [SB_PILE]
        BNE     sb_draw_next
        LDAA    SB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    [SB_DY]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
sb_draw_next:
        INC     [SB_DI]
        LDAA    [SB_DI]
        CMPA    3
        BEQ     sb_draw_counts
        JMP     sb_draw_pile
sb_draw_counts:
        LDAA    SB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [SB_TAKE]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [SB_ETAKE]
        JSR     jr_gfx_dec2
        LDAA    2
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [SB_TURN]
        BEQ     sb_draw_effect
        LDX     sb_txt_you_take
        CMPA    1
        BEQ     sb_draw_turn
        LDX     sb_txt_rival_took
sb_draw_turn:
        JSR     jr_gfx_text
sb_draw_effect:
        TST     [SB_EFFECT]
        BEQ     sb_draw_done
        LDAA    SB_ATTR_MINE
        LDAB    [SB_TURN]
        CMPB    1
        BEQ     sb_draw_flight
        LDAA    SB_ATTR_RIVAL
sb_draw_flight:
        STAA    [JR_RT_COLOR]
        LDAA    [SB_EX]
        LDAB    [SB_EY]
        JSR     jr_gfx_at
        LDAA    SB_TILE_STONE
        JMP     jr_gfx_tile
sb_draw_done:
        RTS

game_draw_title:
        LDX     sb_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    SB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sb_title_stones
        STX     [JR_RT_TABLE]
sb_title_stone:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     sb_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        JSR     jr_gfx_at
        LDAA    SB_TILE_STONE
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     sb_title_stone
sb_title_text:
        LDX     sb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

sb_heaps:
        .db     2, 3, 7, 3, 3, 7, 4, 3, 6, 5, 3, 7, 6, 3, 7
        .db     2, 5, 6, 3, 5, 7, 4, 5, 7, 5, 5, 7, 6, 5, 6
; Upstream win tables: bit b[2] of table[b[0] * 8 + b[1]].
sb_normal:
        .db     238, 221, 187, 119, 238, 221, 187, 119, 221, 238, 119, 187, 221, 238, 119, 187
        .db     187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238
        .db     238, 221, 187, 119, 238, 221, 187, 119, 221, 238, 119, 187, 221, 238, 119, 187
        .db     187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238
sb_reverse:
        .db     221, 238, 187, 119, 221, 238, 187, 119, 238, 221, 119, 187, 238, 221, 119, 187
        .db     187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238
        .db     221, 238, 187, 119, 221, 238, 187, 119, 238, 221, 119, 187, 238, 221, 119, 187
        .db     187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238

sb_hud:
        .db     1, 0, SB_ATTR_TITLE
        .dw     sb_txt_name
        .db     23, 0, SB_ATTR_LABEL
        .dw     sb_txt_stage
        .db     2, 19, SB_ATTR_LABEL
        .dw     sb_txt_take
        .db     15, 19, SB_ATTR_LABEL
        .dw     sb_txt_rival
        .db     0xff

; x, attribute, y: three piles of stones on the title.
sb_title_stones:
        .db     6, SB_ATTR_STONE, 3
        .db     9, SB_ATTR_STONE, 3
        .db     13, SB_ATTR_MARK, 3
        .db     16, SB_ATTR_MARK, 3
        .db     20, SB_ATTR_RIVAL, 3
        .db     23, SB_ATTR_STONE, 3
        .db     0xff
sb_title_lines:
        .db     9, 8, SB_ATTR_TITLE
        .dw     sb_txt_name
        .db     4, 10, SB_ATTR_LABEL
        .dw     sb_txt_tagline
        .db     8, 15, SB_ATTR_TEXT
        .dw     sb_txt_start
        .db     5, 17, SB_ATTR_TEXT
        .dw     sb_txt_howto
        .db     4, 22, SB_ATTR_DIM
        .dw     sb_txt_credit
        .db     0xff
sb_help_lines:
        .db     9, 2, SB_ATTR_TITLE
        .dw     sb_txt_name
        .db     1, 5, SB_ATTR_TEXT
        .dw     sb_help_1
        .db     1, 7, SB_ATTR_TEXT
        .dw     sb_help_2
        .db     1, 9, SB_ATTR_TEXT
        .dw     sb_help_3
        .db     1, 11, SB_ATTR_TEXT
        .dw     sb_help_4
        .db     1, 13, SB_ATTR_TEXT
        .dw     sb_help_5
        .db     1, 15, SB_ATTR_TEXT
        .dw     sb_help_6
        .db     1, 17, SB_ATTR_TEXT
        .dw     sb_help_7
        .db     1, 20, SB_ATTR_LABEL
        .dw     sb_help_back
        .db     0xff

sb_txt_name:
        .db     "STONE BALANCE", 0
sb_txt_stage:
        .db     "STAGE", 0
sb_txt_take:
        .db     "TAKE", 0
sb_txt_rival:
        .db     "RIVAL TOOK", 0
sb_txt_wins:
        .db     "LAST STONE WINS", 0
sb_txt_loses:
        .db     "LAST STONE LOSES", 0
sb_txt_you_take:
        .db     "YOU TAKE", 0
sb_txt_rival_took:
        .db     "RIVAL TOOK - YOUR TURN", 0
sb_txt_lose_self:
        .db     "YOU TOOK THE LAST STONE", 0
sb_txt_lose_rival:
        .db     "THE RIVAL TOOK THE LAST STONE", 0
sb_txt_tagline:
        .db     "TAKE ONE TO THREE STONES", 0
sb_txt_start:
        .db     "RETURN : START", 0
sb_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
sb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sb_help_1:
        .db     "W/S : PILE   A/D : TAKE 1-3", 0
sb_help_2:
        .db     "RETURN : REMOVE YELLOW STONES", 0
sb_help_3:
        .db     "THE RIVAL LOOKS FOR A WIN.", 0
sb_help_4:
        .db     "STAGES 1-5: LAST STONE WINS.", 0
sb_help_5:
        .db     "STAGES 6-10: IT LOSES.", 0
sb_help_6:
        .db     "READ THE RULE ABOVE THE PILES.", 0
sb_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
sb_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     sb_sfx_stone, sb_sfx_rival, sb_jingle_win, sb_jingle_lose
sb_sfx_stone:
        .db     110, 2, 0, 0
sb_sfx_rival:
        .db     180, 4, 0, 2, 150, 4, 0, 0

; Title: four bars in F major, quarter note = 24 frames, looping.
sb_title_song:
        .db     1
        .dw     sb_title_melody, sb_title_harmony, sb_title_bass
sb_title_melody:
        .db     AU_C6, 24, AU_A5, 24, AU_F5, 24, AU_A5, 24
        .db     AU_AS5, 36, AU_A5, 12, AU_G5, 48
        .db     AU_A5, 24, AU_C6, 24, AU_F6, 24, AU_E6, 24
        .db     AU_F6, 72, 0, 24, 0, 0
sb_title_harmony:
        .db     AU_F5, 48, AU_C5, 48, AU_D5, 48, AU_E5, 48
        .db     AU_F5, 48, AU_A5, 48, AU_A5, 72, 0, 24, 0, 0
sb_title_bass:
        .db     AU_F3, 48, AU_A3, 48, AU_AS2, 48, AU_C3, 48
        .db     AU_F3, 48, AU_C3, 48, AU_F2, 72, 0, 24, 0, 0

; Clear: rising F major arpeggio over a held tonic (54 frames).
sb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     sb_win_melody, sb_win_harmony, sb_win_bass
sb_win_melody:
        .db     AU_F5, 8, AU_A5, 8, AU_C6, 8, AU_F6, 30, 0, 0
sb_win_harmony:
        .db     AU_C5, 8, AU_F5, 8, AU_A5, 8, AU_C6, 30, 0, 0
sb_win_bass:
        .db     AU_F3, 24, AU_F2, 30, 0, 0
; Lost: a falling F minor line (66 frames).
sb_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     sb_lose_melody, sb_lose_harmony, sb_lose_bass
sb_lose_melody:
        .db     AU_C5, 12, AU_AS4, 12, AU_GS4, 12, AU_G4, 30, 0, 0
sb_lose_harmony:
        .db     AU_GS4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
sb_lose_bass:
        .db     AU_F3, 36, AU_C3, 30, 0, 0

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

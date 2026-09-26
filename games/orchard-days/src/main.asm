; SPDX-License-Identifier: MIT
; ORCHARD DAYS for JR-200: a port of jr100dev games/orchard_days/rules.py 2.0.0.
; Seeds, water, the well, rain periods, berry and apple growth, harvests and
; quotas follow the upstream source; display, colour and three-voice sound use
; the JR-200 port SDK.
        .filename.jr "ORCHARD-DAYS"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[16], c[16], d[16].
OD_SEEDS:           .equ    GAME_STATE
OD_WATER:           .equ    GAME_STATE + 1
OD_QUOTA:           .equ    GAME_STATE + 2
OD_PERIOD:          .equ    GAME_STATE + 3
OD_CURSOR:          .equ    GAME_STATE + 4
OD_CROP:            .equ    GAME_STATE + 5
OD_NOTICE:          .equ    GAME_STATE + 6
OD_GAIN:            .equ    GAME_STATE + 7
OD_FRUIT:           .equ    GAME_STATE + 8
OD_DAY:             .equ    GAME_STATE + 9
OD_RAIN:            .equ    GAME_STATE + 10
OD_GROWING:         .equ    GAME_STATE + 11
OD_B:               .equ    GAME_STATE + 12
OD_C:               .equ    GAME_STATE + 28
OD_D:               .equ    GAME_STATE + 44
; Flight effect and rule work bytes.
OD_EFFECT:          .equ    GAME_STATE + 64
OD_ECODE:           .equ    GAME_STATE + 65
OD_EATTR:           .equ    GAME_STATE + 66
OD_EX:              .equ    GAME_STATE + 67
OD_EY:              .equ    GAME_STATE + 68
OD_FX:              .equ    GAME_STATE + 69
OD_FY:              .equ    GAME_STATE + 70
OD_TX:              .equ    GAME_STATE + 71
OD_TY:              .equ    GAME_STATE + 72
OD_FRAME:           .equ    GAME_STATE + 73
OD_IA:              .equ    GAME_STATE + 74
OD_I:               .equ    GAME_STATE + 75
OD_NEED:            .equ    GAME_STATE + 76
OD_PX:              .equ    GAME_STATE + 77
OD_PY:              .equ    GAME_STATE + 78
; Drawing work bytes.
OD_DI:              .equ    GAME_STATE + 80
OD_DCODE:           .equ    GAME_STATE + 81
OD_DATTR:           .equ    GAME_STATE + 82
OD_DCROP:           .equ    GAME_STATE + 83
OD_DPX:             .equ    GAME_STATE + 84
OD_DPY:             .equ    GAME_STATE + 85

OD_TILE_SOIL:       .equ    0x80
OD_TILE_SPROUT:     .equ    0x84
OD_TILE_BERRY:      .equ    0x8c
OD_TILE_TREE:       .equ    0x90
OD_TILE_DROP:       .equ    0x94
OD_TILE_APPLE:      .equ    0x98
OD_ATTR_SOIL:       .equ    0x42        ; red furrows
OD_ATTR_GREEN:      .equ    0x44
OD_ATTR_BERRY:      .equ    0x63        ; magenta berries on green
OD_ATTR_APPLE:      .equ    0x62        ; red apples on green
OD_ATTR_DROP:       .equ    0x45
OD_ATTR_TEXT:       .equ    0x07
OD_ATTR_LABEL:      .equ    0x04
OD_ATTR_TITLE:      .equ    0x06
OD_ATTR_DIM:        .equ    0x05
OD_ATTR_PICK:       .equ    0x06
OD_ATTR_WATER:      .equ    0x05
OD_ATTR_GOOD:       .equ    0x04
OD_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     od_patterns
        LDAA    OD_TILE_SOIL
        LDAB    28
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    8
        STAA    [OD_SEEDS]
        LDAA    6
        STAA    [OD_WATER]
        LDAA    [JR_PORT_LEVEL]
        LDAB    6
        JSR     jr_mul8
        ADDA    18
        STAA    [OD_QUOTA]
        LDAA    [JR_PORT_LEVEL]
        ADDA    4
        STAA    [OD_PERIOD]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        TSTA
        BEQ     od_act_done
        CMPA    JR_KEY_CONFIRM
        BEQ     od_confirm
        BCC     od_act_done
        TAB
        LDAA    [OD_CURSOR]
        JSR     od_move
        STAA    [OD_CURSOR]
od_act_done:
        RTS

od_confirm:
        CLR     [OD_NOTICE]
        LDAA    [OD_CURSOR]
        CMPA    16
        BCS     od_plot
        CMPA    18
        BCC     od_tool
        ; BERRY / APPLE choose the crop without using a day
        SUBA    16
        STAA    [OD_CROP]
        CLRA
        JMP     jr_port_sound
od_tool:
        BNE     od_well
        LDAA    3
        STAA    [OD_NOTICE]
        JMP     od_pass_day
od_well:
        LDAA    [OD_WATER]
        CMPA    9
        BCC     od_act_done
        ADDA    3
        CMPA    9
        BLS     od_well_fill
        LDAA    9
od_well_fill:
        STAA    [OD_WATER]
        LDAA    4
        STAA    [OD_NOTICE]
        CLRA
        JSR     jr_port_sound
        JMP     od_pass_day

od_plot:
        JSR     od_plot_xy
        STAA    [OD_PX]
        STAB    [OD_PY]
        LDAA    [OD_CURSOR]
        JSR     od_need_of
        LDAA    [OD_CURSOR]
        LDX     OD_B
        JSR     jr_add_x_a
        LDAA    [X]
        BNE     od_plot_grow
        ; plant: a seed flies from the seed box
        TST     [OD_SEEDS]
        BNE     od_plant
        LDAA    5
        STAA    [OD_NOTICE]
        JMP     od_buzz
od_plant:
        CLRA
        JSR     jr_port_sound
        LDAA    24
        STAA    [OD_FX]
        LDAA    5
        STAA    [OD_FY]
        LDAA    [OD_PX]
        STAA    [OD_TX]
        LDAA    [OD_PY]
        STAA    [OD_TY]
        LDAA    OD_TILE_SPROUT
        LDAB    OD_ATTR_GREEN
        JSR     od_flight
        DEC     [OD_SEEDS]
        LDAA    [OD_CURSOR]
        LDX     OD_B
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        LDAA    [OD_CROP]
        STAA    [X + 16]
        JMP     od_pass_day
od_plot_grow:
        CMPA    [OD_NEED]
        BCC     od_harvest
        ; water: a drop falls from the top of the field
        TST     [OD_WATER]
        BNE     od_pour
        LDAA    6
        STAA    [OD_NOTICE]
        JMP     od_buzz
od_pour:
        DEC     [OD_WATER]
        LDAA    1
        STAA    [OD_NOTICE]
        CLRA
        JSR     jr_port_sound
        LDAA    [OD_PX]
        STAA    [OD_FX]
        STAA    [OD_TX]
        LDAA    2
        STAA    [OD_FY]
        LDAA    [OD_PY]
        STAA    [OD_TY]
        LDAA    OD_TILE_DROP
        LDAB    OD_ATTR_DROP
        JSR     od_flight
        LDAA    [OD_CURSOR]
        LDX     OD_D
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        JMP     od_pass_day
od_harvest:
        CLR     [X]
        LDAA    2
        STAA    [OD_NOTICE]
        LDAA    3
        TST     [X + 16]
        BEQ     od_harvest_gain
        LDAA    7
od_harvest_gain:
        STAA    [OD_GAIN]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [OD_PX]
        STAA    [OD_FX]
        LDAA    [OD_PY]
        STAA    [OD_FY]
        LDAA    24
        STAA    [OD_TX]
        LDAA    10
        STAA    [OD_TY]
        LDAA    [OD_CURSOR]
        LDX     OD_C
        JSR     jr_add_x_a
        LDAA    OD_TILE_BERRY
        LDAB    OD_ATTR_BERRY
        TST     [X]
        BEQ     od_harvest_fly
        LDAA    OD_TILE_APPLE
        LDAB    OD_ATTR_APPLE
od_harvest_fly:
        JSR     od_flight
        LDAA    [OD_FRUIT]
        ADDA    [OD_GAIN]
        STAA    [OD_FRUIT]
        INC     [OD_SEEDS]

; A day passes: rain on every period-th day, then watered plants grow.
od_pass_day:
        INC     [OD_DAY]
        LDAA    [OD_DAY]
        LDAB    [OD_PERIOD]
        JSR     jr_divmod8
        TSTB
        BNE     od_day_grow
        LDAA    1
        STAA    [OD_RAIN]
        LDAA    [OD_WATER]
        ADDA    4
        CMPA    9
        BLS     od_day_rain
        LDAA    9
od_day_rain:
        STAA    [OD_WATER]
        LDX     od_sfx_rain
        JSR     jr_sfx_play
        LDAA    12
        JSR     jr_port_animate
od_day_grow:
        CLR     [OD_I]
od_grow_plot:
        LDAA    [OD_I]
        JSR     od_need_of
        LDAA    [OD_I]
        LDX     OD_B
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     od_grow_next
        CMPA    [OD_NEED]
        BCC     od_grow_next
        TST     [X + 32]
        BNE     od_grow_up
        TST     [OD_RAIN]
        BEQ     od_grow_next
od_grow_up:
        INC     [X]
        LDAA    [OD_I]
        INCA
        STAA    [OD_GROWING]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
od_grow_next:
        LDAA    [OD_I]
        LDX     OD_D
        JSR     jr_add_x_a
        CLR     [X]
        INC     [OD_I]
        LDAA    [OD_I]
        CMPA    16
        BNE     od_grow_plot
        CLR     [OD_GROWING]
        CLR     [OD_RAIN]
        LDAA    [OD_FRUIT]
        CMPA    [OD_QUOTA]
        BCS     od_day_end
        JMP     jr_port_win
od_day_end:
        LDAA    [OD_DAY]
        CMPA    28
        BCS     od_day_done
        LDX     od_txt_lose
        JMP     jr_port_lose
od_day_done:
        RTS

od_buzz:
        LDX     od_sfx_buzz
        JMP     jr_sfx_play

; A = plot -> OD_NEED = 5 for an apple, 3 for a berry.
od_need_of:
        LDX     OD_C
        JSR     jr_add_x_a
        LDAA    3
        TST     [X]
        BEQ     od_need_set
        LDAA    5
od_need_set:
        STAA    [OD_NEED]
        RTS

; A = plot -> A = 2 + plot % 4 * 3, B = 4 + plot // 4 * 3.
od_plot_xy:
        TAB
        LSRB
        LSRB
        STAB    [OD_IA]
        ASLB
        ADDB    [OD_IA]
        ADDB    4
        ANDA    3
        STAA    [OD_IA]
        ASLA
        ADDA    [OD_IA]
        ADDA    2
        RTS

; A = position, B = action 1-4 -> A = moved position (4 wide, 5 tall).
od_move:
        CMPB    JR_KEY_UP
        BNE     od_move_down
        CMPA    4
        BCS     od_move_done
        SUBA    4
        RTS
od_move_down:
        CMPB    JR_KEY_DOWN
        BNE     od_move_left
        CMPA    16
        BCC     od_move_done
        ADDA    4
        RTS
od_move_left:
        STAA    [OD_IA]
        ANDA    3
        CMPB    JR_KEY_LEFT
        BNE     od_move_right
        TSTA
        BEQ     od_move_stay
        LDAA    [OD_IA]
        DECA
        RTS
od_move_right:
        CMPA    3
        BCC     od_move_stay
        LDAA    [OD_IA]
        INCA
        RTS
od_move_stay:
        LDAA    [OD_IA]
od_move_done:
        RTS

; A = code, B = attribute: five frames of animate(3) from (FX, FY) to (TX, TY).
od_flight:
        STAA    [OD_ECODE]
        STAB    [OD_EATTR]
        LDAA    1
        STAA    [OD_EFFECT]
        CLR     [OD_FRAME]
od_flight_frame:
        LDAA    [OD_FX]
        LDAB    [OD_TX]
        JSR     od_interp
        STAA    [OD_EX]
        LDAA    [OD_FY]
        LDAB    [OD_TY]
        JSR     od_interp
        STAA    [OD_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [OD_FRAME]
        LDAA    [OD_FRAME]
        CMPA    5
        BNE     od_flight_frame
        CLR     [OD_EFFECT]
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
od_interp:
        STAA    [OD_IA]
        CBA
        BHI     od_interp_back
        SUBB    [OD_IA]
        TBA
        LDAB    [OD_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [OD_IA]
        RTS
od_interp_back:
        SBA
        LDAB    [OD_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [OD_IA]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    OD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     od_hud
        JSR     jr_gfx_lines
        LDAA    OD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    28
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the sixteen plots
        CLR     [OD_DI]
od_draw_plot:
        LDAA    [OD_DI]
        JSR     od_need_of
        LDAA    [OD_DI]
        LDX     OD_B
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 16]
        STAB    [OD_DCROP]
        CMPA    [OD_NEED]
        BCS     od_draw_growing
        LDAA    OD_TILE_BERRY
        LDAB    OD_ATTR_BERRY
        TST     [OD_DCROP]
        BEQ     od_draw_tile
        LDAA    OD_TILE_APPLE
        LDAB    OD_ATTR_APPLE
        BRA     od_draw_tile
od_draw_growing:
        LDAB    OD_ATTR_GREEN
        CMPA    3
        BCS     od_draw_young
        LDAA    OD_TILE_TREE
        BRA     od_draw_tile
od_draw_young:
        TSTA
        BNE     od_draw_code
        LDAB    OD_ATTR_SOIL
od_draw_code:
        ASLA
        ASLA
        ADDA    OD_TILE_SOIL
od_draw_tile:
        STAA    [OD_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [OD_DI]
        JSR     od_plot_xy
        STAA    [OD_DPX]
        STAB    [OD_DPY]
        JSR     jr_gfx_at
        LDAA    [OD_DCODE]
        JSR     jr_gfx_tile
        ; A (apple) or B (berry) and the growths left
        LDAA    [OD_DI]
        LDX     OD_B
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     od_draw_plot_next
        STAA    [OD_DCODE]
        LDAA    0x03
        LDAB    0x42
        TST     [OD_DCROP]
        BEQ     od_draw_kind
        LDAA    0x02
        LDAB    0x41
od_draw_kind:
        STAA    [JR_RT_COLOR]
        STAB    [OD_DATTR]
        LDAA    [OD_DPX]
        LDAB    [OD_DPY]
        INCB
        INCB
        JSR     jr_gfx_at
        LDAA    [OD_DATTR]
        JSR     jr_gfx_putc
        LDAA    OD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [OD_NEED]
        SUBA    [OD_DCODE]
        ADDA    0x30
        JSR     jr_gfx_putc
od_draw_plot_next:
        INC     [OD_DI]
        LDAA    [OD_DI]
        CMPA    16
        BEQ     od_draw_plot_near547
        JMP     od_draw_plot
od_draw_plot_near547:
        ; the cursor and the crop mark
        LDAA    OD_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [OD_CURSOR]
        CMPA    16
        BCC     od_draw_tool_cursor
        JSR     od_plot_xy
        DECA
        BRA     od_draw_cursor
od_draw_tool_cursor:
        SUBA    16
        ASLA
        ASLA
        ASLA
        LDAB    18
od_draw_cursor:
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    [OD_CROP]
        ASLA
        ASLA
        ASLA
        INCA
        LDAB    18
        JSR     jr_gfx_at
        LDAA    0x5e
        JSR     jr_gfx_putc
        ; seeds, water, fruit and the next rain
        LDAA    OD_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [OD_SEEDS]
        JSR     jr_gfx_dec2
        LDAA    OD_ATTR_WATER
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [OD_WATER]
        JSR     jr_gfx_dec2
        LDAA    28
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [OD_DAY]
        LDAB    [OD_PERIOD]
        JSR     jr_divmod8
        NEGB
        ADDB    [OD_PERIOD]
        TBA
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    OD_ATTR_TEXT
        LDAB    [OD_FRUIT]
        CMPB    [OD_QUOTA]
        BCS     od_draw_fruit
        LDAA    OD_ATTR_GOOD
od_draw_fruit:
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    10
        JSR     jr_gfx_at
        LDAA    [OD_FRUIT]
        JSR     jr_gfx_dec2
        LDAA    0x2f
        JSR     jr_gfx_putc
        LDAA    [OD_QUOTA]
        JSR     jr_gfx_dec2
        LDAA    OD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [OD_DAY]
        JSR     jr_gfx_dec2
        ; what happened today
        LDAA    [OD_NOTICE]
        ASLA
        LDX     od_notice_text
        JSR     jr_add_x_a
        LDX     [X]
        CPX     0
        BEQ     od_draw_growing_mark
        STX     [JR_RT_TABLE]
        LDAA    [OD_NOTICE]
        LDX     od_notice_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    13
        LDAB    20
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        LDAA    [OD_NOTICE]
        CMPA    2
        BNE     od_draw_growing_mark
        LDAA    [OD_GAIN]
        ADDA    0x30
        JSR     jr_gfx_putc
od_draw_growing_mark:
        LDAA    [OD_GROWING]
        BEQ     od_draw_rain
        LDAB    OD_ATTR_PICK
        STAB    [JR_RT_COLOR]
        DECA
        JSR     od_plot_xy
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
od_draw_rain:
        TST     [OD_RAIN]
        BEQ     od_draw_effect
        LDAA    OD_ATTR_WATER
        STAA    [JR_RT_COLOR]
        CLR     [OD_DI]
od_draw_drop:
        LDAA    [OD_DI]
        ASLA
        INCA
        LDAB    3
        JSR     jr_gfx_at
        LDAA    0x2f
        JSR     jr_gfx_putc
        INC     [OD_DI]
        LDAA    [OD_DI]
        CMPA    7
        BNE     od_draw_drop
od_draw_effect:
        TST     [OD_EFFECT]
        BEQ     od_draw_done
        LDAA    [OD_EATTR]
        STAA    [JR_RT_COLOR]
        LDAA    [OD_EX]
        LDAB    [OD_EY]
        JSR     jr_gfx_at
        LDAA    [OD_ECODE]
        JMP     jr_gfx_tile
od_draw_done:
        RTS

game_draw_title:
        LDX     od_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    OD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     od_title_tiles
        STX     [JR_RT_TABLE]
od_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     od_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [OD_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [OD_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     od_title_tile
od_title_text:
        LDX     od_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    OD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     od_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

od_notice_text:
        .dw     0, 0, od_txt_harvest, 0, 0, od_txt_no_seeds, od_txt_empty
od_notice_attr:
        .db     0x07, 0x07, OD_ATTR_GOOD, 0x07, 0x07, OD_ATTR_BAD, OD_ATTR_BAD

; x, attribute, code, y
od_title_tiles:
        .db     7, OD_ATTR_SOIL, OD_TILE_SOIL, 3
        .db     10, OD_ATTR_GREEN, OD_TILE_SPROUT + 4, 3
        .db     13, OD_ATTR_BERRY, OD_TILE_BERRY, 3
        .db     16, OD_ATTR_GREEN, OD_TILE_TREE, 3
        .db     19, OD_ATTR_APPLE, OD_TILE_APPLE, 3
        .db     22, OD_ATTR_DROP, OD_TILE_DROP, 3
        .db     0xff

od_hud:
        .db     1, 0, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     21, 0, OD_ATTR_LABEL
        .dw     od_txt_season
        .db     19, 3, OD_ATTR_LABEL
        .dw     od_txt_seeds
        .db     19, 6, OD_ATTR_LABEL
        .dw     od_txt_water
        .db     19, 9, OD_ATTR_LABEL
        .dw     od_txt_fruit
        .db     19, 12, OD_ATTR_LABEL
        .dw     od_txt_rain
        .db     1, 17, OD_ATTR_TEXT
        .dw     od_txt_tools
        .db     1, 20, OD_ATTR_LABEL
        .dw     od_txt_day
        .db     0xff
od_title_lines:
        .db     10, 8, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     3, 10, OD_ATTR_LABEL
        .dw     od_txt_tagline
        .db     8, 15, OD_ATTR_TEXT
        .dw     od_txt_start
        .db     5, 17, OD_ATTR_TEXT
        .dw     od_txt_howto
        .db     4, 22, OD_ATTR_DIM
        .dw     od_txt_credit
        .db     0xff
od_help_lines:
        .db     10, 2, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     1, 4, OD_ATTR_TEXT
        .dw     od_help_1
        .db     1, 6, OD_ATTR_TEXT
        .dw     od_help_2
        .db     1, 8, OD_ATTR_TEXT
        .dw     od_help_3
        .db     1, 10, OD_ATTR_TEXT
        .dw     od_help_4
        .db     1, 12, OD_ATTR_TEXT
        .dw     od_help_5
        .db     1, 14, OD_ATTR_TEXT
        .dw     od_help_6
        .db     1, 16, OD_ATTR_TEXT
        .dw     od_help_7
        .db     1, 18, OD_ATTR_TEXT
        .dw     od_help_8
        .db     1, 20, OD_ATTR_TEXT
        .dw     od_help_9
        .db     1, 22, OD_ATTR_LABEL
        .dw     od_help_back
        .db     0xff

od_txt_name:
        .db     "ORCHARD DAYS", 0
od_txt_season:
        .db     "SEASON", 0
od_txt_seeds:
        .db     "SEEDS", 0
od_txt_water:
        .db     "WATER", 0
od_txt_fruit:
        .db     "FRUIT", 0
od_txt_rain:
        .db     "RAIN IN", 0
od_txt_tools:
        .db     "BERRY   APPLE   WAIT    WELL", 0
od_txt_day:
        .db     "DAY   /28", 0
od_txt_harvest:
        .db     "HARVEST +", 0
od_txt_no_seeds:
        .db     "NO SEEDS", 0
od_txt_empty:
        .db     "WELL IS EMPTY", 0
od_txt_lose:
        .db     "THE SEASON ENDED BELOW QUOTA", 0
od_txt_tagline:
        .db     "PLANT, WATER, WAIT FOR RAIN", 0
od_txt_start:
        .db     "RETURN : START", 0
od_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
od_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
od_help_1:
        .db     "WASD : SELECT PLOT OR TOOL ROW", 0
od_help_2:
        .db     "RETURN : PLANT / WATER / PICK", 0
od_help_3:
        .db     "BERRY: TWO GROWTHS, THREE FRUIT", 0
od_help_4:
        .db     "APPLE: 4 GROWTHS, 7 FRUIT", 0
od_help_5:
        .db     "WELL: SPEND A DAY FOR +3 WATER", 0
od_help_6:
        .db     "RAIN GROWS ALL AND FILLS WATER.", 0
od_help_7:
        .db     "MEET THE QUOTA WITHIN 28 DAYS.", 0
od_help_8:
        .db     "A/B: CROP / NUMBER: GROWTH LEFT", 0
od_help_9:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
od_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     od_sfx_tap, od_sfx_harvest, od_jingle_win, od_jingle_lose
od_sfx_tap:
        .db     140, 2, 0, 0
od_sfx_harvest:
        .db     70, 4, 56, 4, 47, 8, 0, 0
od_sfx_rain:
        .db     30, 2, 0, 1, 40, 2, 0, 1, 28, 2, 0, 1, 36, 2, 0, 0
od_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a pastoral in A major, 6/8 with the eighth note = 8 frames, looping.
od_title_song:
        .db     1
        .dw     od_title_melody, od_title_harmony, od_title_bass
od_title_melody:
        .db     AU_E5, 16, AU_CS5, 8, AU_E5, 16, AU_A5, 8, AU_GS5, 16, AU_FS5, 8, AU_E5, 24
        .db     AU_FS5, 16, AU_D5, 8, AU_FS5, 16, AU_B5, 8, AU_A5, 16, AU_GS5, 8, AU_A5, 24
        .db     0, 0
od_title_harmony:
        .db     AU_CS5, 24, AU_CS5, 24, AU_B4, 24, AU_CS5, 24
        .db     AU_D5, 24, AU_D5, 24, AU_CS5, 24, AU_CS5, 24, 0, 0
od_title_bass:
        .db     AU_A2, 24, AU_E3, 24, AU_E3, 24, AU_A2, 24
        .db     AU_D3, 24, AU_B2, 24, AU_E3, 24, AU_A2, 24, 0, 0

; Full basket: A major arpeggio over the tonic (54 frames).
od_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     od_win_melody, od_win_harmony, od_win_bass
od_win_melody:
        .db     AU_A5, 8, AU_CS6, 8, AU_E6, 8, AU_A6, 30, 0, 0
od_win_harmony:
        .db     AU_E5, 8, AU_A5, 8, AU_CS6, 8, AU_E6, 30, 0, 0
od_win_bass:
        .db     AU_A3, 24, AU_A2, 30, 0, 0
od_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     od_lose_melody, od_lose_harmony, od_lose_bass
od_lose_melody:
        .db     AU_E5, 12, AU_D5, 12, AU_C5, 12, AU_B4, 30, 0, 0
od_lose_harmony:
        .db     AU_C5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
od_lose_bass:
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

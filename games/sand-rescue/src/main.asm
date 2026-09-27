; SPDX-License-Identifier: MIT
; SAND RESCUE for JR-200: a port of jr100dev games/sand_rescue/rules.py 2.0.0.
; Six fields of three channels, the tank filling from the reserve, pouring
; the whole tank down one channel, the near and far crops, the cracks that
; soak water, tank overflow, leaving a field at its target and the carried
; campaign (water and total kept for the next field; a loss or a restart
; begins again at field 1) follow the upstream source, one upstream tick per
; game_tick. Rules are checked by the in-program self test (sdk/selftest.inc,
; title key T); P plays the field-1 demo.
        .filename.jr "SAND-RESCUE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46a0
SR_KEEP:            .equ    0x46a0      ; cleared field (255 none), water, total
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream ticks every 12 frames; one tick here is GAME_RATE idle frames plus
; the render, about 12.5 upstream frames (see README).
GAME_RATE:          .equ    5
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    40
GAME_TEST_LIMIT:    .equ    3000
GAME_TEST_HELD:     .equ    SR_HELD

; Upstream state (tests/model.py LAYOUT), then work bytes.
SR_WATER:           .equ    GAME_STATE
SR_TOTAL:           .equ    GAME_STATE + 1
SR_QUOTA:           .equ    GAME_STATE + 2
SR_INTERVAL:        .equ    GAME_STATE + 3
SR_FILL:            .equ    GAME_STATE + 4
SR_GATE:            .equ    GAME_STATE + 5
SR_SCORE:           .equ    GAME_STATE + 6
SR_FLOW:            .equ    GAME_STATE + 7
SR_TANK:            .equ    GAME_STATE + 8
SR_ROUTE:           .equ    GAME_STATE + 9
SR_STEP:            .equ    GAME_STATE + 10
SR_NOTICE:          .equ    GAME_STATE + 11
SR_OPENING:         .equ    GAME_STATE + 12
SR_NOTICE_TIME:     .equ    GAME_STATE + 13
SR_GROWING:         .equ    GAME_STATE + 14
SR_REWARD:          .equ    GAME_STATE + 15
SR_AGE:             .equ    GAME_STATE + 16
SR_WASTE:           .equ    GAME_STATE + 17
SR_DRYING:          .equ    GAME_STATE + 18
SR_B:               .equ    GAME_STATE + 19     ; needs, soak, steps (15)
SR_C:               .equ    GAME_STATE + 34     ; water given (6)
SR_HELD:            .equ    GAME_STATE + 44     ; unused (no held keys)
SR_I:               .equ    GAME_STATE + 45
SR_K:               .equ    GAME_STATE + 46
SR_T:               .equ    GAME_STATE + 47
SR_X:               .equ    GAME_STATE + 48
SR_Y:               .equ    GAME_STATE + 49
SR_DI:              .equ    GAME_STATE + 50
SR_DS:              .equ    GAME_STATE + 51
SR_DW:              .equ    GAME_STATE + 52
SR_DQ:              .equ    GAME_STATE + 53
SR_FLASH:           .equ    GAME_STATE + 54     ; plant + 1 flashing
SR_J:               .equ    GAME_STATE + 55
; sr_irrigate keeps these across its animations (game_draw uses the others)
SR_P:               .equ    GAME_STATE + 56
SR_N:               .equ    GAME_STATE + 57
SR_PTR:             .equ    GAME_STATE + 58

SR_TILE_SPROUT:     .equ    0x80        ; sprout, ripe near, growing, ripe far
SR_CHAR_CHANNEL:    .equ    0x90        ; straight, bend, step
SR_CHAR_GATE_SHUT:  .equ    0x93
SR_CHAR_WET:        .equ    0x94        ; and 0x95
SR_CHAR_GATE_OPEN:  .equ    0x96
SR_CHAR_CRACK:      .equ    0x97
SR_CHAR_FEED:       .equ    0x98
SR_CHAR_FEED_WET:   .equ    0x99
SR_CHAR_DRY:        .equ    0x9a        ; and 0x9b
SR_ATTR_SAND:       .equ    0x46
SR_ATTR_WATER:      .equ    0x45
SR_ATTR_GATE:       .equ    0x47
SR_ATTR_CROP:       .equ    0x44
SR_ATTR_CRACK:      .equ    0x42
SR_ATTR_SPARK:      .equ    0x6e        ; yellow on green
SR_ATTR_TEXT:       .equ    0x07
SR_ATTR_LABEL:      .equ    0x04
SR_ATTR_TITLE:      .equ    0x06
SR_ATTR_DIM:        .equ    0x05
SR_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDAA    255
        STAA    [SR_KEEP]
        LDX     sr_patterns
        LDAA    SR_TILE_SPROUT
        LDAB    28
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; A field starts: the next field after a clear takes the kept water and total;
; anything else (a loss, a restart) begins again at field 1 with 108 water.
game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    [SR_KEEP]
        LDAB    255
        STAB    [SR_KEEP]
        INCA
        TST     [JR_PORT_LEVEL]
        BEQ     sr_init_first
        CMPA    [JR_PORT_LEVEL]
        BEQ     sr_init_carry
sr_init_first:
        CLR     [JR_PORT_LEVEL]
        LDAA    108
        STAA    [SR_WATER]
        CLR     [SR_TOTAL]
        BRA     sr_init_field
sr_init_carry:
        LDAA    [SR_KEEP + 1]
        STAA    [SR_WATER]
        LDAA    [SR_KEEP + 2]
        STAA    [SR_TOTAL]
sr_init_field:
        LDX     sr_quotas
        LDAA    [JR_PORT_LEVEL]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SR_QUOTA]
        LDAA    [JR_PORT_LEVEL]
        LSRA
        NEGA
        ADDA    5
        STAA    [SR_INTERVAL]
        STAA    [SR_FILL]
        ; the three channels of this field: needs, soak and steps
        LDAA    [JR_PORT_LEVEL]
        LDAB    15
        JSR     jr_mul8
        LDX     sr_channels
        JSR     jr_add_x_a
        CLR     [SR_I]
sr_init_channel:
        STX     [SR_DQ]
        LDAB    [X]
        LDAA    [SR_I]
        LDX     SR_B
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [SR_DQ]
        LDAB    [X + 1]
        LDAA    [SR_I]
        LDX     SR_B + 3
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [SR_DQ]
        LDAB    [X + 2]
        LDAA    [SR_I]
        LDX     SR_B + 6
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [SR_DQ]
        LDAB    [X + 3]
        LDAA    [SR_I]
        LDX     SR_B + 9
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [SR_DQ]
        LDAB    [X + 4]
        LDAA    [SR_I]
        LDX     SR_B + 12
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [SR_DQ]
        LDAA    5
        JSR     jr_add_x_a
        INC     [SR_I]
        LDAA    [SR_I]
        CMPA    3
        BNE     sr_init_channel
        RTS

; T (self test) and P (demo) begin from field 1.
game_raw_key:
        LDAA    255
        STAA    [SR_KEEP]
        CLRA
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_LEFT
        BNE     sr_act_right
        LDAA    [SR_GATE]
        ADDA    2
        BRA     sr_act_gate
sr_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     sr_act_leave
        LDAA    [SR_GATE]
        INCA
sr_act_gate:
        CMPA    3
        BCS     sr_act_gate_set
        SUBA    3
sr_act_gate_set:
        STAA    [SR_GATE]
        CLRA
        JMP     jr_port_sound
sr_act_leave:
        CMPA    JR_KEY_UP
        BNE     sr_act_pour
        LDAA    [SR_SCORE]
        CMPA    [SR_QUOTA]
        BCS     sr_act_done
        TST     [SR_FLOW]
        BNE     sr_act_done
        ; bank the harvest and keep water and total for the next field
        ADDA    [SR_TOTAL]
        STAA    [SR_TOTAL]
        STAA    [SR_KEEP + 2]
        LDAA    [SR_WATER]
        ADDA    [SR_TANK]
        STAA    [SR_KEEP + 1]
        LDAA    [JR_PORT_LEVEL]
        STAA    [SR_KEEP]
        JMP     jr_port_win
sr_act_pour:
        CMPA    JR_KEY_CONFIRM
        BNE     sr_act_done
        TST     [SR_FLOW]
        BNE     sr_act_done
        TST     [SR_TANK]
        BEQ     sr_act_done
        LDAA    [SR_GATE]
        STAA    [SR_ROUTE]
        LDAA    [SR_TANK]
        STAA    [SR_FLOW]
        CLR     [SR_TANK]
        CLR     [SR_STEP]
        CLR     [SR_NOTICE]
        LDX     sr_sfx_pour
        JSR     jr_sfx_play
        LDAA    1
        STAA    [SR_OPENING]
        LDAA    5
        JSR     jr_test_animate
        LDAA    2
        STAA    [SR_OPENING]
        LDAA    5
        JSR     jr_test_animate
        CLR     [SR_OPENING]
sr_act_done:
        RTS

; A = offset in b (0 near need .. 12 far step), B = channel -> A = b[offset + channel].
sr_bget:
        STAB    [SR_T]
        ADDA    [SR_T]
        LDX     SR_B
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; SR_P = plant (0-2 near, 3-5 far): up to five drops while it still needs water.
sr_irrigate:
        LDAA    [SR_P]
        INCA
        STAA    [SR_GROWING]
        LDAA    5
        STAA    [SR_N]
sr_irrigate_drop:
        TST     [SR_FLOW]
        BEQ     sr_irrigate_next
        LDX     SR_C
        LDAA    [SR_P]
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    [SR_P]
        STX     [SR_PTR]
        LDX     SR_B
        JSR     jr_add_x_a
        CMPB    [X]
        BCC     sr_irrigate_next
        DEC     [SR_FLOW]
        LDX     [SR_PTR]
        INC     [X]
        CLRA
        JSR     jr_port_sound
        LDAA    5
        JSR     jr_test_animate
        ; ripe: 3 for a near crop, twice the need for a far one
        LDX     [SR_PTR]
        LDAB    [X]
        LDAA    [SR_P]
        LDX     SR_B
        JSR     jr_add_x_a
        CMPB    [X]
        BNE     sr_irrigate_next
        LDAA    3
        LDAB    [SR_P]
        CMPB    3
        BCS     sr_irrigate_reward
        LDAA    [X]
        ASLA
sr_irrigate_reward:
        STAA    [SR_REWARD]
        ADDA    [SR_SCORE]
        STAA    [SR_SCORE]
        LDAA    1
        STAA    [SR_NOTICE]
        LDAA    12
        STAA    [SR_NOTICE_TIME]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [SR_P]
        INCA
        STAA    [SR_FLASH]
        LDAA    6
        JSR     jr_test_animate
        CLR     [SR_FLASH]
sr_irrigate_next:
        DEC     [SR_N]
        BNE     sr_irrigate_drop
        CLR     [SR_GROWING]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     sr_act_done_near335
        JMP     sr_act_done
sr_act_done_near335:
        INC     [SR_AGE]
        TST     [SR_NOTICE_TIME]
        BEQ     sr_tick_flow
        DEC     [SR_NOTICE_TIME]
sr_tick_flow:
        TST     [SR_FLOW]
        BNE     sr_tick_flowing
        JMP     sr_tick_fill
sr_tick_flowing:
        INC     [SR_STEP]
        LDAA    9
        LDAB    [SR_ROUTE]
        JSR     sr_bget
        STAA    [SR_X]
        CMPA    [SR_STEP]
        BNE     sr_tick_crack
        ; the near crop
        LDAA    [SR_ROUTE]
        STAA    [SR_P]
        JSR     sr_irrigate
        JMP     sr_tick_fill
sr_tick_crack:
        ADDA    3
        CMPA    [SR_STEP]
        BNE     sr_tick_far
        ; the crack soaks up to its size
        LDAA    6
        LDAB    [SR_ROUTE]
        JSR     sr_bget
        CMPA    [SR_FLOW]
        BLS     sr_tick_soak
        LDAA    [SR_FLOW]
sr_tick_soak:
        STAA    [SR_T]
        LDAA    [SR_FLOW]
        SUBA    [SR_T]
        STAA    [SR_FLOW]
        LDAA    [SR_WASTE]
        ADDA    [SR_T]
        STAA    [SR_WASTE]
        LDAA    2
        STAA    [SR_NOTICE]
        LDAA    8
        STAA    [SR_NOTICE_TIME]
        LDX     sr_sfx_soak
        JSR     jr_sfx_play
        LDAA    1
        STAA    [SR_DRYING]
        LDAA    5
        JSR     jr_test_animate
        LDAA    2
        STAA    [SR_DRYING]
        LDAA    5
        JSR     jr_test_animate
        CLR     [SR_DRYING]
        BRA     sr_tick_fill
sr_tick_far:
        LDAA    12
        LDAB    [SR_ROUTE]
        JSR     sr_bget
        CMPA    [SR_STEP]
        BNE     sr_tick_end
        LDAA    [SR_ROUTE]
        ADDA    3
        STAA    [SR_P]
        JSR     sr_irrigate
        BRA     sr_tick_fill
sr_tick_end:
        ; past the far crop: the rest runs off
        ADDA    2
        CMPA    [SR_STEP]
        BCC     sr_tick_fill
        LDAA    [SR_WASTE]
        ADDA    [SR_FLOW]
        STAA    [SR_WASTE]
        CLR     [SR_FLOW]
sr_tick_fill:
        ; the reserve fills the tank one unit every interval ticks
        TST     [SR_WATER]
        BEQ     sr_tick_dry
        DEC     [SR_FILL]
        BNE     sr_tick_dry
        LDAA    [SR_INTERVAL]
        STAA    [SR_FILL]
        DEC     [SR_WATER]
        LDAA    [SR_TANK]
        CMPA    9
        BCC     sr_tick_overflow
        INC     [SR_TANK]
        BRA     sr_tick_dry
sr_tick_overflow:
        INC     [SR_WASTE]
        LDAA    3
        STAA    [SR_NOTICE]
        LDAA    8
        STAA    [SR_NOTICE_TIME]
        LDX     sr_sfx_soak
        JSR     jr_sfx_play
sr_tick_dry:
        TST     [SR_WATER]
        BEQ     sr_act_done_near438
        JMP     sr_act_done
sr_act_done_near438:
        TST     [SR_TANK]
        BEQ     sr_act_done_near442
        JMP     sr_act_done
sr_act_done_near442:
        TST     [SR_FLOW]
        BEQ     sr_act_done_near446
        JMP     sr_act_done
sr_act_done_near446:
        LDAA    [SR_SCORE]
        CMPA    [SR_QUOTA]
        BCS     sr_act_done_near451
        JMP     sr_act_done
sr_act_done_near451:
        LDX     sr_txt_loss
        JMP     jr_port_lose

; ---------------------------------------------------------------- drawing

; SR_DI = channel, A = step, SR_DW = wet: one cell of the channel.
sr_channel:
        STAA    [SR_DS]
        LDAA    9
        LDAB    [SR_DI]
        JSR     sr_bget
        ADDA    2
        STAA    [SR_T]              ; the bend
        LDAA    [SR_DI]
        LDAB    10
        JSR     jr_mul8
        ADDA    2
        STAA    [SR_X]
        LDAA    [SR_DS]
        ADDA    6
        STAA    [SR_Y]
        LDAB    SR_CHAR_CHANNEL
        LDAA    [SR_DS]
        CMPA    [SR_T]
        BCS     sr_channel_put
        BNE     sr_channel_after
        LDAB    SR_CHAR_CHANNEL + 1
        BRA     sr_channel_put
sr_channel_after:
        INC     [SR_X]
        DEC     [SR_Y]
        DECA
        CMPA    [SR_T]
        BNE     sr_channel_put
        LDAB    SR_CHAR_CHANNEL + 2
sr_channel_put:
        TST     [SR_DW]
        BEQ     sr_channel_draw
        LDAB    [SR_AGE]
        ANDB    1
        ADDB    SR_CHAR_WET
sr_channel_draw:
        STAB    [SR_DQ]
        LDAA    SR_ATTR_SAND
        TST     [SR_DW]
        BEQ     sr_channel_colour
        LDAA    SR_ATTR_WATER
sr_channel_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        LDAB    [SR_Y]
        JSR     jr_gfx_at
        LDAA    [SR_DQ]
        JMP     jr_gfx_putc

; A = plant -> A = y of its crop tile.
sr_crop_y:
        CMPA    3
        BCC     sr_crop_y_far
        TAB
        LDAA    9
        JSR     sr_bget
        ADDA    6
        RTS
sr_crop_y_far:
        SUBA    3
        TAB
        LDAA    12
        JSR     sr_bget
        ADDA    5
        RTS

game_draw:
        LDAA    0x20
        LDAB    SR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sr_hud
        JSR     jr_gfx_lines
        LDAA    SR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        ADDA    0x31
        JSR     jr_gfx_putc
        LDAA    6
        LDAB    1
        JSR     jr_gfx_at
        LDAA    [SR_WATER]
        ADDA    [SR_TANK]
        JSR     jr_gfx_dec3
        LDAA    19
        LDAB    1
        JSR     jr_gfx_at
        LDAA    [SR_SCORE]
        JSR     jr_gfx_dec2
        LDAA    22
        LDAB    1
        JSR     jr_gfx_at
        LDAA    [SR_QUOTA]
        JSR     jr_gfx_dec2
        LDAA    21
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [SR_TANK]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    30
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [SR_FLOW]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the tank
        LDAA    10
        LDAB    3
        JSR     jr_gfx_at
        CLR     [SR_K]
sr_draw_tank:
        LDAA    SR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    0x2e
        LDAB    [SR_K]
        CMPB    [SR_TANK]
        BCC     sr_draw_tank_cell
        LDAB    SR_ATTR_WATER
        STAB    [JR_RT_COLOR]
        LDAA    [SR_AGE]
        ANDA    1
        ADDA    SR_CHAR_WET
sr_draw_tank_cell:
        JSR     jr_gfx_putc
        INC     [SR_K]
        LDAA    [SR_K]
        CMPA    9
        BNE     sr_draw_tank
        ; the three channels
        CLR     [SR_DI]
sr_draw_route:
        LDAA    [SR_DI]
        LDAB    10
        JSR     jr_mul8
        ADDA    2
        STAA    [SR_X]
        ; gate: open while its water flows, half-open while opening
        LDAA    SR_ATTR_GATE
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        DECA
        LDAB    5
        JSR     jr_gfx_at
        LDAA    0x20
        LDAB    [SR_GATE]
        CMPB    [SR_DI]
        BNE     sr_draw_gate_mark
        LDAA    0x3e
sr_draw_gate_mark:
        PSHA
        LDAA    SR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        PULA
        JSR     jr_gfx_putc
        LDAA    SR_ATTR_GATE
        STAA    [JR_RT_COLOR]
        LDAA    SR_CHAR_GATE_SHUT
        LDAB    [SR_ROUTE]
        CMPB    [SR_DI]
        BNE     sr_draw_gate
        TST     [SR_FLOW]
        BEQ     sr_draw_gate_opening
        LDAA    SR_CHAR_GATE_OPEN
sr_draw_gate_opening:
        LDAB    [SR_OPENING]
        BEQ     sr_draw_gate
        LDAA    SR_CHAR_GATE_OPEN
        CMPB    1
        BNE     sr_draw_gate
        LDAA    0x2d
        LDAB    SR_ATTR_TITLE
        STAB    [JR_RT_COLOR]
sr_draw_gate:
        JSR     jr_gfx_putc
        ; the dry channel down to two steps past the far crop
        CLR     [SR_DW]
        CLR     [SR_K]
sr_draw_channel:
        LDAA    [SR_K]
        JSR     sr_channel
        INC     [SR_K]
        LDAA    12
        LDAB    [SR_DI]
        JSR     sr_bget
        ADDA    3
        CMPA    [SR_K]
        BNE     sr_draw_channel
        ; its two crops
        CLR     [SR_J]
sr_draw_crop:
        LDAA    [SR_J]
        ASLA
        ADDA    [SR_J]
        ADDA    [SR_DI]
        STAA    [SR_I]
        JSR     sr_draw_plant
        INC     [SR_J]
        LDAA    [SR_J]
        CMPA    2
        BNE     sr_draw_crop
        ; the crack and its size
        LDAA    SR_ATTR_CRACK
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    [SR_DI]
        JSR     sr_bget
        STAA    [SR_T]
        LDAA    [SR_DI]
        LDAB    10
        JSR     jr_mul8
        ADDA    3
        STAA    [SR_X]
        LDAB    [SR_T]
        ADDB    8
        JSR     jr_gfx_at
        LDAA    SR_CHAR_CRACK
        LDAB    [SR_DRYING]
        BEQ     sr_draw_crack
        LDAB    [SR_ROUTE]
        CMPB    [SR_DI]
        BNE     sr_draw_crack
        LDAA    [SR_DRYING]
        ADDA    SR_CHAR_DRY - 1
sr_draw_crack:
        JSR     jr_gfx_putc
        LDAA    SR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        INCA
        LDAB    [SR_T]
        ADDB    9
        JSR     jr_gfx_at
        LDAA    6
        LDAB    [SR_DI]
        JSR     sr_bget
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [SR_DI]
        LDAA    [SR_DI]
        CMPA    3
        BEQ     sr_draw_flow
        JMP     sr_draw_route
sr_draw_flow:
        ; the water running down, up to three cells long
        TST     [SR_FLOW]
        BEQ     sr_draw_panel
        LDAA    [SR_ROUTE]
        STAA    [SR_DI]
        LDAA    1
        STAA    [SR_DW]
        CLR     [SR_K]
sr_draw_flow_cell:
        LDAA    [SR_K]
        CMPA    [SR_FLOW]
        BCC     sr_draw_panel
        LDAA    [SR_STEP]
        SUBA    [SR_K]
        BCS     sr_draw_panel
        JSR     sr_channel
        INC     [SR_K]
        LDAA    [SR_K]
        CMPA    3
        BNE     sr_draw_flow_cell
sr_draw_panel:
        ; row 20: banked or the latest notice
        LDAA    SR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BEQ     sr_draw_banked
        CMPA    JR_MODE_END
        BNE     sr_draw_notice
sr_draw_banked:
        LDX     sr_txt_banked
        JSR     jr_gfx_text
        LDAA    8
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SR_SCORE]
        JSR     jr_gfx_dec2
        LDAA    13
        LDAB    20
        JSR     jr_gfx_at
        LDX     sr_txt_saved
        JSR     jr_gfx_text
        LDAA    25
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SR_WATER]
        ADDA    [SR_TANK]
        JSR     jr_gfx_dec3
        BRA     sr_draw_total
sr_draw_notice:
        TST     [SR_NOTICE_TIME]
        BEQ     sr_draw_total
        LDAA    [SR_NOTICE]
        BEQ     sr_draw_total
        LDX     sr_notices - 2
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [SR_NOTICE]
        CMPA    1
        BNE     sr_draw_total
        LDAA    10
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SR_REWARD]
        JSR     jr_gfx_dec2
sr_draw_total:
        LDAA    SR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [SR_TOTAL]
        LDAB    [JR_PORT_MODE]
        CMPB    JR_MODE_PLAY
        BNE     sr_draw_total_value
        ADDA    [SR_SCORE]
sr_draw_total_value:
        JSR     jr_gfx_dec3
        LDAA    [JR_PORT_LEVEL]
        CMPA    5
        BCC     sr_draw_ready
        LDAA    18
        LDAB    22
        JSR     jr_gfx_at
        LDX     sr_quotas + 1
        LDAA    [JR_PORT_LEVEL]
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_dec2
sr_draw_ready:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     sr_draw_medal
        LDAA    [SR_SCORE]
        CMPA    [SR_QUOTA]
        BCS     sr_draw_demo
        LDAA    SR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    22
        JSR     jr_gfx_at
        LDX     sr_txt_ready
        JSR     jr_gfx_text
        BRA     sr_draw_demo
sr_draw_medal:
        LDAA    [JR_PORT_LEVEL]
        CMPA    5
        BNE     sr_draw_demo
        LDAA    SR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    2
        JSR     jr_gfx_at
        LDX     sr_txt_gold
        LDAA    [SR_TOTAL]
        CMPA    140
        BCC     sr_draw_medal_text
        LDX     sr_txt_silver
        CMPA    130
        BCC     sr_draw_medal_text
        LDX     sr_txt_bronze
sr_draw_medal_text:
        JSR     jr_gfx_text
sr_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     sr_draw_done
        LDAA    SR_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    14
        CLRB
        JSR     jr_gfx_at
        LDX     sr_txt_demo
        JSR     jr_gfx_text
sr_draw_done:
        RTS

; SR_I = plant: its crop tile, points, water given/needed and the feeder.
sr_draw_plant:
        LDAA    [SR_I]
        JSR     sr_crop_y
        STAA    [SR_DS]
        LDAA    [SR_DI]
        LDAB    10
        JSR     jr_mul8
        ADDA    2
        STAA    [SR_X]
        ; kind: ripe (near 3 / far 5), growing (4) or a sprout (2)
        LDX     SR_C
        LDAA    [SR_I]
        JSR     jr_add_x_a
        LDAB    [X]
        STAB    [SR_DQ]
        LDX     SR_B
        LDAA    [SR_I]
        JSR     jr_add_x_a
        LDAA    SR_TILE_SPROUT
        TSTB
        BEQ     sr_draw_plant_kind
        LDAA    SR_TILE_SPROUT + 8
        CMPB    [X]
        BNE     sr_draw_plant_kind
        LDAA    SR_TILE_SPROUT + 4
        LDAB    [SR_I]
        CMPB    3
        BCS     sr_draw_plant_kind
        LDAA    SR_TILE_SPROUT + 12
sr_draw_plant_kind:
        STAA    [SR_T]
        LDAA    SR_ATTR_CROP
        LDAB    [SR_I]
        INCB
        CMPB    [SR_FLASH]
        BNE     sr_draw_plant_colour
        LDAA    SR_ATTR_SPARK
sr_draw_plant_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        ADDA    3
        LDAB    [SR_DS]
        JSR     jr_gfx_at
        LDAA    [SR_T]
        JSR     jr_gfx_tile
        ; +points
        LDAA    SR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        ADDA    6
        LDAB    [SR_DS]
        JSR     jr_gfx_at
        LDAA    0x2b
        JSR     jr_gfx_putc
        LDAA    3
        LDAB    [SR_I]
        CMPB    3
        BCS     sr_draw_plant_points
        LDX     SR_B
        LDAA    [SR_I]
        JSR     jr_add_x_a
        LDAA    [X]
        ASLA
sr_draw_plant_points:
        JSR     jr_gfx_dec2
        ; given / needed under it
        LDAA    SR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        ADDA    3
        LDAB    [SR_DS]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [SR_DQ]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    0x2f
        JSR     jr_gfx_putc
        LDX     SR_B
        LDAA    [SR_I]
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the feeder from the channel, wet while the crop drinks
        LDAA    SR_ATTR_SAND
        STAA    [JR_RT_COLOR]
        LDAA    [SR_X]
        INCA
        LDAB    [SR_DS]
        INCB
        JSR     jr_gfx_at
        LDAA    SR_CHAR_FEED
        LDAB    [SR_I]
        INCB
        CMPB    [SR_GROWING]
        BNE     sr_draw_plant_feed
        LDAB    SR_ATTR_WATER
        STAB    [JR_RT_COLOR]
        LDAA    SR_CHAR_FEED_WET
sr_draw_plant_feed:
        JSR     jr_gfx_putc
        JMP     jr_gfx_putc

game_draw_title:
        LDX     sr_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    SR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sr_title_tiles
        STX     [JR_RT_TABLE]
sr_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     sr_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [SR_DQ]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [SR_DQ]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     sr_title_tile
sr_title_text:
        LDX     sr_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sr_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; upstream game.json dataTables, per field and channel: near need, far need,
; soak, near step, far step
sr_channels:
        .db     2, 4, 1, 3, 10
        .db     2, 3, 2, 4, 11
        .db     2, 5, 3, 3, 12
        .db     2, 4, 2, 4, 12
        .db     3, 5, 1, 3, 10
        .db     2, 3, 2, 5, 11
        .db     3, 5, 3, 5, 11
        .db     2, 4, 2, 3, 12
        .db     3, 3, 1, 4, 10
        .db     2, 4, 1, 3, 10
        .db     3, 5, 3, 5, 12
        .db     2, 4, 2, 4, 11
        .db     3, 5, 2, 4, 12
        .db     3, 4, 1, 5, 11
        .db     2, 5, 3, 3, 10
        .db     3, 5, 3, 5, 11
        .db     2, 5, 2, 4, 10
        .db     3, 4, 1, 3, 12
sr_quotas:
        .db     14, 17, 19, 21, 24, 26
sr_notices:
        .dw     sr_txt_harvest, sr_txt_soaked, sr_txt_overflow

; x, attribute, code, y
sr_title_tiles:
        .db     8, SR_ATTR_CROP, SR_TILE_SPROUT, 3
        .db     12, SR_ATTR_CROP, SR_TILE_SPROUT + 8, 3
        .db     16, SR_ATTR_CROP, SR_TILE_SPROUT + 4, 3
        .db     20, SR_ATTR_CROP, SR_TILE_SPROUT + 12, 3
        .db     0xff

sr_hud:
        .db     0, 0, SR_ATTR_TITLE
        .dw     sr_txt_name
        .db     23, 0, SR_ATTR_LABEL
        .dw     sr_txt_field
        .db     0, 1, SR_ATTR_LABEL
        .dw     sr_txt_row1
        .db     21, 1, SR_ATTR_LABEL
        .dw     sr_txt_slash
        .db     1, 3, SR_ATTR_LABEL
        .dw     sr_txt_tank
        .db     20, 3, SR_ATTR_LABEL
        .dw     sr_txt_of9
        .db     25, 3, SR_ATTR_LABEL
        .dw     sr_txt_pour
        .db     4, 5, SR_ATTR_TITLE
        .dw     sr_txt_a
        .db     14, 5, SR_ATTR_TITLE
        .dw     sr_txt_b
        .db     24, 5, SR_ATTR_TITLE
        .dw     sr_txt_c
        .db     1, 22, SR_ATTR_LABEL
        .dw     sr_txt_total
        .db     13, 22, SR_ATTR_LABEL
        .dw     sr_txt_next
        .db     0xff
sr_title_lines:
        .db     10, 8, SR_ATTR_TITLE
        .dw     sr_txt_name
        .db     2, 10, SR_ATTR_LABEL
        .dw     sr_txt_tagline
        .db     4, 13, SR_ATTR_TEXT
        .dw     sr_txt_start
        .db     4, 15, SR_ATTR_TEXT
        .dw     sr_txt_howto
        .db     4, 17, SR_ATTR_DIM
        .dw     sr_txt_demo_hint
        .db     4, 19, SR_ATTR_DIM
        .dw     sr_txt_credit
        .db     0xff
sr_help_lines:
        .db     10, 1, SR_ATTR_TITLE
        .dw     sr_txt_name
        .db     1, 3, SR_ATTR_TEXT
        .dw     sr_help_1
        .db     1, 5, SR_ATTR_TEXT
        .dw     sr_help_2
        .db     1, 7, SR_ATTR_TEXT
        .dw     sr_help_3
        .db     1, 9, SR_ATTR_TEXT
        .dw     sr_help_4
        .db     1, 11, SR_ATTR_TEXT
        .dw     sr_help_5
        .db     1, 13, SR_ATTR_TEXT
        .dw     sr_help_6
        .db     1, 15, SR_ATTR_TEXT
        .dw     sr_help_7
        .db     1, 17, SR_ATTR_TEXT
        .dw     sr_help_8
        .db     1, 19, SR_ATTR_TEXT
        .dw     sr_help_9
        .db     1, 21, SR_ATTR_LABEL
        .dw     sr_help_back
        .db     0xff

sr_txt_name:
        .db     "SAND RESCUE", 0
sr_txt_field:
        .db     "FIELD", 0
sr_txt_row1:
        .db     "WATER      HARVEST", 0
sr_txt_slash:
        .db     "/", 0
sr_txt_tank:
        .db     "TANK", 0
sr_txt_of9:
        .db     "  /9", 0
sr_txt_pour:
        .db     "POUR", 0
sr_txt_a:
        .db     "A", 0
sr_txt_b:
        .db     "B", 0
sr_txt_c:
        .db     "C", 0
sr_txt_total:
        .db     "TOTAL", 0
sr_txt_next:
        .db     "NEXT", 0
sr_txt_ready:
        .db     "READY", 0
sr_txt_banked:
        .db     "BANKED", 0
sr_txt_saved:
        .db     "WATER SAVED", 0
sr_txt_harvest:
        .db     "HARVEST +", 0
sr_txt_soaked:
        .db     "WATER SOAKED INTO SAND", 0
sr_txt_overflow:
        .db     "TANK OVERFLOW!", 0
sr_txt_gold:
        .db     "GOLD HARVEST", 0
sr_txt_silver:
        .db     "SILVER HARVEST", 0
sr_txt_bronze:
        .db     "BRONZE HARVEST", 0
sr_txt_demo:
        .db     "DEMO", 0
sr_txt_loss:
        .db     "NO WATER LEFT FOR THE HARVEST", 0
sr_txt_tagline:
        .db     "POUR WISELY, SAVE THE CROPS", 0
sr_txt_start:
        .db     "RETURN : START", 0
sr_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
sr_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
sr_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sr_help_1:
        .db     "A/D: SELECT WATER GATE.", 0
sr_help_2:
        .db     "RETURN: POUR THE WHOLE TANK.", 0
sr_help_3:
        .db     "W: LEAVE AFTER HARVEST TARGET.", 0
sr_help_4:
        .db     "TANK HOLDS 9. EXCESS OVERFLOWS.", 0
sr_help_5:
        .db     "NEAR CROPS: 3 PTS. FAR: 6-10.", 0
sr_help_6:
        .db     "CRACKS SOAK 1-3 WATER PER POUR.", 0
sr_help_7:
        .db     "CROP: WATER GIVEN/NEEDED, +PTS", 0
sr_help_8:
        .db     "SAVE WATER ACROSS SIX FIELDS.", 0
sr_help_9:
        .db     "SPACE: NEW GAME FROM FIELD 1", 0
sr_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     sr_sfx_drip, sr_sfx_ripe, sr_jingle_win, sr_jingle_lose
sr_sfx_drip:
        .db     50, 1, 0, 0
sr_sfx_ripe:
        .db     36, 2, 30, 2, 24, 6, 0, 0
sr_sfx_pour:
        .db     120, 2, 100, 2, 80, 2, 60, 4, 0, 0
sr_sfx_soak:
        .db     200, 3, 240, 6, 0, 0

; Title: a desert lament in D minor, eighth note = 8 frames, looping.
sr_title_song:
        .db     1
        .dw     sr_title_melody, sr_title_harmony, sr_title_bass
sr_title_melody:
        .db     AU_D5, 16, AU_F5, 8, AU_E5, 8, AU_D5, 8, AU_CS5, 8, AU_D5, 16
        .db     AU_A4, 8, AU_AS4, 8, AU_A4, 8, AU_G4, 8, AU_A4, 32
        .db     AU_F5, 16, AU_G5, 8, AU_F5, 8, AU_E5, 8, AU_D5, 8, AU_E5, 16
        .db     AU_CS5, 8, AU_A4, 8, AU_CS5, 8, AU_E5, 8, AU_D5, 32, 0, 0
sr_title_harmony:
        .db     AU_A4, 32, AU_F4, 32, AU_D4, 32, AU_E4, 32
        .db     AU_A4, 32, AU_G4, 32, AU_A4, 32, AU_F4, 32, 0, 0
sr_title_bass:
        .db     AU_D3, 32, AU_D3, 32, AU_AS2, 32, AU_A2, 32
        .db     AU_D3, 32, AU_C3, 32, AU_A2, 32, AU_D2, 32, 0, 0

; Field banked: D major rain.
sr_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     sr_win_melody, sr_win_harmony, sr_win_bass
sr_win_melody:
        .db     AU_FS5, 6, AU_A5, 6, AU_D6, 6, AU_FS6, 12, AU_D6, 30, 0, 0
sr_win_harmony:
        .db     AU_D5, 12, AU_FS5, 18, AU_A5, 30, 0, 0
sr_win_bass:
        .db     AU_D3, 12, AU_A2, 18, AU_D2, 30, 0, 0
sr_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     sr_lose_melody, sr_lose_harmony, sr_lose_bass
sr_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
sr_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
sr_lose_bass:
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

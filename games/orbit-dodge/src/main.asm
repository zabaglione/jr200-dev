; SPDX-License-Identifier: MIT
; ORBIT DODGE for JR-200: a port of jr100dev games/orbit_dodge/rules.py 3.0.0.
; Six sectors, eight orbit positions on two rings, the wave timer, the beam
; targets (a second one on the other ring from wave 5 or sector 3), gems and
; their chain, the hull and the gold orbit follow the upstream source, one
; upstream tick per game_tick. Rules are checked by the in-program self test
; (sdk/selftest.inc, title key T); P plays the sector-1 demo.
        .filename.jr "ORBIT-DODGE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4680
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream ticks every 14 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    9
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    18
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    OD_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
OD_HP:              .equ    GAME_STATE
OD_TARGET:          .equ    GAME_STATE + 1
OD_LIMIT:           .equ    GAME_STATE + 2
OD_WINDOW:          .equ    GAME_STATE + 3
OD_RING:            .equ    GAME_STATE + 4
OD_OTHER:           .equ    GAME_STATE + 5
OD_DUAL:            .equ    GAME_STATE + 6
OD_GEM:             .equ    GAME_STATE + 7
OD_GEM_RING:        .equ    GAME_STATE + 8
OD_AGE:             .equ    GAME_STATE + 9
OD_POS:             .equ    GAME_STATE + 10
OD_ORBIT:           .equ    GAME_STATE + 11
OD_TRAVEL:          .equ    GAME_STATE + 12
OD_WAVES:           .equ    GAME_STATE + 13
OD_CHAIN:           .equ    GAME_STATE + 14
OD_SCORE:           .equ    GAME_STATE + 15
OD_FIRING:          .equ    GAME_STATE + 16
OD_BEAM:            .equ    GAME_STATE + 17
OD_FX:              .equ    GAME_STATE + 20
OD_FY:              .equ    GAME_STATE + 21
OD_FLASH:           .equ    GAME_STATE + 22     ; 1 hit, 2 gem at the ship
OD_HELD:            .equ    GAME_STATE + 23     ; unused (no held keys)
OD_OLD:             .equ    GAME_STATE + 24
OD_BEFORE:          .equ    GAME_STATE + 25
OD_T:               .equ    GAME_STATE + 26
OD_HIT:             .equ    GAME_STATE + 27
OD_DI:              .equ    GAME_STATE + 28
OD_DX:              .equ    GAME_STATE + 29
OD_DY:              .equ    GAME_STATE + 30
OD_SX:              .equ    GAME_STATE + 31
OD_SY:              .equ    GAME_STATE + 32
OD_AX:              .equ    GAME_STATE + 33
OD_AY:              .equ    GAME_STATE + 34
OD_STROKE:          .equ    GAME_STATE + 35
OD_DCODE:           .equ    GAME_STATE + 36
OD_TX:              .equ    GAME_STATE + 37
OD_TY:              .equ    GAME_STATE + 38

OD_TILE_DOT:        .equ    0x80
OD_TILE_GEM:        .equ    0x84
OD_TILE_TARGET:     .equ    0x88
OD_TILE_SHIP:       .equ    0x8c
OD_TILE_PLANET:     .equ    0x90
OD_CHAR_V:          .equ    0x94
OD_CHAR_H:          .equ    0x95
OD_CHAR_FALL:       .equ    0x96
OD_CHAR_RISE:       .equ    0x97
OD_CHAR_TIP:        .equ    0x98
OD_ATTR_DOT:        .equ    0x45
OD_ATTR_GEM:        .equ    0x46
OD_ATTR_TARGET:     .equ    0x43
OD_ATTR_TARGET_HOT: .equ    0x7a        ; red on white: fires next tick
OD_ATTR_SHIP:       .equ    0x47
OD_ATTR_PLANET:     .equ    0x44
OD_ATTR_BEAM:       .equ    0x42
OD_ATTR_HIT:        .equ    0x72        ; red on yellow
OD_ATTR_SPARK:      .equ    0x6d        ; cyan on green
OD_ATTR_TEXT:       .equ    0x07
OD_ATTR_LABEL:      .equ    0x04
OD_ATTR_TITLE:      .equ    0x06
OD_ATTR_DIM:        .equ    0x05
OD_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     od_patterns
        LDAA    OD_TILE_DOT
        LDAB    25
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    3
        STAA    [OD_HP]
        STAA    [OD_TARGET]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ADDA    12
        STAA    [OD_LIMIT]
        LDAB    5
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     od_init_window
        LDAB    4
od_init_window:
        STAB    [OD_WINDOW]

; target = (target * 5 + 3 + level * 2) % 8, ring = (waves + level) % 2,
; other = (target + 3 + waves % 3) % 8, dual from wave 5 or sector 3,
; gem = (target + 1 + waves % 2) % 8 on the target's ring.
od_next_wave:
        LDAA    [OD_TARGET]
        ASLA
        ASLA
        ADDA    [OD_TARGET]
        ADDA    3
        ADDA    [JR_PORT_LEVEL]
        ADDA    [JR_PORT_LEVEL]
        ANDA    7
        STAA    [OD_TARGET]
        LDAA    [OD_WAVES]
        ADDA    [JR_PORT_LEVEL]
        ANDA    1
        STAA    [OD_RING]
        STAA    [OD_GEM_RING]
        LDAA    [OD_WAVES]
od_next_mod3:
        CMPA    3
        BCS     od_next_other
        SUBA    3
        BRA     od_next_mod3
od_next_other:
        ADDA    [OD_TARGET]
        ADDA    3
        ANDA    7
        STAA    [OD_OTHER]
        CLRB
        LDAA    [OD_WAVES]
        CMPA    4
        BCC     od_next_dual
        LDAA    [JR_PORT_LEVEL]
        CMPA    2
        BCS     od_next_single
od_next_dual:
        INCB
od_next_single:
        STAB    [OD_DUAL]
        LDAA    [OD_WAVES]
        ANDA    1
        ADDA    [OD_TARGET]
        INCA
        ANDA    7
        STAA    [OD_GEM]
        CLR     [OD_AGE]
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        LDAB    [OD_POS]
        STAB    [OD_OLD]
        LDAB    [OD_ORBIT]
        STAB    [OD_BEFORE]
        CMPA    JR_KEY_LEFT
        BEQ     od_act_back
        CMPA    JR_KEY_UP
        BNE     od_act_forward
od_act_back:
        LDAA    [OD_POS]
        ADDA    7
        BRA     od_act_pos
od_act_forward:
        CMPA    JR_KEY_RIGHT
        BEQ     od_act_on
        CMPA    JR_KEY_DOWN
        BNE     od_act_switch
od_act_on:
        LDAA    [OD_POS]
        INCA
od_act_pos:
        ANDA    7
        STAA    [OD_POS]
        BRA     od_act_moved
od_act_switch:
        CMPA    JR_KEY_CONFIRM
        BNE     od_act_done
        LDAA    [OD_ORBIT]
        EORA    1
        STAA    [OD_ORBIT]
od_act_moved:
        ; fly half-way between the old and the new place
        LDAA    [OD_POS]
        CMPA    [OD_OLD]
        BNE     od_act_fly
        LDAA    [OD_ORBIT]
        CMPA    [OD_BEFORE]
        BEQ     od_act_done
od_act_fly:
        LDAA    1
        STAA    [OD_TRAVEL]
        CLRA
        JSR     jr_port_sound
        LDAA    [OD_OLD]
        LDAB    [OD_BEFORE]
        JSR     od_place
        STAA    [OD_FX]
        STAB    [OD_FY]
        LDAA    [OD_POS]
        LDAB    [OD_ORBIT]
        JSR     od_place
        ADDA    [OD_FX]
        LSRA
        STAA    [OD_FX]
        ADDB    [OD_FY]
        LSRB
        STAB    [OD_FY]
        LDAA    2
        JSR     jr_test_animate
        CLR     [OD_TRAVEL]
od_act_done:
        RTS

; A = position, B = ring -> A = x, B = y of its tile.
od_place:
        ASLB
        ASLB
        ASLB
        ABA
        STAA    [OD_T]
        LDX     od_ring_y
        JSR     jr_add_x_a
        LDAB    [X]
        LDX     od_ring_x
        LDAA    [OD_T]
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     od_act_done
        INC     [OD_AGE]
        LDAA    [OD_AGE]
        CMPA    [OD_WINDOW]
        BCS     od_act_done
        ; the beams fire: they grow 5, 10 and 15 steps
        LDAA    1
        STAA    [OD_FIRING]
        LDX     od_sfx_fire
        JSR     jr_sfx_play
        LDAA    5
od_tick_beam:
        STAA    [OD_BEAM]
        LDAA    3
        JSR     jr_test_animate
        LDAA    [OD_BEAM]
        ADDA    5
        CMPA    20
        BNE     od_tick_beam
        LDAA    15
        STAA    [OD_BEAM]
        ; hit on the target (same ring) or on the other target (other ring)
        CLR     [OD_HIT]
        LDAA    [OD_ORBIT]
        CMPA    [OD_RING]
        BNE     od_tick_other
        LDAA    [OD_POS]
        CMPA    [OD_TARGET]
        BNE     od_tick_gem
        INC     [OD_HIT]
        BRA     od_tick_gem
od_tick_other:
        TST     [OD_DUAL]
        BEQ     od_tick_gem
        LDAA    [OD_POS]
        CMPA    [OD_OTHER]
        BNE     od_tick_gem
        INC     [OD_HIT]
od_tick_gem:
        TST     [OD_HIT]
        BEQ     od_tick_collect
        DEC     [OD_HP]
        CLR     [OD_CHAIN]
        LDAA    1
        STAA    [OD_FLASH]
        LDX     od_sfx_hit
        JSR     jr_sfx_play
        BRA     od_tick_flash
od_tick_collect:
        LDAA    [OD_ORBIT]
        CMPA    [OD_GEM_RING]
        BNE     od_tick_nothing
        LDAA    [OD_POS]
        CMPA    [OD_GEM]
        BNE     od_tick_nothing
        LDAA    [OD_CHAIN]
        CMPA    3
        BCC     od_tick_chain
        INC     [OD_CHAIN]
od_tick_chain:
        LDAA    [OD_SCORE]
        ADDA    [OD_CHAIN]
        STAA    [OD_SCORE]
        LDAA    2
        STAA    [OD_FLASH]
        LDAA    1
        JSR     jr_port_sound
od_tick_flash:
        LDAA    6
        JSR     jr_test_animate
        CLR     [OD_FLASH]
        BRA     od_tick_wave
od_tick_nothing:
        CLR     [OD_CHAIN]
od_tick_wave:
        CLR     [OD_FIRING]
        INC     [OD_WAVES]
        TST     [OD_HP]
        BNE     od_tick_limit
        LDX     od_txt_loss
        JMP     jr_port_lose
od_tick_limit:
        LDAA    [OD_WAVES]
        CMPA    [OD_LIMIT]
        BCS     od_tick_next
        JMP     jr_port_win
od_tick_next:
        JMP     od_next_wave

; ---------------------------------------------------------------- drawing

; A = position, B = ring, [JR_RT_COLOR] set, [OD_DCODE] = tile.
od_put:
        JSR     od_place
        JSR     jr_gfx_at
        LDAA    [OD_DCODE]
        JMP     jr_gfx_tile

; A = position, B = ring: a beam of OD_BEAM steps from (15, 10) toward it.
od_draw_ray:
        JSR     od_place
        STAA    [OD_TX]
        STAB    [OD_TY]
        ; stroke: | on the axis, - on the horizon, else \ or /
        LDAB    OD_CHAR_V
        CMPA    15
        BEQ     od_draw_ray_stroke
        LDAB    OD_CHAR_H
        LDAA    [OD_TY]
        CMPA    10
        BEQ     od_draw_ray_stroke
        CLRA
        LDAB    [OD_TX]
        CMPB    15
        BCS     od_draw_ray_west
        INCA
od_draw_ray_west:
        LDAB    [OD_TY]
        CMPB    10
        BCS     od_draw_ray_north
        EORA    1
od_draw_ray_north:
        LDAB    OD_CHAR_FALL
        TSTA
        BEQ     od_draw_ray_stroke
        LDAB    OD_CHAR_RISE
od_draw_ray_stroke:
        STAB    [OD_STROKE]
        ; |dx|, |dy| and their signs
        CLR     [OD_SX]
        LDAA    [OD_TX]
        SUBA    15
        BCC     od_draw_ray_dx
        NEGA
        INC     [OD_SX]
od_draw_ray_dx:
        STAA    [OD_DX]
        CLR     [OD_SY]
        LDAA    [OD_TY]
        SUBA    10
        BCC     od_draw_ray_dy
        NEGA
        INC     [OD_SY]
od_draw_ray_dy:
        STAA    [OD_DY]
        CLR     [OD_AX]
        CLR     [OD_AY]
        CLR     [OD_DI]
od_draw_ray_step:
        LDAA    [OD_AX]
        JSR     od_div14
        TST     [OD_SX]
        BEQ     od_draw_ray_x
        NEGA
od_draw_ray_x:
        ADDA    15
        STAA    [OD_T]
        LDAA    [OD_AY]
        JSR     od_div14
        TST     [OD_SY]
        BEQ     od_draw_ray_y
        NEGA
od_draw_ray_y:
        ADDA    10
        TAB
        LDAA    [OD_T]
        JSR     jr_gfx_at
        LDAA    [OD_STROKE]
        LDAB    [OD_DI]
        INCB
        CMPB    [OD_BEAM]
        BNE     od_draw_ray_char
        LDAA    OD_CHAR_TIP
od_draw_ray_char:
        JSR     jr_gfx_putc
        LDAA    [OD_AX]
        ADDA    [OD_DX]
        STAA    [OD_AX]
        LDAA    [OD_AY]
        ADDA    [OD_DY]
        STAA    [OD_AY]
        INC     [OD_DI]
        LDAA    [OD_DI]
        CMPA    [OD_BEAM]
        BNE     od_draw_ray_step
        RTS

; A -> A / 14.
od_div14:
        CLRB
od_div14_next:
        CMPA    14
        BCS     od_div14_done
        SUBA    14
        INCB
        BRA     od_div14_next
od_div14_done:
        TBA
        RTS

game_draw:
        LDAA    0x20
        LDAB    OD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     od_hud
        JSR     jr_gfx_lines
        LDAA    OD_ATTR_PLANET
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    10
        JSR     jr_gfx_at
        LDAA    OD_TILE_PLANET
        JSR     jr_gfx_tile
        ; both orbits
        LDAA    OD_ATTR_DOT
        STAA    [JR_RT_COLOR]
        LDAA    OD_TILE_DOT
        STAA    [OD_DCODE]
        CLR     [OD_DI]
od_draw_dot:
        LDAA    [OD_DI]
        ANDA    7
        LDAB    [OD_DI]
        LSRB
        LSRB
        LSRB
        JSR     od_put
        INC     [OD_DI]
        LDAA    [OD_DI]
        CMPA    16
        BNE     od_draw_dot
        LDAA    OD_ATTR_GEM
        STAA    [JR_RT_COLOR]
        LDAA    OD_TILE_GEM
        STAA    [OD_DCODE]
        LDAA    [OD_GEM]
        LDAB    [OD_GEM_RING]
        JSR     od_put
        ; targets: hot when they fire on the next tick
        LDAA    OD_ATTR_TARGET
        LDAB    [OD_AGE]
        INCB
        CMPB    [OD_WINDOW]
        BCS     od_draw_target
        LDAA    OD_ATTR_TARGET_HOT
od_draw_target:
        STAA    [JR_RT_COLOR]
        LDAA    OD_TILE_TARGET
        STAA    [OD_DCODE]
        LDAA    [OD_TARGET]
        LDAB    [OD_RING]
        JSR     od_put
        TST     [OD_DUAL]
        BEQ     od_draw_beams
        LDAB    [OD_RING]
        EORB    1
        LDAA    [OD_OTHER]
        JSR     od_put
od_draw_beams:
        TST     [OD_FIRING]
        BEQ     od_draw_ship
        LDAA    OD_ATTR_BEAM
        STAA    [JR_RT_COLOR]
        LDAA    [OD_TARGET]
        LDAB    [OD_RING]
        JSR     od_draw_ray
        TST     [OD_DUAL]
        BEQ     od_draw_ship
        LDAB    [OD_RING]
        EORB    1
        LDAA    [OD_OTHER]
        JSR     od_draw_ray
od_draw_ship:
        LDAA    OD_ATTR_SHIP
        LDAB    [OD_FLASH]
        BEQ     od_draw_ship_colour
        LDAA    OD_ATTR_HIT
        CMPB    1
        BEQ     od_draw_ship_colour
        LDAA    OD_ATTR_SPARK
od_draw_ship_colour:
        STAA    [JR_RT_COLOR]
        LDAA    OD_TILE_SHIP
        STAA    [OD_DCODE]
        TST     [OD_TRAVEL]
        BEQ     od_draw_ship_at
        LDAA    [OD_FX]
        LDAB    [OD_FY]
        JSR     jr_gfx_at
        LDAA    OD_TILE_SHIP
        JSR     jr_gfx_tile
        BRA     od_draw_panel
od_draw_ship_at:
        LDAA    [OD_POS]
        LDAB    [OD_ORBIT]
        JSR     od_put
od_draw_panel:
        LDAA    OD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [OD_HP]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    29
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [OD_AGE]
        CMPA    [OD_WINDOW]
        BCS     od_draw_impact
        LDAA    [OD_WINDOW]
od_draw_impact:
        NEGA
        ADDA    [OD_WINDOW]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    6
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [OD_WAVES]
        JSR     jr_gfx_dec2
        LDAA    9
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [OD_LIMIT]
        JSR     jr_gfx_dec2
        LDAA    19
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [OD_SCORE]
        JSR     jr_gfx_dec3
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BNE     od_draw_demo
        LDAA    OD_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDX     od_txt_secured
        LDAA    [OD_SCORE]
        CMPA    [OD_LIMIT]
        BCS     od_draw_result
        LDX     od_txt_gold
od_draw_result:
        JSR     jr_gfx_text
od_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     od_draw_done
        LDAA    OD_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     od_txt_demo
        JSR     jr_gfx_text
od_draw_done:
        RTS

game_draw_title:
        LDX     od_title_song
        JSR     jr_music_play
game_test_draw:
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

; x, attribute, code, y
od_title_tiles:
        .db     9, OD_ATTR_SHIP, OD_TILE_SHIP, 3
        .db     12, OD_ATTR_DOT, OD_TILE_DOT, 3
        .db     15, OD_ATTR_PLANET, OD_TILE_PLANET, 3
        .db     18, OD_ATTR_TARGET_HOT, OD_TILE_TARGET, 3
        .db     21, OD_ATTR_GEM, OD_TILE_GEM, 3
        .db     0xff

od_hud:
        .db     1, 0, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     0, 2, OD_ATTR_LABEL
        .dw     od_txt_hull
        .db     21, 2, OD_ATTR_LABEL
        .dw     od_txt_impact
        .db     1, 20, OD_ATTR_LABEL
        .dw     od_txt_wave
        .db     0xff
od_title_lines:
        .db     10, 8, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     3, 10, OD_ATTR_LABEL
        .dw     od_txt_tagline
        .db     4, 13, OD_ATTR_TEXT
        .dw     od_txt_start
        .db     4, 15, OD_ATTR_TEXT
        .dw     od_txt_howto
        .db     4, 17, OD_ATTR_DIM
        .dw     od_txt_demo_hint
        .db     4, 19, OD_ATTR_DIM
        .dw     od_txt_credit
        .db     0xff
od_help_lines:
        .db     10, 1, OD_ATTR_TITLE
        .dw     od_txt_name
        .db     1, 3, OD_ATTR_TEXT
        .dw     od_help_1
        .db     1, 5, OD_ATTR_TEXT
        .dw     od_help_2
        .db     1, 7, OD_ATTR_TEXT
        .dw     od_help_3
        .db     1, 9, OD_ATTR_TEXT
        .dw     od_help_4
        .db     1, 11, OD_ATTR_TEXT
        .dw     od_help_5
        .db     1, 13, OD_ATTR_TEXT
        .dw     od_help_6
        .db     1, 15, OD_ATTR_TEXT
        .dw     od_help_7
        .db     1, 17, OD_ATTR_TEXT
        .dw     od_help_8
        .db     1, 21, OD_ATTR_LABEL
        .dw     od_help_back
        .db     0xff

od_txt_name:
        .db     "ORBIT DODGE", 0
od_txt_hull:
        .db     "HULL", 0
od_txt_impact:
        .db     "IMPACT", 0
od_txt_wave:
        .db     "WAVE   /    ENERGY", 0
od_txt_gold:
        .db     "GOLD ORBIT", 0
od_txt_secured:
        .db     "ORBIT SECURED", 0
od_txt_demo:
        .db     "DEMO", 0
od_txt_loss:
        .db     "STRUCK BY AN ORBITAL BEAM", 0
od_txt_tagline:
        .db     "CIRCLE, SWITCH, DODGE BEAMS", 0
od_txt_start:
        .db     "RETURN : START", 0
od_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
od_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
od_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
od_help_1:
        .db     "A/D OR W/S : MOVE AROUND ORBIT", 0
od_help_2:
        .db     "RETURN : CHANGE INNER / OUTER", 0
od_help_3:
        .db     "FLASHING TARGETS WILL BE HIT.", 0
od_help_4:
        .db     "COLLECT GEMS AT IMPACT TIME.", 0
od_help_5:
        .db     "CONSECUTIVE GEMS PAY UP TO +3.", 0
od_help_6:
        .db     "ENERGY >= WAVES EARNS GOLD.", 0
od_help_7:
        .db     "SIX SECTORS / THREE HULL EACH.", 0
od_help_8:
        .db     "SPACE : RETRY THE SECTOR", 0
od_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     od_sfx_move, od_sfx_gem, od_jingle_win, od_jingle_lose
od_sfx_move:
        .db     100, 1, 0, 0
od_sfx_gem:
        .db     36, 2, 30, 2, 24, 2, 18, 6, 0, 0
od_sfx_fire:
        .db     20, 1, 30, 1, 40, 1, 50, 1, 60, 1, 70, 1, 0, 0
od_sfx_hit:
        .db     200, 2, 150, 2, 250, 8, 0, 0

; Title: a floating theme in F major, eighth note = 8 frames, looping.
od_title_song:
        .db     1
        .dw     od_title_melody, od_title_harmony, od_title_bass
od_title_melody:
        .db     AU_C5, 8, AU_F5, 8, AU_A5, 8, AU_C6, 8, AU_AS5, 16, AU_A5, 16
        .db     AU_G5, 8, AU_A5, 8, AU_AS5, 8, AU_G5, 8, AU_F5, 32
        .db     AU_D5, 8, AU_F5, 8, AU_AS5, 8, AU_D6, 8, AU_C6, 16, AU_AS5, 16
        .db     AU_A5, 8, AU_G5, 8, AU_E5, 8, AU_G5, 8, AU_F5, 32, 0, 0
od_title_harmony:
        .db     AU_A4, 32, AU_C5, 32, AU_AS4, 32, AU_A4, 32
        .db     AU_AS4, 32, AU_F5, 32, AU_C5, 32, AU_A4, 32, 0, 0
od_title_bass:
        .db     AU_F2, 32, AU_A2, 32, AU_C3, 32, AU_F2, 32
        .db     AU_AS2, 32, AU_D3, 32, AU_C3, 32, AU_F2, 32, 0, 0

; Sector secured: F major arpeggio.
od_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     od_win_melody, od_win_harmony, od_win_bass
od_win_melody:
        .db     AU_C5, 6, AU_F5, 6, AU_A5, 6, AU_C6, 12, AU_F6, 30, 0, 0
od_win_harmony:
        .db     AU_A4, 12, AU_C5, 18, AU_A5, 30, 0, 0
od_win_bass:
        .db     AU_F3, 12, AU_C3, 18, AU_F2, 30, 0, 0
od_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     od_lose_melody, od_lose_harmony, od_lose_bass
od_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
od_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
od_lose_bass:
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

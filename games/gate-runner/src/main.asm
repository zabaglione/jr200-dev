; SPDX-License-Identifier: MIT
; GATE RUNNER for JR-200: a port of jr100dev games/gate_runner/rules.py 3.0.0.
; Six courses of gates (walls, pits and low beams, from the upstream
; game.json tables, mirrored on the even courses), stepping and running with
; A/D held, the jump arc, crystals on the risky side, three hits and the
; gold / silver / bronze result follow the upstream source, one upstream tick
; per game_tick. Held A/D comes from the keyboard MCU scan (sdk/keyscan.inc).
; The road is this port's own drawing from the upstream width and floor
; tables (upstream scene.asm is not used). Rules are
; checked by the in-program self test (sdk/selftest.inc, title key T); P
; plays the course-1 demo.
        .filename.jr "GATE-RUNNER"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46a0
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream runs every 6 frames; one tick here is GAME_RATE idle frames plus
; the render and the key scan (see README).
GAME_RATE:          .equ    1
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    38
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    GR_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
GR_X:               .equ    GAME_STATE
GR_HP:              .equ    GAME_STATE + 1
GR_LIMIT:           .equ    GAME_STATE + 2
GR_SPEED:           .equ    GAME_STATE + 3
GR_RATE:            .equ    GAME_STATE + 4
GR_AIR:             .equ    GAME_STATE + 5
GR_CLOCK:           .equ    GAME_STATE + 6
GR_NOTICE_TIME:     .equ    GAME_STATE + 7
GR_PACE:            .equ    GAME_STATE + 8
GR_AGE:             .equ    GAME_STATE + 9
GR_HIT:             .equ    GAME_STATE + 10
GR_NOTICE:          .equ    GAME_STATE + 11
GR_GATES:           .equ    GAME_STATE + 12
GR_COINS:           .equ    GAME_STATE + 13
GR_B:               .equ    GAME_STATE + 14     ; gates (24)
GR_HELD:            .equ    GAME_STATE + 40     ; direction held (0, 3, 4)
GR_FLASH:           .equ    GAME_STATE + 41     ; 1 hit, 2 crystal
GR_T:               .equ    GAME_STATE + 42
GR_U:               .equ    GAME_STATE + 43
GR_H:               .equ    GAME_STATE + 44
GR_SLOT:            .equ    GAME_STATE + 45
GR_C0:              .equ    GAME_STATE + 46
GR_DEPTH:           .equ    GAME_STATE + 48
GR_HALF:            .equ    GAME_STATE + 49
GR_GROUND:          .equ    GAME_STATE + 50
GR_HEIGHT:          .equ    GAME_STATE + 51
GR_LEFT:            .equ    GAME_STATE + 52
GR_RIGHT:           .equ    GAME_STATE + 53
GR_KIND:            .equ    GAME_STATE + 54
GR_OBJ:             .equ    GAME_STATE + 55
GR_DI:              .equ    GAME_STATE + 56
GR_DT:              .equ    GAME_STATE + 57
GR_DCODE:           .equ    GAME_STATE + 58
GR_ROW:             .equ    GAME_STATE + 59
GR_STRIPE:          .equ    GAME_STATE + 60
GR_PQ:              .equ    GAME_STATE + 61

GR_CHAR_EDGE_L:     .equ    0x80
GR_CHAR_EDGE_R:     .equ    0x81
GR_CHAR_STRIPE:     .equ    0x82
GR_CHAR_WALL:       .equ    0x83
GR_CHAR_PIT:        .equ    0x84
GR_CHAR_BEAM:       .equ    0x85
GR_CHAR_JEWEL:      .equ    0x86
GR_CHAR_SHADOW:     .equ    0x87
GR_TILE_RUNNER:     .equ    0x88        ; + 4 per pose (stride, stride, jump)
GR_ATTR_EDGE:       .equ    0x47
GR_ATTR_STRIPE:     .equ    0x45
GR_ATTR_WALL:       .equ    0x42
GR_ATTR_PIT:        .equ    0x48        ; black on blue
GR_ATTR_BEAM:       .equ    0x43
GR_ATTR_JEWEL:      .equ    0x45
GR_ATTR_RUNNER:     .equ    0x47
GR_ATTR_SHADOW:     .equ    0x41
GR_ATTR_HIT:        .equ    0x72        ; red on yellow
GR_ATTR_SPARK:      .equ    0x6d        ; cyan on green
GR_ATTR_TEXT:       .equ    0x07
GR_ATTR_LABEL:      .equ    0x04
GR_ATTR_TITLE:      .equ    0x06
GR_ATTR_DIM:        .equ    0x05
GR_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_keyscan_init
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     gr_patterns
        LDAA    GR_CHAR_EDGE_L
        LDAB    20
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    15
        STAA    [GR_X]
        LDAA    3
        STAA    [GR_HP]
        LDAA    12
        TST     [JR_PORT_LEVEL]
        BNE     gr_init_limit
        LDAA    9
gr_init_limit:
        STAA    [GR_LIMIT]
        LDAA    1
        STAA    [GR_SPEED]
        LDAA    [JR_PORT_LEVEL]
        LSRA
        NEGA
        ADDA    6
        STAA    [GR_RATE]
        CLRA
        CLRB
        JSR     gr_load_gate
        LDAA    1
        LDAB    16
        JMP     gr_load_gate

; A = event, B = slot: gate (event + level * 2) % 12 from the tables, mirrored
; round column 16 on the even courses (odd level indices).
gr_load_gate:
        STAB    [GR_SLOT]
        ADDA    [JR_PORT_LEVEL]
        ADDA    [JR_PORT_LEVEL]
gr_load_mod:
        CMPA    12
        BCS     gr_load_row
        SUBA    12
        BRA     gr_load_mod
gr_load_row:
        ASLA
        ASLA
        ASLA
        LDX     gr_gate_table
        JSR     jr_add_x_a
        STX     [GR_C0]
        CLR     [GR_T]
gr_load_copy:
        LDX     [GR_C0]
        LDAA    [GR_T]
        JSR     jr_add_x_a
        LDAB    [X]
        LDX     GR_B
        LDAA    [GR_SLOT]
        ADDA    [GR_T]
        JSR     jr_add_x_a
        STAB    [X]
        INC     [GR_T]
        LDAA    [GR_T]
        CMPA    8
        BNE     gr_load_copy
        LDAA    [JR_PORT_LEVEL]
        ANDA    1
        BEQ     gr_act_done
        LDX     GR_B
        LDAA    [GR_SLOT]
        JSR     jr_add_x_a
        JSR     gr_mirror
        INX
        INX
        INX
        JSR     gr_mirror
        LDAA    30
        SUBA    [X + 3]
        STAA    [X + 3]
        RTS

; X = a gate part: (left, right) at +1, +2 become (32 - right, 32 - left).
gr_mirror:
        LDAA    32
        SUBA    [X + 2]
        LDAB    32
        SUBB    [X + 1]
        STAA    [X + 1]
        STAB    [X + 2]
        RTS

; A = action: one step for A (3) or D (4), inside columns 2-28.
gr_shift:
        LDAB    [GR_X]
        CMPA    JR_KEY_LEFT
        BNE     gr_shift_right
        CMPB    3
        BCS     gr_act_done
        DEC     [GR_X]
        RTS
gr_shift_right:
        CMPA    JR_KEY_RIGHT
        BNE     gr_act_done
        CMPB    28
        BCC     gr_act_done
        INC     [GR_X]
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        PSHA
        JSR     gr_shift
        PULA
        CMPA    JR_KEY_UP
        BEQ     gr_act_jump
        CMPA    JR_KEY_CONFIRM
        BNE     gr_act_done
gr_act_jump:
        TST     [GR_AIR]
        BNE     gr_act_done
        LDAA    8
        STAA    [GR_AIR]
        CLRA
        JMP     jr_port_sound
gr_act_done:
        RTS

; -> A = heights[air].
gr_lift:
        LDX     gr_heights
        LDAA    [GR_AIR]
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; A = part offset (0 or 3) in the current gate -> A = the kind it hits (0 none).
gr_collides:
        LDX     GR_B
        JSR     jr_add_x_a
        LDAA    [GR_X]
        ADDA    2
        CMPA    [X + 1]
        BLS     gr_collides_none
        LDAA    [GR_X]
        CMPA    [X + 2]
        BCC     gr_collides_none
        LDAB    [X]
        STX     [GR_C0]
        JSR     gr_lift
        CMPB    1
        BEQ     gr_collides_kind
        CMPB    2
        BNE     gr_collides_beam
        CMPA    2
        BCS     gr_collides_kind
        BRA     gr_collides_none
gr_collides_beam:
        CMPB    3
        BNE     gr_collides_none
        CMPA    2
        BCC     gr_collides_kind
gr_collides_none:
        CLRB
gr_collides_kind:
        TBA
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     gr_act_done
        TST     [JR_TEST_QUIET]
        BNE     gr_tick_rules
        LDAA    [JR_TEST_DEMO]
        CMPA    2
        BEQ     gr_tick_rules
        ; held A/D from the MCU scan
        JSR     jr_keyscan
        CLRB
        ORAA    0x20
        CMPA    0x61
        BNE     gr_tick_scan_right
        LDAB    JR_KEY_LEFT
gr_tick_scan_right:
        CMPA    0x64
        BNE     gr_tick_scan_store
        LDAB    JR_KEY_RIGHT
gr_tick_scan_store:
        STAB    [GR_HELD]
gr_tick_rules:
        INC     [GR_CLOCK]
        TST     [GR_NOTICE_TIME]
        BEQ     gr_tick_shift
        DEC     [GR_NOTICE_TIME]
gr_tick_shift:
        LDAA    [GR_HELD]
        JSR     gr_shift
        TST     [GR_AIR]
        BEQ     gr_tick_pace
        DEC     [GR_AIR]
gr_tick_pace:
        INC     [GR_PACE]
        LDAA    [GR_PACE]
        CMPA    [GR_SPEED]
        BCC     gr_act_done_near318
        JMP     gr_act_done
gr_act_done_near318:
        CLR     [GR_PACE]
        INC     [GR_AGE]
        LDAA    [GR_AGE]
        CMPA    20
        BNE     gr_tick_reach
        ; the next two gates come up
        CLR     [GR_AGE]
        LDAA    [GR_GATES]
        CLRB
        JSR     gr_load_gate
        LDAA    [GR_GATES]
        INCA
        LDAB    16
        JMP     gr_load_gate
gr_tick_reach:
        CMPA    18
        BEQ     gr_act_done_near337
        JMP     gr_act_done
gr_act_done_near337:
        ; the gate reaches the runner
        CLRA
        JSR     gr_collides
        STAA    [GR_T]
        LDAA    3
        JSR     gr_collides
        CMPA    [GR_T]
        BCC     gr_tick_hit
        LDAA    [GR_T]
gr_tick_hit:
        STAA    [GR_HIT]
        TSTA
        BEQ     gr_tick_crystal
        DEC     [GR_HP]
        STAA    [GR_NOTICE]
        LDAA    18
        STAA    [GR_NOTICE_TIME]
        LDX     gr_sfx_crash
        JSR     jr_sfx_play
        LDAA    1
        STAA    [GR_FLASH]
        LDAA    15
        JSR     jr_test_animate
        CLR     [GR_FLASH]
        TST     [GR_HP]
        BNE     gr_tick_passed
        LDAA    [GR_HIT]
        LDX     gr_txt_wall
        CMPA    1
        BEQ     gr_tick_lose
        LDX     gr_txt_pit
        CMPA    2
        BEQ     gr_tick_lose
        LDX     gr_txt_beam
gr_tick_lose:
        JMP     jr_port_lose
gr_tick_crystal:
        ; a crystal within one column, on the ground or in the air as placed
        LDAA    [GR_X]
        SUBA    [GR_B + 6]
        BCC     gr_tick_delta
        NEGA
gr_tick_delta:
        CMPA    2
        BCC     gr_tick_pass
        JSR     gr_lift
        CLRB
        CMPA    2
        BCS     gr_tick_air
        INCB
gr_tick_air:
        CMPB    [GR_B + 7]
        BNE     gr_tick_pass
        INC     [GR_COINS]
        LDAA    4
        STAA    [GR_NOTICE]
        LDAA    12
        STAA    [GR_NOTICE_TIME]
        LDAA    1
        JSR     jr_port_sound
        LDAA    2
        STAA    [GR_FLASH]
        LDAA    6
        JSR     jr_test_animate
        CLR     [GR_FLASH]
        BRA     gr_tick_passed
gr_tick_pass:
        LDX     gr_sfx_pass
        JSR     jr_sfx_play
gr_tick_passed:
        INC     [GR_GATES]
        LDAA    [GR_GATES]
        CMPA    [GR_LIMIT]
        BEQ     gr_act_done_near413
        JMP     gr_act_done
gr_act_done_near413:
        JMP     jr_port_win

; ---------------------------------------------------------------- drawing

; A = world column, [GR_HALF] = half width at the depth -> A = screen column.
gr_project:
        CLR     [GR_PQ]
        CMPA    16
        BCC     gr_project_right
        NEGA
        ADDA    16
        INC     [GR_PQ]
        BRA     gr_project_scale
gr_project_right:
        SUBA    16
gr_project_scale:
        ; (distance * half) / 14
        STAA    [GR_U]
        CLRA
        LDAB    [GR_HALF]
        BEQ     gr_project_div
gr_project_mul:
        ADDA    [GR_U]
        DECB
        BNE     gr_project_mul
gr_project_div:
        CLRB
gr_project_div_next:
        CMPA    14
        BCS     gr_project_done
        SUBA    14
        INCB
        BRA     gr_project_div_next
gr_project_done:
        TBA
        TST     [GR_PQ]
        BEQ     gr_project_add
        NEGA
gr_project_add:
        ADDA    16
        RTS

; A = depth -> GR_HALF, GR_HEIGHT (half / 4 + 1) and GR_GROUND.
gr_camera:
        STAA    [GR_DEPTH]
        LDX     gr_widths
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [GR_HALF]
        LSRA
        LSRA
        INCA
        STAA    [GR_HEIGHT]
        LDX     gr_floors
        LDAA    [GR_DEPTH]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [GR_GROUND]
        RTS

; A = code, [JR_RT_COLOR]: a row of it on GR_GROUND from 16 - half, 2 * half long.
gr_road_line:
        STAA    [GR_DCODE]
        LDAA    16
        SUBA    [GR_HALF]
        LDAB    [GR_GROUND]
        JSR     jr_gfx_at
        LDAB    [GR_HALF]
        ASLB
gr_road_line_next:
        LDAA    [GR_DCODE]
        JSR     jr_gfx_putc
        DECB
        BNE     gr_road_line_next
        RTS

; A = code, B = row, [JR_RT_COLOR]: GR_LEFT .. GR_RIGHT - 1 (at least one cell).
gr_span:
        STAA    [GR_DCODE]
        LDAA    [GR_LEFT]
        JSR     jr_gfx_at
        LDAB    [GR_RIGHT]
        SUBB    [GR_LEFT]
        BHI     gr_span_next
        LDAB    1
gr_span_next:
        LDAA    [GR_DCODE]
        JSR     jr_gfx_putc
        DECB
        BNE     gr_span_next
        RTS

; GR_DEPTH set by gr_camera, GR_SLOT = 0 or 16: draw the gate there.
gr_gate:
        CLR     [GR_OBJ]
gr_gate_part:
        LDX     GR_B
        LDAA    [GR_SLOT]
        ADDA    [GR_OBJ]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     gr_gate_next
        STAA    [GR_KIND]
        LDAA    [X + 2]
        STAA    [GR_T]
        LDAA    [X + 1]
        JSR     gr_project
        STAA    [GR_LEFT]
        LDAA    [GR_T]
        JSR     gr_project
        STAA    [GR_RIGHT]
        LDAA    [GR_KIND]
        CMPA    1
        BNE     gr_gate_pit
        ; a wall: HEIGHT rows up to the ground
        LDAA    GR_ATTR_WALL
        STAA    [JR_RT_COLOR]
        LDAA    [GR_GROUND]
        SUBA    [GR_HEIGHT]
        STAA    [GR_ROW]
gr_gate_wall:
        INC     [GR_ROW]
        LDAA    GR_CHAR_WALL
        LDAB    [GR_ROW]
        JSR     gr_span
        LDAA    [GR_ROW]
        CMPA    [GR_GROUND]
        BNE     gr_gate_wall
        BRA     gr_gate_next
gr_gate_pit:
        CMPA    2
        BNE     gr_gate_beam
        LDAA    GR_ATTR_PIT
        STAA    [JR_RT_COLOR]
        LDAA    GR_CHAR_PIT
        LDAB    [GR_GROUND]
        JSR     gr_span
        BRA     gr_gate_next
gr_gate_beam:
        LDAA    GR_ATTR_BEAM
        STAA    [JR_RT_COLOR]
        LDAB    [GR_GROUND]
        SUBB    [GR_HEIGHT]
        LDAA    GR_CHAR_BEAM
        JSR     gr_span
gr_gate_next:
        LDAA    [GR_OBJ]
        ADDA    3
        STAA    [GR_OBJ]
        CMPA    6
        BEQ     gr_gate_part_near566
        JMP     gr_gate_part
gr_gate_part_near566:
        ; the crystal, on the ground or up in the air
        LDX     GR_B
        LDAA    [GR_SLOT]
        JSR     jr_add_x_a
        LDAB    [GR_GROUND]
        TST     [X + 7]
        BEQ     gr_gate_jewel
        SUBB    [GR_HEIGHT]
gr_gate_jewel:
        STAB    [GR_ROW]
        LDAA    [X + 6]
        JSR     gr_project
        LDAB    [GR_ROW]
        JSR     jr_gfx_at
        LDAA    GR_ATTR_JEWEL
        STAA    [JR_RT_COLOR]
        LDAA    GR_CHAR_JEWEL
        JMP     jr_gfx_putc

game_draw:
        LDAA    0x20
        LDAB    GR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gr_hud
        JSR     jr_gfx_lines
        CLR     [GR_DI]
gr_draw_road:
        LDAA    [GR_DI]
        JSR     gr_camera
        LDAA    GR_ATTR_EDGE
        STAA    [JR_RT_COLOR]
        LDAA    15
        SUBA    [GR_HALF]
        LDAB    [GR_GROUND]
        JSR     jr_gfx_at
        LDAA    GR_CHAR_EDGE_L
        JSR     jr_gfx_putc
        LDAA    16
        ADDA    [GR_HALF]
        LDAB    [GR_GROUND]
        JSR     jr_gfx_at
        LDAA    GR_CHAR_EDGE_R
        JSR     jr_gfx_putc
        INC     [GR_DI]
        LDAA    [GR_DI]
        CMPA    20
        BNE     gr_draw_road
        ; three stripes rushing toward the runner
        LDAA    GR_ATTR_STRIPE
        STAA    [JR_RT_COLOR]
        LDAA    [GR_AGE]
        STAA    [GR_STRIPE]
        CLR     [GR_DI]
gr_draw_stripe:
        LDAA    [GR_STRIPE]
        JSR     gr_camera
        LDAA    GR_ATTR_STRIPE
        STAA    [JR_RT_COLOR]
        LDAA    GR_CHAR_STRIPE
        JSR     gr_road_line
        LDAA    [GR_STRIPE]
        ADDA    6
        CMPA    18
        BCS     gr_draw_stripe_depth
        SUBA    18
gr_draw_stripe_depth:
        STAA    [GR_STRIPE]
        INC     [GR_DI]
        LDAA    [GR_DI]
        CMPA    3
        BNE     gr_draw_stripe
        ; the next gate on the horizon, then the gate at hand
        LDAA    [GR_GATES]
        INCA
        CMPA    [GR_LIMIT]
        BCC     gr_draw_current
        CLRA
        JSR     gr_camera
        LDAA    16
        STAA    [GR_SLOT]
        JSR     gr_gate
gr_draw_current:
        LDAA    [GR_AGE]
        JSR     gr_camera
        CLR     [GR_SLOT]
        JSR     gr_gate
        ; the runner and its shadow
        LDAA    GR_ATTR_SHADOW
        STAA    [JR_RT_COLOR]
        LDAA    [GR_X]
        LDAB    20
        JSR     jr_gfx_at
        LDAA    GR_CHAR_SHADOW
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    GR_ATTR_RUNNER
        LDAB    [GR_FLASH]
        BEQ     gr_draw_runner_colour
        LDAA    GR_ATTR_HIT
        CMPB    1
        BEQ     gr_draw_runner_colour
        LDAA    GR_ATTR_SPARK
gr_draw_runner_colour:
        STAA    [JR_RT_COLOR]
        JSR     gr_lift
        NEGA
        ADDA    18
        TAB
        LDAA    [GR_X]
        JSR     jr_gfx_at
        LDAA    GR_TILE_RUNNER + 8
        TST     [GR_AIR]
        BNE     gr_draw_runner
        LDAA    [GR_CLOCK]
        ANDA    1
        ASLA
        ASLA
        ADDA    GR_TILE_RUNNER
gr_draw_runner:
        JSR     jr_gfx_tile
        ; the panel
        LDAA    GR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        ADDA    0x31
        JSR     jr_gfx_putc
        CLR     [GR_DI]
gr_draw_hull:
        LDAA    [GR_DI]
        ASLA
        ADDA    5
        LDAB    1
        JSR     jr_gfx_at
        LDAA    0x2a
        LDAB    [GR_DI]
        CMPB    [GR_HP]
        BCS     gr_draw_hull_mark
        LDAA    0x2d
gr_draw_hull_mark:
        JSR     jr_gfx_putc
        INC     [GR_DI]
        LDAA    [GR_DI]
        CMPA    3
        BNE     gr_draw_hull
        LDAA    7
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [GR_GATES]
        JSR     jr_gfx_dec2
        LDAA    10
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [GR_LIMIT]
        JSR     jr_gfx_dec2
        LDAA    23
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [GR_COINS]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [GR_LIMIT]
        JSR     jr_gfx_dec2
        ; the result or a notice on row 2
        LDAA    GR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BEQ     gr_draw_result
        CMPA    JR_MODE_END
        BNE     gr_draw_notice
gr_draw_result:
        LDX     gr_txt_gold
        LDAA    [GR_LIMIT]
        SUBA    2
        CMPA    [GR_COINS]
        BLS     gr_draw_text
        LDX     gr_txt_silver
        LDAA    [GR_LIMIT]
        INCA
        LSRA
        CMPA    [GR_COINS]
        BLS     gr_draw_text
        LDX     gr_txt_bronze
        BRA     gr_draw_text
gr_draw_notice:
        TST     [GR_NOTICE_TIME]
        BEQ     gr_draw_demo
        LDX     gr_notices - 2
        LDAA    [GR_NOTICE]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
gr_draw_text:
        JSR     jr_gfx_text
gr_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     gr_draw_done
        LDAA    GR_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    14
        CLRB
        JSR     jr_gfx_at
        LDX     gr_txt_demo
        JSR     jr_gfx_text
gr_draw_done:
        RTS

game_draw_title:
        LDX     gr_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    GR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    GR_ATTR_RUNNER
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    2
        JSR     jr_gfx_at
        LDAA    GR_TILE_RUNNER + 8
        JSR     jr_gfx_tile
        LDAA    GR_ATTR_WALL
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    5
        JSR     jr_gfx_at
        LDAB    4
gr_title_wall:
        LDAA    GR_CHAR_WALL
        JSR     jr_gfx_putc
        DECB
        BNE     gr_title_wall
        LDAA    GR_ATTR_JEWEL
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    4
        JSR     jr_gfx_at
        LDAA    GR_CHAR_JEWEL
        JSR     jr_gfx_putc
        LDAA    GR_ATTR_PIT
        STAA    [JR_RT_COLOR]
        LDAA    18
        LDAB    5
        JSR     jr_gfx_at
        LDAB    5
gr_title_pit:
        LDAA    GR_CHAR_PIT
        JSR     jr_gfx_putc
        DECB
        BNE     gr_title_pit
        LDX     gr_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    GR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gr_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; upstream game.json dataTables, one gate per row: kind, left, right, other
; kind, other left, other right, crystal column, crystal in the air
gr_gate_table:
        .db     1, 11, 20, 0, 2, 2, 5, 0
        .db     2, 2, 16, 1, 22, 30, 10, 1
        .db     2, 2, 30, 0, 2, 2, 17, 1
        .db     1, 2, 8, 1, 15, 30, 10, 0
        .db     3, 2, 30, 0, 2, 2, 20, 0
        .db     2, 2, 30, 1, 9, 17, 24, 1
        .db     3, 2, 16, 2, 16, 30, 23, 1
        .db     1, 13, 23, 0, 2, 2, 6, 0
        .db     2, 2, 30, 0, 2, 2, 11, 1
        .db     2, 10, 22, 0, 2, 2, 16, 1
        .db     1, 2, 20, 0, 2, 2, 25, 0
        .db     1, 2, 20, 1, 26, 30, 22, 0
gr_heights:
        .db     0, 0, 1, 2, 3, 3, 2, 1, 0
gr_widths:
        .db     2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 14, 14
gr_floors:
        .db     5, 5, 6, 6, 7, 7, 8, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20

gr_notices:
        .dw     gr_txt_hit_wall, gr_txt_hit_pit, gr_txt_hit_beam, gr_txt_crystal

gr_hud:
        .db     0, 0, GR_ATTR_TITLE
        .dw     gr_txt_name
        .db     23, 0, GR_ATTR_LABEL
        .dw     gr_txt_stage
        .db     0, 1, GR_ATTR_LABEL
        .dw     gr_txt_hull
        .db     1, 22, GR_ATTR_LABEL
        .dw     gr_txt_counts
        .db     0xff
gr_title_lines:
        .db     10, 8, GR_ATTR_TITLE
        .dw     gr_txt_name
        .db     3, 10, GR_ATTR_LABEL
        .dw     gr_txt_tagline
        .db     4, 13, GR_ATTR_TEXT
        .dw     gr_txt_start
        .db     4, 15, GR_ATTR_TEXT
        .dw     gr_txt_howto
        .db     4, 17, GR_ATTR_DIM
        .dw     gr_txt_demo_hint
        .db     4, 19, GR_ATTR_DIM
        .dw     gr_txt_credit
        .db     0xff
gr_help_lines:
        .db     10, 1, GR_ATTR_TITLE
        .dw     gr_txt_name
        .db     1, 3, GR_ATTR_TEXT
        .dw     gr_help_1
        .db     1, 5, GR_ATTR_TEXT
        .dw     gr_help_2
        .db     1, 7, GR_ATTR_TEXT
        .dw     gr_help_3
        .db     1, 9, GR_ATTR_TEXT
        .dw     gr_help_4
        .db     1, 11, GR_ATTR_TEXT
        .dw     gr_help_5
        .db     1, 13, GR_ATTR_TEXT
        .dw     gr_help_6
        .db     1, 15, GR_ATTR_TEXT
        .dw     gr_help_7
        .db     1, 17, GR_ATTR_TEXT
        .dw     gr_help_8
        .db     1, 19, GR_ATTR_TEXT
        .dw     gr_help_9
        .db     1, 21, GR_ATTR_LABEL
        .dw     gr_help_back
        .db     0xff

gr_txt_name:
        .db     "GATE RUNNER", 0
gr_txt_stage:
        .db     "STAGE", 0
gr_txt_hull:
        .db     "HULL", 0
gr_txt_counts:
        .db     "GATES   /    CRYSTALS   /", 0
gr_txt_gold:
        .db     "GOLD RUN", 0
gr_txt_silver:
        .db     "SILVER RUN", 0
gr_txt_bronze:
        .db     "BRONZE RUN", 0
gr_txt_hit_wall:
        .db     "HIT THE WALL!", 0
gr_txt_hit_pit:
        .db     "FELL INTO THE PIT!", 0
gr_txt_hit_beam:
        .db     "HIT THE LOW BEAM!", 0
gr_txt_crystal:
        .db     "CRYSTAL +1", 0
gr_txt_demo:
        .db     "DEMO", 0
gr_txt_wall:
        .db     "HIT THE WALL", 0
gr_txt_pit:
        .db     "FELL INTO THE PIT", 0
gr_txt_beam:
        .db     "JUMPED INTO THE LOW BEAM", 0
gr_txt_tagline:
        .db     "DODGE, JUMP, GRAB CRYSTALS", 0
gr_txt_start:
        .db     "RETURN : START", 0
gr_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
gr_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
gr_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
gr_help_1:
        .db     "A/D: MOVE ONE STEP. HOLD: RUN.", 0
gr_help_2:
        .db     "W/RETURN: JUMP. LAND TO REPEAT.", 0
gr_help_3:
        .db     "WALLS: MOVE AROUND THEM.", 0
gr_help_4:
        .db     "PITS: JUMP. FULL WIDTH TOO!", 0
gr_help_5:
        .db     "LOW BEAMS: STAY ON THE GROUND.", 0
gr_help_6:
        .db     "CRYSTALS: TAKE THE RISKY ROUTE.", 0
gr_help_7:
        .db     "6 COURSES. THREE HITS END RUN.", 0
gr_help_8:
        .db     "GOLD: MISS AT MOST 2 CRYSTALS.", 0
gr_help_9:
        .db     "SPACE : RETRY THE COURSE", 0
gr_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     gr_sfx_jump, gr_sfx_crystal, gr_jingle_win, gr_jingle_lose
gr_sfx_jump:
        .db     80, 1, 60, 1, 45, 2, 0, 0
gr_sfx_crystal:
        .db     24, 2, 20, 2, 16, 6, 0, 0
gr_sfx_pass:
        .db     110, 1, 0, 0
gr_sfx_crash:
        .db     200, 2, 160, 2, 240, 8, 0, 0

; Title: a driving desert theme in D mixolydian, eighth note = 8 frames, looping.
gr_title_song:
        .db     1
        .dw     gr_title_melody, gr_title_harmony, gr_title_bass
gr_title_melody:
        .db     AU_D5, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_C6, 16, AU_A5, 16
        .db     AU_G5, 8, AU_FS5, 8, AU_E5, 8, AU_FS5, 8, AU_D5, 32
        .db     AU_D5, 8, AU_E5, 8, AU_FS5, 8, AU_G5, 8, AU_A5, 16, AU_C6, 16
        .db     AU_B5, 8, AU_A5, 8, AU_G5, 8, AU_E5, 8, AU_D5, 32, 0, 0
gr_title_harmony:
        .db     AU_A4, 32, AU_C5, 32, AU_B4, 32, AU_A4, 32
        .db     AU_B4, 32, AU_E5, 32, AU_D5, 32, AU_FS4, 32, 0, 0
gr_title_bass:
        .db     AU_D3, 8, AU_D3, 8, AU_A2, 8, AU_D3, 8, AU_C3, 8, AU_C3, 8, AU_G2, 8, AU_C3, 8
        .db     AU_G2, 8, AU_G2, 8, AU_A2, 8, AU_A2, 8, AU_D3, 16, AU_D2, 16
        .db     AU_D3, 8, AU_D3, 8, AU_A2, 8, AU_D3, 8, AU_C3, 8, AU_C3, 8, AU_G2, 8, AU_C3, 8
        .db     AU_G2, 8, AU_G2, 8, AU_A2, 8, AU_A2, 8, AU_D3, 32, 0, 0

; Course finished: D major burst.
gr_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     gr_win_melody, gr_win_harmony, gr_win_bass
gr_win_melody:
        .db     AU_A4, 6, AU_D5, 6, AU_FS5, 6, AU_A5, 12, AU_D6, 30, 0, 0
gr_win_harmony:
        .db     AU_FS4, 12, AU_A4, 18, AU_FS5, 30, 0, 0
gr_win_bass:
        .db     AU_D3, 12, AU_A2, 18, AU_D2, 30, 0, 0
gr_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     gr_lose_melody, gr_lose_harmony, gr_lose_bass
gr_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
gr_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
gr_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


        .include "selftest.inc"
        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/keyscan.inc"
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

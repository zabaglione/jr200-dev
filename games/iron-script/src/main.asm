; SPDX-License-Identifier: MIT
; IRON SCRIPT for JR-200: a port of jr100dev games/iron_script/rules.py 2.0.1.
; Twenty-four rooms (upstream levels.json), the twelve-slot program of eight
; commands kept across failed runs, the run stepping one command per tick,
; doors and switches, sentries and armored sentries, lasers that flip after
; each step, the replay-pair command and every stop reason follow the
; upstream source. Rules are checked by the in-program self test
; (sdk/selftest.inc, title key T), which types and runs the upstream
; solutions.json programs; P plays the room-1 demo.
        .filename.jr "IRON-SCRIPT"
        .include "../../../sdk/jr200.inc"

; The program with its 24 rooms and self-test tables needs more than 8K, so
; the work area starts at $4000 (one page above the other ports).
JR_SHADOW:          .equ    0x4000
JR_SAVE:            .equ    0x4600
JR_RT:              .equ    0x5600
GAME_STATE:         .equ    0x5640
GAME_STATE_END:     .equ    0x56c0
JR_AUDIO:           .equ    0x56c0
JR_TEST:            .equ    0x56e0
JR_TEST_OUT:        .equ    0x6000
JR_STACK_TOP:       .equ    0x5fff

GAME_LEVELS:        .equ    24
; Upstream steps every 20 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    4
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    90
GAME_TEST_LIMIT:    .equ    200
GAME_TEST_HELD:     .equ    IS_HELD

; Upstream state (tests/model.py LAYOUT), then the room tail and work bytes.
IS_POS:             .equ    GAME_STATE
IS_ORIGIN:          .equ    GAME_STATE + 1
IS_FACING:          .equ    GAME_STATE + 2
IS_AMMO:            .equ    GAME_STATE + 3
IS_GATE:            .equ    GAME_STATE + 4
IS_DOOR_POSE:       .equ    GAME_STATE + 5
IS_STEPS:           .equ    GAME_STATE + 6
IS_PC:              .equ    GAME_STATE + 7
IS_SUB:             .equ    GAME_STATE + 8
IS_NOTICE:          .equ    GAME_STATE + 9
IS_BEAM:            .equ    GAME_STATE + 10
IS_RUNNING:         .equ    GAME_STATE + 11
IS_CURSOR:          .equ    GAME_STATE + 12
IS_ACTIVE:          .equ    GAME_STATE + 13
IS_B:               .equ    GAME_STATE + 14     ; the room (64)
IS_C:               .equ    GAME_STATE + 78     ; the program (12)
IS_TAIL:            .equ    GAME_STATE + 90     ; d[64-68]
IS_LENGTH:          .equ    IS_TAIL + 3
IS_PHASE:           .equ    IS_TAIL + 4
IS_HELD:            .equ    GAME_STATE + 96     ; unused (no held keys)
IS_I:               .equ    GAME_STATE + 97
IS_T:               .equ    GAME_STATE + 98
IS_TARGET:          .equ    GAME_STATE + 99
IS_COMMAND:         .equ    GAME_STATE + 100
IS_RAY:             .equ    GAME_STATE + 101
IS_FLASH:           .equ    GAME_STATE + 102    ; cell + 1 of an impact
IS_DI:              .equ    GAME_STATE + 103
IS_DT:              .equ    GAME_STATE + 104
IS_DY:              .equ    GAME_STATE + 105
IS_DCODE:           .equ    GAME_STATE + 106
IS_DQ:              .equ    GAME_STATE + 107
IS_P:               .equ    GAME_STATE + 108    ; 2 bytes

IS_TILE_FLOOR:      .equ    0x80
IS_TILE_WALL:       .equ    0x84
IS_TILE_TERMINAL:   .equ    0x88
IS_TILE_SWITCH:     .equ    0x8c
IS_TILE_SENTRY:     .equ    0x90
IS_TILE_LASER:      .equ    0x94
IS_CHAR_ARROW:      .equ    0x98        ; up, down, left, right
IS_CHAR_DOT:        .equ    0x9c
IS_CHAR_CURSOR:     .equ    0x9d
IS_TILE_ROBOT:      .equ    0x00        ; + 4 * (facing - 1)
IS_TILE_DOOR:       .equ    0x10        ; + 4 * (pose - 1)
IS_ATTR_TEXT:       .equ    0x07
IS_ATTR_LABEL:      .equ    0x04
IS_ATTR_TITLE:      .equ    0x06
IS_ATTR_DIM:        .equ    0x05
IS_ATTR_WARN:       .equ    0x02
IS_ATTR_ROBOT:      .equ    0x47
IS_ATTR_ICON:       .equ    0x46
IS_ATTR_CURSOR:     .equ    0x42
IS_ATTR_HIT:        .equ    0x72        ; red on yellow

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     is_patterns
        LDAA    IS_TILE_FLOOR
        LDAB    30
        JSR     jr_pcg_load
        LDX     is_robot_patterns
        CLRA
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level

; The room back to its start: map, robot, ammo, door, counters.
is_reset_world:
        LDX     is_levels
        LDAA    [JR_PORT_LEVEL]
        STAA    [IS_T]
is_reset_room:
        TST     [IS_T]
        BEQ     is_reset_unpack
        LDAA    37
        JSR     jr_add_x_a
        DEC     [IS_T]
        BRA     is_reset_room
is_reset_unpack:
        STX     [IS_P]
        CLR     [IS_I]
is_reset_cell:
        LDX     [IS_P]
        LDAA    [IS_I]
        JSR     jr_add_x_a
        LDAB    [X]
        LDX     IS_B
        LDAA    [IS_I]
        ASLA
        JSR     jr_add_x_a
        TBA
        LSRA
        LSRA
        LSRA
        LSRA
        STAA    [X]
        ANDB    15
        STAB    [X + 1]
        INC     [IS_I]
        LDAA    [IS_I]
        CMPA    32
        BNE     is_reset_cell
        LDX     [IS_P]
        LDAA    [X + 32]
        STAA    [IS_TAIL]
        STAA    [IS_POS]
        STAA    [IS_ORIGIN]
        LDAA    [X + 33]
        STAA    [IS_TAIL + 1]
        STAA    [IS_FACING]
        LDAA    [X + 34]
        STAA    [IS_TAIL + 2]
        STAA    [IS_AMMO]
        LDAA    [X + 35]
        STAA    [IS_LENGTH]
        LDAA    [X + 36]
        STAA    [IS_PHASE]
        CLR     [IS_GATE]
        LDAA    1
        STAA    [IS_DOOR_POSE]
        CLR     [IS_STEPS]
        CLR     [IS_PC]
        CLR     [IS_SUB]
        CLR     [IS_NOTICE]
        LDAA    255
        STAA    [IS_BEAM]
        RTS

; A = reason: the run stops, the cursor goes to the failing slot.
is_stop:
        STAA    [IS_NOTICE]
        CLR     [IS_RUNNING]
        LDAA    [IS_LENGTH]
        DECA
        CMPA    [IS_PC]
        BCS     is_stop_cursor
        LDAA    [IS_PC]
is_stop_cursor:
        STAA    [IS_CURSOR]
        LDX     is_sfx_stop
        JSR     jr_sfx_play
        LDAA    40
        JMP     jr_test_animate

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        TST     [IS_RUNNING]
        BEQ     is_act_edit
        CMPA    JR_KEY_CONFIRM
        BNE     is_act_done
        LDAA    9
        JMP     is_stop
is_act_edit:
        CMPA    JR_KEY_LEFT
        BNE     is_act_right
        TST     [IS_CURSOR]
        BEQ     is_act_sound
        DEC     [IS_CURSOR]
        BRA     is_act_sound
is_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     is_act_change
        LDAB    [IS_LENGTH]
        DECB
        CMPB    [IS_CURSOR]
        BLS     is_act_sound
        INC     [IS_CURSOR]
        BRA     is_act_sound
is_act_change:
        LDAB    1
        CMPA    JR_KEY_UP
        BEQ     is_act_command
        LDAB    7
        CMPA    JR_KEY_DOWN
        BNE     is_act_run
is_act_command:
        LDX     IS_C
        LDAA    [IS_CURSOR]
        JSR     jr_add_x_a
        ADDB    [X]
        ANDB    7
        STAB    [X]
is_act_sound:
        CLRA
        JMP     jr_port_sound
is_act_run:
        CMPA    JR_KEY_CONFIRM
        BNE     is_act_done
        JSR     is_reset_world
        LDAA    1
        STAA    [IS_RUNNING]
        CLR     [JR_PORT_TICKS]
is_act_done:
        RTS

; A = position, B = direction 1-4 -> A = moved position (8x8, stops at edges).
is_move:
        STAA    [IS_T]
        CMPB    JR_KEY_UP
        BNE     is_move_down
        CMPA    8
        BCS     is_move_done
        SUBA    8
        RTS
is_move_down:
        CMPB    JR_KEY_DOWN
        BNE     is_move_side
        CMPA    56
        BCC     is_move_done
        ADDA    8
        RTS
is_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     is_move_right
        TSTA
        BEQ     is_move_stay
        LDAA    [IS_T]
        DECA
        RTS
is_move_right:
        CMPA    7
        BCC     is_move_stay
        LDAA    [IS_T]
        INCA
        RTS
is_move_stay:
        LDAA    [IS_T]
is_move_done:
        RTS

; A = cell -> X = b[cell].
is_cell:
        LDX     IS_B
        JMP     jr_add_x_a

; Fire ahead: a wall or a locked door stops the shot; a sentry is destroyed,
; an armored sentry loses its armor.
is_shoot:
        TST     [IS_AMMO]
        BNE     is_shoot_fire
        LDAA    5
        JMP     is_stop
is_shoot_fire:
        DEC     [IS_AMMO]
        LDAA    [IS_POS]
        STAA    [IS_TARGET]
        LDAA    1
        JSR     jr_port_sound
        LDAA    7
        STAA    [IS_RAY]
is_shoot_step:
        LDAA    [IS_TARGET]
        LDAB    [IS_FACING]
        JSR     is_move
        STAA    [IS_TARGET]
        JSR     is_cell
        LDAA    [X]
        CMPA    1
        BEQ     is_shoot_end
        CMPA    6
        BNE     is_shoot_open
        TST     [IS_GATE]
        BEQ     is_shoot_end
is_shoot_open:
        LDAA    [IS_TARGET]
        STAA    [IS_BEAM]
        LDAA    3
        JSR     jr_test_animate
        LDAA    [IS_TARGET]
        JSR     is_cell
        LDAA    [X]
        CMPA    5
        BEQ     is_shoot_sentry
        CMPA    8
        BNE     is_shoot_next
        LDAA    5
        STAA    [X]
        LDAA    10
        BRA     is_shoot_hit
is_shoot_sentry:
        CLR     [X]
        LDAA    11
is_shoot_hit:
        STAA    [IS_NOTICE]
        LDAA    [IS_TARGET]
        JSR     is_blink
        BRA     is_shoot_end
is_shoot_next:
        DEC     [IS_RAY]
        BNE     is_shoot_step
is_shoot_end:
        LDAA    255
        STAA    [IS_BEAM]
        RTS

; A = cell: flash it for a moment.
is_blink:
        INCA
        STAA    [IS_FLASH]
        LDAA    8
        JSR     jr_test_animate
        CLR     [IS_FLASH]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     is_act_done_near357
        JMP     is_act_done
is_act_done_near357:
        TST     [IS_RUNNING]
        BNE     is_act_done_near361
        JMP     is_act_done
is_act_done_near361:
        ; L replays the two commands before it, once each
        LDAA    [IS_PC]
        STAA    [IS_ACTIVE]
        JSR     is_slot
        CMPA    7
        BNE     is_tick_command
        LDAA    [IS_PC]
        CMPA    2
        BCS     is_tick_bad_loop
        DECA
        JSR     is_slot
        CMPA    7
        BEQ     is_tick_bad_loop
        LDAA    [IS_PC]
        SUBA    2
        JSR     is_slot
        CMPA    7
        BEQ     is_tick_bad_loop
        LDAA    [IS_PC]
        SUBA    2
        ADDA    [IS_SUB]
        STAA    [IS_ACTIVE]
        BRA     is_tick_command
is_tick_bad_loop:
        LDAA    7
        JMP     is_stop
is_tick_command:
        LDAA    [IS_ACTIVE]
        JSR     is_slot
        STAA    [IS_COMMAND]
        INC     [IS_STEPS]
        CLR     [IS_NOTICE]
        LDAA    [IS_COMMAND]
        BNE     is_tick_wait_near397
        JMP     is_tick_wait
is_tick_wait_near397:
        CMPA    5
        BCC     is_tick_fire
        ; a move: turn, then step unless blocked
        STAA    [IS_FACING]
        TAB
        LDAA    [IS_POS]
        JSR     is_move
        STAA    [IS_TARGET]
        JSR     is_cell
        LDAA    [X]
        LDAB    1
        CMPA    1
        BEQ     is_tick_blocked
        LDAB    2
        CMPA    5
        BEQ     is_tick_blocked
        CMPA    8
        BEQ     is_tick_blocked
        CMPA    6
        BNE     is_tick_step
        LDAB    3
        TST     [IS_GATE]
        BEQ     is_tick_blocked
is_tick_step:
        LDAA    [IS_POS]
        STAA    [IS_ORIGIN]
        LDAA    [IS_TARGET]
        STAA    [IS_POS]
        CLRA
        JSR     jr_port_sound
        LDAA    5
        JSR     jr_test_animate
        LDAA    [IS_POS]
        STAA    [IS_ORIGIN]
        BRA     is_tick_after
is_tick_blocked:
        STAB    [IS_NOTICE]
        LDAA    [IS_TARGET]
        JSR     is_blink
        LDAA    [IS_NOTICE]
        JMP     is_stop
is_tick_fire:
        BNE     is_tick_use
        JSR     is_shoot
        BRA     is_tick_after
is_tick_use:
        ; U works only on a switch: the door toggles
        LDAA    [IS_POS]
        JSR     is_cell
        LDAA    [X]
        CMPA    4
        BEQ     is_tick_switch
        LDAA    6
        JMP     is_stop
is_tick_switch:
        LDAA    [IS_GATE]
        EORA    1
        STAA    [IS_GATE]
        LDAA    12
        STAA    [IS_NOTICE]
        LDAA    1
        JSR     jr_port_sound
        CLR     [IS_I]
is_tick_door:
        LDAA    [IS_I]
        ADDA    2
        TST     [IS_GATE]
        BNE     is_tick_door_pose
        LDAA    3
        SUBA    [IS_I]
is_tick_door_pose:
        STAA    [IS_DOOR_POSE]
        LDAA    5
        JSR     jr_test_animate
        INC     [IS_I]
        LDAA    [IS_I]
        CMPA    3
        BNE     is_tick_door
        BRA     is_tick_after
is_tick_wait:
        CLRA
        JSR     jr_port_sound
        LDAA    5
        JSR     jr_test_animate
is_tick_after:
        TST     [IS_RUNNING]
        BNE     is_act_done_near486
        JMP     is_act_done
is_act_done_near486:
        ; a laser that is on this step
        LDAA    [IS_POS]
        JSR     is_cell
        LDAA    [X]
        CMPA    7
        BNE     is_tick_goal
        JSR     is_laser_on
        BEQ     is_tick_goal
        LDAA    4
        STAA    [IS_NOTICE]
        LDAA    [IS_POS]
        JSR     is_blink
        LDAA    4
        JMP     is_stop
is_tick_goal:
        LDAA    [IS_POS]
        JSR     is_cell
        LDAA    [X]
        CMPA    3
        BNE     is_tick_next
        CLR     [IS_RUNNING]
        JMP     jr_port_win
is_tick_next:
        LDAA    [IS_PC]
        JSR     is_slot
        CMPA    7
        BNE     is_tick_advance
        TST     [IS_SUB]
        BNE     is_tick_advance
        LDAA    1
        STAA    [IS_SUB]
        BRA     is_tick_end
is_tick_advance:
        CLR     [IS_SUB]
        INC     [IS_PC]
is_tick_end:
        LDAA    [IS_PC]
        CMPA    [IS_LENGTH]
        BCC     is_act_done_near527
        JMP     is_act_done
is_act_done_near527:
        LDAA    8
        JMP     is_stop

; A = slot -> A = c[slot].
is_slot:
        LDX     IS_C
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; -> Z clear when lasers are on at this step ((steps + phase) odd).
is_laser_on:
        LDAA    [IS_STEPS]
        ADDA    [IS_PHASE]
        ANDA    1
        RTS

; ---------------------------------------------------------------- drawing

; A = cell -> A = x, B = y of its tile.
is_place:
        TAB
        ANDA    7
        ASLA
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        RTS

game_draw:
        LDAA    0x20
        LDAB    IS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     is_hud
        JSR     jr_gfx_lines
        LDAA    IS_ATTR_DIM
        STAA    [JR_RT_COLOR]
        LDX     is_frame_rows
is_draw_frame:
        LDAB    [X]
        CMPB    0xff
        BEQ     is_draw_side
        STX     [IS_P]
        LDAA    18
        JSR     jr_gfx_at
        LDX     is_txt_frame
        JSR     jr_gfx_text
        LDX     [IS_P]
        INX
        BRA     is_draw_frame
is_draw_side:
        LDAB    3
is_draw_side_next:
        LDAA    31
        PSHB
        JSR     jr_gfx_at
        LDAA    0x3a
        JSR     jr_gfx_putc
        PULB
        INCB
        CMPB    19
        BNE     is_draw_side_next
        ; the room
        CLR     [IS_DI]
is_draw_cell:
        LDAA    [IS_DI]
        JSR     is_cell
        LDAA    [X]
        STAA    [IS_DQ]
        CMPA    8
        BNE     is_draw_kind
        LDAA    5
is_draw_kind:
        CMPA    7
        BNE     is_draw_tile
        JSR     is_laser_on
        BNE     is_draw_laser_on
        CLRA
        BRA     is_draw_tile
is_draw_laser_on:
        LDAA    7
is_draw_tile:
        ASLA
        LDX     is_looks
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [IS_DCODE]
        LDAA    [X + 1]
        STAA    [JR_RT_COLOR]
        LDAA    [IS_DCODE]
        CMPA    IS_TILE_DOOR
        BNE     is_draw_put
        LDAA    [IS_DOOR_POSE]
        DECA
        ASLA
        ASLA
        ADDA    IS_TILE_DOOR
        STAA    [IS_DCODE]
is_draw_put:
        LDAA    [IS_DI]
        INCA
        CMPA    [IS_FLASH]
        BNE     is_draw_put_at
        LDAA    IS_ATTR_HIT
        STAA    [JR_RT_COLOR]
is_draw_put_at:
        LDAA    [IS_DI]
        JSR     is_place
        STAA    [IS_DT]
        STAB    [IS_DY]
        JSR     jr_gfx_at
        LDAA    [IS_DCODE]
        JSR     jr_gfx_tile
        ; an armored sentry carries a 2, an idle laser two dots
        LDAA    [IS_DQ]
        CMPA    8
        BNE     is_draw_idle_laser
        LDAA    IS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    [IS_DT]
        INCA
        LDAB    [IS_DY]
        JSR     jr_gfx_at
        LDAA    0x32
        JSR     jr_gfx_putc
        BRA     is_draw_cell_next
is_draw_idle_laser:
        CMPA    7
        BNE     is_draw_cell_next
        JSR     is_laser_on
        BNE     is_draw_cell_next
        LDAA    IS_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    [IS_DT]
        LDAB    [IS_DY]
        JSR     jr_gfx_at
        LDAA    IS_CHAR_DOT
        JSR     jr_gfx_putc
        LDAA    [IS_DT]
        INCA
        LDAB    [IS_DY]
        INCB
        JSR     jr_gfx_at
        LDAA    IS_CHAR_DOT
        JSR     jr_gfx_putc
is_draw_cell_next:
        INC     [IS_DI]
        LDAA    [IS_DI]
        CMPA    64
        BEQ     is_draw_cell_near681
        JMP     is_draw_cell
is_draw_cell_near681:
        ; the robot, half-way while it steps
        LDAA    IS_ATTR_ROBOT
        STAA    [JR_RT_COLOR]
        LDAA    [IS_POS]
        JSR     is_place
        STAA    [IS_DT]
        STAB    [IS_DY]
        LDAA    [IS_ORIGIN]
        JSR     is_place
        ADDA    [IS_DT]
        LSRA
        ADDB    [IS_DY]
        LSRB
        JSR     jr_gfx_at
        LDAA    [IS_FACING]
        DECA
        ANDA    3
        ASLA
        ASLA
        ADDA    IS_TILE_ROBOT
        JSR     jr_gfx_tile
        LDAA    [IS_BEAM]
        CMPA    255
        BEQ     is_draw_panel
        JSR     is_place
        JSR     jr_gfx_at
        LDAA    IS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    0x2a
        JSR     jr_gfx_putc
is_draw_panel:
        LDAA    IS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [IS_AMMO]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [IS_LENGTH]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [IS_STEPS]
        JSR     jr_gfx_dec3
        LDAA    IS_ATTR_ICON
        STAA    [JR_RT_COLOR]
        LDAA    29
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [IS_FACING]
        JSR     is_icon
        JSR     jr_gfx_putc
        LDAA    IS_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    5
        JSR     jr_gfx_at
        LDX     is_txt_lock
        TST     [IS_GATE]
        BEQ     is_draw_gate
        LDX     is_txt_open
is_draw_gate:
        JSR     jr_gfx_text
        LDAA    22
        LDAB    7
        JSR     jr_gfx_at
        JSR     is_laser_on
        LDX     is_txt_laser_on
        BEQ     is_draw_laser
        LDX     is_txt_laser_off
is_draw_laser:
        JSR     jr_gfx_text
        ; the program: twelve slots, unused ones crossed out
        CLR     [IS_DI]
is_draw_slot:
        LDAA    IS_ATTR_ICON
        STAA    [JR_RT_COLOR]
        LDAA    [IS_DI]
        JSR     is_slot_place
        INCA
        JSR     jr_gfx_at
        LDAA    [IS_DI]
        CMPA    [IS_LENGTH]
        BCS     is_draw_slot_icon
        LDAA    IS_ATTR_DIM
        STAA    [JR_RT_COLOR]
        LDAA    0x58
        BRA     is_draw_slot_put
is_draw_slot_icon:
        JSR     is_slot
        JSR     is_icon
is_draw_slot_put:
        JSR     jr_gfx_putc
        INC     [IS_DI]
        LDAA    [IS_DI]
        CMPA    12
        BNE     is_draw_slot
        ; the cursor (or the running slot) and its command name
        LDAA    [IS_CURSOR]
        TST     [IS_RUNNING]
        BEQ     is_draw_current
        LDAA    [IS_PC]
is_draw_current:
        CMPA    11
        BLS     is_draw_current_slot
        LDAA    11
is_draw_current_slot:
        STAA    [IS_DI]
        JSR     is_slot_place
        JSR     jr_gfx_at
        LDAA    IS_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    IS_CHAR_CURSOR
        JSR     jr_gfx_putc
        LDAA    IS_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [IS_DI]
        JSR     is_slot
        ASLA
        ASLA
        ASLA
        LDX     is_names
        JSR     jr_add_x_a
        JSR     is_draw_chars8
        ; the message row
        LDAA    IS_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        TST     [IS_RUNNING]
        BEQ     is_draw_message
        TST     [IS_NOTICE]
        BNE     is_draw_message
        LDX     is_txt_executing
        LDAA    [IS_PC]
        JSR     is_slot
        CMPA    7
        BNE     is_draw_running
        LDX     is_txt_replay
is_draw_running:
        JSR     jr_gfx_text
        BRA     is_draw_demo
is_draw_message:
        LDAA    [IS_NOTICE]
        ASLA
        ASLA
        ASLA
        ASLA
        LDX     is_messages
        JSR     jr_add_x_a
        JSR     is_draw_chars8
        JSR     is_draw_chars8
is_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     is_draw_done
        LDAA    IS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     is_txt_demo
        JSR     jr_gfx_text
is_draw_done:
        RTS

; X = eight characters: put them at the cursor, X advances past them.
is_draw_chars8:
        LDAB    8
is_draw_chars8_next:
        LDAA    [X]
        STX     [IS_P]
        PSHB
        JSR     jr_gfx_putc
        PULB
        LDX     [IS_P]
        INX
        DECB
        BNE     is_draw_chars8_next
        RTS

; A = slot -> A = x of its "[", B = y.
is_slot_place:
        TAB
        ANDA    3
        STAA    [IS_T]
        ASLA
        ADDA    [IS_T]
        ADDA    18
        LSRB
        LSRB
        STAB    [IS_T]
        ASLB
        ADDB    [IS_T]
        ADDB    11
        RTS

; A = command -> A = its icon code; the colour is set to match (the arrows
; are user patterns, the letters and the dot come from the font).
is_icon:
        LDX     is_icons
        JSR     jr_add_x_a
        LDAB    IS_ATTR_ICON
        LDAA    [X]
        BMI     is_icon_colour
        LDAB    IS_ATTR_TITLE
is_icon_colour:
        STAB    [JR_RT_COLOR]
        RTS

game_draw_title:
        LDX     is_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    IS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     is_title_tiles
        STX     [JR_RT_TABLE]
is_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     is_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [IS_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [IS_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     is_title_tile
is_title_text:
        LDX     is_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    IS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     is_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; by cell kind 0-7: code, attribute (6 is the door, posed at draw time)
is_looks:
        .db     IS_TILE_FLOOR, 0x41, IS_TILE_WALL, 0x47, IS_TILE_FLOOR, 0x41
        .db     IS_TILE_TERMINAL, 0x45, IS_TILE_SWITCH, 0x46, IS_TILE_SENTRY, 0x43
        .db     IS_TILE_DOOR, 0x44, IS_TILE_LASER, 0x42
; icons of the eight commands: wait, up, down, left, right, fire, use, replay
is_icons:
        .db     0x2e, IS_CHAR_ARROW, IS_CHAR_ARROW + 1, IS_CHAR_ARROW + 2
        .db     IS_CHAR_ARROW + 3, 0x46, 0x55, 0x4c
is_names:
        .db     "WAIT    UP      DOWN    LEFT    RIGHT   FIRE    USE     LOOP X2 "
is_messages:
        .db     "EDITING         WALL COLLISION  SENTRY COLLISIONDOOR IS LOCKED  "
        .db     "LASER HIT       NO AMMO LEFT    USE ON SWITCH   LOOP NEEDS TWO  "
        .db     "PROGRAM ENDED   STOPPED / EDIT  ARMOR DAMAGED   SENTRY DESTROYED"
        .db     "DOOR SWITCHED   "
is_frame_rows:
        .db     2, 8, 19, 0xff

; x, attribute, code, y
is_title_tiles:
        .db     8, IS_ATTR_ROBOT, IS_TILE_ROBOT + 12, 3
        .db     11, 0x44, IS_TILE_DOOR, 3
        .db     14, 0x43, IS_TILE_SENTRY, 3
        .db     17, 0x42, IS_TILE_LASER, 3
        .db     20, 0x45, IS_TILE_TERMINAL, 3
        .db     0xff

is_hud:
        .db     1, 0, IS_ATTR_TITLE
        .dw     is_txt_name
        .db     1, 1, IS_ATTR_LABEL
        .dw     is_txt_goal
        .db     18, 3, IS_ATTR_LABEL
        .dw     is_txt_ammo
        .db     26, 3, IS_ATTR_LABEL
        .dw     is_txt_dir
        .db     18, 5, IS_ATTR_LABEL
        .dw     is_txt_door
        .db     18, 6, IS_ATTR_LABEL
        .dw     is_txt_next_laser
        .db     18, 9, IS_ATTR_LABEL
        .dw     is_txt_program
        .db     28, 9, IS_ATTR_LABEL
        .dw     is_txt_of12
        .db     18, 20, IS_ATTR_LABEL
        .dw     is_txt_steps
        .db     18, 11, IS_ATTR_DIM
        .dw     is_txt_slots
        .db     18, 14, IS_ATTR_DIM
        .dw     is_txt_slots
        .db     18, 17, IS_ATTR_DIM
        .dw     is_txt_slots
        .db     18, 10, IS_ATTR_DIM
        .dw     is_txt_numbers_1
        .db     18, 13, IS_ATTR_DIM
        .dw     is_txt_numbers_2
        .db     18, 16, IS_ATTR_DIM
        .dw     is_txt_numbers_3
        .db     0xff
is_title_lines:
        .db     10, 8, IS_ATTR_TITLE
        .dw     is_txt_name
        .db     3, 10, IS_ATTR_LABEL
        .dw     is_txt_tagline
        .db     4, 13, IS_ATTR_TEXT
        .dw     is_txt_start
        .db     4, 15, IS_ATTR_TEXT
        .dw     is_txt_howto
        .db     4, 17, IS_ATTR_DIM
        .dw     is_txt_demo_hint
        .db     4, 19, IS_ATTR_DIM
        .dw     is_txt_credit
        .db     0xff
is_help_lines:
        .db     10, 1, IS_ATTR_TITLE
        .dw     is_txt_name
        .db     1, 3, IS_ATTR_TEXT
        .dw     is_help_1
        .db     1, 5, IS_ATTR_TEXT
        .dw     is_help_2
        .db     1, 7, IS_ATTR_TEXT
        .dw     is_help_3
        .db     1, 9, IS_ATTR_TEXT
        .dw     is_help_4
        .db     1, 11, IS_ATTR_TEXT
        .dw     is_help_5
        .db     1, 13, IS_ATTR_TEXT
        .dw     is_help_6
        .db     1, 15, IS_ATTR_TEXT
        .dw     is_help_7
        .db     1, 17, IS_ATTR_TEXT
        .dw     is_help_8
        .db     1, 21, IS_ATTR_LABEL
        .dw     is_help_back
        .db     0xff

is_txt_name:
        .db     "IRON SCRIPT", 0
is_txt_goal:
        .db     "GOAL: DIAMOND / 24 ROOMS", 0
is_txt_ammo:
        .db     "AMMO", 0
is_txt_dir:
        .db     "DIR", 0
is_txt_door:
        .db     "DOOR", 0
is_txt_next_laser:
        .db     "NEXT", 0
is_txt_program:
        .db     "PROGRAM", 0
is_txt_of12:
        .db     "/12", 0
is_txt_steps:
        .db     "STEPS", 0
is_txt_slots:
        .db     "[ ][ ][ ][ ]", 0
is_txt_numbers_1:
        .db     " 1  2  3  4", 0
is_txt_numbers_2:
        .db     " 5  6  7  8", 0
is_txt_numbers_3:
        .db     " 9  A  B  C", 0
is_txt_frame:
        .db     "+------------+", 0
is_txt_lock:
        .db     "LOCK", 0
is_txt_open:
        .db     "OPEN", 0
is_txt_laser_on:
        .db     "LASER ON!", 0
is_txt_laser_off:
        .db     "LASER OFF", 0
is_txt_executing:
        .db     "EXECUTING", 0
is_txt_replay:
        .db     "REPLAY PAIR", 0
is_txt_demo:
        .db     "DEMO", 0
is_txt_tagline:
        .db     "WRITE THE PROGRAM, RUN IT", 0
is_txt_start:
        .db     "RETURN : START", 0
is_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
is_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
is_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
is_help_1:
        .db     "A/D SLOT  W/S CHANGE COMMAND", 0
is_help_2:
        .db     "ARROWS MOVE / DOT WAITS", 0
is_help_3:
        .db     "F: FIRE AHEAD / U: USE SWITCH", 0
is_help_4:
        .db     "L: REPLAY PREVIOUS TWO ONCE", 0
is_help_5:
        .db     "LASERS FLIP AFTER EACH ACTION", 0
is_help_6:
        .db     "RETURN RUN/STOP; EDIT TO RETRY", 0
is_help_7:
        .db     "REACH THE DIAMOND TERMINAL.", 0
is_help_8:
        .db     "SPACE: CLEAR AND RESTART", 0
is_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     is_sfx_tick, is_sfx_zap, is_jingle_win, is_jingle_lose
is_sfx_tick:
        .db     90, 1, 0, 0
is_sfx_zap:
        .db     30, 1, 50, 1, 30, 1, 50, 1, 0, 0
is_sfx_stop:
        .db     180, 3, 240, 6, 0, 0

; Title: a mechanical ostinato in E minor, eighth note = 8 frames, looping.
is_title_song:
        .db     1
        .dw     is_title_melody, is_title_harmony, is_title_bass
is_title_melody:
        .db     AU_E5, 8, AU_B4, 8, AU_E5, 8, AU_G5, 8, AU_FS5, 8, AU_E5, 8, AU_D5, 8, AU_B4, 8
        .db     AU_C5, 8, AU_E5, 8, AU_A5, 8, AU_G5, 8, AU_FS5, 16, AU_DS5, 16
        .db     AU_E5, 8, AU_B4, 8, AU_E5, 8, AU_G5, 8, AU_B5, 8, AU_A5, 8, AU_G5, 8, AU_FS5, 8
        .db     AU_E5, 8, AU_FS5, 8, AU_DS5, 8, AU_B4, 8, AU_E5, 32, 0, 0
is_title_harmony:
        .db     AU_G4, 32, AU_B4, 32, AU_E4, 32, AU_B4, 32
        .db     AU_G4, 32, AU_D5, 32, AU_B4, 32, AU_G4, 32, 0, 0
is_title_bass:
        .db     AU_E2, 16, AU_E3, 16, AU_G2, 16, AU_B2, 16, AU_A2, 16, AU_C3, 16, AU_B2, 32
        .db     AU_E2, 16, AU_E3, 16, AU_G2, 16, AU_B2, 16, AU_A2, 16, AU_B2, 16, AU_E2, 32, 0, 0

; Terminal reached: E major chime.
is_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     is_win_melody, is_win_harmony, is_win_bass
is_win_melody:
        .db     AU_B4, 6, AU_E5, 6, AU_GS5, 6, AU_B5, 12, AU_E6, 30, 0, 0
is_win_harmony:
        .db     AU_GS4, 12, AU_B4, 18, AU_GS5, 30, 0, 0
is_win_bass:
        .db     AU_E3, 12, AU_B2, 18, AU_E2, 30, 0, 0
is_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     is_lose_melody, is_lose_harmony, is_lose_bass
is_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
is_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
is_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


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
        .include "selftest.inc"
        .include "rooms.inc"

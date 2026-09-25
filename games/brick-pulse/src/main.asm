; SPDX-License-Identifier: MIT
; BRICK PULSE for JR-200: a port of jr100dev games/brick_pulse/rules.py 2.3.1.
; Twelve arenas, three balls, armored bricks, drones from arena 3, bombs from
; arena 6 and the W/S/G pickups follow the upstream source. Held A/D comes
; from the keyboard MCU scan (sdk/keyscan.inc).
        .filename.jr "BRICK-PULSE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46c0
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    12
; One upstream tick is five 1/60 s frames. Rendering and the MCU scan take
; about 3.5 frames, so one idle frame gives about 13 ticks per second (upstream 12).
GAME_RATE:          .equ    1
GAME_SPACE_RESET:   .equ    0
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: b[24] then the fields below (tests/model.py STATE_FIELDS).
BP_B:               .equ    GAME_STATE
BP_LEFT:            .equ    GAME_STATE + 24
BP_PADDLE:          .equ    GAME_STATE + 25
BP_WIDTH:           .equ    GAME_STATE + 26
BP_HP:              .equ    GAME_STATE + 27
BP_EX:              .equ    GAME_STATE + 28
BP_ED:              .equ    GAME_STATE + 29
BP_ENEMY:           .equ    GAME_STATE + 30
BP_X:               .equ    GAME_STATE + 31
BP_Y:               .equ    GAME_STATE + 32
BP_DY:              .equ    GAME_STATE + 33
BP_DX:              .equ    GAME_STATE + 34
BP_STEEP:           .equ    GAME_STATE + 35
BP_REPEAT:          .equ    GAME_STATE + 36
BP_ITEM:            .equ    GAME_STATE + 37
BP_IX:              .equ    GAME_STATE + 38
BP_IY:              .equ    GAME_STATE + 39
BP_CLOCK:           .equ    GAME_STATE + 40
BP_BOMB:            .equ    GAME_STATE + 41
BP_BX:              .equ    GAME_STATE + 42
BP_GUARD:           .equ    GAME_STATE + 43
BP_JAM:             .equ    GAME_STATE + 44
BP_WIDE:            .equ    GAME_STATE + 45
BP_SLOW:            .equ    GAME_STATE + 46
BP_CAUGHT:          .equ    GAME_STATE + 47
BP_STEPS:           .equ    GAME_STATE + 48
BP_BROKEN:          .equ    GAME_STATE + 49
BP_BOUNCES:         .equ    GAME_STATE + 50
BP_STATE_SIZE:      .equ    51
; Rule work bytes.
BP_HELD:            .equ    GAME_STATE + 56
BP_T:               .equ    GAME_STATE + 57
BP_I:               .equ    GAME_STATE + 58
BP_MID:             .equ    GAME_STATE + 59
BP_EFX:             .equ    GAME_STATE + 60
BP_EFY:             .equ    GAME_STATE + 61
BP_EFN:             .equ    GAME_STATE + 62
BP_EFP:             .equ    GAME_STATE + 63
; Drawing work bytes.
BP_DI:              .equ    GAME_STATE + 96
BP_DRAW_X:          .equ    GAME_STATE + 97
BP_DRAW_Y:          .equ    GAME_STATE + 98
BP_DN:              .equ    GAME_STATE + 99
; Self-test bytes (outside the per-stage state).
BP_QUIET:           .equ    0x46c0
BP_FIX:             .equ    0x46c2
BP_OUT:             .equ    0x46c4
BP_TICKS:           .equ    0x46c6
BP_PAIRS:           .equ    0x46c8
BP_AUTO_LEVEL:      .equ    0x46c9
BP_COPY:            .equ    0x46ca
BP_DEMO:            .equ    0x46cc
BP_WAIT_FRAMES:     .equ    0x46cd
BP_RESULTS:         .equ    0x5000
BP_FIXTURE_STRIDE:  .equ    52
BP_AUTO_STRIDE:     .equ    54
BP_AUTO_LIMIT:      .equ    20000

BP_CHAR_CAP_L:      .equ    0x80
BP_CHAR_CAP_R:      .equ    0x81
BP_CHAR_BODY:       .equ    0x81
BP_CHAR_BALL:       .equ    0x85
BP_CHAR_PAD_L:      .equ    0x86
BP_CHAR_PAD_M:      .equ    0x87
BP_CHAR_PAD_R:      .equ    0x88
BP_CHAR_DRONE:      .equ    0x89
BP_CHAR_BOMB:       .equ    0x8c
BP_CHAR_BLOCK:      .equ    0x8d
BP_TILE_BURST:      .equ    0x8e
BP_ATTR_TEXT:       .equ    0x07
BP_ATTR_LABEL:      .equ    0x04
BP_ATTR_TITLE:      .equ    0x06
BP_ATTR_BALL:       .equ    0x47
BP_ATTR_PADDLE:     .equ    0x44
BP_ATTR_WIDE:       .equ    0x45
BP_ATTR_JAM:        .equ    0x42
BP_ATTR_DRONE:      .equ    0x45
BP_ATTR_BOMB:       .equ    0x42
BP_ATTR_GUARD:      .equ    0x01
BP_ATTR_HIT:        .equ    0x42
BP_ATTR_BURST:      .equ    0x46

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     bp_patterns
        LDAA    BP_CHAR_CAP_L
        LDAB    30
        JSR     jr_pcg_load
        JSR     jr_keyscan_init
        CLR     [BP_QUIET]
        CLR     [BP_DEMO]
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        ; arena address = bp_arenas + level * 24 (up to 264: 16-bit steps)
        LDX     bp_arenas
        LDAB    [JR_PORT_LEVEL]
bp_init_arena:
        TSTB
        BEQ     bp_init_arena_found
        LDAA    24
        JSR     jr_add_x_a
        DECB
        BRA     bp_init_arena
bp_init_arena_found:
        STX     [JR_RT_SRC]
        CLR     [BP_I]
bp_init_brick:
        LDX     [JR_RT_SRC]
        LDAA    [X]
        INX
        STX     [JR_RT_SRC]
        PSHA
        LDX     BP_B
        LDAA    [BP_I]
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        TSTA
        BEQ     bp_init_next
        INC     [BP_LEFT]
bp_init_next:
        INC     [BP_I]
        LDAA    [BP_I]
        CMPA    24
        BNE     bp_init_brick
        LDAA    12
        STAA    [BP_PADDLE]
        LDAA    6
        STAA    [BP_WIDTH]
        LDAA    3
        STAA    [BP_HP]
        LDAA    6
        STAA    [BP_EX]
        LDAA    1
        STAA    [BP_ED]
        LDAA    [JR_PORT_LEVEL]
        CMPA    2
        BCS     bp_serve
        LSRA
        LSRA
        ADDA    2
        STAA    [BP_ENEMY]
bp_serve:
        LDAA    [BP_WIDTH]
        LSRA
        ADDA    [BP_PADDLE]
        STAA    [BP_X]
        LDAA    14
        STAA    [BP_Y]
        CLR     [BP_DY]
        LDAA    1
        STAA    [BP_DX]
        CLR     [BP_STEEP]
        RTS

; A = 3 (left) or 4 (right).
bp_move_paddle:
        CMPA    3
        BNE     bp_move_right
        LDAA    [BP_PADDLE]
        SUBA    2
        BCC     bp_move_store
        CLRA
        BRA     bp_move_store
bp_move_right:
        CMPA    4
        BNE     bp_move_done
        LDAA    30
        SUBA    [BP_WIDTH]
        STAA    [BP_T]
        LDAA    [BP_PADDLE]
        ADDA    2
        CMPA    [BP_T]
        BLS     bp_move_store
        LDAA    [BP_T]
bp_move_store:
        STAA    [BP_PADDLE]
bp_move_done:
        RTS

game_act:
        CMPA    3
        BEQ     bp_act_move
        CMPA    4
        BNE     bp_move_done
bp_act_move:
        JSR     bp_move_paddle
        LDAA    1
        STAA    [BP_REPEAT]
        RTS

; drop(kind, x, y) with A = kind; x and y come from BP_EFX / BP_EFY.
bp_drop:
        TST     [BP_ITEM]
        BNE     bp_drop_done
        STAA    [BP_ITEM]
        LDAA    [BP_EFX]
        STAA    [BP_IX]
        LDAA    [BP_EFY]
        STAA    [BP_IY]
bp_drop_done:
        RTS

game_tick:
        TST     [BP_QUIET]
        BNE     bp_tick_held
        TST     [BP_DEMO]
        BEQ     bp_tick_scan
        JSR     bp_autopilot
        BRA     bp_tick_held
bp_tick_scan:
        JSR     bp_read_held
bp_tick_held:
        LDAA    [BP_HELD]
        CMPA    3
        BEQ     bp_tick_direction
        CMPA    4
        BEQ     bp_tick_direction
        CLR     [BP_REPEAT]
        BRA     bp_tick_clock
bp_tick_direction:
        TST     [BP_REPEAT]
        BEQ     bp_tick_move
        DEC     [BP_REPEAT]
        BRA     bp_tick_clock
bp_tick_move:
        JSR     bp_move_paddle
bp_tick_clock:
        INC     [BP_CLOCK]
        TST     [BP_JAM]
        BEQ     bp_tick_wide
        DEC     [BP_JAM]
        BNE     bp_tick_wide
        LDAA    6
        STAA    [BP_WIDTH]
        LDAA    [BP_PADDLE]
        CMPA    24
        BLS     bp_tick_wide
        LDAA    24
        STAA    [BP_PADDLE]
bp_tick_wide:
        TST     [BP_WIDE]
        BEQ     bp_tick_slow
        DEC     [BP_WIDE]
        BNE     bp_tick_slow
        LDAA    6
        STAA    [BP_WIDTH]
bp_tick_slow:
        TST     [BP_SLOW]
        BEQ     bp_tick_hazards
        DEC     [BP_SLOW]
bp_tick_hazards:
        JSR     bp_hazards
        TST     [BP_HP]
        BEQ     bp_tick_end
        TST     [BP_SLOW]
        BEQ     bp_tick_step
        LDAA    [BP_CLOCK]
        BITA    1
        BNE     bp_tick_end
bp_tick_step:
        INC     [BP_STEPS]
        JSR     bp_ball
bp_tick_end:
        TST     [BP_HP]
        BNE     bp_tick_win
        LDX     0
        JMP     jr_port_lose
bp_tick_win:
        TST     [BP_LEFT]
        BNE     bp_tick_done
        TST     [BP_ENEMY]
        BNE     bp_tick_done
        JMP     jr_port_win
bp_tick_done:
        RTS

; Held A/D from the MCU scan -> BP_HELD 3/4, anything else 0.
bp_read_held:
        JSR     jr_keyscan
        CLRB
        ORAA    0x20
        CMPA    0x61
        BNE     bp_read_right
        LDAB    3
bp_read_right:
        CMPA    0x64
        BNE     bp_read_store
        LDAB    4
bp_read_store:
        STAB    [BP_HELD]
        RTS

bp_hazards:
        TST     [BP_ENEMY]
        BEQ     bp_hazard_bomb
        LDAA    [BP_CLOCK]
        BITA    1
        BNE     bp_hazard_spawn
        LDAA    [BP_EX]
        CMPA    2
        BNE     bp_hazard_east
        LDAB    1
        STAB    [BP_ED]
bp_hazard_east:
        CMPA    27
        BNE     bp_hazard_fly
        CLR     [BP_ED]
bp_hazard_fly:
        TST     [BP_ED]
        BEQ     bp_hazard_west
        INC     [BP_EX]
        BRA     bp_hazard_spawn
bp_hazard_west:
        DEC     [BP_EX]
bp_hazard_spawn:
        LDAA    [JR_PORT_LEVEL]
        CMPA    5
        BCS     bp_hazard_bomb
        LDAA    [BP_CLOCK]
        ANDA    31
        BNE     bp_hazard_bomb
        TST     [BP_BOMB]
        BNE     bp_hazard_bomb
        LDAA    10
        STAA    [BP_BOMB]
        LDAA    [BP_EX]
        STAA    [BP_BX]
bp_hazard_bomb:
        TST     [BP_BOMB]
        BEQ     bp_hazard_item
        LDAA    [BP_CLOCK]
        BITA    1
        BNE     bp_hazard_item
        INC     [BP_BOMB]
        LDAA    [BP_BOMB]
        CMPA    17
        BNE     bp_hazard_item
        LDAA    [BP_BX]
        JSR     bp_on_paddle
        BCS     bp_hazard_bomb_gone
        TST     [BP_GUARD]
        BEQ     bp_hazard_jam
        CLR     [BP_GUARD]
        BRA     bp_hazard_bomb_hit
bp_hazard_jam:
        LDAA    48
        STAA    [BP_JAM]
        CLR     [BP_WIDE]
        LDAA    4
        STAA    [BP_WIDTH]
bp_hazard_bomb_hit:
        LDAA    3
        JSR     bp_sound
        LDAA    [BP_BX]
        INCA
        LDAB    18
        JSR     bp_impact
bp_hazard_bomb_gone:
        CLR     [BP_BOMB]
bp_hazard_item:
        TST     [BP_ITEM]
        BEQ     bp_hazard_done
        LDAA    [BP_CLOCK]
        BITA    1
        BNE     bp_hazard_done
        INC     [BP_IY]
        LDAA    [BP_IY]
        CMPA    17
        BNE     bp_hazard_done
        LDAA    [BP_IX]
        JSR     bp_on_paddle
        BCS     bp_hazard_item_gone
        LDAA    [BP_ITEM]
        CMPA    1
        BNE     bp_hazard_slow
        CLR     [BP_JAM]
        LDAA    96
        STAA    [BP_WIDE]
        LDAA    10
        STAA    [BP_WIDTH]
        LDAA    [BP_PADDLE]
        CMPA    20
        BLS     bp_hazard_caught
        LDAA    20
        STAA    [BP_PADDLE]
        BRA     bp_hazard_caught
bp_hazard_slow:
        CMPA    2
        BNE     bp_hazard_guard
        LDAA    96
        STAA    [BP_SLOW]
        BRA     bp_hazard_caught
bp_hazard_guard:
        CMPA    3
        BNE     bp_hazard_caught
        LDAA    1
        STAA    [BP_GUARD]
bp_hazard_caught:
        INC     [BP_CAUGHT]
        LDAA    2
        JSR     bp_sound
bp_hazard_item_gone:
        CLR     [BP_ITEM]
bp_hazard_done:
        RTS

; A = column -> carry clear when paddle <= A < paddle + width.
bp_on_paddle:
        CMPA    [BP_PADDLE]
        BCS     bp_on_paddle_done
        SUBA    [BP_PADDLE]
        CMPA    [BP_WIDTH]
        BCS     bp_on_paddle_yes
        SEC
        RTS
bp_on_paddle_yes:
        CLC
bp_on_paddle_done:
        RTS

bp_ball:
        LDAA    [BP_X]
        BNE     bp_ball_east_wall
        LDAB    1
        STAB    [BP_DX]
bp_ball_east_wall:
        CMPA    29
        BNE     bp_ball_x
        CLR     [BP_DX]
bp_ball_x:
        TST     [BP_STEEP]
        BEQ     bp_ball_step_x
        LDAA    [BP_STEPS]
        BITA    1
        BNE     bp_ball_y
bp_ball_step_x:
        TST     [BP_DX]
        BEQ     bp_ball_west
        INC     [BP_X]
        BRA     bp_ball_y
bp_ball_west:
        DEC     [BP_X]
bp_ball_y:
        TST     [BP_Y]
        BNE     bp_ball_step_y
        LDAB    1
        STAB    [BP_DY]
bp_ball_step_y:
        TST     [BP_DY]
        BEQ     bp_ball_up
        INC     [BP_Y]
        BRA     bp_ball_bricks
bp_ball_up:
        DEC     [BP_Y]
bp_ball_bricks:
        LDAA    [BP_Y]
        CMPA    8
        BCC     bp_ball_drone
        JSR     bp_brick_hit
bp_ball_drone:
        JSR     bp_drone_hit
        JMP     bp_paddle_hit

; y < 8: i = x // 5 + (y // 2) * 6.
bp_brick_hit:
        LDAA    [BP_X]
        LDAB    5
        JSR     jr_divmod8
        STAA    [BP_T]
        LDAA    [BP_Y]
        LSRA
        LDAB    6
        JSR     jr_mul8
        ADDA    [BP_T]
        STAA    [BP_I]
        LDX     BP_B
        JSR     jr_add_x_a
        LDAA    [X]
        BNE     bp_brick_struck
        RTS
bp_brick_struck:
        JSR     bp_brick_cell
        LDX     BP_B
        LDAA    [BP_I]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    1
        BNE     bp_brick_armor
        LDAA    [BP_EFX]
        LDAB    [BP_EFY]
        JSR     bp_vanish
bp_brick_armor:
        LDX     BP_B
        LDAA    [BP_I]
        JSR     jr_add_x_a
        DEC     [X]
        BEQ     bp_brick_flip
        JSR     bp_brick_cell
        LDAA    [BP_EFX]
        LDAB    [BP_EFY]
        JSR     bp_impact
bp_brick_flip:
        LDAA    [BP_DY]
        EORA    1
        STAA    [BP_DY]
        LDX     BP_B
        LDAA    [BP_I]
        JSR     jr_add_x_a
        TST     [X]
        BNE     bp_brick_sound
        DEC     [BP_LEFT]
        INC     [BP_BROKEN]
        LDAA    [BP_BROKEN]
        LDAB    3
        JSR     jr_divmod8
        TSTB
        BNE     bp_brick_sound
        ADDA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_divmod8
        INCB
        PSHB
        LDAA    [BP_X]
        STAA    [BP_EFX]
        LDAA    [BP_Y]
        STAA    [BP_EFY]
        PULA
        JSR     bp_drop
bp_brick_sound:
        LDAA    1
        JMP     bp_sound

; BP_I -> BP_EFX = 1 + i % 6 * 5, BP_EFY = 2 + i // 6 * 2.
bp_brick_cell:
        LDAA    [BP_I]
        LDAB    6
        JSR     jr_divmod8
        ASLA
        ADDA    2
        STAA    [BP_EFY]
        TBA
        ASLA
        ASLA
        ABA
        INCA
        STAA    [BP_EFX]
        RTS

bp_drone_hit:
        TST     [BP_ENEMY]
        BEQ     bp_drone_done
        LDAA    [BP_Y]
        CMPA    10
        BNE     bp_drone_done
        LDAA    [BP_X]
        INCA
        CMPA    [BP_EX]
        BCS     bp_drone_done
        LDAA    [BP_EX]
        INCA
        CMPA    [BP_X]
        BCS     bp_drone_done
        DEC     [BP_ENEMY]
        LDAA    [BP_DY]
        EORA    1
        STAA    [BP_DY]
        LDAA    1
        JSR     bp_sound
        LDAA    [BP_EX]
        LDAB    12
        TST     [BP_ENEMY]
        BEQ     bp_drone_gone
        JMP     bp_impact
bp_drone_gone:
        JSR     bp_vanish
        LDAA    [BP_EX]
        STAA    [BP_EFX]
        LDAA    10
        STAA    [BP_EFY]
        LDAA    3
        JMP     bp_drop
bp_drone_done:
        RTS

bp_paddle_hit:
        LDAA    [BP_Y]
        CMPA    16
        BNE     bp_drone_done
        LDAA    [BP_X]
        JSR     bp_on_paddle
        BCS     bp_paddle_missed
        CLR     [BP_DY]
        INC     [BP_BOUNCES]
        LDAA    [BP_WIDTH]
        LSRA
        ADDA    [BP_PADDLE]
        STAA    [BP_MID]
        CLR     [BP_STEEP]
        LDAA    [BP_X]
        CMPA    [BP_MID]
        BEQ     bp_paddle_steep
        INCA
        CMPA    [BP_MID]
        BNE     bp_paddle_side
bp_paddle_steep:
        LDAA    1
        STAA    [BP_STEEP]
bp_paddle_side:
        CLR     [BP_DX]
        LDAA    [BP_X]
        CMPA    [BP_MID]
        BCS     bp_paddle_sound
        LDAA    1
        STAA    [BP_DX]
bp_paddle_sound:
        CLRA
        JMP     bp_sound
bp_paddle_missed:
        TST     [BP_GUARD]
        BEQ     bp_paddle_lost
        CLR     [BP_GUARD]
        CLR     [BP_DY]
        LDAA    1
        JMP     bp_sound
bp_paddle_lost:
        DEC     [BP_HP]
        LDAA    3
        JSR     bp_sound
        LDAA    [BP_X]
        INCA
        LDAB    18
        JSR     bp_impact
        TST     [BP_HP]
        BEQ     bp_drone_done
        JMP     bp_serve

; ---------------------------------------------------------------- effects

bp_sound:
        TST     [BP_QUIET]
        BNE     bp_effect_skip
        JMP     jr_port_sound
bp_effect_skip:
        RTS

; A = x, B = y -> X = VRAM code address of that cell.
bp_vram:
        JSR     jr_gfx_at
        LDAA    [JR_RT_CURSOR]
        ADDA    (JR200_SCREEN_CODES >> 8) - (JR_SHADOW >> 8)
        STAA    [BP_EFP]
        LDAA    [JR_RT_CURSOR + 1]
        STAA    [BP_EFP + 1]
        LDX     [BP_EFP]
        RTS

; A = code, B = attribute: fill the 2x2 cell at BP_EFX, BP_EFY in VRAM.
bp_cell_write:
        PSHB
        PSHA
        LDAA    [BP_EFX]
        LDAB    [BP_EFY]
        JSR     bp_vram
        PULA
        STAA    [X]
        STAA    [X + 1]
        STAA    [X + 32]
        STAA    [X + 33]
        LDAA    [BP_EFP]
        ADDA    4
        STAA    [BP_EFP]
        LDX     [BP_EFP]
        PULB
        STAB    [X]
        STAB    [X + 1]
        STAB    [X + 32]
        STAB    [X + 33]
        RTS

; impact(x, y): two blinks of the struck 2x2 cell (the game clock stops).
bp_impact:
        TST     [BP_QUIET]
        BNE     bp_effect_skip
        STAA    [BP_EFX]
        STAB    [BP_EFY]
        JSR     jr_port_render
        LDAA    2
        STAA    [BP_EFN]
bp_impact_blink:
        LDAA    BP_CHAR_BLOCK
        LDAB    BP_ATTR_HIT
        JSR     bp_cell_write
        LDAA    4
        JSR     bp_hold_input
        JSR     jr_gfx_present
        LDAA    4
        JSR     bp_hold_input
        DEC     [BP_EFN]
        BNE     bp_impact_blink
        RTS

; vanish(x, y): four burst frames in the 2x2 cell (the game clock stops).
bp_vanish:
        TST     [BP_QUIET]
        BNE     bp_effect_skip
        STAA    [BP_EFX]
        STAB    [BP_EFY]
        JSR     jr_port_render
        LDX     bp_sfx_vanish
        JSR     jr_sfx_play
        CLR     [BP_EFN]
bp_vanish_frame:
        LDAA    [BP_EFX]
        LDAB    [BP_EFY]
        JSR     bp_vram
        LDAA    [BP_EFN]
        ASLA
        ASLA
        ADDA    BP_TILE_BURST
        STAA    [X]
        INCA
        STAA    [X + 1]
        INCA
        STAA    [X + 32]
        INCA
        STAA    [X + 33]
        LDAA    [BP_EFP]
        ADDA    4
        STAA    [BP_EFP]
        LDX     [BP_EFP]
        LDAA    BP_ATTR_BURST
        STAA    [X]
        STAA    [X + 1]
        STAA    [X + 32]
        STAA    [X + 33]
        LDAA    2
        JSR     bp_hold_input
        INC     [BP_EFN]
        LDAA    [BP_EFN]
        CMPA    4
        BNE     bp_vanish_frame
        RTS

; Keep brief A/D taps while a brick effect pauses the main game loop.
; jr_port_hold polls the MCU but discards non-exit key events.
bp_hold_input:
        STAA    [BP_WAIT_FRAMES]
bp_hold_input_frame:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        JSR     jr_keys_poll
        CMPA    JR_KEY_EXIT
        BNE     bp_hold_input_direction
        JMP     jr_session_leave
bp_hold_input_direction:
        CMPA    JR_KEY_LEFT
        BEQ     bp_hold_input_move
        CMPA    JR_KEY_RIGHT
        BNE     bp_hold_input_next
bp_hold_input_move:
        JSR     game_act
        JSR     jr_port_render
bp_hold_input_next:
        DEC     [BP_WAIT_FRAMES]
        BNE     bp_hold_input_frame
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    BP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     bp_hud
        JSR     jr_gfx_lines
        LDAA    BP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; bricks: cap, body x2, cap at (1 + i % 6 * 5, 2 + i // 6 * 2)
        CLR     [BP_DI]
bp_draw_brick:
        LDX     BP_B
        LDAA    [BP_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     bp_draw_brick_next
        STAA    [BP_DN]
        LDX     bp_brick_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [BP_DI]
        LDAB    6
        JSR     jr_divmod8
        ASLA
        ADDA    2
        STAA    [BP_DRAW_Y]
        TBA
        ASLA
        ASLA
        ABA
        INCA
        LDAB    [BP_DRAW_Y]
        JSR     jr_gfx_at
        LDAA    BP_CHAR_CAP_L
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_BODY
        ADDA    [BP_DN]
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_CAP_R
        JSR     jr_gfx_putc
bp_draw_brick_next:
        INC     [BP_DI]
        LDAA    [BP_DI]
        CMPA    24
        BNE     bp_draw_brick
        ; drone
        TST     [BP_ENEMY]
        BEQ     bp_draw_bomb
        LDAA    BP_ATTR_DRONE
        STAA    [JR_RT_COLOR]
        LDAA    [BP_EX]
        LDAB    12
        JSR     jr_gfx_at
        LDAA    BP_CHAR_DRONE
        JSR     jr_gfx_putc
        INCA
        JSR     jr_gfx_putc
        INCA
        JSR     jr_gfx_putc
bp_draw_bomb:
        TST     [BP_BOMB]
        BEQ     bp_draw_item
        LDAA    BP_ATTR_BOMB
        STAA    [JR_RT_COLOR]
        LDAA    [BP_BX]
        INCA
        LDAB    [BP_BOMB]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    BP_CHAR_BOMB
        JSR     jr_gfx_putc
bp_draw_item:
        TST     [BP_ITEM]
        BEQ     bp_draw_ball
        LDX     bp_item_look
        LDAA    [BP_ITEM]
        ASLA
        JSR     jr_add_x_a
        LDAA    [X + 1]
        STAA    [JR_RT_COLOR]
        LDAA    [X]
        STAA    [BP_DN]
        LDAA    [BP_IX]
        INCA
        LDAB    [BP_IY]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [BP_DN]
        JSR     jr_gfx_putc
bp_draw_ball:
        LDAA    BP_ATTR_BALL
        STAA    [JR_RT_COLOR]
        LDAA    [BP_X]
        INCA
        LDAB    [BP_Y]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    BP_CHAR_BALL
        JSR     jr_gfx_putc
        ; paddle: left cap, width - 2 middles, right cap on row 19
        LDAA    BP_ATTR_PADDLE
        TST     [BP_WIDE]
        BEQ     bp_draw_paddle_jam
        LDAA    BP_ATTR_WIDE
bp_draw_paddle_jam:
        TST     [BP_JAM]
        BEQ     bp_draw_paddle_color
        LDAA    BP_ATTR_JAM
bp_draw_paddle_color:
        STAA    [JR_RT_COLOR]
        LDAA    [BP_PADDLE]
        INCA
        LDAB    19
        JSR     jr_gfx_at
        LDAA    BP_CHAR_PAD_L
        JSR     jr_gfx_putc
        LDAB    [BP_WIDTH]
        SUBB    2
        LDAA    BP_CHAR_PAD_M
bp_draw_paddle_mid:
        JSR     jr_gfx_putc
        DECB
        BNE     bp_draw_paddle_mid
        LDAA    BP_CHAR_PAD_R
        JSR     jr_gfx_putc
        ; guard line and counters
        TST     [BP_GUARD]
        BEQ     bp_draw_counters
        LDAA    BP_ATTR_GUARD
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDX     bp_txt_guard_line
        JSR     jr_gfx_text
bp_draw_counters:
        LDAA    BP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    6
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [BP_HP]
        JSR     jr_gfx_dec3
        LDAA    16
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [BP_LEFT]
        JSR     jr_gfx_dec3
        LDAA    28
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [BP_ENEMY]
        JSR     jr_gfx_dec3
        LDAA    BP_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        TST     [BP_WIDE]
        BEQ     bp_draw_jam_label
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDX     bp_txt_wide
        JSR     jr_gfx_text
bp_draw_jam_label:
        TST     [BP_JAM]
        BEQ     bp_draw_slow_label
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDX     bp_txt_jam
        JSR     jr_gfx_text
bp_draw_slow_label:
        TST     [BP_SLOW]
        BEQ     bp_draw_guard_label
        LDAA    10
        LDAB    22
        JSR     jr_gfx_at
        LDX     bp_txt_slow
        JSR     jr_gfx_text
bp_draw_guard_label:
        TST     [BP_GUARD]
        BEQ     bp_draw_done
        LDAA    20
        LDAB    22
        JSR     jr_gfx_at
        LDX     bp_txt_guard
        JSR     jr_gfx_text
        BRA     bp_draw_done
bp_draw_done:
        TST     [BP_DEMO]
        BEQ     bp_draw_end
        LDAA    BP_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        LDAA    14
        CLRB
        JSR     jr_gfx_at
        LDX     bp_txt_demo
        JMP     jr_gfx_text
bp_draw_end:
        RTS

game_draw_title:
        CLR     [BP_DEMO]
        LDAA    0x20
        LDAB    BP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     bp_title_lines
        JSR     jr_gfx_lines
        ; a row of bricks, a ball and a paddle
        CLR     [BP_DI]
bp_title_brick:
        LDX     bp_brick_attr
        LDAA    [BP_DI]
        ANDA    3
        INCA
        CMPA    4
        BNE     bp_title_brick_hits
        LDAA    1
bp_title_brick_hits:
        STAA    [BP_DN]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [BP_DI]
        ASLA
        ASLA
        ADDA    [BP_DI]
        INCA
        LDAB    3
        JSR     jr_gfx_at
        LDAA    BP_CHAR_CAP_L
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_BODY
        ADDA    [BP_DN]
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_CAP_R
        JSR     jr_gfx_putc
        INC     [BP_DI]
        LDAA    [BP_DI]
        CMPA    6
        BNE     bp_title_brick
        LDAA    BP_ATTR_BALL
        STAA    [JR_RT_COLOR]
        LDAA    18
        LDAB    6
        JSR     jr_gfx_at
        LDAA    BP_CHAR_BALL
        JSR     jr_gfx_putc
        LDAA    BP_ATTR_PADDLE
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    8
        JSR     jr_gfx_at
        LDAA    BP_CHAR_PAD_L
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_PAD_M
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    BP_CHAR_PAD_R
        JMP     jr_gfx_putc

game_draw_help:
        LDAA    0x20
        LDAB    BP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     bp_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- self test

; T on the title runs the rule fixtures and the autoplay of all arenas, then
; returns to the title. Results stay in RAM from BP_RESULTS for the runner.
game_raw_key:
        TBA
        ORAA    0x20
        CMPA    0x74
        BEQ     bp_self_test
        CMPA    0x70
        BNE     bp_raw_ignore
        ; P: start arena 1 with the self-test autopilot at normal speed (demo).
        LDAA    1
        STAA    [BP_DEMO]
        LDAA    JR_KEY_CONFIRM
        RTS
bp_raw_ignore:
        CLRA
        RTS
bp_self_test:
        LDAA    1
        STAA    [BP_QUIET]
        LDX     bp_txt_testing
        JSR     bp_title_message
        LDX     bp_fixtures
        STX     [BP_FIX]
        LDX     BP_RESULTS
        STX     [BP_OUT]
bp_self_fixture:
        LDX     [BP_FIX]
        LDAA    [X]
        CMPA    0xff
        BEQ     bp_self_auto
        JSR     bp_start_level
        LDX     [BP_FIX]
        LDAA    [X + 1]
        STAA    [BP_HELD]
        LDAA    [X + 2]
        STAA    [BP_PAIRS]
        INX
        INX
        INX
bp_self_pair:
        TST     [BP_PAIRS]
        BEQ     bp_self_run
        LDAA    [X]
        LDAB    [X + 1]
        INX
        INX
        STX     [BP_FIX]
        LDX     GAME_STATE
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [BP_FIX]
        DEC     [BP_PAIRS]
        BRA     bp_self_pair
bp_self_run:
        STX     [BP_FIX]
        JSR     game_tick
        JSR     bp_store_state
        BRA     bp_self_fixture
bp_self_auto:
        CLR     [BP_AUTO_LEVEL]
bp_self_auto_level:
        LDAA    [BP_AUTO_LEVEL]
        JSR     bp_start_level
        CLR     [BP_TICKS]
        CLR     [BP_TICKS + 1]
bp_self_auto_tick:
        JSR     bp_autopilot
        JSR     game_tick
        LDX     [BP_TICKS]
        INX
        STX     [BP_TICKS]
        LDAA    [BP_TICKS + 1]
        BNE     bp_self_auto_check
        JSR     jr_keys_poll
        CMPA    JR_KEY_EXIT
        BNE     bp_self_auto_check
        JMP     jr_session_leave
bp_self_auto_check:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     bp_self_auto_store
        LDX     [BP_TICKS]
        CPX     BP_AUTO_LIMIT
        BNE     bp_self_auto_tick
bp_self_auto_store:
        JSR     bp_store_state
        LDX     [BP_OUT]
        LDAA    [BP_TICKS]
        STAA    [X]
        LDAA    [BP_TICKS + 1]
        STAA    [X + 1]
        INX
        INX
        STX     [BP_OUT]
        INC     [BP_AUTO_LEVEL]
        LDAA    [BP_AUTO_LEVEL]
        CMPA    GAME_LEVELS
        BNE     bp_self_auto_level
        CLR     [BP_QUIET]
        CLR     [JR_PORT_MODE]
        CLR     [JR_PORT_LEVEL]
        JSR     jr_sfx_stop
        LDX     bp_txt_tested
        JSR     bp_title_message
        CLRA
        RTS
bp_title_message:
        STX     [BP_COPY]
        JSR     game_draw_title
        LDAA    BP_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    9
        JSR     jr_gfx_at
        LDX     [BP_COPY]
        JSR     jr_gfx_text
        JMP     jr_gfx_present

; A = arena index: clear the stage state and run game_init, like the loop.
bp_start_level:
        STAA    [JR_PORT_LEVEL]
        LDX     GAME_STATE
bp_start_clear:
        CLR     [X]
        INX
        CPX     GAME_STATE_END
        BNE     bp_start_clear
        LDAA    JR_MODE_PLAY
        STAA    [JR_PORT_MODE]
        JMP     game_init

; Copies the 51 state bytes and the mode to BP_OUT and advances it.
bp_store_state:
        LDX     GAME_STATE
        STX     [JR_RT_SRC]
        LDX     [BP_OUT]
        STX     [JR_RT_DST]
        LDX     BP_STATE_SIZE
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDX     [JR_RT_COUNT]
        LDAA    [JR_PORT_MODE]
        STAA    [X]
        INX
        STX     [BP_OUT]
        RTS

; Autopilot for the self test: aim the paddle so the ball meets its middle.
bp_autopilot:
        LDAA    [BP_WIDTH]
        LSRA
        STAA    [BP_T]
        LDAA    [BP_X]
        SUBA    [BP_T]
        BCC     bp_auto_max
        CLRA
bp_auto_max:
        STAA    [BP_MID]
        LDAA    30
        SUBA    [BP_WIDTH]
        CMPA    [BP_MID]
        BCC     bp_auto_choose
        STAA    [BP_MID]
bp_auto_choose:
        CLRB
        LDAA    [BP_PADDLE]
        SUBA    [BP_MID]
        BCS     bp_auto_right
        CMPA    2
        BCS     bp_auto_store
        LDAB    3
        BRA     bp_auto_store
bp_auto_right:
        NEGA
        CMPA    2
        BCS     bp_auto_store
        LDAB    4
bp_auto_store:
        STAB    [BP_HELD]
        RTS

; ---------------------------------------------------------------- data

; levels.json: twelve arenas of 24 bricks.
bp_arenas:
        .db     1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0
        .db     0, 0, 1, 1, 0, 0, 0, 1, 2, 2, 1, 0, 1, 2, 1, 1, 2, 1, 1, 1, 0, 0, 1, 1
        .db     1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 2, 2, 0, 0, 0, 1, 0, 0, 1, 0
        .db     2, 0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 0, 1, 2, 2, 1, 0, 0, 0, 1, 1, 0, 0
        .db     2, 0, 2, 0, 2, 0, 0, 2, 0, 2, 0, 2, 2, 1, 2, 1, 2, 1, 1, 2, 1, 2, 1, 2
        .db     2, 2, 2, 2, 2, 2, 1, 0, 1, 1, 0, 1, 2, 1, 2, 2, 1, 2, 0, 1, 0, 0, 1, 0
        .db     0, 0, 3, 3, 0, 0, 0, 3, 2, 2, 3, 0, 3, 2, 1, 1, 2, 3, 2, 1, 0, 0, 1, 2
        .db     3, 0, 2, 2, 0, 3, 2, 3, 0, 0, 3, 2, 1, 2, 3, 3, 2, 1, 0, 1, 1, 1, 1, 0
        .db     3, 3, 3, 3, 3, 3, 0, 2, 0, 0, 2, 0, 2, 2, 2, 2, 2, 2, 1, 0, 1, 1, 0, 1
        .db     3, 0, 3, 0, 3, 0, 0, 3, 0, 3, 0, 3, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 1, 2
        .db     3, 2, 3, 3, 2, 3, 2, 3, 2, 2, 3, 2, 3, 2, 1, 1, 2, 3, 2, 2, 3, 3, 2, 2
        .db     3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 3, 2, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2
; hits -> brick attribute (index 0 unused).
bp_brick_attr:
        .db     0x47, 0x46, 0x43, 0x42
; item -> letter, attribute (index 0 unused): W wide, S slow, G guard.
bp_item_look:
        .db     0x20, 0x07, 0x57, 0x05, 0x53, 0x04, 0x47, 0x06

bp_hud:
        .db     1, 0, BP_ATTR_TITLE
        .dw     bp_txt_name
        .db     23, 0, BP_ATTR_LABEL
        .dw     bp_txt_stage
        .db     1, 21, BP_ATTR_LABEL
        .dw     bp_txt_ball
        .db     10, 21, BP_ATTR_LABEL
        .dw     bp_txt_brick
        .db     22, 21, BP_ATTR_LABEL
        .dw     bp_txt_drone
        .db     0xff
bp_title_lines:
        .db     10, 11, BP_ATTR_TITLE
        .dw     bp_txt_name
        .db     6, 13, BP_ATTR_LABEL
        .dw     bp_txt_tagline
        .db     8, 16, BP_ATTR_TEXT
        .dw     bp_txt_start
        .db     5, 18, BP_ATTR_TEXT
        .dw     bp_txt_howto
        .db     5, 20, BP_ATTR_LABEL
        .dw     bp_txt_demo_hint
        .db     4, 22, 0x01
        .dw     bp_txt_credit
        .db     0xff
bp_help_lines:
        .db     10, 2, BP_ATTR_TITLE
        .dw     bp_txt_name
        .db     2, 5, BP_ATTR_TEXT
        .dw     bp_help_1
        .db     2, 7, BP_ATTR_TEXT
        .dw     bp_help_2
        .db     2, 9, BP_ATTR_TEXT
        .dw     bp_help_3
        .db     2, 11, BP_ATTR_TEXT
        .dw     bp_help_4
        .db     2, 13, BP_ATTR_TEXT
        .dw     bp_help_5
        .db     2, 15, BP_ATTR_TEXT
        .dw     bp_help_6
        .db     2, 17, BP_ATTR_TEXT
        .dw     bp_help_7
        .db     2, 20, BP_ATTR_LABEL
        .dw     bp_help_back
        .db     0xff

bp_txt_name:
        .db     "BRICK PULSE", 0
bp_txt_stage:
        .db     "STAGE", 0
bp_txt_ball:
        .db     "BALL", 0
bp_txt_brick:
        .db     "BRICK", 0
bp_txt_drone:
        .db     "DRONE", 0
bp_txt_wide:
        .db     "WIDE", 0
bp_txt_jam:
        .db     "JAM", 0
bp_txt_slow:
        .db     "SLOW", 0
bp_txt_guard:
        .db     "GUARD", 0
bp_txt_guard_line:
        .db     "------------------------------", 0
bp_txt_tagline:
        .db     "12 ARENAS / 3 BALLS EACH", 0
bp_txt_start:
        .db     "RETURN : START", 0
bp_txt_howto:
        .db     "W/S : HOW TO PLAY", 0
bp_txt_demo_hint:
        .db     "P : WATCH A DEMO", 0
bp_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
bp_txt_demo:
        .db     "DEMO", 0
bp_txt_testing:
        .db     "SELF TEST RUNNING", 0
bp_txt_tested:
        .db     "SELF TEST FINISHED", 0
bp_help_1:
        .db     "HOLD A/D : MOVE THE PADDLE", 0
bp_help_2:
        .db     "12 ARENAS / THREE BALLS EACH", 0
bp_help_3:
        .db     "W WIDE / S SLOW / G GUARD", 0
bp_help_4:
        .db     "ARMORED BRICKS NEED MORE HITS", 0
bp_help_5:
        .db     "HIT DRONES / DODGE BOMBS.", 0
bp_help_6:
        .db     "CLEAR BRICKS AND DRONE TO WIN", 0
bp_help_7:
        .db     "CTRL+C : BACK TO BASIC", 0
bp_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     bp_sfx_bounce, bp_sfx_hit, bp_sfx_catch, bp_sfx_lost
bp_sfx_bounce:
        .db     90, 1, 0, 0
bp_sfx_hit:
        .db     60, 1, 0, 0
bp_sfx_catch:
        .db     100, 2, 70, 2, 50, 3, 0, 0
bp_sfx_lost:
        .db     180, 4, 220, 6, 0, 0
bp_sfx_vanish:
        .db     50, 2, 80, 2, 110, 3, 0, 0

        .include "fixtures.inc"
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
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"

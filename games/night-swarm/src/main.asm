; SPDX-License-Identifier: MIT
; NIGHT SWARM for JR-200: a port of jr100dev games/night_swarm/rules.py 3.0.0.
; Six waves, eight-way movement, the portal preview, armored and plain foes
; marching toward the ship every third tick, auto fire every fourth, the
; area pulse and its cooldown, salvage cells that heal, and the hull follow
; the upstream source, one upstream tick per game_tick. Rules are checked by
; the in-program self test (sdk/selftest.inc, title key T); P plays the
; wave-1 demo.
        .filename.jr "NIGHT-SWARM"
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
; Upstream ticks every 10 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    3
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    40
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    NS_HELD

NS_EMPTY:           .equ    255

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
NS_POS:             .equ    GAME_STATE
NS_ORIGIN:          .equ    GAME_STATE + 1
NS_FACING:          .equ    GAME_STATE + 2
NS_HP:              .equ    GAME_STATE + 3
NS_LIMIT:           .equ    GAME_STATE + 4
NS_PERIOD:          .equ    GAME_STATE + 5
NS_CELL:            .equ    GAME_STATE + 6
NS_TIME:            .equ    GAME_STATE + 7
NS_COOLDOWN:        .equ    GAME_STATE + 8
NS_SPAWN:           .equ    GAME_STATE + 9
NS_PORTAL:          .equ    GAME_STATE + 10
NS_ENTRY:           .equ    GAME_STATE + 11
NS_KILLS:           .equ    GAME_STATE + 12
NS_SALVAGE:         .equ    GAME_STATE + 13
NS_PULSE:           .equ    GAME_STATE + 14
NS_MARCHING:        .equ    GAME_STATE + 15
NS_B:               .equ    GAME_STATE + 16     ; foe cells (8)
NS_C:               .equ    GAME_STATE + 24     ; foe armor (8)
NS_D:               .equ    GAME_STATE + 32     ; cells they marched from (8)
NS_FLASH:           .equ    GAME_STATE + 40     ; cell + 1 of an effect
NS_FLASH_ATTR:      .equ    GAME_STATE + 41
NS_SHOT:            .equ    GAME_STATE + 42     ; cell + 1 of an auto-fire shot
NS_HELD:            .equ    GAME_STATE + 43     ; unused (no held keys)
NS_I:               .equ    GAME_STATE + 44
NS_P:               .equ    GAME_STATE + 45
NS_T:               .equ    GAME_STATE + 46
NS_U:               .equ    GAME_STATE + 47
NS_MOVING:          .equ    GAME_STATE + 48
NS_HIT:             .equ    GAME_STATE + 49
NS_DI:              .equ    GAME_STATE + 50
NS_DT:              .equ    GAME_STATE + 51
NS_DY:              .equ    GAME_STATE + 52
NS_DCODE:           .equ    GAME_STATE + 53
NS_DQ:              .equ    GAME_STATE + 54
NS_DA:              .equ    GAME_STATE + 55
NS_DB:              .equ    GAME_STATE + 56

NS_TILE_FLOOR:      .equ    0x80
NS_TILE_FOE:        .equ    0x84
NS_TILE_WEAK:       .equ    0x88
NS_TILE_CELL:       .equ    0x8c
NS_TILE_PORTAL:     .equ    0x90
NS_TILE_SHIP:       .equ    0x00        ; + 4 * (facing - 1)
NS_CHAR_PULSE:      .equ    0x10
NS_ATTR_FLOOR:      .equ    0x41
NS_ATTR_FOE:        .equ    0x42
NS_ATTR_WEAK:       .equ    0x43
NS_ATTR_CELL:       .equ    0x44
NS_ATTR_PORTAL:     .equ    0x45
NS_ATTR_SHIP:       .equ    0x47
NS_ATTR_PULSE:      .equ    0x46
NS_ATTR_HIT:        .equ    0x72        ; red on yellow
NS_ATTR_VANISH:     .equ    0x7e        ; yellow on white
NS_ATTR_SPARK:      .equ    0x6d        ; cyan on green
NS_ATTR_TEXT:       .equ    0x07
NS_ATTR_LABEL:      .equ    0x04
NS_ATTR_TITLE:      .equ    0x06
NS_ATTR_DIM:        .equ    0x05
NS_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     ns_patterns
        LDAA    NS_TILE_FLOOR
        LDAB    20
        JSR     jr_pcg_load
        LDX     ns_ship_patterns
        CLRA
        LDAB    17
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    27
        STAA    [NS_POS]
        STAA    [NS_ORIGIN]
        LDAA    2
        STAA    [NS_FACING]
        LDAA    4
        STAA    [NS_HP]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ADDA    12
        STAA    [NS_LIMIT]
        LDAB    4
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     ns_init_period
        LDAB    3
ns_init_period:
        STAB    [NS_PERIOD]
        LDAA    NS_EMPTY
        STAA    [NS_CELL]
        LDX     NS_B
ns_init_foes:
        STAA    [X]
        INX
        CPX     NS_B + 8
        BNE     ns_init_foes

; portal = ((spawn % 28) * 9 % 28 + level * 7) % 28 round the edge:
; top 0-7, right 8-13, bottom 14-21, left 22-27.
ns_preview:
        LDAA    [NS_SPAWN]
        JSR     ns_mod28
        STAA    [NS_T]
        ASLA
        ASLA
        ASLA
        ADDA    [NS_T]
        JSR     ns_mod28
        STAA    [NS_T]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ASLA
        ASLA
        SUBA    [JR_PORT_LEVEL]
        ADDA    [NS_T]
        JSR     ns_mod28
        STAA    [NS_PORTAL]
        CMPA    8
        BCC     ns_preview_right
        STAA    [NS_ENTRY]
        RTS
ns_preview_right:
        CMPA    14
        BCC     ns_preview_bottom
        SUBA    7
        ASLA
        ASLA
        ASLA
        ADDA    7
        STAA    [NS_ENTRY]
        RTS
ns_preview_bottom:
        CMPA    22
        BCC     ns_preview_left
        NEGA
        ADDA    77
        STAA    [NS_ENTRY]
        RTS
ns_preview_left:
        NEGA
        ADDA    28
        ASLA
        ASLA
        ASLA
        STAA    [NS_ENTRY]
        RTS

ns_mod28:
        CMPA    28
        BCS     ns_mod28_done
        SUBA    28
        BRA     ns_mod28
ns_mod28_done:
        RTS

; A, B = cells -> A = |dx| + |dy|.
ns_distance:
        STAA    [NS_DA]
        STAB    [NS_DB]
        ANDA    7
        ANDB    7
        SBA
        BCC     ns_distance_x
        NEGA
ns_distance_x:
        STAA    [NS_DQ]
        LDAA    [NS_DA]
        LDAB    [NS_DB]
        LSRA
        LSRA
        LSRA
        LSRB
        LSRB
        LSRB
        SBA
        BCC     ns_distance_y
        NEGA
ns_distance_y:
        ADDA    [NS_DQ]
        RTS

; A = position, B = action 1-4 or 9-12 -> A = moved position.
ns_move8:
        CMPB    9
        BCS     ns_move
        STAB    [NS_U]
        LDAB    JR_KEY_UP
        PSHA
        LDAA    [NS_U]
        CMPA    11
        PULA
        BCS     ns_move8_first
        LDAB    JR_KEY_DOWN
ns_move8_first:
        JSR     ns_move
        LDAB    JR_KEY_LEFT
        PSHA
        LDAA    [NS_U]
        CMPA    9
        BEQ     ns_move8_west
        CMPA    11
        BEQ     ns_move8_west
        LDAB    JR_KEY_RIGHT
ns_move8_west:
        PULA
; A = position, B = direction 1-4 -> A = moved position (8x8, stops at edges).
ns_move:
        STAA    [NS_T]
        CMPB    JR_KEY_UP
        BNE     ns_move_down
        CMPA    8
        BCS     ns_move_done
        SUBA    8
        RTS
ns_move_down:
        CMPB    JR_KEY_DOWN
        BNE     ns_move_side
        CMPA    56
        BCC     ns_move_done
        ADDA    8
        RTS
ns_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     ns_move_right
        TSTA
        BEQ     ns_move_stay
        LDAA    [NS_T]
        DECA
        RTS
ns_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     ns_move_stay
        CMPA    7
        BCC     ns_move_stay
        LDAA    [NS_T]
        INCA
        RTS
ns_move_stay:
        LDAA    [NS_T]
ns_move_done:
        RTS

; NS_I = foe: a hit wears its armor or destroys it (every fourth kill leaves
; a salvage cell); the wave is won at the kill limit.
ns_hurt:
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAA    [X]
        INCA
        STAA    [NS_FLASH]
        LDAA    [X + 8]
        CMPA    2
        BCS     ns_hurt_kill
        DEC     [X + 8]
        LDAA    NS_ATTR_HIT
        STAA    [NS_FLASH_ATTR]
        LDX     ns_sfx_armor
        JSR     jr_sfx_play
        BRA     ns_hurt_show
ns_hurt_kill:
        LDAA    [NS_KILLS]
        ANDA    3
        CMPA    3
        BNE     ns_hurt_gone
        LDAA    [X]
        STAA    [NS_CELL]
ns_hurt_gone:
        LDAA    NS_EMPTY
        STAA    [X]
        INC     [NS_KILLS]
        LDAA    NS_ATTR_VANISH
        STAA    [NS_FLASH_ATTR]
        LDAA    1
        JSR     jr_port_sound
ns_hurt_show:
        LDAA    4
        JSR     jr_test_animate
        CLR     [NS_FLASH]
        LDAA    [NS_KILLS]
        CMPA    [NS_LIMIT]
        BCS     ns_act_done
        JMP     jr_port_win

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     ns_act_pulse
        CMPA    9
        BCC     ns_act_move
        CMPA    JR_KEY_CONFIRM
        BCC     ns_act_done
ns_act_move:
        ; facing: the direction, or west / east for the diagonals
        TAB
        CMPA    5
        BCS     ns_act_face
        LDAA    JR_KEY_LEFT
        CMPB    9
        BEQ     ns_act_face
        CMPB    11
        BEQ     ns_act_face
        LDAA    JR_KEY_RIGHT
ns_act_face:
        STAA    [NS_FACING]
        LDAA    [NS_POS]
        STAA    [NS_ORIGIN]
        JSR     ns_move8
        STAA    [NS_POS]
        LDAA    2
        JSR     jr_test_animate
        LDAA    [NS_POS]
        STAA    [NS_ORIGIN]
        CMPA    [NS_CELL]
        BNE     ns_act_done
        ; salvage: heal one (up to 4) and ready the pulse
        LDAA    NS_EMPTY
        STAA    [NS_CELL]
        LDAA    [NS_HP]
        CMPA    4
        BCC     ns_act_salvage
        INC     [NS_HP]
ns_act_salvage:
        CLR     [NS_COOLDOWN]
        INC     [NS_SALVAGE]
        LDAA    [NS_POS]
        INCA
        STAA    [NS_FLASH]
        LDAA    NS_ATTR_SPARK
        STAA    [NS_FLASH_ATTR]
        LDAA    1
        JSR     jr_port_sound
        LDAA    6
        JSR     jr_test_animate
        CLR     [NS_FLASH]
ns_act_done:
        RTS
ns_act_pulse:
        TST     [NS_COOLDOWN]
        BNE     ns_act_done
        LDX     ns_sfx_pulse
        JSR     jr_sfx_play
        LDAA    1
ns_act_ring:
        STAA    [NS_PULSE]
        LDAA    3
        JSR     jr_test_animate
        LDAA    [NS_PULSE]
        INCA
        CMPA    4
        BNE     ns_act_ring
        CLR     [NS_PULSE]
        CLR     [NS_I]
ns_act_blast:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     ns_act_blast_next
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAB    [X]
        CMPB    NS_EMPTY
        BEQ     ns_act_blast_next
        LDAA    [NS_POS]
        JSR     ns_distance
        CMPA    4
        BCC     ns_act_blast_next
        JSR     ns_hurt
ns_act_blast_next:
        INC     [NS_I]
        LDAA    [NS_I]
        CMPA    8
        BNE     ns_act_blast
        LDAA    8
        STAA    [NS_COOLDOWN]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     ns_act_done
        INC     [NS_TIME]
        TST     [NS_COOLDOWN]
        BEQ     ns_tick_march
        DEC     [NS_COOLDOWN]
ns_tick_march:
        LDAA    [NS_TIME]
        LDAB    3
        JSR     ns_mod
        TSTA
        BEQ     ns_tick_march_go
        JMP     ns_tick_spawn
ns_tick_march_go:
        ; every third tick each foe steps toward the ship: rows first on
        ; alternate foes and ticks, otherwise columns first
        CLR     [NS_MOVING]
        CLR     [NS_I]
ns_tick_foe:
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [X + 16]
        CMPA    NS_EMPTY
        BEQ     ns_tick_foe_next
        STAA    [NS_MOVING]
        STAA    [NS_P]
        LDAA    [NS_TIME]
        ADDA    [NS_I]
        ANDA    1
        BNE     ns_tick_foe_column
        JSR     ns_row_step
        BNE     ns_tick_foe_store
ns_tick_foe_column:
        LDAA    [NS_P]
        ANDA    7
        STAA    [NS_T]
        LDAB    [NS_POS]
        ANDB    7
        CMPB    [NS_T]
        BEQ     ns_tick_foe_row
        LDAA    [NS_P]
        BCS     ns_tick_foe_west
        INCA
        BRA     ns_tick_foe_set
ns_tick_foe_west:
        DECA
ns_tick_foe_set:
        STAA    [NS_P]
        BRA     ns_tick_foe_store
ns_tick_foe_row:
        JSR     ns_row_step
ns_tick_foe_store:
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAA    [NS_P]
        STAA    [X]
ns_tick_foe_next:
        INC     [NS_I]
        LDAA    [NS_I]
        CMPA    8
        BNE     ns_tick_foe
        TST     [NS_MOVING]
        BEQ     ns_tick_contact
        LDAA    1
        STAA    [NS_MARCHING]
        LDAA    3
        JSR     jr_test_animate
        CLR     [NS_MARCHING]
ns_tick_contact:
        ; foes that reach the ship crash into it: one hull for any number
        CLR     [NS_HIT]
        LDX     NS_B
ns_tick_contact_foe:
        LDAA    [X]
        CMPA    [NS_POS]
        BNE     ns_tick_contact_next
        LDAA    NS_EMPTY
        STAA    [X]
        LDAA    1
        STAA    [NS_HIT]
ns_tick_contact_next:
        INX
        CPX     NS_B + 8
        BNE     ns_tick_contact_foe
        TST     [NS_HIT]
        BEQ     ns_tick_spawn
        DEC     [NS_HP]
        LDAA    [NS_POS]
        INCA
        STAA    [NS_FLASH]
        LDAA    NS_ATTR_HIT
        STAA    [NS_FLASH_ATTR]
        LDX     ns_sfx_crash
        JSR     jr_sfx_play
        LDAA    8
        JSR     jr_test_animate
        CLR     [NS_FLASH]
        TST     [NS_HP]
        BNE     ns_tick_spawn
        LDX     ns_txt_loss
        JMP     jr_port_lose
ns_tick_spawn:
        LDAA    [NS_TIME]
        LDAB    [NS_PERIOD]
        JSR     ns_mod
        TSTA
        BNE     ns_tick_fire
        ; the next foe arrives at the portal (plain on every third spawn)
        LDX     NS_B
ns_tick_spawn_slot:
        LDAA    [X]
        CMPA    NS_EMPTY
        BEQ     ns_tick_spawn_place
        INX
        CPX     NS_B + 8
        BNE     ns_tick_spawn_slot
        BRA     ns_tick_spawn_next
ns_tick_spawn_place:
        LDAA    [NS_ENTRY]
        STAA    [X]
        STAA    [X + 16]
        LDAA    [NS_SPAWN]
        ADDA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     ns_mod
        LDAB    1
        TSTA
        BEQ     ns_tick_spawn_armor
        INCB
ns_tick_spawn_armor:
        STAB    [X + 8]
ns_tick_spawn_next:
        INC     [NS_SPAWN]
        JSR     ns_preview
ns_tick_fire:
        ; auto fire on the first foe within two, every fourth tick
        LDAA    [NS_TIME]
        ANDA    3
        CMPA    1
        BNE     ns_tick_done
        CLR     [NS_I]
ns_tick_fire_foe:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     ns_tick_done
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAB    [X]
        CMPB    NS_EMPTY
        BEQ     ns_tick_fire_next
        LDAA    [NS_POS]
        JSR     ns_distance
        CMPA    3
        BCC     ns_tick_fire_next
        CLRA
        JSR     jr_port_sound
        LDX     NS_B
        LDAA    [NS_I]
        JSR     jr_add_x_a
        LDAA    [X]
        INCA
        STAA    [NS_SHOT]
        LDAA    4
        JSR     jr_test_animate
        CLR     [NS_SHOT]
        JMP     ns_hurt
ns_tick_fire_next:
        INC     [NS_I]
        LDAA    [NS_I]
        CMPA    8
        BNE     ns_tick_fire_foe
ns_tick_done:
        RTS

; NS_P one row toward the ship when they are on different rows (Z clear).
ns_row_step:
        LDAA    [NS_P]
        LSRA
        LSRA
        LSRA
        STAA    [NS_T]
        LDAB    [NS_POS]
        LSRB
        LSRB
        LSRB
        CMPB    [NS_T]
        BEQ     ns_row_step_done
        LDAA    [NS_P]
        BCS     ns_row_step_up
        ADDA    8
        BRA     ns_row_step_set
ns_row_step_up:
        SUBA    8
ns_row_step_set:
        STAA    [NS_P]
        CLRA
        INCA
ns_row_step_done:
        RTS

; A = value, B = divisor -> A = value mod divisor.
ns_mod:
        STAB    [NS_T]
ns_mod_next:
        CMPA    [NS_T]
        BCS     ns_tick_done
        SUBA    [NS_T]
        BRA     ns_mod_next

; ---------------------------------------------------------------- drawing

; A = cell, B = the cell it moves from -> A = x, B = y half-way between them.
ns_between:
        STAB    [NS_DQ]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [NS_DT]
        STAB    [NS_DY]
        LDAA    [NS_DQ]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [NS_DT]
        ADDB    [NS_DY]
        ADDB    3
        RTS

; A = cell, [JR_RT_COLOR] set, [NS_DCODE] = tile.
ns_put:
        TAB
        JSR     ns_between
        JSR     jr_gfx_at
        LDAA    [NS_DCODE]
        JMP     jr_gfx_tile

game_draw:
        LDAA    0x20
        LDAB    NS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ns_hud
        JSR     jr_gfx_lines
        CLR     [NS_DI]
ns_draw_floor:
        LDAA    NS_ATTR_FLOOR
        STAA    [JR_RT_COLOR]
        LDAA    NS_TILE_FLOOR
        STAA    [NS_DCODE]
        LDAA    [NS_DI]
        JSR     ns_put
        TST     [NS_PULSE]
        BEQ     ns_draw_floor_next
        LDAA    [NS_DI]
        LDAB    [NS_POS]
        JSR     ns_distance
        CMPA    [NS_PULSE]
        BNE     ns_draw_floor_next
        LDAA    NS_ATTR_PULSE
        STAA    [JR_RT_COLOR]
        LDAA    [NS_DI]
        TAB
        JSR     ns_between
        JSR     jr_gfx_at
        LDAA    NS_CHAR_PULSE
        JSR     jr_gfx_putc
ns_draw_floor_next:
        INC     [NS_DI]
        LDAA    [NS_DI]
        CMPA    64
        BNE     ns_draw_floor
        LDAA    NS_ATTR_PORTAL
        STAA    [JR_RT_COLOR]
        LDAA    NS_TILE_PORTAL
        STAA    [NS_DCODE]
        LDAA    [NS_ENTRY]
        JSR     ns_put
        LDAA    [NS_CELL]
        CMPA    NS_EMPTY
        BEQ     ns_draw_foes
        LDAB    NS_ATTR_CELL
        STAB    [JR_RT_COLOR]
        LDAB    NS_TILE_CELL
        STAB    [NS_DCODE]
        JSR     ns_put
ns_draw_foes:
        CLR     [NS_DI]
ns_draw_foe:
        LDX     NS_B
        LDAA    [NS_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    NS_EMPTY
        BEQ     ns_draw_foe_next
        LDAB    NS_ATTR_FOE
        STAB    [JR_RT_COLOR]
        LDAB    NS_TILE_FOE
        STAB    [NS_DCODE]
        LDAB    [X + 8]
        CMPB    2
        BCC     ns_draw_foe_at
        LDAB    NS_ATTR_WEAK
        STAB    [JR_RT_COLOR]
        LDAB    NS_TILE_WEAK
        STAB    [NS_DCODE]
ns_draw_foe_at:
        LDAB    [X]
        TST     [NS_MARCHING]
        BEQ     ns_draw_foe_put
        LDAB    [X + 16]
ns_draw_foe_put:
        JSR     ns_between
        JSR     jr_gfx_at
        LDAA    [NS_DCODE]
        JSR     jr_gfx_tile
ns_draw_foe_next:
        INC     [NS_DI]
        LDAA    [NS_DI]
        CMPA    8
        BNE     ns_draw_foe
        ; effects on a cell (hit, destroyed, salvage) and the shot
        LDAA    [NS_FLASH]
        BEQ     ns_draw_shot
        DECA
        LDAB    [NS_FLASH_ATTR]
        STAB    [JR_RT_COLOR]
        LDAB    NS_TILE_FOE
        STAB    [NS_DCODE]
        JSR     ns_put
ns_draw_shot:
        LDAA    [NS_SHOT]
        BEQ     ns_draw_ship
        DECA
        LDAB    [NS_POS]
        JSR     ns_between
        JSR     jr_gfx_at
        LDAA    NS_ATTR_PULSE
        STAA    [JR_RT_COLOR]
        LDAA    NS_CHAR_PULSE
        JSR     jr_gfx_putc
ns_draw_ship:
        LDAA    NS_ATTR_SHIP
        STAA    [JR_RT_COLOR]
        LDAA    [NS_POS]
        LDAB    [NS_ORIGIN]
        JSR     ns_between
        JSR     jr_gfx_at
        LDAA    [NS_FACING]
        DECA
        ANDA    3
        ASLA
        ASLA
        ADDA    NS_TILE_SHIP
        JSR     jr_gfx_tile
        ; the panel
        LDAA    NS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [NS_HP]
        JSR     jr_gfx_dec2
        LDAA    23
        LDAB    11
        JSR     jr_gfx_at
        LDAA    [NS_KILLS]
        JSR     jr_gfx_dec2
        LDAA    0x2f
        JSR     jr_gfx_putc
        LDAA    [NS_LIMIT]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [NS_COOLDOWN]
        JSR     jr_gfx_dec2
        LDAA    10
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [NS_SALVAGE]
        JSR     jr_gfx_dec2
        TST     [NS_COOLDOWN]
        BNE     ns_draw_demo
        LDAA    NS_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    19
        LDAB    18
        JSR     jr_gfx_at
        LDX     ns_txt_ready
        JSR     jr_gfx_text
ns_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     ns_draw_done
        LDAA    NS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     ns_txt_demo
        JSR     jr_gfx_text
ns_draw_done:
        RTS

game_draw_title:
        LDX     ns_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    NS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ns_title_tiles
        STX     [JR_RT_TABLE]
ns_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     ns_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [NS_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [NS_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     ns_title_tile
ns_title_text:
        LDX     ns_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    NS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ns_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; Q E Z C for the diagonals and X for south, as upstream's eight-way input.
game_key_table:
        .db     0x71, 9, 0x65, 10, 0x7a, 11, 0x63, 12, 0x78, 2, 0

; x, attribute, code, y: the ship among the swarm
ns_title_tiles:
        .db     6, NS_ATTR_FOE, NS_TILE_FOE, 3
        .db     10, NS_ATTR_WEAK, NS_TILE_WEAK, 1
        .db     15, NS_ATTR_SHIP, NS_TILE_SHIP, 4
        .db     20, NS_ATTR_FOE, NS_TILE_FOE, 1
        .db     24, NS_ATTR_PORTAL, NS_TILE_PORTAL, 3
        .db     0xff

ns_hud:
        .db     1, 0, NS_ATTR_TITLE
        .dw     ns_txt_name
        .db     19, 3, NS_ATTR_TITLE
        .dw     ns_txt_survival
        .db     20, 5, NS_ATTR_LABEL
        .dw     ns_txt_hull
        .db     20, 10, NS_ATTR_LABEL
        .dw     ns_txt_down
        .db     20, 15, NS_ATTR_LABEL
        .dw     ns_txt_pulse
        .db     1, 20, NS_ATTR_LABEL
        .dw     ns_txt_salvage
        .db     0xff
ns_title_lines:
        .db     10, 8, NS_ATTR_TITLE
        .dw     ns_txt_name
        .db     1, 10, NS_ATTR_LABEL
        .dw     ns_txt_tagline
        .db     4, 13, NS_ATTR_TEXT
        .dw     ns_txt_start
        .db     4, 15, NS_ATTR_TEXT
        .dw     ns_txt_howto
        .db     4, 17, NS_ATTR_DIM
        .dw     ns_txt_demo_hint
        .db     4, 19, NS_ATTR_DIM
        .dw     ns_txt_credit
        .db     0xff
ns_help_lines:
        .db     10, 1, NS_ATTR_TITLE
        .dw     ns_txt_name
        .db     1, 3, NS_ATTR_TEXT
        .dw     ns_help_1
        .db     1, 5, NS_ATTR_TEXT
        .dw     ns_help_2
        .db     1, 7, NS_ATTR_TEXT
        .dw     ns_help_3
        .db     1, 9, NS_ATTR_TEXT
        .dw     ns_help_4
        .db     1, 11, NS_ATTR_TEXT
        .dw     ns_help_5
        .db     1, 13, NS_ATTR_TEXT
        .dw     ns_help_6
        .db     1, 15, NS_ATTR_TEXT
        .dw     ns_help_7
        .db     1, 17, NS_ATTR_TEXT
        .dw     ns_help_8
        .db     1, 21, NS_ATTR_LABEL
        .dw     ns_help_back
        .db     0xff

ns_txt_name:
        .db     "NIGHT SWARM", 0
ns_txt_survival:
        .db     "SURVIVAL", 0
ns_txt_hull:
        .db     "HULL", 0
ns_txt_down:
        .db     "DOWN", 0
ns_txt_pulse:
        .db     "PULSE", 0
ns_txt_ready:
        .db     "PULSE READY", 0
ns_txt_salvage:
        .db     "SALVAGE", 0
ns_txt_demo:
        .db     "DEMO", 0
ns_txt_loss:
        .db     "THE SWARM BROKE THROUGH", 0
ns_txt_tagline:
        .db     "HOLD THE NIGHT, BREAK THE SWARM", 0
ns_txt_start:
        .db     "RETURN : START", 0
ns_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
ns_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
ns_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
ns_help_1:
        .db     "QWE / AD / ZXC : EIGHT WAYS", 0
ns_help_2:
        .db     "RETURN : AREA PULSE WHEN READY", 0
ns_help_3:
        .db     "AUTO FIRE HITS ONE NEARBY FOE.", 0
ns_help_4:
        .db     "PORTALS SHOW THE NEXT ARRIVAL.", 0
ns_help_5:
        .db     "ARMOURED FOES TAKE TWO HITS.", 0
ns_help_6:
        .db     "SALVAGE: HEAL + READY PULSE", 0
ns_help_7:
        .db     "SIX WAVES GROW MORE CROWDED.", 0
ns_help_8:
        .db     "SPACE : RETRY THE WAVE", 0
ns_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     ns_sfx_shot, ns_sfx_down, ns_jingle_win, ns_jingle_lose
ns_sfx_shot:
        .db     30, 1, 40, 1, 0, 0
ns_sfx_down:
        .db     50, 2, 40, 2, 30, 4, 0, 0
ns_sfx_armor:
        .db     120, 2, 0, 0
ns_sfx_pulse:
        .db     200, 2, 150, 2, 100, 2, 60, 2, 30, 4, 0, 0
ns_sfx_crash:
        .db     180, 2, 250, 2, 200, 2, 250, 6, 0, 0

; Title: a tense night theme in C minor, eighth note = 8 frames, looping.
ns_title_song:
        .db     1
        .dw     ns_title_melody, ns_title_harmony, ns_title_bass
ns_title_melody:
        .db     AU_C5, 8, AU_DS5, 8, AU_G5, 16, AU_F5, 8, AU_DS5, 8, AU_D5, 16
        .db     AU_C5, 8, AU_D5, 8, AU_DS5, 8, AU_D5, 8, AU_B4, 32
        .db     AU_C5, 8, AU_DS5, 8, AU_G5, 16, AU_GS5, 8, AU_G5, 8, AU_F5, 16
        .db     AU_DS5, 8, AU_D5, 8, AU_B4, 8, AU_D5, 8, AU_C5, 32, 0, 0
ns_title_harmony:
        .db     AU_G4, 32, AU_GS4, 32, AU_G4, 32, AU_F4, 32
        .db     AU_G4, 32, AU_C5, 32, AU_GS4, 32, AU_G4, 32, 0, 0
ns_title_bass:
        .db     AU_C3, 16, AU_G2, 16, AU_F2, 16, AU_GS2, 16, AU_G2, 16, AU_D3, 16, AU_G2, 32
        .db     AU_C3, 16, AU_G2, 16, AU_F2, 16, AU_GS2, 16, AU_G2, 16, AU_G2, 16, AU_C3, 32, 0, 0

; Wave broken: C major dawn.
ns_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     ns_win_melody, ns_win_harmony, ns_win_bass
ns_win_melody:
        .db     AU_G4, 6, AU_C5, 6, AU_E5, 6, AU_G5, 12, AU_C6, 30, 0, 0
ns_win_harmony:
        .db     AU_E4, 12, AU_G4, 18, AU_E5, 30, 0, 0
ns_win_bass:
        .db     AU_C3, 12, AU_G2, 18, AU_C2, 30, 0, 0
ns_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     ns_lose_melody, ns_lose_harmony, ns_lose_bass
ns_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
ns_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
ns_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


        .include "selftest.inc"
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
        .include "../../../sdk/port.inc"
        .include "../../../sdk/selftest.inc"
        .include "../../../sdk/font_data.inc"

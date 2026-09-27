; SPDX-License-Identifier: MIT
; CHRONO BREACH for JR-200: a port of jr100dev games/chrono_breach 1.6.1.
; Time moves only when the agent acts: a move (a strike when it enters a
; guard), a four-cell shot or a wait advances every bolt one cell, and the
; guards fire every third action. Walls, the first free of 16 bolt slots,
; friendly fire, the exit that opens once no guard lives and the twenty
; sectors with their ammo and par follow upstream src/turn.asm and
; levels.json (see tests/model.py). Display, colour and three-voice sound
; use the JR-200 port SDK.
        .filename.jr "CHRONO-BREACH"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46c0
JR_AUDIO:           .equ    0x46c0
CB_DEATHS:          .equ    0x46e0      ; retries this session (kept across sectors)
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    20
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    0       ; SPACE opens the menu, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    3

; Upstream state (same order as tests/model.py LAYOUT).
CB_X:               .equ    GAME_STATE
CB_Y:               .equ    GAME_STATE + 1
CB_FACING:          .equ    GAME_STATE + 2      ; 1 N, 2 S, 3 W, 4 E
CB_AMMO:            .equ    GAME_STATE + 3
CB_TURNS:           .equ    GAME_STATE + 4
CB_PHASE:           .equ    GAME_STATE + 5
CB_ALIVE:           .equ    GAME_STATE + 6
CB_MENU:            .equ    GAME_STATE + 7
CB_SUB:             .equ    GAME_STATE + 8      ; 0 play, 1 menu, 2/3 question
CB_CHOICE:          .equ    GAME_STATE + 9
CB_GUARDS:          .equ    GAME_STATE + 10     ; 6 x (x, y, direction, alive)
CB_BOLTS:           .equ    GAME_STATE + 34     ; 16 x (x, y, direction)
; Rule work bytes.
CB_CX:              .equ    GAME_STATE + 82
CB_CY:              .equ    GAME_STATE + 83
CB_DIR:             .equ    GAME_STATE + 84
CB_I:               .equ    GAME_STATE + 85
CB_K:               .equ    GAME_STATE + 86
CB_DEAD:            .equ    GAME_STATE + 87
CB_PTR:             .equ    GAME_STATE + 88     ; 2 bytes
CB_EXIT_X:          .equ    GAME_STATE + 90
CB_EXIT_Y:          .equ    GAME_STATE + 91
CB_PAR:             .equ    GAME_STATE + 92
CB_WALLS:           .equ    GAME_STATE + 93     ; 2 bytes: the sector's wall bits
; Effect bytes (set by the rules, read by game_draw).
CB_FX:              .equ    GAME_STATE + 95     ; burst stage 1-3
CB_FXX:             .equ    GAME_STATE + 96
CB_FXY:             .equ    GAME_STATE + 97
CB_BEAM:            .equ    GAME_STATE + 98     ; 0 none, else the beam's direction
CB_BEAMX:           .equ    GAME_STATE + 99
CB_BEAMY:           .equ    GAME_STATE + 100
CB_SLIDE:           .equ    GAME_STATE + 101    ; a step between two cells
; Drawing work bytes.
CB_DX:              .equ    GAME_STATE + 104
CB_DY:              .equ    GAME_STATE + 105
CB_DI:              .equ    GAME_STATE + 106
CB_DCODE:           .equ    GAME_STATE + 107
CB_DPTR:            .equ    GAME_STATE + 108    ; 2 bytes
CB_DT:              .equ    GAME_STATE + 110

CB_SUB_MENU:        .equ    1
CB_SUB_RESET:       .equ    2
CB_SUB_TITLE:       .equ    3
CB_BURST_FRAMES:    .equ    4       ; three stages

CB_TILE_WALL:       .equ    0x80
CB_TILE_AGENT:      .equ    0x84
CB_TILE_GUARD:      .equ    0x88    ; + 4 * (direction - 1)
CB_TILE_BOLT:       .equ    0x98
CB_TILE_SHUT:       .equ    0x9c
CB_TILE_OPEN:       .equ    0x00    ; second PCG bank
CB_TILE_BURST:      .equ    0x04    ; glow, shards, dust
CB_CHAR_RAY:        .equ    0x10
CB_CHAR_BEAM_H:     .equ    0x11
CB_CHAR_BEAM_V:     .equ    0x12
CB_ATTR_WALL:       .equ    0x41
CB_ATTR_AGENT:      .equ    0x46
CB_ATTR_GUARD:      .equ    0x42
CB_ATTR_BOLT:       .equ    0x47
CB_ATTR_SHUT:       .equ    0x43
CB_ATTR_OPEN:       .equ    0x44
CB_ATTR_BURST:      .equ    0x46
CB_ATTR_RAY:        .equ    0x42
CB_ATTR_BEAM:       .equ    0x45
CB_ATTR_TEXT:       .equ    0x07
CB_ATTR_LABEL:      .equ    0x04
CB_ATTR_TITLE:      .equ    0x06
CB_ATTR_DIM:        .equ    0x05
CB_ATTR_PICK:       .equ    0x06
CB_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     cb_patterns
        LDAA    CB_TILE_WALL
        LDAB    32
        JSR     jr_pcg_load
        LDX     cb_patterns_low
        LDAA    CB_TILE_OPEN
        LDAB    19
        JSR     jr_pcg_load
        CLR     [CB_DEATHS]
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; LOAD_LEVEL: the sector's agent, exit, guards, ammo, par and walls.
game_init:
        JSR     jr_music_stop
        LDX     cb_sectors
        LDAA    [JR_PORT_LEVEL]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        LDAA    [X]
        STAA    [CB_X]
        LDAA    [X + 1]
        STAA    [CB_Y]
        LDAA    [X + 2]
        STAA    [CB_EXIT_X]
        LDAA    [X + 3]
        STAA    [CB_EXIT_Y]
        LDAA    [X + 4]
        STAA    [CB_ALIVE]
        STAA    [CB_K]
        LDAA    [X + 5]
        STAA    [CB_AMMO]
        LDAA    [X + 6]
        STAA    [CB_PAR]
        LDAA    7
        JSR     jr_add_x_a
        STX     [CB_PTR]
        LDX     CB_GUARDS
        STX     [CB_DPTR]
        TST     [CB_K]
        BEQ     cb_init_walls
cb_init_guard:
        LDX     [CB_PTR]
        LDAA    [X]
        LDAB    [X + 1]
        PSHB
        LDAB    [X + 2]
        INX
        INX
        INX
        STX     [CB_PTR]
        LDX     [CB_DPTR]
        STAA    [X]
        STAB    [X + 2]
        PULB
        STAB    [X + 1]
        LDAA    1
        STAA    [X + 3]
        INX
        INX
        INX
        INX
        STX     [CB_DPTR]
        DEC     [CB_K]
        BNE     cb_init_guard
cb_init_walls:
        LDX     [CB_PTR]
        STX     [CB_WALLS]
        LDAA    4
        STAA    [CB_FACING]
        LDAA    2
        STAA    [CB_PHASE]
game_raw_key:
game_tick:
        RTS

; CB_CX / CB_CY -> Z clear when a wall (A = the wall bit).
cb_wall_at:
        LDAA    [CB_CY]
        LDAB    12
        JSR     jr_mul8
        ADDA    [CB_CX]
        TAB
        LSRA
        LSRA
        LSRA
        LDX     [CB_WALLS]
        JSR     jr_add_x_a
        ANDB    7
        LDAA    0x80
cb_wall_bit:
        TSTB
        BEQ     cb_wall_test
        LSRA
        DECB
        BRA     cb_wall_bit
cb_wall_test:
        ANDA    [X]
        RTS

; CB_DIR: step CB_CX / CB_CY.
cb_step:
        LDAA    [CB_DIR]
        CMPA    1
        BNE     cb_step_south
        DEC     [CB_CY]
        RTS
cb_step_south:
        CMPA    2
        BNE     cb_step_west
        INC     [CB_CY]
        RTS
cb_step_west:
        CMPA    3
        BNE     cb_step_east
        DEC     [CB_CX]
        RTS
cb_step_east:
        INC     [CB_CX]
        RTS

; HIT_GUARD: the first living guard at CB_CX / CB_CY dies (burst). Z clear on a hit.
cb_hit_guard:
        LDX     CB_GUARDS
cb_hit_guard_scan:
        TST     [X + 3]
        BEQ     cb_hit_guard_next
        LDAA    [CB_CX]
        CMPA    [X]
        BNE     cb_hit_guard_next
        LDAA    [CB_CY]
        CMPA    [X + 1]
        BNE     cb_hit_guard_next
        CLR     [X + 3]
        DEC     [CB_ALIVE]
        STX     [CB_PTR]
        LDX     cb_sfx_kill
        JSR     jr_sfx_play
        LDAA    [CB_CX]
        STAA    [CB_FXX]
        LDAA    [CB_CY]
        STAA    [CB_FXY]
        LDAA    1
        STAA    [CB_FX]
cb_hit_guard_burst:
        LDAA    CB_BURST_FRAMES
        JSR     jr_port_animate
        INC     [CB_FX]
        LDAA    [CB_FX]
        CMPA    4
        BNE     cb_hit_guard_burst
        CLR     [CB_FX]
        LDAA    1
        RTS
cb_hit_guard_next:
        LDAA    4
        JSR     jr_add_x_a
        CPX     CB_GUARDS + 24
        BNE     cb_hit_guard_scan
        CLRA
        RTS

; HIT_PLAYER: the agent at CB_CX / CB_CY dies (once). Z clear on a hit.
cb_hit_player:
        LDAA    [CB_CX]
        CMPA    [CB_X]
        BNE     cb_hit_player_miss
        LDAA    [CB_CY]
        CMPA    [CB_Y]
        BNE     cb_hit_player_miss
        LDAA    1
        STAA    [CB_DEAD]
        RTS
cb_hit_player_miss:
        CLRA
        RTS

game_act:
        STAA    [CB_K]
        CLR     [CB_DEAD]
        LDAB    [CB_SUB]
        BNE     cb_act_menu
        CMPA    JR_KEY_CONFIRM
        BEQ     cb_open_menu
        CMPA    JR_KEY_BACK
        BEQ     cb_open_menu
        JMP     cb_take_action
cb_open_menu:
        LDAA    CB_SUB_MENU
        STAA    [CB_SUB]
        CLR     [CB_MENU]
        LDX     cb_sfx_menu
        JMP     jr_sfx_play

cb_act_menu:
        CMPB    CB_SUB_MENU
        BNE     cb_act_answer
        CMPA    JR_KEY_BACK
        BEQ     cb_close_menu
        CMPA    JR_KEY_UP
        BNE     cb_menu_down
        DEC     [CB_MENU]
        BPL     cb_act_done
        LDAA    4
        STAA    [CB_MENU]
        RTS
cb_menu_down:
        CMPA    JR_KEY_DOWN
        BNE     cb_menu_left
        INC     [CB_MENU]
        LDAA    [CB_MENU]
        CMPA    5
        BCS     cb_act_done
        CLR     [CB_MENU]
        RTS
cb_menu_left:
        ; aim N, S, W, E around
        CMPA    JR_KEY_LEFT
        BNE     cb_menu_right
        DEC     [CB_FACING]
        BNE     cb_act_done
        LDAA    4
        STAA    [CB_FACING]
        RTS
cb_menu_right:
        CMPA    JR_KEY_RIGHT
        BNE     cb_menu_pick
        INC     [CB_FACING]
        LDAA    [CB_FACING]
        CMPA    5
        BCS     cb_act_done
        LDAA    1
        STAA    [CB_FACING]
        RTS
cb_menu_pick:
        CMPA    JR_KEY_CONFIRM
        BNE     cb_act_done
        LDAA    [CB_MENU]
        CMPA    2
        BCC     cb_menu_other
        CLR     [CB_SUB]
        LDAB    8                   ; FIRE
        TSTA
        BEQ     cb_menu_act
        LDAB    7                   ; WAIT
cb_menu_act:
        STAB    [CB_K]
        JMP     cb_take_action
cb_menu_other:
        CMPA    4
        BEQ     cb_close_menu
        STAA    [CB_SUB]            ; RESET 2, TITLE 3
        CLR     [CB_CHOICE]
        RTS
cb_close_menu:
        CLR     [CB_SUB]
cb_act_done:
        RTS

; RESET? / TITLE?: A picks YES, D picks NO, RETURN answers, SPACE cancels.
cb_act_answer:
        CMPA    JR_KEY_LEFT
        BNE     cb_answer_no
        LDAA    1
        STAA    [CB_CHOICE]
        RTS
cb_answer_no:
        CMPA    JR_KEY_RIGHT
        BNE     cb_answer_back
        CLR     [CB_CHOICE]
        RTS
cb_answer_back:
        CMPA    JR_KEY_BACK
        BEQ     cb_answer_menu
        CMPA    JR_KEY_CONFIRM
        BNE     cb_act_done
        TST     [CB_CHOICE]
        BNE     cb_answer_yes
cb_answer_menu:
        LDAA    CB_SUB_MENU
        STAA    [CB_SUB]
        RTS
cb_answer_yes:
        LDAA    [CB_SUB]
        CMPA    CB_SUB_RESET
        BNE     cb_answer_title
        ; the sector again from its start
        LDX     GAME_STATE
cb_answer_clear:
        CLR     [X]
        INX
        CPX     GAME_STATE_END
        BNE     cb_answer_clear
        JMP     game_init
cb_answer_title:
        ; leave the sector for the title: drop game_act's return address
        INS
        INS
        JMP     jr_port_title

; TAKE_ACTION: CB_K = 1-4 move, 7 wait, 8 fire.
cb_take_action:
        LDAA    [CB_K]
        CMPA    7
        BNE     cb_take_fire
        JMP     cb_advance
cb_take_fire:
        CMPA    8
        BNE     cb_take_move
        JMP     cb_fire
cb_take_move:
        CMPA    JR_KEY_RIGHT
        BHI     cb_act_done
        STAA    [CB_FACING]
        STAA    [CB_DIR]
        LDAA    [CB_X]
        STAA    [CB_CX]
        LDAA    [CB_Y]
        STAA    [CB_CY]
        JSR     cb_step
        JSR     cb_wall_at
        BNE     cb_act_done         ; a wall: aim only, no time
        ; half a step on screen, then the new cell
        LDAA    [CB_DIR]
        STAA    [CB_SLIDE]
        LDAA    2
        JSR     jr_port_animate
        CLR     [CB_SLIDE]
        LDAA    [CB_CX]
        STAA    [CB_X]
        LDAA    [CB_CY]
        STAA    [CB_Y]
        LDX     cb_sfx_move
        JSR     jr_sfx_play
        JSR     cb_hit_guard
        ; entering an occupied bolt cell is lethal before that bolt moves
        LDX     CB_BOLTS
cb_take_enter:
        TST     [X + 2]
        BEQ     cb_take_enter_next
        LDAA    [X]
        CMPA    [CB_X]
        BNE     cb_take_enter_next
        LDAA    [X + 1]
        CMPA    [CB_Y]
        BNE     cb_take_enter_next
        LDAA    1
        STAA    [CB_DEAD]
cb_take_enter_next:
        LDAA    3
        JSR     jr_add_x_a
        CPX     CB_BOLTS + 48
        BNE     cb_take_enter
        JMP     cb_advance

; PLAYER_FIRE: four cells in the facing, stopped by a wall or the first guard.
cb_fire:
        TST     [CB_AMMO]
        BNE     cb_fire_ready
        LDX     cb_sfx_empty
        JMP     jr_sfx_play
cb_fire_ready:
        DEC     [CB_AMMO]
        LDAA    [CB_X]
        STAA    [CB_CX]
        LDAA    [CB_Y]
        STAA    [CB_CY]
        LDAA    [CB_FACING]
        STAA    [CB_DIR]
        LDAA    4
        STAA    [CB_I]
        LDX     cb_sfx_shot
        JSR     jr_sfx_play
cb_fire_ray:
        JSR     cb_step
        JSR     cb_wall_at
        BNE     cb_fire_done
        ; the beam reaches this cell
        LDAA    [CB_DIR]
        STAA    [CB_BEAM]
        LDAA    [CB_CX]
        STAA    [CB_BEAMX]
        LDAA    [CB_CY]
        STAA    [CB_BEAMY]
        LDAA    1
        JSR     jr_port_animate
        CLR     [CB_BEAM]
        JSR     cb_hit_guard
        BNE     cb_fire_done
        DEC     [CB_I]
        BNE     cb_fire_ray
cb_fire_done:
        CLR     [CB_BEAM]
        ; fall through

; ADVANCE_WORLD: bolts in slot order, then every third action the guards fire.
cb_advance:
        LDAA    [CB_TURNS]
        CMPA    255
        BEQ     cb_advance_bolts
        INC     [CB_TURNS]
cb_advance_bolts:
        CLR     [CB_I]
cb_bolt:
        LDX     CB_BOLTS
        LDAA    [CB_I]
        JSR     jr_add_x_a
        LDAA    [X + 2]
        BEQ     cb_bolt_next
        STAA    [CB_DIR]
        LDAA    [X]
        STAA    [CB_CX]
        LDAA    [X + 1]
        STAA    [CB_CY]
        JSR     cb_step
        JSR     cb_wall_at
        BNE     cb_bolt_remove
        JSR     cb_hit_player
        BNE     cb_bolt_remove
        JSR     cb_hit_guard
        BNE     cb_bolt_remove
        LDX     CB_BOLTS
        LDAA    [CB_I]
        JSR     jr_add_x_a
        LDAA    [CB_CX]
        STAA    [X]
        LDAA    [CB_CY]
        STAA    [X + 1]
        BRA     cb_bolt_next
cb_bolt_remove:
        LDX     CB_BOLTS
        LDAA    [CB_I]
        JSR     jr_add_x_a
        CLR     [X + 2]
cb_bolt_next:
        LDAA    [CB_I]
        ADDA    3
        STAA    [CB_I]
        CMPA    48
        BNE     cb_bolt
        INC     [CB_PHASE]
        LDAA    [CB_PHASE]
        CMPA    3
        BCS     cb_check
        CLR     [CB_PHASE]
        CLR     [CB_K]
cb_guard_fire:
        LDX     CB_GUARDS
        LDAA    [CB_K]
        JSR     jr_add_x_a
        TST     [X + 3]
        BEQ     cb_guard_next
        LDAA    [X]
        STAA    [CB_CX]
        LDAA    [X + 1]
        STAA    [CB_CY]
        LDAA    [X + 2]
        STAA    [CB_DIR]
        JSR     cb_step
        JSR     cb_wall_at
        BNE     cb_guard_next
        JSR     cb_hit_player
        BNE     cb_guard_next
        JSR     cb_hit_guard
        BNE     cb_guard_next
        LDX     CB_BOLTS
cb_guard_slot:
        TST     [X + 2]
        BEQ     cb_guard_spawn
        LDAA    3
        JSR     jr_add_x_a
        CPX     CB_BOLTS + 48
        BNE     cb_guard_slot
        BRA     cb_guard_next
cb_guard_spawn:
        LDAA    [CB_CX]
        STAA    [X]
        LDAA    [CB_CY]
        STAA    [X + 1]
        LDAA    [CB_DIR]
        STAA    [X + 2]
        LDX     cb_sfx_volley
        JSR     jr_sfx_play
cb_guard_next:
        LDAA    [CB_K]
        ADDA    4
        STAA    [CB_K]
        CMPA    24
        BNE     cb_guard_fire
cb_check:
        TST     [CB_DEAD]
        BEQ     cb_check_clear
        LDAA    [CB_DEATHS]
        CMPA    255
        BEQ     cb_check_lost
        INC     [CB_DEATHS]
cb_check_lost:
        LDX     cb_txt_caught
        JMP     jr_port_lose
cb_check_clear:
        TST     [CB_ALIVE]
        BNE     cb_check_done
        LDAA    [CB_X]
        CMPA    [CB_EXIT_X]
        BNE     cb_check_done
        LDAA    [CB_Y]
        CMPA    [CB_EXIT_Y]
        BNE     cb_check_done
        JMP     jr_port_win
cb_check_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = column, B = row of a cell -> the shadow cursor at its top left.
cb_cell_at:
        ASLA
        ASLB
        ADDB    2
        JMP     jr_gfx_at

game_draw:
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cb_hud
        JSR     jr_gfx_lines
        ; walls, the exit and the guards' firing lines
        CLR     [CB_DY]
cb_draw_row:
        CLR     [CB_DX]
cb_draw_cell:
        LDAA    [CB_DY]
        LDAB    12
        JSR     jr_mul8
        ADDA    [CB_DX]
        TAB
        LSRA
        LSRA
        LSRA
        LDX     [CB_WALLS]
        JSR     jr_add_x_a
        ANDB    7
        LDAA    0x80
cb_draw_bit:
        TSTB
        BEQ     cb_draw_bit_done
        LSRA
        DECB
        BRA     cb_draw_bit
cb_draw_bit_done:
        ANDA    [X]
        BEQ     cb_draw_cell_next
        LDAA    CB_ATTR_WALL
        STAA    [JR_RT_COLOR]
        LDAA    [CB_DX]
        LDAB    [CB_DY]
        JSR     cb_cell_at
        LDAA    CB_TILE_WALL
        JSR     jr_gfx_tile
cb_draw_cell_next:
        INC     [CB_DX]
        LDAA    [CB_DX]
        CMPA    12
        BNE     cb_draw_cell
        INC     [CB_DY]
        LDAA    [CB_DY]
        CMPA    10
        BNE     cb_draw_row
        ; the exit: shut while a guard lives
        LDAA    CB_ATTR_SHUT
        LDAB    CB_TILE_SHUT
        TST     [CB_ALIVE]
        BNE     cb_draw_exit
        LDAA    CB_ATTR_OPEN
        LDAB    CB_TILE_OPEN
cb_draw_exit:
        STAA    [JR_RT_COLOR]
        STAB    [CB_DCODE]
        LDAA    [CB_EXIT_X]
        LDAB    [CB_EXIT_Y]
        JSR     cb_cell_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_tile
        JSR     cb_draw_rays
        JSR     cb_draw_bolts
        JSR     cb_draw_guards
        JSR     cb_draw_agent
        JSR     cb_draw_effects
        JSR     cb_draw_hud
        JMP     cb_draw_panel

; Each living guard's firing line: a mark in the cells up to the next wall.
cb_draw_rays:
        LDAA    CB_ATTR_RAY
        STAA    [JR_RT_COLOR]
        CLR     [CB_DI]
cb_draw_ray_guard:
        LDX     CB_GUARDS
        LDAA    [CB_DI]
        JSR     jr_add_x_a
        TST     [X + 3]
        BEQ     cb_draw_ray_next
        LDAA    [X]
        STAA    [CB_DX]
        LDAA    [X + 1]
        STAA    [CB_DY]
        LDAA    [X + 2]
        STAA    [CB_DT]
cb_draw_ray_cell:
        ; one cell on in the guard's direction
        LDAA    [CB_DT]
        CMPA    1
        BNE     cb_draw_ray_s
        DEC     [CB_DY]
        BRA     cb_draw_ray_test
cb_draw_ray_s:
        CMPA    2
        BNE     cb_draw_ray_w
        INC     [CB_DY]
        BRA     cb_draw_ray_test
cb_draw_ray_w:
        CMPA    3
        BNE     cb_draw_ray_e
        DEC     [CB_DX]
        BRA     cb_draw_ray_test
cb_draw_ray_e:
        INC     [CB_DX]
cb_draw_ray_test:
        LDAA    [CB_DY]
        LDAB    12
        JSR     jr_mul8
        ADDA    [CB_DX]
        TAB
        LSRA
        LSRA
        LSRA
        LDX     [CB_WALLS]
        JSR     jr_add_x_a
        ANDB    7
        LDAA    0x80
cb_draw_ray_bit:
        TSTB
        BEQ     cb_draw_ray_bit_done
        LSRA
        DECB
        BRA     cb_draw_ray_bit
cb_draw_ray_bit_done:
        ANDA    [X]
        BNE     cb_draw_ray_next
        LDAA    [CB_DX]
        LDAB    [CB_DY]
        ASLA
        INCA
        ASLB
        ADDB    3
        JSR     jr_gfx_at
        LDAA    CB_CHAR_RAY
        JSR     jr_gfx_putc
        BRA     cb_draw_ray_cell
cb_draw_ray_next:
        LDAA    [CB_DI]
        ADDA    4
        STAA    [CB_DI]
        CMPA    24
        BEQ     cb_draw_ray_guard_near773
        JMP     cb_draw_ray_guard
cb_draw_ray_guard_near773:
        RTS

cb_draw_bolts:
        LDAA    CB_ATTR_BOLT
        STAA    [JR_RT_COLOR]
        CLR     [CB_DI]
cb_draw_bolt:
        LDX     CB_BOLTS
        LDAA    [CB_DI]
        JSR     jr_add_x_a
        TST     [X + 2]
        BEQ     cb_draw_bolt_next
        LDAA    [X]
        LDAB    [X + 1]
        JSR     cb_cell_at
        LDAA    CB_TILE_BOLT
        JSR     jr_gfx_tile
cb_draw_bolt_next:
        LDAA    [CB_DI]
        ADDA    3
        STAA    [CB_DI]
        CMPA    48
        BNE     cb_draw_bolt
        RTS

cb_draw_guards:
        LDAA    CB_ATTR_GUARD
        STAA    [JR_RT_COLOR]
        CLR     [CB_DI]
cb_draw_guard:
        LDX     CB_GUARDS
        LDAA    [CB_DI]
        JSR     jr_add_x_a
        TST     [X + 3]
        BEQ     cb_draw_guard_next
        LDAA    [X + 2]
        DECA
        ASLA
        ASLA
        ADDA    CB_TILE_GUARD
        STAA    [CB_DCODE]
        LDAA    [X]
        LDAB    [X + 1]
        JSR     cb_cell_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_tile
cb_draw_guard_next:
        LDAA    [CB_DI]
        ADDA    4
        STAA    [CB_DI]
        CMPA    24
        BNE     cb_draw_guard
        RTS

; The agent, half a cell on while it steps.
cb_draw_agent:
        LDAA    CB_ATTR_AGENT
        STAA    [JR_RT_COLOR]
        LDAA    [CB_X]
        ASLA
        LDAB    [CB_Y]
        ASLB
        ADDB    2
        PSHB
        LDAB    [CB_SLIDE]
        CMPB    1
        BNE     cb_draw_agent_s
        PULB
        DECB
        BRA     cb_draw_agent_put
cb_draw_agent_s:
        CMPB    2
        BNE     cb_draw_agent_w
        PULB
        INCB
        BRA     cb_draw_agent_put
cb_draw_agent_w:
        CMPB    3
        BNE     cb_draw_agent_e
        PULB
        DECA
        BRA     cb_draw_agent_put
cb_draw_agent_e:
        CMPB    4
        PULB
        BNE     cb_draw_agent_put
        INCA
cb_draw_agent_put:
        JSR     jr_gfx_at
        LDAA    CB_TILE_AGENT
        JMP     jr_gfx_tile

; A guard's burst and the shot's beam.
cb_draw_effects:
        TST     [CB_FX]
        BEQ     cb_draw_beam
        LDAA    CB_ATTR_BURST
        STAA    [JR_RT_COLOR]
        LDAA    [CB_FX]
        DECA
        ASLA
        ASLA
        ADDA    CB_TILE_BURST
        STAA    [CB_DCODE]
        LDAA    [CB_FXX]
        LDAB    [CB_FXY]
        JSR     cb_cell_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_tile
cb_draw_beam:
        LDAA    [CB_BEAM]
        BEQ     cb_draw_effects_done
        LDAB    CB_CHAR_BEAM_V
        CMPA    3
        BCS     cb_draw_beam_char
        LDAB    CB_CHAR_BEAM_H
cb_draw_beam_char:
        STAB    [CB_DCODE]
        LDAA    CB_ATTR_BEAM
        STAA    [JR_RT_COLOR]
        LDAA    [CB_BEAMX]
        LDAB    [CB_BEAMY]
        JSR     cb_cell_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_putc
        LDAA    [CB_DCODE]
        JSR     jr_gfx_putc
        LDAA    [CB_BEAMX]
        ASLA
        LDAB    [CB_BEAMY]
        ASLB
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_putc
        LDAA    [CB_DCODE]
        JMP     jr_gfx_putc
cb_draw_effects_done:
        RTS

cb_draw_hud:
        LDAA    CB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [CB_ALIVE]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    26
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [CB_AMMO]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; FIRE IN: actions to the next volley (3 - phase)
        LDAA    26
        LDAB    7
        JSR     jr_gfx_at
        LDAA    3
        SUBA    [CB_PHASE]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    26
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [CB_TURNS]
        JSR     jr_gfx_dec3
        LDAA    26
        LDAB    11
        JSR     jr_gfx_at
        LDAA    [CB_PAR]
        JSR     jr_gfx_dec3
        LDAA    29
        LDAB    13
        JSR     jr_gfx_at
        LDX     cb_aim_names - 1
        LDAA    [CB_FACING]
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_putc
        ; row 22: the sector's name, or the result
        LDAA    CB_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BEQ     cb_draw_rating
        CMPA    JR_MODE_END
        BEQ     cb_draw_end
        LDX     cb_names
        LDAA    [JR_PORT_LEVEL]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_gfx_text
cb_draw_rating:
        ; ACE within the par, else CLEAR
        LDX     cb_txt_ace
        LDAA    [CB_TURNS]
        CMPA    [CB_PAR]
        BLS     cb_draw_rating_text
        LDX     cb_txt_clear
cb_draw_rating_text:
        JMP     jr_gfx_text
cb_draw_end:
        LDX     cb_txt_end
        JSR     jr_gfx_text
        LDAA    [CB_DEATHS]
        JMP     jr_gfx_dec3

; The tactical menu under the gauges, and its question.
cb_draw_panel:
        LDAA    [CB_SUB]
        BEQ     cb_draw_panel_done
        LDX     cb_menu_lines
        JSR     jr_gfx_lines
        LDAA    CB_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [CB_MENU]
        ADDA    15
        TAB
        LDAA    25
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    [CB_SUB]
        CMPA    CB_SUB_RESET
        BCS     cb_draw_panel_done
        BNE     cb_draw_panel_title
        LDX     cb_ask_reset_lines
        BRA     cb_draw_panel_ask
cb_draw_panel_title:
        LDX     cb_ask_title_lines
cb_draw_panel_ask:
        JSR     jr_gfx_lines
        LDAA    CB_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    14
        TST     [CB_CHOICE]
        BNE     cb_draw_panel_choice
        LDAA    20
cb_draw_panel_choice:
        LDAB    22
        JSR     jr_gfx_at
        LDAA    0x3e
        JMP     jr_gfx_putc
cb_draw_panel_done:
        RTS

game_draw_title:
        LDX     cb_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cb_title_tiles
        STX     [CB_DPTR]
cb_title_tile:
        LDX     [CB_DPTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     cb_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [CB_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [CB_DCODE]
        JSR     jr_gfx_tile
        LDX     [CB_DPTR]
        INX
        INX
        INX
        INX
        STX     [CB_DPTR]
        BRA     cb_title_tile
cb_title_text:
        LDX     cb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x66, 8, 0x78, 7, 0         ; F: fire, X: wait

cb_aim_names:
        .db     0x4e, 0x53, 0x57, 0x45      ; N S W E

; x, attribute, code, y
cb_title_tiles:
        .db     6, CB_ATTR_AGENT, CB_TILE_AGENT, 3
        .db     10, CB_ATTR_BOLT, CB_TILE_BOLT, 3
        .db     14, CB_ATTR_GUARD, CB_TILE_GUARD + 8, 3
        .db     18, CB_ATTR_WALL, CB_TILE_WALL, 3
        .db     22, CB_ATTR_OPEN, CB_TILE_OPEN, 3
        .db     0xff

cb_hud:
        .db     1, 0, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     22, 0, CB_ATTR_LABEL
        .dw     cb_txt_sector
        .db     25, 2, CB_ATTR_LABEL
        .dw     cb_txt_guards
        .db     25, 4, CB_ATTR_LABEL
        .dw     cb_txt_rounds
        .db     25, 6, CB_ATTR_LABEL
        .dw     cb_txt_fire_in
        .db     25, 8, CB_ATTR_LABEL
        .dw     cb_txt_acts
        .db     25, 10, CB_ATTR_LABEL
        .dw     cb_txt_target
        .db     25, 13, CB_ATTR_LABEL
        .dw     cb_txt_aim
        .db     0xff
cb_menu_lines:
        .db     26, 15, CB_ATTR_TEXT
        .dw     cb_txt_m0
        .db     26, 16, CB_ATTR_TEXT
        .dw     cb_txt_m1
        .db     26, 17, CB_ATTR_TEXT
        .dw     cb_txt_m2
        .db     26, 18, CB_ATTR_TEXT
        .dw     cb_txt_m3
        .db     26, 19, CB_ATTR_TEXT
        .dw     cb_txt_m4
        .db     25, 20, CB_ATTR_DIM
        .dw     cb_txt_aim_keys
        .db     0xff
cb_ask_reset_lines:
        .db     1, 22, CB_ATTR_WARN
        .dw     cb_txt_ask_reset
        .db     0xff
cb_ask_title_lines:
        .db     1, 22, CB_ATTR_WARN
        .dw     cb_txt_ask_title
        .db     0xff
cb_title_lines:
        .db     9, 8, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     3, 10, CB_ATTR_LABEL
        .dw     cb_txt_tagline
        .db     8, 14, CB_ATTR_TEXT
        .dw     cb_txt_start
        .db     4, 16, CB_ATTR_TEXT
        .dw     cb_txt_howto
        .db     4, 22, CB_ATTR_DIM
        .dw     cb_txt_credit
        .db     0xff
cb_help_lines:
        .db     9, 1, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     1, 3, CB_ATTR_TEXT
        .dw     cb_help_1
        .db     1, 4, CB_ATTR_TEXT
        .dw     cb_help_2
        .db     1, 6, CB_ATTR_TEXT
        .dw     cb_help_3
        .db     1, 7, CB_ATTR_TEXT
        .dw     cb_help_4
        .db     1, 9, CB_ATTR_TEXT
        .dw     cb_help_5
        .db     1, 10, CB_ATTR_TEXT
        .dw     cb_help_6
        .db     1, 12, CB_ATTR_TEXT
        .dw     cb_help_7
        .db     1, 13, CB_ATTR_TEXT
        .dw     cb_help_8
        .db     1, 15, CB_ATTR_TEXT
        .dw     cb_help_9
        .db     1, 16, CB_ATTR_TEXT
        .dw     cb_help_10
        .db     1, 18, CB_ATTR_TEXT
        .dw     cb_help_11
        .db     8, 21, CB_ATTR_LABEL
        .dw     cb_help_back
        .db     0xff

cb_txt_name:
        .db     "CHRONO BREACH", 0
cb_txt_sector:
        .db     "SECTOR", 0
cb_txt_guards:
        .db     "GUARDS", 0
cb_txt_rounds:
        .db     "ROUNDS", 0
cb_txt_fire_in:
        .db     "FIRE IN", 0
cb_txt_acts:
        .db     "ACTS", 0
cb_txt_target:
        .db     "TARGET", 0
cb_txt_aim:
        .db     "AIM", 0
cb_txt_m0:
        .db     "FIRE", 0
cb_txt_m1:
        .db     "WAIT", 0
cb_txt_m2:
        .db     "RESET", 0
cb_txt_m3:
        .db     "TITLE", 0
cb_txt_m4:
        .db     "BACK", 0
cb_txt_aim_keys:
        .db     "A/D AIM", 0
cb_txt_ask_reset:
        .db     "RESET SECTOR? YES   NO", 0
cb_txt_ask_title:
        .db     "TO TITLE?     YES   NO", 0
cb_txt_ace:
        .db     "SECTOR CLEAR - ACE", 0
cb_txt_clear:
        .db     "SECTOR CLEAR", 0
cb_txt_end:
        .db     "ALL SECTORS BREACHED, RETRIES ", 0
cb_txt_caught:
        .db     "CAUGHT IN THE CROSSFIRE", 0
cb_txt_tagline:
        .db     "TIME MOVES ONLY WHEN YOU DO", 0
cb_txt_start:
        .db     "RETURN : START", 0
cb_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
cb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cb_help_1:
        .db     "W/A/S/D: ONE CELL. EACH MOVE,", 0
cb_help_2:
        .db     "SHOT OR WAIT MOVES THE BOLTS.", 0
cb_help_3:
        .db     "GUARDS FIRE EVERY THIRD ACT.", 0
cb_help_4:
        .db     "RED MARKS SHOW THEIR LINES.", 0
cb_help_5:
        .db     "STEP ONTO A GUARD TO STRIKE.", 0
cb_help_6:
        .db     "F: SHOOT 4 CELLS. X: WAIT.", 0
cb_help_7:
        .db     "RETURN/SPACE: MENU, A/D AIM", 0
cb_help_8:
        .db     "(FIRE WAIT RESET TITLE BACK).", 0
cb_help_9:
        .db     "BOLTS HIT GUARDS TOO. CLEAR", 0
cb_help_10:
        .db     "ALL GUARDS, THEN THE EXIT.", 0
cb_help_11:
        .db     "WITHIN TARGET ACTS: ACE.", 0
cb_help_back:
        .db     "ANY KEY : TITLE", 0

        .include "levels.inc"

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     cb_sfx_move, cb_sfx_kill, cb_jingle_win, cb_jingle_lose
cb_sfx_move:
        .db     100, 1, 0, 0
cb_sfx_menu:
        .db     70, 1, 0, 0
cb_sfx_shot:
        .db     25, 1, 35, 1, 50, 2, 0, 0
cb_sfx_kill:
        .db     40, 2, 60, 2, 90, 3, 0, 0
cb_sfx_volley:
        .db     180, 1, 0, 0
cb_sfx_empty:
        .db     230, 3, 0, 0

; Title: a tense ostinato in C minor, eighth note = 8 frames, looping.
cb_title_song:
        .db     1
        .dw     cb_title_melody, cb_title_harmony, cb_title_bass
cb_title_melody:
        .db     AU_C5, 8, AU_DS5, 8, AU_G5, 16, AU_F5, 8, AU_DS5, 8, AU_D5, 16
        .db     AU_DS5, 8, AU_G5, 8, AU_C6, 16, AU_B5, 8, AU_G5, 8, AU_C6, 16
        .db     AU_AS5, 8, AU_GS5, 8, AU_G5, 16, AU_F5, 8, AU_D5, 8, AU_C5, 32, 0, 0
cb_title_harmony:
        .db     AU_G4, 32, AU_GS4, 32, AU_G4, 32, AU_G4, 32
        .db     AU_F4, 32, AU_G4, 16, AU_B4, 16, AU_C5, 16, 0, 16, 0, 0
cb_title_bass:
        .db     AU_C3, 8, AU_C3, 8, AU_G2, 8, AU_C3, 8, AU_GS2, 8, AU_GS2, 8, AU_G2, 16
        .db     AU_C3, 8, AU_C3, 8, AU_G2, 8, AU_C3, 8, AU_G2, 8, AU_G2, 8, AU_C3, 16
        .db     AU_F2, 16, AU_G2, 16, AU_C3, 32, 0, 0

; Sector clear: C major.
cb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     cb_win_melody, cb_win_harmony, cb_win_bass
cb_win_melody:
        .db     AU_G5, 6, AU_C6, 6, AU_E6, 6, AU_G6, 30, 0, 0
cb_win_harmony:
        .db     AU_E5, 6, AU_G5, 6, AU_C6, 6, AU_E6, 30, 0, 0
cb_win_bass:
        .db     AU_C3, 18, AU_C2, 30, 0, 0
; Caught: a falling C minor figure.
cb_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     cb_lose_melody, cb_lose_harmony, cb_lose_bass
cb_lose_melody:
        .db     AU_G5, 12, AU_FS5, 12, AU_F5, 12, AU_DS5, 30, 0, 0
cb_lose_harmony:
        .db     AU_DS5, 12, AU_D5, 12, AU_CS5, 12, AU_C5, 30, 0, 0
cb_lose_bass:
        .db     AU_C3, 36, AU_C2, 30, 0, 0

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
        .include "../../../sdk/font_data.inc"

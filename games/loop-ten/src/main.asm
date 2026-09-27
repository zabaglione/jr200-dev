; SPDX-License-Identifier: MIT
; LOOP TEN for JR-200: a port of jr100dev games/loop_ten 1.6.1.
; Upstream is hand-written JR-100 assembly with no Python rules module; the
; twelve chambers, the ten-second loop, walls, hazards, the right-hand gates
; that open once the chamber's seal is lit, seals that stay lit across every
; rewind, the anchor at the start that jumps to the first unlit chamber, the
; early rewind by using a lit seal (or SPACE) and the held-direction repeat
; follow the upstream source (see tests/model.py). One tick here is six
; upstream ticks (0.1 s); effects pause the clock as upstream FX_BEGIN does.
; Display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "LOOP-TEN"
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

GAME_LEVELS:        .equ    1
; One tick is 0.1 s: GAME_RATE idle frames plus the render (see README).
GAME_RATE:          .equ    1
GAME_SPACE_RESET:   .equ    0       ; SPACE rewinds, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    4
GAME_TEST_SIZE:     .equ    10
GAME_TEST_LIMIT:    .equ    2000
GAME_TEST_HELD:     .equ    LT_HELD

; Upstream state (same order as tests/model.py LAYOUT).
LT_ROOM:            .equ    GAME_STATE
LT_X:               .equ    GAME_STATE + 1
LT_Y:               .equ    GAME_STATE + 2
LT_FLAGS:           .equ    GAME_STATE + 3      ; 2 bytes, seal i is bit i
LT_LOOPS:           .equ    GAME_STATE + 5
LT_TIME:            .equ    GAME_STATE + 6      ; tenths of a second left
LT_SINCE:           .equ    GAME_STATE + 7      ; ticks since the last move
LT_HELD:            .equ    GAME_STATE + 8
LT_SECONDS:         .equ    GAME_STATE + 9
; Rule work bytes.
LT_CX:              .equ    GAME_STATE + 16
LT_CY:              .equ    GAME_STATE + 17
LT_K:               .equ    GAME_STATE + 18
LT_FX:              .equ    GAME_STATE + 20     ; burst stage 1-3
LT_FXX:             .equ    GAME_STATE + 21
LT_FXY:             .equ    GAME_STATE + 22
; Drawing work bytes (game_draw runs inside effects: never shared with rules).
LT_DX:              .equ    GAME_STATE + 32
LT_DY:              .equ    GAME_STATE + 33
LT_OPEN:            .equ    GAME_STATE + 34
LT_DI:              .equ    GAME_STATE + 35
LT_DB:              .equ    GAME_STATE + 36
LT_DPTR:            .equ    GAME_STATE + 37     ; 2 bytes
LT_SCR:             .equ    GAME_STATE + 39     ; 2 bytes
LT_ATR:             .equ    GAME_STATE + 41     ; 2 bytes
LT_DCODE:           .equ    GAME_STATE + 43
LT_DT:              .equ    GAME_STATE + 44

LT_WALL:            .equ    1
LT_SEAL:            .equ    2
LT_GATE:            .equ    4
LT_HAZARD:          .equ    5
LT_ANCHOR:          .equ    6
LT_LOOP_TICKS:      .equ    100
LT_BURST_FRAMES:    .equ    4       ; three stages

LT_TILE_FLOOR:      .equ    0x80
LT_TILE_WALL:       .equ    0x84
LT_TILE_HERO:       .equ    0x88
LT_TILE_GATE:       .equ    0x8c
LT_TILE_SEAL:       .equ    0x90
LT_TILE_LIT:        .equ    0x94
LT_TILE_HAZARD:     .equ    0x98
LT_TILE_ANCHOR:     .equ    0x9c
LT_TILE_BURST:      .equ    0x00    ; three stages, in the second PCG bank
LT_CHAR_BAR:        .equ    0x0c
LT_CHAR_SEAL_OFF:   .equ    0x0d
LT_CHAR_SEAL_ON:    .equ    0x0e
LT_ATTR_FLOOR:      .equ    0x41
LT_ATTR_WALL:       .equ    0x41
LT_ATTR_HERO:       .equ    0x44
LT_ATTR_GATE:       .equ    0x45
LT_ATTR_SEAL:       .equ    0x43
LT_ATTR_LIT:        .equ    0x46
LT_ATTR_HAZARD:     .equ    0x42
LT_ATTR_ANCHOR:     .equ    0x47
LT_ATTR_BURST:      .equ    0x46
LT_ATTR_BAR:        .equ    0x45
LT_ATTR_BAR_LOW:    .equ    0x42
LT_ATTR_TEXT:       .equ    0x07
LT_ATTR_LABEL:      .equ    0x04
LT_ATTR_TITLE:      .equ    0x06
LT_ATTR_DIM:        .equ    0x05
LT_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_keyscan_init
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     lt_patterns
        LDAA    LT_TILE_FLOOR
        LDAB    32
        JSR     jr_pcg_load
        LDX     lt_patterns_low
        LDAA    LT_TILE_BURST
        LDAB    15
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; NEW_GAME: no seal lit, then the first loop.
game_init:
        JSR     jr_test_level
        JSR     jr_music_stop
        CLR     [LT_FLAGS]
        CLR     [LT_FLAGS + 1]
        CLR     [LT_LOOPS]
        ; fall through

; REWIND: back to the first chamber's start with ten seconds; seals stay.
lt_rewind:
        CLR     [LT_ROOM]
        LDAA    [LT_LOOPS]
        CMPA    255
        BEQ     lt_rewind_counted
        INC     [LT_LOOPS]
lt_rewind_counted:
        LDAA    2
        STAA    [LT_X]
        LDAA    4
        STAA    [LT_Y]
        LDAA    LT_LOOP_TICKS
        STAA    [LT_TIME]
        LDAA    10
        STAA    [LT_SECONDS]
        CLR     [LT_SINCE]
        RTS

; T runs the self test; P plays the whole escape as a demo.
game_raw_key:
        CLRA
        JMP     jr_test_raw_key

; A = chamber, LT_CX / LT_CY -> A = cell (4-bit, two per byte).
lt_cell_at:
        LDX     lt_chambers
        TSTA
        BEQ     lt_cell_row
lt_cell_seek:
        PSHA
        LDAA    80
        JSR     jr_add_x_a
        PULA
        DECA
        BNE     lt_cell_seek
lt_cell_row:
        LDAA    [LT_CY]
        ASLA
        ASLA
        ASLA
        JSR     jr_add_x_a
        LDAA    [LT_CX]
        LSRA
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [LT_CX]
        RORB
        BCS     lt_cell_low
        LSRA
        LSRA
        LSRA
        LSRA
lt_cell_low:
        ANDA    0x0f
        RTS

; A = chamber -> X = its flag byte, B = its bit, A = B AND [X] (Z set when
; unlit). Stores nothing, so game_draw may use it inside an effect.
lt_lit:
        TAB
        LDX     LT_FLAGS
        CMPA    8
        BCS     lt_lit_bit
        SUBB    8
        INX
lt_lit_bit:
        LDAA    1
lt_lit_shift:
        TSTB
        BEQ     lt_lit_ready
        ASLA
        DECB
        BRA     lt_lit_shift
lt_lit_ready:
        TAB
        ANDA    [X]
        RTS

game_act:
        CLR     [LT_SINCE]
        CMPA    JR_KEY_BACK
        BNE     lt_act_use
        LDX     lt_sfx_rewind
        JSR     jr_sfx_play
        LDAA    [LT_X]
        LDAB    [LT_Y]
        JSR     lt_burst
        JMP     lt_rewind
lt_act_use:
        CMPA    JR_KEY_CONFIRM
        BNE     lt_act_move
        JMP     lt_interact
lt_act_move:
        CMPA    JR_KEY_RIGHT
        BHI     lt_act_done
        JSR     lt_move
lt_act_done:
        RTS

; A = direction. Carry set when the step rewound (a hazard).
lt_move:
        STAA    [LT_K]
        LDAA    [LT_X]
        STAA    [LT_CX]
        LDAA    [LT_Y]
        STAA    [LT_CY]
        LDAA    [LT_K]
        CMPA    JR_KEY_UP
        BNE     lt_move_down
        DEC     [LT_CY]
        BRA     lt_move_test
lt_move_down:
        CMPA    JR_KEY_DOWN
        BNE     lt_move_left
        INC     [LT_CY]
        BRA     lt_move_test
lt_move_left:
        CMPA    JR_KEY_LEFT
        BNE     lt_move_right
        DEC     [LT_CX]
        BRA     lt_move_test
lt_move_right:
        INC     [LT_CX]
lt_move_test:
        LDAA    [LT_ROOM]
        JSR     lt_cell_at
        CMPA    LT_WALL
        BEQ     lt_blocked
        CMPA    LT_HAZARD
        BEQ     lt_move_hazard
        CMPA    LT_GATE
        BEQ     lt_move_gate
        LDAA    [LT_CX]
        STAA    [LT_X]
        LDAA    [LT_CY]
        STAA    [LT_Y]
        LDX     lt_sfx_step
        JSR     jr_sfx_play
        CLC
        RTS
lt_move_gate:
        LDAA    [LT_ROOM]
        JSR     lt_lit
        BEQ     lt_blocked
        INC     [LT_ROOM]
        LDAA    1
        STAA    [LT_X]
        LDAA    4
        STAA    [LT_Y]
        LDX     lt_sfx_gate
        JSR     jr_sfx_play
        CLC
        RTS
lt_move_hazard:
        LDX     lt_sfx_hit
        JSR     jr_sfx_play
        LDAA    [LT_CX]
        LDAB    [LT_CY]
        JSR     lt_burst
        JSR     lt_rewind
        SEC
        RTS
lt_blocked:
        LDX     lt_sfx_empty
        JSR     jr_sfx_play
        CLC
        RTS

; INTERACT: the anchor at the start, else the seal (on it or next to it).
lt_interact:
        LDAA    [LT_X]
        CMPA    2
        BNE     lt_interact_seal
        LDAA    [LT_Y]
        CMPA    4
        BNE     lt_interact_seal
        CLR     [LT_K]
lt_interact_scan:
        LDAA    [LT_K]
        JSR     lt_lit
        BEQ     lt_interact_anchor
        INC     [LT_K]
        LDAA    [LT_K]
        CMPA    12
        BCS     lt_interact_scan
        JMP     lt_blocked
lt_interact_anchor:
        LDAA    [LT_K]
        STAA    [LT_ROOM]
        LDX     lt_sfx_anchor
        JMP     jr_sfx_play
lt_interact_seal:
        LDAA    [LT_X]
        SUBA    12
        BCC     lt_interact_dx
        NEGA
lt_interact_dx:
        STAA    [LT_K]
        LDAA    [LT_Y]
        SUBA    4
        BCC     lt_interact_dy
        NEGA
lt_interact_dy:
        ADDA    [LT_K]
        CMPA    1
        BHI     lt_blocked
        LDAA    [LT_ROOM]
        JSR     lt_lit
        BEQ     lt_interact_light
        ; a lit seal used again rewinds early
        LDAA    JR_KEY_BACK
        JMP     game_act
lt_interact_light:
        LDAA    [LT_ROOM]
        JSR     lt_lit
        TBA
        ORAA    [X]
        STAA    [X]
        LDX     lt_sfx_seal
        JSR     jr_sfx_play
        LDAA    12
        LDAB    4
        JSR     lt_burst
        LDAA    [LT_ROOM]
        CMPA    11
        BNE     lt_interact_done
        JMP     jr_port_win
lt_interact_done:
        RTS

; A, B = cell: three burst stages there (the clock stands still meanwhile).
lt_burst:
        STAA    [LT_FXX]
        STAB    [LT_FXY]
        LDAA    1
        STAA    [LT_FX]
lt_burst_stage:
        LDAA    LT_BURST_FRAMES
        JSR     jr_test_animate
        INC     [LT_FX]
        LDAA    [LT_FX]
        CMPA    4
        BNE     lt_burst_stage
        CLR     [LT_FX]
        RTS

; One tick (0.1 s): the clock, then a held direction.
game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     lt_act_done_near377
        JMP     lt_act_done
lt_act_done_near377:
        TST     [JR_TEST_QUIET]
        BNE     lt_tick_rules
        LDAA    [JR_TEST_DEMO]
        CMPA    2
        BEQ     lt_tick_rules
        ; the held direction from the MCU scan
        JSR     jr_keyscan
        ORAA    0x20
        LDX     lt_held_keys
        CLRB
lt_tick_scan:
        INCB
        CMPA    [X]
        BEQ     lt_tick_scan_store
        INX
        CMPB    4
        BNE     lt_tick_scan
        CLRB
lt_tick_scan_store:
        STAB    [LT_HELD]
lt_tick_rules:
        DEC     [LT_TIME]
        BNE     lt_tick_seconds
        JMP     lt_rewind
lt_tick_seconds:
        ; seconds = ceil(time / 10); the last three are counted aloud
        LDAA    [LT_TIME]
        ADDA    9
        LDAB    10
        JSR     jr_divmod8          ; A = quotient
        CMPA    [LT_SECONDS]
        BEQ     lt_tick_held
        STAA    [LT_SECONDS]
        CMPA    4
        BCC     lt_tick_held
        LDX     lt_sfx_tick
        JSR     jr_sfx_play
lt_tick_held:
        LDAA    [LT_SINCE]
        CMPA    255
        BEQ     lt_tick_since
        INC     [LT_SINCE]
lt_tick_since:
        LDAA    [LT_HELD]
        BEQ     lt_tick_done
        CMPA    JR_KEY_RIGHT
        BHI     lt_tick_done
        LDAB    [LT_SINCE]
        CMPB    2
        BCS     lt_tick_done
        JSR     lt_move
        BCS     lt_tick_done
        LDAA    1
        STAA    [LT_SINCE]
lt_tick_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        ; the chamber covers rows 2-21; clear only the HUD rows 0-1 and 22-23
        LDAA    0x20
        LDX     JR_SHADOW
        JSR     lt_clear_rows
        LDX     JR_SHADOW + 704
        JSR     lt_clear_rows
        LDAA    LT_ATTR_TEXT
        LDX     JR_SHADOW + 0x300
        JSR     lt_clear_rows
        LDX     JR_SHADOW + 0x300 + 704
        JSR     lt_clear_rows
        LDX     lt_hud
        JSR     jr_gfx_lines
        LDAA    LT_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        CLRB
        JSR     jr_gfx_at
        LDAA    [LT_SECONDS]
        JSR     jr_gfx_dec2
        LDAA    15
        CLRB
        JSR     jr_gfx_at
        LDAA    [LT_LOOPS]
        JSR     jr_gfx_dec3
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDAA    [LT_ROOM]
        INCA
        JSR     jr_gfx_dec2
        ; the time bar: two cells a second, red in the last three
        LDAA    LT_ATTR_BAR
        LDAB    [LT_SECONDS]
        CMPB    4
        BCC     lt_draw_bar_colour
        LDAA    LT_ATTR_BAR_LOW
lt_draw_bar_colour:
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    1
        JSR     jr_gfx_at
        LDAB    [LT_SECONDS]
        ASLB
        BEQ     lt_draw_seals
lt_draw_bar:
        LDAA    LT_CHAR_BAR
        JSR     jr_gfx_putc
        DECB
        BNE     lt_draw_bar
lt_draw_seals:
        ; twelve seal marks
        LDAA    20
        LDAB    1
        JSR     jr_gfx_at
        CLR     [LT_DI]
lt_draw_seal:
        LDAA    [LT_DI]
        JSR     lt_lit
        BNE     lt_draw_seal_on
        LDAA    LT_ATTR_SEAL
        LDAB    LT_CHAR_SEAL_OFF
        BRA     lt_draw_seal_put
lt_draw_seal_on:
        LDAA    LT_ATTR_LIT
        LDAB    LT_CHAR_SEAL_ON
lt_draw_seal_put:
        STAA    [JR_RT_COLOR]
        TBA
        JSR     jr_gfx_putc
        INC     [LT_DI]
        LDAA    [LT_DI]
        CMPA    12
        BNE     lt_draw_seal
        ; the chamber's name, or the result
        LDAA    LT_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     lt_draw_name
        LDX     lt_txt_escaped
        JSR     jr_gfx_text
        LDAA    [LT_LOOPS]
        JSR     jr_gfx_dec3
        LDX     lt_txt_loops
        JSR     jr_gfx_text
        BRA     lt_draw_room
lt_draw_name:
        LDX     lt_names
        LDAA    [LT_ROOM]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
lt_draw_room:
        ; the chamber, straight into the shadow screen (attributes 0x300 on)
        LDAA    [LT_ROOM]
        JSR     lt_lit
        STAA    [LT_OPEN]
        LDX     lt_chambers
        LDAA    [LT_ROOM]
        BEQ     lt_draw_found
lt_draw_seek:
        PSHA
        LDAA    80
        JSR     jr_add_x_a
        PULA
        DECA
        BNE     lt_draw_seek
lt_draw_found:
        STX     [LT_DPTR]
        LDX     JR_SHADOW + 64
        STX     [LT_SCR]
        LDX     JR_SHADOW + 0x340
        STX     [LT_ATR]
        CLR     [LT_DX]
        CLR     [LT_DY]
lt_draw_cell:
        ; the cell's code: high nibble on even columns
        LDX     [LT_DPTR]
        LDAA    [X]
        LDAB    [LT_DX]
        RORB
        BCS     lt_draw_low
        LSRA
        LSRA
        LSRA
        LSRA
        BRA     lt_draw_code
lt_draw_low:
        ANDA    0x0f
        INX
        STX     [LT_DPTR]
lt_draw_code:
        ANDA    0x0f
        ; an open chamber shows its seal lit and its gate as floor
        TST     [LT_OPEN]
        BEQ     lt_draw_kind
        CMPA    LT_SEAL
        BNE     lt_draw_open_gate
        LDAA    3
        BRA     lt_draw_kind
lt_draw_open_gate:
        CMPA    LT_GATE
        BNE     lt_draw_kind
        CLRA
lt_draw_kind:
        ; the walker, and a burst over whatever lies below
        LDAB    [LT_DX]
        CMPB    [LT_X]
        BNE     lt_draw_fx
        LDAB    [LT_DY]
        CMPB    [LT_Y]
        BNE     lt_draw_fx
        LDAA    7
lt_draw_fx:
        TST     [LT_FX]
        BEQ     lt_draw_look
        LDAB    [LT_DX]
        CMPB    [LT_FXX]
        BNE     lt_draw_look
        LDAB    [LT_DY]
        CMPB    [LT_FXY]
        BNE     lt_draw_look
        LDAA    [LT_FX]
        ADDA    7
lt_draw_look:
        ASLA
        LDX     lt_cell_tiles
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 1]
        LDX     [LT_ATR]
        STAB    [X]
        STAB    [X + 1]
        STAB    [X + 32]
        STAB    [X + 33]
        INX
        INX
        STX     [LT_ATR]
        LDX     [LT_SCR]
        STAA    [X]
        INCA
        STAA    [X + 1]
        INCA
        STAA    [X + 32]
        INCA
        STAA    [X + 33]
        INX
        INX
        STX     [LT_SCR]
        INC     [LT_DX]
        LDAA    [LT_DX]
        CMPA    16
        BEQ     lt_draw_cell_near629
        JMP     lt_draw_cell
lt_draw_cell_near629:
        CLR     [LT_DX]
        LDAA    32
        LDX     [LT_SCR]
        JSR     jr_add_x_a
        STX     [LT_SCR]
        LDAA    32
        LDX     [LT_ATR]
        JSR     jr_add_x_a
        STX     [LT_ATR]
        INC     [LT_DY]
        LDAA    [LT_DY]
        CMPA    10
        BEQ     lt_draw_cell_near644
        JMP     lt_draw_cell
lt_draw_cell_near644:
        TST     [JR_TEST_DEMO]
        BEQ     lt_draw_done
        LDAA    LT_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    22
        JSR     jr_gfx_at
        LDX     lt_txt_demo
        JMP     jr_gfx_text
lt_draw_done:
        RTS

; X = shadow row, A = byte: fill two rows (64 codes or attributes).
lt_clear_rows:
        LDAB    64
lt_clear_cell:
        STAA    [X]
        INX
        DECB
        BNE     lt_clear_cell
        RTS

game_draw_title:
        LDX     lt_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    LT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lt_title_tiles
        STX     [LT_DPTR]
lt_title_tile:
        LDX     [LT_DPTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     lt_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [LT_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [LT_DCODE]
        JSR     jr_gfx_tile
        LDX     [LT_DPTR]
        INX
        INX
        INX
        INX
        STX     [LT_DPTR]
        BRA     lt_title_tile
lt_title_text:
        LDX     lt_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    LT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lt_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

lt_held_keys:
        .db     0x77, 0x73, 0x61, 0x64      ; W S A D

; cell kind (0 floor .. 6 anchor, 3 lit seal, 7 walker, 8-10 burst) -> tile, attribute
lt_cell_tiles:
        .db     LT_TILE_FLOOR, LT_ATTR_FLOOR, LT_TILE_WALL, LT_ATTR_WALL
        .db     LT_TILE_SEAL, LT_ATTR_SEAL, LT_TILE_LIT, LT_ATTR_LIT
        .db     LT_TILE_GATE, LT_ATTR_GATE, LT_TILE_HAZARD, LT_ATTR_HAZARD
        .db     LT_TILE_ANCHOR, LT_ATTR_ANCHOR, LT_TILE_HERO, LT_ATTR_HERO
        .db     LT_TILE_BURST, LT_ATTR_BURST, LT_TILE_BURST + 4, LT_ATTR_BURST
        .db     LT_TILE_BURST + 8, LT_ATTR_BURST

; x, attribute, code, y
lt_title_tiles:
        .db     8, LT_ATTR_ANCHOR, LT_TILE_ANCHOR, 3
        .db     12, LT_ATTR_HERO, LT_TILE_HERO, 3
        .db     16, LT_ATTR_SEAL, LT_TILE_SEAL, 3
        .db     20, LT_ATTR_LIT, LT_TILE_LIT, 3
        .db     0xff

lt_hud:
        .db     0, 0, LT_ATTR_LABEL
        .dw     lt_txt_time
        .db     10, 0, LT_ATTR_LABEL
        .dw     lt_txt_loop
        .db     22, 0, LT_ATTR_LABEL
        .dw     lt_txt_room
        .db     0xff
lt_title_lines:
        .db     11, 8, LT_ATTR_TITLE
        .dw     lt_txt_name
        .db     3, 10, LT_ATTR_LABEL
        .dw     lt_txt_tagline
        .db     8, 14, LT_ATTR_TEXT
        .dw     lt_txt_start
        .db     4, 16, LT_ATTR_TEXT
        .dw     lt_txt_howto
        .db     4, 19, LT_ATTR_DIM
        .dw     lt_txt_demo_hint
        .db     4, 22, LT_ATTR_DIM
        .dw     lt_txt_credit
        .db     0xff
lt_help_lines:
        .db     11, 1, LT_ATTR_TITLE
        .dw     lt_txt_name
        .db     1, 3, LT_ATTR_TEXT
        .dw     lt_help_1
        .db     1, 5, LT_ATTR_TEXT
        .dw     lt_help_2
        .db     1, 7, LT_ATTR_TEXT
        .dw     lt_help_3
        .db     1, 9, LT_ATTR_TEXT
        .dw     lt_help_4
        .db     1, 11, LT_ATTR_TEXT
        .dw     lt_help_5
        .db     1, 13, LT_ATTR_TEXT
        .dw     lt_help_6
        .db     1, 15, LT_ATTR_TEXT
        .dw     lt_help_7
        .db     1, 17, LT_ATTR_TEXT
        .dw     lt_help_8
        .db     1, 21, LT_ATTR_LABEL
        .dw     lt_help_back
        .db     0xff

lt_txt_name:
        .db     "LOOP TEN", 0
lt_txt_time:
        .db     "TIME", 0
lt_txt_loop:
        .db     "LOOP", 0
lt_txt_room:
        .db     "ROOM", 0
lt_txt_escaped:
        .db     "ESCAPED AFTER ", 0
lt_txt_loops:
        .db     " LOOPS", 0
lt_txt_demo:
        .db     "DEMO", 0
lt_txt_tagline:
        .db     "TEN SECONDS, TWELVE SEALS", 0
lt_txt_start:
        .db     "RETURN : START", 0
lt_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
lt_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
lt_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
lt_help_1:
        .db     "W/A/S/D: WALK (HOLD TO REPEAT).", 0
lt_help_2:
        .db     "EVERY 10 SECONDS YOU RETURN", 0
lt_help_3:
        .db     "TO THE FIRST ROOM'S START.", 0
lt_help_4:
        .db     "RETURN BY THE DIAMOND SEAL:", 0
lt_help_5:
        .db     "LIGHT IT; THE RIGHT DOOR OPENS.", 0
lt_help_6:
        .db     "LIT SEALS STAY LIT. RETURN ON", 0
lt_help_7:
        .db     "THE CLOCK: FIRST UNLIT ROOM.", 0
lt_help_8:
        .db     "SPACE REWINDS. RED FLOOR HURTS.", 0
lt_help_back:
        .db     "ANY KEY : TITLE", 0

        .include "rooms.inc"
        .include "selftest.inc"

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     lt_sfx_step, lt_sfx_seal, lt_jingle_win, lt_jingle_win
lt_sfx_step:
        .db     90, 1, 0, 0
lt_sfx_empty:
        .db     230, 2, 0, 0
lt_sfx_gate:
        .db     120, 2, 90, 2, 0, 0
lt_sfx_hit:
        .db     200, 2, 240, 2, 250, 4, 0, 0
lt_sfx_rewind:
        .db     40, 2, 60, 2, 80, 2, 100, 2, 120, 3, 0, 0
lt_sfx_seal:
        .db     60, 2, 45, 2, 30, 6, 0, 0
lt_sfx_anchor:
        .db     70, 2, 50, 4, 0, 0
lt_sfx_tick:
        .db     35, 1, 0, 0

; Title: a clock-like figure in A minor, eighth note = 8 frames, looping.
lt_title_song:
        .db     1
        .dw     lt_title_melody, lt_title_harmony, lt_title_bass
lt_title_melody:
        .db     AU_A5, 8, AU_E5, 8, AU_A5, 8, AU_E5, 8, AU_C6, 8, AU_B5, 8, AU_A5, 16
        .db     AU_G5, 8, AU_D5, 8, AU_G5, 8, AU_D5, 8, AU_B5, 8, AU_A5, 8, AU_G5, 16
        .db     AU_F5, 8, AU_C5, 8, AU_F5, 8, AU_A5, 8, AU_E5, 8, AU_GS5, 8, AU_B5, 16
        .db     AU_A5, 32, 0, 32, 0, 0
lt_title_harmony:
        .db     AU_C5, 32, AU_E5, 32, AU_B4, 32, AU_D5, 32
        .db     AU_A4, 32, AU_B4, 32, AU_C5, 32, 0, 32, 0, 0
lt_title_bass:
        .db     AU_A2, 16, AU_E3, 16, AU_A2, 16, AU_E3, 16, AU_G2, 16, AU_D3, 16
        .db     AU_G2, 16, AU_D3, 16, AU_F2, 16, AU_C3, 16, AU_E2, 16, AU_E3, 16
        .db     AU_A2, 32, 0, 32, 0, 0

; Escape: A major bells.
lt_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     lt_win_melody, lt_win_harmony, lt_win_bass
lt_win_melody:
        .db     AU_E6, 6, AU_CS6, 6, AU_A5, 6, AU_E6, 6, AU_A6, 30, 0, 0
lt_win_harmony:
        .db     AU_CS6, 12, AU_A5, 12, AU_CS6, 30, 0, 0
lt_win_bass:
        .db     AU_A3, 24, AU_A2, 30, 0, 0

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

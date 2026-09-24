; SPDX-License-Identifier: MIT
; CIRCUIT WORKS for JR-200: a port of jr100dev games/circuit_works/rules.py 2.1.0.
; G1 = A op B, G2 = G1 op C, G3 = G2 op A with AND/OR/XOR, 22 target tables,
; the eight-row test and the TESTS counter follow the upstream source.
        .filename.jr "CIRCUIT-WORKS"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    22
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: c[3], d[8], b[8], cursor, probe, running, signal, pulse,
; correct, tested, tests.
CW_C:               .equ    GAME_STATE
CW_D:               .equ    GAME_STATE + 3
CW_B:               .equ    GAME_STATE + 11
CW_CURSOR:          .equ    GAME_STATE + 19
CW_PROBE:           .equ    GAME_STATE + 20
CW_RUNNING:         .equ    GAME_STATE + 21
CW_SIGNAL:          .equ    GAME_STATE + 22
CW_PULSE:           .equ    GAME_STATE + 23
CW_CORRECT:         .equ    GAME_STATE + 24
CW_TESTED:          .equ    GAME_STATE + 25
CW_TESTS:           .equ    GAME_STATE + 26
; Rule work bytes.
CW_I:               .equ    GAME_STATE + 32
CW_STAGE:           .equ    GAME_STATE + 33
CW_OPERAND:         .equ    GAME_STATE + 34
CW_KIND:            .equ    GAME_STATE + 35
CW_P:               .equ    GAME_STATE + 36
CW_Q:               .equ    GAME_STATE + 37
CW_R:               .equ    GAME_STATE + 38
CW_IN_A:            .equ    GAME_STATE + 39
CW_IN_B:            .equ    GAME_STATE + 40
CW_IN_C:            .equ    GAME_STATE + 41
CW_TMP:             .equ    GAME_STATE + 42
; Drawing work bytes.
CW_DI:              .equ    GAME_STATE + 48
CW_DY:              .equ    GAME_STATE + 49
CW_DV:              .equ    GAME_STATE + 50
CW_DW:              .equ    GAME_STATE + 51

CW_TILE_GATE:       .equ    0x80
CW_CODE_WIRE:       .equ    0x8c
CW_ATTR_TEXT:       .equ    0x07
CW_ATTR_LABEL:      .equ    0x04
CW_ATTR_TITLE:      .equ    0x06
CW_ATTR_WIRE:       .equ    0x41
CW_ATTR_ZERO:       .equ    0x05
CW_ATTR_ONE:        .equ    0x06
CW_ATTR_MATCH:      .equ    0x04
CW_ATTR_MISS:       .equ    0x02
CW_ATTR_HOT:        .equ    0x03

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     cw_patterns
        LDAA    CW_TILE_GATE
        LDAB    13
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; A, B, kind -> A = gate(a, b, kind)
cw_gate:
        LDAB    [CW_KIND]
        BEQ     cw_gate_and
        CMPB    1
        BEQ     cw_gate_or
        EORA    [CW_OPERAND]
        RTS
cw_gate_and:
        ANDA    [CW_OPERAND]
        RTS
cw_gate_or:
        ORAA    [CW_OPERAND]
        RTS

; A = input index 0-7 -> CW_IN_A, CW_IN_B, CW_IN_C.
cw_inputs:
        TAB
        LSRA
        LSRA
        STAA    [CW_IN_A]
        TBA
        LSRA
        ANDA    1
        STAA    [CW_IN_B]
        ANDB    1
        STAB    [CW_IN_C]
        RTS

game_init:
        LDX     cw_targets
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_mul8
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [CW_P]
        LDAA    [X + 1]
        STAA    [CW_Q]
        LDAA    [X + 2]
        STAA    [CW_R]
        CLR     [CW_I]
cw_init_row:
        LDAA    [CW_I]
        JSR     cw_inputs
        LDAA    [CW_IN_B]
        STAA    [CW_OPERAND]
        LDAA    [CW_P]
        STAA    [CW_KIND]
        LDAA    [CW_IN_A]
        JSR     cw_gate
        LDAB    [CW_IN_C]
        STAB    [CW_OPERAND]
        LDAB    [CW_Q]
        STAB    [CW_KIND]
        JSR     cw_gate
        LDAB    [CW_IN_A]
        STAB    [CW_OPERAND]
        LDAB    [CW_R]
        STAB    [CW_KIND]
        JSR     cw_gate
        STAA    [CW_TMP]
        LDX     CW_D
        LDAA    [CW_I]
        JSR     jr_add_x_a
        LDAA    [CW_TMP]
        STAA    [X]
        INC     [CW_I]
        LDAA    [CW_I]
        CMPA    8
        BNE     cw_init_row
        LDAA    0xff
        STAA    [CW_PROBE]
        STAA    [CW_RUNNING]
        RTS

game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     cw_test
        CMPA    JR_KEY_UP
        BNE     cw_act_down
        LDAA    [CW_CURSOR]
        ADDA    2
        BRA     cw_act_cursor
cw_act_down:
        CMPA    JR_KEY_DOWN
        BNE     cw_act_kind
        LDAA    [CW_CURSOR]
        INCA
cw_act_cursor:
        JSR     cw_mod3
        STAA    [CW_CURSOR]
        RTS
cw_act_kind:
        LDX     CW_C
        LDAB    [CW_CURSOR]
        STAB    [CW_TMP]
        LDAA    [CW_TMP]
        JSR     jr_add_x_a
        LDAA    [JR_PORT_ACTION]
        CMPA    JR_KEY_LEFT
        BNE     cw_act_right
        LDAA    [X]
        ADDA    2
        BRA     cw_act_store
cw_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     cw_act_done
        LDAA    [X]
        INCA
cw_act_store:
        JSR     cw_mod3
        STAA    [X]
cw_act_done:
        RTS

; A = 0-5 -> A % 3.
cw_mod3:
        CMPA    3
        BCS     cw_mod3_done
        SUBA    3
        BRA     cw_mod3
cw_mod3_done:
        RTS

; RETURN: run all eight inputs through the three gates.
cw_test:
        CLR     [CW_CORRECT]
        CLR     [CW_TESTED]
        CLR     [CW_I]
cw_test_row:
        LDAA    [CW_I]
        STAA    [CW_PROBE]
        JSR     cw_inputs
        LDAA    [CW_IN_A]
        STAA    [CW_SIGNAL]
        CLR     [CW_STAGE]
cw_test_stage:
        LDAA    [CW_STAGE]
        STAA    [CW_RUNNING]
        LDAA    [CW_IN_B]
        LDAB    [CW_STAGE]
        BEQ     cw_test_operand
        LDAA    [CW_IN_C]
        CMPB    1
        BEQ     cw_test_operand
        LDAA    [CW_IN_A]
cw_test_operand:
        STAA    [CW_OPERAND]
        LDX     CW_C
        LDAA    [CW_STAGE]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [CW_KIND]
        LDAA    [CW_SIGNAL]
        JSR     cw_gate
        STAA    [CW_SIGNAL]
        CLRA
        JSR     jr_port_sound
        CLR     [CW_PULSE]
cw_test_pulse:
        LDAA    2
        JSR     jr_port_animate
        INC     [CW_PULSE]
        LDAA    [CW_PULSE]
        CMPA    3
        BNE     cw_test_pulse
        DEC     [CW_PULSE]
        INC     [CW_STAGE]
        LDAA    [CW_STAGE]
        CMPA    3
        BNE     cw_test_stage
        LDX     CW_B
        LDAA    [CW_I]
        JSR     jr_add_x_a
        LDAA    [CW_SIGNAL]
        STAA    [X]
        INC     [CW_TESTED]
        LDX     CW_D
        LDAA    [CW_I]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [CW_SIGNAL]
        BNE     cw_test_next
        INC     [CW_CORRECT]
cw_test_next:
        LDAA    4
        JSR     jr_port_animate
        INC     [CW_I]
        LDAA    [CW_I]
        CMPA    8
        BEQ     cw_test_done
        JMP     cw_test_row
cw_test_done:
        LDAA    0xff
        STAA    [CW_RUNNING]
        STAA    [CW_PROBE]
        LDAA    [CW_TESTS]
        CMPA    99
        BCC     cw_test_sound
        INC     [CW_TESTS]
cw_test_sound:
        LDAA    3
        LDAB    [CW_CORRECT]
        CMPB    8
        BNE     cw_test_result
        LDAA    1
cw_test_result:
        JSR     jr_port_sound
        LDAA    12
        JSR     jr_port_animate
        LDAA    [CW_CORRECT]
        CMPA    8
        BEQ     cw_test_won
        RTS
cw_test_won:
        JMP     jr_port_win

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    CW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cw_hud
        JSR     jr_gfx_lines
        LDAA    CW_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        CLR     [CW_DI]
cw_draw_gate:
        LDAA    [CW_DI]
        ASLA
        ASLA
        ADDA    5
        STAA    [CW_DY]
        LDX     CW_C
        LDAA    [CW_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [CW_DV]
        ; gate symbol at (4, y), coloured by kind
        LDX     cw_kind_attr
        JSR     jr_add_x_a
        LDAA    [X]
        ORAA    0x40
        STAA    [JR_RT_COLOR]
        LDAA    4
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    [CW_DV]
        ASLA
        ASLA
        ADDA    CW_TILE_GATE
        JSR     jr_gfx_tile
        ; kind name at (8, y)
        LDX     cw_kind_attr
        LDAA    [CW_DV]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDX     cw_kind_names
        LDAA    [CW_DV]
        ASLA
        ASLA
        JSR     jr_add_x_a
        JSR     jr_gfx_text
        ; '>' at (7, y) and the operand name at (7, y + 1)
        LDAA    CW_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    7
        LDAB    [CW_DY]
        INCB
        JSR     jr_gfx_at
        LDX     cw_operand_names
        LDAA    [CW_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     jr_gfx_putc
        ; three wire cells below the gate
        LDAA    CW_ATTR_WIRE
        STAA    [JR_RT_COLOR]
        CLR     [CW_DW]
cw_draw_wire:
        LDAA    5
        LDAB    [CW_DY]
        ADDB    2
        ADDB    [CW_DW]
        JSR     jr_gfx_at
        LDAA    CW_CODE_WIRE
        JSR     jr_gfx_putc
        INC     [CW_DW]
        LDAA    [CW_DW]
        CMPA    3
        BNE     cw_draw_wire
        LDAA    [CW_RUNNING]
        CMPA    [CW_DI]
        BNE     cw_draw_gate_next
        ; running stage: signal at (12, y), '*' at (3, y), pulse on the wire
        LDAA    [CW_SIGNAL]
        JSR     cw_value_attr
        LDAA    12
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    [CW_SIGNAL]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    5
        LDAB    [CW_DY]
        ADDB    2
        ADDB    [CW_PULSE]
        JSR     jr_gfx_at
        LDAA    [CW_SIGNAL]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    CW_ATTR_HOT
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
cw_draw_gate_next:
        INC     [CW_DI]
        LDAA    [CW_DI]
        CMPA    3
        BEQ     cw_draw_cursor
        JMP     cw_draw_gate
cw_draw_cursor:
        LDAA    CW_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    [CW_CURSOR]
        ASLA
        ASLA
        ADDA    5
        TAB
        LDAA    1
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; truth table
        CLR     [CW_DI]
cw_draw_row:
        LDAA    [CW_DI]
        ASLA
        ADDA    4
        STAA    [CW_DY]
        LDAA    [CW_DI]
        JSR     cw_inputs_draw
        LDAA    17
        LDAB    [CW_IN_A + 16]
        JSR     cw_draw_bit
        LDAA    19
        LDAB    [CW_IN_B + 16]
        JSR     cw_draw_bit
        LDAA    21
        LDAB    [CW_IN_C + 16]
        JSR     cw_draw_bit
        LDX     CW_D
        LDAA    [CW_DI]
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    25
        JSR     cw_draw_bit
        LDAA    [CW_DI]
        CMPA    [CW_TESTED]
        BCC     cw_draw_probe
        LDX     CW_B
        LDAA    [CW_DI]
        JSR     jr_add_x_a
        LDAB    [X]
        STAB    [CW_DV]
        LDAA    29
        JSR     cw_draw_bit
        LDX     CW_D
        LDAA    [CW_DI]
        JSR     jr_add_x_a
        LDAA    CW_ATTR_MATCH
        LDAB    0x2a
        STAB    [CW_DW]
        LDAB    [X]
        CMPB    [CW_DV]
        BEQ     cw_draw_mark
        LDAA    CW_ATTR_MISS
        LDAB    0x58
        STAB    [CW_DW]
cw_draw_mark:
        STAA    [JR_RT_COLOR]
        LDAA    31
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    [CW_DW]
        JSR     jr_gfx_putc
cw_draw_probe:
        LDAA    [CW_PROBE]
        CMPA    [CW_DI]
        BNE     cw_draw_row_next
        LDAA    CW_ATTR_HOT
        STAA    [JR_RT_COLOR]
        LDAA    16
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
cw_draw_row_next:
        INC     [CW_DI]
        LDAA    [CW_DI]
        CMPA    8
        BEQ     cw_draw_counters
        JMP     cw_draw_row
cw_draw_counters:
        LDAA    CW_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [CW_TESTS]
        JSR     jr_gfx_dec2
        LDAA    25
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [CW_CORRECT]
        JMP     jr_gfx_dec2

; Drawing copy of cw_inputs (stores 16 bytes higher, never shared with rules).
cw_inputs_draw:
        TAB
        LSRA
        LSRA
        STAA    [CW_IN_A + 16]
        TBA
        LSRA
        ANDA    1
        STAA    [CW_IN_B + 16]
        ANDB    1
        STAB    [CW_IN_C + 16]
        RTS

; A = column, B = bit at row CW_DY, coloured by value.
cw_draw_bit:
        PSHB
        PSHA
        TBA
        JSR     cw_value_attr
        PULA
        LDAB    [CW_DY]
        JSR     jr_gfx_at
        PULA
        ADDA    0x30
        JMP     jr_gfx_putc

; A = bit -> JR_RT_COLOR.
cw_value_attr:
        LDAB    CW_ATTR_ZERO
        TSTA
        BEQ     cw_value_attr_set
        LDAB    CW_ATTR_ONE
cw_value_attr_set:
        STAB    [JR_RT_COLOR]
        RTS

game_draw_title:
        LDAA    0x20
        LDAB    CW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cw_title_gates
        STX     [JR_RT_TABLE]
cw_title_gate:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     cw_title_text
        LDAB    [X + 3]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        LDAA    [X + 2]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     cw_title_gate
cw_title_text:
        LDX     cw_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cw_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; game.json dataTables.targets (22 puzzles x gate kinds for G1, G2, G3).
cw_targets:
        .db     0, 0, 0, 0, 0, 1, 0, 0, 2, 0, 1, 0, 0, 1, 1, 0, 1, 2
        .db     0, 2, 0, 0, 2, 2, 1, 0, 0, 1, 0, 1, 1, 0, 2, 1, 1, 1
        .db     1, 1, 2, 1, 2, 0, 1, 2, 1, 1, 2, 2, 2, 0, 0, 2, 0, 2
        .db     2, 1, 0, 2, 1, 2, 2, 2, 0, 2, 2, 2
cw_kind_attr:
        .db     0x05, 0x03, 0x06
cw_kind_names:
        .db     "AND", 0, "OR ", 0, "XOR", 0
cw_operand_names:
        .db     "BCA"

cw_hud:
        .db     1, 0, CW_ATTR_TITLE
        .dw     cw_txt_name
        .db     23, 0, CW_ATTR_LABEL
        .dw     cw_txt_stage
        .db     1, 2, CW_ATTR_LABEL
        .dw     cw_txt_logic
        .db     17, 2, CW_ATTR_LABEL
        .dw     cw_txt_columns
        .db     1, 18, CW_ATTR_LABEL
        .dw     cw_txt_chain
        .db     1, 20, CW_ATTR_LABEL
        .dw     cw_txt_tests
        .db     16, 20, CW_ATTR_LABEL
        .dw     cw_txt_matched
        .db     0xff

; column, row, tile, attribute
cw_title_gates:
        .db     9, 3, CW_TILE_GATE, 0x45
        .db     14, 3, CW_TILE_GATE + 4, 0x43
        .db     19, 3, CW_TILE_GATE + 8, 0x46
        .db     0xff
cw_title_lines:
        .db     9, 8, CW_ATTR_TITLE
        .dw     cw_txt_name
        .db     6, 10, CW_ATTR_LABEL
        .dw     cw_txt_tagline
        .db     8, 15, CW_ATTR_TEXT
        .dw     cw_txt_start
        .db     5, 17, CW_ATTR_TEXT
        .dw     cw_txt_howto
        .db     4, 22, 0x01
        .dw     cw_txt_credit
        .db     0xff
cw_help_lines:
        .db     9, 2, CW_ATTR_TITLE
        .dw     cw_txt_name
        .db     2, 5, CW_ATTR_TEXT
        .dw     cw_help_1
        .db     2, 7, CW_ATTR_TEXT
        .dw     cw_help_2
        .db     2, 9, CW_ATTR_TEXT
        .dw     cw_help_3
        .db     2, 11, CW_ATTR_TEXT
        .dw     cw_help_4
        .db     2, 13, CW_ATTR_TEXT
        .dw     cw_help_5
        .db     2, 15, CW_ATTR_TEXT
        .dw     cw_help_6
        .db     2, 17, CW_ATTR_TEXT
        .dw     cw_help_7
        .db     2, 20, CW_ATTR_LABEL
        .dw     cw_help_back
        .db     0xff

cw_txt_name:
        .db     "CIRCUIT WORKS", 0
cw_txt_stage:
        .db     "STAGE", 0
cw_txt_logic:
        .db     "3-INPUT LOGIC", 0
cw_txt_columns:
        .db     "A B C   W   NOW", 0
cw_txt_chain:
        .db     "G1>G2>G3", 0
cw_txt_tests:
        .db     "TESTS", 0
cw_txt_matched:
        .db     "MATCHED    /8", 0
cw_txt_tagline:
        .db     "MATCH EVERY OUTPUT", 0
cw_txt_start:
        .db     "RETURN : START", 0
cw_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
cw_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cw_help_1:
        .db     "W/S : SELECT A LOGIC GATE", 0
cw_help_2:
        .db     "A/D : CHOOSE AND, OR OR XOR", 0
cw_help_3:
        .db     "G1=A OP B / G2=G1 OP C", 0
cw_help_4:
        .db     "G3=G2 OP A / W=WANTED", 0
cw_help_5:
        .db     "RETURN : TEST ALL 8 INPUTS", 0
cw_help_6:
        .db     "MATCH EVERY OUTPUT TO WIN.", 0
cw_help_7:
        .db     "SPACE RESTART / ESC TO BASIC", 0
cw_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     cw_sfx_pulse, cw_sfx_ok, cw_sfx_win, cw_sfx_miss
cw_sfx_pulse:
        .db     60, 1, 0, 0
cw_sfx_ok:
        .db     100, 3, 80, 3, 60, 6, 0, 0
cw_sfx_win:
        .db     120, 6, 95, 6, 80, 6, 60, 14, 0, 0
cw_sfx_miss:
        .db     160, 6, 220, 10, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"

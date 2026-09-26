; SPDX-License-Identifier: MIT
; PHASE PAIRS for JR-200: a port of jr100dev games/phase_pairs/rules.py 1.6.1.
; The ten boards (upstream levels.json), neighbour pairs that sum to ten, the
; fusion, the rejections and the six-miss limit follow the upstream source;
; display, colour and three-voice sound use the JR-200 port SDK. Neighbours
; that make ten are marked steadily instead of upstream's src/hints.asm blink.
        .filename.jr "PHASE-PAIRS"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    10
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[16] and c[16].
PH_CURSOR:          .equ    GAME_STATE
PH_LEFT:            .equ    GAME_STATE + 1
PH_FIRST:           .equ    GAME_STATE + 2
PH_ERRORS:          .equ    GAME_STATE + 3
PH_REJECT:          .equ    GAME_STATE + 4
PH_MERGING:         .equ    GAME_STATE + 5
PH_AX:              .equ    GAME_STATE + 6
PH_AY:              .equ    GAME_STATE + 7
PH_BX:              .equ    GAME_STATE + 8
PH_BY:              .equ    GAME_STATE + 9
PH_CX:              .equ    GAME_STATE + 10
PH_CY:              .equ    GAME_STATE + 11
PH_B:               .equ    GAME_STATE + 12
PH_C:               .equ    GAME_STATE + 28
; Rule work bytes.
PH_K:               .equ    GAME_STATE + 48
PH_VALID:           .equ    GAME_STATE + 49
PH_N:               .equ    GAME_STATE + 50
PH_T:               .equ    GAME_STATE + 51
; Drawing work bytes.
PH_DI:              .equ    GAME_STATE + 56
PH_DX:              .equ    GAME_STATE + 57
PH_DY:              .equ    GAME_STATE + 58
PH_DV:              .equ    GAME_STATE + 59
PH_DCH:             .equ    GAME_STATE + 60
PH_DHI:             .equ    GAME_STATE + 61
PH_DBG:             .equ    GAME_STATE + 62

PH_TILE_DIGIT:      .equ    0x00        ; + 2 * digit (top), + 1 (bottom)
PH_ATTR_BIG:        .equ    0x47
PH_ATTR_TEN:        .equ    0x38
PH_ATTR_TEXT:       .equ    0x07
PH_ATTR_LABEL:      .equ    0x04
PH_ATTR_TITLE:      .equ    0x06
PH_ATTR_DIM:        .equ    0x05
PH_ATTR_PICK:       .equ    0x06
PH_ATTR_GOOD:       .equ    0x04
PH_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     ph_digit_patterns
        CLRA
        LDAB    20
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        CLR     [PH_K]
ph_init_copy:
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ASLA
        ASLA
        ASLA
        ADDA    [PH_K]
        LDX     ph_levels
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    [PH_K]
        JSR     ph_slot
        STAB    [X]
        INC     [PH_K]
        LDAA    [PH_K]
        CMPA    16
        BNE     ph_init_copy
        LDAA    16
        STAA    [PH_LEFT]
        LDAA    0xff
        STAA    [PH_FIRST]
        RTS

; A = cell -> X = b[cell].
ph_slot:
        LDX     PH_B
        JMP     jr_add_x_a

; A = position, B = action 1-4 -> A = moved position (4x4, stops at edges).
ph_move:
        STAA    [PH_T]
        CMPB    JR_KEY_UP
        BNE     ph_move_down
        CMPA    4
        BCS     ph_move_done
        SUBA    4
        RTS
ph_move_down:
        CMPB    JR_KEY_DOWN
        BNE     ph_move_side
        CMPA    12
        BCC     ph_move_done
        ADDA    4
        RTS
ph_move_side:
        ANDA    3
        CMPB    JR_KEY_LEFT
        BNE     ph_move_right
        TSTA
        BEQ     ph_move_stay
        LDAA    [PH_T]
        DECA
        RTS
ph_move_right:
        CMPA    3
        BCC     ph_move_stay
        LDAA    [PH_T]
        INCA
        RTS
ph_move_stay:
        LDAA    [PH_T]
ph_move_done:
        RTS

; A = value, B = target -> A one step closer.
ph_toward:
        CBA
        BEQ     ph_toward_done
        BCC     ph_toward_down
        INCA
        RTS
ph_toward_down:
        DECA
ph_toward_done:
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     ph_pick
        BCC     ph_act_done
        TSTA
        BEQ     ph_act_done
        TAB
        LDAA    [PH_CURSOR]
        JSR     ph_move
        STAA    [PH_CURSOR]
ph_act_done:
        RTS

ph_pick:
        LDAA    [PH_CURSOR]
        JSR     ph_slot
        TST     [X]
        BEQ     ph_act_done
        LDAA    [PH_FIRST]
        CMPA    0xff
        BNE     ph_second
        ; the first number: mark neighbours that make ten with it
        LDAA    [PH_CURSOR]
        STAA    [PH_FIRST]
        LDAA    1
        STAA    [PH_K]
ph_first_side:
        LDAA    [PH_FIRST]
        LDAB    [PH_K]
        JSR     ph_move
        STAA    [PH_N]
        CMPA    [PH_FIRST]
        BEQ     ph_first_next
        JSR     ph_slot
        LDAB    [X]
        LDAA    [PH_FIRST]
        PSHB
        JSR     ph_slot
        PULB
        ADDB    [X]
        CMPB    10
        BNE     ph_first_next
        LDAA    [PH_N]
        JSR     ph_slot
        LDAA    1
        STAA    [X + 16]
ph_first_next:
        INC     [PH_K]
        LDAA    [PH_K]
        CMPA    5
        BNE     ph_first_side
        CLRA
        JMP     jr_port_sound

ph_second:
        ; valid when the second is a different, orthogonal neighbour
        CLR     [PH_VALID]
        LDAA    1
        STAA    [PH_K]
ph_second_side:
        LDAA    [PH_CURSOR]
        CMPA    [PH_FIRST]
        BEQ     ph_second_next
        LDAA    [PH_FIRST]
        LDAB    [PH_K]
        JSR     ph_move
        CMPA    [PH_CURSOR]
        BNE     ph_second_next
        LDAA    1
        STAA    [PH_VALID]
ph_second_next:
        INC     [PH_K]
        LDAA    [PH_K]
        CMPA    5
        BNE     ph_second_side
        TST     [PH_VALID]
        BEQ     ph_miss
        LDAA    [PH_FIRST]
        JSR     ph_slot
        LDAB    [X]
        LDAA    [PH_CURSOR]
        PSHB
        JSR     ph_slot
        PULB
        ADDB    [X]
        CMPB    10
        BEQ     ph_fuse
ph_miss:
        INC     [PH_ERRORS]
        LDAA    1
        TST     [PH_VALID]
        BEQ     ph_miss_kind
        LDAA    2
ph_miss_kind:
        STAA    [PH_REJECT]
        LDX     ph_sfx_buzz
        JSR     jr_sfx_play
        LDAA    18
        JSR     jr_port_animate
        CLR     [PH_REJECT]
        JMP     ph_settle
ph_fuse:
        ; both cards step toward their middle, become 10 and burst
        LDAA    [PH_FIRST]
        JSR     ph_card_xy
        STAA    [PH_AX]
        STAB    [PH_AY]
        LDAA    [PH_CURSOR]
        JSR     ph_card_xy
        STAA    [PH_BX]
        STAB    [PH_BY]
        ADDA    [PH_AX]
        LSRA
        STAA    [PH_CX]
        LDAA    [PH_BY]
        ADDA    [PH_AY]
        LSRA
        STAA    [PH_CY]
        LDAA    [PH_AX]
        LDAB    [PH_CX]
        JSR     ph_toward
        STAA    [PH_AX]
        LDAA    [PH_AY]
        LDAB    [PH_CY]
        JSR     ph_toward
        STAA    [PH_AY]
        LDAA    [PH_BX]
        LDAB    [PH_CX]
        JSR     ph_toward
        STAA    [PH_BX]
        LDAA    [PH_BY]
        LDAB    [PH_CY]
        JSR     ph_toward
        STAA    [PH_BY]
        LDAA    1
        STAA    [PH_MERGING]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        LDAA    2
        STAA    [PH_MERGING]
        LDAA    1
        JSR     jr_port_sound
        LDAA    9
        JSR     jr_port_animate
        LDAA    3
        STAA    [PH_MERGING]
ph_fuse_phase:
        LDAA    4
        JSR     jr_port_animate
        INC     [PH_MERGING]
        LDAA    [PH_MERGING]
        CMPA    7
        BNE     ph_fuse_phase
        LDAA    [PH_FIRST]
        JSR     ph_slot
        CLR     [X]
        LDAA    [PH_CURSOR]
        JSR     ph_slot
        CLR     [X]
        DEC     [PH_LEFT]
        DEC     [PH_LEFT]
        CLR     [PH_MERGING]
ph_settle:
        LDAA    0xff
        STAA    [PH_FIRST]
        LDX     PH_C
ph_settle_clear:
        CLR     [X]
        INX
        CPX     PH_C + 16
        BNE     ph_settle_clear
        TST     [PH_LEFT]
        BNE     ph_settle_misses
        JMP     jr_port_win
ph_settle_misses:
        LDAA    [PH_ERRORS]
        CMPA    6
        BCS     ph_settle_done
        LDX     0
        JMP     jr_port_lose
ph_settle_done:
        RTS

; A = cell -> A = 2 + cell % 4 * 4, B = 4 + cell // 4 * 4.
ph_card_xy:
        TAB
        ANDB    0x0c
        ADDB    4
        ANDA    3
        ASLA
        ASLA
        ADDA    2
        RTS

; ---------------------------------------------------------------- drawing

; PH_DX, PH_DY = top-left, PH_DV = number, PH_DCH = chosen, PH_DHI = hint:
; a 3x3 card on its pair's colour with a tall numeral in the middle.
ph_card:
        LDX     ph_pair_colour
        LDAA    [PH_DV]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [PH_DBG]
        ORAA    0x07
        STAA    [JR_RT_COLOR]
        CLR     [PH_T]
ph_card_row:
        LDAA    [PH_DX]
        LDAB    [PH_DY]
        ADDB    [PH_T]
        JSR     jr_gfx_at
        LDAB    3
ph_card_col:
        PSHB
        LDAA    0x20
        JSR     jr_gfx_putc
        PULB
        DECB
        BNE     ph_card_col
        INC     [PH_T]
        LDAA    [PH_T]
        CMPA    3
        BNE     ph_card_row
        TST     [PH_DCH]
        BEQ     ph_card_hint
        LDAA    [PH_DX]
        INCA
        LDAB    [PH_DY]
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
ph_card_hint:
        TST     [PH_DHI]
        BEQ     ph_card_digit
        LDAA    [PH_DX]
        LDAB    [PH_DY]
        JSR     ph_star
        LDAA    [PH_DX]
        ADDA    2
        LDAB    [PH_DY]
        JSR     ph_star
        LDAA    [PH_DX]
        LDAB    [PH_DY]
        ADDB    2
        JSR     ph_star
        LDAA    [PH_DX]
        ADDA    2
        LDAB    [PH_DY]
        ADDB    2
        JSR     ph_star
ph_card_digit:
        LDAA    [PH_DBG]
        ORAA    0x40
        STAA    [JR_RT_COLOR]
        LDAA    [PH_DX]
        INCA
        LDAB    [PH_DY]
        INCB
        JMP     ph_numeral

; A = x, B = y: '*' in the current colour.
ph_star:
        JSR     jr_gfx_at
        LDAA    0x2a
        JMP     jr_gfx_putc

; A = x, B = y, PH_DV = digit: the tall numeral (two glyphs), current colour.
ph_numeral:
        STAA    [PH_N]
        STAB    [PH_K]
        JSR     jr_gfx_at
        LDAA    [PH_DV]
        ASLA
        JSR     jr_gfx_putc
        LDAA    [PH_N]
        LDAB    [PH_K]
        INCB
        JSR     jr_gfx_at
        LDAA    [PH_DV]
        ASLA
        INCA
        JMP     jr_gfx_putc

; A = x, B = y, digit in PH_DV: a white tall numeral.
ph_big:
        PSHA
        LDAA    PH_ATTR_BIG
        STAA    [JR_RT_COLOR]
        PULA
        JMP     ph_numeral

game_draw:
        LDAA    0x20
        LDAB    PH_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ph_hud
        JSR     jr_gfx_lines
        LDAA    PH_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the cards (the fusing pair is drawn by the fusion)
        CLR     [PH_DI]
ph_draw_card:
        LDAA    [PH_DI]
        JSR     ph_slot
        LDAA    [X]
        BEQ     ph_draw_next
        STAA    [PH_DV]
        LDAA    [X + 16]
        STAA    [PH_DHI]
        TST     [PH_MERGING]
        BEQ     ph_draw_this
        CLR     [PH_DHI]
        LDAA    [PH_DI]
        CMPA    [PH_FIRST]
        BEQ     ph_draw_next
        CMPA    [PH_CURSOR]
        BEQ     ph_draw_next
ph_draw_this:
        CLR     [PH_DCH]
        LDAA    [PH_DI]
        CMPA    [PH_FIRST]
        BNE     ph_draw_place
        INC     [PH_DCH]
ph_draw_place:
        LDAA    [PH_DI]
        JSR     ph_card_xy
        STAA    [PH_DX]
        STAB    [PH_DY]
        JSR     ph_card
ph_draw_next:
        INC     [PH_DI]
        LDAA    [PH_DI]
        CMPA    16
        BNE     ph_draw_card
        ; the fusion: two cards closing in, the 10, and the burst corners
        LDAA    [PH_MERGING]
        CMPA    1
        BNE     ph_draw_ten
        LDAA    1
        STAA    [PH_DCH]
        CLR     [PH_DHI]
        LDAA    [PH_FIRST]
        JSR     ph_slot
        LDAA    [X]
        STAA    [PH_DV]
        LDAA    [PH_AX]
        STAA    [PH_DX]
        LDAA    [PH_AY]
        STAA    [PH_DY]
        JSR     ph_card
        LDAA    [PH_CURSOR]
        JSR     ph_slot
        LDAA    [X]
        STAA    [PH_DV]
        LDAA    [PH_BX]
        STAA    [PH_DX]
        LDAA    [PH_BY]
        STAA    [PH_DY]
        JSR     ph_card
        JMP     ph_draw_panel
ph_draw_ten:
        CMPA    2
        BCC     ph_draw_cursor_near532
        JMP     ph_draw_cursor
ph_draw_cursor_near532:
        CMPA    5
        BCC     ph_draw_burst
        LDAA    PH_ATTR_TEN
        STAA    [JR_RT_COLOR]
        CLR     [PH_T]
ph_draw_ten_row:
        LDAA    [PH_CX]
        LDAB    [PH_CY]
        ADDB    [PH_T]
        JSR     jr_gfx_at
        LDAB    4
ph_draw_ten_col:
        PSHB
        LDAA    0x20
        JSR     jr_gfx_putc
        PULB
        DECB
        BNE     ph_draw_ten_col
        INC     [PH_T]
        LDAA    [PH_T]
        CMPA    3
        BNE     ph_draw_ten_row
        LDAA    PH_ATTR_TEN | 0x40
        STAA    [JR_RT_COLOR]
        LDAA    1
        STAA    [PH_DV]
        LDAA    [PH_CX]
        INCA
        LDAB    [PH_CY]
        INCB
        JSR     ph_numeral
        CLR     [PH_DV]
        LDAA    [PH_CX]
        ADDA    2
        LDAB    [PH_CY]
        INCB
        JSR     ph_numeral
ph_draw_burst:
        LDAA    [PH_MERGING]
        CMPA    3
        BCS     ph_draw_panel
        LDAA    PH_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [PH_CX]
        DECA
        LDAB    [PH_CY]
        DECB
        JSR     ph_star
        LDAA    [PH_CX]
        ADDA    4
        LDAB    [PH_CY]
        DECB
        JSR     ph_star
        LDAA    [PH_CX]
        DECA
        LDAB    [PH_CY]
        ADDB    3
        JSR     ph_star
        LDAA    [PH_CX]
        ADDA    4
        LDAB    [PH_CY]
        ADDB    3
        JSR     ph_star
        BRA     ph_draw_panel
ph_draw_cursor:
        LDAA    PH_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [PH_CURSOR]
        JSR     ph_card_xy
        DECA
        INCB
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
ph_draw_panel:
        ; PAIR: the chosen numbers, or '?'
        LDAA    [PH_FIRST]
        CMPA    0xff
        BEQ     ph_draw_pair_none
        JSR     ph_slot
        LDAA    [X]
        STAA    [PH_DV]
        LDAA    23
        LDAB    10
        JSR     ph_big
        LDAA    [PH_CURSOR]
        CMPA    [PH_FIRST]
        BEQ     ph_draw_pair_second
        JSR     ph_slot
        LDAA    [X]
        BEQ     ph_draw_pair_second
        STAA    [PH_DV]
        LDAA    27
        LDAB    10
        JSR     ph_big
        BRA     ph_draw_counts
ph_draw_pair_none:
        LDAA    PH_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    11
        JSR     jr_gfx_at
        LDAA    0x3f
        JSR     jr_gfx_putc
ph_draw_pair_second:
        LDAA    PH_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    11
        JSR     jr_gfx_at
        LDAA    0x3f
        JSR     jr_gfx_putc
ph_draw_counts:
        LDAA    [PH_LEFT]
        LDAB    10
        JSR     jr_divmod8
        STAB    [PH_DI]
        STAA    [PH_DV]
        LDAA    23
        LDAB    17
        JSR     ph_big
        LDAA    [PH_DI]
        STAA    [PH_DV]
        LDAA    24
        LDAB    17
        JSR     ph_big
        LDAA    [PH_ERRORS]
        STAA    [PH_DV]
        LDAA    28
        LDAB    17
        JSR     ph_big
        ; the gauge: one lamp per cleared pair
        LDAA    16
        SUBA    [PH_LEFT]
        LSRA
        STAA    [PH_T]
        CLR     [PH_DI]
ph_draw_gauge:
        LDAA    PH_ATTR_GOOD
        LDAB    0x23
        TST     [PH_T]
        BNE     ph_draw_lamp
        LDAA    0x01
        LDAB    0x2e
ph_draw_lamp:
        STAA    [JR_RT_COLOR]
        PSHB
        LDAA    [PH_DI]
        ASLA
        ADDA    2
        LDAB    20
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_putc
        TST     [PH_T]
        BEQ     ph_draw_lamp_next
        DEC     [PH_T]
ph_draw_lamp_next:
        INC     [PH_DI]
        LDAA    [PH_DI]
        CMPA    8
        BNE     ph_draw_gauge
        ; the message
        LDX     ph_txt_neighbors
        LDAA    [PH_REJECT]
        CMPA    1
        BEQ     ph_draw_bad
        LDX     ph_txt_sum
        CMPA    2
        BEQ     ph_draw_bad
        TST     [PH_MERGING]
        BEQ     ph_draw_done
        LDAA    PH_ATTR_GOOD
        LDX     ph_txt_fusion
        BRA     ph_draw_message
ph_draw_bad:
        LDAA    PH_ATTR_BAD
ph_draw_message:
        STAA    [JR_RT_COLOR]
        STX     [JR_RT_TABLE]
        LDAA    2
        LDAB    21
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JMP     jr_gfx_text
ph_draw_done:
        RTS

game_draw_title:
        LDX     ph_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    PH_ATTR_TEXT
        JSR     jr_gfx_fill
        CLR     [PH_DCH]
        CLR     [PH_DHI]
        LDX     ph_title_cards
        STX     [JR_RT_TABLE]
ph_title_card:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     ph_title_text
        STAA    [PH_DX]
        LDAA    [X + 1]
        STAA    [PH_DY]
        LDAA    [X + 2]
        STAA    [PH_DV]
        JSR     ph_card
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     ph_title_card
ph_title_text:
        LDX     ph_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    PH_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ph_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

ph_levels:
        .db     6, 4, 6, 4, 6, 4, 1, 3, 1, 3, 9, 7, 9, 7, 8, 2
        .db     8, 3, 7, 5, 2, 4, 6, 5, 7, 6, 4, 7, 3, 4, 6, 3
        .db     9, 1, 9, 3, 5, 5, 1, 7, 6, 7, 5, 5, 4, 3, 3, 7
        .db     8, 2, 6, 4, 5, 5, 2, 6, 6, 4, 8, 4, 4, 6, 5, 5
        .db     1, 9, 4, 6, 8, 2, 2, 8, 3, 9, 5, 5, 7, 1, 9, 1
        .db     6, 4, 8, 2, 9, 1, 2, 8, 6, 9, 9, 1, 4, 1, 3, 7
        .db     6, 6, 6, 7, 4, 4, 4, 3, 5, 5, 1, 4, 5, 5, 9, 6
        .db     2, 8, 9, 1, 6, 5, 5, 9, 4, 6, 4, 1, 4, 6, 9, 1
        .db     2, 8, 7, 3, 8, 2, 6, 4, 8, 2, 3, 7, 2, 8, 3, 7
        .db     3, 9, 1, 2, 7, 6, 4, 8, 2, 4, 6, 9, 8, 5, 5, 1
; card grounds by number: pairs that make ten share a colour
; (1/9 red, 2/8 yellow, 3/7 green, 4/6 cyan, 5 magenta)
ph_pair_colour:
        .db     0x00, 0x10, 0x30, 0x20, 0x28, 0x18, 0x28, 0x20, 0x30, 0x10

; x, y, number
ph_title_cards:
        .db     7, 3, 3
        .db     11, 3, 7
        .db     17, 3, 4
        .db     21, 3, 6
        .db     0xff

ph_hud:
        .db     1, 0, PH_ATTR_TITLE
        .dw     ph_txt_name
        .db     23, 0, PH_ATTR_LABEL
        .dw     ph_txt_round
        .db     22, 5, PH_ATTR_LABEL
        .dw     ph_txt_make
        .db     22, 8, PH_ATTR_LABEL
        .dw     ph_txt_pair
        .db     25, 11, PH_ATTR_DIM
        .dw     ph_txt_plus
        .db     22, 15, PH_ATTR_LABEL
        .dw     ph_txt_left
        .db     27, 15, PH_ATTR_LABEL
        .dw     ph_txt_miss
        .db     0xff
ph_title_lines:
        .db     10, 8, PH_ATTR_TITLE
        .dw     ph_txt_name
        .db     3, 10, PH_ATTR_LABEL
        .dw     ph_txt_tagline
        .db     8, 15, PH_ATTR_TEXT
        .dw     ph_txt_start
        .db     5, 17, PH_ATTR_TEXT
        .dw     ph_txt_howto
        .db     4, 22, PH_ATTR_DIM
        .dw     ph_txt_credit
        .db     0xff
ph_help_lines:
        .db     10, 2, PH_ATTR_TITLE
        .dw     ph_txt_name
        .db     1, 5, PH_ATTR_TEXT
        .dw     ph_help_1
        .db     1, 7, PH_ATTR_TEXT
        .dw     ph_help_2
        .db     1, 9, PH_ATTR_TEXT
        .dw     ph_help_3
        .db     1, 11, PH_ATTR_TEXT
        .dw     ph_help_4
        .db     1, 13, PH_ATTR_TEXT
        .dw     ph_help_5
        .db     1, 15, PH_ATTR_TEXT
        .dw     ph_help_6
        .db     1, 17, PH_ATTR_TEXT
        .dw     ph_help_7
        .db     1, 21, PH_ATTR_LABEL
        .dw     ph_help_back
        .db     0xff

ph_txt_name:
        .db     "PHASE PAIRS", 0
ph_txt_round:
        .db     "ROUND", 0
ph_txt_make:
        .db     "MAKE 10", 0
ph_txt_pair:
        .db     "PAIR", 0
ph_txt_plus:
        .db     "+", 0
ph_txt_left:
        .db     "LEFT", 0
ph_txt_miss:
        .db     "MISS", 0
ph_txt_neighbors:
        .db     "NEIGHBORS ONLY", 0
ph_txt_sum:
        .db     "SUM MUST BE 10", 0
ph_txt_fusion:
        .db     "PHASE FUSION!", 0
ph_txt_tagline:
        .db     "NEIGHBORS THAT MAKE TEN", 0
ph_txt_start:
        .db     "RETURN : START", 0
ph_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
ph_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
ph_help_1:
        .db     "WASD : CHOOSE A NUMBER", 0
ph_help_2:
        .db     "RETURN : SELECT TWO NEIGHBORS", 0
ph_help_3:
        .db     "THEIR SUM MUST BE TEN.", 0
ph_help_4:
        .db     "REMOVE ALL SIXTEEN NUMBERS.", 0
ph_help_5:
        .db     "SIX WRONG PAIRS END A ROUND.", 0
ph_help_6:
        .db     "SAME COLOUR = PAIR TO TEN.", 0
ph_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
ph_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     ph_sfx_pick, ph_sfx_fuse, ph_jingle_win, ph_jingle_lose
ph_sfx_pick:
        .db     100, 2, 0, 0
ph_sfx_fuse:
        .db     80, 3, 60, 3, 45, 3, 34, 6, 0, 0
ph_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a bright electronic tune in B flat major, eighth note = 8 frames, looping.
ph_title_song:
        .db     1
        .dw     ph_title_melody, ph_title_harmony, ph_title_bass
ph_title_melody:
        .db     AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_AS5, 8, AU_A5, 16, AU_F5, 16
        .db     AU_G5, 8, AU_F5, 8, AU_DS5, 8, AU_D5, 8, AU_C5, 32
        .db     AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_AS5, 8, AU_C6, 16, AU_A5, 16
        .db     AU_AS5, 8, AU_A5, 8, AU_G5, 8, AU_F5, 8, AU_AS5, 32, 0, 0
ph_title_harmony:
        .db     AU_F4, 32, AU_F5, 32, AU_DS5, 32, AU_A4, 32
        .db     AU_F4, 32, AU_F5, 32, AU_DS5, 32, AU_D5, 32, 0, 0
ph_title_bass:
        .db     AU_AS2, 16, AU_F2, 16, AU_F2, 16, AU_C3, 16
        .db     AU_DS2, 16, AU_AS2, 16, AU_F2, 16, AU_F3, 16
        .db     AU_AS2, 16, AU_F2, 16, AU_F2, 16, AU_F3, 16
        .db     AU_DS2, 16, AU_F2, 16, AU_AS2, 32, 0, 0

; Board cleared: B flat major arpeggio over the tonic (54 frames).
ph_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     ph_win_melody, ph_win_harmony, ph_win_bass
ph_win_melody:
        .db     AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_AS5, 30, 0, 0
ph_win_harmony:
        .db     AU_F4, 8, AU_AS4, 8, AU_D5, 8, AU_F5, 30, 0, 0
ph_win_bass:
        .db     AU_AS2, 24, AU_AS3, 30, 0, 0
ph_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     ph_lose_melody, ph_lose_harmony, ph_lose_bass
ph_lose_melody:
        .db     AU_F5, 12, AU_DS5, 12, AU_CS5, 12, AU_C5, 30, 0, 0
ph_lose_harmony:
        .db     AU_CS5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
ph_lose_bass:
        .db     AU_AS2, 36, AU_F2, 30, 0, 0

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

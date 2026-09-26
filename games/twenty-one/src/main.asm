; SPDX-License-Identifier: MIT
; TWENTY ONE for JR-200: a port of jr100dev games/twenty_one/rules.py 2.0.0.
; The seeded 52-card shuffle, dealing, totals with aces, the dealer drawing to
; 17, doubles, naturals and the seven-hand goal follow the upstream source;
; display, colour and three-voice sound use the JR-200 port SDK. Upstream's
; entropy() (the JR-100 timer) is replaced by the position of the title song
; when the table opens.
        .filename.jr "TWENTY-ONE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
TO_LOG:             .equ    0x4760      ; count, then each sampled origin
TO_LOG_MAX:         .equ    31
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[12], c[12], d[52].
TO_ORIGIN:          .equ    GAME_STATE
TO_SEED:            .equ    GAME_STATE + 1
TO_COINS:           .equ    GAME_STATE + 2
TO_DRAWN:           .equ    GAME_STATE + 3
TO_NP:              .equ    GAME_STATE + 4
TO_ND:              .equ    GAME_STATE + 5
TO_PLAYER:          .equ    GAME_STATE + 6
TO_DEALER:          .equ    GAME_STATE + 7
TO_RESULT:          .equ    GAME_STATE + 8
TO_CHOICE:          .equ    GAME_STATE + 9
TO_REVEAL:          .equ    GAME_STATE + 10
TO_WAGER:           .equ    GAME_STATE + 11
TO_GAIN:            .equ    GAME_STATE + 12
TO_ROUND:           .equ    GAME_STATE + 13
TO_READY:           .equ    GAME_STATE + 14
TO_B:               .equ    GAME_STATE + 15
TO_C:               .equ    GAME_STATE + 27
TO_D:               .equ    GAME_STATE + 39
; Rule and flight work bytes.
TO_I:               .equ    GAME_STATE + 96
TO_J:               .equ    GAME_STATE + 97
TO_V:               .equ    GAME_STATE + 98
TO_ACES:            .equ    GAME_STATE + 99
TO_CNT:             .equ    GAME_STATE + 100
TO_K:               .equ    GAME_STATE + 101
TO_PTR:             .equ    GAME_STATE + 102    ; 2 bytes
TO_WHO:             .equ    GAME_STATE + 104
TO_VALUE:           .equ    GAME_STATE + 105
TO_NAT:             .equ    GAME_STATE + 106
TO_DNAT:            .equ    GAME_STATE + 107
TO_EFFECT:          .equ    GAME_STATE + 108
TO_EX:              .equ    GAME_STATE + 109
TO_EY:              .equ    GAME_STATE + 110
TO_FX:              .equ    GAME_STATE + 111
TO_FY:              .equ    GAME_STATE + 112
TO_TX:              .equ    GAME_STATE + 113
TO_TY:              .equ    GAME_STATE + 114
TO_FRAME:           .equ    GAME_STATE + 115
TO_IA:              .equ    GAME_STATE + 116
TO_SI:              .equ    GAME_STATE + 117
; Drawing work bytes.
TO_DI:              .equ    GAME_STATE + 128
TO_DX:              .equ    GAME_STATE + 129
TO_DY:              .equ    GAME_STATE + 130
TO_DV:              .equ    GAME_STATE + 131
TO_DS:              .equ    GAME_STATE + 132
TO_DR:              .equ    GAME_STATE + 133
TO_DC:              .equ    GAME_STATE + 134

TO_TILE_SUIT:       .equ    0x80        ; + suit: spade, heart, diamond, club
TO_TILE_BACK:       .equ    0x84
TO_ATTR_CARD:       .equ    0x38        ; black on a white card
TO_ATTR_CARD_RED:   .equ    0x3a
TO_ATTR_SUIT:       .equ    0x78
TO_ATTR_SUIT_RED:   .equ    0x7a
TO_ATTR_BACK:       .equ    0x4f        ; white checks on blue
TO_ATTR_TEXT:       .equ    0x07
TO_ATTR_LABEL:      .equ    0x04
TO_ATTR_TITLE:      .equ    0x06
TO_ATTR_DIM:        .equ    0x05
TO_ATTR_PICK:       .equ    0x06
TO_ATTR_GOOD:       .equ    0x04
TO_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        CLR     [TO_LOG]
        JSR     jr_font_install
        LDX     to_patterns
        LDAA    TO_TILE_SUIT
        LDAB    5
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; origin = entropy(): (voice 0 offset * 8 + frames left) of the song playing
; when the table opens; the deck is shuffled from it.
game_init:
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        STAA    [TO_ORIGIN]
        JSR     jr_music_stop
        LDAB    [TO_LOG]
        CMPB    TO_LOG_MAX
        BCC     to_init_table
        INC     [TO_LOG]
        LDX     TO_LOG + 1
        LDAA    [TO_LOG]
        DECA
        JSR     jr_add_x_a
        LDAA    [TO_ORIGIN]
        STAA    [X]
to_init_table:
        LDAA    [TO_ORIGIN]
        STAA    [TO_SEED]
        LDAA    10
        STAA    [TO_COINS]
        JSR     to_shuffle
        JSR     to_hand
        LDAA    1
        STAA    [TO_READY]
        RTS

; d = 0..51, then 51 swaps driven by seed = seed * 109 + 89.
to_shuffle:
        CLR     [TO_I]
to_shuffle_fill:
        LDAA    [TO_I]
        LDX     TO_D
        JSR     jr_add_x_a
        LDAA    [TO_I]
        STAA    [X]
        INC     [TO_I]
        LDAA    [TO_I]
        CMPA    52
        BNE     to_shuffle_fill
        CLR     [TO_I]
to_shuffle_swap:
        LDAA    [TO_SEED]
        LDAB    109
        JSR     jr_mul8
        ADDA    89
        STAA    [TO_SEED]
        LDAB    52
        SUBB    [TO_I]
        JSR     jr_divmod8
        STAB    [TO_J]
        ; swap d[51 - i] and d[j]
        LDAA    51
        SUBA    [TO_I]
        LDX     TO_D
        JSR     jr_add_x_a
        LDAB    [X]
        STX     [TO_PTR]
        LDAA    [TO_J]
        LDX     TO_D
        JSR     jr_add_x_a
        LDAA    [X]
        STAB    [X]
        LDX     [TO_PTR]
        STAA    [X]
        INC     [TO_I]
        LDAA    [TO_I]
        CMPA    51
        BNE     to_shuffle_swap
        CLR     [TO_DRAWN]
        RTS

; A = count of cards, X = their array -> A = total, aces counting 11 when safe.
to_total:
        STAA    [TO_CNT]
        STX     [TO_PTR]
        CLR     [TO_V]
        CLR     [TO_ACES]
        CLR     [TO_K]
to_total_card:
        LDAA    [TO_K]
        CMPA    [TO_CNT]
        BCC     to_total_aces
        LDX     [TO_PTR]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    13
        JSR     jr_divmod8
        INCB
        CMPB    1
        BNE     to_total_face
        INC     [TO_ACES]
to_total_face:
        CMPB    10
        BLS     to_total_add
        LDAB    10
to_total_add:
        ADDB    [TO_V]
        STAB    [TO_V]
        INC     [TO_K]
        BRA     to_total_card
to_total_aces:
        LDAA    [TO_V]
        TST     [TO_ACES]
        BEQ     to_total_done
        CMPA    11
        BHI     to_total_done
        ADDA    10
to_total_done:
        RTS

; A = who (0 you, 1 dealer): the next card flies to its place.
to_deal:
        STAA    [TO_WHO]
        LDAA    [TO_DRAWN]
        CMPA    52
        BNE     to_deal_take
        JSR     to_shuffle
to_deal_take:
        LDAA    [TO_DRAWN]
        LDX     TO_D
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TO_VALUE]
        INC     [TO_DRAWN]
        TST     [TO_READY]
        BEQ     to_deal_store
        CLRA
        JSR     jr_port_sound
        LDAA    14
        STAA    [TO_FX]
        LDAA    18
        STAA    [TO_FY]
        JSR     to_deal_count
        JSR     to_card_xy
        STAA    [TO_TX]
        STAB    [TO_TY]
        JSR     to_flight
to_deal_store:
        JSR     to_deal_count
        PSHA
        LDX     TO_B
        TST     [TO_WHO]
        BEQ     to_deal_hand
        LDX     TO_C
to_deal_hand:
        JSR     jr_add_x_a
        LDAA    [TO_VALUE]
        STAA    [X]
        PULA
        INCA
        TST     [TO_WHO]
        BNE     to_deal_dealer
        STAA    [TO_NP]
        LDX     TO_B
        JSR     to_total
        STAA    [TO_PLAYER]
        BRA     to_deal_wait
to_deal_dealer:
        STAA    [TO_ND]
        LDX     TO_C
        JSR     to_total
        STAA    [TO_DEALER]
to_deal_wait:
        TST     [TO_READY]
        BEQ     to_deal_done
        LDAA    8
        JMP     jr_port_animate
to_deal_done:
        RTS

; -> A = cards in the hand being dealt, B = who.
to_deal_count:
        LDAB    [TO_WHO]
        LDAA    [TO_NP]
        TSTB
        BEQ     to_deal_count_done
        LDAA    [TO_ND]
to_deal_count_done:
        RTS

; A = card index, B = who -> A = x (who * 17 + index % 3 * 5), B = y (4 + index // 3 * 3).
to_card_xy:
        STAB    [TO_IA]
        LDAB    3
        JSR     jr_divmod8
        ; A = row, B = column
        PSHB
        TAB
        ASLB
        ABA
        ADDA    4
        PULB
        PSHA
        TBA
        ASLA
        ASLA
        ABA
        TST     [TO_IA]
        BEQ     to_card_xy_done
        ADDA    17
to_card_xy_done:
        PULB
        RTS

to_hand:
        CLR     [TO_NP]
        CLR     [TO_ND]
        CLR     [TO_PLAYER]
        CLR     [TO_DEALER]
        CLR     [TO_RESULT]
        CLR     [TO_CHOICE]
        CLR     [TO_REVEAL]
        LDAA    2
        STAA    [TO_WAGER]
        CLRA
        JSR     to_deal
        LDAA    1
        JSR     to_deal
        CLRA
        JSR     to_deal
        LDAA    1
        JMP     to_deal

; Settle the hand: win (3 for a natural), bust, dealer win or push.
to_finish:
        LDAA    1
        STAA    [TO_REVEAL]
        CLR     [TO_NAT]
        LDAA    [TO_PLAYER]
        CMPA    21
        BNE     to_finish_dealer_nat
        LDAA    [TO_NP]
        CMPA    2
        BNE     to_finish_dealer_nat
        INC     [TO_NAT]
to_finish_dealer_nat:
        CLR     [TO_DNAT]
        LDAA    [TO_DEALER]
        CMPA    21
        BNE     to_finish_judge
        LDAA    [TO_ND]
        CMPA    2
        BNE     to_finish_judge
        INC     [TO_DNAT]
to_finish_judge:
        LDAA    [TO_PLAYER]
        CMPA    21
        BHI     to_finish_not_win
        LDAB    [TO_DEALER]
        CMPB    21
        BHI     to_finish_win
        CMPA    [TO_DEALER]
        BHI     to_finish_win
        TST     [TO_NAT]
        BEQ     to_finish_not_win
        TST     [TO_DNAT]
        BNE     to_finish_not_win
to_finish_win:
        LDAA    [TO_WAGER]
        TST     [TO_NAT]
        BEQ     to_finish_gain
        LDAA    3
to_finish_gain:
        STAA    [TO_GAIN]
        ADDA    [TO_COINS]
        STAA    [TO_COINS]
        LDAA    1
        STAA    [TO_RESULT]
        LDAA    1
        JSR     jr_port_sound
        BRA     to_finish_wait
to_finish_not_win:
        LDAA    [TO_PLAYER]
        CMPA    21
        BHI     to_finish_lost
        CMPA    [TO_DEALER]
        BCS     to_finish_lost
        TST     [TO_DNAT]
        BEQ     to_finish_push
        TST     [TO_NAT]
        BNE     to_finish_push
to_finish_lost:
        LDAA    [TO_COINS]
        SUBA    [TO_WAGER]
        STAA    [TO_COINS]
        LDAB    3
        LDAA    [TO_PLAYER]
        CMPA    21
        BLS     to_finish_result
        LDAB    2
to_finish_result:
        STAB    [TO_RESULT]
        LDX     to_sfx_buzz
        JSR     jr_sfx_play
        BRA     to_finish_wait
to_finish_push:
        LDAA    4
        STAA    [TO_RESULT]
        CLRA
        JSR     jr_port_sound
to_finish_wait:
        LDAA    42
        JSR     jr_port_animate
        INC     [TO_ROUND]
        LDAA    [TO_COINS]
        CMPA    2
        BCC     to_finish_round
        LDX     to_txt_no_coins
        JMP     jr_port_lose
to_finish_round:
        LDAA    [TO_ROUND]
        CMPA    7
        BEQ     to_finish_end
        JMP     to_hand
to_finish_end:
        LDAA    [TO_COINS]
        CMPA    12
        BCS     to_finish_below
        JMP     jr_port_win
to_finish_below:
        LDX     to_txt_below
        JMP     jr_port_lose

to_stand:
        LDAA    1
        STAA    [TO_REVEAL]
        LDAA    3
        STAA    [TO_CHOICE]
        LDAA    12
        JSR     jr_port_animate
        LDAA    9
        STAA    [TO_SI]
to_stand_draw:
        LDAA    [TO_DEALER]
        CMPA    17
        BCC     to_stand_next
        LDAA    1
        JSR     to_deal
to_stand_next:
        DEC     [TO_SI]
        BNE     to_stand_draw
        JMP     to_finish

game_raw_key:
game_tick:
        RTS

game_act:
        TSTA
        BEQ     to_act_done
        CMPA    JR_KEY_CONFIRM
        BEQ     to_confirm
        BCC     to_act_done
        ; W and A step back, S and D forward, through three choices
        LDAB    1
        CMPA    JR_KEY_UP
        BEQ     to_act_back
        CMPA    JR_KEY_LEFT
        BNE     to_act_move
to_act_back:
        LDAB    2
to_act_move:
        ADDB    [TO_CHOICE]
        CMPB    3
        BCS     to_act_store
        SUBB    3
to_act_store:
        STAB    [TO_CHOICE]
to_act_done:
        RTS

to_confirm:
        LDAA    [TO_CHOICE]
        BNE     to_confirm_stand
        CLRA
        JSR     to_deal
        JMP     to_check_bust
to_confirm_stand:
        CMPA    1
        BNE     to_confirm_double
        JMP     to_stand
to_confirm_double:
        LDAA    [TO_NP]
        CMPA    2
        BNE     to_confirm_refuse
        LDAA    [TO_COINS]
        CMPA    4
        BCS     to_confirm_refuse
        LDAA    4
        STAA    [TO_WAGER]
        CLRA
        JSR     to_deal
        LDAA    [TO_PLAYER]
        CMPA    21
        BLS     to_confirm_stand_after
        JMP     to_finish
to_confirm_stand_after:
        JMP     to_stand
to_confirm_refuse:
        LDX     to_sfx_buzz
        JMP     jr_sfx_play
to_check_bust:
        LDAA    [TO_PLAYER]
        CMPA    21
        BLS     to_act_done
        JMP     to_finish

; five frames of animate(3) from (FX, FY) to (TX, TY).
to_flight:
        LDAA    1
        STAA    [TO_EFFECT]
        CLR     [TO_FRAME]
to_flight_frame:
        LDAA    [TO_FX]
        LDAB    [TO_TX]
        JSR     to_interp
        STAA    [TO_EX]
        LDAA    [TO_FY]
        LDAB    [TO_TY]
        JSR     to_interp
        STAA    [TO_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [TO_FRAME]
        LDAA    [TO_FRAME]
        CMPA    5
        BNE     to_flight_frame
        CLR     [TO_EFFECT]
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
to_interp:
        STAA    [TO_IA]
        CBA
        BHI     to_interp_back
        SUBB    [TO_IA]
        TBA
        LDAB    [TO_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [TO_IA]
        RTS
to_interp_back:
        SBA
        LDAB    [TO_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [TO_IA]
        RTS

; ---------------------------------------------------------------- drawing

; TO_DX, TO_DY = top-left, TO_DV = card, TO_DS = face up: a 4x3 card.
to_draw_card:
        LDAA    TO_ATTR_BACK
        LDAB    TO_TILE_BACK
        TST     [TO_DS]
        BEQ     to_draw_card_fill
        LDAA    TO_ATTR_CARD
        LDAB    0x20
to_draw_card_fill:
        STAA    [JR_RT_COLOR]
        STAB    [TO_DC]
        CLR     [TO_DR]
to_draw_card_row:
        LDAA    [TO_DX]
        LDAB    [TO_DY]
        ADDB    [TO_DR]
        JSR     jr_gfx_at
        LDAA    [TO_DC]
        JSR     jr_gfx_putc
        LDAA    [TO_DC]
        JSR     jr_gfx_putc
        LDAA    [TO_DC]
        JSR     jr_gfx_putc
        LDAA    [TO_DC]
        JSR     jr_gfx_putc
        INC     [TO_DR]
        LDAA    [TO_DR]
        CMPA    3
        BNE     to_draw_card_row
        TST     [TO_DS]
        BEQ     to_draw_card_done
        ; rank (A, 2-10, J, Q, K) and suit; hearts and diamonds in red
        LDAA    [TO_DV]
        LDAB    13
        JSR     jr_divmod8
        STAA    [TO_DC]
        INCB
        STAB    [TO_DR]
        LDAB    TO_ATTR_CARD
        DECA
        CMPA    2
        BCC     to_draw_card_colour
        LDAB    TO_ATTR_CARD_RED
to_draw_card_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [TO_DX]
        INCA
        LDAB    [TO_DY]
        INCB
        JSR     jr_gfx_at
        LDAA    [TO_DR]
        CMPA    10
        BNE     to_draw_card_letter
        JSR     jr_gfx_dec2
        BRA     to_draw_card_suit
to_draw_card_letter:
        LDX     to_rank_letters - 1
        JSR     jr_add_x_a
        LDAB    [X]
        PSHB
        LDAA    0x20
        JSR     jr_gfx_putc
        PULA
        JSR     jr_gfx_putc
to_draw_card_suit:
        LDAB    TO_ATTR_SUIT
        LDAA    [TO_DC]
        DECA
        CMPA    2
        BCC     to_draw_card_suit_colour
        LDAB    TO_ATTR_SUIT_RED
to_draw_card_suit_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [TO_DC]
        ADDA    TO_TILE_SUIT
        JMP     jr_gfx_putc
to_draw_card_done:
        RTS

game_draw:
        LDAA    0x20
        LDAB    TO_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     to_hud
        JSR     jr_gfx_lines
        ; your cards face up; the dealer's second on is hidden until the reveal
        CLR     [TO_DI]
to_draw_player:
        LDAA    [TO_DI]
        CMPA    [TO_NP]
        BCC     to_draw_dealer_start
        CLRB
        JSR     to_card_xy
        STAA    [TO_DX]
        STAB    [TO_DY]
        LDAA    [TO_DI]
        LDX     TO_B
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TO_DV]
        LDAA    1
        STAA    [TO_DS]
        JSR     to_draw_card
        INC     [TO_DI]
        BRA     to_draw_player
to_draw_dealer_start:
        CLR     [TO_DI]
to_draw_dealer:
        LDAA    [TO_DI]
        CMPA    [TO_ND]
        BCC     to_draw_flight
        LDAB    1
        JSR     to_card_xy
        STAA    [TO_DX]
        STAB    [TO_DY]
        LDAA    [TO_DI]
        LDX     TO_C
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [TO_DV]
        LDAA    [TO_REVEAL]
        TST     [TO_DI]
        BNE     to_draw_dealer_face
        LDAA    1
to_draw_dealer_face:
        STAA    [TO_DS]
        JSR     to_draw_card
        INC     [TO_DI]
        BRA     to_draw_dealer
to_draw_flight:
        TST     [TO_EFFECT]
        BEQ     to_draw_totals
        LDAA    [TO_EX]
        STAA    [TO_DX]
        LDAA    [TO_EY]
        STAA    [TO_DY]
        CLR     [TO_DS]
        JSR     to_draw_card
to_draw_totals:
        LDAA    TO_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    6
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [TO_PLAYER]
        JSR     jr_gfx_dec2
        LDAA    25
        LDAB    16
        JSR     jr_gfx_at
        TST     [TO_REVEAL]
        BEQ     to_draw_hidden
        LDAA    [TO_DEALER]
        JSR     jr_gfx_dec2
        BRA     to_draw_coins
to_draw_hidden:
        LDX     to_txt_hidden
        JSR     jr_gfx_text
to_draw_coins:
        ; coins: green at the goal of 12, red when a double is out of reach
        LDAA    TO_ATTR_TEXT
        LDAB    [TO_COINS]
        CMPB    12
        BCS     to_draw_coins_low
        LDAA    TO_ATTR_GOOD
to_draw_coins_low:
        CMPB    4
        BCC     to_draw_coins_put
        LDAA    TO_ATTR_BAD
to_draw_coins_put:
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [TO_COINS]
        JSR     jr_gfx_dec2
        LDAA    TO_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [TO_ROUND]
        CMPA    6
        BCS     to_draw_round
        LDAA    6
to_draw_round:
        ADDA    0x31
        JSR     jr_gfx_putc
        ; the result, the dealer drawing, or the three choices
        LDAA    [TO_RESULT]
        BNE     to_draw_result
        LDAA    [TO_CHOICE]
        CMPA    3
        BNE     to_draw_choices
        LDAA    5
to_draw_result:
        STAA    [TO_DC]
        LDX     to_result_attr - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [TO_DC]
        DECA
        ASLA
        LDX     to_result_text
        JSR     jr_add_x_a
        LDX     [X]
        STX     [JR_RT_TABLE]
        LDAA    6
        LDAB    20
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        LDAA    [TO_DC]
        CMPA    1
        BNE     to_draw_result_wager
        LDAA    [TO_GAIN]
        BRA     to_draw_result_amount
to_draw_result_wager:
        CMPA    4
        BCC     to_draw_done
        LDAA    [TO_WAGER]
to_draw_result_amount:
        ADDA    0x30
        JMP     jr_gfx_putc
to_draw_choices:
        CLR     [TO_DI]
to_draw_choice:
        LDAB    TO_ATTR_TEXT
        LDAA    [TO_DI]
        CMPA    [TO_CHOICE]
        BNE     to_draw_choice_colour
        LDAB    TO_ATTR_PICK
to_draw_choice_colour:
        STAB    [JR_RT_COLOR]
        LDAB    9
        JSR     jr_mul8
        ADDA    2
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [TO_DI]
        ASLA
        LDX     to_choice_text
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        INC     [TO_DI]
        LDAA    [TO_DI]
        CMPA    3
        BNE     to_draw_choice
        LDAA    TO_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [TO_CHOICE]
        LDAB    9
        JSR     jr_mul8
        INCA
        LDAB    20
        JSR     jr_gfx_at
        LDAA    0x3e
        JMP     jr_gfx_putc
to_draw_done:
        RTS

game_draw_title:
        LDX     to_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    TO_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     to_title_cards
        STX     [JR_RT_TABLE]
to_title_card:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     to_title_text
        STAA    [TO_DX]
        LDAA    [X + 1]
        STAA    [TO_DY]
        LDAA    [X + 2]
        STAA    [TO_DV]
        LDAA    [X + 3]
        STAA    [TO_DS]
        JSR     to_draw_card
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     to_title_card
to_title_text:
        LDX     to_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    TO_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     to_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

to_rank_letters:
        .db     "A23456789", 0x30, "JQK"
to_choice_text:
        .dw     to_txt_hit, to_txt_stand, to_txt_double
to_result_text:
        .dw     to_txt_win, to_txt_bust, to_txt_dealer_wins, to_txt_push, to_txt_draws
to_result_attr:
        .db     TO_ATTR_GOOD, TO_ATTR_BAD, TO_ATTR_BAD, 0x05, TO_ATTR_PICK

; x, y, card, face up
to_title_cards:
        .db     8, 3, 0, 1
        .db     13, 3, 25, 1
        .db     18, 3, 0, 0
        .db     0xff

to_hud:
        .db     1, 0, TO_ATTR_TITLE
        .dw     to_txt_name
        .db     2, 2, TO_ATTR_LABEL
        .dw     to_txt_player
        .db     21, 2, TO_ATTR_LABEL
        .dw     to_txt_dealer
        .db     0, 16, TO_ATTR_LABEL
        .dw     to_txt_total
        .db     19, 16, TO_ATTR_LABEL
        .dw     to_txt_total
        .db     0, 18, TO_ATTR_LABEL
        .dw     to_txt_coins
        .db     22, 18, TO_ATTR_LABEL
        .dw     to_txt_hand
        .db     0xff
to_title_lines:
        .db     11, 8, TO_ATTR_TITLE
        .dw     to_txt_name
        .db     4, 10, TO_ATTR_LABEL
        .dw     to_txt_tagline
        .db     8, 15, TO_ATTR_TEXT
        .dw     to_txt_start
        .db     5, 17, TO_ATTR_TEXT
        .dw     to_txt_howto
        .db     4, 22, TO_ATTR_DIM
        .dw     to_txt_credit
        .db     0xff
to_help_lines:
        .db     11, 2, TO_ATTR_TITLE
        .dw     to_txt_name
        .db     1, 4, TO_ATTR_TEXT
        .dw     to_help_1
        .db     1, 6, TO_ATTR_TEXT
        .dw     to_help_2
        .db     1, 8, TO_ATTR_TEXT
        .dw     to_help_3
        .db     1, 10, TO_ATTR_TEXT
        .dw     to_help_4
        .db     1, 12, TO_ATTR_TEXT
        .dw     to_help_5
        .db     1, 14, TO_ATTR_TEXT
        .dw     to_help_6
        .db     1, 16, TO_ATTR_TEXT
        .dw     to_help_7
        .db     1, 18, TO_ATTR_TEXT
        .dw     to_help_8
        .db     1, 20, TO_ATTR_TEXT
        .dw     to_help_9
        .db     1, 22, TO_ATTR_LABEL
        .dw     to_help_back
        .db     0xff

to_txt_name:
        .db     "TWENTY ONE", 0
to_txt_player:
        .db     "PLAYER", 0
to_txt_dealer:
        .db     "DEALER", 0
to_txt_total:
        .db     "TOTAL", 0
to_txt_coins:
        .db     "COINS", 0
to_txt_hand:
        .db     "HAND  /7", 0
to_txt_hidden:
        .db     "??", 0
to_txt_hit:
        .db     "HIT", 0
to_txt_stand:
        .db     "STAND", 0
to_txt_double:
        .db     "DOUBLE", 0
to_txt_win:
        .db     "YOU WIN! +", 0
to_txt_bust:
        .db     "BUST! -", 0
to_txt_dealer_wins:
        .db     "DEALER WINS -", 0
to_txt_push:
        .db     "PUSH - COINS STAY", 0
to_txt_draws:
        .db     "DEALER DRAWS TO 17", 0
to_txt_no_coins:
        .db     "NO COINS LEFT AT THE TABLE", 0
to_txt_below:
        .db     "SEVEN HANDS ENDED BELOW 12", 0
to_txt_tagline:
        .db     "SEVEN HANDS, TWELVE COINS", 0
to_txt_start:
        .db     "RETURN : START", 0
to_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
to_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
to_help_1:
        .db     "A/D : HIT / STAND / DOUBLE", 0
to_help_2:
        .db     "RETURN : CONFIRM THE CHOICE", 0
to_help_3:
        .db     "ACE IS 1 OR 11 / FACES ARE 10.", 0
to_help_4:
        .db     "DEALER KEEPS ONE CARD HIDDEN.", 0
to_help_5:
        .db     "DOUBLE: BET 4, DRAW ONE, STAND.", 0
to_help_6:
        .db     "NATURAL 21 PAYS THREE COINS.", 0
to_help_7:
        .db     "FINISH SEVEN HANDS WITH 12.", 0
to_help_8:
        .db     "A SHUFFLED 52-CARD DECK.", 0
to_help_9:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
to_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     to_sfx_deal, to_sfx_win, to_jingle_win, to_jingle_lose
to_sfx_deal:
        .db     70, 2, 0, 1, 60, 2, 0, 0
to_sfx_win:
        .db     60, 4, 48, 4, 40, 8, 0, 0
to_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a lounge swing in G minor, eighth note = 8 frames, looping.
to_title_song:
        .db     1
        .dw     to_title_melody, to_title_harmony, to_title_bass
to_title_melody:
        .db     AU_D5, 12, AU_G5, 4, AU_AS5, 16, AU_A5, 12, AU_G5, 4, AU_F5, 16
        .db     AU_G5, 12, AU_DS5, 4, AU_D5, 16, AU_C5, 16, AU_D5, 16
        .db     AU_D5, 12, AU_G5, 4, AU_AS5, 16, AU_C6, 12, AU_AS5, 4, AU_A5, 16
        .db     AU_G5, 16, AU_FS5, 16, AU_G5, 32, 0, 0
to_title_harmony:
        .db     AU_AS4, 32, AU_C5, 32, AU_AS4, 32, AU_A4, 32
        .db     AU_AS4, 32, AU_DS5, 32, AU_D5, 32, AU_AS4, 32, 0, 0
to_title_bass:
        .db     AU_G2, 16, AU_D3, 16, AU_F2, 16, AU_C3, 16
        .db     AU_DS2, 16, AU_AS2, 16, AU_D2, 16, AU_A2, 16
        .db     AU_G2, 16, AU_D3, 16, AU_C3, 16, AU_A2, 16
        .db     AU_D3, 16, AU_D2, 16, AU_G2, 32, 0, 0

; Twelve coins: G major arpeggio over the tonic (54 frames).
to_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     to_win_melody, to_win_harmony, to_win_bass
to_win_melody:
        .db     AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_G6, 30, 0, 0
to_win_harmony:
        .db     AU_D5, 8, AU_G5, 8, AU_B5, 8, AU_D6, 30, 0, 0
to_win_bass:
        .db     AU_G3, 24, AU_G2, 30, 0, 0
to_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     to_lose_melody, to_lose_harmony, to_lose_bass
to_lose_melody:
        .db     AU_D5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
to_lose_harmony:
        .db     AU_AS4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
to_lose_bass:
        .db     AU_G3, 36, AU_D3, 30, 0, 0

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

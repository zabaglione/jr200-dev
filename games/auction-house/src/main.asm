; SPDX-License-Identifier: MIT
; AUCTION HOUSE for JR-200: a port of jr100dev games/auction_house/rules.py 3.0.0.
; The lot table, market seed, rival pressure, inspection and goals follow the
; upstream source; display, colour and three-voice sound use the JR-200 port
; SDK. Upstream's entropy() (the JR-100 timer) is replaced by the position of
; the title song when a market starts.
        .filename.jr "AUCTION-HOUSE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
AH_LOG:             .equ    0x4720      ; count, then each sampled origin
AH_LOG_MAX:         .equ    31
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
AH_ORIGIN:          .equ    GAME_STATE
AH_SEED:            .equ    GAME_STATE + 1
AH_MARKET:          .equ    GAME_STATE + 2
AH_VALUE:           .equ    GAME_STATE + 3
AH_LOW:             .equ    GAME_STATE + 4
AH_HIGH:            .equ    GAME_STATE + 5
AH_LIMIT:           .equ    GAME_STATE + 6
AH_BID:             .equ    GAME_STATE + 7
AH_CHOICE:          .equ    GAME_STATE + 8
AH_INSPECTED:       .equ    GAME_STATE + 9
AH_PHASE:           .equ    GAME_STATE + 10
AH_CASH:            .equ    GAME_STATE + 11
AH_GOAL:            .equ    GAME_STATE + 12
AH_ROUND:           .equ    GAME_STATE + 13
AH_WON:             .equ    GAME_STATE + 14
AH_HAMMER:          .equ    GAME_STATE + 15
; Rule and drawing work bytes.
AH_STEP:            .equ    GAME_STATE + 32
AH_DI:              .equ    GAME_STATE + 33

AH_PHASE_BID:       .equ    1
AH_PHASE_RIVAL:     .equ    2
AH_PHASE_SOLD:      .equ    3
AH_PHASE_PASSED:    .equ    4
AH_PHASE_NOCASH:    .equ    5
AH_PHASE_APPRAISED: .equ    6

AH_TILE_GAVEL:      .equ    0x80
AH_TILE_VASE:       .equ    0x84
AH_TILE_COINS:      .equ    0x88
AH_ATTR_GAVEL:      .equ    0x47
AH_ATTR_VASE:       .equ    0x45        ; cyan lot
AH_ATTR_COINS:      .equ    0x46        ; yellow coins
AH_ATTR_TEXT:       .equ    0x07
AH_ATTR_LABEL:      .equ    0x04
AH_ATTR_TITLE:      .equ    0x06
AH_ATTR_DIM:        .equ    0x05
AH_ATTR_TABLE:      .equ    0x02
AH_ATTR_PICK:       .equ    0x06
AH_ATTR_GOOD:       .equ    0x04
AH_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        CLR     [AH_LOG]
        JSR     jr_font_install
        LDX     ah_patterns
        LDAA    AH_TILE_GAVEL
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; origin = entropy(): (voice 0 offset * 8 + frames left) of the song playing
; when the market starts. seed = origin ^ (level * 37).
game_init:
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        STAA    [AH_ORIGIN]
        JSR     jr_music_stop
        LDAB    [AH_LOG]
        CMPB    AH_LOG_MAX
        BCC     ah_init_seed
        INC     [AH_LOG]
        LDX     AH_LOG + 1
        LDAA    [AH_LOG]
        DECA
        JSR     jr_add_x_a
        LDAA    [AH_ORIGIN]
        STAA    [X]
ah_init_seed:
        LDAA    [JR_PORT_LEVEL]
        LDAB    37
        JSR     jr_mul8
        EORA    [AH_ORIGIN]
        STAA    [AH_SEED]
        LDAA    40
        STAA    [AH_CASH]
        ; goal = 58 + level * 2 - level // 2
        LDAA    [JR_PORT_LEVEL]
        LSRA
        NEGA
        ADDA    58
        ADDA    [JR_PORT_LEVEL]
        ADDA    [JR_PORT_LEVEL]
        STAA    [AH_GOAL]
; The next lot: seed = seed * 109 + 89, market = seed % 3.
ah_lot:
        LDAA    [AH_SEED]
        LDAB    109
        JSR     jr_mul8
        ADDA    89
        STAA    [AH_SEED]
        LDAB    3
        JSR     jr_divmod8
        STAB    [AH_MARKET]
        LDAA    [AH_ROUND]
        LDAB    5
        JSR     jr_mul8
        LDX     ah_lots
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    [AH_MARKET]
        STAA    [AH_VALUE]
        LDAA    [X + 1]
        STAA    [AH_LOW]
        LDAA    [X + 2]
        ADDA    2
        STAA    [AH_HIGH]
        LDAA    [X + 3]
        ADDA    [JR_PORT_LEVEL]
        STAA    [AH_LIMIT]
        LDAA    [X + 4]
        STAA    [AH_BID]
        CLR     [AH_CHOICE]
        CLR     [AH_INSPECTED]
        CLR     [AH_PHASE]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     ah_confirm
        BCC     ah_act_done
        TSTA
        BEQ     ah_act_done
        ; W and A step back, S and D forward, through four choices
        LDAB    1
        CMPA    JR_KEY_UP
        BEQ     ah_act_back
        CMPA    JR_KEY_LEFT
        BNE     ah_act_move
ah_act_back:
        LDAB    3
ah_act_move:
        ADDB    [AH_CHOICE]
        ANDB    3
        STAB    [AH_CHOICE]
ah_act_done:
        RTS

ah_confirm:
        LDAA    [AH_CHOICE]
        CMPA    2
        BNE     ah_confirm_pass
        ; inspect: one coin reveals the exact value
        TST     [AH_INSPECTED]
        BNE     ah_act_done
        LDAA    [AH_CASH]
        CMPA    2
        BCS     ah_act_done
        DEC     [AH_CASH]
        LDAA    1
        STAA    [AH_INSPECTED]
        LDAA    AH_PHASE_APPRAISED
        STAA    [AH_PHASE]
        CLRA
        JSR     jr_port_sound
        LDAA    18
        JSR     jr_port_animate
        LDAA    [AH_VALUE]
        STAA    [AH_LOW]
        STAA    [AH_HIGH]
        LDAA    1
        JMP     jr_port_sound
ah_confirm_pass:
        CMPA    3
        BNE     ah_confirm_bid
        LDAA    AH_PHASE_PASSED
        STAA    [AH_PHASE]
        CLRA
        JSR     jr_port_sound
        JMP     ah_settle
ah_confirm_bid:
        LDAB    2
        TSTA
        BEQ     ah_bid_step
        LDAB    6
ah_bid_step:
        STAB    [AH_STEP]
        LDAA    [AH_BID]
        ADDA    [AH_STEP]
        CMPA    [AH_CASH]
        BHI     ah_no_cash
        STAA    [AH_BID]
        LDAA    AH_PHASE_BID
        STAA    [AH_PHASE]
        CLRA
        JSR     jr_port_sound
        LDAA    16
        JSR     jr_port_animate
        ; sold when bid >= limit - (4 for a jump bid)
        LDAA    [AH_LIMIT]
        TST     [AH_CHOICE]
        BEQ     ah_bid_limit
        SUBA    4
ah_bid_limit:
        LDAB    [AH_BID]
        CBA
        BLS     ah_sold
        LDAA    AH_PHASE_RIVAL
        STAA    [AH_PHASE]
        LDAA    [AH_BID]
        ADDA    2
        STAA    [AH_BID]
        LDX     ah_sfx_rival
        JSR     jr_sfx_play
        LDAA    20
        JMP     jr_port_animate
ah_no_cash:
        LDAA    AH_PHASE_NOCASH
        STAA    [AH_PHASE]
        LDX     ah_sfx_buzz
        JMP     jr_sfx_play

ah_sold:
        LDAA    AH_PHASE_SOLD
        STAA    [AH_PHASE]
        LDAA    1
        JSR     jr_port_sound
        CLR     [AH_HAMMER]
ah_sold_frame:
        LDAA    5
        JSR     jr_port_animate
        LDAA    [AH_HAMMER]
        CMPA    2
        BEQ     ah_sold_pay
        INC     [AH_HAMMER]
        BRA     ah_sold_frame
ah_sold_pay:
        ; cash = min(99, cash - bid + value)
        LDAA    [AH_CASH]
        SUBA    [AH_BID]
        ADDA    [AH_VALUE]
        CMPA    99
        BLS     ah_sold_cash
        LDAA    99
ah_sold_cash:
        STAA    [AH_CASH]
        INC     [AH_WON]

ah_settle:
        LDAA    36
        JSR     jr_port_animate
        INC     [AH_ROUND]
        LDAA    [AH_ROUND]
        CMPA    6
        BEQ     ah_settle_end
        JMP     ah_lot
ah_settle_end:
        LDAA    [AH_CASH]
        CMPA    [AH_GOAL]
        BCS     ah_settle_lose
        JMP     jr_port_win
ah_settle_lose:
        LDX     ah_txt_lose
        JMP     jr_port_lose

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    AH_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ah_hud
        JSR     jr_gfx_lines
        LDAA    AH_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the auction table: gavel, the lot and the bidders' coins
        LDAA    AH_ATTR_TABLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    10
        JSR     jr_gfx_at
        LDX     ah_txt_table
        JSR     jr_gfx_text
        LDAA    AH_ATTR_VASE
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    8
        JSR     jr_gfx_at
        LDAA    AH_TILE_VASE
        JSR     jr_gfx_tile
        LDAA    AH_ATTR_COINS
        STAA    [JR_RT_COLOR]
        LDAA    12
        LDAB    8
        JSR     jr_gfx_at
        LDAA    AH_TILE_COINS
        JSR     jr_gfx_tile
        ; the gavel falls in three steps while a lot is sold
        LDAB    4
        LDAA    [AH_PHASE]
        CMPA    AH_PHASE_SOLD
        BNE     ah_draw_gavel
        LDAB    [AH_HAMMER]
        ASLB
        ADDB    4
ah_draw_gavel:
        LDAA    AH_ATTR_GAVEL
        STAA    [JR_RT_COLOR]
        LDAA    3
        JSR     jr_gfx_at
        LDAA    AH_TILE_GAVEL
        JSR     jr_gfx_tile
        ; appraisal: green once inspected
        LDAA    AH_ATTR_TEXT
        TST     [AH_INSPECTED]
        BEQ     ah_draw_appraisal
        LDAA    AH_ATTR_GOOD
ah_draw_appraisal:
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [AH_LOW]
        JSR     jr_gfx_dec2
        LDAA    0x2d
        JSR     jr_gfx_putc
        LDAA    [AH_HIGH]
        JSR     jr_gfx_dec2
        LDAA    AH_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [AH_BID]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [AH_WON]
        JSR     jr_gfx_dec2
        LDAA    5
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [AH_ROUND]
        CMPA    6
        BCS     ah_draw_lot
        LDAA    5
ah_draw_lot:
        ADDA    0x31
        JSR     jr_gfx_putc
        LDAA    22
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [AH_GOAL]
        JSR     jr_gfx_dec2
        ; cash: green once it reaches the goal
        LDAA    AH_ATTR_TEXT
        LDAB    [AH_CASH]
        CMPB    [AH_GOAL]
        BCS     ah_draw_cash
        LDAA    AH_ATTR_GOOD
ah_draw_cash:
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [AH_CASH]
        JSR     jr_gfx_dec2
        ; the four choices, the selected one in yellow with a '^' below
        CLR     [AH_DI]
ah_draw_choice:
        LDAB    AH_ATTR_TEXT
        LDAA    [AH_DI]
        CMPA    [AH_CHOICE]
        BNE     ah_draw_choice_colour
        LDAB    AH_ATTR_PICK
ah_draw_choice_colour:
        STAB    [JR_RT_COLOR]
        ASLA
        ASLA
        ASLA
        INCA
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [AH_DI]
        ASLA
        LDX     ah_choice_text
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        INC     [AH_DI]
        LDAA    [AH_DI]
        CMPA    4
        BNE     ah_draw_choice
        LDAA    AH_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [AH_CHOICE]
        ASLA
        ASLA
        ASLA
        INCA
        LDAB    20
        JSR     jr_gfx_at
        LDAA    0x5e
        JSR     jr_gfx_putc
        ; what just happened at the table
        LDAA    [AH_PHASE]
        BEQ     ah_draw_done
        DECA
        LDX     ah_phase_colours
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    15
        JSR     jr_gfx_at
        LDAA    [AH_PHASE]
        DECA
        ASLA
        LDX     ah_phase_text
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [AH_PHASE]
        CMPA    AH_PHASE_SOLD
        BNE     ah_draw_done
        LDAA    13
        LDAB    15
        JSR     jr_gfx_at
        LDAA    [AH_VALUE]
        JMP     jr_gfx_dec2
ah_draw_done:
        RTS

game_draw_title:
        LDX     ah_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    AH_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    AH_ATTR_GAVEL
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    3
        JSR     jr_gfx_at
        LDAA    AH_TILE_GAVEL
        JSR     jr_gfx_tile
        LDAA    AH_ATTR_VASE
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    3
        JSR     jr_gfx_at
        LDAA    AH_TILE_VASE
        JSR     jr_gfx_tile
        LDAA    AH_ATTR_COINS
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    3
        JSR     jr_gfx_at
        LDAA    AH_TILE_COINS
        JSR     jr_gfx_tile
        LDX     ah_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    AH_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ah_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

ah_lots:
        .db     24, 22, 26, 14, 4, 18, 16, 22, 26, 8, 30, 26, 32, 22, 6
        .db     16, 14, 20, 22, 4, 28, 24, 30, 18, 6, 20, 18, 24, 22, 8

ah_choice_text:
        .dw     ah_txt_bid2, ah_txt_bid6, ah_txt_inspect, ah_txt_pass
ah_phase_text:
        .dw     ah_txt_your_bid, ah_txt_rival, ah_txt_sold, ah_txt_passed
        .dw     ah_txt_no_cash, ah_txt_appraised
ah_phase_colours:
        .db     0x07, 0x02, 0x06, 0x05, 0x02, 0x04

ah_hud:
        .db     1, 0, AH_ATTR_TITLE
        .dw     ah_txt_name
        .db     22, 0, AH_ATTR_LABEL
        .dw     ah_txt_market
        .db     18, 3, AH_ATTR_LABEL
        .dw     ah_txt_appraisal
        .db     18, 9, AH_ATTR_LABEL
        .dw     ah_txt_bid
        .db     18, 13, AH_ATTR_LABEL
        .dw     ah_txt_cash
        .db     18, 17, AH_ATTR_LABEL
        .dw     ah_txt_won
        .db     1, 22, AH_ATTR_LABEL
        .dw     ah_txt_lot
        .db     0xff
ah_title_lines:
        .db     9, 8, AH_ATTR_TITLE
        .dw     ah_txt_name
        .db     4, 10, AH_ATTR_LABEL
        .dw     ah_txt_tagline
        .db     8, 15, AH_ATTR_TEXT
        .dw     ah_txt_start
        .db     5, 17, AH_ATTR_TEXT
        .dw     ah_txt_howto
        .db     4, 22, AH_ATTR_DIM
        .dw     ah_txt_credit
        .db     0xff
ah_help_lines:
        .db     9, 2, AH_ATTR_TITLE
        .dw     ah_txt_name
        .db     1, 5, AH_ATTR_TEXT
        .dw     ah_help_1
        .db     1, 7, AH_ATTR_TEXT
        .dw     ah_help_2
        .db     1, 9, AH_ATTR_TEXT
        .dw     ah_help_3
        .db     1, 11, AH_ATTR_TEXT
        .dw     ah_help_4
        .db     1, 13, AH_ATTR_TEXT
        .dw     ah_help_5
        .db     1, 15, AH_ATTR_TEXT
        .dw     ah_help_6
        .db     1, 17, AH_ATTR_TEXT
        .dw     ah_help_7
        .db     1, 19, AH_ATTR_TEXT
        .dw     ah_help_8
        .db     1, 21, AH_ATTR_LABEL
        .dw     ah_help_back
        .db     0xff

ah_txt_name:
        .db     "AUCTION HOUSE", 0
ah_txt_market:
        .db     "MARKET", 0
ah_txt_appraisal:
        .db     "APPRAISAL", 0
ah_txt_bid:
        .db     "BID", 0
ah_txt_cash:
        .db     "CASH", 0
ah_txt_won:
        .db     "WON", 0
ah_txt_lot:
        .db     "LOT  /6    CASH GOAL", 0
ah_txt_table:
        .db     "===============", 0
ah_txt_bid2:
        .db     "BID +2", 0
ah_txt_bid6:
        .db     "BID +6", 0
ah_txt_inspect:
        .db     "INSPECT", 0
ah_txt_pass:
        .db     "PASS", 0
ah_txt_your_bid:
        .db     "YOUR BID", 0
ah_txt_rival:
        .db     "RIVAL +2", 0
ah_txt_sold:
        .db     "SOLD! VALUE", 0
ah_txt_passed:
        .db     "LOT PASSED", 0
ah_txt_no_cash:
        .db     "NO CASH", 0
ah_txt_appraised:
        .db     "APPRAISED", 0
ah_txt_lose:
        .db     "THE AUCTION ENDED BELOW TARGET", 0
ah_txt_tagline:
        .db     "SIX LOTS / THREE MARKETS", 0
ah_txt_start:
        .db     "RETURN : START", 0
ah_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
ah_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
ah_help_1:
        .db     "A/D : CHOICE  RETURN : CONFIRM", 0
ah_help_2:
        .db     "BID +2 OR JUMP BID +6.", 0
ah_help_3:
        .db     "JUMP BIDS PRESSURE THE RIVAL.", 0
ah_help_4:
        .db     "INSPECT COSTS ONE COIN.", 0
ah_help_5:
        .db     "INSPECTION REVEALS EXACT VALUE.", 0
ah_help_6:
        .db     "PASS BEFORE YOU OVERPAY.", 0
ah_help_7:
        .db     "VALUES CHANGE EACH AUCTION.", 0
ah_help_8:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
ah_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     ah_sfx_tap, ah_sfx_hammer, ah_jingle_win, ah_jingle_lose
ah_sfx_tap:
        .db     120, 2, 0, 1, 120, 2, 0, 0
ah_sfx_hammer:
        .db     200, 2, 0, 2, 200, 2, 0, 2, 160, 5, 0, 0
ah_sfx_rival:
        .db     90, 3, 0, 1, 80, 4, 0, 0
ah_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a bright ragtime figure in F major, eighth note = 10 frames, looping.
ah_title_song:
        .db     1
        .dw     ah_title_melody, ah_title_harmony, ah_title_bass
ah_title_melody:
        .db     AU_A5, 10, AU_C6, 10, AU_A5, 10, AU_F5, 10, AU_G5, 20, AU_E5, 20
        .db     AU_F5, 10, AU_A5, 10, AU_G5, 10, AU_E5, 10, AU_D5, 20, AU_C5, 20
        .db     AU_A5, 10, AU_C6, 10, AU_D6, 10, AU_C6, 10, AU_AS5, 20, AU_G5, 20
        .db     AU_A5, 10, AU_G5, 10, AU_E5, 10, AU_G5, 10, AU_F5, 40, 0, 0
ah_title_harmony:
        .db     AU_F5, 40, AU_E5, 40, AU_C5, 40, AU_AS4, 40
        .db     AU_F5, 40, AU_E5, 40, AU_C5, 40, AU_A4, 40, 0, 0
ah_title_bass:
        .db     AU_F3, 20, AU_C3, 20, AU_C3, 20, AU_G2, 20
        .db     AU_F3, 20, AU_C3, 20, AU_AS2, 20, AU_C3, 20
        .db     AU_F3, 20, AU_C3, 20, AU_AS2, 20, AU_G2, 20
        .db     AU_C3, 20, AU_C3, 20, AU_F2, 40, 0, 0

; Sold out: three gavel knocks rising to an F major chord (54 frames).
ah_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     ah_win_melody, ah_win_harmony, ah_win_bass
ah_win_melody:
        .db     AU_C6, 6, 0, 2, AU_C6, 6, 0, 2, AU_C6, 8, AU_F6, 30, 0, 0
ah_win_harmony:
        .db     AU_A5, 6, 0, 2, AU_A5, 6, 0, 2, AU_AS5, 8, AU_C6, 30, 0, 0
ah_win_bass:
        .db     AU_F3, 24, AU_F2, 30, 0, 0
ah_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     ah_lose_melody, ah_lose_harmony, ah_lose_bass
ah_lose_melody:
        .db     AU_C5, 12, AU_AS4, 12, AU_GS4, 12, AU_G4, 30, 0, 0
ah_lose_harmony:
        .db     AU_GS4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
ah_lose_bass:
        .db     AU_F3, 36, AU_C3, 30, 0, 0

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

; SPDX-License-Identifier: MIT
; PRISM TRACE for JR-200: a port of jr100dev games/prism_trace/rules.py 1.6.1.
; The mirror layout, the beam trace with its loop guard and the receiver
; follow the upstream source; display, colour and three-voice sound use the
; JR-200 port SDK (the beam is drawn with its own tiles instead of upstream's
; src/optics.asm character stamps).
        .filename.jr "PRISM-TRACE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[49], c[49], d[49].
PT_CURSOR:          .equ    GAME_STATE
PT_TURNS:           .equ    GAME_STATE + 1
PT_B:               .equ    GAME_STATE + 2
PT_C:               .equ    GAME_STATE + 51
PT_D:               .equ    GAME_STATE + 100
; Trace work bytes.
PT_P:               .equ    GAME_STATE + 160
PT_DIR:             .equ    GAME_STATE + 161
PT_IN:              .equ    GAME_STATE + 162
PT_STEP:            .equ    GAME_STATE + 163
PT_T:               .equ    GAME_STATE + 164
; Drawing work bytes.
PT_DI:              .equ    GAME_STATE + 170
PT_DCODE:           .equ    GAME_STATE + 171

PT_START:           .equ    21
PT_RECEIVER:        .equ    6
PT_TILE_EMPTY:      .equ    0x80
PT_TILE_BEAM_H:     .equ    0x84
PT_TILE_BEAM_V:     .equ    0x88
PT_TILE_BEAM_X:     .equ    0x8c
PT_TILE_SLASH:      .equ    0x90        ; + 4 for '\'
PT_TILE_RECEIVER:   .equ    0x98
PT_TILE_EMITTER:    .equ    0x9c
PT_ATTR_EMPTY:      .equ    0x41
PT_ATTR_BEAM:       .equ    0x46        ; yellow light
PT_ATTR_MIRROR:     .equ    0x47
PT_ATTR_MIRROR_LIT: .equ    0x70        ; black glass on a lit yellow ground
PT_ATTR_RECEIVER:   .equ    0x45
PT_ATTR_RECEIVED:   .equ    0x66        ; yellow on green
PT_ATTR_EMITTER:    .equ    0x42
PT_ATTR_TEXT:       .equ    0x07
PT_ATTR_LABEL:      .equ    0x04
PT_ATTR_TITLE:      .equ    0x06
PT_ATTR_DIM:        .equ    0x05
PT_ATTR_PICK:       .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     pt_patterns
        LDAA    PT_TILE_EMPTY
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    1
        STAA    [PT_B + 23]
        STAA    [PT_B + 37]
        STAA    [PT_B + 12]
        LDAA    2
        STAA    [PT_B + 40]
        STAA    [PT_B + 8]
        STAA    [PT_B + 1]
        JMP     pt_trace

; A = cell -> X = b[cell].
pt_slot:
        LDX     PT_B
        JMP     jr_add_x_a

; Follow the beam from the left edge; mirrors turn it, the receiver wins.
pt_trace:
        LDX     PT_C
pt_trace_clear:
        CLR     [X]
        INX
        CPX     PT_D + 49
        BNE     pt_trace_clear
        LDAA    PT_START
        STAA    [PT_P]
        LDAA    4
        STAA    [PT_DIR]
        LDAA    64
        STAA    [PT_STEP]
pt_trace_step:
        LDAA    [PT_DIR]
        LDX     pt_incoming - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [PT_IN]
        ; the same entry twice is a loop
        LDAA    [PT_P]
        JSR     pt_slot
        LDAA    [X + 98]
        BITA    [PT_IN]
        BEQ     pt_trace_enter
        RTS
pt_trace_enter:
        ORAA    [PT_IN]
        STAA    [X + 98]
        LDAA    [PT_P]
        CMPA    PT_RECEIVER
        BNE     pt_trace_turn
        LDAA    [PT_IN]
        STAA    [X + 49]
        TST     [PT_TURNS]
        BEQ     pt_trace_win
        LDAA    4
        JSR     jr_port_animate
pt_trace_win:
        JMP     jr_port_win
pt_trace_turn:
        LDAA    [X]
        BEQ     pt_trace_mark
        LDX     pt_slash - 1
        CMPA    1
        BEQ     pt_trace_mirror
        LDX     pt_backslash - 1
pt_trace_mirror:
        LDAA    [PT_DIR]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [PT_DIR]
pt_trace_mark:
        LDAA    [PT_DIR]
        LDX     pt_side - 1
        JSR     jr_add_x_a
        LDAB    [X]
        ORAB    [PT_IN]
        LDAA    [PT_P]
        JSR     pt_slot
        ORAB    [X + 49]
        STAB    [X + 49]
        TST     [PT_TURNS]
        BEQ     pt_trace_move
        TST     [X]
        BEQ     pt_trace_straight
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        BRA     pt_trace_move
pt_trace_straight:
        LDAA    1
        JSR     jr_port_animate
pt_trace_move:
        LDAA    [PT_P]
        LDAB    [PT_DIR]
        JSR     pt_move
        CMPA    [PT_P]
        BNE     pt_trace_next
        RTS
pt_trace_next:
        STAA    [PT_P]
        DEC     [PT_STEP]
        BEQ     pt_trace_step_near178
        JMP     pt_trace_step
pt_trace_step_near178:
        RTS

; A = position, B = action 1-4 -> A = moved position (7x7, stops at edges).
pt_move:
        STAA    [PT_T]
        CMPB    JR_KEY_UP
        BNE     pt_move_down
        CMPA    7
        BCS     pt_move_done
        SUBA    7
        RTS
pt_move_down:
        CMPB    JR_KEY_DOWN
        BNE     pt_move_side
        CMPA    42
        BCC     pt_move_done
        ADDA    7
        RTS
pt_move_side:
        PSHB
        LDAB    7
        JSR     jr_divmod8
        PULA
        CMPA    JR_KEY_LEFT
        BNE     pt_move_right
        LDAA    [PT_T]
        TSTB
        BEQ     pt_move_done
        DECA
        RTS
pt_move_right:
        LDAA    [PT_T]
        CMPB    6
        BCC     pt_move_done
        INCA
pt_move_done:
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     pt_act_turn
        BCC     pt_act_done
        TSTA
        BEQ     pt_act_done
        TAB
        LDAA    [PT_CURSOR]
        JSR     pt_move
        STAA    [PT_CURSOR]
pt_act_done:
        RTS
pt_act_turn:
        LDAA    [PT_CURSOR]
        JSR     pt_slot
        LDAA    [X]
        BEQ     pt_act_done
        NEGA
        ADDA    3
        STAA    [X]
        INC     [PT_TURNS]
        LDAA    1
        JSR     jr_port_sound
        JMP     pt_trace

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    PT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pt_hud
        JSR     jr_gfx_lines
        CLR     [PT_DI]
pt_draw_cell:
        LDAA    [PT_DI]
        JSR     pt_slot
        LDAB    [X + 49]
        LDAA    [PT_DI]
        CMPA    PT_RECEIVER
        BNE     pt_draw_mirror
        LDAA    PT_TILE_RECEIVER
        LDAB    PT_ATTR_RECEIVER
        TST     [X + 49]
        BEQ     pt_draw_put
        LDAB    PT_ATTR_RECEIVED
        BRA     pt_draw_put
pt_draw_mirror:
        LDAA    [X]
        BEQ     pt_draw_beam
        DECA
        ASLA
        ASLA
        ADDA    PT_TILE_SLASH
        TSTB
        BEQ     pt_draw_mirror_dark
        LDAB    PT_ATTR_MIRROR_LIT
        BRA     pt_draw_put
pt_draw_mirror_dark:
        LDAB    PT_ATTR_MIRROR
        BRA     pt_draw_put
pt_draw_beam:
        ; across (left + right), down (up + down), or both
        LDAA    PT_TILE_EMPTY
        TSTB
        BEQ     pt_draw_empty
        LDAA    PT_TILE_BEAM_X
        CMPB    15
        BEQ     pt_draw_lit
        LDAA    PT_TILE_BEAM_H
        CMPB    12
        BEQ     pt_draw_lit
        LDAA    PT_TILE_BEAM_V
pt_draw_lit:
        LDAB    PT_ATTR_BEAM
        BRA     pt_draw_put
pt_draw_empty:
        LDAB    PT_ATTR_EMPTY
pt_draw_put:
        STAA    [PT_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [PT_DI]
        LDAB    7
        JSR     jr_divmod8
        ; A = row, B = column
        ASLA
        ADDA    4
        ASLB
        ADDB    2
        PSHA
        TBA
        PULB
        JSR     jr_gfx_at
        LDAA    [PT_DCODE]
        JSR     jr_gfx_tile
        INC     [PT_DI]
        LDAA    [PT_DI]
        CMPA    49
        BNE     pt_draw_cell
        LDAA    PT_ATTR_EMITTER
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    10
        JSR     jr_gfx_at
        LDAA    PT_TILE_EMITTER
        JSR     jr_gfx_tile
        ; the cursor sits outside the board so it never cuts the beam
        LDAA    PT_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [PT_CURSOR]
        LDAB    7
        JSR     jr_divmod8
        STAA    [PT_DI]
        TBA
        ASLA
        ADDA    2
        LDAB    2
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        LDAB    [PT_DI]
        ASLB
        ADDB    4
        LDAA    17
        JSR     jr_gfx_at
        LDAA    0x3c
        JSR     jr_gfx_putc
        LDAA    PT_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [PT_TURNS]
        JMP     jr_gfx_dec2

game_draw_title:
        LDX     pt_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    PT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pt_title_tiles
        STX     [JR_RT_TABLE]
pt_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     pt_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [PT_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [PT_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     pt_title_tile
pt_title_text:
        LDX     pt_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    PT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pt_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; by direction 1-4 (up, down, left, right)
pt_incoming:
        .db     2, 1, 8, 4
pt_side:
        .db     1, 2, 4, 8
pt_slash:
        .db     4, 3, 2, 1
pt_backslash:
        .db     3, 4, 1, 2

; x, attribute, code, y
pt_title_tiles:
        .db     7, PT_ATTR_EMITTER, PT_TILE_EMITTER, 3
        .db     9, PT_ATTR_BEAM, PT_TILE_BEAM_H, 3
        .db     11, PT_ATTR_MIRROR_LIT, PT_TILE_SLASH, 3
        .db     11, PT_ATTR_BEAM, PT_TILE_BEAM_V, 1
        .db     13, PT_ATTR_BEAM, PT_TILE_BEAM_H, 5
        .db     15, PT_ATTR_MIRROR_LIT, PT_TILE_SLASH + 4, 5
        .db     17, PT_ATTR_BEAM, PT_TILE_BEAM_H, 3
        .db     19, PT_ATTR_RECEIVED, PT_TILE_RECEIVER, 3
        .db     0xff

pt_hud:
        .db     1, 0, PT_ATTR_TITLE
        .dw     pt_txt_name
        .db     20, 3, PT_ATTR_LABEL
        .dw     pt_txt_optics
        .db     20, 8, PT_ATTR_LABEL
        .dw     pt_txt_rotations
        .db     0, 9, PT_ATTR_EMITTER & 0x07
        .dw     pt_txt_in
        .db     0xff
pt_title_lines:
        .db     10, 8, PT_ATTR_TITLE
        .dw     pt_txt_name
        .db     3, 10, PT_ATTR_LABEL
        .dw     pt_txt_tagline
        .db     8, 15, PT_ATTR_TEXT
        .dw     pt_txt_start
        .db     5, 17, PT_ATTR_TEXT
        .dw     pt_txt_howto
        .db     4, 22, PT_ATTR_DIM
        .dw     pt_txt_credit
        .db     0xff
pt_help_lines:
        .db     10, 2, PT_ATTR_TITLE
        .dw     pt_txt_name
        .db     1, 5, PT_ATTR_TEXT
        .dw     pt_help_1
        .db     1, 7, PT_ATTR_TEXT
        .dw     pt_help_2
        .db     1, 9, PT_ATTR_TEXT
        .dw     pt_help_3
        .db     1, 11, PT_ATTR_TEXT
        .dw     pt_help_4
        .db     1, 13, PT_ATTR_TEXT
        .dw     pt_help_5
        .db     1, 15, PT_ATTR_TEXT
        .dw     pt_help_6
        .db     1, 21, PT_ATTR_LABEL
        .dw     pt_help_back
        .db     0xff

pt_txt_name:
        .db     "PRISM TRACE", 0
pt_txt_optics:
        .db     "OPTICS", 0
pt_txt_rotations:
        .db     "ROTATIONS", 0
pt_txt_in:
        .db     "IN", 0
pt_txt_tagline:
        .db     "GUIDE THE LIGHT TO THE EYE", 0
pt_txt_start:
        .db     "RETURN : START", 0
pt_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
pt_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
pt_help_1:
        .db     "WASD : SELECT A MIRROR", 0
pt_help_2:
        .db     "RETURN : ROTATE THE MIRROR", 0
pt_help_3:
        .db     "GUIDE THE BEAM FROM THE LEFT", 0
pt_help_4:
        .db     "TO THE TOP RIGHT RECEIVER.", 0
pt_help_5:
        .db     "THE TRACE UPDATES IMMEDIATELY.", 0
pt_help_6:
        .db     "SPACE : RESTORE  CTRL+C : BASIC", 0
pt_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     pt_sfx_bounce, pt_sfx_turn, pt_jingle_win, pt_jingle_lose
pt_sfx_bounce:
        .db     40, 2, 0, 0
pt_sfx_turn:
        .db     150, 2, 120, 2, 0, 0

; Title: a shimmering arpeggio in E major, sixteenth note = 6 frames, looping.
pt_title_song:
        .db     1
        .dw     pt_title_melody, pt_title_harmony, pt_title_bass
pt_title_melody:
        .db     AU_E5, 6, AU_GS5, 6, AU_B5, 6, AU_E6, 6, AU_B5, 6, AU_GS5, 6, AU_E5, 12
        .db     AU_FS5, 6, AU_A5, 6, AU_CS6, 6, AU_FS6, 6, AU_CS6, 6, AU_A5, 6, AU_FS5, 12
        .db     AU_GS5, 6, AU_B5, 6, AU_E6, 6, AU_GS6, 6, AU_E6, 6, AU_B5, 6, AU_GS5, 12
        .db     AU_A5, 6, AU_FS5, 6, AU_DS5, 6, AU_B4, 6, AU_E5, 24, 0, 0
pt_title_harmony:
        .db     AU_B4, 48, AU_CS5, 48, AU_B4, 48, AU_A4, 24, AU_GS4, 24, 0, 0
pt_title_bass:
        .db     AU_E3, 48, AU_FS2, 48, AU_GS2, 48, AU_B2, 24, AU_E2, 24, 0, 0

; Received: E major arpeggio over the tonic (54 frames).
pt_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     pt_win_melody, pt_win_harmony, pt_win_bass
pt_win_melody:
        .db     AU_E5, 8, AU_GS5, 8, AU_B5, 8, AU_E6, 30, 0, 0
pt_win_harmony:
        .db     AU_B4, 8, AU_E5, 8, AU_GS5, 8, AU_B5, 30, 0, 0
pt_win_bass:
        .db     AU_E3, 24, AU_E2, 30, 0, 0
pt_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     pt_lose_melody, pt_lose_harmony, pt_lose_bass
pt_lose_melody:
        .db     AU_B4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
pt_lose_harmony:
        .db     AU_G4, 12, AU_FS4, 12, AU_E4, 12, AU_DS4, 30, 0, 0
pt_lose_bass:
        .db     AU_E3, 36, AU_B2, 30, 0, 0

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

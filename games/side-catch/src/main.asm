; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "SIDE-CATCH"
        .include "../../../sdk/jr200.inc"

JR_SAVE:                .equ    0x3000
JR_RT:                  .equ    0x4000
JR_STACK_TOP:           .equ    0x4fff

GAME_STATUS:            .equ    0x2000
GAME_ROUND:             .equ    0x2001
GAME_WINS:              .equ    0x2002
GAME_RETURN_PROOF:      .equ    0x2003
GAME_LAST_KEY:          .equ    0x2004
GAME_TEXT_SOURCE:       .equ    0x2006
GAME_TEXT_DESTINATION:  .equ    0x2008

GAME_CELL_LEFT:         .equ    0xc28e
GAME_CELL_CENTER:       .equ    0xc28f
GAME_CELL_RIGHT:        .equ    0xc290
GAME_TITLE_CELL:        .equ    0xc14a
GAME_PROMPT_CELL:       .equ    0xc384
GAME_RESULT_CELL:       .equ    0xc344
GAME_PLAYER_ATTR:       .equ    0x44
GAME_TARGET_ATTR:       .equ    0x46

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        CLRA
        STAA    [GAME_STATUS]
        STAA    [GAME_ROUND]
        STAA    [GAME_WINS]
        STAA    [GAME_RETURN_PROOF]
        STAA    [GAME_LAST_KEY]
        LDX     game_player_glyph
        LDAA    0x00
        JSR     jr_pcg_define
        BCS     game_error
        LDX     game_target_glyph
        LDAA    0x01
        JSR     jr_pcg_define
        BCS     game_error
        JSR     game_setup_round

game_loop:
        LDX     128
        JSR     jr_wait_x
        JSR     jr_key_read
        CMPA    [GAME_LAST_KEY]
        BEQ     game_loop
        STAA    [GAME_LAST_KEY]
        CMPA    0x71
        BEQ     game_quit
        LDAB    [GAME_STATUS]
        CMPB    1
        BEQ     game_won_input
        LDAB    [GAME_ROUND]
        CMPB    0
        BEQ     game_expect_right
        CMPA    0x61
        BNE     game_loop
        JSR     game_catch
        BRA     game_loop
game_expect_right:
        CMPA    0x64
        BNE     game_loop
        JSR     game_catch
        BRA     game_loop

game_won_input:
        CMPA    0x72
        BNE     game_loop
        LDAA    [GAME_ROUND]
        EORA    1
        STAA    [GAME_ROUND]
        JSR     game_setup_round
        BRA     game_loop

game_quit:
        LDAA    2
        STAA    [GAME_STATUS]
        JMP     jr_session_leave

game_error:
        LDAA    0xff
        STAA    [GAME_STATUS]
        JMP     jr_session_leave

game_setup_round:
        JSR     jr_screen_clear
        LDX     game_title
        STX     [GAME_TEXT_SOURCE]
        LDX     GAME_TITLE_CELL
        STX     [GAME_TEXT_DESTINATION]
        JSR     game_copy_text
        LDX     GAME_CELL_CENTER
        LDAA    0x00
        LDAB    GAME_PLAYER_ATTR
        JSR     jr_screen_put
        LDAA    [GAME_ROUND]
        BEQ     game_setup_right
        LDX     GAME_CELL_LEFT
        BRA     game_setup_target
game_setup_right:
        LDX     GAME_CELL_RIGHT
game_setup_target:
        LDAA    0x01
        LDAB    GAME_TARGET_ATTR
        JSR     jr_screen_put
        LDAA    [GAME_ROUND]
        BEQ     game_prompt_right
        LDX     game_prompt_left
        BRA     game_prompt_ready
game_prompt_right:
        LDX     game_prompt_right_text
game_prompt_ready:
        STX     [GAME_TEXT_SOURCE]
        LDX     GAME_PROMPT_CELL
        STX     [GAME_TEXT_DESTINATION]
        JSR     game_copy_text
        CLRA
        STAA    [GAME_STATUS]
        RTS

game_catch:
        LDX     GAME_CELL_CENTER
        LDAA    JR200_CHAR_SPACE
        LDAB    JR200_ATTR_STANDARD_WHITE
        JSR     jr_screen_put
        LDAA    [GAME_ROUND]
        BEQ     game_catch_right
        LDX     GAME_CELL_LEFT
        BRA     game_catch_draw
game_catch_right:
        LDX     GAME_CELL_RIGHT
game_catch_draw:
        LDAA    0x00
        LDAB    GAME_PLAYER_ATTR
        JSR     jr_screen_put
        INC     [GAME_WINS]
        LDAA    1
        STAA    [GAME_STATUS]
        LDX     game_result
        STX     [GAME_TEXT_SOURCE]
        LDX     GAME_RESULT_CELL
        STX     [GAME_TEXT_DESTINATION]
        JSR     game_copy_text
        LDAA    213
        JSR     jr_sound_c_start
        BCC     game_sound_started
        JMP     game_error
game_sound_started:
        LDX     1000
        JSR     jr_wait_x
        JSR     jr_sound_c_stop
        RTS

game_copy_text:
        LDX     [GAME_TEXT_SOURCE]
        LDAA    [X]
        BEQ     game_copy_text_done
        INX
        STX     [GAME_TEXT_SOURCE]
        LDX     [GAME_TEXT_DESTINATION]
        STAA    [X]
        INX
        STX     [GAME_TEXT_DESTINATION]
        BRA     game_copy_text
game_copy_text_done:
        RTS

game_title:
        .db     "SIDE CATCH", 0
game_prompt_right_text:
        .db     "D CATCH   Q QUIT", 0
game_prompt_left:
        .db     "A CATCH   Q QUIT", 0
game_result:
        .db     "CAUGHT  R RESTART", 0

        .include "../../../sdk/screen.inc"
        .include "../../../sdk/input.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/timing.inc"
        .include "glyphs.inc"

        .org    0x1300
return_probe:
        LDAA    0xa5
        STAA    [GAME_RETURN_PROOF]
        RTS

        .include "../../../sdk/session.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/font_data.inc"

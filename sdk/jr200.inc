; SPDX-License-Identifier: BSD-3-Clause
; Include once before the other SDK modules.

JR200_USER_RAM_START:       .equ    0x0800
JR200_USER_RAM_END:         .equ    0x7fff

JR200_PCG_BANK0:            .equ    0xc000
JR200_SCREEN_CODES:         .equ    0xc100
JR200_SCREEN_CODES_END:     .equ    0xc400
JR200_PCG_BANK1:            .equ    0xc400
JR200_SCREEN_ATTRIBUTES:    .equ    0xc500
JR200_SCREEN_ATTRIBUTES_END:.equ    0xc800

JR200_KEY_DATA:             .equ    0xc801
JR200_KEY_CONTROL:          .equ    0xc803
JR200_SOUND_C_CONTROL:      .equ    0xc812
JR200_SOUND_C_COUNT:        .equ    0xc813
JR200_SOUND_D_CONTROL:      .equ    0xc814
JR200_SOUND_D_COUNT:        .equ    0xc815
JR200_SOUND_F_CONTROL:      .equ    0xc819
JR200_SOUND_F_COUNT_HIGH:   .equ    0xc81a
JR200_SOUND_F_COUNT_LOW:    .equ    0xc81b
JR200_KEY_IRQ_STATUS:       .equ    0xc81c
JR200_KEY_IRQ_MASK:         .equ    0xc81e
JR200_BORDER:               .equ    0xca00

JR200_SCREEN_WIDTH:         .equ    32
JR200_SCREEN_HEIGHT:        .equ    24
JR200_CHAR_SPACE:           .equ    0x20
JR200_ATTR_STANDARD_WHITE:  .equ    0x07
JR200_ATTR_USER_WHITE:      .equ    0x47
JR200_SOUND_C_ENABLE:       .equ    0x06

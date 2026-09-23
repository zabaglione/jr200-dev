; SPDX-License-Identifier: MIT
        .filename.jr "RELIC-DIVE"
        .include "../../../sdk/jr200.inc"

        .org    0x1000
start:
        JMP     ENTRY

        .include "constants.inc"
        .include "compat.inc"
        .include "../../../sdk/sound.inc"
        .include "platform.asm"
        .include "game.asm"
        .include "map.asm"
        .include "terrain.asm"
        .include "dungeon.asm"
        .include "sight_rays.inc"
        .include "turns.asm"
        .include "items.asm"
        .include "extras.asm"
        .include "ui.asm"
        .include "assets.asm"
        .include "generated.inc"

CODE_END:

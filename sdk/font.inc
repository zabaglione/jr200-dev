; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and session.inc. Installs the SDK's own glyphs for codes
; 0x20-0x5F into character RAM ($D100-$D2FF) so standard-mode text renders the
; same with or without a manufacturer FONT. jr_session_leave restores the
; caller's character RAM. Include font_data.inc once as well.
;
; jr_font_install
;   Clobbers A, B and X.

jr_font_install:
        LDX     jr_font_data
        STX     [JR_RT_SRC]
        LDX     JR_CHARACTER_RAM + 0x100
        STX     [JR_RT_DST]
        LDX     0x0200
        STX     [JR_RT_COUNT]
        JMP     jr_copy

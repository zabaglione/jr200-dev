; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc, session.inc and sound.inc. Non-blocking phrases on
; sound channel C, advanced once per frame by jr_sfx_tick.
; A phrase is a list of (count, frames) byte pairs ending with frames 0.
; count 0 is a rest. Counts are channel C values; pitch is not calibrated.
;
; jr_sfx_play
;   Input: X = phrase. Replaces the current phrase. Clobbers A, B and X.
; jr_sfx_tick
;   Call once per frame. Clobbers A, B and X.
; jr_sfx_stop
;   Silences channel C. Clobbers A.

JR_RT_SFX_PTR:      .equ    JR_RT + 27
JR_RT_SFX_LEFT:     .equ    JR_RT + 29

jr_sfx_play:
        STX     [JR_RT_SFX_PTR]
jr_sfx_note:
        LDX     [JR_RT_SFX_PTR]
        LDAB    [X + 1]
        STAB    [JR_RT_SFX_LEFT]
        BEQ     jr_sfx_stop
        LDAA    [X]
        BNE     jr_sfx_tone
        JMP     jr_sound_c_stop
jr_sfx_tone:
        JMP     jr_sound_c_start

jr_sfx_tick:
        LDAA    [JR_RT_SFX_LEFT]
        BEQ     jr_sfx_tick_done
        DECA
        STAA    [JR_RT_SFX_LEFT]
        BNE     jr_sfx_tick_done
        LDX     [JR_RT_SFX_PTR]
        INX
        INX
        STX     [JR_RT_SFX_PTR]
        BRA     jr_sfx_note
jr_sfx_tick_done:
        RTS

jr_sfx_stop:
        CLR     [JR_RT_SFX_LEFT]
        JMP     jr_sound_c_stop

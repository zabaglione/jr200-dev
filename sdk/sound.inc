; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc.
; The channel C start routine uses prescaler selection zero. Count must be 1-255.
; These routines do not provide a wall-clock or pitch guarantee on hardware.
;
; jr_sound_c_start
;   Input: A = channel C count.
;   Output: carry clear on success, carry set when count is zero.
;   Clobbers A. Preserves B, X, and S.
;
; jr_sound_c_stop
;   Clobbers A. Preserves B, X, and S.
;
; jr_sound_all_stop
;   Clobbers A. Preserves B, X, and S.

jr_sound_c_start:
        TSTA
        BEQ     jr_sound_c_invalid
        STAA    [JR200_SOUND_C_COUNT]
        LDAA    JR200_SOUND_C_ENABLE
        STAA    [JR200_SOUND_C_CONTROL]
        CLC
        RTS
jr_sound_c_invalid:
        SEC
        RTS

jr_sound_c_stop:
        CLRA
        STAA    [JR200_SOUND_C_CONTROL]
        RTS

jr_sound_all_stop:
        CLRA
        STAA    [JR200_SOUND_C_CONTROL]
        STAA    [JR200_SOUND_D_CONTROL]
        STAA    [JR200_SOUND_F_CONTROL]
        RTS

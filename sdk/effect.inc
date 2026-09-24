; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and session.inc. A non-blocking effect stepper. The game
; calls jr_effect_tick once per chosen update tick and draws from the returned
; phase. This module never waits, polls input or changes the game clock.
;
; jr_effect_init: clears remaining steps and phase. Clobbers no registers.
; jr_effect_start: A = step count (0 cancels), phase resets to 0. Preserves B, X.
; jr_effect_tick: advances one step. Output A = phase, B = 1 when a step was
;   advanced, otherwise B = 0. Preserves X and S. A new effect may be started
;   while one is active; it restarts at phase 0.
; Uses JR_RT + 52..53; poll cadence belongs to the caller, not a fixed fps.

JR_RT_EFFECT_REMAIN: .equ    JR_RT + 52
JR_RT_EFFECT_PHASE:  .equ    JR_RT + 53

jr_effect_init:
        CLR     [JR_RT_EFFECT_REMAIN]
        CLR     [JR_RT_EFFECT_PHASE]
        RTS

jr_effect_start:
        STAA    [JR_RT_EFFECT_REMAIN]
        CLR     [JR_RT_EFFECT_PHASE]
        RTS

jr_effect_tick:
        TST     [JR_RT_EFFECT_REMAIN]
        BEQ     jr_effect_idle
        DEC     [JR_RT_EFFECT_REMAIN]
        INC     [JR_RT_EFFECT_PHASE]
        LDAA    [JR_RT_EFFECT_PHASE]
        LDAB    1
        RTS
jr_effect_idle:
        LDAA    [JR_RT_EFFECT_PHASE]
        CLRB
        RTS

; SPDX-License-Identifier: BSD-3-Clause
; Three-voice music and channel-C effects. Requires jr200.inc and a 28-byte
; JR_AUDIO area defined by the game. Include audio_notes.inc as well.
;
; Drop-in replacement for sfx.inc: jr_sfx_play / jr_sfx_tick / jr_sfx_stop
; keep the same contract, so sdk/port.inc works unchanged. Do not include
; sfx.inc together with this file.
;
; Voices: 0 = channel F (16-bit count), 1 = channel D, 2 = channel C.
; A track is a list of (note, frames) byte pairs ending with frames 0; note 0
; is a rest and notes 1-60 are C2-B6 (audio_notes.inc). A song is
;   .db flags (bit 0 = loop)
;   .dw track_f, track_d, track_c      (0 = silent voice)
; An effect phrase is a list of (channel-C count, frames) pairs ending with
; frames 0, exactly as in sfx.inc. A phrase whose first byte is 0xfe is a
; song (the bytes after 0xfe): jr_sfx_play then starts it as music, which
; lets game_sfx_table hold three-voice jingles.
; While an effect sounds on channel C the music's channel-C voice keeps its
; timing silently and resumes when the effect ends.
; Everything advances once per jr_sfx_tick; the tempo is in calls, not in
; wall-clock time. Pitch follows the emulator's divider formula; hardware
; pitch is unverified.
;
; jr_audio_init    clears JR_AUDIO and silences C, D and F. Call once after
;                  jr_session_enter.
; jr_music_play    X = song. Clobbers A, B and X.
; jr_music_stop    Clobbers A, B and X.
; jr_sfx_play      X = phrase or 0xfe song. Clobbers A, B and X.
; jr_sfx_tick      Call once per frame. Clobbers A, B and X.
; jr_sfx_stop      Stops the effect and restores the music voice on C.

JR_AU_VOICE:        .equ    JR_AUDIO + 0    ; 3 x (ptr 2, left 1, start 2)
JR_AU_LOOP:         .equ    JR_AUDIO + 15
JR_AU_SFX_PTR:      .equ    JR_AUDIO + 16
JR_AU_SFX_LEFT:     .equ    JR_AUDIO + 18
JR_AU_CNOTE:        .equ    JR_AUDIO + 19
JR_AU_REC:          .equ    JR_AUDIO + 20
JR_AU_TMP:          .equ    JR_AUDIO + 22    ; voice index being processed
JR_AU_SONG:         .equ    JR_AUDIO + 24
JR_AU_START:        .equ    JR_AUDIO + 26
JR_AUDIO_SIZE:      .equ    28

JR_AU_SONG_MARK:    .equ    0xfe

jr_audio_init:
        LDX     JR_AUDIO
jr_audio_init_clear:
        CLR     [X]
        INX
        CPX     JR_AUDIO + JR_AUDIO_SIZE
        BNE     jr_audio_init_clear
        CLR     [JR200_SOUND_F_CONTROL]
        CLR     [JR200_SOUND_D_CONTROL]
        CLR     [JR200_SOUND_C_CONTROL]
        RTS

; ---------------------------------------------------------------- music

jr_music_play:
        STX     [JR_AU_SONG]
        LDAA    [X]
        STAA    [JR_AU_LOOP]
        CLRB
jr_music_play_voice:
        STAB    [JR_AU_TMP]
        LDX     [JR_AU_SONG]
        INX
        TBA
        INCA
        JSR     au_note_x           ; X = song + 1 + 2 * voice
        LDAA    [X]
        STAA    [JR_AU_START]
        LDAA    [X + 1]
        STAA    [JR_AU_START + 1]
        LDAB    [JR_AU_TMP]
        JSR     au_record_x
        LDAA    [JR_AU_START]
        STAA    [X + 3]
        STAA    [X]
        LDAA    [JR_AU_START + 1]
        STAA    [X + 4]
        STAA    [X + 1]
        LDAB    [JR_AU_TMP]
        JSR     au_voice_start
        LDAB    [JR_AU_TMP]
        INCB
        CMPB    3
        BNE     jr_music_play_voice
        RTS

jr_music_stop:
        CLR     [JR_AU_VOICE + 2]
        CLR     [JR_AU_VOICE + 7]
        CLR     [JR_AU_VOICE + 12]
        CLR     [JR_AU_CNOTE]
        CLR     [JR200_SOUND_F_CONTROL]
        CLR     [JR200_SOUND_D_CONTROL]
        TST     [JR_AU_SFX_LEFT]
        BNE     jr_music_stop_done
        CLR     [JR200_SOUND_C_CONTROL]
jr_music_stop_done:
        RTS

; B = voice (0-2). Output X = voice record. Uses JR_AU_REC.
au_record_x:
        PSHB
        LDX     JR_AU_VOICE
        STX     [JR_AU_REC]
        TSTB
        BEQ     au_record_x_done
au_record_x_step:
        LDAA    [JR_AU_REC + 1]
        ADDA    5
        STAA    [JR_AU_REC + 1]
        LDAA    [JR_AU_REC]
        ADCA    0
        STAA    [JR_AU_REC]
        DECB
        BNE     au_record_x_step
au_record_x_done:
        LDX     [JR_AU_REC]
        PULB
        RTS

; X = record, B = voice. Starts the event at ptr (or loops / stops).
au_voice_start:
        STX     [JR_AU_REC]
        LDX     [X]
        CPX     0
        BEQ     au_voice_stop
        LDAA    [X + 1]
        BNE     au_voice_event
        TST     [JR_AU_LOOP]
        BEQ     au_voice_stop
        LDX     [JR_AU_REC]
        LDAA    [X + 3]
        STAA    [X]
        LDAA    [X + 4]
        STAA    [X + 1]
        LDX     [X]
        LDAA    [X + 1]
        BEQ     au_voice_stop
au_voice_event:
        PSHA
        LDAA    [X]
        LDX     [JR_AU_REC]
        PULB
        STAB    [X + 2]
        LDAB    [JR_AU_TMP]         ; voice index saved by the caller
        BRA     au_voice_out
au_voice_stop:
        LDX     [JR_AU_REC]
        CLR     [X + 2]
        CLRA
        LDAB    [JR_AU_TMP]
        ; fall through with A = rest

; A = note (0 rest), B = voice. Writes the channel registers.
au_voice_out:
        TSTB
        BEQ     au_out_f
        CMPB    1
        BEQ     au_out_d
        STAA    [JR_AU_CNOTE]
        TST     [JR_AU_SFX_LEFT]
        BNE     au_out_done
au_out_c:
        TSTA
        BEQ     au_out_c_rest
        JSR     au_cd_entry
        LDAB    [X + 1]
        STAB    [JR200_SOUND_C_COUNT]
        LDAA    [X]
        STAA    [JR200_SOUND_C_CONTROL]
        RTS
au_out_c_rest:
        CLR     [JR200_SOUND_C_CONTROL]
        RTS
au_out_d:
        TSTA
        BEQ     au_out_d_rest
        JSR     au_cd_entry
        LDAB    [X + 1]
        STAB    [JR200_SOUND_D_COUNT]
        LDAA    [X]
        STAA    [JR200_SOUND_D_CONTROL]
        RTS
au_out_d_rest:
        CLR     [JR200_SOUND_D_CONTROL]
        RTS
au_out_f:
        TSTA
        BEQ     au_out_f_rest
        LDX     au_f_table
        JSR     au_note_x
        LDAA    [X]
        STAA    [JR200_SOUND_F_COUNT_HIGH]
        LDAA    [X + 1]
        STAA    [JR200_SOUND_F_COUNT_LOW]
        LDAA    JR200_SOUND_C_ENABLE
        STAA    [JR200_SOUND_F_CONTROL]
        RTS
au_out_f_rest:
        CLR     [JR200_SOUND_F_CONTROL]
au_out_done:
        RTS

au_cd_entry:
        LDX     au_cd_table
; X = table, A = note 1-60. Output X = table + 2 * (note - 1).
au_note_x:
        DECA
        ASLA
        STX     [JR_AU_REC]
        ADDA    [JR_AU_REC + 1]
        STAA    [JR_AU_REC + 1]
        LDAA    [JR_AU_REC]
        ADCA    0
        STAA    [JR_AU_REC]
        LDX     [JR_AU_REC]
        RTS

; ---------------------------------------------------------------- effects

jr_sfx_play:
        LDAA    [X]
        CMPA    JR_AU_SONG_MARK
        BNE     jr_sfx_play_effect
        INX
        JMP     jr_music_play
jr_sfx_play_effect:
        STX     [JR_AU_SFX_PTR]
au_sfx_note:
        LDX     [JR_AU_SFX_PTR]
        LDAB    [X + 1]
        STAB    [JR_AU_SFX_LEFT]
        BEQ     jr_sfx_stop
        LDAA    [X]
        BEQ     au_sfx_rest
        STAA    [JR200_SOUND_C_COUNT]
        LDAA    JR200_SOUND_C_ENABLE
        STAA    [JR200_SOUND_C_CONTROL]
        RTS
au_sfx_rest:
        CLR     [JR200_SOUND_C_CONTROL]
        RTS

jr_sfx_stop:
        CLR     [JR_AU_SFX_LEFT]
        LDAA    [JR_AU_CNOTE]
        TST     [JR_AU_VOICE + 12]
        BNE     jr_sfx_stop_music
        CLRA
jr_sfx_stop_music:
        JMP     au_out_c

jr_sfx_tick:
        LDAA    [JR_AU_SFX_LEFT]
        BEQ     au_music_tick
        DECA
        STAA    [JR_AU_SFX_LEFT]
        BNE     au_music_tick
        LDX     [JR_AU_SFX_PTR]
        INX
        INX
        STX     [JR_AU_SFX_PTR]
        JSR     au_sfx_note
au_music_tick:
        CLRB
au_music_tick_voice:
        STAB    [JR_AU_TMP]
        JSR     au_record_x
        LDAA    [X + 2]
        BEQ     au_music_tick_next
        DECA
        STAA    [X + 2]
        BNE     au_music_tick_next
        ; ptr += 2, then start the next event
        STX     [JR_AU_REC]
        LDAA    [X + 1]
        ADDA    2
        STAA    [X + 1]
        LDAA    [X]
        ADCA    0
        STAA    [X]
        LDAB    [JR_AU_TMP]
        JSR     au_voice_start
au_music_tick_next:
        LDAB    [JR_AU_TMP]
        INCB
        CMPB    3
        BNE     au_music_tick_voice
        RTS

# SPDX-License-Identifier: BSD-3-Clause
"""sdk/audio.inc: note table, driver model and the three-voice chord sample."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from audio_model import AudioModel  # noqa: E402
import audio_notes  # noqa: E402

C3, E4, G4, C5, E5, G5, C6 = 13, 29, 32, 37, 41, 44, 49


class NoteTableTests(unittest.TestCase):
    def test_generated_table_is_current(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/audio_notes.py'), '--check'])
        self.assertEqual(result.returncode, 0, 'run tools/audio_notes.py')

    def test_emulated_pitch_is_close_to_equal_temperament(self):
        # The emulator computes whole hertz, so low notes may be off by 1 Hz.
        for note in range(1, audio_notes.NOTES + 1):
            target = audio_notes.frequency(note)
            f_hz = audio_notes.emulated(1, audio_notes.f_count(note))
            control, count = audio_notes.cd_entry(note)
            self.assertLessEqual(count, 255)
            cd_hz = audio_notes.emulated(8 if control == 0x0e else 64, count)
            with self.subTest(note=note):
                self.assertLessEqual(abs(f_hz - target), max(1, 0.003 * target))
                self.assertLessEqual(abs(cd_hz - target), max(1, 0.018 * target))
        self.assertEqual(audio_notes.frequency(34), 440.0)       # note 34 = A4


class DriverModelTests(unittest.TestCase):
    def layout(self, base):
        """Byte layout of the chord sample's data, in source order."""
        melody = bytes([C5, 15, E5, 15, G5, 15, C6, 15, 0, 0])
        harmony = bytes([E4, 30, G4, 30, 0, 0])
        bass = bytes([C3, 60, 0, 0])
        beep = bytes([120, 10, 90, 10, 0, 0])
        song = base
        m, h, b = base + 7, base + 7 + len(melody), base + 7 + len(melody) + len(harmony)
        e = b + len(bass)
        header = bytes([1, m >> 8, m & 0xff, h >> 8, h & 0xff, b >> 8, b & 0xff])
        model = AudioModel()
        model.load(song, header + melody + harmony + bass + beep)
        return model, song, e

    def test_sample_source_matches_the_modelled_layout(self):
        source = (ROOT / 'samples/chord/src/main.asm').read_text()
        expected = ('chord_song:\n        .db     1\n'
                    '        .dw     chord_melody, chord_harmony, chord_bass\n'
                    'chord_melody:\n        .db     AU_C5, 15, AU_E5, 15, AU_G5, 15, AU_C6, 15, 0, 0\n'
                    'chord_harmony:\n        .db     AU_E4, 30, AU_G4, 30, 0, 0\n'
                    'chord_bass:\n        .db     AU_C3, 60, 0, 0\n'
                    'chord_beep:\n        .db     120, 10, 90, 10, 0, 0\n')
        self.assertIn(expected, source)
        notes = (ROOT / 'sdk/audio_notes.inc').read_text()
        for name, value in (('C3', C3), ('E4', E4), ('G4', G4), ('C5', C5),
                            ('E5', E5), ('G5', G5), ('C6', C6)):
            self.assertIn(f'AU_{name}:', notes)
            self.assertRegex(notes, rf'AU_{name}:\s+\.equ\s+{value}\n')

    def test_frame_100_snapshot_matches_the_runner_expectation(self):
        profile = json.loads((ROOT / 'samples/chord/tests/expectations.json').read_text())[
            'runtime']['profiles'][0]
        snapshot = bytes.fromhex(profile['expect']['memory']['snapshot'])
        start = (snapshot[3] << 8) | snapshot[4]           # voice 0 start = song + 7
        model, song, _ = self.layout(start - 7)
        model.music_play(song)
        for _ in range(100):
            model.tick()
        self.assertEqual(model.state_bytes(), snapshot)
        self.assertEqual(model.channel, {'F': G5, 'D': G4, 'C': C3})

    def test_effect_pauses_and_restores_the_channel_c_voice(self):
        model, song, beep = self.layout(0x1200)
        model.music_play(song)
        model.tick()
        model.sfx_play(beep)
        self.assertEqual(model.channel['C'], ('sfx', 120))
        for _ in range(10):
            model.tick()
        self.assertEqual(model.channel['C'], ('sfx', 90))
        for _ in range(10):
            model.tick()
        self.assertEqual(model.channel['C'], C3)
        self.assertEqual(model.voice[2][1], 60 - 21)

    def test_non_looping_jingle_ends_silent(self):
        model = AudioModel()
        model.load(0x1300, bytes([0xfe, 0, 0x13, 0x08, 0, 0, 0, 0, C5, 2, E5, 2, 0, 0]))
        model.sfx_play(0x1300)
        self.assertEqual(model.channel['F'], C5)
        for _ in range(4):
            model.tick()
        self.assertEqual(model.channel, {'F': 0, 'D': 0, 'C': 0})
        self.assertEqual([voice[1] for voice in model.voice], [0, 0, 0])


class DriverSourceTests(unittest.TestCase):
    def test_audio_replaces_sfx_without_changing_published_modules(self):
        audio = (ROOT / 'sdk/audio.inc').read_text()
        for label in ('jr_sfx_play:', 'jr_sfx_tick:', 'jr_sfx_stop:', 'jr_audio_init:',
                      'jr_music_play:', 'jr_music_stop:'):
            self.assertIn('\n' + label, audio)
        self.assertNotIn('JR_RT', audio)
        self.assertIn('JR_AUDIO_SIZE:      .equ    28', audio)

    def test_chord_expectation_requires_three_voice_peak(self):
        profiles = json.loads((ROOT / 'samples/chord/tests/expectations.json').read_text())[
            'runtime']['profiles']
        chord = next(p for p in profiles if p['profile'] == 'synthetic-chord')
        self.assertEqual(chord['expect']['pcm']['minimum_peak'], 21000)


if __name__ == '__main__':
    unittest.main()

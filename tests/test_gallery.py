# SPDX-License-Identifier: BSD-3-Clause
"""Gallery manifests: every image/video is tied to a verified replay profile."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from png_rgba import decode_rgba  # noqa: E402

ROLES = {'title', 'play', 'goal'}


def galleries():
    return sorted(ROOT.glob('games/*/media/gallery.json'))


class GalleryTests(unittest.TestCase):
    def test_side_catch_player_and_target_use_distinct_colors(self):
        _, _, pixels = decode_rgba(
            (ROOT / 'games/side-catch/media/title.png').read_bytes())
        colors = {pixels[index:index + 4] for index in range(0, len(pixels), 4)}
        self.assertIn(bytes.fromhex('00ff00ff'), colors)  # player: green
        self.assertIn(bytes.fromhex('ffff00ff'), colors)  # target: yellow

    def test_rom_capture_guard_rejects_foreign_glyphs(self):
        node = shutil.which('node')
        if node is None:
            self.skipTest('Node.js is unavailable; standalone guard smoke not run')
        completed = subprocess.run(
            [node, str(ROOT / 'tests/authored_capture_smoke.mjs')],
            capture_output=True, text=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn('authored capture guard: OK', completed.stdout)

    def test_new_ports_have_three_scenes_and_a_video(self):
        for game in ('side-catch', 'lumen-cross', 'corner-crown', 'circuit-works',
                     'hearth-zero', 'brick-pulse', 'relic-dive'):
            path = ROOT / 'games' / game / 'media/gallery.json'
            with self.subTest(game=game):
                gallery = json.loads(path.read_text(encoding='utf-8'))
                self.assertEqual({scene['role'] for scene in gallery['scenes']}, ROLES)
                self.assertIn('video', gallery)

    def test_scene_files_match_hashes_and_replay_framebuffers(self):
        for path in galleries():
            project = path.parents[1]
            gallery = json.loads(path.read_text(encoding='utf-8'))
            expectations = json.loads((project / 'tests/expectations.json').read_text())
            profiles = {p['profile']: p for p in expectations['runtime']['profiles']}
            self.assertIn(gallery['schema_version'], (1, 2))
            capture_mode = ('synthetic-injection' if gallery['schema_version'] == 1
                            else 'rom-cassette')
            if capture_mode == 'rom-cassette':
                provenance = gallery['capture']
                self.assertEqual(provenance['mode'], capture_mode)
                source = ROOT / provenance['glyph_source']
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),
                                 provenance['glyph_source_sha256'])
                catalog = json.loads((ROOT / 'games/catalog.json').read_text())
                game = next(item for item in catalog['games']
                            if item['id'] == project.name)
                self.assertEqual(provenance['artifact_sha256'],
                                 game['artifact_sha256'])
            for scene in gallery['scenes']:
                with self.subTest(game=project.name, scene=scene['id']):
                    image = path.parent / scene['file']
                    self.assertEqual(image.parent, path.parent)
                    data = image.read_bytes()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), scene['sha256'])
                    width, height, pixels = decode_rgba(data)
                    self.assertEqual((width, height), (320, 224))
                    self.assertEqual(hashlib.sha256(pixels).hexdigest(),
                                     scene['framebuffer_sha256'])
                    profile = profiles[scene['profile']]
                    self.assertEqual(profile['mode'], capture_mode)
                    self.assertEqual(profile['expect']['framebuffer_sha256'],
                                     scene['framebuffer_sha256'])
                    self.assertTrue(scene['caption'])
            video = gallery.get('video')
            if video:
                with self.subTest(game=project.name, video=video['file']):
                    data = (path.parent / video['file']).read_bytes()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), video['sha256'])
                    self.assertEqual(data[:4], b'\x1a\x45\xdf\xa3')  # WebM/Matroska
                    self.assertEqual(profiles[video['profile']]['mode'], capture_mode)
                    if capture_mode == 'rom-cassette':
                        self.assertEqual(video['mode'], capture_mode)
                        self.assertEqual(video['artifact_sha256'],
                                         gallery['capture']['artifact_sha256'])
                        self.assertGreater(video['start_cycle'], 0)
                        self.assertLess(video['start_cycle'],
                                        profiles[video['profile']]['max_cycles'])
                    self.assertGreater(video['seconds'], 0)
                    self.assertLessEqual(video['seconds'], 60)


if __name__ == '__main__':
    unittest.main()

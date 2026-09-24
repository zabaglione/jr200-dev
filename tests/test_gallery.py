# SPDX-License-Identifier: BSD-3-Clause
"""Gallery manifests: every image/video is tied to a verified synthetic profile."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from png_rgba import decode_rgba  # noqa: E402

ROLES = {'title', 'play', 'goal'}


def galleries():
    return sorted(ROOT.glob('games/*/media/gallery.json'))


class GalleryTests(unittest.TestCase):
    def test_new_ports_have_three_scenes_and_a_video(self):
        for game in ('lumen-cross', 'corner-crown', 'circuit-works', 'hearth-zero',
                     'brick-pulse'):
            path = ROOT / 'games' / game / 'media/gallery.json'
            with self.subTest(game=game):
                gallery = json.loads(path.read_text(encoding='utf-8'))
                self.assertEqual({scene['role'] for scene in gallery['scenes']}, ROLES)
                self.assertIn('video', gallery)

    def test_scene_files_match_hashes_and_synthetic_framebuffers(self):
        for path in galleries():
            project = path.parents[1]
            gallery = json.loads(path.read_text(encoding='utf-8'))
            expectations = json.loads((project / 'tests/expectations.json').read_text())
            profiles = {p['profile']: p for p in expectations['runtime']['profiles']}
            self.assertEqual(gallery['schema_version'], 1)
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
                    self.assertEqual(profile['mode'], 'synthetic-injection')
                    self.assertEqual(profile['expect']['framebuffer_sha256'],
                                     scene['framebuffer_sha256'])
                    self.assertTrue(scene['caption'])
            video = gallery.get('video')
            if video:
                with self.subTest(game=project.name, video=video['file']):
                    data = (path.parent / video['file']).read_bytes()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), video['sha256'])
                    self.assertEqual(data[:4], b'\x1a\x45\xdf\xa3')  # WebM/Matroska
                    self.assertEqual(profiles[video['profile']]['mode'], 'synthetic-injection')
                    self.assertGreater(video['seconds'], 0)
                    self.assertLessEqual(video['seconds'], 60)


if __name__ == '__main__':
    unittest.main()

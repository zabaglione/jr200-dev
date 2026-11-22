# SPDX-License-Identifier: BSD-3-Clause
"""Check that the authored title scenes agree with their assembled assets."""

from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TitleArtworkTests(unittest.TestCase):
    def test_assembled_scenes_match_authoring_sources(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / 'tools/title_art/render.py'), '--check'],
            cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

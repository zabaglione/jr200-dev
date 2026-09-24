# SPDX-License-Identifier: BSD-3-Clause
"""Local play staging: fixed web UI, fresh CJR, loopback server. No browser."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import socket
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import game_play  # noqa: E402
from ci_plan import select  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CJR = bytes.fromhex('0102')


def make_web(directory: Path, lock: dict) -> None:
    directory.mkdir(parents=True)
    for name in game_play.WEB_FILES:
        text = '<html><head></head><body></body></html>' if name == 'index.html' else name
        (directory / name).write_text(text)
    (directory / 'backend.json').write_text('{"backend":"emscripten"}\n')
    (directory / 'LICENSES').mkdir()
    (directory / 'LICENSES/x.txt').write_text('x')
    for item in lock['module_files']:
        payload = item['path'].encode()
        (directory / item['path']).write_bytes(payload)
        item['size'] = len(payload)
        item['sha256'] = hashlib.sha256(payload).hexdigest()


class GamePlayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.lock = json.loads((ROOT / 'emulator.lock.json').read_text())
        self.web = self.root / 'site'
        make_web(self.web, self.lock)
        self.lock_path = self.root / 'lock.json'
        self.lock_path.write_text(json.dumps(self.lock))
        project = self.root / 'fixture'
        shutil.copytree(ROOT / 'templates/minimal', project,
                        ignore=shutil.ignore_patterns('build'))
        self.project = project

    def tearDown(self):
        self.temp.cleanup()

    def fake_build(self):
        spec = game_play.validate_project(self.project)
        build = self.project / 'build'
        build.mkdir(exist_ok=True)
        spec.output.write_bytes(CJR)
        inputs = [{'path': p, 'sha256': game_play.sha256_file(self.project / p)}
                  for p in (*spec.assembly_inputs, *spec.asset_inputs)]
        inputs += [{'path': '@repo/' + p, 'sha256': game_play.sha256_file(ROOT / p)}
                   for p in spec.sdk_inputs]
        (build / 'build-report.json').write_text(json.dumps({
            'inputs': inputs, 'artifact': {'sha256': hashlib.sha256(CJR).hexdigest()}}))

    def test_stages_allow_listed_site_with_one_catalog_entry(self):
        self.fake_build()
        out = self.root / 'out'
        report = game_play.stage(self.project, self.web, out, self.lock_path)
        catalog = json.loads((out / 'game-catalog.json').read_text())
        self.assertEqual(len(catalog['games']), 1)
        entry = catalog['games'][0]
        # Same checks as jr200-web-emulator web/game-launch.mjs.
        self.assertRegex(entry['id'], r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$')
        self.assertRegex(entry['version'], r'^\d+\.\d+\.\d+$')
        self.assertEqual(entry['path'],
                         f'games/{entry["id"]}/{entry["version"]}/{entry["id"]}.cjr')
        self.assertRegex(entry['runCommand'], r'^A=USR\(\$[0-9A-F]{4}\)$')
        self.assertEqual((out / entry['path']).read_bytes(), CJR)
        self.assertEqual(entry['sha256'], report['cjr_sha256'])
        self.assertLessEqual(len(entry['title']), 80)
        self.assertIn('DEVELOPMENT BUILD', (out / 'index.html').read_text())
        self.assertIn('dev-banner.css', (out / 'index.html').read_text())
        staged = {p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()}
        self.assertFalse({p for p in staged if 'local-data' in p or p.endswith('.rom')})
        self.assertIn(f'games/{entry["id"]}/{entry["version"]}/LICENSE.txt', staged)

    def test_rejects_missing_and_stale_builds(self):
        with self.assertRaisesRegex(game_play.PlayError, 'No built CJR'):
            game_play.stage(self.project, self.web, self.root / 'a', self.lock_path)
        self.fake_build()
        source = self.project / 'src/main.asm'
        source.write_text(source.read_text() + '\n; edited\n')
        with self.assertRaisesRegex(game_play.PlayError, 'older than its sources'):
            game_play.stage(self.project, self.web, self.root / 'b', self.lock_path)

    def test_rejects_unlocked_codec_and_incomplete_site(self):
        self.fake_build()
        (self.web / 'jr200_codec.wasm').write_bytes(b'other')
        with self.assertRaisesRegex(game_play.PlayError, 'does not match emulator.lock'):
            game_play.stage(self.project, self.web, self.root / 'a', self.lock_path)
        (self.web / 'app.mjs').unlink()
        with self.assertRaisesRegex(game_play.PlayError, 'missing app.mjs'):
            game_play.stage(self.project, self.web, self.root / 'b', self.lock_path)

    def test_refuses_non_empty_staging_directory(self):
        self.fake_build()
        out = self.root / 'out'
        out.mkdir()
        (out / 'keep').write_text('x')
        with self.assertRaisesRegex(game_play.PlayError, 'not empty'):
            game_play.stage(self.project, self.web, out, self.lock_path)

    def test_server_binds_loopback_and_reports_port_conflicts(self):
        self.fake_build()
        out = self.root / 'out'
        game_play.stage(self.project, self.web, out, self.lock_path)
        server = game_play.serve(out, 0)
        try:
            self.assertEqual(server.server_address[0], '127.0.0.1')
            port = server.server_address[1]
            with self.assertRaisesRegex(game_play.PlayError, 'Cannot listen'):
                game_play.serve(out, port)
        finally:
            server.server_close()

    def test_directory_listing_is_disabled(self):
        handler = mock.Mock(spec=game_play.StagedHandler)
        game_play.StagedHandler.list_directory(handler, '/')
        handler.send_error.assert_called_once_with(404)

    def test_play_tool_changes_do_not_build_targets(self):
        registry = json.loads((ROOT / 'ci/targets.json').read_text())
        plan = select(registry, ['tools/game_play.py'])
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(plan['unclassified_paths'], [])


if __name__ == '__main__':
    unittest.main()

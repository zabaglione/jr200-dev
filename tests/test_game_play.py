# SPDX-License-Identifier: BSD-3-Clause
"""Local play staging: fixed web UI, fresh CJR, loopback server. No browser."""
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import socket
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
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
    (directory / 'game-catalog.json').write_text('{"schemaVersion":1,"games":[]}\n')
    (directory / 'backend.json').write_text('{"backend":"emscripten"}\n')
    (directory / 'LICENSES').mkdir()
    for name in game_play.WEB_LICENSE_FILES:
        (directory / 'LICENSES' / name).write_text(name)
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
        self.site_lock_path = self.root / 'site-lock.json'
        self.site_lock_path.write_text(json.dumps({
            'schema_version': 1,
            'source': {'repository': self.lock['source']['repository'],
                       'revision': '0' * 40},
            'files': {path.relative_to(self.web).as_posix(): game_play.sha256_file(path)
                      for path in self.web.rglob('*') if path.is_file()},
        }))
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
            'inputs': inputs,
            'configuration': {name: game_play.sha256_file(self.project / name)
                              for name in ('build.json', 'game.json')},
            'artifact': {'sha256': hashlib.sha256(CJR).hexdigest()}}))

    def test_stages_allow_listed_site_with_one_catalog_entry(self):
        self.fake_build()
        out = self.root / 'out'
        report = game_play.stage(self.project, self.web, out, self.lock_path,
                                 self.site_lock_path)
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
            game_play.stage(self.project, self.web, self.root / 'a', self.lock_path,
                            self.site_lock_path)
        self.fake_build()
        source = self.project / 'src/main.asm'
        source.write_text(source.read_text() + '\n; edited\n')
        with self.assertRaisesRegex(game_play.PlayError, 'older than its sources'):
            game_play.stage(self.project, self.web, self.root / 'b', self.lock_path,
                            self.site_lock_path)

    def test_rejects_changed_build_and_game_contracts(self):
        self.fake_build()
        for name in ('build.json', 'game.json'):
            path = self.project / name
            original = path.read_text()
            path.write_text(original + '\n')
            with self.assertRaisesRegex(game_play.PlayError, 'older than its sources'):
                game_play.stage(self.project, self.web, self.root / name,
                                self.lock_path, self.site_lock_path)
            path.write_text(original)
        report_path = self.project / 'build/build-report.json'
        report = json.loads(report_path.read_text())
        del report['configuration']
        report_path.write_text(json.dumps(report))
        with self.assertRaisesRegex(game_play.PlayError, 'older than its sources'):
            game_play.stage(self.project, self.web, self.root / 'missing',
                            self.lock_path, self.site_lock_path)

    def test_rejects_unlocked_codec_and_incomplete_site(self):
        self.fake_build()
        (self.web / 'jr200_codec.wasm').write_bytes(b'other')
        with self.assertRaisesRegex(game_play.PlayError, 'jr200_codec.wasm'):
            game_play.stage(self.project, self.web, self.root / 'a', self.lock_path,
                            self.site_lock_path)
        (self.web / 'app.mjs').unlink()
        with self.assertRaisesRegex(game_play.PlayError, 'app.mjs'):
            game_play.stage(self.project, self.web, self.root / 'b', self.lock_path,
                            self.site_lock_path)

    def test_refuses_non_empty_staging_directory(self):
        self.fake_build()
        out = self.root / 'out'
        out.mkdir()
        (out / 'keep').write_text('x')
        with self.assertRaisesRegex(game_play.PlayError, 'not empty'):
            game_play.stage(self.project, self.web, out, self.lock_path,
                            self.site_lock_path)

    def test_path_with_spaces_and_rebuilt_cjr_hash(self):
        spaced = self.root / 'path with spaces'
        shutil.move(str(self.project), str(spaced))
        self.project = spaced
        self.fake_build()
        first = game_play.stage(self.project, self.web, self.root / 'first site',
                                self.lock_path, self.site_lock_path)
        source = self.project / 'src/main.asm'
        source.write_text(source.read_text() + '\n; new revision\n')
        with self.assertRaisesRegex(game_play.PlayError, 'older than its sources'):
            game_play.stage(self.project, self.web, self.root / 'stale site',
                            self.lock_path, self.site_lock_path)
        self.fake_build()
        (self.project / 'build' / 'minimal.cjr').write_bytes(b'new cjr')
        # A changed artifact must be represented by its own fresh build report.
        report_path = self.project / 'build/build-report.json'
        report = json.loads(report_path.read_text())
        report['artifact']['sha256'] = hashlib.sha256(b'new cjr').hexdigest()
        report_path.write_text(json.dumps(report))
        second = game_play.stage(self.project, self.web, self.root / 'second site',
                                 self.lock_path, self.site_lock_path)
        self.assertNotEqual(first['cjr_sha256'], second['cjr_sha256'])

    def test_browser_open_failure_still_reports_manual_url(self):
        class StoppedServer:
            def serve_forever(self):
                raise KeyboardInterrupt

            def server_close(self):
                pass

        output = io.StringIO()
        with (mock.patch.object(game_play, 'stage', return_value={
                'id': 'side-catch', 'version': '0.1.0', 'cjr_sha256': '0' * 64,
                'emulator_revision': '1' * 40, 'run_command': 'A=USR($1000)'}),
              mock.patch.object(game_play, 'serve', return_value=StoppedServer()),
              mock.patch.object(game_play.webbrowser, 'open', return_value=False),
              redirect_stdout(output)):
            result = game_play.main(['--project', str(self.project), '--web', str(self.web)])
        self.assertEqual(result, 0)
        self.assertIn('http://127.0.0.1:8765/?game=side-catch', output.getvalue())
        self.assertIn('Could not open a browser', output.getvalue())

    def test_non_bsd_game_stages_sdk_license_and_rejects_linked_notice(self):
        (self.project / 'LICENSE').write_text('MIT fixture')
        notice = self.project / 'THIRD_PARTY_NOTICES.md'
        notice.write_text('SDK BSD fixture')
        spec = SimpleNamespace(project=self.project, repository_root=ROOT,
                               metadata={'license': 'MIT'}, sdk_inputs=('sdk/jr200.inc',))
        game_dir = self.root / 'game'
        game_dir.mkdir()
        game_play.copy_game_legal(spec, game_dir)
        self.assertEqual((game_dir / 'LICENSE.txt').read_text(), 'MIT fixture')
        self.assertEqual((game_dir / 'THIRD_PARTY_NOTICES.md').read_text(),
                         'SDK BSD fixture')
        self.assertEqual((game_dir / 'LICENSES/BSD-3-Clause.txt').read_bytes(),
                         (ROOT / 'LICENSE').read_bytes())
        notice.unlink()
        notice.symlink_to(self.root / 'lock.json')
        other_dir = self.root / 'other game'
        other_dir.mkdir()
        with self.assertRaisesRegex(game_play.PlayError, 'linked staging source'):
            game_play.copy_game_legal(spec, other_dir)

    def test_bsd_game_keeps_existing_notice(self):
        (self.project / 'THIRD_PARTY_NOTICES.md').write_text('Existing notice')
        spec = SimpleNamespace(project=self.project, repository_root=ROOT,
                               metadata={'license': 'BSD-3-Clause'}, sdk_inputs=())
        game_dir = self.root / 'game'
        game_dir.mkdir()
        game_play.copy_game_legal(spec, game_dir)
        self.assertEqual((game_dir / 'THIRD_PARTY_NOTICES.md').read_text(),
                         'Existing notice')

    def test_server_binds_loopback_and_reports_port_conflicts(self):
        self.fake_build()
        out = self.root / 'out'
        game_play.stage(self.project, self.web, out, self.lock_path,
                        self.site_lock_path)
        server = game_play.serve(out, 0)
        try:
            self.assertEqual(server.server_address[0], '127.0.0.1')
            port = server.server_address[1]
            with self.assertRaisesRegex(game_play.PlayError, 'Cannot listen'):
                game_play.serve(out, port)
        finally:
            server.server_close()

    def test_rejects_tampered_ui_extra_files_and_license_symlinks(self):
        self.fake_build()
        (self.web / 'app.mjs').write_text('changed')
        with self.assertRaisesRegex(game_play.PlayError, 'app.mjs'):
            game_play.stage(self.project, self.web, self.root / 'a', self.lock_path,
                            self.site_lock_path)
        make_web_file = self.web / 'app.mjs'
        make_web_file.write_text('app.mjs')
        (self.web / 'private.rom').write_bytes(b'private')
        with self.assertRaisesRegex(game_play.PlayError, 'unexpected root'):
            game_play.stage(self.project, self.web, self.root / 'b', self.lock_path,
                            self.site_lock_path)
        (self.web / 'private.rom').unlink()
        license_path = self.web / 'LICENSES' / game_play.WEB_LICENSE_FILES[0]
        license_path.unlink()
        license_path.symlink_to(self.root / 'lock.json')
        with self.assertRaisesRegex(game_play.PlayError, 'LICENSES/Emscripten'):
            game_play.stage(self.project, self.web, self.root / 'c', self.lock_path,
                            self.site_lock_path)

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

# SPDX-License-Identifier: BSD-3-Clause
import json
import copy
import hashlib
import io
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from ci_pipeline import (PipelineError, calculate_fingerprints, gate, make_plan,
                         run_target_build, run_target_test, verify_build_cache,
                         verify_receipt, write_receipt)
from ci_snapshot import (assemble, entry_fingerprints, inspect_state, main as snapshot_main,
                         latest_success, package_entry, restore, unpack_artifact)


SOURCE_ROOT = Path(__file__).resolve().parents[1]
BANNER = 'JR-200 Assembler 1.0.2 Copyright (C) 2018 ypsitau'
PLATFORM = 'test-linux-x86_64'


def make_cjr(payload=b'\x01\x39', start=0x1000):
    name = b'JR200-MINIMAL'.ljust(16, b'\0')
    header = bytearray(b'\x02\x2a\x00\x1a\xff\xff' + name + b'\x01\x00' + b'\xff' * 8)
    header.append(sum(header) & 0xff)
    block = bytearray((2, 0x2a, 1, len(payload), start >> 8, start & 0xff))
    block.extend(payload)
    block.append(sum(block) & 0xff)
    end = start + len(payload)
    return bytes(header + block + bytes((2, 0x2a, 0xff, 0xff, end >> 8, end & 0xff)))


class PipelineFixture:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for directory in ('ci', 'rules', 'templates', 'mk', 'tools', 'tests', 'games'):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        for relative in ('.gitignore', 'LICENSE', 'toolchain.lock.json',
                         'emulator.lock.json', 'ci/targets.json', 'ci/runner.lock.json',
                         'rules/jr200.json',
                         'mk/game.mk', 'tools/game_project.py', 'tools/jrasm_tool.py',
                         'tools/ci_pipeline.py', 'tools/ci_snapshot.py',
                         'tools/emulator_runner.py',
                         'tools/jr200_wasm_runner.mjs', 'tools/png_rgba.py',
                         'tests/test_game_project.py'):
            source = SOURCE_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        registry = json.loads((self.root / 'ci/targets.json').read_text())
        registry['targets'] = [
            item for item in registry['targets'] if item['id'] == 'minimal'
        ]
        (self.root / 'ci/targets.json').write_text(
            json.dumps(registry, indent=2) + '\n', encoding='utf-8')
        shutil.copytree(SOURCE_ROOT / 'templates/minimal', self.root / 'templates/minimal',
                        dirs_exist_ok=True, ignore=shutil.ignore_patterns('build'))
        shutil.copytree(SOURCE_ROOT / 'tests/fixtures', self.root / 'tests/fixtures')
        self.git('init')
        self.git('config', 'user.email', 'ci@example.invalid')
        self.git('config', 'user.name', 'CI Test')
        self.git('add', '.')
        self.git('commit', '-m', 'base')

    @property
    def registry(self):
        return self.root / 'ci/targets.json'

    @property
    def receipts(self):
        return self.root / '.ci-cache/receipts'

    def close(self):
        self.temporary.cleanup()

    def git(self, *args):
        return subprocess.check_output(
            ['git', *args], cwd=self.root, stderr=subprocess.DEVNULL).decode().strip()

    def fingerprints(self):
        registry = json.loads(self.registry.read_text(encoding='utf-8'))
        from ci_plan import validate_registry
        return calculate_fingerprints(self.root, validate_registry(registry), PLATFORM)['minimal']

    def fake_jrasm(self):
        executable = self.root / 'external tool/jrasm'
        executable.parent.mkdir(parents=True)
        executable.write_text(
            '#!/usr/bin/env python3\n'
            'import pathlib, sys\n'
            f'BANNER = {BANNER!r}\n'
            f'DATA = bytes.fromhex({make_cjr().hex()!r})\n'
            'if len(sys.argv) == 1:\n'
            '    print(BANNER)\n'
            '    print("usage: jrasm [option] source")\n'
            '    raise SystemExit(0)\n'
            'output = sys.argv[sys.argv.index("-o") + 1]\n'
            'pathlib.Path(output).write_bytes(DATA)\n'
            'print(f"{output} was created")\n'
            'print("[Symbol List]")\n'
            'print("1000  start")\n',
            encoding='utf-8')
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        return executable


class PlannerTests(unittest.TestCase):
    def setUp(self):
        self.fixture = PipelineFixture()

    def tearDown(self):
        self.fixture.close()

    def plan(self, changed, full=False):
        return make_plan(self.fixture.root, self.fixture.registry, PLATFORM,
                         None, changed, full)

    def test_docs_only_has_empty_matrix(self):
        plan = self.plan(['README.md'])
        self.assertEqual(plan['matrix']['include'], [])
        self.assertTrue(plan['docs'])

    def test_source_change_builds_and_tests_only_owner(self):
        plan = self.plan(['templates/minimal/src/main.asm'])
        self.assertEqual(plan['build_targets'], ['minimal'])
        self.assertEqual(plan['test_targets'], ['minimal'])
        self.assertTrue(plan['matrix']['include'][0]['build_required'])

    def test_test_only_reuses_compatible_build(self):
        plan = self.plan(['templates/minimal/tests/expectations.json'])
        self.assertEqual(plan['build_targets'], [])
        self.assertEqual(plan['test_targets'], ['minimal'])
        self.assertEqual(plan['reuse_candidates'], ['minimal'])
        self.assertFalse(plan['matrix']['include'][0]['build_required'])

    def test_metadata_change_is_wiki_only(self):
        plan = self.plan(['templates/minimal/game.json'])
        self.assertEqual(plan['matrix']['include'], [])
        self.assertTrue(plan['wiki'])

    def test_unknown_and_toolchain_changes_fail_closed(self):
        unknown = self.plan(['unknown/new.file'])
        self.assertEqual(unknown['build_targets'], ['minimal'])
        self.assertEqual(unknown['unclassified_paths'], ['unknown/new.file'])
        toolchain = self.plan(['toolchain.lock.json'])
        self.assertEqual(toolchain['build_targets'], ['minimal'])

    def test_build_and_test_fingerprints_are_separate(self):
        before = self.fixture.fingerprints()
        expectations = self.fixture.root / 'templates/minimal/tests/expectations.json'
        value = json.loads(expectations.read_text())
        value['notes'] += ' Changed test condition.'
        expectations.write_text(json.dumps(value, indent=2) + '\n')
        after_test = self.fixture.fingerprints()
        self.assertEqual(before['build'], after_test['build'])
        self.assertNotEqual(before['test'], after_test['test'])
        source = self.fixture.root / 'templates/minimal/src/main.asm'
        source.write_text(source.read_text() + '\n; build change\n')
        after_build = self.fixture.fingerprints()
        self.assertNotEqual(after_test['build'], after_build['build'])
        self.assertNotEqual(after_test['test'], after_build['test'])

    def test_removed_target_is_reported_from_previous_graph(self):
        base = self.fixture.git('rev-parse', 'HEAD')
        registry = json.loads(self.fixture.registry.read_text())
        registry['targets'] = []
        self.fixture.registry.write_text(json.dumps(registry, indent=2) + '\n')
        self.fixture.git('add', 'ci/targets.json')
        self.fixture.git('commit', '-m', 'remove target')
        plan = make_plan(self.fixture.root, self.fixture.registry, PLATFORM,
                         base, None, False)
        self.assertEqual(plan['removed_targets'], ['minimal'])
        self.assertEqual(plan['matrix']['include'], [])

    def test_full_run_is_explicit(self):
        plan = self.plan([], full=True)
        self.assertEqual(plan['build_targets'], ['minimal'])
        self.assertEqual(plan['test_targets'], ['minimal'])


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.fixture = PipelineFixture()

    def tearDown(self):
        self.fixture.close()

    def complete(self):
        fingerprints = self.fixture.fingerprints()
        run_target_build(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                         fingerprints['build'], str(self.fixture.fake_jrasm()))
        run_target_test(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                        fingerprints['build'], fingerprints['test'])
        receipt = write_receipt(
            self.fixture.root, self.fixture.registry, self.fixture.receipts,
            'minimal', PLATFORM, fingerprints['build'], fingerprints['test'])
        return fingerprints, receipt

    def test_missing_cache_is_not_reusable(self):
        fingerprints = self.fixture.fingerprints()
        with self.assertRaisesRegex(PipelineError, 'Cannot read build cache metadata'):
            verify_build_cache(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                               fingerprints['build'])

    def test_success_receipt_and_artifact_are_reusable(self):
        fingerprints, receipt = self.complete()
        checked = verify_receipt(
            self.fixture.root, self.fixture.registry, self.fixture.receipts,
            'minimal', PLATFORM, fingerprints['build'], fingerprints['test'])
        self.assertEqual(checked, receipt)
        self.assertEqual(checked['emulator'], 'not_run')
        self.assertEqual(checked['emulator_evidence'], 'not_run')
        self.assertEqual(checked['emulator_unavailable_reason'],
                         'release_asset_not_published')

    def test_runner_lock_changes_only_test_fingerprint(self):
        before = self.fixture.fingerprints()
        lock_path = self.fixture.root / 'emulator.lock.json'
        lock = json.loads(lock_path.read_text())
        lock['runner_version'] = '0.2.1'
        lock_path.write_text(json.dumps(lock, indent=2) + '\n')
        after = self.fixture.fingerprints()
        self.assertEqual(before['build'], after['build'])
        self.assertNotEqual(before['test'], after['test'])

    def test_emulator_bundle_runs_every_synthetic_profile(self):
        expectations_path = (
            self.fixture.root / 'templates/minimal/tests/expectations.json')
        expectations = json.loads(expectations_path.read_text(encoding='utf-8'))
        second = copy.deepcopy(expectations['runtime']['profiles'][0])
        second['profile'] = 'synthetic-second'
        expectations['runtime']['profiles'].append(second)
        expectations_path.write_text(
            json.dumps(expectations, indent=2) + '\n', encoding='utf-8')
        fingerprints = self.fixture.fingerprints()
        run_target_build(
            self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
            fingerprints['build'], str(self.fixture.fake_jrasm()))
        reports = [
            {'result': {'evidence': 'emulator'}},
            {'result': {'evidence': 'emulator'}},
        ]
        with patch('ci_pipeline.run_emulator', side_effect=reports) as runner:
            result = run_target_test(
                self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                fingerprints['build'], fingerprints['test'],
                self.fixture.root / 'fixed-emulator')
        self.assertEqual(
            [call.kwargs['profile'] for call in runner.call_args_list],
            ['synthetic-ci', 'synthetic-second'])
        self.assertEqual(
            result['emulator_profiles'],
            ['synthetic-ci', 'synthetic-second'])

    def test_corrupt_artifact_invalidates_cache_and_receipt(self):
        fingerprints, _ = self.complete()
        artifact = self.fixture.root / 'templates/minimal/build/minimal.cjr'
        artifact.write_bytes(artifact.read_bytes() + b'corrupt')
        with self.assertRaisesRegex(PipelineError, 'hash or size mismatch'):
            verify_receipt(
                self.fixture.root, self.fixture.registry, self.fixture.receipts,
                'minimal', PLATFORM, fingerprints['build'], fingerprints['test'])

    def test_failed_test_result_cannot_create_receipt(self):
        fingerprints = self.fixture.fingerprints()
        run_target_build(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                         fingerprints['build'], str(self.fixture.fake_jrasm()))
        result = self.fixture.root / 'templates/minimal/build/ci-test.json'
        result.write_text(json.dumps({'tests': 'failed'}))
        with self.assertRaisesRegex(PipelineError, 'not eligible'):
            write_receipt(
                self.fixture.root, self.fixture.registry, self.fixture.receipts,
                'minimal', PLATFORM, fingerprints['build'], fingerprints['test'])


class GateTests(unittest.TestCase):
    def test_gate_accepts_success_and_empty_matrix(self):
        gate('success', 'success', 'success', 'true')
        gate('success', 'success', 'skipped', 'false')

    def test_gate_rejects_failure_cancel_and_unexpected_skip(self):
        cases = [
            ('failure', 'success', 'success', 'true'),
            ('success', 'failure', 'success', 'true'),
            ('success', 'success', 'cancelled', 'true'),
            ('success', 'success', 'skipped', 'true'),
        ]
        for values in cases:
            with self.subTest(values=values), self.assertRaises(PipelineError):
                gate(*values)

    def test_trusted_snapshot_is_required_only_for_main(self):
        gate('success', 'success', 'skipped', 'false', 'success', True)
        with self.assertRaisesRegex(PipelineError, 'Trusted snapshot'):
            gate('success', 'success', 'skipped', 'false', 'cancelled', True)
        with self.assertRaisesRegex(PipelineError, 'Unexpected snapshot'):
            gate('success', 'success', 'skipped', 'false', 'success', False)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.fixture = PipelineFixture()
        self.state = self.fixture.root / '.ci-cache/trusted-state'
        self.entry = self.state / 'targets/minimal'

    def tearDown(self):
        self.fixture.close()

    def complete(self):
        fingerprints = self.fixture.fingerprints()
        run_target_build(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                         fingerprints['build'], str(self.fixture.fake_jrasm()))
        run_target_test(self.fixture.root, self.fixture.registry, 'minimal', PLATFORM,
                        fingerprints['build'], fingerprints['test'])
        write_receipt(self.fixture.root, self.fixture.registry, self.fixture.receipts,
                      'minimal', PLATFORM, fingerprints['build'], fingerprints['test'])
        package_entry(self.fixture.root, self.fixture.registry, self.entry, 'minimal',
                      PLATFORM, fingerprints['build'], fingerprints['test'])
        (self.state / 'state.json').write_text(json.dumps({
            'schema_version': 1, 'run_id': 1, 'head_sha': self.fixture.git('rev-parse', 'HEAD'),
            'platform': PLATFORM,
        }))
        return fingerprints

    def plan(self, changed):
        trusted = inspect_state(self.fixture.root, self.fixture.registry,
                                self.state, PLATFORM)
        return make_plan(self.fixture.root, self.fixture.registry, PLATFORM,
                         None, changed, trusted=trusted)

    def test_docs_only_uses_verified_snapshot(self):
        self.complete()
        self.assertEqual(self.plan(['README.md'])['test_targets'], [])

    def test_failed_or_cancelled_predecessor_cannot_hide_game_change(self):
        self.complete()
        source = self.fixture.root / 'templates/minimal/src/main.asm'
        source.write_text(source.read_text() + '\n; unverified source\n')
        plan = self.plan(['README.md'])
        self.assertEqual(plan['build_targets'], ['minimal'])
        self.assertEqual(plan['test_targets'], ['minimal'])

    def test_test_only_keeps_verified_build_and_retests(self):
        before = self.complete()
        expectations = self.fixture.root / 'templates/minimal/tests/expectations.json'
        value = json.loads(expectations.read_text())
        value['notes'] += ' New test only.'
        expectations.write_text(json.dumps(value, indent=2) + '\n')
        plan = self.plan(['templates/minimal/tests/expectations.json'])
        self.assertEqual(plan['build_targets'], [])
        self.assertEqual(plan['test_targets'], ['minimal'])
        self.assertEqual(before['build'], self.fixture.fingerprints()['build'])

    def test_restore_reuses_build_but_not_stale_test_receipt(self):
        before = self.complete()
        expectations = self.fixture.root / 'templates/minimal/tests/expectations.json'
        value = json.loads(expectations.read_text())
        value['notes'] += ' Recheck.'
        expectations.write_text(json.dumps(value, indent=2) + '\n')
        current = self.fixture.fingerprints()
        shutil.rmtree(self.fixture.root / 'templates/minimal/build')
        shutil.rmtree(self.fixture.receipts)
        restore(self.fixture.root, self.fixture.registry, self.state, 'minimal',
                PLATFORM, current['build'], current['test'])
        verify_build_cache(self.fixture.root, self.fixture.registry, 'minimal',
                           PLATFORM, current['build'])
        self.assertFalse((self.fixture.receipts / 'minimal/receipt.json').exists())
        self.assertEqual(before['build'], current['build'])

    def test_assemble_requires_every_current_target(self):
        current = self.complete()
        output = self.fixture.root / '.ci-cache/trusted-output'
        with patch('ci_snapshot.artifact_for_run', return_value={'id': 5}), \
                patch('ci_snapshot.unpack_artifact',
                      side_effect=lambda repo, artifact, token, destination:
                      shutil.copytree(self.entry, destination)):
            assemble(self.fixture.root, self.fixture.registry, self.state, output,
                     'owner/repo', 'token', 9, PLATFORM,
                     '{"include":[{"id":"minimal"}]}')
        self.assertEqual(inspect_state(self.fixture.root, self.fixture.registry,
                                       output, PLATFORM)['minimal'], current)
        (output / 'targets/minimal/artifact.cjr').unlink()
        self.assertNotIn('minimal', inspect_state(self.fixture.root,
                                                 self.fixture.registry, output, PLATFORM))

    def test_missing_or_corrupt_snapshot_forces_recheck(self):
        self.complete()
        artifact = self.entry / 'artifact.cjr'
        artifact.write_bytes(artifact.read_bytes() + b'bad')
        self.assertIsNone(entry_fingerprints(self.entry, 'minimal', PLATFORM))
        self.assertEqual(self.plan(['README.md'])['build_targets'], ['minimal'])
        artifact.unlink()
        self.assertEqual(self.plan(['README.md'])['test_targets'], ['minimal'])

    def test_rejected_snapshot_manifest_cannot_restore_or_be_carried_forward(self):
        current = self.complete()
        (self.state / 'state.json').unlink()
        shutil.rmtree(self.fixture.root / 'templates/minimal/build')
        shutil.rmtree(self.fixture.receipts)
        restore(self.fixture.root, self.fixture.registry, self.state, 'minimal',
                PLATFORM, current['build'], current['test'])
        self.assertFalse((self.fixture.root / 'templates/minimal/build/ci-build.json').exists())
        self.assertEqual(self.plan(['README.md'])['build_targets'], ['minimal'])
        with self.assertRaisesRegex(PipelineError, 'Previous trusted state'):
            assemble(self.fixture.root, self.fixture.registry, self.state,
                     self.fixture.root / '.ci-cache/output', 'owner/repo', 'token',
                     9, PLATFORM, '{"include":[]}')

    def test_failed_download_does_not_publish_partial_snapshot(self):
        def fail_after_extract(root, repo, run_id, current_run, token, output):
            output.mkdir()
            (output / 'state.json').write_text('{}')
            raise PipelineError('digest mismatch')

        with patch.dict(os.environ, {'GITHUB_TOKEN': 'test-token'}), \
                patch('ci_snapshot.download', side_effect=fail_after_extract):
            result = snapshot_main(['download', '--root', str(self.fixture.root),
                                    '--repo', 'owner/repo', '--output', str(self.state)])
        self.assertEqual(result, 0)
        self.assertFalse(self.state.exists())

    def test_malformed_metadata_forces_recheck(self):
        self.complete()
        metadata_path = self.entry / 'ci-build.json'
        metadata_path.write_text('[]')
        self.assertIsNone(entry_fingerprints(self.entry, 'minimal', PLATFORM))
        self.assertEqual(self.plan(['README.md'])['test_targets'], ['minimal'])
        metadata_path.write_text(json.dumps({'artifact': {'path': ''},
                                             'build_report': {}}))
        self.assertIsNone(entry_fingerprints(self.entry, 'minimal', PLATFORM))

    def test_rejects_non_main_or_failed_run_origin(self):
        sha = self.fixture.git('rev-parse', 'HEAD')
        runs = {'workflow_runs': [
            {'id': 1, 'event': 'pull_request', 'head_branch': 'main',
             'conclusion': 'success', 'head_sha': sha, 'path': '.github/workflows/ci.yml'},
            {'id': 2, 'event': 'push', 'head_branch': 'main',
             'conclusion': 'failure', 'head_sha': sha, 'path': '.github/workflows/ci.yml'},
            {'id': 4, 'event': 'push', 'head_branch': 'main',
             'conclusion': 'success', 'head_sha': sha, 'path': '.github/workflows/other.yml'},
        ]}
        with patch('ci_snapshot.api_json', return_value=runs):
            self.assertIsNone(latest_success(self.fixture.root, 'owner/repo', 3, 'token'))

    def test_rejects_unsafe_and_corrupt_zip(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('../unsafe', 'x')
        payload = stream.getvalue()
        metadata = {'id': 1, 'digest': 'sha256:' + hashlib.sha256(payload).hexdigest()}
        with patch('ci_snapshot.api', return_value=(payload, {})):
            with self.assertRaisesRegex(PipelineError, 'Unsafe'):
                unpack_artifact('owner/repo', metadata, 'token', self.state)
        metadata['digest'] = 'sha256:' + '0' * 64
        with patch('ci_snapshot.api', return_value=(payload, {})):
            with self.assertRaisesRegex(PipelineError, 'digest mismatch'):
                unpack_artifact('owner/repo', metadata, 'token', self.state)


class WorkflowTests(unittest.TestCase):
    def test_actions_are_pinned_and_privileged_trigger_is_absent(self):
        workflow = (SOURCE_ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertNotIn('pull_request_target', workflow)
        uses = [line.split('uses:', 1)[1].strip().split('@', 1)[1].split()[0]
                for line in workflow.splitlines() if 'uses:' in line]
        self.assertTrue(uses)
        self.assertTrue(all(len(revision) == 40
                            and all(character in '0123456789abcdef' for character in revision)
                            for revision in uses))

    def test_workflow_has_dynamic_matrix_receipt_and_required_gate(self):
        workflow = (SOURCE_ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        for text in ('fromJSON(needs.plan.outputs.matrix)', 'receipt-check',
                     "github.event_name == 'push'", "github.ref == 'refs/heads/main'",
                     'if: always()', 'required-gate', 'cache-mode: read',
                     'trusted-snapshot', 'tools/ci_snapshot.py download'):
            self.assertIn(text, workflow)
        self.assertNotIn('echo "- Reason: ${{ matrix.reason }}"', workflow)


if __name__ == '__main__':
    unittest.main()

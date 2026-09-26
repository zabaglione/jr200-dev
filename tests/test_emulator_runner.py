# SPDX-License-Identifier: BSD-3-Clause
import base64
import hashlib
import json
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from emulator_runner import (MAX_CYCLES, RunnerError, expand_replay_profile, load_lock, run,
                             validate_expectations, verify_bundle)
from png_rgba import encode_rgba


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / 'templates/minimal'
CAPTURE_PIXELS = bytes(320 * 224 * 4)
CAPTURE_PNG = encode_rgba(320, 224, CAPTURE_PIXELS)
CAPTURE_SHA256 = hashlib.sha256(CAPTURE_PIXELS).hexdigest()


def make_cjr(payload=b'\x01\x39', start=0x1000):
    name = b'JR200-MINIMAL'.ljust(16, b'\0')
    header = bytearray(b'\x02\x2a\x00\x1a\xff\xff' + name + b'\x01\x00' + b'\xff' * 8)
    header.append(sum(header) & 0xff)
    block = bytearray((2, 0x2a, 1, len(payload), start >> 8, start & 0xff))
    block.extend(payload)
    block.append(sum(block) & 0xff)
    end = start + len(payload)
    return bytes(header + block + bytes((2, 0x2a, 0xff, 0xff, end >> 8, end & 0xff)))


class RunnerFixture:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / 'project'
        shutil.copytree(TEMPLATE, self.project, ignore=shutil.ignore_patterns('build'))
        (self.project / 'build').mkdir()
        (self.project / 'build/minimal.cjr').write_bytes(make_cjr())
        self.bundle = self.root / 'bundle'
        self.bundle.mkdir()
        files = {'jr200_codec.mjs': b'fake module', 'jr200_codec.wasm': b'fake wasm'}
        for name, payload in files.items():
            (self.bundle / name).write_bytes(payload)
        lock = json.loads((ROOT / 'emulator.lock.json').read_text(encoding='utf-8'))
        lock['module_files'] = [
            {'path': name, 'size': len(payload),
             'sha256': hashlib.sha256(payload).hexdigest()}
            for name, payload in files.items()
        ]
        self.lock = self.root / 'emulator.lock.json'
        self.lock.write_text(json.dumps(lock, indent=2) + '\n', encoding='utf-8')
        self.node = self.root / 'fake-node'
        self.node.write_text(
            '#!/usr/bin/env python3\n'
            'import base64, json, pathlib, sys\n'
            'if sys.argv[1:] == ["--version"]:\n'
            '    print("v20.11.1")\n'
            '    raise SystemExit(0)\n'
            'args = dict(zip(sys.argv[2::2], sys.argv[3::2]))\n'
            'request = json.loads(pathlib.Path(args["--request"]).read_text())\n'
            'memory = {item["name"]: "0139" for item in request["observations"]}\n'
            f'framebuffer = {"0" * 64!r}\n'
            'if "--screenshot" in args:\n'
            f'    pathlib.Path(args["--screenshot"]).write_bytes(base64.b64decode({base64.b64encode(CAPTURE_PNG).decode()!r}))\n'
            f'    framebuffer = {CAPTURE_SHA256!r}\n'
            'result = {\n'
            ' "schema_version":1, "runner_contract_version":1,\n'
            ' "runner_version":"0.3.0", "status":"passed",\n'
            ' "profile":request["profile"], "mode":request["mode"],\n'
            ' "evidence":"emulator",\n'
            ' "artifact_sha256":request["artifact"]["sha256"],\n'
            ' "elapsed_cycles":11,\n'
            ' "stop":{"reason":"breakpoint","address":request["return_address"]},\n'
            ' "registers":{"pc":request["return_address"],"sp":2,"x":0,"a":0,"b":0,"cc":208,"waiting":0},\n'
            ' "memory":memory, "framebuffer_sha256":framebuffer,\n'
            ' "pcm":{"frames":0,"nonzero_frames":0,"peak":0,"sha256":"0"*64,"dropped_low":0,"dropped_high":0},\n'
            ' "cassette":{"state":0,"mode":0,"remote":False,"read_started":False},\n'
            ' "hardware":"not_run"}\n'
            'pathlib.Path(args["--result"]).write_text(json.dumps(result))\n'
            'print("Runner result: passed")\n',
            encoding='utf-8')
        self.node.chmod(self.node.stat().st_mode | stat.S_IXUSR)

    def close(self):
        self.temporary.cleanup()


class LockTests(unittest.TestCase):
    def setUp(self):
        self.fixture = RunnerFixture()

    def tearDown(self):
        self.fixture.close()

    def test_locked_bundle_is_verified(self):
        lock = load_lock(self.fixture.lock)
        report = verify_bundle(self.fixture.bundle, lock)
        self.assertEqual(len(report['files']), 2)

    def test_current_lock_records_verified_macos_runtime(self):
        lock = load_lock(ROOT / 'emulator.lock.json')
        macos = next(item for item in lock['hosts']
                     if item['os'] == 'macos' and item['arch'] == 'arm64')
        self.assertEqual(macos['status'], 'verified')
        self.assertEqual(lock['build']['system_api_version'], 9)

    def test_wrong_bundle_digest_is_rejected(self):
        (self.fixture.bundle / 'jr200_codec.wasm').write_bytes(b'changed')
        with self.assertRaisesRegex(RunnerError, 'does not match lock'):
            verify_bundle(self.fixture.bundle, load_lock(self.fixture.lock))

    def test_incompatible_system_api_is_rejected(self):
        lock = json.loads(self.fixture.lock.read_text(encoding='utf-8'))
        lock['build']['system_api_version'] = 10
        self.fixture.lock.write_text(json.dumps(lock), encoding='utf-8')
        with self.assertRaisesRegex(RunnerError, 'Invalid emulator build lock'):
            load_lock(self.fixture.lock)

    def test_runtime_timeout_is_reported(self):
        lock = json.loads(self.fixture.lock.read_text(encoding='utf-8'))
        lock['execution']['timeout_seconds'] = 1
        self.fixture.lock.write_text(json.dumps(lock), encoding='utf-8')
        self.fixture.node.write_text(
            '#!/usr/bin/env python3\n'
            'import sys, time\n'
            'if sys.argv[1:] == ["--version"]:\n'
            '    print("v20.11.1")\n'
            'else:\n'
            '    time.sleep(3)\n', encoding='utf-8')
        with self.assertRaisesRegex(RunnerError, 'wall-clock timeout'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)

    def test_runtime_expectation_mismatch_is_reported(self):
        path = self.fixture.project / 'tests/expectations.json'
        expectations = json.loads(path.read_text(encoding='utf-8'))
        expectations['runtime']['profiles'][0]['expect']['framebuffer_sha256'] = 'f' * 64
        path.write_text(json.dumps(expectations), encoding='utf-8')
        with self.assertRaisesRegex(RunnerError, 'framebuffer expectation failed'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)

    def test_pcm_minimum_peak_is_enforced(self):
        path = self.fixture.project / 'tests/expectations.json'
        expectations = json.loads(path.read_text(encoding='utf-8'))
        pcm = {'minimum_frames': 0, 'minimum_nonzero_frames': 0,
               'maximum_dropped_frames': 0}
        expectations['runtime']['profiles'][0]['expect']['pcm'] = pcm
        path.write_text(json.dumps(expectations), encoding='utf-8')
        run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
            ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)
        pcm['minimum_peak'] = 21000
        path.write_text(json.dumps(expectations), encoding='utf-8')
        with self.assertRaisesRegex(RunnerError, 'PCM expectation failed'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)
        pcm['minimum_peak'] = 40000
        path.write_text(json.dumps(expectations), encoding='utf-8')
        with self.assertRaisesRegex(RunnerError, 'Invalid expected PCM'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)

    def test_synthetic_contract_runs_and_writes_bounded_report(self):
        report = run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                     ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock)
        self.assertEqual(report['verification'], {
            'emulator': 'passed', 'rom': 'not_used',
            'cassette_path': 'memory_injection', 'hardware': 'not_run'})
        self.assertEqual(report['result']['registers']['pc'], 0x7ff0)
        stored = json.loads((self.fixture.project / 'build/runtime-report.json').read_text())
        self.assertEqual(stored, report)
        profiled = json.loads((self.fixture.project /
                               'build/runtime-reports/synthetic-ci.json').read_text())
        self.assertEqual(profiled, report)

    def test_synthetic_capture_is_verified_before_destination_write(self):
        screenshot = self.fixture.root / 'capture.png'
        report = run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                     ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock,
                     screenshot=screenshot)
        self.assertEqual(report['result']['framebuffer_sha256'], CAPTURE_SHA256)
        self.assertEqual(screenshot.read_bytes(), CAPTURE_PNG)
        with self.assertRaisesRegex(RunnerError, 'overwrite'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock,
                screenshot=screenshot)

    def test_capture_refuses_symlink_destination(self):
        screenshot = self.fixture.root / 'linked.png'
        screenshot.symlink_to(self.fixture.root / 'missing-target.png')
        with self.assertRaisesRegex(RunnerError, 'symlink'):
            run(self.fixture.project, self.fixture.bundle, str(self.fixture.node),
                ROOT / 'tools/jr200_wasm_runner.mjs', self.fixture.lock,
                screenshot=screenshot)

    def test_expectation_length_mismatch_is_rejected(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        expectations['runtime']['profiles'][0]['expect']['memory']['program'] = '01'
        with self.assertRaisesRegex(RunnerError, 'length'):
            validate_expectations(expectations, 0x1000)

    def test_text_replay_expands_to_bounded_key_events(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        profile = expectations['runtime']['profiles'][0]
        profile['replay'] = [{
            'kind': 'text', 'cycle': 100, 'text': 'a\r',
            'key_duration': 20, 'key_interval': 50,
        }]
        checked = validate_expectations(expectations, 0x1000)
        self.assertEqual(checked['replay'], [
            {'kind': 'key', 'cycle': 100, 'code': 0x61, 'pressed': True},
            {'kind': 'key', 'cycle': 120, 'code': 0x61, 'pressed': False},
            {'kind': 'key', 'cycle': 150, 'code': 0x0d, 'pressed': True},
            {'kind': 'key', 'cycle': 170, 'code': 0x0d, 'pressed': False},
        ])

    def test_cycle_limit_covers_large_rom_cassette_profiles(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        profile = expectations['runtime']['profiles'][0]
        profile['max_cycles'] = MAX_CYCLES
        self.assertEqual(
            validate_expectations(expectations, 0x1000)['max_cycles'],
            MAX_CYCLES)
        profile['max_cycles'] = MAX_CYCLES + 1
        with self.assertRaisesRegex(RunnerError, 'expectation contract'):
            validate_expectations(expectations, 0x1000)

    def test_rom_gallery_replay_reuses_bounded_synthetic_input(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        synthetic, rom = expectations['runtime']['profiles']
        synthetic['replay'] = [
            {'kind': 'key', 'cycle': 100, 'code': '0x20', 'pressed': True},
            {'kind': 'key', 'cycle': 200, 'code': '0x20', 'pressed': False},
        ]
        rom['replay_from'] = 'synthetic-ci'
        rom['replay_offset'] = 6_000_000
        checked = validate_expectations(expectations, 0x1000, 'local-rom-mload')
        self.assertEqual(checked['replay'][-2:], [
            {'kind': 'key', 'cycle': 6_000_100, 'code': 0x20, 'pressed': True},
            {'kind': 'key', 'cycle': 6_000_200, 'code': 0x20, 'pressed': False},
        ])
        rom['replay_offset'] = 15_000_000
        with self.assertRaisesRegex(RunnerError, 'cycle limit'):
            validate_expectations(expectations, 0x1000, 'local-rom-mload')
        rom['replay_offset'] = 6_000_000
        rom['replay_from'] = 'missing-profile'
        with self.assertRaisesRegex(RunnerError, 'synthetic source'):
            validate_expectations(expectations, 0x1000, 'local-rom-mload')

    def test_replay_reference_rejects_malformed_source_without_crashing(self):
        source = {'mode': 'synthetic-injection', 'replay': [{'kind': 'key'}]}
        target = {'profile': 'gallery', 'mode': 'rom-cassette', 'max_cycles': 100,
                  'return_address': '0x7ff0', 'replay': [], 'observations': [],
                  'breakpoints': [], 'expect': {}, 'replay_from': 'source',
                  'replay_offset': 10}
        with self.assertRaisesRegex(RunnerError, 'Invalid referenced replay'):
            expand_replay_profile(target, {'source': source})

    def test_joystick_replay_normalizes_active_low_state(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        profile = expectations['runtime']['profiles'][0]
        profile['replay'] = [
            {'kind': 'joystick', 'cycle': 100, 'player': 0, 'state': '0xea'},
            {'kind': 'joystick', 'cycle': 100, 'player': 1, 'state': '0xd5'},
        ]
        checked = validate_expectations(expectations, 0x1000)
        self.assertEqual(checked['replay'], [
            {'kind': 'joystick', 'cycle': 100, 'player': 0, 'state': 0xea},
            {'kind': 'joystick', 'cycle': 100, 'player': 1, 'state': 0xd5},
        ])

    def test_invalid_joystick_replay_is_rejected(self):
        expectations = json.loads(
            (self.fixture.project / 'tests/expectations.json').read_text())
        profile = expectations['runtime']['profiles'][0]
        profile['replay'] = [
            {'kind': 'joystick', 'cycle': 100, 'player': 2, 'state': '0xff'},
        ]
        with self.assertRaisesRegex(RunnerError, 'joystick'):
            validate_expectations(expectations, 0x1000)


if __name__ == '__main__':
    unittest.main()

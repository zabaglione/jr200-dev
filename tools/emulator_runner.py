#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Verify and invoke the fixed JR-200 Web Emulator WASM runner bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import sys
import tempfile
from typing import Any

from game_project import ProjectError, address, parse_cjr, validate_project
from jrasm_tool import sha256_file
from png_rgba import PngError, decode_rgba


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / 'emulator.lock.json'
DEFAULT_RULES = ROOT / 'rules/jr200.json'
DEFAULT_NODE_RUNNER = ROOT / 'tools/jr200_wasm_runner.mjs'
VERSION = re.compile(r'(\d+)\.(\d+)\.(\d+)')
HEX64 = re.compile(r'[0-9a-f]{64}')
SAFE_NAME = re.compile(r'[a-z][a-z0-9_-]{0,31}')
MAX_CYCLES = 250_000_000


class RunnerError(ValueError):
    """Expected runner contract, bundle, request, or result failure."""


def read_json(path: Path, description: str) -> Any:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise RunnerError(f'Cannot read {description}: {path}: {exc}') from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def validate_lock(value: Any) -> dict[str, Any]:
    fields = {'schema_version', 'runner_contract_version', 'runner_version', 'source',
              'build', 'module_files', 'notice_files', 'hosts', 'execution', 'evidence'}
    if not isinstance(value, dict) or set(value) != fields:
        raise RunnerError('Invalid emulator lock fields')
    if value['schema_version'] != 2 or value['runner_contract_version'] != 1:
        raise RunnerError('Unsupported emulator lock schema or contract')
    if not isinstance(value['runner_version'], str) or VERSION.fullmatch(
            value['runner_version']) is None:
        raise RunnerError('Invalid runner version')
    source = value['source']
    if (not isinstance(source, dict)
            or set(source) != {'repository', 'revision', 'availability',
                               'release_asset', 'release_sha256'}
            or source['repository'] != 'https://github.com/zabaglione/jr200-web-emulator'
            or not isinstance(source['revision'], str)
            or re.fullmatch(r'[0-9a-f]{40}', source['revision']) is None
            or source['availability'] not in ('local_build_only', 'release')
            or (source['availability'] == 'local_build_only'
                and (source['release_asset'] is not None
                     or source['release_sha256'] is not None))
            or (source['availability'] == 'release'
                and (not isinstance(source['release_asset'], str)
                     or not isinstance(source['release_sha256'], str)
                     or HEX64.fullmatch(source['release_sha256']) is None))):
        raise RunnerError('Invalid emulator source lock')
    build = value['build']
    if (not isinstance(build, dict)
            or set(build) != {'emulator_version', 'emscripten_version',
                              'codec_api_version', 'system_api_version'}
            or build['emulator_version'] != '0.0.1'
            or build['emscripten_version'] != '6.0.9'
            or build['codec_api_version'] != 1
            or build['system_api_version'] not in (6, 8, 9)):
        raise RunnerError('Invalid emulator build lock')
    module_files = value['module_files']
    if not isinstance(module_files, list) or len(module_files) != 2:
        raise RunnerError('Invalid emulator module file list')
    names = set()
    for item in module_files:
        if (not isinstance(item, dict) or set(item) != {'path', 'size', 'sha256'}
                or item['path'] not in ('jr200_codec.mjs', 'jr200_codec.wasm')
                or item['path'] in names or type(item['size']) is not int
                or item['size'] <= 0 or not isinstance(item['sha256'], str)
                or HEX64.fullmatch(item['sha256']) is None):
            raise RunnerError('Invalid emulator module file record')
        names.add(item['path'])
    if names != {'jr200_codec.mjs', 'jr200_codec.wasm'}:
        raise RunnerError('Incomplete emulator module file list')
    notice_files = value['notice_files']
    expected_notices = {'LICENSE.txt', 'THIRD_PARTY_NOTICES.md', 'SBOM.spdx.json',
                        'LICENSES/Emscripten-6.0.9.txt', 'LICENSES/VJR200.txt',
                        'LICENSES/MAME_BSD-3-Clause.txt',
                        'LICENSES/libcxxabi-6.0.9.txt'}
    if (not isinstance(notice_files, list) or len(notice_files) != len(expected_notices)
            or any(not isinstance(item, dict)
                   or set(item) != {'path', 'size', 'sha256'}
                   or item['path'] not in expected_notices
                   or type(item['size']) is not int or item['size'] <= 0
                   or not isinstance(item['sha256'], str)
                   or HEX64.fullmatch(item['sha256']) is None
                   for item in notice_files)
            or {item['path'] for item in notice_files} != expected_notices):
        raise RunnerError('Invalid emulator notice file list')
    hosts = value['hosts']
    if (not isinstance(hosts, list) or not hosts
            or any(not isinstance(item, dict)
                   or set(item) != {'os', 'arch', 'status'}
                   or item['os'] not in ('macos', 'linux')
                   or item['arch'] not in ('arm64', 'x86_64')
                   or item['status'] not in ('verified', 'contract_only')
                   for item in hosts)):
        raise RunnerError('Invalid emulator host list')
    execution = value['execution']
    expected_codes = {'success': 0, 'invalid_request': 2, 'missing_asset': 3,
                      'timeout': 4, 'incompatible_runner': 5,
                      'expectation_failed': 6, 'internal_error': 7}
    if (not isinstance(execution, dict)
            or set(execution) != {'node_minimum', 'request_format', 'result_format',
                                  'timeout_seconds', 'exit_codes'}
            or VERSION.fullmatch(str(execution['node_minimum'])) is None
            or execution['request_format'] != 'jr200-runner-request-v1'
            or execution['result_format'] != 'jr200-runner-result-v1'
            or type(execution['timeout_seconds']) is not int
            or not 1 <= execution['timeout_seconds'] <= 120
            or execution['exit_codes'] != expected_codes):
        raise RunnerError('Invalid emulator execution contract')
    if value['evidence'] != {'synthetic_injection': 'emulator',
                             'rom_cassette': 'emulator_with_local_rom',
                             'hardware': 'not_run'}:
        raise RunnerError('Invalid emulator evidence contract')
    return value


def load_lock(path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    return validate_lock(read_json(path, 'emulator lock'))


def verify_bundle(bundle: Path, lock: dict[str, Any]) -> dict[str, Any]:
    bundle = bundle.resolve()
    if not bundle.is_dir():
        raise RunnerError(f'Emulator bundle directory was not found: {bundle}')
    report = {'source_revision': lock['source']['revision'], 'files': []}
    for item in lock['module_files']:
        relative = PurePosixPath(item['path'])
        if relative.is_absolute() or '..' in relative.parts or len(relative.parts) != 1:
            raise RunnerError('Unsafe module path in emulator lock')
        path = bundle / item['path']
        if (not path.is_file() or path.is_symlink()
                or path.stat().st_size != item['size']
                or sha256_file(path) != item['sha256']):
            raise RunnerError(f'Emulator bundle file does not match lock: {item["path"]}')
        report['files'].append(dict(item))
    return report


def node_version(node: str, minimum: str) -> str:
    try:
        completed = subprocess.run([node, '--version'], capture_output=True, text=True,
                                   check=False, timeout=10)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RunnerError(f'Cannot run Node.js: {exc}') from exc
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)\s*', completed.stdout)
    required = tuple(int(part) for part in minimum.split('.'))
    if completed.returncode != 0 or match is None:
        raise RunnerError('Cannot determine Node.js version')
    actual = tuple(int(match.group(index)) for index in range(1, 4))
    if actual < required:
        raise RunnerError(f'Node.js {minimum} or newer is required')
    return '.'.join(str(part) for part in actual)


def validate_runtime_profile(runtime: Any) -> dict[str, Any]:
    fields = {'profile', 'mode', 'max_cycles', 'return_address', 'replay',
              'observations', 'breakpoints', 'expect'}
    if (not isinstance(runtime, dict) or set(runtime) != fields
            or not isinstance(runtime['profile'], str)
            or SAFE_NAME.fullmatch(runtime['profile']) is None
            or runtime['mode'] not in ('synthetic-injection', 'rom-cassette')
            or type(runtime['max_cycles']) is not int
            or not 1 <= runtime['max_cycles'] <= MAX_CYCLES):
        raise RunnerError('Invalid runtime expectation contract')
    return_address = address(runtime['return_address'], 'runtime return address')
    breakpoints = [address(item, 'runtime breakpoint') for item in runtime['breakpoints']]
    replay = []
    previous = -1
    for item in runtime['replay']:
        if (not isinstance(item, dict)
                or item.get('kind') not in ('key', 'nmi', 'text', 'joystick')
                or type(item.get('cycle')) is not int):
            raise RunnerError('Invalid runtime replay')
        if item['kind'] == 'key':
            if (set(item) != {'kind', 'cycle', 'code', 'pressed'}
                    or not isinstance(item['code'], str)
                    or re.fullmatch(r'0x[0-9a-fA-F]{2}', item['code']) is None
                    or type(item['pressed']) is not bool):
                raise RunnerError('Invalid runtime key event')
            events = [{'kind': 'key', 'cycle': item['cycle'],
                       'code': int(item['code'], 16), 'pressed': item['pressed']}]
        elif item['kind'] == 'nmi':
            if set(item) != {'kind', 'cycle'}:
                raise RunnerError('Invalid runtime NMI event')
            events = [{'kind': 'nmi', 'cycle': item['cycle']}]
        elif item['kind'] == 'joystick':
            if (set(item) != {'kind', 'cycle', 'player', 'state'}
                    or type(item['player']) is not int
                    or item['player'] not in (0, 1)
                    or not isinstance(item['state'], str)
                    or re.fullmatch(r'0x[0-9a-fA-F]{2}', item['state']) is None):
                raise RunnerError('Invalid runtime joystick event')
            events = [{'kind': 'joystick', 'cycle': item['cycle'],
                       'player': item['player'], 'state': int(item['state'], 16)}]
        else:
            if (set(item) != {'kind', 'cycle', 'text', 'key_duration', 'key_interval'}
                    or not isinstance(item['text'], str)
                    or not 1 <= len(item['text']) <= 64
                    or any(ord(character) not in (*range(0x20, 0x7f), 0x0d)
                           for character in item['text'])
                    or type(item['key_duration']) is not int
                    or type(item['key_interval']) is not int
                    or not 1 <= item['key_duration'] < item['key_interval']):
                raise RunnerError('Invalid runtime text event')
            events = []
            for index, character in enumerate(item['text']):
                pressed = item['cycle'] + index * item['key_interval']
                events.extend((
                    {'kind': 'key', 'cycle': pressed,
                     'code': ord(character), 'pressed': True},
                    {'kind': 'key', 'cycle': pressed + item['key_duration'],
                     'code': ord(character), 'pressed': False},
                ))
        if (not events or events[0]['cycle'] < previous
                or events[-1]['cycle'] > runtime['max_cycles']):
            raise RunnerError('Runtime replay is unsorted or exceeds the cycle limit')
        replay.extend(events)
        previous = events[-1]['cycle']
    observations = []
    names = set()
    for item in runtime['observations']:
        if (not isinstance(item, dict) or set(item) != {'name', 'address', 'length'}
                or not isinstance(item['name'], str) or SAFE_NAME.fullmatch(item['name']) is None
                or item['name'] in names or type(item['length']) is not int
                or not 1 <= item['length'] <= 4096):
            raise RunnerError('Invalid runtime observation')
        location = address(item['address'], 'runtime observation address')
        if location + item['length'] > 0x10000:
            raise RunnerError('Runtime observation leaves memory')
        names.add(item['name'])
        observations.append({'name': item['name'], 'address': location,
                             'length': item['length']})
    expect = runtime['expect']
    if (not isinstance(expect, dict)
            or set(expect) != {'stop_reason', 'pc', 'memory', 'framebuffer_sha256',
                               'pcm', 'cassette'}
            or expect['stop_reason'] not in ('breakpoint', 'cycle-limit')
            or (expect['pc'] is not None and
                (not isinstance(expect['pc'], str)
                 or re.fullmatch(r'0x[0-9a-fA-F]{1,4}', expect['pc']) is None))
            or not isinstance(expect['memory'], dict)
            or not set(expect['memory']).issubset(names)
            or (expect['framebuffer_sha256'] is not None
                and (not isinstance(expect['framebuffer_sha256'], str)
                     or HEX64.fullmatch(expect['framebuffer_sha256']) is None))):
        raise RunnerError('Invalid runtime expected result')
    pcm = expect['pcm']
    if pcm is not None:
        if (not isinstance(pcm, dict)
                or set(pcm) != {'minimum_frames', 'minimum_nonzero_frames',
                                'maximum_dropped_frames'}
                or any(type(pcm[field]) is not int or pcm[field] < 0
                       for field in pcm)
                or pcm['minimum_nonzero_frames'] > pcm['minimum_frames']):
            raise RunnerError('Invalid expected PCM result')
    cassette = expect['cassette']
    if cassette is not None:
        if (not isinstance(cassette, dict)
                or set(cassette) != {'state', 'mode', 'remote'}
                or type(cassette['state']) is not int
                or not 0 <= cassette['state'] <= 7
                or type(cassette['mode']) is not int
                or not 0 <= cassette['mode'] <= 2
                or type(cassette['remote']) is not bool):
            raise RunnerError('Invalid expected cassette state')
    if runtime['mode'] == 'rom-cassette' and cassette is None:
        raise RunnerError('ROM cassette profile requires a cassette expectation')
    expected_memory = {}
    for name, payload in expect['memory'].items():
        if not isinstance(payload, str) or re.fullmatch(r'(?:[0-9a-f]{2})+', payload) is None:
            raise RunnerError('Invalid expected memory bytes')
        length = next(item['length'] for item in observations if item['name'] == name)
        if len(payload) != length * 2:
            raise RunnerError('Expected memory length does not match observation')
        expected_memory[name] = payload
    return {
        'profile': runtime['profile'],
        'mode': runtime['mode'],
        'max_cycles': runtime['max_cycles'],
        'return_address': return_address,
        'replay': replay,
        'observations': observations,
        'breakpoints': breakpoints,
        'expect': {'stop_reason': expect['stop_reason'],
                   'pc': (None if expect['pc'] is None
                          else address(expect['pc'], 'expected PC')),
                   'memory': expected_memory,
                   'framebuffer_sha256': expect['framebuffer_sha256'],
                   'pcm': pcm,
                   'cassette': cassette},
    }


def validate_expectations(value: Any, entry: int,
                          profile: str | None = None) -> dict[str, Any]:
    if (not isinstance(value, dict)
            or set(value) != {'schema_version', 'expected_entry_address', 'runtime', 'notes'}
            or value['schema_version'] != 2
            or address(value['expected_entry_address'], 'expected entry address') != entry
            or not isinstance(value['notes'], str) or not value['notes']):
        raise RunnerError('Invalid target expectations')
    runtime = value['runtime']
    if (not isinstance(runtime, dict)
            or set(runtime) != {'default_profile', 'profiles'}
            or not isinstance(runtime['default_profile'], str)
            or SAFE_NAME.fullmatch(runtime['default_profile']) is None
            or not isinstance(runtime['profiles'], list)
            or not runtime['profiles']):
        raise RunnerError('Invalid runtime profile collection')
    profiles: dict[str, dict[str, Any]] = {}
    for item in runtime['profiles']:
        checked = validate_runtime_profile(item)
        if checked['profile'] in profiles:
            raise RunnerError(f'Duplicate runtime profile: {checked["profile"]}')
        profiles[checked['profile']] = checked
    if runtime['default_profile'] not in profiles:
        raise RunnerError('Default runtime profile is missing')
    selected = profile or runtime['default_profile']
    if selected not in profiles:
        raise RunnerError(f'Unknown runtime profile: {selected}')
    return profiles[selected]


def request_for_project(project: Path, artifact: Path, profile: str | None,
                        rom: Path | None, font: Path | None) -> tuple[dict[str, Any], dict[str, Any]]:
    try:
        spec = validate_project(project, DEFAULT_RULES)
        parsed = parse_cjr(artifact.read_bytes())
    except (ProjectError, OSError) as exc:
        raise RunnerError(str(exc)) from exc
    entry = address(spec.config['entry_address'], 'entry address')
    runtime = validate_expectations(
        read_json(spec.project / 'tests/expectations.json', 'target expectations'),
        entry, profile)
    if runtime['mode'] == 'synthetic-injection':
        if rom is not None or font is not None:
            raise RunnerError('Synthetic runtime does not accept ROM or font assets')
        assets = {}
        segments = [{'address': block.start, 'bytes': block.data.hex()}
                    for block in parsed['blocks']]
    else:
        if rom is None or font is None:
            raise RunnerError('ROM cassette runtime requires --rom and --font')
        assets = {'rom_path': str(rom.resolve()), 'font_path': str(font.resolve())}
        segments = []
    request = {
        'schema_version': 1,
        'runner_contract_version': 1,
        'profile': runtime['profile'],
        'mode': runtime['mode'],
        'artifact': {'path': str(artifact.resolve()), 'sha256': sha256_file(artifact)},
        'entry_address': entry,
        'max_cycles': runtime['max_cycles'],
        'return_address': runtime['return_address'],
        'segments': segments,
        'replay': runtime['replay'],
        'observations': runtime['observations'],
        'breakpoints': runtime['breakpoints'],
        'assets': assets,
    }
    return request, runtime


def validate_result(value: Any, request: dict[str, Any], runtime: dict[str, Any],
                    lock: dict[str, Any]) -> dict[str, Any]:
    fields = {'schema_version', 'runner_contract_version', 'runner_version', 'status',
              'profile', 'mode', 'evidence', 'artifact_sha256', 'elapsed_cycles',
              'stop', 'registers', 'memory', 'framebuffer_sha256', 'pcm',
              'cassette', 'hardware'}
    if (not isinstance(value, dict) or set(value) != fields
            or value['schema_version'] != 1
            or value['runner_contract_version'] != lock['runner_contract_version']
            or value['runner_version'] != lock['runner_version']
            or value['status'] != 'passed'
            or value['profile'] != request['profile']
            or value['mode'] != request['mode']
            or value['artifact_sha256'] != request['artifact']['sha256']
            or value['hardware'] != 'not_run'
            or not isinstance(value['elapsed_cycles'], int)
            or not 0 < value['elapsed_cycles'] <= request['max_cycles'] + 64
            or not isinstance(value['framebuffer_sha256'], str)
            or HEX64.fullmatch(value['framebuffer_sha256']) is None):
        raise RunnerError('Runner result does not match request contract')
    pcm_result = value['pcm']
    if (not isinstance(pcm_result, dict)
            or set(pcm_result) != {'frames', 'nonzero_frames', 'peak', 'sha256',
                                   'dropped_low', 'dropped_high'}
            or any(type(pcm_result[field]) is not int or pcm_result[field] < 0
                   for field in ('frames', 'nonzero_frames', 'peak',
                                 'dropped_low', 'dropped_high'))
            or pcm_result['nonzero_frames'] > pcm_result['frames']
            or pcm_result['peak'] > 32768
            or not isinstance(pcm_result['sha256'], str)
            or HEX64.fullmatch(pcm_result['sha256']) is None):
        raise RunnerError('Invalid runner PCM result')
    expected_evidence = lock['evidence'][request['mode'].replace('-', '_')]
    if value['evidence'] != expected_evidence:
        raise RunnerError('Runner evidence class does not match mode')
    if not isinstance(value['stop'], dict):
        raise RunnerError('Runtime stop result is missing')
    actual_reason = value['stop'].get('reason')
    actual_pc = value['registers'].get('pc')
    expected_reason = runtime['expect']['stop_reason']
    expected_pc = runtime['expect']['pc']
    if (actual_reason != expected_reason
            or (expected_pc is not None and actual_pc != expected_pc)):
        shown_pc = '<missing>' if actual_pc is None else f'0x{actual_pc:04x}'
        wanted_pc = '<any>' if expected_pc is None else f'0x{expected_pc:04x}'
        raise RunnerError(
            f'Runtime stop or PC expectation failed: reason={actual_reason!r} '
            f'pc={shown_pc}, expected reason={expected_reason!r} pc={wanted_pc}')
    if not isinstance(value['memory'], dict):
        raise RunnerError('Runtime memory result is missing')
    for name, expected in runtime['expect']['memory'].items():
        actual = value['memory'].get(name)
        if actual != expected:
            raise RunnerError(
                f'Runtime memory expectation failed: {name}: '
                f'actual={actual!r} expected={expected!r}')
    expected_framebuffer = runtime['expect']['framebuffer_sha256']
    if (expected_framebuffer is not None
            and value['framebuffer_sha256'] != expected_framebuffer):
        raise RunnerError('Runtime framebuffer expectation failed')
    expected_pcm = runtime['expect']['pcm']
    if expected_pcm is not None:
        dropped = pcm_result['dropped_low'] + (pcm_result['dropped_high'] << 32)
        if (pcm_result['frames'] < expected_pcm['minimum_frames']
                or pcm_result['nonzero_frames'] < expected_pcm['minimum_nonzero_frames']
                or dropped > expected_pcm['maximum_dropped_frames']):
            raise RunnerError('Runtime PCM expectation failed')
    cassette = runtime['expect']['cassette']
    if cassette is not None and any(value['cassette'].get(key) != expected
                                    for key, expected in cassette.items()):
        raise RunnerError('Runtime cassette expectation failed')
    return value


def run(project: Path, bundle: Path, node: str, runner: Path, lock_path: Path,
        artifact: Path | None = None, profile: str | None = None,
        rom: Path | None = None, font: Path | None = None,
        screenshot: Path | None = None) -> dict[str, Any]:
    lock = load_lock(lock_path)
    bundle_report = verify_bundle(bundle, lock)
    actual_node = node_version(node, lock['execution']['node_minimum'])
    project = project.resolve()
    if artifact is None:
        try:
            spec = validate_project(project, DEFAULT_RULES)
        except ProjectError as exc:
            raise RunnerError(str(exc)) from exc
        artifact = spec.output
    artifact = artifact.resolve()
    if not artifact.is_file():
        raise RunnerError(f'Built CJR was not found: {artifact}')
    request, runtime = request_for_project(project, artifact, profile, rom, font)
    screenshot_target = None
    if screenshot is not None:
        if screenshot.is_symlink():
            raise RunnerError('Refusing a screenshot symlink')
        screenshot_target = screenshot.resolve()
        if (request['mode'] != 'synthetic-injection'
                or screenshot_target.suffix.lower() != '.png'):
            raise RunnerError('PNG screenshots are restricted to synthetic mode')
        if screenshot_target.exists() or screenshot_target.is_symlink():
            raise RunnerError(f'Refusing to overwrite screenshot: {screenshot_target}')
        if (not screenshot_target.parent.is_dir()
                or screenshot_target.parent.is_symlink()):
            raise RunnerError('Screenshot parent must be an existing real directory')
    with tempfile.TemporaryDirectory(prefix='jr200-runner-') as temporary:
        temporary_path = Path(temporary)
        request_path = temporary_path / 'request.json'
        result_path = temporary_path / 'result.json'
        screenshot_path = temporary_path / 'framebuffer.png'
        write_json(request_path, request)
        command = [node, str(runner.resolve()), '--bundle', str(bundle.resolve()),
                   '--request', str(request_path), '--result', str(result_path),
                   '--system-api', str(lock['build']['system_api_version'])]
        if screenshot_target is not None:
            command.extend(('--screenshot', str(screenshot_path)))
        try:
            completed = subprocess.run(
                command,
                capture_output=True, text=True, check=False,
                timeout=lock['execution']['timeout_seconds'])
        except subprocess.TimeoutExpired as exc:
            raise RunnerError('Emulator runner exceeded the wall-clock timeout') from exc
        except (OSError, subprocess.SubprocessError) as exc:
            raise RunnerError(f'Cannot invoke emulator runner: {exc}') from exc
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip().splitlines()
            bounded = detail[-1][:240] if detail else 'no diagnostic'
            raise RunnerError(
                f'Emulator runner failed with exit {completed.returncode}: {bounded}')
        result = validate_result(read_json(result_path, 'runner result'), request,
                                 runtime, lock)
        if screenshot_target is not None:
            try:
                width, height, pixels = decode_rgba(screenshot_path.read_bytes())
            except (OSError, PngError) as exc:
                raise RunnerError(f'Invalid captured screenshot: {exc}') from exc
            if ((width, height) != (320, 224)
                    or hashlib.sha256(pixels).hexdigest()
                    != result['framebuffer_sha256']):
                raise RunnerError('Screenshot does not match the verified framebuffer')
            screenshot_path.replace(screenshot_target)
    report = {
        'schema_version': 1,
        'project': validate_project(project, DEFAULT_RULES).config['id'],
        'profile': result['profile'],
        'mode': result['mode'],
        'artifact_sha256': result['artifact_sha256'],
        'expectations_sha256': sha256_file(project / 'tests/expectations.json'),
        'runner': {
            'version': lock['runner_version'],
            'contract_version': lock['runner_contract_version'],
            'source_revision': lock['source']['revision'],
            'node_version': actual_node,
            'module_files': bundle_report['files'],
        },
        'result': result,
        'verification': {
            'emulator': 'passed',
            'rom': 'provided_locally' if result['mode'] == 'rom-cassette' else 'not_used',
            'cassette_path': ('normal' if result['mode'] == 'rom-cassette'
                              else 'memory_injection'),
            'hardware': 'not_run',
        },
    }
    write_json(project / 'build/runtime-report.json', report)
    write_json(project / 'build/runtime-reports' / (result['profile'] + '.json'), report)
    return report


def host_id() -> tuple[str, str]:
    os_name = {'Darwin': 'macos', 'Linux': 'linux'}.get(platform.system(), 'unsupported')
    arch = {'arm64': 'arm64', 'aarch64': 'arm64', 'x86_64': 'x86_64'}.get(
        platform.machine().lower(), 'unsupported')
    return os_name, arch


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--lock', type=Path, default=DEFAULT_LOCK)
    value.add_argument('--node', default=os.environ.get('NODE', 'node'))
    value.add_argument('--runner', type=Path, default=DEFAULT_NODE_RUNNER)
    commands = value.add_subparsers(dest='command', required=True)
    doctor = commands.add_parser('doctor')
    doctor.add_argument('--bundle', type=Path)
    run_command = commands.add_parser('run')
    run_command.add_argument('--project', type=Path, required=True)
    run_command.add_argument('--bundle', type=Path)
    run_command.add_argument('--artifact', type=Path)
    run_command.add_argument('--profile')
    run_command.add_argument('--rom', type=Path)
    run_command.add_argument('--font', type=Path)
    run_command.add_argument('--screenshot', type=Path)
    return value


def selected_bundle(argument: Path | None) -> Path:
    if argument is not None:
        return argument
    value = os.environ.get('JR200_RUNNER_BUNDLE')
    if value:
        return Path(value)
    raise RunnerError(
        'No emulator bundle is configured; pass --bundle or set JR200_RUNNER_BUNDLE')


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        lock = load_lock(args.lock)
        if args.command == 'doctor':
            version = node_version(args.node, lock['execution']['node_minimum'])
            bundle = selected_bundle(args.bundle)
            verify_bundle(bundle, lock)
            current_os, current_arch = host_id()
            host = next((item for item in lock['hosts']
                         if item['os'] == current_os and item['arch'] == current_arch), None)
            if host is None:
                raise RunnerError(f'Unsupported runner host: {current_os}-{current_arch}')
            print(f'Emulator runner doctor: OK (node {version}, {current_os}-{current_arch}, '
                  f'{host["status"]})')
            print(f'Emulator source revision: {lock["source"]["revision"]}')
        else:
            report = run(args.project, selected_bundle(args.bundle), args.node,
                         args.runner, args.lock, args.artifact, args.profile,
                         args.rom, args.font, args.screenshot)
            result = report['result']
            print(f'Emulator runtime: passed ({result["mode"]}, '
                  f'{result["elapsed_cycles"]} cycles)')
            print(f'Evidence: emulator={result["evidence"]} hardware=not_run')
    except (RunnerError, OSError, subprocess.SubprocessError) as exc:
        print(f'Emulator runner failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

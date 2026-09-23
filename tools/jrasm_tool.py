# SPDX-License-Identifier: BSD-3-Clause
"""Locate and validate the externally installed, revision-locked jrasm tool."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Mapping


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / 'toolchain.lock.json'


class ToolError(ValueError):
    """Expected tool configuration or execution failure."""


def validate_lock(value: Any, root: Path = ROOT) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {'schema_version', 'jrasm'}:
        raise ToolError('Toolchain lock requires schema_version and jrasm')
    if type(value['schema_version']) is not int or value['schema_version'] != 1:
        raise ToolError('Unsupported toolchain lock schema')
    item = value['jrasm']
    expected = {'repository', 'revision', 'version', 'banner', 'license',
                'redistribution', 'build', 'fixture'}
    if not isinstance(item, dict) or set(item) != expected:
        raise ToolError('Invalid jrasm lock fields')
    for field in ('repository', 'version', 'banner', 'license'):
        if not isinstance(item[field], str) or not item[field]:
            raise ToolError(f'Invalid jrasm {field}')
    if not item['repository'].startswith('https://github.com/'):
        raise ToolError('jrasm repository must use an HTTPS GitHub URL')
    if (not isinstance(item['revision'], str)
            or not re.fullmatch(r'[0-9a-f]{40}', item['revision'])):
        raise ToolError('jrasm revision must be a full lowercase commit SHA')
    if type(item['redistribution']) is not bool:
        raise ToolError('jrasm redistribution must be boolean')
    build = item['build']
    if (not isinstance(build, dict)
            or set(build) != {'cmake_minimum', 'platforms'}
            or not isinstance(build['cmake_minimum'], str)
            or not re.fullmatch(r'[0-9]+\.[0-9]+', build['cmake_minimum'])):
        raise ToolError('Invalid jrasm build configuration')
    platforms = build['platforms']
    if not isinstance(platforms, dict) or set(platforms) != {'Darwin', 'Linux'}:
        raise ToolError('jrasm build platforms must be Darwin and Linux')
    for name, config in platforms.items():
        if (not isinstance(config, dict) or set(config) != {'cxx_flags'}
                or not isinstance(config['cxx_flags'], list)
                or not all(isinstance(flag, str) and flag for flag in config['cxx_flags'])):
            raise ToolError(f'Invalid jrasm build configuration for {name}')
    fixture = item['fixture']
    fixture_fields = {'source', 'inputs', 'sha256', 'size', 'timeout_seconds'}
    if not isinstance(fixture, dict) or set(fixture) != fixture_fields:
        raise ToolError('Invalid jrasm fixture fields')
    source = fixture['source']
    if (not isinstance(source, str) or not source or source.startswith('/')
            or '\\' in source or '..' in source.split('/')):
        raise ToolError('Unsafe jrasm fixture source')
    inputs = fixture['inputs']
    if not isinstance(inputs, dict) or source not in inputs or not inputs:
        raise ToolError('jrasm fixture inputs must include its source')
    for path, digest in inputs.items():
        if (not isinstance(path, str) or not path or path.startswith('/')
                or '\\' in path or '..' in path.split('/')):
            raise ToolError('Unsafe jrasm fixture input')
        if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ToolError(f'Invalid jrasm fixture input SHA-256: {path}')
        input_path = root / path
        if not input_path.is_file():
            raise ToolError(f'Missing jrasm fixture input: {path}')
        if sha256_file(input_path) != digest:
            raise ToolError(f'jrasm fixture input SHA-256 mismatch: {path}')
    if (not isinstance(fixture['sha256'], str)
            or not re.fullmatch(r'[0-9a-f]{64}', fixture['sha256'])):
        raise ToolError('Invalid jrasm fixture SHA-256')
    if type(fixture['size']) is not int or fixture['size'] <= 0:
        raise ToolError('Invalid jrasm fixture size')
    timeout = fixture['timeout_seconds']
    if type(timeout) is not int or not 1 <= timeout <= 60:
        raise ToolError('Invalid jrasm fixture timeout')
    return item


def load_lock(path: Path = DEFAULT_LOCK, root: Path | None = None) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise ToolError(f'Cannot read toolchain lock: {exc}') from exc
    return validate_lock(value, root if root is not None else path.resolve().parent)


def resolve_executable(argument: str | None,
                       environ: Mapping[str, str] | None = None) -> Path:
    env = os.environ if environ is None else environ
    requested = argument or env.get('JRASM')
    if requested:
        expanded = str(Path(requested).expanduser())
        candidate = shutil.which(expanded, path=env.get('PATH'))
        if candidate is None and Path(expanded).is_file():
            candidate = expanded
        source = '--jrasm' if argument else 'JRASM'
        if candidate is None:
            raise ToolError(f'{source} executable was not found: {requested}')
    else:
        candidate = shutil.which('jrasm', path=env.get('PATH'))
        if candidate is None:
            raise ToolError('jrasm was not found; set JRASM or pass --jrasm')
    path = Path(candidate).resolve()
    if not path.is_file():
        raise ToolError(f'jrasm is not a regular file: {path}')
    if not os.access(path, os.X_OK):
        raise ToolError(f'jrasm is not executable: {path}')
    return path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def inspect(executable: Path, lock: dict[str, Any]) -> dict[str, Any]:
    try:
        result = subprocess.run(
            [str(executable)], check=False, capture_output=True, text=True,
            timeout=lock['fixture']['timeout_seconds'],
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ToolError(f'Cannot execute jrasm: {exc}') from exc
    output = result.stdout + result.stderr
    banner = next((line.strip() for line in output.splitlines()
                   if line.startswith('JR-200 Assembler ')), '')
    if banner != lock['banner']:
        shown = banner or '<missing>'
        raise ToolError(f'jrasm version mismatch: expected {lock["banner"]!r}, got {shown!r}')
    return {
        'path': str(executable),
        'sha256': sha256_file(executable),
        'banner': banner,
        'probe_exit_code': result.returncode,
    }


def verify_fixture(executable: Path, lock: dict[str, Any], root: Path) -> dict[str, Any]:
    source = (root / lock['fixture']['source']).resolve()
    with tempfile.TemporaryDirectory(prefix='jr200-jrasm-') as directory:
        output = Path(directory) / 'fixture output.cjr'
        try:
            result = subprocess.run(
                [str(executable), '-o', str(output), str(source)],
                check=False, capture_output=True, text=True,
                timeout=lock['fixture']['timeout_seconds'], cwd=root,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ToolError(f'Cannot assemble fixture: {exc}') from exc
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise ToolError(f'jrasm fixture failed with exit {result.returncode}: {detail}')
        if not output.is_file():
            raise ToolError('jrasm fixture did not create its requested output')
        size = output.stat().st_size
        digest = sha256_file(output)
    expected_size = lock['fixture']['size']
    expected_digest = lock['fixture']['sha256']
    if size != expected_size:
        raise ToolError(f'jrasm fixture size mismatch: expected {expected_size}, got {size}')
    if digest != expected_digest:
        raise ToolError(f'jrasm fixture SHA-256 mismatch: expected {expected_digest}, got {digest}')
    return {'source': str(source), 'size': size, 'sha256': digest}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--lock', type=Path, default=DEFAULT_LOCK)
    value.add_argument('--jrasm', help='jrasm executable; overrides JRASM and PATH')
    value.add_argument('command', choices=('doctor', 'verify-fixture'))
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        root = args.lock.resolve().parent
        lock = load_lock(args.lock, root)
        executable = resolve_executable(args.jrasm)
        report = inspect(executable, lock)
        fixture = verify_fixture(executable, lock, root) if args.command == 'verify-fixture' else None
    except ToolError as exc:
        print(f'jrasm check failed: {exc}', file=sys.stderr)
        return 1
    print('jrasm doctor: OK')
    print(f'Locked version: {lock["version"]}')
    print(f'Locked source revision: {lock["revision"]}')
    print(f'Executable: {report["path"]}')
    print(f'Executable SHA-256: {report["sha256"]}')
    print(f'Platform: {platform.system()} {platform.machine()}')
    if fixture is not None:
        print(f'Fixture: OK ({fixture["size"]} bytes, SHA-256 {fixture["sha256"]})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

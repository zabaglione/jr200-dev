# SPDX-License-Identifier: BSD-3-Clause
"""Build the locked external jrasm checkout without modifying its sources."""
from __future__ import annotations

import argparse
from pathlib import Path
import platform
import subprocess
import sys

from jrasm_tool import DEFAULT_LOCK, ToolError, load_lock


def source_revision(source: Path) -> str:
    try:
        return subprocess.check_output(
            ['git', '-C', str(source), 'rev-parse', 'HEAD'],
            stderr=subprocess.PIPE, text=True,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ToolError(f'Cannot read jrasm source revision: {exc}') from exc


def cmake_arguments(lock: dict, system: str, source: Path, build: Path) -> list[str]:
    try:
        flags = lock['build']['platforms'][system]['cxx_flags']
    except KeyError as exc:
        raise ToolError(f'Unsupported jrasm build platform: {system}') from exc
    args = ['cmake', '-S', str(source), '-B', str(build), '-DCMAKE_BUILD_TYPE=Release']
    if flags:
        args.append('-DCMAKE_CXX_FLAGS=' + ' '.join(flags))
    return args


def build_jrasm(source: Path, build: Path, lock: dict, system: str) -> Path:
    source = source.resolve()
    build = build.resolve()
    if not source.is_dir():
        raise ToolError(f'jrasm source directory was not found: {source}')
    revision = source_revision(source)
    if revision != lock['revision']:
        raise ToolError(f'jrasm source revision mismatch: expected {lock["revision"]}, got {revision}')
    try:
        subprocess.run(cmake_arguments(lock, system, source, build), check=True)
        subprocess.run(['cmake', '--build', str(build), '--parallel'], check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ToolError(f'jrasm build failed: {exc}') from exc
    executable = build / 'src/jrasm/jrasm'
    if not executable.is_file():
        raise ToolError(f'jrasm build did not create the expected executable: {executable}')
    return executable


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--lock', type=Path, default=DEFAULT_LOCK)
    value.add_argument('--source', type=Path, required=True,
                       help='locked upstream jrasm checkout')
    value.add_argument('--build-dir', type=Path,
                       help='build directory; defaults to SOURCE/build')
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        lock = load_lock(args.lock, args.lock.resolve().parent)
        build = args.build_dir if args.build_dir is not None else args.source / 'build'
        executable = build_jrasm(args.source, build, lock, platform.system())
    except ToolError as exc:
        print(f'jrasm build failed: {exc}', file=sys.stderr)
        return 1
    print(f'jrasm build: OK ({executable})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

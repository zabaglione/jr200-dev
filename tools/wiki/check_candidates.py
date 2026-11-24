#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check new catalog CJR candidates against builds from the PR checkout."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from game_project import ProjectError, build_project
from wiki.generate import ROOT, WikiError, catalog_entries


def candidates(root: Path, base: str) -> list[dict[str, Any]]:
    if re.fullmatch(r'[0-9a-f]{40}', base) is None:
        raise WikiError('Candidate validation requires the full PR base commit')
    previous = json.loads(subprocess.check_output(
        ['git', 'show', f'{base}:games/catalog.json'], cwd=root, timeout=20))
    fixed = {(entry['id'], entry['version'], entry['artifact_sha256'])
             for entry in previous['games'] if entry['status'] != 'draft'}
    return [entry for entry in catalog_entries(root)
            if entry['status'] != 'draft'
            and (entry['id'], entry['version'], entry['artifact_sha256']) not in fixed]


def check_cjr(root: Path, entry: dict[str, Any], jrasm: str) -> None:
    _, report = build_project(
        entry['_project'], jrasm, lock_path=root / 'toolchain.lock.json',
        rules_path=root / 'rules/jr200.json', repository_root=root)
    actual = report['artifact']['sha256']
    expected = entry['artifact_sha256']
    if actual != expected:
        raise WikiError(f"{entry['id']}: candidate CJR hash mismatch: "
                        f'expected {expected}, built {actual}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--base', required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--github-output', type=Path, help='report whether builds are needed')
    mode.add_argument('--jrasm', help='path to the locked assembler for candidate builds')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        selected = candidates(root, args.base)
        if args.github_output is not None:
            with args.github_output.open('a', encoding='utf-8') as stream:
                print(f'build_required={str(bool(selected)).lower()}', file=stream)
        for entry in selected:
            if args.jrasm is not None:
                check_cjr(root, entry, args.jrasm)
            action = 'verified' if args.jrasm is not None else 'selected'
            print(f"{entry['id']}@{entry['version']}: candidate CJR {action}")
        print(f'Candidate CJR count: {len(selected)}')
    except (WikiError, ProjectError, OSError, subprocess.SubprocessError,
            json.JSONDecodeError) as exc:
        print(f'Candidate CJR check failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

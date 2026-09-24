# SPDX-License-Identifier: BSD-3-Clause
"""Advisory changed-input selector; NOT a successful-build receipt checker."""
from __future__ import annotations

import argparse
from fnmatch import fnmatchcase
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

FIELDS = ('build_inputs', 'test_inputs', 'doc_inputs')
POLICY = ('ci/targets.json', '.github/workflows/**', 'tools/ci_plan.py',
          'tools/check_repository.py', 'tools/game_project.py',
          'tools/ci_pipeline.py', 'tests/**', 'rules/jr200.json',
          'mk/**', 'Makefile', 'toolchain.lock.json')
TEST_POLICY = ('ci/runner.lock.json', 'emulator.lock.json',
               'tools/emulator_runner.py', 'tools/jr200_wasm_runner.mjs',
               'tools/png_rgba.py')
DOCS = ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md',
        'docs/**', 'sdk/README.md', '.github/ISSUE_TEMPLATE/**',
        '.github/pull_request_template.md')
WIKI = ('tools/wiki/**', 'tools/web_export.py', 'games/catalog.json')
INFRA = ('.gitignore', '.gitattributes', '.editorconfig')
# Interactive local tools that neither build nor test targets.
LOCAL_TOOLS = ('tools/game_play.py', 'tools/capture_video.py', 'tools/jr200_capture.mjs')


def path_ok(value: str) -> bool:
    """Use POSIX relative paths; reject traversal, controls and Windows paths."""
    return (isinstance(value, str) and bool(value) and not value.startswith('/')
            and '\\' not in value and ':' not in value
            and not any(part in ('', '.', '..') for part in value.split('/'))
            and not any(ord(c) < 32 or ord(c) == 127 for c in value))


def matches(path: str, patterns: list[str] | tuple[str, ...]) -> bool:
    return any(fnmatchcase(path, pattern) for pattern in patterns)


def validate_registry(value: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(value, dict) or set(value) != {'schema_version', 'targets'}:
        raise ValueError('Registry requires schema_version and targets')
    version = value['schema_version']
    if type(version) is not int or version not in (1, 2):
        raise ValueError('Unsupported registry schema')
    if not isinstance(value['targets'], list):
        raise ValueError('targets must be an array')
    targets: dict[str, dict[str, Any]] = {}
    expected_v1 = {'id', 'kind', 'depends_on', *FIELDS}
    expected_v2 = {*expected_v1, 'project', 'runner'}
    for item in value['targets']:
        expected = expected_v1 if version == 1 else expected_v2
        if not isinstance(item, dict) or set(item) != expected:
            raise ValueError('Invalid target fields')
        name = item['id']
        if not isinstance(name, str) or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', name):
            raise ValueError('Invalid target ID')
        if name in targets or item['kind'] not in ('game', 'sample', 'sdk', 'tool'):
            raise ValueError('Duplicate target or invalid kind')
        normalized = dict(item)
        if version == 1:
            root = ('sdk/' if item['kind'] == 'sdk' else 'games/') + name
            normalized['project'] = root
            normalized['runner'] = 'legacy-unconfigured'
        else:
            if not path_ok(item['project']) or any(c in item['project'] for c in '*?['):
                raise ValueError(f'{name}: unsafe project path')
            if item['runner'] not in ('jr200-project', 'python'):
                raise ValueError(f'{name}: invalid runner')
        for key in (*FIELDS, 'depends_on'):
            seq = item[key]
            if not isinstance(seq, list) or not all(isinstance(p, str) for p in seq):
                raise ValueError(f'{name}: {key} must be a string array')
            if len(seq) != len(set(seq)):
                raise ValueError(f'{name}: duplicate {key}')
        if not item['build_inputs']:
            raise ValueError(f'{name}: no build inputs')
        if any(not path_ok(p) for key in FIELDS for p in item[key]):
            raise ValueError(f'{name}: unsafe input pattern')
        targets[name] = normalized
    done: set[str] = set()
    active: set[str] = set()

    def visit(name: str) -> None:
        if name not in targets:
            raise ValueError(f'Unknown dependency: {name}')
        if name in active:
            raise ValueError(f'Dependency cycle at {name}')
        if name in done:
            return
        active.add(name)
        for dep in targets[name]['depends_on']:
            visit(dep)
        active.remove(name)
        done.add(name)

    for name in targets:
        visit(name)
    return targets


def select(registry: Any, changed: list[str], force: bool = False) -> dict[str, Any]:
    targets = validate_registry(registry)
    if not isinstance(changed, list) or any(not path_ok(p) for p in changed):
        raise ValueError('Unsafe changed path')
    builds: set[str] = set(targets) if force else set()
    tests: set[str] = set()
    docs = False
    wiki = False
    unknown: list[str] = []
    reasons: dict[str, set[str]] = {name: set() for name in targets}
    if force:
        for name in targets:
            reasons[name].add('explicit-full')
    for path in sorted(set(changed)):
        declared = False
        for name, target in targets.items():
            for field in FIELDS:
                if not matches(path, target[field]):
                    continue
                declared = True
                if field == 'build_inputs':
                    builds.add(name)
                    reasons[name].add('build-input:' + path)
                elif field == 'test_inputs':
                    tests.add(name)
                    reasons[name].add('test-input:' + path)
                else:
                    docs = wiki = True
        # Policy edits always invalidate, even when also declared as an input.
        if matches(path, POLICY):
            builds.update(targets)
            for name in targets:
                reasons[name].add('policy:' + path)
        elif matches(path, TEST_POLICY):
            tests.update(targets)
            for name in targets:
                reasons[name].add('test-policy:' + path)
        elif declared:
            pass
        elif matches(path, DOCS):
            docs = True
        elif matches(path, WIKI):
            docs = wiki = True
        elif path in INFRA or path in LOCAL_TOOLS:
            pass
        else:
            unknown.append(path)
            builds.update(targets)
            for name in targets:
                reasons[name].add('unclassified:' + path)
    # Build invalidation propagates; a dependency's test-only edit does not.
    progress = True
    while progress:
        progress = False
        for name, target in targets.items():
            affected = set(target['depends_on']) & builds
            if affected:
                reasons[name].update('dependency:' + dep for dep in affected)
                if name not in builds:
                    builds.add(name)
                    progress = True
    tests.update(builds)
    return {'schema_version': 1, 'advisory_only': True,
            'build_candidates': sorted(builds), 'test_candidates': sorted(tests),
            'docs': docs, 'wiki': wiki, 'unclassified_paths': unknown,
            'reasons': {k: sorted(v) for k, v in sorted(reasons.items()) if v}}


def git_paths(root: Path, base: str | None) -> list[str]:
    """Diff endpoints without rename folding, preserving both old and new paths."""
    def git(*args: str) -> bytes:
        return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.PIPE)
    if base == '' or (base and set(base) == {'0'}):
        base = None
    if base is not None:
        if not re.fullmatch(r'[0-9a-fA-F]{40,64}', base):
            raise ValueError('Base must be a full commit SHA')
        git('cat-file', '-e', base + '^{commit}')
        data = git('diff', '--no-renames', '--name-only', '-z', base, 'HEAD', '--')
    else:
        data = git('ls-files', '-z')
    paths = [p.decode('utf-8', errors='strict') for p in data.split(b'\0') if p]
    if any(not path_ok(p) for p in paths):
        raise ValueError('Unsupported repository path')
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', type=Path, default=Path('ci/targets.json'))
    parser.add_argument('--changed', nargs='*', default=None)
    parser.add_argument('--base', default=None)
    parser.add_argument('--full', action='store_true')
    args = parser.parse_args()
    try:
        registry = json.loads(args.registry.read_text(encoding='utf-8'))
        changed = args.changed if args.changed is not None else git_paths(Path.cwd(), args.base)
        print(json.dumps(select(registry, changed, args.full), ensure_ascii=False, indent=2))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'CI selection failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

# SPDX-License-Identifier: BSD-3-Clause
"""Plan selective CI and validate reusable target artifacts and receipts."""
from __future__ import annotations

import argparse
from fnmatch import fnmatchcase
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

from ci_plan import git_paths, path_ok, select, validate_registry
from emulator_runner import (RunnerError, run as run_emulator,
                             validate_expectations)
from game_project import (ProjectError, address, build_project, parse_cjr,
                          validate_project)
from jrasm_tool import sha256_file


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY = ROOT / 'ci/targets.json'
DEFAULT_RUNNER_LOCK = ROOT / 'ci/runner.lock.json'
DEFAULT_RECEIPTS = ROOT / '.ci-cache/receipts'
BUILD_COMMON = ('ci/targets.json', 'tools/ci_pipeline.py')
TEST_COMMON = ('ci/runner.lock.json', 'ci/targets.json', 'emulator.lock.json',
               'tools/ci_pipeline.py', 'tools/ci_snapshot.py', 'tools/emulator_runner.py',
               'tools/runner_fetch.py', 'tools/runner_joystick_smoke.mjs',
               'tools/jr200_wasm_runner.mjs', 'tools/png_rgba.py')


class PipelineError(ValueError):
    """Expected CI plan, cache, receipt, or target failure."""


def read_json(path: Path, description: str) -> Any:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise PipelineError(f'Cannot read {description}: {path}: {exc}') from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n',
                    encoding='utf-8')


def validate_runner_lock(value: Any) -> dict[str, Any]:
    expected = {'schema_version', 'platform', 'python_minimum',
                'target_runner_version', 'cache_contract', 'emulator'}
    if not isinstance(value, dict) or set(value) != expected:
        raise PipelineError('Invalid runner lock fields')
    if type(value['schema_version']) is not int or value['schema_version'] != 3:
        raise PipelineError('Unsupported runner lock schema')
    if (not isinstance(value['platform'], str)
            or not re.fullmatch(r'[a-z0-9][a-z0-9._-]+', value['platform'])):
        raise PipelineError('Invalid runner platform')
    if (not isinstance(value['python_minimum'], str)
            or not re.fullmatch(r'[0-9]+\.[0-9]+', value['python_minimum'])
            or type(value['target_runner_version']) is not int
            or value['target_runner_version'] < 2
            or type(value['cache_contract']) is not int
            or value['cache_contract'] < 2):
        raise PipelineError('Invalid runner lock values')
    emulator = value['emulator']
    if (not isinstance(emulator, dict)
            or set(emulator) != {'lock', 'runtime_required', 'unavailable_reason',
                                 'runtime_policy'}
            or emulator['lock'] != 'emulator.lock.json'
            or type(emulator['runtime_required']) is not bool
            or not isinstance(emulator['unavailable_reason'], str)
            or (emulator['runtime_required'] and emulator['unavailable_reason'])
            or not isinstance(emulator['runtime_policy'], dict)
            or any(not isinstance(target, str)
                   or re.fullmatch(r'[a-z][a-z0-9-]{0,31}', target) is None
                   or policy != 'local_rom_only'
                   for target, policy in emulator['runtime_policy'].items())):
        raise PipelineError('Invalid emulator runner lock')
    return value


def load_registry(path: Path = DEFAULT_REGISTRY) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    value = read_json(path, 'target registry')
    try:
        targets = validate_registry(value)
    except ValueError as exc:
        raise PipelineError(str(exc)) from exc
    return value, targets


def repository_files(root: Path) -> list[str]:
    try:
        data = subprocess.check_output(
            ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
            cwd=root, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as exc:
        raise PipelineError('Cannot enumerate repository inputs') from exc
    paths = [item.decode('utf-8', errors='strict') for item in data.split(b'\0') if item]
    if any(not path_ok(path) for path in paths):
        raise PipelineError('Repository contains an unsupported path')
    return sorted(set(paths))


def matching_files(paths: list[str], patterns: list[str] | tuple[str, ...]) -> list[str]:
    return sorted(path for path in paths
                  if any(fnmatchcase(path, pattern) for pattern in patterns))


def hash_records(label: str, records: list[tuple[str, str]]) -> str:
    digest = hashlib.sha256()
    digest.update((label + '\0').encode('utf-8'))
    for name, value in records:
        digest.update(name.encode('utf-8') + b'\0')
        digest.update(value.encode('ascii') + b'\0')
    return digest.hexdigest()


def content_records(root: Path, paths: list[str]) -> list[tuple[str, str]]:
    records = []
    for relative in sorted(set(paths)):
        path = root / relative
        if not path.is_file():
            raise PipelineError(f'Fingerprint input is missing: {relative}')
        records.append((relative, sha256_file(path)))
    return records


def validate_target_contracts(root: Path, targets: dict[str, dict[str, Any]]) -> None:
    root = root.resolve()
    for name, target in targets.items():
        project = (root / target['project']).resolve()
        try:
            project.relative_to(root)
        except ValueError as exc:
            raise PipelineError(f'{name}: project leaves repository') from exc
        if target['runner'] == 'legacy-unconfigured':
            continue
        if target['runner'] != 'jr200-project':
            if not project.is_dir():
                raise PipelineError(f'{name}: project directory is missing')
            continue
        try:
            spec = validate_project(project, root / 'rules/jr200.json', root)
        except ProjectError as exc:
            raise PipelineError(f'{name}: {exc}') from exc
        if spec.config['id'] != name:
            raise PipelineError(f'{name}: target ID does not match build.json')
        required_build = [
            f'{target["project"]}/Makefile',
            f'{target["project"]}/build.json',
            *(f'{target["project"]}/{path}'
              for path in (*spec.assembly_inputs, *spec.asset_inputs)),
            *spec.sdk_inputs,
        ]
        for relative in required_build:
            if not any(fnmatchcase(relative, pattern) for pattern in target['build_inputs']):
                raise PipelineError(f'{name}: undeclared CI build input: {relative}')
        expectation = f'{target["project"]}/tests/expectations.json'
        if not any(fnmatchcase(expectation, pattern) for pattern in target['test_inputs']):
            raise PipelineError(f'{name}: undeclared CI test input: {expectation}')


def calculate_fingerprints(root: Path, targets: dict[str, dict[str, Any]],
                           platform_id: str) -> dict[str, dict[str, str]]:
    root = root.resolve()
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]+', platform_id):
        raise PipelineError('Invalid fingerprint platform')
    validate_target_contracts(root, targets)
    paths = repository_files(root)
    common_build = matching_files(paths, BUILD_COMMON)
    common_test = matching_files(paths, TEST_COMMON)
    results: dict[str, dict[str, str]] = {}
    active: set[str] = set()

    def visit(name: str) -> dict[str, str]:
        if name in results:
            return results[name]
        if name in active:
            raise PipelineError(f'Fingerprint dependency cycle at {name}')
        active.add(name)
        target = targets[name]
        dependency_hashes = [(dep, visit(dep)['build']) for dep in target['depends_on']]
        build_paths = matching_files(paths, target['build_inputs'])
        if not build_paths:
            raise PipelineError(f'{name}: build inputs match no repository files')
        build_records = [
            ('platform', hashlib.sha256(platform_id.encode('utf-8')).hexdigest()),
            ('target', hashlib.sha256(json.dumps(
                target, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()),
            *content_records(root, sorted(set(build_paths + common_build))),
            *((f'dependency:{dep}', digest) for dep, digest in dependency_hashes),
        ]
        build_fingerprint = hash_records('jr200-build-v1', build_records)
        test_paths = matching_files(paths, target['test_inputs'])
        if not test_paths:
            raise PipelineError(f'{name}: test inputs match no repository files')
        test_records = [
            ('build-fingerprint', build_fingerprint),
            *content_records(root, sorted(set(test_paths + common_test))),
        ]
        test_fingerprint = hash_records('jr200-test-v1', test_records)
        results[name] = {'build': build_fingerprint, 'test': test_fingerprint}
        active.remove(name)
        return results[name]

    for target_name in targets:
        visit(target_name)
    return results


def registry_at(root: Path, revision: str | None) -> dict[str, Any] | None:
    if revision in (None, '') or (revision and set(revision) == {'0'}):
        return None
    if not re.fullmatch(r'[0-9a-fA-F]{40,64}', revision):
        raise PipelineError('Base must be a full commit SHA')
    try:
        subprocess.check_call(['git', 'cat-file', '-e', revision + '^{commit}'],
                              cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data = subprocess.check_output(['git', 'show', f'{revision}:ci/targets.json'],
                                       cwd=root, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError:
        return None
    try:
        value = json.loads(data.decode('utf-8'))
        validate_registry(value)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise PipelineError(f'Invalid base target registry: {exc}') from exc
    return value


def merge_reasons(current: dict[str, Any], previous: dict[str, Any] | None,
                  names: set[str]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name in sorted(names):
        reasons = set(current.get('reasons', {}).get(name, []))
        if previous is not None:
            reasons.update('previous:' + item
                           for item in previous.get('reasons', {}).get(name, []))
        result[name] = sorted(reasons)
    return result


def make_plan(root: Path, registry_path: Path, platform_id: str,
              base: str | None, changed: list[str] | None,
              full: bool = False,
              trusted: dict[str, dict[str, str]] | None = None) -> dict[str, Any]:
    root = root.resolve()
    registry_path = registry_path.resolve()
    raw, targets = load_registry(registry_path)
    if raw.get('schema_version') != 2:
        raise PipelineError('Current target registry must use schema version 2')
    validate_runner_lock(read_json(root / 'ci/runner.lock.json', 'runner lock'))
    if changed is None:
        try:
            changed = git_paths(root, base)
        except (ValueError, subprocess.CalledProcessError) as exc:
            raise PipelineError(str(exc)) from exc
    current = select(raw, changed, full)
    old_raw = registry_at(root, base)
    previous = select(old_raw, changed, full) if old_raw is not None else None
    build_names = set(current['build_candidates'])
    test_names = set(current['test_candidates'])
    old_names: set[str] = set()
    if previous is not None:
        old_names.update(previous['build_candidates'])
        old_names.update(previous['test_candidates'])
        build_names.update(name for name in previous['build_candidates'] if name in targets)
        test_names.update(name for name in previous['test_candidates'] if name in targets)
    if full:
        build_names.update(targets)
        test_names.update(targets)
    test_names.update(build_names)
    removed = sorted(name for name in old_names if name not in targets)
    reasons = merge_reasons(current, previous, set(targets))
    fingerprints = calculate_fingerprints(root, targets, platform_id)
    if trusted is not None:
        for name in targets:
            old = trusted.get(name)
            current_fingerprints = fingerprints[name]
            if old is None or old.get('build') != current_fingerprints['build']:
                build_names.add(name)
                test_names.add(name)
                reasons.setdefault(name, []).append('trusted build missing or changed')
            elif old.get('test') != current_fingerprints['test']:
                test_names.add(name)
                reasons.setdefault(name, []).append('trusted test missing or changed')
    matrix = []
    for name in sorted(test_names):
        target = targets[name]
        matrix.append({
            'id': name,
            'kind': target['kind'],
            'project': target['project'],
            'runner': target['runner'],
            'platform': platform_id,
            'build_fingerprint': fingerprints[name]['build'],
            'test_fingerprint': fingerprints[name]['test'],
            'build_required': name in build_names,
            'reason': ', '.join(reasons.get(name, [])) or 'dependency graph selection',
        })
    plan = {
        'schema_version': 1,
        'advisory_only': False,
        'platform': platform_id,
        'changed_paths': sorted(set(changed)),
        'build_targets': sorted(build_names),
        'test_targets': sorted(test_names),
        'removed_targets': removed,
        'reuse_candidates': sorted(test_names - build_names),
        'docs': current['docs'] or bool(previous and previous['docs']),
        'wiki': current['wiki'] or bool(previous and previous['wiki']),
        'unclassified_paths': sorted(set(
            current['unclassified_paths']
            + ([] if previous is None else previous['unclassified_paths']))),
        'reasons': {name: reasons[name] for name in sorted(test_names)},
        'matrix': {'include': matrix},
    }
    plan['plan_sha256'] = hashlib.sha256(json.dumps(
        plan, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()
    return plan


def github_outputs(path: Path, plan: dict[str, Any]) -> None:
    matrix = json.dumps(plan['matrix'], separators=(',', ':'))
    with path.open('a', encoding='utf-8') as output:
        output.write(f'matrix={matrix}\n')
        output.write(f'has_targets={str(bool(plan["matrix"]["include"])).lower()}\n')
        output.write(f'plan_sha256={plan["plan_sha256"]}\n')


def append_plan_summary(path: Path, plan: dict[str, Any]) -> None:
    lines = [
        '## Selective CI plan',
        '',
        f'- Plan SHA-256: `{plan["plan_sha256"]}`',
        f'- Build targets: {len(plan["build_targets"])}',
        f'- Test targets: {len(plan["test_targets"])}',
        f'- Reuse candidates: {len(plan["reuse_candidates"])}',
        f'- Removed targets: {len(plan["removed_targets"])}',
        f'- Unclassified paths: {len(plan["unclassified_paths"])}',
        '',
    ]
    if plan['matrix']['include']:
        lines.extend(['| Target | Build | Reason |', '| --- | --- | --- |'])
        for item in plan['matrix']['include']:
            lines.append(
                f'| `{item["id"]}` | {str(item["build_required"]).lower()} | '
                f'{item["reason"]} |')
    else:
        lines.append('No target build or test job is required.')
    lines.append('')
    with path.open('a', encoding='utf-8') as output:
        output.write('\n'.join(lines))


def target_and_fingerprints(root: Path, registry_path: Path, target_id: str,
                            platform_id: str) -> tuple[dict[str, Any], dict[str, str]]:
    _, targets = load_registry(registry_path)
    if target_id not in targets:
        raise PipelineError(f'Unknown target: {target_id}')
    fingerprints = calculate_fingerprints(root, targets, platform_id)
    return targets[target_id], fingerprints[target_id]


def build_metadata_path(root: Path, target: dict[str, Any]) -> Path:
    return root / target['project'] / 'build/ci-build.json'


def verify_build_cache(root: Path, registry_path: Path, target_id: str,
                       platform_id: str, expected_fingerprint: str) -> dict[str, Any]:
    target, fingerprints = target_and_fingerprints(
        root, registry_path, target_id, platform_id)
    if fingerprints['build'] != expected_fingerprint:
        raise PipelineError('Expected build fingerprint does not match current inputs')
    metadata = read_json(build_metadata_path(root, target), 'build cache metadata')
    expected_fields = {'schema_version', 'target', 'platform', 'build_fingerprint',
                       'artifact', 'build_report'}
    if (not isinstance(metadata, dict) or set(metadata) != expected_fields
            or metadata['schema_version'] != 1
            or metadata['target'] != target_id
            or metadata['platform'] != platform_id
            or metadata['build_fingerprint'] != expected_fingerprint):
        raise PipelineError('Build cache metadata does not match this target')
    project = root / target['project']
    spec = validate_project(project, root / 'rules/jr200.json', root)
    artifact = project / metadata['artifact']['path']
    report_path = project / metadata['build_report']['path']
    for item, path, label in ((metadata['artifact'], artifact, 'artifact'),
                              (metadata['build_report'], report_path, 'build report')):
        if not path.is_file():
            raise PipelineError(f'Cached {label} is missing')
        if path.stat().st_size != item['size'] or sha256_file(path) != item['sha256']:
            raise PipelineError(f'Cached {label} hash or size mismatch')
    report = read_json(report_path, 'cached build report')
    if (report.get('project') != target_id
            or report.get('artifact', {}).get('sha256') != metadata['artifact']['sha256']
            or report.get('verification', {}).get('assembler') != 'passed'
            or report.get('verification', {}).get('cjr_layout') != 'passed'):
        raise PipelineError('Cached build report is inconsistent')
    parsed = parse_cjr(artifact.read_bytes())
    entry = address(spec.config['entry_address'], 'entry address')
    if not any(block.start <= entry <= block.end for block in parsed['blocks']):
        raise PipelineError('Cached CJR does not contain the entry address')
    for block in parsed['blocks']:
        if not all(any(region.start <= location <= region.end for region in spec.regions)
                   for location in range(block.start, block.end + 1)):
            raise PipelineError('Cached CJR is outside declared regions')
    return metadata


def run_target_build(root: Path, registry_path: Path, target_id: str,
                     platform_id: str, expected_fingerprint: str,
                     jrasm: str | None) -> dict[str, Any]:
    target, fingerprints = target_and_fingerprints(
        root, registry_path, target_id, platform_id)
    if fingerprints['build'] != expected_fingerprint:
        raise PipelineError('Expected build fingerprint does not match current inputs')
    if target['runner'] != 'jr200-project':
        raise PipelineError(f'Unsupported build runner: {target["runner"]}')
    try:
        spec, report = build_project(root / target['project'], jrasm,
                                     root / 'toolchain.lock.json',
                                     root / 'rules/jr200.json', root)
    except ProjectError as exc:
        raise PipelineError(str(exc)) from exc
    report_path = spec.project / 'build/build-report.json'
    artifact_path = spec.output
    metadata = {
        'schema_version': 1,
        'target': target_id,
        'platform': platform_id,
        'build_fingerprint': expected_fingerprint,
        'artifact': {
            'path': artifact_path.relative_to(spec.project).as_posix(),
            'size': artifact_path.stat().st_size,
            'sha256': sha256_file(artifact_path),
        },
        'build_report': {
            'path': report_path.relative_to(spec.project).as_posix(),
            'size': report_path.stat().st_size,
            'sha256': sha256_file(report_path),
        },
    }
    if metadata['artifact']['sha256'] != report['artifact']['sha256']:
        raise PipelineError('Built artifact does not match its report')
    write_json(build_metadata_path(root, target), metadata)
    return metadata


def run_target_test(root: Path, registry_path: Path, target_id: str,
                    platform_id: str, build_fingerprint: str,
                    test_fingerprint: str, emulator_bundle: Path | None = None,
                    node: str = 'node') -> dict[str, Any]:
    target, fingerprints = target_and_fingerprints(
        root, registry_path, target_id, platform_id)
    if (fingerprints['build'] != build_fingerprint
            or fingerprints['test'] != test_fingerprint):
        raise PipelineError('Expected test fingerprints do not match current inputs')
    metadata = verify_build_cache(
        root, registry_path, target_id, platform_id, build_fingerprint)
    if target['runner'] != 'jr200-project':
        raise PipelineError(f'Unsupported test runner: {target["runner"]}')
    project = root / target['project']
    spec = validate_project(project, root / 'rules/jr200.json', root)
    expectations = read_json(project / 'tests/expectations.json', 'target expectations')
    try:
        validate_expectations(
            expectations, address(spec.config['entry_address'], 'entry address'))
    except RunnerError as exc:
        raise PipelineError(str(exc)) from exc
    runner_lock = validate_runner_lock(
        read_json(root / 'ci/runner.lock.json', 'runner lock'))
    emulator_status = 'not_run'
    emulator_evidence = 'not_run'
    emulator_profiles: list[str] = []
    unavailable_reason = runner_lock['emulator']['unavailable_reason']
    synthetic_profiles = [
        item['profile'] for item in expectations['runtime']['profiles']
        if item['mode'] == 'synthetic-injection'
    ]
    policy = runner_lock['emulator']['runtime_policy'].get(target_id)
    if policy == 'local_rom_only':
        if (synthetic_profiles or not any(
                item['mode'] == 'rom-cassette'
                for item in expectations['runtime']['profiles'])):
            raise PipelineError('Local-ROM-only target has invalid runtime profiles')
        emulator_status = 'local_rom_only'
        unavailable_reason = 'requires_local_rom_font'
    elif emulator_bundle is not None:
        if not synthetic_profiles:
            raise PipelineError('Target has no synthetic emulator profile')
        evidence = set()
        for profile in synthetic_profiles:
            try:
                runtime_report = run_emulator(
                    project, emulator_bundle, node,
                    root / 'tools/jr200_wasm_runner.mjs',
                    root / runner_lock['emulator']['lock'], profile=profile)
            except RunnerError as exc:
                raise PipelineError(f'{profile}: {exc}') from exc
            evidence.add(runtime_report['result']['evidence'])
        if len(evidence) != 1:
            raise PipelineError('Synthetic profiles returned mixed evidence classes')
        emulator_status = 'passed'
        emulator_evidence = next(iter(evidence))
        emulator_profiles = synthetic_profiles
        unavailable_reason = ''
    elif runner_lock['emulator']['runtime_required']:
        raise PipelineError('Required emulator bundle was not provided')
    result = {
        'schema_version': 1,
        'target': target_id,
        'platform': platform_id,
        'build_fingerprint': build_fingerprint,
        'test_fingerprint': test_fingerprint,
        'artifact_sha256': metadata['artifact']['sha256'],
        'tests': 'passed',
        'emulator': emulator_status,
        'emulator_evidence': emulator_evidence,
        'emulator_profiles': emulator_profiles,
        'emulator_unavailable_reason': unavailable_reason,
        'hardware': 'not_run',
    }
    write_json(project / 'build/ci-test.json', result)
    return result


def receipt_path(receipts: Path, target_id: str) -> Path:
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,31}', target_id):
        raise PipelineError('Invalid receipt target ID')
    return receipts / target_id / 'receipt.json'


def write_receipt(root: Path, registry_path: Path, receipts: Path,
                  target_id: str, platform_id: str,
                  build_fingerprint: str, test_fingerprint: str) -> dict[str, Any]:
    target, fingerprints = target_and_fingerprints(
        root, registry_path, target_id, platform_id)
    if (fingerprints['build'] != build_fingerprint
            or fingerprints['test'] != test_fingerprint):
        raise PipelineError('Receipt fingerprints do not match current inputs')
    metadata = verify_build_cache(
        root, registry_path, target_id, platform_id, build_fingerprint)
    test_result = read_json(root / target['project'] / 'build/ci-test.json',
                            'target test result')
    if (test_result.get('test_fingerprint') != test_fingerprint
            or test_result.get('artifact_sha256') != metadata['artifact']['sha256']
            or test_result.get('tests') != 'passed'):
        raise PipelineError('Target test result is not eligible for a receipt')
    receipt = {
        'schema_version': 1,
        'target': target_id,
        'platform': platform_id,
        'build_fingerprint': build_fingerprint,
        'test_fingerprint': test_fingerprint,
        'artifact_sha256': metadata['artifact']['sha256'],
        'build': 'passed',
        'tests': 'passed',
        'emulator': test_result['emulator'],
        'emulator_evidence': test_result['emulator_evidence'],
        'emulator_profiles': test_result['emulator_profiles'],
        'emulator_unavailable_reason': test_result['emulator_unavailable_reason'],
        'hardware': test_result['hardware'],
    }
    write_json(receipt_path(receipts, target_id), receipt)
    return receipt


def verify_receipt(root: Path, registry_path: Path, receipts: Path,
                   target_id: str, platform_id: str,
                   build_fingerprint: str, test_fingerprint: str) -> dict[str, Any]:
    target, fingerprints = target_and_fingerprints(
        root, registry_path, target_id, platform_id)
    if (fingerprints['build'] != build_fingerprint
            or fingerprints['test'] != test_fingerprint):
        raise PipelineError('Receipt fingerprints do not match current inputs')
    metadata = verify_build_cache(
        root, registry_path, target_id, platform_id, build_fingerprint)
    receipt = read_json(receipt_path(receipts, target_id), 'verification receipt')
    expected = {
        'schema_version': 1,
        'target': target_id,
        'platform': platform_id,
        'build_fingerprint': build_fingerprint,
        'test_fingerprint': test_fingerprint,
        'artifact_sha256': metadata['artifact']['sha256'],
        'build': 'passed',
        'tests': 'passed',
        'hardware': 'not_run',
        'emulator_profiles': receipt.get('emulator_profiles'),
    }
    fixed = {key: value for key, value in receipt.items()
             if key not in ('emulator', 'emulator_evidence',
                            'emulator_unavailable_reason')}
    if fixed != expected:
        raise PipelineError('Verification receipt is missing, stale, or inconsistent')
    runner_lock = validate_runner_lock(
        read_json(root / 'ci/runner.lock.json', 'runner lock'))
    emulator_fields = (receipt.get('emulator'), receipt.get('emulator_evidence'),
                       receipt.get('emulator_unavailable_reason'))
    expectations = read_json(
        root / target['project'] / 'tests/expectations.json',
        'target expectations')
    declared_synthetic = [
        item['profile'] for item in expectations['runtime']['profiles']
        if item['mode'] == 'synthetic-injection'
    ]
    policy = runner_lock['emulator']['runtime_policy'].get(target_id)
    if policy == 'local_rom_only':
        valid_emulator = (not declared_synthetic
                          and any(item['mode'] == 'rom-cassette'
                                  for item in expectations['runtime']['profiles'])
                          and emulator_fields == ('local_rom_only', 'not_run',
                                                  'requires_local_rom_font')
                          and receipt.get('emulator_profiles') == [])
    elif runner_lock['emulator']['runtime_required']:
        valid_emulator = (emulator_fields[0] == 'passed'
                          and emulator_fields[1] in ('emulator',
                                                     'emulator_with_local_rom')
                          and emulator_fields[2] == ''
                          and receipt.get('emulator_profiles') == declared_synthetic)
    else:
        valid_emulator = (
            (emulator_fields[0] == 'passed'
             and emulator_fields[1] in ('emulator', 'emulator_with_local_rom')
             and emulator_fields[2] == ''
             and receipt.get('emulator_profiles') == declared_synthetic)
            or emulator_fields == (
                'not_run', 'not_run', runner_lock['emulator']['unavailable_reason'])
            and receipt.get('emulator_profiles') == [])
    if not valid_emulator:
        raise PipelineError('Verification receipt has invalid emulator evidence')
    if target['runner'] != 'jr200-project':
        raise PipelineError('Receipt runner does not match target contract')
    return receipt


def gate(required: str, plan: str, targets: str, has_targets: str,
         snapshot: str = 'skipped', snapshot_required: bool = False) -> None:
    if required != 'success':
        raise PipelineError(f'Repository contracts result is {required}')
    if plan != 'success':
        raise PipelineError(f'Planner result is {plan}')
    expected_targets = has_targets == 'true'
    if expected_targets and targets != 'success':
        raise PipelineError(f'Required target jobs result is {targets}')
    if not expected_targets and targets not in ('skipped', 'success'):
        raise PipelineError(f'Unexpected empty-matrix job result is {targets}')
    if snapshot_required and snapshot != 'success':
        raise PipelineError(f'Trusted snapshot job result is {snapshot}')
    if not snapshot_required and snapshot != 'skipped':
        raise PipelineError(f'Unexpected snapshot job result is {snapshot}')


def add_target_arguments(command: argparse.ArgumentParser) -> None:
    command.add_argument('--root', type=Path, default=ROOT)
    command.add_argument('--registry', type=Path, default=DEFAULT_REGISTRY)
    command.add_argument('--target', required=True)
    command.add_argument('--platform', required=True)
    command.add_argument('--build-fingerprint', required=True)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    commands = value.add_subparsers(dest='command', required=True)
    plan = commands.add_parser('plan')
    plan.add_argument('--root', type=Path, default=ROOT)
    plan.add_argument('--registry', type=Path, default=DEFAULT_REGISTRY)
    plan.add_argument('--platform')
    plan.add_argument('--base')
    plan.add_argument('--changed', nargs='*')
    plan.add_argument('--full', action='store_true')
    plan.add_argument('--output', type=Path)
    plan.add_argument('--github-output', type=Path)
    plan.add_argument('--summary', type=Path)
    plan.add_argument('--trusted-state', type=Path)
    build = commands.add_parser('build')
    add_target_arguments(build)
    build.add_argument('--jrasm')
    test = commands.add_parser('test')
    add_target_arguments(test)
    test.add_argument('--test-fingerprint', required=True)
    test.add_argument('--emulator-bundle', type=Path)
    test.add_argument('--node', default='node')
    cache = commands.add_parser('cache-check')
    add_target_arguments(cache)
    receipt_write = commands.add_parser('receipt-write')
    add_target_arguments(receipt_write)
    receipt_write.add_argument('--test-fingerprint', required=True)
    receipt_write.add_argument('--receipts', type=Path, default=DEFAULT_RECEIPTS)
    receipt_check = commands.add_parser('receipt-check')
    add_target_arguments(receipt_check)
    receipt_check.add_argument('--test-fingerprint', required=True)
    receipt_check.add_argument('--receipts', type=Path, default=DEFAULT_RECEIPTS)
    gate_command = commands.add_parser('gate')
    gate_command.add_argument('--required-result', required=True)
    gate_command.add_argument('--plan-result', required=True)
    gate_command.add_argument('--targets-result', required=True)
    gate_command.add_argument('--has-targets', required=True)
    gate_command.add_argument('--snapshot-result', default='skipped')
    gate_command.add_argument('--snapshot-required', default='false')
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == 'plan':
            runner = validate_runner_lock(read_json(
                args.root.resolve() / 'ci/runner.lock.json', 'runner lock'))
            platform_id = args.platform or runner['platform']
            trusted = None
            if args.trusted_state is not None:
                from ci_snapshot import inspect_state
                trusted = inspect_state(args.root.resolve(), args.registry.resolve(),
                                        args.trusted_state.resolve(), platform_id)
            result = make_plan(args.root.resolve(), args.registry.resolve(), platform_id,
                               args.base, args.changed, args.full, trusted)
            encoded = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
            if args.output:
                args.output.write_text(encoded, encoding='utf-8')
            else:
                print(encoded, end='')
            if args.github_output:
                github_outputs(args.github_output, result)
            if args.summary:
                append_plan_summary(args.summary, result)
        elif args.command == 'build':
            metadata = run_target_build(
                args.root.resolve(), args.registry.resolve(), args.target,
                args.platform, args.build_fingerprint, args.jrasm)
            print(f'Target build: OK ({args.target}, {metadata["artifact"]["sha256"]})')
            print('Runtime verification: emulator=not_run hardware=not_run')
        elif args.command == 'test':
            result = run_target_test(
                args.root.resolve(), args.registry.resolve(), args.target,
                args.platform, args.build_fingerprint, args.test_fingerprint,
                args.emulator_bundle, args.node)
            print(f'Target tests: OK ({args.target}, {result["test_fingerprint"]})')
            print(f'Runtime verification: emulator={result["emulator"]} '
                  'hardware=not_run')
        elif args.command == 'cache-check':
            metadata = verify_build_cache(
                args.root.resolve(), args.registry.resolve(), args.target,
                args.platform, args.build_fingerprint)
            print(f'Build cache: valid ({args.target}, {metadata["artifact"]["sha256"]})')
        elif args.command == 'receipt-write':
            receipt = write_receipt(
                args.root.resolve(), args.registry.resolve(), args.receipts.resolve(),
                args.target, args.platform, args.build_fingerprint,
                args.test_fingerprint)
            print(f'Verification receipt: written ({args.target}, {receipt["test_fingerprint"]})')
        elif args.command == 'receipt-check':
            receipt = verify_receipt(
                args.root.resolve(), args.registry.resolve(), args.receipts.resolve(),
                args.target, args.platform, args.build_fingerprint,
                args.test_fingerprint)
            print(f'Verification receipt: valid ({args.target}, {receipt["test_fingerprint"]})')
        else:
            gate(args.required_result, args.plan_result,
                 args.targets_result, args.has_targets,
                 args.snapshot_result, args.snapshot_required == 'true')
            print('Required gate: OK')
    except (PipelineError, ProjectError, OSError, subprocess.SubprocessError) as exc:
        print(f'CI pipeline failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

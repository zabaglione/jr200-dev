# SPDX-License-Identifier: BSD-3-Clause
"""Read and publish verified CI target snapshots from successful main runs."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile

from ci_pipeline import (PipelineError, calculate_fingerprints, load_registry,
                         read_json, verify_receipt, write_json)
from game_project import parse_cjr
from jrasm_tool import sha256_file


ENTRY_FILES = ('artifact.cjr', 'build-report.json', 'ci-build.json', 'receipt.json')
ARTIFACT_NAME = 'trusted-targets-v1'
MAX_ZIP_BYTES = 64 * 1024 * 1024


class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
        if redirected is not None and urlsplit(newurl).netloc != urlsplit(request.full_url).netloc:
            redirected.remove_header('Authorization')
        return redirected


def api(path: str, token: str) -> tuple[bytes, dict[str, str]]:
    request = Request('https://api.github.com/' + path.lstrip('/'), headers={
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'jr200-dev-ci-snapshot',
    })
    with build_opener(SafeRedirect()).open(request, timeout=30) as response:
        return response.read(MAX_ZIP_BYTES + 1), dict(response.headers)


def api_json(path: str, token: str) -> dict:
    data, _ = api(path, token)
    if len(data) > MAX_ZIP_BYTES:
        raise PipelineError('GitHub API response is too large')
    result = json.loads(data)
    if not isinstance(result, dict):
        raise PipelineError('GitHub API returned an invalid object')
    return result


def accepted_repo(repo: str) -> str:
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise PipelineError('Invalid repository name')
    return repo


def ancestor(root: Path, revision: str) -> bool:
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        return False
    return subprocess.run(['git', 'merge-base', '--is-ancestor', revision, 'HEAD'],
                          cwd=root, check=False).returncode == 0


def artifact_for_run(repo: str, run_id: int, name: str, token: str) -> dict | None:
    data = api_json(f'repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100', token)
    matches = [item for item in data.get('artifacts', [])
               if item.get('name') == name and not item.get('expired')]
    if len(matches) > 1:
        raise PipelineError(f'Duplicate CI artifact: {name}')
    return matches[0] if matches else None


def unpack_artifact(repo: str, artifact: dict, token: str, output: Path) -> None:
    artifact_id = artifact.get('id')
    if type(artifact_id) is not int:
        raise PipelineError('Invalid artifact ID')
    data, _ = api(f'repos/{repo}/actions/artifacts/{artifact_id}/zip', token)
    if len(data) > MAX_ZIP_BYTES:
        raise PipelineError('CI artifact ZIP is too large')
    digest = artifact.get('digest')
    if not isinstance(digest, str) or not digest.startswith('sha256:'):
        raise PipelineError('CI artifact has no SHA-256 digest')
    if hashlib.sha256(data).hexdigest() != digest.removeprefix('sha256:'):
        raise PipelineError('CI artifact ZIP digest mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        members = archive.infolist()
        if sum(item.file_size for item in members) > MAX_ZIP_BYTES:
            raise PipelineError('Unpacked CI artifact is too large')
        seen: set[str] = set()
        for item in members:
            name = PurePosixPath(item.filename)
            if (name.is_absolute() or '..' in name.parts
                    or not name.parts or item.filename in seen
                    or item.external_attr >> 16 & 0o170000 == 0o120000):
                raise PipelineError('Unsafe CI artifact ZIP member')
            seen.add(item.filename)
            destination = output.joinpath(*name.parts)
            if item.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as source, destination.open('wb') as target:
                shutil.copyfileobj(source, target)


def latest_success(root: Path, repo: str, current_run: int, token: str) -> dict | None:
    data = api_json(
        f'repos/{repo}/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=20',
        token)
    for run in data.get('workflow_runs', []):
        if (run.get('id') != current_run and run.get('event') == 'push'
                and run.get('head_branch') == 'main'
                and run.get('conclusion') == 'success'
                and run.get('path') == '.github/workflows/ci.yml'
                and ancestor(root, run.get('head_sha', ''))):
            return run
    return None


def download(root: Path, repo: str, run_id: int, current_run: int,
             token: str, output: Path) -> int:
    accepted_repo(repo)
    if run_id == 0:
        run = latest_success(root, repo, current_run, token)
        if run is None:
            return 0
        run_id = run['id']
    else:
        run = api_json(f'repos/{repo}/actions/runs/{run_id}', token)
        if (run.get('event') != 'push' or run.get('head_branch') != 'main'
                or run.get('conclusion') != 'success'
                or run.get('path') != '.github/workflows/ci.yml'
                or not ancestor(root, run.get('head_sha', ''))):
            return 0
    artifact = artifact_for_run(repo, run_id, ARTIFACT_NAME, token)
    if artifact is None:
        return 0
    unpack_artifact(repo, artifact, token, output)
    manifest = read_json(output / 'state.json', 'trusted state manifest')
    if (not isinstance(manifest, dict)
            or manifest != {'schema_version': 1, 'run_id': run_id,
                            'head_sha': run['head_sha'],
                            'platform': manifest.get('platform')}
            or not isinstance(manifest['platform'], str)
            or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]+',
                                manifest['platform'])
            or not valid_manifest(output, manifest['platform'])):
        raise PipelineError('Trusted state provenance mismatch')
    return run_id


def entry_fingerprints(entry: Path, name: str, platform: str) -> dict[str, str] | None:
    try:
        if not all((entry / item).is_file() for item in ENTRY_FILES):
            return None
        metadata = read_json(entry / 'ci-build.json', 'snapshot build metadata')
        receipt = read_json(entry / 'receipt.json', 'snapshot receipt')
        report = read_json(entry / 'build-report.json', 'snapshot build report')
        if (not isinstance(metadata, dict) or not isinstance(receipt, dict)
                or not isinstance(report, dict)
                or not isinstance(metadata.get('artifact'), dict)
                or not isinstance(metadata.get('build_report'), dict)):
            return None
        artifact = entry / 'artifact.cjr'
        if (metadata.get('schema_version') != 1 or metadata.get('target') != name
                or metadata.get('platform') != platform
                or receipt.get('schema_version') != 1 or receipt.get('target') != name
                or receipt.get('platform') != platform
                or receipt.get('build') != 'passed' or receipt.get('tests') != 'passed'
                or receipt.get('hardware') != 'not_run'
                or receipt.get('build_fingerprint') != metadata.get('build_fingerprint')
                or receipt.get('artifact_sha256') != metadata['artifact']['sha256']
                or report.get('project') != name
                or report.get('artifact', {}).get('sha256') != metadata['artifact']['sha256']
                or report.get('verification', {}).get('assembler') != 'passed'
                or report.get('verification', {}).get('cjr_layout') != 'passed'):
            return None
        for label, path in (('artifact', artifact), ('build_report', entry / 'build-report.json')):
            item = metadata[label]
            if (not isinstance(item.get('path'), str)
                    or not isinstance(item.get('size'), int)
                    or not isinstance(item.get('sha256'), str)):
                return None
            relative = PurePosixPath(item['path'])
            if (relative.is_absolute() or '..' in relative.parts
                    or len(relative.parts) != 2 or relative.parts[0] != 'build'
                    or path.stat().st_size != item['size']
                    or sha256_file(path) != item['sha256']):
                return None
        if not re.fullmatch(r'[0-9a-f]{64}', receipt.get('test_fingerprint', '')):
            return None
        parse_cjr(artifact.read_bytes())
        return {'build': metadata['build_fingerprint'], 'test': receipt['test_fingerprint']}
    except (OSError, KeyError, TypeError, ValueError, AttributeError,
            IndexError, PipelineError):
        return None


def valid_manifest(state: Path, platform: str) -> bool:
    path = state / 'state.json'
    if not path.is_file():
        return False
    try:
        manifest = read_json(path, 'trusted state manifest')
    except PipelineError:
        return False
    return (isinstance(manifest, dict)
            and set(manifest) == {'schema_version', 'run_id', 'head_sha', 'platform'}
            and manifest['schema_version'] == 1
            and type(manifest['run_id']) is int and manifest['run_id'] > 0
            and isinstance(manifest['head_sha'], str)
            and re.fullmatch(r'[0-9a-f]{40}', manifest['head_sha']) is not None
            and manifest['platform'] == platform)


def inspect_state(root: Path, registry_path: Path, state: Path,
                  platform: str) -> dict[str, dict[str, str]]:
    if not valid_manifest(state, platform):
        return {}
    _, targets = load_registry(registry_path)
    return {name: result for name in targets
            if (result := entry_fingerprints(state / 'targets' / name, name, platform))}


def restore(root: Path, registry_path: Path, state: Path, name: str, platform: str,
            build_fingerprint: str, test_fingerprint: str) -> None:
    _, targets = load_registry(registry_path)
    entry = state / 'targets' / name
    if not valid_manifest(state, platform):
        print(f'Snapshot provenance unavailable: {name}')
        return
    old = entry_fingerprints(entry, name, platform)
    if name not in targets or old is None or old['build'] != build_fingerprint:
        print(f'Snapshot build unavailable: {name}')
        return
    project = root / targets[name]['project']
    metadata = read_json(entry / 'ci-build.json', 'snapshot metadata')
    for label, source in (('artifact', 'artifact.cjr'),
                          ('build_report', 'build-report.json')):
        destination = project / metadata[label]['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry / source, destination)
    shutil.copy2(entry / 'ci-build.json', project / 'build/ci-build.json')
    if old['test'] == test_fingerprint:
        receipt = root / '.ci-cache/receipts' / name / 'receipt.json'
        receipt.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry / 'receipt.json', receipt)
    print(f'Snapshot build restored: {name}; receipt={old["test"] == test_fingerprint}')


def package_entry(root: Path, registry_path: Path, output: Path, name: str,
                  platform: str, build: str, test: str) -> None:
    _, targets = load_registry(registry_path)
    verify_receipt(root, registry_path, root / '.ci-cache/receipts',
                   name, platform, build, test)
    project = root / targets[name]['project']
    metadata = read_json(project / 'build/ci-build.json', 'build metadata')
    sources = (project / metadata['artifact']['path'],
               project / metadata['build_report']['path'],
               project / 'build/ci-build.json',
               root / '.ci-cache/receipts' / name / 'receipt.json')
    output.mkdir(parents=True, exist_ok=True)
    for source, target in zip(sources, ENTRY_FILES):
        shutil.copy2(source, output / target)
    if entry_fingerprints(output, name, platform) != {'build': build, 'test': test}:
        raise PipelineError('Packaged snapshot entry is invalid')


def assemble(root: Path, registry_path: Path, previous: Path, output: Path,
             repo: str, token: str, run_id: int, platform: str,
             selected_json: str) -> None:
    accepted_repo(repo)
    matrix = json.loads(selected_json)
    selected = {item['id'] for item in matrix['include']}
    _, targets = load_registry(registry_path)
    fingerprints = calculate_fingerprints(root, targets, platform)
    if selected != set(targets) and not valid_manifest(previous, platform):
        raise PipelineError('Previous trusted state is missing or invalid')
    for name in targets:
        destination = output / 'targets' / name
        if name in selected:
            artifact = None
            for attempt in range(5):
                artifact = artifact_for_run(repo, run_id, f'target-{name}', token)
                if artifact is not None:
                    break
                time.sleep(1)
            if artifact is None:
                raise PipelineError(f'Missing target result artifact: {name}')
            unpack_artifact(repo, artifact, token, destination)
        else:
            source = previous / 'targets' / name
            if source.is_dir():
                shutil.copytree(source, destination)
        if entry_fingerprints(destination, name, platform) != fingerprints[name]:
            raise PipelineError(f'Missing or invalid trusted target: {name}')
    head_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root,
                                       text=True).strip()
    write_json(output / 'state.json', {'schema_version': 1, 'run_id': run_id,
                                      'head_sha': head_sha, 'platform': platform})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('download', 'inspect', 'restore', 'package', 'assemble'))
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--registry', type=Path)
    parser.add_argument('--state', type=Path, default=Path('.ci-cache/trusted-state'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--github-output', type=Path)
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY', ''))
    parser.add_argument('--run-id', type=int, default=0)
    parser.add_argument('--platform', default='ubuntu-24.04-x86_64')
    parser.add_argument('--target')
    parser.add_argument('--build-fingerprint')
    parser.add_argument('--test-fingerprint')
    parser.add_argument('--selected-json')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    registry = (args.registry or root / 'ci/targets.json').resolve()
    state = args.state.resolve()
    token = os.environ.get('GITHUB_TOKEN', '')
    try:
        if args.command == 'download':
            if not token:
                raise PipelineError('GITHUB_TOKEN is required')
            output = (args.output or state).resolve()
            if output.exists():
                raise PipelineError('Trusted snapshot destination already exists')
            output.parent.mkdir(parents=True, exist_ok=True)
            try:
                with tempfile.TemporaryDirectory(prefix='ci-snapshot-',
                                                 dir=output.parent) as directory:
                    candidate = Path(directory) / 'state'
                    run_id = download(root, args.repo, args.run_id,
                                      int(os.environ.get('GITHUB_RUN_ID', '0')),
                                      token, candidate)
                    if run_id:
                        candidate.rename(output)
            except (PipelineError, OSError, ValueError, KeyError, HTTPError, URLError,
                    zipfile.BadZipFile) as exc:
                print(f'Trusted snapshot unavailable; all targets will be checked: {exc}',
                      file=sys.stderr)
                run_id = 0
            if args.github_output:
                with args.github_output.open('a', encoding='utf-8') as stream:
                    stream.write(f'trusted_run_id={run_id}\n')
            print(f'Trusted snapshot run: {run_id}')
        elif args.command == 'inspect':
            print(json.dumps(inspect_state(root, registry, state, args.platform), sort_keys=True))
        elif args.command == 'restore':
            restore(root, registry, state, args.target, args.platform,
                    args.build_fingerprint, args.test_fingerprint)
        elif args.command == 'package':
            package_entry(root, registry, args.output, args.target, args.platform,
                          args.build_fingerprint, args.test_fingerprint)
        else:
            if not token:
                raise PipelineError('GITHUB_TOKEN is required')
            assemble(root, registry, state, args.output, args.repo, token,
                     args.run_id, args.platform, args.selected_json)
    except (PipelineError, OSError, ValueError, KeyError, HTTPError, URLError,
            zipfile.BadZipFile) as exc:
        print(f'CI snapshot failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

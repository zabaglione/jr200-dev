#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Stage one approved, verified game version for jr200-web-emulator's catalog.

The output is a local directory to copy into the emulator site; this tool
never pushes, publishes, or edits the emulator repository.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from game_project import ProjectError, address, parse_cjr  # noqa: E402
from wiki.generate import WikiError, catalog_entries, load_package, package_path  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
# Mirrors jr200-web-emulator web/game-launch.mjs validateGameCatalog.
WEB_ID = re.compile(r'[a-z][a-z0-9]*(?:-[a-z0-9]+)*')
WEB_VERSION = re.compile(r'\d+\.\d+\.\d+')
WEB_HASH = re.compile(r'[0-9a-f]{64}')
WEB_RUN = re.compile(r'A=USR\(\$[0-9A-F]{4}\)')
MAX_CJR_BYTES = 1024 * 1024
WEB_RUNNER_VERSION = (0, 3, 0)


class ExportError(ValueError):
    """Expected export refusal."""


def validate_web_catalog(value: Any) -> dict[str, dict[str, Any]]:
    if (not isinstance(value, dict) or set(value) != {'schemaVersion', 'games'}
            or value['schemaVersion'] != 1 or not isinstance(value['games'], list)):
        raise ExportError('Web catalog must be {"schemaVersion": 1, "games": [...]}')
    games: dict[str, dict[str, Any]] = {}
    for game in value['games']:
        fields = {'id', 'title', 'version', 'path', 'sha256', 'runCommand'}
        if (not isinstance(game, dict) or set(game) != fields
                or not isinstance(game['id'], str) or len(game['id']) > 64
                or WEB_ID.fullmatch(game['id']) is None
                or not isinstance(game['title'], str) or not game['title'].strip()
                or len(game['title']) > 80
                or not isinstance(game['version'], str)
                or WEB_VERSION.fullmatch(game['version']) is None
                or game['path'] != f'games/{game["id"]}/{game["version"]}/{game["id"]}.cjr'
                or not isinstance(game['sha256'], str)
                or WEB_HASH.fullmatch(game['sha256']) is None
                or not isinstance(game['runCommand'], str)
                or WEB_RUN.fullmatch(game['runCommand']) is None
                or game['id'] in games):
            raise ExportError(f'Invalid web catalog entry: {game!r:.120}')
        games[game['id']] = game
    return games


def select_entry(root: Path, identifier: str, version: str, approval: str,
                 preview: bool = False) -> dict[str, Any]:
    if approval != f'{identifier}@{version}':
        raise ExportError('Export needs --approve <id>@<version> naming the same game '
                          'version (selection guard, not publication authorization)')
    try:
        entries = catalog_entries(root)
    except WikiError as exc:
        raise ExportError(str(exc)) from exc
    matches = [item for item in entries if item['id'] == identifier]
    if not matches:
        raise ExportError(f'{identifier} is not in games/catalog.json')
    entry = matches[0]
    if entry['version'] != version:
        raise ExportError(f'{identifier}: catalog version is {entry["version"]}, not {version}')
    if not preview and WEB_VERSION.fullmatch(version) is None:
        raise ExportError(f'{identifier}: web catalog versions must be x.y.z')
    minimum = entry['_metadata']['release']['minimum_runner_version']
    if (not isinstance(minimum, str) or WEB_VERSION.fullmatch(minimum) is None
            or tuple(map(int, minimum.split('.'))) > WEB_RUNNER_VERSION):
        raise ExportError(f'{identifier}: fixed Web runner 0.3.0 is below required {minimum}')
    if preview:
        if (entry['status'] != 'candidate' or entry['wiki']['publish']
                or entry['_metadata']['release']['publication'] != 'not-published'):
            raise ExportError(f'{identifier}: preview requires an unpublished candidate')
    elif entry['status'] != 'verified' or not entry['wiki']['publish']:
        raise ExportError(f'{identifier}: only verified versions marked for publication '
                          f'can be exported (status={entry["status"]})')
    return entry


def package_members(root: Path, entry: dict[str, Any],
                    packages: Path | None) -> dict[str, bytes]:
    prefix = f'{entry["id"]}-{entry["version"]}/'
    wanted = {'CJR': entry['_metadata']['distribution']['file'], 'LICENSE': 'LICENSE',
              'THIRD_PARTY_NOTICES.md': 'THIRD_PARTY_NOTICES.md',
              'LICENSES/BSD-3-Clause.txt': 'LICENSES/BSD-3-Clause.txt'}
    found = {}
    with zipfile.ZipFile(package_path(root, entry, packages)) as archive:
        names = set(archive.namelist())
        for key, name in wanted.items():
            if prefix + name in names:
                found[key] = archive.read(prefix + name)
    if 'CJR' not in found or 'LICENSE' not in found:
        raise ExportError(f'{entry["id"]}: package lacks the CJR or LICENSE')
    return found


def plan_export(root: Path, identifier: str, version: str, approval: str,
                site_catalog: Path, site: Path | None = None,
                packages: Path | None = None,
                expected_commit: str | None = None,
                preview: bool = False) -> dict[str, Any]:
    if expected_commit is None:
        raise ExportError('An expected source commit is required')
    entry = select_entry(root, identifier, version, approval, preview)
    try:
        package = load_package(root, entry, packages, require_release_ready=True,
                               expected_commit=expected_commit)
    except WikiError as exc:
        raise ExportError(str(exc)) from exc
    members = package_members(root, entry, packages)
    if entry['_metadata']['license'] == 'MIT' and not {
            'THIRD_PARTY_NOTICES.md', 'LICENSES/BSD-3-Clause.txt'}.issubset(members):
        raise ExportError(f'{identifier}: MIT game using BSD SDK lacks full notices/license')
    cjr = members['CJR']
    if (len(cjr) == 0 or len(cjr) > MAX_CJR_BYTES
            or hashlib.sha256(cjr).hexdigest() != entry['artifact_sha256']):
        raise ExportError(f'{identifier}: packaged CJR does not match the catalog hash')
    try:
        parsed = parse_cjr(cjr)
        entry_address = address(entry['_metadata']['run']['entry_address'], 'entry')
    except ProjectError as exc:
        raise ExportError(f'{identifier}: invalid CJR: {exc}') from exc
    if not any(block.start <= entry_address <= block.end for block in parsed['blocks']):
        raise ExportError(f'{identifier}: entry is outside the loaded CJR blocks')
    run_command = f'A=USR(${entry_address:04X})'
    if (entry['_metadata']['run']['command'].upper() != run_command
            or WEB_RUN.fullmatch(run_command) is None):
        raise ExportError(f'{identifier}: run command is not {run_command}')
    try:
        current_bytes = site_catalog.read_bytes()
        current = json.loads(current_bytes.decode('utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise ExportError(f'Cannot read the web catalog: {exc}') from exc
    games = validate_web_catalog(current)
    if site is not None and (site.is_symlink() or not site.is_dir()):
        raise ExportError(f'Unsafe existing site: {site}')
    web_version = version if WEB_VERSION.fullmatch(version) else '0.0.0'
    base = f'games/{identifier}/{web_version}/'
    title = entry['_metadata']['title']
    if web_version != version:
        title += f' [{version}]'
    web_entry = {'id': identifier, 'title': title[:80],
                 'version': web_version, 'path': base + f'{identifier}.cjr',
                 'sha256': entry['artifact_sha256'], 'runCommand': run_command}
    files = {base + f'{identifier}.cjr': cjr, base + 'LICENSE.txt': members['LICENSE']}
    for key in ('THIRD_PARTY_NOTICES.md', 'LICENSES/BSD-3-Clause.txt'):
        if key in members:
            files[base + key] = members[key]
    release = package['release']
    compatibility = release['compatibility']
    notice = {'id': identifier, 'title': web_entry['title'], 'version': version,
              'web_version': web_version, 'mode': 'preview' if preview else 'release',
              'license': entry['_metadata']['license'],
              'source_commit': release['source']['commit'],
              'cjr_sha256': entry['artifact_sha256'],
              'cjr_size': len(cjr), 'entry_address': f'0x{entry_address:04X}',
              'run_command': run_command,
              'runner_contract': compatibility['runner_contract'],
              'sdk_contract': compatibility['sdk_contract'],
              'minimum_runner_version': entry['_metadata']['release']['minimum_runner_version'],
              'package_sha256': entry['package']['sha256'],
              'hardware': 'not_run'}
    files[base + 'EXPORT.json'] = (json.dumps(notice, indent=2) + '\n').encode()
    actions = {}
    for path, payload in files.items():
        existing = site / path if site is not None else None
        if existing is not None and (existing.exists() or existing.is_symlink()):
            if existing.is_symlink() or not existing.is_file():
                raise ExportError(f'Unsafe existing file: {path}')
            if existing.read_bytes() != payload:
                raise ExportError(f'{path} already exists with different bytes; published '
                                  'version paths are immutable, bump the version')
            actions[path] = 'unchanged'
        else:
            actions[path] = 'add'
    previous = games.get(identifier)
    new_games = [web_entry if item['id'] == identifier else item
                 for item in current['games']]
    if previous is None:
        new_games.append(web_entry)
    catalog = {'schemaVersion': 1, 'games': new_games}
    validate_web_catalog(catalog)
    catalog_action = 'unchanged' if previous == web_entry else (
        'add' if previous is None else 'update')
    return {'entry': web_entry, 'previous': previous, 'catalog': catalog,
            'catalog_action': catalog_action, 'files': files, 'actions': actions,
            'notice': notice, 'mode': notice['mode'],
            'base_catalog_sha256': hashlib.sha256(current_bytes).hexdigest()}


def write_export(plan: dict[str, Any], output: Path) -> None:
    if output.is_symlink() or (output.exists() and not output.is_dir()):
        raise ExportError(f'Unsafe staging output: {output}')
    if output.exists() and any(output.iterdir()):
        raise ExportError(f'Output directory is not empty: {output}')
    for path, payload in plan['files'].items():
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    (output / 'game-catalog.json').write_text(
        json.dumps(plan['catalog'], indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    manifest = {path: {'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
                for path, payload in sorted(plan['files'].items())}
    (output / 'export-manifest.json').write_text(
        json.dumps({'schema_version': 2, 'mode': plan['mode'],
                    'catalog_action': plan['catalog_action'], 'entry': plan['entry'],
                    'source': plan['notice'],
                    'base_catalog_sha256': plan['base_catalog_sha256'],
                    'catalog_sha256': hashlib.sha256(
                        (json.dumps(plan['catalog'], indent=2, ensure_ascii=False) + '\n')
                        .encode('utf-8')).hexdigest(),
                    'files': manifest}, indent=2) + '\n',
        encoding='utf-8')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--approve', required=True,
                        help='selection guard <id>@<version>; not publication authorization')
    parser.add_argument('--site-catalog', type=Path, required=True,
                        help="the emulator's current web/game-catalog.json")
    parser.add_argument('--site', type=Path,
                        help='existing site root, to refuse overwriting fixed paths')
    parser.add_argument('--packages', type=Path)
    parser.add_argument('--expected-commit')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--preview-candidate', action='store_true',
                        help='local-only candidate staging; never eligible for publication')
    args = parser.parse_args(argv)
    try:
        plan = plan_export(ROOT, args.game, args.version, args.approve, args.site_catalog,
                           args.site, args.packages, args.expected_commit,
                           args.preview_candidate)
        print(f'catalog {plan["catalog_action"]}: {plan["entry"]["id"]} '
              f'{plan["entry"]["version"]}')
        for path, action in sorted(plan['actions'].items()):
            print(f'{action:9} {path}')
        if args.output is None:
            print('Dry run: pass --output DIR to write the staging files.')
        else:
            write_export(plan, args.output)
            print(f'Staged export in {args.output}')
        return 0
    except (ExportError, WikiError, OSError, zipfile.BadZipFile) as exc:
        print(f'Web export failed: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())

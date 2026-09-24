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


def select_entry(root: Path, identifier: str, version: str, approval: str) -> dict[str, Any]:
    if approval != f'{identifier}@{version}':
        raise ExportError('Export needs --approve <id>@<version> naming the same game '
                          'version (explicit publication approval)')
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
    if WEB_VERSION.fullmatch(version) is None:
        raise ExportError(f'{identifier}: web catalog versions must be x.y.z')
    if entry['status'] != 'verified' or not entry['wiki']['publish']:
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
                expected_commit: str | None = None) -> dict[str, Any]:
    entry = select_entry(root, identifier, version, approval)
    try:
        package = load_package(root, entry, packages, require_release_ready=True,
                               expected_commit=expected_commit)
    except WikiError as exc:
        raise ExportError(str(exc)) from exc
    members = package_members(root, entry, packages)
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
        current = json.loads(site_catalog.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise ExportError(f'Cannot read the web catalog: {exc}') from exc
    games = validate_web_catalog(current)
    base = f'games/{identifier}/{version}/'
    web_entry = {'id': identifier, 'title': entry['_metadata']['title'][:80],
                 'version': version, 'path': base + f'{identifier}.cjr',
                 'sha256': entry['artifact_sha256'], 'runCommand': run_command}
    files = {base + f'{identifier}.cjr': cjr, base + 'LICENSE.txt': members['LICENSE']}
    for key in ('THIRD_PARTY_NOTICES.md', 'LICENSES/BSD-3-Clause.txt'):
        if key in members:
            files[base + key] = members[key]
    release = package['release']
    notice = {'id': identifier, 'title': web_entry['title'], 'version': version,
              'license': entry['_metadata']['license'],
              'source_commit': release['source']['commit'],
              'cjr_sha256': entry['artifact_sha256'],
              'package_sha256': entry['package']['sha256'],
              'hardware': 'not_run'}
    files[base + 'EXPORT.json'] = (json.dumps(notice, indent=2) + '\n').encode()
    actions = {}
    for path, payload in files.items():
        existing = site / path if site is not None else None
        if existing is not None and existing.exists():
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
            'catalog_action': catalog_action, 'files': files, 'actions': actions}


def write_export(plan: dict[str, Any], output: Path) -> None:
    if output.exists() and any(output.iterdir()):
        raise ExportError(f'Output directory is not empty: {output}')
    for path, payload in plan['files'].items():
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    (output / 'game-catalog.json').write_text(
        json.dumps(plan['catalog'], indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    manifest = {path: hashlib.sha256(payload).hexdigest()
                for path, payload in sorted(plan['files'].items())}
    (output / 'export-manifest.json').write_text(
        json.dumps({'schema_version': 1, 'catalog_action': plan['catalog_action'],
                    'entry': plan['entry'], 'files': manifest}, indent=2) + '\n',
        encoding='utf-8')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--approve', required=True,
                        help='explicit approval token <id>@<version>')
    parser.add_argument('--site-catalog', type=Path, required=True,
                        help="the emulator's current web/game-catalog.json")
    parser.add_argument('--site', type=Path,
                        help='existing site root, to refuse overwriting fixed paths')
    parser.add_argument('--packages', type=Path)
    parser.add_argument('--expected-commit')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    try:
        plan = plan_export(ROOT, args.game, args.version, args.approve, args.site_catalog,
                           args.site, args.packages, args.expected_commit)
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

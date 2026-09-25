#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check public game assets before enabling or after updating Wiki links."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wiki.generate import ROOT, WikiError, catalog_entries, render_pages

SITE = 'https://zabaglione.github.io/jr200-web-emulator/'
WIKI_RAW = 'https://raw.githubusercontent.com/wiki/zabaglione/jr200-dev/'


def fetch_bytes(url: str, limit: int) -> bytes:
    request = Request(url, headers={'User-Agent': 'jr200-dev-public-check/1',
                                    'Cache-Control': 'no-cache'})
    with urlopen(request, timeout=20) as response:
        result = response.read(limit + 1)
    if len(result) > limit:
        raise WikiError(f'Public asset exceeds size limit: {url}')
    return result


def check_public(root: Path, *, after_wiki_push: bool = False,
                 packages_dir: Path | None = None,
                 approved_games: str | None = None,
                 expected_commit: str | None = None,
                 fetch=fetch_bytes) -> dict[str, int]:
    entries = [entry for entry in catalog_entries(root) if entry['wiki']['publish']]
    if approved_games is not None:
        expected = ','.join(sorted(f'{entry["id"]}@{entry["version"]}'
                                   for entry in entries))
        if approved_games != expected:
            raise WikiError(f'Approved game selection differs; expected: {expected}')
    try:
        site_catalog = json.loads(fetch(SITE + 'game-catalog.json', 256_000))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WikiError('Public game catalog is not valid JSON') from exc
    if (not isinstance(site_catalog, dict) or site_catalog.get('schemaVersion') != 1
            or not isinstance(site_catalog.get('games'), list)):
        raise WikiError('Public game catalog has the wrong schema')
    site_games = site_catalog['games']
    indexed = {game.get('id'): game for game in site_games if isinstance(game, dict)}
    if len(indexed) != len(site_games):
        raise WikiError('Public game catalog has duplicate or invalid IDs')
    downloads = {}
    for entry in entries:
        game_id = entry['id']
        version = entry['version']
        asset = indexed.get(game_id)
        path = f'games/{game_id}/{version}/{game_id}.cjr'
        if (not isinstance(asset, dict) or asset.get('version') != version
                or asset.get('path') != path
                or asset.get('sha256') != entry['artifact_sha256']):
            raise WikiError(f'Public catalog differs from approved game: {game_id}')
        cjr = fetch(SITE + path, 1_048_576)
        if hashlib.sha256(cjr).hexdigest() != entry['artifact_sha256']:
            raise WikiError(f'Public CJR hash mismatch: {game_id}')
        package = entry['package']
        archive = fetch(package['release_url'], 20_000_000)
        if hashlib.sha256(archive).hexdigest() != package['sha256']:
            raise WikiError(f'Public release hash mismatch: {game_id}')
        downloads[package['file']] = archive
    if packages_dir is not None:
        if packages_dir.is_symlink():
            raise WikiError('Refusing package directory symlink')
        packages_dir.mkdir(parents=True, exist_ok=True)
        for name, archive in downloads.items():
            destination = packages_dir / name
            if destination.is_symlink():
                raise WikiError('Refusing package symlink')
            if destination.exists():
                if destination.read_bytes() != archive:
                    raise WikiError(f'Existing package differs from public release: {name}')
            else:
                destination.write_bytes(archive)
    result = {'games': len(entries), 'cjr': len(entries), 'packages': len(entries),
              'wiki_files': 0}
    if after_wiki_push:
        if expected_commit is None:
            expected_commit = subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
        pages, _ = render_pages(root, packages_dir, False, expected_commit, False)
        for name, content in pages.items():
            public = fetch(WIKI_RAW + name, 20_000_000)
            if public != content:
                raise WikiError(f'Public Wiki file differs from generated source: {name}')
        result['wiki_files'] = len(pages)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--after-wiki-push', action='store_true')
    parser.add_argument('--packages-dir', type=Path)
    parser.add_argument('--approved-games', help='exact sorted comma-separated id@version list')
    parser.add_argument('--expected-commit', help='exact source commit for Wiki post-push validation')
    args = parser.parse_args()
    try:
        result = check_public(args.root.resolve(), after_wiki_push=args.after_wiki_push,
                              packages_dir=args.packages_dir.resolve()
                              if args.packages_dir else None,
                              approved_games=args.approved_games,
                              expected_commit=args.expected_commit)
    except (WikiError, HTTPError, URLError, OSError, ValueError) as exc:
        print(f'Public link check failed: {exc}', file=sys.stderr)
        return 1
    print(json.dumps({'status': 'passed', **result}, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

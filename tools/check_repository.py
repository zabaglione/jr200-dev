# SPDX-License-Identifier: BSD-3-Clause
"""Check initial repository contracts, not game or hardware correctness."""
import json
from pathlib import Path
from ci_plan import validate_registry


def check(root: Path) -> None:
    for path in ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md',
                 'docs/DEVELOPMENT.md', 'docs/CI.md'):
        if not (root / path).read_text(encoding='utf-8').strip():
            raise ValueError(f'Empty required document: {path}')
    targets = validate_registry(json.loads((root / 'ci/targets.json').read_text(encoding='utf-8')))
    catalog = json.loads((root / 'games/catalog.json').read_text(encoding='utf-8'))
    if (not isinstance(catalog, dict) or set(catalog) != {'schema_version', 'games'}
            or type(catalog['schema_version']) is not int or catalog['schema_version'] != 1
            or not isinstance(catalog['games'], list)):
        raise ValueError('Invalid catalog schema')
    # Replace only when real build/test jobs and their required gate are wired.
    if targets or catalog['games'] or any(p.is_dir() for p in (root / 'games').iterdir()):
        raise ValueError('Game pipeline is not enabled. Implement DEV-03 before registering targets.')


if __name__ == '__main__':
    check(Path(__file__).resolve().parents[1])
    print('Repository contracts: OK (no game verification performed)')

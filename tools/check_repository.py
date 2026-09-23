# SPDX-License-Identifier: BSD-3-Clause
"""Check initial repository contracts, not game or hardware correctness."""
import json
from pathlib import Path
from ci_plan import validate_registry
from ci_pipeline import validate_runner_lock, validate_target_contracts
from emulator_runner import load_lock as load_emulator_lock
from game_project import load_rules, validate_project
from jrasm_tool import load_lock
from wiki.generate import catalog_entries


def check(root: Path) -> None:
    for path in ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md',
                 'docs/DEVELOPMENT.md', 'docs/CI.md', 'docs/JRASM.md',
                 'docs/PORTING.md', 'docs/PROJECTS.md', 'docs/RELEASE_AUDIT.md', 'docs/RUNNER.md',
                 'docs/WIKI.md', 'rules/README.md',
                 'sdk/README.md'):
        if not (root / path).read_text(encoding='utf-8').strip():
            raise ValueError(f'Empty required document: {path}')
    load_lock(root / 'toolchain.lock.json', root)
    load_rules(root / 'rules/jr200.json')
    validate_project(root / 'templates/minimal', root / 'rules/jr200.json')
    registry = json.loads((root / 'ci/targets.json').read_text(encoding='utf-8'))
    if registry.get('schema_version') != 2:
        raise ValueError('Current target registry must use schema version 2')
    targets = validate_registry(registry)
    runner = validate_runner_lock(json.loads(
        (root / 'ci/runner.lock.json').read_text(encoding='utf-8')))
    emulator = load_emulator_lock(root / runner['emulator']['lock'])
    if (runner['emulator']['runtime_required']
            and emulator['source']['availability'] != 'release'):
        raise ValueError('Required emulator runner has no release acquisition source')
    validate_target_contracts(root, targets)
    registered_games = {name: target for name, target in targets.items()
                        if target['kind'] == 'game'}
    entries = catalog_entries(root)
    catalog_games = {}
    for item in entries:
        if (item['id'] in catalog_games
                or item['id'] not in registered_games
                or item['project'] != registered_games[item['id']]['project']):
            raise ValueError('Invalid or unregistered game catalog entry')
        catalog_games[item['id']] = item
    actual_directories = {path.name for path in (root / 'games').iterdir()
                          if path.is_dir()}
    declared_directories = {Path(item['project']).name
                            for item in registered_games.values()}
    if actual_directories != declared_directories:
        raise ValueError('CI game targets do not match game directories')


if __name__ == '__main__':
    check(Path(__file__).resolve().parents[1])
    print('Repository contracts: OK (target execution not performed)')

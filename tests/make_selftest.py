# SPDX-License-Identifier: BSD-3-Clause
"""Write games/<id>/src/selftest.inc from games/<id>/tests/selftest.py.

Usage: python3 tests/make_selftest.py <game-id> [--check]
"""
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import load_game_model  # noqa: E402
from selftest_model import fixture_include  # noqa: E402


def load_selftest(ident):
    path = ROOT / 'games' / ident / 'tests/selftest.py'
    spec = importlib.util.spec_from_file_location(ident.replace('-', '_') + '_selftest', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render(ident):
    model = load_game_model(ident)
    data = load_selftest(ident)
    prefix = ''.join(word[0] for word in ident.split('-'))
    return fixture_include(prefix, model.LAYOUT, data.FIXTURES, data.SCRIPTS)


if __name__ == '__main__':
    ident = sys.argv[1]
    output = ROOT / 'games' / ident / 'src/selftest.inc'
    text = render(ident)
    if '--check' in sys.argv:
        raise SystemExit(0 if output.read_text() == text else f'{output} is stale')
    output.write_text(text)
    print(f'wrote {output.relative_to(ROOT)}')

# SPDX-License-Identifier: BSD-3-Clause
"""Machine-independent model of sdk/port.inc for replay expectations.

Game models implement init(), act(action) and state_bytes(); they call
port.win() / port.lose() like the upstream rules call win()/lose(). The model
assumes every key in a replay is processed: replays must leave enough cycles
for effects to finish, otherwise the emulator result will differ from the
model and the runtime test fails.
"""
from __future__ import annotations

KEY_ACTIONS = {0x77: 1, 0x57: 1, 0x73: 2, 0x53: 2, 0x61: 3, 0x41: 3, 0x64: 4, 0x44: 4,
               0x0d: 5, 0x20: 6}
EXIT_KEYS = (0x1b, 0x03)
TITLE, PLAY, CLEAR, LOST, END, HELP = range(6)


class PortModel:
    def __init__(self, game, levels: int, space_reset: bool = True):
        self.game = game
        self.levels = levels
        self.space_reset = space_reset
        self.mode = TITLE
        self.level = 0
        self.confirm = None
        self.exited = False
        self.loss = None
        game.port = self

    # Upstream win()/lose() equivalents.
    def win(self) -> None:
        self.mode = CLEAR

    def lose(self, message: str | None = None) -> None:
        self.mode = LOST
        self.loss = message

    def new_level(self) -> None:
        self.mode = PLAY
        self.loss = None
        self.game.reset()
        self.game.init()

    def key(self, code: int) -> None:
        if self.exited:
            return
        if code in EXIT_KEYS:
            self.exited = True
            return
        action = KEY_ACTIONS.get(code, 0)
        if action == 0:
            return
        if self.confirm is not None:
            self.confirm_key(action)
            return
        if self.mode == TITLE:
            if action == 5:
                self.level = 0
                self.new_level()
            else:
                self.mode = HELP
        elif self.mode == HELP:
            self.mode = TITLE
        elif self.mode == PLAY:
            if action == 6 and self.space_reset:
                self.confirm = 0
            else:
                self.game.act(action)
        elif action == 5:
            if self.mode == CLEAR:
                self.level += 1
                if self.level < self.levels:
                    self.new_level()
                else:
                    self.level -= 1
                    self.mode = END
            elif self.mode == LOST:
                self.confirm = 0
            else:
                self.mode = TITLE

    def confirm_key(self, action: int) -> None:
        if action == 6:
            self.confirm = None
        elif action == 5:
            choice, self.confirm = self.confirm, None
            if choice:
                self.new_level()
        else:
            self.confirm = (action - 1) & 1

    def run(self, replay: list[dict]) -> 'PortModel':
        for event in replay:
            if event['kind'] == 'key' and event['pressed']:
                self.key(int(event['code'], 16) if isinstance(event['code'], str)
                         else event['code'])
        return self

    def mode_bytes(self) -> str:
        return bytes((self.mode, self.level)).hex()


def check_expectations(case, expectations: dict, make_model, max_cycles: int = 250_000_000):
    """Assert every profile's model-owned memory equals the model's prediction."""
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
    from emulator_runner import validate_expectations
    for profile in expectations['runtime']['profiles']:
        with case.subTest(profile=profile['profile']):
            runtime = validate_expectations(expectations, 0x1000, profile['profile'])
            case.assertLessEqual(runtime['max_cycles'], max_cycles)
            port = make_model().run(profile['replay'])
            memory = profile['expect']['memory']
            predicted = {'state': port.game.state_bytes(), 'mode': f'{port.mode:02x}',
                         'level': f'{port.level:02x}'}
            for name in ('state', 'mode', 'level'):
                if name in memory:
                    case.assertEqual(memory[name], predicted[name], name)
            case.assertEqual(port.exited, profile['expect']['stop_reason'] == 'breakpoint')

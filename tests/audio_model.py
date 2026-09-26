# SPDX-License-Identifier: BSD-3-Clause
"""Machine-independent model of sdk/audio.inc (state after N jr_sfx_tick calls).

Tracks and songs are given as Python lists; the model mirrors the 28-byte
JR_AUDIO layout so runner observations can be compared byte for byte.
"""
from __future__ import annotations


class AudioModel:
    """Addresses are symbolic: tracks are (address, [(note, frames), ...])."""

    def __init__(self):
        self.voice = [[0, 0, 0] for _ in range(3)]   # ptr, left, start
        self.loop = 0
        self.sfx_ptr = 0
        self.sfx_left = 0
        self.cnote = 0
        self.rec = 0
        self.tmp = 0
        self.song = 0
        self.start = 0
        self.memory: dict[int, int] = {}
        self.channel = {'F': 0, 'D': 0, 'C': 0}      # sounding note / C count

    def load(self, address: int, data: bytes) -> None:
        for offset, value in enumerate(data):
            self.memory[address + offset] = value

    def byte(self, address: int) -> int:
        return self.memory[address]

    def word(self, address: int) -> int:
        return (self.memory[address] << 8) | self.memory[address + 1]

    # ------------------------------------------------------------- music
    def music_play(self, song: int) -> None:
        self.song = song
        self.loop = self.byte(song)
        for index in range(3):
            self.tmp = index
            self.start = self.word(song + 1 + 2 * index)
            self.voice[index][0] = self.start
            self.voice[index][2] = self.start
            self.voice_start(index)

    def voice_start(self, index: int) -> None:
        pointer = self.voice[index][0]
        if pointer == 0:
            self.voice_stop(index)
            return
        frames = self.byte(pointer + 1)
        if frames == 0:
            if not self.loop:
                self.voice_stop(index)
                return
            pointer = self.voice[index][2]
            self.voice[index][0] = pointer
            frames = self.byte(pointer + 1)
            if frames == 0:
                self.voice_stop(index)
                return
        self.voice[index][1] = frames
        self.out(index, self.byte(pointer))

    def voice_stop(self, index: int) -> None:
        self.voice[index][1] = 0
        self.out(index, 0)

    def out(self, index: int, note: int) -> None:
        if index == 0:
            self.channel['F'] = note
        elif index == 1:
            self.channel['D'] = note
        else:
            self.cnote = note
            if not self.sfx_left:
                self.channel['C'] = note

    def music_stop(self) -> None:
        for voice in self.voice:
            voice[1] = 0
        self.cnote = 0
        self.channel['F'] = self.channel['D'] = 0
        if not self.sfx_left:
            self.channel['C'] = 0

    # ------------------------------------------------------------ effects
    def sfx_play(self, phrase: int) -> None:
        if self.byte(phrase) == 0xfe:
            self.music_play(phrase + 1)
            return
        self.sfx_ptr = phrase
        self.sfx_note()

    def sfx_note(self) -> None:
        self.sfx_left = self.byte(self.sfx_ptr + 1)
        if self.sfx_left == 0:
            self.sfx_stop()
            return
        self.channel['C'] = ('sfx', self.byte(self.sfx_ptr))

    def sfx_stop(self) -> None:
        self.sfx_left = 0
        self.channel['C'] = self.cnote if self.voice[2][1] else 0

    def tick(self) -> None:
        if self.sfx_left:
            self.sfx_left -= 1
            if self.sfx_left == 0:
                self.sfx_ptr += 2
                self.sfx_note()
        for index in range(3):
            self.tmp = index
            voice = self.voice[index]
            if voice[1] == 0:
                continue
            voice[1] -= 1
            if voice[1]:
                continue
            voice[0] += 2
            self.voice_start(index)

    def state_bytes(self) -> bytes:
        """JR_AUDIO bytes 0-19 and 22 (REC, SONG and START are scratch)."""
        out = bytearray()
        for pointer, left, start in self.voice:
            out += bytes((pointer >> 8, pointer & 0xff, left, start >> 8, start & 0xff))
        out += bytes((self.loop, self.sfx_ptr >> 8, self.sfx_ptr & 0xff,
                      self.sfx_left, self.cnote))
        return bytes(out)


def cjr_memory(cjr: bytes) -> dict[int, int]:
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
    from game_project import parse_cjr
    memory: dict[int, int] = {}
    for block in parse_cjr(cjr)['blocks']:
        for offset, value in enumerate(block.data):
            memory[block.start + offset] = value
    return memory


def find_song(memory: dict[int, int], flags: int, tracks: list[bytes]) -> int:
    """Address of the song header whose three track pointers hold `tracks`."""
    found = []
    for address in memory:
        if memory.get(address) != flags:
            continue
        try:
            pointers = [(memory[address + 1 + 2 * i] << 8) | memory[address + 2 + 2 * i]
                        for i in range(3)]
            if all(bytes(memory[p + k] for k in range(len(t))) == t
                   for p, t in zip(pointers, tracks)):
                found.append(address)
        except KeyError:
            continue
    if len(found) != 1:
        raise ValueError(f'song not found uniquely: {found}')
    return found[0]


def find_bytes(memory: dict[int, int], data: bytes) -> int:
    found = [a for a in memory
             if all(memory.get(a + k) == v for k, v in enumerate(data))]
    if len(found) != 1:
        raise ValueError(f'bytes not found uniquely: {found}')
    return found[0]

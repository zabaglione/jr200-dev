# Bounded game loop sample

画面初期化、自作文字、direct key、channel C tone、busy waitを1本のbounded loopで組み合わせます。
`q` を検出するとsoundを停止し、caller stackを保持したまま `RTS` でBASICへ戻ります。

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

default profileはROMなし直接注入です。`local-rom-basic-return` は通常 `MLOAD`、BASIC `USR`、
`q` での終了後に2本目のprobe routineをBASICから呼ぶことで、BASICへ制御が戻ったことも確認します。
direct latchで読んだ `q` はBASICのline bufferにも残るため、profileは空のEnterで消去してからprobeを呼びます。
ROM／FONTは利用者がGit対象外で明示します。いずれも物理実機の証拠ではありません。

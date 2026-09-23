# Minimal JR-200 Project

jr200-devの最小プロジェクトです。自己作成した2命令を `$1000` に配置し、
BASICから `A=USR($1000)` で呼び出して `RTS` で戻る構成です。

```sh
JRASM=/absolute/path/to/jrasm make validate
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
JRASM=/absolute/path/to/jrasm make package
make clean
```

`validate` はROMやFONT、jrasmなしで構造を検査します。`build` は `build/minimal.cjr` と
依存・検証レポートを生成します。`run` は固定WASM runnerでCJRをRAMへ直接配置し、
`NOP`、`RTS`、callerの戻り先を確認します。`package` は `build/package/` に配布ZIPを作ります。

このROMなしprofileはエミュレータCPU実行の確認であり、BASIC起動やカセット読込みではありません。
権利を確認したローカルROM／FONTがある場合は、rootの `tools/emulator_runner.py` へ
`--profile local-rom-mload --rom ... --font ...` を指定すると、通常 `MLOAD` 経路を確認できます。
Release bundle未公開のため配布metadataは `emulator=not_run` のままです。CJR生成や直接注入の成功を
通常 `LOAD`／`MLOAD`、実機動作の証拠として扱わないでください。

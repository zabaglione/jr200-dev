# Sound channel C sample

MN1271 channel Cへ非0 countとenable controlを書き、busy wait後に停止します。
fixed runnerはPCM frame数、非0 sample数、drop数を検査します。

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

PCM観測は固定エミュレータの実行結果であり、物理JR-200の音程・音量・波形確認ではありません。

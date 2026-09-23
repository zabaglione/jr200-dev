# Screen and PCG sample

画面を空白・白文字／黒背景で初期化し、許諾不要の自作8×8 patternをuser character 0へ転送して、
中央付近の1 cellへ表示します。`screen.inc` の動的cell描画とPCG code範囲検査を使用します。

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

固定runnerはVRAM、attribute、PCG bytesとframebuffer hashを確認します。これは物理JR-200の表示確認ではありません。

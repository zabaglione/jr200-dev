# Joystick input sample

JR-200 BASIC ROMの入力走査 `$E8CB` を呼び、direct-page `$0002`（1P）と `$0003`（2P）から
active-lowのジョイスティック状態を取得し、1P／2Pの状態を画面へ連続表示します。
押されている方向・ボタンは文字、離されている入力は`.`で示し、右端にraw値を16進表示します。
RETURNを押すとBASICへ戻ります。`jr_joystick_pressed` は反転後の押下bitを返します。

| bit | 入力 |
| ---: | --- |
| `$01` | 上 |
| `$02` | 下 |
| `$04` | 左 |
| `$08` | 右 |
| `$10` | Aボタン |
| `$20` | Bボタン |

ビルド後、権利を確認したローカルROM／FONTを指定して、通常の`MLOAD`経路で試験します。

```sh
JRASM=/absolute/path/to/jrasm make build
python3 ../../tools/emulator_runner.py \
  run \
  --project . \
  --bundle /absolute/path/to/emulator/build/emscripten/web \
  --profile local-rom-joystick \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin
```

試験replayは1Pへ`$EA`（上・左・A）、2Pへ`$D5`（下・右・B）を与え、画面の
`1P: U . L . A .   EA`、`2P: . D . R . B   D5`、raw値と押下bit`$15`／`$2A`を確認します。
RETURN replayでBASIC復帰直前まで進めます。ジョイスティックreplayには対応する
エミュレータbundleが必要です。現行の`emulator.lock.json`はsystem API 9を固定しており、
上記コマンドは既定のlockを使ってbundleのsize・SHA-256・APIを検査します。
別のbundleを試す場合だけ、そのbundle専用のlockを`--lock`で明示してください。
ROM／FONTは本projectへ含めません。物理ジョイスティックと実機の動作確認は別です。

入力走査の呼出し方は、inufuto氏の
[Cate_examples JR-200 ScanKeys.asm](https://github.com/inufuto/Cate_examples/blob/main/jr200/mazy2/ScanKeys.asm)
とも照合しています。本sampleは同ファイルをコピーせず、JR-200用SDKの呼出し規約として独自に記述しています。

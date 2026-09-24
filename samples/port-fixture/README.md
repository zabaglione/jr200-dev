# Port SDK fixture

JR100dev移植用SDK（`session`、`keys`、`keyscan`、`keyrepeat`、`effect`、`gfx`、`font`、`pcg`、`frame`、`math`、`sfx`、`port`）を
1本で通す、2面だけの3×3十字反転fixtureです。ゲーム作品ではなく、SDKの回帰試験用です。

| key | 動作 |
| --- | --- |
| `W` / `A` / `S` / `D` | セル選択 |
| `RETURN` | 十字反転（タイトルでは開始） |
| `SPACE` | やり直し確認（初期選択NO） |
| `ESC` / `CTRL+C` | BASICへ戻る |
| タイトル画面で`T` | 保持入力の検査モード。`W`の押下・リピート・離上をRAMへ記録し、`ESC`/`CTRL+C`でBASICへ戻る |
| タイトル画面で`E` | 待機しない色演出の検査モード。`W`で演出を開始し、進行中の`D`入力とtickをRAMへ記録する |

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

合成profileは、タイトル→操作→反転演出→確認dialog→2面クリア→終了とBASIC復帰
（PCG、画面、文字RAMの復元）を状態値で確認します。保持入力用profileは`W`の短押しで
押下1・リピート0・離上1、長押しで押下1・リピート複数・離上1を検査し、離上後の
repeat状態の消去と`ESC`/`CTRL+C`後の画面・キーmask復帰も確認します。これは固定エミュレータの
キーボードMCU modelによる結果です。走査後にPCG転送（`jr_copy`）を挟んでも走査状態が
壊れないことも確認します。物理JR-200では未確認です。
`E`の合成profileは色演出の20 step中も通常tickと`D`入力が進み、終了後に属性RAMが
復元することを確認します。`jr_port_animate`自体は同期待機であり、この別APIとは混同しません。

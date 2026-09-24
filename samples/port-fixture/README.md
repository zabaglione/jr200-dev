# Port SDK fixture

JR100dev移植用SDK（`session`、`keys`、`gfx`、`font`、`pcg`、`frame`、`math`、`sfx`、`port`）を
1本で通す、2面だけの3×3十字反転fixtureです。ゲーム作品ではなく、SDKの回帰試験用です。

| key | 動作 |
| --- | --- |
| `W` / `A` / `S` / `D` | セル選択 |
| `RETURN` | 十字反転（タイトルでは開始） |
| `SPACE` | やり直し確認（初期選択NO） |
| `ESC` / `CTRL+C` | BASICへ戻る |

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

合成profileは、タイトル→操作→反転演出→確認dialog→2面クリア→終了とBASIC復帰
（PCG、画面、文字RAMの復元）を状態値で確認します。物理JR-200では未確認です。

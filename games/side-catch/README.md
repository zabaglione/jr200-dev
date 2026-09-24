# SIDE CATCH

32×24文字画面の隣り合うtargetを捕まえる、短い自作reaction gameです。
最初のroundはplayerの右隣にtargetが出ます。`D` で捕まえ、`R` で再開すると左隣に出るので
`A` で捕まえます。`Q` でいつでも終了し、caller stackを保ったままBASICへ戻ります。

## 操作

| key | 動作 |
| --- | --- |
| `D` | 1回目の右targetを捕まえる |
| `A` | 再開後の左targetを捕まえる |
| `R` | 捕獲後に次のroundを開始する |
| `Q` | ゲームを終了してBASICへ戻る |

同じkeyを連打する方式ではなく、roundごとに必要なkeyを切り替えます。direct key latchはreleaseで
自動的に0へ戻る契約ではないため、この作品は異なる操作eventの遷移を処理します。

## Build and run

```sh
export JRASM=/absolute/path/to/jrasm
export RUNNER_BUNDLE=/absolute/path/to/emulator/bundle
make build
make run
python3 ../../tools/emulator_runner.py run \
  --project . --bundle "$RUNNER_BUNDLE" --profile synthetic-screenshot
python3 ../../tools/emulator_runner.py run \
  --project . --bundle "$RUNNER_BUNDLE" --profile local-rom-basic-return \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin
make package
```

CJRを通常 `MLOAD` した場合は、BASICから `A=USR($1000)` で開始します。
固定runnerのdefault profileはROMなし直接注入です。`local-rom-basic-return` は利用者が権利を確認した
ローカルROM／FONTを明示し、通常MLOAD、2 round、Q終了、BASIC復帰後のprobeまで確認します。
`synthetic-screenshot` は2回目のround中に停止し、ROMやメーカーFONTを使わないWiki画面例を固定します。
候補packageは上記3 profileのreportが同じCJRと期待値に結び付いている場合だけ生成できます。
ROM／FONTは本リポジトリやpackageへコピーしません。

自作PCG patternは `src/glyphs.inc` にあり、外部素材はありません。固定エミュレータでの表示・入力・
PCMとローカルROMでのBASIC復帰は確認対象ですが、物理JR-200、実カセット、実機音声は未確認です。

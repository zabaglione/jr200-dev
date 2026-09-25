# SIDE CATCH

32×24文字画面の隣り合うtargetを捕まえる、短い自作reaction gameです。
最初のroundはplayerの右隣にtargetが出ます。`D` で捕まえ、`R` で再開すると左隣に出るので
`A` で捕まえます。`Q` でいつでも終了し、画面・文字RAM・PCGを復元してBASICへ戻ります。

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
python3 ../../tools/emulator_runner.py run \
  --project . --bundle "$RUNNER_BUNDLE" --profile local-rom-title \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin \
  --screenshot media/title.png --self-font ../../sdk/font_data.inc
make package
```

CJRを通常 `MLOAD` した場合は、BASICから `A=USR($1000)` で開始します。
固定runnerのdefault profileはROMなし直接注入です。`local-rom-basic-return` は利用者が権利を確認した
ローカルROM／FONTを明示し、通常MLOAD、2 round、Q終了、BASIC復帰後のprobeまで確認します。
`synthetic-screenshot` は合成回帰専用です。Wiki媒体は`local-rom-title`／`goal`／`play`で
所有ROM/FONTの通常MLOAD/USRから撮影し、自作字形を照合します。動画は起動中のBASICを
除外した実ゲーム画面・PCMです。撮影済みの同名fileは上書きしないため、上記の撮影commandは
出力先がない場合の例です。候補packageには全合成・所有ROM/FONT profileの合格reportが必要です。
対象は`--profile synthetic-sound`、`--profile local-rom-goal`、
`--profile local-rom-play`も含みます。`synthetic-sound`は音声の回帰試験であり、
所有ROM/FONTでの合否判定は`local-rom-*`を基準にします。
ROM／FONTは本リポジトリやpackageへコピーしません。

自作PCG patternは `src/glyphs.inc`、自作文字は共通SDKの`font_data.inc`にあり、外部素材はありません。
固定エミュレータでの表示・入力・
PCMとローカルROMでのBASIC復帰は確認対象ですが、物理JR-200、実カセット、実機音声は未確認です。

# RELIC DIVE for JR-200

`jr100dev` のJR-100標準16 KB版 `RELIC DIVE 1.6.1` を、ゲーム規則とダンジョン生成を
維持してJR-200へ移植したターン制ローグライクです。画面属性だけを追加し、壁、床、階段、
アイテム、プレイヤー、敵をJR-200の8色で控えめに色分けします。

## 操作

| key | 動作 |
| --- | --- |
| `W` / `X` / `A` / `D` | 上／下／左／右 |
| `Q` / `E` / `Z` / `C` | 斜め4方向 |
| `S` | その場で1ターン待つ |
| `RETURN` | 決定、メニュー |
| `SPACE` | 戻る |
| `ESC` または `CTRL-C` | ゲームを終了してBASICへ戻る |

ジョイスティック入力は、JR-100版とJR-200の配線契約が異なるため初回移植では未対応です。

## Build and run

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

CJRを `MLOAD` した後、BASICから `A=USR($1000)` で開始します。ゲーム中は専用stackを使い、
終了時にcaller stack、割り込み状態、Key-On mask、border、PCG bank 1、画面属性を復元します。

ローカルのROM／FONTを使って、通常の `MLOAD`、起動、横スクロール後の文字・属性を確認する
replayは次のとおりです。ROMとFONTはリポジトリへ追加しません。

```sh
python3 ../../tools/emulator_runner.py run \
  --project . \
  --bundle /absolute/path/to/emulator/bundle \
  --profile local-rom-scroll \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin
```

移植固有ソースはMIT Licenseです。CJRへ組み込む共通SDKはBSD-3-Clauseで、配布packageには
両ライセンス全文と [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) を収録します。
詳しい上流revision、ファイルhash、変換内容は [`UPSTREAM.md`](UPSTREAM.md) に記録します。
固定エミュレータでのbuild／実行結果と物理JR-200での
結果は別々に扱い、未実施の項目を成功とは記載しません。

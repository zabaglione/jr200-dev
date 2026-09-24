# LUMEN CROSS

選んだ場所と上下左右の明かりを反転し、5×5の盤をすべて消灯する全18面のパズルです。
JR100devの`LUMEN CROSS 2.0.0`（`games/lumen_cross/rules.py`）を仕様として、JR-200向けに
M6800アセンブリで作り直しました。面の生成式、60回の操作上限、PAR表は上流と同じです。

## 目的と勝敗

- すべての明かりを消すと面クリア。最短回数PAR以内なら`PERFECT CIRCUIT`を表示します。
- 1面につき60回反転しても消せなければ失敗（`SIXTY SWITCHES WERE NOT ENOUGH`）。
- 18面をクリアすると`ALL STAGES CLEAR - THANK YOU`で終わります。

## 操作

| key | 動作 |
| --- | --- |
| `W` / `A` / `S` / `D` | セルを選ぶ（端では止まる） |
| `RETURN` | 選んだセルの十字（最大5個）を反転。タイトルでは開始、クリア後は次の面 |
| `SPACE` | この面のやり直し確認。初期選択はNO、`A`/`D`で選び`RETURN`で確定、`SPACE`で取消 |
| `ESC` / `CTRL+C` | ゲームを終えてBASICへ戻る |

タイトルで`RETURN`以外の操作キーを押すと遊び方の画面、もう一度押すとタイトルへ戻ります。
失敗後の`RETURN`もやり直し確認を開きます。反転の演出中に押したキーは捨てられます。
ジョイスティックには対応していません。

## 最初の目標と序盤のコツ

- 盤の`^`は、今のカーソルで`RETURN`を押したときに反転する明かりの予告です。
- 同じセルを2回押すと元に戻ります。押す順番は結果に関係しません。
- 最初の目標はステージ1を4回（PAR）で消すことです。上の行から順に、残った明かりの真下を押して
  いく「追いかけ」で最下段まで運び、残り方から最上段の押し方を考え直します。

## 画面

右側の`PRESSES`は使った回数、`REMAIN`は60回までの残り、`PAR`はその面の最短回数です。
明かりは点灯が黄色の格子模様、消灯が青い枠、反転中は水色で細くなる5段階の形で表示し、
色が見分けにくい場合も形で状態が分かるようにしています。

## 起動

1. JR-200（またはエミュレータ）でCJRを通常の`MLOAD`で読み込みます。
2. BASICから`A=USR($1000)`を実行します。
3. 終了後はBASICへ戻り、画面・ユーザー文字・文字RAMは起動前の状態に戻ります。

標準のRAM構成で、ロード先は`$1000-$2FFF`、作業領域は`$3000-$4FFF`（専用stackを含む）です。

## 開発

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
make game-play PROJECT=games/lumen-cross WEB_SITE=/absolute/path/to/emulator/site  # repository root
```

`tests/expectations.json`の各profileのRAM期待値は`tests/model.py`（上流ルールのPythonモデル）から
計算したもので、エミュレータの出力を記録したものではありません。`synthetic-all-stages`は18面を
最短解で解き切るreplayです。PARが各面の最短回数であることは、全解の列挙で`tests/test_lumen_cross.py`が
確認します。

## 検証の範囲

| 区分 | 状態 |
| --- | --- |
| ROMなし合成実行（固定エミュレータ） | タイトル、説明、開始、端、2回押し、やり直し確認、60回失敗と再挑戦、18面クリア、BASIC復帰を確認 |
| 所有ROM/FONTでの通常`MLOAD`/`USR` | 未実施 |
| 物理JR-200 | 未実施 |

## ライセンス

移植固有のソースと絵は上流と同じMIT License（`LICENSE`）です。CJRに組み込むjr200-dev SDKは
BSD-3-Clauseで、[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)に対象moduleを記載します。
上流の由来は[`UPSTREAM.md`](UPSTREAM.md)を参照してください。

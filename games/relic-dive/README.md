# RELIC DIVE

自動生成される迷宮を1ターンずつ降り、最下層の遺物を持ち帰るターン制ローグライクです。
JR100devの`RELIC DIVE 1.6.1`（JR-100標準16 KB版）を、ゲーム規則・乱数・迷宮生成・敵・品物を
変えずにJR-200へ移植しました。JR-200の属性RAMで、壁・床・階段・品物・主人公・敵を8色で色分けします。

## 目的と勝敗

- 階段から次の階へ降り、最下層に置かれた遺物を拾うとクリアです。
- HPが0になると冒険は失敗です。食料が0になると2ターンごとにHPを失います。
- 難易度（EASY 5階、NORMAL 10階、HARD 20階）をタイトルで選びます。
- 考えている間やメニュー操作中は時間が進みません。

敵15種・品物の効果・難易度ごとの数値は上流と同じです。一覧は上流の説明
（[RELIC DIVE for JR-100](https://github.com/zabaglione/jr100dev/blob/9a3921c4371d84c55fc468879dbed2f00fe42960/games/relic_dive/README.md)）
を参照してください。JR-100版のプレイURL、PRG、パッド操作はこの版には当てはまりません。

## 操作

| key | 動作 |
| --- | --- |
| `W` / `X` / `A` / `D` | 上／下／左／右へ移動。敵の方向へ移動すると攻撃 |
| `Q` / `E` / `Z` / `C` | 斜め4方向へ移動 |
| `S` | その場で1ターン待つ |
| `RETURN` | メニューを開く、決定 |
| `SPACE` | 戻る |
| `ESC` または `CTRL+C` | ゲームを終了してBASICへ戻る |

JR-200の移植版はキーボードだけで操作します。ジョイスティックは、JR-100版とJR-200で配線の
契約が異なるため未対応です。

## 最初の目標と序盤のコツ

- 最初の目標は、1階を探索して下り階段を見つけ、メニューの`DESCEND`で2階へ進むことです。
- 敵とは通路で1体ずつ戦います。HPが減ったら`S`で待つより、先に安全な場所へ下がります。
- 食料は拾っただけでは食べません。持ち物（`INVENTORY`）から使います。

## 画面

上2行が階層・HP・食料・レベル・攻撃力・防御力・金、下2行がメッセージと操作案内です。
64×32マスの迷宮を32×20マスの範囲でスクロール表示します。壁は水色、主人公は緑、敵は赤系など、
上流の絵柄（PCG）に属性色を加えました。色だけに頼らず、絵柄でも見分けられます。

## 起動

1. CJRを通常の`MLOAD`で読み込みます。
2. BASICから`A=USR($1000)`を実行します。
3. 終了時はcaller stack、割り込み状態、Key-On mask、PCG bank 1、画面属性を起動前に戻します。

## 開発

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

利用権のあるROM／FONTでの通常`MLOAD`・起動・スクロール確認は`local-rom-scroll`で行います。
ROMとFONTはリポジトリへ追加しません。

```sh
python3 ../../tools/emulator_runner.py run --project . \
  --bundle /absolute/path/to/emulator/bundle --profile local-rom-scroll \
  --rom /absolute/local/path/to/JR200.rom --font /absolute/local/path/to/FONT.bin
```

## 検証の範囲

| 区分 | 状態 |
| --- | --- |
| ROMなし合成実行（固定エミュレータ） | タイトル、1階の移動と待機、最初の戦闘、音（channel C）、ESCでの復帰と資源の復元を確認 |
| 所有ROM/FONTでの通常`MLOAD`/`USR` | profileは定義済み。このリポジトリの検証環境では未実施 |
| 物理JR-200 | 未実施 |

ROMなし合成実行ではメーカーFONTを読み込まないため、ギャラリーの画面にはHUDの文字が出ません。
文字codeと属性は実行時のメモリ期待値で別に固定しています。

## ライセンス

移植固有のソースはMIT License（`LICENSE`）です。CJRへ組み込む共通SDKはBSD-3-Clauseで、
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)に記載します。上流revision、ファイルhash、
変換内容は[`UPSTREAM.md`](UPSTREAM.md)に記録します。

# ゲームプロジェクト契約

## 新規作成

```sh
make new-project ID=my-game TITLE="My Game"
```

`games/my-game/` に最小テンプレートを複製します。この操作は既存のCIや公開候補を暗黙に変更しないため、
生成したゲームを `ci/targets.json` や `games/catalog.json` へ自動登録しません。構造と実行条件を確認後、
CI対象は `ci/targets.json` へ明示登録し、公開候補にする場合だけ `games/catalog.json` へ追加します。

任意の場所へ試験生成する場合:

```sh
python3 tools/game_project.py new \
  --id my-game \
  --title "My Game" \
  --destination /absolute/path/to/my-game
```

## ディレクトリ

| パス | 用途 |
| --- | --- |
| `src/` | jrasmの主ソースと再帰include |
| `assets/` | CJR生成へ組み込む素材。全ファイルを `assets/manifest.json` へ由来付きで列挙 |
| `tests/` | 構造・実行条件・期待値。紹介文ではない |
| `build.json` | load、entry、メモリ領域、実依存、起動・復帰条件 |
| `game.json` | タイトル、version、配布形式、利用者向けロード／実行条件、検証状態 |
| `README.md` | 遊び方と開発説明 |
| `media/` | 紹介用画像。ビルド入力ではない |
| `build/` | CJR、依存一覧、検証report、package。Git対象外 |

`assets/` と `media/` は同じ画像形式でも意味が異なります。前者の変更はCJRを無効化し、
後者は紹介情報だけを無効化します。

## build.json version 1

`templates/minimal/build.json` を正規例とします。

- `source`: jrasmへ渡す1個の主 `.asm`。
- `output`: `build/` 直下へ生成する安全な `.cjr` ファイル名。
- `load_address`: 最初の宣言領域の先頭。現在は標準user RAM `$0800-$7FFF` のみ許可。
- `entry_address` / `entry_symbol`: code領域と、jrasm symbol listの双方に存在するentry。
- `regions`: endを含む範囲。`code` と `data` は重複不可。
- `inputs.assembly`: 主ソースを含む、再帰 `.include` の正確な一覧。過不足を拒否。
- `inputs.sdk`: 再帰 `.include` で使用する `sdk/` 以下の共有moduleをリポジトリ相対pathで列挙。
  project外のincludeはこの領域だけを許可し、過不足を拒否。
- `inputs.assets`: `assets/manifest.json` と一致する組込み素材一覧。
- `execution`: CJR、BASIC `USR`、`RTS`、caller stackを明記した現在の起動契約。

`NBA` は未文書opcode `$14` に相当し、実機互換を確認できないため拒否します。
`.db 0x14` はdataと命令を静的に区別できないため拒否対象ではありません。

## asset manifest

空の例:

```json
{
  "schema_version": 1,
  "assets": []
}
```

素材を追加する場合は `path`、`kind`、`source`、`author`、`license`、
`redistributable: true` を持つentryを追加し、同じ `assets/<path>` を
`build.json` の `inputs.assets` に列挙します。未列挙ファイル、`redistributable: true` でない素材、
およびmanifestで `rom`、`firmware`、`manufacturer_font` と申告された素材を拒否します。
内容を自動判定する仕組みではないため、kindや由来を偽った素材まで検出できるとは扱いません。
privateリポジトリでも権利条件は変わりません。

## 単体操作

プロジェクト自身から:

```sh
cd games/my-game
make validate
JRASM=/absolute/path/to/jrasm make build
JRASM=/absolute/path/to/jrasm make package
make clean
```

リポジトリrootから、対象を明示して実行する場合:

```sh
make game-validate PROJECT=games/my-game
JRASM=/absolute/path/to/jrasm make game-build PROJECT=games/my-game
make game-run PROJECT=games/my-game RUNNER_BUNDLE=/absolute/path/to/emulator/bundle
JRASM=/absolute/path/to/jrasm make game-package PROJECT=games/my-game
make game-clean PROJECT=games/my-game
```

これらは指定プロジェクトだけを操作し、全ゲームへ再帰しません。`validate` はPythonと
プロジェクト内ファイルだけで実行でき、ROM、FONT、jrasmを要求しません。

`build` はCJR header/block/checksum、load範囲、entry symbol、実依存を検査し、
`build/build-report.json` を生成します。`package` はCJR、README、game metadata、
build report、`SHA256SUMS` とmetadataに対応するライセンス全文を固定時刻のZIPに収めます。
BSD-3-Clause作品はroot `LICENSE`、MIT作品は作品directoryの `LICENSE` を使います。
BSD-3-Clauseの共通SDKを組み込むMIT作品は、使用moduleを列挙した作品directoryの
`THIRD_PARTY_NOTICES.md` とroot BSD全文を `LICENSES/BSD-3-Clause.txt` として併載します。

`run` は `tests/expectations.json` version 2のdefault profile、入力replay、期待値を固定WASM runnerへ渡し、
`build/runtime-report.json` とprofile別reportを生成します。reportはCJRとexpectationsのhashを保持します。
bundleのversion、source commit、file digestを照合し、
異なるbundle、timeout、非0終了、期待値不一致を拒否します。詳細は
[固定エミュレータrunner契約](RUNNER.md)を参照してください。

schema version 2の作品packageは、合成実行とlocal-ROM通常cassette実行の両report、固定CJR、
README、metadata、license、build report、release manifest、内部checksumを含みます。dirty treeからも
候補確認用packageは作れますが、manifestの `release_ready` はfalseとなり公開入力には使用できません。

## ブラウザでの試遊

`game-run`はheadlessの固定runnerで期待値を検査し、`game-play`は人がブラウザで遊ぶための
ローカル配信です。後者は合否を判定しません。

```sh
# エミュレータ側で一度だけ作る固定版Web一式（jr200-web-emulatorのREADME参照）
#   make wasm            -> build/site
JRASM=/absolute/path/to/jrasm make game-build PROJECT=games/my-game
make game-play PROJECT=games/my-game WEB_SITE=/absolute/path/to/jr200-web-emulator/build/site
```

`tools/game_play.py`は次だけを行います。

- `build/build-report.json`の入力hashと現在のsource／SDK／素材、CJRのhashを照合し、古いCJRなら停止する。
  自動buildはしない。
- 指定したsiteに`stage_web.py`のUI fileと`LICENSES/`があり、`jr200_codec.mjs`／`.wasm`が
  `emulator.lock.json`のsize／SHA-256と一致することを確認する。エミュレータはbuildしない。
- 一時directoryへUI、選んだ1作品のCJRとライセンス、1件だけの`game-catalog.json`、開発版bannerを置き、
  `127.0.0.1`（既定port 8765）で配信する。directory一覧は返さず、リポジトリや`local-data/`は配信しない。
  `-dev`等の版はWebカタログの形式に合わせて`0.0.0`のpathへ置き、表示名に元の版を付ける。
- `http://127.0.0.1:8765/?game=<id>`を開く。CJRはカセットへセットされるだけなので、利用者が
  ROM／FONTをページで選び、`MLOAD`と作品の`A=USR(...)`を入力する。Ctrl-Cで停止し一時directoryを消す。

ROM／FONTの保存はブラウザのoriginごとです。`PORT=`でportを変えると保存も別になります。
音声はページ上の操作後に有効になります。

## 共通SDKとsample

`sdk/` のmoduleはprojectへ複製せず、主sourceから相対includeし、使用fileを `inputs.sdk` に列挙します。
ビルダーはincludeの実体がrepository内の `sdk/` に収まることと、宣言が過不足なく一致することを検査します。
build reportでは共有入力を `@repo/sdk/...` としてhash化し、ローカル絶対pathは記録しません。

`samples/screen`、`samples/input`、`samples/joystick`、`samples/sound`、
`samples/game-loop`、`samples/port-fixture` が機能別・移植用のsampleです。
各sampleは自身のdirectoryで `make build` でき、使わないmoduleを依存へ含めません。
`joystick`はROM／FONTを用いる通常`MLOAD` profileのみ対応するため、`make run`ではなく
[専用手順](../samples/joystick/README.md)で`--rom`／`--font`を指定します。
ほかのsampleは`make run`で既定の合成profileを実行できます。
`game-loop` のlocal ROM profileは通常 `MLOAD`、BASIC `USR`、BASIC復帰probeまで確認します。
物理JR-200での表示、keyboard、音声、時間は未確認です。

## 検証境界

| report項目 | 意味 |
| --- | --- |
| `structure=passed` | JSON、path、依存、素材由来、メモリ宣言が静的契約を満たした |
| `assembler=passed` | 固定versionのjrasmが終了code 0でCJRを生成した |
| `cjr_layout=passed` | CJR構造、checksum、load範囲、entryが一致した |
| `emulator=passed`, `cassette_path=memory_injection` | 固定エミュレータでROMなし直接注入profileが合格。LOAD／MLOADの証拠ではない |
| `emulator=passed`, `cassette_path=normal` | ローカルROM／FONTを使う通常cassette profileが合格。実機の証拠ではない |
| `emulator=not_run` | BASIC起動、表示、入力、音声をまだ実行していない |
| `hardware=not_run` | 実カセットや実機では未確認 |

構造・assembler合格を、エミュレータや実機の動作成功へ読み替えないでください。

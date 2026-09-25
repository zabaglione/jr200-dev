# JR-200 Game Development Kit

JR-200向けゲームの開発ルール、共通ルーチン、サンプル、ゲームの検証・公開環境を整備するプロジェクトです。
エミュレータ本体は [jr200-web-emulator](https://github.com/zabaglione/jr200-web-emulator) で管理します。
アセンブラは既存の [jrasm](https://github.com/ypsitau/jrasm) を外部ツールとして利用し、独自版を開発・同梱しません。

**7作品の初版配信とWiki公開を確認しました。** 要求仕様、CIの影響範囲判定、外部jrasmの固定版・doctor・
合成fixtureに加え、JR-200ルール、プロジェクト契約、最小CJRテンプレート、選択的CI、
固定エミュレータrunner、画面／入力／ジョイスティック／音声／待機module、6つのsample、最初のゲーム
`SIDE CATCH`、JR-100からカラー移植したローグライク`RELIC DIVE`、固定package、
Wiki preview／dry-run同期を整備しています。
runnerは固定Release資産として公開済みで、ZIPの匿名取得とdigestを確認しています。
Mac arm64新規クローンとLinux CIでROMなし合成実行を確認し、合成runtimeをCI必須条件にしました。
7作品のclean-source ZIPを固定ハッシュ付きで公開
[Release](https://github.com/zabaglione/jr200-dev/releases/tag/games-2026-09-25)へ登録しました。
公開[Wiki](https://github.com/zabaglione/jr200-dev/wiki/All-Games)には7作品ページとワンクリック実行リンクを同期済みです。
[公開Webエミュレータ](https://zabaglione.github.io/jr200-web-emulator/)では7作品の
固定CJRを配信し、所有ROM/FONTを使うブラウザで起動と開始入力を確認しました。
開発リポジトリ、Releaseの7 ZIP、Wikiの22ページ・35媒体は匿名取得を確認しました。
物理JR-200での動作とChrome以外の全ブラウザ受入は未確認です。
構造検査やCJR生成の成功は、エミュレータや実機の動作確認を示しません。

## 開発方針

- Macを主な開発環境とし、Linuxでもビルドを再現できる構成にします。
- CJRを基本配布形式とし、WAVは検証条件を明示して必要な作品だけ生成します。
- エミュレータのビルドはこのリポジトリのゲームCIから呼び出しません。
- 変更ゲームとその依存先だけをビルド・試験し、紹介文だけの変更ではゲームを再ビルドしません。
- ゲームの説明とメタデータを正本とし、検証済みの公開版をWikiで案内します。

仕様は [開発範囲](docs/DEVELOPMENT.md)、機種固有条件は [JR-200開発ルール](rules/README.md)、
ゲームの構造と操作は [ゲームプロジェクト契約](docs/PROJECTS.md)、runnerは
[固定エミュレータrunner契約](docs/RUNNER.md)、CIは [選択的CI](docs/CI.md)、
Wikiは [Wiki生成とローカル同期](docs/WIKI.md)、JR100devからの移植は [移植契約](docs/PORTING.md)、
公開可否は [初版候補の公開前監査](docs/RELEASE_AUDIT.md)、
作業順序は [開発計画Issue](https://github.com/zabaglione/jr200-dev/issues/1) を参照してください。

## 初期設定の検査

Python 3.10以降とGitだけで実行できます。jrasm、C++、Emscriptenのインストールは不要です。

```sh
git clone https://github.com/zabaglione/jr200-dev.git
cd jr200-dev
make check
```

変更パスから影響候補を表示する例:

```sh
python3 tools/ci_plan.py --changed README.md
```

これは対象選択の計画表示です。ビルドやテストの実行、成功キャッシュによる検証省略は行いません。
`templates/minimal`、`samples/`、7作品をCI対象へ登録し、共有SDK変更が
利用targetだけへ波及することを検査します。catalogの7作品は固定済みの公開版です。

最小テンプレートはROMやFONTなしで構造検査できます。CJR生成には固定jrasmを指定します。

```sh
make template-validate
JRASM="/absolute/path/to/jrasm" make template-build
RUNNER_BUNDLE="/absolute/path/to/emulator/build/emscripten/web" make template-run
JRASM="/absolute/path/to/jrasm" make template-package
```

新規ゲームの作成とゲーム単体の操作方法は [ゲームプロジェクト契約](docs/PROJECTS.md) を参照してください。
所有ROM/FONTでの通常MLOAD・画面・入力を素早く確認するには、
同文書の `make game-accept-local` を利用できます。公開前には全profileと候補ZIPを検査します。
共有moduleと機能別sampleは [SDK README](sdk/README.md) を参照してください。

jrasmは本リポジトリへ同梱しません。固定commitから外部にビルドし、`JRASM`で指定して検査します。
詳細は[jrasmの導入と固定](docs/JRASM.md)を参照してください。

```sh
python3 tools/build_jrasm.py --source /absolute/path/to/jrasm
JRASM="/absolute/path/to/jrasm/build/src/jrasm/jrasm" make jrasm-check
```

## ゲームの公開

[games/catalog.json](games/catalog.json) は作品ごとの固定版と公開指定の正本です。
初回7作品は検証済みで、clean-source packageを公開
[Release](https://github.com/zabaglione/jr200-dev/releases/tag/games-2026-09-25)に登録しました。
作品ごとにソース、テスト、紹介文、素材のライセンスを保持します。
Wikiの7作品ページと媒体は公開済みです。固定CJRを配信した
[Webエミュレータ](https://zabaglione.github.io/jr200-web-emulator/)では、所有ROM/FONTを
利用するChromeで7作品の「遊ぶ」リンクから通常MLOAD/USR起動を確認しました。
公開版Wikiの承認付き自動remote同期は実行・再実行済みです。BRICK PULSEの推奨版は
[0.1.1](https://github.com/zabaglione/jr200-dev/releases/tag/brick-pulse-0.1.1)へ更新し、
旧0.1.0の固定URLを保持しています。今回のRelease/Wiki匿名アクセスは確認済みですが、
コードのpushだけで新しい作品を一般公開しません。

```sh
make wiki-check
make wiki-preview
```

ROM・メーカー由来フォント・権利未確認のゲームや録音を同梱しません。
ローカル検体はGit対象外の `local-data/` に置いてください。

## ライセンス

新規コードは [BSD-3-Clause](LICENSE)。`games/relic-dive` の移植固有部分は移植元を継承した
MIT Licenseで、組込み共通SDKのBSD全文も作品packageへ併載します。
外部ツールと素材の条件は別に扱います。
[第三者コードの取扱い](THIRD_PARTY_NOTICES.md)を参照してください。

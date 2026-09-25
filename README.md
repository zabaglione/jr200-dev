# JR-200 Game Development Kit

JR-200向けゲームの開発ルール、共通ルーチン、サンプル、ゲームの検証・公開環境を整備するプロジェクトです。
エミュレータ本体は [jr200-web-emulator](https://github.com/zabaglione/jr200-web-emulator) で管理します。
アセンブラは既存の [jrasm](https://github.com/ypsitau/jrasm) を外部ツールとして利用し、独自版を開発・同梱しません。

**現在は初版候補のローカル受入段階です。** 要求仕様、CIの影響範囲判定、外部jrasmの固定版・doctor・
合成fixtureに加え、JR-200ルール、プロジェクト契約、最小CJRテンプレート、選択的CI、
固定エミュレータrunner、画面／入力／ジョイスティック／音声／待機module、6つのsample、最初のゲーム
`SIDE CATCH`、JR-100からカラー移植したローグライク`RELIC DIVE`、固定package、
Wiki preview／dry-run同期を整備しています。
runnerは固定Release資産として公開済みで、ZIPの匿名取得とdigestを確認しています。
Mac arm64新規クローンとLinux CIでROMなし合成実行を確認し、合成runtimeをCI必須条件にしました。
ゲームのReleaseは未公開です。GitHub Wikiには非公開リポジトリ内の案内4ページを配置済みですが、
作品の配布ページやワンクリック実行リンクはまだ掲載していません。
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
`templates/minimal`、`samples/` の5 target、`SIDE CATCH`、`RELIC DIVE` を登録し、共有SDK変更が
利用targetだけへ波及することを検査します。catalog登録ゲームは候補版1件、公開版0件で、
`RELIC DIVE` は移植検証中の開発版です。

最小テンプレートはROMやFONTなしで構造検査できます。CJR生成には固定jrasmを指定します。

```sh
make template-validate
JRASM="/absolute/path/to/jrasm" make template-build
RUNNER_BUNDLE="/absolute/path/to/emulator/build/emscripten/web" make template-run
JRASM="/absolute/path/to/jrasm" make template-package
```

新規ゲームの作成とゲーム単体の操作方法は [ゲームプロジェクト契約](docs/PROJECTS.md) を参照してください。
共有moduleと機能別sampleは [SDK README](sdk/README.md) を参照してください。

jrasmは本リポジトリへ同梱しません。固定commitから外部にビルドし、`JRASM`で指定して検査します。
詳細は[jrasmの導入と固定](docs/JRASM.md)を参照してください。

```sh
python3 tools/build_jrasm.py --source /absolute/path/to/jrasm
JRASM="/absolute/path/to/jrasm/build/src/jrasm/jrasm" make jrasm-check
```

## ゲームの公開

[games/catalog.json](games/catalog.json) は公開候補の登録場所です。現在は `SIDE CATCH 0.1.0` を
候補版として登録し、固定CJR／package／画面hashを保持しています。`RELIC DIVE` はcatalog未登録の
開発版で、公開操作は行っていません。
作品ごとにソース、テスト、紹介文、素材のライセンスを保持します。
Wikiの基本案内4ページは非公開リポジトリへpush済みです。作品ページはローカル生成と
Git worktreeへのdry-run／applyまで対応し、公開版の自動remote pushは未対応です。
公開Webエミュレータは固定カタログからのワンクリック読込みに対応しましたが、
現在のカタログは空で、作品ごとの「遊ぶ」リンクはまだありません。
コードのpushだけで作品を一般公開しません。

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

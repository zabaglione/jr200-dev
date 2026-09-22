# JR-200 Game Development Kit

JR-200向けゲームの開発ルール、共通ルーチン、サンプル、ゲームの検証・公開環境を整備するプロジェクトです。
エミュレータ本体は [jr200-web-emulator](https://github.com/zabaglione/jr200-web-emulator) で管理します。
アセンブラは既存の [jrasm](https://github.com/ypsitau/jrasm) を外部ツールとして利用し、独自版を開発・同梱しません。

**現在は初期設定段階です。** 要求仕様、作業Issue、CIの影響範囲判定とそのテストを登録しています。
ゲームSDK、ゲームのビルド／実行ランナー、成功記録と生成物の再利用、Wiki同期は未実装です。
初期CIの成功はこれらの完成を示しません。

## 開発方針

- Macを主な開発環境とし、Linuxでもビルドを再現できる構成にします。
- CJRを基本配布形式とし、WAVは検証条件を明示して必要な作品だけ生成します。
- エミュレータのビルドはこのリポジトリのゲームCIから呼び出しません。
- 変更ゲームとその依存先だけをビルド・試験し、紹介文だけの変更ではゲームを再ビルドしません。
- ゲームの説明とメタデータを正本とし、検証済みの公開版をWikiで案内します。

仕様は [開発範囲](docs/DEVELOPMENT.md)、CIの契約は [選択的CI](docs/CI.md)、
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
現在のターゲット登録は空です。実ゲームを追加する前に、Issueで定義したビルド・検証パイプラインを実装します。

## ゲームの公開

[games/catalog.json](games/catalog.json) は公開候補の登録場所です。現在の登録作品は0件です。
作品ごとにソース、テスト、紹介文、素材のライセンスを保持します。
Wikiへの自動同期と「遊ぶ」リンクは後続作業です。コードのpushだけで作品やWikiを一般公開しません。

ROM・メーカー由来フォント・権利未確認のゲームや録音を同梱しません。
ローカル検体はGit対象外の `local-data/` に置いてください。

## ライセンス

新規コードは [BSD-3-Clause](LICENSE)。外部ツールと素材の条件は別に扱います。
[第三者コードの取扱い](THIRD_PARTY_NOTICES.md)を参照してください。

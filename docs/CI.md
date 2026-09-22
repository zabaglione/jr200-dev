# 選択的CIの契約

## 初期実装と未実装の境界

`tools/ci_plan.py` は宣言済み入力と逆依存を使う**影響候補の判定器**である。
初期CIはUbuntuの1ジョブでリポジトリ構造・判定器の単体テスト・変更候補表示だけを実行する。
C++、jrasm、Emscripten、エミュレータのビルドは行わない。

成功記録・成果物キャッシュ・動的matrix・ゲームのビルド／実行・Wiki同期は後続Issueで実装する。
判定器の `build_candidates` / `test_candidates` は成功証拠ではなく、検証スキップの許可でもない。
初期CIは未実装のゲームを緑にしないため、ターゲット／ゲーム登録が非空なら明示エラーにする。
実パイプラインを接続するIssueでこのガードを置換する。

## 判定表

| 入力変更 | 必要な処理 |
| --- | --- |
| README／一般文書 | 文書検査のみ。ゲームビルドなし |
| ゲームAのsrc・組込みassets・build.json | Aのビルドと試験 |
| Aのtests | Aの再試験。ビルド入力が同じなら適合生成物を再利用 |
| AのREADME・game.json・media | Aの公開情報検査とWiki生成のみ |
| SDK共通モジュール | そのモジュールと推移的な逆依存先のビルド・試験 |
| jrasm採用版／共通build条件 | 影響する全ターゲットを再ビルド |
| テストランナー／テスト条件 | 影響する試験を再実行。ゲーム自体は入力不変なら再利用 |
| Wiki生成コード | Wiki試験と生成のみ |
| 判定器／CIポリシー／不明な入力パス | 保守的に対象を広げ、理由を出力。黙って除外しない |

宣言した入力パターンを拡張子による一般分類より優先する。埋め込むREADMEやPNGを文書として除外しない。
削除は旧パス、renameは旧・新パスの双方を扱い、旧graphと新graphの和集合で影響判定する。
初期判定器は現在graphだけを使うため、graphファイル変更では全候補へ拡大し、旧graphによる精密化は後続作業とする。

## ターゲット登録形式（version 1）

`ci/targets.json` のtargetsには次の形式を使用する。以下は書式例であり実装済みゲームではない。

```json
{
  "id": "example-game",
  "kind": "game",
  "depends_on": ["sdk-sound"],
  "build_inputs": ["games/example-game/src/**", "games/example-game/assets/**", "games/example-game/Makefile", "games/example-game/build.json"],
  "test_inputs": ["games/example-game/tests/**"],
  "doc_inputs": ["games/example-game/README.md", "games/example-game/game.json", "games/example-game/media/**"]
}
```

依存先も同じ一覧に登録する。重複ID、未知依存、循環、絶対パス、`..`を拒否する。
初期パターンはPython `fnmatchcase` の一致規則を使う。シェルで展開しない。
入力の重複は全所有者を対象にする。SDKのテストだけの変更では依存ゲームを再ビルドしない。

## 完成時のパイプライン

1. 軽量plannerでtracked入力を列挙し、宣言・実依存・旧新graphを検査する。
2. ソース内容・依存内容・toolchain版／digest・build設定からbuild fingerprintを作る。
3. build fingerprintとtest入力・runner版／digest・条件からtest fingerprintを作る。
4. 信頼済み成功記録と実際の生成物hashを照合し、作業が必要なターゲットだけmatrix化する。
5. 必要なビルド・試験を実行し、すべて成功した検証だけを記録する。
6. 固定名の最終gateがplanner・必要jobの失敗／取消／想定外skipを失敗にする。

直前commitとの差だけでは、失敗／取消を挟んだ変更を見逃す。全ターゲットの現在fingerprintを信頼済み記録と照合する。
キャッシュ欠落・hash不一致・toolchain更新は再実行し、キャッシュhitだけを合格根拠にしない。
PRは読取り専用で検証し、公開資格情報や信頼済み記録の書込み権限を渡さない。
fork PRが生成したコード・成果物を権限付き `pull_request_target` 等で実行しない。

ゲームCIは別配布の固定エミュレータ／CLIを使用する。開発リポジトリの浮動mainや暗黙の再ビルドに依存しない。
依存更新時の互換性試験とエミュレータ自体のbuildは分離する。

## トリガー・公開・費用

初期トリガーはmainへのpush、main向けPR、手動実行のみ。作業branchのpushとPRを二重起動しない。
同一PRの古い検査は取り消せる。公開処理は別groupで直列化し、途中取消で配布物を壊さない。
必須workflow全体をpathsでskipせず、不要jobだけを内部条件でskipする。
全件実行はtoolchain／全体共通変更・リリース受入・明示手動実行に限定し、定期的な全件buildは設けない。

Wiki処理はゲームbuildの後処理に固定しない。紹介文変更だけなら文書検査と差分同期で完結する。
成果物が未検証／未公開ならゲームページを公開しない。検査と公開の権限を分離する。

## CI自体の受入

文書のみ、単一ゲーム、共有・推移依存、testのみ、組込み素材と紹介画像、rename／削除、graph変更、
未分類パス、失敗／取消を挟む変更、キャッシュ欠落・破損、toolchain／runner更新、空matrixを検査する。
初期単体テストはパス・逆依存・graph検査・Git差分を対象とし、成功記録や公開制御の試験は未実施である。

## 一次資料

- [動的matrix](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations)
- [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [必須チェックとskip](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)
- [Dependency caching](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching)
